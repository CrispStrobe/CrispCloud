// SPDX-License-Identifier: Apache-2.0
// Adapted from flyfish-dev/file-viewer d264009ca6efb3daed79a39d1ae63133e0f25558.
// Modified for CrispCloud: bounded decoding, ordered blocks, explicit fidelity limits,
// allocation checks and failure propagation. Native MPL-covered sources are unchanged.

import {
  assertWordPerfectInput, MAX_WORDPERFECT_BLOCKS, MAX_WORDPERFECT_CELLS,
  MAX_WORDPERFECT_EVENTS, MAX_WORDPERFECT_TEXT_BYTES, MAX_WORDPERFECT_WIRE_BYTES,
  type WordPerfectBlock, type WordPerfectDocument, type WordPerfectParagraph,
  type WordPerfectRun, type WordPerfectTable, type WordPerfectTableCell,
} from './parser.js';

interface LibWpdModule {
  HEAPU8: Uint8Array;
  HEAPU32: Uint32Array;
  _malloc(size: number): number;
  _free(pointer: number): void;
  _xberg_wpd_is_supported(data: number, length: number): number;
  _xberg_wpd_extract_document(data: number, length: number, output: number, outputLength: number, error: number): number;
  _xberg_wpd_free_string(pointer: number): void;
}

type LibWpdModuleFactory = (options: { locateFile: (path: string) => string; wasmBinary?: Uint8Array }) => Promise<LibWpdModule>;

class WireReader {
  private offset = 0;
  private textBytes = 0;
  constructor(private readonly bytes: Uint8Array) {
    if (bytes.byteLength > MAX_WORDPERFECT_WIRE_BYTES) throw new Error('WordPerfect event stream exceeds the 32 MiB preview limit.');
  }
  get remaining() { return this.bytes.length - this.offset; }
  u8() {
    if (this.remaining < 1) throw new Error('Truncated libwpd event stream.');
    return this.bytes[this.offset++];
  }
  bool() {
    const value = this.u8();
    if (value !== 0 && value !== 1) throw new Error('Invalid boolean in libwpd event stream.');
    return value === 1;
  }
  u32() {
    if (this.remaining < 4) throw new Error('Truncated libwpd event stream.');
    const value = new DataView(this.bytes.buffer, this.bytes.byteOffset + this.offset, 4).getUint32(0, true);
    this.offset += 4;
    return value;
  }
  i32() { const value = this.u32(); return value > 0x7fffffff ? value - 0x1_0000_0000 : value; }
  string() {
    const length = this.u32();
    if (length > this.remaining || length > MAX_WORDPERFECT_TEXT_BYTES - this.textBytes) {
      throw new Error('WordPerfect text exceeds the 8 MiB preview limit or the event stream is truncated.');
    }
    this.textBytes += length;
    const start = this.offset;
    this.offset += length;
    return new TextDecoder().decode(this.bytes.subarray(start, start + length));
  }
}

const generationFromHeader = (bytes: Uint8Array): WordPerfectDocument['generation'] => {
  if (bytes[0] !== 0xff || bytes[1] !== 0x57 || bytes[2] !== 0x50 || bytes[3] !== 0x43) return 'unknown';
  return (bytes[10] || 0) >= 2 ? 'wp6' : 'wp5';
};

interface Section {
  paragraphs: WordPerfectParagraph[];
  tables: WordPerfectTable[];
  blocks: WordPerfectBlock[];
}
const section = (): Section => ({ paragraphs: [], tables: [], blocks: [] });
const emptyParagraph = (): WordPerfectParagraph => ({ kind: 'paragraph', runs: [] });

/** Decode libwpd's actual callback stream; never infer content from binary text. */
export const decodeStructuredDocument = (wire: Uint8Array, source: Uint8Array): WordPerfectDocument => {
  const reader = new WireReader(wire);
  if (reader.u8() !== 1) throw new Error('Unsupported libwpd event-stream version.');
  const metadataCount = reader.u32();
  if (metadataCount > 1_000) throw new Error('WordPerfect metadata exceeds the preview limit.');
  const metadata: Record<string, string> = Object.create(null);
  for (let index = 0; index < metadataCount; index += 1) metadata[reader.string()] = reader.string();
  const eventCount = reader.u32();
  if (eventCount > MAX_WORDPERFECT_EVENTS) throw new Error('WordPerfect event count exceeds the preview limit.');
  const body = section(), headers = section(), footers = section(), notes = section();
  let destination = body;
  let paragraph = emptyParagraph();
  let styles = new Set<WordPerfectRun['styles'][number]>();
  let activeLink: string | undefined;
  let list: WordPerfectParagraph['list'];
  let table: WordPerfectTable | undefined;
  let row: WordPerfectTableCell[] | undefined;
  let cell: WordPerfectTableCell | undefined;
  let blockCount = 0, cellCount = 0;
  const contexts: Array<{
    end: number; destination: Section; paragraph: WordPerfectParagraph;
    styles: typeof styles; activeLink: typeof activeLink; list: typeof list;
    table: typeof table; row: typeof row; cell: typeof cell;
  }> = [];
  const appendBlock = (block: WordPerfectBlock) => {
    if (++blockCount > MAX_WORDPERFECT_BLOCKS) throw new Error('WordPerfect block count exceeds the preview limit.');
    destination.blocks.push(block);
  };
  const addText = (value: string) => {
    if (!value) return;
    if (cell) { cell.text += value; return; }
    const run: WordPerfectRun = { text: value, styles: [...styles] };
    if (activeLink && /^(?:https?:|mailto:)/i.test(activeLink)) run.href = activeLink;
    paragraph.runs.push(run);
  };
  const flushParagraph = () => {
    if (cell) {
      if (cell.text && !cell.text.endsWith('\n')) cell.text += '\n';
      paragraph = emptyParagraph(); list = undefined;
      return;
    }
    if (paragraph.runs.length) {
      paragraph.list = list;
      destination.paragraphs.push(paragraph);
      appendBlock({ kind: 'paragraph', paragraph });
    }
    paragraph = emptyParagraph();
    list = undefined;
  };
  const style = (name: WordPerfectRun['styles'][number], enabled: boolean) => {
    if (enabled) styles.add(name); else styles.delete(name);
  };
  const enterSection = (next: Section, end: number) => {
    if (contexts.length >= 16) throw new Error('WordPerfect section nesting exceeds the preview limit.');
    contexts.push({ end, destination, paragraph, styles, activeLink, list, table, row, cell });
    destination = next;
    paragraph = emptyParagraph(); styles = new Set(); activeLink = undefined; list = undefined;
    table = undefined; row = undefined; cell = undefined;
  };
  const leaveSection = (end: number) => {
    if (table || row || cell) throw new Error('Unclosed WordPerfect table in a document section.');
    flushParagraph();
    const previous = contexts.pop();
    if (!previous || previous.end !== end) throw new Error('Unbalanced WordPerfect document sections.');
    ({ destination, paragraph, styles, activeLink, list, table, row, cell } = previous);
  };
  const addCell = (next: WordPerfectTableCell) => {
    if (!table || !row || cell) throw new Error('Invalid WordPerfect table cell ordering.');
    if (++cellCount > MAX_WORDPERFECT_CELLS) throw new Error('WordPerfect table cell count exceeds the preview limit.');
    if (next.colSpan > 1_000 || next.rowSpan > 1_000) throw new Error('WordPerfect table span exceeds the preview limit.');
    next.colSpan = Math.max(1, next.colSpan); next.rowSpan = Math.max(1, next.rowSpan);
    row.push(next);
    if (!next.covered) cell = next;
  };
  for (let index = 0; index < eventCount; index += 1) {
    switch (reader.u8()) {
      case 0: addText(reader.string()); break;
      case 1: addText('\t'); break;
      case 2: addText(' '); break;
      case 3: addText('\n'); break;
      case 4: flushParagraph(); break;
      case 5: list = { ordered: reader.bool(), level: reader.u8(), counter: reader.u32() }; break;
      case 6: flushParagraph(); break;
      case 7: paragraph.kind = 'heading'; paragraph.level = reader.u8(); break;
      case 8: style('bold', true); break;
      case 9: style('bold', false); break;
      case 10: style('italic', true); break;
      case 11: style('italic', false); break;
      case 12: style('underline', true); break;
      case 13: style('underline', false); break;
      case 14: style('strikethrough', true); break;
      case 15: style('strikethrough', false); break;
      case 16: style('superscript', true); break;
      case 17: style('superscript', false); break;
      case 18: style('subscript', true); break;
      case 19: style('subscript', false); break;
      case 20:
        if (table) throw new Error('Nested WordPerfect tables are not supported by this preview.');
        flushParagraph(); table = { rows: [] }; destination.tables.push(table);
        appendBlock({ kind: 'table', table }); break;
      case 21:
        if (!table || row) throw new Error('Invalid WordPerfect table row ordering.');
        row = []; table.rows.push(row); reader.bool(); break;
      case 22: addCell({ text: '', column: reader.i32(), colSpan: reader.u32(), rowSpan: reader.u32() }); break;
      case 23: addCell({ text: '', column: reader.i32(), colSpan: 1, rowSpan: 1, covered: true }); break;
      case 24:
        if (!cell) throw new Error('Unbalanced WordPerfect table cells.');
        cell.text = cell.text.replace(/\n$/, ''); cell = undefined; break;
      case 25:
        if (!row || cell) throw new Error('Unbalanced WordPerfect table rows.');
        row = undefined; break;
      case 26:
        if (!table || row || cell) throw new Error('Unbalanced WordPerfect table.');
        table = undefined; break;
      case 27: enterSection(headers, 28); break;
      case 28: leaveSection(28); break;
      case 29: enterSection(footers, 30); break;
      case 30: leaveSection(30); break;
      case 31: reader.bool(); enterSection(notes, 32); break;
      case 32: leaveSection(32); break;
      case 33: reader.string(); enterSection(notes, 34); break;
      case 34: leaveSection(34); break;
      case 35: activeLink = reader.string(); break;
      case 36: activeLink = undefined; break;
      case 37: addText(`[${reader.string()}]`); break;
      default: throw new Error('Unknown libwpd event tag.');
    }
  }
  if (contexts.length || table || row || cell) throw new Error('Unclosed WordPerfect document structure.');
  flushParagraph();
  if (reader.remaining !== 0) throw new Error('Unexpected trailing bytes in libwpd event stream.');
  return {
    format: 'wordperfect', generation: generationFromHeader(source),
    documentOffset: source.length >= 8 ? new DataView(source.buffer, source.byteOffset + 4, 4).getUint32(0, true) : 0,
    encrypted: false, engine: 'libwpd-wasm',
    paragraphs: body.paragraphs.map(item => item.runs.map(run => run.text).join('')),
    structuredParagraphs: body.paragraphs, tables: body.tables,
    headers: headers.paragraphs, footers: footers.paragraphs, notes: notes.paragraphs,
    blocks: body.blocks, headerBlocks: headers.blocks, footerBlocks: footers.blocks, noteBlocks: notes.blocks,
    metadata,
    warnings: ['Structured WordPerfect preview: page layout, embedded images and fonts, equations, and drawings are not reproduced. Table cells use plain text; headers, footers, and notes are shown separately.'],
  };
};

const readCString = (heap: Uint8Array, pointer: number) => {
  if (!pointer || pointer >= heap.length) return '';
  let end = pointer;
  while (end < heap.length && heap[end] !== 0 && end - pointer < 16_384) end += 1;
  return new TextDecoder().decode(heap.subarray(pointer, end));
};

export const parseWordPerfectWithLibWpd = async (
  buffer: ArrayBuffer, moduleUrl: string, wasmUrl: string, wasmBinary?: Uint8Array
): Promise<WordPerfectDocument> => {
  assertWordPerfectInput(buffer);
  const imported = await import(/* @vite-ignore */ moduleUrl) as { default: LibWpdModuleFactory };
  let resolvedBinary = wasmBinary;
  if (!resolvedBinary) {
    const response = await fetch(wasmUrl, { credentials: 'same-origin' });
    if (!response.ok) throw new Error(`libwpd WebAssembly returned HTTP ${response.status}.`);
    resolvedBinary = new Uint8Array(await response.arrayBuffer());
  }
  const module = await imported.default({ locateFile: path => path.endsWith('.wasm') ? wasmUrl : path, wasmBinary: resolvedBinary });
  let input = 0, output = 0, outputLength = 0, error = 0, extracted = 0, errorPointer = 0;
  const allocate = (length: number) => {
    const pointer = module._malloc(length);
    if (!pointer || pointer > module.HEAPU8.byteLength - length) throw new Error('WordPerfect parser could not allocate memory.');
    return pointer;
  };
  try {
    input = allocate(buffer.byteLength); output = allocate(4); outputLength = allocate(4); error = allocate(4);
    module.HEAPU8.set(new Uint8Array(buffer), input);
    module.HEAPU32[output >>> 2] = 0; module.HEAPU32[outputLength >>> 2] = 0; module.HEAPU32[error >>> 2] = 0;
    if (!module._xberg_wpd_is_supported(input, buffer.byteLength)) throw new Error('libwpd does not recognize this WordPerfect document.');
    const result = module._xberg_wpd_extract_document(input, buffer.byteLength, output, outputLength, error);
    extracted = module.HEAPU32[output >>> 2];
    const length = module.HEAPU32[outputLength >>> 2];
    errorPointer = module.HEAPU32[error >>> 2];
    if (result === 6) throw new Error('Encrypted WordPerfect documents are detected but cannot be decrypted.');
    if (result !== 0 || !extracted || !length) {
      const detail = readCString(module.HEAPU8, errorPointer);
      throw new Error(`libwpd could not parse the document${detail ? `: ${detail}` : ''}.`);
    }
    if (length > MAX_WORDPERFECT_WIRE_BYTES || extracted > module.HEAPU8.byteLength - length) {
      throw new Error('WordPerfect event stream exceeds the preview limit or is outside parser memory.');
    }
    return decodeStructuredDocument(module.HEAPU8.subarray(extracted, extracted + length), new Uint8Array(buffer));
  } finally {
    if (extracted) module._xberg_wpd_free_string(extracted);
    if (errorPointer) module._xberg_wpd_free_string(errorPointer);
    for (const pointer of [input, output, outputLength, error]) if (pointer) module._free(pointer);
  }
};
