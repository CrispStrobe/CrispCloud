import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _package(String cells, String extension) {
  final kind = extension == 'ods' ? 'spreadsheet' : 'text';
  final xml =
      '''
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
 <office:body><office:$kind><table:table><table:table-row>
 $cells
 </table:table-row></table:table></office:$kind></office:body>
</office:document-content>''';
  return Uint8List.fromList(
    ZipEncoder().encode(
      Archive()..addFile(ArchiveFile.bytes('content.xml', utf8.encode(xml))),
    ),
  );
}

String _cell(String count) =>
    '<table:table-cell><text:p><text:s text:c="$count"/></text:p></table:table-cell>';

void main() {
  for (final extension in ['odt', 'ods']) {
    for (final scenario in [
      ('nondecimal whitespace counts', _cell('0x10')),
      ('oversized explicit whitespace', _cell('8388609')),
      // Trimming a cell must not restore the cumulative decoding allowance.
      (
        'cumulative whitespace across empty cells',
        '${_cell('5000000')}${_cell('5000000')}',
      ),
    ]) {
      test('$extension rejects ${scenario.$1}', () async {
        final preview = await parseOfficeDocument(
          _package(scenario.$2, extension),
          'bounded.$extension',
        );
        expect(preview.fallback, OfficePreviewFallback.extractionFailed);
        expect(preview.markdown, isEmpty);
        expect(preview.csv, isNull);
      });
    }
  }
}
