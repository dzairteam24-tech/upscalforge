//! Error taxonomy shared by all ScaleForge crates.

use std::fmt;

/// Classes of device (GPU/CPU backend) failure.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DeviceErrorKind {
    /// The device could not satisfy an allocation.
    OutOfMemory,
    /// The device was lost (driver reset, removal, timeout).
    Lost,
    /// Any other backend failure.
    Other,
}

/// What went wrong, independent of the message text.
///
/// Callers branch on the kind (e.g. retry with a smaller tile on
/// `Device(OutOfMemory)`); the message is for humans.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ErrorKind {
    /// Input data is malformed or violates a documented contract.
    InvalidInput,
    /// The input is valid but uses a feature ScaleForge does not support.
    Unsupported,
    /// A configured resource limit would be exceeded.
    LimitExceeded,
    /// An operating-system I/O operation failed.
    Io,
    /// A model or checkpoint file failed validation.
    ModelInvalid,
    /// A compute device failed.
    Device(DeviceErrorKind),
    /// The operation was cancelled through a [`crate::CancelToken`].
    Cancelled,
    /// A bug: an internal invariant did not hold.
    Internal,
}

impl fmt::Display for ErrorKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            ErrorKind::InvalidInput => "invalid input",
            ErrorKind::Unsupported => "unsupported",
            ErrorKind::LimitExceeded => "limit exceeded",
            ErrorKind::Io => "I/O error",
            ErrorKind::ModelInvalid => "invalid model",
            ErrorKind::Device(DeviceErrorKind::OutOfMemory) => "device out of memory",
            ErrorKind::Device(DeviceErrorKind::Lost) => "device lost",
            ErrorKind::Device(DeviceErrorKind::Other) => "device error",
            ErrorKind::Cancelled => "cancelled",
            ErrorKind::Internal => "internal error",
        };
        f.write_str(s)
    }
}

type Source = Box<dyn std::error::Error + Send + Sync + 'static>;

/// A ScaleForge error: a machine-readable [`ErrorKind`], a human message,
/// and an optional underlying cause.
pub struct Error {
    kind: ErrorKind,
    message: String,
    source: Option<Source>,
}

/// Result alias using [`Error`].
pub type Result<T, E = Error> = std::result::Result<T, E>;

impl Error {
    /// Creates an error of the given kind.
    pub fn new(kind: ErrorKind, message: impl Into<String>) -> Self {
        Error { kind, message: message.into(), source: None }
    }

    /// Shorthand for [`ErrorKind::InvalidInput`].
    pub fn invalid_input(message: impl Into<String>) -> Self {
        Self::new(ErrorKind::InvalidInput, message)
    }

    /// Shorthand for [`ErrorKind::Unsupported`].
    pub fn unsupported(message: impl Into<String>) -> Self {
        Self::new(ErrorKind::Unsupported, message)
    }

    /// Shorthand for [`ErrorKind::LimitExceeded`].
    pub fn limit_exceeded(message: impl Into<String>) -> Self {
        Self::new(ErrorKind::LimitExceeded, message)
    }

    /// Shorthand for [`ErrorKind::ModelInvalid`].
    pub fn model_invalid(message: impl Into<String>) -> Self {
        Self::new(ErrorKind::ModelInvalid, message)
    }

    /// Shorthand for [`ErrorKind::Internal`].
    pub fn internal(message: impl Into<String>) -> Self {
        Self::new(ErrorKind::Internal, message)
    }

    /// The standard cancellation error.
    pub fn cancelled() -> Self {
        Self::new(ErrorKind::Cancelled, "operation cancelled")
    }

    /// Attaches an underlying cause.
    pub fn with_source(mut self, source: impl Into<Source>) -> Self {
        self.source = Some(source.into());
        self
    }

    /// Prefixes the message with context, keeping kind and source.
    pub fn context(mut self, context: impl fmt::Display) -> Self {
        self.message = format!("{context}: {}", self.message);
        self
    }

    /// The error kind.
    pub fn kind(&self) -> ErrorKind {
        self.kind
    }

    /// The human-readable message (without the kind prefix).
    pub fn message(&self) -> &str {
        &self.message
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.kind, self.message)?;
        if let Some(src) = &self.source {
            write!(f, " (caused by: {src})")?;
        }
        Ok(())
    }
}

impl fmt::Debug for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Error")
            .field("kind", &self.kind)
            .field("message", &self.message)
            .field("source", &self.source)
            .finish()
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.source.as_deref().map(|s| s as &(dyn std::error::Error + 'static))
    }
}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::new(ErrorKind::Io, e.to_string()).with_source(e)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::error::Error as _;

    #[test]
    fn display_includes_kind_message_and_source() {
        let io = std::io::Error::new(std::io::ErrorKind::NotFound, "missing.png");
        let e = Error::from(io).context("opening input");
        assert_eq!(e.kind(), ErrorKind::Io);
        let s = e.to_string();
        assert!(s.starts_with("I/O error: opening input: missing.png"), "{s}");
        assert!(e.source().is_some());
    }

    #[test]
    fn device_kinds_are_distinguishable() {
        let oom = Error::new(ErrorKind::Device(DeviceErrorKind::OutOfMemory), "arena");
        assert_eq!(oom.kind(), ErrorKind::Device(DeviceErrorKind::OutOfMemory));
        assert_ne!(oom.kind(), ErrorKind::Device(DeviceErrorKind::Lost));
        assert_eq!(oom.to_string(), "device out of memory: arena");
    }

    #[test]
    fn errors_are_send_and_sync() {
        fn assert_bounds<T: Send + Sync + 'static>() {}
        assert_bounds::<Error>();
    }
}
