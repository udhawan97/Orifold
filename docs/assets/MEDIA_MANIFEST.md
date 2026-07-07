# Docs media capture manifest

**Status: 6 of 14 slots are real photographic captures; the remaining 8 are hand-illustrated,
app-faithful SVGs** shown as honestly-captioned `<Figure>` illustrations (never claimed as
recordings). Both live in `docs-site/public/assets/screenshots/` and
`docs-site/public/assets/gifs/` and are wired into their pages' `<Figure src="...">` prop; the
`Figure` component's dashed-placeholder fallback (see `docs-site/src/components/Figure.astro`)
is not in use anywhere in the built site.

**Component infrastructure (added in the premium makeover):** a `Media.astro` component now
exists for real short clips — `<video>` (MP4/WebM) + poster, IntersectionObserver play/pause,
reduced-motion → poster only, and an honest "clip pending capture" placeholder when no source is
supplied. When the four first-tier flows below are captured (combine, edit-text, sign,
export-save), swap the illustrated `gifs/*.svg` `<Figure>` for `<Media mp4=... poster=... />` with
**zero other code changes**. Until then the illustrated Figures stay — they inform the reader and
are captioned as illustrations, which beats an empty placeholder. Diagrams were also renamed from
`orifold-v3-*` to `orifold-{architecture,workspace}-diagram.svg`.

**Pet figures (real app geometry):** `gami-figure.svg` and `ori-figure.svg` are generated
directly from the app's `PaperFigure` facet geometry in `Orifold/Views/OrifoldFoldMark.swift`
(same vertices, same two-tone `tone(hi)`→`tone(lo)` shading the Canvas renderer uses). They are
the real in-app companions, not illustrations, and now drive every pet appearance in the docs:
`PetTip` marks, the companion page pair, and the README companion table. The old simplified
head marks (`gami-mark.svg`/`ori-mark.svg`), the illustrated `companion-gami-ori.svg`, and the
animated `orifold-{dog-wag,cat-twitch}.svg` are no longer referenced by the live docs.

Captured for real (v0.8.1, dark mode, native window, no Dock/menu bar in frame):
`first-workspace-empty-state.png`, `the-orifold-window-annotated.png`,
`annotate-markup-tools.png`, `night-mode-comparison.png`, `reader-mode-toggle.png`,
`language-switcher.png`.

Still illustrated SVGs (open work — replace per the standards below when captured):
`import-files-overview.svg`, `combine-reorder-pages.svg`, `reorder-rotate-delete-pages.svg`,
`edit-text-workflow.svg`, `sign-document-workflow.svg`, `export-save-confirmation.svg`,
`recently-viewed-shelf.svg`, `companion-gami-ori.svg`. The recently-viewed shelf and the
Gami/Ori side-by-side comparison in particular need either a persisted recent-files list or a
companion-switch reset to capture for real — not just opening the app once.

The four **motion** flows are already wired through the `Media` component
(`docs-site/src/components/Media.astro`) with the illustrated SVG as the video `poster`, so
dropping in a real clip is a one-line change — add `mp4="/Orifold/assets/gifs/<name>.mp4"` next
to the existing `poster=` and the still is replaced by an autoplaying, muted, looping, reduced-
motion-aware `<video>`. These four, with their target clips (from each page's `spec`):

| Page | `Media` on page | Target clip |
| --- | --- | --- |
| `import/combine` | `combine-reorder-pages.svg` | 4–6s · drag a page across two demo docs → Export once |
| `import/organize-pages` | `reorder-rotate-delete-pages.svg` | 4–6s · right-click a sidebar page → Rotate, then Delete |
| `fill-sign/signatures` | `sign-document-workflow.svg` | 4–6s · draw a signature → place on the line → export |
| `export/export-save` | `export-save-confirmation.svg` | 3–5s · ⇧⌘E → pick PDF → save panel → confirmation |

`import-files-overview.svg` and `recently-viewed-shelf.svg` remain single-still `Figure`s and
should become real PNG captures, not clips.

The top-level `docs/assets/screenshots/` and `docs/assets/gifs/` folders remain unused
(placeholder `.gitkeep` only) — the Astro site serves only from `docs-site/public/assets/`.

## Capture standards (apply to every asset)

- **App UI only.** No personal files, desktop clutter, browser tabs, terminal output, emails,
  usernames, or real file paths anywhere in frame.
- **Demo content only.** Use a small set of clean, obviously-fake sample PDFs/images (e.g.
  `Sample Agreement.pdf`, `Sample Invoice.pdf`, `Sample Scan.pdf`) — never a real document.
- **Consistent chrome.** Dark mode (the app default), same window size (1600×1000 recommended),
  same zoom level, same companion (pick one of Gami/Ori and stick with it across all captures).
- **Format.** PNG for static screenshots. **MP4 (H.264) for motion — not GIF** (the `Media`
  component renders `<video>`, which is smaller and higher-quality than a GIF). Keep clips under
  ~3–6 seconds, looping cleanly (first frame ≈ last frame), silent, and under ~1.5 MB; add a
  poster still and downscale/optimize before committing.
- **Naming.** `kebab-case-workflow-name.png` / `.gif`, matching the filenames below exactly.

## Shot list

| Filename | Type | Status | Page | Shows |
| --- | --- | --- | --- | --- |
| `import-files-overview.svg` | screenshot | illustrated | [import/import-files](../../docs-site/src/content/docs/import/import-files.mdx) | Empty-state screen mid-drag, 2–3 demo files entering the drop zone |
| `combine-reorder-pages.gif` | gif | illustrated | [import/combine](../../docs-site/src/content/docs/import/combine.mdx) | Sidebar drag: a page from one demo document moved into another document's position |
| `reorder-rotate-delete-pages.gif` | gif | illustrated | [import/organize-pages](../../docs-site/src/content/docs/import/organize-pages.mdx) | Right-click a page → rotate, then delete, in the sidebar |
| `edit-text-workflow.gif` | gif | illustrated | [edit/edit-text](../../docs-site/src/content/docs/edit/edit-text.mdx) | Click a line of detected text, type a change, click away to commit |
| `annotate-markup-tools.png` | screenshot | **real** | [annotate/markup](../../docs-site/src/content/docs/annotate/markup.mdx) | Highlight tool active in the toolbar, one yellow highlight placed on demo text |
| `sign-document-workflow.gif` | gif | illustrated | [fill-sign/signatures](../../docs-site/src/content/docs/fill-sign/signatures.mdx) | Draw a signature, place it on a demo signature line, export |
| `export-save-confirmation.gif` | gif | illustrated | [export/export-save](../../docs-site/src/content/docs/export/export-save.mdx) | ⇧⌘E → format picker → save panel → confirmation |
| `language-switcher.png` | screenshot | **real** | [settings/language](../../docs-site/src/content/docs/settings/language.mdx) | Landing-screen language switcher open, all 6 languages visible |
| `recently-viewed-shelf.svg` | screenshot | illustrated | [import/recently-viewed](../../docs-site/src/content/docs/import/recently-viewed.mdx) | Empty-state screen with the Recently Viewed shelf, 3–4 demo-file thumbnails |
| `night-mode-comparison.png` | screenshot | **real** | [reading/night-mode](../../docs-site/src/content/docs/reading/night-mode.mdx) | The Document Comfort popover open: presets, application/page mode, fine-tune sliders |
| `reader-mode-toggle.png` | screenshot | **real** | [reading/reader-mode](../../docs-site/src/content/docs/reading/reader-mode.mdx) | Reader Mode active, sidebar and toolbar tucked away |
| `first-workspace-empty-state.png` | screenshot | **real** | [get-started/first-workspace](../../docs-site/src/content/docs/get-started/first-workspace.mdx) | The empty-state screen just after picking a companion (Gami shown) |
| `the-orifold-window-annotated.png` | screenshot | **real** | [get-started/the-window](../../docs-site/src/content/docs/get-started/the-window.mdx) | Sidebar, toolbar, and canvas with a document open |
| `companion-gami-ori.svg` | screenshot | illustrated | [get-started/companion](../../docs-site/src/content/docs/get-started/companion.mdx) | Gami and Ori shown side by side in the corner of a workspace |

Each target page's placeholder `alt` text repeats the exact filename and framing above, so
whoever captures these can grep the docs source for a filename and know precisely what to shoot.

## After capturing a real asset

1. Drop the file into `docs/assets/screenshots/` or `docs/assets/gifs/`.
2. Copy it into `docs-site/public/assets/screenshots/` (or `/gifs/`) so Astro can serve it — the
   Astro site does not read from the top-level `docs/` folder directly.
3. Update that page's `<Figure src="/Orifold/assets/screenshots/<file>" alt="..." caption="..." />`,
   replacing the placeholder (no `src`) with the real path.
4. Remove the corresponding row from this table once the page no longer has a placeholder.
