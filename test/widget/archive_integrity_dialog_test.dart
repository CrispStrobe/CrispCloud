import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/widgets/archive_integrity_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ViewerArchive _archive({
  Future<Uint8List> Function(ViewerArchiveMember, int)? read,
}) => ViewerArchive.reader(
  formatName: 'test',
  members: const [
    ViewerArchiveMember(
      name: 'hello.txt',
      size: 5,
      isFile: true,
      isEncrypted: false,
      pathEscapedRoot: false,
      index: 0,
    ),
  ],
  read: read ?? (_, _) async => Uint8List.fromList(utf8.encode('hello')),
  close: () async {},
);

Future<void> _open(
  WidgetTester tester,
  ViewerArchive archive, {
  String locale = 'en',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showArchiveIntegrityDialog(
              context,
              archive: archive,
              displayName: 'sample.zip',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reports verified content and copies full digests', (
    tester,
  ) async {
    String? clipboard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final archive = _archive();
    await _open(tester, archive);
    expect(find.text('All regular files checked'), findsOneWidget);
    expect(
      find.text('Checked 1 · Failed 0 · Skipped 0 · Unchecked 0'),
      findsOneWidget,
    );
    await tester.tap(find.text('hello.txt'));
    await tester.pumpAndSettle();
    final digest = sha256.convert(utf8.encode('hello')).toString();
    expect(find.text('SHA-256: $digest'), findsOneWidget);
    await tester.tap(find.text('Copy report'));
    await tester.pump();
    expect(clipboard, contains(digest));
    expect(clipboard, contains('do not authenticate its publisher'));
    expect(clipboard, contains('sample.zip'));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(ArchiveIntegrityDialog), findsNothing);
    expect(archive.isClosed, isFalse);
  });

  testWidgets('corrupt payload is visible as a failure with details', (
    tester,
  ) async {
    await _open(
      tester,
      _archive(
        read: (_, _) async =>
            throw const ArchiveViewException('Stored checksum mismatch.'),
      ),
    );
    expect(find.text('Check incomplete or issues found'), findsOneWidget);
    expect(
      find.text('Checked 0 · Failed 1 · Skipped 0 · Unchecked 0'),
      findsOneWidget,
    );
    await tester.tap(find.text('hello.txt'));
    await tester.pumpAndSettle();
    expect(find.text('Stored checksum mismatch.'), findsOneWidget);
    expect(find.textContaining('SHA-256:'), findsNothing);
  });

  testWidgets('cancel during a pending read reports unchecked members', (
    tester,
  ) async {
    final gate = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveIntegrityDialog(
          archive: _archive(read: (_, _) => gate.future),
          displayName: 'pending.zip',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(
      find.text('Stops between reads. A bounded decode may finish first.'),
      findsOneWidget,
    );
    gate.complete(Uint8List.fromList([1, 2, 3, 4, 5]));
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsOneWidget);
    expect(
      find.text('Checked 0 · Failed 0 · Skipped 0 · Unchecked 1'),
      findsOneWidget,
    );
    expect(find.text('All regular files checked'), findsNothing);
  });

  testWidgets('disposing an active report releases callbacks safely', (
    tester,
  ) async {
    final gate = Completer<Uint8List>();
    final archive = _archive(read: (_, _) => gate.future);
    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveIntegrityDialog(
          archive: archive,
          displayName: 'pending.zip',
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete(Uint8List(5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(archive.isClosed, isFalse);
  });

  for (final locale in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
    testWidgets('translated report fits a narrow window ($locale)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _open(tester, _archive(), locale: locale);
      expect(find.text('All regular files checked'), findsNothing);
      expect(find.text('Copy report'), findsNothing);
      await tester.scrollUntilVisible(find.text('hello.txt'), 150);
      expect(find.text('hello.txt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('F3 archive listing exposes the integrity workflow', (
    tester,
  ) async {
    final bytes = ar.ZipEncoder().encode(
      ar.Archive()..addFile(ar.ArchiveFile('file.txt', 3, [65, 66, 67])),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: InternalViewerDialog(
            file: FileItem(name: 'sample.zip', isFolder: false),
            side: PanelSide.local,
            bytesOverride: Uint8List.fromList(bytes),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('test-archive')));
    await tester.pumpAndSettle();
    expect(find.text('Archive integrity'), findsOneWidget);
    expect(find.text('All regular files checked'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
