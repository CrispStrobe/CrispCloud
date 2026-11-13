// SPDX-License-Identifier: MIT
import assert from 'node:assert/strict';
import {after, test} from 'node:test';
import {cp, readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {stageEngine, fixture, upstreamRoot} from '../../spreadsheet/test/support.mjs';
import {pptFontPatches, patchPptFontSource} from '../../../tooling/ppt-font-patches.mjs';

const staged = await stageEngine('ppt', {limits: 'limits.ts'});
after(() => staged.close());
const {boundPptRuntime} = await staged.load('limits');
const vendor = resolve(staged.directory, 'ppt-runtime');
await cp(resolve(upstreamRoot, 'apps/viewer-demo/public/vendor/ppt/dist'), vendor, {recursive: true});
for (const patch of pptFontPatches) {
  const path = resolve(vendor, patch.path);
  await writeFile(path, patchPptFontSource(await readFile(path, 'utf8'), patch));
}

test('every pinned PPT font patch requires one exact source match', async () => {
  for (const patch of pptFontPatches) {
    const source = await readFile(resolve(upstreamRoot, 'apps/viewer-demo/public/vendor/ppt/dist', patch.path), 'utf8');
    assert.match(patchPptFontSource(source, patch), /Liberation Sans|transformSvg/);
    assert.throws(() => patchPptFontSource(source.replace(patch.before, ''), patch), /no longer matches exactly/);
    assert.throws(() => patchPptFontSource(source + patch.before, patch), /no longer matches exactly/);
  }
});

test('the real patched runtime invokes the SVG font hook before image decoding', async () => {
  const runtimeModule = await import(pathToFileURL(resolve(vendor, 'runtime.js')).href);
  const {fontCss} = await import(pathToFileURL(resolve(vendor, 'layout/measure.js')).href);
  const {cssFont} = await import(pathToFileURL(resolve(vendor, 'render/safe.js')).href);
  assert.match(fontCss({fontFamily: 'Uninstalled'}), /"Uninstalled","Liberation Sans","Noto Naskh Arabic"/);
  assert.match(cssFont('Uninstalled'), /'Uninstalled', 'Liberation Sans', 'Noto Naskh Arabic'/);
  const runtime = await runtimeModule.createPptViewer({worker: false});
  const bytes = await fixture('apps/viewer-demo/public/example/format-matrix-template.pot',
    '12dfd552e38ffe1a6b8b9d9ec2af83585e5ded679b61cc7c4f1cfa11d8af0282');
  const document = await runtime.open(bytes);
  let hookCalls = 0, draws = 0, blob;
  const createObjectURL = URL.createObjectURL;
  URL.createObjectURL = value => { blob = value; return createObjectURL(value); };
  const context = {measureText: text => ({width: text.length * 10, actualBoundingBoxAscent: 12, actualBoundingBoxDescent: 3}),
    clearRect() {}, drawImage() { draws++; }};
  const owner = {fonts: {ready: Promise.resolve()}, defaultView: {devicePixelRatio: 1}, createElement(name) {
    if (name === 'canvas') return {getContext: () => context};
    if (name === 'img') return {set src(_) { queueMicrotask(() => this.onload()); }};
    throw new Error(`Unexpected element: ${name}`);
  }};
  const canvas = {ownerDocument: owner, width: 1, height: 1, style: {}, dataset: {}, getContext: () => context};
  try {
    await document.renderSlide(0, canvas, {transformSvg: async svg => {
      hookCalls++; assert.match(svg, /^<svg/);
      return svg.replace('<defs>', '<defs><style>/* selected local font bytes */</style>');
    }});
    assert.equal(hookCalls, 1); assert.equal(draws, 1);
    assert.match(await blob.text(), /selected local font bytes/);
    assert.equal(canvas.dataset.renderState, 'rendered');
  } finally { URL.createObjectURL = createObjectURL; await runtime.close(); }
});

function documentControl() {
  const slide = {id: 1, size: {width: 960, height: 720}, masterId: 10, shapes: []};
  const master = {id: 10, shapes: []};
  const other = {id: 20, shapes: []};
  const calls = [];
  const document = {model: {slides: [slide], masters: [master, other]}, closed: false,
    async renderSlide(index, canvas, options) { calls.push({index, canvas, options}); return {source: 'svg'}; },
    async releaseSlide() {return false;}, async close() {this.closed = true;}};
  return {document, slide, master, calls};
}

test('PPT font selection waits per requested slide and includes only its master chain', async () => {
  const control = documentControl();
  const requests = [];
  const fonts = {async prepareModel(model, fallback) {requests.push({model, fallback}); return {embedSvg: svg => svg + ' fonts'};}};
  const runtime = boundPptRuntime({open: async () => control.document}, fonts);
  const document = await runtime.open(new ArrayBuffer(1));
  assert.equal(requests.length, 0);
  await document.renderSlide(0, {width: 1, height: 1, dataset: {}}, {scale: 1.5});
  assert.deepEqual(requests[0], {model: [control.slide, control.master], fallback: 'Arial'});
  assert.equal(control.calls[0].options.scale, 1.5);
  assert.equal(control.calls[0].options.transformSvg('<svg/>'), '<svg/> fonts');
});

test('releasing a slide while its fonts load prevents a late canvas paint', async () => {
  const control = documentControl();
  let finish;
  const fonts = {prepareModel: () => new Promise(resolve => {finish = resolve;})};
  const document = await boundPptRuntime({open: async () => control.document}, fonts).open(new ArrayBuffer(1));
  const canvas = {width: 20, height: 20, dataset: {}};
  const pending = document.renderSlide(0, canvas);
  const rejected = assert.rejects(pending, {name: 'AbortError'});
  assert.equal(await document.releaseSlide(0), true);
  finish({embedSvg: svg => svg}); await rejected;
  assert.equal(control.calls.length, 0); assert.equal(canvas.dataset.renderState, 'released');
  assert.deepEqual([canvas.width, canvas.height], [1, 1]);
});
