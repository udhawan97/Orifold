# Orifold — Unreleased changes after v0.9.1

Status: **Proposed release notes.** These changes are implemented on `main` after the `v0.9.1` tag but have not been assigned a version, tagged, packaged, or published.

Comparison: `v0.9.1..main`

## Added

- **Restyle compatible vector objects.** Select an existing simple path and use **Object Style** in the Markup inspector to change an existing solid fill, stroke, or 0.25–24 pt line width. The edit is undoable and survives save, reopen, and export. It does not add a missing paint channel or rewrite images, gradients, reused Form XObjects, or rotated-page content.
- **Import CBZ comic-book archives.** Orifold converts naturally sorted image entries into PDF pages in memory, ignores non-image/macOS metadata entries, and reports specific errors for empty, unreadable, oversized, or over-1,000-page archives.
- **Translate selected text or the current page on macOS 15+.** A read-only panel uses Apple’s on-device Translation framework, preserves chunk order for long text, copies results without modifying the PDF, and gives first-use notice that macOS may download a language model. The action is hidden on macOS 14.

## Documentation

- Added exact CBZ import, object-restyling, and translation guides and boundaries.
- Corrected public privacy wording: document contents are never uploaded, while updates, optional signing timestamps, and translation language-model downloads remain explicit network-capable flows.
- Refreshed source and test counts from the current tree.

## Important boundaries

- The current tagged download remains **v0.9.1** and does not contain these features.
- Translation is a reading aid, not a PDF edit, and requires macOS 15 or later.
- CBZ import accepts ZIP-compatible comic archives; it does not support RAR/CBR.
- Object restyling changes only compatible, existing path paint channels on unrotated pages.
