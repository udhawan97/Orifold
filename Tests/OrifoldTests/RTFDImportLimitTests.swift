import Foundation
import PDFKit
import XCTest
@testable import Orifold

@MainActor
final class RTFDImportLimitTests: XCTestCase {
    private let limit = 100 * 1024 * 1024
    private let rtf = Data("{\\rtf1\\ansi Fictional RTFD}".utf8)
    private var directories: [URL] = []

    override func tearDown() {
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    func testURLImportRejectsOversizedHiddenChild() throws {
        let package = try makePackage(files: [(".payload", 101 * 1024 * 1024)])
        XCTAssertThrowsError(try DocumentImportConverter.importedDocument(from: package)) {
            assertTypedLimit($0)
        }
    }

    func testURLImportStillRejectsOversizedVisibleChild() throws {
        let package = try makePackage(files: [("payload.bin", 101 * 1024 * 1024)])
        XCTAssertThrowsError(try DocumentImportConverter.importedDocument(from: package)) {
            assertTypedLimit($0)
        }
    }

    func testAsyncURLImportCountsNestedHiddenRegularFiles() async throws {
        let package = try makePackage(files: [(".hidden/nested/.payload", 101 * 1024 * 1024)])
        do {
            _ = try await DocumentImportConverter.importedDocumentAsync(from: package)
            XCTFail("Nested hidden package bytes must count toward the import limit")
        } catch {
            assertTypedLimit(error)
        }
    }

    func testURLImportCountsTheCombinedSizeOfHiddenAndNestedFiles() throws {
        let package = try makePackage(files: [
            (".first", 60 * 1024 * 1024),
            ("nested/.second", 41 * 1024 * 1024),
        ])
        XCTAssertThrowsError(try DocumentImportConverter.importedDocument(from: package)) {
            assertTypedLimit($0)
        }
    }

    func testURLAndFileWrapperImportsAgreeAtTheExactLimitAndOneByteOver() throws {
        for extraByte in [0, 1] {
            let package = try makePackage(files: [(".payload", limit - rtf.count + extraByte)])
            if extraByte == 0 {
                assertImported(try DocumentImportConverter.importedDocument(from: package))
            } else {
                XCTAssertThrowsError(try DocumentImportConverter.importedDocument(from: package)) {
                    assertTypedLimit($0)
                }
            }

            let wrapper = try FileWrapper(url: package, options: [.immediate])
            let children = try XCTUnwrap(wrapper.fileWrappers)
            if extraByte == 0 {
                assertImported(try DocumentImportConverter.importedRTFDDocument(
                    fromFileWrappers: children, filename: "Fictional.rtfd"))
            } else {
                XCTAssertThrowsError(try DocumentImportConverter.importedRTFDDocument(
                    fromFileWrappers: children, filename: "Fictional.rtfd")) {
                    assertTypedLimit($0)
                }
            }
        }
    }

    private func assertTypedLimit(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard case DocumentImportConverter.ConversionError.fileTypeTooLarge(let type, let actual, let allowed) = error else {
            return XCTFail("Expected the existing rich-document size error, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(type, "document", file: file, line: line)
        XCTAssertEqual(allowed, Int64(limit), file: file, line: line)
        XCTAssertGreaterThan(actual, allowed, file: file, line: line)
    }

    private func assertImported(_ imported: DocumentImportConverter.ImportedDocument,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(imported.pdfDocument.pageCount, 0, file: file, line: line)
        XCTAssertTrue(imported.pdfDocument.string?.contains("Fictional RTFD") == true, file: file, line: line)
        XCTAssertNil(imported.sourcePayload, file: file, line: line)
    }

    private func makePackage(files: [(path: String, byteCount: Int)]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RTFDImportLimit-\(UUID())")
        let package = root.appendingPathComponent("Fictional.rtfd")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        directories.append(root)
        try rtf.write(to: package.appendingPathComponent("TXT.rtf"))
        for item in files {
            let child = package.appendingPathComponent(item.path)
            try FileManager.default.createDirectory(at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
            XCTAssertTrue(FileManager.default.createFile(atPath: child.path, contents: Data()))
            let handle = try FileHandle(forWritingTo: child)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(item.byteCount))
        }
        return package
    }
}
