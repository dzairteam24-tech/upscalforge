//! Tile planning and tiled execution (ADR-0004).
//!
//! **Exact mode.** The image is split into non-overlapping *cores*. Each
//! core is computed inside a *window*: the core plus at least `halo`
//! pixels of real image context on every side that is not the image
//! border. All windows have one size, so one compiled plan serves every
//! tile and tiles can be batched. Because every output pixel sees exactly
//! the inputs of a whole-image run, tiled output equals whole-image output,
//! and no seams can exist.
//!
//! **Blended mode.** For models whose receptive field is too large to cover,
//! windows get a smaller halo, and overlapping outputs are cross-faded. The
//! deviation from a whole-image run is not zero. It must be measured per
//! model, never assumed.

use std::sync::Arc;

use sf_compute::{Binding, Bindings, Buffer, Event, Executable, Precision};
use sf_core::{CancelToken, Error, ProgressEvent, ProgressSink, Rect, Result, Size, geometry::align_up};
use sf_graph::{Graph, Shape};

use crate::vram::{Pool, VramManager};

/// Spatial properties of a model relevant to tiling.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TileGeometry {
    /// Receptive radius in input pixels (the halo exact mode needs).
    pub halo: u32,
    /// Window origins and the canonical image size must be multiples of this.
    pub alignment: u32,
    /// Output pixels per input pixel.
    pub scale: u32,
}

/// Tiling mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TileMode {
    /// Halo equal to the receptive radius: bit-exact, seam-free.
    Exact,
    /// Smaller halo with cross-fading; the deviation must be measured.
    Blended {
        /// Halo in input pixels.
        halo: u32,
    },
}

/// One tile.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Tile {
    /// The region this tile is responsible for (disjoint from other cores).
    pub core: Rect,
    /// The region actually computed.
    pub window: Rect,
}

/// A complete tile plan over the canonical (aligned) image.
#[derive(Debug, Clone, PartialEq)]
pub struct TilePlan {
    /// Canonical image size (padded to the alignment).
    pub image: Size,
    /// Uniform window size.
    pub window: Size,
    /// Tiles in row-major band order.
    pub tiles: Vec<Tile>,
    /// Mode.
    pub mode: TileMode,
    /// Halo actually used.
    pub halo: u32,
    /// Output scale.
    pub scale: u32,
}

/// The image size padded up to a multiple of `alignment`.
pub fn canonical_size(size: Size, alignment: u32) -> Result<Size> {
    let a = alignment.max(1);
    let w = align_up(size.width, a).ok_or_else(|| Error::limit_exceeded("width overflows alignment"))?;
    let h = align_up(size.height, a).ok_or_else(|| Error::limit_exceeded("height overflows alignment"))?;
    Ok(Size::new(w, h))
}

/// Plans tiles of (at most) `core` size over an image of `image` size.
pub fn plan(image: Size, core: Size, geom: TileGeometry, mode: TileMode) -> Result<TilePlan> {
    let a = geom.alignment.max(1);
    let canon = canonical_size(image, a)?;
    if canon.is_empty() || core.is_empty() {
        return Err(Error::invalid_input("empty image or tile size"));
    }
    let halo = match mode {
        TileMode::Exact => geom.halo,
        TileMode::Blended { halo } => halo,
    };
    let halo_a = align_up(halo, a).ok_or_else(|| Error::limit_exceeded("halo overflow"))?;
    let core_w = align_up(core.width.min(canon.width), a).unwrap_or(canon.width).min(canon.width);
    let core_h = align_up(core.height.min(canon.height), a).unwrap_or(canon.height).min(canon.height);
    // Extra `a` absorbs rounding window origins down to the alignment.
    let span = |c: u32, full: u32| -> u32 {
        align_up(c.saturating_add(2 * halo_a).saturating_add(a), a).unwrap_or(full).min(full)
    };
    let window = Size::new(span(core_w, canon.width), span(core_h, canon.height));
    let origin = |c0: u32, win: u32, full: u32| -> u32 {
        let want = c0.saturating_sub(halo_a) / a * a;
        want.min(full - win)
    };
    let mut tiles = Vec::new();
    let mut y = 0;
    while y < canon.height {
        let ch = core_h.min(canon.height - y);
        let mut x = 0;
        while x < canon.width {
            let cw = core_w.min(canon.width - x);
            let core_r = Rect::new(x, y, cw, ch).expect("inside the image");
            let wx = origin(x, window.width, canon.width);
            let wy = origin(y, window.height, canon.height);
            let win = Rect::new(wx, wy, window.width, window.height).expect("inside the image");
            tiles.push(Tile { core: core_r, window: win });
            x += cw;
        }
        y += ch;
    }
    Ok(TilePlan { image: canon, window, tiles, mode, halo, scale: geom.scale })
}

/// A planar `f32` image `[channels][height][width]`.
#[derive(Debug, Clone, PartialEq)]
pub struct Planar {
    /// Channels.
    pub channels: usize,
    /// Width.
    pub width: usize,
    /// Height.
    pub height: usize,
    /// Samples.
    pub data: Vec<f32>,
}

impl Planar {
    /// A zero image.
    pub fn zeros(channels: usize, width: usize, height: usize) -> Planar {
        Planar { channels, width, height, data: vec![0.0; channels * width * height] }
    }

    /// Copies a rectangle into a new planar image.
    pub fn crop(&self, r: Rect) -> Planar {
        let (x0, y0, w, h) = (r.x() as usize, r.y() as usize, r.width() as usize, r.height() as usize);
        let mut out = Planar::zeros(self.channels, w, h);
        for c in 0..self.channels {
            for y in 0..h {
                let src = (c * self.height + y0 + y) * self.width + x0;
                out.data[(c * h + y) * w..][..w].copy_from_slice(&self.data[src..src + w]);
            }
        }
        out
    }

    /// Pads right and bottom by reflection (mirror without repeating the
    /// edge sample) to `size`.
    pub fn pad_reflect(&self, size: Size) -> Planar {
        let (w, h) = (size.width as usize, size.height as usize);
        if (w, h) == (self.width, self.height) {
            return self.clone();
        }
        let refl = |i: usize, n: usize| -> usize {
            if n == 1 {
                return 0;
            }
            let period = 2 * (n - 1);
            let m = i % period;
            if m < n { m } else { period - m }
        };
        let mut out = Planar::zeros(self.channels, w, h);
        for c in 0..self.channels {
            for y in 0..h {
                for x in 0..w {
                    out.data[(c * h + y) * w + x] = self.data
                        [(c * self.height + refl(y, self.height)) * self.width + refl(x, self.width)];
                }
            }
        }
        out
    }
}

/// Extra, tile-independent graph inputs (after the image input).
#[derive(Debug, Clone, PartialEq)]
pub enum ExtraInput {
    /// A runtime scalar.
    Scalar(f32),
    /// A vector `[1, n]`.
    Vector(Vec<f32>),
}

/// Runs `graph` over `input` following `plan`. The graph's first input
/// must be the image; `extra` supplies the remaining inputs. `params` are
/// the already-uploaded weights, and `ready` are the events that signal
/// their upload has completed (the run waits on them before reading).
/// Returns the output of the first graph output, at `plan.scale` times the
/// canonical input size.
#[allow(clippy::too_many_arguments)]
pub fn run_tiled(
    vram: &VramManager,
    graph: &Graph,
    params: &[&Buffer],
    ready: &[Event],
    extra: &[ExtraInput],
    input: &Planar,
    plan: &TilePlan,
    cancel: &CancelToken,
    progress: &dyn ProgressSink,
) -> Result<Planar> {
    if (input.width, input.height) != (plan.image.width as usize, plan.image.height as usize) {
        return Err(Error::invalid_input("input does not match the canonical plan size"));
    }
    let device = Arc::clone(vram.device());
    let (ww, wh) = (plan.window.width as usize, plan.window.height as usize);
    let mut shapes = vec![Shape::Spatial { n: 1, c: input.channels as u32, h: wh as u32, w: ww as u32 }];
    for e in extra {
        shapes.push(match e {
            ExtraInput::Scalar(_) => Shape::Scalar,
            ExtraInput::Vector(v) => Shape::Vector { n: 1, c: v.len() as u32 },
        });
    }
    let exe: Arc<dyn Executable> = device.compile(graph, &shapes, Precision::F32)?;
    let out_shape = sf_graph::infer_shapes(graph, &shapes)?
        .value(graph, graph.outputs[0].value)
        .ok_or_else(|| Error::internal("output has no shape"))?;
    let Shape::Spatial { c: oc, h: oh, w: ow, .. } = out_shape else {
        return Err(Error::invalid_input("the first graph output must be spatial"));
    };
    let s = plan.scale as usize;
    if (oh as usize, ow as usize) != (wh * s, ww * s) {
        return Err(Error::invalid_input(format!(
            "graph output {ow}x{oh} does not match window {ww}x{wh} at scale {s}"
        )));
    }
    let oc = oc as usize;
    let mem = exe.memory();
    let arena = vram.allocate(Pool::Activations, mem.arena_bytes)?;
    let in_buf = vram.allocate(Pool::Io, (input.channels * ww * wh * 4) as u64)?;
    let out_buf = vram.allocate(Pool::Io, (oc * ww * wh * s * s * 4) as u64)?;
    let mut extra_bufs = Vec::new();
    let mut queue = device.create_queue()?;
    for &e in ready {
        queue.wait(e)?;
    }
    for e in extra {
        if let ExtraInput::Vector(v) = e {
            let b = vram.allocate(Pool::Io, (v.len() * 4) as u64)?;
            queue.upload(b.buffer(), v)?;
            extra_bufs.push(Some(b));
        } else {
            extra_bufs.push(None);
        }
    }

    let (fw, fh) = (input.width * s, input.height * s);
    let mut out = Planar::zeros(oc, fw, fh);
    let blended = matches!(plan.mode, TileMode::Blended { .. });
    let mut weight = if blended { vec![0f32; fw * fh] } else { Vec::new() };
    let total = plan.tiles.len() as u64;
    for (i, tile) in plan.tiles.iter().enumerate() {
        cancel.check()?;
        queue.upload(in_buf.buffer(), &input.crop(tile.window).data)?;
        let mut inputs = vec![Binding::Buffer(in_buf.buffer())];
        for (e, b) in extra.iter().zip(&extra_bufs) {
            inputs.push(match (e, b) {
                (ExtraInput::Scalar(v), _) => Binding::Scalar(*v),
                (ExtraInput::Vector(_), Some(b)) => Binding::Buffer(b.buffer()),
                _ => return Err(Error::internal("missing vector buffer")),
            });
        }
        let bindings = Bindings {
            inputs,
            params: params.to_vec(),
            outputs: vec![out_buf.buffer()],
            arena: arena.buffer(),
        };
        queue.execute(exe.as_ref(), &bindings)?;
        let result = queue.download(out_buf.buffer())?.wait()?;
        let (wx, wy) = (tile.window.x() as usize * s, tile.window.y() as usize * s);
        let (tw, th) = (ww * s, wh * s);
        if !blended {
            let c = tile.core;
            for ch in 0..oc {
                for y in c.y() as usize * s..c.bottom() as usize * s {
                    let src = (ch * th + y - wy) * tw + (c.x() as usize * s - wx);
                    let dst = (ch * fh + y) * fw + c.x() as usize * s;
                    let n = c.width() as usize * s;
                    out.data[dst..dst + n].copy_from_slice(&result[src..src + n]);
                }
            }
        } else {
            blend_into(&mut out, &mut weight, &result, tile, plan, (tw, th));
        }
        progress.report(&ProgressEvent { stage: "tiles", completed: i as u64 + 1, total });
    }
    if blended {
        for ch in 0..oc {
            for (i, &wv) in weight.iter().enumerate() {
                if wv > 0.0 {
                    out.data[ch * fw * fh + i] /= wv;
                }
            }
        }
    }
    Ok(out)
}

/// Adds a window's output with a weight that ramps up over the halo on
/// every side that is not the image border.
fn blend_into(
    out: &mut Planar,
    weight: &mut [f32],
    result: &[f32],
    tile: &Tile,
    plan: &TilePlan,
    (tw, th): (usize, usize),
) {
    let s = plan.scale as usize;
    let ramp = (plan.halo as usize * s).max(1) as f32;
    let (fw, fh) = (out.width, out.height);
    let w = tile.window;
    let (x0, y0) = (w.x() as usize * s, w.y() as usize * s);
    let left_border = w.x() == 0;
    let top_border = w.y() == 0;
    let right_border = w.right() == plan.image.width;
    let bottom_border = w.bottom() == plan.image.height;
    let edge = |d: usize, border: bool| if border { 1.0 } else { ((d as f32 + 0.5) / ramp).min(1.0) };
    for y in 0..th {
        let wy = edge(y, top_border).min(edge(th - 1 - y, bottom_border));
        for x in 0..tw {
            let wv = wy * edge(x, left_border).min(edge(tw - 1 - x, right_border));
            // Raised-cosine shaping of the linear ramp.
            let wv = 0.5 - 0.5 * (std::f32::consts::PI * wv).cos();
            let idx = (y0 + y) * fw + x0 + x;
            weight[idx] += wv;
            for ch in 0..out.channels {
                out.data[ch * fw * fh + idx] += wv * result[(ch * th + y) * tw + x];
            }
        }
    }
}

#[cfg(test)]
mod tests;
