//
// PanelReadingOrder.swift
//
// Detector-agnostic reading-order layer. Takes unordered normalized panel rects
// and returns them in manga/comic reading order via a recursive X-Y cut. This is
// the one piece shared by every detection provider, so it contains NO detector or
// networking specifics.
//

import CoreGraphics
import Foundation

/// Recursive X-Y cut panel ordering.
///
/// At each level: look for a clean horizontal gutter first (split into rows, top
/// read before bottom); failing that, a clean vertical gutter (split into columns,
/// right-before-left for RTL, left-before-right for LTR). Recurse until each group
/// holds a single panel. Pages with no clean cut (borderless / heavy overlap) fall
/// back to a deterministic banded sort, keeping the order stable even when the
/// layout is genuinely ambiguous.
nonisolated enum PanelReadingOrder {
    /// Minimum normalized gap that counts as a real cut. Keeps thin inter-panel art
    /// lines from triggering spurious splits.
    static let defaultGutter: Double = 0.015
    /// Normalized slack so a panel whose detection box bleeds slightly past a gutter does not
    /// block an otherwise-clean cut: each edge is pulled in by this much before the gap is
    /// tested, so a small overhang is forgiven instead of defeating the cut and dropping the
    /// page to the less-accurate banded fallback.
    static let defaultOverlapTolerance: Double = 0.02

    static func ordered(
        _ rects: [PanelRect],
        direction: ReadingDirection,
        gutter: Double = defaultGutter,
        overlapTolerance: Double = defaultOverlapTolerance
    ) -> [PanelRect] {
        guard rects.count > 1 else { return rects }

        // Horizontal cut first: rows, top before bottom.
        if let (top, bottom) = cut(
            rects, lo: { $0.y }, hi: { $0.y + $0.height },
            gutter: gutter, tolerance: overlapTolerance
        ) {
            return ordered(top, direction: direction, gutter: gutter, overlapTolerance: overlapTolerance)
                + ordered(bottom, direction: direction, gutter: gutter, overlapTolerance: overlapTolerance)
        }

        // Vertical cut: columns. RTL reads right group first.
        if let (left, right) = cut(
            rects, lo: { $0.x }, hi: { $0.x + $0.width },
            gutter: gutter, tolerance: overlapTolerance
        ) {
            let first = direction == .rtl ? right : left
            let second = direction == .rtl ? left : right
            return ordered(first, direction: direction, gutter: gutter, overlapTolerance: overlapTolerance)
                + ordered(second, direction: direction, gutter: gutter, overlapTolerance: overlapTolerance)
        }

        return fallbackSorted(rects, direction: direction, rowEpsilon: max(gutter, overlapTolerance))
    }

    // MARK: - Private

    /// Find the single largest clean gutter along one axis and split there.
    /// Returns `(lowerSide, upperSide)` ordered by ascending coordinate, or `nil` if
    /// no gap of at least `gutter` separates the panels cleanly. Edges are shrunk by
    /// `tolerance` so minor bleed across the gutter is forgiven.
    private static func cut(
        _ rects: [PanelRect],
        lo: (PanelRect) -> Double,
        hi: (PanelRect) -> Double,
        gutter: Double,
        tolerance: Double
    ) -> ([PanelRect], [PanelRect])? {
        guard rects.count > 1 else { return nil }
        let sorted = rects.sorted { lo($0) < lo($1) }

        var maxCoreHi = -Double.infinity   // greatest core-bottom seen in the lower group
        var bestGap = gutter               // require strictly clean separation ≥ gutter
        var splitIndex: Int?

        for i in sorted.indices {
            if i > 0 {
                let coreLo = lo(sorted[i]) + tolerance
                let gap = coreLo - maxCoreHi
                if gap >= bestGap {
                    bestGap = gap
                    splitIndex = i
                }
            }
            maxCoreHi = max(maxCoreHi, hi(sorted[i]) - tolerance)
        }

        guard let idx = splitIndex else { return nil }
        return (Array(sorted[0..<idx]), Array(sorted[idx...]))
    }

    /// Deterministic order for pages with no clean cut: band by vertical center, then
    /// order within a band by horizontal center (reversed for RTL).
    private static func fallbackSorted(
        _ rects: [PanelRect],
        direction: ReadingDirection,
        rowEpsilon: Double
    ) -> [PanelRect] {
        rects.sorted { a, b in
            let aMidY = a.y + a.height / 2
            let bMidY = b.y + b.height / 2
            if abs(aMidY - bMidY) > rowEpsilon { return aMidY < bMidY }
            let aMidX = a.x + a.width / 2
            let bMidX = b.x + b.width / 2
            return direction == .rtl ? aMidX > bMidX : aMidX < bMidX
        }
    }
}
