// test/file_bytes_loader_test.dart
//
// Tests for ViewBytesSource: in-memory slices and file-backed windowed reads
// (the mechanism that lets the F3 viewer hex-view arbitrarily large files).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

import 'support/workflow_fake_client.dart';

void main() {
  group('ViewBytesSource.memory', () {
    test('open exposes size and readSync slices and clamps at EOF', () async {
      final data = Uint8List.fromList(List<int>.generate(100, (i) => i));
      final source = ViewBytesSource.memory(data);
      await source.open();

      expect(source.isStreamed, isFalse);
      expect(source.size, 100);
      expect(source.readSync(10, 5), <int>[10, 11, 12, 13, 14]);
      expect(source.readSync(95, 100).length, 5);
      expect(source.readSync(200, 10), isEmpty);

      source.dispose();
      expect(() => source.readSync(0, 1), throwsA(isA<StateError>()));
    });
  });

  testWidgets('local read retries once after access is granted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final dir = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('viewer_retry_');
      await File('${directory.path}/x.zip').writeAsBytes(<int>[1, 2, 3]);
      return directory;
    }))!;
    addTearDown(() => dir.delete(recursive: true));
    late WidgetRef captured;
    final fake = _RetryLocalService('${dir.path}/x.zip');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((_) => _LocalTestAuth()),
          localFileServiceProvider.overrideWithValue(fake),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    );

    final bytes = await tester.runAsync(() async {
      final panel = captured.read(panelProvider(PanelSide.local));
      await panel.navigateToPath(dir.path);
      final file = panel.files!.singleWhere(
        (item) => item.path == fake.filePath,
      );
      expect(panel.originForOperation(file), isNotNull);
      return loadFileBytes(captured, file, PanelSide.local);
    });

    expect(bytes, <int>[1, 2, 3]);
    expect(fake.reads, 2);
    expect(fake.accessRequests, 1);
    await tester.pumpWidget(const SizedBox());
  });

  group('ViewBytesSource.file', () {
    late Directory dir;
    late File file;
    const length = 600 * 1024;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('viewer_bytes_');
      file = File('${dir.path}/data.bin');
      final data = Uint8List.fromList(
        List<int>.generate(length, (i) => i % 251),
      );
      await file.writeAsBytes(data);
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('streams across the 256 KiB window boundary', () async {
      final source = ViewBytesSource.file(file.path);
      await source.open();

      expect(source.isStreamed, isTrue);
      expect(source.size, length);

      // Straddles the end of the first read window.
      const nearBoundary = 256 * 1024 - 4;
      final slice = source.readSync(nearBoundary, 16);
      expect(slice.length, 16);
      expect(slice.first, nearBoundary % 251);
      expect(slice.last, (nearBoundary + 15) % 251);

      // Far read forces the window to be reloaded.
      const far = 590 * 1024;
      final tail = source.readSync(far, 32);
      expect(tail.length, 32);
      expect(tail.first, far % 251);

      source.dispose();
    });

    test('open is idempotent', () async {
      final source = ViewBytesSource.file(file.path);
      await source.open();
      await source.open();
      expect(source.size, length);
      source.dispose();
    });
  });
}

class _LocalTestAuth extends ChangeNotifier implements AuthNotifier {
  @override
  final WorkflowFakeClient client = WorkflowFakeClient()..current = false;

  @override
  bool get isConnected => false;

  @override
  String? get userEmail => null;

  @override
  String get providerName => client.providerName;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RetryLocalService
    implements LocalFileService, ScopedLocalFileOperations {
  _RetryLocalService(this.filePath) : currentPath = File(filePath).parent.path;

  final String filePath;
  int reads = 0;
  int accessRequests = 0;
  bool _accessGranted = false;

  @override
  String currentPath;

  @override
  String? get grantedBasePath => currentPath;

  @override
  Future<String> getInitialPath() async => currentPath;

  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async =>
      path == currentPath ? <FileSystemEntity>[File(filePath)] : [];

  @override
  Future<bool> hasAccessToPath(String path) async => true;

  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    // The native loader streams through a scoped operation rather than the
    // old whole-file readFile API. Directory stat/list access remains valid.
    if (path == filePath) {
      reads++;
      if (!_accessGranted) {
        throw PathAccessException(
          path,
          const OSError('Operation not permitted', 1),
        );
      }
    }
    return action();
  }

  @override
  Future<bool> ensureAccess(String path) async {
    expect(path, filePath);
    accessRequests++;
    _accessGranted = true;
    return true;
  }

  @override
  Future<int?> fileLength(String path) async => 3;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
