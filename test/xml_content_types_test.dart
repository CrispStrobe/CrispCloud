import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/editor_highlighting.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:crisp_cloud/utils/file_editability.dart';
import 'package:crisp_cloud/widgets/code_highlighting.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/xml_tree_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('XML content aliases agree in F3, F4 and syntax language selection', () {
    const viewer = InternalViewerService();
    for (final extension in [
      'acsm',
      'opf',
      'ncx',
      'gpx',
      'kml',
      'xspf',
      'xsd',
      'xslt',
      'rss',
      'atom',
    ]) {
      final name = 'document.${extension.toUpperCase()}';
      expect(viewer.detectMode(name), ViewerMode.xml);
      expect(
        viewer.detectMode(
          name,
          header: Uint8List.fromList([0xef, 0xbb, 0xbf, 0x3c]),
        ),
        ViewerMode.xml,
      );
      expect(isTextEditableName(name), isTrue);
      expect(highlightLanguageFor(name), 'xml');
      expect(editorLanguageForFile(name), 'xml');
    }
    // Strong binary signatures continue to override a misleading suffix.
    expect(
      viewer.detectMode(
        'fake.acsm',
        header: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]),
      ),
      ViewerMode.image,
    );
  });

  testWidgets('ACSM without XML declaration opens the XML tree and source', (
    tester,
  ) async {
    const xml =
        '<fulfillmentToken xmlns="urn:synthetic-test"><operatorURL>https://example.invalid/fulfill</operatorURL></fulfillmentToken>';
    final bytes = Uint8List.fromList(utf8.encode(xml));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: InternalViewerDialog(
            file: FileItem(
              name: 'URLLink.acsm',
              isFolder: false,
              size: bytes.length,
            ),
            side: PanelSide.local,
            bytesOverride: bytes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(XmlTreeView), findsOneWidget);
    expect(
      find.textContaining('fulfillmentToken', findRichText: true),
      findsWidgets,
    );
    await tester.ensureVisible(find.text('Source'));
    await tester.tap(find.text('Source'));
    await tester.pumpAndSettle();
    expect(find.byType(XmlTreeView), findsNothing);
    expect(
      find.textContaining('fulfillmentToken', findRichText: true),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });
}
