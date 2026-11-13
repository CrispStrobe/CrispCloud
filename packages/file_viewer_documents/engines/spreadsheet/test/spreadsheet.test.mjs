// SPDX-License-Identifier: Apache-2.0
import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { stageEngine, requireDependency, fixture, FakeWorker, exactArrayBuffer } from './support.mjs';

const staged = await stageEngine('spreadsheet', {
  limits: 'limits.ts', zip: 'zipPreflight.ts', worker: 'boundedWorker.ts',
  parser: 'spreadsheet/worker/sheetjs/parser.ts', entry: 'entry.ts',
});
after(() => staged.close());
const limits = await staged.load('limits');
const { preflightSpreadsheetZip } = await staged.load('zip');
const { BoundedSpreadsheetWorker } = await staged.load('worker');
const parser = await staged.load('parser');
const { renderSpreadsheet } = await staged.load('entry');
const sheetjs = requireDependency('styled-exceljs');
const JSZip = requireDependency('jszip');
const book = sheet => ({ SheetNames: ['Data'], Sheets: { Data: sheet } });

async function makeWorkbook(bookType = 'xlsb') {
  const workbook = sheetjs.utils.book_new();
  sheetjs.utils.book_append_sheet(workbook, sheetjs.utils.aoa_to_sheet([
    ['Name', 'Count'], ['CrispCloud Ω', 42], ['<script>literal</script>', 7],
  ]), 'Values');
  return exactArrayBuffer(sheetjs.write(workbook, { type: 'buffer', bookType }));
}

test('rejects empty, oversized, cancelled and workerless entry requests before DOM work', async () => {
  await assert.rejects(renderSpreadsheet(new ArrayBuffer(0), null), /empty/);
  await assert.rejects(renderSpreadsheet(new ArrayBuffer(limits.SPREADSHEET_LIMITS.maxFileBytes + 1), null), /32 MiB/);
  const controller = new AbortController(); controller.abort();
  await assert.rejects(renderSpreadsheet(new ArrayBuffer(1), null, { signal: controller.signal }), { name: 'AbortError' });
  await assert.rejects(renderSpreadsheet(new ArrayBuffer(1), null), /requires a parsing worker/);
});

test('accepts actual BIFF8 and XLSB generated containers without losing Unicode or literal markup', async () => {
  for (const bookType of ['biff8', 'xlsb']) {
    const bytes = await makeWorkbook(bookType);
    assert.equal(new Uint8Array(bytes)[0], bookType === 'biff8' ? 0xd0 : 0x50);
    const context = parser.createSpreadsheetParserContext();
    const responses = await parser.parseSpreadsheetWorkbook(context, bytes, { filename: `sample.${bookType === 'biff8' ? 'xls' : 'xlsb'}` });
    assert.equal(responses[0].type, 'sheets', JSON.stringify(responses));
    const sheet = context.workbook.Sheets.Values;
    const rows = Array.isArray(sheet) ? sheet : sheet['!data'];
    assert.equal(rows[1][0].v, 'CrispCloud Ω');
    assert.equal(rows[1][1].v, 42);
    assert.equal(rows[2][0].v, '<script>literal</script>');
    const window = parser.parseSpreadsheetSheet(context, { sheet: 0, startRow: 0, pageSize: 500, sessionId: 7 });
    assert.equal(window[0].type, 'parseSheet');
    assert.equal(window[0].payload.sessionId, 7);
  }
});

test('opens the genuine upstream binary XLS embedded-image regression fixture', async () => {
  const bytes = await fixture('packages/renderers/spreadsheet/test/fixtures/github-178-embedded-image.xls',
    'bc5d4542e16382a4a79b639b744f767c7cd5c420b5d5a3c42f132cb51c62eb20');
  assert.equal(new Uint8Array(bytes)[0], 0xd0);
  const context = parser.createSpreadsheetParserContext();
  const responses = await parser.parseSpreadsheetWorkbook(context, bytes, { filename: 'image.xls' });
  assert.equal(responses[0].type, 'sheets', JSON.stringify(responses));
  assert.ok(context.sheets.length > 0);
  const sheet = context.workbook.Sheets[context.workbook.SheetNames[0]];
  assert.ok(sheet['!drawings']?.images?.length > 0);
});

test('ZIP preflight accepts stored and deflated data and rejects malformed/truncated directories', async () => {
  for (const compression of ['STORE', 'DEFLATE']) {
    const zip = new JSZip(); zip.file('sheet.xml', '<sheet>Ω</sheet>');
    const bytes = await zip.generateAsync({ type: 'arraybuffer', compression });
    assert.doesNotThrow(() => preflightSpreadsheetZip(bytes));
    assert.throws(() => preflightSpreadsheetZip(bytes.slice(0, -1)), /ZIP/);
  }
  assert.doesNotThrow(() => preflightSpreadsheetZip(new Uint8Array([0xd0, 0xcf]).buffer));
});

test('ZIP preflight checks actual inflated bytes even when central-directory lengths lie', async () => {
  const zip = new JSZip(); zip.file('bomb.xml', 'x'.repeat(50_000));
  const bytes = await zip.generateAsync({ type: 'arraybuffer', compression: 'DEFLATE' });
  const view = new DataView(bytes);
  const end = bytes.byteLength - 22;
  const directory = view.getUint32(end + 16, true);
  view.setUint32(directory + 24, 10, true);
  assert.throws(() => preflightSpreadsheetZip(bytes), /actual expanded bytes/);
});

test('ZIP preflight rejects declared expansion, encryption and ZIP64 before inflation', async () => {
  const zip = new JSZip(); zip.file('one', 'a');
  const original = await zip.generateAsync({ type: 'arraybuffer' });
  const mutations = [
    [buffer => { const view = new DataView(buffer); const directory = view.getUint32(buffer.byteLength - 6, true); view.setUint32(directory + 24, limits.SPREADSHEET_LIMITS.maxEntryBytes + 1, true); }, /expanded workbook/],
    [buffer => { const view = new DataView(buffer); const directory = view.getUint32(buffer.byteLength - 6, true); view.setUint16(directory + 8, 1, true); }, /encrypted/],
    [buffer => new DataView(buffer).setUint16(buffer.byteLength - 12, 0xffff, true), /ZIP64/],
  ];
  for (const [mutate, message] of mutations) { const bytes = original.slice(0); mutate(bytes); assert.throws(() => preflightSpreadsheetZip(bytes), message); }
});

test('workbook ranges and row-limited reads cannot silently become a complete preview', () => {
  assert.doesNotThrow(() => limits.assertSpreadsheetWorkbook(book({ '!ref': 'A1:A100000', A1: { v: 1 } })));
  for (const sheet of [
    { '!ref': 'A1:A100001' }, { '!ref': 'A1', '!fullref': 'A1:A100001' },
    { '!ref': 'A1:XFD1' }, { '!ref': 'A1', A100001: { v: 1 } }, { '!ref': 'B2:A1' },
  ]) assert.throws(() => limits.assertSpreadsheetWorkbook(book(sheet)), /limit/);
});

test('workbook budgets cover sheets, populated cells, text, merges and decoration depth', () => {
  assert.throws(() => limits.assertSpreadsheetWorkbook({ SheetNames: Array(129).fill('x'), Sheets: {} }), /worksheets/);
  const sharedRow = Array(501).fill({ v: 1 });
  assert.throws(() => limits.assertSpreadsheetWorkbook(book({ '!ref': 'A1', '!data': Array(2000).fill(sharedRow) })), /populated cells/);
  assert.throws(() => limits.assertSpreadsheetWorkbook(book({ A1: { v: 'x'.repeat(limits.SPREADSHEET_LIMITS.maxCellCharacters + 1) } })), /text is too long/);
  assert.throws(() => limits.assertSpreadsheetWorkbook(book({ '!merges': [{ s: { r: 0, c: 0 }, e: { r: 99999, c: 511 } }] })), /merged ranges/);
  const cycle = {}; cycle.self = cycle;
  assert.throws(() => limits.assertSpreadsheetDecorations(cycle), /too complex/);
  assert.throws(() => limits.assertSpreadsheetDisplaySize(Infinity, 10), /display/);
});

test('hostile row-window parameters fail before SheetJsModel allocation', () => {
  const context = parser.createSpreadsheetParserContext();
  for (const [startRow, pageSize] of [[-1, 500], [0, 501], [Infinity, 1], [0, Infinity], [0.5, 1], [100000, 1]]) {
    const result = parser.parseSpreadsheetSheet(context, { startRow, pageSize });
    assert.equal(result[0].type, 'parseError');
    assert.match(result[0].payload.message, /row window/);
  }
});

test('failed parse clears an earlier workbook instead of retaining stale content', async () => {
  const context = parser.createSpreadsheetParserContext();
  await parser.parseSpreadsheetWorkbook(context, await makeWorkbook(), { filename: 'good.xlsb' });
  assert.ok(context.workbook);
  const result = await parser.parseSpreadsheetWorkbook(context, new ArrayBuffer(0));
  assert.equal(result[0].type, 'parseError');
  assert.equal(context.workbook, null);
  assert.deepEqual(context.sheets, []);
});

test('worker timeout terminates a hung parser and reports a visible failure', async () => {
  const underlying = new FakeWorker();
  const worker = new BoundedSpreadsheetWorker(() => underlying, undefined, 5);
  const failure = new Promise(resolve => worker.addEventListener('error', resolve, { once: true }));
  worker.postMessage({ type: 'parseWorkbook', payload: {} });
  const event = await failure;
  assert.match(event.message, /worker limit/);
  assert.equal(underlying.terminated, true);
});

test('worker cancellation, parse failure, malformed reply and transfer failure terminate ownership', async () => {
  for (const mode of ['abort', 'parseError', 'messageerror', 'unexpected', 'transfer']) {
    const underlying = new FakeWorker(); const controller = new AbortController();
    const worker = new BoundedSpreadsheetWorker(() => underlying, controller.signal, 100);
    worker.addEventListener('error', () => {});
    if (mode === 'transfer') underlying.postMessage = () => { throw new Error('transfer'); };
    if (mode === 'transfer') assert.throws(() => worker.postMessage({}), /transfer/);
    else {
      worker.postMessage({ type: 'parseWorkbook' });
      if (mode === 'abort') controller.abort();
      if (mode === 'parseError') underlying.respond({ type: 'parseError', payload: { message: 'bad workbook' } });
      if (mode === 'messageerror') underlying.dispatchEvent(new Event('messageerror'));
      if (mode === 'unexpected') underlying.respond({ type: 'unrecognized' });
    }
    assert.equal(underlying.terminated, true, mode);
  }
});

test('an answered worker request clears its deadline and late replies after termination are ignored', async () => {
  const underlying = new FakeWorker();
  const worker = new BoundedSpreadsheetWorker(() => underlying, undefined, 5);
  let replies = 0; worker.addEventListener('message', () => replies++);
  worker.postMessage({ type: 'parseWorkbook' });
  underlying.respond({ type: 'sheets', payload: { sheets: [] } });
  await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(underlying.terminated, false);
  worker.terminate(); underlying.respond({ type: 'sheets' });
  assert.equal(replies, 1);
});
