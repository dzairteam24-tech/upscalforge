//! Progress reporting for long-running jobs.

/// One progress update. `completed` never exceeds `total` for a stage.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProgressEvent {
    /// Stable stage name, e.g. `"summary"`, `"tiles"`, `"encode"`.
    pub stage: &'static str,
    /// Units completed in this stage.
    pub completed: u64,
    /// Total units in this stage.
    pub total: u64,
}

impl ProgressEvent {
    /// Fraction done in `[0, 1]`; an empty stage counts as complete.
    pub fn fraction(&self) -> f64 {
        if self.total == 0 { 1.0 } else { self.completed.min(self.total) as f64 / self.total as f64 }
    }
}

/// Receives progress events. Implementations must be cheap and must not
/// block, because they are called on the processing path.
pub trait ProgressSink: Send + Sync {
    /// Handles one event.
    fn report(&self, event: &ProgressEvent);
}

/// A sink that discards all events.
#[derive(Debug, Clone, Copy, Default)]
pub struct NoProgress;

impl ProgressSink for NoProgress {
    fn report(&self, _event: &ProgressEvent) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fraction_is_clamped() {
        let e = |completed, total| ProgressEvent { stage: "tiles", completed, total };
        assert_eq!(e(0, 0).fraction(), 1.0);
        assert_eq!(e(1, 4).fraction(), 0.25);
        assert_eq!(e(9, 4).fraction(), 1.0);
        NoProgress.report(&e(1, 2));
    }
}
