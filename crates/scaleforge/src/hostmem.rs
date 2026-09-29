//! Host memory budget.
//!
//! Large host buffers (decoded images, tile staging, outputs) are reserved
//! against a process-wide budget **before** allocation. A [`Reservation`]
//! returns its bytes when dropped.

use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use sf_core::{Error, Result};

/// A process-wide host memory budget.
#[derive(Debug, Clone)]
pub struct HostBudget {
    limit: u64,
    used: Arc<AtomicU64>,
}

/// Bytes reserved from a [`HostBudget`]; released on drop.
#[derive(Debug)]
pub struct Reservation {
    bytes: u64,
    used: Arc<AtomicU64>,
}

impl Reservation {
    /// Reserved bytes.
    pub fn bytes(&self) -> u64 {
        self.bytes
    }
}

impl Drop for Reservation {
    fn drop(&mut self) {
        self.used.fetch_sub(self.bytes, Ordering::AcqRel);
    }
}

impl HostBudget {
    /// A budget of `limit` bytes.
    pub fn new(limit: u64) -> HostBudget {
        HostBudget { limit, used: Arc::new(AtomicU64::new(0)) }
    }

    /// A budget of `fraction` of physical memory when that can be
    /// determined (Linux: `/proc/meminfo`), otherwise `fallback` bytes.
    pub fn from_system(fraction: f64, fallback: u64) -> HostBudget {
        let total = std::fs::read_to_string("/proc/meminfo").ok().and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("MemTotal:"))?
                .split_whitespace()
                .nth(1)?
                .parse::<u64>()
                .ok()
                .map(|kb| kb * 1024)
        });
        HostBudget::new(total.map_or(fallback, |t| (t as f64 * fraction) as u64))
    }

    /// The limit.
    pub fn limit(&self) -> u64 {
        self.limit
    }

    /// Bytes currently reserved.
    pub fn used(&self) -> u64 {
        self.used.load(Ordering::Acquire)
    }

    /// Reserves `bytes`, or fails with `LimitExceeded` without reserving.
    pub fn reserve(&self, bytes: u64, what: &str) -> Result<Reservation> {
        let mut cur = self.used.load(Ordering::Acquire);
        loop {
            let next = cur.checked_add(bytes).filter(|&n| n <= self.limit).ok_or_else(|| {
                Error::limit_exceeded(format!(
                    "{what} needs {bytes} bytes of host memory; {} of {} are in use",
                    cur, self.limit
                ))
            })?;
            match self.used.compare_exchange(cur, next, Ordering::AcqRel, Ordering::Acquire) {
                Ok(_) => return Ok(Reservation { bytes, used: Arc::clone(&self.used) }),
                Err(actual) => cur = actual,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sf_core::ErrorKind;

    #[test]
    fn reservations_are_bounded_and_released() {
        let b = HostBudget::new(1_000);
        let r1 = b.reserve(600, "decode").unwrap();
        assert_eq!(b.reserve(500, "tiles").unwrap_err().kind(), ErrorKind::LimitExceeded);
        assert_eq!(b.used(), 600);
        drop(r1);
        let _r2 = b.reserve(1_000, "all").unwrap();
        assert_eq!(b.used(), 1_000);
    }

    #[test]
    fn concurrent_reservations_never_exceed_the_limit() {
        let b = HostBudget::new(10_000);
        std::thread::scope(|s| {
            for _ in 0..8 {
                let b = b.clone();
                s.spawn(move || {
                    for _ in 0..2_000 {
                        if let Ok(r) = b.reserve(700, "t") {
                            assert!(b.used() <= b.limit());
                            drop(r);
                        }
                    }
                });
            }
        });
        assert_eq!(b.used(), 0);
    }

    #[test]
    fn system_budget_is_positive() {
        assert!(HostBudget::from_system(0.5, 1 << 30).limit() > 0);
    }
}
