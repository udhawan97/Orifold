import CoreGraphics
import Foundation

/// Pure visual page comparison. Both renders are resampled onto one small luminance grid and
/// compared tile by tile, so anti-aliasing and resolution differences wash out while real
/// content changes survive the threshold. Deterministic — unit-tested with synthetic images.
enum PDFVisualDiff {
    struct Result: Equatable, Sendable {
        /// Changed regions in normalized page coordinates (origin bottom-left, 0…1 on both
        /// axes), merged from vertically-stacked identical tile runs.
        var changedRects: [CGRect]
        /// Fraction of grid tiles whose luminance moved past the threshold (0…1).
        var changedFraction: Double

        var hasChanges: Bool { !changedRects.isEmpty }

        static let unchanged = Result(changedRects: [], changedFraction: 0)
    }

    /// Compares two page renders. `grid` is the comparison resolution per axis; `threshold`
    /// is the per-tile mean-luminance delta (0…1) below which a tile counts as unchanged —
    /// high enough to ignore anti-aliasing noise, low enough that a pale watermark registers.
    static func diff(_ lhs: CGImage, _ rhs: CGImage, grid: Int = 48, threshold: Double = 0.08) -> Result {
        guard grid > 0,
              let a = lumaGrid(lhs, grid: grid),
              let b = lumaGrid(rhs, grid: grid),
              a.count == grid * grid, b.count == grid * grid else {
            return .unchanged
        }
        let limit = Int((threshold * 255).rounded())
        var changed = [Bool](repeating: false, count: grid * grid)
        var changedCount = 0
        for index in 0..<(grid * grid) where abs(Int(a[index]) - Int(b[index])) > limit {
            changed[index] = true
            changedCount += 1
        }
        return Result(
            changedRects: mergedRects(from: changed, grid: grid),
            changedFraction: Double(changedCount) / Double(grid * grid)
        )
    }

    // MARK: - Internals

    /// Resamples an image to a `grid`×`grid` 8-bit grayscale buffer. Row 0 of the returned
    /// buffer is the TOP scanline of the image (CGContext memory order).
    private static func lumaGrid(_ image: CGImage, grid: Int) -> [UInt8]? {
        guard let context = CGContext(
            data: nil,
            width: grid,
            height: grid,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: grid, height: grid))
        context.draw(image, in: CGRect(x: 0, y: 0, width: grid, height: grid))
        guard let data = context.data else { return nil }
        let stride = context.bytesPerRow
        let pointer = data.bindMemory(to: UInt8.self, capacity: stride * grid)
        var out = [UInt8](repeating: 0, count: grid * grid)
        for row in 0..<grid {
            for column in 0..<grid {
                out[row * grid + column] = pointer[row * stride + column]
            }
        }
        return out
    }

    /// Merges the changed-tile mask into rects: horizontal runs per row, then runs with an
    /// identical x-range on consecutive rows merge vertically. Output is in normalized
    /// bottom-left-origin coordinates and deterministically ordered.
    private static func mergedRects(from changed: [Bool], grid: Int) -> [CGRect] {
        struct OpenRun {
            var xStart: Int
            var xEnd: Int
            var topRow: Int
            var bottomRow: Int
        }
        var open: [Int: OpenRun] = [:]   // keyed by xStart * grid + xEnd
        var closed: [OpenRun] = []

        for row in 0..<grid {
            var rowKeys = Set<Int>()
            var column = 0
            while column < grid {
                if changed[row * grid + column] {
                    let start = column
                    while column < grid, changed[row * grid + column] { column += 1 }
                    let key = start * grid + (column - 1)
                    rowKeys.insert(key)
                    if var run = open[key] {
                        run.bottomRow = row
                        open[key] = run
                    } else {
                        open[key] = OpenRun(xStart: start, xEnd: column - 1, topRow: row, bottomRow: row)
                    }
                } else {
                    column += 1
                }
            }
            for (key, run) in open where !rowKeys.contains(key) {
                closed.append(run)
                open[key] = nil
            }
        }
        closed.append(contentsOf: open.values)

        let unit = 1.0 / CGFloat(grid)
        return closed
            .map { run in
                CGRect(
                    x: CGFloat(run.xStart) * unit,
                    y: CGFloat(grid - 1 - run.bottomRow) * unit,
                    width: CGFloat(run.xEnd - run.xStart + 1) * unit,
                    height: CGFloat(run.bottomRow - run.topRow + 1) * unit
                )
            }
            .sorted { lhs, rhs in
                if lhs.minY != rhs.minY { return lhs.minY < rhs.minY }
                return lhs.minX < rhs.minX
            }
    }
}
