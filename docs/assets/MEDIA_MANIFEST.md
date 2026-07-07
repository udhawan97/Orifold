# Docs media capture manifest

**Status: every slot below is filled with a hand-illustrated, app-faithful SVG** — not a
photographic capture. The illustrations live in `docs-site/public/assets/screenshots/` and
`docs-site/public/assets/gifs/` (as `.svg` files) and are wired into their pages' `<Figure src="...">`
prop; the `Figure` component's dashed-placeholder fallback (see
`docs-site/src/components/Figure.astro`) is no longer in use anywhere in the built site.

The top-level `docs/assets/screenshots/` and `docs/assets/gifs/` folders are unused
(placeholder `.gitkeep` only) — real photographic captures were never taken. That remains
open work: this manifest's capture standards and shot list still apply if/when someone
replaces an illustration with a real screenshot or GIF.

## Capture standards (apply to every asset)

- **App UI only.** No personal files, desktop clutter, browser tabs, terminal output, emails,
  usernames, or real file paths anywhere in frame.
- **Demo content only.** Use a small set of clean, obviously-fake sample PDFs/images (e.g.
  `Sample Agreement.pdf`, `Sample Invoice.pdf`, `Sample Scan.pdf`) — never a real document.
- **Consistent chrome.** Dark mode (the app default), same window size (1600×1000 recommended),
  same zoom level, same companion (pick one of Gami/Ori and stick with it across all captures).
- **Format.** PNG for static screenshots, GIF (or MP4 transcoded to GIF) for motion — keep GIFs
  under ~3–4 seconds looped and under ~2 MB; downscale/optimize before committing.
- **Naming.** `kebab-case-workflow-name.png` / `.gif`, matching the filenames below exactly.

## Shot list

| Filename | Type | Page | Shows |
| --- | --- | --- | --- |
| `import-files-overview.png` | screenshot | [import/import-files](../../docs-site/src/content/docs/import/import-files.mdx) | Empty-state screen mid-drag, 2–3 demo files entering the drop zone |
| `combine-reorder-pages.gif` | gif | [import/combine](../../docs-site/src/content/docs/import/combine.mdx) | Sidebar drag: a page from one demo document moved into another document's position |
| `reorder-rotate-delete-pages.gif` | gif | [import/organize-pages](../../docs-site/src/content/docs/import/organize-pages.mdx) | Right-click a page → rotate, then delete, in the sidebar |
| `edit-text-workflow.gif` | gif | [edit/edit-text](../../docs-site/src/content/docs/edit/edit-text.mdx) | Click a line of detected text, type a change, click away to commit |
| `annotate-markup-tools.png` | screenshot | [annotate/markup](../../docs-site/src/content/docs/annotate/markup.mdx) | Toolbar open with highlight/underline/strikeout tools, one highlight already placed on demo text |
| `sign-document-workflow.gif` | gif | [fill-sign/signatures](../../docs-site/src/content/docs/fill-sign/signatures.mdx) | Draw a signature, place it on a demo signature line, export |
| `export-save-confirmation.gif` | gif | [export/export-save](../../docs-site/src/content/docs/export/export-save.mdx) | ⇧⌘E → format picker → save panel → confirmation |
| `language-switcher.png` | screenshot | [settings/language](../../docs-site/src/content/docs/settings/language.mdx) | Landing-screen language switcher open, all 6 languages visible |
| `recently-viewed-shelf.png` | screenshot | [import/recently-viewed](../../docs-site/src/content/docs/import/recently-viewed.mdx) | Empty-state screen with the Recently Viewed shelf, 3–4 demo-file thumbnails |
| `night-mode-comparison.png` | screenshot | [reading/night-mode](../../docs-site/src/content/docs/reading/night-mode.mdx) | Same demo page shown side by side under a few Document Comfort reading presets |
| `reader-mode-toggle.png` | screenshot | [reading/reader-mode](../../docs-site/src/content/docs/reading/reader-mode.mdx) | Before/after: normal toolbar view vs. Reader Mode with chrome hidden |
| `first-workspace-empty-state.png` | screenshot | [get-started/first-workspace](../../docs-site/src/content/docs/get-started/first-workspace.mdx) | The Gami/Ori companion picker on first launch |
| `the-orifold-window-annotated.png` | screenshot | [get-started/the-window](../../docs-site/src/content/docs/get-started/the-window.mdx) | Full window with sidebar/canvas/toolbar/inspector regions labeled |
| `companion-gami-ori.png` | screenshot | [get-started/companion](../../docs-site/src/content/docs/get-started/companion.mdx) | Gami and Ori shown side by side in the corner of a workspace |

Each target page's placeholder `alt` text repeats the exact filename and framing above, so
whoever captures these can grep the docs source for a filename and know precisely what to shoot.

## After capturing a real asset

1. Drop the file into `docs/assets/screenshots/` or `docs/assets/gifs/`.
2. Copy it into `docs-site/public/assets/screenshots/` (or `/gifs/`) so Astro can serve it — the
   Astro site does not read from the top-level `docs/` folder directly.
3. Update that page's `<Figure src="/Orifold/assets/screenshots/<file>" alt="..." caption="..." />`,
   replacing the placeholder (no `src`) with the real path.
4. Remove the corresponding row from this table once the page no longer has a placeholder.
