import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:crisp_cloud/widgets/preview_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

// One authored binary Word body for host routing. Detailed piece-table,
// encryption, ordering and resource controls live in quds_office_engine tests.
Uint8List _document() {
  const text = 'Hello\rWorld\r';
  final word = Uint8List(4096);
  final fib = ByteData.sublistView(word);
  for (final (offset, value) in [
    (0, 0xa5ec),
    (2, 0x00c1),
    (10, 0x0200),
    (32, 14),
    (62, 22),
    (152, 93),
  ]) {
    fib.setUint16(offset, value, Endian.little);
  }
  fib.setUint32(76, text.length, Endian.little);
  fib.setUint32(0x1a2, 0, Endian.little);
  fib.setUint32(0x1a6, 21, Endian.little);
  word.setRange(2048, 2048 + text.length, ascii.encode(text));
  final table = Uint8List(21)..[0] = 2;
  final clx = ByteData.sublistView(table);
  clx.setUint32(1, 16, Endian.little);
  clx.setUint32(9, text.length, Endian.little);
  clx.setUint32(15, 0x40001000, Endian.little);
  return (CfbfWriter()
        ..addStream('WordDocument', word)
        ..addStream('1Table', table))
      .build();
}

void main() {
  test(
    'DOC and DOT previews retain main-story text and disclose partial fidelity',
    () async {
      for (final name in ['report.doc', 'template.DOT']) {
        final preview = await parseOfficeDocument(_document(), name);
        expect(preview.plainText, 'Hello\nWorld');
        expect(preview.fallback, isNull);
        expect(preview.markdown, isEmpty);
        expect(preview.safeHtml, contains('Hello'));
        expect(preview.notice, OfficePreviewNotice.legacyWordPartial);
        expect(preview.rawXml, isNull);
        expect(await extractOfficeText(_document(), name), 'Hello\nWorld');
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
