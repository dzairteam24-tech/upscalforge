//! In-memory images and their metadata.

use sf_core::{Error, Limits, Result};

/// Sample storage, interleaved by pixel (e.g. `R G B A R G B A …`).
#[derive(Debug, Clone, PartialEq)]
pub enum Samples {
    /// 8-bit integer samples.
    U8(Vec<u8>),
    /// 16-bit integer samples.
    U16(Vec<u16>),
    /// Floating-point samples (nominal range 0–1; HDR may exceed it).
    F32(Vec<f32>),
}

impl Samples {
    /// Number of samples.
    pub fn len(&self) -> usize {
        match self {
            Samples::U8(v) => v.len(),
            Samples::U16(v) => v.len(),
            Samples::F32(v) => v.len(),
        }
    }

    /// True if empty.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Bytes per sample.
    pub fn sample_bytes(&self) -> u32 {
        match self {
            Samples::U8(_) => 1,
            Samples::U16(_) => 2,
            Samples::F32(_) => 4,
        }
    }
}

/// A decoded image: `width × height` pixels of `channels` interleaved
/// samples. Channels: 1 grey, 2 grey + alpha, 3 RGB, 4 RGBA. Alpha, when
/// present, is straight (not premultiplied).
#[derive(Debug, Clone, PartialEq)]
pub struct ImageBuffer {
    width: u32,
    height: u32,
    channels: u8,
    samples: Samples,
}

impl ImageBuffer {
    /// Wraps samples, checking that dimensions and length agree.
    pub fn new(width: u32, height: u32, channels: u8, samples: Samples) -> Result<ImageBuffer> {
        if !(1..=4).contains(&channels) {
            return Err(Error::invalid_input(format!("{channels} channels; 1 to 4 are supported")));
        }
        let expected = u64::from(width) * u64::from(height) * u64::from(channels);
        if width == 0 || height == 0 || samples.len() as u64 != expected {
            return Err(Error::invalid_input(format!(
                "{width}x{height}x{channels} image needs {expected} samples, got {}",
                samples.len()
            )));
        }
        Ok(ImageBuffer { width, height, channels, samples })
    }

    /// Allocates a zeroed image after checking `limits`.
    pub fn zeroed(
        width: u32,
        height: u32,
        channels: u8,
        format: SampleFormat,
        limits: &Limits,
    ) -> Result<ImageBuffer> {
        let bytes_per_pixel = u32::from(channels) * format.bytes();
        limits.check_decoded_bytes(width, height, bytes_per_pixel)?;
        let n = width as usize * height as usize * channels as usize;
        let samples = match format {
            SampleFormat::U8 => Samples::U8(vec![0; n]),
            SampleFormat::U16 => Samples::U16(vec![0; n]),
            SampleFormat::F32 => Samples::F32(vec![0.0; n]),
        };
        ImageBuffer::new(width, height, channels, samples)
    }

    /// Width in pixels.
    pub fn width(&self) -> u32 {
        self.width
    }

    /// Height in pixels.
    pub fn height(&self) -> u32 {
        self.height
    }

    /// Samples per pixel.
    pub fn channels(&self) -> u8 {
        self.channels
    }

    /// True if the last channel is alpha.
    pub fn has_alpha(&self) -> bool {
        self.channels == 2 || self.channels == 4
    }

    /// Sample format.
    pub fn format(&self) -> SampleFormat {
        match self.samples {
            Samples::U8(_) => SampleFormat::U8,
            Samples::U16(_) => SampleFormat::U16,
            Samples::F32(_) => SampleFormat::F32,
        }
    }

    /// The samples.
    pub fn samples(&self) -> &Samples {
        &self.samples
    }

    /// Mutable samples (length is fixed).
    pub fn samples_mut(&mut self) -> &mut Samples {
        &mut self.samples
    }

    /// Consumes the buffer, returning its samples.
    pub fn into_samples(self) -> Samples {
        self.samples
    }

    /// Converts to normalised `f32` (integers map to 0–1).
    pub fn to_f32(&self) -> Vec<f32> {
        match &self.samples {
            Samples::U8(v) => v.iter().map(|&x| f32::from(x) / 255.0).collect(),
            Samples::U16(v) => v.iter().map(|&x| f32::from(x) / 65_535.0).collect(),
            Samples::F32(v) => v.clone(),
        }
    }
}

/// Sample formats.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SampleFormat {
    /// 8-bit unsigned.
    U8,
    /// 16-bit unsigned.
    U16,
    /// 32-bit float.
    F32,
}

impl SampleFormat {
    /// Bytes per sample.
    pub fn bytes(self) -> u32 {
        match self {
            SampleFormat::U8 => 1,
            SampleFormat::U16 => 2,
            SampleFormat::F32 => 4,
        }
    }
}

/// File formats ScaleForge reads and writes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FileFormat {
    /// PNG.
    Png,
    /// JPEG (JFIF/EXIF).
    Jpeg,
    /// TIFF / BigTIFF.
    Tiff,
}

/// Evidence about JPEG compression, kept for analysis.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct JpegInfo {
    /// Quantisation tables as stored (64 values, zig-zag order), by table id.
    pub quant_tables: Vec<(u8, Vec<u16>)>,
    /// Horizontal and vertical sampling factors per component.
    pub sampling: Vec<(u8, u8)>,
    /// True for progressive coding.
    pub progressive: bool,
}

/// Metadata that affects how pixels must be interpreted.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ImageMeta {
    /// Embedded ICC profile.
    pub icc_profile: Option<Vec<u8>>,
    /// The file declares sRGB (PNG `sRGB` chunk or JFIF defaults).
    pub declares_srgb: bool,
    /// File gamma exponent as declared (PNG `gAMA`: encoding gamma, e.g. 0.45455).
    pub gamma: Option<f64>,
    /// EXIF orientation 1–8 (1 = upright), if declared.
    pub orientation: Option<u8>,
    /// JPEG coding details, for JPEG sources.
    pub jpeg: Option<JpegInfo>,
}

/// A decoded image with metadata.
#[derive(Debug, Clone, PartialEq)]
pub struct Image {
    /// Pixels.
    pub buffer: ImageBuffer,
    /// Metadata.
    pub meta: ImageMeta,
    /// Source format.
    pub format: FileFormat,
}
