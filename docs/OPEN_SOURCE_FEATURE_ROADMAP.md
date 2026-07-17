# Open-Source & Free-Data Feature Roadmap

**Status:** Planning only — nothing here is implemented.
**Date:** 2026-07-16
**Method:** Three parallel research passes (codebase inventory, open-source library sweep, free-data sweep) followed by **two verification loops**: (1) local verification against the actual vendored binaries and code — `nm` on the shipped PDFium dylib and `libQPDF.a`, greps for existing integration points; (2) an adversarial refutation pass against primary sources (licenses re-read on project pages, live API tests, binary string inspection). Only items surviving both loops at Medium-High or High confidence are recommended.

## Ground rules these candidates were filtered against

- **Offline-first.** No feature may add a mandatory network call. (Existing network surface: opt-in GitHub update check, opt-in RFC-3161 timestamping.)
- **License-clean.** App is Apache-2.0. Acceptable: MIT/BSD/Apache/MPL-2.0 code, OFL fonts, CC0/public-domain/permissive data. Rejected: AGPL/GPL linking, CC-BY-SA assets, anything without an explicit redistribution grant.
- **macOS 14 deployment target stays.** Newer-OS features ship behind `#available` gates (this would be the repo's first gate — CI's Xcode 16.4 compiles macOS 15 APIs fine; macOS 26 APIs do **not** compile until the CI toolchain bumps).
- **Size-aware.** DMG is ~15 MB today. >20 MB additions must be optional GitHub-Release packs.
- **Verified engine headroom:** every PDFium symbol needed by any candidate below is already exported by the vendored dylib (`espresso3389` v144.0.7811.0) — **no PDFium rebuild needed for anything**. The only binary work anywhere on this list is qpdf-side (zopfli/mozjpeg rebuild) or net-new vendored libs (jbig2enc, Tesseract).

---

## Tier 1 — HIGH confidence

### 1. Follow-along Read-Aloud
Read the document aloud with per-word highlight, using existing text geometry.
- **How:** `AVSpeechSynthesizer` (system, macOS 14-safe, offline). Live-verified: 180 offline voices present by default; `willSpeakRangeOfSpeechString` fires reliable per-word range callbacks on macOS.
- **Fits:** Reader Mode + Document Comfort; accessibility + proofreading story.
- **Effort:** S–M. **Size:** 0. **Caveats:** default voices are compact quality (enhanced voices are a user-side System Settings download); Hindi has exactly one voice.

### 2. Metadata viewer/editor
View and edit Title/Author/Subject/Keywords; today the app only write-stamps a title on import and has no metadata UI (confirmed gap).
- **How:** `qpdf_get_info_key`/`qpdf_set_info_key` — already present in the linked `libQPDF.a` and reachable through the existing `CQPDF` import; `FPDF_GetMetaText` available for read fallback.
- **Trap handled:** qpdf info keys touch the **Info dictionary only** — XMP can diverge. Strategy: edit Info dict; offer "also clear XMP" (sanitize pass already strips metadata) rather than pretending to edit XMP.
- **Effort:** S–M. **Size:** 0.

### 3. Offline translation (macOS 15+, gated)
Translate selected text / whole page via Apple's Translation framework.
- **How:** `TranslationSession` — verified macOS 15.0+ and open to third-party Mac apps; batch `translations(from:)` exists; models are on-device and OS-managed. Session must be obtained via SwiftUI `.translationTask` modifier (fits the SwiftUI app). Compiles on CI Xcode 16.4 behind `#available(macOS 15)`.
- **Disclosure needed:** first use triggers an OS-managed language-model download (Apple's system service, not an app network call) — word the UI honestly alongside "Nothing leaves your Mac."
- **Effort:** M. **Size:** 0.

### 4. Font-substitution pack + Core-14 AFM metrics (most on-mission)
When editing a PDF whose fonts aren't embedded, substitute **metric-compatible** open fonts so edited text keeps its layout instead of reflowing wrong.
- **Data:** Liberation Sans/Serif/Mono (OFL-1.1, = Arial/Times/Courier metrics), Carlito (OFL, = Calibri), Caladea (Apache-2.0 — corrected in verification, not OFL, still fine), Adobe Core-14 AFM metrics (redistributable with notice retention — same license Apache PDFBox ships under, ASF-reviewed). ~7–8 MB, bundle-time.
- **Wire-in point exists:** today's fallback chain is ad-hoc (`editingFamilyName(for:fallback:)` in `ReadingCanvas.swift` → blind `"Helvetica"` default in `WorkspaceViewModel.swift`); replace with a substitution table + real metrics.
- **Effort:** M. **Why it matters:** directly hardens the flagship text-editing pipeline — the highest-leverage item on this list.

### 5. Barcode / QR insert + scan
Generate QR/Aztec/PDF417/Code128 as page objects or stamps; detect barcodes on pages (e.g., "copy link from this QR").
- **How:** Core Image generators + `VNDetectBarcodesRequest`, both macOS 14-safe, offline, zero dependencies. Insert lane exists (`FPDFImageObj_SetBitmap` already silgen-bound; stamp/bake pipeline shipped); scan reuses the OCR rasterizer. zxing-cpp (Apache-2.0, ~1 MB) only if more *generation* formats ever needed.
- **Effort:** S–M. **Size:** 0.

---

## Tier 2 — MEDIUM-HIGH confidence

### 6. Spell-check in the inline text editor
- One property (`isContinuousSpellCheckingEnabled`) on the existing `InlineEditableTextView: NSTextView` + a toggle. **Verified limit:** system spellcheck covers en/es/fr/hi but **not ja/zh-Hans** — scope the UI copy accordingly. Effort: S.

### 7. Attachments manager
- List / extract / add / remove embedded files. Symbols verified present both sides; prefer qpdf (`QPDFEmbeddedFileDocumentHelper` / qpdfjob `--add-attachment`) over PDFium's experimental attachment API. Today the app can only *strip* attachments (sanitize). Effort: M.

### 8. Booklet / N-up imposition
- `FPDF_ImportNPagesToOne` + `FPDF_ImportPages` verified present. Caveat: N-up flattens pages into XObjects — annotations drop, so impose **after** the existing decoration-bake pipeline. Print path today is a single plain `NSPrintOperation`. Effort: M.

### 9. Hanko stamp studio (brand hero)
- Procedural personal seal: circle/square border + user's name set in Shippori Mincho, in shu-iro vermillion — extends the existing `StampPalette` + appearance-baking infra. **No dataset needed at all**; OFL explicitly permits rasterizing/embedding glyphs. Add a "decorative, not a registered jitsuin" note. Effort: M. Zero legal risk, maximal brand payoff.

### 10. CJK / brand font pack
- Shippori Mincho bundled (~2–8 MB, OFL — already the website brand font); Noto Sans JP/SC as an optional GitHub-Release pack (~25–40 MB). `FPDFText_LoadFont` verified present for embedding. **Spike first:** PDFium's subsetting behavior when embedding large CJK fonts is unproven — measure exported-PDF bloat before committing. Effort: M + spike.

### 11. Compression pack v2 (the only binary work on this list)
- **Zopfli max-compression toggle:** the vendored qpdf 12.3 already contains the zopfli *hooks* (verified in `libQPDF.a`) but the library itself was **not compiled in** — rebuild QPDF.xcframework with `-DZOPFLI=ON` (qpdf ≥11.10 supports it; zopfli is Apache-2.0). Effort: S–M (build work).
- **mozjpeg** (IJG/BSD-3/zlib) as drop-in for the libjpeg-turbo statically inside the same rebuild — better DCT recompression. Effort: M.
- **JBIG2 for 1-bpp scans:** jbig2enc v0.32 (Apache-2.0) + Leptonica (BSD-2) as a new vendored lib, splicing streams via qpdf. **Default lossless generic mode** — symbol mode has the infamous character-substitution hazard. Effort: L.

### 12. Scan cleanup ("Scan mode")
- Deskew / crop / shadow-removal / binarize before OCR: `VNDetectDocumentSegmentationRequest` (macOS 12+) + vImage; Leptonica's deskew/despeckle comes free **only if** the JBIG2 work ships. Pairs OCR + cleanup + JBIG2 into one scan story. Output quality needs a spike. Effort: M.

### 13. Archival readiness hints (PDF/A-lite)
- Self-written checks via already-linked introspection (encryption present? JS? fonts embedded? OutputIntent? XMP?): qpdf `oh` API already in use, `FPDFCatalog_IsTagged` verified present. veraPDF (MPL option) as a **CI-only** oracle. **Never brand as "PDF/A validation"** — full validation is hundreds of clauses. Effort: M.

### 14. Reading-order / structure inspector
- Tagged-PDF tree viewer + "this document is untagged" accessibility warning via `FPDF_StructTree_*` (verified present, read-only — tag *writing* stays out of scope, no permissive tooling exists). Niche but accessibility-forward. Effort: M.

### 15. CC0 onboarding/demo document
- A beautiful sample PDF typeset in brand style from a Standard Ebooks (CC0) text — for first-run, tutorials, screenshots. **Pick an author public-domain worldwide (dead >70y)** — Standard Ebooks' PD determination is US-only. Effort: S.

### 16. CBZ → PDF import
- ZIPFoundation (MIT, sandbox-fine) + the existing images→PDF import lane. Effort: S–M. (EPUB is *not* included here — see Medium.)

### 17. macOS-26 "Intelligence" tier — verified real, **parked until CI Xcode bump**
- **Table extraction → CSV/Markdown:** Vision `RecognizeDocumentsRequest` (macOS 26+) — paragraphs/lists/tables.
- **Summarize / "ask this PDF":** FoundationModels (macOS 26+) — also requires Apple-Intelligence-capable hardware with AI enabled, so not universal even on 26.
- Both APIs confirmed via Apple docs; blocked today only by CI's pinned Xcode 16.4. Revisit when the toolchain moves.

---

## Medium confidence — possible, but downgraded honestly

| Item | Why it's only Medium |
|---|---|
| Outline/bookmark **editor** | Reading via PDFKit is easy (and the current TOC doesn't even read `PDFOutline` — cheap win there); *writing* outlines through PDFKit requires `dataRepresentation()`, which the app's own shipped findings say destroys the qpdf-preserved text layer. PDFium has no bookmark-write API → consistent path is raw qpdf object surgery on `/Outlines`. Real work. |
| PDFium form-fill runtime upgrade | **Refuted in part:** the shipped PDFium binary has no V8 (verified — zero `v8` strings, no JS built-ins), so JS field calculations are impossible with this artifact. Remaining gain (widget behavior, appearance regeneration) costs heavy event plumbing. |
| Signature **trust-anchor** verification (EUTL) | Correct long-term differentiator, but: LOTL reuse license is an inference from general Commission policy (no explicit grant on the LOTL legal notice); Mozilla's bundle is the wrong trust domain for document signing (would generate false "untrusted" noise — EUTL-first if built); and the app currently has **no third-party signature verification feature at all**, so this is a bigger lift than "add anchors". AATL is confirmed non-redistributable — never bundle. |
| EPUB import | Readium swift-toolkit is iOS-only (verified); DIY WKWebView pagination gives mediocre fidelity. Ship CBZ; treat EPUB separately. |
| Genkō yōshi / stationery / graph-paper generator | Zero risk, procedural, very on-brand — but a delight feature, not a driver. Good filler for a brand-polish release alongside the hanko studio. |
| Redaction-assist NER (`NLTagger`) | On-device and macOS 14-safe, but English-centric — and suggesting redactions before **true redaction** (already on the public roadmap; erase is still visual-only) manufactures false safety. Sequence strictly after the real redaction engine. |
| Tesseract + tessdata (Hindi OCR) | Verified: Vision still has no Devanagari (live-checked, 30 languages, no Hindi) and tessdata is Apache-2.0 — but a second OCR engine is a permanent maintenance tax. This is really the public roadmap's "More languages — the OCR" item; do it as an optional pack when that item comes up. |
| ICC soft-proof | CC0 profile set confirmed, but the only CC0 CMYK profile is display-only — soft-proof would be approximate; FOGRA/ECI profiles need individual permission. Risk of overpromising "preflight". |

## Dropped — with the refutation that killed each

- **US-gov forms gallery** — forms are public domain, but many USCIS forms are XFA/LiveCycle and the shipped PDFium has no XFA/V8 (verified): they wouldn't even fill correctly. Plus yearly churn + US-only appeal.
- **AATL trust list** — no public redistribution grant exists; Acrobat-only distribution.
- **Bundled local LLM (llama.cpp/MLX)** — models are 1–8 GB; bundling unjustifiable, downloading breaks the offline promise. FoundationModels (item 17) is the right path.
- **Bergamot / Argos offline translation** — dormant project / inconsistent model licensing; Apple Translation wins decisively.
- **Hunspell + dictionaries** — `NSSpellChecker` makes bundling moot (and hi_IN dictionary is GPL).
- **OpenMoji stamps** — CC-BY-SA contaminates modified derivatives; use Noto assets if emoji stamps are ever wanted.
- **ECI/FOGRA ICC bundling** — requires individual permission (confirmed).
- **CLDR / Adobe CMaps bundling** — macOS/PDFium already ship them.

---

## Suggested sequencing

1. **Wave 1 — quiet quick wins (no new deps):** spell-check (6), metadata editor (2), read-aloud (1), demo document (15).
2. **Wave 2 — editing depth + brand:** font-substitution pack + AFMs (4), hanko studio (9) [+ genkō yōshi templates as filler], barcode/QR (5).
3. **Wave 3 — engine work:** compression pack v2 (11), attachments manager (7), booklet/N-up (8), scan mode (12).
4. **Wave 4 — positioning features:** translation (3), archival hints (13), structure inspector (14), CJK pack (10).
5. **Parked:** macOS-26 tier (17) until CI Xcode bump; trust-anchor verification until a third-party signature-verification feature is designed; NER until true redaction ships.

**Relationship to the existing public roadmap** (README "What's Folding Next"): real redaction, side-by-side compare, batch folder ops, faster large-doc navigation, notarization, and more UI/OCR languages remain as already-published commitments — nothing above duplicates them; scan mode (12) and the Tesseract pack feed the "more OCR languages" and scan story, and NER-assist feeds redaction.
