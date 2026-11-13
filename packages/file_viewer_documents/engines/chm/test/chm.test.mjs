// SPDX-License-Identifier: Apache-2.0
import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { runInNewContext } from 'node:vm';
import { FakeWorker, fixtureBytes, stageEngine, upstreamRoot, withFakeWorkers } from '../../wordperfect/test/support.mjs';

const staged = await stageEngine('chm', ['entry', 'model', 'workerClient', 'security', 'links']);
after(() => staged.close());
const { normalizeChmManifest, resolveChmOptions, CHM_HARD_LIMITS } = await staged.load('model');
const { renderChm } = await staged.load('entry');
const { ChmWorkerClient } = await staged.load('workerClient');
const { normalizeChmPath, resolveChmReference, sanitizeChmCss, assertChmSvgSourceSafety } = await staged.load('security');
const { findChmTopicLink } = await staged.load('links');

test('accepts topic link elements from another realm and ignores non-elements', () => {
  // A VM-created element shape exercises the cross-realm identity boundary;
  // the separate Chromium smoke checks real iframe clicks end to end.
  const target = runInNewContext(`new (class Element {
    nodeType = 1;
    closest(selector) { return selector === 'a[data-chm-link-kind],area[data-chm-link-kind]' ? { dataset: { chmLinkKind: 'internal', chmPath: '/guide/setup.html' } } : null; }
  })()`);
  assert.equal(target instanceof Object, false);
  assert.equal(findChmTopicLink(target).dataset.chmPath, '/guide/setup.html');
  assert.equal(findChmTopicLink(null), null);
  assert.equal(findChmTopicLink({ nodeType: 3 }), null);
  assert.equal(findChmTopicLink({ nodeType: 1 }), null);
});

test('clamps caller limits and preserves stricter requested ceilings', () => {
  const elevated = resolveChmOptions({
    maxArchiveBytes: 2 ** 40, maxEntries: 1e8, maxEntryBytes: 2 ** 40,
    maxTotalDecompressedBytes: 2 ** 40, maxHtmlBytes: 2 ** 40,
    workerTimeoutMs: 2 ** 40, maxSearchTopics: 1e8, maxSearchResults: 1e8,
  });
  for (const [key, maximum] of Object.entries(CHM_HARD_LIMITS)) assert.equal(elevated[key], maximum, key);
  assert.equal(elevated.workerTimeoutMs, 60_000);
  assert.equal(elevated.maxSearchTopics, 2_000); assert.equal(elevated.maxSearchResults, 200);
  assert.equal(resolveChmOptions({ maxArchiveBytes: 1234.5 }).maxArchiveBytes, 1234);
  assert.equal(resolveChmOptions({ maxArchiveBytes: NaN }).maxArchiveBytes, 64 * 1024 * 1024);
  assert.equal(resolveChmOptions({ maxEntries: 0 }).maxEntries, 1);
});

test('preserves parser warnings and merged-help requirements without accepting arbitrary objects', () => {
  const manifest = normalizeChmManifest({
    warnings: ['Missing binary TOC', {}, '<script>literal warning</script>'],
    mergedArchives: ['extra.chm', 1],
  });
  assert.deepEqual(manifest.warnings, ['Missing binary TOC', '<script>literal warning</script>']);
  assert.deepEqual(manifest.mergedArchives, ['extra.chm']);
  assert.deepEqual(normalizeChmManifest({}).warnings, []);
  assert.deepEqual(normalizeChmManifest({ merged_archives: ['legacy.chm'] }).mergedArchives, ['legacy.chm']);
  const long = normalizeChmManifest({ warnings: Array(1000).fill('x'.repeat(3000)) });
  assert.equal(long.warnings.length, 100); assert.equal(long.warnings[0].length, 2048);
});

test('rejects over-limit or empty source before creating DOM or workers', async () => {
  await assert.rejects(renderChm(new ArrayBuffer(0), null), /empty/);
  await assert.rejects(renderChm(new ArrayBuffer(64 * 1024 * 1024 + 1), null), /preview limit/);
  await assert.rejects(renderChm(new ArrayBuffer(10), null, { options: { chm: { maxArchiveBytes: 9 } } }), /preview limit/);
  const controller = new AbortController(); controller.abort();
  await assert.rejects(renderChm(new ArrayBuffer(1), null, { signal: controller.signal }), { name: 'AbortError' });
});

test('keeps archive paths inside the CHM and classifies active/external URLs', () => {
  for (const path of ['../../outside', '/%2e%2e/outside', 'C:\\secret', '//server/share', '/null\0path']) {
    assert.equal(normalizeChmPath(path), null, path);
  }
  assert.equal(normalizeChmPath('/guide/../index.html'), '/index.html');
  assert.equal(resolveChmReference('/guide/topic.html', '../index.html').path, '/index.html');
  assert.equal(resolveChmReference('/index.html', 'javascript:alert(1)').kind, 'blocked');
  assert.equal(resolveChmReference('/index.html', 'data:text/html,<script>1</script>').kind, 'blocked');
  assert.equal(resolveChmReference('/index.html', 'https://example.invalid/image.png').kind, 'external');
});

test('retains upstream CSS and SVG resource protections', () => {
  const sanitized = sanitizeChmCss('body{background:url(https://remote.invalid/image.png);color:red;behavior:url(evil.htc)} .ok{background:url(../images/icon.png)}', '/styles/main.css');
  assert.ok(!sanitized.css.includes('https://remote.invalid'));
  assert.ok(!sanitized.css.includes('behavior:'));
  assert.deepEqual(sanitized.resourcePaths, ['/images/icon.png']);
  assert.throws(() => assertChmSvgSourceSafety('<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///secret">]><svg/>'), /SVG|DOCTYPE|entity|Entity/);
});

test('requires local worker/module/WASM assets', async () => {
  await withFakeWorkers(async () => {
    for (const key of ['workerUrl', 'wasmModuleUrl', 'wasmUrl']) {
      assert.throws(() => new ChmWorkerClient({ [key]: 'https://remote.invalid/runtime' }), /local viewer origin/);
    }
    assert.equal(FakeWorker.instances.length, 0);
  });
});

test('checks source bounds before transfer and passes the bounded limits to the worker', async () => {
  await withFakeWorkers(async () => {
    const client = new ChmWorkerClient({ maxArchiveBytes: 4 });
    try {
      const oversized = new ArrayBuffer(5);
      oversized.slice = () => { throw new Error('Unexpected copy'); };
      await assert.rejects(client.open(oversized), /CHM_LIMIT_EXCEEDED/);
      assert.equal(FakeWorker.instances[0].sent.length, 0);
      FakeWorker.behavior = (worker, request) => queueMicrotask(() => worker.respond({ id: request.id, ok: true, type: 'open', manifest: normalizeChmManifest({}), entries: [] }));
      await client.open(new ArrayBuffer(4));
      const { message, transfers } = FakeWorker.instances[0].sent[0];
      assert.equal(message.limits.maxArchiveBytes, 4);
      assert.equal(message.limits.maxTotalDecompressedBytes, 128 * 1024 * 1024);
      assert.equal(transfers.length, 1);
    } finally { client.destroy(); }
  });
});

test('terminates the archive worker on cancellation or transfer failure', async () => {
  await withFakeWorkers(async () => {
    const client = new ChmWorkerClient();
    const controller = new AbortController();
    const pending = client.open(new ArrayBuffer(4), controller.signal);
    controller.abort();
    await assert.rejects(pending, { name: 'AbortError' });
    assert.ok(FakeWorker.instances[0].terminated);
    await assert.rejects(client.open(new ArrayBuffer(4)), /CHM_WORKER_CLOSED/);
    const broken = new ChmWorkerClient();
    FakeWorker.behavior = () => { throw new Error('Transfer failed'); };
    await assert.rejects(broken.open(new ArrayBuffer(4)), /Transfer failed/);
    assert.ok(FakeWorker.instances[1].terminated);
  });
});

test('reads real LZX-compressed topics, navigation and resources using the pinned CHM WASM', async () => {
  await fixtureBytes('chm', 'src/wasm/chm_wasm.js', 'e7f1a6e0de035e7178c04a0307f52806997c9971a948e333e66a49fbe73a3d5c');
  const wasm = await fixtureBytes('chm', 'src/wasm/chm_wasm_bg.wasm', '02904a83ae8be928d5c90b9fd61faf28d8ba7e67ee96e3aeeb5d5b5102691538');
  const bytes = await fixtureBytes('chm', 'rust/tests/fixtures/complete.chm', 'bafdb0dc7e499630ed02751843f6401c5f718341ac3a97aed2deee234e25c35d');
  const module = await import(pathToFileURL(resolve(upstreamRoot, 'packages/renderers/chm/src/wasm/chm_wasm.js')).href);
  await module.default({ module_or_path: wasm });
  const options = resolveChmOptions();
  const limits = { ...options, maxMetadataBytes: options.maxHtmlBytes, maxSitemapNodes: options.maxEntries, maxSitemapDepth: 256 };
  const archive = new module.ChmArchive(new Uint8Array(bytes), limits);
  try {
    const raw = archive.manifest();
    assert.equal(raw.compressed, true);
    const manifest = normalizeChmManifest(raw);
    assert.equal(manifest.title, 'File Viewer CHM Fixture');
    assert.equal(manifest.homePath, '/index.html');
    assert.equal(manifest.topics.length, 2);
    assert.equal(manifest.contents[0].title, 'Welcome');
    assert.equal(manifest.contents[0].children[0].title, 'Setup');
    assert.ok(manifest.hasBinaryToc && manifest.hasBinaryIndex && manifest.hasFullTextIndex);
    assert.ok(manifest.index.some(item => item.title === 'offline'));
    assert.match(new TextDecoder().decode(archive.read('/index.html')), /Offline CHM preview/);
    assert.match(new TextDecoder().decode(archive.read('/guide/setup.html')), /Setup/);
    assert.match(new TextDecoder().decode(archive.read('/styles/site.css')), /#123456/);
    assert.throws(() => archive.read('/../../outside'), /CHM_|path|entry/i);
  } finally { archive.dispose(); archive.free(); }
  assert.throws(() => new module.ChmArchive(new Uint8Array(bytes), { ...limits, maxArchiveBytes: bytes.length - 1 }), /CHM_LIMIT|limit/i);
  for (const cut of [0, 3, 63]) assert.throws(() => new module.ChmArchive(new Uint8Array(bytes.subarray(0, cut)), limits), /CHM_|header|truncated/i);
});
