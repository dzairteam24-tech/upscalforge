//! Cooperative cancellation.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::error::{Error, Result};

/// A cloneable cancellation flag. Long-running work calls
/// [`CancelToken::check`] at safe points (e.g. between tiles).
#[derive(Debug, Clone, Default)]
pub struct CancelToken {
    flag: Arc<AtomicBool>,
}

impl CancelToken {
    /// Creates a token that is not cancelled.
    pub fn new() -> Self {
        Self::default()
    }

    /// Requests cancellation. All clones observe it.
    pub fn cancel(&self) {
        self.flag.store(true, Ordering::Release);
    }

    /// True once cancellation was requested.
    pub fn is_cancelled(&self) -> bool {
        self.flag.load(Ordering::Acquire)
    }

    /// Returns [`Error::cancelled`] if cancellation was requested.
    pub fn check(&self) -> Result<()> {
        if self.is_cancelled() { Err(Error::cancelled()) } else { Ok(()) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ErrorKind;

    #[test]
    fn clones_share_state_across_threads() {
        let token = CancelToken::new();
        assert!(token.check().is_ok());
        let clone = token.clone();
        std::thread::spawn(move || clone.cancel()).join().unwrap();
        assert!(token.is_cancelled());
        assert_eq!(token.check().unwrap_err().kind(), ErrorKind::Cancelled);
    }
}
