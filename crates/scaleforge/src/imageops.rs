//! Pixel-layout helpers for the pipeline: orientation, sample conversion,
//! and alpha separation.

use sf_core::Result;
use sf_image::{ImageBuffer, SampleFormat, Samples};

/// Interleaved `f32` pixels (0–1) with `channels` samples per pixel.
#[derive(Debug, Clone, PartialEq)]
pub struct Pixels {
    /// Width.
    pub width: usize,
    /// Height.
    pub height: usize,
    /// Channels (1–4).
    pub channels: usize,
    /// Samples.
    pub data: Vec<f32>,
}

impl Pixels {
    /// Converts a decoded buffer to normalised floats.
    pub fn from_buffer(b: &ImageBuffer) -> Pixels {
        Pixels {
            width: b.width() as usize,
            height: b.height() as usize,
            channels: b.channels() as usize,
            data: b.to_f32(),
        }
    }

    /// Quantises to the given integer format (or keeps floats), clamping to
    /// the representable range.
    pub fn to_buffer(&self, format: SampleFormat) -> Result<ImageBuffer> {
        let samples = match format {
            SampleFormat::U8 => {
                Samples::U8(self.data.iter().map(|&v| (v.clamp(0.0, 1.0) * 255.0).round() as u8).collect())
            }
            SampleFormat::U16 => Samples::U16(
                self.data.iter().map(|&v| (v.clamp(0.0, 1.0) * 65_535.0).round() as u16).collect(),
            ),
            SampleFormat::F32 => Samples::F32(self.data.clone()),
        };
        ImageBuffer::new(self.width as u32, self.height as u32, self.channels as u8, samples)
    }

    /// Splits off the alpha channel, if any: (colour, alpha plane).
    pub fn split_alpha(&self) -> (Pixels, Option<Vec<f32>>) {
        if self.channels % 2 == 1 {
            return (self.clone(), None);
        }
        let cc = self.channels - 1;
        let mut colour = Vec::with_capacity(self.width * self.height * cc);
        let mut alpha = Vec::with_capacity(self.width * self.height);
        for px in self.data.chunks(self.channels) {
            colour.extend_from_slice(&px[..cc]);
            alpha.push(px[cc]);
        }
        (Pixels { width: self.width, height: self.height, channels: cc, data: colour }, Some(alpha))
    }

    /// Re-attaches an alpha plane of the same size.
    pub fn with_alpha(&self, alpha: &[f32]) -> Pixels {
        let c = self.channels + 1;
        let mut data = Vec::with_capacity(self.width * self.height * c);
        for (px, &a) in self.data.chunks(self.channels).zip(alpha) {
            data.extend_from_slice(px);
            data.push(a);
        }
        Pixels { width: self.width, height: self.height, channels: c, data }
    }

    /// Interleaved → planar `[c][h][w]`.
    pub fn to_planar(&self) -> Vec<f32> {
        let n = self.width * self.height;
        let mut out = vec![0f32; n * self.channels];
        for (i, px) in self.data.chunks(self.channels).enumerate() {
            for (c, &v) in px.iter().enumerate() {
                out[c * n + i] = v;
            }
        }
        out
    }

    /// Planar `[c][h][w]` → interleaved.
    pub fn from_planar(planar: &[f32], width: usize, height: usize, channels: usize) -> Pixels {
        let n = width * height;
        let mut data = vec![0f32; n * channels];
        for c in 0..channels {
            for i in 0..n {
                data[i * channels + c] = planar[c * n + i];
            }
        }
        Pixels { width, height, channels, data }
    }

    /// Applies an EXIF orientation (1–8) so the result is upright.
    pub fn oriented(&self, orientation: u8) -> Pixels {
        if orientation <= 1 || orientation > 8 {
            return self.clone();
        }
        let (w, h, c) = (self.width, self.height, self.channels);
        let transpose = orientation >= 5;
        let (nw, nh) = if transpose { (h, w) } else { (w, h) };
        let mut data = vec![0f32; w * h * c];
        for ny in 0..nh {
            for nx in 0..nw {
                // Map each destination pixel back to its source position.
                let (sx, sy) = match orientation {
                    2 => (w - 1 - nx, ny),
                    3 => (w - 1 - nx, h - 1 - ny),
                    4 => (nx, h - 1 - ny),
                    5 => (ny, nx),
                    6 => (ny, h - 1 - nx),
                    7 => (w - 1 - ny, h - 1 - nx),
                    _ => (w - 1 - ny, nx), // 8
                };
                let (src, dst) = ((sy * w + sx) * c, (ny * nw + nx) * c);
                data[dst..dst + c].copy_from_slice(&self.data[src..src + c]);
            }
        }
        Pixels { width: nw, height: nh, channels: c, data }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn grid() -> Pixels {
        // 3×2 grey: values 0..5 row-major.
        Pixels { width: 3, height: 2, channels: 1, data: (0..6).map(|v| v as f32).collect() }
    }

    #[test]
    fn orientations_match_their_definitions() {
        let g = grid();
        assert_eq!(g.oriented(1).data, vec![0., 1., 2., 3., 4., 5.]);
        assert_eq!(g.oriented(2).data, vec![2., 1., 0., 5., 4., 3.]); // mirror horizontal
        assert_eq!(g.oriented(3).data, vec![5., 4., 3., 2., 1., 0.]); // rotate 180
        assert_eq!(g.oriented(4).data, vec![3., 4., 5., 0., 1., 2.]); // mirror vertical
        let r = g.oriented(6); // stored rotated 90° CCW: rotate 90° CW to fix
        assert_eq!((r.width, r.height), (2, 3));
        assert_eq!(r.data, vec![3., 0., 4., 1., 5., 2.]);
        let r = g.oriented(8); // rotate 90° CCW
        assert_eq!(r.data, vec![2., 5., 1., 4., 0., 3.]);
        let r = g.oriented(5); // transpose
        assert_eq!(r.data, vec![0., 3., 1., 4., 2., 5.]);
        let r = g.oriented(7); // transverse
        assert_eq!(r.data, vec![5., 2., 4., 1., 3., 0.]);
    }

    #[test]
    fn alpha_and_planar_round_trips() {
        let p =
            Pixels { width: 2, height: 1, channels: 4, data: vec![0.1, 0.2, 0.3, 1.0, 0.4, 0.5, 0.6, 0.5] };
        let (c, a) = p.split_alpha();
        assert_eq!(c.channels, 3);
        assert_eq!(a.as_deref(), Some(&[1.0, 0.5][..]));
        assert_eq!(c.with_alpha(&a.unwrap()), p);
        let planar = c.to_planar();
        assert_eq!(planar, vec![0.1, 0.4, 0.2, 0.5, 0.3, 0.6]);
        assert_eq!(Pixels::from_planar(&planar, 2, 1, 3), c);
        let q = c.to_buffer(SampleFormat::U8).unwrap();
        assert_eq!(q.samples(), &Samples::U8(vec![26, 51, 77, 102, 128, 153]));
    }
}
