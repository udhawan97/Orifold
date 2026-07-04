# Orifold v6 Verification

Date: July 2, 2026

This records the final Acrobat-parity v6 release gate after modules C, E, B, D, and A were merged.

## Final Integrated Gate

Added `V6IntegratedFlowTests.testFinalGateAllFiveFeaturesTogether` in `Tests/OrifoldTests/OrifoldTests.swift`.

The test exercises the combined flow in release order:

1. Import a PDF form, DOCX package, and PNG scan through `WorkspaceViewModel.importFiles`.
2. Reorder documents, rotate a rich-document page, and add a PDF note annotation.
3. Lock form answers in place during export.
4. Burn in watermark and page numbers.
5. Add searchable text to the scanned member.
6. Reduce file size.
7. Protect the final PDF with a password.
8. Validate intermediate and final PDF artifacts with PDFium.
9. Re-import the protected PDF, unlock it, and verify the expected form and searchable-scan text survives.

The gate also verifies the existing product decision that workspace writes are PDF-only. The app intentionally does not advertise `.orifoldproj` as a writable document type; existing tests cover that behavior.

## Audit Findings And Fixes

- Initial final E2E audit found that the integrated gate was too synthetic and did not cover real import/re-import, reorder, annotation, and intermediate PDFium validation. Fixed by hardening `V6IntegratedFlowTests` to drive PDF + DOCX + PNG imports through the real view model path and validate artifacts throughout the combined flow.
- Initial final UI audit found that imports could start while compression or making a scan searchable was active. Fixed by routing `WorkspaceViewModel.importFiles` through `canPerformMutatingAction()` before starting import state, with regression coverage in `WorkspaceViewModelTests.testProcessingBlocksNewImports`.
- Final UI auditor rerun: zero confirmed findings.
- Final E2E auditor rerun: zero confirmed findings.

## Commands

All commands were run with SwiftPM. Xcode tooling was not used as release-gate evidence.

- `swift test --filter WorkspaceViewModelTests/testProcessingBlocksNewImports` passed.
- `swift test --filter V6IntegratedFlowTests` passed.
- `swift build` passed.
- `swift test` passed: 188 tests, 1 skipped, 0 failures.
- `swift build -c release` passed.

Non-failing CoreGraphics/CoreText logging appeared during PDF/font-heavy tests and did not correspond to test failures.

## Auditor IDs

- Final UI behavior auditor: `019f250a-229b-7133-8e8d-bb4edc84fdf9`, zero confirmed findings.
- Final end-to-end flow auditor: `019f250a-3c84-79f3-b189-b984f182df25`, zero confirmed findings.
