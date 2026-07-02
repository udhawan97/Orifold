import AppKit
import CoreGraphics
import Foundation
import PDFKit

@_silgen_name("FPDF_LoadPage")
private func FPDFCompression_LoadPage(_ document: OpaquePointer?, _ pageIndex: Int32) -> OpaquePointer?

@_silgen_name("FPDF_ClosePage")
private func FPDFCompression_ClosePage(_ page: OpaquePointer?)

@_silgen_name("FPDFPage_CountObjects")
private func FPDFCompression_PageCountObjects(_ page: OpaquePointer?) -> Int32

@_silgen_name("FPDFPage_GetObject")
private func FPDFCompression_PageGetObject(_ page: OpaquePointer?, _ index: Int32) -> OpaquePointer?

@_silgen_name("FPDFPageObj_GetType")
private func FPDFCompression_PageObjectGetType(_ pageObject: OpaquePointer?) -> Int32

@_silgen_name("FPDFPageObj_GetBounds")
private func FPDFCompression_PageObjectGetBounds(
    _ pageObject: OpaquePointer?,
    _ left: UnsafeMutablePointer<Float>?,
    _ bottom: UnsafeMutablePointer<Float>?,
    _ right: UnsafeMutablePointer<Float>?,
    _ top: UnsafeMutablePointer<Float>?
) -> Int32

@_silgen_name("FPDFImageObj_GetBitmap")
private func FPDFCompression_ImageObjectGetBitmap(_ imageObject: OpaquePointer?) -> OpaquePointer?

@_silgen_name("FPDFImageObj_GetImagePixelSize")
private func FPDFCompression_ImageObjectGetPixelSize(
    _ imageObject: OpaquePointer?,
    _ width: UnsafeMutablePointer<UInt32>?,
    _ height: UnsafeMutablePointer<UInt32>?
) -> Int32

@_silgen_name("FPDFImageObj_SetBitmap")
private func FPDFCompression_ImageObjectSetBitmap(
    _ pages: UnsafeMutablePointer<OpaquePointer?>?,
    _ count: Int32,
    _ imageObject: OpaquePointer?,
    _ bitmap: OpaquePointer?
) -> Int32

@_silgen_name("FPDFImageObj_LoadJpegFileInline")
private func FPDFCompression_ImageObjectLoadJpegFileInline(
    _ pages: UnsafeMutablePointer<OpaquePointer?>?,
    _ count: Int32,
    _ imageObject: OpaquePointer?,
    _ fileAccess: UnsafeMutablePointer<FPDFCompressionFileAccess>?
) -> Int32

@_silgen_name("FPDFPage_GenerateContent")
private func FPDFCompression_PageGenerateContent(_ page: OpaquePointer?) -> Int32

@_silgen_name("FPDFBitmap_Create")
private func FPDFCompression_BitmapCreate(_ width: Int32, _ height: Int32, _ alpha: Int32) -> OpaquePointer?

@_silgen_name("FPDFBitmap_GetBuffer")
private func FPDFCompression_BitmapGetBuffer(_ bitmap: OpaquePointer?) -> UnsafeMutableRawPointer?

@_silgen_name("FPDFBitmap_GetWidth")
private func FPDFCompression_BitmapGetWidth(_ bitmap: OpaquePointer?) -> Int32

@_silgen_name("FPDFBitmap_GetHeight")
private func FPDFCompression_BitmapGetHeight(_ bitmap: OpaquePointer?) -> Int32

@_silgen_name("FPDFBitmap_GetStride")
private func FPDFCompression_BitmapGetStride(_ bitmap: OpaquePointer?) -> Int32

@_silgen_name("FPDFBitmap_Destroy")
private func FPDFCompression_BitmapDestroy(_ bitmap: OpaquePointer?)

@_silgen_name("FPDF_SaveAsCopy")
private func FPDFCompression_SaveAsCopy(
    _ document: OpaquePointer?,
    _ fileWrite: UnsafeMutablePointer<FPDFCompressionFileWrite>?,
    _ flags: UInt32
) -> Int32

private struct FPDFCompressionFileWrite {
    var version: Int32
    var writeBlock: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, CUnsignedLong) -> Int32)?
}

private struct FPDFCompressionFileAccess {
    var fileLength: CUnsignedLong
    var getBlock: (@convention(c) (UnsafeMutableRawPointer?, CUnsignedLong, UnsafeMutablePointer<UInt8>?, CUnsignedLong) -> Int32)?
    var parameter: UnsafeMutableRawPointer?
}

private var fpdfCompressionSaveData = Data()
private var fpdfCompressionJPEGData = Data()

enum PDFCompressionService {
    typealias ProgressHandler = @Sendable (Double) -> Void
    typealias CancellationHandler = @Sendable () -> Bool
    private static let maxSourceImagePixels: Int64 = 80_000_000
    private static let maxTargetImagePixels: Int64 = 40_000_000

    static func reduceFileSize(
        of pdfData: Data,
        preset: PDFCompressionPreset,
        processingEngine: PDFProcessingEngine = PDFiumProcessingEngine(),
        progress: ProgressHandler? = nil,
        isCancelled: CancellationHandler? = nil
    ) throws -> PDFCompressionResult {
        try checkCancellation(isCancelled)
        progress?(0.1)
        guard let document = PDFDocument(data: pdfData), document.pageCount > 0 else {
            throw PDFCompressionError.invalidPDF
        }
        let originalPageText = pageStrings(in: document)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdFold-compress-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try autoreleasepool {
            try checkCancellation(isCancelled)
            let writeOptions: [PDFDocumentWriteOption: Any] = [
                .saveImagesAsJPEGOption: true,
                .optimizeImagesForScreenOption: true
            ]
            guard document.write(to: tempURL, withOptions: writeOptions) else {
                throw PDFCompressionError.writeFailed
            }
        }

        try checkCancellation(isCancelled)
        progress?(0.45)
        var compressedData = try Data(contentsOf: tempURL)
        if compressedData.count >= pdfData.count {
            compressedData = try downsampleImagesWithPDFium(
                in: pdfData,
                preset: preset,
                progress: { progress?(0.45 + ($0 * 0.45)) },
                isCancelled: isCancelled
            )
        }
        progress?(0.9)
        guard compressedData.count < pdfData.count else { throw PDFCompressionError.grewLarger }

        try validate(compressedData, expectedPageText: originalPageText, processingEngine: processingEngine)
        try checkCancellation(isCancelled)
        progress?(1.0)
        return PDFCompressionResult(
            data: compressedData,
            originalByteCount: pdfData.count,
            compressedByteCount: compressedData.count
        )
    }

    private static func validate(
        _ data: Data,
        expectedPageText: [String],
        processingEngine: PDFProcessingEngine
    ) throws {
        do {
            let validation = try processingEngine.validatePDF(data: data, password: nil)
            guard validation.pageCount == expectedPageText.count else {
                throw PDFCompressionError.validationFailed
            }
        } catch let compressionError as PDFCompressionError {
            throw compressionError
        } catch {
            throw PDFCompressionError.validationFailed
        }

        guard let compressedDocument = PDFDocument(data: data),
              compressedDocument.pageCount == expectedPageText.count else {
            throw PDFCompressionError.validationFailed
        }
        for pageIndex in 0..<compressedDocument.pageCount {
            guard (compressedDocument.page(at: pageIndex)?.string ?? "") == expectedPageText[pageIndex] else {
                throw PDFCompressionError.textChanged
            }
        }
    }

    private static func pageStrings(in document: PDFDocument) -> [String] {
        (0..<document.pageCount).map { pageIndex in
            document.page(at: pageIndex)?.string ?? ""
        }
    }

    private static func downsampleImagesWithPDFium(
        in pdfData: Data,
        preset: PDFCompressionPreset,
        progress: ProgressHandler?,
        isCancelled: CancellationHandler?
    ) throws -> Data {
        guard !pdfData.isEmpty, pdfData.count <= Int(Int32.max) else { throw PDFCompressionError.invalidPDF }
        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }

        return try pdfData.withUnsafeBytes { rawBuffer -> Data in
            guard let baseAddress = rawBuffer.baseAddress else { throw PDFCompressionError.invalidPDF }
            guard let document = FPDF_LoadMemDocument(baseAddress, Int32(pdfData.count), nil) else {
                throw PDFCompressionError.invalidPDF
            }
            defer { FPDF_CloseDocument(document) }

            let pageCount = Int(FPDF_GetPageCount(document))
            guard pageCount > 0 else { throw PDFCompressionError.invalidPDF }

            var changedAnyPage = false
            for pageIndex in 0..<pageCount {
                try autoreleasepool {
                    try checkCancellation(isCancelled)
                    guard let page = FPDFCompression_LoadPage(document, Int32(pageIndex)) else {
                        throw PDFCompressionError.pdfiumRewriteFailed
                    }
                    defer { FPDFCompression_ClosePage(page) }
                    let pageChanged = try downsampleImages(on: page, preset: preset)
                    if pageChanged {
                        guard FPDFCompression_PageGenerateContent(page) != 0 else {
                            throw PDFCompressionError.pdfiumRewriteFailed
                        }
                        changedAnyPage = true
                    }
                    progress?(Double(pageIndex + 1) / Double(pageCount))
                }
            }
            guard changedAnyPage else { throw PDFCompressionError.grewLarger }

            fpdfCompressionSaveData = Data()
            var fileWrite = FPDFCompressionFileWrite(version: 1, writeBlock: { _, data, size in
                guard let data, size > 0 else { return 0 }
                fpdfCompressionSaveData.append(data.assumingMemoryBound(to: UInt8.self), count: Int(size))
                return 1
            })
            defer { fpdfCompressionSaveData.removeAll(keepingCapacity: false) }
            guard FPDFCompression_SaveAsCopy(document, &fileWrite, UInt32(1 << 1)) != 0,
                  !fpdfCompressionSaveData.isEmpty else {
                throw PDFCompressionError.pdfiumRewriteFailed
            }
            return fpdfCompressionSaveData
        }
    }

    private static func downsampleImages(on page: OpaquePointer?, preset: PDFCompressionPreset) throws -> Bool {
        let objectCount = Int(FPDFCompression_PageCountObjects(page))
        guard objectCount > 0 else { return false }
        var changed = false
        for objectIndex in 0..<objectCount {
            guard let object = FPDFCompression_PageGetObject(page, Int32(objectIndex)),
                  FPDFCompression_PageObjectGetType(object) == 3 else {
                continue
            }
            guard let targetSize = targetPixelSize(for: object, preset: preset),
                  let sourceBitmap = FPDFCompression_ImageObjectGetBitmap(object) else {
                continue
            }
            defer { FPDFCompression_BitmapDestroy(sourceBitmap) }
            guard let replacement = makeDownsampledJPEG(
                from: sourceBitmap,
                targetSize: targetSize,
                quality: preset.jpegQuality
            ) else {
                throw PDFCompressionError.pdfiumRewriteFailed
            }
            fpdfCompressionJPEGData = replacement
            defer { fpdfCompressionJPEGData.removeAll(keepingCapacity: false) }
            var fileAccess = FPDFCompressionFileAccess(
                fileLength: CUnsignedLong(replacement.count),
                getBlock: { _, position, buffer, size in
                    guard let buffer else { return 0 }
                    let start = Int(position)
                    let byteCount = Int(size)
                    guard start >= 0,
                          byteCount >= 0,
                          start <= fpdfCompressionJPEGData.count,
                          start + byteCount <= fpdfCompressionJPEGData.count else {
                        return 0
                    }
                    fpdfCompressionJPEGData.withUnsafeBytes { rawBuffer in
                        guard let baseAddress = rawBuffer.baseAddress else { return }
                        buffer.update(from: baseAddress.advanced(by: start).assumingMemoryBound(to: UInt8.self), count: byteCount)
                    }
                    return 1
                },
                parameter: nil
            )
            var pagePointer = page
            guard FPDFCompression_ImageObjectLoadJpegFileInline(&pagePointer, 1, object, &fileAccess) != 0 else {
                throw PDFCompressionError.pdfiumRewriteFailed
            }
            changed = true
        }
        return changed
    }

    private static func targetPixelSize(for imageObject: OpaquePointer?, preset: PDFCompressionPreset) -> CGSize? {
        var pixelWidth: UInt32 = 0
        var pixelHeight: UInt32 = 0
        guard FPDFCompression_ImageObjectGetPixelSize(imageObject, &pixelWidth, &pixelHeight) != 0,
              pixelWidth > 0,
              pixelHeight > 0 else {
            return nil
        }
        let sourcePixels = Int64(pixelWidth) * Int64(pixelHeight)
        guard sourcePixels <= maxSourceImagePixels else { return nil }
        var left: Float = 0
        var bottom: Float = 0
        var right: Float = 0
        var top: Float = 0
        guard FPDFCompression_PageObjectGetBounds(imageObject, &left, &bottom, &right, &top) != 0 else {
            return nil
        }
        let displayWidth = max(1, CGFloat(right - left))
        let displayHeight = max(1, CGFloat(top - bottom))
        let targetWidth = max(1, Int((displayWidth / 72.0 * CGFloat(preset.dpiCap)).rounded()))
        let targetHeight = max(1, Int((displayHeight / 72.0 * CGFloat(preset.dpiCap)).rounded()))
        guard Int64(targetWidth) * Int64(targetHeight) <= maxTargetImagePixels else { return nil }
        guard Int(pixelWidth) > targetWidth || Int(pixelHeight) > targetHeight else { return nil }
        let scale = min(CGFloat(targetWidth) / CGFloat(pixelWidth), CGFloat(targetHeight) / CGFloat(pixelHeight))
        let scaledWidth = max(1, CGFloat(pixelWidth) * scale).rounded(.down)
        let scaledHeight = max(1, CGFloat(pixelHeight) * scale).rounded(.down)
        guard Int64(scaledWidth) * Int64(scaledHeight) <= maxTargetImagePixels else { return nil }
        return CGSize(width: scaledWidth, height: scaledHeight)
    }

    private static func makeDownsampledJPEG(from sourceBitmap: OpaquePointer?, targetSize: CGSize, quality: Double) -> Data? {
        let sourceWidth = Int(FPDFCompression_BitmapGetWidth(sourceBitmap))
        let sourceHeight = Int(FPDFCompression_BitmapGetHeight(sourceBitmap))
        let sourceStride = Int(FPDFCompression_BitmapGetStride(sourceBitmap))
        guard sourceWidth > 0,
              sourceHeight > 0,
              sourceStride >= sourceWidth * 4,
              let sourceBuffer = FPDFCompression_BitmapGetBuffer(sourceBitmap) else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let sourceContext = CGContext(
            data: sourceBuffer,
            width: sourceWidth,
            height: sourceHeight,
            bitsPerComponent: 8,
            bytesPerRow: sourceStride,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ),
              let sourceImage = sourceContext.makeImage() else {
            return nil
        }

        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)
        guard targetWidth > 0,
              targetHeight > 0,
              let targetContext = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        targetContext.interpolationQuality = .medium
        targetContext.draw(sourceImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let targetImage = targetContext.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: targetImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: min(max(quality, 0.1), 1.0)])
    }

    private static func checkCancellation(_ isCancelled: CancellationHandler?) throws {
        if isCancelled?() == true || Task.isCancelled {
            throw PDFCompressionError.cancelled
        }
    }
}
