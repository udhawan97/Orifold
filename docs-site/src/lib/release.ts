/** Build-time release facts. Offline builds keep usable links without inventing a version. */
import site from '../data/site.json' with { type: 'json' };

export interface ReleaseInfo {
	version: string | null;
	tag: string | null;
	publishedAt: string | null;
	dmgUrl: string;
	dmgSize: string | null;
	zipUrl: string;
	releaseUrl: string;
	allReleasesUrl: string;
	downloadUrl: string;
	downloadKind: 'dmg' | 'zip' | 'release';
	metadataAvailable: boolean;
	zipAvailable: boolean;
}

const releases = 'https://github.com/' + site.repo + '/releases';
const stableUrl = (asset: string) => releases + '/latest/download/' + asset;
const taggedUrl = (tag: string, asset: string) => releases + '/download/' + encodeURIComponent(tag) + '/' + encodeURIComponent(asset);

export function normalizeTag(tag: string): string {
	return tag.replace(/^release-/, '').replace(/^v/, '');
}

function fallback(): ReleaseInfo {
	return {
		version: null, tag: null, publishedAt: null,
		dmgUrl: stableUrl(site.dmgAsset), dmgSize: null,
		zipUrl: stableUrl(site.zipAsset), releaseUrl: releases + '/latest',
		allReleasesUrl: releases, downloadUrl: stableUrl(site.dmgAsset),
		downloadKind: 'dmg', metadataAvailable: false, zipAvailable: true,
	};
}

/** Prefer stable aliases; pin a versioned-only asset to its actual release tag. */
export async function getRelease(): Promise<ReleaseInfo> {
	const headers: Record<string, string> = {
		Accept: 'application/vnd.github+json', 'User-Agent': 'orifold-docs-site-build',
	};
	if (process.env.GITHUB_TOKEN) headers.Authorization = 'Bearer ' + process.env.GITHUB_TOKEN;
	try {
		const response = await fetch('https://api.github.com/repos/' + site.repo + '/releases/latest', {
			headers, signal: AbortSignal.timeout(8000),
		});
		if (!response.ok) return fallback();
		const data = await response.json();
		if (typeof data.tag_name !== 'string' || !/^\d+\.\d+\.\d+$/.test(normalizeTag(data.tag_name))
			|| data.draft || data.prerelease) return fallback();
		const tag = data.tag_name;
		const assets: { name: string; size?: number }[] = Array.isArray(data.assets) ? data.assets : [];
		const alias = assets.find((asset) => asset?.name === site.dmgAsset);
		const versioned = assets.find((asset) => asset?.name === 'Orifold-' + normalizeTag(tag) + '-macOS-universal.dmg');
		const dmg = alias ?? versioned;
		const zip = assets.find((asset) => asset?.name === site.zipAsset);
		const releaseUrl = releases + '/tag/' + encodeURIComponent(tag);
		const dmgUrl = alias ? stableUrl(site.dmgAsset) : dmg ? taggedUrl(tag, dmg.name) : stableUrl(site.dmgAsset);
		const zipUrl = stableUrl(site.zipAsset);
		const bytes = dmg?.size;
		return {
			version: normalizeTag(tag), tag,
			publishedAt: typeof data.published_at === 'string' ? data.published_at : null,
			dmgUrl, dmgSize: typeof bytes === 'number' && bytes > 0 ? Math.round(bytes / 1024 / 1024) + ' MB' : null,
			zipUrl, releaseUrl, allReleasesUrl: releases,
			downloadUrl: dmg ? dmgUrl : zip ? zipUrl : releaseUrl,
			downloadKind: dmg ? 'dmg' : zip ? 'zip' : 'release', metadataAvailable: true, zipAvailable: Boolean(zip),
		};
	} catch {
		return fallback();
	}
}
