# Feature Waves Master Plan (Open-Source & Free-Data Roadmap)

> **For agentic workers:** This is the coordination document for implementing all 15 High/Medium-High features from `docs/OPEN_SOURCE_FEATURE_ROADMAP.md`. Each wave is executed in its own session. Wave 1 has a full step-by-step plan (`docs/WAVE_1_QUICK_WINS_PLAN.md`); Waves 2–4 have briefs below — **each wave's session MUST first re-verify the brief's file anchors against fresh code and expand the brief into a full plan (superpowers:writing-plans) before implementing (superpowers:test-driven-development).** Update the status table here as features land.

**Goal:** Ship all 5 High-confidence + 10 Medium-High-confidence features, quick-wins first, one wave per session, TDD throughout.

**Architecture:** Every feature builds on already-verified engine surface (all needed PDFium symbols confirmed exported by the vendored dylib; qpdf C API already linked via CQPDF). Only Wave 3's compression pack requires binary work (QPDF.xcframework rebuild). No feature adds a mandatory network call.

**Tech Stack:** Swift/SwiftUI (macOS 14 target), PDFKit, PDFium (`@_silgen_name` bindings), qpdf 12.3 (CQPDF), Vision, AVFoundation, Core Image.

## Global Constraints (apply to every task in every wave)

- Deployment target stays **macOS 14.0**; newer APIs go behind `#available` (repo precedent established by Wave 4's translation feature; none exist before that).
- **Offline-first:** no new mandatory network calls. Optional downloads only via GitHub Releases (existing update-channel pattern).
- **License hygiene:** every bundled asset gets an entry in `Orifold/Resources/THIRD-PARTY-NOTICES.md` in the same commit that adds it.
- **L10n:** every user-facing string added to `Localizable.xcstrings` in **all 6 languages** (en, es, fr, hi, ja, zh-Hans) — the coverage test fails otherwise. Non-SwiftUI strings via `L10n.string(_:locale:)`; SwiftUI views must read `\.locale` or live-switch breaks.
- **New files:** SPM picks up new Swift files automatically; Xcode CI regenerates pbxproj via `xcodegen generate` — never hand-edit `Orifold.xcodeproj`.
- **Preserving pipeline:** any feature that mutates member PDF **bytes** must run through `QPDFService` structural validation and the existing ops↔bytes reconcile path (see `WorkspaceViewModel` reconcile + `PDFImportNormalizer`); never re-serialize via PDFKit `dataRepresentation()` (destroys the preserved text layer).
- **Verification:** every wave ends with `swift test`, a release build (`swift build -c release` — catches `@_silgen_name` duplicate-binding breaks), a local install + **hands-on click-through** of each new feature (view-layer bugs are invisible to tests), then merge + push to main.
- **CI text-extraction quirk:** never assert on `PDFPage.string` equality in tests (Xcode 16.4 SDK interleaves/undercounts); use PDFium `FPDFText_*` extraction or `attributedString`.

## Status

| Wave | Feature | Confidence | Status |
|---|---|---|---|
| 1 | Spell-check in inline editor | Med-High | ✅ |
| 1 | Metadata viewer/editor | High | ✅ |
| 1 | Read-aloud with follow-along | High | ✅ |
| 1 | CC0 demo/onboarding document | Med-High | ✅ |
| 2 | Font-substitution pack + Core-14 AFMs | High | ✅ |
| 2 | Hanko stamp studio | Med-High | ✅ |
| 2 | Barcode/QR insert + scan | High | ✅ |
| 3 | Compression pack v2 (zopfli, mozjpeg, JBIG2) | Med-High | ☐ |
| 3 | Attachments manager | Med-High | ✅ |
| 3 | Booklet / N-up imposition | Med-High | ✅ |
| 3 | Scan cleanup ("Scan mode") | Med-High | ☐ |
| 4 | Offline translation (macOS 15 gate) | High | ☐ |
| 4 | Archival readiness hints | Med-High | ☐ |
| 4 | Structure/reading-order inspector | Med-High | ☐ |
| 4 | CJK/brand font pack (+ embedding spike) | Med-High | ☐ |
| 4 | CBZ → PDF import | Med-High | ☐ |

(16 rows because CBZ rides in Wave 4 as a small extra; macOS-26 tier is explicitly out of scope until CI's Xcode bumps.)

## Session protocol (every wave)

1. Read this doc + the wave's brief/plan. Re-verify every file:line anchor (`grep` before trusting — shared repo moves fast).
2. Expand brief → full plan via superpowers:writing-plans (Wave 1: already written, still re-verify anchors).
3. Implement via superpowers:test-driven-development, committing per task; merge + push to main per feature (standing rule).
4. Bump version + `docs/release-vX.Y.Z.md` at wave end; update the Status table above; refresh `docs/OPEN_SOURCE_FEATURE_ROADMAP.md` tiers if findings changed.
5. Hands-on click-through of each shipped feature in the installed app (delete stale Orifold.app copies first — `mdfind` sweep).

---

## Wave 1 — Quick wins (full plan: `docs/WAVE_1_QUICK_WINS_PLAN.md`)

Spell-check, metadata editor, read-aloud, demo document. No new dependencies, no binary work. Target: one session, version bump at end.

## Wave 2 — Editing depth + brand

### 2A. Font-substitution pack + Core-14 AFM metrics
- **What:** Bundle Liberation Sans/Serif/Mono (OFL-1.1), Carlito (OFL-1.1), Caladea (**Apache-2.0**, not OFL) + Adobe Core-14 AFM metrics (redistributable with notice retention — ship the license file; PDFBox precedent). Replace the ad-hoc fallback (`editingFamilyName(for:fallback:)` in `ReadingCanvas.swift` ≈4383; blind `"Helvetica"` default in `WorkspaceViewModel.swift` ≈2868; subset-tag normalization ≈2783) with a substitution table: PDF font name → metric-compatible bundled font, AFM-driven width checks for the Core-14.
- **New units:** `Engine/Fonts/FontSubstitutionTable.swift` (pure lookup, heavily unit-tested), `Engine/Fonts/AFMMetricsStore.swift` (parse bundled AFMs once, expose `advanceWidth(glyphName:)/width(of:in:)`), font registration at app start (`CTFontManagerRegisterFontsForURL`, process scope).
- **Assets:** `Orifold/Resources/Fonts/` via `.copy` resources; ~7–8 MB. THIRD-PARTY-NOTICES entries: Liberation, Carlito, Caladea, Adobe AFM notice.
- **Tests:** substitution-table mapping (Arial→Liberation Sans etc., subset-prefixed names, bold/italic variants); AFM parser against a bundled file (known width for 'A' in Helvetica.afm = 667); render-side: edited text with unembedded Arial resolves to Liberation Sans (assert via `CTFontCopyPostScriptName`), not Helvetica.
- **Gotchas:** registration must happen before first edit render; L10n for any "substituted font" UI hint; DMG grows — update download-page copy if it states a size.

### 2B. Hanko stamp studio
- **What:** Procedural personal seal — circle/square border + user's name set vertically in Shippori Mincho, shu-iro vermillion — as a new stamp source next to the 5 text presets in `StampPalette.swift` (presets ≈108–163, placement via `beginStampPlacement`). Reuse glyph-path infra from `SignatureAppearanceRenderer.swift` ≈177–238 (`CTFontCreatePathForGlyph` → vector paths) and the decoration bake pipeline (`PDFDecorationExportBaker.swift`).
- **Depends:** Shippori Mincho bundled (do in Wave 2 alongside 2A's font-registration plumbing; the full CJK pack stays Wave 4).
- **New units:** `Engine/Stamps/HankoRenderer.swift` (pure: name + style → CGPath/NSImage; unit-testable geometry), `Views/HankoDesignerView.swift` (live preview, name field, circle/square, size).
- **Tests:** renderer determinism (same input → same path bounds), 1–4 char CJK layout vs latin fallback layout, bake round-trip (stamp survives export; reuse existing bake-stamp test patterns). UI copy includes the "decorative, not a registered jitsuin" note (L10n ×6).
- **Gotchas:** bake-stamp annotation-leak — audit every `.annotations`/`type ==` site when adding a new internal annotation type (shipped 2026-07-07 lesson).

### 2C. Barcode/QR insert + scan
- **What:** Generate QR/Aztec/PDF417/Code128 via Core Image (`CIQRCodeGenerator` etc.) and place through the stamp/image lane (`FPDFImageObj_SetBitmap` already silgen-bound in `PDFCompressionService.swift` ≈41, or simpler: stamp-palette image placement + bake). Detect via `VNDetectBarcodesRequest` on the OCR rasterizer output (`PDFOCRService.renderedImage(for:)` ≈277) with a "Copy payload / Open link (confirm)" result sheet.
- **Tests:** generate→detect round-trip in-memory (CIImage → VNDetectBarcodesRequest recovers payload); placement bake round-trip; payload-size limits (QR max ~2953 bytes → validation error).
- **Gotchas:** link payloads are untrusted input — show URL before opening; error-correction level default M; zxing-cpp explicitly NOT added (Core Image formats suffice).

## Wave 3 — Engine work

### 3A. Compression pack v2 (the only binary work in the roadmap)
- **Order within task:** (1) rebuild `Packages/QPDFBinary/QPDF.xcframework` from qpdf 12.3 source with `-DZOPFLI=ON` (zopfli Apache-2.0; hooks verified already present in current lib) and mozjpeg (IJG/BSD-3/zlib) replacing libjpeg-turbo — follow the original build recipe used 2026-07-04 (universal arm64+x86_64, native crypto); (2) surface a "Maximum (slow)" compression preset that sets `QPDF_ZOPFLI=force` env / write-param; (3) jbig2enc v0.32 (Apache-2.0) + Leptonica (BSD-2) as a NEW `Packages/JBIG2Binary` for 1-bpp scan pages — **lossless generic mode only, never symbol mode** (character-substitution hazard) — spliced via qpdf stream replacement.
- **Tests:** byte-level: zopfli preset produces valid PDF (structural gate) ≤ baseline size; mozjpeg re-encode preserves dimensions/colorspace; jbig2: 1-bpp fixture shrinks vs CCITT G4 and round-trips pixel-identical (lossless assertion via PDFium render + hash). Release-build check mandatory (silgen memory).
- **Gotchas:** rebuild must keep the empty-document/encrypted-PDF exemptions that the original qpdf merge fixed; THIRD-PARTY-NOTICES for zopfli/mozjpeg/jbig2enc/Leptonica; verify `swift build -c release` and CI both link the new xcframework.

### 3B. Attachments manager
- **What:** List / extract / add / remove embedded files. **Use qpdf, not PDFium's experimental API:** low-level `qpdf_oh_*` surgery on `/Names/EmbeddedFiles` (the sanitize pass already strips this key — `QPDFService.swift` ≈108 — so the object shape is known) or `qpdfjob` JSON (`--add-attachment`/`--remove-attachment`, symbols verified present).
- **UI:** new Inspector tab "Attachments" (paperclip icon) following the existing `InspectorView.Tab` enum pattern; drag-in to add, per-row extract (NSSavePanel) / remove.
- **Tests:** add→list→extract byte-identical round-trip; remove; interaction with sanitize (sanitize still strips all); encrypted-PDF behavior; export preserves attachments through the preserving pipeline.
- **Gotchas:** extraction of attachments from untrusted PDFs — quarantine flag the written file (`NSURL` quarantine attrs); size display; attachments must survive the bake/export path (add a regression test — export paths bypassing gates was a real historical bug).

### 3C. Booklet / N-up imposition
- **What:** Bind `FPDF_ImportNPagesToOne` + `FPDF_ImportPages` (verified exported); new export option "Imposition: 2-up / booklet" + print-dialog n-up. Booklet = compute signature page order (n, 1, 2, n-1, …) via `FPDF_ImportPages` range string, then 2-up.
- **Critical ordering:** impose **after** the decoration-bake pipeline — N-up flattens pages into XObjects and **drops annotations** (verified header behavior).
- **Tests:** page-order math (pure function, exhaustive for 1–16 pages incl. non-multiple-of-4 padding); output page count; content presence via PDFium text extraction; annotations-baked-first regression test.

### 3D. Scan cleanup ("Scan mode")
- **What:** Pre-OCR pipeline: `VNDetectDocumentSegmentationRequest` (macOS 12+, no gate needed) for crop/perspective → vImage adaptive threshold/contrast → optional Leptonica deskew/despeckle (free if 3A shipped jbig2's Leptonica; otherwise skip Leptonica and ship Vision+vImage only). Swap cleaned bitmap back via the bound `FPDFImageObj_SetBitmap` lane. UI: "Clean up scan…" sheet with before/after preview, per-page or whole-doc.
- **Tests:** pure-function image ops on fixture bitmaps (skew angle recovered within tolerance; threshold output is 1-bpp); page-swap round-trip passes structural validation; OCR-after-cleanup confidence ≥ OCR-before on a skewed fixture.
- **Gotchas:** quality spike FIRST (one skewed/shadowed fixture through the pipeline) before building UI; keep original bytes for undo via the existing pristine-base mechanism.

## Wave 4 — Positioning features

### 4A. Offline translation (macOS 15 `#available` gate — repo's first)
- **What:** Translate selection/page via `TranslationSession` (verified macOS 15+, third-party-capable, batch `translations(from:)`). Session must come from SwiftUI `.translationTask` — architect as: gated view-modifier host + result panel (side-by-side original/translated, copy button). NOT an edit operation (no write-back into the PDF in v1).
- **Gate pattern to establish:** `if #available(macOS 15, *)` at the feature-surface level; menu item hidden below 15. CI (Xcode 16.4/macOS 15 SDK) compiles it.
- **Disclosure:** first-use sheet: Apple's system service downloads language models (OS-level, not an app network call) — honest wording next to "Nothing leaves your Mac" (L10n ×6).
- **Tests:** text-chunking (session batch limits), gating logic (feature hidden on 14 — compile-time test via availability shim), UI presence. Actual translation is not CI-testable — protocol-wrap the session for a fake.

### 4B. Archival readiness hints (PDF/A-lite)
- **What:** Read-only checklist panel: encryption present? JS/OpenAction? all fonts embedded? OutputIntent? XMP present? Tagged (`FPDFCatalog_IsTagged`, verified exported)? Uses existing CQPDF `oh` API (in use at `QPDFService.swift` ≈229–283) + PDFium introspection. Copy says **"archival readiness hints" — never "PDF/A validation"**.
- **Oracle:** add veraPDF (MPL option) as a CI-only job comparing verdict direction on fixtures; never shipped in-app.
- **Tests:** one fixture per check (encrypted, JS-bearing, unembedded-font, tagged, untagged…), each flag flips exactly as expected.

### 4C. Structure / reading-order inspector
- **What:** Bind `FPDF_StructTree_GetForPage` / `FPDF_StructElement_GetType/GetAltText/CountChildren` (verified exported, read-only). Inspector section: structure tree outline; "untagged document" accessibility warning; alt-text presence per image.
- **Tests:** tagged fixture → expected tree shape; untagged fixture → warning; struct-element bindings release-build safe (silgen rule: one binding per symbol).

### 4D. CJK/brand font pack (+ mandatory spike)
- **What:** Noto Sans JP/SC as optional GitHub-Release pack (~25–40 MB) using the update-channel download pattern; Shippori already bundled by Wave 2. **Spike FIRST:** embed a large CJK font into an edited PDF via `FPDFText_LoadFont` (verified exported) and measure output size — if PDFium doesn't subset (bloat >2–3 MB per doc), constrain scope to substitution-for-display + warn on export.
- **Tests:** spike is the test; then substitution-table entries for common JP/SC font names (MS Mincho, SimSun, Hiragino…), download-pack verify (checksum, license file included).

### 4E. CBZ → PDF import
- **What:** Add ZIPFoundation (MIT, SPM) — read-only archive use, sandbox-fine; unzip images in natural-sort order → existing images→PDF lane (`PDFKitEngine.renderImage` ≈313). Register `.cbz` in import types + Info.plist document types.
- **Tests:** fixture CBZ (3 tiny PNGs) → 3-page PDF in correct order; corrupt-zip error path surfaces `LocalizedError`; natural sort ("page2" < "page10").
- **Gotchas:** EPUB explicitly out of scope (refuted — Readium is iOS-only); cap extracted size (zip-bomb guard, reuse import batch limits).

---

## Standing exclusions (do not re-add)

macOS-26 tier (until CI Xcode bump) · EPUB · PDFium form-fill runtime (no V8 in artifact) · trust-anchor verification (needs sig-verification feature design first) · NER redaction assist (after true redaction) · Tesseract pack (do with roadmap "more OCR languages") · US-gov forms gallery · AATL · ECI/FOGRA profiles · OpenMoji · Hunspell bundling.
