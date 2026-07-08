# Docs media capture manifest

**Status: 13 of 14 slots are real photographic captures; 1 remains an illustrated SVG.** Real
captures live in `docs-site/public/assets/screenshots/` and `docs-site/public/assets/gifs/` and
are wired into their pages' `<Figure src="...">` prop; the `Figure` component's
dashed-placeholder fallback (see `docs-site/src/components/Figure.astro`) is not in use anywhere
in the built site.

**How the second batch was captured:** driven manually in the running app (source build, not the
older installed release — the toolbar had drifted since that build). Captured via `⌘⇧4` → `Space`
→ **⌥ Option+click** on the window, which crops to exactly the window bounds with no menu bar, no
Dock, and no drop shadow — never use screen recording for a still (it adds an orange
capture-indicator border). Screenshots were resized to 1600px wide and palette-quantized for web
(135–200KB each — smaller than the first batch's real captures despite the higher source
resolution). Two pages' copy was corrected to match what the capture actually showed rather than
what was assumed: **Reader Mode** doesn't hide the sidebar/toolbar — it locks text editing and
signing and shows a "Reader" pill + one-time banner (fixed in `reading/reader-mode.mdx` and
`settings/accessibility.mdx`). **Organize pages** rotate/duplicate/delete is also reachable from
the `···` menu's Pages section, not only via right-click (both are real — verified against
`SidebarView.swift`'s `.contextMenu`).

**Component infrastructure:** a `Media.astro` component exists for real short clips —
`<video>` (MP4/WebM) + poster, IntersectionObserver play/pause, reduced-motion → poster only, and
an honest "clip pending capture" placeholder when no source is supplied. One page still uses it
as an honest placeholder (see below); everywhere else a real static capture was sufficient to
represent the state truthfully (dialogs, palettes, menus don't need motion to be understood).
Diagrams were renamed from `orifold-v3-*` to `orifold-{architecture,workspace}-diagram.svg`.

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
`language-switcher.png`, `edit-text-workflow.png`, `sign-document-digital.png`,
`export-save-confirmation.png`, `combine-reorder-pages.png`, `reorder-rotate-delete-pages.png`,
`import-files-overview.png`, `recently-viewed-shelf.png`.

`import-files-overview.png` catches a real mid-drag moment ("Release to import files," drop zone
highlighted, a demo PDF hovering above it). `recently-viewed-shelf.png` shows a real one-file
shelf entry (a "Resume · p. 1" badge, "6h ago · 1 page") — the alt text was corrected to describe
one real thumbnail rather than the "3–4 demo thumbnails" the illustration implied.
`combine-reorder-pages.png` was upgraded from a two-document to a three-document sidebar capture.

Still illustrated SVG (open work — replace per the standards below when captured):
`sign-document-workflow-visual.svg` (the Draw/Type/Initials flow — distinct from the Digital
signing capture above, which already has a real screenshot). It's wired through the `Media`
component (`docs-site/src/components/Media.astro`) with the illustrated SVG as the video
`poster`, so dropping in a real clip later is a one-line change — add
`mp4="/Orifold/assets/gifs/<name>.mp4"` next to the existing `poster=` and the still is replaced
by an autoplaying, muted, looping, reduced-motion-aware `<video>`:

| Page | `Media` on page | Target clip |
| --- | --- | --- |
| `fill-sign/signatures` (visual signature section) | `sign-document-workflow-visual.svg` | 4–6s · draw a signature → place on the line → export |

`companion-gami-ori.svg` no longer needs capture — the companion page now shows the real
`gami-figure.svg` / `ori-figure.svg` pair directly (see above), so that row is dropped from the
shot list below.

The top-level `docs/assets/screenshots/` and `docs/assets/gifs/` folders mirror the captures for
reference; the Astro site serves only from `docs-site/public/assets/`.

## Capture standards (apply to every asset)

- **App UI only.** No personal files, desktop clutter, browser tabs, terminal output, emails,
  usernames, or real file paths anywhere in frame.
- **No system chrome.** Capture stills with `⌘⇧4` → `Space` → **⌥ Option+click** the window — this
  crops to the window bounds automatically, with no menu bar, no Dock, and no drop shadow. Never
  use screen recording for a still (it adds an orange capture-indicator border).
- **Demo content only.** Use a small set of clean, obviously-fake sample PDFs/images (e.g. the
  "Sample Proposal" demo doc already used across captures) — never a real document.
- **Consistent chrome.** Dark mode (the app default), same window size where practical, same
  companion (pick one of Gami/Ori and stick with it across all captures).
- **Format.** PNG for static screenshots — resize to ~1600px wide and palette-quantize
  (`Image.quantize` / any PNG optimizer) before committing, keeps real captures under ~200KB.
  **MP4 (H.264) for motion — not GIF** (the `Media` component renders `<video>`, which is smaller
  and higher-quality than a GIF). Keep clips under ~3–6 seconds, looping cleanly (first frame ≈
  last frame), silent, and under ~1.5 MB; add a poster still and downscale/optimize before
  committing.
- **Naming.** `kebab-case-workflow-name.png` / `.mp4`, matching the filenames below exactly.

## Shot list

| Filename | Type | Status | Page | Shows |
| --- | --- | --- | --- | --- |
| `import-files-overview.png` | screenshot | **real** | [import/import-files](../../docs-site/src/content/docs/import/import-files.mdx) | Empty-state screen mid-drag: "Release to import files," a demo PDF hovering over the highlighted drop zone |
| `combine-reorder-pages.png` | screenshot | **real** | [import/combine](../../docs-site/src/content/docs/import/combine.mdx) | Three documents in the sidebar, each expanded to show page thumbnails |
| `reorder-rotate-delete-pages.png` | screenshot | **real** | [import/organize-pages](../../docs-site/src/content/docs/import/organize-pages.mdx) | The `···` menu's Pages section: Rotate Left, Rotate Right, Duplicate Page, Delete Page |
| `edit-text-workflow.png` | screenshot | **real** | [edit/edit-text](../../docs-site/src/content/docs/edit/edit-text.mdx) | A sentence selected in detected text, with the floating format toolbar open |
| `annotate-markup-tools.png` | screenshot | **real** | [annotate/markup](../../docs-site/src/content/docs/annotate/markup.mdx) | Highlight tool active in the toolbar, one yellow highlight placed on demo text |
| `sign-document-workflow-visual.svg` | Media poster | illustrated | [fill-sign/signatures](../../docs-site/src/content/docs/fill-sign/signatures.mdx) | Draw a signature, place it on a demo signature line, export |
| `sign-document-digital.png` | screenshot | **real** | [fill-sign/signatures](../../docs-site/src/content/docs/fill-sign/signatures.mdx) | The Digital signing palette: self-signed identity, timestamp provider picker, signature preview |
| `export-save-confirmation.png` | screenshot | **real** | [export/export-save](../../docs-site/src/content/docs/export/export-save.mdx) | The Export dialog: format picker, password/compress/sanitize options |
| `language-switcher.png` | screenshot | **real** | [settings/language](../../docs-site/src/content/docs/settings/language.mdx) | Landing-screen language switcher open, all 6 languages visible |
| `recently-viewed-shelf.png` | screenshot | **real** | [import/recently-viewed](../../docs-site/src/content/docs/import/recently-viewed.mdx) | Empty-state screen with the Recently Viewed shelf: a "Sample Proposal" thumbnail with a "Resume · p. 1" badge |
| `night-mode-comparison.png` | screenshot | **real** | [reading/night-mode](../../docs-site/src/content/docs/reading/night-mode.mdx) | The Document Comfort popover open: presets, application/page mode, fine-tune sliders |
| `reader-mode-toggle.png` | screenshot | **real** | [reading/reader-mode](../../docs-site/src/content/docs/reading/reader-mode.mdx) | Reader Mode on: the Reader pill, the explanatory banner, and the View menu's toggle |
| `first-workspace-empty-state.png` | screenshot | **real** | [get-started/first-workspace](../../docs-site/src/content/docs/get-started/first-workspace.mdx) | The empty-state screen just after picking a companion (Gami shown) |
| `the-orifold-window-annotated.png` | screenshot | **real** | [get-started/the-window](../../docs-site/src/content/docs/get-started/the-window.mdx) | Sidebar, toolbar, and canvas with the Sample Proposal doc open |

Each target page's `alt` text describes the exact framing above, so whoever captures the
remaining slot can grep the docs source for the filename and know precisely what to shoot.

## After capturing a real asset

1. Drop the file into `docs/assets/screenshots/` or `docs/assets/gifs/`.
2. Copy it into `docs-site/public/assets/screenshots/` (or `/gifs/`) so Astro can serve it — the
   Astro site does not read from the top-level `docs/` folder directly.
3. Update that page's `<Figure src="/Orifold/assets/screenshots/<file>" alt="..." caption="..." />`,
   replacing the illustrated `.svg` with the real path (and matching `.png` extension) — or, for
   the one page still using `<Media>`, add `mp4=` alongside the existing `poster=`.
4. Remove the corresponding row from this table once the page no longer has a placeholder.
