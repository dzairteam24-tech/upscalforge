//! Minimal EXIF reading: only the orientation tag (0x0112) of IFD0.

/// Returns the EXIF orientation (1–8) from a TIFF-structured EXIF block
/// (starting at the byte-order mark). Malformed data yields `None`.
pub fn orientation(tiff: &[u8]) -> Option<u8> {
    let le = match tiff.get(0..2)? {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let u16_at = |p: usize| -> Option<u16> {
        let b = tiff.get(p..p + 2)?;
        Some(if le { u16::from_le_bytes([b[0], b[1]]) } else { u16::from_be_bytes([b[0], b[1]]) })
    };
    let u32_at = |p: usize| -> Option<u32> {
        let b = tiff.get(p..p + 4)?;
        let a = [b[0], b[1], b[2], b[3]];
        Some(if le { u32::from_le_bytes(a) } else { u32::from_be_bytes(a) })
    };
    if u16_at(2)? != 42 {
        return None;
    }
    let ifd = u32_at(4)? as usize;
    let count = u16_at(ifd)? as usize;
    for i in 0..count.min(512) {
        let e = ifd + 2 + i * 12;
        if u16_at(e)? == 0x0112 && u16_at(e + 2)? == 3 {
            let v = u16_at(e + 8)?;
            return (1..=8).contains(&v).then_some(v as u8);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn block(le: bool, orient: u16) -> Vec<u8> {
        let mut v = Vec::new();
        let p16 = |v: &mut Vec<u8>, x: u16| v.extend(if le { x.to_le_bytes() } else { x.to_be_bytes() });
        let p32 = |v: &mut Vec<u8>, x: u32| v.extend(if le { x.to_le_bytes() } else { x.to_be_bytes() });
        v.extend(if le { b"II" } else { b"MM" });
        p16(&mut v, 42);
        p32(&mut v, 8);
        p16(&mut v, 1);
        p16(&mut v, 0x0112);
        p16(&mut v, 3);
        p32(&mut v, 1);
        p16(&mut v, orient);
        p16(&mut v, 0);
        p32(&mut v, 0);
        v
    }

    #[test]
    fn reads_both_byte_orders_and_rejects_garbage() {
        assert_eq!(orientation(&block(true, 6)), Some(6));
        assert_eq!(orientation(&block(false, 8)), Some(8));
        assert_eq!(orientation(&block(true, 9)), None);
        assert_eq!(orientation(b"II*\0\xff\xff\xff\xff"), None);
        assert_eq!(orientation(&[]), None);
    }
}
