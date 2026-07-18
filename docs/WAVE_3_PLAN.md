# Wave 3 — Engine Work Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Parent doc: `docs/FEATURE_WAVES_MASTER_PLAN.md` (its Global Constraints apply to every task); source roadmap items #11 (compression pack v2), #7 (attachments manager), #8 (booklet/N-up), #12 (scan cleanup) in `docs/OPEN_SOURCE_FEATURE_ROADMAP.md`.

**Goal:** Ship the three code-only "engine" features — booklet/N-up imposition, an attachments manager, and a scan-cleanup mode — plus the *app-side wiring only* for compression-pack-v2 (its binary is BLOCKED, see below). All offline; zero new bundled runtime dependency (compression's new static libs are a separate ops task).

## FEASIBILITY VERDICTS (verified 2026-07-17 against the vendored binaries on branch `friendly-helper-claude/app-feature-roadmap-6b4c71`)

| Feature | Verdict | Why |
|---|---|---|
| **H — Compression pack v2 (zopfli + mozjpeg + JBIG2)** | **🚫 BLOCKED (binary rebuild) — app-side wiring only this wave** | Needs a from-source universal (`arm64`+`x86_64`) static rebuild of `QPDF.xcframework` **plus** a net-new vendored `jbig2enc`+`leptonica` static lib. No qpdf build script exists in-repo (only the prebuilt `libQPDF.a`). `nm` confirms zopfli **hooks present, library NOT compiled in**; mozjpeg absent (libjpeg-turbo linked); jbig2 = 0 symbols. An agent cannot reliably do a cross-compiled from-source static-lib rebuild headless. **Ship the binary as a separate ops task (H0). Ship the inert-safe app-side toggle now (H1/H2).** |
| **I — Attachments manager** | ✅ Doable, **code-only, ZERO new `@_silgen_name` bindings** | Everything reachable through the existing `import CQPDF` module (list/extract via `qpdf_oh_*` name-tree walk + `qpdf_oh_get_stream_data`; add/remove via `qpdfjob_run_from_argv`). Least binding surface of any option (PDFium's attachment API would cost ~7 new experimental bindings). |
| **J — Booklet / N-up imposition** | ✅ Doable, code-only, **3 new `@_silgen_name` bindings** | `FPDF_ImportNPagesToOne`, `FPDF_ImportPages`, `FPDF_CreateNewDocument` are exported by the dylib but **not yet bound** in Swift. All lifecycle/save helpers already exist and are reused. |
| **K — Scan cleanup ("Scan mode")** | ✅ Doable, code-only, **ZERO new `@_silgen_name` bindings** | Vision (`VNDetectDocumentSegmentationRequest`, macOS 12+) + vImage/Core Image; page apply reuses the rasterizer + an images→PDF page rebuild + the `applyOCRResult` byte-swap precedent. No PDFium image-object surgery needed. |

**Recommended intra-wave order:** **J → I → K → H(wiring).** Do the one binding-adding feature (J) first while fresh and release-build it immediately (silgen/WMO). I and K are zero-binding. H's app-side wiring is small and *inert until the binary lands*, so it goes last with its own BLOCKED banner.

**Total task count: 14 TDD code tasks** (J: 4, I: 4, K: 4, H: 2) **+ 1 BLOCKED ops task (H0, documented recipe, not executed this wave).**

---

## Anchor drift vs master brief (re-verified 2026-07-17 — RE-GREP before editing; shared repo moves fast)

- **Print path:** master brief said `WorkspaceViewModel ~:7623`. **Actual:** `func printWorkspace()` = `WorkspaceViewModel.swift:7765`; `NSPrintOperation(view:printInfo:)` = **:7790** (single plain operation, no n-up). DRIFT — re-grep `NSPrintOperation`.
- **Sanitize strips attachments:** brief said `QPDFService.swift:108`. **Actual:** `removeKey(qpdf, from: names, key: "/EmbeddedFiles")` = `QPDFService.swift:108` ✅ (inside `sanitized(_:removingMetadata:)` at :98; `/Names` fetched :106). Object shape confirmed: attachments live in `/Root/Names/EmbeddedFiles`.
- **OCR rasterizer:** brief said `PDFOCRService.renderedImage(for:) ~:277`. **Actual:** `:277` ✅ but **`private static`** — must be widened to `static` (internal) for K2. (Wave 2 Task G3 may already have widened it — re-grep `func renderedImage` before editing.)
- **PDFium `FPDFImageObj_SetBitmap`:** bound `private` as `FPDFCompression_ImageObjectSetBitmap` at `PDFCompressionService.swift:40`. K does **not** need it (see K3 rationale).
- **`FPDF_SaveAsCopy`:** bound **internal** (reusable) as `FPDFCompression_SaveAsCopy` at `PDFCompressionService.swift:80` with `struct FPDFCompressionFileWrite` at :87. Reuse for J3 — do NOT re-declare (release-build duplicate-type hazard).
- **PDFium lifecycle:** `FPDF_LoadMemDocument` (`PDFiumProcessingEngine.swift:12`), `FPDF_CloseDocument` (:19), `FPDF_GetPageCount` (:22), global `pdfiumLock = NSLock()` (:4) — all internal, reuse in J.
- **Existing PDFium binding file / pattern:** `Orifold/Engine/PDFiumObjectBindings.swift` (the `poe_`-prefixed surface). `FPDF_NewXObjectFromPage`/`FPDF_CloseXObject`/`FPDF_NewFormObjectFromXObject` from `fpdf_ppo.h` are ALREADY bound here (`poe_*`) — J's new `fpdf_ppo.h` bindings go in a new file with a distinct prefix, same style.
- **Compression preset enum:** `PDFCompressionPreset` = `Orifold/Models/WorkspaceExportOptions.swift:42` (cases `.balanced`, `.small`). `WorkspaceExportOptions` struct = same file :3 (already carries `compressionPreset: PDFCompressionPreset?`).
- **Export bake ordering:** `dataForPDFExport(options:)` = `WorkspaceViewModel.swift:5627` → `document.exportedPDFDataThrowing(from:options:)` → `applyDecorationExportAdditions` (bake via `PDFDecorationExportBaker.bake` at `WorkspaceDocument.swift:412`) → then compression. **Imposition must run on the post-bake, post-compression export bytes** (J3).
- **OCR apply/byte-swap precedent:** `applyOCRResult(_:)` = `WorkspaceViewModel.swift:2327` (sets `document.memberPDFData[id]`, resets `originalMemberPDFData` pristine base, `invalidatePageInspection`, `rebuild()`). Both I3 and K3 mirror this.
- **Inspector tab enum:** `InspectorView.Tab` = `Orifold/Views/InspectorView.swift:13` (`info/tags/comments/markup/decorate/ocr`; `iconName` :21, `titleKey` :35). Add `.attachments` for I4.
- **Images→PDF lane:** `PDFKitEngine.renderImage(_:title:)` = `Orifold/Engine/PDFKitEngine.swift:1031` (`private static`) — K3 page rebuild references this pattern (widen or mirror).
- **Export/compression UI:** the export sheet + preset picker live in `Orifold/Views/ContentView.swift` (re-grep `compressionPreset`). H2 and J4 add controls here.
- **L10n tests:** `Tests/OrifoldTests/LocalizationCoverageTests.swift` + `RawLocalizationKeyLeakTests.swift`. `Orifold/Resources/THIRD-PARTY-NOTICES.md` exists (25 KB).

## Binding-surface `nm` findings (macos-arm64_x86_64 slice)

- `libQPDF.a`: `__ZN8Pl_Flate14zopfli_enabledEv`, `..zopfli_supportedEv`, `..zopfli_check_envEP10QPDFLogger`, `..finish_zopfliEv` present (14 hits) = **hooks only**. No `ZopfliDeflate/ZopfliCompress/ZopfliInitOptions` = **zopfli lib not compiled in** → `zopfli_supported()` returns false at runtime. `jinit_*` = libjpeg-turbo (not mozjpeg). `jbig2` = **0**.
- PDFium framework binary: `FPDF_ImportNPagesToOne`, `FPDF_ImportPages`, `FPDF_ImportPagesByIndex`, `FPDF_CreateNewDocument`, `FPDFPage_New`, `FPDFPage_Delete`, `FPDF_GetPageSizeByIndexF`, and all `FPDFDoc_*Attachment*` / `FPDFAttachment_*` symbols = **exported**. Grep of `Orifold/` confirms none of the import/attachment symbols are currently `@_silgen_name`-bound.
- `qpdf-c.h`: **no** dedicated attachment/embedded-file helpers — only `qpdf_oh_*` object surgery (`qpdf_oh_get_key`, `qpdf_oh_has_key`, `qpdf_oh_get_stream_data` :917, `qpdf_oh_new_stream` :852, `qpdf_oh_replace_stream_data` :946, `qpdf_oh_remove_key` :243-in-use). `qpdfjob-c.h` (`qpdfjob_run_from_argv` :58, `qpdfjob_run_from_json` :74) and `qpdflogger-c.h` are BOTH in the CQPDF `module.modulemap` → callable via `import CQPDF` with **no new binding surface**.

## Cross-cutting gotchas (apply to EVERY task)

- **(a) xcstrings is ORDER-PRESERVING.** Insert keys with a Python `OrderedDict` round-trip (no `sort_keys`), at the sorted position. Each entry: `{"extractionState":"manual","localizations":{lang:{"stringUnit":{"state":"translated","value":…}}}}` for **all 6** langs `en/es/fr/hi/ja/zh-Hans`. `LocalizationCoverageTests` fails on any missing lang.
- **(b) L10n.** All user-facing strings via `L10n.string(_, locale:)`; `RawLocalizationKeyLeakTests` fails on raw dotted keys in `Text/Label/Button/Toggle/Menu/help/…`. SwiftUI views that must live-switch read `@Environment(\.locale)`.
- **(c) Safe bundle resolution** mirroring `L10n.swift` probe (Bundle.main/anchor URLs); NEVER the trapping `Bundle.module` accessor.
- **(d) CI-safe text extraction.** NEVER assert `PDFPage.string` equality (Xcode 16.4 SDK interleaves/undercounts). Use PDFium `FPDFText_*`, `attributedString`, or thumbnail pixel brightness (`NSBitmapImageRep.colorAt → brightnessComponent`).
- **(e) New `@_silgen_name` bindings (J only).** One binding per C symbol *per Swift type*. Two bindings of the same symbol with **different** Swift signatures pass debug+`swift test` but **break `swift build -c release`** (WMO merge) — the FPDF_SaveAsCopy-dup lesson (ff08f10). REUSE the existing internal bindings; only add symbols not already bound; keep re-declared signatures byte-identical. **Release-build after any binding change.**
- **(f) Preserving pipeline.** Any feature that mutates member **bytes** routes through `QPDFService` structural validation (`isStructurallySound`) and the ops↔bytes reconcile/pristine-base path (mirror `applyOCRResult`). NEVER re-serialize via PDFKit `dataRepresentation()` (destroys the qpdf-preserved text layer). PDFium `FPDF_SaveAsCopy` re-serialization is an already-accepted path (object-edit write-back uses it) but still gate the output with `isStructurallySound`.
- **(g) Warm-cache focused tests during dev; ONE full `swift test` per feature; commit per task; DO NOT push (recovery branch).** Merge/push only if explicitly instructed.

---

# Feature J — Booklet / N-up imposition  *(do FIRST — the only binding-adding feature)*

Design: pure page-order math (`ImpositionService`, exhaustively tested) → PDFium imposition engine (bytes→bytes via 3 new bindings + reused lifecycle/save) → export option + print n-up → L10n. **Critical:** N-up flattens pages into XObjects and **drops annotations**, so imposition runs on the fully-baked export bytes (post-`PDFDecorationExportBaker`, post-compression), never on the live document.

### Task J1: PDFium imposition bindings (+ release-build gate)

**Files:**
- Create: `Orifold/Engine/PDFiumImpositionBindings.swift`
- Test: `Tests/OrifoldTests/PDFiumImpositionBindingsTests.swift`

**Interfaces (produces — new bindings, `imp_` prefix, mirroring `PDFiumObjectBindings.swift` style):**

```swift
import Foundation

// fpdf_ppo.h — page imposition. Symbols verified exported via `nm`; NOT previously bound.
// (FPDF_NewXObjectFromPage & friends from the same header are already bound `poe_*` in
// PDFiumObjectBindings.swift — do not re-bind those here.)
@_silgen_name("FPDF_ImportNPagesToOne")
func imp_ImportNPagesToOne(_ srcDoc: OpaquePointer?,
                           _ outputWidth: Float, _ outputHeight: Float,
                           _ numPagesX: Int, _ numPagesY: Int) -> OpaquePointer?   // size_t -> Int

@_silgen_name("FPDF_ImportPages")
func imp_ImportPages(_ destDoc: OpaquePointer?, _ srcDoc: OpaquePointer?,
                     _ pageRange: UnsafePointer<CChar>?, _ index: Int32) -> Int32   // FPDF_BOOL, FPDF_BYTESTRING

@_silgen_name("FPDF_CreateNewDocument")
func imp_CreateNewDocument() -> OpaquePointer?
```

- Reuse (do NOT re-declare): `FPDF_LoadMemDocument`/`FPDF_CloseDocument`/`FPDF_GetPageCount` (PDFiumProcessingEngine.swift), `FPDFCompression_SaveAsCopy` + `FPDFCompressionFileWrite` (PDFCompressionService.swift:80/:87), global `pdfiumLock`.

- [ ] **Step 1: Failing smoke test** (proves the symbols link + a trivial 2→1 N-up round-trips through save). Build the source doc with PDFKit *for fixture creation only*:

```swift
import XCTest
import PDFKit
@testable import Orifold

final class PDFiumImpositionBindingsTests: XCTestCase {
    private func twoPageFixture() -> Data {
        let doc = PDFDocument()
        for _ in 0..<2 { doc.insert(PDFPage(), at: doc.pageCount) }
        return doc.dataRepresentation()!   // fixture only — never product code
    }

    func testImportNPagesToOneProducesOnePage() throws {
        let out = try PDFImpositionEngine.impose(twoPageFixture(), layout: .nUp(rows: 1, cols: 2))
        let rendered = try XCTUnwrap(PDFDocument(data: out))
        XCTAssertEqual(rendered.pageCount, 1)                 // 2 src pages -> 1 sheet
        XCTAssertTrue(QPDFService.isStructurallySound(out))   // preserving-pipeline gate (f)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter PDFiumImpositionBindingsTests` → FAIL (no `PDFImpositionEngine`). J1 lands the bindings; J3 lands `PDFImpositionEngine.impose`. Keep the test red until J3, or split the binding-link proof into a raw `imp_CreateNewDocument() != nil` assertion inside `pdfiumLock`.
- [ ] **Step 3: Implement** the three bindings above.
- [ ] **Step 4:** `swift build -c release` **mandatory** (gotcha (e)). Then `swift test --filter PDFiumImpositionBindingsTests` (link-proof variant) → PASS.
- [ ] **Step 5: Commit** — `feat: bind FPDF_ImportPages/ImportNPagesToOne/CreateNewDocument (imposition)`.

**Gotchas:** `size_t` params map to Swift `Int` (not `Int32`). `FPDF_ImportNPagesToOne` returns a NEW document handle the caller owns → must `FPDF_CloseDocument` it. `pagerange` is 1-indexed, `index` (insert position) is 0-indexed.

### Task J2: ImpositionService — pure page-order math

**Files:**
- Create: `Orifold/Engine/Imposition/ImpositionService.swift`
- Test: `Tests/OrifoldTests/ImpositionServiceTests.swift`

**Interfaces:**
```swift
enum ImpositionLayout: Equatable {
    case booklet                       // saddle-stitch, 2-up, auto-padded to multiple of 4
    case nUp(rows: Int, cols: Int)     // sequential grid (2x1, 2x2, 3x3, …)
}
enum ImpositionService {
    /// 0-indexed source page order for a saddle-stitch booklet, padded to a multiple of 4.
    /// `-1` = intentional blank. Order per physical side is [last, first, second, second-last, …].
    static func bookletPageOrder(pageCount: Int) -> [Int]
    /// Number of output sheets for an N-up grid.
    static func nUpSheetCount(pageCount: Int, perSheet: Int) -> Int
}
```

- [ ] **Step 1: Failing tests** (exhaustive small cases — booklet order is where the real logic is):

```swift
final class ImpositionServiceTests: XCTestCase {
    func testBookletPadsToMultipleOfFour() {
        XCTAssertEqual(ImpositionService.bookletPageOrder(pageCount: 1).count, 4)   // 3 blanks
        XCTAssertEqual(ImpositionService.bookletPageOrder(pageCount: 5).count, 8)
        XCTAssertEqual(ImpositionService.bookletPageOrder(pageCount: 4).count, 4)
    }
    func testBookletFourPageSignatureOrder() {
        // 4 pages (0..3): outer sheet back = [3,0], inner = [1,2]
        XCTAssertEqual(ImpositionService.bookletPageOrder(pageCount: 4), [3, 0, 1, 2])
    }
    func testBookletBlanksAreMinusOne() {
        // 2 pages -> padded to 4: pages 0,1 real; slots 2,3 blank
        XCTAssertEqual(ImpositionService.bookletPageOrder(pageCount: 2), [-1, 0, 1, -1])
    }
    func testEveryRealPageAppearsExactlyOnce() {
        for n in 1...16 {
            let order = ImpositionService.bookletPageOrder(pageCount: n)
            let reals = order.filter { $0 >= 0 }.sorted()
            XCTAssertEqual(reals, Array(0..<n), "n=\(n)")
        }
    }
    func testNUpSheetCount() {
        XCTAssertEqual(ImpositionService.nUpSheetCount(pageCount: 5, perSheet: 4), 2)
        XCTAssertEqual(ImpositionService.nUpSheetCount(pageCount: 4, perSheet: 2), 2)
    }
}
```

- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. Booklet: `padded = ceil(n/4)*4`; walk `left=padded-1, right=0` inward, emitting per side `[left, right]` then `[right+1, left-1]`, mapping any index ≥ n to `-1`. **Step 4:** PASS. **Step 5: Commit** — `feat: pure imposition page-order math (booklet + N-up)`.

**Gotchas:** derive the `[last,first,second,second-last,…]` pattern from the exhaustive test, not memory. Keep this file free of PDFium/Foundation-heavy imports so it stays a fast, deterministic unit.

### Task J3: PDFImpositionEngine (bytes→bytes) + wire AFTER bake

**Files:**
- Create: `Orifold/Engine/Imposition/PDFImpositionEngine.swift`
- Modify: `Orifold/ViewModels/WorkspaceViewModel.swift` (post-bake hook in the export path near `dataForPDFExport` :5627 / after `reducedData`), `Orifold/Models/WorkspaceExportOptions.swift` (add `var imposition: ImpositionLayout? = nil` to the struct + init)
- Test: `Tests/OrifoldTests/PDFImpositionEngineTests.swift`

**Interfaces:**
```swift
enum PDFImpositionError: LocalizedError { case invalidPDF, impositionFailed, saveFailed }
enum PDFImpositionEngine {
    /// Loads `data` (already fully baked + compressed), imposes, returns new bytes. Holds `pdfiumLock`.
    static func impose(_ data: Data, layout: ImpositionLayout) throws -> Data
}
```

- [ ] **Step 1: Failing tests** — booklet of 4 pages → 4 output pages (2-up × 2 sides); content still present (CI-safe extraction, gotcha (d)); output structurally sound.

```swift
func testBookletFourPagesProducesTwoUpSheets() throws {
    let src = /* 4-page fixture with distinguishable text via PDFium text draw or a known glyph */
    let out = try PDFImpositionEngine.impose(src, layout: .booklet)
    let doc = try XCTUnwrap(PDFDocument(data: out))
    XCTAssertEqual(doc.pageCount, 2)                       // 4 pages, 2-up, 1 sheet = 2 physical sides
    XCTAssertTrue(QPDFService.isStructurallySound(out))
    // content presence via FPDFText (NEVER PDFPage.string) — assert page-1 text non-empty
}
```

- [ ] **Step 2:** FAIL. **Step 3: Implement** inside `pdfiumLock.lock()/defer unlock()`:
  - `.nUp(rows, cols)`: `FPDF_LoadMemDocument` → read page-0 size via `FPDF_GetPageSizeByIndexF` (bind if needed, same style — it IS exported) → `imp_ImportNPagesToOne(src, outW, outH, cols, rows)` → save via the reused `FPDFCompression_SaveAsCopy` + a local `FPDFCompressionFileWrite` accumulator → `FPDF_CloseDocument` both.
  - `.booklet`: compute `ImpositionService.bookletPageOrder`; build a **reordered** intermediate doc with `imp_CreateNewDocument()` + `imp_ImportPages(dest, src, "<1-indexed range>", -1 append)` in booklet order (skip blanks or import a blank page for `-1`), then `imp_ImportNPagesToOne(reordered, 2*W, H, 2, 1)`.
  - Save accumulator pattern (local, since `fpdfCompressionSaveData` is private to the compression file):

```swift
final class ImpositionSaveSink { var data = Data() }
// FPDFCompressionFileWrite.writeBlock is @convention(c) — route via an unmanaged pointer in `parameter`
// is NOT available on this struct; instead follow PDFCompressionService's global-accumulator pattern:
// declare a file-private `var impositionSaveData = Data()` and reset it under the lock before saving.
```
  Reuse the exact save idiom from `PDFCompressionService` (grep `FPDFCompression_SaveAsCopy(` for the call + flags `1` = incremental? use `0`/`FPDF_NO_INCREMENTAL`). Gate output with `isStructurallySound`.
  - Then modify `WorkspaceViewModel.dataForPDFExport`: after `reducedData` is finalized, `if let layout = options.imposition { return try PDFImpositionEngine.impose(reducedData, layout: layout) }`. This guarantees imposition sees **baked** annotations already flattened into content.
- [ ] **Step 4:** `swift test` (full) + `swift build -c release`. **Step 5: Commit** — `feat: PDFium imposition engine wired after decoration bake`.

**Gotchas:** imposition AFTER bake+compress is load-bearing — imposing first drops all baked stamps/signatures/markup (N-up→XObject flatten). Booklet needs a real blank page for `-1` slots (create via `FPDFPage_New` on the reordered doc, or import a synthesized blank) so page count stays a multiple of 4. Watch output page dimensions: booklet sheet = `2*srcWidth × srcHeight` (landscape).

### Task J4: Export option + print n-up UI + L10n

**Files:**
- Modify: `Orifold/Views/ContentView.swift` (export sheet — add an "Imposition" picker: None / 2-up / Booklet / 4-up), `Orifold/ViewModels/WorkspaceViewModel.swift` (`printWorkspace()` :7765 — add an n-up print variant that imposes the print bytes before building the `NSPrintOperation` at :7790), `Orifold/Resources/Localizable.xcstrings`
- Test: `LocalizationCoverageTests` (new keys ×6)

- [ ] **Step 1:** Export picker bound to `WorkspaceExportOptions.imposition`. Print n-up: impose the export-data bytes, feed the imposed PDF into the existing print view before `NSPrintOperation`. Keys ×6: `imposition.label`, `.none`, `.twoUp`, `.booklet`, `.fourUp`, `.print.nup`. Coverage + RawLocalizationKeyLeak pass.
- [ ] **Step 2:** `swift test`; release build; **hands-on** (view-layer): export a 4-page doc as Booklet → open in Preview → page order/reading is correct; add a stamp first → confirm the stamp survives into the imposed output (bake-before-impose proof); print → n-up preview correct.
- [ ] **Step 3: Commit** — `feat: imposition export option + n-up print + localization`. Tick master Status row.

---

# Feature I — Attachments manager  *(code-only, ZERO new @_silgen_name bindings)*

**API decision (as required by the brief — "least new binding surface, say which and why"): use qpdf, not PDFium.** qpdf's C surface reaches everything through the existing `import CQPDF` module for **zero** new binding surface, versus PDFium's attachment API which would require ~7 net-new `@_silgen_name` bindings of an *experimental* API whose `FPDFDoc_DeleteAttachment` even leaves orphaned file data behind (per `fpdf_attachment.h` L48-52) and whose only save path is a full `FPDF_SaveAsCopy` re-serialization. Split by operation:
- **List + Extract:** `qpdf_oh_*` walk of `/Root/Names/EmbeddedFiles` + `qpdf_oh_get_stream_data` (qpdf-c.h:917) — clean in-memory byte read, no temp files, no stdout capture. The object shape is already known (sanitize touches this exact key at `QPDFService.swift:108`).
- **Add + Remove:** `qpdfjob_run_from_argv` with `--add-attachment` / `--remove-attachment=<key>` — qpdfjob builds/maintains the `/Filespec` + name-tree correctly and writes through qpdf's trusted structure-preserving writer (the same writer `QPDFService.optimized/sanitized` already rely on). Uses temp files (precedent: `PDFCompressionService.swift:121`).

Design: pure service (list/extract/add/remove on `Data`) → workspace byte integration + undo → Inspector tab UI → L10n.

### Task I1: AttachmentsService — list + extract (qpdf_oh surgery)

**Files:**
- Create: `Orifold/Engine/Attachments/AttachmentsService.swift`
- Test: `Tests/OrifoldTests/AttachmentsServiceTests.swift`

**Interfaces:**
```swift
struct PDFAttachment: Equatable { let name: String; let byteCount: Int; let mimeType: String? }
enum AttachmentsError: Error, Equatable { case invalidPDF, notFound, addFailed, removeFailed }
enum AttachmentsService {
    static func list(in data: Data, password: String? = nil) throws -> [PDFAttachment]
    static func extract(_ name: String, from data: Data, password: String? = nil) throws -> Data
}
```
- Consumes: the existing `withQPDF(_:description:password:)` lifecycle wrapper + `qpdf_get_root`, `qpdf_oh_has_key`/`qpdf_oh_get_key`, `qpdf_oh_get_array_n_items`/`qpdf_oh_get_array_item`, `qpdf_oh_get_utf8_value`, `qpdf_oh_get_stream_data` — all already imported via `CQPDF`. Reuse `QPDFService`'s private helpers (`hasKey`, `qpdf_oh_get_key` idioms) — extract/reuse rather than duplicate.

- [x] **Step 1: Failing tests.** Fixture: qpdf can't easily *create* an attachment in-test without the add path, so seed the fixture by running I2's add first (order I2 before I1's round-trip test), OR ship a tiny committed fixture PDF with one known embedded file. Minimal red test:

```swift
final class AttachmentsServiceTests: XCTestCase {
    func testListEmptyWhenNoAttachments() throws {
        let bare = PDFDocument(); bare.insert(PDFPage(), at: 0)
        XCTAssertEqual(try AttachmentsService.list(in: bare.dataRepresentation()!), [])
    }
    // round-trip lives in I2 (add -> list -> extract byte-identical)
}
```

- [x] **Step 2:** FAIL. **Step 3: Implement** `list` by walking the `/Names/EmbeddedFiles` name tree: the tree is either a flat `/Names` array of alternating `(name, filespec)` pairs or a `/Kids` subtree — handle both (recurse on `/Kids`). For each Filespec, read `/UF` (or `/F`) for the display name and `/EF /F` (the embedded-file stream) for `/Params /Size` (byte count) and `/Subtype` (MIME). `extract`: locate the matching Filespec, get its `/EF /F` stream `qpdf_oh`, call `qpdf_oh_get_stream_data(qpdf, streamOh, qpdf_dl_all, &filtered, &bufPtr, &len)` → copy into `Data(bytes:count:)` → free with the qpdf-provided buffer-free function. Throw `.notFound` if absent.
- [x] **Step 4:** PASS (with I2's round-trip). **Step 5: Commit** — `feat: list/extract embedded files via qpdf name-tree walk`.

**Gotchas:** name-tree may be nested under `/Kids` — do not assume a flat `/Names`. `qpdf_oh_get_stream_data` returns a **qpdf-allocated** buffer → copy immediately, then free with the documented `qpdf_..._free_buffer` (qpdf-c.h ~:934) — never `free()` it yourself. Password-protected members: thread `password` into `withQPDF`.

### Task I2: AttachmentsService — add + remove (qpdfjob argv)

**Files/Test:** same as I1.

**Interfaces (append):**
```swift
static func add(_ fileData: Data, name: String, mimeType: String?, to data: Data, password: String? = nil) throws -> Data
static func remove(_ name: String, from data: Data, password: String? = nil) throws -> Data
```

- [x] **Step 1: Failing tests** — full round-trip through the real path:

```swift
func testAddListExtractRoundTrip() throws {
    let base = { let d = PDFDocument(); d.insert(PDFPage(), at: 0); return d.dataRepresentation()! }()
    let payload = Data("hello-orifold".utf8)
    let withAtt = try AttachmentsService.add(payload, name: "note.txt", mimeType: "text/plain", to: base)
    let listed = try AttachmentsService.list(in: withAtt)
    XCTAssertEqual(listed.map(\.name), ["note.txt"])
    XCTAssertEqual(try AttachmentsService.extract("note.txt", from: withAtt), payload)   // byte-identical
    let removed = try AttachmentsService.remove("note.txt", from: withAtt)
    XCTAssertEqual(try AttachmentsService.list(in: removed), [])
    XCTAssertTrue(QPDFService.isStructurallySound(removed))
}
```

- [x] **Step 2:** FAIL. **Step 3: Implement** via temp files + `qpdfjob_run_from_argv`:
  - `add`: write `fileData` to a temp file; argv = `["qpdf", inTmp, outTmp, "--add-attachment", attTmp, "--key=\(name)", "--filename=\(name)", "--mimetype=\(mime)", "--"]` (the trailing `--` terminates the add-attachment sub-options). Read `outTmp` back.
  - `remove`: argv = `["qpdf", inTmp, outTmp, "--remove-attachment=\(name)"]`.
  - `qpdfjob_run_from_argv` returns a qpdf exit code: `0` success, `3` warnings (tolerate), `2` errors → throw `.addFailed`/`.removeFailed`. Clean up all temp files in `defer`. Gate `outTmp` bytes with `isStructurallySound`.
- [x] **Step 4:** PASS + full `swift test`. **Step 5: Commit** — `feat: add/remove embedded files via qpdfjob`.

**Gotchas:** build the C `argv` as a null-terminated `[UnsafeMutablePointer<CChar>?]` and free each `strdup`'d string after the call. `--key` must be unique — qpdf refuses a duplicate key (mirror `FPDFDoc_AddAttachment`'s "empty or existing name → no-op"): pre-check via `list` and disambiguate. Filenames with spaces/Unicode: qpdf handles UTF-8 argv, but sanitize path separators out of `name`.

### Task I3: Workspace integration (bytes + undo + sanitize/export regression)

**Files:**
- Modify: `Orifold/ViewModels/WorkspaceViewModel.swift`
- Test: `Tests/OrifoldTests/AttachmentsServiceTests.swift` (view-model level)

**Interfaces:**
```swift
func addAttachment(_ fileURL: URL) ; func removeAttachment(named: String) ; func extractAttachment(named: String, to url: URL)
```
mutating the active member's preserved bytes, named undo, `structureRevision` bump, `rebuild()` — mirror `applyOCRResult` (:2327) exactly (set `document.memberPDFData[id]`, reset `originalMemberPDFData[id]` pristine base, `invalidatePageInspection`, undo registered INSIDE its group with `setActionName`).

- [x] **Step 1:** Study `applyOCRResult` (:2327) for the byte-swap + pristine-base reset discipline. **Step 2: Failing test** — add to a one-member workspace, assert `AttachmentsService.list` on the member's current bytes returns it, `undoManager.canUndo`, undo restores empty. **Step 3: Implement** following that precedent; extract uses `NSSavePanel` + writes the bytes with an `NSURL` **quarantine** attribute (untrusted content from an arbitrary PDF). **Step 4:** Also add the **export regression test** — attachments must survive `dataForPDFExport` (historical bug: export paths bypassing gates); and a **sanitize interaction test** — `sanitized(removingMetadata:)` still strips ALL attachments (:108 unchanged). **Step 5: Commit** — `feat: attachments flow through preserving pipeline with undo`.

**Gotchas:** quarantine the extracted file (`kLSQuarantineTypeKey`). Attachments must round-trip through the export bake path — add the regression test, don't assume. Encrypted members lacking a stored password: disable add/remove, surface a hint.

### Task I4: Inspector "Attachments" tab UI + L10n

**Files:**
- Modify: `Orifold/Views/InspectorView.swift` (add `case attachments = "Attachments"` to `Tab` :13, `iconName` = `"paperclip"` :21, `titleKey` = `"inspector.tab.attachments"` :35, + the tab body view), `Orifold/Resources/Localizable.xcstrings`

- [x] **Step 1:** New tab: list rows (name, size via `ByteCountFormatter`, MIME); drag-in a file to add; per-row Extract (NSSavePanel) / Remove. Keys ×6: `inspector.tab.attachments`, `attachments.empty`, `attachments.add`, `attachments.extract`, `attachments.remove`, `attachments.dropHint`, `attachments.encrypted.disabled`. Coverage + RawLocalizationKeyLeak pass.
- [x] **Step 2:** `swift test`; **hands-on**: drag a .txt in → row appears → export → reopen exported file in Preview → attachment present; Extract writes byte-identical file; Remove + undo works.
- [x] **Step 3: Commit** — `feat: attachments inspector tab + localization`. Tick master Status row.

---

# Feature K — Scan cleanup ("Scan mode")  *(code-only, ZERO new @_silgen_name bindings)*

Design: **quality spike FIRST**, then pure image ops (`ScanCleanup`) → page-clean pipeline (reuse the rasterizer) → apply-as-replacement (rebuild page as image-PDF, byte-swap like `applyOCRResult`) → sheet UI. No PDFium image-object surgery: replacing the whole page with a cleaned single-image page is more robust than `FPDFImageObj_SetBitmap` (which assumes the page is exactly one full-bleed image) and needs no binding.

### Task K1: ScanCleanup — pure image operations

**Files:**
- Create: `Orifold/Engine/ScanCleanup/ScanCleanup.swift`
- Test: `Tests/OrifoldTests/ScanCleanupTests.swift`

**Interfaces:**
```swift
struct ScanCleanupOptions: Equatable { var deskew = true; var binarize = true; var despeckle = true }
enum ScanCleanup {
    static func detectDocumentQuad(_ image: CGImage) -> [CGPoint]?          // Vision corners, normalized
    static func deskewAndCrop(_ image: CGImage, to quad: [CGPoint]) -> CGImage
    static func binarize(_ image: CGImage) -> CGImage                       // adaptive threshold -> 1-bpp-ish
    static func clean(_ image: CGImage, options: ScanCleanupOptions) -> CGImage
    static func estimateSkewAngle(_ image: CGImage) -> CGFloat              // for the test oracle
}
```
- `detectDocumentQuad`: `VNDetectDocumentSegmentationRequest` (macOS 12+, **no `#available` gate needed** — target is 14) → `results` is `[VNRectangleObservation]`; take the top observation's `topLeft/topRight/bottomLeft/bottomRight` (normalized). Mirror the request/handler setup in `PDFOCRService` (`VNImageRequestHandler`).
- `deskewAndCrop`: perspective-correct via `CIFilter.perspectiveCorrection()` using the four corner points.
- `binarize`: grayscale + adaptive threshold via vImage (`vImageConvert_*` to Planar8, box-blur local mean, threshold) — or `CIColorControls` contrast + `CIColorMonochrome`/threshold. Despeckle: small median (`vImageMax/Min` or `CIMedianFilter`).

- [ ] **Step 1: Failing tests** on synthetic fixtures (pure, deterministic):

```swift
final class ScanCleanupTests: XCTestCase {
    func testDeskewRecoversKnownAngle() throws {
        let skewed = /* render a black rect on white, rotated +7° */
        let corrected = ScanCleanup.clean(skewed, options: .init(deskew: true, binarize: false, despeckle: false))
        XCTAssertLessThan(abs(ScanCleanup.estimateSkewAngle(corrected)), 1.5, "deskew within tolerance")
    }
    func testBinarizeProducesTwoTone() {
        let gray = /* 50%-gray gradient fixture */
        let bw = ScanCleanup.binarize(gray)
        // sample pixels -> assert each is near-black or near-white (bimodal), few mid-tones
    }
}
```

- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS. **Step 5: Commit** — `feat: scan-cleanup image ops (deskew/binarize/despeckle)`.

**Gotchas:** Vision corners are normalized + **y-flipped** vs CGImage — convert carefully. Without Leptonica (only bundled if Feature H's jbig2 lands — it did NOT this wave), despeckle is **vImage-only**; keep it modest. Binarize output is a 1-bpp-equivalent grayscale CGImage (true 1-bpp packing only matters once JBIG2 exists).

### Task K2: Expose rasterizer + page-clean pipeline (+ quality spike)

**Files:**
- Modify: `Orifold/Engine/PDFOCRService.swift` (widen `renderedImage(for:)` :277 from `private static` to `static`)
- Create: `Orifold/Engine/ScanCleanup/ScanCleanupPipeline.swift`
- Test: `Tests/OrifoldTests/ScanCleanupTests.swift` (append)

**Interfaces:**
```swift
enum ScanCleanupPipeline {
    static func cleanedImage(for page: PDFPage, options: ScanCleanupOptions) -> CGImage?   // rasterize -> clean
}
```

- [ ] **Step 1: The spike IS the test** (roadmap gotcha): one skewed/shadowed scanned fixture page → `cleanedImage` → run `PDFOCRService.makeSearchable`-style OCR on both original and cleaned → assert **OCR confidence(cleaned) ≥ confidence(original)**. If it regresses, stop and rethink params before any UI.
- [ ] **Step 2:** FAIL. **Step 3:** Implement (reuse `renderedImage(for:)` now internal; feed into `ScanCleanup.clean`). **Step 4:** PASS. **Step 5: Commit** — `feat: page scan-cleanup pipeline + OCR-uplift spike`.

**Gotcha:** if the widen of `renderedImage` collides with Wave 2 G3 (which may have already exposed it), re-grep and skip the redundant edit.

### Task K3: Apply-as-replacement flow (rebuild page, byte-swap, undo)

**Files:**
- Modify: `Orifold/ViewModels/WorkspaceViewModel.swift`
- Test: `Tests/OrifoldTests/ScanCleanupTests.swift` (view-model level)

**Interfaces:**
```swift
func applyScanCleanup(pageRefIDs: [String], options: ScanCleanupOptions)   // per-page or whole-doc
```

- [ ] **Step 1:** Study `applyOCRResult` (:2327) and the images→PDF lane `PDFKitEngine.renderImage(_:title:)` (:1031). **Step 2: Failing test** — apply to a scanned fixture page: assert the member's new bytes pass `isStructurallySound`, page count unchanged, undo restores original bytes (pristine-base preserved). **Step 3: Implement**: for each target page, build a single-image PDF page from `ScanCleanupPipeline.cleanedImage` (mirror `renderImage`), splice it in place of the original page in the member bytes, then swap member bytes + reset pristine base + named undo + `rebuild()` — exactly the `applyOCRResult` discipline. **Step 4:** `swift test`. **Step 5: Commit** — `feat: apply scan cleanup as page replacement with undo`.

**Gotchas:** keep original bytes for undo via the existing pristine-base mechanism (do NOT lose the pre-clean scan). Replacing a page must preserve page dimensions/rotation. This is a **lossy raster replacement** — the UI copy must say so (K4).

### Task K4: "Clean up scan…" sheet UI + L10n

**Files:**
- Create: `Orifold/Views/ScanCleanupSheet.swift`
- Modify: `Orifold/Views/ContentView.swift` (More menu entry), `Orifold/Resources/Localizable.xcstrings`

- [ ] **Step 1:** Sheet: before/after preview, deskew/binarize/despeckle toggles, scope = this page / whole document, Apply. Keys ×6: `scanCleanup.title`, `.deskew`, `.binarize`, `.despeckle`, `.scope.page`, `.scope.document`, `.apply`, `.lossyWarning` ("Replaces the page with a cleaned image — editable text on this page will be rasterized."). Coverage + RawLocalizationKeyLeak pass.
- [ ] **Step 2:** `swift test`; release build; **hands-on**: open a skewed scan → Clean up scan → before/after preview updates → Apply → page deskewed/cleaned; undo restores; OCR after cleanup reads better.
- [ ] **Step 3: Commit** — `feat: scan cleanup sheet + localization`. Tick master Status row.

---

# Feature H — Compression pack v2  🚫 **BLOCKED (binary rebuild) — app-side wiring only this wave**

> **BLOCKED RATIONALE (do not attempt the binary headless):** The zopfli toggle, mozjpeg recompression, and JBIG2 all require rebuilding `Packages/QPDFBinary/QPDF.xcframework` **from qpdf source** as a **universal (`arm64`+`x86_64`) static lib**, plus vendoring a **net-new** `jbig2enc`+`leptonica` static lib. `nm` confirms today's `libQPDF.a` has zopfli **hooks but no zopfli library** (no `ZopfliDeflate/Compress/Init` symbols), libjpeg-turbo (not mozjpeg), and **zero** jbig2 symbols. There is **no qpdf build script in-repo** (only the prebuilt artifact + a `binaryTarget` `Package.swift`). A from-source cross-compiled static-lib rebuild with native crypto and the empty-doc/encrypted-PDF exemptions is not something an agent can reliably produce and verify headless. **Per the user's skip-if-blocked decision: document the recipe (H0), ship the inert-safe app toggle (H1/H2), and hand the binary to a human ops task.**

### Task H0 — (BLOCKED, ops task — DOCUMENT ONLY, do not execute)

Recorded recipe for whoever rebuilds the binary later:
1. **qpdf** (vendored 12.3): `cmake -DZOPFLI=ON -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DBUILD_SHARED_LIBS=OFF -DREQUIRE_CRYPTO_NATIVE=ON …` with zopfli dev headers/lib present. `-DZOPFLI=ON` is off by default; qpdf ≥ 11.10 supports it. Runtime trigger is the **`QPDF_ZOPFLI` environment variable** (any value other than `disabled` enables it) — there is no C-API write-param, so the app wires the **env var** (H1). Package the result back into `QPDF.xcframework/macos-arm64_x86_64/libQPDF.a` keeping the current `Headers/` + `module.modulemap`.
2. **mozjpeg** (IJG/BSD-3/zlib): build static, substitute for libjpeg-turbo inside the same link.
3. **jbig2enc v0.32 (Apache-2.0) + Leptonica (BSD-2):** new `Packages/JBIG2Binary` xcframework; **lossless generic mode only, never symbol mode** (character-substitution hazard); splice 1-bpp streams via qpdf stream replacement.
4. **Verify:** `swift build -c release` AND CI both link the new xcframework; keep the empty-document/encrypted-PDF exemptions the original 2026-07-04 qpdf merge fixed; add THIRD-PARTY-NOTICES entries for zopfli/mozjpeg/jbig2enc/Leptonica in the same commit.
5. When landed, flip H1's test from "produces a valid PDF" to "≤ baseline size", and unblock the JBIG2/mozjpeg passes.

### Task H1: App-side wiring — `.maximum` preset + `QPDF_ZOPFLI` env (inert-safe)

**Files:**
- Modify: `Orifold/Models/WorkspaceExportOptions.swift` (add `case maximum` to `PDFCompressionPreset` :42, with its own `dpiCap`/`jpegQuality` + `label` key), `Orifold/Engine/QPDFService.swift` (in `optimized(_:linearize:)` :40 — or a new `maximumOptimized` — `setenv("QPDF_ZOPFLI", "1", 1)` around the write when max is requested), `Orifold/Engine/PDFCompressionService.swift` (thread the preset so `.maximum` routes through the zopfli-env optimize pass)
- Test: `Tests/OrifoldTests/PDFCompressionServiceTests.swift` (or the existing compression test file)

**Interfaces:** `PDFCompressionPreset.maximum` (label `pdfCompressionPreset.maximum.label` = "Maximum (slow)").

- [ ] **Step 1: Failing test** (inert-safe — assert *validity*, NOT smaller-size, because zopfli is a no-op until the binary ships):

```swift
func testMaximumPresetProducesValidPDF() throws {
    let src = /* small multi-image fixture */
    let result = try PDFCompressionService.reduceFileSize(of: src, preset: .maximum)
    XCTAssertTrue(QPDFService.isStructurallySound(result.data))     // valid today; ≤ baseline once binary lands
    XCTAssertGreaterThan(PDFDocument(data: result.data)?.pageCount ?? 0, 0)
}
```

- [ ] **Step 2:** FAIL (no `.maximum`). **Step 3: Implement.** Add the case; in the qpdf optimize pass set the env var before `write` and unset after (so it can't leak into unrelated qpdf calls). Because `Pl_Flate::zopfli_supported()` returns false in today's lib, qpdf silently ignores it → **safe no-op**, exactly the "ready when the binary lands" wiring the brief asks for. **Step 4:** PASS + full `swift test`. **Step 5: Commit** — `feat: maximum-compression preset wiring (zopfli env, inert until binary rebuild)`.

**Gotchas:** `setenv` is process-global — set it immediately before the specific write and restore prior state after; never leave it set. Do NOT assert size reduction in CI (would fail until the binary ships). Add a code comment pointing at H0.

### Task H2: Export UI "Maximum compression" toggle + L10n

**Files:**
- Modify: `Orifold/Views/ContentView.swift` (export sheet — surface `.maximum` in the compression picker with a "slow" caption), `Orifold/Resources/Localizable.xcstrings`

- [ ] **Step 1:** Add the `.maximum` option to the export compression picker (it already binds `WorkspaceExportOptions.compressionPreset`). Keys ×6: `pdfCompressionPreset.maximum.label` ("Maximum (slow)"), `pdfCompressionPreset.maximum.caption` ("Smallest files; much slower. Extra shrink activates after the next engine update."). Coverage + RawLocalizationKeyLeak pass.
- [ ] **Step 2:** `swift test`; **hands-on**: export with Maximum → produces a valid PDF (size parity today is expected). **Step 3: Commit** — `feat: maximum compression export option + localization`.

---

## Wave 3 close-out

- [ ] Bump version (coordinate with whatever `main`/`project.yml`/`Package.swift` say today; Wave 1/2 already bumped) + write `docs/release-vX.Y.Z.md` in the existing format.
- [ ] `swift build -c release` (silgen/WMO — **J adds bindings**) + full `swift test`.
- [ ] Delete stale local `Orifold.app` copies (`mdfind` sweep), install fresh, click through J/I/K (H is inert — just confirm the option renders + exports validly).
- [ ] Tick Wave 3 rows in `docs/FEATURE_WAVES_MASTER_PLAN.md`; note in the Status table that **H is app-wiring-only, binary rebuild deferred to ops task H0**. Refresh `docs/OPEN_SOURCE_FEATURE_ROADMAP.md` item #11 to reflect the BLOCKED-binary finding.
- [ ] Hold pushes (recovery branch) unless instructed.

## Sources (external facts verified)

- qpdf zopfli build/runtime: [qpdf installation docs](https://qpdf.readthedocs.io/en/stable/installation.html), [qpdf #1323 "compile with zopfli"](https://github.com/qpdf/qpdf/issues/1323) — `-DZOPFLI=ON` (off by default, qpdf ≥ 11.10), runtime via `QPDF_ZOPFLI` env, ~100× slower.
- Vision segmentation: [VNDetectDocumentSegmentationRequest](https://developer.apple.com/documentation/vision/vndetectdocumentsegmentationrequest) — macOS 12+, results are `[VNRectangleObservation]` with normalized corner points.
