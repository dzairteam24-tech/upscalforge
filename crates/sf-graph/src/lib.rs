//! The ScaleForge tensor and graph system.
//!
//! A model is a [`Graph`]: a topologically ordered list of [`Node`]s over a
//! small, versioned operator set ([`Op`]). It has declared inputs and
//! parameters (weights). This crate is pure logic with no device code. It
//! provides:
//!
//! - graph construction and [`validate`] (references, arity, role rules);
//! - [`infer_shapes`] for concrete input shapes;
//! - [`locality`]: the receptive radius and alignment, derived from the
//!   graph itself (these values make exact tiling possible);
//! - [`plan_memory`]: liveness-based placement of every intermediate tensor
//!   in a single arena, giving exact activation memory before execution.

mod graph;
mod infer;
mod locality;
mod memory;
mod op;
pub mod sfm;
mod shape;

pub use graph::{
    Graph, GraphRole, InputDecl, InputKind, Node, OutputDecl, OutputKind, ParamDecl, ValueRef, validate,
};
pub use infer::{Shapes, infer_shapes};
pub use locality::{Locality, OutputLocality, locality};
pub use memory::{ARENA_ALIGNMENT, MemoryPlan, Slot, plan_memory};
pub use op::{Activation, OPSET_VERSION, Op};
pub use shape::Shape;

#[cfg(test)]
mod tests;
