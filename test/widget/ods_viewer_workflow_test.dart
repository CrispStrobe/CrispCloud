import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/preview_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../support/office_test_harness.dart';

Uint8List _source() {
  const content = '''
<office:document-content
 xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
 <office:body><office:spreadsheet><table:table table:name="Budget">
  <table:table-row>
   <table:table-cell office:value-type="string" table:number-columns-spanned="2"><text:p>Heading</text:p></table:table-cell>
   <table:covered-table-cell/>
   <table:table-cell office:value-type="float" office:value="7"/>
  </table:table-row>
  <table:table-row table:number-rows-repeated="2"/>
  <table:table-row><table:table-cell office:value-type="string"><text:p>Tail</text:p></table:table-cell></table:table-row>
 </table:table></office:spreadsheet></office:body>
</office:document-content>
''';
  final archive = Archive()
    ..addFile(
      ArchiveFile.bytes(
        'mimetype',
        utf8.encode('application/vnd.oasis.opendocument.spreadsheet'),
      ),
    )
    ..addFile(ArchiveFile.bytes('content.xml', utf8.encode(content)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  for (final archiveMember in [false, true]) {
    testWidgets(
      archiveMember
          ? 'ODS archive member uses its display name for grid and table fallback'
          : 'ODS F3 grid and table fallback preserve typed cells and source bytes',
      (tester) async {
        await tester.runAsync(() async {
          tester.view.physicalSize = const Size(1400, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final bytes = _source();
          final original = Uint8List.fromList(bytes);
          final title = archiveMember ? 'Member.ODS' : 'budget.ods';
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: InternalViewerDialog(
                  file: FileItem(
                    name: archiveMember ? 'container.zip' : title,
                    isFolder: false,
                    size: bytes.length,
                  ),
                  side: PanelSide.local,
                  bytesOverride: bytes,
                  displayName: archiveMember ? title : null,
                ),
              ),
            ),
          );
          try {
            await officePumpUntil(
              tester,
              () => find.byType(QudsSheetEditor).evaluate().isNotEmpty,
            );
            final grid = tester.widget<QudsSheetEditor>(
              find.byType(QudsSheetEditor),
            );
            final controller = grid.controller;
            expect(grid.config!.mode, OfficeInteractionMode.viewing);
            expect(grid.config!.allowsMutation, isFalse);
            expect(controller.sheet.name, 'Budget');
            expect(controller.sheet.cellA1('A1').value, 'Heading');
            expect(controller.sheet.cellA1('C1').value, 7);
            expect(controller.sheet.cellA1('A2').asString, isEmpty);
            expect(controller.sheet.cellA1('A3').asString, isEmpty);
            expect(controller.sheet.cellA1('A4').value, 'Tail');
            expect(find.text(title), findsOneWidget);
            expect(find.byTooltip('Edit (F4)'), findsNothing);

            // The existing alternate-view control is labelled Legacy. For ODS
            // it must select the native typed table, not the XLS browser route.
            await tester.tap(find.text('Legacy'));
            await officePumpUntil(
              tester,
              () => find.byType(CsvTableView).evaluate().isNotEmpty,
            );
            expect(find.byType(QudsSheetEditor), findsNothing);
            final table = tester.widget<CsvTableView>(
              find.byType(CsvTableView),
            );
            expect(table.filename, title);
            expect(table.content.split('\n'), ['Heading,,7', '', '', 'Tail']);
            expect(find.text(title), findsOneWidget);
            expect(find.text('Tail'), findsOneWidget);

            await tester.tap(find.text('Grid'));
            await officePumpUntil(
              tester,
              () => find.byType(QudsSheetEditor).evaluate().isNotEmpty,
            );
            expect(find.byType(CsvTableView), findsNothing);
            expect(
              tester
                  .widget<QudsSheetEditor>(find.byType(QudsSheetEditor))
                  .controller,
              same(controller),
            );
            expect(controller.isDirty, isFalse);
            expect(controller.sheet.cellA1('C1').value, 7);
            expect(bytes, orderedEquals(original));
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          }
        });
        expect(tester.takeException(), isNull);
      },
    );
  }
}
