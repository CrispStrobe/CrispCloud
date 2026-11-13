// SPDX-License-Identifier: Apache-2.0
import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { stageEngine, fixture, upstreamRoot, FakeWorker } from '../../spreadsheet/test/support.mjs';

const staged = await stageEngine('ppt', { limits: 'limits.ts', entry: 'entry.ts' });
after(() => staged.close());
const { PPT_LIMITS, PPT_MAX_SLIDE_PIXELS, assertPptSlideBounds, boundPptRuntime } = await staged.load('limits');
const { renderPpt } = await staged.load('entry');
const engine = await import(pathToFileURL(resolve(upstreamRoot, 'apps/viewer-demo/public/vendor/ppt/dist/index.js')).href);

test('PPT entry rejects empty, oversized, cancelled and workerless inputs before DOM work', async () => {
  await assert.rejects(renderPpt(new ArrayBuffer(0), null), /empty/);
  await assert.rejects(renderPpt(new ArrayBuffer(PPT_LIMITS.maxFileBytes + 1), null), /32 MiB/);
  const controller = new AbortController(); controller.abort();
  await assert.rejects(renderPpt(new ArrayBuffer(1), null, { signal: controller.signal }), { name: 'AbortError' });
  await assert.rejects(renderPpt(new ArrayBuffer(1), null), /requires a parsing worker/);
});

test('PPT model canvas limits reject huge, nonfinite and over-count slides before mounting', () => {
  const valid = { slides: [{ size: { width: 960, height: 720 } }] };
  assert.doesNotThrow(() => assertPptSlideBounds(valid));
  for (const [width, height] of [[0, 1], [-1, 2], [Infinity, 10], [4097, 1], [4096, 4096], [NaN, 1]]) {
    assert.throws(() => assertPptSlideBounds({ slides: [{ size: { width, height } }] }), /canvas/);
  }
  assert.ok(4096 * 4096 > PPT_MAX_SLIDE_PIXELS);
  assert.throws(() => assertPptSlideBounds({ slides: Array(201).fill(valid.slides[0]) }), /slide limit/);
});

test('runtime boundary closes rejected documents and preserves valid owned models', async () => {
  let closed = 0;
  const document = { model: { slides: [{ size: { width: 100000, height: 1 } }] }, close: async () => closed++ };
  const runtime = boundPptRuntime({ open: async () => document });
  await assert.rejects(runtime.open(new ArrayBuffer(1)), /canvas/);
  assert.equal(closed, 1);
  document.model.slides[0].size.width = 960;
  assert.equal(await runtime.open(new ArrayBuffer(1)), document);
  assert.equal(closed, 1);
});

test('pinned Apache PPT runtime parses real binary presentation and template fixtures under our limits', async () => {
  const cases = [
    ['apps/viewer-demo/public/example/office-demo.ppt', '636afd24d8bbd04ef771ed7ad4be6226721f951e81f6d2cf5e5d198bcc8bb927'],
    ['apps/viewer-demo/public/example/format-matrix-template.pot', '12dfd552e38ffe1a6b8b9d9ec2af83585e5ded679b61cc7c4f1cfa11d8af0282'],
  ];
  for (const [path, hash] of cases) {
    const bytes = await fixture(path, hash);
    assert.equal(new Uint8Array(bytes)[0], 0xd0);
    const model = engine.parsePpt(bytes, { limits: { ...PPT_LIMITS } });
    assert.ok(model.slides.length > 0, path);
    assertPptSlideBounds(model);
    assert.ok(model.slides.some(slide => slide.shapes.length > 0), path);
  }
});

test('actual PPT parser enforces record and file limits rather than returning a text substitute', async () => {
  const bytes = await fixture('apps/viewer-demo/public/example/format-matrix-template.pot',
    '12dfd552e38ffe1a6b8b9d9ec2af83585e5ded679b61cc7c4f1cfa11d8af0282');
  assert.throws(() => engine.parsePpt(bytes, { limits: { ...PPT_LIMITS, maxFileBytes: 1 } }), /limit/i);
  assert.throws(() => engine.parsePpt(bytes, { limits: { ...PPT_LIMITS, maxRecords: 1 } }), /limit/i);
});

test('actual PPT runtime sends fixed parser limits to its worker and closing cancels a pending parse', async () => {
  const previous = globalThis.Worker;
  const workers = [];
  globalThis.Worker = class extends FakeWorker {
    constructor(url, options) { super(); this.url = url; this.options = options; workers.push(this); }
  };
  let runtime;
  try {
    runtime = await engine.createPptViewer({ worker: true, workerUrl: 'http://127.0.0.1/runtime/pptjs.worker.js', parseOptions: { limits: { ...PPT_LIMITS } } });
    const input = new ArrayBuffer(8);
    const pending = runtime.open(input);
    const rejected = assert.rejects(pending, { name: 'AbortError' });
    assert.equal(workers.length, 1);
    assert.equal(workers[0].options.type, 'module');
    assert.deepEqual(workers[0].sent[0].options.limits, PPT_LIMITS);
    assert.notEqual(workers[0].sent[0].buffer, input);
    await runtime.close();
    await rejected;
    assert.equal(workers[0].terminated, true);
    assert.equal(input.byteLength, 8);
  } finally {
    await runtime?.close();
    if (previous === undefined) delete globalThis.Worker; else globalThis.Worker = previous;
  }
});
