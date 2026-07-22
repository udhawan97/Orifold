# Orifold website and documentation

The public Astro/Starlight site for [Orifold](https://github.com/udhawan97/Orifold), including the custom product landing page, user guide, release notes, and developer documentation published at [udhawan97.github.io/Orifold](https://udhawan97.github.io/Orifold/).

## Project structure

```text
.
├── public/                 Static images, GIFs, icons, and install assets
├── src/
│   ├── content/docs/       User and developer documentation
│   ├── data/               Public product and release facts
│   ├── pages/index.astro   Custom product landing page
│   └── styles/             Shared docs and landing-page styles
├── astro.config.mjs        Site, navigation, and Starlight configuration
└── package.json
```

## Commands

Run from `docs-site/`:

| Command | Action |
| :--- | :--- |
| `npm ci` | Install locked dependencies |
| `npm run dev` | Start the local site at `localhost:4321` |
| `npm run build` | Build the production site into `dist/` |
| `npm run preview` | Preview the production build locally |
| `npm run astro -- --help` | Show Astro CLI help |

## Documentation contract

- Describe behavior the shipped app actually supports and keep limitations visible.
- Keep `src/data/stats.json` and release fallback metadata current for a new release.
- Use root-relative `/Orifold/...` links so the GitHub Pages base path is preserved.
- Run `npm run build` before publishing. GitHub Pages deployment remains separate from the native-app release workflow.
