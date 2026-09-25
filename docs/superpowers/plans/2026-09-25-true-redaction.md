# True Redaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Redact tool that marks regions and permanently removes the text, image pixels and
annotations under them from every byte lane, then burns in black boxes.

**Architecture:** `RedactionEngine` (PDFium edit stage → qpdf XObject-prune stage → PDFium
verification) is a pure `Data -> Data` transform. `WorkspaceViewModel.applyRedactions()`
runs it through `mutateMemberBytes`, so all lanes change atomically in one undo step. The UI
reuses the comment-region drag overlay, the page decoration overlay, and a `ScanBar`-style bar.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, PDFium (`@_silgen_name`), qpdf C API, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-25-true-redaction-design.md`

## Global Constraints

- macOS 14 deployment target; no new dependencies.
- Every PDFium call holds `pdfiumLock` with per-call `FPDF_InitLibrary`/`FPDF_DestroyLibrary`.
- New `@_silgen_name` bindings: `red_` prefix. **The Swift signature must match
  byte-for-byte any other app-target binding of the same C symbol**, and it must pass
  `swift build -c release`.
- `FPDFPage_GenerateContent` needs `poeTouchPathColorsForGenerateContent(page)` first.
- Every user-facing string goes through `L10n` with all 6 languages (en, es, fr, hi, ja,
  zh-Hans). Append xcstrings keys, never re-sort the file.
- Never assert on `PDFPage.string`. Read text via
  `PDFTextAnalysisEngine.readingOrderText(data:pageIndex:)`.
- XCTest only, and one new file per test subject.

---

### Task 1: RedactionEngine: text, annotations, burn-in, verification

**Files:**
- Create: `Orifold/Engine/Redaction/RedactionEngine.swift`
- Test: `Tests/OrifoldTests/RedactionEngineTests.swift`

**Interfaces:**
- Produces: `RedactionEngine.redact(_ data: Data, regions: [Int: [CGRect]]) throws -> Data`,
  plus `RedactionEngine.Failure` (`unreadableDocument`,
  `formFieldInRegion(pageIndex:)`, `writeFailed`, `verificationFailed(pageIndex:)`).

- [ ] **Step 1: Write the failing tests.** Fixtures are built with `EditingFixturePDFBuilder`
  (US Letter, y-up):
  - `testTextUnderRegionIsRemovedAndTextElsewhereSurvives`: runs "SECRET" at (72,700) and
    "KEEPME" at (72,400). Region `CGRect(x: 60, y: 690, width: 200, height: 30)`. After
    redaction, the reading-order text lacks "SECRET" and still contains "KEEPME".
  - `testRegionIsBurnedInBlack`: the output renders dark in the region's center (PDFKit
    thumbnail sample < 0.2 luminance) and light in an empty area.
  - `testPartiallyCoveredLineKeepsItsVisibleNeighboursAsPixels`: one run "Alpha SECRET
    Omega", with the region over "SECRET" only. "SECRET" is gone from the text, and ink still
    renders over "Alpha".
  - `testIntersectingAnnotationIsRemovedAndOthersSurvive`: two PDFKit `.square` annotations,
    one inside and one outside. Afterwards PDFKit sees exactly 1 annotation.
  - `testFormFieldInRegionIsRefused`: a `.widget` text-field annotation inside the region.
    `XCTAssertThrowsError`, with the error equal to `.formFieldInRegion(pageIndex: 0)`.
  - `testRotatedPageIsRedactedInUserSpace`: `makePDF(runs:…, rotation: 90)` with the same
    "SECRET" region. The text is gone.
  - `testEmptyRegionsReturnInputUnchanged`.
- [ ] **Step 2:** `swift test --filter RedactionEngineTests`. Expect a compile failure
  (`RedactionEngine` undefined).
- [ ] **Step 3: Implement the engine.** Bindings:

  ```swift
  @_silgen_name("FPDF_RenderPageBitmap")
  private func red_RenderPageBitmap(_ bitmap: OpaquePointer?, _ page: OpaquePointer?, _ startX: Int32,
                                    _ startY: Int32, _ sizeX: Int32, _ sizeY: Int32, _ rotate: Int32, _ flags: Int32)
  @_silgen_name("FPDFBitmap_Create")
  private func red_BitmapCreate(_ width: Int32, _ height: Int32, _ alpha: Int32) -> OpaquePointer?
  @_silgen_name("FPDFBitmap_FillRect")
  private func red_BitmapFillRect(_ bitmap: OpaquePointer?, _ left: Int32, _ top: Int32,
                                  _ width: Int32, _ height: Int32, _ color: UInt) -> Int32
  @_silgen_name("FPDF_GetPageBoundingBox")
  private func red_GetPageBoundingBox(_ page: OpaquePointer?, _ rect: UnsafeMutablePointer<POEFSRect>?) -> Int32
  @_silgen_name("FPDFPageObj_NewImageObj")
  private func red_NewImageObj(_ document: OpaquePointer?) -> OpaquePointer?
  @_silgen_name("FPDFImageObj_SetBitmap")   // identical to PDFCompressionService's binding
  private func red_ImageSetBitmap(_ pages: UnsafeMutablePointer<OpaquePointer?>?, _ count: Int32,
                                  _ imageObject: OpaquePointer?, _ bitmap: OpaquePointer?) -> Int32
  @_silgen_name("FPDFPageObj_CreateNewRect")
  private func red_CreateNewRect(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> OpaquePointer?
  @_silgen_name("FPDFPath_SetDrawMode")
  private func red_PathSetDrawMode(_ path: OpaquePointer?, _ fillMode: Int32, _ stroke: Int32) -> Int32
  @_silgen_name("FPDFPage_InsertObject")
  private func red_InsertObject(_ page: OpaquePointer?, _ object: OpaquePointer?) -> Int32
  @_silgen_name("FPDFAnnot_GetSubtype")
  private func red_AnnotGetSubtype(_ annotation: OpaquePointer?) -> Int32
  @_silgen_name("FPDFAnnot_GetRect")
  private func red_AnnotGetRect(_ annotation: OpaquePointer?, _ rect: UnsafeMutablePointer<POEFSRect>?) -> Int32
  // FPDFText_* identical to PDFTextAnalysisEngine's private bindings:
  @_silgen_name("FPDFText_LoadPage") private func red_TextLoadPage(_ page: OpaquePointer?) -> OpaquePointer?
  @_silgen_name("FPDFText_ClosePage") private func red_TextClosePage(_ textPage: OpaquePointer?)
  @_silgen_name("FPDFText_CountChars") private func red_TextCountChars(_ textPage: OpaquePointer?) -> Int32
  @_silgen_name("FPDFText_GetCharBox")
  private func red_TextGetCharBox(_ textPage: OpaquePointer?, _ index: Int32, _ left: UnsafeMutablePointer<Double>?,
                                  _ right: UnsafeMutablePointer<Double>?, _ bottom: UnsafeMutablePointer<Double>?,
                                  _ top: UnsafeMutablePointer<Double>?) -> Int32
  ```

  Reused from `PDFiumObjectBindings`: `poe_LoadPage`, `poe_ClosePage`,
  `poe_Get/SetPageRotation`, `poe_CountObjects`, `poe_GetObject`, `poe_GetType`,
  `poe_GetBounds`, `poe_GetMatrix`, `poe_SetMatrix`, `poe_RemoveObject`, `poe_Destroy`,
  `poe_SetFillColor`, `poe_GetAnnotationCount`, `poe_GetAnnotation`,
  `poe_CloseAnnotation`, `poe_RemoveAnnotation`, `poe_GenerateContent`,
  `poe_BitmapGetBuffer`, `poe_BitmapGetStride` and `poe_BitmapDestroy`, plus
  `PDFObjectEditEngine.saveAsCopy`.

  Algorithm (`redactPage`):
  1. Collect the annotation indices whose rects intersect a region, and throw on subtype 20
     (Widget).
  2. Build a `PageSnapshot`. Read the page bbox, temporarily set rotation 0, render BGRx at
     `min(3, 6000/maxSide)` over a white fill with flags 0, restore rotation, then
     `FillRect` each region black.
     Mapping: `px = (x - box.minX) * s`, `py = (box.maxY - y) * s`.
  3. Walk objects from `count-1` down to `0`, handling each whose bounds intersect a region:
     - path or shading: remove only when wholly inside one region.
     - image: remove when wholly inside. Otherwise black out its pixels (Task 2). Task 1
       uses the remove-plus-patch fallback.
     - everything else: remove, and add a patch unless wholly inside.
     Removal is `poe_RemoveObject` followed by `poe_Destroy`, and a failed removal throws
     `.writeFailed`. A patch is a snapshot crop placed as a new image object with the matrix
     `(w, 0, 0, h, x, y)`.
  4. Remove the collected annotations in reverse order, then insert the patches.
  5. For each region, insert a black filled rect (`fillMode 2`, `stroke 0`).
  6. Run `poeTouchPathColorsForGenerateContent`, then `poe_GenerateContent`.

  Then `saveAsCopy` and verify: reload, and fail if any `FPDFText_GetCharBox` intersects a
  region inset by 0.5 pt.
- [ ] **Step 4:** `swift test --filter RedactionEngineTests`. All pass.
- [ ] **Step 5:** Commit `feat(redaction): PDFium redaction engine for text and annotations`.

### Task 2: Images and resource pruning (no leftover bytes)

**Files:**
- Modify: `Orifold/Engine/Redaction/RedactionEngine.swift`
- Test: `Tests/OrifoldTests/RedactionEngineTests.swift`

**Interfaces:**
- Produces: `RedactionEngine.prunedUnusedXObjects(_ data: Data, pageIndices: Set<Int>) -> Data?`
  (internal, so tests can call it)

- [ ] **Step 1: Failing tests.** The fixture is a CG-drawn 200×200 red image at (100,300),
  with text elsewhere.
  - `testPartiallyCoveredImageIsBlackedOnlyUnderTheRegion`: region over its left half.
    Afterwards the page's `/Resources/XObject` holds exactly one image, and a render shows
    dark on the left half and red on the right half.
  - `testFullyCoveredImageLeavesNoXObjectBehind`: region covering the whole image. The
    XObject count is 0, read through `QPDFService.withQPDF`.
- [ ] **Step 2:** Run. Both fail: the fallback leaves a patch image and PDFium leaves the
  removed XObject in `/Resources`.
- [ ] **Step 3: Implement.**
  - `blackOutPixels(of:under:)`: get the object matrix and invert it. Map each region's
    corners to pixel space (`col = u*W`, `row = (1-v)*H`) and take the bounding box,
    clamped. Zero the color bytes by format (Gray 1 byte, BGR 3, BGRx/BGRA 4, with alpha
    set to 255), then `red_ImageSetBitmap(nil, 0, image, bmp)`. Return `false` on any failure,
    which falls back to remove plus patch.
  - `prunedUnusedXObjects`:
    1. `qpdf_push_inherited_attributes_to_page`.
    2. On each redacted page, read the content with `qpdf_oh_get_page_content_data` and
       tokenize names with the regex `/[^\s/\[\]<>(){}%]+`, decoding `#xx`.
    3. Rebuild `/Resources` as a new dictionary, copy-on-write, so shared dictionaries stay
       intact. Its `/XObject` keeps only the used names.
    4. `QPDFService.write` drops everything unreachable.
  - `redact` becomes: PDFium stage → prune → verify (verification runs on the pruned bytes).
- [ ] **Step 4:** Run the whole `RedactionEngineTests` suite. All pass.
- [ ] **Step 5:** Commit `feat(redaction): black out image pixels and prune orphaned XObjects`.

### Task 3: View model workflow

**Files:**
- Modify: `Orifold/ViewModels/WorkspaceViewModel.swift` (new `// MARK: - Redaction` next
  to the page operations)
- Modify: `Orifold/Resources/Localizable.xcstrings` (status and undo keys, all 6 languages)
- Test: `Tests/OrifoldTests/RedactionWorkflowTests.swift`

**Interfaces:**
- Consumes: `RedactionEngine.redact`
- Produces:
  - `struct RedactionMark: Identifiable, Equatable { var id: UUID; var pageRefID: UUID; var rect: CGRect }`
  - `private(set) var pendingRedactions: [RedactionMark]`
  - `@discardableResult func addRedactionMark(rect: CGRect, on page: PDFPage, in pdfDocument: PDFDocument?) -> UUID?`
  - `func addRedactionMark(rect: CGRect, pageRefID: UUID)` (a test seam, also used by the
    first overload)
  - `func removeRedactionMark(id: UUID)`
  - `func clearRedactionMarks()`
  - `@discardableResult func applyRedactions() -> Bool`

- [ ] **Step 1: Failing tests.** The workspace is built from `WorkspaceDocument(testingFile:)`
  as in `PageCropTests`, with an `UndoManager` attached.
  - `testApplyRemovesTextFromLiveBytes`
  - `testUndoRestoresAndRedoRemovesAgain`
  - `testPageWithTextEditOperationsIsRefusedAndBytesUnchanged`: append a `PageEditState`
    with one operation.
  - `testIntersectingCommentSnippetIsScrubbed`
  - `testSourcePayloadIsDroppedForRedactedMember`: a Markdown import like
    `makeMarkdownViewModel`.
  - `testRedactionSurvivesObjectReplayFromBaseLanes`: a two-page fixture. Redact page 1,
    then apply an object edit on page 2. Page 1's text is still gone from the live bytes.
  - `testMarkUndoRemovesMark`
- [ ] **Step 2:** Run. Compile fails.
- [ ] **Step 3: Implement.** Mirror `applyPageCrop`, as in spec §2. Keys: `undo.markRedaction`,
  `undo.applyRedactions`, `status.redaction.applied`, `status.redaction.failed`,
  `status.redaction.formField`, `status.redaction.editConflict`.
- [ ] **Step 4:** Run `RedactionWorkflowTests` and `LocalizationCoverageTests`. All pass.
- [ ] **Step 5:** Commit `feat(redaction): mark and apply redactions across byte lanes`.

### Task 4: UI

**Files:**
- Modify: `Orifold/ViewModels/WorkspaceViewModel.swift` (`AnnotationTool.redact`: label,
  icon, help, and flags)
- Modify: `Orifold/Views/ContentView.swift` (add `.redact` to the eraser tool group)
- Modify: `Orifold/Views/ReadingCanvas.swift`:
  - the region overlay shows for `.redact`, and the commit dispatches on the tool
  - `PageDecorationOverlayView` draws the marks
  - `RedactionBar` with a confirmation alert
- Modify: `Orifold/Resources/Localizable.xcstrings` (tool, bar and confirm keys)

- [ ] **Step 1:** Add the enum case and fix every `switch`. The compiler lists them.
- [ ] **Step 2:** Wire the overlay: `isHidden = !(tool == .commentRegion || tool == .redact)`.
  In `onRegionCommitted`, `.redact` calls `viewModel.addRedactionMark`.
- [ ] **Step 3:** Draw the marks in `PageDecorationOverlayView.draw`: red at 0.18 alpha fill,
  plus a red 1.5 pt dashed stroke. Use the same page→view conversion as the decoration
  drawing.
- [ ] **Step 4:** Add a `RedactionBar` (count, Clear, Apply…) shown when
  `!viewModel.pendingRedactions.isEmpty`. Its `.alert` has a destructive **Redact** button
  and states the v1 limits.
- [ ] **Step 5:** Run `swift build`, `LocalizationCoverageTests`, `RawLocalizationKeyLeakTests`
  and `swiftlint lint --quiet`.
- [ ] **Step 6:** Commit `feat(redaction): Redact tool, mark overlay, and apply bar`.

### Task 5: Ship gate

- [ ] `swift build -c release` (new silgen bindings)
- [ ] Full `swift test`
- [ ] `xcodegen generate`, if a new folder needs it. `git diff --exit-code` on the
  generated files must pass.
- [ ] Docs:
  - README: move real redaction out of the roadmap and into the features table and beta
    note
  - CONTEXT.md: add a **Redaction** glossary entry
  - Count sync (`README.md` in 3 spots, `docs-site/src/data/stats.json`) per
    `docs-site/AGENTS.md`
- [ ] Hands-on: launch the app, redact a sample line, export, and confirm the text isn't
  selectable.
- [ ] Merge to main, then push.
