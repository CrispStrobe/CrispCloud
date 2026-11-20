import 'package:crisp_cloud/services/document_fonts.dart';
// test/widget/office_editor_dialog_test.dart
//
// Tests the F4 Office editor host: routing, slide editor loading and the safe
// rejection of legacy/ODF formats.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/file_bytes_error_strings.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/captured_file_target.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/office_device_export.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';

import '../support/workflow_fake_client.dart';
import '../support/workspace_fixture.dart';

class _OversizedOfficeClient extends WorkflowFakeClient {
  int contentReads = 0;
  static const metadata = <String, dynamic>{
    'name': 'large.docx',
    'path': '/large.docx',
    'size': 65 * 1024 * 1024,
  };

  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'folders': <Map<String, dynamic>>[],
    'files': [metadata],
  };

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async =>
      path == metadata['path'] ? metadata : null;

  @override
  Future<Uint8List> downloadFileBytes(
    String path, {
    Function(int, int)? onProgress,
  }) async {
    contentReads++;
    throw StateError('An oversized Office file must not be downloaded.');
  }
}

Uint8List _macroSheet({required bool template}) {
  final source = ZipDecoder().decodeBytes(
    File('test/fixtures/office_native_workflows/native-sheet-source.xlsx')
        .readAsBytesSync(),
  );
  final files = <String, List<int>>{
    for (final file in source.files)
      if (file.isFile) file.name: file.content as List<int>,
  };
  var types = utf8.decode(files['[Content_Types].xml']!);
  types = types.replaceFirst(
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
    template
        ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.template.main+xml'
        : 'application/vnd.ms-excel.sheet.macroEnabled.main+xml',
  );
  if (!template) {
    types = types.replaceFirst(
      '</Types>',
      '<Override PartName="/xl/vbaProject.bin" '
          'ContentType="application/vnd.ms-office.vbaProject"/></Types>',
    );
    files['xl/vbaProject.bin'] = utf8.encode('INERT-VBA-BYTES');
  }
  files['[Content_Types].xml'] = utf8.encode(types);
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  setUpAll(DocumentFonts.ensureRegistered);
  test('Office extensions are routed to the Office editor', () {
    expect(isOfficeFileName('report.docx'), isTrue);
    expect(isOfficeFileName('budget.xlsx'), isTrue);
    expect(isOfficeFileName('deck.pptx'), isTrue);
    expect(isOfficeFileName('legacy.ppt'), isTrue);
    expect(isOfficeFileName('notes.odt'), isTrue);
    expect(isOfficeFileName('notes.txt'), isFalse);
    expect(isOfficeFileName('README'), isFalse);
  });

  testWidgets(
    'office load translates an oversized verified file without reading it',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final cloud = _OversizedOfficeClient();
      final container = ProviderContainer(
        overrides: [authProvider.overrideWith((_) => WorkspaceTestAuth(cloud))],
      );
      addTearDown(container.dispose);
      final panel = container.read(panelProvider(PanelSide.remote));
      await panel.refresh();
      final file = panel.files!.single;
      expect(panel.originForOperation(file), isNotNull);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('de'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: OfficeEditorDialog(file: file, side: PanelSide.remote),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Diese Datei überschreitet das Bearbeitungslimit von 64 MiB.',
        ),
        findsOneWidget,
      );
      expect(find.byType(QudsWordEditor), findsNothing);
      expect(cloud.contentReads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'captured editing limits stay typed and localized in all locales',
    (tester) async {
      final error = FileTargetTooLarge(64 * 1024 * 1024);
      expect(error, isA<FileTargetConflict>());
      expect(error.toString(), 'This file exceeds the 64 MiB editing limit.');
      for (final locale in AppLocalizations.supportedLocales) {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        final text = localizedFileBytesError(context, error);
        expect(text, contains('64 MiB'));
        expect(text, isNot(contains('{limit}')));
        if (locale.languageCode != 'en') {
          expect(text, isNot(error.toString()), reason: locale.languageCode);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('PPTX opens in the slide editor', (tester) async {
    final deck =
        (PptxDeckBuilder()
              ..addCoverSlide(title: 'Editable deck', subtitle: 'F4'))
            .build();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OfficeEditorDialog(
            file: FileItem(name: 'deck.pptx', isFolder: false),
            side: PanelSide.local,
            bytesOverride: deck,
          ),
        ),
      ),
    );

    // Font registration + controller creation are async.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(QudsSlideEditor), findsOneWidget);
    expect(find.textContaining('deck.pptx'), findsWidgets);

    // Dispose the editor surface cleanly.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('DOCX opens in the Word editor with the ribbon', (tester) async {
    final bytes =
        (DocxDocumentBuilder()
              ..heading('Editable document')
              ..paragraph('This is a paragraph that can be formatted.'))
            .build();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OfficeEditorDialog(
            file: FileItem(name: 'report.docx', isFolder: false),
            side: PanelSide.local,
            bytesOverride: bytes,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(QudsWordEditor), findsOneWidget);
    expect(find.text('Home'), findsWidgets);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(OfficeEditorDialog)),
    );
    expect(
      container.read(officeEditorMenuProvider)?.kind,
      OfficeEditorKind.word,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing the editor clears the native-menu bridge safely', (
    tester,
  ) async {
    final deck = (PptxDeckBuilder()..addCoverSlide(title: 'Close me')).build();
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: OfficeEditorDialog(
            file: FileItem(name: 'close.pptx', isFolder: false),
            side: PanelSide.local,
            bytesOverride: deck,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(officeEditorMenuProvider), isNotNull);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );
    await tester.pump();
    expect(container.read(officeEditorMenuProvider), isNull);
  });

  testWidgets('ODF/legacy files show a safe editing message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OfficeEditorDialog(
            file: FileItem(name: 'notes.odt', isFolder: false),
            side: PanelSide.local,
            bytesOverride: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('cannot be edited safely'), findsOneWidget);
  });

  testWidgets('macro-enabled workbooks open in the sheet editor', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    for (final entry in <(String, Uint8List)>[
      ('macro.xlsm', _macroSheet(template: false)),
      ('template.xltx', _macroSheet(template: true)),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: OfficeEditorDialog(
              file: FileItem(
                name: entry.$1,
                isFolder: false,
                size: entry.$2.length,
              ),
              side: PanelSide.local,
              bytesOverride: entry.$2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QudsSheetEditor), findsOneWidget, reason: entry.$1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('sheet Export as ODS writes a readable package', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Uint8List? exported;
    String? exportedName;
    final source = File(
      'test/fixtures/office_native_workflows/native-sheet-source.xlsx',
    ).readAsBytesSync();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OfficeEditorDialog(
            file: FileItem(
              name: 'sheet.xlsx',
              isFolder: false,
              size: source.length,
            ),
            side: PanelSide.local,
            bytesOverride: source,
            copyExporter: (bytes, name, title, {initialDirectory}) async {
              exported = bytes;
              exportedName = name;
              return OfficeCopyOutcome.savedCopy;
            },
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 100 && find.byType(QudsSheetEditor).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(find.byType(QudsSheetEditor), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OfficeEditorDialog)),
    );
    container
        .read(officeEditorMenuProvider)!
        .perform(OfficeEditorAction.exportOds);
    for (var i = 0; i < 100 && exported == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(exported, isNotNull);
    expect(exportedName, endsWith('.ods'));
    final book = OdsSheetReader.readBytes(exported!);
    expect(book.sheets, isNotEmpty);
  });

  testWidgets('word Export as ODT writes a readable package', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Uint8List? exported;
    String? exportedName;
    final source = File(
      'test/fixtures/office_native_workflows/native-word-source.docx',
    ).readAsBytesSync();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OfficeEditorDialog(
            file: FileItem(
              name: 'document.docx',
              isFolder: false,
              size: source.length,
            ),
            side: PanelSide.local,
            bytesOverride: source,
            copyExporter: (bytes, name, title, {initialDirectory}) async {
              exported = bytes;
              exportedName = name;
              return OfficeCopyOutcome.savedCopy;
            },
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 100 && find.byType(QudsWordEditor).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(find.byType(QudsWordEditor), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OfficeEditorDialog)),
    );
    container
        .read(officeEditorMenuProvider)!
        .perform(OfficeEditorAction.exportOdt);
    for (var i = 0; i < 100 && exported == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(exported, isNotNull);
    expect(exportedName, endsWith('.odt'));
    final package = OpcPackage.openBytes(exported!);
    final content = package.getPart('/content.xml')!.readText();
    expect(content, contains('<office:document-content'));
    expect(content, contains('<office:text'));
  });

  testWidgets('slides Export as ODP writes a readable package', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Uint8List? exported;
    String? exportedName;
    final source = File(
      'test/fixtures/office_native_workflows/native-slide-source.pptx',
    ).readAsBytesSync();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OfficeEditorDialog(
            file: FileItem(
              name: 'deck.pptx',
              isFolder: false,
              size: source.length,
            ),
            side: PanelSide.local,
            bytesOverride: source,
            copyExporter: (bytes, name, title, {initialDirectory}) async {
              exported = bytes;
              exportedName = name;
              return OfficeCopyOutcome.savedCopy;
            },
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 100 && find.byType(QudsSlideEditor).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(find.byType(QudsSlideEditor), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OfficeEditorDialog)),
    );
    container
        .read(officeEditorMenuProvider)!
        .perform(OfficeEditorAction.exportOdp);
    for (var i = 0; i < 100 && exported == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(exported, isNotNull);
    expect(exportedName, endsWith('.odp'));
    final package = OpcPackage.openBytes(exported!);
    final content = package.getPart('/content.xml')!.readText();
    expect(content, contains('<office:presentation'));
    expect(content, contains('<draw:page'));
  });
}
