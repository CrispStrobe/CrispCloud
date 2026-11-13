import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/mbox_message_view.dart';
import 'package:crisp_cloud/widgets/xml_tree_view.dart';
import 'package:file_viewer_documents/file_viewer_documents.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(WidgetTester tester, String name, String contents) async {
  final bytes = Uint8List.fromList(utf8.encode(contents));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: InternalViewerDialog(
          file: FileItem(name: name, isFolder: false, size: bytes.length),
          side: PanelSide.local,
          bytesOverride: bytes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('F3 indexes MBOX and selects separate messages', (tester) async {
    await _open(
      tester,
      'mail.mbox',
      'From one@example.test Mon Jan  1 00:00:00 2024\n'
          'Subject: First message\nFrom: one@example.test\n\nFirst body\n'
          'From two@example.test Tue Jan  2 00:00:00 2024\n'
          'Subject: Second message\nFrom: two@example.test\n\nSecond body\n',
    );
    expect(find.byType(MboxMessageView), findsOneWidget);
    expect(
      tester
          .widget<MboxMessageView>(find.byType(MboxMessageView))
          .selectedIndex,
      0,
    );
    expect(find.textContaining('First body'), findsWidgets);
    await tester.tap(find.byTooltip('Next message'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MboxMessageView>(find.byType(MboxMessageView))
          .selectedIndex,
      1,
    );
    expect(find.textContaining('Second body'), findsWidgets);
    await tester.tap(find.byTooltip('Previous message'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MboxMessageView>(find.byType(MboxMessageView))
          .selectedIndex,
      0,
    );
  });
  testWidgets('XML tools use complete bytes beside existing tree and source', (
    tester,
  ) async {
    const text = '<root><value>42</value></root>';
    await _open(tester, 'data.xml', text);
    expect(find.byType(XmlTreeView), findsOneWidget);
    await tester.ensureVisible(find.text('XSD / XSLT'));
    await tester.tap(find.text('XSD / XSLT'));
    await tester.pumpAndSettle();
    final preview = tester.widget<DocumentPreview>(
      find.byType(DocumentPreview),
    );
    expect(preview.kind, DocumentPreviewKind.xml);
    expect(utf8.decode(preview.bytes), text);
    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();
    expect(find.byType(XmlTreeView), findsOneWidget);
    expect(find.byType(DocumentPreview), findsNothing);
  });
}
