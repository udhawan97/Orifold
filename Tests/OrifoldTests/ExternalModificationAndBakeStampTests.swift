import PDFKit
import XCTest
@testable import Orifold

/// WP-F: a per-machine fingerprint sidecar lets a load detect that a saved file was rewritten
/// by another app since Orifold last wrote it. On mismatch the loader keeps the visible
/// content and discards the now-stale embedded edit operations (data safety, user item B). A
/// bake stamp on each regenerated page records which operations its bytes were baked from, so
/// reconciliation can tell current bytes from stale ones — including style-only edits (item F).
final class ExternalModificationAndBakeStampTests: XCTestCase {
    // MARK: - Fixture plumbing

    /// Every sidecar directory created by `tempStore()`/`makeTempDirectory()` this test run,
    /// removed in `tearDown()` — each store writes a real `workspace-fingerprints.json` under
    /// `FileManager.default.temporaryDirectory`, which otherwise accumulates one leftover
    /// directory per test run forever.
    private var createdDirectories: [URL] = []

    override func tearDown() {
        for dir in createdDirectories { try? FileManager.default.removeItem(at: dir) }
        createdDirectories = []
        super.tearDown()
    }

    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-fpr-\(UUID().uuidString)", isDirectory: true)
        createdDirectories.append(dir)
        return dir
    }

    private final class FixturePageView: NSView {
        private let text: String
        init(frame: CGRect, text: String) { self.text = text; super.init(frame: frame) }
        required init?(coder: NSCoder) { nil }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill(); dirtyRect.fill()
            (text as NSString).draw(
                in: bounds.insetBy(dx: 54, dy: 54),
                withAttributes: [.font: NSFont(name: "Helvetica", size: 14) ?? .systemFont(ofSize: 14),
                                 .foregroundColor: NSColor.black])
        }
    }

    private func makePDFData(pageTexts: [String]) throws -> Data {
        let pdf = PDFDocument()
        for (index, text) in pageTexts.enumerated() {
            let view = FixturePageView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), text: text)
            let pageData = view.dataWithPDF(inside: view.bounds)
            guard let doc = PDFDocument(data: pageData), let page = doc.page(at: 0) else {
                throw XCTSkip("fixture page rendering failed")
            }
            pdf.insert(page, at: index)
        }
        return try XCTUnwrap(pdf.dataRepresentation())
    }

    private func makeViewModel(from pdfData: Data, name: String, store: WorkspaceFingerprintStore) throws -> WorkspaceViewModel {
        let wrapper = FileWrapper(regularFileWithContents: pdfData)
        wrapper.preferredFilename = "\(name).pdf"
        let document = try WorkspaceDocument(testingFile: wrapper, contentType: .pdf, filename: "\(name).pdf", fingerprintStore: store)
        return WorkspaceViewModel(document: document, processingEngine: PDFiumProcessingEngine())
    }

    private func tempStore() -> WorkspaceFingerprintStore {
        WorkspaceFingerprintStore(directory: makeTempDirectory())
    }

    @discardableResult
    private func applyEdit(_ viewModel: WorkspaceViewModel, pageIndex: Int, matching needle: String, replacement: String) throws -> PDFTextEditOperation {
        let memberID = try XCTUnwrap(viewModel.loadedPDFs.first?.0.id)
        let data = try XCTUnwrap(viewModel.document.memberPDFData[memberID])
        let page = try XCTUnwrap(viewModel.loadedPDFs.first?.1.page(at: pageIndex))
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: pageIndex, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains(needle) })
        let target = try XCTUnwrap(viewModel.editableTextBlock(
            at: CGPoint(x: block.bounds.midX, y: block.bounds.midY), on: page, in: viewModel.combinedPDF))
        XCTAssertTrue(viewModel.applyInlineTextEdit(
            pageRef: target.pageRef, sourceBlock: target.block, replacementText: replacement,
            editedBounds: target.block.bounds, fontName: target.block.fontName, fontSize: target.block.fontSize,
            textColor: .black, alignment: .left))
        return try XCTUnwrap(viewModel.document.workspace.pageEditStates
            .first(where: { $0.pageRefID == target.pageRef.id })?
            .operations.first(where: { $0.sourceBlockID == target.block.id }))
    }

    /// Saves the exact bytes a real save writes, recording the fingerprint via the injected store.
    private func save(_ viewModel: WorkspaceViewModel) throws -> Data {
        let wrapper = try viewModel.document.savedFileWrapper(from: viewModel.document.snapshot(contentType: .pdf))
        return try XCTUnwrap(wrapper.regularFileContents)
    }

    /// Simulates a third-party rewrite: reload + re-serialize (changes the raw bytes) while
    /// preserving both the visible content and Orifold's embedded editable metadata.
    private func externallyRewrite(_ data: Data) throws -> Data {
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let note = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 40, height: 12), forType: .freeText, withProperties: nil)
        note.contents = "third-party note"
        try XCTUnwrap(pdf.page(at: 0)).addAnnotation(note)
        return try XCTUnwrap(pdf.dataRepresentation())
    }

    // MARK: - BakeStamp unit

    func testBakeStampHashIsDeterministicOrderIndependentAndContentSensitive() throws {
        let store = tempStore()
        let vm = try makeViewModel(from: try makePDFData(pageTexts: ["Alpha original paragraph text"]), name: "Stamp", store: store)
        let opA = try applyEdit(vm, pageIndex: 0, matching: "Alpha original", replacement: "Alpha one token")
        var opB = opA; opB.id = UUID(); opB.replacementText = "Alpha two token"

        XCTAssertEqual(BakeStamp.hash(for: [opA, opB]), BakeStamp.hash(for: [opB, opA]),
                       "hash is independent of operation array order")
        XCTAssertEqual(BakeStamp.hash(for: [opA]), BakeStamp.hash(for: [opA]),
                       "hash is deterministic for identical operations")
        XCTAssertNotEqual(BakeStamp.hash(for: [opA]), BakeStamp.hash(for: [opB]),
                          "changing an operation's content changes the hash")
        XCTAssertNotEqual(BakeStamp.hash(for: [opA]), BakeStamp.hash(for: [opA, opB]),
                          "adding an operation changes the hash")
    }

    // MARK: - Fingerprint store unit

    func testFingerprintStoreRecordsRetrievesEvictsAndPersists() throws {
        let dir = makeTempDirectory()
        let store = WorkspaceFingerprintStore(directory: dir, maxEntries: 3)
        let ids = (0..<4).map { _ in UUID() }
        for (i, id) in ids.enumerated() { store.record(hash: "h\(i)", for: id) }

        XCTAssertNil(store.fingerprint(for: ids[0]), "oldest entry evicted past the LRU cap")
        XCTAssertEqual(store.fingerprint(for: ids[3]), "h3", "newest entry retained")
        XCTAssertEqual(store.fingerprint(for: ids[1]), "h1", "within-cap entries retained")

        // Persistence: a fresh instance over the same directory sees the recorded entries.
        let reopened = WorkspaceFingerprintStore(directory: dir, maxEntries: 3)
        XCTAssertEqual(reopened.fingerprint(for: ids[3]), "h3", "fingerprints persist across instances")

        XCTAssertEqual(WorkspaceFingerprintStore.hash(of: Data("x".utf8)),
                       WorkspaceFingerprintStore.hash(of: Data("x".utf8)), "hashing is stable")
        XCTAssertNotEqual(WorkspaceFingerprintStore.hash(of: Data("x".utf8)),
                          WorkspaceFingerprintStore.hash(of: Data("y".utf8)), "different bytes → different hash")
    }

    // MARK: - Round trip

    func testUntouchedReopenKeepsEditsAndFiresNoNotice() throws {
        let store = tempStore()
        let vm = try makeViewModel(from: try makePDFData(pageTexts: ["Beta original paragraph text"]), name: "Beta", store: store)
        try applyEdit(vm, pageIndex: 0, matching: "Beta original", replacement: "Beta edited unique token")
        let saved = try save(vm)

        let reopened = try makeViewModel(from: saved, name: "BetaReopen", store: store)
        XCTAssertTrue(reopened.hasInlineTextEdits, "untouched reopen (fingerprint matches) keeps the edit operations")
        XCTAssertNil(reopened.importError, "no external-modification notice for an untouched file")
        XCTAssertFalse(reopened.document.restoredOriginalMemberPDFData.isEmpty, "pristine base retained")
    }

    func testExternalModificationDropsStaleEditsKeepsContentAndFiresNotice() throws {
        let store = tempStore()
        let vm = try makeViewModel(from: try makePDFData(pageTexts: ["Gamma original paragraph text"]), name: "Gamma", store: store)
        try applyEdit(vm, pageIndex: 0, matching: "Gamma original", replacement: "Gamma edited unique token")
        let saved = try save(vm)
        let tampered = try externallyRewrite(saved)   // same visible content + metadata, different bytes

        let reopened = try makeViewModel(from: tampered, name: "GammaReopen", store: store)
        XCTAssertFalse(reopened.hasInlineTextEdits, "external modification discards the now-stale edit operations")
        XCTAssertTrue(reopened.document.restoredOriginalMemberPDFData.isEmpty, "external modification drops the pristine base")
        let notice = try XCTUnwrap(reopened.importError, "external modification surfaces a one-line notice")
        XCTAssertEqual(notice.message, L10n.string("notice.externalModification.detected"))
        // Visible content wins: the baked edit text stays present as page content.
        XCTAssertTrue(InlineEditReconciliationTests.allPagesText(fromData: tampered).contains("Gamma edited unique token"),
                      "the visible (baked) content is preserved")
    }

    func testLegacyFileWithoutFingerprintKeepsEdits() throws {
        let store = tempStore()
        let vm = try makeViewModel(from: try makePDFData(pageTexts: ["Delta original paragraph text"]), name: "Delta", store: store)
        try applyEdit(vm, pageIndex: 0, matching: "Delta original", replacement: "Delta edited unique token")
        let saved = try save(vm)

        // A DIFFERENT machine / cleared sidecar: no fingerprint on record → trust embedded state.
        let freshStore = tempStore()
        let reopened = try makeViewModel(from: saved, name: "DeltaReopen", store: freshStore)
        XCTAssertTrue(reopened.hasInlineTextEdits, "no fingerprint on record → keep the embedded edits (legacy/other-machine)")
        XCTAssertNil(reopened.importError, "absence of a fingerprint is not an external modification")
    }

    // MARK: - Sanitize + stale-bake detection

    func testSanitizeStripsBakeStamp() throws {
        let store = tempStore()
        let vm = try makeViewModel(from: try makePDFData(pageTexts: ["Epsilon original paragraph text"]), name: "Epsilon", store: store)
        try applyEdit(vm, pageIndex: 0, matching: "Epsilon original", replacement: "Epsilon edited unique token")
        let memberBytes = try XCTUnwrap(vm.loadedPDFs.first?.1.dataRepresentation())

        func hasBakeStamp(_ data: Data) -> Bool {
            guard let pdf = PDFDocument(data: data) else { return false }
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                if page.annotations.contains(where: {
                    $0.value(forAnnotationKey: PDFAnnotationKey(rawValue: BakeStamp.annotationKey)) != nil
                }) { return true }
            }
            return false
        }

        XCTAssertTrue(hasBakeStamp(memberBytes), "a regenerated page carries a bake stamp")
        let sanitized = WorkspaceDocument.dataStrippedOfOrifoldMetadata(memberBytes)
        XCTAssertFalse(hasBakeStamp(sanitized), "sanitize strips the bake stamp")
    }

    /// A stamped page whose operation set later changes without a re-bake must be detected as
    /// stale and regenerated — the case text-presence alone can miss for style-only edits.
    func testStaleStampTriggersRegeneration() throws {
        let store = tempStore()
        let vm = try makeViewModel(from: try makePDFData(pageTexts: ["Zeta original paragraph text"]), name: "Zeta", store: store)
        let op = try applyEdit(vm, pageIndex: 0, matching: "Zeta original", replacement: "Zeta edited unique token")

        // Bytes are current immediately after the commit: reconcile is a no-op.
        XCTAssertEqual(vm.reconcileCommittedEditsWithLoadedPages(), 0, "freshly baked page reconciles to zero regenerations")

        // Mutate the stored operation set (simulating a divergence the bytes don't reflect):
        // the page's stamp now mismatches hash(operations) → reconcile must regenerate.
        let stateIdx = try XCTUnwrap(vm.document.workspace.pageEditStates.firstIndex(where: { $0.pageRefID == op.pageRefID }))
        var mutated = op; mutated.id = UUID(); mutated.replacementText = "Zeta second token"
        vm.document.workspace.pageEditStates[stateIdx].operations.append(mutated)
        XCTAssertGreaterThan(vm.reconcileCommittedEditsWithLoadedPages(), 0,
                             "a stamp that no longer matches the operation set forces regeneration")
    }

    /// Adversarial check for a claim that `BakeStamp.hash`'s identity fields (`id`,
    /// `createdAt`, `modifiedAt`) churn on every re-edit — since `applyInlineTextEdit`
    /// never carries them over from the existing op on a same-block re-edit (see its
    /// merge block) — could cause a wrong reconcile decision (a stale-trusted or
    /// wrongly-invalidated bake). It cannot: the stamp is always recomputed from, and
    /// attached to, the SAME in-memory `operations` value in the SAME commit
    /// (`regenerateEditedPage`), so bake-time and reconcile-time always see identical
    /// identity fields for a given edit state. This locks in that real re-edits (not just
    /// synthetic array mutation) still reconcile to zero regenerations right after each
    /// commit, and that the identity fields do churn as claimed (proving the check isn't
    /// vacuous).
    func testReEditingTheSameBlockChurnsIdentityFieldsButReconcilesCleanly() throws {
        let store = tempStore()
        let vm = try makeViewModel(from: try makePDFData(pageTexts: ["Theta original paragraph text"]), name: "Theta", store: store)

        let firstOp = try applyEdit(vm, pageIndex: 0, matching: "Theta original", replacement: "Theta first replacement token")
        XCTAssertEqual(vm.reconcileCommittedEditsWithLoadedPages(), 0, "reconcile is a no-op right after the first commit")

        // Re-edit the SAME block (find it again post-edit and edit again) — this exercises
        // the real `applyInlineTextEdit` merge path, not a synthetic mutation.
        let memberID = try XCTUnwrap(vm.loadedPDFs.first?.0.id)
        let data = try XCTUnwrap(vm.document.memberPDFData[memberID])
        let page = try XCTUnwrap(vm.loadedPDFs.first?.1.page(at: 0))
        let analysis = PDFTextAnalysisEngine().analyze(data: data, pageIndex: 0, pageRefID: UUID(), fallbackPage: page)
        let block = try XCTUnwrap(analysis.blocks.first { $0.text.contains("Theta first replacement") })
        let target = try XCTUnwrap(vm.editableTextBlock(
            at: CGPoint(x: block.bounds.midX, y: block.bounds.midY), on: page, in: vm.combinedPDF))
        XCTAssertTrue(vm.applyInlineTextEdit(
            pageRef: target.pageRef, sourceBlock: target.block, replacementText: "Theta second replacement token",
            editedBounds: target.block.bounds, fontName: target.block.fontName, fontSize: target.block.fontSize,
            textColor: .black, alignment: .left))
        let secondOp = try XCTUnwrap(vm.document.workspace.pageEditStates
            .first(where: { $0.pageRefID == firstOp.pageRefID })?
            .operations.first(where: { $0.sourceBlockID == firstOp.sourceBlockID }))

        // The claim under test: identity fields are NOT carried over on a re-edit.
        XCTAssertNotEqual(firstOp.id, secondOp.id, "id gets a fresh UUID on every re-edit (not carried over)")
        XCTAssertNotEqual(firstOp.createdAt, secondOp.createdAt, "createdAt gets a fresh Date on every re-edit (not carried over)")
        // Meaningful content DID change (this is a genuine re-edit), and the paired
        // sourceBounds/originalFormat (the actually load-bearing fields) WERE preserved.
        XCTAssertEqual(secondOp.replacementText, "Theta second replacement token")
        XCTAssertEqual(secondOp.sourceBounds, firstOp.sourceBounds, "sourceBounds is carried over across the re-edit")
        XCTAssertEqual(secondOp.originalFormat, firstOp.originalFormat, "originalFormat is carried over across the re-edit")

        // Despite that identity churn, reconcile is STILL a clean no-op right after the
        // second commit — the stamp and the hash of the current operations are computed
        // from the same values in the same commit, so a fresh id/createdAt never causes a
        // stale-trusted or wrongly-invalidated bake.
        XCTAssertEqual(vm.reconcileCommittedEditsWithLoadedPages(), 0,
                       "reconcile is still a no-op right after the re-edit commit, despite id/createdAt churn")
    }
}
