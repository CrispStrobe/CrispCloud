import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/hex_viewer.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/archive_iso_fixtures.dart';
import '../support/dmg_fixture.dart';
import '../support/hfs_fixture.dart';
import '../support/workflow_fake_client.dart';
import '../support/workspace_fixture.dart' show WorkspaceTestAuth;

class _ArchiveLocal extends Fake implements LocalFileService {
  _ArchiveLocal(String path, {this.acquireGate})
    : currentPath = path,
      rootPath = path;

  @override
  String currentPath;
  final String rootPath;
  final Completer<void>? acquireGate;
  int acquisitions = 0, releases = 0, fullReads = 0;

  @override
  String get grantedBasePath => rootPath;
  @override
  Future<String> getInitialPath() async => rootPath;
  @override
  Future<String> getSafeFallbackDirectory() async => rootPath;
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<bool> ensureAccess(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async =>
      path == rootPath ? Directory(path).list().toList() : [];
  @override
  Future<void> refresh() async {}

  @override
  Future<bool> beginStreamAccess(String path) async {
    acquisitions++;
    await acquireGate?.future;
    return true;
  }

  @override
  Future<void> endStreamAccess() async {
    releases++;
  }

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    fullReads++;
    throw StateError('The large ISO must use the existing positional source.');
  }
}

class _NativeIso {
  _NativeIso(this.directory, this.local, this.container, this.file);

  final Directory directory;
  final _ArchiveLocal local;
  final ProviderContainer container;
  final FileItem file;

  static Future<_NativeIso> create(
    WidgetTester tester, {
    Completer<void>? acquireGate,
  }) async {
    return (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('f3-archive-');
      final fixture = IsoFixture();
      const fileBytes = 80 * 1024 * 1024;
      isoBoth32(
        fixture.bytes,
        16 * IsoFixture.sectorSize + 80,
        fileBytes ~/ IsoFixture.sectorSize,
      );
      final disk = File('${directory.path}/large.iso');
      await disk.writeAsBytes(fixture.bytes);
      final handle = await disk.open(mode: FileMode.append);
      try {
        // Sparse padding keeps the test fixture small while exercising a
        // real file larger than the old full-buffer archive limit.
        await handle.truncate(fileBytes);
      } finally {
        await handle.close();
      }
      final local = _ArchiveLocal(directory.path, acquireGate: acquireGate);
      final cloud = WorkflowFakeClient()..current = false;
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
          localFileServiceProvider.overrideWithValue(local),
        ],
      );
      final panel = container.read(panelProvider(PanelSide.local));
      await panel.refresh();
      container
          .read(panelSourceProvider(PanelSide.local).notifier)
          .setSource(LocalPanelSource(directory.path));
      await panel.refresh();
      final file = panel.files!.firstWhere((file) => file.name == 'large.iso');
      expect(file.size, fileBytes);
      expect(panel.originForOperation(file), isNotNull);
      return _NativeIso(directory, local, container, file);
    }))!;
  }

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _app(InternalViewerDialog(file: file, side: PanelSide.local)),
    ),
  );

  Future<void> dispose(WidgetTester tester) async {
    final gate = local.acquireGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await _waitFor(tester, () => local.releases == local.acquisitions);
    container.dispose();
    await tester.runAsync(() => directory.delete(recursive: true));
  }
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

Future<void> _memoryViewer(
  WidgetTester tester,
  Uint8List bytes,
  String name,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: _app(
        InternalViewerDialog(
          file: FileItem(name: name, isFolder: false, size: bytes.length),
          side: PanelSide.local,
          bytesOverride: bytes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  // Native stat/open operations need real event-loop turns; advancing the
  // widget test's fake clock alone cannot finish them.
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  expect(ready(), isTrue, reason: 'The asynchronous viewer operation stalled.');
}

ChoiceChip _chip(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'a native 80 MiB ISO lists and reopens without releasing its viewer source',
    (tester) async {
      final native = await _NativeIso.create(tester);
      try {
        await native.mount(tester);
        await _waitFor(
          tester,
          () => find.text('HELLO.TXT').evaluate().isNotEmpty,
        );
        expect(find.text('DOCS/NOTE.TXT'), findsOneWidget);
        expect(native.local.fullReads, 0);
        expect(native.local.acquisitions, 1);
        expect(native.local.releases, 0);

        _chip(tester, 'Hex').onSelected!(true);
        await tester.pumpAndSettle();
        expect(find.byType(HexViewer), findsOneWidget);
        expect(native.local.releases, 0);

        _chip(tester, 'Archive').onSelected!(true);
        await _waitFor(
          tester,
          () => find.text('HELLO.TXT').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('HELLO.TXT'));
        await _waitFor(
          tester,
          () => find
              .textContaining('hello iso', findRichText: true)
              .evaluate()
              .isNotEmpty,
        );
        expect(find.byType(InternalViewerDialog), findsNWidgets(2));
        expect(native.local.acquisitions, 1);
        expect(native.local.releases, 0);
        expect(native.local.fullReads, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await native.dispose(tester);
      }
      expect(native.local.releases, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a zlib DMG lists HFS+ members and opens a file', (tester) async {
    final image = DmgFixture(HfsFixture().bytes, method: 0x80000005);
    await _memoryViewer(tester, image.bytes, 'volume.dmg');
    expect(find.text('files/001-Test volume/hello.txt'), findsOneWidget);
    expect(find.text('files/001-Test volume/資料/nested.bin'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('archive-format-notices')),
      findsOneWidget,
    );
    await tester.tap(find.text('files/001-Test volume/hello.txt'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('hello HFS+', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(InternalViewerDialog), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty ZIP packages still display their container details', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(ZipEncoder().encode(Archive()));
    await _memoryViewer(tester, bytes, 'extension.xpi');
    expect(find.text('This archive contains no entries.'), findsOneWidget);
    final details = find.byKey(const ValueKey('archive-format-notices'));
    expect(details, findsOneWidget);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Publisher signatures are not verified.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching modes cancels an in-flight archive member read', (
    tester,
  ) async {
    await _memoryViewer(tester, IsoFixture().bytes, 'small.iso');
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('HELLO.TXT'),
        matching: find.byType(ListTile),
      ),
    );
    // Start the actual member callback, then revoke its mode before the
    // borrowed source's queued asynchronous read is allowed to continue.
    tile.onTap!();
    _chip(tester, 'Hex').onSelected!(true);
    await tester.pumpAndSettle();
    expect(find.byType(HexViewer), findsOneWidget);
    expect(find.byType(InternalViewerDialog), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    _chip(tester, 'Archive').onSelected!(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('HELLO.TXT'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('hello iso', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing while native access opens releases the late source', (
    tester,
  ) async {
    final gate = Completer<void>();
    final native = await _NativeIso.create(tester, acquireGate: gate);
    try {
      await native.mount(tester);
      await _waitFor(tester, () => native.local.acquisitions == 1);
      expect(native.local.releases, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await _waitFor(tester, () => native.local.releases == 1);
      expect(find.byType(InternalViewerDialog), findsNothing);
      expect(native.local.fullReads, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await native.dispose(tester);
    }
    expect(native.local.releases, 1);
  });

  testWidgets('an incorrect archive password can retry using the same viewer', (
    tester,
  ) async {
    final bytes = File('test/fixtures/archives/header_encrypted.7z')
        .readAsBytesSync();
    await _memoryViewer(tester, bytes, 'locked.7z');
    expect(find.text('Password required'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'incorrect');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('hello.txt'), findsOneWidget);
    await tester.tap(find.text('hello.txt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('hello, 7z!', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a late password result cannot reopen an abandoned archive mode',
    (tester) async {
      final bytes = File('test/fixtures/archives/header_encrypted.7z')
          .readAsBytesSync();
      await _memoryViewer(tester, bytes, 'locked.7z');
      expect(find.text('Password required'), findsOneWidget);
      // Mode callbacks can also come from navigation/shortcuts while a prompt
      // is pending; completing that old prompt must not replace the new mode.
      _chip(tester, 'Hex').onSelected!(true);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(HexViewer), findsOneWidget);
      expect(find.text('hello.txt'), findsNothing);
      expect(find.byType(InternalViewerDialog), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('header encryption allows exactly three submitted passwords', (
    tester,
  ) async {
    final bytes = File('test/fixtures/archives/header_encrypted.7z')
        .readAsBytesSync();
    await _memoryViewer(tester, bytes, 'locked.7z');
    for (var attempt = 0; attempt < 3; attempt++) {
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'incorrect-$attempt');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Too many incorrect password attempts.'), findsOneWidget);
    expect(find.text('hello.txt'), findsNothing);
    _chip(tester, 'Hex').onSelected!(true);
    await tester.pumpAndSettle();
    expect(find.byType(HexViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unlocking preserves the selected duplicate-name ZIP member', (
    tester,
  ) async {
    final first = ArchiveFile('first.txt', 13, 'first payload'.codeUnits);
    final second = ArchiveFile('other.txt', 13, 'other payload'.codeUnits);
    final archive = Archive()
      ..addFile(first)
      ..addFile(second);
    // ZIP permits duplicate paths. Changing names after insertion keeps the
    // fixture builder's map from replacing one of these distinct entries.
    first.name = 'same.txt';
    second.name = 'same.txt';
    final bytes = Uint8List.fromList(
      ZipEncoder(password: 'secret').encode(archive),
    );
    await _memoryViewer(tester, bytes, 'duplicates.zip');
    expect(find.text('same.txt'), findsNWidgets(2));
    await tester.tap(find.text('same.txt').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('other payload', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('first payload', findRichText: true),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
