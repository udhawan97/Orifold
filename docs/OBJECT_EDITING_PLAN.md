# Orifold — Professional Object Editing System

**Status:** Planning (for a later Sonnet implementation agent). No code written yet.
**Audience:** The implementing agent (Sonnet). This document is the single source of truth for the feature.
**Scope:** Select, move, resize, rotate, delete, duplicate, align, layer, and restyle visual objects inside PDFs — lines, arrows, rectangles, ellipses, borders, table/grid lines, images, icons, logos, signatures/stamps, drawn shapes, vector paths, annotation objects, form widgets, decorative artifacts, grouped objects, Form XObject instances, and flattened elements (fallback-only).
**Constraint:** Orifold stays **local-first, free, and open-source**. No network, no telemetry, no new paid dependency. All processing runs through the already-bundled PDFKit / PDFium / qpdf.

---

## 0. How to read this plan (and the one fact that changes everything)

This plan was assembled from a full architecture audit of the current code plus five design workstreams. **Where the workstreams disagreed, this document states one canonical answer.** Do not re-introduce the alternatives. The reconciliations (object identity, the editability enum, the operation struct, cache naming, delete-engine primacy, Form-XObject semantics) are recorded in **Appendix A** — read it before writing any model code, or three incompatible object systems will be built against the same on-disk schema.

**The load-bearing discovery.** The PDFium binary Orifold already links (`Packages/PDFiumBinary`, the espresso3389 chromium xcframework) **exports the complete page-object editing API**, verified by `nm` on the built framework:

- Enumerate: `FPDFPage_CountObjects`, `FPDFPage_GetObject`, `FPDFPageObj_GetType`, `FPDFPageObj_GetBounds`
- Transform: `FPDFPageObj_GetMatrix` / `SetMatrix` / `Transform` / `TransformF`, `FPDFImageObj_SetMatrix`
- Delete (true, structural): `FPDFPage_RemoveObject`, `FPDFPageObj_Destroy`
- Insert / z-order: `FPDFPage_InsertObject`, `FPDFPage_InsertObjectAtIndex`
- Style: `FPDFPageObj_Get/SetStrokeColor`, `Get/SetFillColor`, `Get/SetStrokeWidth`, `Get/SetDashArray`, `GetDashCount`, `GetDashPhase`, `GetLineCap`, `GetLineJoin`
- Vector paths: `FPDFPath_CountSegments`, `GetPathSegment`, `MoveTo` / `LineTo` / `BezierTo` / `Close`, `Get/SetDrawMode`, `FPDFPageObj_CreateNewPath` / `CreateNewRect`
- Images: `FPDFImageObj_GetBitmap` / `SetBitmap` / `GetImagePixelSize` / `LoadJpegFileInline` (declared+used today) + `GetImageDataDecoded` / `GetImageMetadata` / `GetImageFilter`
- Form XObjects: `FPDFFormObj_CountObjects`, `GetObject`, `RemoveObject`
- Clip & form fields: `FPDFPageObj_GetClipPath`, `FPDFPage_HasFormFieldAtPoint`, `FPDFPage_FormFieldZOrderAtPoint`
- Commit + save: `FPDFPage_GenerateContent`, `FPDF_SaveAsCopy`

Crucially, `Orifold/Engine/PDFCompressionService.swift` **already runs the full `enumerate → mutate image bitmap → FPDFPage_GenerateContent → FPDF_SaveAsCopy` loop** (`PDFCompressionService.swift:201-256`), binding PDFium symbols with `@_silgen_name` (no C header needed) and using the alias trick (`@_silgen_name("FPDF_LoadPage")`, `:6-7`) to avoid duplicate-symbol link errors. **This is the exact template the object system extends.** The consequence: genuine content-stream object editing — move/resize/rotate/restyle/delete that mutates the real bytes with **no ghost and no leak** — is a *linked, partially-proven* capability, not a wish. Only the additional symbols (path/transform/style/remove) are undeclared in Swift today; they must be declared from scratch via `@_silgen_name`, and the binary is confirmed to export them.

**The one make-or-break unknown** is whether `FPDFPage_GenerateContent` — which re-emits the *entire* page content stream from PDFium's in-memory model — round-trips real-world pages without perturbing untouched text/vector content, and whether object identity survives that round-trip. **Phase 0 exists to prove this before any UI is built.** If Phase 0 fails, the structural lane narrows to annotations + images and the rest falls back to disclosed cover-and-redraw. Everything downstream is contingent on the Phase 0 gate.

---

## 1. Current Architecture Audit

Ground truth from reading the code. Every claim carries a `file:line`.

### 1.1 Page rendering & the canvas
- **There is no custom bitmap canvas.** The page is displayed by Apple **PDFKit** `PDFView` (subclass `OrifoldPDFView`, `ReadingCanvas.swift:1190`) wrapped in `PDFViewRepresentable: NSViewRepresentable` (`ReadingCanvas.swift:349`), `displayMode = .singlePageContinuous`, `autoScales = true` (`:354-476`). PDFKit internally rasterizes each `PDFPage` at the current `scaleFactor`; Orifold never produces a `CGImage` for on-canvas display.
- **Zoom/scale** is `pdfView.scaleFactor`; overlays read `max(pdfView.scaleFactor, 0.01)` (`:3685`). All view↔page mapping uses `pdfView.convert(_:from/to: page)` (`:1600, :1784, :1811, :3080`). **This returns points in the page's native, *unrotated* space** — `/Rotate` is baked into display only.
- **High-DPI/Retina** is handled entirely inside PDFKit; there is no tiled/LOD rendering and no scale-keyed cache in Orifold code.

### 1.2 How an edit becomes a live page + cache invalidation
- A committed text edit is baked into a **fresh `PDFPage`** by `PDFEditedPageRenderer.regeneratedPage(from:applying:)` (`PDFEditedPageRenderer.swift:14-69`): it redraws the pristine page background (`drawPageBackground`, `:71-96`, via `context.drawPDFPage`), paints erase patches (`drawErasePatch`, `:147-155`), and draws replacement text — all into a `CGContext` PDF, then re-decodes to a `PDFPage`.
- `regenerateEditedPage(pageRef:operations:)` (`WorkspaceViewModel.swift:2681-2709`) swaps that page into the member `PDFDocument`, **re-serializes the member and reloads a fresh `PDFDocument`** so PDFKit drops stale render caches (`:2698-2707`), then `rebuild()` (`:1075-1088`) re-concatenates `combinedPDF` and `syncDocumentPreservingViewport` (`ReadingCanvas.swift:847-880`) repaints without a viewport jump.
- **Cache invalidation is by object-identity:** every commit produces new `PDFDocument`s, discarding PDFKit's cache wholesale; `textAnalysisCache.removeValue(forKey:)` is called for the edited page (`:2696`), and undo/redo `removeAll()`s it (`:1351`). There is **no cheap "redraw one object" path** — every commit is a full member re-serialize + full `combinedPDF` rebuild, too heavy to run per drag-frame.

### 1.3 Content-stream / object access (the enabling layer)
- **`PDFTextAnalysisEngine.swift`** holds the only existing PDFium object-enumeration loop: `renderModeRegions` (`:170-191`) does `FPDFPage_CountObjects → GetObject → GetType==TEXT → GetBounds → GetTextRenderMode`, under the process-wide `pdfiumLock` (`PDFiumProcessingEngine.swift:4`). It always analyzes **pristine `originalMemberPDFData`** (`WorkspaceViewModel.swift:6226`), and matrix marshalling (`FSMatrix`, `:63-70`) is established.
- **`PDFCompressionService.swift`** is the proven mutate+save precedent (`:201-256`): object loop, image bitmap swap, `FPDFPage_GenerateContent` (`:56-57`), `FPDF_SaveAsCopy` (`:77-87`), plus the alias-`@_silgen_name` duplicate-symbol workaround (`:6-7`).
- **`QPDFService.swift`** reaches the PDF object graph losslessly without rasterizing (`sanitized`, `:98-117`; `withQPDF` open/recover/cleanup, `:136-165`; `write`, `:174-182`). The linked qpdf C API *also* exports `qpdf_oh_get_page_content_data` / `get_stream_data` / `replace_stream_data` (`qpdf-c.h:917, 930, 946`) — content-stream editing is reachable but **not yet wired**.
- **`PDFiumProcessingEngine.swift`** owns the shared lifecycle symbols (`pdfiumLock`, `FPDF_InitLibrary/LoadMemDocument/LoadPage/…`).
- **Gap:** no general object model, no path/transform/style silgen declarations, no object classification, no structural write-back wired, no durable per-object identity.

### 1.4 Annotations / widgets / signatures / stamps (the reusable UX spine)
- **A working 8-handle move/resize/delete overlay already exists:** `SignatureSelectionOverlayView` (`ReadingCanvas.swift:1654-1903`) draws outline + 8 handles + delete button, hit-tests, and converts drag deltas to page space via `pdfView.convert(_:to: page)` (`:1784`). It is driven by `PageObjectSelectionTarget` (`:1624-1652`), which already abstracts a selection over *both* a `PDFAnnotation` and a stamp `PageDecoration`.
- Move/resize commits are already undoable document ops with inverse-snapshot undo: `updateStampDecoration` (`WorkspaceViewModel.swift:3447-3478`), `updateSignaturePlacement` (`:3480-3513`), bounds clamped by `constrainedSignatureBounds` (`:3515-3533`).
- Export baking precedents: `PDFDecorationExportBaker.bake` (`:32-83`), `SignatureExportBakingSupport.bake` (`SignatureAppearanceRenderer.swift:309-355`) which returns CGContext bytes **directly** (no `PDFSerializer` round-trip), and a real **vector-path→PDF-content emitter** `CGPath.pdfFillCommands` / `pdfAppearanceStream` (`:254, :114`).
- Form widgets: `PDFFormSupport.scan` + `isPDFWidget` (`:43-67, :220`), highlighted live by `drawFormHighlights` (`ReadingCanvas.swift:1515`).
- **Landmine:** every existing baker redraws the whole page via `page.draw(with:.mediaBox,…)` into a fresh CGPDF context — the documented "PDFKit re-serialization destroys the text layer" path. `AnnotationIndexEntry.swift` is **dead code** (zero references); do not plan around it.

### 1.5 Selection state, edit-op model, undo/redo, persistence
- **Edit ops are per-page structs:** `PDFTextEditOperation` (`PDFTextEditingModels.swift:139-284`, hand-written `init(from:)` with `decodeIfPresent` for schema evolution) held in `PageEditState { pageRefID, operations: [] }` (`:286-290`), stored in `Workspace.pageEditStates` (`Workspace.swift:140`, `schemaVersion = 5` at `:141`).
- **Editability is already an enum precedent:** `PDFTextEditability` (`:13-34`) — the object system mirrors this exactly. Confidence: `PDFTextEditConfidence {high, medium, low}` (`:4-8`).
- **Commit lifecycle** (`applyInlineTextEdit`, `WorkspaceViewModel.swift:2545-2659`): capture snapshot → build/merge op (upsert by `sourceBlockID`, `:2606-2635`) → `regenerateEditedPage` → `rebuild()` + `markWorkspaceModified()` → `registerIsolatedUndo` (`:1320-1331`, forces a standalone undo group). Rollback on renderer failure restores `editStates` only (**not** `pdfData` — a partial-state bug the object path must fix).
- **Snapshot undo/redo:** `InlineTextEditSnapshot { editStates, pageRotations, pdfData }` (`:1238-1242`); `capture`/`restore` (`:1333-1361`) where restore re-registers its inverse for redo.
- **Stable page identity across reopen:** `PageRef.id` (UUID) is the join key (`PageRef.swift:3-46`); `pageRef(for:in:)` maps a live `PDFPage` back to a `PageRef` skipping `BoundaryPage` banners (`:6203-6218`).
- **Reopen persistence:** the whole `Workspace` (incl. edit states) + member bytes round-trip as invisible metadata — `embedMetadata` (`WorkspaceDocument.swift:594-640`) / `importPDFDocument` restore (`:200-206`). `@Published workspace` wires mutations into autosave.
- **Key instability to inherit and solve:** re-analysis assigns brand-new `EditableTextBlock.id`s every pass (`PDFTextEditingModels.swift:154-161`), so text ops fall back to nearest-bounds matching. The object system needs a durable identity (§3.6, §8.5).

### 1.6 Export / serialization / reopen fidelity
- Single export funnel: `WorkspaceDocument.exportedPDFDataThrowing` (`:254-317`) → `concatenateForExport` (`PDFKitEngine.swift:83-104`) → serialize → signature-bake → form-flatten → decoration-bake → comment-bake → embed-metadata. **Every stage funnels through `PDFSerializer.data` = `PDFDocument.dataRepresentation()`** (`PDFSerializer.swift:10-23`) — the exact call that drops Type3/Skia/vector text.
- **Import protects the text layer via qpdf** (`PDFImportNormalizer.normalizedData`, `:38-73`, gated by a two-parser page-count agreement `isTrustworthy`, `:79-91`) — but there is **no export-side equivalent**. Even leak-free member bytes get re-destroyed at assembly.
- Encryption/permissions on export are qpdf-based and self-verified (`PDFEncryptionService.swift:7-72`) — the only existing reopen-from-bytes fidelity check. `verifyExportedFile` otherwise checks only size > 0 (`:4445-4458`).
- `sourcePayloadsForPDFMetadata` disables the faithful-source fast path when `pageEditStates` is non-empty (`:340`) — object edits must do the same.
- `PDFPage.copy()` **silently blanks** CGContext-built pages (`PDFKitEngine.swift:38-46`); never round-trip rendered pages through it.

### 1.7 Toolbar / contextual controls / i18n / design system
- Toolbar mode-switching is `AnnotationToolPicker` (`ContentView.swift:1632`), a capsule over the `AnnotationTool` enum (`WorkspaceViewModel.swift:74-158`) whose `select(_:)` (`:1935-1966`) opens/closes companion palettes. Adding an `AnnotationTool` case yields localized label/icon/help for free.
- Contextual on-canvas toolbar precedent: `InlineTextEditorOverlay` (`ReadingCanvas.swift:2351`), a floating AppKit `NSView` with format controls + move/resize handles + keyDown shortcuts (`:4169-4205`). Delete-key is wired via `OrifoldPDFView.keyDown` → `onDeleteKey` (`:1227-1237`).
- Reusable toolbar kit: `ToolbarIconButton` + `ActiveStyle` (`:2093`), `ToolbarIconMetrics` (`:2081`), `ToolbarVerticalDivider` (`:2065`), `ToolbarMoreMenu` + `MoreRoute` + `pendingMoreRoute` one-runloop-hop (`:2968-3176, 2932-2946`). **Never** a bare `Divider()` in a toolbar group (`:474-479`).
- **i18n:** `L10n.string(_:locale:)` / `L10n.format(_:_:locale:)` (`L10n.swift:41-77`); keys live in `Orifold/Resources/Localizable.xcstrings`; **`LocalizationCoverageTests` fails CI** if any non-interpolated key lacks es/fr/hi/zh-Hans/ja (`LocalizationCoverageTests.swift:8, 57-78`). Interpolated values must use `%@`/`%lld` catalog entries via `L10n.format`, not Swift `\(…)`. New popovers must re-inject `.environment(\.locale, languageManager.effectiveLocale)` (macOS popovers reset locale). Under `swift test`, xcstrings is not compiled — lookups use a raw-JSON fallback (`:44-52, 83-105`), so a key must physically exist in the JSON.
- **Design tokens** (mandatory, no hardcoded colors/spacing): `Color.ds*` / `NSColor.ds*NS` (`DesignSystem.swift:26-197`), spacing (`:201-208`), radii (`:234-238`), typography (`:250-267`), origami motifs `FoldedCornerRect` / `CreaseRule` / `EnsoRing` (`:283-387`). `ContentView.body` is near the type-checker complexity ceiling — factor new presentation logic into `ViewModifier`s.
- Shortcuts: `ShortcutRegistry.all` (`ShortcutRegistry.swift:47-160`) is **descriptive only** — a shortcut must be added there *and* in a real `.keyboardShortcut`/`keyDown` site (drift hazard). `AppCommands` binds ⌘Z/⇧⌘Z (`AppCommands.swift:142-164`).

---

## 2. Object Detection Strategy

Detection is a **new PDFium page-object enumeration pass** in a new engine, `PDFObjectDetectionEngine`, modeled line-for-line on `PDFTextAnalysisEngine.renderModeRegions` (`:170-191`): hold `pdfiumLock`, `FPDF_InitLibrary → FPDF_LoadMemDocument → FPDF_LoadPage`, then walk `FPDFPage_CountObjects / GetObject / GetType`. It **always runs against pristine `originalMemberPDFData`** (`WorkspaceViewModel.swift:398, 6226`) so re-serialization damage never contaminates the map.

**Symbol reality — be honest.** Only `FPDFPage_CountObjects/GetObject/GetType/GetBounds` (`PDFTextAnalysisEngine.swift:88-104`) and the image chain + `GenerateContent` + `SaveAsCopy` (`PDFCompressionService.swift:30-82`) are declared in Swift today. **Everything else this plan uses is undeclared and must be added from scratch** via `@_silgen_name` (verified linked in the binary): `FPDFPageObj_GetMatrix/SetMatrix/Transform`, all `FPDFPath_*`/`FPDFPathSegment_*`, all style getters/setters, `FPDFPageObj_GetClipPath`, `FPDFImageObj_GetImageMetadata/GetImageFilter/GetImageDataDecoded`, `FPDFFormObj_*`, `FPDFPage_RemoveObject/InsertObjectAtIndex`, `FPDFPageObj_Destroy/AddMark`, and the annotation surface `FPDFPage_GetAnnot*`/`FPDFAnnot_*`. For any name already declared elsewhere, use the alias trick (`PDFCompressionService.swift:6-7`) or the build fails with duplicate-symbol errors.

**Two disjoint detection sources, fused per page:**
1. **PDFium content-stream page objects** (`FPDFPage_GetObject`): text, path, image, shading, Form XObject. All native vector/image/shape detection.
2. **PDFKit annotations + Orifold overlay objects**: `page.annotations` (+ `isPDFWidget`, `PDFFormSupport.swift:220`) for annotation-backed graphics/widgets; `workspace.signatures`/`workspace.decorations` for Orifold overlays.

**No annotation-vs-content dedup is needed:** annotations live in `/Annots`, never returned by `FPDFPage_GetObject`. The *only* dedup pass is overlay-vs-content: suppress a content-stream object whose bounds match (within 1pt, same `pageRefID`) an Orifold `SignaturePlacement`/`PageDecoration` rect (the overlay wins — it carries editability metadata). This guards the single real overlap: an Orifold overlay that was baked on a prior export-and-reopen.

### 2.1 Per-category detection & tiers

PDFium type constants: `TEXT=1, PATH=2, IMAGE=3, SHADING=4, FORM=5`.

| Category | Technique (linked API) | Tier |
|---|---|---|
| **Annotations** (ink/note/signature/stamp) | PDFKit `page.annotations` + `signaturePlacementID` key + `workspace.decorations`. Working selection already exists. | **RELIABLE** |
| **Image XObjects** | `GetType==3`; bounds `GetBounds`; matrix `GetMatrix`; pixels `GetImagePixelSize`/`GetImageMetadata`/`GetImageFilter`. Mutation proven (`PDFCompressionService:201-256`). | **RELIABLE** |
| **Vector paths** | `GetType==2`; segment walk `FPDFPath_CountSegments/GetPathSegment` + `FPDFPathSegment_GetType/GetPoint`, `GetDrawMode`; style via stroke/fill/dash getters. | **RELIABLE** |
| **Lines** | Path = `MOVETO` + one `LINETO`, unclosed, stroke-only. | **RELIABLE** |
| **Rectangles** | Closed 4-`LINETO` axis-aligned loop (or `CreateNewRect` shape), right-angle corners within ε. | **RELIABLE** |
| **Filled shapes** | Draw-mode fill/fill+stroke, `GetFillColor` α>0; sub-classify by segment shape. | RELIABLE (shape) / HEURISTIC (semantic role) |
| **Stroked shapes / ellipses** | Draw-mode stroke, `GetStrokeWidth`>0; ellipse = 4-bezier near-circular loop. | RELIABLE (as stroke) / HEURISTIC (ellipse vs rounded-rect) |
| **Table / grid lines** | Many thin line/rect paths grouped by §2.2. | HEURISTIC (as a group) |
| **Form widgets** | `isPDFWidget` + `PDFFormField` scan; `drawFormHighlights`. | **RELIABLE** |
| **Form XObjects** | `GetType==5`; children via `FPDFFormObj_CountObjects/GetObject`. Instance placement (matrix+bounds) reliable; shared-source editing not. | RELIABLE (instance) / FALLBACK (source) |
| **Decorative artifacts** | Inferred: thin rule (aspect > ~20:1), or large low-saturation fill, outside grids, not over text. `/Artifact` BDC not readable via declared surface. | HEURISTIC |
| **Clipped / masked** | `GetClipPath` reports presence (intent unrecoverable → `clipInfo.hasClip`); image SMask via `GetImageMetadata`. | RELIABLE (clip exists); editability degrades (§4) |
| **Flattened / scanned** | Single image covering >~95% of the crop box, no meaningful text layer (reuse `regionIsBlankBackground`, `PDFEditedPageRenderer.swift:338`). | FALLBACK (`rasterRegionReplace`) |
| **Shading / gradient** | `GetType==4`; type+bounds only, no rich accessors. | UNSUPPORTED (select+inspect) |

### 2.2 Grouping vector ops into one semantic object

A **two-tier pass** runs in Swift over the detected primitives (no extra PDFium calls):
- **Tier A — atomic shape recognition:** classify each single `PATH` object by its own segment list into `line/rect/ellipse/polyline/freeform` before any cross-object grouping. An arrow drawn as one stroked polyline stays one object.
- **Tier B — spatial clustering (tables/grids):** bucket `line`/thin-`rect` primitives into horizontal/vertical runs (within 2° of axis); if ≥2 horizontals and ≥2 verticals form a lattice within a common rect, emit **one** `tableGrid` group (`groupSource == .inferredCluster`) whose `children` lists members. Members stay in the map flagged `isGroupChild = true` (suppressed from the default top-layer hit-test, drillable on a second click at the same point — mirroring the reopen-op re-route at `:2370-2399`).

**Form XObject grouping** is the declarative counterpart: when `FPDFFormObj_CountObjects > 0`, that instance's children group under one object with `groupSource == .formXObject(name:)` — no heuristic. (This groups one instance's children; it does not link separate instances of the same source — see §4/§10.)

### 2.3 Confidence scoring

Every object carries `confidence: PDFTextEditConfidence` (reuse the shipping enum, `PDFTextEditingModels.swift:4-8` — do **not** invent a parallel enum). Deterministic:
- **high** — a typed PDFium op or clean annotation matching a recognized primitive exactly; no heuristic fired.
- **medium** — a heuristic agreed with geometry (ellipse-from-beziers, clean lattice, unambiguous rule).
- **low** — ambiguous grouping, unknown-intent clip/mask, or flattened soup. **`low` objects are never default-selectable** (require an explicit "select artifacts" toggle) so a stray click on scanned paper never grabs the whole page.

Confidence gates default hit-test eligibility (only high/medium participate in ordinary click selection) and feeds editability (§4).

---

## 3. Per-Page Object Map (canonical data model)

> **CANONICAL.** This is the one object-model definition. §5, §8, §9 reference these types; they do not redefine them. All types live in a new file `Orifold/Models/PDFObjectEditingModels.swift`, follow `PDFTextEditingModels.swift` conventions (`Codable`, `Equatable`, `UUID` ids, `CGRect` bounds in **raw/unrotated content-stream space**, `PDFTextTransform` matrices, hand-written `init(from:)` with `decodeIfPresent`).

**Central design rule (defeats the ghost/duplicate export trap):** the object map is a **read-only detection index**, never the source of truth for bytes. Detected native objects already exist in `originalMemberPDFData` — they must **never be re-baked on export** or they double up. Only entries in the **operation list** (`PageObjectEditState`, §8) mutate the document. `duplicate` is the *only* op that adds geometry.

### 3.1 Enums

```swift
enum PDFObjectType: String, Codable {
    case annotation, imageXObject, vectorPath, line, rectangle, ellipse,
         filledShape, strokedShape, tableGrid, formWidget, formXObject,
         shading, decorativeArtifact, flattenedRaster
}

enum PDFObjectSource: String, Codable {
    case pdfiumPageObject, pdfKitAnnotation, orifoldDecoration, orifoldPlacement, inferred
}

enum PDFObjectGroupSource: Codable, Equatable {
    case none
    case inferredCluster            // Tier-B spatial cluster (table/grid)
    case formXObject(name: String)  // PDF-declared /Form XObject instance
}

// Ranking helper on the REUSED text-confidence enum (do not invent a parallel enum).
extension PDFTextEditConfidence { var rank: Int { self == .high ? 2 : (self == .medium ? 1 : 0) } }
```

### 3.2 Style + payload value types

```swift
struct PDFObjectStyle: Codable, Equatable {          // CodableColor reused (PDFTextEditingModels.swift:342)
    var strokeColor: CodableColor? = nil             // FPDFPageObj_GetStrokeColor
    var fillColor: CodableColor? = nil               // FPDFPageObj_GetFillColor
    var opacity: CGFloat = 1.0                        // color alpha / SMask
    var lineWidth: CGFloat = 0                        // FPDFPageObj_GetStrokeWidth
    var dashPattern: [CGFloat] = []                   // FPDFPageObj_GetDashArray + GetDashCount
    var dashPhase: CGFloat = 0
    var lineCap: Int = 0
    var lineJoin: Int = 0
}

enum PDFPathSegmentKind: String, Codable { case moveTo, lineTo, bezierTo, close }
struct PDFPathSegment: Codable, Equatable {
    var kind: PDFPathSegmentKind
    var point: CGPoint
    var control1: CGPoint? = nil
    var control2: CGPoint? = nil
    var isClosed: Bool = false                        // FPDFPathSegment_GetClose
}
struct PDFPathData: Codable, Equatable {              // geometry in the object's OWN pre-matrix space
    var segments: [PDFPathSegment]
    var fillRule: Int                                 // FPDFPath_GetDrawMode
    var isStroked: Bool
    var isFilled: Bool
    /// Flattened polyline (beziers pre-flattened HERE, in detection) for the hit-test's
    /// distance-to-segment pass — so §5 stays allocation-free and O(#segments).
    var flattenedStroke: [CGPoint] = []
}
struct PDFObjectImageMetadata: Codable, Equatable {
    var pixelWidth: Int; var pixelHeight: Int         // FPDFImageObj_GetImagePixelSize
    var bitsPerPixel: Int? = nil; var colorSpace: Int? = nil   // FPDFImageObj_GetImageMetadata
    var filter: String? = nil                         // FPDFImageObj_GetImageFilter
    var hasSoftMask: Bool = false
    var pixelDigest: UInt64 = 0                        // FNV-1a of decoded pixels → structuralDigest
}
struct PDFObjectClipInfo: Codable, Equatable {
    var hasClip: Bool = false                         // FPDFPageObj_GetClipPath != nil
    var clipBounds: CGRect? = nil
    var hasSoftMask: Bool = false
}
```

### 3.3 `DetectedObject`

```swift
struct DetectedObject: Codable, Identifiable, Equatable {
    // identity
    var id: UUID = UUID()                    // fresh per detection pass; dies with the cache
    var stableKey: PDFObjectStableKey        // durable cross-reopen identity (§3.6 / §8.5)
    var markedContentId: Int? = nil          // FPDFPageObj_AddMark hint (Phase-0-gated, §8.5)
    var pageRefID: UUID?                      // PageRef.id join key

    // classification
    var objectType: PDFObjectType
    var sourceType: PDFObjectSource
    var confidence: PDFTextEditConfidence    // REUSED enum + .rank (§2.3)
    var editability: PDFObjectEditability     // §4

    // geometry (raw content-stream space)
    var boundsPdf: CGRect                     // FPDFPageObj_GetBounds — POST-matrix AABB; a hit-test hint,
                                              // NOT the thing move/resize edits.
    var transform: PDFTextTransform           // FPDFPageObj_GetMatrix. MOVE/RESIZE/ROTATE mutate THIS via
                                              // SetMatrix/Transform, never boundsPdf, to avoid double-apply.
    var pageRotation: CGFloat                 // page /Rotate, verbatim (EditableTextBlock split, :118-119)
    var zOrder: Int                           // FPDFPage_GetObject index at detection

    // style + typed payloads
    var style: PDFObjectStyle
    var pathData: PDFPathData? = nil
    var imageMetadata: PDFObjectImageMetadata? = nil
    var clipInfo: PDFObjectClipInfo = .init()

    // grouping
    var groupSource: PDFObjectGroupSource = .none
    var children: [UUID] = []
    var isGroupChild: Bool = false
    var formXObjectName: String? = nil
    var isBackgroundLike: Bool = false        // ≥92% crop-box area / full-bleed / decorative (§5.7)

    // session-only (excluded from CodingKeys and ==)
    var boundsViewport: CGRect? = nil         // pdfView.convert result; recomputed, never persisted
    var detectedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, stableKey, markedContentId, pageRefID, objectType, sourceType, confidence, editability
        case boundsPdf, transform, pageRotation, zOrder, style, pathData, imageMetadata, clipInfo
        case groupSource, children, isGroupChild, formXObjectName, isBackgroundLike, detectedAt
        // boundsViewport deliberately omitted
    }
}
```

> Reconciliation note: this single struct merges the detection workstream's `DetectedObject` and the hit-test workstream's `DetectedPageObject`. The hit-test-only fields (`flattenedStroke`, `isBackgroundLike`) are folded in above.

### 3.4 `PageObjectMap` (transient per-page index)

```swift
struct PageObjectMap: Equatable {            // NOT Codable — never serialized
    var pageRefID: UUID
    var objects: [DetectedObject]             // ascending zOrder
    var analysisRevision: Int = 0             // debug/telemetry only
}
```

### 3.5 Cache: build, invalidate, reuse

One canonical cache on the view model, parallel to `textAnalysisCache` (`:375`):

```swift
private var objectAnalysisCache: [UUID: PageObjectMap] = [:]   // keyed by PageRef.id
func objectMap(for pageRef: PageRef, page: PDFPage, memberID: UUID, localIndex: Int) -> PageObjectMap
```
(name **`objectAnalysisCache`**; ignore the alternate names `ObjectAnalysisCache`/`objectMapCache` that appeared in draft sections.)

- **Lazy.** Nothing is detected until the object tool is active AND a page is clicked/hovered (or the object inspector opens). Per-page, cached, never whole-document eager (heeds the O(pageCount) main-thread footgun at `ReadingCanvas.swift:3744-3752`). Because detection holds the single `pdfiumLock`, run `objectMap(for:)` **off the main actor** and publish back, or bound it with a page-object-count ceiling → `flattenedRaster` above it.
- **Built off pristine bytes** (`originalMemberPDFData`, `:6226`).
- **Invalidated** by `objectAnalysisCache.removeValue(forKey: pageRefID)` on commit (as `textAnalysisCache` is cleared at `:2696`), `removeAll()` on undo-restore (as `:1351`), and a new `removeObjectMaps(forRemovedPageRefIDs:)` in the page-delete cascade (mirroring `:1705`, called from `:1176-1177, :5867, :5904`).
- **Reused for** hit-test/selection (§5), drag/resize preview (overlay proxy, no rebuild), duplicate (adds geometry), and export/undo (map is read-only reference).

### 3.6 Persistence & cross-reopen re-identification

**The map is NOT persisted — it is rebuilt on open** (like `textAnalysisCache`). What persists is the **operation list** `Workspace.objectEditStates: [PageObjectEditState]` (§8), added exactly as `pageEditStates` was: new `CodingKeys` case (`Workspace.swift:143-145`), a `decodeIfPresent` line (`:164`), and a **single coordinated `schemaVersion` bump** (`:141`). It round-trips via `embedMetadata`/`editableWorkspace` (`WorkspaceDocument.swift:200-206, 270-271`); extend `sourcePayloadsForPDFMetadata` (`:336-376`) to disable its fast path when `objectEditStates` is non-empty (as it does for `pageEditStates` at `:340`).

**Durable identity — `PDFObjectStableKey` (canonical; see Appendix A, decision 1).** `FPDFPage_GetObject` is index-based and every commit re-serializes+reloads the document (`:2698-2701`), renumbering objects. Identity therefore hashes **only mutation-invariant intrinsic content**, recomputed from a *fresh detection pass* on every load — **never a persisted cross-serialization byte digest** (`FPDFPage_GenerateContent` re-emits the whole stream, so raw byte digests of untouched objects legitimately change):

```swift
struct PDFObjectStableKey: Codable, Equatable, Hashable {
    var pageRefID: UUID
    /// Mutation-INVARIANT structural digest, recomputed from the LIVE model each detection pass.
    /// Paths: FNV-1a over segment topology (kinds + points NORMALIZED to the path's own origin —
    /// translation/scale/rotation via the matrix do NOT change it). Images: pixelDigest + dims.
    /// Annotations: /OrifoldSignaturePlacementID or contents. THE ONLY field in == / hashValue.
    var structuralDigest: UInt64

    // Ranked disambiguators — NOT part of == / hashValue:
    var quantizedBoundsHint: [Int] = []   // boundsPdf at detection, rounded to 1pt [x,y,w,h]
    var zOrderHint: Int = 0
    var typeHint: String = ""             // objectType.rawValue at detection
    var sourceXObjectName: String? = nil  // Form XObject placements

    static func == (l: Self, r: Self) -> Bool { l.pageRefID == r.pageRefID && l.structuralDigest == r.structuralDigest }
    func hash(into h: inout Hasher) { h.combine(pageRefID); h.combine(structuralDigest) }
}
```

**Re-identification on reopen / after every commit-reload:**
1. `objectMap(for:)` rebuilds fresh `DetectedObject`s from the (post-round-trip) bytes.
2. Each persisted `ObjectEditOperation` re-binds to its object by, in order: **(a) `markedContentId`** if present *and Phase 0 proved AddMark survives GenerateContent* → **(b) `structuralDigest`** (position-invariant, so a moved object still matches) → **(c)** nearest `quantizedBoundsHint`, then `zOrderHint`, then `typeHint` — the same nearest-bounds tie-break the text path already relies on (`:2370-2374`).
3. If neither AddMark nor structuralDigest survives the round-trip (Phase 0 disproves both), the system falls back to (c) alone — the exact behavior the text path ships with today.

This is **the make-or-break identity contract; Phase 0 must validate it before the architecture is committed** (§12, §16, Appendix A decision 3).

---

## 4. Editability Classification

> **CANONICAL enum.** Defined exactly in the `PDFTextEditability` style (`PDFTextEditingModels.swift:13-34`), assigned during detection from `objectType` + `confidence` + `clipInfo` + document permissions. Every object resolves to exactly one editability — never "editable or nothing." Ignore the alternate 5-case/7-case enums that appeared in draft sections; those are expressed here as the derived capability set (§4.1).

```swift
enum PDFObjectEditability: String, Codable {
    case directAnnotationEdit          // DIRECT_ANNOTATION_EDIT
    case directVectorEdit              // DIRECT_VECTOR_EDIT
    case directImageEdit               // DIRECT_IMAGE_EDIT
    case formWidgetEdit                // FORM_WIDGET_EDIT
    case formXObjectInstanceEdit       // FORM_XOBJECT_INSTANCE_EDIT  (ships in v1)
    case formXObjectSourceEdit         // FORM_XOBJECT_SOURCE_EDIT     (v1-DEFERRED → fallback message)
    case groupedObjectEdit             // GROUPED_OBJECT_EDIT
    case inferredArtifactEdit          // INFERRED_ARTIFACT_EDIT
    case rasterRegionReplace           // RASTER_REGION_REPLACE
    case lockedOrPermissionRestricted  // LOCKED_OR_PERMISSION_RESTRICTED
    case unsupported                   // UNSUPPORTED
}
```

### 4.1 Derived capability set (the UI / hit-test / export dispatch key off THIS, not a second enum)

```swift
struct ObjectCapabilities {
    var canMove, canResize, canRotate, canRestyle, canReplaceImage: Bool
    var canDeleteStructurally, canDuplicate, canLayer: Bool
    var isOverlayBacked: Bool     // Orifold annotation/decoration → baked, never a content-stream write
    var isReadOnly: Bool
}
extension PDFObjectEditability { var capabilities: ObjectCapabilities { /* per the table below */ } }
```

Operation vocabulary: **move, resize, rotate, delete, duplicate, align, layer (z-order), restyle (stroke/fill/width/dash/opacity), replace-image**. Every fallback message is a ready-to-author `L10n` key + English value (all six languages, via `L10n.format` with `%lld`/`%@` for interpolation).

| Editability | Allows | Blocks | Fallback message (`key` → en) |
|---|---|---|---|
| **directAnnotationEdit** — annotation-backed (ink/note/stamp/Orifold signature). Already works via `PageObjectSelectionTarget` (`:1624`) + `updateStampDecoration`/`updateSignaturePlacement` (`:3447, 3480`). Overlay-baked on export, no ghost. | move, resize, rotate, delete, duplicate, align, layer, restyle | nothing (crypto-sig invalidation guard `:3345` still applies) | — |
| **directVectorEdit** — high-confidence path/line/rect/ellipse, **no clip**. `SetMatrix`/`Transform` + style setters → `GenerateContent`+`SaveAsCopy`. **Delete = `FPDFPage_RemoveObject`+`Destroy` (structural, no leak).** | move, resize, rotate, delete, duplicate, align, layer, restyle | nothing | — |
| **directImageEdit** — high-confidence image XObject, **no soft mask**, no clip. | move, resize (aspect-lock offered), rotate, delete (structural), duplicate, align, layer, replace-image, opacity | stroke/fill/dash restyle (meaningless for raster) | `object.editability.image.styleUnsupported` → "Stroke and fill styling don't apply to images. You can move, resize, rotate, replace, or delete this picture." |
| **formWidgetEdit** — PDFKit widget (`isPDFWidget`). | move, resize, align, layer, delete-widget (confirm) | duplicate (breaks AcroForm names), rotate, restyle of field content | `object.editability.formWidget.restricted` → "This is a fillable form field. You can reposition or remove it, but its contents and duplication are managed in the form tools to avoid breaking the form." |
| **formXObjectInstanceEdit** — one placed instance of a reused `/Form` XObject. **Transforms only THIS placement's matrix** (`FPDFPageObj_Transform` on the form object — the `Do` invocation's CTM — not the shared stream). **Ships in v1.** | move, resize, rotate, delete (this instance), duplicate (new instance), align, layer | editing shared interior content (deferred) | `object.editability.formXObject.instanceOnly` → "This is a reused graphic placed in several spots. You can move, resize, or remove this copy — but its interior look-and-feel can't be changed yet." |
| **formXObjectSourceEdit** — editing the shared `/Form` stream so *every* placement updates. **v1-DEFERRED**: no safe per-page write path (`GenerateContent` is per-page; the source stream is shared). Resolves to a gated explicit action or a message. | selection + inspection | every structural mutation in v1 | `object.editability.formXObject.sourceDeferred` → "Changing this reused graphic everywhere at once isn't available yet — edit an individual copy instead." |
| **groupedObjectEdit** — inferred `tableGrid` cluster. Group op fans out to one op **per member** (§8.4), applied structurally. | move, resize (scales all), delete (group), duplicate, align, layer, restyle (all member strokes) | per-segment edits (drill into a child → `directVectorEdit`) | `object.editability.group.hint` → "Selected a group of %lld lines. Edits apply to all of them — click again to pick a single line." |
| **inferredArtifactEdit** — medium/low-confidence decorative rule/divider/tint. | move, delete (structural via `RemoveObject`), restyle, opacity, layer | — (not default-selectable; requires "select artifacts") | `object.editability.artifact.lowConfidence` → "This looks like a decorative element, but Orifold isn't fully sure it's a separate object. Edits may affect nearby graphics — check the result before saving." |
| **rasterRegionReplace** — clipped/masked/soft-masked/flattened soup, no clean object boundary. | rectangular region cover/replace (disclosed visual-only); true removal only via the gated qpdf redaction path | move, resize, rotate, duplicate, restyle, layer | `object.editability.raster.regionOnly` → "This area is part of a scanned or flattened image with no separate objects. You can cover or replace a region, but individual shapes here can't be moved or restyled." |
| **lockedOrPermissionRestricted** — `!allowsContentModification` / crypto-signed. | selection + inspection only | every mutation | `object.editability.locked` → "This document restricts edits to its content. Remove the restriction (or the signature) to edit this object." |
| **unsupported** — shading/gradient, unclassifiable-above-low. | selection + inspection only | every mutation | `object.editability.unsupported` → "Orifold can't edit this kind of object yet. It's shown for reference only." |

**Honesty requirement (rasterRegionReplace).** The cover-patch path is **visual-only and leaks the original bytes** (`PDFEditedPageRenderer.swift:71-96, 147` re-embeds the whole original stream). The UI must **never** call it "redact" or "remove"; only the gated qpdf structural path may claim removal.

**Grounding note.** Editability is computed once at detection and stored on `DetectedObject.editability`; the UI reads it to enable/disable controls, showing the fallback message via a non-blocking disclosure (reuse the one-time `NSAlert` disclosure used for the visual-only-erase warning), never a hard error. Every structural mutation MUST route through the PDFium `SetMatrix`/`RemoveObject`/`InsertObject` → `GenerateContent` → `SaveAsCopy` chain (`PDFCompressionService.swift:233, 250`) — **never** the rasterizing `PDFEditedPageRenderer.regeneratedPage`, which would repeat the erase leak and flatten the page — followed by the mandatory validation gate (§8.4). Never `PDFPage.copy()` a rendered page (`PDFKitEngine.swift:38-46`).

---

## 5. Hit-Testing & Selection Model

Resolves a click on `OrifoldPDFView` to zero/one/many editable objects. It consumes `DetectedObject` (§3); it does not parse content streams.

### 5.1 Where it hooks in
- **Click dispatch:** the single `NSClickGestureRecognizer` (`ReadingCanvas.swift:391-395`) fires `handleClick(_:)` (`:590-660`). A new `.selectObject` tool case (and the passive `.none` case, §7) calls a new `objectHitTest(at:on:in:)` beside `editableTextBlock(at:on:in:)` (`WorkspaceViewModel.swift:2359`) and `stampDecoration(at:on:in:)` (`:3421`). Reuse the existing guards verbatim: `inlineEditor?.containsInteractivePoint` bail (`:593`) and `guard let page = pdfView.page(for:nearest:), !(page is BoundaryPage)` (`:596-597`).
- **Coordinate conversion:** `pdfView.convert(viewPoint, to: page)` — already in native/unrotated page space (§5.4). No `/Rotate` correction.
- **Selection overlay:** a new `ObjectSelectionOverlayView` cloned from `SignatureSelectionOverlayView` (`:1654-1903`), registered in `makeNSView` (`:397-419`), refreshed via `refreshObjectOverlay` (sibling to `refreshSignatureOverlay`, `:1101-1115`), and **added to `gestureRecognizerShouldBegin`** (`:681-688`, which today only checks `signatureOverlay`/`inlineEditor`). Its `hitTest` returns `nil` when hidden or off its interaction frame (like `:1696-1701`).
- **Selection state:** new `@Published var objectSelection` on the view model, beside `selectedAnnotation`/`selectedStampDecorationID`, mutually exclusive with them.
- **Scale/scroll sync:** reuse the existing `.PDFViewScaleChanged` (`:469, 1034`) and clip-view `boundsDidChange` observers (`:522-542`). Do **not** add a second observer set.

### 5.2 Selection state

```swift
struct ObjectSelection: Equatable {
    var pageRefID: UUID?               // single-page; cross-page multi-select disallowed
    var objectKeys: [PDFObjectStableKey]   // ordered; .last is primary (anchor for handles/align)
    var isMarquee: Bool
    var isEmpty: Bool { objectKeys.isEmpty }
    var primary: PDFObjectStableKey? { objectKeys.last }
    var isMulti: Bool { objectKeys.count > 1 }
}
```
`@Published var objectSelection = ObjectSelection()`. Setting a non-empty selection clears `selectedAnnotation`/`selectedStampDecorationID` and dismisses any live `InlineTextEditorOverlay` (§7), preserving the single-selection-lane invariant (`:644-653`). **Selection stores `PDFObjectStableKey`, never a raw pdfium index.** After any commit-reload, the overlay **re-resolves** each key against the fresh `objectAnalysisCache` (§3.6); unresolved keys drop out silently.

### 5.3 Pipeline (returns a ranked list, so the pick and the chooser share one path)

```swift
struct ObjectHit { let object: DetectedObject; let region: HitRegion; let pointerDistance: CGFloat }
enum HitRegion: Equatable { case fill; case edge(distance: CGFloat); case handleSlop }
func objectHitTest(at viewPoint: CGPoint, on page: PDFPage, in pdfView: PDFView) -> [ObjectHit]
```
1. Reject boundary pages; resolve `pageRef(for:in:)` (`:6203`).
2. `q = pdfView.convert(viewPoint, to: page)` — native/unrotated space.
3. Scale-aware slop (§5.5) from `pdfView.scaleFactor`.
4. Per-object test (§5.5) → `HitRegion` + `pointerDistance`.
5. Filter background-like unless nothing else hit (§5.7).
6. Score + sort (§5.6).
7. `handleClick` takes `[0]`; if `[0]`/`[1]` are ambiguous (§5.8), open the chooser.

### 5.4 Page `/Rotate` — the coordinate contract (do not "un-rotate" the click)
`pdfView.convert(_:to: page)` already returns native/unrotated page space — proven by `editableTextBlock(at:)` feeding that point straight into `textAnalysisEngine.hitTest` (raw PDFium coords, no rotation math) and by `SignatureSelectionOverlayView` using plain `pdfView.convert` on rotated pages. `DetectedObject.boundsPdf` is in this same space; compare like-for-like directly. The only rotation at hit-test time is the **object's own** `transform` (§5.5.1). Page `/Rotate` is fully absorbed by PDFKit's `convert`. (One consequence for §8: the commit renderer normalizes `/Rotate` as `PDFEditedPageRenderer` does at `:19-33, :84`, and object geometry passed to it is already in this native space — no conversion at the selection→commit boundary.)

### 5.5 Per-object test (fill, edge, thin-line tolerance)

Distances are in **content-space points**; the slop is constant in **screen points** so targets feel identical at every zoom:
```swift
let kMinHitSlopScreenPts: CGFloat = 6, kEdgeGrabScreenPts: CGFloat = 4
let scale = max(pdfView.scaleFactor, 0.01)             // same guard as :3686
let slopContent = kMinHitSlopScreenPts / scale, edgeGrabContent = kEdgeGrabScreenPts / scale
```
- **Fill hit** — `pathData?.isFilled` and local point inside the path (even-odd/nonzero) → `.fill`, distance 0.
- **Thin-line / stroke hit** — min distance-to-segment over `pathData.flattenedStroke` (pre-flattened in detection); hit if `minSegDist <= max(style.lineWidth/2, 0) + slopContent + edgeGrabContent` → `.edge(distance:)`.
```swift
func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let ab = CGVector(dx: b.x-a.x, dy: b.y-a.y); let len2 = ab.dx*ab.dx + ab.dy*ab.dy
    if len2 == 0 { return hypot(p.x-a.x, p.y-a.y) }
    let t = min(1, max(0, ((p.x-a.x)*ab.dx + (p.y-a.y)*ab.dy) / len2))
    return hypot(p.x-(a.x+t*ab.dx), p.y-(a.y+t*ab.dy))
}
```
- **AABB fallback** — images/shadings: inside local AABB → `.fill`; within `slopContent` of an edge → `.edge`.

**5.5.1 Transformed/rotated objects.** Inverse-transform the click into object-local space (O(1) per object):
```swift
let affine = object.transform.cgAffineTransform      // PDFTextEditingModels.swift:58-60
guard affine.determinant != 0 else { return aabbTest(q, object.boundsPdf) }   // near-singular shear guard
let local = q.applying(affine.inverted())
```
**5.5.2 Minimum target size.** Inflate the hit region (never the drawn frame) so a 2×2pt icon stays clickable, mirroring the `-18` interaction-frame inset (`:1696-1701`):
```swift
let kMinTargetScreenPts: CGFloat = 12
let padX = max(0, (kMinTargetScreenPts - object.boundsPdf.width*scale)/2)/scale   // (padY symmetric)
let inflated = object.boundsPdf.insetBy(dx: -padX, dy: -padY)
```

### 5.6 Scoring — the exact seven-rule priority (lexicographic, not weighted)

| # | Rule | Better = |
|---|------|----------|
| 1 | Active tool mode | `toolAffinity` (exact 2 / neutral 1 / mismatch 0) higher |
| 2 | Clicked-object confidence | `confidence.rank` higher |
| 3 | Distance to edge/fill | fill (dist 0) beats edge; smaller edge distance |
| 4 | Z-order / frontmost | larger `zOrder` |
| 5 | Object size | smaller AABB area (small object atop a big one is the target) |
| 6 | Text-vs-graphic | in `.selectObject`/`.none`, graphic beats text; in `.editText`, text wins (§7) |
| 7 | Decorative/background-like | non-background beats background |

Implement as a `Comparable` tuple `(toolAffinity, confidence.rank, regionRank, -edgeDist, zOrder, -area, graphicRank, nonBackground)` and `sort` descending — Swift tuple `<` gives exact lexicographic precedence, no weights to tune.

### 5.7 Never selecting the page background
Classifier tags `isBackgroundLike` for ≥92%-crop-box objects, full-bleed rects, decorative artifacts. `let ranked = foreground.isEmpty ? hits : foreground` — a background object is chosen only when nothing else was hit (and rule 7 still keeps it last). Empty canvas → `[]` → `clearSelection()`.

### 5.8 Overlap & disambiguation chooser
Open the chooser only when `[0]`/`[1]` tie down to z-order/size (same tool-affinity, confidence, region, edge distance within 0.5pt); else pick `[0]`. The chooser is a lightweight SwiftUI popover (re-inject `\.locale`, `:537-568`) anchored at the click, listing tied objects in rank order with a kind glyph + z-order badge, using the `MoreMenuRow`/`MoreIconTile` kit (`:3094-3176`); hovering a row live-previews its outline, clicking commits, `Esc`/click-outside dismisses. **Cycle-on-repeat-click fallback:** clicking the same point again (within `kMinTargetScreenPts`, 1.2s) advances to `ranked[(prev+1) % count]` without reopening the popover ("⌥-click to cycle down the stack"). Copy keys: `objectPicker.title` → "Select object", `objectPicker.badge.front/back`, `objectPicker.kind.*` ("Shape/Line/Image/Group/Form field/Text/Gradient").

### 5.9 Gestures: single, Shift-click, marquee, Escape
Selection changes are **not undoable** (only edits register undo, `:1320`).
- **Single** — `objectHitTest` → pick/chooser → `select(single:on:)`: sets `objectKeys=[key]`, clears other lanes, dismisses any text editor, mounts the overlay at `pdfView.convert(boundsPdf, from: page)`.
- **Shift-click** — toggle membership; if the hit is on a *different* `pageRefID`, **replace** (single-page invariant). Multi-select draws a union box with **move + delete only** (no group resize in v1 — base resize is axis-aligned, no aspect lock, `:1850`).
- **Marquee** — drag on empty canvas **only while `.selectObject`**. Clone `CommentRegionOverlayView` (`:1389-1438`) into `ObjectMarqueeOverlayView`. **Critical:** that overlay's `hitTest` returns `self` whenever visible (`:1471-1473`) and would steal PDFKit's text-selection drag, so keep it `isHidden = true` except when `.selectObject` is active and no object is under `mouseDown`. On `mouseUp`, convert the rect to page space (`:1428-1435`, no rotation math) and select every object whose AABB **intersects** (not merely contains) the marquee and is not `isBackgroundLike`; Shift+marquee unions. Single-page only.
- **Escape** — `OrifoldPDFView.keyDown` (`:1227-1237`), keyCode 53, with §7.4 precedence; **falls through to `super.keyDown` when idle** so Escape still reaches the responder chain.

### 5.10 Live update / undo / delete hazard (cross-refs)
Selecting never mutates bytes. A committed move/resize/delete flows through §8's commit path. Two hazards this section respects but does not solve:
- **Delete must not repeat the visual-only-erase leak** — route through PDFium `RemoveObject`+`GenerateContent`+`SaveAsCopy` (`PDFCompressionService.swift:233, 250`), never `PDFEditedPageRenderer`, never `dataRepresentation()`. Selection supplies the durable key; the delete engine resolves it to a live pdfium index **at commit time**.
- **After any commit the document reloads** (`:2698-2701`); the overlay re-resolves `objectKeys` against the fresh cache and re-lays-out handles.

---

## 6. UX Design

All new AppKit drawing uses `NSColor.ds*NS`; all SwiftUI chrome uses `Color.ds*`/`Font.ds*`/spacing/radius tokens. No hardcoded colors/spacing/fonts. **The UX action set keys off the §4.1 capability set** (derived from the canonical `PDFObjectEditability`), not a second enum.

### 6.1 The mode
New `AnnotationTool.selectObject` case (`WorkspaceViewModel.swift:74-158`; `isColorable=false`, `isReaderModeAllowed=false`). Renders in `AnnotationToolPicker.toolGroups` (`ContentView.swift:1655-1662`); `select(_:)` (`:1935-1966`) mounts/dismisses the object contextual surface as it does signature/stamp palettes. New service-tint pair `dsObjectAccent`/`dsObjectAccentSoft` next to `dsEditTextAccent`/`dsSignatureAccent` (`DesignSystem.swift:56-97`), branched in `toolAccent`/`toolAccentSoft` (`:1913-1933`). **The whole feature is behind a feature flag** (Appendix A, decision 8); v1's object selection requires the explicit Select-Object tool so text editing is never disturbed.

### 6.2 Selection chrome (`ObjectSelectionOverlayView`)
Sibling of `SignatureSelectionOverlayView` (`:1654-1903`): clone its 8-handle geometry, `DragMode`, `handleRects` (`:1833`), `resizedFrame` min-size clamp (`:1850`), and `pdfView.convert(proposedFrame, to: page)` commit (`:1784`). Driven by a generalized `PageObjectSelectionTarget` (`:1624-1652`) carrying a `stableKey` alongside the existing annotation/stamp cases. Mounted last in z-order (its handles win over the draw-only `PageDecorationOverlayView` whose `hitTest` returns nil, `:1475`); subscribes to `.PDFViewScaleChanged` (`:1034`) + clip-view `boundsDidChange` (`:522-542`) so handles never drift; `hitTest` returns `self` only inside the interactive frame.

Visual spec (drawn in `draw(_:)`, mirroring `:1703-1738`):
- **Outline** — 1px `dsAccentNS`. For `rasterRegionReplace`/deferred objects, a dashed `dsAccentSoftNS` stroke signals "visual-only".
- **8 handles** — 8×8pt white squares (radius 2) with `dsAccentNS` border, shown only for editabilities permitting resize (§4.1); annotation/`overlayBacked` images offer aspect-locked corners only; `rasterRegionReplace` hides all resize handles.
- **Rotation handle** — a 10×10pt `EnsoRing` (`:369-387`) 20pt above top-center on a `dsSeparatorNS` stem, shown only when `capabilities.canRotate` (image/vector). Hidden for widgets/annotations/raster in v1.
- **Delete button** — 16×16pt circle + white X, `NSColor.systemRed` (the one semantic non-`ds` color, for destructive clarity). For `rasterRegionReplace` it dims and invokes the disclosed "Cover (visual only)…" flow.
- **Cursors** — body: `openHand`→`closedHand` on drag; handles: the per-handle `ResizeHandle` cursors (`:1884-1899`); rotation: a rotate cursor (fallback `crosshair`). Refreshed in `resetCursorRects()` on scale/scroll.

### 6.3 Object-type tooltip
On hover (via `NSTrackingArea`), a one-line tooltip at the outline's top-left names the type + editability — e.g. "Vector shape · editable", "Reused group · this copy only", "Table border · visual-only" — via `object.tooltip.format` = "%@ · %@". This is the primary way users learn *why* an object may be non-editable, replacing a wall of disabled controls. Styling: `Color.dsCard`, `dsRadiusSm`, `Font.dsCaption`, `dsElevation()`; re-inject `\.locale` if hosted.

### 6.4 Contextual object toolbar
A floating AppKit toolbar, sibling to `InlineTextEditorOverlay` (`:2351`), mounted like `showInlineTextEditor` (`:767`), positioned above the selection (flipping below near the top edge, using the clip-view-aware positioning at `:2730-2748` and subscribing to `boundsDidChangeNotification`). Primary controls inline; everything else in a **"More" overflow** reusing `ToolbarMoreMenu` + `MoreRoute` + `pendingMoreRoute` (`:2968-3176, 2932-2946`) — never a popover-out-of-a-popover-button (`:618-623`). All buttons reuse `ToolbarIconButton`/`ToolbarIconMetrics`/`ToolbarVerticalDivider`; presentation logic factored into its own `ViewModifier` (like `ToolbarOverflowPresentations`, `:2878`), never inlined into `ContentView.body`.

Inline controls (each shown only when §4.1 enables it; disabled ones render inactive **with an explanatory tooltip, never hidden**): **Duplicate** · **Delete** · ｜ · **Stroke color** · **Fill color** · **Opacity** · ｜ · **Layer** (forward/back) · **More** (line width, dash, align, distribute, replace image, reset, numeric fields). For images, stroke/fill collapse into **Replace image…**. For `rasterRegionReplace`, structural controls disable and Delete → "Cover (visual only)…".

**Optional numeric fields** — a "More" toggle reveals X/Y/W/H (PDF points) + a rotation-degrees field when supported; commit on Return/blur through the `constrainedSignatureBounds` cropBox clamp (`:3515`), producing one `OBJECT_TRANSFORM` op per commit. Values shown after applying the page-`/Rotate` inverse so the user sees on-screen coordinates.

### 6.5 Direct-manipulation UX requirements
- **No-jump drag (grab-offset).** On `mouseDown`, `grabOffset = mouseDownPagePoint − object.originPage`; during drag, `newOrigin = currentPagePoint − grabOffset`. (The current signature overlay lacks this offset term.)
- **No flicker (preview proxy above the cached bitmap).** The heavy `regenerate + rebuild` is **never** run per drag frame. The overlay draws a **preview proxy** — a `CGImage` snapshot of the object's region captured on `mouseDown` (via a `drawPageForSampling`-style off-screen raster, clipped to bounds), or the object's `CGPath` for vectors — and only `setNeedsDisplay` during the drag (the signature-drag technique, `:1770-1804`). Because content-stream objects are not PDFKit-drawn, the proxy is mandatory. To hide the still-visible original under the moving proxy, paint a `sampledBackgroundColor` patch (`PDFEditedPageRenderer.swift:404-458`) over the original bounds **for the preview only** — discarded on `mouseUp` (the committed bytes come from the structural write-back, never the patch).
- **Accurate cursor tracking at all zooms** — all conversion via `pdfView.convert` (incorporates `scaleFactor`); handle sizes from `max(pdfView.scaleFactor, 0.01)` (`:3685`).
- **Subtle snapping/guides** — snap to page edges, page center (H+V), and other objects' edges/centers (from `objectAnalysisCache`) within a 4pt view-space threshold; draw a 1px `dsAccentSoftNS` guide; **hold ⌥ to disable**. Guides drawn, never committed.
- **Rotated pages (highest-risk path).** v1 default: **if the Phase-2 coordinate test does not validate rotated-page write-back, `objectHit` returns non-editable on `pageRotation != 0`** and the overlay shows `object.error.rotatedPageUnsupported` (mirroring the existing rotation bail-outs at `WorkspaceDocument.swift:356, 369`). If it validates, convert view→page→raw-content-space via the inverse of `getDrawingTransform(.mediaBox, rotate:)` (`PDFEditedPageRenderer.swift:32-45, 81-96`) before writing the matrix. **Ship whichever the test validates; do not ship untested rotated-page transforms.** (Appendix A, decision 7.)
- **Crypto-signature guard** — every edit routes through `markAnnotationsModified(warnAboutSignatureInvalidation:)` (`:3345, 3468, 3503`).

### 6.6 New i18n keys
All keys in `Localizable.xcstrings` with en+es+fr+hi+zh-Hans+ja (or `LocalizationCoverageTests` fails, `:57-78`), via `L10n.string`/`L10n.format` passing `@Environment(\.locale)`; interpolation uses `%@`/`%lld`; new popovers re-inject `\.locale`.
- **Tool:** `annotationTool.selectObject.label` → "Select"; `.helpText` → "Select and edit objects on the page".
- **Types/editability:** `object.type.{vectorShape,image,path,formXObject,tableBorder,annotationObject,formWidget,group,shading}`; `object.editability.{editable,visualOnly,imageReplaceable,instanceOnly}`; `object.tooltip.format` → "%@ · %@".
- **Actions:** `object.action.{duplicate,duplicateAsOverlay,delete,coverVisualOnly,copy,paste,bringForward,sendBackward,alignLeft,alignCenter,alignRight,alignTop,alignMiddle,alignBottom,distributeH,distributeV,replaceImage,strokeColor,fillColor,opacity,lineWidth,dashStyle,resetTransform,rotate,showNumericFields}`.
- **Undo names:** `object.undo.{move,resize,rotate,delete,duplicate,replaceImage,style,reorder}`.
- **Numeric fields:** `object.field.{x,y,width,height,rotation}`.
- **Errors/disclosures:** `object.disabled.fallbackOnly`, `object.disabled.needsImage`, `object.cover.visualOnlyWarning` → "This only hides the object visually — the original data stays in the file. Use Redact for true removal.", `object.error.commitFailed`, `object.error.exportVerifyFailed`, `object.error.rotatedPageUnsupported`.

### 6.7 New keyboard shortcuts
Each added in **two** places (drift hazard, `ShortcutRegistry.swift:42-46`): `ShortcutRegistry.all` under `.editing` **and** a real binding. Delete reuses `onDeleteKey` (`:1227-1237`). Nudge/⌘D/copy/paste/layer/Esc are handled in a dedicated overlay `keyDown` (mirror `:4169-4205`); the overlay is `firstResponder` while a selection exists. Global-menu equivalents (Duplicate, Bring/Send) in `AppCommands.body` (`:18-59`).

| Action | Keys | Registry key |
|---|---|---|
| Nudge / Nudge×10 | arrows / ⇧+arrows | `shortcut.object.nudge` / `shortcut.object.nudgeLarge` |
| Duplicate / Delete | ⌘D / ⌫⌦ | `shortcut.object.duplicate` / `shortcut.object.delete` |
| Copy / Paste | ⌘C / ⌘V | `shortcut.object.copy` / `shortcut.object.paste` |
| Bring Forward / Send Backward | ⌥⌘] / ⌥⌘[ | `shortcut.object.bringForward` / `shortcut.object.sendBackward` |
| Cancel transform | Esc | `shortcut.object.cancel` |

---

## 7. Text vs Object Mode Interaction

### 7.1 Interaction modes (computed, not persisted)
```swift
enum CanvasInteractionMode: Equatable { case idle, textCaret, objectSelected, objectDragging, marquee, toolPlacement }
```
Invariant: **entering `textCaret` clears `objectSelection`; entering an object mode dismisses any live text editor** via the editor's existing `finishForHandoff()`/`Completion` teardown (`:614, 2370-2374`) — no new commit path. One lane is live at a time (extension of `:644-653`).

### 7.2 Arbitration decision table
Evaluated in `handleClick` after both `objectHitTest` (§5) and `editableTextBlock(at:)` run. "Text hit" = a real text region (not bare `.insertion` on empty space); "Object hit" = ≥1 non-background object.

| Active tool | Text? | Object? | Overlap? | Action |
|---|---|---|---|---|
| `.editText` | yes | any | — | **Edit text.** Object lane suppressed. |
| `.editText` | no | yes | — | No-op (objects not selectable while Text tool active; mode stays explicit). |
| `.editText` | no | no | — | Existing text behavior (caret/insertion, `:614-621`). |
| `.selectObject` | any | yes | — | **Select object.** Text lane suppressed. |
| `.selectObject` | yes | no | — | Select the text run *as an object* if classified selectable (rank rule 6); else no-op. Does **not** open the text editor. |
| `.selectObject` | no | no | — | `clearSelection()`. |
| `.none` | yes | no | — | Existing `.none` = annotation-only today; passive text-open here is a **new, flag-gated extension** (off until objects ship). |
| `.none` | no | yes | — | Select object (single). |
| `.none` | yes | yes | **yes** | Disambiguate by z-order + glyph-ink vs fill: fill of a frontmost graphic → object; glyph ink → text; tie → chooser listing both. |
| `.none` | yes | yes | no | Pick smaller `pointerDistance` (rule 3). |

With an explicit tool, **the tool is authoritative** (rule 1) — no cross-lane surprises. Only passive `.none` auto-arbitrates, and even then glyph-ink-vs-fill decides, falling back to the chooser rather than guessing. (Correction vs. an earlier draft: `.none` today does **not** open the inline text editor — that is `.editText`'s job; the passive text-open row is a new flag-gated behavior, not current behavior.)

### 7.3 Drag, double-click, toolbar
- **Dragging a selected object never starts text editing:** the overlay's `hitTest` returns `self` (`:1696-1701`) and it is in the `gestureRecognizerShouldBegin` guard (`:681-688`), so the drag enters `objectDragging`, never `textCaret`, even over a text run.
- **Double-click:** add a second `NSClickGestureRecognizer` (`numberOfClicksRequired = 2`) and `singleClick.require(toFail: doubleClick)`. Double-click **text** → enter text edit (`showInlineTextEditor`, `:767`), regardless of tool (the sanctioned crossover). Double-click **object** → object-specific edit (shape → inline stroke/fill/width; image → replace; `formXObject` instance → select-within *this instance's* children, editing which affects **only this instance** — see §4/§10, and the corrected Form-XObject semantics in Appendix A decision 2). Double-click empty → no-op.
- **Toolbar swaps with mode** (reusing the capsule + `select(_:)`, `:1935-1966`): `textCaret` → text-format controls; `objectSelected`/`objectDragging` → object controls (align/distribute/forward-back/duplicate/delete/stroke/fill/width) in a sibling contextual bar + `More` + a new object-properties Inspector tab (extend `InspectorView.Tab`, `:9-27`, **with its own localized keys** — the existing tab picker uses `Tab.rawValue` and is not localized). Text controls hide in object mode and vice versa.

### 7.4 Escape precedence (first match wins; one keypress peels one layer)
1. Chooser open → close, keep selection.
2. `objectDragging`/`marquee` in flight → cancel, revert to pre-drag bounds (no commit, no undo).
3. `textCaret` → editor handles its own Esc (commit/cancel, `:2370-2374`); then → `idle`.
4. `objectSelected` → `clearSelection()`; → `idle`.
5. `idle` → `super.keyDown` so Esc propagates (popover dismiss, reader-mode exit) — **do not swallow it** (unlike Delete, which always consumes).

---

## 8. Object Edit Lifecycle & Operation Model

> **CANONICAL operation model.** Follows inline-text conventions but the byte-level write-back runs through the **PDFium structural chain** (`GenerateContent`+`SaveAsCopy`, `PDFCompressionService.swift:201-256`), never `PDFEditedPageRenderer`. Ignore the alternate op names (`PDFObjectEditOperation`) from draft sections; the canonical op is `ObjectEditOperation`.

### 8.1 `ObjectEditOperation`
Added to `Orifold/Models/PDFObjectEditingModels.swift`, hand-written `init(from:)` with `decodeIfPresent` (mirroring `:247-283`).
```swift
enum ObjectEditType: String, Codable { case objectTransform, objectDelete, objectReplace, objectStyleChange, objectReorder }
enum ObjectReplacementStrategy: String, Codable {
    case pdfiumStructural   // SetMatrix/Transform/Set*Color/Width + RemoveObject/InsertObjectAtIndex + GenerateContent + SaveAsCopy (leak-free)
    case overlayComposite   // Orifold overlay (signature/stamp) baked on export; never a content-stream write
    case coverPatch         // visual-only cover (rasterRegionReplace ONLY; disclosed; DOES leak bytes)
    case qpdfRedact         // gated explicit "true removal" for content PDFium can't round-trip (fallback)
}
enum ObjectCommitState: String, Codable { case preview, committed, reverted }
struct ObjectStylePayload: Codable, Equatable {   // absent key = unchanged; CodableColor reused
    var strokeColor: CodableColor?; var fillColor: CodableColor?; var opacity: CGFloat?
    var lineWidth: CGFloat?; var dashArray: [CGFloat]?; var dashPhase: CGFloat?
}
struct ObjectEditOperation: Codable, Identifiable, Equatable {
    let id: UUID
    var type: ObjectEditType
    let documentID: UUID            // MemberDocument.id
    let pageRefID: UUID             // PageRef.id — durable join key
    var sourceObjectKey: PDFObjectStableKey   // §3.6, canonical durable identity
    var markedContentId: Int?       // FPDFPageObj_AddMark hint (Phase-0-gated, §8.5)
    var objectType: PDFObjectType
    var editability: PDFObjectEditability
    // geometry — RAW, UNROTATED content-stream space
    var originalBoundsPdf: CGRect; var newBoundsPdf: CGRect
    var originalTransform: PDFTextTransform; var newTransform: PDFTextTransform
    let pageRotation: Int
    // style
    var originalStylePayload: ObjectStylePayload?; var newStylePayload: ObjectStylePayload?
    // z-order (PDFium object-index order); realized by RemoveObject + InsertObjectAtIndex
    var originalZIndex: Int; var newZIndex: Int
    var replacementStrategy: ObjectReplacementStrategy
    var replacementImageData: Data?   // objectReplace only; keep to the RESAMPLED image (payload note §8.2)
    var committedState: ObjectCommitState
    let createdAt: Date; var updatedAt: Date
}
```

### 8.2 `PageObjectEditState`, persistence
```swift
struct PageObjectEditState: Codable, Identifiable, Equatable { let pageRefID: UUID; var operations: [ObjectEditOperation]; var id: UUID { pageRefID } }
```
Add `Workspace.objectEditStates: [PageObjectEditState] = []` next to `pageEditStates` (`Workspace.swift:140`), with a `CodingKeys` entry (`:143-145`), a `decodeIfPresent` line (`:164`), and a single `schemaVersion` bump (`:141`). `@Published workspace` wires mutations into autosave; the whole `Workspace` round-trips via `embedMetadata`/`metadata` (`:594-640, 560-587`). **Payload note:** `replacementImageData` and `editableMemberPDFData` are base64'd into a single page-0 annotation (`:612-635`), no chunking — keep `replacementImageData` to the resampled image and rely on the committed structural bytes in `memberPDFData` as the source of truth.

### 8.3 The lifecycle
1. **Select** — `objectHit(at:on:in:)` (new; modeled on `editableTextBlock`, `:2359`) via §2's enumerator, using `pageRef(for:in:)`/`memberPDF(for:)`/`localIndex(ref:memberIndex:)` (`:6203, 6237, 6245`) and `objectAnalysisCache` (§3.5). A click inside an existing op's bounds **reopens** it (re-route, `:2370-2399`). If `pageRotation != 0` and rotated-page write-back isn't validated (§6.5), return a non-editable `rotatedPageUnsupported` result.
2. **Preview (temporary)** — the overlay drags a **proxy** only (§6.5); a reopened op is mutated in a scratch copy (`committedState = .preview`). No write to `objectEditStates`, no regenerate, no undo, no autosave. Bytes untouched.
3. **Commit** (mouse-up / Done / field-Return), via a new `applyObjectEdit(_:)` modeled on `applyInlineTextEdit` (`:2545-2659`):
   1. Capture the shared snapshot (§8.4) **before** mutation.
   2. Build the op from the preview delta; clamp `newBoundsPdf` via `constrainedSignatureBounds` (`:3515`).
   3. **Upsert** into `objectEditStates` keyed by `sourceObjectKey` (mirroring the `sourceBlockID` upsert, `:2606-2635`): preserve the *original* baseline fields and `markedContentId` from the first op so successive drags **coalesce into one op** (solves the op-per-drag-tick gap).
   4. `committedState = .committed`, `updatedAt = now`.
   5. `regenerateObjectEditedPage(pageRef:operations:)` (step 4 below).
   6. `rebuild()` + `markWorkspaceModified()`.
   7. `registerIsolatedUndo` (`:1320-1331`) with localized `setActionName` (`object.undo.*`).
   8. On regenerate/validation failure, roll back to the snapshot **including member bytes** (fixing the text path's partial rollback at `:2641`): restore `objectEditStates`, `document.memberPDFData`, `loadedPDFs`, then `rebuild()`; surface `object.error.commitFailed`.
4. **Live update via structural write-back** — `regenerateObjectEditedPage` parallels `regenerateEditedPage` (`:2681-2709`) but replaces the `PDFEditedPageRenderer` call with a PDFium mutate pass in a **new engine `PDFObjectEditEngine`** (alias-`@_silgen_name`, holds `pdfiumLock` across load→mutate→save):
   - Starts from pristine `originalMemberPDFData`; applies **all committed ops for that member** to the in-memory PDFium doc; produces new member bytes via `SaveAsCopy`.
   - `objectTransform` → `SetMatrix`/`Transform` mapping `originalBoundsPdf`→`newBoundsPdf` in raw space.
   - `objectStyleChange` → `SetFillColor`/`SetStrokeColor`/`SetStrokeWidth`/`SetDashArray` from `newStylePayload`.
   - `objectReplace` → `LoadJpegFileInline`/`SetBitmap` (as compression, `:302`).
   - `objectReorder` → `RemoveObject` then `InsertObjectAtIndex(newZIndex)`.
   - `objectDelete` (structural) → `RemoveObject` + `Destroy` — **true removal, no leak.**
   - `objectDelete` on `rasterRegionReplace` → `coverPatch` only, behind the disclosed `object.cover.visualOnlyWarning`, via `drawErasePatch`/`sampledBackgroundColor` (`:147-155, 404-458`). **The sole intentionally-leaky path; the UI says so.**
   - `overlayComposite` ops (signatures/stamps) → **no content-stream write** at edit time; handled by existing overlay draw + export bakers. `regenerateObjectEditedPage` skips them.
   - Then `GenerateContent(page)` + `SaveAsCopy` → new member `Data`. **Object resolution is by `markedContentId` (if Phase-0-proven) or `sourceObjectKey` recomputation over the freshly-loaded objects (§8.5), never a stored index.**
   - **Mandatory validation gate** (before accepting bytes): reopen the produced `Data`; assert (a) page count unchanged; (b) per-page text unchanged for pages carrying text — using **`PDFTextAnalysisEngine`/`attributedString`, never `PDFPage.string`** (CI quirk, memory `ci-xcode164-pdfkit-string-extraction-quirk`); (c) the ghost/duplicate object-count guard (§8.5). On failure → step 3.8 rollback.
   - Write validated bytes into `document.memberPDFData` and reload a fresh `PDFDocument` (mirroring `:2698-2707`); clear `objectAnalysisCache` for the affected pages. **Do NOT route the PDFium output through `PDFSerializer`/`dataRepresentation` for the member bytes** — store the `SaveAsCopy` bytes directly (PDFKit still *loads* them for display, which is lossless; only PDFKit *re-serialization* is destructive).
5. **Undo/redo** — §8.4; restores geometry/style/z-order **and bytes**; integrates with ⌘Z/⇧⌘Z automatically.
6. **Persist** — `objectEditStates` rides `@Published workspace` → autosave → embedded metadata. Extend `sourcePayloadsForPDFMetadata` to bail when it is non-empty (`:340`).
7. **Export** — the H1-at-assembly landmine (§9). Committed structural ops are already leak-free in `memberPDFData`, but `concatenateForExport` (`PDFKitEngine.swift:83-104`) and comment/metadata stages re-serialize via `dataRepresentation()` and would re-destroy the layer. Mitigation: a **qpdf-preserving export assembly** (`PDFExportNormalizer`, §9) that splices edited member bytes unchanged and concatenates with qpdf; overlay bakes use the CGContext-direct path (`SignatureAppearanceRenderer.swift:309-355`) via a new `applyObjectExportAdditions` stage; `.preview` ops are skipped.
8. **Reopen-from-bytes verification** — after `writePDFExportData` writes atomically (`:4498-4534`), reopen the just-written file **from disk**, re-run the §2 enumerator on affected pages, and assert (per §9): each transform/style object present at `newBoundsPdf`/style within tolerance; each structural `objectDelete` object **absent** (`coverPatch` deletes are exempt — instead assert the patch is present); and the per-page object-count equals the expected post-edit count (ghost/duplicate guard). Failure aborts export → `object.error.exportVerifyFailed`.

### 8.4 Snapshot undo/redo (extend the shared snapshot; also handles multi-select batches)
Rename `InlineTextEditSnapshot` → `EditStateSnapshot` and add `objectEditStates`:
```swift
struct EditStateSnapshot {
    let editStates: [PageEditState]              // text
    let objectEditStates: [PageObjectEditState]  // NEW
    let pageRotations: [UUID: Int]
    let pdfData: [UUID: Data]                     // member bytes — the leak-free SaveAsCopy bytes
}
```
- **Capture** before commit; **Restore** sets both op arrays, rebuilds `loadedPDFs`/`memberPDFData` from `pdfData`, `objectAnalysisCache.removeAll()` + `textAnalysisCache.removeAll()`, `rebuild()`. Because restore reinstates the `SaveAsCopy` bytes, undo/redo is **byte-exact** (no `GenerateContent` re-run).
- **Batch/multi-select commit:** N object ops on one page are applied to the PDFium doc, then a **single** `GenerateContent`+`SaveAsCopy` runs for that page, under **one** `registerIsolatedUndo` group. Never one save per object (`applyObjectEdit` accepts an op array). Align/distribute and group edits fan out to N `objectTransform` ops committed this way.

**Align/distribute geometry** (multi-select): the anchor is the selection's **union bounding box**. Align L/C/R and T/M/B snap each object's edge/center to that union rect's edge/center; distribute H/V equalizes gaps between sorted object centers. Each produces one `objectTransform` matrixDelta; all batched.

**Copy/paste** serializes the object's reconstructable payload (kind, segments/bitmap, style, bounds) into an in-memory `ObjectClipboardItem`; paste **creates a new object** (`CreateNewPath`/`NewImageObj` + `InsertObjectAtIndex`) with a fresh `stableKey` — additive, no ghost. Cross-page paste clamps to the target cropBox (`constrainedSignatureBounds`, `:3515`); pasting an `overlayComposite`/annotation object appends the overlay model instead.

### 8.5 Durable identity (`sourceObjectKey`, with an AddMark optimization)
See §3.6 for `PDFObjectStableKey`. Two layers, **re-resolved from a fresh detection pass every load** (never trust a persisted cross-serialization byte digest):
1. **Optimization: marked-content id.** On the first structural write-back, stamp `FPDFPageObj_AddMark` and persist `markedContentId`; on later loads, re-select by scanning marks — exact. **Gated on Phase 0 proving marks survive `GenerateContent`+`SaveAsCopy`+reload** (unverified today; Phase 0 must add this assertion). If unproven, this layer is disabled and identity relies entirely on layer 2.
2. **Canonical: structural digest + disambiguators.** `structuralDigest` over rotation/translation/scale-invariant intrinsic content, recomputed from the live model each pass, matched then tie-broken by `quantizedBoundsHint` → `zOrderHint` → `typeHint` → `sourceXObjectName`. Because the digest excludes post-edit geometry, an op re-binds to the same physical object after index renumbering *and* after its geometry changed.
- For visually-identical overlapping twins (same digest), disambiguate by `markedContentId` if present, else by nearest `quantizedBoundsHint`; **pre-write, treat a digest collision as "user must re-select," never silently editing the wrong twin.**

---

## 9. Export & Serialization Strategy

The highest-risk section. Two audited hazards dominate:
- **H1 — PDFKit re-serialization destroys the text/vector layer.** Every export stage funnels through `PDFSerializer.data` → `dataRepresentation()` (`PDFSerializer.swift:10-23`), dropping Type3/Skia. Import protects via qpdf (`PDFImportNormalizer.swift:38-73`) but there is **no export-side equivalent** — and even a leak-free `SaveAsCopy` member is **re-serialized again** by `concatenateForExport` (`PDFKitEngine.swift:83-104`) and by comment/metadata re-serialization (`WorkspaceDocument.swift:445, 636`). "Lane A produced clean bytes" is necessary but **not sufficient**; the *assembly* must be hardened.
- **H2 — erase is visual-only / content leaks.** `PDFEditedPageRenderer.regeneratedPage` replays the *entire* original stream then paints an opaque patch over it (`:14-96, 147-155`). A vector move reusing this leaves a **ghost** + a **duplicate**. The single most important thing the object system must not repeat.

**Three lanes, chosen per object by editability:**
- **Lane A — PDFium structural rewrite** (`SetMatrix`/`Transform` + `RemoveObject` + `GenerateContent` + `SaveAsCopy`). The only leak-free, ghost-free path for native in-content objects; reuses the proven chain (`PDFCompressionService.swift:201-256`).
- **Lane B — overlay bake** for objects never in the original bytes (Orifold signatures/stamps/new shapes) — *additive*, no ghost. Modeled on `SignatureExportBakingSupport.bake` returning CGContext bytes directly (`:309-355`). (Its page redraw is still H1-exposed → route through the export normalizer on Type3/Skia pages.)
- **Lane C — cover-and-redraw fallback**, the *honest* last resort for shading/clipped/flattened. Explicitly a visual cover, never claimed as removal. True byte removal on a Lane-C delete is available only via the gated qpdf redaction action.

**Strategy → editability → engine (decision matrix):**

| Object type | Editability | Move/Resize/Rotate | Restyle | Delete | Duplicate | Engine |
|---|---|---|---|---|---|---|
| Image XObject | directImageEdit | `SetMatrix` | replace bitmap | `RemoveObject`+`Destroy` | `NewImageObj`+copy stream | PDFium (A) |
| Vector path/line/arrow/rect/ellipse/table border | directVectorEdit | `SetMatrix` | `SetStroke`/`Fill`/`Width`/`Dash` | `RemoveObject`+`Destroy` | `CreateNewPath`+replay segments | PDFium (A) |
| Form XObject instance | formXObjectInstanceEdit | placement matrix (this instance only) | n/a (source shared) | `RemoveObject` (this placement) | new `Do` on same source | PDFium (A), instance-only |
| Form XObject source (all copies) | formXObjectSourceEdit | **v1-deferred** | — | — | — | (gated qpdf, deferred) |
| PDFKit annotation/widget | directAnnotationEdit/formWidgetEdit | `annotation.bounds` | annotation props | remove annotation | copy annotation | PDFKit (B) |
| Orifold signature/stamp/new shape | directAnnotationEdit (overlay) | placement rect | swatch/style | drop model | append model copy | baker (B) |
| Shading (type 4) | unsupported/rasterRegionReplace | cover-redraw | n/a | cover → gated qpdf redact | n/a | CGContext + qpdf (C) |
| Clipped/masked soup | rasterRegionReplace | cover-redraw | limited | cover → gated qpdf redact | n/a | (C) |
| Flattened/scanned raster | rasterRegionReplace → directImageEdit | `SetMatrix` if single image; else region | replace bitmap | region | n/a | PDFium if image, else (C) |
| Locked/encrypted | lockedOrPermissionRestricted | blocked | blocked | blocked | blocked | none |

**Ghost avoidance — the critical rule.** Moving a vector/image object **mutates that one object's matrix in place**; `GenerateContent` re-emits the page from PDFium's model so the original op is *replaced*, not supplemented. One object before and after. **No cover patch. No `drawPageBackground` replay** for structural edits. Delete = `RemoveObject`+`Destroy` — the honest object-delete the audit says has "no existing path." (**Corrected:** delivery-draft's claim that a Form-XObject-instance transform changes *both* instances is wrong — each `Do` invocation is a distinct page object with its own CTM, so `FPDFPageObj_Transform` on it moves only that placement; changing all copies requires the deferred shared-source edit. See Appendix A decision 2.)

**Duplicate (PDFium has no clone API).** Create a new object of the same type and copy properties: image → `NewImageObj` + re-set bitmap + offset matrix + `InsertObject`; path → `CreateNewPath` + replay segments + copy style + offset + insert; annotation/overlay → append the model copy (`placeStamp`/`placeSignature`, `:3386, 3314`); Form XObject instance → a new `Do` on the same source name. Additive, fresh `stableKey`, no ghost.

**The export-side qpdf normalizer (H1 mitigation, mandatory).** New `PDFExportNormalizer.normalizedData(...)` in `Orifold/Engine/`, hooked before `writePDFExportData` (`:4536`), operating on the **final assembled document**:
1. Prefer a **qpdf-preserving assembly**: instead of `concatenateForExport`'s PDFKit re-serialize, concatenate the raw Lane-A `SaveAsCopy` member bytes with qpdf (structural merge, no `dataRepresentation()`), mirroring import's approach (`PDFImportNormalizer:38-73`), gated on `isTrustworthy` page-count agreement (`:79-91`).
2. For pages that went through a Lane-B/C bake, run a `QPDFService.sanitized`-style re-linearize (`:98-117`) on the assembled bytes — no `dataRepresentation()`.
3. Never `PDFPage.copy()` Lane-A/CGContext pages (`PDFKitEngine.swift:38-46`).
4. If qpdf assembly isn't viable (page-count disagreement, malformed member), fall back to `concatenateForExport` **and record the export is H1-exposed** so the reopen check catches a dropped text layer rather than shipping it silently.

> **This qpdf-preserving assembly is substantial new C-interop and is arguably the single hardest piece of the feature** (not a small splice). It is a first-class Phase 3 deliverable (Appendix A decision 5).

**Post-commit validation gate (mandatory).** `GenerateContent` rebuilds the whole stream and can perturb untouched operators; add `PDFObjectEditValidator`, modeled on `PDFEncryptionService.validateEncryptedData` (`:43-72`): page count unchanged; per-page text preserved on non-edited pages (via `PDFTextAnalysisEngine`/`attributedString`, **never `PDFPage.string`** — CI quirk); edited object present at `newBoundsPdf` (re-detect); **ghost canary — detection-based, not byte-digest** (re-enumerate objects intersecting `originalBoundsPdf`; assert none matching the moved object's `(type, structuralDigest)` remains — byte digests false-positive because `GenerateContent` legitimately reorders operators). On failure, roll back including member bytes.

**Reopen-fidelity verification (new — none exists today).** After `writePDFExportData`, reopen the written file **from disk bytes**, re-run detection on each edited page, assert every committed op's object present at `newBoundsPdf` (± tolerance) and no matching object at `originalBoundsPdf`; re-run the non-edited-page text canary against the pre-export snapshot to catch an H1 assembly drop. Byte-level, not in-memory. (`coverPatch` deletes are scoped out of the "no leak" assertion — see acceptance §13.)

**Export requirements checklist** (all must pass on exported-and-reopened file): no duplicate · no ghost (Lane A guarantees; Lane C is disclosed visual-cover) · object at new position · reopen shows edits from bytes · non-edited content unchanged (text canary; no raw byte-digest equality) · no orphaned streams · rotation/coords correct (verified on 90/180/270) · z-order preserved (`InsertObjectAtIndex`) · renders across Orifold/Preview/Chrome/Acrobat (qpdf structural check + manual QA spot-check for the first release, since cross-viewer `GenerateContent` fidelity is the untested risk) · crypto-safe (no silent signature break).

**Recommended primary engine:** **PDFium structural rewrite (Lane A), with qpdf reserved for assembly preservation + gated true redaction.** Justification: the mutate→`GenerateContent`→`SaveAsCopy` chain is already shipping/proven in Orifold (`PDFCompressionService`); it is the only lane offering per-object matrix/style mutation (the exact primitive that avoids ghosts by construction); `SaveAsCopy` sidesteps H1 at the member level. qpdf is co-primary only for assembly (concatenate raw member bytes structurally) and the gated "Flatten & redact region" action (`qpdf_oh_get_page_content_data`/`replace_stream_data`, `qpdf-c.h:930, 946`, wrapped in `withQPDF` recovery). qpdf is **not** the primary edit engine — a matrix-move via qpdf means hand-editing operator spans (fragile under its C++ exception model). Accepted trade-off: `GenerateContent` may perturb operator fidelity in pathological files → mitigated by the mandatory validation gate + reopen check.

---

## 10. Edge Cases

For each: detection / selection / edit / export / exact message. All copy in `Localizable.xcstrings` (6 languages; `%lld`/`%@` for interpolation); new popovers re-inject `\.locale`.

- **Scanned / image-only** — single full-page `IMAGE` → `directImageEdit` (whole page); path-soup → `rasterRegionReplace`. Whole-page image moves/replaces; overlays on top are fully editable. `objectEdit.scanned.wholePageOnly` → "This looks like a scanned page. You can move or replace the whole image, but individual marks inside a scan can't be edited separately."
- **Locked / permission-restricted** — reuse import smoke-check (`PDFiumProcessingEngine.validatePDF:31-76`) + PDFKit `allowsContentModification`; if not permitted, all objects `lockedOrPermissionRestricted`. **Hard block by policy** (PDFium's `SaveAsCopy` wouldn't itself enforce DRM — this is an explicit Orifold policy gate). `objectEdit.locked.blocked` → "This PDF's permissions don't allow editing its contents. Remove protection first (Tools ▸ Security) to edit objects." Deep-link the decrypt flow if the user holds the owner password.
- **Malformed** — `LoadMemDocument`/`GenerateContent`/`SaveAsCopy` errors or two-parser disagreement (`isTrustworthy:79-91`). Attempt qpdf repair (`withQPDF` recovery, `:147-148`); if it fails, block. Never write a member that fails the validation gate. `objectEdit.malformed.repairPrompt` → "This page couldn't be parsed cleanly. Orifold can try to repair it before editing." / on failure `objectEdit.malformed.blocked`.
- **Clipped** — `GetClipPath` → `hasClip`. Select by visible bounds, transform the full object matrix. Move preserves the clip; resize revealing hidden content is allowed but warned. `objectEdit.clipped.mayReveal` → "This object is clipped. Resizing it may reveal parts that were hidden."
- **Masked images** — image with `/SMask`/stencil (via `GetImageMetadata`, **new decl**). Move/resize keeps the mask; **replacement blocked** unless the replacement carries a compatible mask → `rasterRegionReplace` for replace. `objectEdit.masked.replaceUnsupported` → "This image has a transparency mask. Moving it works, but replacing it isn't supported yet."
- **Invisible artifacts** — `Tr 3` invisible text (`:113`), transparent fill, `/Artifact`. Hidden from normal selection; surfaced via an inspector "Show hidden objects" toggle (mirror the hidden/low-visibility text classification). On opt-in, delete uses real `RemoveObject` (leak-free — invisible OCR text is exactly the export-leak vector). `objectEdit.invisible.hiddenNotice`.
- **Very thin lines** — stroke width < ~0.75pt or 0. Inflate the hit rect (§5.5.2; mirror `stampDecoration` inset `-4`); preserve zero-width on restyle (don't coerce 0→1). No message.
- **Overlapping shapes** — top-most-first by z-order (`stampDecoration(at:).reversed()`); ⌥-click/repeat-click cycles; inspector lists all hits. `zOrderIndex` preserved on commit (`InsertObjectAtIndex`). `objectEdit.overlap.cycleHint` → "Multiple objects here. Click again or ⌥-click to select the one underneath."
- **Table borders** — many short `directVectorEdit` paths, each cell border usually its own op. Individual selection; marquee multi-select for group move; batch = N ops → **single** `GenerateContent`/`SaveAsCopy` per page under one undo group. `objectEdit.tableBorder.singleSegment` → "You're moving one border line. Select the whole table to move the grid together."
- **Repeated Form XObjects (instance vs source)** — multiple `FORM` objects referencing the same `sourceXObjectName`. Selects one placement (`formXObjectInstanceEdit`). **The default (and only auto) edit transforms this placement's matrix, changing only this instance.** Editing the shared source (`formXObjectSourceEdit`, v1-deferred) is never implicit — it is a gated explicit action with a count confirm. `objectEdit.formXObject.instanceNotice` → "This graphic is reused %lld times on this page. Your edit affects only this copy."
- **Grouped objects** — Form XObject bundling children (heuristic) or Orifold group (out-of-scope, must not break). Select the placement as a unit; double-click enters *this instance's* children (`directVectorEdit`/`directImageEdit` via `FPDFFormObj_GetObject`/`RemoveObject`). `objectEdit.group.enterHint` → "Double-click to edit objects inside this group."
- **Very large images** — move/resize is a matrix op (cheap, no re-decode); **do not rasterize on drag** (overlay proxy). Replacement decodes **off the `pdfiumLock` critical path** on a background queue. Matrix-only `SaveAsCopy` doesn't re-encode pixels. `objectEdit.image.tooLarge`.
- **High-DPI** — geometry is resolution-independent; handles subscribe to the same `.PDFViewScaleChanged` + clip-view `boundsDidChange` as the inline editor (`:1034, 522-542`). No message.
- **Rotated pages** — `PageRef.rotation` captured; convert on commit via the renderer's rotation-neutralization (`:32-45, 81-96`) — the double-rotation landmine the `pageRotation`-vs-`rotation` split prevents. `SetMatrix` operates in unrotated space, so un-rotate the drag delta before it becomes a matrix. Validation gate **re-runs specifically on 90/270**. v1 punt if not validated (§6.5). `objectEdit.rotated.unsupported`.
- **Multi-page** — `pageRef(for:in:)` skips `BoundaryPage` banners; guard `!(page is BoundaryPage)`. Ops per-page in `PageObjectEditState`. No message.
- **Undo/redo across pages** — `EditStateSnapshot` restores `objectEditStates` + affected member bytes + rotations for **all** touched members, so undoing on page 5 while viewing page 12 is safe; `syncDocumentPreservingViewport` handles the viewport. No message (menu shows the localized action name).
- **Copy/paste across pages** — additive new object at the target (§8.4); default same content-space offset, clamped to target cropBox. `objectEdit.paste.reposition` → "Pasted to fit this page." (only when clamped).
- **Objects outside page bounds** — clamp `newBoundsPdf` to the cropBox (`constrainedSignatureBounds:3515`); partial off-page allowed, fully-off-page prevented. `objectEdit.bounds.clamped` → "Kept the object on the page."
- **Deleting shared/reused objects** — delete removes **this placement's page object** (`RemoveObject`), not the shared source; `GenerateContent` drops the orphaned source only if this was the last reference. `objectEdit.shared.deleteInstance` → "Deleted this copy. %lld other copies remain." **Never** silently delete all instances.
- **Background watermarks** — distinguish Orifold-authored (`PageDecoration.kind == .watermark`) from native (large low-opacity object, often `/Artifact`). Orifold watermark → overlay, clean delete via `replaceDecorations` (`:2218`). Native detectable object → Lane A `RemoveObject` (leak-free). Native flattened → `rasterRegionReplace` cover → gated qpdf redact. `objectEdit.watermark.coverOnly` → "This watermark is part of the page content. Orifold can cover it, but to remove it from the file, use Flatten & redact." (no warning for the clean Orifold case).

---

## 11. Testing Matrix

All tests under `Tests/OrifoldTests/`, following existing conventions: fixtures built **in code** (there is no fixtures directory), an `NSView`/PDFKit page rendered via `view.dataWithPDF(inside:)` and reopened with `PDFDocument(data:)` (mirror `UserFlowRegressionTests.swift:12-28`, `QPDFServiceTests.swift:214-217`), assertions on `attributedString?.string` and `darkPixelCount` (`InlineEditExportHardeningTests.swift:105, 142-143`), PDFium/qpdf round-trips serialized under `pdfiumLock`. **A fixture that must contain a known-typed vector path or image XObject cannot come from `dataWithPDF` alone** — build it with the PDFium creation API (`CreateNewPath`/`NewImageObj` + `InsertObject` + `GenerateContent` + `SaveAsCopy`) so detection asserts on a deterministic object graph. New files: `ObjectDetectionTests`, `ObjectEditCommitTests`, `ObjectEditExportReopenTests`, `ObjectFixtureFactory` (helper), plus `LocalizationCoverageTests` additions.

**Legend:** **RP** = reopen-from-bytes; **PDFium** = object round-trip; **qpdf** = content-stream path; **px** = pixel assertion; **model** = pure Swift/undo assertion.

| # | Object type | Action | Expected | Method |
|---|---|---|---|---|
| 1 | Vector line | Select | Handles; `directVectorEdit`; smallest-containing hit | PDFium + model |
| 2 | Rectangle (stroke+fill) | Select | `directVectorEdit`; stroke/fill/width read via getters | PDFium + model |
| 3 | Image XObject | Select | `directImageEdit`; bounds+matrix read | PDFium + model |
| 4 | Table/grid borders | Select | Each border pickable; overlaps resolve topmost by z-order | PDFium + model |
| 5 | Existing signature annotation | Select | Reuses `PageObjectSelectionTarget` lane (`:1624`); no regression | model |
| 6 | Form widget | Select | `formWidgetEdit`; highlighted; no delete/restyle of contents | model (`isPDFWidget:220`) |
| 7 | Logo (large image) | Move | Translates; op carries correct delta; live update in place | PDFium + RP + px |
| 8 | Vector line | Nudge (arrows) | 1/10pt nudges coalesce into ONE op per gesture | model + PDFium |
| 9 | Rectangle | Resize (corner) | Scale-about-anchor matrix; Shift = aspect-lock | PDFium + RP + px |
| 10 | Image | Resize (edge) | Non-proportional `SetMatrix`; reopened occupies new rect | PDFium + RP + px |
| 11 | Image | Delete | `RemoveObject`+`Destroy`+`GenerateContent`; **gone from graph**, not covered | PDFium + RP (count decremented AND region background) |
| 12 | Vector rect | Delete | Object removed (not patched); no ghost ink | PDFium + RP + px (region ≈ background) |
| 13 | Image | Duplicate | New object at offset; count +1; both render; fresh identity | PDFium + RP + px |
| 14 | Vector rect | Change stroke/fill/width | Setters applied; reopened style matches | PDFium + RP |
| 15 | Vector rect | Change opacity | Fill/stroke alpha applied (shared `/ca`·`/CA` ExtGState is Loop-3 fallback); reopened alpha matches | PDFium + RP |
| 16 | Two overlapping images | Bring/send | Z-order changes via `RemoveObject`+`InsertObjectAtIndex`; reopened order matches | PDFium + RP + px |
| 17 | Any op | Undo | Inverse snapshot restores `objectEditStates` **and** member bytes; repaints | model + px |
| 18 | Any op | Redo | Re-registered inverse re-applies; identical state | model + px |
| 19 | Moved image | Save→reopen | Object at moved position **from bytes** | RP |
| 20 | Deleted rect | Save→reopen | Absent from enumeration AND region blank | PDFium + RP |
| 21 | Resized+restyled image | Save→reopen | Both persist; no ghost/duplicate | PDFium + RP + px |
| 22 | Any op, `/Rotate 90` | Move/resize | Geometry in unrotated space; lands correctly | PDFium + RP + px |
| 23 | Any op, `/Rotate 270` | Move/delete | As #22; no offset/mirror | PDFium + RP + px |
| 24 | Image, 3 zoom levels | Select+drag | Handles track during zoom; drag commits to same page rect at every zoom | model + px |
| 25 | Scanned/flattened page | Click a glyph | `rasterRegionReplace`; NO handles; localized banner | model + UI |
| 26 | Repeated Form XObject | Select+move one instance | `formXObjectInstanceEdit`; **only that instance moves; the other stays put**; instance notice shown | PDFium + RP + model |
| 27 | Shading/gradient (type 4) | Select | `unsupported`; move allowed (matrix), restyle/delete-to-blank disabled | PDFium + model |
| 28 | Clipped/masked | Select | `rasterRegionReplace`; move allowed with warning; structural delete disabled | model |
| 29 | Malformed PDF | Open + detect | Detection returns empty gracefully (no crash); "objects unavailable" | PDFium + qpdf (no-throw) |
| 30 | Locked/encrypted PDF | Detect | Short-circuits; object mode disabled until unlocked; no crash | model |
| 31 | Large PDF (500pg/~50MB) | Select+move | Detection cached per pageRef; first-click within budget; commit doesn't stall UI | perf (`measure {}`) + model |
| 32 | Text run under an object | Select object, then text | Object hit-test doesn't steal text clicks; `.editText` still reaches `editableTextBlock(at::2359)` | model |
| 33 | Op must not change page count | Commit | `currentPDFDataForExport` guard (`:1292`) not tripped; export succeeds | RP |
| 34 | `GenerateContent` fidelity | Commit any op | Untouched objects + real text survive the stream rebuild — reopened `attributedString?.string` still has the fixture's text | PDFium + RP (`attributedString`) |
| 35 | New string keys | CI | `LocalizationCoverageTests` passes for every `object*` key in all 6 languages | model (CI gate) |

**Rows 11, 12, 20, 34 are the highest-value guards** (structural delete proven from reopened bytes; text layer survives the rebuild). They must assert **from reopened bytes**. Row 26 is the Form-XObject correctness guard — **it asserts only the clicked instance moves** (correcting the earlier wrong "both change" fixture).

---

## 12. Verification Loops

Each loop is build → run → observe → fix, exited only when every criterion passes. End each with `swift build && swift test`; `LocalizationCoverageTests` green before a loop counts complete.

**Loop 0 (gate) — Phase-0 spike (see §16 Phase 0).** Prove on real fixtures that PDFium `GenerateContent`+`SaveAsCopy` round-trips move/delete/transform **without perturbing untouched text/vectors**, that identity survives (AddMark and/or structuralDigest), and that a co-located text run still extracts after commit. **If this fails, the structural architecture is revised before Loop 1** (narrow to annotations+images + disclosed cover-redraw). This gate is non-negotiable.

**Loop 1 — Architecture + basic selection (no export).** Model + detection for the three reliable types (annotation, image XObject, simple vector path); selection handles; move + delete; undo/redo; live in-canvas update. No export, Form XObjects, rotation, or styling. **Exit:** (1) clicking an image, a signature, and a stroked rect each shows the 8-handle overlay; blank click clears; (2) object hit-test doesn't break text editing (Test #32) and the overlay is in `gestureRecognizerShouldBegin` with correct `hitTest`; (3) move+delete commit as ops; canvas live-updates with no viewport jump; mid-drag preview is the overlay proxy, heavy regenerate only on mouseUp; (4) ⌘Z restores geometry AND bytes, ⌘⇧Z re-applies, undo-of-delete restores the object (Tests #17, #18); (5) detection cached per pageRef off the `pdfiumLock` hot path, first-click budget met on a 100-page fixture (Test #31); (6) `swift build && swift test` green, no new `pdfiumLock` deadlock under `ImportStressTests`.

**Loop 2 — Export + reopen reliability (hazard-critical).** Committed edits survive save → close → fresh reopen **from file bytes**. Build the `applyObjectExportAdditions` stage + PDFium `SaveAsCopy` bake (never `PDFSerializer`), the `PDFExportNormalizer` qpdf-preserving assembly, the post-commit/post-export validation gate, structural delete (PDFium primary; qpdf fallback), and the `objectEditStates` round-trip. **Exit:** (1) move/resize/delete/duplicate/restyle → Export → fresh reopen asserts each edit from bytes (Tests #19–21); (2) **no ghost** — deleted object absent + region background (Tests #11, 12, 20); (3) **no duplicate** — exactly one instance at the new location; (4) exported file passes the qpdf structural check + a real text run survives to reopened `attributedString?.string` (Test #34); (5) reopening restores `objectEditStates` for continued editing; (6) encryption path still passes (`validateEncryptedData:43-72`); (7) large-fixture export stays under (or consciously outside) the decoration size guards (`:29-30`).

**Loop 3 — Edge-case hardening + UX polish.** Fallback classification + copy (Form XObjects, repeated instances, table soup, shading, clipped/masked, scanned); rotated-page correctness; overlap disambiguation + cycle; resize/duplicate/style/z-order; nudge coalescing; snapping/guides; toolbar/inspector; align/distribute; multi-select batch commit. **Exit:** (1) every fallback type classified with specific localized copy, no destructive control it can't honor (Tests #25–28); (2) move/resize/delete pixel-correct on `/Rotate 90/270` from reopened bytes (Tests #22, 23) — or the documented v1 punt is in place; (3) overlapping objects individually selectable + reorderable, z-order persists across reopen (Tests #4, 16); (4) handles track through zoom+scroll (Test #24); (5) malformed/locked degrade gracefully, zero crashes (Tests #29, 30); (6) `LocalizationCoverageTests` green, `swift build && swift test` green, SwiftLint clean.

---

## 13. Acceptance Criteria

Done when every box is checked, each backed by a §11 test:
- [ ] **Select common objects** — lines, rectangles, ellipses, images, logos, signatures/stamps, form widgets, annotation objects, with visible handles (Tests #1–6).
- [ ] **Core operations on supported objects** — move, resize, delete, duplicate on the reliably-editable types; stroke/fill/opacity + bring-forward/send-backward on vector/image (Tests #7–16).
- [ ] **Object mode never breaks text editing** — a click on a text run still opens the inline text editor (in the default tool, unchanged behavior); object hit-testing ordered so `.editText` reaches `editableTextBlock(at::2359)` (Test #32).
- [ ] **Unsupported objects classified and explained** — scanned/flattened, shading, clipped/masked, repeated Form XObject instances detected and labeled with localized *why*, never a silent no-op; repeated-instance edits explain that only this copy changes (Tests #25–28).
- [ ] **Live update** — every committed edit updates the page in place, no viewport jump (Tests #7, 17).
- [ ] **Undo/redo** — every op a single undoable step; undo-of-delete restores the object; undo restores member **bytes**; batched nudges collapse into one op (Tests #8, 17, 18).
- [ ] **Save/export preserves edits and the text layer** — exported bytes contain the edits; a real text run survives the `GenerateContent` rebuild (Test #34); encryption/permissions still pass (Tests #19–21, #34).
- [ ] **Fresh reopen shows edits from bytes** — close+reopen shows every edit from file bytes, not app memory (Tests #19–23).
- [ ] **No ghost, no duplicate** — a deleted **structural** object is gone from the page-object graph with no leaked ink; a moved object exists exactly once at its new location (Tests #11, 12, 20). *(Scope: `rasterRegionReplace` cover-deletes are disclosed visual-only — they satisfy "no visual ghost" but the underlying bytes remain by design, surfaced to the user; they are not held to structural absence.)*
- [ ] **Large PDFs stay responsive** — detection/selection/commit on a 500-page/~50MB doc never stalls the main thread; detection cached per pageRef, off `pdfiumLock`'s hot path (Test #31).
- [ ] **Crypto signatures respected** — object edits on a signed document warn/invalidate consistently; no silent break.
- [ ] **Local-first / free / OSS preserved** — no network, no telemetry, no new paid dependency; all via bundled PDFKit/PDFium/qpdf; grep audit shows no new `URLSession`/analytics; license check clean.

---

## 14. Deliverable

The deliverable is **this document** — `docs/OBJECT_EDITING_PLAN.md` — a self-contained implementation plan for the Sonnet agent, covering architecture findings (§1), object model/data structures (§3), editability classification (§4), hit-testing (§5), UX (§6–§7), lifecycle + export (§8–§9), edge cases (§10), testing matrix (§11), verification loops (§12), acceptance (§13), risks (§15), phased steps (§16), and prioritization (§17). The canonical reconciliation decisions in **Appendix A** are part of the deliverable and must be honored so multiple implementers build one object system, not three. No code is written yet.

---

## 15. Risks & Mitigations

| # | Risk | L | I | Mitigation |
|---|---|---|---|---|
| R0 | **`GenerateContent` whole-stream rebuild is the load-bearing, least-validated assumption** — it can alter untouched objects/marked-content/inline images and is the mechanism identity must survive | Med | Critical | **Phase 0 gates the whole structural architecture** (§16). If the spike shows fidelity/identity loss on real fixtures, Strategies 2/3/5 and the "PDFium primary" recommendation are revised before Loop 1 (fall back to annotations+images + disclosed cover-redraw). Do not commit the architecture before the spike passes. |
| R1 | **Ghost / erase-leak on delete** | High | Critical | Route delete through PDFium `RemoveObject`+`Destroy`+`GenerateContent`+`SaveAsCopy` (rebuilds the stream with the object physically absent); never `PDFEditedPageRenderer` for object ops; gate on reopened count-decrement + region-blank (Tests #11, 12, 20). The single most important mitigation. |
| R2 | **Re-serialization destroys the text/vector layer** — `dataRepresentation()` drops Type3/Skia at member commit AND export assembly | High | High | Member bytes via `SaveAsCopy`, never `PDFSerializer`; **the `PDFExportNormalizer` qpdf-preserving assembly** (§9) handles H1 at export; post-commit text-preservation gate; Test #34. |
| R3 | **Export-assembly qpdf-preserving merge is substantial new C-interop** and is under-weighted if treated as a splice | Med | High | First-class Phase 3 deliverable (Appendix A decision 5); gate on `isTrustworthy` page-count agreement; fall back to `concatenateForExport` **and flag H1-exposed** so the reopen check catches a drop. |
| R4 | **Cross-serialization identity** — every persisted op re-binds after a reload that renumbers indices; AddMark durability is unverified | Med | High | Canonical `structuralDigest` recomputed from a fresh detection pass (never a persisted byte digest) + bounds/z/type tie-break; AddMark is a Phase-0-gated optimization with its own survival assertion; ultimate fallback = nearest-bounds (the text precedent). Proven in Phase 0, not assumed. |
| R5 | **Performance on large PDFs / commit holds `pdfiumLock`** — per-click re-parse or a big mutate+save+revalidate under the process-wide lock stalls the UI | Med | High | Detection cached per pageRef off the lock's hot path; drag preview is the overlay proxy; heavy regenerate only on mouseUp; **commit runs off the main actor with a progress indicator, preview stays until it resolves** (Appendix A decision 6); Test #31 budget. |
| R6 | **Hit-test ambiguity / gesture fighting** | Med | Med | Topmost-by-z pick, distance-to-segment tolerance, ⌥-cycle; preserve ordering so text wins where appropriate (Test #32); add the overlay to `gestureRecognizerShouldBegin` and get `hitTest` right. |
| R7 | **Rotation double-transform** on 90/180/270 pages | Med | High | Express geometry in unrotated content-stream space; reuse the renderer's normalize→re-tag; **v1 punts (disable transform on rotated pages with a message) unless the Loop-3 test validates it** (Appendix A decision 7); Tests #22, 23. |
| R8 | **Undo/redo correctness** — op-per-keystroke; failed regenerate leaves half-applied bytes | Med | Med | Coalesce deltas by `sourceObjectKey` (upsert `:2606-2635`); `registerIsolatedUndo` per commit; snapshot includes member `pdfData` and restore reinstates bytes (Tests #8, 17, 18). |
| R9 | **Crypto-signature invalidation** | Low | High | Thread `markAnnotationsModified(warnAboutSignatureInvalidation:)` (`:3345`); disable/warn object edits when a crypto signature is present (as `:405` already skips). |
| R10 | **PDFium API limits** — Form-XObject grouping heuristic; shading/clipped have no rich accessors | Med | Med | Classify fallback-only up front and restrict operations; ship "detected, explained, not editable." |
| R11 | **Scope creep** — all types × all ops at once destabilizes the reliable core | High | Med | Enforce the §17 do-first slice as a hard gate; reject any Loop-1/2 PR that adds a fallback type's write path. |

---

## 16. Phased Implementation Steps

Each phase is independently shippable (behind the `objectEditingEnabled` feature flag until Phase 5) and independently testable.

**Phase 0 — Spike: PDFium + qpdf round-trip proof (throwaway harness, 1–2 days; the architecture gate).** No production code merged. Load a fixture, enumerate objects, translate one image via `SetMatrix`, `GenerateContent`, `SaveAsCopy`, reopen the **bytes**; assert the image moved, count unchanged, and a co-located text run still extracts. Delete one object via `RemoveObject`+`GenerateContent`; assert count decremented + region blank. **Also assert AddMark survives `GenerateContent`+`SaveAsCopy`+reload**, and that `structuralDigest` (normalized geometry) re-matches after the round-trip. Spike qpdf `qpdf_oh_get_page_content_data`/`replace_stream_data` for one delete to confirm the fallback. Follows the native-build-verification approach (standalone harness, full call chain). **Purpose: de-risk R0/R1/R2/R4 before any UI. If it fails, revise the architecture here.**

**Phase 1 — Object model + detection (no UI).** Canonical types (`PDFObjectEditingModels.swift`): `PDFObjectEditability` (§4), `ObjectEditOperation`/`PageObjectEditState` (§8), `DetectedObject`/`PageObjectMap`/`PDFObjectStableKey` (§3); `Workspace.objectEditStates` + CodingKeys + `decodeIfPresent` + schemaVersion bump. New `PDFObjectDetectionEngine` (type-agnostic enumerator, alias-`@_silgen_name`) with per-pageRef caching and the stable-identity scheme. Classifies the three reliable types + all fallback types. **Tests:** `ObjectDetectionTests` (#1–6, #25–28 classification). Ships: detection API + model, zero UI.

**Phase 2 — Selection + move/delete + undo (live, no export).** Generalize `PageObjectSelectionTarget`; mount `ObjectSelectionOverlayView`; `objectHit(at:)`; `applyObjectEdit` → `regenerateObjectEditedPage` (PDFium path); snapshot extension carrying `objectEditStates` **and** `pdfData`; delete-key wiring; flag-gated `.selectObject` tool; overlay in `gestureRecognizerShouldBegin`. **Tests:** `ObjectEditCommitTests` (#7, #11 in-memory, #17, #18, #32). **Exit = Loop 1.** Ships: in-app move/delete/undo, live.

**Phase 3 — Export + true delete + reopen fidelity.** `applyObjectExportAdditions` in `exportedPDFDataThrowing:274`; PDFium `SaveAsCopy` bake (no `PDFSerializer`); **`PDFExportNormalizer` qpdf-preserving assembly**; post-commit/post-export validation gate; qpdf content-stream fallback delete; `objectEditStates` round-trip; extend `sourcePayloadsForPDFMetadata:340`; reopen-from-bytes assertion. **Tests:** `ObjectEditExportReopenTests` (#11, 12, 19, 20, 33, 34). **Exit = Loop 2.** Ships: edits that survive save/reopen with no ghost/duplicate — the first genuinely useful release.

**Phase 4 — Resize + duplicate + styling + z-order + multi-select batch.** Resize → `SetMatrix` scale-about-anchor (Shift aspect-lock); duplicate; stroke/fill/opacity via setters; bring/send via `RemoveObject`+`InsertObjectAtIndex`; nudge coalescing; multi-select batch commit + align/distribute; styling in inspector/`MoreRoute`. **Tests:** #8, 9, 10, 13–16. Ships: full transform+style toolkit on reliable objects.

**Phase 5 — Edge-case hardening + UX polish + un-flag.** Rotated-page correctness (or the documented punt); overlap disambiguation + snapping/guides; fallback explanations (incl. repeated-instance + Form-XObject); malformed/locked degradation; toolbar service tint + all `L10n`/xcstrings 6-language entries; overlay z-order finalized; **remove the feature flag**. **Tests:** #22–24, 26–31, 35; `LocalizationCoverageTests`. **Exit = Loop 3.** Ships: GA object editing.

---

## 17. Prioritization (Do First / Do Later)

**DO FIRST — Minimum Viable Slice (Phases 0–3):**
- **Types:** (1) image XObjects, (2) existing PDFAnnotations (signatures/stamps — already have a working selection lane), (3) simple stroked/filled vector paths (lines, rectangles, ellipses).
- **Operations:** select, move, delete, undo/redo — **plus** the non-negotiable export → fresh-reopen-from-bytes guarantee with **no ghost, no duplicate**.
- **Rotation:** unrotated pages only.

**Rationale:** these three types are the only ones the audit rates *reliable* (`FPDFImageObj_*`, `FPDFPath_*`, `FPDFAnnot_*` all linked). Annotations already ride the proven `PageObjectSelectionTarget`/`SignatureSelectionOverlayView` handle system, so selection is near-free. Move + delete are the first operations users reach for. Shipping export + reopen fidelity **early** forces R1/R2/R3 to be solved in the core rather than bolted on — a delete that leaks or an export that ghosts is worse than no delete at all. The slice is small enough to reach pixel-verified reopen correctness with high confidence.

**DO LATER (Phases 4–5+):**
- **Resize, duplicate, styling, z-order** — high value; layer onto the proven move/delete spine.
- **Form XObject instance transform** — ships in v1 as `formXObjectInstanceEdit` *only after* Phase 0 confirms per-placement matrix edits round-trip; **shared-source editing (`formXObjectSourceEdit`) is deferred** (classify + explain first).
- **Rotated-page editing** — correctness-critical, smaller segment; do-first on unrotated pages, harden in Loop 3.
- **Shading/gradients, clipped/masked, scanned/flattened** — fallback-only, likely permanently. Ship as "detected, explained, not editable."
- **Multi-select, grouping, align/distribute, rotation handles, snapping** — UX richness, low fidelity risk, large surface. Defer.

**Guiding rule:** ship *depth on the reliable three* (move/delete → export/reopen → resize/duplicate/style) before *breadth across object types*. Breadth without byte-level reopen fidelity ships the exact leak-and-ghost failures R1/R2 warn against.

---

## Appendix A — Canonical Reconciliation Decisions (read before writing model code)

The design workstreams independently invented incompatible versions of the same models. These are the binding decisions; do not re-introduce the alternatives.

1. **Object identity → one type: `PDFObjectStableKey` (§3.6).** Equality is `pageRefID + structuralDigest` only; `structuralDigest` is over **mutation-invariant intrinsic content** (path segment topology normalized to local origin; decoded-image pixel digest), **recomputed from a fresh detection pass every load — never a persisted cross-serialization byte digest**. `quantizedBoundsHint`/`zOrderHint`/`typeHint`/`sourceXObjectName` are ranked disambiguators, not equality terms. This reconciles the detection workstream's content-hash, the hit-test workstream's opaque token, and the export workstream's "re-hash from the live model, never across serialization" mandate — they are the same scheme stated once. `markedContentId` (AddMark) is an **optional in-session optimization, gated on Phase 0 proving it survives `GenerateContent`+`SaveAsCopy`**; identity never *depends* on it. Ultimate fallback if neither survives: nearest-bounds (the shipping text-edit behavior).

2. **Form XObject instance semantics — corrected.** `FPDFPageObj_Transform`/`SetMatrix` on a `FORM` page object mutates **only that placement's CTM** (each `Do` invocation is a distinct page object). Moving one instance moves **only** that instance. `formXObjectInstanceEdit` therefore **ships in v1** (move/resize/rotate/delete/duplicate the placement). Editing the shared `/Form` source so **all** copies change is `formXObjectSourceEdit`, **v1-deferred** (gated explicit action). **This overrides** (a) the UX draft's "Form-XObject instances are fallbackOnly," and (b) the delivery draft's Test #26/R7 claim that "the default edit rewrites the shared stream so BOTH instances change." Test #26 asserts **only the clicked instance moves**.

3. **Delete engine primacy.** PDFium `FPDFPage_RemoveObject`+`FPDFPageObj_Destroy`+`GenerateContent`+`SaveAsCopy` is the **primary, leak-free** delete (rebuilds the stream with the object physically absent). qpdf content-stream editing is a **fallback only** for pages PDFium won't round-trip. `coverPatch` is for `rasterRegionReplace` **only**, disclosed as visual-only. **This overrides** any framing of qpdf as the "true delete" and PDFium as insufficient.

4. **Editability → one enum: `PDFObjectEditability` (§4)**, 11 cases matching the user's spec (incl. `formXObjectSourceEdit`, v1-deferred). The 5-case (UX) and 7-case (export) variants become the **derived `ObjectCapabilities`** set (§4.1) that UI/hit-test/export dispatch key off — not competing enums.

5. **One op struct: `ObjectEditOperation` (§8.1)** with `PageObjectEditState`, `Workspace.objectEditStates`, and a **single coordinated `schemaVersion` bump**. One detected-object struct: `DetectedObject` (§3.3). One cache: `objectAnalysisCache: [UUID: PageObjectMap]`. Confidence: the **reused** `PDFTextEditConfidence` + `.rank` (never a new confidence enum).

6. **Export-assembly H1 is a first-class, hard deliverable.** The `PDFExportNormalizer` qpdf-preserving assembly (§9) is substantial new C-interop, scheduled in Phase 3, not treated as a splice. Even leak-free member bytes are re-destroyed by `concatenateForExport` without it.

7. **Concurrency for commit.** Detection runs off the `pdfiumLock` hot path (cached). **Commit** holds `pdfiumLock` across load→mutate→`GenerateContent`→`SaveAsCopy`→validate; for large docs it runs **off the main actor with a progress indicator**, and the drag preview proxy stays visible until the commit resolves.

8. **Rotated pages: v1 default is the explicit punt.** Object editing on `/Rotate != 0` pages is **detect+select only, transform disabled with a disclosure**, matching the existing rotation bail-outs (`WorkspaceDocument.swift:356, 369`) — **unless** the Loop-3 coordinate test validates rotated-page write-back, in which case it ships. The plan owns this decision rather than leaving it to an unwritten test.

9. **Feature flag & text safety.** The whole feature is behind `objectEditingEnabled`. v1 object selection requires the explicit `.selectObject` tool; the passive `.none`→object/text arbitration extension is flag-gated and off until objects ship. This is why acceptance criterion "a click on a text run still opens the text editor" holds — the **default** tool's behavior is unchanged.

10. **Validation canary is CI-safe.** Text-preservation checks use `PDFTextAnalysisEngine`/`attributedString`, **never `PDFPage.string`** (memory `ci-xcode164-pdfkit-string-extraction-quirk`). The ghost canary is **detection-based** (re-enumerate at `originalBoundsPdf`), never raw byte-digest equality (`GenerateContent` legitimately reorders operators).
