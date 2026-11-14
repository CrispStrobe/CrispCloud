import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/archive_integrity_dialog.dart';
import 'package:crisp_cloud/widgets/hex_viewer.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/archive_ntfs_reference_data.dart';
import '../support/workflow_fake_client.dart';
import '../support/workspace_fixture.dart' show WorkspaceTestAuth;

const _fixture = 'ntfs31';
const _hello = 'Hello from NTFS filesystem';
const _paddedLength = 80 * 1024 * 1024;

class _NtfsLocal extends Fake implements LocalFileService {
  _NtfsLocal(String path, {this.acquireGate})
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
    throw StateError('Native NTFS images must use the bounded file source.');
  }
}

class _NativeNtfs {
  _NativeNtfs(this.directory, this.local, this.container, this.file);

  final Directory directory;
  final _NtfsLocal local;
  final ProviderContainer container;
  final FileItem file;

  static Future<_NativeNtfs> create(
    WidgetTester tester, {
    Completer<void>? acquireGate,
    String name = 'large.ntfs',
  }) async {
    return (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('f3-ntfs-');
      final disk = File('${directory.path}/$name');
      final reference = NtfsReferenceSource(_fixture);
      final handle = await disk.open(mode: FileMode.write);
      try {
        for (final (offset, data) in reference.blocks) {
          await handle.setPosition(offset);
          await handle.writeFrom(data);
        }
        // Keep the original, externally mastered volume geometry and backup
        // boot sector. Trailing sparse padding exercises the native path.
        await handle.truncate(_paddedLength);
      } finally {
        await handle.close();
        await reference.close();
      }
      final local = _NtfsLocal(directory.path, acquireGate: acquireGate);
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
      final file = panel.files!.singleWhere((file) => file.name == name);
      expect(file.size, _paddedLength);
      expect(panel.originForOperation(file), isNotNull);
      return _NativeNtfs(directory, local, container, file);
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

Future<void> _memoryViewer(WidgetTester tester) async {
  final bytes = ntfsReferenceBytes(_fixture);
  await tester.pumpWidget(
    ProviderScope(
      child: _app(
        InternalViewerDialog(
          file: FileItem(
            name: 'volume.ntfs',
            isFolder: false,
            size: bytes.length,
          ),
          side: PanelSide.local,
          bytesOverride: bytes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready, {
  int attempts = 1500,
}) async {
  // Real stat/read calls need real event-loop turns, while reader yields also
  // need the widget test's fake clock to advance. Both are deliberately bounded.
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(
    ready(),
    isTrue,
    reason:
        'The NTFS viewer operation stalled. Visible text: '
        '${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? text.textSpan?.toPlainText()).join(" | ")}',
  );
}

ChoiceChip _chip(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

Future<void> _revealMember(WidgetTester tester, String path) async {
  await _waitFor(
    tester,
    () => find.textContaining('   ·   NTFS').evaluate().isNotEmpty,
  );
  final list = find
      .descendant(
        of: find.byType(InternalViewerDialog),
        matching: find.byType(ListView),
      )
      .first;
  await tester.scrollUntilVisible(
    find.text(path),
    120,
    scrollable: find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
  expect(find.text(path), findsOneWidget);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('buffered NTFS opens in Archive and previews a regular file', (
    tester,
  ) async {
    await _memoryViewer(tester);
    await _revealMember(tester, 'hello.txt');
    expect(_chip(tester, 'Archive').selected, isTrue);
    await tester.tap(find.text('hello.txt'));
    await tester.pumpAndSettle();
    expect(find.textContaining(_hello, findRichText: true), findsOneWidget);
    expect(find.byType(InternalViewerDialog), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('NTFS named streams remain visible metadata in browse and check', (
    tester,
  ) async {
    await _memoryViewer(tester);
    await _revealMember(tester, 'hello.txt');
    final details = find.byKey(const ValueKey('archive-format-notices'));
    expect(details, findsOneWidget);
    if (!tester.widget<ExpansionTile>(details).initiallyExpanded) {
      await tester.tap(details);
      await tester.pumpAndSettle();
    }
    for (final stream in ntfsReferenceStreams['hello.txt']!.entries) {
      final description =
          'Alternate DATA stream ${jsonEncode(stream.key)} on "hello.txt" '
          '(${stream.value.$1} bytes) is metadata only; '
          'it was not read, tested, or extracted.';
      expect(find.textContaining(description), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'hello.txt:${stream.key}'),
        findsNothing,
      );
    }
    await tester.tap(find.byKey(const ValueKey('test-archive')));
    await tester.pumpAndSettle();
    final dialog = find.byType(ArchiveIntegrityDialog);
    final check = tester.widget<ArchiveIntegrityDialog>(dialog);
    expect(check.archive.formatName, 'ntfs');
    expect(
      check.archive.members.any((member) => member.name.contains(':')),
      isFalse,
    );
    expect(find.text('All regular files checked'), findsOneWidget);
    expect(
      find.text(
        'Checked ${ntfsReferencePayloads.length} · Failed 0 · Skipped 0 · Unchecked 0',
      ),
      findsOneWidget,
    );
    for (final stream in ntfsReferenceStreams['hello.txt']!.entries) {
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining(
            'Alternate DATA stream ${jsonEncode(stream.key)} on "hello.txt" '
            '(${stream.value.$1} bytes) is metadata only;',
          ),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final name in ['large.ntfs', 'misnamed.zip']) {
    testWidgets('native NTFS named $name uses one bounded streaming source', (
      tester,
    ) async {
      final native = await _NativeNtfs.create(tester, name: name);
      try {
        await native.mount(tester);
        await _revealMember(tester, 'hello.txt');
        expect(native.file.size, greaterThan(kArchiveReadLimit));
        expect(native.local.fullReads, 0);
        expect(native.local.acquisitions, 1);
        expect(native.local.releases, 0);

        await tester.tap(find.byKey(const ValueKey('test-archive')));
        await tester.pump();
        final check = tester.widget<ArchiveIntegrityDialog>(
          find.byType(ArchiveIntegrityDialog),
        );
        expect(check.archive.maxStreamingMemberBytes, kArchiveStreamingLimit);
        await _waitFor(
          tester,
          () => find.text('All regular files checked').evaluate().isNotEmpty,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Close'));
        await tester.pumpAndSettle();

        _chip(tester, 'Hex').onSelected!(true);
        await tester.pumpAndSettle();
        expect(find.byType(HexViewer), findsOneWidget);
        _chip(tester, 'Archive').onSelected!(true);
        await _revealMember(tester, 'hello.txt');
        await tester.tap(find.text('hello.txt'));
        await _waitFor(
          tester,
          () => find
              .textContaining(_hello, findRichText: true)
              .evaluate()
              .isNotEmpty,
        );
        expect(find.byType(InternalViewerDialog), findsNWidgets(2));
        expect(native.local.acquisitions, 1);
        expect(native.local.fullReads, 0);
        expect(native.local.releases, 0);

        await tester.runAsync(() async {
          final reference = NtfsReferenceSource(_fixture);
          final handle = await File(native.file.path!).open();
          try {
            expect(await handle.length(), _paddedLength);
            for (final (offset, data) in reference.blocks) {
              await handle.setPosition(offset);
              expect(await handle.read(data.length), data);
            }
          } finally {
            await handle.close();
            await reference.close();
          }
        });
        expect(tester.takeException(), isNull);
      } finally {
        await native.dispose(tester);
      }
      expect(native.local.releases, 1);
    });
  }

  testWidgets('leaving NTFS Archive cancels a queued member preview', (
    tester,
  ) async {
    await _memoryViewer(tester);
    await _revealMember(tester, 'hello.txt');
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('hello.txt'),
        matching: find.byType(ListTile),
      ),
    );
    tile.onTap!();
    _chip(tester, 'Hex').onSelected!(true);
    await tester.pumpAndSettle();
    expect(find.byType(HexViewer), findsOneWidget);
    expect(find.byType(InternalViewerDialog), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    _chip(tester, 'Archive').onSelected!(true);
    await _revealMember(tester, 'hello.txt');
    await tester.tap(find.text('hello.txt'));
    await tester.pumpAndSettle();
    expect(find.textContaining(_hello, findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing NTFS during access acquisition releases the late source',
    (tester) async {
      final gate = Completer<void>();
      final native = await _NativeNtfs.create(tester, acquireGate: gate);
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
    },
  );
}
