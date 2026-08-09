import CQPDF
import CoreGraphics
import Foundation

extension QPDFService {
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
