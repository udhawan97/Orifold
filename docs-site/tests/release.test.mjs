import test from 'node:test';
import assert from 'node:assert/strict';
import { getRelease, normalizeTag } from '../src/lib/release.ts';

const release = (assets) => ({ tag_name: 'v0.12.2', published_at: '2026-10-21T12:00:00Z', assets });
const mockRelease = (t, data) => t.mock.method(globalThis, 'fetch', async () => Response.json(data));

test('stable alias survives a later release changing latest', async (t) => {
	mockRelease(t, release([{ name: 'Orifold-0.12.2-macOS-universal.dmg', size: 35000000 }, { name: 'Orifold.dmg', size: 35000000 }]));
	const value = await getRelease();
	assert.equal(value.version, '0.12.2');
	assert.equal(value.downloadUrl, 'https://github.com/udhawan97/Orifold/releases/latest/download/Orifold.dmg');
	assert.equal(value.downloadKind, 'dmg');
	assert.equal(value.dmgSize, '33 MB');
});

test('versioned-only DMG is pinned to its actual tag', async (t) => {
	mockRelease(t, release([{ name: 'Orifold-0.12.2-macOS-universal.dmg' }]));
	assert.equal((await getRelease()).downloadUrl, 'https://github.com/udhawan97/Orifold/releases/download/v0.12.2/Orifold-0.12.2-macOS-universal.dmg');
});

test('ZIP-only release offers ZIP; no-assets release offers release page', async (t) => {
	const mock = mockRelease(t, release([{ name: 'Orifold.zip' }]));
	assert.equal((await getRelease()).downloadKind, 'zip');
	mock.mock.mockImplementation(async () => Response.json(release([])));
	const pending = await getRelease();
	assert.equal(pending.downloadKind, 'release');
	assert.equal(pending.zipAvailable, false);
	assert.equal(pending.downloadUrl, 'https://github.com/udhawan97/Orifold/releases/tag/v0.12.2');
});

test('an asset from a different version cannot masquerade as this release', async (t) => {
	mockRelease(t, release([{ name: 'Orifold-0.11.0-macOS-universal.dmg' }]));
	assert.equal((await getRelease()).downloadKind, 'release');
});

test('offline fallback has useful latest links and no fabricated facts', async (t) => {
	t.mock.method(globalThis, 'fetch', async () => { throw new Error('offline'); });
	const value = await getRelease();
	assert.equal(value.metadataAvailable, false);
	assert.equal(value.version, null);
	assert.equal(value.tag, null);
	assert.equal(value.publishedAt, null);
	assert.equal(value.dmgSize, null);
	assert.equal(value.releaseUrl, 'https://github.com/udhawan97/Orifold/releases/latest');
	assert.match(value.downloadUrl, /latest\/download\/Orifold\.dmg$/);
});

test('API failure or unexpected prerelease uses honest fallback', async (t) => {
	const mock = t.mock.method(globalThis, 'fetch', async () => new Response('', { status: 403 }));
	assert.equal((await getRelease()).version, null);
	mock.mock.mockImplementation(async () => Response.json({ ...release([]), prerelease: true }));
	assert.equal((await getRelease()).metadataAvailable, false);
	assert.equal(normalizeTag('release-v0.12.2'), '0.12.2');
});
