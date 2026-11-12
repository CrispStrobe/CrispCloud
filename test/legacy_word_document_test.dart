import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// Hand-built [MS-DOC] FIB and piece tables. Text deliberately occupies a
// different physical order from its CP order and includes unreferenced bytes.
Uint8List _document({
  List<(String, bool)> pieces = const [('Hello\rWorld\r', true)],
  int flags = 0x0200,
  int? characterCount,
  int? firstOffset,
  int? lastPosition,
  bool includeTable = true,
  bool includePropertyRecord = true,
  bool nestedOnly = false,
}) {
  final word = Uint8List(16384);
  final fib = ByteData.sublistView(word);
  void u16(int offset, int value) =>
      fib.setUint16(offset, value, Endian.little);
  void u32(int offset, int value) =>
      fib.setUint32(offset, value, Endian.little);
  u16(0, 0xa5ec);
  u16(2, 0x00c1);
  u16(10, flags);
  u16(32, 14);
  u16(62, 22);
  u16(152, 93);
  final count = pieces.fold<int>(0, (sum, piece) => sum + piece.$1.length);
  u32(76, characterCount ?? count);
  final plc = Uint8List(pieces.length * 12 + 4);
  final tableData = ByteData.sublistView(plc);
  var cp = 0;
  final pcdStart = (pieces.length + 1) * 4;
  for (var index = 0; index < pieces.length; index++) {
    final (text, compressed) = pieces[index];
    final offset = index == 0 && firstOffset != null
        ? firstOffset
        : 8192 - index * 1024;
    tableData.setUint32(index * 4, cp, Endian.little);
    tableData.setUint32(
      pcdStart + index * 8 + 2,
      compressed ? 0x40000000 | (offset * 2) : offset,
      Endian.little,
    );
    if (offset + text.length * 2 <= word.length) {
      for (var character = 0; character < text.length; character++) {
        if (compressed) {
          word[offset + character] = text.codeUnitAt(character);
        } else {
          u16(offset + character * 2, text.codeUnitAt(character));
        }
      }
    }
    cp += text.length;
  }
  tableData.setUint32(pieces.length * 4, lastPosition ?? cp, Endian.little);
  final clx = BytesBuilder();
  if (includePropertyRecord) clx.add([1, 2, 0, 0, 0]);
  clx.add([2]);
  clx.add(
    (ByteData(4)..setUint32(0, plc.length, Endian.little)).buffer.asUint8List(),
  );
  clx.add(plc);
  final clxBytes = clx.takeBytes();
  u32(0x1a2, 16);
  u32(0x1a6, clxBytes.length);
  word.setRange(12000, 12014, ascii.encode('DELETED SECRET'));
  final table = Uint8List(16 + clxBytes.length)
    ..setRange(16, 16 + clxBytes.length, clxBytes);
  final writer = CfbfWriter();
  final prefix = nestedOnly ? 'Embedded/' : '';
  writer.addStream('${prefix}WordDocument', word);
  if (includeTable) {
    writer.addStream(
      '$prefix${flags & 0x0200 != 0 ? '1Table' : '0Table'}',
      table,
    );
  }
  // A stale table must never be used instead of the selected FIB table.
  writer.addStream(
    '$prefix${flags & 0x0200 != 0 ? '0Table' : '1Table'}',
    Uint8List(0),
  );
  return writer.build();
}

void main() {
  test(
    'reads body CPs from compressed and Unicode pieces in logical order',
    () {
      final bytes = _document(
        pieces: [('Hello\r', true), ('世界 😀\r', false), ('End\r', true)],
      );
      expect(extractLegacyWordText(bytes), 'Hello\n世界 😀\nEnd');
      expect(extractLegacyWordText(bytes), isNot(contains('DELETED SECRET')));
    },
  );

  test('uses the selected 0Table and excludes trailing non-body stories', () {
    final bytes = _document(
      flags: 0,
      pieces: [('Main\r', true), ('Footnote\r', true)],
      characterCount: 5,
    );
    expect(extractLegacyWordText(bytes), 'Main');
  });

  test('decodes documented compressed punctuation and table cells', () {
    final bytes = _document(pieces: [('\x93Quoted\x94\x07Next\r', true)]);
    expect(extractLegacyWordText(bytes), '“Quoted”\tNext');
  });

  test(
    'shows field results without instruction text, including nested fields',
    () {
      final bytes = _document(
        pieces: [
          (
            'Before \x13HYPERLINK "secret"\x14Link\x15 '
                '\x13IF \x13X\x14Y\x15\x14Shown\x15 after\r',
            true,
          ),
        ],
      );
      expect(extractLegacyWordText(bytes), 'Before Link Shown after');
    },
  );

  test('does not fall back to a same-named embedded Word stream', () {
    expect(
      () => extractLegacyWordText(_document(nestedOnly: true)),
      throwsFormatException,
    );
  });

  test('rejects encrypted Word input before decoding tables', () {
    expect(
      () => extractLegacyWordText(_document(flags: 0x0300)),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('encrypted'),
        ),
      ),
    );
  });

  test(
    'rejects missing, truncated, nonmonotonic and oversized text tables',
    () {
      for (final bytes in [
        _document(includeTable: false),
        _document(firstOffset: 16380),
        _document(lastPosition: 0),
        _document(characterCount: 4 * 1024 * 1024 + 1),
        _document(characterCount: 100),
      ]) {
        expect(() => extractLegacyWordText(bytes), throwsFormatException);
      }
    },
  );

  test(
    'DOC and DOT previews provide a structured, explicitly partial view',
    () async {
      for (final name in ['report.doc', 'template.DOT']) {
        final preview = await parseOfficeDocument(_document(), name);
        expect(preview.plainText, 'Hello\nWorld');
        expect(preview.fallback, isNull);
        expect(preview.markdown, isEmpty);
        expect(preview.safeHtml, contains('Hello'));
        expect(preview.notice, OfficePreviewNotice.legacyWordPartial);
        expect(preview.rawXml, isNull);
      }
    },
  );

  test('malformed DOC becomes a safe extraction failure', () async {
    final preview = await parseOfficeDocument(
      Uint8List.fromList([0, 1, 2]),
      'bad.doc',
    );
    expect(preview.fallback, OfficePreviewFallback.extractionFailed);
    expect(preview.note, isNotEmpty);
  });
}
