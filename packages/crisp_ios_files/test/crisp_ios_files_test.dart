import 'dart:async';

import 'package:crisp_ios_files/crisp_ios_files.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('crisp_ios_files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late IosFilesClient client;
  late List<MethodCall> calls;
  Future<Object?> Function(MethodCall)? response;

  Map<String, Object> entry(String path, {String kind = 'file'}) => {
    'path': path,
    'kind': kind,
    'size': 12,
    'modifiedMs': 1700000000000,
  };

  setUp(() {
    client = IosFilesClient();
    calls = [];
    response = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (response != null) return response!(call);
      return switch (call.method) {
        'pickDirectory' || 'restoreLastDirectory' => '/provider/folder',
        'acquireAccess' => {
          'path': (call.arguments as Map)['path'],
          'token': 'lease-${calls.length}',
        },
        'hasAccess' => true,
        'listDirectory' || 'walkFiles' => [entry('/provider/folder/file')],
        'readFile' => Uint8List.fromList([1, 2, 3]),
        'fileLength' => 3,
        _ => null,
      };
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('normalizes absolute paths and rejects relative/NUL paths', () {
    expect(normalizeIosFilePath('/a/./b/../c'), '/a/c');
    expect(normalizeIosFilePath('/'), '/');
    for (final path in ['', 'relative', 'file:///a', '/a\u0000b']) {
      expect(() => normalizeIosFilePath(path), throwsArgumentError);
    }
  });

  test(
    'picker supplies initial directory and preserves cancellation',
    () async {
      expect(
        await client.pickDirectory(initialDirectory: '/folder/../start'),
        '/provider/folder',
      );
      expect(calls.single.method, 'pickDirectory');
      expect(calls.single.arguments, {'initialDirectory': '/start'});
      response = (_) async => null;
      expect(await client.pickDirectory(), isNull);
      expect(calls.last.arguments, isEmpty);
    },
  );

  test(
    'restore returns canonical refreshed path or no previous grant',
    () async {
      response = (_) async => '/provider/renamed/./';
      expect(await client.restoreLastDirectory(), '/provider/renamed');
      expect(calls.single.method, 'restoreLastDirectory');
      response = (_) async => null;
      expect(await client.restoreLastDirectory(), isNull);
    },
  );

  test(
    'native picker/restore errors propagate and invalid paths are rejected',
    () async {
      response = (_) async => throw PlatformException(code: 'access_denied');
      await expectLater(
        client.pickDirectory(),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        client.restoreLastDirectory(),
        throwsA(isA<PlatformException>()),
      );
      response = (_) async => 'relative';
      await expectLater(client.pickDirectory(), throwsArgumentError);
      await expectLater(client.restoreLastDirectory(), throwsArgumentError);
    },
  );

  test(
    'independent leases release only their own token and are idempotent',
    () async {
      final first = await client.acquireAccess('/provider/folder/./a');
      final second = await client.acquireAccess('/provider/folder/b');
      expect(first.path, '/provider/folder/a');
      expect(first.token, isNot(second.token));
      await second.release();
      await second.release();
      expect(calls.where((call) => call.method == 'releaseAccess').length, 1);
      expect(calls.last.arguments, {'token': second.token});
      await first.release();
      expect(calls.last.arguments, {'token': first.token});
    },
  );

  test(
    'concurrent release joins same operation; failed release can retry',
    () async {
      final gate = Completer<void>();
      response = (call) async {
        if (call.method == 'acquireAccess') {
          return {'path': '/folder', 'token': 'a'};
        }
        await gate.future;
        return null;
      };
      final lease = await client.acquireAccess('/folder');
      final a = lease.release();
      final b = lease.release();
      expect(identical(a, b), isTrue);
      gate.complete();
      await Future.wait([a, b]);
      expect(calls.where((c) => c.method == 'releaseAccess').length, 1);

      var attempts = 0;
      response = (call) async {
        if (call.method == 'acquireAccess') {
          return {'path': '/folder', 'token': 'b'};
        }
        if (++attempts == 1) throw PlatformException(code: 'transport_failure');
        return null;
      };
      final retry = await client.acquireAccess('/folder');
      await expectLater(retry.release(), throwsA(isA<PlatformException>()));
      await retry.release();
      expect(attempts, 2);
    },
  );

  test('invalid or denied native lease never invokes operation', () async {
    for (final malformed in [
      null,
      <String, Object>{},
      {'path': '/a', 'token': ''},
      {'path': '/a', 'token': 3},
    ]) {
      response = (_) async => malformed;
      await expectLater(client.acquireAccess('/a'), throwsFormatException);
    }
    response = (_) async => throw PlatformException(code: 'access_denied');
    var ran = false;
    await expectLater(
      client.withAccess('/a', (_) async {
        ran = true;
      }),
      throwsA(isA<PlatformException>()),
    );
    expect(ran, isFalse);
  });

  test('malformed native path releases an otherwise valid token', () async {
    response = (call) async {
      if (call.method == 'acquireAccess') {
        return {'path': 'relative', 'token': 'stranded'};
      }
      return null;
    };
    await expectLater(client.acquireAccess('/a'), throwsArgumentError);
    expect(calls.last.method, 'releaseAccess');
    expect(calls.last.arguments, {'token': 'stranded'});
    response = (call) async =>
        call.method == 'acquireAccess' ? {'token': 'no-path'} : null;
    await expectLater(client.acquireAccess('/a'), throwsFormatException);
    expect(calls.last.arguments, {'token': 'no-path'});
  });

  test('callback cleanup retries one transient transport failure', () async {
    var releases = 0;
    response = (call) async {
      if (call.method == 'acquireAccess') {
        return {'path': '/a', 'token': 'lease'};
      }
      if (++releases == 1) throw PlatformException(code: 'transport');
      return null;
    };
    expect(await client.withAccess('/a', (_) async => 'saved'), 'saved');
    expect(releases, 2);
  });

  test(
    'withAccess holds scope through async work and releases after completion',
    () async {
      final entered = Completer<void>();
      final gate = Completer<int>();
      final operation = client.withAccess('/provider/folder', (path) {
        expect(path, '/provider/folder');
        entered.complete();
        return gate.future;
      });
      await entered.future;
      expect(calls.map((c) => c.method), ['acquireAccess']);
      gate.complete(42);
      expect(await operation, 42);
      expect(calls.map((c) => c.method), ['acquireAccess', 'releaseAccess']);
    },
  );

  test(
    'withAccess preserves action failure and completed write when cleanup fails',
    () async {
      response = (call) async {
        if (call.method == 'acquireAccess') {
          return {'path': '/a', 'token': 'lease'};
        }
        throw PlatformException(code: 'release_failure');
      };
      final original = StateError('original');
      await expectLater(
        client.withAccess<void>('/a', (_) async => throw original),
        throwsA(same(original)),
      );
      expect(await client.withAccess('/a', (_) async => 'saved'), 'saved');
    },
  );

  test('hasAccess delegates native proof and null means false', () async {
    expect(await client.hasAccess('/provider/./folder'), isTrue);
    expect(calls.last.arguments, {'path': '/provider/folder'});
    response = (_) async => null;
    expect(await client.hasAccess('/a'), isFalse);
    response = (_) async => throw PlatformException(code: 'file_error');
    await expectLater(
      client.hasAccess('/a'),
      throwsA(isA<PlatformException>()),
    );
  });

  test('lists and walks metadata with exact recursion options', () async {
    final entries = await client.listDirectory('/provider/folder');
    expect(entries.single.path, '/provider/folder/file');
    expect(entries.single.kind, 'file');
    expect(entries.single.size, 12);
    expect(entries.single.modifiedAt.millisecondsSinceEpoch, 1700000000000);
    await client.walkFiles(
      '/provider/folder',
      includeHidden: true,
      maxItems: 2,
    );
    expect(calls.last.arguments, {
      'path': '/provider/folder',
      'includeHidden': true,
      'maxItems': 2,
    });
    await client.walkFiles('/provider/folder');
    expect((calls.last.arguments as Map)['maxItems'], 10000);
    expect(() => client.walkFiles('/a', maxItems: -1), throwsArgumentError);
  });

  test('malformed native listings fail instead of looking empty', () async {
    for (final malformed in [
      null,
      ['invalid'],
      [
        {'path': '/a'},
      ],
    ]) {
      response = (_) async => malformed;
      await expectLater(client.listDirectory('/a'), throwsFormatException);
      await expectLater(client.walkFiles('/a'), throwsFormatException);
    }
    response = (_) async => [];
    expect(await client.listDirectory('/a'), isEmpty);
  });

  test(
    'metadata supports file directory and link and rejects malformed fields',
    () {
      for (final kind in ['file', 'directory', 'link']) {
        expect(IosFileEntry.fromMap(entry('/a/./b', kind: kind)).path, '/a/b');
      }
      for (final malformed in [
        {'path': '/a', 'kind': 'socket', 'size': 1, 'modifiedMs': 1},
        {'path': 3, 'kind': 'file', 'size': 1, 'modifiedMs': 1},
        {'path': '/a', 'kind': 'file', 'size': '1', 'modifiedMs': 1},
        {'path': '/a', 'kind': 'file', 'size': 1, 'modifiedMs': null},
      ]) {
        expect(() => IosFileEntry.fromMap(malformed), throwsFormatException);
      }
      expect(
        () => IosFileEntry.fromMap(entry('relative')),
        throwsArgumentError,
      );
    },
  );

  test('reads bytes and length; absent bytes are an error', () async {
    expect(await client.readFile('/a'), [1, 2, 3]);
    expect(await client.fileLength('/a'), 3);
    response = (_) async => null;
    await expectLater(client.readFile('/a'), throwsFormatException);
    expect(await client.fileLength('/a'), isNull);
  });

  test(
    'writes create and delete pass normalized paths and explicit intent',
    () async {
      final data = Uint8List.fromList([1, 2]);
      await client.writeFile('/a/../file', data, overwrite: false);
      expect(calls.last.arguments, {
        'path': '/file',
        'bytes': data,
        'overwrite': false,
      });
      await client.writeFile('/file', data);
      expect((calls.last.arguments as Map)['overwrite'], isTrue);
      await client.createDirectory('/a/./b');
      expect(calls.last.method, 'createDirectory');
      expect(calls.last.arguments, {'path': '/a/b'});
      await client.deleteEntry('/a/./b', isFolder: true);
      expect(calls.last.arguments, {'path': '/a/b', 'isFolder': true});
      await client.deleteEntry('/a/file', isFolder: false);
      expect((calls.last.arguments as Map)['isFolder'], isFalse);
    },
  );

  test('every mutating/read method propagates native failures', () async {
    response = (_) async => throw PlatformException(code: 'provider_failed');
    final operations = <Future<Object?> Function()>[
      () => client.listDirectory('/a'),
      () => client.walkFiles('/a'),
      () => client.readFile('/a'),
      () => client.writeFile('/a', Uint8List(0)),
      () => client.createDirectory('/a'),
      () => client.deleteEntry('/a', isFolder: false),
      () => client.fileLength('/a'),
    ];
    for (final operation in operations) {
      await expectLater(operation(), throwsA(isA<PlatformException>()));
    }
  });

  test('a supplied channel is honored', () async {
    const custom = MethodChannel('files-test-custom');
    messenger.setMockMethodCallHandler(custom, (_) async => '/custom');
    addTearDown(() => messenger.setMockMethodCallHandler(custom, null));
    expect(
      await IosFilesClient(channel: custom).restoreLastDirectory(),
      '/custom',
    );
    expect(calls, isEmpty);
  });
}
