// SPDX-License-Identifier: Apache-2.0
// Actual streaming inflation is bounded before the workbook reader sees ZIP data.
// pako 1.0.11 is also the pinned JSZip dependency; retain its MIT/Zlib grants.
import { Inflate } from 'pako';
import { assertSpreadsheetInput, SPREADSHEET_LIMITS } from './limits.js';

const invalid = (reason: string): never => { throw new Error(`Spreadsheet ZIP preview limit: ${reason}.`); };

export function preflightSpreadsheetZip(buffer: ArrayBuffer): void {
  assertSpreadsheetInput(buffer);
  const bytes = new Uint8Array(buffer);
  if (bytes[0] !== 0x50 || bytes[1] !== 0x4b) return;
  const view = new DataView(buffer);
  const require = (offset: number, count: number) => {
    if (offset < 0 || count < 0 || offset > bytes.length - count) invalid('truncated archive');
  };
  let end = -1;
  for (let offset = bytes.length - 22; offset >= Math.max(0, bytes.length - 65_557); offset--) {
    if (view.getUint32(offset, true) === 0x06054b50 && offset + 22 + view.getUint16(offset + 20, true) === bytes.length) {
      end = offset; break;
    }
  }
  if (end < 0) invalid('missing ZIP directory');
  const count = view.getUint16(end + 10, true);
  const size = view.getUint32(end + 12, true);
  const offset = view.getUint32(end + 16, true);
  if (view.getUint16(end + 4, true) !== 0 || view.getUint16(end + 6, true) !== 0 ||
      count !== view.getUint16(end + 8, true) || count === 0xffff || size === 0xffffffff || offset === 0xffffffff) {
    invalid('multi-volume or ZIP64 workbook is unavailable');
  }
  if (count > SPREADSHEET_LIMITS.maxZipEntries) invalid('too many ZIP entries');
  require(offset, size);
  if (offset + size !== end) invalid('invalid ZIP directory extent');
  let cursor = offset;
  let declaredTotal = 0;
  let actualTotal = 0;
  for (let index = 0; index < count; index++) {
    require(cursor, 46);
    if (view.getUint32(cursor, true) !== 0x02014b50) invalid('invalid ZIP entry');
    const flags = view.getUint16(cursor + 8, true);
    const method = view.getUint16(cursor + 10, true);
    const compressed = view.getUint32(cursor + 20, true);
    const uncompressed = view.getUint32(cursor + 24, true);
    const nameLength = view.getUint16(cursor + 28, true);
    const extraLength = view.getUint16(cursor + 30, true);
    const commentLength = view.getUint16(cursor + 32, true);
    const start = view.getUint32(cursor + 42, true);
    const recordBytes = 46 + nameLength + extraLength + commentLength;
    require(cursor, recordBytes);
    if (cursor + recordBytes > end || (flags & 1) || (method !== 0 && method !== 8) ||
        compressed === 0xffffffff || uncompressed === 0xffffffff || start === 0xffffffff ||
        view.getUint16(cursor + 34, true) !== 0) invalid('unsupported or encrypted ZIP entry');
    if (uncompressed > SPREADSHEET_LIMITS.maxEntryBytes ||
        (declaredTotal += uncompressed) > SPREADSHEET_LIMITS.maxUncompressedBytes) invalid('expanded workbook exceeds 64 MiB or entry exceeds 32 MiB');
    require(start, 30);
    if (view.getUint32(start, true) !== 0x04034b50 || view.getUint16(start + 8, true) !== method ||
        (view.getUint16(start + 6, true) & 1)) invalid('invalid local ZIP header');
    const dataOffset = start + 30 + view.getUint16(start + 26, true) + view.getUint16(start + 28, true);
    require(dataOffset, compressed);
    if (dataOffset + compressed > offset) invalid('ZIP entry overlaps directory');
    let actualEntry = 0;
    const observe = (length: number) => {
      actualEntry += length; actualTotal += length;
      if (actualEntry > uncompressed || actualEntry > SPREADSHEET_LIMITS.maxEntryBytes ||
          actualTotal > SPREADSHEET_LIMITS.maxUncompressedBytes) invalid('actual expanded bytes exceed the declared resource budget');
    };
    if (method === 0) {
      observe(compressed);
    } else {
      // onData discards each 16 KiB chunk; it never accumulates an output buffer.
      const inflate = new Inflate({ raw: true, chunkSize: 16 * 1024 });
      inflate.onData = (chunk: Uint8Array) => observe(chunk.length);
      inflate.push(bytes.subarray(dataOffset, dataOffset + compressed), true);
      if (inflate.err || !inflate.ended) invalid('invalid deflated entry');
    }
    if (actualEntry !== uncompressed) invalid('incorrect ZIP expanded size');
    cursor += recordBytes;
  }
  if (cursor !== end) invalid('ZIP entry count differs from directory');
}
