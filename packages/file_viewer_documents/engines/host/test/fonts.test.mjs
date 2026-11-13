// SPDX-License-Identifier: MIT
import assert from 'node:assert/strict';
import {after, test} from 'node:test';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {build} from '../../../tooling/node_modules/esbuild/lib/main.js';

const directory = await mkdtemp(resolve(tmpdir(), 'crisp-host-fonts-'));
after(() => rm(directory, {recursive: true, force: true}));
await writeFile(resolve(directory, 'package.json'), '{"type":"module"}\n');
await build({entryPoints: [new URL('../fonts.ts', import.meta.url).pathname], outfile: resolve(directory, 'fonts.js'),
  bundle: true, format: 'esm', platform: 'node', target: 'es2022', logLevel: 'silent'});
const {validateDocumentFonts, collectDocumentFontRequests, createDocumentFonts, fontFamilies} =
  await import(pathToFileURL(resolve(directory, 'fonts.js')).href);
const session = 'abcdefghijklmnopqrstuvwx01234567';
const origin = 'http://127.0.0.1:8123';
const host = `${origin}/${session}/index.html#${session}`;
const face = (family = 'Liberation Sans', weight = 400, italic = false, index = 0) =>
  ({family, aliases: family === 'Liberation Sans' ? ['Arial'] : [], weight, italic,
    url: `${origin}/${session}/fonts/${index}.ttf`});

test('font descriptors accept only the exact native session and Flutter web asset routes', () => {
  assert.deepEqual(validateDocumentFonts([face()], host), [face()]);
  const webHost = 'https://example.test/app/assets/packages/file_viewer_documents/assets/index.html#' + session;
  const web = {...face(), url: 'https://example.test/app/assets/packages/quds_office_editor/fonts/LiberationSans-Regular.ttf'};
  assert.deepEqual(validateDocumentFonts([web], webHost), [web]);
  const values = [
    'https://remote.invalid/font.ttf', `${origin}/${session}/fonts/0.ttf?x=1`,
    `${origin}/${session}/fonts/0.ttf#fragment`, `${origin}/other/fonts/0.ttf`,
    `${origin}/${session}/fonts/%30.ttf`, `${origin}/${session}/fonts/../fonts/0.ttf`,
    `${origin}/${session}/fonts/0.js`, `${origin}/assets/secret.ttf`,
    `${origin}/${session}/fonts/0.ttf\\other`,
  ];
  for (const url of values) assert.throws(() => validateDocumentFonts([{...face(), url}], host), /font|Font/);
  assert.throws(() => validateDocumentFonts([{...web, url: 'https://example.test/app/assets/other/secret.ttf'}], webHost), /asset route/);
  assert.throws(() => validateDocumentFonts([face()], `${origin}/index.html#${session}`), /asset route/);
});

test('font catalog bounds reject excess faces, alias expansions and malformed descriptors', () => {
  for (const changed of [
    {family: ''}, {family: 'a'.repeat(129)}, {family: 'bad\nfont'}, {aliases: Array(17).fill('A')},
    {weight: 450}, {weight: NaN}, {weight: 1000}, {italic: 'false'}, {url: 'data:font/ttf;base64,AAAA'},
  ]) assert.throws(() => validateDocumentFonts([{...face(), ...changed}], host));
  assert.throws(() => validateDocumentFonts(Array(65).fill(face()), host), /catalog/);
  assert.throws(() => validateDocumentFonts([face(), face()], host), /Duplicate/);
  assert.deepEqual(validateDocumentFonts(undefined, host), []);
  assert.equal(validateDocumentFonts([face('خط "document"')], host)[0].family, 'خط "document"');
});

test('model inspection finds named emphasis faces and Arabic without scanning binary payloads', () => {
  const model = {paragraphs: [
    {kind: 'heading', runs: [{text: 'Heading', styles: []}]},
    {runs: [{text: 'body', style: {fontFamily: 'Times New Roman', bold: true, italic: true}}]},
    {runs: [{text: 'العربية', style: {fontFamily: 'Arial', bold: true}}]},
  ], cell: {A1: {style: {font: 'italic bold 12px "Courier New"'}}},
  assets: [{bytes: new Uint8Array(1_000_000)}]};
  const requests = collectDocumentFontRequests(model, 'Liberation Serif');
  assert.ok(requests.some(r => r.family === 'Times New Roman' && r.weight === 700 && r.italic));
  assert.ok(requests.some(r => r.family === 'Liberation Serif' && r.weight === 700));
  assert.ok(requests.some(r => r.family === 'Noto Naskh Arabic' && r.weight === 700));
  assert.ok(requests.some(r => r.family === '"Courier New"' && r.weight === 700 && r.italic));
  assert.deepEqual(fontFamilies('"A, B", Arial, sans-serif'), ['A, B', 'Arial', 'sans-serif']);
  assert.deepEqual(fontFamilies("Bob's Font"), ["Bob's Font"]);
});

function harness(descriptors, options = {}) {
  const added = new Set(), requests = [], warnings = [], controller = new AbortController();
  const previous = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    requests.push({url, init});
    if (options.fetch) return options.fetch(url, init);
    return new Response(Uint8Array.of(0, 1, 0, 0, 10, 20));
  };
  class FontFaceControl {
    constructor(family, bytes, descriptors) { this.family = family; this.bytes = bytes; Object.assign(this, descriptors); }
    async load() { if (options.load) await options.load(); return this; }
  }
  const document = {defaultView: {FontFace: FontFaceControl}, fonts: {add: font => added.add(font), delete: font => added.delete(font)}};
  const fonts = createDocumentFonts(validateDocumentFonts(descriptors, host), document, controller.signal, message => warnings.push(message));
  return {fonts, controller, added, requests, warnings, close() {fonts.dispose(); globalThis.fetch = previous;}};
}

test('loads only requested named styles, reuses bytes and embeds only the selected SVG faces', async () => {
  const h = harness([face(), face('Liberation Sans', 700, true, 1), face('Liberation Serif', 400, false, 2)]);
  try {
    assert.equal(h.requests.length, 0);
    const selected = await h.fonts.prepare([{family: 'Arial', weight: 700, italic: true}], 'Arial');
    assert.equal(h.requests.length, 1);
    assert.ok(h.requests[0].url.endsWith('/1.ttf'));
    assert.equal(h.requests[0].init.redirect, 'error');
    assert.equal([...h.added][0].weight, '700');
    assert.equal([...h.added][0].style, 'italic');
    const svg = selected.embedSvg('<svg xmlns="http://www.w3.org/2000/svg"><text>Hello</text></svg>');
    assert.match(svg, /@font-face/); assert.match(svg, /font-family:"Arial"/); assert.match(svg, /data:font\/ttf;base64/);
    assert.doesNotMatch(svg, /Liberation Serif/);
    await h.fonts.prepare([{family: 'Arial', weight: 700, italic: true}], 'Arial');
    assert.equal(h.requests.length, 1);
    assert.equal(h.added.size, 1);
    h.fonts.dispose(); assert.equal(h.added.size, 0);
  } finally { h.close(); }
});

test('missing families preserve their name and fetch only a configured fallback', async () => {
  const h = harness([face()]);
  try {
    const selected = await h.fonts.prepare([{family: 'Uninstalled Fancy', weight: 400}], 'Arial');
    assert.equal(h.requests.length, 1);
    assert.match(h.warnings.join(' '), /not bundled.*installed font/);
    assert.match(h.fonts.familyCss('Uninstalled Fancy', 'Arial'), /^"Uninstalled Fancy","Arial"/);
    assert.doesNotMatch(selected.embedSvg('<svg></svg>'), /font-family:"Uninstalled Fancy"/);
  } finally { h.close(); }
});

test('Arabic fallback never hides an unknown primary family or its Latin default', async () => {
  const h = harness([face(), face('Noto Naskh Arabic', 400, false, 1)]);
  try {
    const selected = await h.fonts.prepare([{family: 'Unknown Mixed Font', text: 'Hello العربية'}], 'Arial');
    assert.equal(h.requests.length, 2);
    assert.match(h.warnings.join(' '), /Unknown Mixed Font.*not bundled/);
    const svg = selected.embedSvg('<svg/>');
    assert.match(svg, /font-family:"Liberation Sans"/);
    assert.match(svg, /font-family:"Noto Naskh Arabic"/);
  } finally { h.close(); }
});

test('an explicitly requested Arabic face with Latin text also loads its Latin default', async () => {
  const h = harness([face(), face('Noto Naskh Arabic', 400, false, 1)]);
  try {
    const selected = await h.fonts.prepareModel({runs: [{text: 'Hello العربية', style: {fontFamily: 'Noto Naskh Arabic'}}]}, 'Arial');
    assert.equal(h.requests.length, 2, 'aliases reuse the same cached font bytes');
    const svg = selected.embedSvg('<svg/>');
    assert.match(svg, /font-family:"Liberation Sans"/);
    assert.match(svg, /font-family:"Noto Naskh Arabic"/);
    assert.deepEqual(h.warnings, []);
  } finally { h.close(); }
});

test('font asset failure is a visible diagnostic and oversized bodies cannot allocate a face', async () => {
  for (const fetch of [
    async () => new Response('', {status: 404}),
    async () => new Response('', {headers: {'content-length': String(4 * 1024 * 1024 + 1)}}),
    async () => new Response(new Uint8Array(4 * 1024 * 1024 + 1)),
  ]) {
    const h = harness([face()], {fetch});
    try {
      const selected = await h.fonts.prepare([{family: 'Arial'}], 'Arial');
      assert.equal(h.added.size, 0); assert.match(h.warnings.join(' '), /could not load/);
      assert.equal(selected.embedSvg('<svg></svg>'), '<svg></svg>');
    } finally { h.close(); }
  }
});

test('abort settles a pending font decode and cannot register a late face', async () => {
  let finish;
  const h = harness([face()], {load: () => new Promise(resolve => { finish = resolve; })});
  try {
    const pending = h.fonts.prepare([{family: 'Arial'}], 'Arial');
    const rejected = assert.rejects(pending, {name: 'AbortError'});
    while (!finish) await new Promise(resolve => setImmediate(resolve));
    h.controller.abort();
    await rejected; finish(); await new Promise(resolve => setImmediate(resolve));
    assert.equal(h.added.size, 0);
  } finally { h.close(); }
});

test('quoted family names remain CSS and XML text in the standalone SVG', async () => {
  const family = 'Quoted "<tag>$&" Font';
  const h = harness([face(family)]);
  try {
    const selected = await h.fonts.prepare([{family}], family);
    const svg = selected.embedSvg('<svg><text>safe</text></svg>');
    assert.equal((svg.match(/<svg>/g) || []).length, 1);
    assert.match(svg, /&lt;tag&gt;\$&amp;/); assert.doesNotMatch(svg, /<tag>/);
  } finally { h.close(); }
});
