import 'dart:typed_data';

import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:file_viewer_documents/file_viewer_documents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = InternalViewerService();
  const groups = {
    DocumentPreviewKind.wordperfect: ['wpd', 'wp', 'wp5', 'wp6'],
    DocumentPreviewKind.chm: ['chm'],
    DocumentPreviewKind.spreadsheet: ['xls', 'xlt', 'xlsb'],
    DocumentPreviewKind.ppt: ['ppt', 'pot', 'pps'],
    DocumentPreviewKind.postscript: ['ps', 'eps'],
  };
  for (final group in groups.entries) {
    for (final extension in group.value) {
      test('$extension selects its bounded document engine', () {
        final name = 'SAMPLE.${extension.toUpperCase()}';
        expect(service.detectMode(name), ViewerMode.office);
        expect(documentPreviewKind(name), group.key);
      });
    }
  }
  test('MBOX and XML keep their mode when a UTF-8 BOM is present', () {
    final bom = Uint8List.fromList([0xef, 0xbb, 0xbf, 0x46]);
    expect(service.detectMode('mail.mbox', header: bom), ViewerMode.email);
    for (final ext in ['xml', 'xsd', 'xsl', 'xslt']) {
      expect(service.detectMode('data.$ext', header: bom), ViewerMode.xml);
      expect(documentPreviewKind('data.$ext'), DocumentPreviewKind.xml);
    }
  });
  test('existing Office routes stay on their native readers', () {
    for (final ext in ['doc', 'dot', 'docx', 'xlsx', 'pptx', 'odt', 'rtf']) {
      expect(service.detectMode('data.$ext'), ViewerMode.office);
      expect(documentPreviewKind('data.$ext'), isNull);
    }
  });
  test('strong image/PDF signatures still override a misleading suffix', () {
    expect(
      service.detectMode(
        'data.wpd',
        header: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
      ),
      ViewerMode.pdf,
    );
    expect(
      service.detectMode(
        'data.xls',
        header: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
      ),
      ViewerMode.image,
    );
  });
  test('content MIME identifies the selected legacy format', () {
    expect(
      service.loadContent(Uint8List(0), 'a.mbox').mimeType,
      'application/mbox',
    );
    expect(
      service.loadContent(Uint8List(0), 'a.xls').mimeType,
      'application/vnd.ms-excel',
    );
    expect(
      service.loadContent(Uint8List(0), 'a.eps').mimeType,
      'application/postscript',
    );
    expect(
      service.loadContent(Uint8List(0), 'a.wpd').mimeType,
      'application/vnd.wordperfect',
    );
  });
}
