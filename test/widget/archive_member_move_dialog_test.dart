import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_member_move_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/widgets/archive_member_move_dialog.dart';
import 'package:crisp_cloud/widgets/archive_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/archive_endpoint_backend.dart';
import '../support/external_drop_fixture.dart';

Uint8List _zip(Map<String, List<int>?> contents) {
  final archive = codec.Archive();
  for (final item in contents.entries) {
    archive.addFile(
      item.value == null
          ? codec.ArchiveFile.directory(item.key)
          : codec.ArchiveFile.bytes(item.key, item.value!),
    );
  }
  return Uint8List.fromList(codec.ZipEncoder().encode(archive));
}

class _Fixture {
  _Fixture(this.backend, this.workspace, this.original);
  final ArchiveEndpointTestBackend backend;
  final ArchiveWorkspace workspace;
  final Uint8List original;

  static Future<_Fixture> open({
    Map<String, List<int>?>? contents,
    bool compressedFile = false,
  }) async {
    final bytes = compressedFile
        ? Uint8List.fromList(const codec.GZipEncoder().encode([1, 2, 3]))
        : _zip(
            contents ??
                {
                  'chosen/a.txt': [1, 2],
                  'chosen/empty/': null,
                  'other.txt': [3],
                  'destination/keep.txt': [4],
                },
          );
    final name = compressedFile ? '/input/work.gz' : '/input/work.zip';
    final backend = ArchiveEndpointTestBackend()..put(name, bytes);
    final workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat(name))!,
      journal: ArchivePublicationJournal(
        storage: MemoryFileCollectionStorage(),
      ),
    );
    addTearDown(workspace.close);
    return _Fixture(backend, workspace, bytes);
  }

  List<FileItem> selected(Iterable<String> names) =>
      workspace.list().where((file) => names.contains(file.name)).toList();
}

class _DialogRun {
  ArchiveMemberMoveResult? result;
  bool finished = false;
}

Future<_DialogRun> _open(
  WidgetTester tester,
  _Fixture fixture, {
  List<FileItem>? members,
  String initialDirectory = '/',
  String locale = 'en',
  double textScale = 1,
}) async {
  final run = _DialogRun();
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
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
            onPressed: () async {
              run.result = await showArchiveMemberMoveDialog(
                context,
                workspace: fixture.workspace,
                members: members ?? fixture.selected(['chosen', 'other.txt']),
                initialDirectory: initialDirectory,
              );
              run.finished = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return run;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _makeVisible(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _makeVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('archive-member-move-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  // ensureVisible updates scroll offsets; lay out before using coordinates.
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _policy(
  WidgetTester tester,
  ArchiveMemberMoveConflict conflict,
) async {
  await _tap(tester, 'archive-member-move-conflict');
  await tester.tap(
    find.text(archiveMemberMoveMessages[conflict.name]!.first).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('stages a captured group and leaves physical bytes for review', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_Fixture.open))!;
    final run = await _open(tester, fixture);
    await _tap(tester, 'archive-member-move-folder-/destination');
    await _tap(tester, 'archive-member-move-stage');
    expect(run.finished, isTrue);
    expect(run.result!.moved, {
      '/chosen': '/destination/chosen',
      '/other.txt': '/destination/other.txt',
    });
    expect(
      fixture.workspace.list('/destination/chosen').map((file) => file.name),
      ['empty', 'a.txt'],
    );
    expect(await fixture.workspace.read('/destination/other.txt'), [3]);
    expect(fixture.workspace.dirty, isTrue);
    expect(fixture.backend.files['/input/work.zip'], fixture.original);
    expect(fixture.backend.mutations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling a folder choice keeps the draft unchanged', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_Fixture.open))!;
    final revision = fixture.workspace.revision;
    final run = await _open(tester, fixture);
    await _tap(tester, 'archive-member-move-folder-/destination');
    await _tap(tester, 'archive-member-move-cancel');
    expect(run.finished, isTrue);
    expect(run.result, isNull);
    expect(fixture.workspace.revision, revision);
    expect(fixture.workspace.dirty, isFalse);
    expect(fixture.backend.mutations, isEmpty);
  });

  testWidgets('a changed draft invalidates the displayed move selection', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_Fixture.open))!;
    final run = await _open(tester, fixture);
    await _tap(tester, 'archive-member-move-folder-/destination');
    fixture.workspace.replace('/other.txt', Uint8List.fromList([9]));
    final revision = fixture.workspace.revision;
    await _tap(tester, 'archive-member-move-stage');
    expect(run.finished, isFalse);
    expect(
      find.text(archiveMemberMoveMessages['stale']!.first),
      findsOneWidget,
    );
    expect(fixture.workspace.revision, revision);
    expect(await fixture.workspace.read('/other.txt'), [9]);
    expect(fixture.workspace.list('/destination').map((file) => file.name), [
      'keep.txt',
    ]);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('archive-member-move-stage')),
          )
          .onPressed,
      isNull,
    );
    await _tap(tester, 'archive-member-move-cancel');
  });

  testWidgets('source invalidation cannot move an old selection', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_Fixture.open))!;
    await _open(tester, fixture);
    final revision = fixture.workspace.revision;
    fixture.backend.current = false;
    await _tap(tester, 'archive-member-move-stage');
    expect(
      find.text(archiveMemberMoveMessages['stale']!.first),
      findsOneWidget,
    );
    expect(fixture.workspace.revision, revision);
    expect(fixture.backend.mutations, isEmpty);
    await _tap(tester, 'archive-member-move-cancel');
  });

  testWidgets(
    'the picker retains the original selection when caller list changes',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.open))!;
      final selected = fixture.selected(['other.txt']);
      final run = await _open(tester, fixture, members: selected);
      selected
        ..clear()
        ..addAll(fixture.selected(['chosen']));
      await _tap(tester, 'archive-member-move-folder-/destination');
      await _tap(tester, 'archive-member-move-stage');
      expect(run.result!.moved, {'/other.txt': '/destination/other.txt'});
      expect(
        fixture.workspace.list().map((file) => file.name),
        contains('chosen'),
      );
    },
  );

  testWidgets(
    'collision failure is atomic and keep both allows explicit retry',
    (tester) async {
      final fixture = (await tester.runAsync(
        () => _Fixture.open(
          contents: {
            'a.txt': [1],
            'z.txt': [2],
            'destination/z.txt': [3],
          },
        ),
      ))!;
      final revision = fixture.workspace.revision;
      final run = await _open(
        tester,
        fixture,
        members: fixture.selected(['a.txt', 'z.txt']),
      );
      await _tap(tester, 'archive-member-move-folder-/destination');
      await _tap(tester, 'archive-member-move-stage');
      expect(run.finished, isFalse);
      expect(fixture.workspace.revision, revision);
      expect(await fixture.workspace.read('/a.txt'), [1]);
      expect(find.textContaining('Move could not be staged:'), findsOneWidget);
      await _policy(tester, ArchiveMemberMoveConflict.keepBoth);
      await _tap(tester, 'archive-member-move-stage');
      expect(run.result!.moved, {
        '/a.txt': '/destination/a.txt',
        '/z.txt': '/destination/z (2).txt',
      });
      expect(await fixture.workspace.read('/destination/z.txt'), [3]);
      expect(await fixture.workspace.read('/destination/z (2).txt'), [2]);
      expect(fixture.backend.mutations, isEmpty);
    },
  );

  testWidgets('skip keeps conflicting roots and moves other selected items', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _Fixture.open(
        contents: {
          'a.txt': [1],
          'folder/empty/': null,
          'destination/folder/keep.txt': [3],
        },
      ),
    ))!;
    final run = await _open(
      tester,
      fixture,
      members: fixture.selected(['a.txt', 'folder']),
    );
    await _tap(tester, 'archive-member-move-folder-/destination');
    await _policy(tester, ArchiveMemberMoveConflict.skip);
    await _tap(tester, 'archive-member-move-stage');
    expect(run.result!.skipped, ['/folder']);
    expect(run.result!.moved, {'/a.txt': '/destination/a.txt'});
    expect(fixture.workspace.list('/folder').single.name, 'empty');
    expect(await fixture.workspace.read('/destination/folder/keep.txt'), [3]);
  });

  testWidgets('selected folders cannot be entered as move destinations', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_Fixture.open))!;
    await _open(tester, fixture);
    final selectedFolder = find.byKey(
      const ValueKey('archive-member-move-folder-/chosen'),
    );
    await _makeVisible(tester, selectedFolder);
    expect(tester.widget<ListTile>(selectedFolder).onTap, isNull);
    expect(
      find.text(archiveMemberMoveMessages['blocked']!.first),
      findsOneWidget,
    );
    await _tap(tester, 'archive-member-move-cancel');

    await _open(tester, fixture, initialDirectory: '/chosen/empty');
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('archive-member-move-stage')),
          )
          .onPressed,
      isNull,
    );
    await _tap(tester, 'archive-member-move-root');
    await _makeVisible(
      tester,
      find.byKey(const ValueKey('archive-member-move-folder-/destination')),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('archive-member-move-stage')),
          )
          .onPressed,
      isNotNull,
    );
    await _tap(tester, 'archive-member-move-cancel');
    expect(fixture.workspace.dirty, isFalse);
  });

  testWidgets('root and up navigate existing implicit and empty folders', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_Fixture.open))!;
    await _open(tester, fixture, members: fixture.selected(['other.txt']));
    await _tap(tester, 'archive-member-move-folder-/chosen');
    await _tap(tester, 'archive-member-move-folder-/chosen/empty');
    expect(find.text('No subfolders here.'), findsOneWidget);
    await _tap(tester, 'archive-member-move-up');
    expect(
      find.byKey(const ValueKey('archive-member-move-folder-/chosen/empty')),
      findsOneWidget,
    );
    await _tap(tester, 'archive-member-move-root');
    await _makeVisible(
      tester,
      find.byKey(const ValueKey('archive-member-move-folder-/destination')),
    );
    expect(
      find.byKey(const ValueKey('archive-member-move-folder-/destination')),
      findsOneWidget,
    );
    await _tap(tester, 'archive-member-move-cancel');
  });

  testWidgets('same parent selection returns an unchanged outcome', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_Fixture.open))!;
    final revision = fixture.workspace.revision;
    final run = await _open(
      tester,
      fixture,
      members: fixture.selected(['other.txt']),
    );
    await _tap(tester, 'archive-member-move-stage');
    expect(run.result!.unchanged, ['/other.txt']);
    expect(run.result!.moved, isEmpty);
    expect(fixture.workspace.revision, revision);
    expect(fixture.workspace.dirty, isFalse);
  });

  testWidgets('a single compressed payload offers no move action', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _Fixture.open(compressedFile: true),
    ))!;
    await _open(tester, fixture, members: fixture.workspace.list());
    expect(
      find.text(archiveMemberMoveMessages['unsupported']!.first),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('archive-member-move-stage')),
          )
          .onPressed,
      isNull,
    );
    await _tap(tester, 'archive-member-move-cancel');
    expect(fixture.workspace.dirty, isFalse);
  });

  for (final locale in ['en', 'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
    testWidgets('move picker fits narrow large text in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = (await tester.runAsync(_Fixture.open))!;
      final run = await _open(tester, fixture, locale: locale, textScale: 1.8);
      final index = [
        'en',
        'de',
        'fr',
        'es',
        'pt',
        'zh',
        'ja',
        'ko',
        'ar',
      ].indexOf(locale);
      expect(
        find.text(archiveMemberMoveMessages['title']![index]),
        findsOneWidget,
      );
      await _tap(tester, 'archive-member-move-conflict');
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.text(archiveMemberMoveMessages['skip']![index]).last,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('archive-member-move-folder-/destination')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('archive-member-move-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await _tap(tester, 'archive-member-move-folder-/destination');
      await _tap(tester, 'archive-member-move-cancel');
      expect(run.result, isNull);
      expect(fixture.workspace.dirty, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'workspace action stages, reviews and publishes one native archive',
    (tester) async {
      late Directory directory;
      late String archivePath;
      late Uint8List original;
      late ProviderContainer container;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await InstallationIdentityService.instance.initialize();
        directory = await Directory.systemTemp.createTemp(
          'archive-member-move-',
        );
        archivePath = p.join(directory.path, 'work.zip');
        original = _zip({
          'chosen.txt': [1, 2],
          'destination/keep.txt': [3],
        });
        await File(archivePath).writeAsBytes(original);
        container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              (_) => DropTestAuth(DropTestCloud('move-ui')),
            ),
            localFileServiceProvider.overrideWithValue(
              DropTestLocal(directory.path),
            ),
          ],
        );
        final panel = container.read(panelProvider(PanelSide.local));
        await Future<void>.delayed(Duration.zero);
        await panel.navigateToPath(
          directory.path,
          origin: panel.captureLocalClipboardOrigin(directory.path),
        );
        await panel.enterArchive(
          panel.files!.firstWhere((file) => file.path == archivePath),
        );
        panel.toggleSelection(
          panel.files!.firstWhere((file) => file.name == 'chosen.txt'),
        );
      });
      addTearDown(() async {
        container.dispose();
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showCurrentArchiveWorkspaceDialog(
                    context,
                    ref,
                    PanelSide.local,
                  ),
                  child: const Text('Open workspace'),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> until(bool Function() done) async {
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          while (!done() && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 15));
            await tester.pump(const Duration(milliseconds: 16));
          }
        });
        expect(
          done(),
          isTrue,
          reason: [
            ...tester
                .widgetList<Text>(find.byType(Text))
                .map((text) => text.data),
            ...tester
                .widgetList<SelectableText>(find.byType(SelectableText))
                .map((text) => text.data),
          ].join('\n'),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(find.text('Open workspace'));
      await until(() {
        final action = find.byKey(
          const ValueKey('archive-workspace-move-within'),
        );
        return action.evaluate().isNotEmpty &&
            tester.widget<TextButton>(action).onPressed != null;
      });
      // The workspace holds its busy guard while this modal is open. Its
      // underlying progress indicator deliberately remains animated.
      Future<void> tapModal(String key) async {
        final target = find.byKey(ValueKey(key));
        await _makeVisible(tester, target);
        await tester.tap(target);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tapModal('archive-workspace-move-within');
      await tapModal('archive-member-move-folder-/destination');
      await tapModal('archive-member-move-stage');
      expect(find.textContaining('Staged 1 item(s)'), findsOneWidget);
      expect(
        await tester.runAsync(() => File(archivePath).readAsBytes()),
        original,
      );
      await tester.runAsync(() => tester.tap(find.text('Save archive')));
      await until(
        () => find.text('Publish verified archive').evaluate().isNotEmpty,
      );
      await tester.ensureVisible(find.text('Publish verified archive'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => tester.tap(find.text('Publish verified archive')),
      );
      await until(
        () =>
            find.text('Archive published and verified.').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Close').last);
      await until(
        () => find.text('Archive saved and verified.').evaluate().isNotEmpty,
      );
      final saved = (await tester.runAsync(
        () => File(archivePath).readAsBytes(),
      ))!;
      final decoded = codec.ZipDecoder().decodeBytes(saved);
      expect(decoded.findFile('chosen.txt'), isNull);
      expect(decoded.findFile('destination/chosen.txt')!.content, [1, 2]);
      expect(decoded.findFile('destination/keep.txt')!.content, [3]);
      await tester.tap(find.byTooltip('Close archive'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );
}
