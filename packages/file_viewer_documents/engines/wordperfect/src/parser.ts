// SPDX-License-Identifier: Apache-2.0
// Adapted from flyfish-dev/file-viewer d264009ca6efb3daed79a39d1ae63133e0f25558.
// Modified for CrispCloud: preserve ordered blocks; remove approximate fallback.

export const MAX_WORDPERFECT_INPUT_BYTES = 64 * 1024 * 1024;
export const MAX_WORDPERFECT_WIRE_BYTES = 32 * 1024 * 1024;
export const MAX_WORDPERFECT_EVENTS = 200_000;
export const MAX_WORDPERFECT_TEXT_BYTES = 8 * 1024 * 1024;
export const MAX_WORDPERFECT_BLOCKS = 20_000;
export const MAX_WORDPERFECT_CELLS = 50_000;

export const assertWordPerfectInput = (buffer: ArrayBuffer) => {
  if (!(buffer instanceof ArrayBuffer) || buffer.byteLength === 0) {
    throw new Error('WordPerfect input is empty or is not an ArrayBuffer.');
  }
  if (buffer.byteLength > MAX_WORDPERFECT_INPUT_BYTES) {
    throw new Error('WordPerfect file exceeds the 64 MiB preview limit.');
  }
};

export interface WordPerfectRun {
  text: string;
  styles: Array<'bold' | 'italic' | 'underline' | 'strikethrough' | 'superscript' | 'subscript'>;
  href?: string;
}

export interface WordPerfectParagraph {
  kind: 'paragraph' | 'heading';
  level?: number;
  list?: { ordered: boolean; level: number; counter: number };
  runs: WordPerfectRun[];
}

export interface WordPerfectTableCell {
  text: string;
  column: number;
  colSpan: number;
  rowSpan: number;
  covered?: boolean;
}

export interface WordPerfectTable {
  rows: WordPerfectTableCell[][];
}

export type WordPerfectBlock =
  | { kind: 'paragraph'; paragraph: WordPerfectParagraph }
  | { kind: 'table'; table: WordPerfectTable };

export interface WordPerfectDocument {
  format: 'wordperfect';
  generation: 'wp5' | 'wp6' | 'unknown';
  documentOffset: number;
  encrypted: false;
  engine: 'libwpd-wasm';
  paragraphs: string[];
  structuredParagraphs: WordPerfectParagraph[];
  tables: WordPerfectTable[];
  headers: WordPerfectParagraph[];
  footers: WordPerfectParagraph[];
  notes: WordPerfectParagraph[];
  blocks: WordPerfectBlock[];
  headerBlocks: WordPerfectBlock[];
  footerBlocks: WordPerfectBlock[];
  noteBlocks: WordPerfectBlock[];
  metadata: Record<string, string>;
  warnings: string[];
}
