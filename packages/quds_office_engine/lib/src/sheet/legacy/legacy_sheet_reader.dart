// Bounded BIFF8 (Excel 97–2003 `.xls`) workbook reader.
//
// CrispCloud used to depend on the preview worker for `.xls`, which returns a
// rendered grid: values became strings and formulas, number formats and styles
// were lost. This reader produces the same workbook model as the OOXML path, so
// an imported `.xls` can be edited and saved as `.xlsx` without a conversion
// service.
//
// Scope: BIFF8 (`Workbook` stream) produced by Excel 97+ and LibreOffice.
// BIFF5/7 (`Book`) is rejected with a clear message; encrypted workbooks fail
// closed because the CFB stream is not readable without the key.

import 'dart:convert';
import 'dart:typed_data';

import '../../opc/ole/bounded_cfb_reader.dart';
import '../formula/formula_eval.dart';
import '../model/sml_workbook.dart';
import '../styles/sml_styles.dart';

/// Thrown when a legacy workbook cannot be read safely.
class LegacySheetFormatException implements Exception {
  /// LegacySheetFormatException API.
  const LegacySheetFormatException(this.message);

  /// message API.
  final String message;

  @override
  String toString() => 'LegacySheetFormatException: $message';
}

/// Reads `.xls` (BIFF8) into [SmlWorkbook].
abstract final class LegacySheetReader {
  /// True when [bytes] start with the OLE/CFB signature.
  static bool isCompoundFile(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0xD0 &&
      bytes[1] == 0xCF &&
      bytes[2] == 0x11 &&
      bytes[3] == 0xE0 &&
      bytes[4] == 0xA1 &&
      bytes[5] == 0xB1 &&
      bytes[6] == 0x1A &&
      bytes[7] == 0xE1;

  /// Reads a BIFF8 workbook. Throws [LegacySheetFormatException] on malformed
  /// or unsupported input.
  static SmlWorkbook readBytes(Uint8List bytes) {
    if (!isCompoundFile(bytes)) {
      // Excel 2003 can save an HTML table with an .xls extension. That is not
      // BIFF, but it is a real workbook users expect to open.
      final text = _decodeText(bytes);
      if (_looksLikeHtml(text)) return LegacyHtmlSheetReader.read(text);
      throw const LegacySheetFormatException(
        'Not an OLE compound file or an Excel HTML workbook',
      );
    }
    final BoundedCfbReader cfb;
    try {
      cfb = BoundedCfbReader(bytes);
    } on FormatException catch (error) {
      throw LegacySheetFormatException(error.message);
    }
    final stream =
        cfb.readPath('Workbook') ??
        cfb.readPath('Book') ??
        cfb.readPath('workbook');
    if (stream == null) {
      throw const LegacySheetFormatException(
        'No Workbook stream (encrypted or not a spreadsheet)',
      );
    }
    return _BiffWorkbookParser(stream).parse();
  }
}

String _decodeText(Uint8List bytes) {
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  return utf8.decode(bytes.sublist(start), allowMalformed: true);
}

bool _looksLikeHtml(String text) {
  final head = text.trimLeft().toLowerCase();
  return head.startsWith('<html') ||
      head.startsWith('<!doctype html') ||
      head.contains('<table');
}

/// Reads the HTML-table flavour of `.xls` (Excel 2003 "Save as Web Page").
abstract final class LegacyHtmlSheetReader {
  static SmlWorkbook read(String html) {
    // Sheet names live in an Office XML block that Excel wraps in a
    // downlevel-revealed conditional comment, so read them before stripping
    // comments.
    final names = RegExp(
      r'<[A-Za-z0-9]+:Name>(.*?)</[A-Za-z0-9]+:Name>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html).map((match) => _text(match.group(1)!)).toList();
    final source = html.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    final tables = RegExp(
      r'<table\b.*?</table>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(source).toList();
    if (tables.isEmpty) {
      throw const LegacySheetFormatException('HTML workbook has no tables');
    }
    final book = SmlWorkbook(sheets: <SmlWorksheet>[], styles: SmlStyleSheet());
    for (var index = 0; index < tables.length; index++) {
      final name = index < names.length && names[index].isNotEmpty
          ? names[index]
          : 'Sheet${index + 1}';
      final sheet = SmlWorksheet(name: name, sheetId: index + 1);
      var row = 0;
      final table = tables[index].group(0)!;
      final caption = RegExp(
        r'<caption\b[^>]*>(.*?)</caption>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(table);
      var captionColumns = 0;
      if (caption != null) {
        final text = _text(caption.group(1)!);
        if (text.isNotEmpty) {
          sheet
              .cellA1('A1')
            ..value = text
            ..type = SmlCellType.string;
          row = 1;
        }
      }
      for (final rowMatch in RegExp(
        r'<tr\b.*?</tr>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(tables[index].group(0)!)) {
        var col = 0;
        for (final cellMatch in RegExp(
          r'<t[dh]\b([^>]*)>(.*?)</t[dh]>',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(rowMatch.group(0)!)) {
          final attributes = cellMatch.group(1)!;
          final body = cellMatch.group(2)!;
          final rowspan = _span(attributes, 'rowspan');
          final colspan = _span(attributes, 'colspan');
          final isHeader = cellMatch
              .group(0)!
              .toLowerCase()
              .startsWith('<th');
          final numeric = RegExp(
            r'x:num\s*=\s*"([^"]*)"',
            caseSensitive: false,
          ).firstMatch(attributes);
          final raw = numeric?.group(1) ?? _text(body);
          final value = num.tryParse(raw.trim());
          final target = sheet.cell(SmlCellRef(col, row));
          if (value != null) {
            target
              ..value = value
              ..type = SmlCellType.number;
          } else if (raw.isNotEmpty) {
            target
              ..value = raw
              ..type = SmlCellType.string;
          }
          // Excel's HTML table import applies a 10 pt wrapped cell style;
          // header cells are bold and centred.
          target.fontSize = 10;
          target.wrapText = true;
          if (isHeader) {
            target
              ..fontBold = true
              ..horizontalAlign = SmlHAlign.center;
          }
          if (rowspan > 1 || colspan > 1) {
            sheet.merges.add(
              SmlMerge(
                c0: col,
                r0: row,
                c1: col + colspan - 1,
                r1: row + rowspan - 1,
              ),
            );
          }
          col += colspan;
          if (col > captionColumns) captionColumns = col;
        }
        row++;
      }
      if (caption != null && captionColumns > 1) {
        sheet.merges.add(
          SmlMerge(c0: 0, r0: 0, c1: captionColumns - 1, r1: 0),
        );
      }
      book.sheets.add(sheet);
    }
    return book;
  }

  static int _span(String attributes, String name) {
    final match = RegExp(
      '$name\\s*=\\s*"?(\\d+)',
      caseSensitive: false,
    ).firstMatch(attributes);
    final value = int.tryParse(match?.group(1) ?? '') ?? 1;
    return value < 1 ? 1 : value;
  }

  static String _text(String html) {
    final withoutTags = html.replaceAll(RegExp(r'<[^>]*>'), '');
    return withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }
}

class _Record {
  _Record(this.id, this.offset, this.data);

  final int id;
  final int offset;
  final Uint8List data;
}

class _Reader {
  _Reader(this.data);

  final Uint8List data;
  int pos = 0;

  int get remaining => data.length - pos;
  bool get done => pos >= data.length;

  int u8() {
    if (pos + 1 > data.length) throw const FormatException('Truncated BIFF');
    return data[pos++];
  }

  int u16() {
    if (pos + 2 > data.length) throw const FormatException('Truncated BIFF');
    final value = data[pos] | (data[pos + 1] << 8);
    pos += 2;
    return value;
  }

  int u32() {
    if (pos + 4 > data.length) throw const FormatException('Truncated BIFF');
    final value =
        data[pos] |
        (data[pos + 1] << 8) |
        (data[pos + 2] << 16) |
        (data[pos + 3] << 24);
    pos += 4;
    return value;
  }

  double f64() {
    if (pos + 8 > data.length) throw const FormatException('Truncated BIFF');
    final value = ByteData.sublistView(data, pos, pos + 8).getFloat64(0, Endian.little);
    pos += 8;
    return value;
  }

  Uint8List take(int count) {
    if (count < 0 || pos + count > data.length) {
      throw const FormatException('Truncated BIFF');
    }
    final slice = Uint8List.sublistView(data, pos, pos + count);
    pos += count;
    return slice;
  }

  int get peek => pos < data.length ? data[pos] : 0;
}

class _BiffWorkbookParser {
  _BiffFont? _fontAt(int index) {
    // BIFF reserves font index 4 for a dummy/Normal face; real fonts from 5
    // onwards are stored one slot earlier than their XF index.
    if (index == 4) return _fonts.isNotEmpty ? _fonts.first : null;
    final adjusted = index >= 5 ? index - 1 : index;
    return adjusted >= 0 && adjusted < _fonts.length ? _fonts[adjusted] : null;
  }
  _BiffWorkbookParser(this.bytes);

  final Uint8List bytes;
  final Map<int, String> _formats = <int, String>{};
  final List<_BiffFont> _fonts = <_BiffFont>[];
  final List<_BiffXf> _xfs = <_BiffXf>[];
  final List<String> _strings = <String>[];
  final List<_BoundSheet> _sheets = <_BoundSheet>[];
  final List<List<String>> _supBooks = <List<String>>[];
  final Map<int, String> _paletteOverride = <int, String>{};
  final List<({int supBook, int first, int last})> _externSheets =
      <({int supBook, int first, int last})>[];
  bool _sawGlobals = false;
  bool _uses1904Dates = false;
  double? _defaultRowHeightPx;

  SmlWorkbook parse() {
    final records = _records(0, bytes.length);
    for (var recordIndex = 0; recordIndex < records.length; recordIndex++) {
      final record = records[recordIndex];
      switch (record.id) {
        case 0x0809: // BOF
          final bof = _Reader(record.data)..skip(2);
          final type = record.data.length >= 4 ? bof.u16() : 0x0005;
          if (type == 0x0005) _sawGlobals = true;
          if (type == 0x0010) {
            throw const LegacySheetFormatException(
              'Unexpected worksheet substream before globals',
            );
          }
        case 0x0022: // DATEMODE
          final reader = _Reader(record.data);
          if (reader.remaining >= 2) _uses1904Dates = reader.u16() == 1;
        case 0x0042: // CODEPAGE
          break;
        case 0x0225: // DEFAULTROWHEIGHT
          final reader = _Reader(record.data);
          reader.u16(); // flags
          _defaultRowHeightPx = SmlWorksheet.rowHeightFromExcel(
            reader.u16() / 20,
          );
        case 0x0085: // BOUNDSHEET
          final reader = _Reader(record.data);
          final position = reader.u32();
          reader.u8(); // hidden state
          reader.u8(); // sheet type
          final name = _shortString(reader);
          _sheets.add(_BoundSheet(name, position));
        case 0x00FC: // SST
          _readSst(records, recordIndex);
        case 0x041E: // FORMAT
          final reader = _Reader(record.data);
          final id = reader.u16();
          _formats[id] = _unicodeString(reader);
        case 0x00E0: // XF
          _xfs.add(_BiffXf.parse(record.data));
        case 0x0092: // PALETTE
          final reader = _Reader(record.data);
          if (reader.remaining >= 2) {
            final count = reader.u16();
            for (var i = 0; i < count && reader.remaining >= 4; i++) {
              final r = reader.u8();
              final g = reader.u8();
              final b = reader.u8();
              reader.u8(); // reserved
              // Palette entries start at colour index 8.
              _paletteOverride[8 + i] =
                  '${r.toRadixString(16).padLeft(2, '0')}'
                  '${g.toRadixString(16).padLeft(2, '0')}'
                  '${b.toRadixString(16).padLeft(2, '0')}'
                      .toUpperCase();
            }
          }
        case 0x01AE: // SUPBOOK
          final reader = _Reader(record.data);
          if (reader.remaining >= 2) {
            final ctab = reader.u16();
            if (ctab == 0x0401) {
              // Internal reference: ctab-1 sheet names follow.
              final names = <String>[];
              var count = ctab - 1;
              while (count > 0 && !reader.done) {
                names.add(_shortString(reader));
                count--;
              }
              _supBooks.add(names);
            } else {
              _supBooks.add(<String>[]);
            }
          }
        case 0x0017: // EXTERNSHEET
          final reader = _Reader(record.data);
          if (reader.remaining >= 2) {
            final count = reader.u16();
            for (var i = 0; i < count && reader.remaining >= 6; i++) {
              _externSheets.add((
                supBook: reader.u16(),
                first: reader.u16(),
                last: reader.u16(),
              ));
            }
          }
        case 0x0031: // FONT
          _fonts.add(
            _BiffFont.parse(record.data, _paletteColor),
          );
        case 0x000A: // EOF
          break;
      }
    }
    if (!_sawGlobals && _sheets.isEmpty) {
      throw const LegacySheetFormatException('Missing BIFF workbook globals');
    }
    if (_sheets.isEmpty) {
      throw const LegacySheetFormatException('Workbook has no worksheets');
    }
    final book = SmlWorkbook(
      sheets: <SmlWorksheet>[],
      styles: SmlStyleSheet(),
      uses1904Dates: _uses1904Dates,
    );
    final styles = book.styles!;
    final styleCache = <int, int>{};
    var sheetId = 0;
    for (final bound in _sheets) {
      sheetId++;
      final sheet = _parseSheet(bound, sheetId, styles, styleCache);
      book.sheets.add(sheet);
    }
    if (book.sheets.isEmpty) {
      throw const LegacySheetFormatException('Workbook has no readable sheets');
    }
    return book;
  }

  SmlWorksheet _parseSheet(
    _BoundSheet bound,
    int sheetId,
    SmlStyleSheet styles,
    Map<int, int> styleCache,
  ) {
    final sheet = SmlWorksheet(name: bound.name, sheetId: sheetId);
    if (bound.position <= 0 || bound.position >= bytes.length) {
      return sheet;
    }
    final records = _records(bound.position, bytes.length);
    var pendingRow = -1;
    var paneRow = 0;
    var paneCol = 0;
    var frozen = false;
    double? sheetDefaultRowHeight;
    Uint8List? sharedTokens;
    SmlCellRef? sharedOrigin;
    int sharedFirstRow = 0;
    int sharedLastRow = 0;
    int sharedFirstCol = 0;
    int sharedLastCol = 0;
    var pendingCol = -1;
    for (final record in records) {
      final reader = _Reader(record.data);
      switch (record.id) {
        case 0x000A: // EOF
          if (frozen) {
            if (paneRow > 0) sheet.freezeRows = paneRow;
            if (paneCol > 0) sheet.freezeCols = paneCol;
          }
          return sheet;
        case 0x0200: // DIMENSIONS
          break;
        case 0x00FD: // LABELSST
          final row = reader.u16();
          final col = reader.u16();
          final xf = reader.u16();
          final index = reader.u32();
          _put(
            sheet,
            row,
            col,
            index >= 0 && index < _strings.length ? _strings[index] : '',
            xf,
            styles,
            styleCache,
          );
        case 0x0204: // LABEL
          final row = reader.u16();
          final col = reader.u16();
          final xf = reader.u16();
          _put(sheet, row, col, _unicodeString(reader), xf, styles, styleCache);
        case 0x0203: // NUMBER
          final row = reader.u16();
          final col = reader.u16();
          final xf = reader.u16();
          _put(sheet, row, col, reader.f64(), xf, styles, styleCache);
        case 0x027E: // RK
          final row = reader.u16();
          final col = reader.u16();
          final xf = reader.u16();
          _put(sheet, row, col, _rk(reader.u32()), xf, styles, styleCache);
        case 0x00BD: // MULRK
          final row = reader.u16();
          final first = reader.u16();
          // Layout is row, colFirst, (xf, rk)*, colLast — colLast is last.
          var col = first;
          while (reader.remaining > 2) {
            final xf = reader.u16();
            _put(sheet, row, col, _rk(reader.u32()), xf, styles, styleCache);
            col++;
          }
          if (reader.remaining >= 2) reader.u16(); // colLast
        case 0x0006: // FORMULA
          final row = reader.u16();
          final col = reader.u16();
          final xf = reader.u16();
          final result = reader.take(8);
          final marker = result[6] == 0xFF && result[7] == 0xFF;
          String? formula;
          // FORMULA: rw, col, ixfe, result(8), grbit(2), chn(4), cce(2), rgce.
          if (reader.remaining >= 8) {
            final grbit = reader.u16();
            reader.u32(); // chn
            final cce = reader.u16();
            if (cce > 0 && reader.remaining >= cce) {
              final tokens = reader.take(cce);
              formula = _decodeFormula(tokens, origin: SmlCellRef(col, row));
              // A shared-formula master carries the tokens for the group.
              if ((grbit & 0x0008) != 0) {
                sharedTokens = tokens;
                sharedOrigin = SmlCellRef(col, row);
              }
            } else if (sharedTokens != null && sharedOrigin != null) {
              // Child of a shared group: shift the master's relative refs.
              formula = _shiftFormula(
                sharedTokens,
                row - sharedOrigin.row,
                col - sharedOrigin.col,
                origin: sharedOrigin,
              );
            }
          }
          Object? value;
          if (!marker) {
            value = ByteData.sublistView(result).getFloat64(0, Endian.little);
          } else {
            switch (result[0]) {
              case 0: // string result in the next STRING record
                pendingRow = row;
                pendingCol = col;
              case 1:
                value = result[2] != 0;
              case 2:
                value = _errorText(result[2]);
              default:
                value = null;
            }
          }
          final cell = _put(
            sheet,
            row,
            col,
            value,
            xf,
            styles,
            styleCache,
            overwrite: true,
          );
          if (formula != null && formula.isNotEmpty) {
            cell.formula = formula;
            cell.type = cell.value is String &&
                    FormulaEvaluator.hasErrorSpelling(cell.value)
                ? SmlCellType.error
                : SmlCellType.formula;
          }
        case 0x0207: // STRING (result of the preceding FORMULA)
          if (pendingRow >= 0) {
            final text = _unicodeString(reader);
            final cell = sheet.cell(SmlCellRef(pendingCol, pendingRow));
            cell.value = text;
            if (cell.formula == null) cell.type = SmlCellType.string;
            pendingRow = -1;
          }
        case 0x0205: // BOOLERR
          final row = reader.u16();
          final col = reader.u16();
          final xf = reader.u16();
          final value = reader.u8();
          final isError = reader.u8();
          _put(
            sheet,
            row,
            col,
            isError == 1 ? _errorText(value) : value != 0,
            xf,
            styles,
            styleCache,
          );
        case 0x0201: // BLANK
          final row = reader.u16();
          final col = reader.u16();
          final xf = reader.u16();
          _styleOnly(sheet, row, col, xf, styles, styleCache);
        case 0x00BE: // MULBLANK
          final row = reader.u16();
          final first = reader.u16();
          var col = first;
          while (reader.remaining > 2) {
            _styleOnly(sheet, row, col, reader.u16(), styles, styleCache);
            col++;
          }
          if (reader.remaining >= 2) reader.u16(); // colLast
        case 0x0208: // ROW
          final row = reader.u16();
          reader.u16(); // first column
          reader.u16(); // last column
          final height = reader.u16() / 20;
          final px = SmlWorksheet.rowHeightFromExcel(height);
          final baseline = sheetDefaultRowHeight ?? _defaultRowHeightPx;
          // ROW records are written for every used row; only non-default
          // heights are explicit formatting.
          if (height > 0 &&
              (baseline == null || (px - baseline).abs() > 0.01)) {
            sheet.rowHeights[row] = px;
          }
        case 0x007D: // COLINFO
          final first = reader.u16();
          final last = reader.u16();
          final width = reader.u16() / 256.0;
          reader.u16(); // xf
          reader.u16(); // flags
          // A COLINFO covering the whole sheet is the default width; keeping
          // it would turn every untouched column into an explicit width.
          // A record spanning dozens of columns is the sheet default, not an
          // explicit width for each column in the span.
          final broad = (last - first) >= 32;
          if (width > 0 && !broad) {
            for (var col = first; col <= last && col < 1024; col++) {
              sheet.importColumnWidth(col, width);
            }
          }
        case 0x04BC: // SHRFMLA
          if (reader.remaining >= 10) {
            // ShrFmla: rwFirst(2), rwLast(2), colFirst(1), colLast(1),
            // reserved(1), cUse(1), cce(2), rgce.
            sharedFirstRow = reader.u16();
            sharedLastRow = reader.u16();
            sharedFirstCol = reader.u8();
            sharedLastCol = reader.u8();
            reader.u8(); // reserved
            reader.u8(); // cUse
            final cce = reader.u16();
            if (cce > 0 && reader.remaining >= cce) {
              sharedTokens = reader.take(cce);
              sharedOrigin = SmlCellRef(sharedFirstCol, sharedFirstRow);
              final text = _decodeFormula(
                sharedTokens,
                origin: SmlCellRef(sharedFirstCol, sharedFirstRow),
              );
              if (text != null && text.isNotEmpty) {
                for (var r = sharedFirstRow; r <= sharedLastRow; r++) {
                  for (var c = sharedFirstCol; c <= sharedLastCol; c++) {
                    final target = sheet.cell(SmlCellRef(c, r));
                    if (target.formula == null) {
                      target.formula = _shiftFormula(
                        sharedTokens,
                        r - sharedFirstRow,
                        c - sharedFirstCol,
                        origin: SmlCellRef(sharedFirstCol, sharedFirstRow),
                      );
                      target.type = SmlCellType.formula;
                    }
                  }
                }
              }
            }
          }
        case 0x00E5: // MERGEDCELLS
          final count = reader.u16();
          for (var i = 0; i < count && reader.remaining >= 8; i++) {
            final rowFirst = reader.u16();
            final rowLast = reader.u16();
            final colFirst = reader.u16();
            final colLast = reader.u16();
            sheet.merges.add(
              SmlMerge(c0: colFirst, r0: rowFirst, c1: colLast, r1: rowLast),
            );
          }
        case 0x0041: // PANE
          reader.u16(); // x split
          reader.u16(); // y split
          paneRow = reader.u16();
          paneCol = reader.u16();
        case 0x023E: // WINDOW2
          // Bit 2 selects a frozen pane; otherwise this is a movable split.
          final options = reader.u16();
          frozen = (options & 0x0004) != 0;
        case 0x0225: // DEFAULTROWHEIGHT inside the worksheet substream
          if (reader.remaining >= 4) {
            reader.u16(); // flags
            sheetDefaultRowHeight = SmlWorksheet.rowHeightFromExcel(
              reader.u16() / 20,
            );
          }
      }
    }
    return sheet;
  }

  SmlCell _put(
    SmlWorksheet sheet,
    int row,
    int col,
    Object? value,
    int xfIndex,
    SmlStyleSheet styles,
    Map<int, int> styleCache, {
    bool overwrite = false,
  }) {
    final cell = sheet.cell(SmlCellRef(col, row));
    if (!overwrite && cell.hasContent && cell.value != null) {
      // Later records win in BIFF; keep the last value.
    }
    if (value != null) {
      cell.value = value;
      cell.type = value is bool
          ? SmlCellType.boolean
          : value is num
          ? SmlCellType.number
          : SmlCellType.string;
    }
    _applyStyle(cell, xfIndex, styles, styleCache);
    return cell;
  }

  void _styleOnly(
    SmlWorksheet sheet,
    int row,
    int col,
    int xfIndex,
    SmlStyleSheet styles,
    Map<int, int> styleCache,
  ) {
    final cell = sheet.cell(SmlCellRef(col, row));
    _applyStyle(cell, xfIndex, styles, styleCache);
  }

  void _applyStyle(
    SmlCell cell,
    int xfIndex,
    SmlStyleSheet styles,
    Map<int, int> styleCache,
  ) {
    if (xfIndex < 0 || xfIndex >= _xfs.length) return;
    final engineIndex = styleCache.putIfAbsent(xfIndex, () {
      final xf = _xfs[xfIndex];
      final font = _fontAt(xf.fontIndex);
      final code = _formatCode(xf.formatIndex);
      final fill = _fillRgb(xf);
      final align = _align(xf);
      return styles.xfFor(
        align: align,
        fillRgb: fill,
        fillColorExplicit: fill.isNotEmpty,
        fontRgb: font?.color ?? '',
        fontColorExplicit: (font?.color ?? '').isNotEmpty,
        bold: font?.bold ?? false,
        size: font?.size ?? 11,
        fontFamily: font?.family ?? 'Calibri',
        numFmtCode: code,
      );
    });
    cell.styleIndex = engineIndex;
    cell.hasExplicitStyleIndex = true;
    final xf = _xfs[xfIndex];
    final font = _fontAt(xf.fontIndex);
    if (font != null) {
      cell.fontBold = font.bold;
      cell.fontSize = font.size;
      cell.fontFamily = font.family;
      if (font.color.isNotEmpty) {
        cell.fontRgb = font.color;
        cell.hasExplicitFontColorEdit = true;
      }
    }
    final fill = _fillRgb(xf);
    if (fill.isNotEmpty) cell.fillRgb = fill;
    cell.horizontalAlign = _align(xf);
  }

  String? _paletteColor(int index) {
    final override = _paletteOverride[index];
    if (override != null) return override;
    return index >= 0 && index < _palette.length ? _palette[index] : null;
  }

  String _formatCode(int index) {
    if (_formats.containsKey(index)) return _formats[index]!;
    return _builtInFormats[index] ?? 'General';
  }

  String _fillRgb(_BiffXf xf) {
    if (xf.fillPattern == 0) return '';
    return _paletteColor(xf.fillForeground & 0x7F) ?? '';
  }

  SmlHAlign _align(_BiffXf xf) => switch (xf.horizontal) {
    1 => SmlHAlign.left,
    2 => SmlHAlign.center,
    3 => SmlHAlign.right,
    4 => SmlHAlign.center, // fill
    5 => SmlHAlign.center, // justify
    6 => SmlHAlign.center, // center across selection
    _ => SmlHAlign.general,
  };

  void _readSst(List<_Record> records, int index) {
    final segments = <Uint8List>[records[index].data];
    for (var i = index + 1; i < records.length; i++) {
      if (records[i].id != 0x003C) break; // CONTINUE
      segments.add(records[i].data);
    }
    final reader = _SstReader(segments);
    try {
      reader.u32(); // total refs
      final unique = reader.u32();
      for (var i = 0; i < unique; i++) {
        _strings.add(reader.string());
      }
    } on FormatException {
      // Keep the strings decoded so far; LABEL records still carry text.
    }
  }

  List<_Record> _records(int start, int limit) {
    final out = <_Record>[];
    var pos = start;
    while (pos + 4 <= limit) {
      final id = bytes[pos] | (bytes[pos + 1] << 8);
      final length = bytes[pos + 2] | (bytes[pos + 3] << 8);
      if (pos + 4 + length > limit) break;
      out.add(
        _Record(id, pos, Uint8List.sublistView(bytes, pos + 4, pos + 4 + length)),
      );
      pos += 4 + length;
      if (id == 0x000A && out.length > 1) break; // EOF
    }
    return out;
  }

  static double _rk(int rk) {
    final int value = rk & 0xFFFFFFFF;
    double number;
    if ((value & 0x02) != 0) {
      number = ((value & 0xFFFFFFFC).toSigned(32) >> 2).toDouble();
    } else {
      final bytes = ByteData(8);
      bytes.setUint32(4, value & 0xFFFFFFFC, Endian.little);
      number = bytes.getFloat64(0, Endian.little);
    }
    if ((value & 0x01) != 0) number /= 100;
    return number;
  }

  static String _shortString(_Reader reader) {
    final count = reader.u8();
    final flags = reader.u8();
    return _chars(reader, count, (flags & 0x01) != 0);
  }

  static String _unicodeString(_Reader reader) {
    final count = reader.u16();
    final flags = reader.u8();
    final high = (flags & 0x01) != 0;
    final rich = (flags & 0x08) != 0;
    final ext = (flags & 0x04) != 0;
    final runs = rich ? reader.u16() : 0;
    final extLength = ext ? reader.u32() : 0;
    final text = _chars(reader, count, high);
    if (runs > 0) reader.skip(runs * 4);
    if (extLength > 0) reader.skip(extLength);
    return text;
  }

  static String _chars(_Reader reader, int count, bool high) {
    if (high) {
      final units = List<int>.generate(count, (_) => reader.u16());
      return String.fromCharCodes(units);
    }
    final bytes = reader.take(count);
    return String.fromCharCodes(bytes);
  }

  String? _decodeFormula(Uint8List tokens, {SmlCellRef? origin}) {
    try {
      return _FormulaDecoder(
        tokens,
        _ixtiNames,
        originRow: origin?.row ?? 0,
        originCol: origin?.col ?? 0,
      ).decode();
    } on Object {
      return null;
    }
  }

  String? _shiftFormula(
    Uint8List tokens,
    int dRow,
    int dCol, {
    required SmlCellRef origin,
  }) {
    final text = _decodeFormula(tokens, origin: origin);
    if (text == null || (dRow == 0 && dCol == 0)) return text;
    return _shiftA1(text, dRow, dCol);
  }

  static String _shiftA1(String formula, int dRow, int dCol) {
    final out = StringBuffer();
    var i = 0;
    var inString = false;
    while (i < formula.length) {
      final ch = formula[i];
      if (ch == '"') {
        inString = !inString;
        out.write(ch);
        i++;
        continue;
      }
      if (!inString) {
        final match = RegExp(
          r'^(\$?)([A-Za-z]{1,3})(\$?)([0-9]+)',
        ).firstMatch(formula.substring(i));
        if (match != null) {
          final before = i > 0 ? formula[i - 1] : '';
          if (!RegExp(r'[A-Za-z0-9_]').hasMatch(before)) {
            final colAbs = match.group(1)!.isNotEmpty;
            final rowAbs = match.group(3)!.isNotEmpty;
            final col = _columnIndex(match.group(2)!) + (colAbs ? 0 : dCol);
            final row = int.parse(match.group(4)!) - 1 + (rowAbs ? 0 : dRow);
            if (col >= 0 && row >= 0) {
              out.write(
                '${colAbs ? '\$' : ''}${_columnLetters(col)}'
                '${rowAbs ? '\$' : ''}${row + 1}',
              );
              i += match.end;
              continue;
            }
          }
        }
      }
      out.write(ch);
      i++;
    }
    return out.toString();
  }

  static int _columnIndex(String letters) {
    var index = 0;
    for (final rune in letters.toUpperCase().runes) {
      index = index * 26 + (rune - 64);
    }
    return index - 1;
  }

  static String _columnLetters(int index) {
    var value = index + 1;
    var letters = '';
    while (value > 0) {
      final remainder = (value - 1) % 26;
      letters = String.fromCharCode(65 + remainder) + letters;
      value = (value - 1) ~/ 26;
    }
    return letters;
  }

  /// Resolve each EXTERNSHEET index to a sheet name (empty for external books).
  List<String> get _ixtiNames {
    final names = <String>[];
    for (final entry in _externSheets) {
      if (entry.supBook < 0 || entry.supBook >= _supBooks.length) {
        names.add('');
        continue;
      }
      final book = _supBooks[entry.supBook];
      final index = entry.first;
      if (book.isEmpty) {
        // Internal SUPBOOK without embedded names: index the workbook's sheets.
        names.add(
          index >= 0 && index < _sheets.length ? _sheets[index].name : '',
        );
        continue;
      }
      names.add(index >= 0 && index < book.length ? book[index] : '');
    }
    return names;
  }

  static String _errorText(int code) => switch (code) {
    0x00 => '#NULL!',
    0x07 => '#DIV/0!',
    0x0F => '#VALUE!',
    0x17 => '#REF!',
    0x1D => '#NAME?',
    0x24 => '#NUM!',
    0x2A => '#N/A',
    _ => '#ERROR!',
  };
}

extension on _Reader {
  void skip(int count) {
    if (count < 0 || pos + count > data.length) {
      throw const FormatException('Truncated BIFF');
    }
    pos += count;
  }
}

class _BoundSheet {
  _BoundSheet(this.name, this.position);
  final String name;
  final int position;
}

class _BiffFont {
  _BiffFont({
    required this.size,
    required this.bold,
    required this.color,
    required this.family,
  });

  final double size;
  final bool bold;
  final String color;
  final String family;

  static _BiffFont parse(
    Uint8List data,
    String? Function(int) paletteColor,
  ) {
    final reader = _Reader(data);
    final height = reader.u16();
    final attributes = reader.u16();
    final colorIndex = reader.u16();
    final weight = reader.u16();
    reader.u16(); // escapement
    reader.u8(); // underline
    reader.u8(); // family
    reader.u8(); // charset
    reader.u8(); // reserved
    final nameLength = reader.u8();
    final flags = reader.u8();
    final name = _BiffWorkbookParser._chars(
      reader,
      nameLength,
      (flags & 0x01) != 0,
    );
    final rgb = paletteColor(colorIndex);
    return _BiffFont(
      size: height / 20,
      bold: (weight >= 700) || (attributes & 0x01) != 0,
      color: rgb ?? '',
      family: name.isEmpty ? 'Calibri' : name,
    );
  }
}

class _BiffXf {
  _BiffXf({
    required this.fontIndex,
    required this.formatIndex,
    required this.horizontal,
    required this.isStyle,
    required this.fillPattern,
    required this.fillForeground,
  });

  final int fontIndex;
  final int formatIndex;
  final int horizontal;
  final bool isStyle;
  final int fillPattern;
  final int fillForeground;

  static _BiffXf parse(Uint8List data) {
    final reader = _Reader(data);
    final fontIndex = reader.u16();
    final formatIndex = reader.u16();
    final flags = reader.u16();
    final alignment = reader.u8();
    reader.u8(); // rotation
    reader.u8(); // indent
    reader.u8(); // shrink/merge/reading order
    reader.skip(4); // border line styles (10-13)
    // BIFF8 packs the fill into brdbkg2 (bits 26-31 = pattern) and brdbkg3
    // (bits 0-6 = foreground colour index, 7-13 = background).
    final int brdbkg2 = reader.remaining >= 6 ? reader.u32() : 0;
    final int brdbkg3 = reader.remaining >= 2 ? reader.u16() : 0;
    return _BiffXf(
      fontIndex: fontIndex,
      formatIndex: formatIndex,
      horizontal: alignment & 0x07,
      isStyle: (flags & 0x0004) != 0,
      fillPattern: (brdbkg2 >> 26) & 0x3F,
      fillForeground: brdbkg3 & 0x007F,
    );
  }
}

/// SST reader that follows strings across CONTINUE records.
class _SstReader {
  _SstReader(this.segments) : _reader = _Reader(segments.first);

  final List<Uint8List> segments;
  _Reader _reader;
  int _segment = 0;

  int u8() => _reader.u8();
  int u16() => _reader.u16();
  int u32() => _reader.u32();

  bool _advance() {
    if (_segment + 1 >= segments.length) return false;
    _segment++;
    _reader = _Reader(segments[_segment]);
    return true;
  }

  int _byteAcross() {
    while (_reader.done) {
      if (!_advance()) throw const FormatException('Truncated SST');
    }
    return _reader.u8();
  }

  int _u16Across() => _byteAcross() | (_byteAcross() << 8);

  String string() {
    final count = _u16Across();
    final flags = _byteAcross();
    final high = (flags & 0x01) != 0;
    final rich = (flags & 0x08) != 0;
    final ext = (flags & 0x04) != 0;
    final runs = rich ? _u16Across() : 0;
    final extLength = ext ? _u32Across() : 0;
    final codes = <int>[];
    var remaining = count;
    while (remaining > 0) {
      while (_reader.done) {
        if (!_advance()) throw const FormatException('Truncated SST string');
        // A CONTINUE that splits a string begins with a fresh flags byte.
        final continuationFlags = _reader.u8();
        if ((continuationFlags & 0x01) != 0) {
          // Switch the remaining characters of this string to UTF-16; the
          // decoder below reads two bytes per code unit from here on.
          if (!high) {
            for (var i = 0; i < remaining; i++) {
              codes.add(_u16Across());
            }
            remaining = 0;
          }
        }
      }
      if (remaining == 0) break;
      if (high) {
        if (_reader.remaining < 2) {
          if (!_advance()) throw const FormatException('Truncated SST string');
          _reader.u8();
          continue;
        }
        codes.add(_reader.u16());
        remaining--;
      } else {
        codes.add(_reader.u8());
        remaining--;
      }
    }
    if (runs > 0) {
      for (var i = 0; i < runs * 4; i++) {
        _byteAcross();
      }
    }
    for (var i = 0; i < extLength; i++) {
      _byteAcross();
    }
    return String.fromCharCodes(codes);
  }

  int _u32Across() {
    final a = _byteAcross();
    final b = _byteAcross();
    final c = _byteAcross();
    final d = _byteAcross();
    return a | (b << 8) | (c << 16) | (d << 24);
  }
}

class _FormulaDecoder {
  _FormulaDecoder(
    this.tokens,
    this.sheetNames, {
    this.originRow = 0,
    this.originCol = 0,
  });

  final Uint8List tokens;
  final List<String> sheetNames;
  final int originRow;
  final int originCol;
  final List<String> _stack = <String>[];
  int _pos = 0;

  String decode() {
    while (_pos < tokens.length) {
      _token();
    }
    return _stack.isEmpty ? '' : _stack.last;
  }

  void _push(String value) => _stack.add(value);

  String _pop() {
    if (_stack.isEmpty) throw const FormatException('Formula stack underflow');
    return _stack.removeLast();
  }

  void _binary(String op) {
    final right = _pop();
    final left = _pop();
    _push('($left$op$right)');
  }

  void _token() {
    final id = tokens[_pos++];
    switch (id) {
      case 0x03:
        _binary('+');
      case 0x04:
        _binary('-');
      case 0x05:
        _binary('*');
      case 0x06:
        _binary('/');
      case 0x07:
        _binary('^');
      case 0x08:
        _binary('&');
      case 0x09:
        _binary('<');
      case 0x0A:
        _binary('<=');
      case 0x0B:
        _binary('=');
      case 0x0C:
        _binary('>=');
      case 0x0D:
        _binary('>');
      case 0x0E:
        _binary('<>');
      case 0x11:
        _binary(':');
      case 0x12:
        _push('+${_pop()}');
      case 0x13:
        _push('-${_pop()}');
      case 0x14:
        _push('${_pop()}%');
      case 0x15:
        _push('(${_pop()})');
      case 0x16:
        _push('');
      case 0x17: {
        final count = tokens[_pos++];
        final flags = tokens[_pos++];
        final high = (flags & 0x01) != 0;
        final codes = <int>[];
        for (var i = 0; i < count; i++) {
          if (high) {
            codes.add(tokens[_pos] | (tokens[_pos + 1] << 8));
            _pos += 2;
          } else {
            codes.add(tokens[_pos++]);
          }
        }
        final text = String.fromCharCodes(codes);
        _push('"${text.replaceAll('"', '""')}"');
      }
      case 0x19: {
        // tAttr: grbit(1), data(2). fSum marks an AutoSum over the range
        // already on the stack; Excel often emits this instead of tFuncVar.
        final flags = tokens[_pos];
        _pos += 3;
        if ((flags & 0x10) != 0 && _stack.isNotEmpty) {
          _push('SUM(${_pop()})');
        } else if ((flags & 0x04) != 0 && _stack.length >= 2) {
          // fChoose: the stack holds extra CHOOSE arguments; keep the value.
        }
      }
      case 0x1C:
        _pos += 1;
        _push('#ERROR!');
      case 0x1D:
        _push(tokens[_pos++] != 0 ? 'TRUE' : 'FALSE');
      case 0x1E:
        _push('${tokens[_pos] | (tokens[_pos + 1] << 8)}');
        _pos += 2;
      case 0x1F: {
        final value = ByteData.sublistView(tokens, _pos, _pos + 8)
            .getFloat64(0, Endian.little);
        _pos += 8;
        _push('$value');
      }
      case 0x21:
      case 0x41:
      case 0x61: {
        final index = tokens[_pos] | (tokens[_pos + 1] << 8);
        _pos += 2;
        final name = _functionName(index);
        // tFunc carries no argument count; the function id fixes it.
        final arity = _fixedArity[index] ?? 1;
        final args = <String>[];
        for (var i = 0; i < arity; i++) {
          args.insert(0, _pop());
        }
        _push('$name(${args.join(',')})');
      }
      case 0x22:
      case 0x42:
      case 0x62: {
        final argc = tokens[_pos++];
        final index = tokens[_pos] | (tokens[_pos + 1] << 8);
        _pos += 2;
        final args = <String>[];
        for (var i = 0; i < argc; i++) {
          args.insert(0, _pop());
        }
        _push('${_functionName(index & 0x7FFF)}(${args.join(',')})');
      }
      case 0x24:
      case 0x44:
      case 0x64: {
        final row = tokens[_pos] | (tokens[_pos + 1] << 8);
        final col = tokens[_pos + 2] | (tokens[_pos + 3] << 8);
        _pos += 4;
        _push(_cellRef(col & 0x3FFF, row, col));
      }
      case 0x25:
      case 0x45:
      case 0x65: {
        final row1 = tokens[_pos] | (tokens[_pos + 1] << 8);
        final row2 = tokens[_pos + 2] | (tokens[_pos + 3] << 8);
        final col1 = tokens[_pos + 4] | (tokens[_pos + 5] << 8);
        final col2 = tokens[_pos + 6] | (tokens[_pos + 7] << 8);
        _pos += 8;
        _push(
          '${_cellRef(col1 & 0x3FFF, row1, col1)}:'
          '${_cellRef(col2 & 0x3FFF, row2, col2)}',
        );
      }
      case 0x3A:
      case 0x5A:
      case 0x7A: {
        final ixti = tokens[_pos] | (tokens[_pos + 1] << 8);
        _pos += 2;
        final row = tokens[_pos] | (tokens[_pos + 1] << 8);
        final col = tokens[_pos + 2] | (tokens[_pos + 3] << 8);
        _pos += 4;
        _push(_cellRef3d(ixti, col & 0x3FFF, row, col));
      }
      case 0x3B:
      case 0x5B:
      case 0x7B: {
        final ixti = tokens[_pos] | (tokens[_pos + 1] << 8);
        _pos += 2;
        final row1 = tokens[_pos] | (tokens[_pos + 1] << 8);
        final row2 = tokens[_pos + 2] | (tokens[_pos + 3] << 8);
        final col1 = tokens[_pos + 4] | (tokens[_pos + 5] << 8);
        final col2 = tokens[_pos + 6] | (tokens[_pos + 7] << 8);
        _pos += 8;
        _push(
          '${_cellRef3d(ixti, col1 & 0x3FFF, row1, col1)}:'
          '${_cellRef3d(ixti, col2 & 0x3FFF, row2, col2)}',
        );
      }
      case 0x23:
      case 0x43:
      case 0x63:
        _pos += 4;
        _push('#NAME?');
      case 0x2A:
      case 0x4A:
      case 0x6A: // tRefErr
        _pos += 4;
        _push('#REF!');
      case 0x2B:
      case 0x4B:
      case 0x6B: // tAreaErr
        _pos += 8;
        _push('#REF!');
      case 0x3C:
      case 0x5C:
      case 0x7C: { // tRefErr3d
        final ixti = tokens[_pos] | (tokens[_pos + 1] << 8);
        _pos += 6;
        _push('${_sheetPrefix(ixti)}#REF!');
      }
      case 0x3D:
      case 0x5D:
      case 0x7D: { // tAreaErr3d
        final ixti = tokens[_pos] | (tokens[_pos + 1] << 8);
        _pos += 10;
        _push('${_sheetPrefix(ixti)}#REF!');
      }
      case 0x2C:
      case 0x4C:
      case 0x6C: {
        // tRefN: signed row delta (2), signed column delta (1), flags (1).
        final int rowDelta = _int16(tokens, _pos);
        final int colDelta = _int8(tokens[_pos + 2]);
        _pos += 4;
        final int row = originRow + rowDelta;
        final int col = originCol + colDelta;
        if (row >= 0 && col >= 0) {
          _push('${_letters(col)}${row + 1}');
        } else {
          _push('#REF!');
        }
      }
      case 0x2D:
      case 0x4D:
      case 0x6D: {
        // tAreaN: four deltas then flags.
        final int row1 = originRow + _int16(tokens, _pos);
        final int row2 = originRow + _int16(tokens, _pos + 2);
        final int col1 = originCol + _int8(tokens[_pos + 4]);
        final int col2 = originCol + _int8(tokens[_pos + 5]);
        _pos += 7;
        if (row1 >= 0 && row2 >= 0 && col1 >= 0 && col2 >= 0) {
          _push('${_letters(col1)}${row1 + 1}:${_letters(col2)}${row2 + 1}');
        } else {
          _push('#REF!');
        }
      }
      case 0x20:
      case 0x40:
      case 0x60:
        // Array constant: skip safely.
        _pos += 1;
        throw const FormatException('Array constants are not decoded');
      default:
        throw FormatException('Unknown BIFF token 0x${id.toRadixString(16)}');
    }
  }

  String _cellRef(int col, int row, int flags) {
    // PtgRef col flags: bit 14 fColRel, bit 15 fRwRel.
    final colAbs = (flags & 0x4000) == 0;
    final rowAbs = (flags & 0x8000) == 0;
    return '${colAbs ? '\$' : ''}${_letters(col)}${rowAbs ? '\$' : ''}${row + 1}';
  }

  String _sheetPrefix(int ixti) {
    if (ixti < 0 || ixti >= sheetNames.length) return '';
    final name = sheetNames[ixti];
    if (name.isEmpty) return '';
    return name.contains(' ') ? "'$name'!" : '$name!';
  }

  String _cellRef3d(int ixti, int col, int row, int flags) {
    final ref = _cellRef(col, row, flags);
    if (ixti >= 0 && ixti < sheetNames.length) {
      final name = sheetNames[ixti];
      if (name.isEmpty) return ref;
      return name.contains(' ') ? "'$name'!$ref" : '$name!$ref';
    }
    return ref;
  }

  static String _letters(int index) {
    var value = index + 1;
    var out = '';
    while (value > 0) {
      final remainder = (value - 1) % 26;
      out = String.fromCharCode(65 + remainder) + out;
      value = (value - 1) ~/ 26;
    }
    return out;
  }

  static int _int16(Uint8List bytes, int offset) {
    if (offset + 2 > bytes.length) {
      throw const FormatException('Truncated token');
    }
    final value = bytes[offset] | (bytes[offset + 1] << 8);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  static int _int8(int value) => value >= 0x80 ? value - 0x100 : value;

  static String _functionName(int id) => _functions[id] ?? 'FUNC$id';
}

/// Paletted BIFF8 colours (index 8 = black … index 63).
const List<String?> _palette = <String?>[
  null, null, null, null, null, null, null, null,
  '000000', 'FFFFFF', 'FF0000', '00FF00', '0000FF', 'FFFF00', 'FF00FF', '00FFFF',
  '800000', '008000', '000080', '808000', '800080', '008080', 'C0C0C0', '808080',
  '9999FF', '993366', 'FFFFCC', 'CCFFFF', '660066', 'FF8080', '0066CC', 'CCCCFF',
  '000080', 'FF00FF', 'FFFF00', '00FFFF', '800080', '800000', '008080', '0000FF',
  '00CCFF', 'CCFFFF', 'CCFFCC', 'FFFF99', '99CCFF', 'FF99CC', 'CC99FF', 'FFCC99',
  '3366FF', '33CCCC', '99CC00', 'FFCC00', 'FF9900', 'FF6600', '666699', '969696',
  '003366', '339966', '003300', '333300', '993300', '993366', '333399', '333333',
];

/// Built-in `.xls` number formats (ECMA-376 §18.8.30 ids).
const Map<int, String> _builtInFormats = <int, String>{
  0: 'General',
  1: '0',
  2: '0.00',
  3: '#,##0',
  4: '#,##0.00',
  9: '0%',
  10: '0.00%',
  11: '0.00E+00',
  12: '# ?/?',
  13: '# ??/??',
  14: 'mm-dd-yy',
  15: 'd-mmm-yy',
  16: 'd-mmm',
  17: 'mmm-yy',
  18: 'h:mm AM/PM',
  19: 'h:mm:ss AM/PM',
  20: 'h:mm',
  21: 'h:mm:ss',
  22: 'm/d/yy h:mm',
  37: '#,##0 ;(#,##0)',
  38: '#,##0 ;[Red](#,##0)',
  39: '#,##0.00;(#,##0.00)',
  40: '#,##0.00;[Red](#,##0.00)',
  45: 'mm:ss',
  46: '[h]:mm:ss',
  47: 'mmss.0',
  48: '##0.0E+0',
  49: '@',
};

/// Fixed argument counts for tokens that use `tFunc` rather than `tFuncVar`.
const Map<int, int> _fixedArity = <int, int>{
  3: 1, // ISERROR
  10: 0, // NA
  19: 0, // PI
  20: 1, // SQRT
  21: 2, // POWER
  22: 1, // EXP
  23: 1, // LN
  24: 1, // ABS
  25: 1, // INT
  26: 1, // SIGN
  27: 2, // ROUND
  30: 2, // REPT
  32: 1, // LEN
  33: 1, // VALUE
  34: 0, // TRUE
  35: 0, // FALSE
  39: 2, // MOD
  68: 1, // MONTH
  69: 1, // YEAR
  70: 1, // WEEKDAY
  71: 1, // HOUR
  72: 1, // MINUTE
  73: 1, // SECOND
  74: 0, // NOW
  75: 1, // AREAS
  76: 1, // ROWS
  77: 1, // COLUMNS
  82: 2, // SEARCH
  86: 1, // TYPE
  97: 2, // ATAN2
  98: 1, // ASIN
  99: 1, // ACOS
  111: 1, // CHAR
  112: 1, // LOWER
  113: 1, // UPPER
  114: 1, // PROPER
  115: 2, // LEFT
  116: 2, // RIGHT
  118: 1, // TRIM
  121: 1, // CODE
  125: 2, // CELL
  127: 1, // ISTEXT
  128: 1, // ISNUMBER
  129: 1, // ISBLANK
  130: 1, // T
  131: 1, // N
  140: 1, // DATEVALUE
  141: 1, // TIMEVALUE
  162: 1, // CLEAN
  169: 1, // COUNTA (var in practice; keep 1 for the common case)
  183: 1, // PRODUCT (var)
  189: 1, // DPRODUCT
  190: 1, // ISNONTEXT
  193: 1, // STDEVP
  194: 1, // VARP
  197: 2, // TRUNC
  198: 1, // ISLOGICAL
  212: 2, // ROUNDUP
  213: 2, // ROUNDDOWN
  216: 2, // RANK
  221: 0, // TODAY
  227: 1, // MEDIAN (var)
  228: 1, // SUMPRODUCT (var)
  229: 1, // SINH
  230: 1, // COSH
  231: 1, // TANH
  232: 1, // ASINH
  233: 1, // ACOSH
  234: 1, // ATANH
  269: 1, // AVEDEV
  277: 2, // CONFIDENCE
  279: 1, // EVEN
  283: 1, // FISHER
  284: 1, // FISHERINV
  285: 2, // FLOOR
  288: 2, // CEILING
  298: 1, // ODD
  299: 2, // PERMUT
  318: 1, // DEVSQ
  319: 1, // GEOMEAN
  320: 1, // HARMEAN
  321: 1, // SUMSQ
  330: 1, // MODE
  331: 2, // TRIMMEAN
  342: 1, // RADIANS
  343: 1, // DEGREES
  350: 1, // ROMAN
  353: 1, // PHONETIC
};

const Map<int, String> _functions = <int, String>{
  0: 'COUNT',
  1: 'IF',
  2: 'ISNA',
  3: 'ISERROR',
  4: 'SUM',
  5: 'AVERAGE',
  6: 'MIN',
  7: 'MAX',
  8: 'ROW',
  9: 'COLUMN',
  10: 'NA',
  11: 'NPV',
  12: 'STDEV',
  15: 'SIN',
  16: 'COS',
  17: 'TAN',
  18: 'ATAN',
  19: 'PI',
  20: 'SQRT',
  21: 'POWER',
  22: 'EXP',
  23: 'LN',
  24: 'ABS',
  25: 'INT',
  26: 'SIGN',
  27: 'ROUND',
  28: 'LOOKUP',
  29: 'INDEX',
  30: 'REPT',
  31: 'MID',
  32: 'LEN',
  33: 'VALUE',
  34: 'TRUE',
  35: 'FALSE',
  36: 'AND',
  37: 'OR',
  38: 'NOT',
  39: 'MOD',
  48: 'TEXT',
  56: 'FV',
  57: 'PV',
  58: 'NPER',
  59: 'PMT',
  60: 'RATE',
  62: 'IRR',
  63: 'MIRR',
  64: 'MATCH',
  65: 'DATE',
  66: 'TIME',
  67: 'DAY',
  68: 'MONTH',
  69: 'YEAR',
  70: 'WEEKDAY',
  71: 'HOUR',
  72: 'MINUTE',
  73: 'SECOND',
  74: 'NOW',
  75: 'AREAS',
  76: 'ROWS',
  77: 'COLUMNS',
  78: 'OFFSET',
  82: 'SEARCH',
  83: 'TRANSPOSE',
  86: 'TYPE',
  97: 'ATAN2',
  98: 'ASIN',
  99: 'ACOS',
  100: 'CHOOSE',
  101: 'HLOOKUP',
  102: 'VLOOKUP',
  105: 'ISREF',
  109: 'LOG',
  111: 'CHAR',
  112: 'LOWER',
  113: 'UPPER',
  114: 'PROPER',
  115: 'LEFT',
  116: 'RIGHT',
  117: 'EXACT',
  118: 'TRIM',
  119: 'REPLACE',
  120: 'SUBSTITUTE',
  121: 'CODE',
  124: 'FIND',
  125: 'CELL',
  126: 'ISERR',
  127: 'ISTEXT',
  128: 'ISNUMBER',
  129: 'ISBLANK',
  130: 'T',
  131: 'N',
  140: 'DATEVALUE',
  141: 'TIMEVALUE',
  142: 'SLN',
  143: 'SYD',
  144: 'DDB',
  148: 'INDIRECT',
  162: 'CLEAN',
  163: 'MDETERM',
  164: 'MINVERSE',
  165: 'MMULT',
  169: 'COUNTA',
  183: 'PRODUCT',
  184: 'FACT',
  189: 'DPRODUCT',
  190: 'ISNONTEXT',
  193: 'STDEVP',
  194: 'VARP',
  197: 'TRUNC',
  198: 'ISLOGICAL',
  199: 'DCOUNTA',
  204: 'USDOLLAR',
  205: 'FINDB',
  206: 'SEARCHB',
  207: 'REPLACEB',
  208: 'LEFTB',
  209: 'RIGHTB',
  210: 'MIDB',
  211: 'LENB',
  212: 'ROUNDUP',
  213: 'ROUNDDOWN',
  214: 'ASC',
  215: 'DBCS',
  216: 'RANK',
  219: 'ADDRESS',
  220: 'DAYS360',
  221: 'TODAY',
  222: 'VDB',
  227: 'MEDIAN',
  228: 'SUMPRODUCT',
  229: 'SINH',
  230: 'COSH',
  231: 'TANH',
  232: 'ASINH',
  233: 'ACOSH',
  234: 'ATANH',
  235: 'DGET',
  244: 'INFO',
  247: 'DB',
  252: 'FREQUENCY',
  261: 'ERROR.TYPE',
  269: 'AVEDEV',
  270: 'BETADIST',
  271: 'GAMMALN',
  272: 'BETAINV',
  273: 'BINOMDIST',
  274: 'CHIDIST',
  275: 'CHIINV',
  276: 'COMBIN',
  277: 'CONFIDENCE',
  278: 'CRITBINOM',
  279: 'EVEN',
  280: 'EXPONDIST',
  281: 'FDIST',
  282: 'FINV',
  283: 'FISHER',
  284: 'FISHERINV',
  285: 'FLOOR',
  286: 'GAMMADIST',
  287: 'GAMMAINV',
  288: 'CEILING',
  289: 'HYPGEOMDIST',
  290: 'LOGNORMDIST',
  291: 'LOGINV',
  292: 'NEGBINOMDIST',
  293: 'NORMDIST',
  294: 'NORMSDIST',
  295: 'NORMINV',
  296: 'NORMSINV',
  297: 'STANDARDIZE',
  298: 'ODD',
  299: 'PERMUT',
  300: 'POISSON',
  301: 'TDIST',
  302: 'WEIBULL',
  303: 'SUMXMY2',
  304: 'SUMX2MY2',
  305: 'SUMX2PY2',
  306: 'CHITEST',
  307: 'CORREL',
  308: 'COVAR',
  309: 'FORECAST',
  310: 'FTEST',
  311: 'INTERCEPT',
  312: 'PEARSON',
  313: 'RSQ',
  314: 'STEYX',
  315: 'SLOPE',
  316: 'TTEST',
  317: 'PROB',
  318: 'DEVSQ',
  319: 'GEOMEAN',
  320: 'HARMEAN',
  321: 'SUMSQ',
  322: 'KURT',
  323: 'SKEW',
  324: 'ZTEST',
  325: 'LARGE',
  326: 'SMALL',
  327: 'QUARTILE',
  328: 'PERCENTILE',
  329: 'PERCENTRANK',
  330: 'MODE',
  331: 'TRIMMEAN',
  332: 'TINV',
  336: 'CONCATENATE',
  337: 'POWER',
  342: 'RADIANS',
  343: 'DEGREES',
  344: 'SUBTOTAL',
  345: 'SUMIF',
  346: 'COUNTIF',
  347: 'COUNTBLANK',
  348: 'ISPMT',
  350: 'ROMAN',
  351: 'GETPIVOTDATA',
  352: 'HYPERLINK',
  353: 'PHONETIC',
  354: 'AVERAGEA',
  355: 'MAXA',
  356: 'MINA',
  357: 'STDEVPA',
  358: 'VARPA',
  359: 'STDEVA',
  360: 'VARA',
  361: 'BAHTTEXT',
  362: 'THAIDAYOFWEEK',
  363: 'THAIDIGIT',
  364: 'THAIMONTHOFYEAR',
  365: 'THAINUMSOUND',
  366: 'THAINUMSTRING',
  367: 'THAISTRINGLENGTH',
  368: 'ISTHAIDIGIT',
  369: 'ROUNDBAHTDOWN',
  370: 'ROUNDBAHTUP',
  371: 'THAIYEAR',
  372: 'RTD',
};
