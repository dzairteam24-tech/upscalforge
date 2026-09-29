//! The ScaleForge device abstraction and the CPU reference backend.
//!
//! The engine talks only to these traits. Their responsibilities are kept
//! separate:
//!
//! | Concern | API |
//! |---------|-----|
//! | device management | [`Backend`], [`Device::info`] |
//! | memory allocation, buffers | [`Device::allocate`], [`Buffer`], [`Device::memory_status`] |
//! | compute operations | [`Device::compile`] → [`Executable`] |
//! | transfers | [`Queue::upload`], [`Queue::download`] |
//! | execution | [`Queue::execute`] |
//! | synchronisation | [`Queue::signal`], [`Queue::wait`], [`Queue::synchronize`] |
//!
//! The abstraction works at the **graph** level: a backend compiles a whole
//! planned graph and chooses its own kernels. The engine never names a
//! kernel (ADR-0003).
//!
//! Queue operations are asynchronous **by contract**. The CPU backend
//! happens to complete them immediately, but in *strict mode* it tracks the
//! logical timeline of every buffer and rejects cross-queue accesses that
//! lack an event dependency. Code validated on the CPU therefore obeys the
//! rules GPU backends need.

pub mod cpu;

use std::any::Any;
use std::sync::Arc;

use sf_core::Result;
use sf_graph::{Graph, Shape};

/// Numeric precision for execution.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Precision {
    /// 32-bit floats.
    F32,
    /// 16-bit floats.
    F16,
}

/// Where a buffer lives.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum MemoryKind {
    /// Device-local memory.
    Device,
    /// Host memory used for transfers.
    HostStaging,
}

/// Static description of a device.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceInfo {
    /// Human-readable name.
    pub name: String,
    /// Backend identifier, e.g. `"cpu"`.
    pub backend: &'static str,
    /// Total device memory, when known.
    pub total_memory: Option<u64>,
    /// Whether [`Precision::F16`] execution is supported.
    pub supports_f16: bool,
}

/// Current memory state of a device.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MemoryStatus {
    /// Total memory, when known.
    pub total: Option<u64>,
    /// Memory this process may use, when the device reports it.
    pub budget: Option<u64>,
    /// Bytes currently allocated through this device object.
    pub allocated: u64,
}

/// Memory an executable needs besides its inputs, parameters and outputs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MemoryRequirement {
    /// Arena for intermediate tensors.
    pub arena_bytes: u64,
    /// Backend scratch space.
    pub workspace_bytes: u64,
}

/// Backend-side storage behind a [`Buffer`].
pub trait BufferObject: Any + Send + Sync {
    /// Unique id within the owning device.
    fn id(&self) -> u64;
    /// Size in bytes.
    fn size_bytes(&self) -> u64;
    /// Memory kind.
    fn kind(&self) -> MemoryKind;
    /// For backend downcasting.
    fn as_any(&self) -> &dyn Any;
}

/// A reference-counted handle to device memory. Memory is released when
/// the last handle is dropped.
#[derive(Clone)]
pub struct Buffer(Arc<dyn BufferObject>);

impl Buffer {
    /// Wraps a backend buffer object.
    pub fn new(object: Arc<dyn BufferObject>) -> Buffer {
        Buffer(object)
    }

    /// The backend object.
    pub fn object(&self) -> &dyn BufferObject {
        self.0.as_ref()
    }

    /// Size in bytes.
    pub fn size_bytes(&self) -> u64 {
        self.0.size_bytes()
    }

    /// True if both handles refer to the same memory.
    pub fn same_as(&self, other: &Buffer) -> bool {
        self.0.id() == other.0.id() && Arc::ptr_eq(&self.0, &other.0)
    }
}

impl std::fmt::Debug for Buffer {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Buffer(id={}, {} bytes, {:?})", self.0.id(), self.0.size_bytes(), self.0.kind())
    }
}

/// A compiled graph, ready to run on its device.
pub trait Executable: Any + Send + Sync {
    /// Memory needed at execution time.
    fn memory(&self) -> MemoryRequirement;
    /// For backend downcasting.
    fn as_any(&self) -> &dyn Any;
}

/// Value supplied for one graph input.
#[derive(Debug, Clone, Copy)]
pub enum Binding<'a> {
    /// A tensor input stored in a buffer.
    Buffer(&'a Buffer),
    /// A scalar input.
    Scalar(f32),
}

/// Everything an execution reads and writes.
#[derive(Debug)]
pub struct Bindings<'a> {
    /// One binding per graph input, in declaration order.
    pub inputs: Vec<Binding<'a>>,
    /// One buffer per parameter, in declaration order.
    pub params: Vec<&'a Buffer>,
    /// One buffer per graph output, in declaration order.
    pub outputs: Vec<&'a Buffer>,
    /// Scratch arena of at least [`MemoryRequirement::arena_bytes`]. It must
    /// not alias any other bound buffer.
    pub arena: &'a Buffer,
}

/// A point on a queue's timeline. Waiting on it orders later work on
/// another queue after everything submitted before the signal.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Event {
    /// Queue that signalled.
    pub queue: u64,
    /// Position on that queue's timeline.
    pub seq: u64,
}

/// A download that completes asynchronously.
pub trait PendingDownload: Send {
    /// Blocks until the data is available and returns it.
    fn wait(self: Box<Self>) -> Result<Vec<f32>>;
}

/// An in-order stream of device work.
pub trait Queue: Send {
    /// Copies `data` into the start of `dst`. The data is captured before
    /// this returns, so the caller may reuse its memory immediately.
    fn upload(&mut self, dst: &Buffer, data: &[f32]) -> Result<()>;
    /// Enqueues a copy of the whole of `src` back to the host.
    fn download(&mut self, src: &Buffer) -> Result<Box<dyn PendingDownload>>;
    /// Enqueues execution of a compiled graph.
    fn execute(&mut self, executable: &dyn Executable, bindings: &Bindings<'_>) -> Result<()>;
    /// Marks the current point of this queue's timeline.
    fn signal(&mut self) -> Event;
    /// Orders all later work on this queue after `event`.
    fn wait(&mut self, event: Event) -> Result<()>;
    /// Blocks until all submitted work has completed.
    fn synchronize(&mut self) -> Result<()>;
}

/// A compute device.
pub trait Device: Send + Sync {
    /// Static description.
    fn info(&self) -> DeviceInfo;
    /// Current memory state.
    fn memory_status(&self) -> MemoryStatus;
    /// Allocates `bytes` of memory.
    fn allocate(&self, bytes: u64, kind: MemoryKind) -> Result<Buffer>;
    /// Creates a new queue.
    fn create_queue(&self) -> Result<Box<dyn Queue>>;
    /// Memory needed to run `graph` with the given input shapes, without
    /// allocating anything.
    fn memory_requirement(
        &self,
        graph: &Graph,
        inputs: &[Shape],
        precision: Precision,
    ) -> Result<MemoryRequirement>;
    /// Compiles `graph` for the given input shapes.
    fn compile(&self, graph: &Graph, inputs: &[Shape], precision: Precision) -> Result<Arc<dyn Executable>>;
}

/// A family of devices (CPU, CUDA, Vulkan).
pub trait Backend: Send + Sync {
    /// Backend identifier.
    fn name(&self) -> &'static str;
    /// Available devices.
    fn devices(&self) -> Result<Vec<DeviceInfo>>;
    /// Opens the device at `index` in [`Backend::devices`].
    fn open(&self, index: usize) -> Result<Arc<dyn Device>>;
}
