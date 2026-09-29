//! The operator set.
//!
//! The operator set is deliberately small, so that every backend (CPU,
//! CUDA, Vulkan) can implement all of it. Operators are added only together
//! with shape rules, locality rules, a CPU reference kernel and tests.

/// Version of the operator set. Model files declare the version they need.
/// Provisional until frozen at the end of Phase 13.
pub const OPSET_VERSION: u32 = 1;

/// Element-wise activation functions.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Activation {
    /// `max(x, 0)`
    Relu,
    /// `x` if `x ≥ 0`, else `slope · x`.
    LeakyRelu(f32),
    /// Gaussian error linear unit, tanh approximation.
    Gelu,
    /// `x · sigmoid(x)`
    Silu,
    /// `1 / (1 + e^-x)`
    Sigmoid,
}

/// A graph operator. Input conventions are documented per variant, and
/// [`crate::validate`] / [`crate::infer_shapes`] enforce them.
#[derive(Debug, Clone, PartialEq)]
pub enum Op {
    /// 2-D convolution with zero "same" padding (`kernel / 2`).
    /// Inputs: `x` spatial `[N, Cin, H, W]`, weight param
    /// `[out_channels, Cin (or 1 if depthwise), k, k]`, optional bias param
    /// `[out_channels]`. `stride` 2 requires even `H` and `W` and halves them.
    Conv2d {
        /// Output channels (equal to `Cin` when depthwise).
        out_channels: u32,
        /// Kernel size: 1, 3, 5 or 7.
        kernel: u32,
        /// Stride: 1 or 2.
        stride: u32,
        /// One filter per channel (groups = channels).
        depthwise: bool,
        /// Whether a bias parameter follows the weight.
        bias: bool,
    },
    /// 2×2 average pooling with stride 2. Requires even `H`, `W`.
    AvgPool2,
    /// Nearest-neighbour ×2 upsampling.
    UpsampleNearest2,
    /// Depth-to-space ×2: `[N, 4C, H, W] → [N, C, 2H, 2W]`, with source channel
    /// `c·4 + dy·2 + dx` for output position offset `(dy, dx)`.
    PixelShuffle2,
    /// Space-to-depth ×2, the exact inverse of [`Op::PixelShuffle2`].
    PixelUnshuffle2,
    /// Element-wise `a + b` (same shape).
    Add,
    /// Element-wise `a − b` (same shape).
    Sub,
    /// Element-wise `a · b` (same shape).
    Mul,
    /// `x · scale[c] + shift[c]`. Inputs: `x` spatial, then scale and shift,
    /// each a vector `[N or 1, C]` or a parameter `[C]`.
    AffineChannel,
    /// Element-wise activation.
    Activation(Activation),
    /// Per-channel leaky rectifier: `x` if `x ≥ 0` else `slope[c] · x`.
    /// Inputs: `x` spatial, slope parameter `[C]`.
    PRelu,
    /// Clamp to `[lo, hi]`.
    Clamp {
        /// Lower bound.
        lo: f32,
        /// Upper bound.
        hi: f32,
    },
    /// Multiplies `x` by a runtime scalar input.
    ScaleScalar,
    /// Concatenates two or more spatial tensors along channels.
    Concat,
    /// Channels `[start, start + len)` of a spatial tensor.
    SliceChannels {
        /// First channel.
        start: u32,
        /// Number of channels.
        len: u32,
    },
    /// Removes the given margins from a spatial tensor. Inserted by the tile
    /// planner; not expected in model files.
    Crop {
        /// Rows removed at the top.
        top: u32,
        /// Columns removed at the left.
        left: u32,
        /// Rows removed at the bottom.
        bottom: u32,
        /// Columns removed at the right.
        right: u32,
    },
    /// Spatial mean: `[N, C, H, W] → [N, C]`. A spatial reduction: forbidden
    /// on any path to a tensor output of a `Main` graph.
    GlobalMean,
    /// Fully connected layer on vectors. Inputs: `x` `[N, In]`, weight param
    /// `[out_features, In]`, optional bias param `[out_features]`.
    Linear {
        /// Output features.
        out_features: u32,
        /// Whether a bias parameter follows the weight.
        bias: bool,
    },
}

impl Op {
    /// Short stable name for messages and files.
    pub fn name(&self) -> &'static str {
        match self {
            Op::Conv2d { .. } => "conv2d",
            Op::AvgPool2 => "avg_pool2",
            Op::UpsampleNearest2 => "upsample_nearest2",
            Op::PixelShuffle2 => "pixel_shuffle2",
            Op::PixelUnshuffle2 => "pixel_unshuffle2",
            Op::Add => "add",
            Op::Sub => "sub",
            Op::Mul => "mul",
            Op::AffineChannel => "affine_channel",
            Op::Activation(_) => "activation",
            Op::PRelu => "prelu",
            Op::Clamp { .. } => "clamp",
            Op::ScaleScalar => "scale_scalar",
            Op::Concat => "concat",
            Op::SliceChannels { .. } => "slice_channels",
            Op::Crop { .. } => "crop",
            Op::GlobalMean => "global_mean",
            Op::Linear { .. } => "linear",
        }
    }

    /// Accepted number of inputs as `(min, max)`.
    pub fn arity(&self) -> (usize, usize) {
        match self {
            Op::Conv2d { bias, .. } | Op::Linear { bias, .. } => {
                let n = if *bias { 3 } else { 2 };
                (n, n)
            }
            Op::AvgPool2
            | Op::UpsampleNearest2
            | Op::PixelShuffle2
            | Op::PixelUnshuffle2
            | Op::Activation(_)
            | Op::Clamp { .. }
            | Op::SliceChannels { .. }
            | Op::Crop { .. }
            | Op::GlobalMean => (1, 1),
            Op::Add | Op::Sub | Op::Mul | Op::PRelu | Op::ScaleScalar => (2, 2),
            Op::AffineChannel => (3, 3),
            Op::Concat => (2, usize::MAX),
        }
    }

    /// True for operators that reduce over spatial dimensions.
    pub fn is_spatial_reduction(&self) -> bool {
        matches!(self, Op::GlobalMean)
    }
}
