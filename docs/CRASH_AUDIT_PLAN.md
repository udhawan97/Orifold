# Crash Audit & Fix Plan — 2026-07-08

**Status: Planning only. No fixes applied yet.**

Every crash the user has hit is explained by two root causes, both confirmed
against real crash reports in `~/Library/Logs/DiagnosticReports/`. A third
latent site of the same class as #2 was found by code audit. PDFium interop,
`fatalError`/`try!` usage, and the other `ForEach` sites were audited and are
clean.

---

## Evidence: 6 crash reports, 2 signatures

| Report | Build | Binary | Signature |
|---|---|---|---|
| 2026-07-08 13:19:19 | 0.8.3 | `/Applications/Orifold.app` | A |
| 2026-07-08 13:19:10 | 0.8.3 | `/Applications/Orifold.app` | A |
| 2026-07-08 13:19:08 | 0.8.3 | `/Applications/Orifold.app` | A |
| 2026-07-08 13:19:05 | 0.8.3 | `/Applications/Orifold.app` | A |
| 2026-07-08 13:18:10 | 0.8.3 | `/Applications/Orifold.app` | A |
| 2026-07-07 11:05:15 | 0.8.1 | Xcode DerivedData Debug | B |

**Signature A** — `EXC_BREAKPOINT` in `_assertionFailure` ←
`NSBundle.module` one-time init ← `L10n.string(_:locale:)` ←
`AboutCommandButton.body` (main thread, during menu-bar construction).
This fires on **every launch** of the installed app — the 4 crashes in
90 seconds are a relaunch loop, not intermittent flakiness.

**Signature B** — `EXC_BREAKPOINT` in `Array._checkSubscript` ←
closure in `AnnotationToolPicker.capsule` ← `ForEachChild.updateValue` ←
`ObservationCenter._withObservation`. Classic stale-index `ForEach` trap
in a debug build while working in the app.

---

## Root cause A (P0): packaged apps ship without the SPM resource bundle

**The installed `/Applications/Orifold.app` (v0.8.3, built Jul 8 02:57)
contains zero `*.bundle` resource bundles.** Verified by inspection —
`Contents/Resources/` holds only `AppIcon.icns`, `CERTIFICATE_GUIDE.md`,
`Orifold.entitlements`.

Causal chain:

1. `Package.swift:33-37` declares `Localizable.xcstrings`,
   `Assets.xcassets`, and two `.md` files as target resources.
2. `swift build` therefore emits `Orifold_Orifold.bundle` (plus five
   `swift-crypto_*.bundle`) next to the binary — verified present in
   `.build/arm64-apple-macosx/release/`.
3. The "Assembling app bundle" step in `scripts/install-mac.sh` (~line
   484–498) copies the binary, `PDFium.framework`, generated
   `Info.plist`/`AppIcon.icns`, and two loose `.md`/entitlements files —
   **it never copies any `*.bundle`**.
4. `Orifold/App/L10n.swift:21` (`#if SWIFT_PACKAGE` branch, introduced
   2026-07-05 in `1adf01b` as the CI xcstrings fix) uses `Bundle.module`
   directly. The SPM-generated accessor `fatalError`s ("unable to find
   bundle named Orifold_Orifold") when the bundle is absent.
5. First L10n lookup happens while SwiftUI builds the menu bar
   (`AboutCommandButton.body`) → **instant crash on every launch**.

**Blast radius — worse than local:** `release.yml:106` builds the public
release zip/DMG via `install-mac.sh --package-only`, so **the shipped
v0.8.3 universal DMG (including the stable-name `Orifold.dmg` the
download page serves) crash-loops on launch for every user.** The same
missing bundle also drops all `Assets.xcassets` images and
`THIRD-PARTY-NOTICES.md` from packaged builds.

Why dev never sees it: Xcode builds don't define `SWIFT_PACKAGE` and embed
resources correctly, so debug runs work. Only swift-build-packaged apps die.

### Fix A1 — copy the resource bundles (scripts/install-mac.sh)

In the assemble step, after copying the binary:

```zsh
# SPM resource bundles (Localizable.xcstrings, Assets.xcassets, notices).
# Bundle.module resolves via Bundle.main.resourceURL, i.e. Contents/Resources.
local products_dir; products_dir="$(dirname "$built_binary")"
for resource_bundle in "$products_dir"/*.bundle(N); do
    /usr/bin/ditto --norsrc "$resource_bundle" \
        "$STAGED_APP/Contents/Resources/$(basename "$resource_bundle")"
done
```

Copy **all** `*.bundle` products (swift-crypto ones included) — cheap, and
future targets with resources are covered automatically.

### Fix A2 — hard gate in `verify_app_bundle()` (scripts/install-mac.sh:196)

```zsh
if [[ ! -d "$app_path/Contents/Resources/Orifold_Orifold.bundle" ]]; then
    fail "The app bundle is missing Orifold_Orifold.bundle (localized strings/assets). It would crash at launch."
fi
```

`verify_app_bundle` runs for both source builds (line ~337) and prebuilt
zip installs (line ~395), so stale broken release zips get refused with a
clear message instead of installing a crash-looper.

### Fix A3 — release CI smoke gate (.github/workflows/release.yml)

After the packaging step: expand the zip, assert
`Contents/Resources/Orifold_Orifold.bundle` exists, `codesign --verify
--deep --strict`, and (optional but recommended) a live launch smoke:
`open` the app, sleep ~5s, assert the process is still alive, kill it.
The structural check alone would have caught this release.

### Fix A4 — make L10n non-trapping (Orifold/App/L10n.swift:21)

Defense in depth: a packaging mistake should degrade to raw English keys,
never a launch crash-loop. Replace the direct `Bundle.module` use with a
resolver that replicates the accessor's candidate search without its
`fatalError`:

```swift
#if SWIFT_PACKAGE
private final class BundleAnchor {}
/// Bundle.module's generated accessor fatalErrors when the resource bundle
/// is missing from a packaged app — that turned a packaging omission into a
/// launch crash-loop (see docs/CRASH_AUDIT_PLAN.md). Resolve the same
/// candidates by hand and fall back to .main (raw keys) instead of trapping.
private static let bundle: Bundle = {
    let name = "Orifold_Orifold.bundle"
    let candidates = [
        Bundle.main.resourceURL,
        Bundle(for: BundleAnchor.self).resourceURL,
        Bundle.main.bundleURL,
        Bundle(for: BundleAnchor.self).bundleURL,
    ]
    for candidate in candidates {
        if let url = candidate?.appendingPathComponent(name),
           let found = Bundle(url: url) { return found }
    }
    return .main
}()
#else
...unchanged Bundle(for:) branch...
#endif
```

Note: `swift test` still resolves the bundle (it sits next to the test
runner's binary → covered by the `Bundle(for:)` candidates); the existing
JSON fallback table keeps working since it reads from this same `bundle`.
Run the full test suite to confirm the 27-test CI regression from 07-05
doesn't come back.

### Fix A5 — re-release + local cleanup

- Cut **v0.8.4** immediately after A1–A3 land so
  `releases/latest/download/Orifold.dmg` stops serving a crash-looping
  build. v0.8.3 should be yanked or marked broken in release notes.
- Reinstall locally (the current `/Applications/Orifold.app` will crash
  on every launch until replaced; per standing practice sweep stray
  copies first).

---

## Root cause B (P1): stale-index `ForEach` over computed arrays

`Orifold/Views/ContentView.swift:1685` (and the same pattern at `:1755` in
`compactToolMenu`):

```swift
ForEach(visibleToolGroups.indices, id: \.self) { groupIndex in
    ... visibleToolGroups[groupIndex] ...
}
```

`visibleToolGroups` is a **computed property** filtered by
`viewModel.isReaderMode` (`@Observable`). When reader mode toggles, the
array shrinks; SwiftUI's observation-driven child update can re-run a
child closure holding an old index against the freshly recomputed,
shorter array → `Array._checkSubscript` trap. The crash trace
(`ObservationCenter._withObservation` under `ForEachChild.updateValue`)
matches exactly.

### Fix B1 — snapshot the array so closures index what they were built from

In both `capsule` and `compactToolMenu`:

```swift
private var capsule: some View {
    let groups = visibleToolGroups   // value-type snapshot; closures capture it
    return HStack(spacing: 4) {
        ForEach(groups.indices, id: \.self) { groupIndex in
            ... groups[groupIndex] ...
        }
        ...
    }
    ...
}
```

Because `Array` is a value type, every closure then subscripts the exact
array instance its indices came from — the mismatch window disappears.

### Fix B2 — same class, latent: InspectorView annotation list

`Orifold/Views/InspectorView.swift:1195`:

```swift
ForEach(allAnnotations.indices, id: \.self) { i in
    InspectorAnnotationRow(ann: allAnnotations[i].annotation, ...)
```

`allAnnotations` (line 1150) is computed from the live document; it
changes on every annotation add/delete. Same trap waiting to fire during
normal editing with the inspector open — high exposure. Fix: snapshot
`let annotations = allAnnotations`, iterate elements directly with
identity from the annotation object, and let closures capture the
element, not the index:

```swift
ForEach(Array(annotations.enumerated()), id: \.element.annotation) { _, entry in
    InspectorAnnotationRow(ann: entry.annotation, ...)
```

(`PDFAnnotation` is a class — `id: ObjectIdentifier(entry.annotation)` via a
small wrapper if it isn't `Hashable`-stable; pick whichever compiles clean.)

### Audited, no change needed

- `ContentView.swift:2261` — indices over `Color.annotationSwatches`,
  a static constant. Safe.
- `SidebarView.swift:729` — `zip` pairs captured by value, id by refId.
  Safe.

**Rule going forward: never `ForEach(someComputedProperty.indices)` —
snapshot into a local first, or iterate identifiable elements.**

---

## Audited and clean (non-findings)

- **PDFium interop**: every FPDF_* entry point
  (`PDFiumProcessingEngine.swift:39`, `PDFTextAnalysisEngine.swift:301`,
  `PDFCompressionService.swift:208`) serializes on the global
  `pdfiumLock` with paired `FPDF_InitLibrary`/`FPDF_DestroyLibrary`.
  Not a crash source.
- **No `fatalError`, `preconditionFailure`, or `try!`** anywhere in app code.
- Two `as!` CoreText casts in `SignatureAppearanceRenderer.swift:200,208`
  (`CTLineGetGlyphRuns as! [CTRun]`, `kCTFontAttributeName as! CTFont`) —
  effectively safe by CoreText contract; optional P2: soften to `as?`
  with a skip, purely defensive.

---

## Execution order

| Phase | What | Files |
|---|---|---|
| P0 | A1 copy bundles + A2 verify gate | `scripts/install-mac.sh` |
| P0 | A3 release smoke gate | `.github/workflows/release.yml` |
| P0 | A4 non-trapping L10n bundle | `Orifold/App/L10n.swift` |
| P0 | A5 cut v0.8.4, reinstall local | release pipeline |
| P1 | B1 toolbar picker snapshot (×2 sites) | `Orifold/Views/ContentView.swift` |
| P1 | B2 inspector annotation list | `Orifold/Views/InspectorView.swift` |
| P2 | CoreText `as?` hardening | `Orifold/Signing/Appearance/SignatureAppearanceRenderer.swift` |

## Verification plan

1. `swift test` — full suite green (guards the 07-05 L10n/CI regression).
2. `scripts/install-mac.sh` locally → installed app launches, About menu
   opens, language switch works, images/pets render (proves xcassets
   bundle arrived).
3. Negative test: temporarily delete `Orifold_Orifold.bundle` from a
   staged app → verify gate must fail the install; app launched by hand
   must show raw keys, **not** crash (proves A4).
4. Toggle reader mode rapidly ~20× with the toolbar visible; add/delete
   annotations with the inspector open — no traps (proves B1/B2).
5. Release workflow on a branch: smoke gate red on pre-fix packaging,
   green after — regression-proofs the pipeline.
