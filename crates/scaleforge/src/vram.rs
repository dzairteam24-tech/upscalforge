//! Device memory management.
//!
//! Every device allocation goes through a [`VramManager`], which tags it
//! with a [`Pool`], enforces a budget **before** asking the device, and
//! records current and peak usage per pool. Memory is released when the
//! last handle of a [`TrackedBuffer`] is dropped, including on error paths.

use std::sync::{Arc, Mutex};

use sf_compute::{Buffer, Device, MemoryKind, MemoryRequirement};
use sf_core::{DeviceErrorKind, Error, ErrorKind, Result};

/// What an allocation is for.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Pool {
    /// Model weights (resident while a model is loaded).
    Weights,
    /// Intermediate tensors (the planned arena).
    Activations,
    /// Input and output tile buffers.
    Io,
    /// Backend scratch space.
    Workspace,
}

const POOLS: [Pool; 4] = [Pool::Weights, Pool::Activations, Pool::Io, Pool::Workspace];

fn index(p: Pool) -> usize {
    POOLS.iter().position(|&q| q == p).expect("known pool")
}

/// Per-pool and total usage.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Usage {
    /// Bytes currently allocated per pool, in [`Pool`] order
    /// (weights, activations, io, workspace).
    pub current: [u64; 4],
    /// Peak bytes per pool since creation or the last reset.
    pub peak: [u64; 4],
    /// Peak of the total.
    pub peak_total: u64,
}

impl Usage {
    /// Total bytes currently allocated.
    pub fn total(&self) -> u64 {
        self.current.iter().sum()
    }

    /// Current bytes in `pool`.
    pub fn of(&self, pool: Pool) -> u64 {
        self.current[index(pool)]
    }
}

/// Whether a plan fits the budget.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Fit {
    /// The plan fits.
    Fits,
    /// The plan needs this many more bytes than are available.
    Shortfall(u64),
}

#[derive(Debug)]
struct Accounting {
    budget: u64,
    usage: Mutex<Usage>,
}

/// Budgeted, tagged device allocation.
pub struct VramManager {
    device: Arc<dyn Device>,
    acct: Arc<Accounting>,
}

/// A device buffer whose release is accounted for automatically.
pub struct TrackedBuffer {
    buffer: Buffer,
    pool: Pool,
    bytes: u64,
    acct: Arc<Accounting>,
}

impl TrackedBuffer {
    /// The underlying device buffer.
    pub fn buffer(&self) -> &Buffer {
        &self.buffer
    }
}

impl Drop for TrackedBuffer {
    fn drop(&mut self) {
        if let Ok(mut u) = self.acct.usage.lock() {
            u.current[index(self.pool)] -= self.bytes;
        }
    }
}

impl VramManager {
    /// Creates a manager. The budget is the smallest of the device-reported
    /// budget, the device capacity and `user_limit`, minus `reserve` bytes
    /// held back for the driver and other processes (the reserve value is a
    /// provisional default until calibrated by measurement).
    pub fn new(device: Arc<dyn Device>, user_limit: Option<u64>, reserve: u64) -> VramManager {
        let status = device.memory_status();
        let reported = [status.budget, status.total, user_limit].into_iter().flatten().min();
        let budget = reported.map_or(u64::MAX, |b| b.saturating_sub(reserve));
        VramManager { device, acct: Arc::new(Accounting { budget, usage: Mutex::new(Usage::default()) }) }
    }

    /// The device.
    pub fn device(&self) -> &Arc<dyn Device> {
        &self.device
    }

    /// Effective budget in bytes (`u64::MAX` when the device reports none).
    pub fn budget(&self) -> u64 {
        self.acct.budget
    }

    /// Current and peak usage.
    pub fn usage(&self) -> Usage {
        *self.acct.usage.lock().expect("accounting lock")
    }

    /// Resets peak counters to current values.
    pub fn reset_peaks(&self) {
        let mut u = self.acct.usage.lock().expect("accounting lock");
        u.peak = u.current;
        u.peak_total = u.total();
    }

    /// Checks whether `extra` more bytes fit.
    pub fn fits(&self, extra: u64) -> Fit {
        let used = self.usage().total();
        let available = self.acct.budget.saturating_sub(used);
        if extra <= available { Fit::Fits } else { Fit::Shortfall(extra - available) }
    }

    /// Bytes an execution needs besides already-resident weights.
    pub fn execution_bytes(req: &MemoryRequirement, io_bytes: u64) -> u64 {
        req.arena_bytes + req.workspace_bytes + io_bytes
    }

    /// Allocates `bytes` in `pool`, refusing with `Device(OutOfMemory)`
    /// before touching the device if the budget would be exceeded.
    pub fn allocate(&self, pool: Pool, bytes: u64) -> Result<TrackedBuffer> {
        let bytes = bytes.max(4);
        if let Fit::Shortfall(s) = self.fits(bytes) {
            return Err(Error::new(
                ErrorKind::Device(DeviceErrorKind::OutOfMemory),
                format!("{pool:?} allocation of {bytes} bytes exceeds the device budget by {s} bytes"),
            ));
        }
        let buffer = self.device.allocate(bytes, MemoryKind::Device)?;
        let mut u = self.acct.usage.lock().expect("accounting lock");
        let i = index(pool);
        u.current[i] += bytes;
        u.peak[i] = u.peak[i].max(u.current[i]);
        u.peak_total = u.peak_total.max(u.total());
        Ok(TrackedBuffer { buffer, pool, bytes, acct: Arc::clone(&self.acct) })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sf_compute::cpu::{CpuBackend, CpuConfig};

    fn manager(capacity: u64, reserve: u64) -> VramManager {
        let dev = CpuBackend::new(CpuConfig { threads: 1, strict: false, memory_limit: Some(capacity) })
            .device()
            .unwrap();
        VramManager::new(dev, None, reserve)
    }

    #[test]
    fn budget_reserve_and_preflight() {
        let m = manager(10_000, 1_000);
        assert_eq!(m.budget(), 9_000);
        let a = m.allocate(Pool::Weights, 5_000).unwrap();
        assert_eq!(m.fits(4_000), Fit::Fits);
        assert_eq!(m.fits(4_500), Fit::Shortfall(500));
        let e = m.allocate(Pool::Activations, 4_500).err().unwrap();
        assert_eq!(e.kind(), ErrorKind::Device(DeviceErrorKind::OutOfMemory));
        assert_eq!(m.device().memory_status().allocated, 5_000, "refused before reaching the device");
        drop(a);
        assert_eq!(m.usage().total(), 0);
    }

    #[test]
    fn per_pool_peaks_and_release_on_drop() {
        let m = manager(1 << 20, 0);
        {
            let _w = m.allocate(Pool::Weights, 1_000).unwrap();
            let a = m.allocate(Pool::Activations, 3_000).unwrap();
            let _io = m.allocate(Pool::Io, 500).unwrap();
            drop(a);
            let _a2 = m.allocate(Pool::Activations, 2_000).unwrap();
            let u = m.usage();
            assert_eq!(u.of(Pool::Activations), 2_000);
            assert_eq!(u.peak[index(Pool::Activations)], 3_000);
            assert_eq!(u.peak_total, 4_500);
        }
        assert_eq!(m.usage().total(), 0, "all released, including on scope exit");
        m.reset_peaks();
        assert_eq!(m.usage().peak_total, 0);
    }

    #[test]
    fn user_limit_caps_the_budget() {
        let dev = CpuBackend::new(CpuConfig { threads: 1, strict: false, memory_limit: Some(1 << 30) })
            .device()
            .unwrap();
        let m = VramManager::new(dev, Some(4_096), 96);
        assert_eq!(m.budget(), 4_000);
    }
}
