import 'dart:io';

import 'package:crisp_cloud/widgets/csv_spreadsheet_import_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/integrity_dialogs.dart';
import 'package:crisp_cloud/widgets/preview_pane.dart';
import 'package:crisp_cloud/widgets/file_context_menu.dart'
    show showPropertiesDialog;
import 'package:crisp_cloud/l10n/app_localizations.dart';

import '../support/workflow_fake_client.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/landing';
  @override
  String? get grantedBasePath => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final WorkflowFakeClient client;
  @override
  bool get isConnected => client.current;
  @override
  String? userEmail = 'fixture@example.test';
  @override
  String get providerName => client.providerName;
  void disconnect() {
    client.current = false;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late WorkflowFakeClient cloud;
  late _Auth auth;
  late ProviderContainer container;
  late PanelNotifier panel;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = WorkflowFakeClient()
      ..put('/a.txt', 'first file\n'.codeUnits)
      ..put('/b.txt', 'unselected\n'.codeUnits)
      ..put('/c.txt', 'third file\n'.codeUnits)
      ..put('/blob.bin', [0, 1, 2])
      ..put('/table.csv', 'id,name\n001,test'.codeUnits);
    auth = _Auth(cloud);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
  });
  tearDown(() => container.dispose());

  FileItem item(String name) =>
      panel.files!.firstWhere((file) => file.name == name);

  testWidgets(
    'CSV viewer creates a verified copy and opens the Quds spreadsheet editor',
    (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: InternalViewerDialog(
              file: item('table.csv'),
              side: PanelSide.remote,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('viewer-import-spreadsheet'));
      expect(action, findsOneWidget);
      await tester.ensureVisible(action);
      await tester.tap(action);
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.text('2 rows · 2 columns').evaluate().isNotEmpty) break;
      }
      expect(find.byType(CsvSpreadsheetImportDialog), findsOneWidget);
      expect(find.text('2 rows · 2 columns'), findsOneWidget);
      expect(cloud.writes, isEmpty);
      await tester.tap(find.text('Create XLSX copy and edit'));
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(OfficeEditorDialog).evaluate().isNotEmpty) break;
      }
      expect(find.byType(OfficeEditorDialog), findsOneWidget);
      await tester.pumpAndSettle();
      final original = cloud.files['/table.csv']!;
      expect(String.fromCharCodes(original), 'id,name\n001,test');
      final sheet = SheetDeserializer()
          .readBytes(cloud.files['/table-imported.xlsx']!)
          .sheets
          .single;
      expect(sheet.cell(const SmlCellRef(0, 1)).value, '001');
      expect(find.textContaining('table-imported.xlsx'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 150));
    },
  );

  testWidgets(
    'navigation keeps only selected files and edits the displayed file',
    (tester) async {
      panel.toggleSelection(item('a.txt'));
      panel.toggleSelection(item('c.txt'), ctrlKey: true);
      late Future<InternalViewerAction> result;
      FileItem? viewed;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    result = showInternalViewer(
                      context,
                      file: item('a.txt'),
                      side: PanelSide.remote,
                      onFileChanged: (file) => viewed = file,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.byTooltip('Edit (F4)'), findsOneWidget);
      await tester.tap(find.byTooltip('Next file (Alt+Right)'));
      await tester.pumpAndSettle();
      expect(find.text('c.txt'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(viewed, same(item('c.txt')));
      await tester.tap(find.byTooltip('Edit (F4)'));
      await tester.pumpAndSettle();
      expect(await result, InternalViewerAction.edit);
    },
  );

  testWidgets(
    'reload and follow use fresh bytes and stop on captured account loss',
    (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: InternalViewerDialog(
              file: item('a.txt'),
              side: PanelSide.remote,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      cloud.put('/a.txt', 'reloaded text\n'.codeUnits);
      await tester.tap(find.byTooltip('Reload (F5)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reloaded text'), findsWidgets);
      await tester.tap(find.byTooltip('Follow end of file'));
      await tester.pumpAndSettle();
      cloud.put('/a.txt', 'reloaded text\nnew line\n'.codeUnits);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('new line'), findsWidgets);
      auth.disconnect();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('source changed'), findsWidgets);
      expect(find.byTooltip('Edit (F4)'), findsNothing);
    },
  );

  testWidgets(
    'a remote file in the left pane uses its actual captured source',
    (tester) async {
      final left = container.read(panelProvider(PanelSide.local));
      await tester.pump();
      container
          .read(panelSourceProvider(PanelSide.local).notifier)
          .setSource(
            RemotePanelSource(
              providerName: cloud.providerName,
              client: cloud,
              path: '/',
            ),
          );
      await left.refresh();
      final listed = left.files!.firstWhere((file) => file.name == 'a.txt');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: InternalViewerDialog(file: listed, side: PanelSide.local),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('first file'), findsWidgets);
      expect(find.byTooltip('Edit (F4)'), findsOneWidget);
    },
  );

  testWidgets('unverified row copies and binary formats do not expose Edit', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: InternalViewerDialog(
            file: item('a.txt').copyWith(),
            side: PanelSide.remote,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('original viewer source is unavailable'),
      findsWidgets,
    );
    expect(find.byTooltip('Edit (F4)'), findsNothing);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: InternalViewerDialog(
            key: const ValueKey('binary'),
            file: item('blob.bin'),
            side: PanelSide.remote,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit (F4)'), findsOneWidget);
  });
  testWidgets(
    'captured cloud checksum and split dialogs produce verified outputs',
    (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => showChecksumToolsDialog(
                        context,
                        ref,
                        PanelSide.remote,
                        [item('a.txt')],
                      ),
                      child: const Text('Checksums'),
                    ),
                    TextButton(
                      onPressed: () => showSplitFileDialog(
                        context,
                        ref,
                        PanelSide.remote,
                        item('a.txt'),
                      ),
                      child: const Text('Split'),
                    ),
                    TextButton(
                      onPressed: () => showCombinePartsDialog(
                        context,
                        ref,
                        PanelSide.remote,
                        [item('a.txt.split.json')],
                      ),
                      child: const Text('Combine'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Checksums'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calculate'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Calculated 1 SHA-256'), findsOneWidget);
      await tester.tap(find.text('Create checksum file'));
      await tester.pumpAndSettle();
      expect(cloud.files.containsKey('/checksums.sha256'), true);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split and verify'));
      for (
        var attempt = 0;
        attempt < 100 && find.text('Close').evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(cloud.files.containsKey('/a.txt.split.json'), true);
      expect(cloud.files['/a.txt.part001'], cloud.files['/a.txt']);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Combine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify and combine'));
      for (
        var attempt = 0;
        attempt < 100 && find.text('Close').evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(cloud.files['/a.txt.combined'], cloud.files['/a.txt']);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'preview reloads fresh row identity and Properties hashes its captured cloud source',
    (tester) async {
      Widget app(FileItem file) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => showPropertiesDialog(context, file),
                    child: const Text('Properties'),
                  ),
                  Expanded(
                    child: PreviewPane(file: file, side: PanelSide.remote),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(item('a.txt')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('first file', findRichText: true),
        findsWidgets,
      );
      cloud.put('/a.txt', 'updated preview'.codeUnits);
      await panel.refresh();
      await tester.pumpWidget(app(item('a.txt')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('updated preview', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining('first file', findRichText: true),
        findsNothing,
      );
      await tester.tap(find.text('Properties'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Compute MD5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compute MD5'));
      await tester.pumpAndSettle();
      expect(find.text('MD5'), findsOneWidget);
      expect(find.textContaining('Error:'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'checksum dialog stays usable in a narrow window with enlarged text',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => showChecksumToolsDialog(
                    context,
                    ref,
                    PanelSide.remote,
                    [item('a.txt')],
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Calculate'));
      await tester.tap(find.text('Calculate'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Close'));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );
}
