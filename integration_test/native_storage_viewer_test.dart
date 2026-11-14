// Runs in the real desktop Flutter host. Only app-owned temporary files are
// used; account/credential state and the user's saved bookmarks are untouched.
// flutter test integration_test/native_storage_viewer_test.dart -d macos
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/catalogue_format.dart';
import 'package:crisp_cloud/services/catalogue_library.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/hex_viewer.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:crisp_cloud/widgets/catalogue_dialog.dart';
import 'package:crisp_cloud/widgets/csv_spreadsheet_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crisp_catalog/crisp_catalog.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/archive_ext_reference_data.dart';
import '../test/support/archive_ntfs_reference_data.dart';
import '../test/support/workflow_fake_client.dart';
import '../test/support/workspace_fixture.dart' show WorkspaceTestAuth;

// Override initial navigation and bookmark resolution only. Reads, security
// checks, stream access and create-only file publication use MacosFileService.
class _AppOwnedLocal extends MacosFileService {
  _AppOwnedLocal(this.root) : super(resolveBookmarks: () async => []) {
    currentPath = root;
  }
  final String root;
  int fullReads = 0;
  @override
  Future<String> getInitialPath() async => root;
  @override
  Future<String> getSafeFallbackDirectory() async => root;
  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    fullReads++;
    return super.readFile(path, fileItem: fileItem);
  }
}

class _AppOwnedPaths extends PathProviderPlatform {
  _AppOwnedPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final timer = Stopwatch()..start();
  while (!done()) {
    if (timer.elapsed > const Duration(seconds: 90)) {
      throw StateError('Desktop viewer transition timed out.');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<(_AppOwnedLocal, ProviderContainer)> _mount(
  WidgetTester tester,
  Directory directory,
  String name,
) async {
  SharedPreferences.setMockInitialValues({});
  final local = _AppOwnedLocal(directory.path);
  final disconnected = WorkflowFakeClient()..current = false;
  final container = ProviderContainer(
    overrides: [
      localFileServiceProvider.overrideWithValue(local),
      authProvider.overrideWith((_) => WorkspaceTestAuth(disconnected)),
    ],
  );
  addTearDown(container.dispose);
  final panel = container.read(panelProvider(PanelSide.local));
  await _until(tester, () => panel.tabs.isNotEmpty && !panel.isLoading);
  container
      .read(panelSourceProvider(PanelSide.local).notifier)
      .setSource(LocalPanelSource(directory.path));
  await panel.refresh();
  final file = panel.files!.singleWhere((entry) => entry.name == name);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: InternalViewerDialog(file: file, side: PanelSide.local),
      ),
    ),
  );
  return (local, container);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final ntfs in [false, true]) {
    testWidgets(
      'live ${ntfs ? 'NTFS' : 'ext'} image preview, Hex return and extraction',
      (tester) async {
        final directory = await Directory.systemTemp.createTemp(
          'crisp-live-image-',
        );
        final name = ntfs ? 'volume.ntfs' : 'volume.ext2';
        final image = File('${directory.path}/$name');
        final bytes = ntfs
            ? ntfsReferenceBytes('ntfs31')
            : extReferenceBytes('ext2');
        await image.writeAsBytes(bytes, flush: true);
        final handle = await image.open(mode: FileMode.append);
        await handle.truncate(80 * 1024 * 1024);
        await handle.close();
        final before = await sha256.bind(image.openRead()).single;
        try {
          final (local, _) = await _mount(tester, directory, name);
          await _until(
            tester,
            () => find.text('hello.txt').evaluate().isNotEmpty,
          );
          expect(
            local.fullReads,
            0,
            reason: 'Large images must use positional reads',
          );
          final hex = find.widgetWithText(ChoiceChip, 'Hex');
          await tester.ensureVisible(hex);
          await tester.tap(hex);
          await _until(
            tester,
            () => find.byType(HexViewer).evaluate().isNotEmpty,
          );
          final archive = find.widgetWithText(ChoiceChip, 'Archive');
          await tester.ensureVisible(archive);
          await tester.tap(archive);
          await _until(
            tester,
            () => find.text('hello.txt').evaluate().isNotEmpty,
          );
          await tester.ensureVisible(find.text('hello.txt'));
          await tester.tap(find.text('hello.txt'));
          final expected = ntfs
              ? 'Hello from NTFS filesystem'
              : 'Hello from ext filesystem';
          await _until(
            tester,
            () => find
                .textContaining(expected, findRichText: true)
                .evaluate()
                .isNotEmpty,
          );
          expect(local.fullReads, 0);
          expect(find.byType(InternalViewerDialog), findsNWidgets(2));
          final output = '${directory.path}/extracted';
          final extracted = await ArchiveService.extractArchive(
            image.path,
            output,
          );
          expect(extracted, isNotEmpty);
          expect(
            await File('$output/hello.txt').readAsString(),
            contains(expected),
          );
          expect(await sha256.bind(image.openRead()).single, before);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(milliseconds: 250));
          await directory.delete(recursive: true);
        }
      },
    );
  }

  testWidgets(
    'live CSV collision can be retried without overwriting either existing file',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'crisp-live-csv-collision-',
      );
      final original = File('${directory.path}/table.csv');
      final existing = File('${directory.path}/table-imported.xlsx');
      await original.writeAsString('id,value\n001,7');
      await existing.writeAsString('existing data must survive');
      try {
        await _mount(tester, directory, 'table.csv');
        final action = find.byKey(const ValueKey('viewer-import-spreadsheet'));
        await _until(tester, () => action.evaluate().isNotEmpty);
        await tester.ensureVisible(action);
        await tester.tap(action);
        await _until(
          tester,
          () => find.text('2 rows · 2 columns').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('Create XLSX copy and edit'));
        await _until(
          tester,
          () => find
              .textContaining('A file already exists:')
              .evaluate()
              .isNotEmpty,
        );
        expect(await existing.readAsString(), 'existing data must survive');
        final filename = find.descendant(
          of: find.byType(CsvSpreadsheetImportDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(filename, 'table-copy.xlsx');
        await tester.tap(find.text('Create XLSX copy and edit'));
        await _until(
          tester,
          () => find.byType(OfficeEditorDialog).evaluate().isNotEmpty,
        );
        final sheet = SheetDeserializer()
            .readBytes(
              await File('${directory.path}/table-copy.xlsx').readAsBytes(),
            )
            .sheets
            .single;
        expect(sheet.cell(const SmlCellRef(0, 1)).value, '001');
        expect(await existing.readAsString(), 'existing data must survive');
        expect(await original.readAsString(), 'id,value\n001,7');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 250));
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'live CAF GUI imports, searches and browses after the original folder is gone',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'crisp-live-catalogue-',
      );
      final previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _AppOwnedPaths(directory.path);
      SharedPreferences.setMockInitialValues({});
      try {
        final source = Directory('${directory.path}/source');
        await Directory('${source.path}/empty').create(recursive: true);
        await File('${source.path}/small.txt').writeAsString('abc');
        await File('${source.path}/largest.txt').writeAsString('123456789');
        final canonicalRoot = await source.resolveSymbolicLinks();
        final db = '${directory.path}/original.crispindex';
        final caf = '${directory.path}/portable.caf';
        await const CrispCatalog().execute({
          'op': 'scan',
          'path': source.path,
          'output': db,
        });
        await const CrispCatalog().execute({
          'op': 'export',
          'index': db,
          'output': caf,
        });
        await source.delete(recursive: true);
        final library = CatalogueLibrary(
          storage: MemoryFileCollectionStorage(),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: CatalogueDialog(
              local: _AppOwnedLocal(directory.path),
              library: library,
              initialPath: caf,
              initialFormat: CatalogueFormat.caf,
            ),
          ),
        );
        final largest = find.byKey(const ValueKey('catalogue-row-largest.txt'));
        await _until(tester, () => largest.evaluate().isNotEmpty);
        expect(find.text('Partial or unknown source coverage'), findsOneWidget);
        expect((await library.list()).single.root, canonicalRoot);
        final search = find.byKey(const ValueKey('catalogue-search'));
        await tester.enterText(search, 'largest');
        await _until(
          tester,
          () =>
              largest.evaluate().isNotEmpty &&
              find
                  .byKey(const ValueKey('catalogue-row-small.txt'))
                  .evaluate()
                  .isEmpty,
        );
        await tester.enterText(search, '');
        final empty = find.byKey(const ValueKey('catalogue-row-empty'));
        await _until(tester, () => empty.evaluate().isNotEmpty);
        await tester.ensureVisible(empty);
        await tester.tap(empty);
        final parent = find.byKey(const ValueKey('catalogue-parent'));
        await _until(tester, () => parent.evaluate().isNotEmpty);
        await tester.tap(parent);
        await _until(tester, () => largest.evaluate().isNotEmpty);
        expect(await source.exists(), false);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 250));
        PathProviderPlatform.instance = previousPaths;
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'live CSV import creates an XLSX in the original local directory',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'crisp-live-csv-',
      );
      final original = File('${directory.path}/table.csv');
      const text = 'id,note\n00123,"hello\nworld"';
      await original.writeAsString(text, flush: true);
      try {
        await _mount(tester, directory, 'table.csv');
        final action = find.byKey(const ValueKey('viewer-import-spreadsheet'));
        await _until(tester, () => action.evaluate().isNotEmpty);
        await tester.ensureVisible(action);
        await tester.tap(action);
        await _until(
          tester,
          () => find.text('2 rows · 2 columns').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('Create XLSX copy and edit'));
        await _until(
          tester,
          () => find.byType(OfficeEditorDialog).evaluate().isNotEmpty,
        );
        final saved = File('${directory.path}/table-imported.xlsx');
        final sheet = SheetDeserializer()
            .readBytes(await saved.readAsBytes())
            .sheets
            .single;
        expect(sheet.cell(const SmlCellRef(0, 1)).value, '00123');
        expect(sheet.cell(const SmlCellRef(1, 1)).value, 'hello\nworld');
        expect(await original.readAsString(), text);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 250));
        await directory.delete(recursive: true);
      }
    },
  );
}
