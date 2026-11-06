import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/directory_comparison_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';
import 'package:crisp_cloud/widgets/archive_workspace_dialog.dart';
import 'package:crisp_cloud/widgets/directory_comparison_dialog.dart';
import 'package:crisp_cloud/widgets/diff_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/integrity_dialogs.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/sync_plan_dialog.dart';
import 'package:crisp_cloud/widgets/sync_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  @override
  CloudProvider get currentProvider => CloudProvider.sftp;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pair extends Fake implements SyncPair {
  @override
  int get id => 1;
  @override
  String get name => 'Keep {1} filenames';
  @override
  String get localPath => '/local';
  @override
  String get remotePath => '/cloud';
  @override
  String get provider => 'sftp';
  @override
  bool get enabled => true;
  @override
  bool get usePlaceholders => false;
  @override
  DateTime? get lastSyncAt => null;
}

class _Plan extends Fake implements SyncPlan {
  @override
  final pair = _Pair();
  @override
  final actions = [
    SyncAction(type: SyncActionType.conflict, relativePath: 'Cancel {1}.txt'),
  ];
  @override
  List<SyncActionType> choicesFor(SyncAction action) => [
    SyncActionType.conflict,
    SyncActionType.skip,
    SyncActionType.upload,
    SyncActionType.download,
    SyncActionType.keepBoth,
  ];
}

class _Sync extends ChangeNotifier implements SyncNotifier {
  @override
  List<SyncPair> get pairs => [_Pair()];
  @override
  bool get isWatchEnabled => false;
  @override
  bool get isSyncing => false;
  @override
  SyncResult? get lastResult => null;
  @override
  bool get isBackgroundSyncEnabled => false;
  @override
  int get backgroundSyncIntervalMinutes => 15;
  @override
  int get autoEvictDays => 0;
  @override
  bool isPairBound(SyncPair pair) => true;
  @override
  Future<SyncPlan> planOne(
    int pairId, {
    bool Function()? isCancelled,
    bool compareContents = false,
    void Function(int completed, int total, String path)? onCompareProgress,
  }) async => _Plan();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late WorkflowFakeClient cloud;
  late ProviderContainer container;
  late PanelNotifier panel;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('Cancel {1}.txt', 'content'.codeUnits));
    cloud = WorkflowFakeClient()
      ..put('/Cancel {1}.txt', 'content\n'.codeUnits)
      ..put('/work.zip', ZipEncoder().encode(archive));
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
        syncProvider.overrideWith((_) => _Sync()),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
  });
  tearDown(() => container.dispose());

  FileItem file(String name) =>
      panel.files!.firstWhere((item) => item.name == name);
  String tr(String language, String source) =>
      CommanderStrings.forLanguage(language, source);

  Future<void> open(
    WidgetTester tester,
    String language,
    void Function(BuildContext, WidgetRef) action,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => action(context, ref),
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
  }

  for (final language in ['de', 'ar']) {
    testWidgets('merge controls remain reachable with large $language text', (
      tester,
    ) async {
      cloud.put('/right.txt', 'changed\n'.codeUnits);
      await panel.refresh();
      await open(
        tester,
        language,
        (context, ref) => showDiffViewerDialog(
          context,
          ref,
          file('Cancel {1}.txt'),
          file('right.txt'),
          leftSide: PanelSide.remote,
          rightSide: PanelSide.remote,
        ),
      );
      final useLeft = find.text(tr(language, 'Use left block'));
      await tester.ensureVisible(useLeft);
      await tester.tap(useLeft);
      await tester.pumpAndSettle();
      expect(find.text(tr(language, 'Unsaved merge')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(cloud.writes, isEmpty);
    });

    testWidgets('split options remain reachable with large $language text', (
      tester,
    ) async {
      await open(
        tester,
        language,
        (context, ref) => showSplitFileDialog(
          context,
          ref,
          PanelSide.remote,
          file('Cancel {1}.txt'),
        ),
      );
      expect(find.textContaining('Cancel {1}.txt'), findsWidgets);
      await tester.ensureVisible(find.text(tr(language, 'Split and verify')));
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(cloud.writes, isEmpty);
    });
    testWidgets('sync manager controls fit large $language text', (
      tester,
    ) async {
      await open(tester, language, (context, _) => showSyncDialog(context));
      await tester.ensureVisible(find.text(tr(language, 'Add Pair')));
      await tester.tap(find.text(tr(language, 'Add Pair')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final policy = find.byType(DropdownButtonFormField<ConflictPolicy>);
      await tester.ensureVisible(policy);
      await tester.tap(policy);
      await tester.pumpAndSettle();
      expect(find.text(tr(language, 'Newest Wins')), findsWidgets);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'directory review fits large $language text and preserves paths',
      (tester) async {
        cloud.put('/left/Cancel {1}.txt', 'left'.codeUnits);
        cloud.directories.add('/right');
        final left = container.read(panelProvider(PanelSide.local));
        await tester.pump();
        for (final side in PanelSide.values) {
          container
              .read(panelSourceProvider(side).notifier)
              .setSource(
                RemotePanelSource(
                  providerName: cloud.providerName,
                  client: cloud,
                  path: side == PanelSide.local ? '/left' : '/right',
                ),
              );
        }
        await left.refresh();
        await panel.refresh();
        await open(
          tester,
          language,
          (context, ref) => showDirectoryComparisonDialog(context, ref),
        );
        final action = find.byKey(
          const ValueKey('compare-action-Cancel {1}.txt'),
        );
        await tester.scrollUntilVisible(
          action,
          150,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Cancel {1}.txt'), findsOneWidget);
        expect(find.text(tr(language, 'Only left')), findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.tap(find.text(tr(language, 'Left → Right')).last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButtonFormField<DirectoryComparisonAction>>(
                action,
              )
              .initialValue,
          DirectoryComparisonAction.copyToRight,
        );
        expect(tester.takeException(), isNull);
        expect(cloud.writes, isEmpty);
      },
    );

    testWidgets(
      'sync review actions remain reachable with large $language text',
      (tester) async {
        await open(
          tester,
          language,
          (context, _) => showSyncPlanDialog(context, 1),
        );
        final action = find.byKey(const ValueKey('sync-action-Cancel {1}.txt'));
        await tester.scrollUntilVisible(
          action,
          150,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Cancel {1}.txt'), findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.tap(find.text(tr(language, 'Keep both versions')).last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButtonFormField<SyncActionType>>(action)
              .initialValue,
          SyncActionType.keepBoth,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('archive members and commands fit large $language text', (
      tester,
    ) async {
      await open(
        tester,
        language,
        (context, ref) => showArchiveWorkspaceDialog(
          context,
          ref,
          PanelSide.remote,
          file('work.zip'),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Cancel {1}.txt'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).value,
        isTrue,
      );
      expect(find.text(tr(language, 'Save archive')), findsOneWidget);
      await tester.tap(find.text(tr(language, 'Close')));
      await tester.pumpAndSettle();
      expect(cloud.writes, isEmpty);
    });

    testWidgets('viewer search and goto work with large $language text', (
      tester,
    ) async {
      await open(
        tester,
        language,
        (context, _) => showInternalViewer(
          context,
          file: file('Cancel {1}.txt'),
          side: PanelSide.remote,
        ),
      );
      expect(find.text('Cancel {1}.txt'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, 'content');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text(tr(language, 'Go to line')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(tr(language, 'Cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'checksum results fit large $language text and preserve filenames',
      (tester) async {
        await open(
          tester,
          language,
          (context, ref) => showChecksumToolsDialog(
            context,
            ref,
            PanelSide.remote,
            [file('Cancel {1}.txt')],
          ),
        );
        await tester.ensureVisible(find.text(tr(language, 'Calculate')));
        await tester.tap(find.text(tr(language, 'Calculate')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Cancel {1}.txt'), findsOneWidget);
        expect(
          find.text(
            CommanderStrings.forLanguage(
              language,
              'Calculated {0} {1} checksum(s).',
              [1, 'SHA-256'],
            ),
          ),
          findsOneWidget,
        );
      },
    );
  }
}
