import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/csv_spreadsheet_strings.dart';
import 'package:crisp_cloud/widgets/csv_spreadsheet_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

Future<void> previewReady(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) return;
  }
  fail('Import preview did not finish');
}

Future<void> openDialog(
  WidgetTester tester, {
  String name = 'table.csv',
  String text = 'id;name\n001;"hello\nworld"',
  Uint8List? bytes,
  TextScaler? scale,
  required Future<void> Function(String, Uint8List) create,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: scale == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: scale),
              child: child!,
            ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showCsvSpreadsheetImportDialog(
                context,
                sourceName: name,
                text: text,
                sourceBytes: bytes,
                onCreate: create,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump(const Duration(milliseconds: 250));
  await previewReady(tester);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'default creates literal XLSX from current text, not an old file',
    (tester) async {
      String? name;
      Uint8List? saved;
      await openDialog(
        tester,
        create: (n, bytes) async {
          name = n;
          saved = bytes;
        },
      );
      expect(find.text('hello\nworld'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      await tester.tap(find.text('Create XLSX copy and edit'));
      await previewReady(tester);
      await tester.pumpAndSettle();
      expect(name, 'table-imported.xlsx');
      final sheet = SheetDeserializer().readBytes(saved!).sheets.single;
      expect(sheet.cell(const SmlCellRef(0, 1)).value, '001');
      expect(find.byType(CsvSpreadsheetImportDialog), findsNothing);
    },
  );

  testWidgets('raw bytes offer encoding choice and preserve decoded Unicode', (
    tester,
  ) async {
    Uint8List? saved;
    await openDialog(
      tester,
      bytes: Uint8List.fromList([
        0xff,
        0xfe,
        ...'id,name\n001,café'.codeUnits.expand((b) => [b & 255, b >> 8]),
      ]),
      create: (_, bytes) async {
        saved = bytes;
      },
    );
    expect(find.text('Text encoding'), findsOneWidget);
    expect(find.text('2 rows · 2 columns'), findsOneWidget);
    await tester.tap(find.text('Create XLSX copy and edit'));
    await previewReady(tester);
    expect(
      SheetDeserializer()
          .readBytes(saved!)
          .sheets
          .single
          .cell(const SmlCellRef(1, 1))
          .value,
      'café',
    );
  });

  testWidgets('malformed CSV disables creation and retains the input dialog', (
    tester,
  ) async {
    var writes = 0;
    await openDialog(
      tester,
      text: 'a,"unterminated',
      create: (_, _) async {
        writes++;
      },
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create XLSX copy and edit'),
          )
          .onPressed,
      isNull,
    );
    expect(find.byType(SelectableText), findsOneWidget);
    expect(writes, 0);
  });

  testWidgets('publication failure is visible and can be retried', (
    tester,
  ) async {
    var writes = 0;
    await openDialog(
      tester,
      create: (_, _) async {
        writes++;
        throw StateError('existing.xlsx already exists');
      },
    );
    await tester.tap(find.text('Create XLSX copy and edit'));
    await previewReady(tester);
    expect(find.textContaining('existing.xlsx already exists'), findsOneWidget);
    expect(find.byType(CsvSpreadsheetImportDialog), findsOneWidget);
    expect(writes, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create XLSX copy and edit'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('small screen with large text can reach import and cancel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openDialog(
      tester,
      scale: const TextScaler.linear(2.5),
      create: (_, _) async {},
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(CsvSpreadsheetImportDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all app locales have import controls and resolved counts', (
    tester,
  ) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) => Text(
              '${CsvSpreadsheetStrings(context).text('action')} ${CsvSpreadsheetStrings(context).dimensions(12, 4)}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('12'), findsOneWidget);
      expect(find.textContaining('{rows}'), findsNothing);
    }
  });
}
