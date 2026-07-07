# Orifold Documentation Website — Product Plan

**Status:** Implemented — the site described here shipped as `docs-site/` (Astro/Starlight), live at https://udhawan97.github.io/Orifold/. Kept here as the original design rationale.
**Audience for this document:** The implementing agent (Sonnet) plus the maintainer.
**Product baseline:** Orifold v7 — macOS 14+ native SwiftUI PDF workspace. Free, MIT, 100% local, 6 languages, Gami & Ori companions.
**Repo:** `udhawan97/Orifold`. Existing brand assets live in `docs/assets/` (crane-fold SVG, hero banners light/dark, value props, architecture diagram, Gami/Ori animations).

---

## 1. Information Architecture

Four clearly separated zones: **User Guide** (task-first), **Help** (troubleshooting/FAQ), **Release Notes**, and **Developers**. Beginners never wade through contributor content; recruiters and contributors get a dedicated wing.

### Full sidebar structure

```
🏠 Home (docs landing page — not in sidebar, reachable via logo)

GET STARTED
├── What is Orifold?                    /get-started/what-is-orifold/
├── Install Orifold                     /get-started/install/
│     (one-line installer, Homebrew, direct download, unidentified-developer prompt)
├── Your first workspace                /get-started/first-workspace/
│     (launch → pick Gami or Ori → drop files → export; the 5-minute tour)
├── The Orifold window                  /get-started/the-window/
│     (sidebar, canvas, toolbar, inspector, page indicator — annotated screenshot)
├── Update & uninstall                  /get-started/update-uninstall/
└── Meet Gami & Ori                     /get-started/companion/

IMPORT & ORGANIZE
├── Import files                        /import/import-files/
│     (supported formats, 50-file limit, drag & drop, corrupt-PDF repair)
├── Combine files into one PDF          /import/combine/
├── Reorder, rotate & delete pages      /import/organize-pages/
├── Section banners                     /import/section-banners/
├── Recently viewed files               /import/recently-viewed/
└── Password-protected PDFs (opening)   /import/locked-pdfs/

EDIT
├── Edit existing PDF text              /edit/edit-text/
├── Add new text boxes                  /edit/text-boxes/
├── Match, copy, paste & reset          /edit/formatting/
│     text formatting
├── OCR scanned pages                   /edit/ocr/
└── Undo & redo                         /edit/undo/

ANNOTATE & REVIEW
├── Highlight, underline & strikeout    /annotate/markup/
├── Notes & ink                         /annotate/notes-ink/
├── Comments & review                   /annotate/comments/
├── Tags & document details             /annotate/tags-details/
└── Stamps, watermarks, page numbers    /annotate/stamps/
      & Bates labels

FILL & SIGN
├── Fill PDF forms                      /fill-sign/forms/
├── Reset & lock form answers           /fill-sign/lock-forms/
└── Sign documents                      /fill-sign/signatures/

EXPORT & PROTECT
├── Export & save                       /export/export-save/
│     (PDF, DOCX, Markdown, TXT, HTML, PNG, JPEG, print; "where did my file go?")
├── Compress a PDF                      /export/compress/
├── Password-protect a PDF (AES-256)    /export/protect/
├── Sanitize before sharing             /export/sanitize/
└── Export integrity checks             /export/integrity/

READ COMFORTABLY
├── Reader Mode                         /reading/reader-mode/
├── Night Mode & Document Comfort       /reading/night-mode/
│     (Gentle / Paper / Amber presets)
└── Search inside your workspace        /reading/search/

SETTINGS & BASICS
├── Change the app language             /settings/language/
├── Keyboard shortcuts                  /settings/shortcuts/
└── Privacy & local-first design        /settings/privacy/      ★ trust page

HELP
├── Troubleshooting                     /help/troubleshooting/
│     ├── Installation problems         /help/troubleshooting/install/
│     ├── Import & file problems        /help/troubleshooting/import/
│     └── Export & save problems        /help/troubleshooting/export/
└── FAQ                                 /help/faq/

RELEASE NOTES
├── What's new (latest — v7)            /releases/
└── Older releases (v3–v6)              /releases/v6/ … /releases/v3/

DEVELOPERS
├── Why Orifold?                        /developers/why-orifold/   ★ philosophy page
├── Architecture overview               /developers/architecture/
├── Build from source                   /developers/build/
├── The engines: PDFKit, PDFium,        /developers/engines/
│     qpdf & Vision
├── Localization guide                  /developers/localization/
├── Testing & the release gate          /developers/release-gate/
└── Contributing                        /developers/contributing/
```

### IA rules

- **Task-first naming.** Sidebar labels are verbs users type into search ("Combine files into one PDF", never "Merge module"). Mirrors PDF Expert's workflow grouping (Import → Edit → Annotate → Fill & Sign → Export) with Acrobat-style Get Started / What's New / Troubleshooting top rails.
- **Max depth: 2 levels** below a section header (only Troubleshooting nests to level 2). Everything else is section → page.
- **One task = one page.** Sejda-style: short pages with a clear outcome beat encyclopedic ones. If a page needs more than ~7 steps, split it.
- **Nitro-style pro workflows** (OCR, Bates labels, AES-256, sanitize, form locking) live in the same user sections — not ghettoized in an "advanced" bucket — but carry a `Pro workflow` badge so beginners can skip them.
- **User docs never mention Swift, qpdf flags, or internals.** Cross-links from user pages to Developer pages are allowed only in a "How it works" footer callout (e.g. Protect page → engines page).

---

## 2. Docs Landing Page

A single calm screen, not a marketing page — the marketing already lives in the README. Structure top to bottom:

1. **Hero.** The existing `orifold-crane-fold.svg` at left (respects `prefers-reduced-motion` — it already has a static final frame), headline right:
   - **Headline:** "Fold chaos into one clean PDF."
   - **Subline:** "Orifold is a free, open-source PDF workspace for macOS. Import up to 50 messy files, edit, sign, and export one polished document — without anything ever leaving your Mac."
   - Two buttons: `Get started →` (primary, accent) and `Install in 30 seconds` (ghost).
2. **Search bar** directly under the hero, full-width on mobile — visually the second element on the page, keyboard-focusable via `/` or `⌘K`. Placeholder cycles a hint: "Try 'combine PDFs' or 'change language'…".
3. **Trust strip** — one slim horizontal band, three items with icons: `🔒 100% local — no uploads, no account` · `🆓 Free forever — MIT licensed` · `🧪 354 tests gate every release`. Links to the Privacy page and repo. This is the local-first callout; keep it quiet and factual, no marketing superlatives.
4. **"Start here" card row (3 cards):** Install Orifold / Your first workspace / The Orifold window.
5. **"Popular workflows" card grid (6–8 cards)** — the actual top support queries:
   - Combine files into one PDF
   - Edit text in a PDF
   - Sign a document
   - Fill a form
   - Compress a PDF for email
   - Password-protect a PDF
   - Make a scan searchable (OCR)
   - Change the app language
6. **Zone footer row (4 cards):** Troubleshooting · FAQ · What's new in v7 · For developers.
7. **Footer:** GitHub, license, "Built in public" line, language switcher placeholder (see §7).

**Visual language:** each card is a `dsCard` surface with a 1px `dsSeparator` border, a single crisp line icon, and a folded top-right corner (see §5 — the one signature motif). No screenshots on the landing page; it must load instantly.

---

## 3. Core Documentation Sections — Page-by-Page Plan

Every page below lists: goal, key content, and the search phrases it must rank for internally. All follow the Task template (§4) unless noted.

### Get Started

| Page | Goal & key content | Must answer |
|---|---|---|
| **What is Orifold?** (Concept) | 3-paragraph orientation + the import→edit→export workspace diagram (reuse `orifold-v3-workspace-diagram.svg`). Positions "workspace, not file editor": you fold many files into one. | "what does this app do" |
| **Install Orifold** | The one-line `curl … \| zsh` installer as the primary path; Homebrew and direct-download in tabs; the Desktop `.command` helpers explained; the "unidentified developer" right-click→Open flow with screenshot. Requirements: macOS 14+ only. | "how to install", "won't open", "unidentified developer" |
| **Your first workspace** | The 5-minute happy path: launch → choose Gami or Ori → drop 3 files onto the empty-state screen → reorder in the sidebar → export one PDF. Ends with "you now know 80% of Orifold." | "getting started", "tutorial" |
| **The Orifold window** (Concept) | One annotated screenshot: sidebar (documents & pages), canvas, annotation toolbar, inspector, page indicator, search field, companion. Every label links to that feature's page. | "what is the inspector", "where is X" |
| **Update & uninstall** | `Orifold.command` double-click updates (and de-duplicates stray copies); Homebrew upgrade; the clean uninstaller; `--keep-user-data` option. | "update", "uninstall", "remove" |
| **Meet Gami & Ori** | Choosing/switching companions, what they react to (highlight, sign, export, warnings), and — prominently — how to turn them off (**Show Orifold Buddy** menu toggle). Tone: charming but respectful of people who want silence. | "turn off the dog", "hide the cat" |

### Import & Organize

| Page | Goal & key content |
|---|---|
| **Import files** | Drag & drop, Open dialog, ⇧⌘O. Full supported-format table (PDF, Word, HTML, Markdown, text, CSV, JSON, XML, images). The 50-file workspace limit, stated plainly. Callout: corrupt PDFs are auto-repaired via qpdf recovery — "if Preview gives up on it, try it here." |
| **Combine files into one PDF** | The #1 workflow. Key teaching: *merging is not a separate step* — the workspace IS the merge; arrange, then export once. Short steps, before/after visual. |
| **Reorder, rotate & delete pages** | Sidebar drag-reorder across documents, rotate, delete; ⌘Z safety net callout ("page deletes are undoable — experiment freely"). |
| **Section banners** | Adding divider/banner pages between merged documents for packets and exhibits. |
| **Recently viewed files** | The empty-state shelf, local-only thumbnails (privacy note), clearing history. Must answer "where are my recent files". |
| **Opening locked PDFs** | Password prompt on import, what permissions checks mean, link to the *creating* protected PDFs page. |

### Edit

| Page | Goal & key content |
|---|---|
| **Edit existing PDF text** | The flagship editor feature. Click detected text → edit in place. Honest scope section: what "detected text" means, why scans need OCR first (link), what happens to fonts. Warning callout about complex layouts. |
| **Add new text boxes** | Insert, move, resize, style a text box; difference vs. editing detected text (decision callout at top: "Which do I want?"). |
| **Match, copy, paste & reset formatting** | Matching a text box to nearby PDF text, copying format between boxes, resetting to default. Small page, heavy on before/after visuals. |
| **OCR scanned pages** | Local Vision OCR; what "searchable" adds; recognized text survives export; ⌘F now works. Privacy callout: OCR runs on-device — a scan of your passport never leaves the machine. |
| **Undo & redo** | Tiny page: ⌘Z / ⇧⌘Z, what's covered (page ops, edits, annotations). Exists because "can I undo a page delete" is a real search. |

### Annotate & Review

| Page | Goal & key content |
|---|---|
| **Highlight, underline & strikeout** | Toolbar tools, colors (highlight yellow `#FBE382` and coral shown as swatches), keyboard-free flow. |
| **Notes & ink** | Sticky notes and freehand ink; where notes appear in the inspector. |
| **Comments & review** | Workspace comments, the inspector's annotation list as a review index, and the export note: hidden Orifold comment metadata is stripped from flat exports (reviewers' margin chatter doesn't ship). |
| **Tags & document details** | Tagging documents in a workspace, viewing metadata. |
| **Stamps, watermarks, page numbers & Bates labels** `Pro workflow` | One page, four tabs. Movable stamps; decorations are *burned in* at export (flattening explained in one sentence). Bates section speaks legal-user language: prefix, padding, sequential across the packet. |

### Fill & Sign

| Page | Goal & key content |
|---|---|
| **Fill PDF forms** | Field detection, typing answers, checkboxes, navigating fields. |
| **Reset & lock form answers** `Pro workflow` | Reset the whole form; lock answers during export so recipients can't edit them — the "flatten before sharing" tip elevated to a page. |
| **Sign documents** | Draw a signature, place & resize it, export the signed PDF locally. Trust callout: no e-sign service, no upload — the signature never leaves the Mac. Honest-scope note distinguishing a drawn signature from cryptographic digital signatures. |

### Export & Protect

| Page | Goal & key content |
|---|---|
| **Export & save** | All formats (PDF, DOCX, Markdown, TXT, HTML, PNG pages, JPEG pages, print), the save dialog, and a dedicated **"Where did my file go?"** section (answers the sandbox reality: files land exactly where you chose in the save panel; no hidden folder). ⇧⌘E shortcut. |
| **Compress a PDF** `Pro workflow` | Two-stage story in user terms: images are downsampled, then the file structure is losslessly repacked; post-compression validation confirms the result. Expectation-setting: text-only PDFs barely shrink. |
| **Password-protect a PDF** `Pro workflow` | AES-256 (PDF 2.0/R6), setting the password, permission options, post-export verification. Warning callout: no password recovery — it's real encryption; lose the password, lose the file. |
| **Sanitize before sharing** `Pro workflow` | What the pass strips (auto-run actions, embedded JavaScript, embedded files, opt-in metadata) and when to use it (files from unknown sources, files leaving your org). |
| **Export integrity checks** (Concept, short) | Every export passes a qpdf structural check before touching disk; what the error report means when a malformed PDF fails. Links from every export-related troubleshooting entry. |

### Read Comfortably

| Page | Goal & key content |
|---|---|
| **Reader Mode** | Entering/leaving distraction-free reading; what gets hidden. |
| **Night Mode & Document Comfort** | The Document Comfort popover; Gentle / Paper / Amber warmth-and-dimming presets with a visual strip comparing them; when to pick which. |
| **Search inside your workspace** | ⌘F, workspace-wide scope (across all imported files), why scans need OCR first (link). |

### Settings & Basics

| Page | Goal & key content |
|---|---|
| **Change the app language** | Switcher on the landing screen, the 6 languages (English, Español, Français, हिन्दी, 简体中文, 日本語), persistence across launches. Each language named in itself so a user lost in the wrong language can still find theirs. |
| **Keyboard shortcuts** (Reference) | Honest, small table: ⌘F find, ⌘Z / ⇧⌘Z undo/redo, ⇧⌘O open, ⇧⌘E export, Esc/Return in dialogs, plus standard macOS text-editing keys. Do NOT pad with invented shortcuts; note the page will grow. |
| **Privacy & local-first design** ★ (Concept) | The trust page. Structure: (1) the one-sentence promise — *there is no server*; (2) what runs locally (import, OCR, compression, encryption, export — everything); (3) the exactly-two sandbox entitlements, shown as code; (4) zero telemetry — "stars are the only telemetry we get"; (5) verify-it-yourself section: it's open source, here's the code, here's how to watch network activity. Written plainly, no marketing tone. |

### Help

| Page | Goal & key content |
|---|---|
| **Troubleshooting hub** | Symptom-first index ("The app won't open" / "My file won't import" / "Export failed"), linking to three sub-pages. |
| **→ Installation problems** | Seeded directly from the README's real entries: installer link opens GitHub instead of installing; unidentified-developer warning; `.command` won't open (chmod fix); "no prebuilt release available" (`ORIFOLD_ALLOW_SOURCE_BUILD=1`); Terminal closed too fast (log locations: `.build/install.log`, `~/.orifold/prebuilt-install.log`). |
| **→ Import & file problems** | Corrupt PDF behavior and repair limits; 50-file limit hit; unsupported format; password prompt loops; huge-file performance expectations. |
| **→ Export & save problems** | Structural-check failure messages; can't find the exported file; protected export won't open elsewhere (PDF 2.0/R6 reader-compat note); compression didn't shrink the file. |
| **FAQ** | ~15 one-paragraph answers: Is it really free? / Does anything upload? / Windows or iPad version? (No — macOS 14+ only, and say so kindly) / Can I recover a lost password? (No) / Is my signature legally binding? / How do I turn off Gami/Ori? / Why does macOS warn about the developer? / Can I contribute? / How is this free — what's the catch? (MIT, built in public, no catch). |

### Release Notes

- **/releases/** — reverse-chronological "What's new," latest (v7) expanded at top. Each release: date, 3–5 headline changes with links into the relevant docs page, then details. Seed content from the existing `docs/release-v3…v7.md` files, rewritten user-facing.
- Convention going forward: every release PR adds a section here; headline features get a `New in v7` badge on their docs page for one release cycle.

### Developers

| Page | Goal & key content |
|---|---|
| **Why Orifold?** ★ (Concept) | Philosophy page, comparison without attack. Frame: three honest trade-offs — *rented vs. owned* (subscription tools are excellent; Orifold bets on ownership), *cloud vs. local* (cloud enables collaboration; Orifold trades that for absolute privacy), *platform vs. product* (Orifold does one thing: fold messy files into one clean PDF). Never name a competitor negatively; "Preview is excellent until the job gets complicated" is the ceiling of comparative tone. Ends with who Orifold is *not* for (collaborative review teams, Windows users) — that honesty is the trust move. |
| **Architecture overview** | Reuse `orifold-v3-architecture-diagram.svg` + the mermaid flow. Layer table (SwiftUI views → one observable view model → protocol-seamed engines → staged export pipeline). Project layout tree. 61 files/~29k lines/354 tests stats. |
| **Build from source** | Requirements (Xcode CLT, Swift 5.9+), `swift build` / `swift test`, the xcodebuild lines, `install-mac.sh --package-only`, signed/notarized build env vars. Copy nearly verbatim from README's "Under the Hood." |
| **The engines** | Why four engines: PDFKit (composition), PDFium (image compression), qpdf (repair/AES-256/sanitize/validation), Vision (OCR). Where the vendored binaries live (`Packages/PDFiumBinary`, `QPDFBinary`). Adapt `docs/features/FREE_LOCAL_ENGINES.md` and `docs/pdfium-processing.md`. |
| **Localization guide** | The 6-language xcstrings setup, the coverage-enforcing test, the SPM `Bundle.module` + JSON fallback gotcha (real CI scar tissue worth documenting), how to add a language. |
| **Testing & the release gate** | The full release-gate command list from the README, plus the manual workflow pass. Message: every release is gated. |
| **Contributing** | Issues welcome; build-from-source = onboarding ("if `swift test` passes, you're set up"); PR expectations (tests pass, localization coverage); good-first-issue pointer; code of conduct line; MIT. |

---

## 4. Page Templates

Three page types. Consistency here is what makes the site feel professional.

### Template A — Task page (majority of pages)

```markdown
---
title: Combine files into one PDF        # verb-first, ≤ 45 chars
description: Merge PDFs, Word docs, and images into a single polished PDF — all on your Mac.
type: task
badge: (optional) pro | new-in-v7
---

[Summary — 1–2 sentences, plain language, states the outcome.]

> **When to use this** — 2–3 bullet scenarios, concrete:
> - You have six PDFs and two screenshots that need to become one attachment.
> - A client sent revisions as separate files.

## Before you start          # optional; only if there are real prerequisites
- Requirement with link (e.g., "Scanned pages? Run OCR first →")

## Steps
1. Numbered, one action per step, ≤ 2 lines each. UI names in **bold**
   exactly as they appear in the app ("click **Export**", never "hit the save thing").
2. …
   ![screenshot placeholder]                      # see figure spec below
   > 💡 **Tip** — inline tip attached to the step it helps.
3. …
   > ⚠️ **Warning** — only for destructive/irreversible moments.

## What you should see       # "Expected result" — 1–2 sentences + optional screenshot
Your workspace shows one document list in the sidebar; Export produces a single PDF.

## Related
- [Reorder, rotate & delete pages](…)
- [Export & save](…)

## If something went wrong   # 2–3 symptom links into Troubleshooting
- [My file won't import →](…)
```

**Figure spec (placeholders during build):** every screenshot slot is a fenced placeholder the maintainer fills later:
`![PLACEHOLDER: sidebar with 3 documents, second page mid-drag — dark mode, 1600×1000, 2x]` — content description, mode, and dimensions in the alt text so capture is unambiguous. Screenshots are captured in **dark mode** (the brand default) at 2x, with a light-mode variant only where the UI differs materially. Wrapped in a component that renders a `dsCard`-style frame with the folded-corner motif.

### Template B — Concept page (What is Orifold?, Privacy, Why Orifold?, Architecture)

Title → summary → prose sections with H2s every ~200 words → one diagram/visual minimum → "Related" footer. No steps, no "When to use this." Max ~800 words; longer means split.

### Template C — Reference page (Shortcuts, FAQ, Troubleshooting, Release notes)

Title → 1-line summary → scannable tables or accordion Q&A → anchors on every entry (each troubleshooting symptom is deep-linkable, e.g. `/help/troubleshooting/install/#unidentified-developer`). Troubleshooting entries follow **Symptom → Cause → Fix → Still stuck? (link to GitHub Issues)**.

---

## 5. Visual Design System

Derive everything from the app's `DesignSystem.swift` so the docs feel like the app's sibling. **Dark is the brand-default theme; light is fully supported.** Respect `prefers-color-scheme`, with a manual toggle persisted to `localStorage`.

### Tokens (CSS custom properties, mapped 1:1 from the app)

| CSS variable | Dark | Light | App token |
|---|---|---|---|
| `--of-canvas` (page bg) | `#0A101C` | `#EEF0F2` | dsCanvas |
| `--of-surface` (sidebar/nav) | `#111A29` | `#F8F8F8` | dsSurface |
| `--of-card` | `#182434` | `#FFFEFC` | dsCard |
| `--of-accent` (links, active nav, primary buttons) | `#4FC3E8` | `#0C67A6` | dsAccent |
| `--of-accent-bright` (hover) | `#7ADEF4` | `#15A3C4` | dsAccentBright |
| `--of-text-1` | `#EDF3FA` | `#131F33` | dsTextPrimary |
| `--of-text-2` | `#AFC2D6` | `#44566B` | dsTextSecondary |
| `--of-text-3` | `#7C8FA3` | `#71808F` | dsTextTertiary |
| `--of-separator` | `#EDF3FA` @ 12% | `#131F33` @ 10% | dsSeparator |
| `--of-warning` | `#F9C452` | `#B37E0A` | dsWarningAccent |
| `--of-success` | `#74CDA4` | `#38805D` | dsSuccessAccent |
| `--of-error` | `#F97A6D` | `#BF3227` | dsErrorAccent |
| `--of-tancho` (rare crimson accent) | `#BF3227`-family red | same | crane's tancho crown |

### Typography

- **UI/body:** system stack (`-apple-system, "SF Pro Text", Inter, system-ui, sans-serif`) — native-feeling on the Mac audience, zero font download; optionally self-host Inter as fallback for non-Apple visitors. Body 16px/1.7.
- **Headings:** same family, weight 650, tight tracking. No decorative display font — restraint *is* the Japanese-modern move.
- **Code:** `ui-monospace, "SF Mono", "JetBrains Mono", monospace`.
- Content column max-width **72ch**; generous whitespace (`ma` 間 — negative space as a design element) rather than boxes-in-boxes.

### The origami motif — one signature element, used everywhere, subtly

**Folded corner:** cards, callouts, and screenshot frames get a small (14px) folded top-right corner rendered in CSS (a clipped triangle one shade lighter than the card, with a faint diagonal crease line). This is the single recurring paper-fold motif. **Do not** add paper textures, drop-shadow origami cranes in margins, or fold animations on scroll. Secondary motif, sparingly: a thin diagonal "crease" line as the divider between landing-page sections (1px, `--of-separator`, 2° skew).

### Components

- **Cards:** `--of-card` bg, 1px `--of-separator` border, 10px radius, folded corner, hover = border shifts to `--of-accent` at 40% + translateY(-1px). No shadows in dark mode; faint shadow in light.
- **Callouts** (4 kinds, mapping to app semantics): Tip (accent), Note (text-2/neutral), Warning (warning), Danger (error). Left border 3px + icon + tinted bg at 8% opacity. Same component renders the "When to use this" block (accent-tinted).
- **Badges:** `Pro workflow` (accent-soft pill), `New in v7` (success-soft pill), platform pill (`macOS 14+`).
- **Keys:** `<kbd>` styled as small `dsCard` chips — ⌘, ⇧ symbols rendered properly.
- **Icons:** one line-icon set only (Lucide — MIT, crisp, 1.5px stroke). No emoji in headings or nav (emoji stays in the README's voice; docs are one notch calmer).
- **Companion touch (optional, tasteful):** a tiny static Gami/Ori line drawing in the 404 page and at the end of "Your first workspace." Nowhere else.

### Motion & performance budget

- Only transitions: link/card hover (120ms), theme toggle cross-fade, details/accordion. The crane-fold SVG animates **only** on the landing hero and honors `prefers-reduced-motion` (static final frame).
- Budget: landing page ≤ 100KB transferred excluding search index (achievable: no web fonts required, SVG assets, no JS framework runtime on content pages). Lighthouse ≥ 95 on Performance and Accessibility.
- Accessibility: all token pairs above pass WCAG AA on their backgrounds (accent-on-canvas both modes ≥ 4.5:1 — verify at build); visible focus rings (`--of-accent`, 2px offset); skip-to-content link; full keyboard nav; every screenshot has real alt text (the placeholder spec forces this).

---

## 6. Search & Navigation

### Search

- **Engine: Pagefind** — static, client-side, indexes at build time, no server, no third-party service (a docs site that phones home to a search SaaS would undercut the privacy story). Ships with Starlight (§9) by default.
- **UX:** `⌘K` / `/` opens a modal; landing page embeds the same input inline. Results show page title + section + highlighted snippet, grouped by sidebar zone.
- **Synonym/keyword seeding:** front-matter `keywords` on every page so casual phrasing hits, e.g. Combine → *merge, join, stitch, put together, append*; Edit text → *change text, fix typo, modify pdf text*; Export → *save, download, where did my file go*; Language → *español, français, 日本語, change language, translate*; Protect → *password, lock, encrypt, secure*. The four canonical queries — "how do I edit text", "how do I combine PDFs", "where did my export go", "how do I change language" — must each return the right page as result #1; this is an acceptance criterion.

### Navigation

- **Sidebar:** the §1 tree; zone headers styled as small-caps `--of-text-3` labels; current page in `--of-accent` with a 2px left crease-line indicator; collapsible sections, state persisted; auto-scrolls to current item.
- **Breadcrumbs:** `Docs / Export & Protect / Compress a PDF` on every non-landing page.
- **On-page ToC:** right rail (≥1280px), H2/H3, scroll-spy; collapses into a "On this page" dropdown below the title on smaller screens.
- **Prev/Next:** footer links following sidebar order, so Get Started reads as a linear course.
- **Popular articles:** hard-curated list (no analytics exists to derive one — say so in code comments): the 8 landing-page workflow cards, repeated in the 404 page and as "Popular" fallback in empty search results.
- **Cross-links:** every Task page ends with Related + troubleshooting links (template-enforced). "Edit existing PDF text" ↔ "OCR" ↔ "Add text boxes" form a triangle — the three pages users conflate most.
- **GitHub affordances:** "Edit this page" link on every page; header links to repo + latest release.

---

## 7. Localization Readiness

Build **English-only at launch**, structured so es / fr / hi / zh-Hans / ja can be added without refactoring:

- **Path-prefix routing from day 1:** English lives at `/en/…` (root `/` redirects). Adding Japanese later = new content folder `ja/`, zero URL redesign. Starlight's built-in i18n does exactly this — configure `locales` now with only `en` enabled and the other five commented in config as a visible roadmap.
- **No text in images.** Screenshots show app UI (which is itself localized — retake per locale later, or accept English screenshots with localized captions as v1 policy — state the policy in the contributing-to-docs section). Diagrams: SVG with `<text>` elements kept translatable, or captioned externally.
- **Layout tolerance:** cards, buttons, nav items, and badges must survive +40% string length (German-class expansion; French/Hindi come close) and CJK line-breaking. Concretely: no fixed-height cards (min-height + flex), no fixed-width buttons, `overflow-wrap: anywhere` off for CJK-safe defaults, nav labels allowed to wrap to 2 lines. Test with a pseudo-locale build (`[!!! Ĉöɱƀíñé ƒíļéš !!!]`) before declaring layouts done.
- **Concise-string discipline:** sidebar labels ≤ 28 chars in English (leaves headroom), card titles ≤ 32, button labels 1–3 words.
- **UI chrome strings** (Search, On this page, Next, Edit this page…) come from the framework's translation files, never hardcoded in components.
- **Fonts:** system stack already covers Devanagari and CJK on every platform — another reason not to ship a custom Latin-only webfont.
- **RTL:** not needed for the six target languages; use CSS logical properties (`margin-inline-start` etc.) anyway — free insurance.
- **Source of truth for app-term consistency:** feature names in docs must match `Localizable.xcstrings` UI strings per locale when translation happens (e.g., whatever 日本語 calls "Reader Mode" in-app is what the docs call it). Note this in the localization guide.

---

## 8. Trust & Open-Source Positioning

The four trust surfaces (all already placed in the IA):

1. **Privacy & local-first** (`/settings/privacy/`) — spec'd in §3. The most-linked page on the site: linked from the landing trust strip, from OCR, Signatures, Protect, Recently Viewed, and the FAQ. One page, one promise, verifiable claims only.
2. **Why Orifold?** (`/developers/why-orifold/`) — spec'd in §3. Philosophy-comparison without attack; honest about what Orifold doesn't do.
3. **Contributing + Architecture + Build from source + Engines** — the developer wing doubles as the recruiter-facing portfolio: the architecture diagram, the four-engine story, the 354-test release gate, and the localization rigor are the credibility artifacts. Keep stats (file count, LOC, test count) in **one** data file so they're updated in one place, not scattered prose.
4. **Persistent positioning band:** the footer of every page carries one quiet line — "Free · Open source (MIT) · 100% local · No account, ever" — with the GitHub link. Not a banner, not a popup; a signature.

Tone rules for all trust content: verifiable claims only ("exactly two sandbox entitlements", "354 tests"), no superlatives ("blazing", "military-grade" are banned words), and every privacy claim links to the code or entitlements file that proves it.

---

## 9. Implementation Recommendation

The app is native Swift/SwiftUI — there is no web app to host a docs route in, which eliminates option 4 quickly.

| Option | Pros | Cons | Effort |
|---|---|---|---|
| **A. Static docs site — Astro Starlight on GitHub Pages** ★ | Purpose-built docs framework: sidebar, ToC, prev/next, breadcrumbs-equivalent, dark/light, `⌘K` Pagefind search, and path-prefix i18n for all 6 target languages **built in**; Markdown/MDX content non-devs can edit; zero-JS-runtime content pages (fits ≤100KB budget); free hosting, MIT stack matches the project's values; heavy theme customization via CSS tokens is a supported path | New tool in the repo (Node toolchain for docs only); origami visual identity requires real CSS override work (~2 days of the estimate) | **~4–6 focused days**: 1 scaffold+theme, 2–3 content (28 user pages + 7 dev pages, many seeded from README), 1 polish/search-tuning/CI |
| B. Static site — VitePress or Docusaurus | Same hosting story; Docusaurus has versioning | VitePress i18n and search are weaker than Starlight's for a 6-locale roadmap; Docusaurus ships a React runtime on every page — heavier, and its look fights customization more | Similar or slightly higher |
| C. Hand-rolled static HTML/CSS | Absolute control, zero dependencies, smallest possible pages | Reimplementing search, i18n routing, ToC, sidebar state = weeks; every future page costs dev time — maintainability fails the brief | High initial + high ongoing |
| D. In-app help (SwiftUI help viewer or Apple Help Book) | Offline, on-brand | Invisible to pre-install users, recruiters, and Google — defeats the trust/discovery goal; per-release update friction; doesn't remove any need for a website | Medium, wrong target |
| E. Docs route inside the existing app | — | Not applicable: Orifold is a native Mac app, no web property exists | — |

**Recommendation: A — Astro Starlight, deployed to GitHub Pages via GitHub Actions.**
It's the only option that ships §6 search, §7 i18n, and the performance budget essentially for free, leaving effort where it matters: content quality and the origami skin. In-app: add a single **Help → Orifold Help** menu item opening the site (plus per-feature "Learn more" links later — the only app change needed, explicitly allowed by the constraints).

**Hosting details:** `docs-site/` directory in the main repo (keeps "edit this page" links and doc-PRs-with-feature-PRs trivial) → Actions workflow builds on push to `main` → GitHub Pages. URL: `udhawan97.github.io/Orifold` now; custom domain later is a CNAME away. The existing `docs/` folder (assets, release notes, internal plans) stays untouched; the site consumes from it.

---

## 10. Sonnet Implementation Brief

> Everything above is the spec; this section is the work order. Do not redesign the app. Do not invent features not listed in §3 — when unsure what the app does, check `README.md` and the source, and write honest scope notes rather than aspirational ones.

### Phase plan

1. **Scaffold** — Astro Starlight in `docs-site/`, GitHub Actions deploy to Pages, base config (site title, `en` locale with 5 locales stubbed-commented, sidebar tree from §1).
2. **Theme** — implement §5 tokens as CSS custom properties overriding Starlight's; folded-corner card component; callout styles; landing page (custom splash route); dark default + toggle.
3. **Content** — all pages from §3 using §4 templates. Seed from `README.md` (install, troubleshooting, under-the-hood, privacy), `docs/release-v*.md` (release notes), `docs/features/FREE_LOCAL_ENGINES.md` + `docs/pdfium-processing.md` (engines). Screenshot slots use the placeholder spec — do not fabricate screenshots.
4. **Search & nav polish** — keyword front-matter per §6, verify the four canonical queries, prev/next order, popular-articles list, 404 page.
5. **QA** — checklist below; then a PR.

### File/folder structure

```
docs-site/
  astro.config.mjs               # Starlight config: sidebar, locales, Pagefind
  package.json
  src/
    content/docs/
      index.mdx                  # landing page (splash template)
      get-started/ …             # one .mdx per page, paths exactly per §1
      import/ … edit/ … annotate/ … fill-sign/ … export/ …
      reading/ … settings/ … help/ … releases/ … developers/
    components/
      Card.astro  CardGrid.astro           # folded-corner card
      Callout.astro                        # tip|note|warning|danger + when-to-use
      Figure.astro                         # screenshot frame + placeholder rendering
      Badge.astro  Kbd.astro  TrustStrip.astro
    styles/
      tokens.css                 # §5 table, light+dark
      theme.css                  # Starlight overrides, folded corner, crease divider
    data/
      stats.json                 # {tests: 354, files: 61, loc: "~29,000", languages: 6, version: "v7"}
      popular.json               # curated popular-articles list
  public/
    assets/ → reuse ../docs/assets/ SVGs (copy or symlink at build)
.github/workflows/docs.yml       # build + deploy Pages on push to main (path-filtered)
```

### Component requirements

- `Card` / `CardGrid`: folded corner, hover per §5, min-height not fixed-height (§7).
- `Callout`: 4 semantic variants + `whentouse` variant; icon + tinted bg; renders in both themes.
- `Figure`: renders real images in a framed card; renders `PLACEHOLDER:` alt-text slots as a visible dashed placeholder box showing the capture spec (so the site is shippable before screenshots exist).
- `Kbd`: renders ⌘⇧⌥ symbols correctly.
- `TrustStrip`: landing trust band; also emits the one-line footer signature.
- Landing page composed from these — no bespoke one-off CSS beyond `theme.css`.

### Acceptance criteria

1. `npm run build` succeeds; site deploys to GitHub Pages via Actions on push to `main`.
2. Every page in §1's tree exists at its exact path, uses its §4 template, and has: summary, (task pages) when-to-use + steps + expected result + related + troubleshooting links.
3. Searching **"how do I edit text"**, **"combine PDFs"**, **"where did my export go"**, and **"change language"** each return the correct page as the top result.
4. Dark and light themes both render correctly; dark is default for first-time visitors with no OS preference detectable; toggle persists.
5. Lighthouse (mobile, landing + one task page): Performance ≥ 95, Accessibility ≥ 95, no contrast failures.
6. Landing page transfers ≤ 100KB excluding the search index; content pages ship no framework JS runtime.
7. `prefers-reduced-motion` disables the crane animation (static final frame shown).
8. All §3 claims match the real app (v7): formats, limits (50 files), shortcuts (only the 5 real ones + standard macOS), languages (6), entitlements (2). No invented features, no invented shortcuts.
9. Stats appear only via `stats.json` — grep for "354" in `.mdx` files returns nothing.
10. Locale scaffolding: `en` path prefix live; adding a `ja/` content dir with one translated page renders correctly with no config surgery beyond uncommenting the locale.
11. Every page has a working "Edit this page" GitHub link; footer signature line on every page.
12. No content page mentions Swift/internal APIs outside the Developers section.

### Testing checklist (run before PR)

- [ ] Build clean, zero broken internal links (use Starlight's link validator or `lychee` in CI).
- [ ] Sidebar: every §1 entry present, ordered, collapsible, current-page highlight works.
- [ ] Keyboard-only pass: skip link, sidebar, search modal (`⌘K` and `/`), theme toggle, ToC — all reachable and operable.
- [ ] Screen-reader spot check (VoiceOver): landing page, one task page, one troubleshooting accordion.
- [ ] Responsive: 360px, 768px, 1280px, 1600px — no horizontal scroll, ToC collapses correctly, cards reflow.
- [ ] Pseudo-locale stress: temporarily lengthen 5 nav labels and 3 card titles by 40% — nothing truncates or overflows.
- [ ] All four canonical search queries verified (criterion 3).
- [ ] Both themes screenshot-diffed on landing + one page of each template type.
- [ ] `prefers-reduced-motion` emulation: no animation plays.
- [ ] Placeholder Figure boxes render with legible capture specs; no broken image icons anywhere.
- [ ] Release notes match `docs/release-v*.md` content; latest is v7.
- [ ] README gains one line linking to the docs site (only README change permitted).
