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
import 'package:crisp_cloud/services/local_file_service_native.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/hex_viewer.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
