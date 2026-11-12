import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/l10n/archive_endpoint_strings.dart';
import 'package:crisp_cloud/services/archive_container_publisher.dart';
import 'package:crisp_cloud/services/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/widgets/archive_endpoint_dialog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_endpoint_backend.dart';

Uint8List packed(String name, List<int> data) {
  final archive = codec.Archive()..addFile(codec.ArchiveFile.bytes(name, data));
  return Uint8List.fromList(codec.ZipEncoder().encode(archive));
}

void main() {
  test('all archive endpoint messages cover nine locales with matching placeholders', () {
    for (final entry in archiveEndpointMessages.entries) {
      expect(entry.value.length, 9, reason: entry.key);
      final placeholders = RegExp(r'\{\d+\}')
          .allMatches(entry.value.first)
          .map((match) => match.group(0))
          .toSet();
      for (final translation in entry.value) {
        expect(translation.trim(), isNotEmpty, reason: entry.key);
        expect(
          RegExp(r'\{\d+\}')
              .allMatches(translation)
              .map((match) => match.group(0))
              .toSet(),
          placeholders,
          reason: entry.key,
        );
      }
    }
  });

  for (final publish in [false, true]) {
    testWidgets(
      publish
          ? 'reviewed import returns a publication receipt'
          : 'closing a staged review returns no success and preserves sources',
      (tester) async {
        final original = packed('keep', [1]);
        final backend = ArchiveEndpointTestBackend()
          ..put('/out/work.zip', original)
          ..put('/input/new.txt', [2, 3]);
        final journal = ArchivePublicationJournal(
          storage: MemoryFileCollectionStorage(),
        );
        ArchiveEndpointTransferResult? result;
        var closed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showArchiveEndpointImportDialog(
                      context,
                      source: backend,
                      files: [(await backend.stat('/input/new.txt'))!],
                      containerBackend: backend,
                      containerFile: (await backend.stat('/out/work.zip'))!,
                      journal: journal,
                    );
                    closed = true;
                  },
                  child: const Text('Open import'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open import'));
        await tester.pumpAndSettle();
        expect(find.text('Prepare review'), findsOneWidget);
        await tester.ensureVisible(find.text('Prepare review'));
        await _activateAndWaitForText(
          tester,
          'Prepare review',
          'Review archive changes',
        );
        expect(
          find.text('Review archive changes'),
          findsOneWidget,
          reason: [
            ...tester
                .widgetList<Text>(find.byType(Text))
                .map((text) => text.data),
            ...tester
                .widgetList<SelectableText>(find.byType(SelectableText))
                .map((text) => text.data),
          ].join('\n'),
        );
        expect(backend.files['/out/work.zip'], original);
        expect(backend.files['/input/new.txt'], [2, 3]);
        expect(result, isNull);
        if (publish) {
          await tester.ensureVisible(find.text('Publish verified archive'));
          await _activateAndWaitForText(
            tester,
            'Publish verified archive',
            'Archive published and verified.',
          );
          expect(find.text('Archive published and verified.'), findsOneWidget);
        }
        await tester.ensureVisible(find.text('Close'));
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(closed, isTrue);
        if (publish) {
          expect(result?.receipt, isNotNull);
          expect(result?.publishedFiles, 1);
        } else {
          expect(result, isNull);
          expect(backend.files['/out/work.zip'], original);
          expect(journal.records, isEmpty);
        }
        expect(backend.files['/input/new.txt'], [2, 3]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'restart recovery lists only captured-account evidence and explicitly finishes publication',
    (tester) async {
      final original = packed('before', [1]), candidate = packed('after', [2]);
      final backend = ArchiveEndpointTestBackend()
        ..put('/out/work.zip', original);
      final storage = MemoryFileCollectionStorage();
      final firstJournal = ArchivePublicationJournal(storage: storage);
      var fail = true;
      backend.before = (action, path, destination) {
        if (action == 'move' && destination == '/out/work.zip' && fail) {
          fail = false;
          throw StateError('Interrupted install');
        }
      };
      await tester.runAsync(() async {
        await expectLater(
          ArchiveContainerPublisher(backend, firstJournal).publish(
            original: (await backend.stat('/out/work.zip'))!,
            originalSha256: sha256.convert(original).toString(),
            bytes: candidate,
          ),
          throwsA(anything),
        );
      });
      backend.before = null;
      var changed = false;
      final restarted = ArchivePublicationJournal(storage: storage);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  changed = await showArchivePublicationRecoveryDialog(
                    context,
                    backend: backend,
                    journal: restarted,
                  );
                },
                child: const Text('Recover'),
              ),
            ),
          ),
        ),
      );
      await _activateAndWaitForText(tester, 'Recover', 'Finish publication');
      await tester.pumpAndSettle();
      expect(find.text('/out/work.zip'), findsOneWidget);
      await tester.ensureVisible(find.text('Finish publication'));
      await _activateAndWaitForText(
        tester,
        'Finish publication',
        'No unfinished archive publication for this account.',
      );
      await tester.pumpAndSettle();
      expect(backend.files['/out/work.zip'], candidate);
      expect(restarted.records.single.phase, ArchivePublicationPhase.complete);
      expect(
        find.text('No unfinished archive publication for this account.'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await Future<void>.delayed(Duration.zero);
      });
      expect(changed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

/// Start deadline-owned I/O in the real async zone. Advancing animated fake
/// frames must not expire ten minutes while a native codec event is pending.
Future<void> _activateAndWaitForText(
  WidgetTester tester,
  String action,
  String completed,
) async {
  await tester.runAsync(() async {
    await tester.tap(find.text(action));
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (find.text(completed).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}
