import Foundation
import PDFKit

/// Converts a Comic Book ZIP into a fresh PDF without extracting archive contents to disk.
/// Page order follows the archive paths using numeric-aware comparison (`2` before `10`).
enum CBZImportService {
    static let maxPageCount = 1_000

    private static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tif", "tiff", "heic", "bmp", "webp"
    ]

    static func pdfDocument(from data: Data, title: String) throws -> PDFDocument {
        let archive: SimpleZIPArchive
        do {
            archive = try SimpleZIPArchive(data: data)
        } catch {
            throw DocumentImportConverter.ConversionError.comicArchiveUnreadable
        }

        let imageNames = archive.entryNames
            .filter(isSupportedImagePath)
            .sorted(by: naturalPathCompare)
        guard !imageNames.isEmpty else {
            throw DocumentImportConverter.ConversionError.comicArchiveNoImages
        }
        guard imageNames.count <= maxPageCount else {
            throw DocumentImportConverter.ConversionError.comicArchiveTooManyImages(
                maxPages: maxPageCount
            )
        }

        let output = PDFDocument()
        for imageName in imageNames {
            let imageData: Data
            do {
                imageData = try archive.data(named: imageName)
            } catch {
                throw DocumentImportConverter.ConversionError.comicArchiveUnreadable
            }
            do {
                let pageDocument = try DocumentImportConverter.renderImage(
                    imageData,
                    title: imageName
                )
                guard let page = pageDocument.page(at: 0) else {
                    throw DocumentImportConverter.ConversionError.comicArchiveUnreadableImage(
                        imageName
                    )
                }
                output.insert(page, at: output.pageCount)
            } catch let error as DocumentImportConverter.ConversionError {
                switch error {
                case .comicArchiveUnreadableImage:
                    throw error
                default:
                    throw DocumentImportConverter.ConversionError.comicArchiveUnreadableImage(
                        imageName
                    )
                }
            } catch {
                throw DocumentImportConverter.ConversionError.comicArchiveUnreadableImage(
                    imageName
                )
            }
        }

        guard output.pageCount == imageNames.count else {
            throw DocumentImportConverter.ConversionError.comicArchiveUnreadable
        }
        output.documentAttributes = [
            PDFDocumentAttribute.titleAttribute:
                URL(fileURLWithPath: title).deletingPathExtension().lastPathComponent
        ]
        return output
    }

    private static func isSupportedImagePath(_ path: String) -> Bool {
        guard !path.hasPrefix("__MACOSX/") else { return false }
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard !name.hasPrefix(".") else { return false }
        return supportedImageExtensions.contains(
            URL(fileURLWithPath: path).pathExtension.lowercased()
        )
    }

    private static func naturalPathCompare(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }
}
