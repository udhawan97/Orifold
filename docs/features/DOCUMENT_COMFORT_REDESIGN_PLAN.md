# Document Comfort Panel — Redesign & Validation Plan

Target: `DocumentComfortPopover` in `Orifold/Views/ContentView.swift` (~line 649).
Native SwiftUI/AppKit macOS app — no HTML/CSS/ARIA/TS involved.

## Root cause of the High Contrast misalignment

Page Mode grid uses `LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))])`. At 340pt
popover width this yields 3 columns. Chips are horizontal `Label(.titleAndIcon)` with no
fixed height. "High Contrast" is the only two-word label, so it wraps and grows taller
than its row-mates — reading as floating/misaligned.

Fix: fixed 3-column `GridItem(.flexible())` grid, vertical icon-over-label cards, all
`.frame(height: 64)`, `.multilineTextAlignment(.center)` + `.lineLimit(2)`. Two-line
wrapping becomes intentional instead of accidental.

## Scope implemented

1. Page Mode: fixed 3-col flexible grid, equal-height vertical cards, hover/pressed/
   selected/focus states, gated behind `shouldReduceMotion`.
2. Shared control grid: 20pt icon column, wrapping labels, right-aligned monospaced
   values for sliders.
3. Hierarchy: `.dsTitle()` header, small-caps section labels, crease-rule dividers
   instead of plain `Divider()`.
4. Reading Presets row (Default / Night / Eye Care / Focus) backed by
   `DocumentComfortSettings.preset(_:)` + `activePreset`.
5. Advanced controls (sliders + Reduce Glare/Soften White) grouped under a
   "Fine-tune" `DisclosureGroup`, persisted expanded state.
6. `ComfortInfoButton` — info.circle popover, click + keyboard-focusable, mirrored to
   `.help()` + `.accessibilityLabel`, for every control.
7. Full-width Reset button with icon + confirmation dialog when settings are
   non-default.
8. Popover width 340 → 360 at both call sites (toolbar + `ReaderModePill`).
9. Full localization of all new strings across en/es/fr/hi/zh-Hans/ja.

## Explicit non-goals (deferred)

- Per-document comfort settings (current storage is global `@AppStorage`).
- Paper Tint selector (overlaps Warm Tone/Sepia).
- Reading ruler / line guide.
- Live before/after preview sample row.

## Validation performed

- `swift build`, `swift test` (including `LocalizationCoverageTests`).
- Two self-audit loops: layout/alignment/a11y/localization/persistence/feature
  behavior, then regressions/crashes/build errors/visual bugs.
- Export-integrity check: comfort settings are presentation-only, exported bytes
  unaffected (unchanged overlay math in `DocumentComfortOverlayView`).
