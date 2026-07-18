import PDFKit
import XCTest
@testable import Orifold

/// Click-to-place features (signature, stamp, hanko, barcode) are mutually
/// exclusive: at most one placement may be armed, because a page click resolves
/// to exactly one of them. These pin that invariant across every pair of arming
/// entry points, including the ones that cross the signature/stamp tool boundary.
final class PendingPlacementTests: XCTestCase {
    private func makeViewModel() throws -> WorkspaceViewModel {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        let wrapper = FileWrapper(regularFileWithContents: doc.dataRepresentation()!)
        wrapper.preferredFilename = "place.pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "place.pdf")
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    /// Every armed placement, as the canvas would see it. The canvas resolves a
    /// click through `currentTool` and then these, so more than one non-nil at a
    /// time means a stale placement is waiting to fire on an unrelated click.
    private func armedPlacements(_ viewModel: WorkspaceViewModel) -> [String] {
        var armed: [String] = []
        if viewModel.pendingSignatureData != nil { armed.append("signature") }
        if viewModel.pendingStampOptions != nil { armed.append("stamp") }
        if viewModel.pendingHankoOptions != nil { armed.append("hanko") }
        if viewModel.pendingBarcodeOptions != nil { armed.append("barcode") }
        return armed
    }

    private func armStamp(_ viewModel: WorkspaceViewModel) {
        viewModel.beginStampPlacement(text: "DRAFT", swatch: .accent)
    }

    private func armSignature(_ viewModel: WorkspaceViewModel) {
        viewModel.beginVisualSignaturePlacement(
            imageData: Data([0x89, 0x50, 0x4E, 0x47]), kind: .visualDrawn, signerName: "Ori")
    }

    // The three stamp-family entry points disarm each other by hand. This is the
    // behaviour that already worked; it guards the refactor that replaces the
    // hand-nil-ing with a single armed slot.
    func testStampFamilyEntryPointsDisarmEachOther() throws {
        let viewModel = try makeViewModel()

        armStamp(viewModel)
        XCTAssertEqual(armedPlacements(viewModel), ["stamp"])

        viewModel.beginHankoPlacement(text: "印", shape: .circle)
        XCTAssertEqual(armedPlacements(viewModel), ["hanko"], "arming a hanko must disarm the stamp")

        viewModel.beginBarcodePlacement(imageData: Data([0x89, 0x50]), pixelSize: CGSize(width: 64, height: 64))
        XCTAssertEqual(armedPlacements(viewModel), ["barcode"], "arming a barcode must disarm the hanko")

        armStamp(viewModel)
        XCTAssertEqual(armedPlacements(viewModel), ["stamp"], "arming a stamp must disarm the barcode")
    }

    // Arming a signature while a stamp is armed leaves BOTH armed: the signature
    // entry points never clear the stamp family, and `currentTool`'s observer only
    // clears signature state when LEAVING `.signature`. Exclusion is enforced by
    // two different mechanisms that don't cover this direction.
    func testArmingASignatureDisarmsAPendingStamp() throws {
        let viewModel = try makeViewModel()

        armStamp(viewModel)
        armSignature(viewModel)

        XCTAssertEqual(armedPlacements(viewModel), ["signature"],
                       "arming a signature must disarm the stamp — at most one placement may be armed")
    }

    // The user-visible consequence: arm a stamp, arm a signature, cancel the
    // signature. The stamp is still armed with no cancel path of its own, so the
    // next click on the stamp tool silently places a stamp the user thought they
    // had moved on from, instead of reopening the palette.
    func testCancellingASignatureLeavesNothingArmed() throws {
        let viewModel = try makeViewModel()

        armStamp(viewModel)
        armSignature(viewModel)
        viewModel.cancelSignaturePlacement()

        XCTAssertEqual(armedPlacements(viewModel), [],
                       "cancelling the only in-flight placement must leave nothing armed to fire on the next click")
    }

    // Symmetric direction: a stamp armed after a signature must disarm it. This one
    // already works (the stamp entry points call clearPendingSignaturePlacement).
    func testArmingAStampDisarmsAPendingSignature() throws {
        let viewModel = try makeViewModel()

        armSignature(viewModel)
        armStamp(viewModel)

        XCTAssertEqual(armedPlacements(viewModel), ["stamp"], "arming a stamp must disarm the signature")
    }
}
