import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_endpoint_strings.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/widgets/archive_endpoint_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import '../support/archive_endpoint_backend.dart';

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
  koni.ArchiveWriteFormat format,
  Map<String, List<int>> files,
  String password, {
  bool names = false,
}) async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: format,
    options: koni.ArchiveWriteOptions(password: password, encryptHeader: names),
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

Future<void> _until(WidgetTester tester, bool Function() done) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
  });
  expect(done(), isTrue);
  // The preparation indicator remains active under password prompts. Settle
  // the route transition without waiting for that deliberate animation to end.
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _activate(
  WidgetTester tester,
  String action,
  bool Function() done,
) async {
  await tester.ensureVisible(find.text(action));
  await tester.runAsync(() => tester.tap(find.text(action)));
  await _until(tester, done);
}

bool _hasText(String text) => find.text(text).evaluate().isNotEmpty;

void main() {
  for (final publish in [false, true]) {
    testWidgets(
      publish
          ? 'archive copy publishes the selected tree and keeps the source bytes'
          : 'closing archive copy review keeps both physical archives unchanged',
      (tester) async {
        final sourceBytes = _zip({
          'chosen/new.txt': [7, 8, 9],
          'chosen/empty/': null,
          'unselected.txt': [4],
        });
        final destinationBytes = _zip({
          'keep.txt': [1],
        });
        final source = ArchiveEndpointTestBackend()
          ..account = 'source-account'
          ..publicationSupported = false
          ..put('/input/source.zip', sourceBytes);
        final destination = ArchiveEndpointTestBackend()
          ..account = 'destination-account'
          ..put('/out/destination.zip', destinationBytes);
        final sourceFile = (await source.stat('/input/source.zip'))!;
        final destinationFile = (await destination.stat(
          '/out/destination.zip',
        ))!;
        ArchiveEndpointTransferResult? result;
        var closed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showArchiveEndpointCopyDialog(
                      context,
                      sourceContainerBackend: source,
                      sourceContainerFile: sourceFile,
                      files: [
                        FileItem(
                          name: 'chosen',
                          path: 'chosen/',
                          isFolder: true,
                        ),
                      ],
                      containerBackend: destination,
                      containerFile: destinationFile,
                      journal: ArchivePublicationJournal(
                        storage: MemoryFileCollectionStorage(),
                      ),
                    );
                    closed = true;
                  },
                  child: const Text('Copy'),
                ),
              ),
            ),
          ),
        );
        await _activate(tester, 'Copy', () => _hasText('Prepare review'));
        expect(find.text('Copy between archives'), findsOneWidget);
        expect(find.text('Source archive'), findsOneWidget);
        expect(find.text('Destination archive'), findsOneWidget);
        expect(
          find.text(archiveEndpointMessages['archiveCopyProtection']!.first),
          findsOneWidget,
        );
        await _activate(
          tester,
          'Prepare review',
          () => _hasText('Review archive changes'),
        );
        expect(source.files['/input/source.zip'], sourceBytes);
        expect(destination.files['/out/destination.zip'], destinationBytes);
        if (publish) {
          await _activate(
            tester,
            'Publish verified archive',
            () => _hasText('Archive published and verified.'),
          );
        }
        await tester.tap(find.text('Close'));
        await _until(tester, () => closed);
        expect(closed, isTrue);
        expect(source.files['/input/source.zip'], sourceBytes);
        expect(source.mutations, isEmpty);
        if (publish) {
          expect(result?.receipt, isNotNull);
          expect(result?.removedSources, 0);
          final decoded = codec.ZipDecoder().decodeBytes(
            destination.files['/out/destination.zip']!,
          );
          expect(decoded.findFile('chosen/new.txt')?.content, [7, 8, 9]);
          expect(decoded.findFile('chosen/empty/')?.isFile, isFalse);
          expect(decoded.findFile('keep.txt')?.content, [1]);
          expect(decoded.findFile('unselected.txt'), isNull);
        } else {
          expect(result, isNull);
          expect(destination.files['/out/destination.zip'], destinationBytes);
          expect(destination.mutations, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'nested source and destination ask for independent passwords and preserve destination protection',
    (tester) async {
      late Uint8List sourceBytes, destinationBytes;
      await tester.runAsync(() async {
        final sourceInner = await _protected(const koni.ZipWriteFormat(), {
          'new.txt': [2, 3],
        }, 'source-inner');
        sourceBytes = await _protected(
          const koni.SevenZWriteFormat(),
          {'inner.zip': sourceInner},
          'source-outer',
          names: true,
        );
        final destinationInner = await _protected(const koni.ZipWriteFormat(), {
          'keep.txt': [1],
        }, 'destination-inner');
        destinationBytes = await _protected(
          const koni.SevenZWriteFormat(),
          {'inner.zip': destinationInner},
          'destination-outer',
          names: true,
        );
      });
      final source = ArchiveEndpointTestBackend()
        ..account = 'source-account'
        ..put('/input/source.7z', sourceBytes);
      final destination = ArchiveEndpointTestBackend()
        ..account = 'destination-account'
        ..put('/out/destination.7z', destinationBytes);
      final sourceFile = (await source.stat('/input/source.7z'))!;
      final destinationFile = (await destination.stat('/out/destination.7z'))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showArchiveEndpointCopyDialog(
                  context,
                  sourceContainerBackend: source,
                  sourceContainerFile: sourceFile,
                  sourceNestedMembers: const ['inner.zip'],
                  files: [
                    FileItem(
                      name: 'new.txt',
                      path: '/new.txt',
                      isFolder: false,
                    ),
                  ],
                  containerBackend: destination,
                  containerFile: destinationFile,
                  nestedMembers: const ['inner.zip'],
                  journal: ArchivePublicationJournal(
                    storage: MemoryFileCollectionStorage(),
                  ),
                ),
                child: const Text('Copy'),
              ),
            ),
          ),
        ),
      );
      await _activate(
        tester,
        'Copy',
        () => _hasText('Source archive password'),
      );
      for (final step in [
        ('source.7z', 'source-outer', 'Source archive password', 'inner.zip'),
        (
          'inner.zip',
          'wrong-password',
          'Incorrect password. Try again',
          'inner.zip',
        ),
        (
          'inner.zip',
          'source-inner',
          'Destination archive password',
          'destination.7z',
        ),
        (
          'destination.7z',
          'destination-outer',
          'Destination archive password',
          'inner.zip',
        ),
        ('inner.zip', 'destination-inner', 'Prepare review', null),
      ]) {
        expect(
          tester
              .widget<TextField>(find.byType(TextField))
              .decoration
              ?.labelText,
          step.$1,
        );
        await tester.enterText(find.byType(TextField), step.$2);
        await _activate(tester, 'Continue', () {
          if (!_hasText(step.$3)) return false;
          return step.$4 == null ||
              find
                  .byType(TextField)
                  .evaluate()
                  .any(
                    (element) =>
                        (element.widget as TextField).decoration?.labelText ==
                        step.$4,
                  );
        });
      }
      await _activate(
        tester,
        'Prepare review',
        () => _hasText('Review archive changes'),
      );
      await _activate(
        tester,
        'Publish verified archive',
        () => _hasText('Archive published and verified.'),
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(source.files['/input/source.7z'], sourceBytes);
      await tester.runAsync(() async {
        final reopened = await ArchiveWorkspace.openNested(
          destination,
          (await destination.stat('/out/destination.7z'))!,
          ['inner.zip'],
          passwords: ['destination-outer', 'destination-inner'],
          journal: ArchivePublicationJournal(
            storage: MemoryFileCollectionStorage(),
          ),
        );
        try {
          expect(await reopened.read('/new.txt'), [2, 3]);
          expect(reopened.encrypted, isTrue);
          expect(reopened.outermost.encryptNames, isTrue);
        } finally {
          await reopened.close();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling a source password leaves both archives unchanged', (
    tester,
  ) async {
    final sourceBytes = Uint8List.fromList(
      codec.ZipEncoder(password: 'secret').encode(
        codec.Archive()..addFile(codec.ArchiveFile.bytes('new.txt', [2])),
      ),
    );
    final destinationBytes = _zip({
      'keep.txt': [1],
    });
    final source = ArchiveEndpointTestBackend()
      ..account = 'source'
      ..put('/input/source.zip', sourceBytes);
    final destination = ArchiveEndpointTestBackend()
      ..account = 'destination'
      ..put('/out/destination.zip', destinationBytes);
    final sourceFile = (await source.stat('/input/source.zip'))!;
    final destinationFile = (await destination.stat('/out/destination.zip'))!;
    var closed = false;
    ArchiveEndpointTransferResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showArchiveEndpointCopyDialog(
                  context,
                  sourceContainerBackend: source,
                  sourceContainerFile: sourceFile,
                  files: [
                    FileItem(
                      name: 'new.txt',
                      path: '/new.txt',
                      isFolder: false,
                    ),
                  ],
                  containerBackend: destination,
                  containerFile: destinationFile,
                  journal: ArchivePublicationJournal(
                    storage: MemoryFileCollectionStorage(),
                  ),
                );
                closed = true;
              },
              child: const Text('Copy'),
            ),
          ),
        ),
      ),
    );
    await _activate(tester, 'Copy', () => _hasText('Source archive password'));
    final passwordDialog = find.ancestor(
      of: find.byType(TextField),
      matching: find.byType(AlertDialog),
    );
    final cancel = find.descendant(
      of: passwordDialog,
      matching: find.widgetWithText(TextButton, 'Cancel'),
    );
    await tester.runAsync(() => tester.tap(cancel));
    await tester.pump(const Duration(milliseconds: 300));
    await _until(
      tester,
      () => find.byType(TextField).evaluate().isEmpty && _hasText('Close'),
    );
    expect(find.text('Prepare review'), findsNothing);
    await tester.tap(find.text('Close'));
    await _until(tester, () => closed);
    expect(result, isNull);
    expect(source.files['/input/source.zip'], sourceBytes);
    expect(destination.files['/out/destination.zip'], destinationBytes);
    expect(source.mutations, isEmpty);
    expect(destination.mutations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final locale in const ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
    testWidgets('archive copy guidance fits a narrow $locale dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = ArchiveEndpointTestBackend()
        ..account = 'source'
        ..put(
          '/input/source.zip',
          _zip({
            'new.txt': [2],
          }),
        );
      final destination = ArchiveEndpointTestBackend()
        ..account = 'destination'
        ..put(
          '/out/destination.zip',
          _zip({
            'keep.txt': [1],
          }),
        );
      final sourceFile = (await source.stat('/input/source.zip'))!;
      final destinationFile = (await destination.stat('/out/destination.zip'))!;
      late BuildContext translated;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              translated = context;
              return Scaffold(
                body: TextButton(
                  onPressed: () => showArchiveEndpointCopyDialog(
                    context,
                    sourceContainerBackend: source,
                    sourceContainerFile: sourceFile,
                    files: [
                      FileItem(
                        name: 'new.txt',
                        path: '/new.txt',
                        isFolder: false,
                      ),
                    ],
                    containerBackend: destination,
                    containerFile: destinationFile,
                    journal: ArchivePublicationJournal(
                      storage: MemoryFileCollectionStorage(),
                    ),
                  ),
                  child: const Text('Copy'),
                ),
              );
            },
          ),
        ),
      );
      await _activate(
        tester,
        'Copy',
        () => _hasText(archiveEndpointText(translated, 'stage')),
      );
      for (final key in [
        'copyTitle',
        'archiveCopySnapshot',
        'archiveCopyProtection',
        'archiveCopyMetadata',
      ]) {
        expect(find.text(archiveEndpointText(translated, key)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(translated.commanderTr('Close')));
      await tester.pumpAndSettle();
    });
  }
}
