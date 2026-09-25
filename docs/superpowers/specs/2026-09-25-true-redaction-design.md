# True Redaction — Design

**Date:** 2026-09-25 · **Status:** approved (chat, 2026-09-25) · **Roadmap:** README "Real redaction"

## Goal

Let a user mark rectangular regions and permanently remove what is under them. The text,
image pixels and annotations in each region are deleted from the PDF's object graph, not
just covered, and a black box is burned in. The removal reaches every stored copy of the
bytes, so neither save, export, nor a later replay can bring the content back.

## Non-goals and v1 limits (all disclosed in the confirm dialog)

- **Not scrubbed:** document metadata, bookmark titles, and structure-tree `/Alt` /
  `/ActualText`. The dialog points to *Sanitize* on export for metadata.
- **Collateral rasterization:** PDFium can only delete a whole text object, which is
  usually a line or a run. Words in the same object outside the region are kept as an
  image patch, not as text. They stay visible but can't be selected or searched. OCR can
  restore them.
- **Vector paths partly under a region** stay in the content and are covered by the black
  box. Paths fully inside a region are deleted.
- **Refused, not handled:** pages with pending inline text edits or object edits (replay
  would re-add their strings), and regions that touch a form-field widget (the field value
  lives in `/AcroForm`, outside the page). The user gets a specific message.
- Marks are session-only and aren't persisted in the workspace file.

## Architecture

### 1. `RedactionEngine` — `Orifold/Engine/Redaction/RedactionEngine.swift`

```swift
enum RedactionEngine {
    enum Failure: Error, Equatable {
        case unreadableDocument, formFieldInRegion(pageIndex: Int),
             writeFailed, verificationFailed(pageIndex: Int)
    }
    /// regions: member-local page index → rects in PDF user space (PDFKit page space).
    static func redact(_ data: Data, regions: [Int: [CGRect]]) throws -> Data
}
```

It runs under `pdfiumLock` with per-call init and destroy, like every PDFium caller. Per
page:

1. **Refuse widgets.** If any `Widget` annotation's rect intersects a region, throw
   `.formFieldInRegion`.
2. **Snapshot pixels.** Render the page (rotation temporarily set to 0, no annotations)
   into a BGRA bitmap at 3× (longest side capped at 6000 px). Paint every region black in
   the bitmap. This is the patch source.
3. **Walk the top-level page objects** in reverse index order so removals don't shift
   pending indices. For each object whose bounds intersect a region:
   - **text / form XObject:** remove it. Unless its bounds sit wholly inside one
     region, insert an image patch cropped from the snapshot at its bounds.
   - **image:** wholly inside → remove it. Otherwise get its bitmap, map each region
     through the inverse image matrix into pixel space (axis-aligned bounding box, which
     errs toward more black), zero those pixels, and `SetBitmap`.
   - **path / shading:** remove only when wholly inside a region. (Large background fills and
     gradients would otherwise rasterize whole pages.)
No separate orphan pass. Tests showed that `GenerateContent` rewrites the page's
`/Resources` with only what the new content uses (inherited `/Pages` resources included),
and `SaveAsCopy` writes only reachable objects. `RedactionEngineTests` scans every stream in
the output (literal and hex text, and image count and width) to hold that line.

Bindings reuse the `poe_*` set. New symbols use a `red_` prefix, with signatures matching
any existing binding of the same symbol byte for byte (the release-build silgen rule).

### 2. View model — `WorkspaceViewModel` (new `// MARK: - Redaction`)

- `struct RedactionMark: Identifiable, Equatable { id, pageRefID, rect }`
- `private(set) var pendingRedactions: [RedactionMark]`
- `addRedactionMark(rect:on:in:)` resolves the `PDFPage` to a `PageRef` the same way
  `createAnchoredRegionComment` does and registers undo (remove).
- `removeRedactionMark(id:)` and `clearRedactionMarks()`.
- `applyRedactions() -> Bool`:
  1. `canPerformMutatingAction()`, and marks must be non-empty.
  2. Preflight: any marked page with non-empty `pageEditStates` or `objectEditStates` →
     `status.redaction.editConflict` (with the workspace page number), and stop.
  3. Group marks by member, then by member-local page index (the resolution
     `applyPageCrop` uses).
  4. Same live-lane preparation as `applyPageCrop`: `PDFSerializer` of the loaded PDF,
     plus `preservingAttachments`.
  5. `mutateMemberBytes(requests:)` with transform `try? RedactionEngine.redact`. The
     first thrown `Failure` is captured so the message is specific (form field,
     verification, generic). The options are `reloadsLivePDF` and
     `invalidatedPageRefIDs`.
  6. On success: set anchor `snippet = nil` on comments whose anchor intersects a mark,
     drop `document.sourcePayloads` for affected members, clear the marks, call
     `warnIfEditingWouldInvalidateSignatures()`, and post a success status.

  Undo restores the bytes (one step, from `mutateMemberBytes`). The scrubbed snippets and
  dropped source payloads are deliberately **not** restored, since that direction is safe.

### 3. UI

- `AnnotationTool.redact` goes in the markup tool group next to the eraser, with label,
  help text and icon.
- `CommentRegionOverlayView` is reused for dragging. It shows for `.commentRegion` or
  `.redact`, and the commit callback dispatches on the current tool.
- `PageDecorationOverlayView` draws pending marks for its page as a red dashed stroke over
  a translucent red fill.
- `RedactionBar`, styled like `ScanBar`, sits in the canvas's bottom stack while marks
  exist and shows count · **Clear** · **Apply Redactions…**. The last opens a
  confirmation alert (destructive button) that states the v1 limits in one paragraph.
- L10n: every new key in all 6 languages.

## Testing (TDD, XCTest)

`RedactionEngineTests`, with fixtures from `EditingFixturePDFBuilder` and text read
through `PDFTextAnalysisEngine.readingOrderText`, never `PDFPage.string`:

- Text under the region disappears from the extracted text. Text elsewhere on the page
  survives as text.
- An object partly under the region is removed and a patch image is added (image object
  count rises).
- Image pixels under the region go black and pixels outside keep their color.
- An intersecting annotation is removed. A non-intersecting one survives.
- A widget in the region → `.formFieldInRegion`.
- Output renders black ink inside the region.
- A rotated page (`/Rotate 90`) is redacted in user space.

`RedactionWorkflowTests` (view model):

- Mark then apply: the text is gone from the live lane and from the pristine and object
  base lanes when those exist.
- Undo restores the text; redo removes it again.
- A page with a pending text edit op is refused with the conflict status, and the bytes
  don't change.
- An intersecting comment snippet is cleared, and the member's source payload is dropped.
- A saved snapshot (`exportedPDFDataThrowing` with `embedsEditableWorkspaceState`)
  doesn't contain the secret.

Also: `swift build -c release` (new silgen bindings), `LocalizationCoverageTests`, and
`RawLocalizationKeyLeakTests`.
