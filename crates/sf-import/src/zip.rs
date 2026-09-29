//! A minimal ZIP reader (central directory, stored and deflated entries).
//! ZIP64 archives are rejected; the model files this is used for are far
//! below 4 GiB.

use sf_core::{Error, Result};

fn bad(what: &str) -> Error {
    Error::invalid_input(format!("zip: {what}"))
}

/// One archive member.
#[derive(Debug, Clone)]
pub struct Entry {
    /// Member name.
    pub name: String,
    method: u16,
    compressed: usize,
    size: usize,
    local_offset: usize,
}

fn u16_at(d: &[u8], p: usize) -> Result<u16> {
    d.get(p..p + 2).map(|b| u16::from_le_bytes([b[0], b[1]])).ok_or_else(|| bad("truncated"))
}

fn u32_at(d: &[u8], p: usize) -> Result<u32> {
    d.get(p..p + 4).map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]])).ok_or_else(|| bad("truncated"))
}

/// Lists the members of an archive.
pub fn entries(d: &[u8]) -> Result<Vec<Entry>> {
    // The end-of-central-directory record is within the last 64 KiB + 22 bytes.
    let search_from = d.len().saturating_sub(65_557);
    let eocd = (search_from..d.len().saturating_sub(21))
        .rev()
        .find(|&p| d[p..p + 4] == [0x50, 0x4B, 0x05, 0x06])
        .ok_or_else(|| bad("end of central directory not found"))?;
    let count = u16_at(d, eocd + 10)? as usize;
    let cd_offset = u32_at(d, eocd + 16)? as usize;
    if cd_offset == 0xFFFF_FFFF || count == 0xFFFF {
        return Err(Error::unsupported("zip: ZIP64 archives are not supported"));
    }
    let mut out = Vec::with_capacity(count);
    let mut p = cd_offset;
    for _ in 0..count {
        if u32_at(d, p)? != 0x0201_4B50 {
            return Err(bad("bad central directory entry"));
        }
        let flags = u16_at(d, p + 8)?;
        let method = u16_at(d, p + 10)?;
        let compressed = u32_at(d, p + 20)? as usize;
        let size = u32_at(d, p + 24)? as usize;
        let (nlen, xlen, clen) =
            (u16_at(d, p + 28)? as usize, u16_at(d, p + 30)? as usize, u16_at(d, p + 32)? as usize);
        let local_offset = u32_at(d, p + 42)? as usize;
        if flags & 1 != 0 {
            return Err(Error::unsupported("zip: encrypted members are not supported"));
        }
        let name =
            String::from_utf8_lossy(d.get(p + 46..p + 46 + nlen).ok_or_else(|| bad("truncated name"))?)
                .to_string();
        out.push(Entry { name, method, compressed, size, local_offset });
        p += 46 + nlen + xlen + clen;
    }
    Ok(out)
}

/// Extracts a member's data, refusing anything above `max` bytes.
pub fn extract<'a>(d: &'a [u8], e: &Entry, max: usize) -> Result<std::borrow::Cow<'a, [u8]>> {
    if e.size > max {
        return Err(Error::limit_exceeded(format!("zip: member {:?} is {} bytes", e.name, e.size)));
    }
    let p = e.local_offset;
    if u32_at(d, p)? != 0x0403_4B50 {
        return Err(bad("bad local header"));
    }
    let (nlen, xlen) = (u16_at(d, p + 26)? as usize, u16_at(d, p + 28)? as usize);
    let start = p + 30 + nlen + xlen;
    let raw = d.get(start..start + e.compressed).ok_or_else(|| bad("member data outside the archive"))?;
    match e.method {
        0 => {
            if raw.len() != e.size {
                return Err(bad("stored member size mismatch"));
            }
            Ok(std::borrow::Cow::Borrowed(raw))
        }
        8 => {
            let (out, _) = sf_image::zlib::inflate(raw, e.size)?;
            if out.len() != e.size {
                return Err(bad("inflated member size mismatch"));
            }
            Ok(std::borrow::Cow::Owned(out))
        }
        m => Err(Error::unsupported(format!("zip: compression method {m}"))),
    }
}

#[cfg(test)]
pub(crate) mod test_writer {
    //! Writes stored ZIP archives for tests.

    pub fn write(members: &[(&str, &[u8])]) -> Vec<u8> {
        let mut out = Vec::new();
        let mut central = Vec::new();
        for (name, data) in members {
            let off = out.len() as u32;
            let crc = sf_image::checksum::crc32(data);
            out.extend(0x0403_4B50u32.to_le_bytes());
            out.extend([20, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
            out.extend(crc.to_le_bytes());
            out.extend((data.len() as u32).to_le_bytes());
            out.extend((data.len() as u32).to_le_bytes());
            out.extend((name.len() as u16).to_le_bytes());
            out.extend(0u16.to_le_bytes());
            out.extend(name.as_bytes());
            out.extend(*data);
            central.extend(0x0201_4B50u32.to_le_bytes());
            central.extend([20, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
            central.extend(crc.to_le_bytes());
            central.extend((data.len() as u32).to_le_bytes());
            central.extend((data.len() as u32).to_le_bytes());
            central.extend((name.len() as u16).to_le_bytes());
            central.extend([0u8; 12]);
            central.extend(off.to_le_bytes());
            central.extend(name.as_bytes());
        }
        let cd_off = out.len() as u32;
        out.extend(&central);
        out.extend(0x0605_4B50u32.to_le_bytes());
        out.extend([0u8; 4]);
        out.extend((members.len() as u16).to_le_bytes());
        out.extend((members.len() as u16).to_le_bytes());
        out.extend((central.len() as u32).to_le_bytes());
        out.extend(cd_off.to_le_bytes());
        out.extend(0u16.to_le_bytes());
        out
    }
}
