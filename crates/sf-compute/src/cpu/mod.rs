//! CPU reference backend.
//!
//! This backend is the correctness reference for all others and the
//! fallback of last resort. Kernels are deterministic: every output element
//! is produced by one thread with a fixed accumulation order, so results do
//! not depend on the thread count.

mod exec;
mod kernels;

#[cfg(test)]
mod tests;

use std::any::Any;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};

use sf_core::{DeviceErrorKind, Error, ErrorKind, Result};
use sf_graph::{Graph, Shape};

use crate::{
    Backend, Bindings, Buffer, BufferObject, Device, DeviceInfo, Event, Executable, MemoryKind,
    MemoryRequirement, MemoryStatus, PendingDownload, Precision, Queue,
};

/// CPU backend configuration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CpuConfig {
    /// Worker threads for parallel kernels (≥ 1).
    pub threads: usize,
    /// Track buffer accesses per queue and reject unsynchronised
    /// cross-queue use (for tests and debugging).
    pub strict: bool,
    /// Emulated device memory capacity. Allocations beyond it fail with
    /// `Device(OutOfMemory)`, which lets out-of-memory handling be tested.
    pub memory_limit: Option<u64>,
}

impl Default for CpuConfig {
    fn default() -> Self {
        CpuConfig {
            threads: std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1),
            strict: false,
            memory_limit: None,
        }
    }
}

/// The CPU backend. It exposes a single device.
#[derive(Debug, Clone, Default)]
pub struct CpuBackend {
    config: CpuConfig,
}

impl CpuBackend {
    /// Creates the backend with the given configuration.
    pub fn new(config: CpuConfig) -> CpuBackend {
        CpuBackend { config }
    }

    /// Opens the CPU device directly.
    pub fn device(&self) -> Result<Arc<CpuDevice>> {
        if self.config.threads == 0 {
            return Err(Error::invalid_input("cpu backend needs at least one thread"));
        }
        Ok(Arc::new(CpuDevice {
            shared: Arc::new(Shared {
                config: self.config.clone(),
                allocated: AtomicU64::new(0),
                next_id: AtomicU64::new(1),
                tracker: Mutex::new(HashMap::new()),
            }),
        }))
    }
}

impl Backend for CpuBackend {
    fn name(&self) -> &'static str {
        "cpu"
    }

    fn devices(&self) -> Result<Vec<DeviceInfo>> {
        Ok(vec![self.info()])
    }

    fn open(&self, index: usize) -> Result<Arc<dyn Device>> {
        if index != 0 {
            return Err(Error::invalid_input(format!("cpu backend has one device, index {index} requested")));
        }
        Ok(self.device()?)
    }
}

impl CpuBackend {
    fn info(&self) -> DeviceInfo {
        DeviceInfo {
            name: format!("CPU ({} threads)", self.config.threads),
            backend: "cpu",
            total_memory: self.config.memory_limit,
            supports_f16: false,
        }
    }
}

/// Per-buffer access history used by strict mode.
#[derive(Debug, Default)]
struct Access {
    last_write: Option<(u64, u64)>,
    reads: Vec<(u64, u64)>,
}

#[derive(Debug)]
struct Shared {
    config: CpuConfig,
    allocated: AtomicU64,
    next_id: AtomicU64,
    tracker: Mutex<HashMap<u64, Access>>,
}

impl Shared {
    fn fresh_id(&self) -> u64 {
        self.next_id.fetch_add(1, Ordering::Relaxed)
    }
}

/// The CPU device.
#[derive(Debug)]
pub struct CpuDevice {
    shared: Arc<Shared>,
}

/// CPU-side buffer storage.
struct CpuBuffer {
    id: u64,
    kind: MemoryKind,
    bytes: u64,
    data: RwLock<Vec<f32>>,
    shared: Arc<Shared>,
}

impl Drop for CpuBuffer {
    fn drop(&mut self) {
        self.shared.allocated.fetch_sub(self.bytes, Ordering::Relaxed);
        if let Ok(mut t) = self.shared.tracker.lock() {
            t.remove(&self.id);
        }
    }
}

impl BufferObject for CpuBuffer {
    fn id(&self) -> u64 {
        self.id
    }
    fn size_bytes(&self) -> u64 {
        self.bytes
    }
    fn kind(&self) -> MemoryKind {
        self.kind
    }
    fn as_any(&self) -> &dyn Any {
        self
    }
}

fn cpu_buffer(buffer: &Buffer) -> Result<&CpuBuffer> {
    buffer
        .object()
        .as_any()
        .downcast_ref::<CpuBuffer>()
        .ok_or_else(|| Error::invalid_input("buffer does not belong to the cpu backend"))
}

fn poisoned() -> Error {
    Error::internal("cpu buffer lock poisoned by an earlier panic")
}

impl Device for CpuDevice {
    fn info(&self) -> DeviceInfo {
        CpuBackend::new(self.shared.config.clone()).info()
    }

    fn memory_status(&self) -> MemoryStatus {
        MemoryStatus {
            total: self.shared.config.memory_limit,
            budget: self.shared.config.memory_limit,
            allocated: self.shared.allocated.load(Ordering::Relaxed),
        }
    }

    fn allocate(&self, bytes: u64, kind: MemoryKind) -> Result<Buffer> {
        let bytes = bytes.div_ceil(4) * 4;
        let oom = |why: String| Error::new(ErrorKind::Device(DeviceErrorKind::OutOfMemory), why);
        // Reserve against the emulated capacity first, atomically.
        let prev = self.shared.allocated.fetch_add(bytes, Ordering::Relaxed);
        if let Some(limit) = self.shared.config.memory_limit
            && prev + bytes > limit
        {
            self.shared.allocated.fetch_sub(bytes, Ordering::Relaxed);
            return Err(oom(format!("allocating {bytes} bytes exceeds the device capacity {limit}")));
        }
        let len =
            usize::try_from(bytes / 4).map_err(|_| oom("allocation size exceeds the address space".into()));
        let mut data = Vec::new();
        let reserved = len.and_then(|len| {
            data.try_reserve_exact(len).map(|_| len).map_err(|e| oom(format!("host allocation failed: {e}")))
        });
        let len = match reserved {
            Ok(len) => len,
            Err(e) => {
                self.shared.allocated.fetch_sub(bytes, Ordering::Relaxed);
                return Err(e);
            }
        };
        data.resize(len, 0.0);
        let buffer = CpuBuffer {
            id: self.shared.fresh_id(),
            kind,
            bytes,
            data: RwLock::new(data),
            shared: Arc::clone(&self.shared),
        };
        Ok(Buffer::new(Arc::new(buffer)))
    }

    fn create_queue(&self) -> Result<Box<dyn Queue>> {
        Ok(Box::new(CpuQueue {
            id: self.shared.fresh_id(),
            seq: 0,
            known: HashMap::new(),
            shared: Arc::clone(&self.shared),
        }))
    }

    fn memory_requirement(
        &self,
        graph: &Graph,
        inputs: &[Shape],
        precision: Precision,
    ) -> Result<MemoryRequirement> {
        Ok(exec::CpuExecutable::build(graph, inputs, precision, self.shared.config.threads)?.memory())
    }

    fn compile(&self, graph: &Graph, inputs: &[Shape], precision: Precision) -> Result<Arc<dyn Executable>> {
        Ok(Arc::new(exec::CpuExecutable::build(graph, inputs, precision, self.shared.config.threads)?))
    }
}

/// A CPU queue. Work completes synchronously; strict mode checks ordering.
struct CpuQueue {
    id: u64,
    seq: u64,
    /// Highest timeline position of other queues this queue has waited on.
    known: HashMap<u64, u64>,
    shared: Arc<Shared>,
}

impl CpuQueue {
    /// Advances the timeline and, in strict mode, checks and records the
    /// given accesses.
    fn access(&mut self, reads: &[&Buffer], writes: &[&Buffer]) -> Result<()> {
        self.seq += 1;
        if !self.shared.config.strict {
            return Ok(());
        }
        let mut tracker = self.shared.tracker.lock().map_err(|_| poisoned())?;
        let synced = |known: &HashMap<u64, u64>, (q, s): (u64, u64)| {
            q == self.id || known.get(&q).is_some_and(|&k| k >= s)
        };
        for (buffers, write) in [(reads, false), (writes, true)] {
            for b in buffers {
                let entry = tracker.entry(b.object().id()).or_default();
                if let Some(w) = entry.last_write
                    && !synced(&self.known, w)
                {
                    return Err(hazard(b, if write { "write-after-write" } else { "read-after-write" }, w.0));
                }
                if write && let Some(&r) = entry.reads.iter().find(|&&r| !synced(&self.known, r)) {
                    return Err(hazard(b, "write-after-read", r.0));
                }
            }
        }
        for b in reads {
            let entry = tracker.entry(b.object().id()).or_default();
            entry.reads.retain(|&(q, _)| q != self.id);
            entry.reads.push((self.id, self.seq));
        }
        for b in writes {
            let entry = tracker.entry(b.object().id()).or_default();
            entry.last_write = Some((self.id, self.seq));
            entry.reads.clear();
        }
        Ok(())
    }
}

fn hazard(buffer: &Buffer, kind: &str, other_queue: u64) -> Error {
    Error::invalid_input(format!(
        "strict mode: {kind} hazard on {buffer:?}: queue {other_queue} accessed it without an event dependency"
    ))
}

struct ReadyDownload(Vec<f32>);

impl PendingDownload for ReadyDownload {
    fn wait(self: Box<Self>) -> Result<Vec<f32>> {
        Ok(self.0)
    }
}

impl Queue for CpuQueue {
    fn upload(&mut self, dst: &Buffer, data: &[f32]) -> Result<()> {
        let target = cpu_buffer(dst)?;
        self.access(&[], &[dst])?;
        let mut storage = target.data.write().map_err(|_| poisoned())?;
        if data.len() > storage.len() {
            return Err(Error::invalid_input(format!(
                "upload of {} values into a buffer of {} values",
                data.len(),
                storage.len()
            )));
        }
        storage[..data.len()].copy_from_slice(data);
        Ok(())
    }

    fn download(&mut self, src: &Buffer) -> Result<Box<dyn PendingDownload>> {
        let source = cpu_buffer(src)?;
        self.access(&[src], &[])?;
        let storage = source.data.read().map_err(|_| poisoned())?;
        Ok(Box::new(ReadyDownload(storage.clone())))
    }

    fn execute(&mut self, executable: &dyn Executable, bindings: &Bindings<'_>) -> Result<()> {
        let exe = executable
            .as_any()
            .downcast_ref::<exec::CpuExecutable>()
            .ok_or_else(|| Error::invalid_input("executable was not compiled by the cpu backend"))?;
        let mut reads: Vec<&Buffer> = bindings.params.clone();
        reads.extend(bindings.inputs.iter().filter_map(|b| match b {
            crate::Binding::Buffer(buf) => Some(*buf),
            crate::Binding::Scalar(_) => None,
        }));
        let mut writes: Vec<&Buffer> = bindings.outputs.clone();
        writes.push(bindings.arena);
        // A rejected submission must not leave traces on the timeline.
        exe.check_bindings(bindings)?;
        self.access(&reads, &writes)?;
        exe.run(bindings)
    }

    fn signal(&mut self) -> Event {
        Event { queue: self.id, seq: self.seq }
    }

    fn wait(&mut self, event: Event) -> Result<()> {
        if event.queue != self.id {
            let k = self.known.entry(event.queue).or_insert(0);
            *k = (*k).max(event.seq);
        }
        Ok(())
    }

    fn synchronize(&mut self) -> Result<()> {
        Ok(())
    }
}
