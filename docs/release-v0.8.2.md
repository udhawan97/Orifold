# v0.8.2 Orifold

## GitHub Release Fields

Tag: `release-v0.8.2`

Target: latest commit tagged by `release-v0.8.2`

Release title: `v0.8.2 Orifold`

Asset to upload: `Orifold.zip`

Automation: `.github/workflows/release.yml` builds and publishes automatically on push of any `release-v*` tag, and marks the tagged release as GitHub's "latest" (`make_latest: true`).

Build the asset with:

```zsh
./scripts/install-mac.sh --package-only --package /tmp/Orifold.zip
```

## Release Notes

# v0.8.2 Orifold

**Release:** Latest release
**Tag:** [`release-v0.8.2`](https://github.com/udhawan97/Orifold/releases/tag/release-v0.8.2)

---

## What Changed Since v0.8.1

v0.8.2 is anchored by two things: document-body Find & Replace (previously limited to comments), and a multi-pass hardening of the inline text-editing and analysis engine driven by a real problem PDF. Alongside them: a new animated landing page, sidebar page-thumbnail drag reordering, two signing-entitlement regressions found and fixed, toolbar polish, and a documentation-media cleanup that closes out the screenshot backlog from v0.8.1.

### Find & Replace on Document Body Text

- Find & Replace now works on the actual page body text, not just comments — search finds every occurrence across the document, the results list shows match count and position, and Replace/Replace All commit through the same editing engine behind the "Edit Text" tool, so undo, persistence, and every export format (PDF, Word/RTF/ODT, images) stay consistent.
- Replace acts on the specific occurrence selected in the results list; Replace All rewrites every eligible occurrence — body text and comments — in one undoable step, with a clear confirmation ("Replaced N occurrences of “X” with “Y”").
- Text that can't be safely rewritten in bulk (an invisible OCR layer, near-transparent fill) is skipped and the skip is reported, never silently dropped; the Replace button itself reflects whether the current selection is actually replaceable, rather than inviting a click that no-ops.

### Text Editing & Analysis Hardening

This cycle ran two sequential hardening passes against the text-analysis engine — "Editing Hardening V2" and a follow-up pass driven by a real problem file (`editedrun2.pdf`). The throughline: making the engine's understanding of a page's *structure*, not just its glyphs, accurate enough that editing text no longer disturbs nearby layout.

- **A new structural primitive, `PageGraphicsIndex`**, classifies thin vector paths as table borders, underlines, and separators — everything below builds on it.
- **Underline detection and survival**: PDF underlines are vector strokes the engine previously never saw; editing an underlined line silently erased the underline. Underlines are now detected, preserved through edits, and fully erased (never leaving half a stroke behind) when replaced.
- **Table-safe editing**: merge/column-split heuristics are rule-aware, so a heading no longer merges into the table cell below it, and erase patches clip around detected rules instead of painting over them.
- **Deletion as a first-class, undoable commit** — emptying a text block used to be silently treated as Cancel.
- **A detected-font menu** surfaces the actual fonts found on a block (with a monospace tag where relevant), and Match Format now excludes ruled-grid cells and list markers, ranking by dominant style cluster.
- **List markers no longer drift** into edited text, and the drag/resize overlay dims instead of opaquely covering the page during interaction.
- **Sanitize-for-sharing now strips embedded Orifold metadata** that previously leaked through in an invisible annotation even after "sanitizing" an export.
- **Header/table line-segmentation fix**: short lines (titles, "Label: value" headers, narrow table cells) no longer incorrectly merge into one oversized block.
- **Font-size trust improvements** when a PDF reports consistent per-run sizes, plus character-aware inference fixes for lines without ascenders or capitals.
- **hitTest tie-breaking**, and an **external-modification safeguard**: if a file was edited by another app since Orifold last saved it, Orifold now detects this and imports the externally-modified content fresh — with a one-line notice — instead of silently overwriting the external change.
- Several rounds of internal bug-audit fixes closed out this pass (word-count gate, label-regex, font dedup, test-fixture cleanup).
- **Not in this release**: rotated-page bakers for decorations/forms/signatures, stable annotation-undo handles, and byte-identical unedited exports remain open, tracked as documented follow-ups in the engine hardening plans.

### Signing

Two related regressions in trusted-timestamp (RFC-3161) signing were found and fixed this cycle:

- Fixed trusted timestamps being silently broken in sandboxed builds — the app was making outbound timestamp-authority requests without declaring the network-client entitlement, so every request failed and signatures silently fell back to un-timestamped. Also fixed ATS blocking two of the fallback timestamp authorities.
- That fix was then accidentally reverted by an unrelated project-regeneration step that didn't carry the entitlement forward. It's now fixed at the actual source of truth (`project.yml`) so it survives future regeneration.

### Toolbar & Sidebar

- **Sidebar page-thumbnail drag reordering** now actually works — the gesture was wired up already, but a container view was swallowing it before it could start.
- Toolbar decluttering continues: a single leading action, curated trailing actions, and a "More" overflow popover.
- Redo is now bound to the macOS-conventional ⌘Y.
- Minor polish: toolbar icon focus/highlight containment, spacing around sidebar icons.

### Documentation & Website

- A new animated landing page ("The Folding Studio") is live at the documentation site root — an origami-fold scroll narrative guided by the Gami and Ori companions, built with accessibility-safe (reduced-motion, no-JS-fallback) animation throughout.
- The documentation screenshot backlog from v0.8.1 is essentially closed: 13 of 14 media slots are now real captures of the running app, versus the illustrated placeholders they replaced.
- A documentation accuracy pass corrected stale "planning only" language, outdated keyboard-shortcut references, and privacy copy that had fallen behind the shipped signing feature set.

### Engineering

- **`ci.yml`'s full test-suite job — pinned to Xcode 16.4/macOS 15 — is fully green for the first time since v7.** v0.8.1 shipped with 3 of 503 tests failing there (all `PDFPage.string`/CoreText extraction quirks specific to that toolchain); this cycle's four extraction-path fixes (switching the affected assertions to PDFium-backed `PDFTextAnalysisEngine`) closed out the last of them. Confirmed on CI, not just locally.
- Several other CI-reliability fixes (project-file drift, test-fixture cleanup).
- Test suite: 589 tests, 0 failures, verified both locally and on CI's pinned toolchain.
- Source size: 132 Swift files, ~57,000 lines.

---

## Known Limitations

- Automated end-to-end UI smoke testing (beyond the headless PDF smoke test added in v0.8.1) remains on the roadmap.
- Rotated-page decoration/form/signature baking, stable annotation-undo handles, and byte-identical unedited exports remain open engine-hardening items, tracked internally in the editing-hardening plan docs.

---

## Upgrade Notes

Existing installs update automatically via the **Orifold.command** Desktop launcher. New installs use the one-line installer:

```zsh
curl -fsSL https://raw.githubusercontent.com/udhawan97/Orifold/main/install.sh | zsh
```

No data migration is required; no settings or documents are affected by this release.

---

Orifold folds a thousand messy pages so you never have to. The crane stays; the chaos doesn't.
