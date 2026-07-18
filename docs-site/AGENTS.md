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

`src/lib/release.ts` and `src/data/stats.json` both hard-code the app version and must be
bumped alongside `project.yml`. They drift independently — `release.ts` is currently stale at
`0.8.10` while `stats.json` tracks the shipped `0.8.14`.

## Reference

- [Astro docs](https://docs.astro.build)
- [Starlight docs](https://starlight.astro.build)
- [Content collections](https://docs.astro.build/en/guides/content-collections/)
- [Internationalization](https://docs.astro.build/en/guides/internationalization/)
