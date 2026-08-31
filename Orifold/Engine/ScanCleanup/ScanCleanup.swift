import CoreImage
import CoreGraphics
import Foundation
import Vision

struct ScanCleanupOptions: Equatable, Hashable, Sendable {
    var deskew: Bool = true
    var binarize: Bool = true
    var despeckle: Bool = true
}

struct ScanCleanupPreviewSource: Sendable {
    let pdfData: Data
    let pageIndex: Int
}

enum ScanCleanupScope: String, CaseIterable, Identifiable, Sendable {
    case currentPage
    case document

    var id: String { rawValue }
}

enum ScanCleanup {
    /// Vision returns normalized corners in lower-left image coordinates. The stable ordering is
    /// top-left, top-right, bottom-right, bottom-left so callers do not depend on Vision types.
    static func detectDocumentQuad(_ image: CGImage) -> [CGPoint]? {
        let request = VNDetectDocumentSegmentationRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        } catch {
            return nil
        }
        guard let rectangle = request.results?.first else { return nil }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        func point(_ normalized: CGPoint) -> CGPoint {
            CGPoint(x: normalized.x * width, y: normalized.y * height)
        }
        return [
            point(rectangle.topLeft),
            point(rectangle.topRight),
            point(rectangle.bottomRight),
            point(rectangle.bottomLeft),
        ]
    }

    static func deskewAndCrop(_ image: CGImage, to quad: [CGPoint]) -> CGImage {
        guard quad.count == 4 else { return image }

        // Perspective correction removes keystone distortion but intentionally preserves a
        // photograph's roll. Remove the page-edge angle first, re-detect in the rotated image,
        // then rectify the remaining quadrilateral.
        let topAngle = atan2(quad[1].y - quad[0].y, quad[1].x - quad[0].x)
        let bottomAngle = atan2(quad[2].y - quad[3].y, quad[2].x - quad[3].x)
        let roll = (topAngle + bottomAngle) / 2
        let shouldRotate = abs(roll) > 0.002
        let rolled = shouldRotate ? rotated(image, by: -roll) : image
        guard let detectedAfterRoll = detectDocumentQuad(rolled) else {
            // `quad` is expressed in the original image's coordinate space and cannot be reused
            // after rotation. Returning the straightened image is safer than cropping with stale
            // coordinates.
            return rolled
        }
        let correctedQuad = expanded(
            detectedAfterRoll,
            width: CGFloat(rolled.width),
            height: CGFloat(rolled.height)
        )
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return rolled }
        let input = CIImage(cgImage: rolled)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: correctedQuad[0]), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: correctedQuad[1]), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: correctedQuad[2]), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: correctedQuad[3]), forKey: "inputBottomLeft")
        guard let output = filter.outputImage else { return image }
        let extent = output.extent.integral
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0,
              let corrected = CIContext(options: [.cacheIntermediates: false])
                .createCGImage(output, from: extent) else { return image }
        return corrected
    }

    /// Vision's segmentation hugs the visible paper edge. A small outward allowance avoids
    /// clipping glyph antialiasing or a scanner's dark border at that edge.
    private static func expanded(_ quad: [CGPoint], width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard quad.count == 4 else { return quad }
        let center = CGPoint(
            x: quad.map(\.x).reduce(0, +) / 4,
            y: quad.map(\.y).reduce(0, +) / 4
        )
        return quad.map { point in
            CGPoint(
                x: min(width, max(0, center.x + (point.x - center.x) * 1.08)),
                y: min(height, max(0, center.y + (point.y - center.y) * 1.08))
            )
        }
    }

    private static func rotated(_ image: CGImage, by angle: CGFloat) -> CGImage {
        let input = CIImage(cgImage: image)
        let transform = CGAffineTransform(rotationAngle: angle)
        let output = input.transformed(by: transform)
        let extent = output.extent.integral
        guard let result = CIContext(options: [.cacheIntermediates: false])
            .createCGImage(output, from: extent) else { return image }
        return result
    }

    static func clean(_ image: CGImage, options: ScanCleanupOptions) -> CGImage {
        var output = image
        if options.deskew, let quad = detectDocumentQuad(output) {
            output = deskewAndCrop(output, to: quad)
        }
        if options.binarize {
            output = binarize(output)
        }
        if options.despeckle {
            output = despeckle(output)
        }
        return output
    }

    /// Converts the source into an opaque black/white image. Otsu's histogram threshold keeps
    /// the operation deterministic and avoids a hard-coded brightness cutoff that fails on
    /// lightly photographed paper.
    static func binarize(_ image: CGImage) -> CGImage {
        guard var raster = Raster(image: image) else { return image }
        let grayscale = raster.grayscale()
        let threshold = otsuThreshold(grayscale)
        for index in grayscale.indices {
            let value: UInt8 = grayscale[index] <= threshold ? 0 : 255
            let offset = index * 4
            raster.pixels[offset] = value
            raster.pixels[offset + 1] = value
            raster.pixels[offset + 2] = value
            raster.pixels[offset + 3] = 255
        }
        return raster.image() ?? image
    }

    /// Removes one-pixel black noise while retaining connected strokes. The operation is
    /// intentionally conservative: only a dark pixel with no dark neighbour is cleared.
    static func despeckle(_ image: CGImage) -> CGImage {
        guard var raster = Raster(image: image) else { return image }
        let grayscale = raster.grayscale()
        guard raster.width > 2, raster.height > 2 else { return image }

        for y in 1..<(raster.height - 1) {
            for x in 1..<(raster.width - 1) {
                let index = y * raster.width + x
                guard grayscale[index] < 128 else { continue }
                var connected = false
                for neighborY in (y - 1)...(y + 1) {
                    for neighborX in (x - 1)...(x + 1)
                    where neighborX != x || neighborY != y {
                        if grayscale[neighborY * raster.width + neighborX] < 128 {
                            connected = true
                            break
                        }
                    }
                    if connected { break }
                }
                if !connected {
                    let offset = index * 4
                    raster.pixels[offset] = 255
                    raster.pixels[offset + 1] = 255
                    raster.pixels[offset + 2] = 255
                    raster.pixels[offset + 3] = 255
                }
            }
        }
        return raster.image() ?? image
    }

    private static func otsuThreshold(_ values: [UInt8]) -> UInt8 {
        guard !values.isEmpty else { return 127 }
        var histogram = [Int](repeating: 0, count: 256)
        for value in values { histogram[Int(value)] += 1 }

        let total = values.count
        let weightedTotal = histogram.enumerated().reduce(0) { partial, entry in
            partial + entry.offset * entry.element
        }
        var backgroundWeight = 0
        var backgroundWeightedSum = 0
        var bestVariance = -Double.infinity
        var bestThreshold = 127

        for threshold in 0..<256 {
            backgroundWeight += histogram[threshold]
            guard backgroundWeight > 0 else { continue }
            let foregroundWeight = total - backgroundWeight
            guard foregroundWeight > 0 else { break }

            backgroundWeightedSum += threshold * histogram[threshold]
            let backgroundMean = Double(backgroundWeightedSum) / Double(backgroundWeight)
            let foregroundMean = Double(weightedTotal - backgroundWeightedSum) / Double(foregroundWeight)
            let difference = backgroundMean - foregroundMean
            let variance = Double(backgroundWeight) * Double(foregroundWeight) * difference * difference
            if variance > bestVariance {
                bestVariance = variance
                bestThreshold = threshold
            }
        }
        return UInt8(bestThreshold)
    }
}

private struct Raster {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init?(image: CGImage) {
        width = image.width
        height = image.height
        guard width > 0, height > 0 else { return nil }
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func grayscale() -> [UInt8] {
        stride(from: 0, to: pixels.count, by: 4).map { offset in
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            return UInt8((77 * red + 150 * green + 29 * blue) >> 8)
        }
    }

    mutating func image() -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        return context.makeImage()
    }
}
