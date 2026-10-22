import CQPDF
import CoreGraphics
import Foundation

extension QPDFService {
    /// Selects pages in the source object graph, including repeated indexes for duplication.
    /// qpdf's page-selection job also carries catalog state and adjusts page labels/forms.
    static func selectingPages(_ data: Data, pageIndices: [Int]) -> Data? {
        selectingPages(data, pageIndices: pageIndices, insertion: nil)
    }

    static func insertingPage(from sourceData: Data, pageIndex: Int, into data: Data, at index: Int) -> Data? {
        guard let pageCount = withQPDF(data, description: "insert-page-count", { Int(qpdf_get_num_pages($0)) }),
              index >= 0, index <= pageCount,
              let sourcePageCount = withQPDF(sourceData, description: "insert-page-source", { Int(qpdf_get_num_pages($0)) }),
              pageIndex >= 0, pageIndex < sourcePageCount else { return nil }
        return selectingPages(data, pageIndices: Array(0..<pageCount),
                              insertion: (sourceData, pageIndex, index))
    }

    private static func selectingPages(_ data: Data, pageIndices: [Int],
                                       insertion: (data: Data, pageIndex: Int, index: Int)?) -> Data? {
        guard !pageIndices.isEmpty,
              let pageCount = withQPDF(data, description: "select-pages", { qpdf -> Int? in
                  guard !hasErrors(qpdf_check_pdf(qpdf)) else { return nil }
                  return Int(qpdf_get_num_pages(qpdf))
              }),
              pageIndices.allSatisfy({ $0 >= 0 && $0 < pageCount }) else { return nil }

        var template = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-select-pages-XXXXXX").path.utf8CString
        guard let path = template.withUnsafeMutableBufferPointer({ buffer -> String? in
            guard let base = buffer.baseAddress, let created = mkdtemp(base) else { return nil }
            return String(cString: created)
        }) else { return nil }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.pdf")
        let output = directory.appendingPathComponent("output.pdf")
        let source = directory.appendingPathComponent("source.pdf")
        func selection(_ indexes: [Int]) -> [String: String] {
            ["file": ".", "range": indexes.map { String($0 + 1) }.joined(separator: ",")]
        }
        var pages = [selection(pageIndices)]
        if let insertion {
            guard FileManager.default.createFile(atPath: source.path, contents: insertion.data,
                                                attributes: [.posixPermissions: 0o600]) else { return nil }
            pages = []
            if insertion.index > 0 { pages.append(selection(Array(pageIndices[..<insertion.index]))) }
            pages.append(["file": source.path, "range": String(insertion.pageIndex + 1)])
            if insertion.index < pageIndices.count { pages.append(selection(Array(pageIndices[insertion.index...]))) }
        }
        let configuration: [String: Any] = [
            "inputFile": input.path, "outputFile": output.path,
            "pages": pages
        ]
        guard FileManager.default.createFile(atPath: input.path, contents: data, attributes: [.posixPermissions: 0o600]),
              FileManager.default.createFile(atPath: output.path, contents: Data(), attributes: [.posixPermissions: 0o600]),
              let json = try? JSONSerialization.data(withJSONObject: configuration),
              let config = String(data: json, encoding: .utf8) else { return nil }
        var ownedJob = qpdfjob_init()
        var ownedLogger = qpdflogger_create()
        defer { qpdfjob_cleanup(&ownedJob); qpdflogger_cleanup(&ownedLogger) }
        guard let job = ownedJob, let logger = ownedLogger else { return nil }
        qpdflogger_set_info(logger, qpdf_log_dest_discard, nil, nil)
        qpdflogger_set_warn(logger, qpdf_log_dest_discard, nil, nil)
        qpdflogger_set_error(logger, qpdf_log_dest_discard, nil, nil)
        qpdfjob_set_logger(job, logger)
        guard config.withCString({ qpdfjob_initialize_from_json(job, $0) }) == 0 else { return nil }
        let exitCode = qpdfjob_run(job)
        guard exitCode == 0 || exitCode == 3,
              let result = try? Data(contentsOf: output),
              isStructurallySound(result),
              withQPDF(result, description: "selected-pages-count", { Int(qpdf_get_num_pages($0)) }) == pageIndices.count + (insertion == nil ? 0 : 1) else {
            return nil
        }
        return result
    }

    /// Applies live PDFKit page rotations to an authoritative structural byte lane without
    /// reserializing that lane through PDFKit. This preserves catalog-level structures such as
    /// attachments and `/PageLabels` while still carrying unsaved reader rotations into OCR.
    static func settingPageRotations(_ data: Data, rotationsByPageIndex: [Int: Int]) -> Data? {
        guard !rotationsByPageIndex.isEmpty else { return data }
        let normalized = rotationsByPageIndex.mapValues { (($0 % 360) + 360) % 360 }
        guard normalized.allSatisfy({ pageIndex, rotation in
            pageIndex >= 0 && [0, 90, 180, 270].contains(rotation)
        }) else { return nil }

        return withQPDF(data, description: "set-page-rotations") { qpdf in
            let pageCount = qpdf_get_num_pages(qpdf)
            guard hasErrors(qpdf_check_pdf(qpdf)) == false,
                  normalized.keys.allSatisfy({ $0 < pageCount }) else { return nil }

            for (pageIndex, rotation) in normalized {
                let page = qpdf_get_page_n(qpdf, numericCast(pageIndex))
                replaceKey(
                    qpdf,
                    in: page,
                    key: "/Rotate",
                    value: qpdf_oh_new_integer(qpdf, numericCast(rotation))
                )
            }
            return write(qpdf) { _ in }
        }
    }

    /// Sets one page's non-destructive PDF `/CropBox` while preserving the rest of the
    /// object graph. PDF page boxes are `[lowerLeftX lowerLeftY upperRightX upperRightY]`,
    /// not CGRect's origin/size representation, so write the standardized extrema.
    static func settingCropBox(_ data: Data, pageIndex: Int, rect: CGRect) -> Data? {
        settingCropBoxes(data, pageCropBoxes: [pageIndex: rect])
    }

    /// Batch form used by the workspace so "all pages" opens and serializes each byte lane
    /// once instead of once per page.
    static func settingCropBoxes(_ data: Data, pageCropBoxes: [Int: CGRect]) -> Data? {
        guard !pageCropBoxes.isEmpty else { return data }
        let standardized = pageCropBoxes.mapValues(\.standardized)
        guard standardized.allSatisfy({ pageIndex, box in
            pageIndex >= 0 &&
                box.minX.isFinite && box.minY.isFinite &&
                box.maxX.isFinite && box.maxY.isFinite &&
                box.width > 0 && box.height > 0
        }) else { return nil }

        return withQPDF(data, description: "set-crop-box") { qpdf in
            let pageCount = qpdf_get_num_pages(qpdf)
            guard hasErrors(qpdf_check_pdf(qpdf)) == false,
                  standardized.keys.allSatisfy({ $0 < pageCount }) else { return nil }

            for (pageIndex, box) in standardized {
                let cropBox = qpdf_oh_new_array(qpdf)
                for coordinate in [box.minX, box.minY, box.maxX, box.maxY] {
                    qpdf_oh_append_item(
                        qpdf,
                        cropBox,
                        qpdf_oh_new_real_from_double(qpdf, Double(coordinate), 6)
                    )
                }
                let page = qpdf_get_page_n(qpdf, numericCast(pageIndex))
                replaceKey(qpdf, in: page, key: "/CropBox", value: cropBox)
            }
            return write(qpdf) { _ in }
        }
    }
}
