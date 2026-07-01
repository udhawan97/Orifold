# PDFium Processing Backend

pdFold keeps PDFKit as the native UI and document engine. PDFKit still owns `PDFView`, `PDFDocument`, `PDFPage`, `PDFAnnotation`, `PDFSelection`, annotation interaction, selection, search, printing, export, and workspace page ownership.

PDFium is added as a supplemental local processing backend behind `PDFProcessingEngine`. The first PDFium-backed feature is a non-blocking PDF validation smoke check during PDF import. If PDFium is unavailable or rejects a PDF that PDFKit can open, the PDFKit import path still proceeds.

This backend is bundled into the app process through Swift Package dependencies. It is not a remote service, daemon, or document upload path.

Text editing is still PDFKit-annotation based. PDFium exposes lower-level text APIs that can help with future character/word hit-testing, font-size hints, and render verification, but pdFold does not yet attempt direct PDF content-stream text rewriting because doing that safely can break fonts, encodings, spacing, content ordering, and signatures.

The current Swift Package integration uses the local wrapper package at `Packages/PDFiumBinary`, which points to `espresso3389/pdfium-xcframework` release `v144.0.7811.0-20260502-190206`, a prebuilt macOS/iOS PDFium XCFramework distributed under MIT. The release notes identify the binaries as built from `bblanchon/pdfium-binaries` for Chromium PDFium `7811`; PDFium itself is part of the Chromium project and uses BSD-style licensing.

Backout is intentionally small: remove the `PDFiumBinary` package dependency from `Package.swift`/`project.yml`, and `PDFiumProcessingEngine` compiles to an unavailable stub while PDFKit fallback processing remains available.
