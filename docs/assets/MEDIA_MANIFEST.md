# Docs media capture manifest

**Status: 12 of 14 slots are real photographic captures; 2 remain illustrated SVGs.** Real
captures live in `docs-site/public/assets/screenshots/` and `docs-site/public/assets/gifs/` and
are wired into their pages' `<Figure src="...">` prop; the `Figure` component's
dashed-placeholder fallback (see `docs-site/src/components/Figure.astro`) is not in use anywhere
in the built site.

**How the second batch was captured:** driven manually in the running app (source build, not the
older installed release — the toolbar had drifted since that build). Captured via `⌘⇧4` → `Space`
→ **⌥ Option+click** on the window, which crops to exactly the window bounds with no menu bar, no
Dock, and no drop shadow. Screenshots were reviewed against the plan's requirements (no dock, no
menu, no recording-border glare) before being resized to 1600px wide and palette-quantized for
web (135–200KB each — smaller than the first batch's real captures despite the higher source
resolution). Two pages' copy was corrected to match what the capture actually showed rather than
what was assumed: **Reader Mode** doesn't hide the sidebar/toolbar — it locks text editing and
signing and shows a "Reader" pill + one-time banner (fixed in `reading/reader-mode.mdx` and
`settings/accessibility.mdx`). **Organize pages** rotate/duplicate/delete is also reachable from
the `···` menu's Pages section, not only via right-click (both are real — verified against
`SidebarView.swift`'s `.contextMenu`).

**Component infrastructure:** a `Media.astro` component exists for real short clips —
`<video>` (MP4/WebM) + poster, IntersectionObserver play/pause, reduced-motion → poster only, and
an honest "clip pending capture" placeholder when no source is supplied. Nothing currently uses
it — all newly captured assets are static PNGs, which is a truthful, sufficient representation of
each state (dialogs, palettes, menus) without needing motion. Diagrams were renamed from
`orifold-v3-*` to `orifold-{architecture,workspace}-diagram.svg`.

**Pet figures (real app geometry):** `gami-figure.svg` and `ori-figure.svg` are generated
directly from the app's `PaperFigure` facet geometry in `Orifold/Views/OrifoldFoldMark.swift`
(same vertices, same two-tone `tone(hi)`→`tone(lo)` shading the Canvas renderer uses). They are
the real in-app companions, not illustrations, and now drive every pet appearance in the docs:
`PetTip` marks, the companion page pair, and the README companion table. The old simplified head
marks (`gami-mark.svg`/`ori-mark.svg`), the illustrated `companion-gami-ori.svg`, and the animated
`orifold-{dog-wag,cat-twitch}.svg` are no longer referenced by the live docs.

Captured for real (v0.8.1 source build, dark mode, no Dock/menu bar/recording-border in frame):
`first-workspace-empty-state.png`, `the-orifold-window-annotated.png`,
`annotate-markup-tools.png`, `night-mode-comparison.png`, `reader-mode-toggle.png`,
`language-switcher.png`, `edit-text-workflow.png`, `sign-document-workflow.png`,
`export-save-confirmation.png`, `combine-reorder-pages.png`, `reorder-rotate-delete-pages.png`.

Still illustrated SVGs (open work — replace per the standards below when captured):
`import-files-overview.svg`, `recently-viewed-shelf.svg`. Both need either a persisted
recent-files list or a mid-drag moment to capture for real — not just opening the app once.
`companion-gami-ori.svg` no longer needs capture — the companion page now shows the real
`gami-figure.svg` / `ori-figure.svg` pair directly (see above), so that row is dropped from the
shot list below.

The top-level `docs/assets/screenshots/` and `docs/assets/gifs/` folders mirror the captures for
reference; the Astro site serves only from `docs-site/public/assets/`.

## Capture standards (apply to every asset)

- **App UI only.** No personal files, desktop clutter, browser tabs, terminal output, emails,
  usernames, or real file paths anywhere in frame.
- **No system chrome.** Capture with `⌘⇧4` → `Space` → **⌥ Option+click** the window — this crops
  to the window bounds automatically, with no menu bar, no Dock, and no drop shadow. Never use
  screen recording for a still (it adds an orange capture-indicator border).
- **Demo content only.** Use a small set of clean, obviously-fake sample PDFs/images (e.g. the
  "Sample Proposal" demo doc already used across captures) — never a real document.
- **Consistent chrome.** Dark mode (the app default), same window size where practical, same
  companion (pick one of Gami/Ori and stick with it across all captures).
- **Format.** PNG for static screenshots. Resize to ~1600px wide and palette-quantize
  (`Image.quantize` / any PNG optimizer) before committing — keeps real captures under ~200KB.
- **Naming.** `kebab-case-workflow-name.png`, matching the filenames below exactly.

## Shot list

| Filename | Type | Status | Page | Shows |
| --- | --- | --- | --- | --- |
| `import-files-overview.svg` | screenshot | illustrated | [import/import-files](../../docs-site/src/content/docs/import/import-files.mdx) | Empty-state screen mid-drag, 2–3 demo files entering the drop zone |
| `combine-reorder-pages.png` | screenshot | **real** | [import/combine](../../docs-site/src/content/docs/import/combine.mdx) | Two documents in the sidebar, both expanded to show page thumbnails |
| `reorder-rotate-delete-pages.png` | screenshot | **real** | [import/organize-pages](../../docs-site/src/content/docs/import/organize-pages.mdx) | The `···` menu's Pages section: Rotate Left, Rotate Right, Duplicate Page, Delete Page |
| `edit-text-workflow.png` | screenshot | **real** | [edit/edit-text](../../docs-site/src/content/docs/edit/edit-text.mdx) | A sentence selected in detected text, with the floating format toolbar open |
| `annotate-markup-tools.png` | screenshot | **real** | [annotate/markup](../../docs-site/src/content/docs/annotate/markup.mdx) | Highlight tool active in the toolbar, one yellow highlight placed on demo text |
| `sign-document-workflow.png` | screenshot | **real** | [fill-sign/signatures](../../docs-site/src/content/docs/fill-sign/signatures.mdx) | The Digital signing palette: self-signed identity, timestamp provider picker, signature preview |
| `export-save-confirmation.png` | screenshot | **real** | [export/export-save](../../docs-site/src/content/docs/export/export-save.mdx) | The Export dialog: format picker, password/compress/sanitize options |
| `language-switcher.png` | screenshot | **real** | [settings/language](../../docs-site/src/content/docs/settings/language.mdx) | Landing-screen language switcher open, all 6 languages visible |
| `recently-viewed-shelf.svg` | screenshot | illustrated | [import/recently-viewed](../../docs-site/src/content/docs/import/recently-viewed.mdx) | Empty-state screen with the Recently Viewed shelf, 3–4 demo-file thumbnails |
| `night-mode-comparison.png` | screenshot | **real** | [reading/night-mode](../../docs-site/src/content/docs/reading/night-mode.mdx) | The Document Comfort popover open: presets, application/page mode, fine-tune sliders |
| `reader-mode-toggle.png` | screenshot | **real** | [reading/reader-mode](../../docs-site/src/content/docs/reading/reader-mode.mdx) | Reader Mode on: the Reader pill, the explanatory banner, and the View menu's toggle |
| `first-workspace-empty-state.png` | screenshot | **real** | [get-started/first-workspace](../../docs-site/src/content/docs/get-started/first-workspace.mdx) | The empty-state screen just after picking a companion (Gami shown) |
| `the-orifold-window-annotated.png` | screenshot | **real** | [get-started/the-window](../../docs-site/src/content/docs/get-started/the-window.mdx) | Sidebar, toolbar, and canvas with the Sample Proposal doc open |

Each target page's `alt` text describes the exact framing above, so whoever captures the two
remaining slots can grep the docs source for a filename and know precisely what to shoot.

## After capturing a real asset

1. Drop the file into `docs/assets/screenshots/` or `docs/assets/gifs/`.
2. Copy it into `docs-site/public/assets/screenshots/` (or `/gifs/`) so Astro can serve it — the
   Astro site does not read from the top-level `docs/` folder directly.
3. Update that page's `<Figure src="/Orifold/assets/screenshots/<file>" alt="..." caption="..." />`,
   replacing the illustrated `.svg` with the real path (and matching `.png` extension).
4. Remove the corresponding row from this table once the page no longer has a placeholder.
