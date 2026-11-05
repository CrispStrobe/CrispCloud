// test/file_bytes_loader_test.dart
//
// Tests for ViewBytesSource: in-memory slices and file-backed windowed reads
// (the mechanism that lets the F3 viewer hex-view arbitrarily large files).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

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
    late WidgetRef captured;
    final fake = _RetryLocalService();
    final dir = Directory.systemTemp.createTempSync('retry_bytes_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/x.zip')..writeAsBytesSync(<int>[1, 2, 3]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localFileServiceProvider.overrideWithValue(fake)],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    );

    final origin = captured
        .read(panelProvider(PanelSide.local))
        .captureLocalClipboardOrigin(dir.path);
    final bytes = await tester.runAsync(
      () => loadFileBytes(
        captured,
        FileItem(name: 'x.zip', path: file.path, isFolder: false, size: 3),
        PanelSide.local,
        origin: origin,
      ),
    );

    expect(bytes, <int>[1, 2, 3]);
    expect(fake.reads, 2);
    expect(fake.accessRequests, 1);
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

class _RetryLocalService implements LocalFileService {
  int reads = 0;
  int accessRequests = 0;

  @override
  String currentPath = '/';

  @override
  String? get grantedBasePath => '/';

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    reads++;
    if (reads == 1) {
      throw PathAccessException(
        path,
        const OSError('Operation not permitted', 1),
      );
    }
    return Uint8List.fromList(<int>[1, 2, 3]);
  }

  @override
  Future<bool> ensureAccess(String path) async {
    accessRequests++;
    return true;
  }

  @override
  Future<int?> fileLength(String path) async => 3;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
