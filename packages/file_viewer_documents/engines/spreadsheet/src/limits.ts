// SPDX-License-Identifier: Apache-2.0
// CrispCloud limits: a rejected workbook never becomes a silently truncated grid.
export const SPREADSHEET_LIMITS = Object.freeze({
  maxFileBytes: 32 * 1024 * 1024,
  maxZipEntries: 10_000,
  maxEntryBytes: 32 * 1024 * 1024,
  maxUncompressedBytes: 64 * 1024 * 1024,
  maxSheets: 128,
  maxRows: 100_000,
  maxColumns: 512,
  maxCells: 1_000_000,
  maxCellCharacters: 128 * 1024,
  maxTextCharacters: 8 * 1024 * 1024,
  maxMerges: 10_000,
  maxMergedCells: 2_000_000,
  maxDrawings: 2_000,
  maxDecorationNodes: 200_000,
  maxWindowRows: 500,
  workerTimeoutMs: 30_000,
});

const fail = (reason: string): never => { throw new Error(`Spreadsheet preview limit: ${reason}.`); };

export function assertSpreadsheetInput(buffer: ArrayBuffer): void {
  if (!(buffer instanceof ArrayBuffer) || buffer.byteLength === 0) fail('empty or invalid input');
  if (buffer.byteLength > SPREADSHEET_LIMITS.maxFileBytes) fail('file exceeds 32 MiB');
}

function checkPosition(row: number, col: number): void {
  if (!Number.isSafeInteger(row) || !Number.isSafeInteger(col) || row < 0 || col < 0 ||
      row >= SPREADSHEET_LIMITS.maxRows || col >= SPREADSHEET_LIMITS.maxColumns) {
    fail('worksheet exceeds 100,000 rows or 512 columns');
  }
}

function address(value: string): { row: number; col: number } {
  if (value.length > 32) return fail('invalid cell address');
  const match = /^\$?([A-Z]{1,4})\$?([1-9][0-9]{0,8})$/i.exec(value);
  if (!match) return fail('invalid cell address');
  let col = 0;
  for (const letter of match[1].toUpperCase()) col = col * 26 + letter.charCodeAt(0) - 64;
  const row = Number(match[2]) - 1;
  checkPosition(row, col - 1);
  return { row, col: col - 1 };
}

function checkRange(value: unknown): void {
  if (value == null) return;
  if (typeof value !== 'string' || value.length > 65) fail('invalid worksheet range');
  const parts = (value as string).split(':');
  if (parts.length > 2) fail('invalid worksheet range');
  const start = address(parts[0]);
  const end = address(parts[1] || parts[0]);
  if (end.row < start.row || end.col < start.col) fail('reversed worksheet range');
}

/** Runs before formula recovery, chart extraction, or display-size allocation. */
export function assertSpreadsheetWorkbook(workbook: any): void {
  const names = workbook?.SheetNames;
  if (!Array.isArray(names) || names.length > SPREADSHEET_LIMITS.maxSheets) fail('too many worksheets');
  let cells = 0;
  let characters = 0;
  let merges = 0;
  let mergedCells = 0;
  let drawings = 0;
  const observeText = (value: unknown) => {
    if (typeof value !== 'string') return;
    if (value.length > SPREADSHEET_LIMITS.maxCellCharacters) fail('cell text is too long');
    characters += value.length;
    if (characters > SPREADSHEET_LIMITS.maxTextCharacters) fail('workbook text exceeds 8 Mi characters');
  };
  const observeCell = (row: number, col: number, value: any) => {
    if (value == null) return;
    checkPosition(row, col);
    if (++cells > SPREADSHEET_LIMITS.maxCells) fail('too many populated cells');
    observeText(value.v); observeText(value.w); observeText(value.f);
    observeText(typeof value.r === 'string' ? value.r : undefined);
  };
  for (const name of names) {
    if (typeof name !== 'string' || name.length > 1024) fail('invalid worksheet name');
    const sheet = workbook.Sheets?.[name];
    if (!sheet || typeof sheet !== 'object') continue;
    checkRange(sheet['!ref']);
    // SheetJS retains the original range when sheetRows limits parsing. Refuse
    // the whole preview if it exceeded our cap; never pass off a prefix as all.
    checkRange(sheet['!fullref']);
    const dense = Array.isArray(sheet) ? sheet : sheet['!data'];
    if (Array.isArray(dense)) {
      if (dense.length > SPREADSHEET_LIMITS.maxRows) fail('worksheet row limit exceeded');
      for (const rowKey of Object.keys(dense)) {
        if (!/^(?:0|[1-9][0-9]*)$/.test(rowKey)) continue;
        const row = dense[Number(rowKey)];
        if (!Array.isArray(row)) continue;
        if (row.length > SPREADSHEET_LIMITS.maxColumns) fail('worksheet column limit exceeded');
        for (const colKey of Object.keys(row)) {
          if (/^(?:0|[1-9][0-9]*)$/.test(colKey)) observeCell(Number(rowKey), Number(colKey), row[Number(colKey)]);
        }
      }
    } else {
      for (const key of Object.keys(sheet)) {
        if (key.startsWith('!')) continue;
        const position = address(key);
        observeCell(position.row, position.col, sheet[key]);
      }
    }
    for (const [key, maximum] of [['!rows', SPREADSHEET_LIMITS.maxRows], ['!cols', SPREADSHEET_LIMITS.maxColumns]] as const) {
      if (Array.isArray(sheet[key]) && sheet[key].length > maximum) fail('worksheet layout limit exceeded');
    }
    const ranges = sheet['!merges'] || [];
    if (!Array.isArray(ranges) || (merges += ranges.length) > SPREADSHEET_LIMITS.maxMerges) fail('too many merged cells');
    for (const range of ranges) {
      checkPosition(range?.s?.r, range?.s?.c);
      checkPosition(range?.e?.r, range?.e?.c);
      const width = range.e.c - range.s.c + 1;
      const height = range.e.r - range.s.r + 1;
      if (width < 1 || height < 1) fail('invalid merged range');
      mergedCells += width * height;
      if (mergedCells > SPREADSHEET_LIMITS.maxMergedCells) fail('merged ranges are too large');
    }
    const images = sheet['!drawings']?.images || [];
    if (!Array.isArray(images) || (drawings += images.length) > SPREADSHEET_LIMITS.maxDrawings) fail('too many drawings');
  }
}

/** Bound structured chart/rich-image output before it reaches the UI thread. */
export function assertSpreadsheetDecorations(value: unknown): void {
  let nodes = 0;
  let characters = 0;
  const visit = (item: unknown, depth: number) => {
    if (++nodes > SPREADSHEET_LIMITS.maxDecorationNodes || depth > 32) fail('chart or image metadata is too complex');
    if (typeof item === 'string') {
      characters += item.length;
      if (characters > SPREADSHEET_LIMITS.maxUncompressedBytes) fail('chart or image data is too large');
    } else if (item && typeof item === 'object') {
      if (ArrayBuffer.isView(item)) return;
      const keys = Object.keys(item);
      if (keys.length > SPREADSHEET_LIMITS.maxDecorationNodes - nodes) fail('chart or image metadata is too complex');
      for (const key of keys) visit((item as Record<string, unknown>)[key], depth + 1);
    }
  };
  visit(value, 0);
}

export function assertSpreadsheetWindow(startRow: unknown, pageSize: unknown): void {
  if (!Number.isSafeInteger(startRow) || (startRow as number) < 0 || (startRow as number) >= SPREADSHEET_LIMITS.maxRows ||
      !Number.isSafeInteger(pageSize) || (pageSize as number) < 1 || (pageSize as number) > SPREADSHEET_LIMITS.maxWindowRows) {
    fail('invalid row window');
  }
}

export function assertSpreadsheetDisplaySize(rows: number, columns: number): void {
  if (!Number.isSafeInteger(rows) || !Number.isSafeInteger(columns) || rows < 0 || columns < 0 ||
      rows > SPREADSHEET_LIMITS.maxRows || columns > SPREADSHEET_LIMITS.maxColumns) fail('display dimensions exceed the grid limit');
}
