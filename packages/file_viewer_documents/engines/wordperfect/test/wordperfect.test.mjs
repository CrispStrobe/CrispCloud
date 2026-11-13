// SPDX-License-Identifier: Apache-2.0
import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { exactArrayBuffer, FakeWorker, fixtureBytes, stageEngine, upstreamRoot, withFakeWorkers } from './support.mjs';

const staged = await stageEngine('wordperfect', ['libwpd', 'parser', 'workerClient', 'wordperfect']);
after(() => staged.close());
const { decodeStructuredDocument, parseWordPerfectWithLibWpd } = await staged.load('libwpd');
const { MAX_WORDPERFECT_INPUT_BYTES, assertWordPerfectInput } = await staged.load('parser');
const { parseWordPerfectWithWorker } = await staged.load('workerClient');

const u32 = value => [value & 255, (value >>> 8) & 255, (value >>> 16) & 255, (value >>> 24) & 255];
const string = value => { const bytes = new TextEncoder().encode(value); return [...u32(bytes.length), ...bytes]; };
const text = value => [0, ...string(value)];
const wire = (events, metadata = []) => Uint8Array.from([1, ...u32(metadata.length), ...metadata.flatMap(([key, value]) => [...string(key), ...string(value)]), ...u32(events.length), ...events.flat()]);
const source = Uint8Array.of(255, 87, 80, 67, 16, 0, 0, 0, 0, 0, 2, 0, 0);
const table = value => [[20], [21, 0], [22, ...u32(0), ...u32(1), ...u32(1)], text(value), [4], [24], [25], [26]];

test('keeps paragraphs and tables interleaved in their source order', () => {
  const document = decodeStructuredDocument(wire([text('before'), [4], ...table('cell'), text('after'), [4]]), source);
  assert.deepEqual(document.blocks.map(block => block.kind), ['paragraph', 'table', 'paragraph']);
  assert.deepEqual(document.paragraphs, ['before', 'after']);
  assert.equal(document.blocks[1].table.rows[0][0].text, 'cell');
  assert.equal(document.engine, 'libwpd-wasm');
  assert.match(document.warnings.join(' '), /page layout.*images.*equations/);
});

test('keeps a body paragraph, link and style across an embedded note', () => {
  const document = decodeStructuredDocument(wire([
    [8], [35, ...string('https://example.invalid/report')], text('before '),
    [31, 0], text('a note'), [4], [32], text('after'), [36], [9], [4],
  ]), source);
  assert.deepEqual(document.paragraphs, ['before after']);
  assert.equal(document.notes[0].runs[0].text, 'a note');
  assert.equal(document.blocks[0].paragraph.runs[1].href, 'https://example.invalid/report');
  assert.deepEqual(document.blocks[0].paragraph.runs[1].styles, ['bold']);
});

test('preserves table placement inside headers and separates footer/notes', () => {
  const document = decodeStructuredDocument(wire([
    [27], text('heading'), [4], ...table('header cell'), [28],
    text('body'), [4], [29], text('footer'), [4], [30],
  ]), source);
  assert.deepEqual(document.headerBlocks.map(block => block.kind), ['paragraph', 'table']);
  assert.deepEqual(document.paragraphs, ['body']);
  assert.equal(document.footerBlocks[0].paragraph.runs[0].text, 'footer');
  assert.equal(document.tables.length, 0);
});

test('honors Uint8Array subview offsets and stores metadata without a prototype', () => {
  const bytes = wire([text('<script>literal text</script>'), [4]], [['__proto__', 'literal metadata']]);
  const wrapped = new Uint8Array(bytes.length + 9); wrapped.set(bytes, 7);
  const document = decodeStructuredDocument(wrapped.subarray(7, 7 + bytes.length), source);
  assert.equal(document.paragraphs[0], '<script>literal text</script>');
  assert.equal(Object.getPrototypeOf(document.metadata), null);
  assert.equal(document.metadata.__proto__, 'literal metadata');
});

test('rejects truncated, unknown and unbalanced event streams', () => {
  const valid = wire([text('document'), [4]]);
  for (const length of [0, 1, 4, valid.length - 1]) {
    assert.throws(() => decodeStructuredDocument(valid.subarray(0, length), source), /Truncated|truncated/);
  }
  for (const events of [[[255]], [[24]], [[20]], [[28]], [[5, 2, 0, ...u32(1)]]]) {
    assert.throws(() => decodeStructuredDocument(wire(events), source), /Unknown|Unbalanced|Unclosed|boolean/);
  }
  assert.throws(() => decodeStructuredDocument(Uint8Array.from([...valid, 0]), source), /trailing/);
});

test('rejects excessive event, string, metadata, table and rendered-block expansion', () => {
  assert.throws(() => decodeStructuredDocument(Uint8Array.from([1, ...u32(0), ...u32(200_001)]), source), /event count/);
  assert.throws(() => decodeStructuredDocument(Uint8Array.from([1, ...u32(1_001)]), source), /metadata/);
  assert.throws(() => decodeStructuredDocument(wire([[0, ...u32(8 * 1024 * 1024 + 1)]]), source), /text exceeds/);
  assert.throws(() => decodeStructuredDocument(wire([[20], [21, 0], [22, ...u32(0), ...u32(1001), ...u32(1)]]), source), /span/);
  assert.throws(() => decodeStructuredDocument(wire([[20], [20]]), source), /Nested/);
  const events = Array.from({ length: 20_001 }, () => [text('p'), [4]]).flat();
  assert.throws(() => decodeStructuredDocument(wire(events), source), /block count/);
});

test('applies the source cap before copying, importing modules or starting a worker', async () => {
  const oversized = new ArrayBuffer(MAX_WORDPERFECT_INPUT_BYTES + 1);
  oversized.slice = () => { throw new Error('Unexpected copy'); };
  assert.throws(() => assertWordPerfectInput(new ArrayBuffer(0)), /empty/);
  await assert.rejects(parseWordPerfectWithLibWpd(oversized, 'unresolvable-module', 'missing.wasm'), /64 MiB/);
  await withFakeWorkers(async () => {
    await assert.rejects(parseWordPerfectWithWorker(oversized), /64 MiB/);
    assert.equal(FakeWorker.instances.length, 0);
  });
});

test('requires the real engine when workers are disabled or parsing fails', async () => {
  await withFakeWorkers(async () => {
    await assert.rejects(parseWordPerfectWithWorker(source.buffer, { useWorker: false }), /requires a Web Worker/);
    assert.equal(FakeWorker.instances.length, 0);
    FakeWorker.behavior = (worker, request) => queueMicrotask(() => worker.respond({ id: request.id, ok: false, error: 'Corrupt WordPerfect file' }));
    await assert.rejects(parseWordPerfectWithWorker(source.buffer), /Corrupt WordPerfect/);
    assert.ok(FakeWorker.instances[0].terminated);
  });
});

test('terminates failed or aborted workers and rejects remote runtime URLs', async () => {
  await withFakeWorkers(async () => {
    const aborted = new AbortController(); aborted.abort();
    await assert.rejects(parseWordPerfectWithWorker(source.buffer, undefined, aborted.signal), { name: 'AbortError' });
    await assert.rejects(parseWordPerfectWithWorker(source.buffer, { workerUrl: 'https://remote.invalid/worker.js' }), /local viewer origin/);
    assert.equal(FakeWorker.instances.length, 0);
    const controller = new AbortController();
    const pending = parseWordPerfectWithWorker(source.buffer, undefined, controller.signal);
    controller.abort();
    await assert.rejects(pending, { name: 'AbortError' });
    assert.ok(FakeWorker.instances.at(-1).terminated);
    FakeWorker.behavior = () => { throw new Error('Transfer failed'); };
    await assert.rejects(parseWordPerfectWithWorker(source.buffer), /Transfer failed/);
    assert.ok(FakeWorker.instances.at(-1).terminated);
  });
});

test('parses licensed real WP 4.2, 5.0, 5.1 and 6.x files with the pinned WASM engine', async () => {
  await fixtureBytes('wordperfect', 'vendor/libwpd.mjs', 'ccd3267ce9cac2961bb6a500761753efa05c93563e7a5e46a31594cceb5e3096');
  const wasm = await fixtureBytes('wordperfect', 'vendor/libwpd.wasm', 'bbfe0c7f712a357e3f9d11f9cf96d931e7cf4b9165d4379af78bf1bcb69333f0');
  const moduleUrl = pathToFileURL(resolve(upstreamRoot, 'packages/renderers/wordperfect/vendor/libwpd.mjs')).href;
  const cases = [
    ['wp42.wp', '5209024eff85ad86d7405503cabe4682e0d36ce2cc20d5cd40f5165e52199927', 'Dit is een test'],
    ['wp50.wp', '4cb383585f11af90a2f1c3f8e8f0244020e2008224effce981446577234273c1', 'President'],
    ['wp51.wp', 'c5b3c18d2c1ba2c99c2fbb1aababcbee15b744f2539605927e589c3c7eeb6bdc', 'Western Gulf of Alaska'],
    ['wp6.wpd', '45ec5771e60fc55c07f398ddec80e9463f3cd7b80bfadacf93743dcfcef866e7', 'APPENDIX'],
    ['corel_wp6.wpd', '3417815c24d7227a1dd3fc5b95cb3e84f895a1e608a58432cb5ffcaebb4cae90', 'Ruimtelijke interpolatie'],
  ];
  for (const [name, hash, expected] of cases) {
    const bytes = await fixtureBytes('wordperfect', `test/fixtures/${name}`, hash);
    const document = await parseWordPerfectWithLibWpd(exactArrayBuffer(bytes), moduleUrl, 'unused.wasm', wasm);
    assert.equal(document.engine, 'libwpd-wasm', name);
    assert.ok(document.paragraphs.join(' ').includes(expected), name);
    assert.ok(document.warnings.length > 0, name);
    if (name === 'corel_wp6.wpd') {
      assert.deepEqual(document.tables.map(item => item.rows.length), [4, 9, 14]);
      assert.equal(document.footers.length, 1); assert.equal(document.notes.length, 1);
      const kinds = document.blocks.map(block => block.kind === 'table' ? 'T' : 'P').join('');
      assert.match(kinds, /TPT/); assert.ok(kinds.endsWith('TPPPP'));
      const styles = new Set(document.structuredParagraphs.flatMap(paragraph => paragraph.runs.flatMap(run => run.styles)));
      for (const style of ['bold', 'italic', 'superscript']) assert.ok(styles.has(style), style);
    }
  }
  await assert.rejects(parseWordPerfectWithLibWpd(Uint8Array.of(1, 2, 3, 4).buffer, moduleUrl, 'unused.wasm', wasm), /does not recognize/);
});
