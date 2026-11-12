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
  test('DOC and DOT previews are readable and explicitly text-only', () async {
    for (final name in ['report.doc', 'template.DOT']) {
      final preview = await parseOfficeDocument(_document(), name);
      expect(preview.plainText, 'Hello\nWorld');
      expect(preview.fallback, isNull);
      expect(preview.markdown, isEmpty);
      expect(preview.note, contains('Formatting'));
      expect(preview.rawXml, isNull);
      expect(await extractOfficeText(_document(), name), 'Hello\nWorld');
    }
  });

  test('malformed DOC becomes a safe extraction failure', () async {
    final preview = await parseOfficeDocument(
      Uint8List.fromList([0, 1, 2]),
      'bad.doc',
    );
    expect(preview.fallback, OfficePreviewFallback.extractionFailed);
    expect(preview.note, isNotEmpty);
  });
}
