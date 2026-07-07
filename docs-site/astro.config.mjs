// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://udhawan97.github.io',
	base: '/Orifold',
	integrations: [
		starlight({
			title: 'Orifold Docs',
			description:
				'Fold chaos into one clean PDF. Free, open-source, 100% local PDF workspace for macOS.',
			logo: {
				src: './public/assets/orifold-app-icon-128.png',
				replacesTitle: false,
			},
			// Crisp vector favicon; PNG/ICO fallbacks + apple-touch, manifest and
			// social-card metadata are added via `head` below. Every icon asset is
			// generated from docs/assets/brand/ by scripts/generate-icons.sh.
			favicon: '/favicon.svg',
			head: [
				{ tag: 'link', attrs: { rel: 'icon', href: '/Orifold/favicon.ico', sizes: '48x48 32x32 16x16' } },
				{ tag: 'link', attrs: { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/Orifold/assets/orifold-app-icon-32.png' } },
				{ tag: 'link', attrs: { rel: 'apple-touch-icon', sizes: '180x180', href: '/Orifold/assets/orifold-app-icon-180.png' } },
				{ tag: 'link', attrs: { rel: 'manifest', href: '/Orifold/site.webmanifest' } },
				{ tag: 'meta', attrs: { name: 'theme-color', content: '#192c48' } },
				{ tag: 'meta', attrs: { property: 'og:image', content: 'https://udhawan97.github.io/Orifold/assets/orifold-og.png' } },
				{ tag: 'meta', attrs: { property: 'og:image:width', content: '1200' } },
				{ tag: 'meta', attrs: { property: 'og:image:height', content: '630' } },
				{ tag: 'meta', attrs: { name: 'twitter:card', content: 'summary_large_image' } },
				{ tag: 'meta', attrs: { name: 'twitter:image', content: 'https://udhawan97.github.io/Orifold/assets/orifold-og.png' } },
			],
			customCss: ['./src/styles/tokens.css', './src/styles/theme.css'],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/udhawan97/Orifold' }],
			editLink: {
				baseUrl: 'https://github.com/udhawan97/Orifold/edit/main/docs-site/',
			},
			components: {
				Footer: './src/components/overrides/Footer.astro',
				Hero: './src/components/overrides/Hero.astro',
				MarkdownContent: './src/components/overrides/MarkdownContent.astro',
				PageTitle: './src/components/overrides/PageTitle.astro',
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
						{ label: 'Night Mode & Document Comfort', slug: 'reading/night-mode' },
						{ label: 'Search inside your workspace', slug: 'reading/search' },
					],
				},
				{
					label: 'Settings & Basics',
					items: [
						{ label: 'Change the app language', slug: 'settings/language' },
						{ label: 'Keyboard shortcuts', slug: 'settings/shortcuts' },
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
						{ label: 'v6', slug: 'releases/v6' },
						{ label: 'v5', slug: 'releases/v5' },
						{ label: 'v4', slug: 'releases/v4' },
						{ label: 'v3', slug: 'releases/v3' },
					],
				},
				{
					label: 'Developers',
					items: [
						{ label: 'Why Orifold?', slug: 'developers/why-orifold' },
						{ label: 'Architecture overview', slug: 'developers/architecture' },
						{ label: 'Build from source', slug: 'developers/build' },
						{ label: 'The engines', slug: 'developers/engines' },
						{ label: 'Localization guide', slug: 'developers/localization' },
						{ label: 'Testing & the release gate', slug: 'developers/release-gate' },
						{ label: 'Contributing', slug: 'developers/contributing' },
					],
				},
			],
		}),
	],
});
