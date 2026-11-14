# CSV and TSV spreadsheet import

F3 and F4 expose **Import as spreadsheet…** for CSV/TSV files. F3 retains its existing table, text and hex views; F4 retains text editing. Import is optional and creates a sibling XLSX file that opens in the existing Quds spreadsheet editor. Saving there saves the new XLSX, not the CSV.

The dialog previews 20 rows and 10 columns while importing the complete table. It detects comma, semicolon or tab outside quoted headings, and allows explicit delimiter selection. Viewer imports offer the editor's BOM-aware text decoding and manual encoding overrides. F4 imports the current text buffer, including unsaved edits; cancelling leaves the buffer and undo history in place. Automatic CSV saving is suspended while the import and spreadsheet editor are open.

All fields are text initially. The optional number recognition converts only finite decimal values with at most 15 mantissa digits. Leading-zero identifiers, longer identifiers and formula-looking fields remain literal text. Import does not activate formulas. This conservative conversion uses a decimal point; localized numbers remain text for editing.

## Existing Quds support used

`ReportCsv.parse` already understands quoted delimiters, escaped quotes, multiline fields, and BOMs. The spreadsheet `SmlPowerQuery.fromCsv` helper previously split physical lines. It now uses the shared parser, has a `detectNumbers` option, and exposes `fromRows`. Spreadsheet imports opt into retaining blank records; report defaults remain compatible. A final quoted empty record is retained without inventing an extra row after a terminal newline.

The host uses `fromRows(..., detectNumbers: false)` and Quds' existing XLSX serializer, deserializer and spreadsheet editor. No second CSV parser, runtime dependency or external conversion service was added.

## Storage and size limits

Import supports local and connected remote storage through the existing verified create-only conversion path. Source identity remains captured even when another pane or account becomes active. Existing filenames are refused and the resulting file is read back and verified before opening. Archive members must first be extracted; in-memory viewer overrides do not expose the import action.

Input is limited to 8 MiB, 1,000,000 cells, 1,048,576 rows and 16,384 columns. Limits reject the import rather than silently truncating it. Desktop/mobile parsing and XLSX construction run in worker isolates; web uses Flutter's compute fallback and the existing storage APIs.

## Verification

The macOS host regression completed with **40 tests passed**, covering BASIC/VBA token scopes in viewer and editor, exact XLSX text/number round trips, create-only storage publication, malformed/oversized input, all supported UI locales, a 320 × 480 dialog with 2.5× text scaling, CSV viewer → verified XLSX → Quds editor, and importing/cancelling unsaved F4 text. Existing viewer actions, text/hex handoffs, account-change guards and large-source highlighting remain covered.

The shared Quds CSV/report and Office-feature run passed 129 tests; the subsequent final-empty-record fix passed all seven CSV import regressions. The host source check verifies all 2,161 managed Office files against Quds `b0335829428d50968258219c4fdced15d546f7c9` and the canonical legacy DOC parser pin. These counts describe separate overlapping checks and should not be added together.
