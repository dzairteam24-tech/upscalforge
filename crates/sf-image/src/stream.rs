//! Band-by-band image input and output, for images larger than memory
//! (ARCHITECTURE §8.1).
//!
//! A [`RowSource`] hands out consecutive bands of rows and can start
//! again from the top. A [`RowSink`] accepts bands in order. Sources:
//! - [`crate::png::PngSource`]: non-interlaced PNG, decoded incrementally
//!   from the file; memory holds one band and the 32 KiB DEFLATE window;
//! - [`MemorySource`]: any format, decoded once at its native precision
//!   (8/16-bit), with EXIF orientation applied.
//!
//! Sinks: [`crate::png::PngSink`] and [`crate::tiff::TiffSink`], whose
//! output is byte-for-byte what the whole-image encoders produce.
//!
//! Streaming decode of TIFF and JPEG is INCOMPLETE: those formats are read
//! through [`MemorySource`].

use sf_core::{Error, Limits, Result};

use crate::image::{FileFormat, Image, ImageBuffer, ImageMeta, SampleFormat};

/// What a source delivers.
#[derive(Debug, Clone, PartialEq)]
pub struct SourceInfo {
    /// Width after orientation.
    pub width: u32,
    /// Height after orientation.
    pub height: u32,
    /// Channels per pixel.
    pub channels: u8,
    /// Sample format of every band.
    pub sample: SampleFormat,
    /// Metadata (orientation, when present, has already been applied).
    pub meta: ImageMeta,
    /// File format.
    pub format: FileFormat,
}

impl SourceInfo {
    /// Bytes of the whole decoded image.
    pub fn decoded_bytes(&self) -> u64 {
        u64::from(self.width)
            * u64::from(self.height)
            * u64::from(self.channels)
            * u64::from(self.sample.bytes())
    }
}

/// Sequential access to an image in bands of rows.
pub trait RowSource: Send {
    /// Size and format.
    fn info(&self) -> &SourceInfo;

    /// The next `rows` rows (fewer at the bottom of the image). Fails when
    /// no rows are left.
    fn read_rows(&mut self, rows: u32) -> Result<ImageBuffer>;

    /// Starts again from the first row.
    fn rewind(&mut self) -> Result<()>;

    /// Bytes the source keeps in memory between calls.
    fn resident_bytes(&self) -> u64;
}

/// Accepts an image band by band, top to bottom.
pub trait RowSink {
    /// Appends rows (the full width of the image).
    fn write_rows(&mut self, rows: &ImageBuffer) -> Result<()>;

    /// Completes the file. Fails if fewer rows than the height were written.
    fn finish(self: Box<Self>) -> Result<()>;
}

/// Checks a band against the sink's layout and returns its height.
pub(crate) fn check_band(
    band: &ImageBuffer,
    (width, height, channels, sample): (u32, u32, u8, SampleFormat),
    rows_done: u32,
) -> Result<u32> {
    if band.width() != width || band.channels() != channels || band.format() != sample {
        return Err(Error::invalid_input(format!(
            "band {}x{} with {} channels ({:?}) does not match the image {width} wide, {channels} channels ({sample:?})",
            band.width(),
            band.height(),
            band.channels(),
            band.format()
        )));
    }
    if rows_done + band.height() > height {
        return Err(Error::invalid_input("more rows written than the image height"));
    }
    Ok(band.height())
}

/// A decoded image served in bands.
pub struct MemorySource {
    image: ImageBuffer,
    info: SourceInfo,
    next: u32,
}

impl MemorySource {
    /// Wraps a decoded image, applying its EXIF orientation.
    pub fn new(image: Image) -> MemorySource {
        let mut meta = image.meta;
        let buffer = image.buffer.oriented(meta.orientation.unwrap_or(1));
        meta.orientation = None;
        let info = SourceInfo {
            width: buffer.width(),
            height: buffer.height(),
            channels: buffer.channels(),
            sample: buffer.format(),
            meta,
            format: image.format,
        };
        MemorySource { image: buffer, info, next: 0 }
    }

    /// Decodes a file completely (any supported format).
    pub fn open(path: &std::path::Path, limits: &Limits) -> Result<MemorySource> {
        let len = std::fs::metadata(path).map_err(|e| Error::from(e).context(path.display()))?.len();
        if len > limits.max_decoded_bytes {
            return Err(Error::limit_exceeded(format!("{} is larger than the decode limit", path.display())));
        }
        let data = std::fs::read(path).map_err(|e| Error::from(e).context(path.display()))?;
        let image = crate::decode_any(&data, limits).map_err(|e| e.context(path.display()))?;
        Ok(MemorySource::new(image))
    }

    /// The whole (oriented) image.
    pub fn image(&self) -> &ImageBuffer {
        &self.image
    }
}

impl RowSource for MemorySource {
    fn info(&self) -> &SourceInfo {
        &self.info
    }

    fn read_rows(&mut self, rows: u32) -> Result<ImageBuffer> {
        let h = self.info.height;
        if self.next >= h || rows == 0 {
            return Err(Error::invalid_input("no rows left in the source"));
        }
        let n = rows.min(h - self.next);
        let band = self.image.rows(self.next, n)?;
        self.next += n;
        Ok(band)
    }

    fn rewind(&mut self) -> Result<()> {
        self.next = 0;
        Ok(())
    }

    fn resident_bytes(&self) -> u64 {
        self.info.decoded_bytes()
    }
}

#[cfg(test)]
mod tests;
