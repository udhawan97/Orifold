# Free Local Engines Plan

Date: July 3, 2026

This is the implementation boundary for adding free/open-source processing engines to Orifold while keeping the app's product design, UI, and workflow original. This file is not a third-party notice inventory; notices and bundled license text belong in the app's dedicated third-party notices work.

## Policy

- Keep Orifold local-first: no document uploads, remote APIs, or hosted conversion services for these engines.
- Prefer optional local tools first, then consider bundling only after size, sandboxing, signing, notarization, and notice requirements are verified.
- Keep each engine behind a narrow Orifold-owned service so UI, errors, progress, cancellation, and export behavior remain native to Orifold.
- Pin exact versions when bundling or testing against a binary. Record the source URL and license file used for that exact version.
- Do not use upstream logos, app names, screenshots, or UI patterns as product branding.

## Approved Engines

| Engine | Integration mode | License posture | Good Orifold features |
| --- | --- | --- | --- |
| PDFium | Already bundled through `Packages/PDFiumBinary` | Verify the wrapper, binary source, and PDFium third-party notices for the exact artifact | Validation, render checks, compression support, text analysis assists |
| qpdf | Optional command-line tool first | Apache 2.0; keep license and notices when bundled | PDF Doctor, repair, linearize, encryption/permission inspection, sanitize export checks |
| Tesseract OCR | Optional command-line tool first | Apache 2.0; trained-data files need their own notice check | OCR fallback, extra language packs, batch scan workflows |
| OpenCV | Optional helper/library first | OpenCV 4.5+ is Apache 2.0; bundled builds may carry extra third-party notices | Deskew, contrast cleanup, blank-page detection, scanned-photo splitting |

LibreOffice is intentionally not in this first approved set. It is free/open source, but its dependency and packaging surface is much larger. If used later, keep it user-installed and optional before considering any bundled distribution.

## Feature Order

1. qpdf PDF Doctor
   - Detect whether `qpdf` is available.
   - Run structural checks on a temporary, user-selected/local PDF copy.
   - Show a concise Health result in Orifold language: readable, encrypted, damaged, repaired copy available, permissions summary.

2. qpdf Repair and Linearize
   - Add explicit user actions, not automatic background rewrites.
   - Always write a new output file or undoable workspace replacement.
   - Validate the repaired output with PDFium/PDFKit before presenting success.

3. qpdf Sanitize Export
   - Combine existing Orifold metadata stripping with qpdf validation.
   - Keep the first version conservative: metadata removal checks, hidden Orifold payload removal, embedded JavaScript warning if detectable, final validation.

4. Tesseract OCR Fallback
   - Keep Apple Vision as the default on macOS.
   - Use Tesseract only when the user enables it or selects language packs unavailable through Vision.
   - Reuse the existing searchable-PDF export path so OCR output remains undoable and validated.

5. OpenCV Scan Cleanup
   - Start with non-destructive preview operations: deskew, contrast, blank-page candidates.
   - Apply changes only through existing snapshot/rebuild paths.
   - Treat automatic deletion of blank pages as a confirmation step, never a silent mutation.

## Non-Goals

- Do not vendor Stirling PDF engine/editor code.
- Do not clone Stirling PDF's tool-grid UI, workflow labels, or product structure.
- Do not add cloud/server modes for these engines.
- Do not add a general automation builder until the narrow features above are reliable.

## Acceptance Checklist

- Feature works when the engine is installed.
- Feature degrades cleanly when the engine is missing.
- No document leaves the machine.
- Output is validated before success is shown.
- Exact binary/source version is recorded before bundling.
- Third-party notices are handled in the separate notice inventory.
