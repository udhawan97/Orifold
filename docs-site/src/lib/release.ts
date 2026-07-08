/**
 * Build-time GitHub release metadata — the canonical, no-JS source of truth for
 * the landing page's version chip, download button, and footer.
 *
 * Runs once during `astro build`. Never hardcode a version in copy; read it from
 * here. A tiny runtime enhancer (see the landing page) may later refresh these
 * values in the browser, but it is only ever allowed to *confirm or upgrade* —
 * the values baked here are always a correct, shippable fallback.
 *
 * Fallback ladder (see WEBSITE_PLAN.md §5.5):
 *   1. dmg asset present on latest release  → real url + size, dmg button.
 *   2. latest release exists but no dmg yet  → zip button + `dmgMissing` warning
 *      (this is today's reality: releases are zip-only until the PR-1 pipeline
 *      ships Orifold.dmg). The stable dmg URL is still returned optimistically.
 *   3. API unreachable / rate-limited         → LAST_KNOWN_GOOD fallback values.
 */

import site from '../data/site.json';

export interface ReleaseAsset {
	name: string;
	url: string;
	size: number | null;
}

export interface ReleaseInfo {
	/** Display version, `v`/`release-` stripped, e.g. "0.8.1". */
	version: string;
	/** Raw tag as published, e.g. "release-v0.8.1". */
	tag: string;
	/** ISO date the release was published, or null. */
	publishedAt: string | null;
	/** Stable, never-changing download URL for the dmg. Always safe to link. */
	dmgUrl: string;
	/** Human-readable dmg size ("14 MB") if known from the API, else null. */
	dmgSize: string | null;
	/** True when the latest release has no dmg asset yet (zip-only era). */
	dmgMissing: boolean;
	/** Stable zip URL — one-line installer / cask reference / manual fallback. */
	zipUrl: string;
	/** URL of the release page itself. */
	releaseUrl: string;
	/** URL that always lists every release. */
	allReleasesUrl: string;
}

/** Bump this whenever a release ships, so the offline build stays truthful. */
const LAST_KNOWN_GOOD = {
	tag: 'release-v0.8.1',
	version: '0.8.1',
	publishedAt: '2026-07-07T15:45:52Z',
} as const;

const REPO = site.repo;
const DMG = site.dmgAsset;
const ZIP = site.zipAsset;

const stableUrl = (asset: string) => `https://github.com/${REPO}/releases/latest/download/${asset}`;

/** Strip a `release-`/`v` prefix and return the dotted version. */
export function normalizeTag(tag: string): string {
	return tag.replace(/^release-/, '').replace(/^v/, '');
}

function humanSize(bytes: number | null): string | null {
	if (!bytes || bytes <= 0) return null;
	const mb = bytes / (1024 * 1024);
	return `${mb < 10 ? mb.toFixed(1) : Math.round(mb)} MB`;
}

function fallback(reason: string): ReleaseInfo {
	if (reason) console.warn(`[release.ts] ${reason} — using LAST_KNOWN_GOOD (${LAST_KNOWN_GOOD.tag}).`);
	return {
		version: LAST_KNOWN_GOOD.version,
		tag: LAST_KNOWN_GOOD.tag,
		publishedAt: LAST_KNOWN_GOOD.publishedAt,
		dmgUrl: stableUrl(DMG),
		dmgSize: null,
		dmgMissing: true,
		zipUrl: stableUrl(ZIP),
		releaseUrl: `https://github.com/${REPO}/releases/tag/${LAST_KNOWN_GOOD.tag}`,
		allReleasesUrl: `https://github.com/${REPO}/releases`,
	};
}

/**
 * Fetch the latest non-prerelease, non-draft release at build time.
 * `releases/latest` already excludes prereleases (so the rolling `Orifold-latest`
 * dev channel can never hijack it — see WEBSITE_PLAN.md §5.1).
 */
export async function getRelease(): Promise<ReleaseInfo> {
	const token = process.env.GITHUB_TOKEN;
	const headers: Record<string, string> = {
		Accept: 'application/vnd.github+json',
		'User-Agent': 'orifold-docs-site-build',
	};
	if (token) headers.Authorization = `Bearer ${token}`;

	let data: any;
	try {
		const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers });
		if (!res.ok) return fallback(`releases/latest returned ${res.status}`);
		data = await res.json();
	} catch (err) {
		return fallback(`fetch failed (${err instanceof Error ? err.message : 'unknown'})`);
	}

	const tag: string = data.tag_name ?? LAST_KNOWN_GOOD.tag;
	const assets: any[] = Array.isArray(data.assets) ? data.assets : [];
	const dmg = assets.find((a) => a.name === DMG);

	return {
		version: normalizeTag(tag),
		tag,
		publishedAt: data.published_at ?? null,
		dmgUrl: stableUrl(DMG),
		dmgSize: humanSize(dmg?.size ?? null),
		dmgMissing: !dmg,
		zipUrl: stableUrl(ZIP),
		releaseUrl: data.html_url ?? `https://github.com/${REPO}/releases/tag/${tag}`,
		allReleasesUrl: `https://github.com/${REPO}/releases`,
	};
}
