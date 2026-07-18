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

`src/lib/release.ts` (`LAST_KNOWN_GOOD`) and `src/data/stats.json` both hard-code app facts
and must be refreshed on every release. Nothing fails when they drift.

`LAST_KNOWN_GOOD` is only read when the GitHub API is unreachable or rate-limited at build
time, so a stale value stays invisible until the day a build actually needs it.

`stats.json` feeds `<Stat name="…" />` and is rendered as-is. Regenerate with:

```bash
find Orifold Tests -name '*.swift' | wc -l          # files  (excludes Packages/)
find Orifold Tests -name '*.swift' | xargs cat | wc -l   # loc, rounded to nearest 1,000
swift test --list-tests | wc -l                      # tests
```

Note `files`/`loc` span **app + tests**, while README's "Under the hood" table counts the
app alone — the two are meant to differ, so don't "reconcile" them.

## Reference

- [Astro docs](https://docs.astro.build)
- [Starlight docs](https://starlight.astro.build)
- [Content collections](https://docs.astro.build/en/guides/content-collections/)
- [Internationalization](https://docs.astro.build/en/guides/internationalization/)
