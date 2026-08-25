# Open-source OCR landscape for Orifold

**Primary-source snapshot:** 2026-08-25
**Decision scope:** a free, local-first macOS workflow that adds a trustworthy searchable text layer to existing PDFs. This is not a claim that one model is universally “best.”

## Executive decision

Orifold should keep Apple Vision as its zero-download fast path, retain ownership of PDF rendering and rewriting, and add interchangeable OCR engines behind one normalized result contract. The most credible first additions are:

1. **Tesseract** as the small, mature, broadly multilingual optional engine.
2. **PP-OCRv6 through PaddleOCR or a verified RapidOCR/ONNX package** as the accuracy-oriented experimental engine, subject to an Orifold-owned Apple Silicon benchmark and an exact model-license audit.
3. **Docling-inspired layout stages** as an optional parser above OCR—not as the component that rewrites the PDF.

OCRmyPDF is the strongest product reference for safe searchable-PDF behavior. Its `skip` / `redo` / `force` modes, sidecars, validation, page selection, stable exit behavior, and explicit preservation caveats are more relevant to Orifold than a leaderboard score. [OCRmyPDF introduction](https://ocrmypdf.readthedocs.io/en/latest/introduction.html), [cookbook](https://ocrmypdf.readthedocs.io/en/latest/cookbook.html), [advanced features](https://ocrmypdf.readthedocs.io/en/latest/advanced.html), [API](https://ocrmypdf.readthedocs.io/en/latest/api.html)

Surya and MinerU are technically interesting but unsuitable as the basis of an unqualified “free open-source” promise: Surya’s model weights prohibit competing products and impose organization-size restrictions, while MinerU uses a custom license with commercial thresholds. [Surya model license](https://github.com/datalab-to/surya/blob/master/MODEL_LICENSE), [MinerU license](https://github.com/opendatalab/MinerU/blob/master/LICENSE.md)

## Orifold’s implemented baseline

The first preservation-first pass now renders and recognizes locally with Apple Vision, supports automatic or explicit language selection, skips pages that already contain text by default, and can continue after individual page failures. It retains line confidence for a review count and returns a postflight receipt with requested, changed, skipped, review, and locally validated member counts.

The PDF write path no longer redraws the source page. It creates a text-only overlay and imports that overlay as a Form XObject into the original PDFium page. Only changed workspace members are returned for replacement. Every changed PDF must preserve page count, all page boxes, and rotation, then pass both qpdf structural validation and PDFium validation before the result is exposed. Regression tests cover invisible searchable text, rotated alignment, annotation and geometry preservation, changed-member isolation, cancellation, low-confidence review, and partial recovery. [PDFOCRService.swift](../../Orifold/Engine/PDFOCRService.swift), [PDFOCRTests.swift](../../Tests/OrifoldTests/PDFOCRTests.swift), [InspectorView.swift](../../Orifold/Views/InspectorView.swift)

The workbench expresses that contract as **Pages → Recognize → Verify**, warns when existing searchable pages or signatures are involved, and shows a structural postflight receipt after the run. Remaining competitive gaps are a calibrated review/correction surface, page ranges and resumable batches, an engine-neutral result contract, optional open engines, and a published benchmark corpus. The next step is therefore not to swap in the biggest model; it is to close those evidence and recovery gaps without weakening PDF preservation.

## Capability and fit matrix

“Not advertised” means the reviewed official material did not establish that capability; it is not proof of impossibility. Runtime weight is directional because model selection and packaging materially change it.

| Project | License reality | Runtime / macOS fit | Languages and document intelligence | Searchable-PDF behavior | Orifold role |
|---|---|---|---|---|---|
| [Tesseract](https://github.com/tesseract-ocr/tesseract) | Apache-2.0 code; official `tessdata` is also [Apache-2.0](https://github.com/tesseract-ocr/tessdata/blob/main/LICENSE) | Native C++/CPU; comparatively light; Homebrew-friendly | 100+ languages; script packs, orientation/script detection, rotated page modes. No handwriting; weak semantic structure and reading order. | CLI can emit image-plus-hidden-text PDF; also TSV, hOCR, ALTO and PAGE with geometry/confidence. | Ship/downloadable mature fallback and language packs; use TSV/hOCR for review, but keep Orifold’s writer. |
| [OCRmyPDF](https://github.com/ocrmypdf/OCRmyPDF) | MPL-2.0 application; dependencies/plugins have their own licenses | Python application plus OCR/rendering dependencies; excellent CLI, less suitable as a bundled native core | Delegates recognition, usually to Tesseract; adds rotation, deskew, cleanup and page policy. | Its specialty: grafts OCR into PDFs, preserves original image resolution when possible, supports PDF/A, sidecar text, validation and thousands of pages. Some force/PDF-A paths can flatten or discard structure. | Product and preservation reference; optional external integration is possible. |
| [PaddleOCR / PP-OCRv6](https://github.com/PaddlePaddle/PaddleOCR) | Apache-2.0 code; reviewed official PP-OCRv6 model cards are Apache-2.0, e.g. [recognition](https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_rec_safetensors) and [detection](https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_det) | Python/Paddle stack is substantial; model tiers range from tiny to large. Packaging must be measured on Apple Silicon. | 100+ languages across project models. PP-StructureV3 adds layout, reading order, tables, formulas, seals, orientation and unwarping. PaddleOCR-VL additionally advertises handwriting and complex document parsing. | Produces OCR/layout data and structured exports, not a preservation-first searchable-PDF grafting workflow. | Strongest practical accuracy candidate to benchmark; start with PP-OCRv6 text models, not a VLM. |
| [RapidOCR](https://github.com/RapidAI/RapidOCR) | Apache-2.0 code; redistributed models still require artifact-level audit | ONNX Runtime and other backends; designed to deploy converted PaddleOCR models cross-platform | Detection, orientation classification and recognition; multiple language model sets. Not a separate quality model family. | Returns OCR results/visualizations; no preservation-first PDF writer. | Promising deployment route for PP-OCR on macOS; treat it as a runtime wrapper, not a benchmark winner. |
| [docTR](https://github.com/mindee/doctr) | Apache-2.0 code; audit the exact checkpoints and dependencies before bundling | Python 3.11+ and PyTorch; CPU/GPU, materially heavier than a native engine | Detection + recognition, rotated boxes, page orientation/straightening, language detection, reading order, layouts, KIE and table structure. Handwriting/formula support is not established in the reviewed docs. | Renders PDFs and exports a nested document/JSON representation; not a searchable-PDF preservation layer. | Useful normalized-document API and visual-debugging reference; lower packaging priority. |
| [EasyOCR](https://github.com/JaidedAI/EasyOCR) | Apache-2.0 code; checkpoint/dependency audit required | Python/PyTorch; CPU is supported but heavier than native Tesseract | 80+ languages across Latin, Chinese, Arabic, Devanagari and Cyrillic sets; word boxes and confidence; optional rotation retry and paragraph grouping. README still lists handwriting as future work. | Image OCR only; no PDF preservation/writer. | Simple confidence-returning API reference; little advantage over PP-OCRv6 for a new Orifold engine. |
| [Surya](https://github.com/datalab-to/surya) | Apache-2.0 code, but **restricted OpenRAIL-derived weights**: competing products and organizations over stated funding/revenue thresholds need another license | Current 650M VLM; Apple Silicon path uses llama.cpp. Official M4 Max result is about 0.108 pages/s at 96 DPI, so it is a heavyweight path. | Layout, reading order, tables, inline math/KaTeX, handwriting examples, polygons and mean token confidence; multilingual. | Structured HTML/blocks, not preservation-first searchable PDF. | Research reference only unless Orifold obtains compatible model rights; do not market it as an open-source model. |
| [Docling](https://github.com/docling-project/docling) | MIT core; each OCR engine and Docling model has a separate license that must be audited | Python; selectable CPU/CUDA/MPS paths and a slim macOS Vision extra; full pipelines are substantial | Orchestrates multiple OCR engines, layout detection, TableFormer, formula/code/chart enrichers, reading order and structured Markdown/JSON/HTML/DocTags output. | PDF-aware OCR can target regions, but the product is conversion/understanding, not loss-minimizing searchable-PDF grafting. | Best architecture reference for composable stages and engine plugins. |
| [MinerU](https://github.com/opendatalab/MinerU) | **Custom MinerU license**, not an unqualified open-source choice: commercial thresholds and service attribution terms apply; model licenses are additional | Official quick start recommends macOS 14+, Apple Silicon, 16 GB RAM and about 20 GB disk; backends range from CPU pipeline to VLM | 100+ languages advertised; layout, reading order, tables, formulas, images and Markdown/JSON. Official limitations include difficult tables, formulas and handwriting. | Converts documents to structured outputs; not a preservation-first searchable-PDF layer. | Heavy research/benchmark reference only; licensing and resource cost conflict with Orifold’s default promise. |
| [olmOCR](https://github.com/allenai/olmocr) | Apache-2.0 code and reviewed olmOCR-2 model card | 7B/8B VLM; official local path targets a recent NVIDIA GPU with at least 12 GB VRAM and roughly 30 GB disk, not a practical native Mac default | Strong complex-page parsing: reading order, tables, formulas, handwriting and old scans; outputs clean Markdown | No searchable-PDF grafting. | Quality and benchmark reference, not an embedded macOS engine. |

## What each leader is worth adapting

### Tesseract: inspectable OCR evidence

Tesseract’s practical advantage is not semantic document understanding; it is stable, inspectable output. The CLI can create a searchable PDF and can emit hOCR with word boxes/confidence, TSV with word-level confidence, ALTO XML, and PAGE XML. Orientation/script detection and page segmentation modes are explicit controls. [Tesseract README](https://github.com/tesseract-ocr/tesseract), [command-line output formats](https://tesseract-ocr.github.io/tessdoc/Command-Line-Usage.html), [official language/script data](https://tesseract-ocr.github.io/tessdoc/Data-Files-in-different-versions.html)

Adapt:

- A deterministic engine contract with geometry and confidence, not text alone.
- Downloadable language packs with exact version, hash, size, license and offline state.
- Advanced page segmentation/orientation controls behind safe presets.

Do not copy its weak product behavior: Tesseract has no GUI and its own documentation warns that OCR engines do not recover paragraphs, headings, reading order or font identity reliably. OCRmyPDF also documents that Tesseract does not recognize handwriting. [OCRmyPDF limitations](https://ocrmypdf.readthedocs.io/en/latest/introduction.html#limitations)

### OCRmyPDF: preservation is a feature, not an implementation detail

OCRmyPDF rasterizes for recognition, then grafts the OCR layer onto the original PDF while trying to minimize unrelated changes. It preserves embedded image resolution when possible, supports multiple output types, validates outputs, uses multiple cores, and can process very large files. [README](https://github.com/ocrmypdf/OCRmyPDF/blob/main/README.md), [introduction](https://ocrmypdf.readthedocs.io/en/latest/introduction.html)

Adapt:

- Three explicit policies: **Scan blank/image-only pages**, **Redo existing hidden OCR**, and **Force rasterize**.
- A strong warning before Force: forms, vector content, tags, signatures or structure can be flattened/lost.
- Page ranges, language selection, sidecar text, quiet/machine-readable logs, stable failure classes, cancellation and resume.
- Write to a new output, validate it, then expose it; never partially replace the source.
- A postflight report: pages changed/skipped/failed, PDF features affected, searchable-text check and visual-difference result.

OCRmyPDF’s own docs are appropriately candid: PDF/A conversion can alter content; Ghostscript-based paths may discard the structure tree; force mode rasterizes pages; digitally signed PDFs should not be modified. [Advanced output modes and caveats](https://ocrmypdf.readthedocs.io/en/latest/advanced.html), [error guidance](https://ocrmypdf.readthedocs.io/en/latest/errors.html)

### PaddleOCR: a staged quality ladder

PaddleOCR separates text detection, recognition, orientation and document parsing. PP-OCRv6 offers model-size tiers; PP-StructureV3 exposes document orientation, unwarping, text-line orientation, tables, formulas, seals and structured JSON/Markdown. Its command line and Python APIs let those modules be switched independently. [PP-StructureV3 pipeline](https://www.paddleocr.ai/latest/en/version3.x/pipeline_usage/PP-StructureV3.html), [installation profiles](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/installation.en.md)

Adapt:

- A staged pipeline: render → preprocess → orient → detect → recognize → order → review → write → validate.
- An “enhanced” model tier that users opt into after seeing download, disk, memory and estimated speed.
- Fine-grained coordinates and semantic labels as a local sidecar for review/accessibility; only verified OCR text belongs in the hidden PDF layer.

Do not transplant headline benchmark claims. Current project pages advertise strong PP-OCRv6 and PaddleOCR-VL results, but those are upstream evaluations over different tasks, datasets, resolutions and hardware. They are useful hypotheses, not proof of Orifold superiority. [PaddleOCR repository](https://github.com/PaddlePaddle/PaddleOCR)

### Docling and docTR: normalize document understanding above OCR

Docling’s useful design is the pluggable pipeline: PDF-aware OCR modes, engine selection, page ranges, table modes, and optional formula/code/chart enrichers that produce structured outputs. [Docling model catalog](https://github.com/docling-project/docling/blob/main/docs/usage/model_catalog.md), [Docling CLI](https://github.com/docling-project/docling/blob/main/docs/reference/cli.md)

docTR similarly returns a nested `Document` model rather than flattening immediately to text, and exposes orientation, straightening, language detection, reading order, layout/KIE and table options. [docTR model usage](https://mindee.github.io/doctr/latest/using_doctr/using_models.html), [docTR model API](https://mindee.github.io/doctr/latest/modules/models.html)

Adapt a shared intermediate representation, for example:

```text
Document → Page → Region(label, order) → Line → Word
                                      ↳ text, polygon, confidence,
                                        language/script, engine/version
```

The PDF writer should consume this representation. It should not depend on a particular OCR framework’s JSON schema.

### Surya, MinerU and olmOCR: useful warnings as well as ideas

Surya’s block-level output includes labels, reading order, polygons and mean token confidence, which is a good review-data shape. Its model license, however, requires attribution and change notices and restricts competing products and larger organizations. That is incompatible with presenting the weights as an unrestricted free/open-source Orifold engine. [Surya README](https://github.com/datalab-to/surya), [model license](https://github.com/datalab-to/surya/blob/master/MODEL_LICENSE)

MinerU offers backend/effort choices, page ranges, formula/table/image switches, CLI/API/Gradio modes and explicit hardware guidance. Those are good transparency patterns. Its custom license can require a commercial license above specified monthly-active-user or revenue thresholds and requires prominent attribution for online services. [MinerU quick start](https://github.com/opendatalab/MinerU/blob/master/docs/en/quick_start/index.md), [CLI](https://github.com/opendatalab/MinerU/blob/master/docs/en/usage/cli_tools.md), [license](https://github.com/opendatalab/MinerU/blob/master/LICENSE.md)

olmOCR’s main value to Orifold is its test philosophy. `olmOCR-bench` contains more than 7,000 tests across over 1,400 documents, covering multicolumn reading order, headers/footers, tables, old scans, math, long tiny text and other difficult cases. The model itself is too large and NVIDIA-oriented for Orifold’s default local Mac path. [olmOCR repository](https://github.com/allenai/olmocr), [olmOCR-2 model card](https://huggingface.co/allenai/olmOCR-2-7B-1025), [olmOCR-bench](https://huggingface.co/datasets/allenai/olmOCR-bench)

## Recommended Orifold design

### 1. Own one engine-neutral result contract

Create an internal `OCREngine` boundary that accepts rendered pages and returns words/lines with polygons, confidence, detected language/script, reading order, semantic label, and engine/model version. Keep preprocessing, the PDF writer, validation, progress, cancellation and provenance in Orifold.

This makes Apple Vision, Tesseract and a PP-OCR runtime swappable without duplicating destructive PDF logic.

### 2. Offer understandable modes, not model names first

- **Fast local** — Apple Vision, no download.
- **Broad language** — Tesseract plus selected language packs.
- **Enhanced text** — benchmark-winning PP-OCRv6 configuration, after its package is verified.
- **Document structure (experimental)** — layout/table/formula sidecar; never silently inject generative descriptions into hidden PDF text.

Then expose the exact engine/model/version in details and provenance.

### 3. Make confidence actionable

Add a review surface with page thumbnails, selectable text polygons, low-confidence heatmap, reading-order connectors, and text correction. Provide **Accept page**, **Accept all above threshold**, and **Needs review** states. Thresholds must be calibrated per engine/language rather than treating a `0.8` score as equivalent across models.

Confidence should guide attention, not imply correctness. Empty output, implausible character density, contradictory orientation, or a sudden language change should fail closed into review.

### 4. Treat searchable-PDF integrity as a product promise

Before OCR, inventory text, annotations, AcroForm fields, outlines, attachments, tags, metadata, encryption and signatures. After OCR, verify:

- the file opens and page count/boxes/rotation are unchanged;
- existing visible content and annotation appearance are visually unchanged within a documented tolerance;
- expected text can be searched, selected and copied in reading order;
- the hidden text aligns to glyph regions;
- features that cannot be preserved are reported before writing;
- signed documents are exported only as clearly unsigned copies.

### 5. Make batch work recoverable

Support folders, page ranges, pause/cancel, resume, per-page retries, bounded parallelism, model warmup/reuse and a final machine-readable report. Keep the original untouched and use an atomic temporary-output → validate → rename sequence.

## Orifold benchmark gate

Do not combine upstream benchmark numbers into a ranking. Tesseract character error, PaddleOCR recognition accuracy, Surya/olmOCR structured-output tests and MinerU document-parsing scores measure different things. Vendor-run results may also use different render resolution, prompts, post-processing, languages and accelerators.

Publish an Orifold-owned, reproducible corpus and runner before claiming “best.” Use public or redistributable documents plus synthetic fixtures, with provenance and licenses. Run every engine on the same Mac, render scale and page images.

Measure:

| Dimension | Required measures |
|---|---|
| Text | CER, WER, Unicode normalization errors, punctuation/numeric accuracy, search/copy success |
| Geometry | word/line polygon overlap, baseline alignment, hidden-layer visual alignment |
| Order/structure | multicolumn reading order, header/footer suppression, table cell adjacency, formula exact match |
| Hard cases | skew/rotation, low contrast, bleed-through, camera perspective, handwriting, mixed scripts, vertical text, tiny type |
| Confidence | calibration error and recall among words sent to review, not only average confidence |
| PDF integrity | page/object changes, visual diff, annotations, forms, outlines, attachments, tags, metadata, encryption/signature handling |
| Local UX | cold/warm pages per minute, peak RAM, disk/model size, first-run download, energy, cancellation latency, offline result |
| Reliability | deterministic reruns, page-level failures, corrupted input behavior, resume correctness |

Use a locked “decision set” to select defaults and a separate hidden regression set. Publish configuration, versions, hashes, hardware, fixture licenses and raw results. A defensible claim would be narrowly scoped—such as “best tested free local-first macOS searchable-PDF workflow on the published Orifold corpus”—not “best OCR overall.”

## Redistribution and credit checklist

This is an engineering inventory, not legal advice. Re-audit the exact source commit, binary, model file and transitive package selected for release.

| Component | If redistributed with Orifold |
|---|---|
| Tesseract + official tessdata; PaddleOCR/PP-OCRv6; RapidOCR; docTR; EasyOCR; olmOCR | Apache-2.0: include the license; retain applicable copyright, patent, trademark and attribution notices; mark modified covered files; preserve applicable upstream `NOTICE` contents. Audit models and dependencies separately even when the main repository is Apache-2.0. |
| OCRmyPDF | MPL-2.0: include the license/notices and make source available for any modified MPL-covered files distributed to recipients; other files in a larger work can remain under their own terms. Its bundled/non-core components have separate licenses. |
| Docling core | MIT: reproduce the copyright and permission notice in copies or substantial portions. Docling models and selected OCR engines remain separate artifacts with separate terms. |
| Surya weights | Do not bundle under Orifold’s unrestricted free/open-source claim. If ever separately offered, comply with the model license’s use restrictions, license copy, attribution/link, change notices and retained notices, and confirm Orifold is not a prohibited competing use. |
| MinerU | Do not bundle as an unqualified open-source default. Its custom license includes commercial thresholds, termination and service-attribution terms; every selected model also needs a separate audit. |

For every shipped engine/model, add a locked record to [THIRD-PARTY-NOTICES.md](../../Orifold/Resources/THIRD-PARTY-NOTICES.md) containing name, version/commit, upstream URL, artifact hash, copyright, license identifier/text location, model-card URL, modification status and dependency provenance. Also expose the same credits in **About → Open Source Credits**. “Powered by” branding is optional unless the selected license expressly requires display attribution; do not imitate another product’s identity or copy its wording/assets.

If an engine remains an unbundled user-installed CLI, document the integration and upstream license, but distinguish courtesy credit from redistribution obligations.

## Sources and verification notes

Only official repositories, documentation, license files, model cards and official benchmark artifacts were used:

- Tesseract: [repository](https://github.com/tesseract-ocr/tesseract), [license](https://github.com/tesseract-ocr/tesseract/blob/main/LICENSE), [CLI/output formats](https://tesseract-ocr.github.io/tessdoc/Command-Line-Usage.html), [languages/scripts](https://tesseract-ocr.github.io/tessdoc/Data-Files-in-different-versions.html)
- OCRmyPDF: [repository/README](https://github.com/ocrmypdf/OCRmyPDF/blob/main/README.md), [license](https://github.com/ocrmypdf/OCRmyPDF/blob/main/LICENSE), [introduction](https://ocrmypdf.readthedocs.io/en/latest/introduction.html), [cookbook](https://ocrmypdf.readthedocs.io/en/latest/cookbook.html), [advanced](https://ocrmypdf.readthedocs.io/en/latest/advanced.html), [API reference](https://ocrmypdf.readthedocs.io/en/latest/apiref.html), [plugin API](https://ocrmypdf.readthedocs.io/en/stable/plugins.html)
- PaddleOCR: [repository](https://github.com/PaddlePaddle/PaddleOCR), [license](https://github.com/PaddlePaddle/PaddleOCR/blob/main/LICENSE), [PP-StructureV3](https://www.paddleocr.ai/latest/en/version3.x/pipeline_usage/PP-StructureV3.html), [installation](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/installation.en.md), [PP-OCRv6 recognition model card](https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_rec_safetensors), [detection model card](https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_det)
- RapidOCR: [repository](https://github.com/RapidAI/RapidOCR), [license](https://github.com/RapidAI/RapidOCR/blob/main/LICENSE)
- docTR: [repository](https://github.com/mindee/doctr), [license](https://github.com/mindee/doctr/blob/main/LICENSE), [model usage](https://mindee.github.io/doctr/latest/using_doctr/using_models.html), [model API](https://mindee.github.io/doctr/latest/modules/models.html)
- EasyOCR: [repository/README](https://github.com/JaidedAI/EasyOCR/blob/master/README.md), [license](https://github.com/JaidedAI/EasyOCR/blob/master/LICENSE), [CLI source](https://github.com/JaidedAI/EasyOCR/blob/master/easyocr/cli.py)
- Surya: [repository/README](https://github.com/datalab-to/surya), [code license](https://github.com/datalab-to/surya/blob/master/LICENSE), [model license](https://github.com/datalab-to/surya/blob/master/MODEL_LICENSE)
- Docling: [repository](https://github.com/docling-project/docling), [license](https://github.com/docling-project/docling/blob/main/LICENSE), [model catalog](https://github.com/docling-project/docling/blob/main/docs/usage/model_catalog.md), [CLI reference](https://github.com/docling-project/docling/blob/main/docs/reference/cli.md), [official model card](https://huggingface.co/docling-project/docling-models)
- MinerU: [repository](https://github.com/opendatalab/MinerU), [license](https://github.com/opendatalab/MinerU/blob/master/LICENSE.md), [quick start](https://github.com/opendatalab/MinerU/blob/master/docs/en/quick_start/index.md), [CLI](https://github.com/opendatalab/MinerU/blob/master/docs/en/usage/cli_tools.md)
- olmOCR: [repository](https://github.com/allenai/olmocr), [license](https://github.com/allenai/olmocr/blob/main/LICENSE), [model card](https://huggingface.co/allenai/olmOCR-2-7B-1025), [official benchmark dataset](https://huggingface.co/datasets/allenai/olmOCR-bench)

Licenses and model cards can change. Pinning, hashing and repeating this audit are release gates, not one-time documentation work.
