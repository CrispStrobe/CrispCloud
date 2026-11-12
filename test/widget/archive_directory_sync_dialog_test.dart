import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_directory_sync_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/archive_directory_sync_service.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/widgets/archive_directory_sync_dialog.dart';
import 'package:crisp_cloud/widgets/commander_review_dialog.dart';
import 'package:crisp_cloud/widgets/directory_comparison_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_drop_fixture.dart';

Uint8List _zip(Map<String, List<int>?> files) {
  final archive = codec.Archive();
  for (final entry in files.entries) {
    archive.addFile(
      entry.value == null
          ? codec.ArchiveFile.directory(entry.key)
          : codec.ArchiveFile.bytes(entry.key, entry.value!),
    );
  }
  return Uint8List.fromList(codec.ZipEncoder().encode(archive));
}

class _SyncBackend extends LocalOperationBackend {
  _SyncBackend(String root) : super(DropTestLocal(root), isCurrent: () => true);
  bool available = true;
  Future<void> Function(FileItem, String)? beforeMove;
  @override
  bool get isCurrent => available && super.isCurrent;
  @override
  Future<bool> moveNoReplace(FileItem file, String destination) async {
    await beforeMove?.call(file, destination);
    return super.moveNoReplace(file, destination);
  }
}

class _Fixture {
  _Fixture(this.root, this.original)
    : sourceDirectory = p.join(root.path, 'input'),
      archivePath = p.join(root.path, 'output', 'work.zip'),
      source = _SyncBackend(root.path),
      destination = _SyncBackend(root.path);
  final Directory root;
  final String sourceDirectory, archivePath;
  final Uint8List original;
  final _SyncBackend source, destination;
  late FileItem archiveFile;
  final journal = ArchivePublicationJournal(
    storage: MemoryFileCollectionStorage(),
  );
}

Future<_Fixture> _fixture(WidgetTester tester, {Uint8List? archive}) async {
  final fixture = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
    final root = await Directory.systemTemp.createTemp('archive-sync-ui-');
    final fixture = _Fixture(
      root,
      archive ??
          _zip({
            'inside/equal.txt': [1, 2, 3],
            'inside/changed.txt': [8, 8, 8],
            'inside/old.txt': [5],
            'inside/obsolete/keep.txt': [6],
            'outside.txt': [9],
          }),
    );
    await Directory(fixture.sourceDirectory).create();
    await Directory(p.dirname(fixture.archivePath)).create();
    await File(p.join(fixture.sourceDirectory, 'equal.txt'))
        .writeAsBytes([1, 2, 3]);
    await File(p.join(fixture.sourceDirectory, 'changed.txt'))
        .writeAsBytes([7, 7, 7]);
    await File(p.join(fixture.sourceDirectory, 'new.txt')).writeAsBytes([4, 4]);
    await Directory(p.join(fixture.sourceDirectory, 'empty')).create();
    await Directory(p.join(fixture.sourceDirectory, 'children')).create();
    await File(p.join(fixture.sourceDirectory, 'children', 'unchecked.txt'))
        .writeAsBytes([3]);
    await File(fixture.archivePath).writeAsBytes(fixture.original);
    fixture.archiveFile = (await fixture.destination.stat(
      fixture.archivePath,
    ))!;
    return fixture;
  }))!;
  addTearDown(() => fixture.root.delete(recursive: true));
  return fixture;
}

class _Run {
  ArchiveDirectorySyncResult? result;
  bool closed = false, current = true;
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var index = 0; index < 1000 && !done(); index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    done(),
    isTrue,
    reason: [
      ...tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
      ...tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((text) => text.data),
    ].join('\n'),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Future<_Run> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  String language = 'en',
  double width = 900,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final run = _Run();
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open sync'),
            onPressed: () async {
              run.result = await showArchiveDirectorySyncDialog(
                context,
                source: fixture.source,
                sourceDirectory: fixture.sourceDirectory,
                containerBackend: fixture.destination,
                containerFile: fixture.archiveFile,
                destinationDirectory: '/inside',
                isCaptureCurrent: () => run.current,
                journal: fixture.journal,
              );
              run.closed = true;
            },
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() => tester.tap(find.text('Open sync')));
  await tester.pump();
  return run;
}

bool _idle(WidgetTester tester) =>
    find.byKey(const ValueKey('archive-sync-close')).evaluate().isNotEmpty &&
    tester
            .widget<TextButton>(
              find.byKey(const ValueKey('archive-sync-close')),
            )
            .onPressed !=
        null;

Future<void> _ready(WidgetTester tester) async {
  await _until(tester, () => _idle(tester));
  await _visible(
    tester,
    find.byKey(const ValueKey('archive-sync-select-updates')),
  );
}

Future<void> _click(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _visible(tester, finder);
  await tester.runAsync(() => tester.tap(finder));
  await tester.pump(const Duration(milliseconds: 80));
}

Future<void> _visible(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  if (finder.evaluate().isEmpty) {
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _row(WidgetTester tester, String path) async {
  final finder = find.byKey(ValueKey('archive-sync-row-$path'));
  await _visible(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _stage(WidgetTester tester) async {
  await _click(tester, 'archive-sync-stage');
  await _until(
    tester,
    () =>
        find
            .byKey(const ValueKey('archive-sync-publish'))
            .evaluate()
            .isNotEmpty &&
        _idle(tester),
  );
}

Future<void> _publish(WidgetTester tester) async {
  await _click(tester, 'archive-sync-publish');
  await _until(
    tester,
    () => find
        .byKey(const ValueKey('archive-sync-complete'))
        .evaluate()
        .isNotEmpty,
  );
}

Future<Map<String, List<int>?>> _read(
  WidgetTester tester,
  _Fixture fixture,
) async => (await tester.runAsync(() async {
  final archive = codec.ZipDecoder().decodeBytes(
    await File(fixture.archivePath).readAsBytes(),
  );
  return {
    for (final file in archive) file.name: file.isFile ? file.content : null,
  };
}))!;

Future<void> _unchanged(WidgetTester tester, _Fixture fixture) async {
  expect(
    await tester.runAsync(() => File(fixture.archivePath).readAsBytes()),
    fixture.original,
  );
}

void main() {
  testWidgets('comparison checks contents and initially keeps every member', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final run = await _mount(tester, fixture);
    await _ready(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('archive-sync-stage')),
          )
          .onPressed,
      isNull,
    );
    await _visible(
      tester,
      find.byKey(const ValueKey('archive-sync-row-old.txt')),
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('archive-sync-row-old.txt')),
          )
          .value,
      isFalse,
    );
    await _visible(
      tester,
      find.byKey(const ValueKey('archive-sync-row-changed.txt')),
    );
    expect(find.text('Changed contents\nKeep unchanged'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('archive-sync-row-equal.txt')),
      findsNothing,
    );
    await _click(tester, 'archive-sync-close');
    await _until(tester, () => run.closed);
    expect(run.result, isNull);
    await _unchanged(tester, fixture);
  });

  testWidgets(
    'selected file and empty directories publish without unchecked descendants',
    (tester) async {
      final fixture = await _fixture(tester);
      final run = await _mount(tester, fixture);
      await _ready(tester);
      await _row(tester, 'new.txt');
      await _row(tester, 'empty');
      await _row(tester, 'children');
      await _stage(tester);
      await _unchanged(tester, fixture);
      await _publish(tester);
      await tester.binding.handlePopRoute();
      await _until(tester, () => run.closed);
      expect(run.result, isNotNull);
      final archive = await _read(tester, fixture);
      expect(archive['inside/new.txt'], [4, 4]);
      expect(archive.keys, containsAll(['inside/empty/', 'inside/children/']));
      expect(archive.containsKey('inside/children/unchecked.txt'), isFalse);
      expect(archive['inside/changed.txt'], [8, 8, 8]);
      expect(archive['inside/old.txt'], [5]);
      expect(archive['outside.txt'], [9]);
      expect(
        await tester.runAsync(
          () => File(p.join(fixture.sourceDirectory, 'new.txt')).readAsBytes(),
        ),
        [4, 4],
      );
    },
  );

  testWidgets(
    'cancelling a full candidate review leaves both endpoints unchanged',
    (tester) async {
      final fixture = await _fixture(tester);
      final run = await _mount(tester, fixture);
      await _ready(tester);
      await _click(tester, 'archive-sync-select-updates');
      await _stage(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _until(tester, () => run.closed);
      expect(run.result, isNull);
      await _unchanged(tester, fixture);
      expect(
        await tester.runAsync(
          () =>
              File(p.join(fixture.sourceDirectory, 'changed.txt'))
                  .readAsBytes(),
        ),
        [7, 7, 7],
      );
    },
  );

  testWidgets(
    'turning removal permission off clears choices and bulk removal is explicit',
    (tester) async {
      final fixture = await _fixture(tester);
      final run = await _mount(tester, fixture);
      await _ready(tester);
      await _click(tester, 'archive-sync-allow-removals');
      await _row(tester, 'old.txt');
      await _click(tester, 'archive-sync-allow-removals');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('archive-sync-stage')),
            )
            .onPressed,
        isNull,
      );
      await _click(tester, 'archive-sync-allow-removals');
      await _click(tester, 'archive-sync-select-removals');
      await _stage(tester);
      await _publish(tester);
      await _click(tester, 'archive-sync-close');
      await _until(tester, () => run.closed);
      final archive = await _read(tester, fixture);
      expect(
        archive.keys.any((path) => path.startsWith('inside/obsolete')),
        isFalse,
      );
      expect(archive.containsKey('inside/old.txt'), isFalse);
      expect(archive.containsKey('inside/new.txt'), isFalse);
      expect(archive['inside/changed.txt'], [8, 8, 8]);
      expect(archive['outside.txt'], [9]);
    },
  );

  testWidgets(
    'folder removal refuses an unchecked child and keeps the plan editable',
    (tester) async {
      final fixture = await _fixture(tester);
      final run = await _mount(tester, fixture);
      await _ready(tester);
      await _click(tester, 'archive-sync-allow-removals');
      await _row(tester, 'obsolete');
      await _click(tester, 'archive-sync-stage');
      await _until(tester, () => _idle(tester));
      expect(find.byKey(const ValueKey('archive-sync-publish')), findsNothing);
      await _unchanged(tester, fixture);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('archive-sync-stage')),
            )
            .onPressed,
        isNotNull,
      );
      await _row(tester, 'obsolete/keep.txt');
      await _stage(tester);
      await _click(tester, 'archive-sync-close');
      await _until(tester, () => run.closed);
    },
  );

  testWidgets('source content changes after comparison prevent staging', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final run = await _mount(tester, fixture);
    await _ready(tester);
    await _row(tester, 'new.txt');
    await tester.runAsync(
      () =>
          File(p.join(fixture.sourceDirectory, 'new.txt')).writeAsBytes([9, 9]),
    );
    await _click(tester, 'archive-sync-stage');
    await _until(tester, () => _idle(tester));
    expect(find.byKey(const ValueKey('archive-sync-publish')), findsNothing);
    await _unchanged(tester, fixture);
    await _click(tester, 'archive-sync-close');
    await _until(tester, () => run.closed);
    expect(run.result, isNull);
  });

  testWidgets('new source entries after review prevent publication', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final run = await _mount(tester, fixture);
    await _ready(tester);
    await _click(tester, 'archive-sync-select-updates');
    await _stage(tester);
    await tester.runAsync(
      () =>
          File(p.join(fixture.sourceDirectory, 'arrived.txt'))
              .writeAsBytes([10]),
    );
    await _click(tester, 'archive-sync-publish');
    await _until(tester, () => _idle(tester));
    expect(find.byKey(const ValueKey('archive-sync-complete')), findsNothing);
    await _unchanged(tester, fixture);
    await _click(tester, 'archive-sync-close');
    await _until(tester, () => run.closed);
    expect(run.result, isNull);
  });

  testWidgets('stale captured panes cannot be published or revived', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final run = await _mount(tester, fixture);
    await _ready(tester);
    await _row(tester, 'new.txt');
    run.current = false;
    await _click(tester, 'archive-sync-stage');
    await _until(tester, () => _idle(tester));
    await _visible(
      tester,
      find.textContaining('The captured folder or archive location changed.'),
    );
    expect(
      find.textContaining('The captured folder or archive location changed.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('archive-sync-publish')), findsNothing);
    await _unchanged(tester, fixture);
    run.current = true; // The lost capture must never become current again.
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('archive-sync-stage')),
          )
          .onPressed,
      isNull,
    );
    await _click(tester, 'archive-sync-close');
    await _until(tester, () => run.closed);
  });

  testWidgets(
    'an externally replaced destination survives refused publication',
    (tester) async {
      final fixture = await _fixture(tester);
      final run = await _mount(tester, fixture);
      await _ready(tester);
      await _row(tester, 'new.txt');
      await _stage(tester);
      final external = _zip({
        'outside.txt': [11, 12],
      });
      await tester.runAsync(
        () => File(fixture.archivePath).writeAsBytes(external),
      );
      await _click(tester, 'archive-sync-publish');
      await _until(tester, () => _idle(tester));
      expect(find.byKey(const ValueKey('archive-sync-complete')), findsNothing);
      expect(
        await tester.runAsync(() => File(fixture.archivePath).readAsBytes()),
        external,
      );
      await _click(tester, 'archive-sync-close');
      await _until(tester, () => run.closed);
      expect(run.result, isNull);
    },
  );

  testWidgets(
    'file and folder conflicts block the plan until corrected and compared again',
    (tester) async {
      final fixture = await _fixture(
        tester,
        archive: _zip({
          'inside/new.txt/child.txt': [1],
          'inside/old.txt': [2],
        }),
      );
      final run = await _mount(tester, fixture);
      await _ready(tester);
      expect(
        find.text(
          'Resolve file/folder conflicts and compare again before selecting any changes.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('archive-sync-select-updates')),
            )
            .onPressed,
        isNull,
      );
      await _click(tester, 'archive-sync-close');
      await _until(tester, () => run.closed);
      await _unchanged(tester, fixture);
    },
  );

  testWidgets(
    'completed synchronization returns its receipt after direct route dismissal',
    (tester) async {
      final fixture = await _fixture(tester);
      final run = await _mount(tester, fixture);
      await _ready(tester);
      await _row(tester, 'new.txt');
      await _stage(tester);
      await _publish(tester);
      Navigator.of(tester.element(find.byType(CommanderReviewDialog))).pop();
      await _until(tester, () => run.closed);
      expect(run.result?.receipt.file.path, fixture.archivePath);
    },
  );

  testWidgets(
    'forced busy dismissal waits for settlement and preserves the actual publication outcome',
    (tester) async {
      final fixture = await _fixture(tester);
      final run = await _mount(tester, fixture);
      await _ready(tester);
      await _row(tester, 'new.txt');
      await _stage(tester);
      final entered = Completer<void>(), release = Completer<void>();
      fixture.destination.beforeMove = (file, destination) async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      await _click(tester, 'archive-sync-publish');
      await _until(tester, () => entered.isCompleted);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(run.closed, isFalse);
      Navigator.of(tester.element(find.byType(CommanderReviewDialog))).pop();
      await tester.pump(const Duration(milliseconds: 500));
      expect(run.closed, isFalse);
      release.complete();
      await _until(tester, () => run.closed);
      if (run.result case final result?) {
        expect(result.receipt.file.path, fixture.archivePath);
        expect((await _read(tester, fixture))['inside/new.txt'], [4, 4]);
      }
      final exists = await tester.runAsync(
        () => File(fixture.archivePath).exists(),
      );
      expect(
        exists == true ||
            fixture.journal.records.any((record) => !record.isFinished),
        isTrue,
      );
    },
  );

  testWidgets(
    'password cancellation leaves encrypted archive and source intact',
    (tester) async {
      final sink = koni.BytesBuilderSink();
      final writer = koni.Archive.create(
        sink,
        format: const koni.ZipWriteFormat(),
        options: const koni.ArchiveWriteOptions(password: 'secret'),
      );
      await writer.addBytes(
        koni.ArchiveEntrySpec(path: 'inside/old.txt'),
        Uint8List.fromList([1]),
      );
      await writer.close();
      await sink.close();
      final fixture = await _fixture(tester, archive: sink.takeBytes());
      final run = await _mount(tester, fixture);
      await _until(
        tester,
        () => find.text('Destination archive password').evaluate().isNotEmpty,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await _until(tester, () => _idle(tester));
      await _click(tester, 'archive-sync-close');
      await _until(tester, () => run.closed);
      expect(run.result, isNull);
      await _unchanged(tester, fixture);
    },
  );

  testWidgets(
    'recovery identifies the source folder and refuses stale-source completion',
    (tester) async {
      final fixture = await _fixture(tester);
      final first = await _mount(tester, fixture);
      await _ready(tester);
      await _row(tester, 'new.txt');
      await _stage(tester);
      fixture.destination.beforeMove = (_, _) async {
        throw StateError('Fixture publication interruption');
      };
      await _click(tester, 'archive-sync-publish');
      await _until(tester, () => _idle(tester));
      expect(
        fixture.journal.records.any((record) => !record.isFinished),
        isTrue,
      );
      await _click(tester, 'archive-sync-close');
      await _until(tester, () => first.closed);
      fixture.destination.beforeMove = null;
      await tester.runAsync(
        () =>
            File(p.join(fixture.sourceDirectory, 'arrived.txt'))
                .writeAsBytes([1]),
      );
      final second = await _mount(tester, fixture);
      await _until(
        tester,
        () =>
            find.text('Finish publication').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().length == 1,
      );
      final recovery = find.widgetWithText(
        AlertDialog,
        'Archive publication recovery',
      );
      expect(
        find.descendant(
          of: recovery,
          matching: find.text(fixture.sourceDirectory),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: recovery, matching: find.text(fixture.archivePath)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Finish publication'),
            )
            .onPressed,
        isNull,
      );
      final restore = find.widgetWithText(TextButton, 'Restore original');
      expect(tester.widget<TextButton>(restore).onPressed, isNotNull);
      await tester.ensureVisible(restore);
      await tester.pump();
      await tester.runAsync(() => tester.tap(restore));
      await _until(
        tester,
        () => find.text('Restore original').evaluate().isEmpty,
      );
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(TextButton, 'Close').last),
      );
      await _until(tester, () => _idle(tester));
      await _click(tester, 'archive-sync-close');
      await _until(tester, () => second.closed);
      expect(second.result, isNull);
      await _unchanged(tester, fixture);
    },
  );

  for (final language in [
    'en',
    'de',
    'fr',
    'es',
    'pt',
    'zh',
    'ja',
    'ko',
    'ar',
  ]) {
    testWidgets(
      '$language comparison and full review fit 320 px with 1.8 text scale',
      (tester) async {
        final fixture = await _fixture(tester);
        final run = await _mount(
          tester,
          fixture,
          language: language,
          width: 320,
          textScale: 1.8,
        );
        await _ready(tester);
        final context = tester.element(find.byType(CommanderReviewDialog));
        for (final entry in archiveDirectorySyncMessages.entries) {
          expect(entry.value.length, 9, reason: entry.key);
          if (language != 'en') {
            expect(
              archiveDirectorySyncText(context, entry.key),
              isNot(entry.value.first),
              reason: '$language:${entry.key}',
            );
          }
        }
        await _click(tester, 'archive-sync-select-updates');
        expect(tester.takeException(), isNull);
        await _stage(tester);
        expect(tester.takeException(), isNull);
        await _click(tester, 'archive-sync-close');
        await _until(tester, () => run.closed);
        await _unchanged(tester, fixture);
      },
    );
  }

  for (final archiveSide in PanelSide.values) {
    testWidgets(
      'Compare dispatches folder→archive when archive is on ${archiveSide.name}',
      (tester) async {
        final fixture = await _fixture(tester);
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              (_) => DropTestAuth(DropTestCloud('archive-sync-host')),
            ),
            localFileServiceProvider.overrideWithValue(
              DropTestLocal(fixture.root.path),
            ),
          ],
        );
        addTearDown(container.dispose);
        final archivePanel = container.read(panelProvider(archiveSide));
        final sourceSide = archiveSide == PanelSide.local
            ? PanelSide.remote
            : PanelSide.local;
        final sourcePanel = container.read(panelProvider(sourceSide));
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
          await archivePanel.navigateToPath(
            p.dirname(fixture.archivePath),
            origin: archivePanel.captureLocalClipboardOrigin(
              p.dirname(fixture.archivePath),
            ),
          );
          await sourcePanel.navigateToPath(
            fixture.sourceDirectory,
            origin: sourcePanel.captureLocalClipboardOrigin(
              fixture.sourceDirectory,
            ),
          );
          await archivePanel.enterArchive(
            archivePanel.files!.firstWhere(
              (file) => file.path == fixture.archivePath,
            ),
          );
          await archivePanel.navigateInto(
            archivePanel.files!.firstWhere((file) => file.name == 'inside'),
          );
        });
        var closed = false;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: TextButton(
                    child: const Text('Compare'),
                    onPressed: () async {
                      await showDirectoryComparisonDialog(context, ref);
                      closed = true;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() => tester.tap(find.text('Compare')));
        await _ready(tester);
        expect(find.text(fixture.sourceDirectory), findsOneWidget);
        expect(find.text(fixture.archivePath), findsOneWidget);
        await _row(tester, 'new.txt');
        await _stage(tester);
        await _publish(tester);
        await _click(tester, 'archive-sync-close');
        await _until(tester, () => closed);
        expect(
          archivePanel.files!.any((file) => file.name == 'new.txt'),
          isTrue,
        );
        expect(sourcePanel.currentPath, fixture.sourceDirectory);
        expect(
          sourcePanel.files!.any((file) => file.name == 'new.txt'),
          isTrue,
        );
      },
    );
  }
}
