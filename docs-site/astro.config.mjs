// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://udhawan97.github.io',
	base: '/Orifold',
	// The site root is now the custom landing page (src/pages/index.astro); /docs
	// is the docs front door (WEBSITE_PLAN.md §1).
	redirects: {
		// Redirect targets are emitted verbatim (Astro does not prepend `base`),
		// so the base is included here for a correct GitHub Pages redirect.
		'/docs': '/Orifold/get-started/workflows/',
	},
	integrations: [
		starlight({
			title: 'Orifold Docs',
			description:
				'Fold chaos into one clean PDF. Free, open-source, 100% local PDF workspace for macOS.',
			logo: {
				src: './public/assets/orifold-app-icon-128.png',
				replacesTitle: false,
			},
			favicon: '/assets/orifold-app-icon-32.png',
			customCss: ['./src/styles/tokens.css', './src/styles/theme.css'],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/udhawan97/Orifold' }],
			editLink: {
				baseUrl: 'https://github.com/udhawan97/Orifold/edit/main/docs-site/',
			},
			components: {
				// Expanding search button — a quiet magnifier that springs into an
				// inline Pagefind-backed search pill (replaces the modal search).
				Search: './src/components/overrides/Search.astro',
				Footer: './src/components/overrides/Footer.astro',
				Hero: './src/components/overrides/Hero.astro',
				MarkdownContent: './src/components/overrides/MarkdownContent.astro',
				PageTitle: './src/components/overrides/PageTitle.astro',
				TableOfContents: './src/components/overrides/TableOfContents.astro',
				// Paper-first theming: default to light (never the OS scheme) and swap
				// Starlight's 3-way Auto/Light/Dark select for a 2-state light⇄dark toggle.
				ThemeProvider: './src/components/overrides/ThemeProvider.astro',
				ThemeSelect: './src/components/overrides/ThemeSelect.astro',
			},
			// English ships first. Locale roadmap — uncomment as translations land.
			defaultLocale: 'root',
			locales: {
				root: { label: 'English', lang: 'en' },
				// es: { label: 'Español', lang: 'es' },
				// fr: { label: 'Français', lang: 'fr' },
				// hi: { label: 'हिन्दी', lang: 'hi' },
				// 'zh-cn': { label: '简体中文', lang: 'zh-CN' },
				// ja: { label: '日本語', lang: 'ja' },
			},
			sidebar: [
				{
					label: 'Get Started',
					items: [
						{ label: 'What is Orifold?', slug: 'get-started/what-is-orifold' },
						{ label: 'Popular workflows', slug: 'get-started/workflows' },
						{ label: 'Install Orifold', slug: 'get-started/install' },
						{ label: 'Your first workspace', slug: 'get-started/first-workspace' },
						{ label: 'The Orifold window', slug: 'get-started/the-window' },
						{ label: 'Update & uninstall', slug: 'get-started/update-uninstall' },
						{ label: 'Meet Gami & Ori', slug: 'get-started/companion' },
					],
				},
				{
					label: 'Import & Organize',
					items: [
						{ label: 'Import files', slug: 'import/import-files' },
						{ label: 'Combine files into one PDF', slug: 'import/combine' },
						{ label: 'Reorder, rotate & delete pages', slug: 'import/organize-pages' },
						{ label: 'Section banners', slug: 'import/section-banners' },
						{ label: 'Recently viewed files', slug: 'import/recently-viewed' },
						{ label: 'Opening locked PDFs', slug: 'import/locked-pdfs' },
					],
				},
				{
					label: 'Edit',
					items: [
						{ label: 'Edit existing PDF text', slug: 'edit/edit-text' },
						{ label: 'Add new text boxes', slug: 'edit/text-boxes' },
						{ label: 'Match, copy, paste & reset formatting', slug: 'edit/formatting' },
						{ label: 'OCR scanned pages', slug: 'edit/ocr' },
						{ label: 'Move & edit objects', slug: 'edit/edit-objects', badge: { text: 'Beta', variant: 'caution' } },
						{ label: 'Undo & redo', slug: 'edit/undo' },
					],
				},
				{
					label: 'Annotate & Review',
					items: [
						{ label: 'Highlight, underline & strikeout', slug: 'annotate/markup' },
						{ label: 'Notes & ink', slug: 'annotate/notes-ink' },
						{ label: 'Comments & review', slug: 'annotate/comments' },
						{ label: 'Tags & document details', slug: 'annotate/tags-details' },
						{ label: 'Stamps, watermarks & Bates labels', slug: 'annotate/stamps' },
					],
				},
				{
					label: 'Fill & Sign',
					items: [
						{ label: 'Fill PDF forms', slug: 'fill-sign/forms' },
						{ label: 'Reset & lock form answers', slug: 'fill-sign/lock-forms' },
						{ label: 'Sign documents', slug: 'fill-sign/signatures' },
					],
				},
				{
					label: 'Export & Protect',
					items: [
						{ label: 'Export & save', slug: 'export/export-save' },
						{ label: 'Compress a PDF', slug: 'export/compress' },
						{ label: 'Password-protect a PDF', slug: 'export/protect' },
						{ label: 'Sanitize before sharing', slug: 'export/sanitize' },
						{ label: 'Export integrity checks', slug: 'export/integrity' },
					],
				},
				{
					label: 'Read Comfortably',
					items: [
						{ label: 'Reader Mode', slug: 'reading/reader-mode' },
						{ label: 'Document Comfort', slug: 'reading/night-mode' },
						{ label: 'Search & replace', slug: 'reading/search' },
					],
				},
				{
					label: 'Settings & Basics',
					items: [
						{ label: 'Change the app language', slug: 'settings/language' },
						{ label: 'Keyboard shortcuts', slug: 'settings/shortcuts' },
						{ label: 'Accessibility', slug: 'settings/accessibility' },
						{ label: 'Privacy & local-first design', slug: 'settings/privacy' },
					],
				},
				{
					label: 'Help',
					items: [
						{ label: 'Troubleshooting', slug: 'help/troubleshooting' },
						{ label: 'Installation problems', slug: 'help/troubleshooting/install' },
						{ label: 'Import & file problems', slug: 'help/troubleshooting/import' },
						{ label: 'Export & save problems', slug: 'help/troubleshooting/export' },
						{ label: 'FAQ', slug: 'help/faq' },
					],
				},
				{
					label: 'Release Notes',
					items: [
						{ label: "What's new", slug: 'releases' },
						{ label: 'v0.7', slug: 'releases/v7' },
						{ label: 'v0.6', slug: 'releases/v6' },
						{ label: 'v0.5', slug: 'releases/v5' },
						{ label: 'v0.4', slug: 'releases/v4' },
						{ label: 'v0.3', slug: 'releases/v3' },
					],
				},
				{
					label: 'Developers',
					items: [
						{ label: 'Start here', slug: 'developers/start-here' },
						{ label: 'Why Orifold?', slug: 'developers/why-orifold' },
						{ label: 'Architecture overview', slug: 'developers/architecture' },
						{ label: 'The engines', slug: 'developers/engines' },
						{ label: 'Build from source', slug: 'developers/build' },
						{ label: 'Build & release', slug: 'developers/build-release' },
						{ label: 'Localization guide', slug: 'developers/localization' },
						{ label: 'Testing & the release gate', slug: 'developers/release-gate' },
						{ label: 'Developer FAQ', slug: 'developers/faq' },
						{ label: 'Roadmap & non-goals', slug: 'developers/roadmap' },
						{ label: 'Contributing', slug: 'developers/contributing' },
					],
				},
			],
		}),
	],
});
