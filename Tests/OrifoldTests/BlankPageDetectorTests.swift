import XCTest
import PDFKit
@testable import Orifold

final class BlankPageDetectorTests: XCTestCase {

    func testWhitePageIsDetectedAsBlank() throws {
        let pdf = try makePDF(pages: [.white])
        XCTAssertEqual(BlankPageDetector.candidateIndices(in: pdf), [0])
    }

    func testTextPageIsNotDetectedAsBlank() throws {
        let pdf = try makePDF(pages: [.text("The quick brown fox jumps over the lazy dog")])
        XCTAssertEqual(BlankPageDetector.candidateIndices(in: pdf), [])
    }

    func testLightScannerNoiseStillCountsAsBlank() throws {
        let pdf = try makePDF(pages: [.speckled(dots: 12)])
        XCTAssertEqual(BlankPageDetector.candidateIndices(in: pdf), [0])
    }

    func testMixedDocumentReportsOnlyTheBlankIndices() throws {
        let pdf = try makePDF(pages: [.white, .text("Chapter One"), .white, .text("Chapter Two")])
        XCTAssertEqual(BlankPageDetector.candidateIndices(in: pdf), [0, 2])
    }

    // MARK: - Fixtures

    private enum PageKind {
        case white
        case text(String)
        case speckled(dots: Int)
    }

    private func makePDF(pages: [PageKind]) throws -> PDFDocument {
        let pdf = PDFDocument()
        for (index, kind) in pages.enumerated() {
            let size = CGSize(width: 400, height: 400)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            switch kind {
            case .white:
                break
            case .text(let text):
                (text as NSString).draw(
                    in: NSRect(x: 20, y: 40, width: 360, height: 320),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black]
                )
            case .speckled(let dots):
                NSColor.black.setFill()
                var seed: UInt64 = 42
                for _ in 0..<dots {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed % 380) + 10
                    let y = CGFloat((seed >> 16) % 380) + 10
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            image.unlockFocus()
            let page = try XCTUnwrap(PDFPage(image: image))
            pdf.insert(page, at: index)
        }
        return pdf
    }
}
