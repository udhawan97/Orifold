import PDFKit
import XCTest
@testable import Orifold

/// PHASE 0 PROBE (part 2) — decode the embedded Orifold workspace payload inside the
/// user fixture to confirm the trapped-state hypothesis: pageEditStates carries the
/// "yolo" op while the visible page bytes (flat pages AND embedded editable member
/// data) do not contain the edit.
final class Phase0MetadataProbeTests: XCTestCase {
    private static let fixtureURL = URL(fileURLWithPath: "/Users/umang/Documents/development/test-files-Orifold/test-text-edit-latest.pdf")

    private struct ProbeMetadata: Codable {
        var editableWorkspace: Workspace?
        var editableMemberPDFData: [UUID: Data]?
    }

    func testProbe_E_dumpEmbeddedWorkspaceState() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let key = PDFAnnotationKey(rawValue: "/OrifoldWorkspaceComments")
        var payload: String?
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                if let raw = annotation.value(forAnnotationKey: key) as? String {
                    payload = raw
                }
            }
        }
        let raw = try XCTUnwrap(payload, "fixture should contain embedded workspace metadata")
        print("PROBE[E] metadata bytes=\(raw.utf8.count)")
        let meta = try JSONDecoder().decode(ProbeMetadata.self, from: Data(raw.utf8))
        let workspace = try XCTUnwrap(meta.editableWorkspace)
        print("PROBE[E] pageEditStates count=\(workspace.pageEditStates.count)")
        for state in workspace.pageEditStates {
            for op in state.operations {
                print("PROBE[E] op page=\(state.pageRefID) source='\(op.sourceText.prefix(50))' replacement='\(op.replacementText.prefix(50))' editedBounds=\(op.editedBounds) font=\(op.fontName)@\(op.fontSize) styleChange=\(op.didManuallyChangeStyle) matchedGeom=\(op.didApplyMatchedGeometry) insertion=\(op.isInsertion) created=\(op.createdAt) modified=\(op.modifiedAt)")
            }
        }
        // Does the embedded editable member data itself contain the visible edit?
        for (memberID, memberData) in meta.editableMemberPDFData ?? [:] {
            guard let memberPDF = PDFDocument(data: memberData) else { continue }
            var yoloPages: [Int] = []
            for i in 0..<memberPDF.pageCount {
                guard let p = memberPDF.page(at: i) else { continue }
                let analysis = PDFTextAnalysisEngine().analyze(data: memberData, pageIndex: i, pageRefID: UUID(), fallbackPage: p)
                if analysis.blocks.contains(where: { $0.text.lowercased().contains("yolo") }) { yoloPages.append(i) }
            }
            print("PROBE[E] member=\(memberID) pages=\(memberPDF.pageCount) yolo visible on pages=\(yoloPages)")
        }
        // And the flat (visible) pages of the fixture itself?
        var flatYoloPages: [Int] = []
        for i in 0..<pdf.pageCount {
            guard let p = pdf.page(at: i) else { continue }
            let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: i, pageRefID: UUID(), fallbackPage: p)
            if analysis.blocks.contains(where: { $0.text.lowercased().contains("yolo") }) { flatYoloPages.append(i) }
        }
        print("PROBE[E] flat fixture yolo visible on pages=\(flatYoloPages)")
    }
}
