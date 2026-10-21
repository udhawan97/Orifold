# Orifold docs site

Astro + Starlight documentation site. Independent of the Swift app build — see the root
[CLAUDE.md](../CLAUDE.md) for the app itself.

## Development

```bash
npm run dev --prefix docs-site      # port 4321
npm run build --prefix docs-site    # verify before pushing
```

Claude Code: use `preview_start` with the `orifold-docs` config from `.claude/launch.json`
rather than running a server via bash.

## Deploys

`.github/workflows/docs.yml` deploys to GitHub Pages on push to `main` touching `docs-site/**`.
A daily 06:17 UTC cron re-bakes the download button's version and file size, so a missed
post-release rebuild self-heals within 24h.

## Gotcha

`src/lib/release.ts` resolves published metadata at build time. API failure preserves verified
stable download links but deliberately omits version, date, and file-size claims. Test this
fallback with `npm test --prefix docs-site`; never reintroduce a guessed latest version.

`src/data/stats.json` describes the source snapshot, not necessarily the latest published
release. It feeds `<Stat name="…" />`; counts do not imply passing tests. Regenerate source
file/line counts from `Orifold/` and `Tests/` and discovered methods with `swift test list`.
Report actual runner execution, skips, failures, and unexpected failures separately.
Update release notes, `project.yml`, and generated project/Info.plist together. Capture provenance
belongs in `docs/assets/MEDIA_MANIFEST.md`; older guide imagery must retain its historical label.

## Reference

- [Astro docs](https://docs.astro.build)
- [Starlight docs](https://starlight.astro.build)
- [Content collections](https://docs.astro.build/en/guides/content-collections/)
- [Internationalization](https://docs.astro.build/en/guides/internationalization/)
