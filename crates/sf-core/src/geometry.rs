//! Overflow-checked image geometry.
//!
//! [`Rect`] maintains the invariant that `x + width` and `y + height` fit in
//! `u32`. Every constructor and operation that could break it returns
//! `Option`, so tiling arithmetic can never wrap silently.

/// Width and height in pixels.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub struct Size {
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
}

impl Size {
    /// Creates a size.
    pub const fn new(width: u32, height: u32) -> Self {
        Size { width, height }
    }

    /// Pixel count (cannot overflow `u64`).
    pub fn area(self) -> u64 {
        u64::from(self.width) * u64::from(self.height)
    }

    /// True if either dimension is zero.
    pub fn is_empty(self) -> bool {
        self.width == 0 || self.height == 0
    }

    /// Multiplies both dimensions, or `None` on overflow.
    pub fn checked_scale(self, factor: u32) -> Option<Size> {
        Some(Size::new(self.width.checked_mul(factor)?, self.height.checked_mul(factor)?))
    }
}

/// An axis-aligned pixel rectangle `[x, x + width) × [y, y + height)`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub struct Rect {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
}

impl Rect {
    /// Creates a rectangle, or `None` if its far edges overflow `u32`.
    pub fn new(x: u32, y: u32, width: u32, height: u32) -> Option<Rect> {
        x.checked_add(width)?;
        y.checked_add(height)?;
        Some(Rect { x, y, width, height })
    }

    /// The rectangle `[0, width) × [0, height)`.
    pub fn from_size(size: Size) -> Rect {
        Rect { x: 0, y: 0, width: size.width, height: size.height }
    }

    /// Left edge.
    pub fn x(self) -> u32 {
        self.x
    }

    /// Top edge.
    pub fn y(self) -> u32 {
        self.y
    }

    /// Width.
    pub fn width(self) -> u32 {
        self.width
    }

    /// Height.
    pub fn height(self) -> u32 {
        self.height
    }

    /// Exclusive right edge.
    pub fn right(self) -> u32 {
        self.x + self.width
    }

    /// Exclusive bottom edge.
    pub fn bottom(self) -> u32 {
        self.y + self.height
    }

    /// Width and height.
    pub fn size(self) -> Size {
        Size::new(self.width, self.height)
    }

    /// Pixel count.
    pub fn area(self) -> u64 {
        self.size().area()
    }

    /// True if the rectangle covers no pixels.
    pub fn is_empty(self) -> bool {
        self.size().is_empty()
    }

    /// True if pixel `(px, py)` lies inside.
    pub fn contains_point(self, px: u32, py: u32) -> bool {
        px >= self.x && px < self.right() && py >= self.y && py < self.bottom()
    }

    /// True if `other` lies entirely inside `self`. An empty `other` is
    /// contained in any rectangle.
    pub fn contains(self, other: Rect) -> bool {
        other.is_empty()
            || (other.x >= self.x
                && other.y >= self.y
                && other.right() <= self.right()
                && other.bottom() <= self.bottom())
    }

    /// The overlapping region, or `None` if the rectangles do not overlap.
    pub fn intersect(self, other: Rect) -> Option<Rect> {
        let x0 = self.x.max(other.x);
        let y0 = self.y.max(other.y);
        let x1 = self.right().min(other.right());
        let y1 = self.bottom().min(other.bottom());
        if x0 < x1 && y0 < y1 { Some(Rect { x: x0, y: y0, width: x1 - x0, height: y1 - y0 }) } else { None }
    }

    /// Grows every side by `margin`, then clips to `bounds`.
    ///
    /// Returns `None` if the grown rectangle does not overlap `bounds`.
    pub fn expand_clamped(self, margin: u32, bounds: Rect) -> Option<Rect> {
        let x0 = self.x.saturating_sub(margin).max(bounds.x);
        let y0 = self.y.saturating_sub(margin).max(bounds.y);
        let x1 = self.right().saturating_add(margin).min(bounds.right());
        let y1 = self.bottom().saturating_add(margin).min(bounds.bottom());
        if x0 < x1 && y0 < y1 { Some(Rect { x: x0, y: y0, width: x1 - x0, height: y1 - y0 }) } else { None }
    }

    /// Multiplies position and size by `factor` (LR → HR coordinates), or
    /// `None` on overflow.
    pub fn scaled(self, factor: u32) -> Option<Rect> {
        Rect::new(
            self.x.checked_mul(factor)?,
            self.y.checked_mul(factor)?,
            self.width.checked_mul(factor)?,
            self.height.checked_mul(factor)?,
        )
    }

    /// Expresses `self` in the coordinate system of `outer` (whose top-left
    /// becomes the origin). `None` if `self` is empty or not inside `outer`.
    pub fn relative_to(self, outer: Rect) -> Option<Rect> {
        if !outer.contains(self) || self.is_empty() {
            return None;
        }
        Some(Rect { x: self.x - outer.x, y: self.y - outer.y, width: self.width, height: self.height })
    }
}

/// Rounds `value` up to a multiple of `align` (> 0), or `None` on overflow.
pub fn align_up(value: u32, align: u32) -> Option<u32> {
    assert!(align > 0, "alignment must be positive");
    let rem = value % align;
    if rem == 0 { Some(value) } else { value.checked_add(align - rem) }
}

/// Rounds `value` down to a multiple of `align` (> 0).
pub fn align_down(value: u32, align: u32) -> u32 {
    assert!(align > 0, "alignment must be positive");
    value - value % align
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Rng;

    fn r(x: u32, y: u32, w: u32, h: u32) -> Rect {
        Rect::new(x, y, w, h).unwrap()
    }

    #[test]
    fn construction_rejects_overflow() {
        assert!(Rect::new(u32::MAX, 0, 1, 1).is_none());
        assert!(Rect::new(0, u32::MAX - 4, 1, 5).is_none());
        assert!(Rect::new(u32::MAX - 1, 0, 1, 1).is_some());
    }

    #[test]
    fn edges_and_area() {
        let a = r(3, 4, 10, 20);
        assert_eq!((a.right(), a.bottom(), a.area()), (13, 24, 200));
        assert!(a.contains_point(3, 4) && a.contains_point(12, 23));
        assert!(!a.contains_point(13, 4) && !a.contains_point(3, 24));
    }

    #[test]
    fn intersect_cases() {
        let a = r(0, 0, 10, 10);
        assert_eq!(a.intersect(r(5, 5, 10, 10)), Some(r(5, 5, 5, 5)));
        assert_eq!(a.intersect(r(10, 0, 5, 5)), None, "touching edges do not overlap");
        assert_eq!(a.intersect(r(2, 2, 3, 3)), Some(r(2, 2, 3, 3)));
    }

    #[test]
    fn expand_clamped_cases() {
        let bounds = r(0, 0, 100, 50);
        assert_eq!(r(10, 10, 20, 20).expand_clamped(5, bounds), Some(r(5, 5, 30, 30)));
        assert_eq!(r(0, 0, 20, 20).expand_clamped(8, bounds), Some(r(0, 0, 28, 28)));
        assert_eq!(r(90, 40, 10, 10).expand_clamped(8, bounds), Some(r(82, 32, 18, 18)));
        assert_eq!(r(200, 200, 1, 1).expand_clamped(1, bounds), None);
        let edge = Rect::new(u32::MAX - 2, 0, 2, 1).unwrap();
        let full = Rect::new(0, 0, u32::MAX, 10).unwrap();
        assert_eq!(edge.expand_clamped(10, full).unwrap().right(), u32::MAX);
    }

    #[test]
    fn scaled_and_relative() {
        assert_eq!(r(1, 2, 3, 4).scaled(4), Some(r(4, 8, 12, 16)));
        assert!(r(1 << 30, 0, 1, 1).scaled(8).is_none());
        let outer = r(10, 10, 50, 50);
        assert_eq!(r(15, 20, 5, 5).relative_to(outer), Some(r(5, 10, 5, 5)));
        assert_eq!(r(5, 20, 10, 5).relative_to(outer), None);
    }

    #[test]
    fn alignment() {
        assert_eq!(align_up(0, 8), Some(0));
        assert_eq!(align_up(9, 8), Some(16));
        assert_eq!(align_up(16, 8), Some(16));
        assert_eq!(align_up(u32::MAX, 8), None);
        assert_eq!(align_down(15, 4), 12);
    }

    fn random_rect(rng: &mut Rng, span: u32) -> Rect {
        let x = rng.below(u64::from(span)) as u32;
        let y = rng.below(u64::from(span)) as u32;
        let w = rng.below(u64::from(span)) as u32;
        let h = rng.below(u64::from(span)) as u32;
        r(x, y, w, h)
    }

    /// Property: intersection agrees with a brute-force point test and is
    /// symmetric; expansion always stays inside the bounds and contains the
    /// part of the original that lies inside the bounds.
    #[test]
    fn property_intersect_and_expand() {
        let mut rng = Rng::seed_from_u64(0x5ca1_ef0e);
        for _ in 0..2_000 {
            let a = random_rect(&mut rng, 24);
            let b = random_rect(&mut rng, 24);
            let i = a.intersect(b);
            assert_eq!(i, b.intersect(a));
            for py in 0..48 {
                for px in 0..48 {
                    let both = a.contains_point(px, py) && b.contains_point(px, py);
                    assert_eq!(both, i.is_some_and(|i| i.contains_point(px, py)));
                }
            }
            let margin = rng.below(10) as u32;
            if let Some(e) = a.expand_clamped(margin, b) {
                assert!(b.contains(e));
                if let Some(inside) = a.intersect(b) {
                    assert!(e.contains(inside));
                }
            }
        }
    }
}
