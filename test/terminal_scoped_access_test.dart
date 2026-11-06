import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/terminal_backends.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';

class _ScopedFiles extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
  final active = <String, int>{};
  final denied = <String>{};

  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    if (denied.contains(path)) throw FileSystemException('Access denied', path);
    active.update(path, (count) => count + 1, ifAbsent: () => 1);
    try {
      return await action();
    } finally {
      active.update(path, (count) => count - 1);
    }
  }

  @override
  Future<String> getSafeFallbackDirectory() async => '/fallback';
}

class _Connection implements TerminalConnection {
  final ended = Completer<int?>();
  final outputController = StreamController<String>();
  var closes = 0;

  @override
  bool get isSandbox => true;
  @override
  Future<int?> get exitCode => ended.future;
  @override
  Stream<String> get output => outputController.stream;
  @override
  Future<void> write(String data) async {}
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    closes++;
    if (!ended.isCompleted) ended.complete(0);
    if (!outputController.isClosed) unawaited(outputController.close());
  }
}

void main() {
  test(
    'each local connection owns its own access grant until exit or close',
    () async {
      final files = _ScopedFiles();
      final first = _Connection();
      final second = _Connection();
      final a = await openScopedLocalTerminal(
        files,
        '/a',
        80,
        24,
        opener: (path, columns, rows) async {
          expect(files.active[path], 1);
          expect((columns, rows), (80, 24));
          return first;
        },
      );
      final b = await openScopedLocalTerminal(
        files,
        '/b',
        100,
        30,
        opener: (path, columns, rows) async => second,
      );
      expect(files.active, {'/a': 1, '/b': 1});
      expect(a.isSandbox, isTrue);
      await a.close();
      await a.close();
      expect(first.closes, 1);
      expect(files.active, {'/a': 0, '/b': 1});
      second.ended.complete(7);
      expect(await b.exitCode, 7);
      expect(files.active, {'/a': 0, '/b': 0});
      await b.close();
    },
  );

  test(
    'closed output does not release access before the process exits',
    () async {
      final files = _ScopedFiles();
      final inner = _Connection();
      final connection = await openScopedLocalTerminal(
        files,
        '/a',
        80,
        24,
        opener: (_, _, _) async => inner,
      );
      final done = connection.output.drain<void>();
      await inner.outputController.close();
      await done;
      expect(files.active['/a'], 1);
      inner.ended.complete(0);
      expect(await connection.exitCode, 0);
      expect(files.active['/a'], 0);
    },
  );

  test('failed opening releases the grant without changing the requested directory', () async {
    final files = _ScopedFiles();
    await expectLater(
      openScopedLocalTerminal(
        files,
        '/a',
        80,
        24,
        opener: (_, _, _) async => throw StateError('cannot start'),
      ),
      throwsStateError,
    );
    expect(files.active, {'/a': 0});
  });

  test('a denied directory uses a separately owned fallback grant', () async {
    final files = _ScopedFiles()..denied.add('/denied');
    final inner = _Connection();
    final connection = await openScopedLocalTerminal(
      files,
      '/denied',
      80,
      24,
      opener: (path, _, _) async {
        expect(path, '/fallback');
        expect(files.active[path], 1);
        return inner;
      },
    );
    expect(files.active, {'/fallback': 1});
    await connection.close();
    expect(files.active, {'/fallback': 0});
  });
}
