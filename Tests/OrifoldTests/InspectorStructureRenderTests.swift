import PDFKit
import SwiftUI
import XCTest
@testable import Orifold

/// Renders the two Wave-4 panels for real and asserts they produce pixels.
///
/// These exist because the panels are otherwise only reachable by clicking, and this
/// app's SwiftUI toolbar/tab buttons do not accept synthetic clicks — so a GUI driver
/// cannot reach them. A render pass is the honest substitute: it proves the view builds
/// its body against a live view model and rasterizes, which is exactly the failure mode
/// (a crash or an empty body) that unit-testing the service layer cannot catch.
///
/// Deliberately not snapshot tests. Pinning exact pixels would fail on every font or
/// palette change and teach the next person to regenerate goldens without looking.
@MainActor
final class InspectorStructureRenderTests: XCTestCase {

    func testStructureTabRendersForATaggedDocument() throws {
        let image = try render(InspectorView(
            viewModel: makeViewModel(data: fixture("tagged-sample.pdf")),
            selectedTab: .constant(.structure)
        ))

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertTrue(hasVisibleContent(image), "structure tab rendered blank")
    }

    func testStructureTabRendersTheWarningForAnUntaggedDocument() throws {
        let image = try render(InspectorView(
            viewModel: makeViewModel(data: fixture("untagged-sample.pdf")),
            selectedTab: .constant(.structure)
        ))

        XCTAssertTrue(hasVisibleContent(image), "untagged warning card rendered blank")
    }

    func testArchivalPanelRenders() throws {
        // Rendered at the panel's own declared width; a narrower proposal fights its
        // internal .frame(width: 420) and yields nothing to rasterize.
        let image = try render(
            ArchivalReadinessView(viewModel: makeViewModel(data: fixture("untagged-sample.pdf"))),
            width: 420
        )

        XCTAssertTrue(hasVisibleContent(image), "archival panel rendered blank")
    }

    /// The whole point of the archival feature is that it never claims validity. This
    /// pins the copy itself, in every shipped language, so a well-meaning reword cannot
    /// quietly turn a hint into a verdict.
    func testArchivalRowCopyNeverClaimsComplianceInAnyLanguage() throws {
        let banned = ["compliant", "compliance", "validated", "certified"]
        let rowKeys = [
            "archival.row.encryption", "archival.row.activeContent",
            "archival.row.fontsEmbedded", "archival.row.outputIntent",
            "archival.row.xmp", "archival.row.tagged", "archival.title"
        ]

        for key in rowKeys {
            for language in ["en", "es", "fr", "hi", "ja", "zh-Hans"] {
                let value = L10n.string(forKey: key, locale: Locale(identifier: language)).lowercased()
                for word in banned {
                    XCTAssertFalse(
                        value.contains(word),
                        "\(key) [\(language)] claims \(word): \(value)"
                    )
                }
            }
        }
    }

    /// Negative control. Without this, `hasVisibleContent` returning true for everything
    /// would make every assertion above vacuous — a green test that proves nothing.
    func testBlankViewIsReportedAsHavingNoVisibleContent() throws {
        let image = try render(Color.clear)

        XCTAssertFalse(hasVisibleContent(image))
    }

    // MARK: - Helpers

    private func render(_ view: some View, width: CGFloat = 320) throws -> NSImage {
        let renderer = ImageRenderer(content: view.frame(width: width, height: 520))
        renderer.scale = 1
        return try XCTUnwrap(renderer.nsImage, "ImageRenderer produced no image")
    }

    /// True when a meaningful share of the raster is opaque — a drawn panel paints its
    /// background, a blank view leaves everything transparent.
    ///
    /// The threshold is 10%, not a majority: a panel shorter than the proposed height
    /// legitimately leaves the remainder transparent, so "more than half opaque" rejected
    /// a perfectly good render. Blank is 0% opaque, so 10% still separates the two
    /// cleanly.
    ///
    /// Counting opaque pixels rather than distinct colours is deliberate. An earlier
    /// version counted distinct colours and reported a fully transparent view as having
    /// content, which made every assertion in this file vacuous;
    /// `testBlankViewIsReportedAsHavingNoVisibleContent` is what caught that, and is why
    /// the control stays.
    private func hasVisibleContent(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return false }

        var sampled = 0
        var opaque = 0
        for column in stride(from: 0, to: bitmap.pixelsWide, by: 5) {
            for row in stride(from: 0, to: bitmap.pixelsHigh, by: 5) {
                guard let colour = bitmap.colorAt(x: column, y: row)?
                    .usingColorSpace(.deviceRGB) else { continue }
                sampled += 1
                if colour.alphaComponent > 0.5 { opaque += 1 }
            }
        }
        guard sampled > 0 else { return false }
        return Double(opaque) / Double(sampled) > 0.1
    }

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        // swiftlint:disable:next force_try
        return try! Data(contentsOf: url)
    }

    private func makeViewModel(data: Data) -> WorkspaceViewModel {
        let document = WorkspaceDocument()
        var member = MemberDocument(displayName: "Fixture", sourcePDFRef: "fixture.pdf")
        let pageCount = PDFDocument(data: data)?.pageCount ?? 0
        let refs = (0..<pageCount).map { PageRef(memberDocId: member.id, sourcePageIndex: $0) }
        member.pageRefs = refs.map(\.id)
        document.workspace.documents = [member]
        document.workspace.pageOrder = refs
        document.memberPDFData[member.id] = data
        let viewModel = WorkspaceViewModel(document: document)
        viewModel.currentPageNumber = 1
        return viewModel
    }
}
