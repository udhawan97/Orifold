# PDFium Processing

PDFold keeps PDFKit as the native UI and document engine. PDFKit still owns `PDFView`, `PDFDocument`, `PDFPage`, `PDFAnnotation`, `PDFSelection`, annotation interaction, selection, search, printing, export, and workspace page ownership.

PDFium is added only as a supplemental processing engine behind `PDFProcessingEngine`. The first PDFium-backed feature is a non-blocking PDF validation smoke check during PDF import. If PDFium is unavailable or rejects a PDF that PDFKit can open, the PDFKit import path still proceeds.

The current Swift Package integration uses the local wrapper package at `Packages/PDFiumBinary`, which points to `espresso3389/pdfium-xcframework` release `v144.0.7811.0-20260502-190206`, a prebuilt macOS/iOS PDFium XCFramework distributed under MIT. The release notes identify the binaries as built from `bblanchon/pdfium-binaries` for Chromium PDFium `7811`; PDFium itself is part of the Chromium project and uses BSD-style licensing.

Backout is intentionally small: remove the `PDFiumBinary` package dependency from `Package.swift`/`project.yml`, and `PDFiumProcessingEngine` compiles to an unavailable stub while PDFKit fallback processing remains available.
