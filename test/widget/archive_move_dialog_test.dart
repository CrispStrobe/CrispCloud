import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_endpoint_strings.dart';
import 'package:crisp_cloud/l10n/archive_transfer_strings.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/widgets/archive_endpoint_dialog.dart';
import 'package:flutter/material.dart';
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

Future<Uint8List> _protected(
  Map<String, List<int>> files,
  String password,
) async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: const koni.ZipWriteFormat(),
    options: koni.ArchiveWriteOptions(password: password),
  );
  for (final entry in files.entries) {
    await writer.addBytes(
      koni.ArchiveEntrySpec(path: entry.key),
      Uint8List.fromList(entry.value),
    );
  }
  await writer.close();
  await sink.close();
  return sink.takeBytes();
}

class _MoveBackend extends LocalOperationBackend {
  _MoveBackend(String root) : super(DropTestLocal(root), isCurrent: () => true);

  bool available = true;
  FutureOr<void> Function(FileItem file, String destination)? beforeMove;
  FutureOr<void> Function(FileItem file, String destination)? afterMove;

  @override
  bool get isCurrent => available && super.isCurrent;

  @override
  Future<bool> moveNoReplace(FileItem file, String destination) async {
    await beforeMove?.call(file, destination);
    final moved = await super.moveNoReplace(file, destination);
    if (moved) await afterMove?.call(file, destination);
    return moved;
  }
}

class _Fixture {
  _Fixture(this.directory, this.sourceBytes, this.destinationBytes)
    : sourcePath = p.join(directory.path, 'source.zip'),
      destinationPath = p.join(directory.path, 'destination.zip'),
      source = _MoveBackend(directory.path),
      destination = _MoveBackend(directory.path);

  final Directory directory;
  final String sourcePath, destinationPath;
  final Uint8List sourceBytes, destinationBytes;
  final _MoveBackend source, destination;
  final journal = ArchivePublicationJournal(
    storage: MemoryFileCollectionStorage(),
  );
  late FileItem sourceFile, destinationFile;
}

Future<_Fixture> _fixture(
  WidgetTester tester, {
  Uint8List? sourceBytes,
  Uint8List? destinationBytes,
}) async {
  final fixture = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
    final directory = await Directory.systemTemp.createTemp('archive-move-ui-');
    final fixture = _Fixture(
      directory,
      sourceBytes ??
          _zip({
            'chosen/new.txt': [7, 8, 9],
            'chosen/empty/': null,
            'unselected.txt': [4],
          }),
      destinationBytes ??
          _zip({
            'keep.txt': [1],
          }),
    );
    await File(fixture.sourcePath).writeAsBytes(fixture.sourceBytes);
    await File(fixture.destinationPath).writeAsBytes(fixture.destinationBytes);
    fixture.sourceFile = (await fixture.source.stat(fixture.sourcePath))!;
    fixture.destinationFile = (await fixture.destination.stat(
      fixture.destinationPath,
    ))!;
    return fixture;
  }))!;
  addTearDown(() => fixture.directory.delete(recursive: true));
  return fixture;
}

class _DialogRun {
  ArchiveEndpointTransferResult? result;
  bool closed = false;
  late BuildContext context;
}

Future<_DialogRun> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  List<FileItem>? files,
  String locale = 'en',
  double textScale = 1,
  List<String> sourceNestedMembers = const [],
  ArchiveWorkspace? borrowed,
}) async {
  final run = _DialogRun();
  final selected =
      files ?? [FileItem(name: 'chosen', path: '/chosen', isFolder: true)];
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
        builder: (context) {
          run.context = context;
          return Scaffold(
            body: TextButton(
              onPressed: () async {
                run.result = borrowed == null
                    ? await showArchiveEndpointMoveDialog(
                        context,
                        sourceContainerBackend: fixture.source,
                        sourceContainerFile: fixture.sourceFile,
                        sourceNestedMembers: sourceNestedMembers,
                        files: selected,
                        containerBackend: fixture.destination,
                        containerFile: fixture.destinationFile,
                        journal: fixture.journal,
                      )
                    : await showArchiveWorkspaceMoveDialog(
                        context,
                        borrowed,
                        files: selected,
                        containerBackend: fixture.destination,
                        containerFile: fixture.destinationFile,
                        journal: fixture.journal,
                      );
                run.closed = true;
              },
              child: const Text('Open move'),
            ),
          );
        },
      ),
    ),
  );
  return run;
}

bool _text(String value) => find.text(value).evaluate().isNotEmpty;

Future<void> _until(WidgetTester tester, bool Function() done) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
  });
  expect(done(), isTrue);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _activate(
  WidgetTester tester,
  String action,
  bool Function() done,
) async {
  await tester.ensureVisible(find.text(action));
  await tester.pump();
  await tester.runAsync(() => tester.tap(find.text(action)));
  await _until(tester, done);
}

Future<void> _review(WidgetTester tester, _DialogRun run) async {
  final stage = archiveTransferText(run.context, 'stage');
  final review = archiveTransferText(run.context, 'review');
  await _activate(tester, 'Open move', () => _text(stage));
  await _activate(tester, stage, () => _text(review));
  expect(
    find.text(archiveTransferText(run.context, 'destinationReview')),
    findsOneWidget,
  );
  expect(
    find.text(archiveTransferText(run.context, 'sourceReview')),
    findsOneWidget,
  );
}

Future<void> _expectOriginals(WidgetTester tester, _Fixture fixture) async {
  await tester.runAsync(() async {
    expect(await File(fixture.sourcePath).readAsBytes(), fixture.sourceBytes);
    expect(
      await File(fixture.destinationPath).readAsBytes(),
      fixture.destinationBytes,
    );
  });
}

void main() {
  const desktop = TargetPlatformVariant({TargetPlatform.linux});

  testWidgets(
    'closing both reviews leaves the physical archives and borrowed source unchanged',
    (tester) async {
      final fixture = await _fixture(tester);
      final workspace = (await tester.runAsync(
        () => ArchiveWorkspace.open(
          fixture.source,
          fixture.sourceFile,
          journal: fixture.journal,
        ),
      ))!;
      addTearDown(workspace.close);
      final revision = workspace.revision;
      final run = await _mount(tester, fixture, borrowed: workspace);
      await _review(tester, run);
      await _expectOriginals(tester, fixture);
      expect(workspace.dirty, isFalse);
      expect(workspace.revision, revision);
      await _activate(tester, 'Close', () => run.closed);
      expect(run.result, isNull);
      expect(workspace.isCurrent, isTrue);
      expect(await workspace.read('/chosen/new.txt'), [7, 8, 9]);
      await _expectOriginals(tester, fixture);
      expect(fixture.journal.records, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'publishing a reviewed move preserves unrelated members and empty folders',
    (tester) async {
      final fixture = await _fixture(tester);
      final run = await _mount(tester, fixture);
      await _review(tester, run);
      await _expectOriginals(tester, fixture);
      await _activate(
        tester,
        'Publish reviewed move',
        () => _text(archiveTransferMessages['published']!.first),
      );
      expect(find.text('Archive published and verified.'), findsNothing);
      await tester.runAsync(() => tester.binding.handlePopRoute());
      await _until(tester, () => run.closed);
      final result = run.result! as ArchiveEndpointMoveResult;
      expect(result.disposition, ArchiveMoveDisposition.moved);
      expect(result.sourceReceipt, isNotNull);
      expect(result.removedSources, 1);
      await tester.runAsync(() async {
        final source = codec.ZipDecoder().decodeBytes(
          await File(fixture.sourcePath).readAsBytes(),
        );
        final destination = codec.ZipDecoder().decodeBytes(
          await File(fixture.destinationPath).readAsBytes(),
        );
        expect(source.findFile('chosen/new.txt'), isNull);
        expect(source.findFile('chosen/empty/'), isNull);
        expect(source.findFile('unselected.txt')?.content, [4]);
        expect(destination.findFile('chosen/new.txt')?.content, [7, 8, 9]);
        expect(destination.findFile('chosen/empty/')?.isFile, isFalse);
        expect(destination.findFile('keep.txt')?.content, [1]);
      });
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'skipped conflicts stay in the source while other reviewed members move',
    (tester) async {
      final fixture = await _fixture(
        tester,
        destinationBytes: _zip({
          'new.txt': [99],
          'keep.txt': [1],
        }),
      );
      final run = await _mount(
        tester,
        fixture,
        files: [
          FileItem(name: 'new.txt', path: '/chosen/new.txt', isFolder: false),
          FileItem(
            name: 'unselected.txt',
            path: '/unselected.txt',
            isFolder: false,
          ),
        ],
      );
      await _activate(tester, 'Open move', () => _text('Prepare both reviews'));
      final conflict = find.byType(DropdownButtonFormField<FileConflictPolicy>);
      await tester.ensureVisible(conflict);
      await tester.pump();
      await tester.tap(conflict);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => tester.tap(find.text('Skip existing files').last),
      );
      await tester.pump();
      await _until(
        tester,
        () =>
            _text('Prepare both reviews') &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      await _activate(
        tester,
        'Prepare both reviews',
        () => _text('Review both archives'),
      );
      expect(find.text('/chosen/new.txt'), findsOneWidget);
      expect(
        find.text('Source paths not removed by this move: 1.'),
        findsOneWidget,
      );
      await _expectOriginals(tester, fixture);
      await _activate(
        tester,
        'Publish reviewed move',
        () => _text(archiveTransferMessages['published']!.first),
      );
      await _activate(tester, 'Close', () => run.closed);
      final result = run.result! as ArchiveEndpointMoveResult;
      expect(result.disposition, ArchiveMoveDisposition.moved);
      expect(result.retainedSources, contains('/chosen/new.txt'));
      await tester.runAsync(() async {
        final source = codec.ZipDecoder().decodeBytes(
          await File(fixture.sourcePath).readAsBytes(),
        );
        final destination = codec.ZipDecoder().decodeBytes(
          await File(fixture.destinationPath).readAsBytes(),
        );
        expect(source.findFile('chosen/new.txt')?.content, [7, 8, 9]);
        expect(source.findFile('unselected.txt'), isNull);
        expect(destination.findFile('new.txt')?.content, [99]);
        expect(destination.findFile('unselected.txt')?.content, [4]);
        expect(destination.findFile('keep.txt')?.content, [1]);
      });
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'a verified destination with unavailable source is reported as an incomplete move',
    (tester) async {
      final fixture = await _fixture(tester);
      fixture.destination.afterMove = (file, destination) {
        if (destination == fixture.destinationPath) {
          fixture.source.available = false;
        }
      };
      final run = await _mount(tester, fixture);
      await _review(tester, run);
      await _activate(
        tester,
        'Publish reviewed move',
        () => _text(archiveTransferMessages['retained']!.first),
      );
      expect(
        find.text(archiveTransferMessages['published']!.first),
        findsNothing,
      );
      expect(find.text('Archive published and verified.'), findsNothing);
      // A caller can pop a route directly without its Close action or
      // PopScope callback. The completed partial outcome must still return.
      await tester.runAsync(() async => Navigator.of(run.context).pop());
      await _until(tester, () => run.closed);
      final result = run.result! as ArchiveEndpointMoveResult;
      expect(result.disposition, ArchiveMoveDisposition.destinationOnly);
      expect(result.sourceReceipt, isNull);
      expect(result.removedSources, 0);
      await tester.runAsync(() async {
        expect(
          await File(fixture.sourcePath).readAsBytes(),
          fixture.sourceBytes,
        );
        final destination = codec.ZipDecoder().decodeBytes(
          await File(fixture.destinationPath).readAsBytes(),
        );
        expect(destination.findFile('chosen/new.txt')?.content, [7, 8, 9]);
      });
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'interrupted source installation shows recovery without claiming source retention or completion',
    (tester) async {
      final fixture = await _fixture(tester);
      fixture.source.beforeMove = (file, destination) {
        if (destination == fixture.sourcePath) {
          throw StateError('Injected source installation failure.');
        }
      };
      final run = await _mount(tester, fixture);
      await _review(tester, run);
      await _activate(
        tester,
        'Publish reviewed move',
        () => _text(archiveTransferMessages['recovery']!.first),
      );
      expect(
        find.text(archiveTransferMessages['published']!.first),
        findsNothing,
      );
      expect(
        find.text(archiveTransferMessages['retained']!.first),
        findsNothing,
      );
      expect(
        find.text('0 source member(s) removed after verified copying.'),
        findsNothing,
      );
      expect(
        find.text(archiveTransferMessages['recoveryDetail']!.first),
        findsOneWidget,
      );
      await tester.runAsync(() => tester.binding.handlePopRoute());
      await _until(tester, () => run.closed);
      final result = run.result! as ArchiveEndpointMoveResult;
      expect(result.disposition, ArchiveMoveDisposition.sourceRecoveryRequired);
      expect(result.sourceReceipt, isNull);
      expect(result.sourceRecovery, isNotNull);
      await tester.runAsync(() async {
        expect(await File(fixture.sourcePath).exists(), isFalse);
        expect(
          await File(result.sourceRecovery!.backupPath(fixture.source.paths))
              .readAsBytes(),
          fixture.sourceBytes,
        );
      });
      var recoveryClosed = false;
      final recovery =
          showArchivePublicationRecoveryDialog(
            run.context,
            backend: fixture.source,
            journal: fixture.journal,
          ).then((changed) {
            recoveryClosed = true;
            return changed;
          });
      await tester.pump();
      await _until(
        tester,
        () =>
            _text('Destination archive') &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(find.text('Source archive'), findsOneWidget);
      expect(find.text(fixture.sourcePath), findsOneWidget);
      expect(find.text(fixture.destinationPath), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Restore original'),
            )
            .onPressed,
        isNotNull,
      );
      await _activate(tester, 'Close', () => recoveryClosed);
      expect(await recovery, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'changed source capture before publication leaves both physical archives unchanged',
    (tester) async {
      final fixture = await _fixture(tester);
      final run = await _mount(tester, fixture);
      await _review(tester, run);
      fixture.source.available = false;
      await _activate(
        tester,
        'Publish reviewed move',
        () => find
            .textContaining('Review both current archive candidates')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.text(archiveTransferMessages['published']!.first),
        findsNothing,
      );
      await _expectOriginals(tester, fixture);
      await _activate(tester, 'Close', () => run.closed);
      expect(run.result, isNull);
      expect(fixture.journal.records, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'nested archive move is refused before asking for passwords or preparing candidates',
    (tester) async {
      final fixture = await _fixture(tester);
      final run = await _mount(
        tester,
        fixture,
        sourceNestedMembers: ['inner.zip'],
      );
      await _activate(
        tester,
        'Open move',
        () => find
            .textContaining(archiveTransferMessages['scope']!.first)
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Prepare both reviews'), findsNothing);
      await _activate(tester, 'Close', () => run.closed);
      expect(run.result, isNull);
      await _expectOriginals(tester, fixture);
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'source and destination passwords remain independent during a physical move',
    (tester) async {
      final protected = (await tester.runAsync(
        () async => (
          await _protected({
            'new.txt': [7, 8],
            'keep-source.txt': [3],
          }, 'source-key'),
          await _protected({
            'keep-destination.txt': [4],
          }, 'destination-key'),
        ),
      ))!;
      final fixture = await _fixture(
        tester,
        sourceBytes: protected.$1,
        destinationBytes: protected.$2,
      );
      final run = await _mount(
        tester,
        fixture,
        files: [FileItem(name: 'new.txt', path: '/new.txt', isFolder: false)],
      );
      await _activate(
        tester,
        'Open move',
        () => _text('Source archive password'),
      );
      await tester.enterText(find.byType(TextField), 'source-key');
      await _activate(
        tester,
        'Continue',
        () => _text('Destination archive password'),
      );
      await tester.enterText(find.byType(TextField), 'source-key');
      await _activate(
        tester,
        'Continue',
        () => _text('Incorrect password. Try again'),
      );
      expect(find.text('Destination archive password'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'destination-key');
      await _activate(tester, 'Continue', () => _text('Prepare both reviews'));
      await _activate(
        tester,
        'Prepare both reviews',
        () => _text('Review both archives'),
      );
      await _expectOriginals(tester, fixture);
      await _activate(
        tester,
        'Publish reviewed move',
        () => _text(archiveTransferMessages['published']!.first),
      );
      await _activate(tester, 'Close', () => run.closed);
      await tester.runAsync(() async {
        final source = await ArchiveWorkspace.open(
          fixture.source,
          (await fixture.source.stat(fixture.sourcePath))!,
          password: 'source-key',
          journal: fixture.journal,
        );
        final destination = await ArchiveWorkspace.open(
          fixture.destination,
          (await fixture.destination.stat(fixture.destinationPath))!,
          password: 'destination-key',
          journal: fixture.journal,
        );
        try {
          expect(source.encrypted, isTrue);
          expect(destination.encrypted, isTrue);
          expect(await source.backend.stat('/new.txt'), isNull);
          expect(await source.read('/keep-source.txt'), [3]);
          expect(await destination.read('/new.txt'), [7, 8]);
          expect(await destination.read('/keep-destination.txt'), [4]);
        } finally {
          await source.close();
          await destination.close();
        }
      });
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'cancelling a move password prompt cannot produce a review or publication',
    (tester) async {
      final bytes = (await tester.runAsync(
        () => _protected({
          'new.txt': [7],
        }, 'source-key'),
      ))!;
      final fixture = await _fixture(tester, sourceBytes: bytes);
      final run = await _mount(
        tester,
        fixture,
        files: [FileItem(name: 'new.txt', path: '/new.txt', isFolder: false)],
      );
      await _activate(
        tester,
        'Open move',
        () => _text('Source archive password'),
      );
      final passwordDialog = find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(AlertDialog),
      );
      final cancel = find.descendant(
        of: passwordDialog,
        matching: find.widgetWithText(TextButton, 'Cancel'),
      );
      await tester.runAsync(() => tester.tap(cancel));
      await _until(
        tester,
        () => find.byType(TextField).evaluate().isEmpty && _text('Close'),
      );
      expect(find.text('Prepare both reviews'), findsNothing);
      await _activate(tester, 'Close', () => run.closed);
      expect(run.result, isNull);
      await _expectOriginals(tester, fixture);
      expect(fixture.journal.records, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  for (final locale in const [
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
    testWidgets('both move reviews fit 320px with large text in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _fixture(tester);
      final run = await _mount(tester, fixture, locale: locale, textScale: 1.8);
      await _review(tester, run);
      for (final key in ['policy', 'skipped', 'draftOnly', 'publish']) {
        expect(
          find.text(archiveTransferText(run.context, key)),
          findsOneWidget,
        );
      }
      expect(
        find.text(archiveEndpointText(run.context, 'archiveCopyProtection')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _activate(
        tester,
        run.context.commanderTr('Close'),
        () => run.closed,
      );
      expect(run.result, isNull);
      await _expectOriginals(tester, fixture);
      expect(tester.takeException(), isNull);
    }, variant: desktop);
  }
}
