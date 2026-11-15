import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Uint8List _odsBytes() {
  const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
 xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
 <office:body><office:spreadsheet>
  <table:table table:name="Data">
   <table:table-row>
    <table:table-cell office:value-type="string"><text:p>Item</text:p></table:table-cell>
    <table:table-cell office:value-type="float" office:value="2"><text:p>2</text:p></table:table-cell>
   </table:table-row>
  </table:table>
 </office:spreadsheet></office:body>
</office:document-content>
''';
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('content.xml', utf8.encode(xml)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready, {
  int attempts = 300,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 1));
    if (ready()) return;
  }
  expect(
    ready(),
    isTrue,
    reason:
        'The ODS viewer stalled. Visible text: '
        '${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? text.textSpan?.toPlainText()).join(" | ")}',
  );
}

void main() {
  testWidgets('ODS opens in the Quds grid and falls back to the typed table', (
    tester,
  ) async {
    final bytes = _odsBytes();
    await tester.pumpWidget(
      ProviderScope(
        child: _app(
          InternalViewerDialog(
            file: FileItem(
              name: 'plan.ods',
              isFolder: false,
              size: bytes.length,
            ),
            side: PanelSide.local,
            bytesOverride: bytes,
          ),
        ),
      ),
    );

    await _waitFor(
      tester,
      () => find.byType(QudsSheetEditor).evaluate().isNotEmpty,
    );
    expect(find.byType(QudsSheetEditor), findsOneWidget);
    expect(find.text('Grid'), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);

    await tester.tap(find.text('Table'));
    await _waitFor(
      tester,
      () =>
          find.byType(QudsSheetEditor).evaluate().isEmpty &&
          find.textContaining('Item').evaluate().isNotEmpty,
    );
    expect(find.byType(QudsSheetEditor), findsNothing);

    await tester.tap(find.text('Grid'));
    await tester.pumpAndSettle();
    expect(find.byType(QudsSheetEditor), findsOneWidget);
  });
}
