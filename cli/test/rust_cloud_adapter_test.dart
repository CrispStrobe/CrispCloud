import 'dart:convert';
import 'dart:io';

import 'package:crisp/adapters/cli_adapter_factory.dart';
import 'package:crisp/adapters/cli_storage_client.dart';
import 'package:crisp/adapters/rust_cloud_adapter.dart';
import 'package:crisp/config/cli_config.dart';
import 'package:crisp_storage/rust_cloud.dart';
import 'package:crisp_storage/rust_cloud_testing.dart';
import 'package:test/test.dart';

RustCloudCliAdapter _adapter(
  FakeRustCloudApi api, {
  String type = 'filen',
  Map<String, dynamic>? extra,
}) => RustCloudCliAdapter.fromConfig(type, {
  'email': 'user@example.com',
  'password': 'secret',
  ...?extra,
}, api: api);

void main() {
  group('config', () {
    test('factory routes filen and internxt to the Rust adapter', () {
      for (final type in ['filen', 'internxt', 'Filen', 'INTERNXT']) {
        expect(
          createAdapter('p', {'type': type, 'email': 'a@b.c', 'password': 'x'}),
          isA<RustCloudCliAdapter>(),
          reason: type,
        );
      }
    });

    test('provider names', () {
      final api = FakeRustCloudApi();
      expect(_adapter(api).providerName, 'Filen');
      expect(_adapter(api, type: 'internxt').providerName, 'Internxt');
    });

    test('email and password are required', () {
      expect(
        () => RustCloudCliAdapter.fromConfig('filen', {'password': 'x'}),
        throwsA(isA<CliConfigException>()),
      );
      expect(
        () => RustCloudCliAdapter.fromConfig('filen', {'email': 'a@b.c'}),
        throwsA(isA<CliConfigException>()),
      );
      expect(
        () => RustCloudCliAdapter.fromConfig('internxt', {
          'email': '',
          'password': 'x',
        }),
        throwsA(isA<CliConfigException>()),
      );
    });

    test('only the Rust engine is accepted', () {
      expect(
        () => _adapter(FakeRustCloudApi(), extra: {'engine': 'dart'}),
        throwsA(isA<CliConfigException>()),
      );
      expect(
        _adapter(FakeRustCloudApi(), extra: {'engine': 'rust'}),
        isA<RustCloudCliAdapter>(),
      );
    });

    test('twoFactorCode must be a string', () {
      expect(
        () => _adapter(FakeRustCloudApi(), extra: {'twoFactorCode': 123456}),
        throwsA(isA<CliConfigException>()),
      );
    });

    test('unknown types still list the supported providers', () {
      expect(
        () => createAdapter('p', {'type': 'dropbox'}),
        throwsA(
          isA<CliConfigException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('filen'), contains('internxt')),
          ),
        ),
      );
    });
  });

  group('engine availability', () {
    test('a missing native library is a config error before sign-in', () async {
      final api = FakeRustCloudApi()..available = false;
      final adapter = _adapter(api);
      await expectLater(
        adapter.list('/'),
        throwsA(
          isA<CliConfigException>().having(
            (e) => e.toString(),
            'message',
            contains('CRISP_CLOUD_LIBRARY'),
          ),
        ),
      );
      expect(api.calls.where((c) => c.startsWith('login')), isEmpty);
    });

    test('signs in once and reuses the session', () async {
      final api = FakeRustCloudApi();
      final adapter = _adapter(api);
      await adapter.list('/');
      await adapter.list('/Docs');
      expect(api.calls.where((c) => c.startsWith('login')), hasLength(1));
      await adapter.dispose();
      expect(api.closed, hasLength(1));
    });

    test('sign-in errors surface without retrying another engine', () async {
      final api = FakeRustCloudApi()
        ..loginError = const RustCloudException(RustCloudErrorCode.authFailed);
      await expectLater(
        _adapter(api).list('/'),
        throwsA(isA<RustCloudException>()),
      );
    });
  });

  group('operations', () {
    late FakeRustCloudApi api;
    late RustCloudCliAdapter adapter;
    setUp(() {
      api = FakeRustCloudApi();
      adapter = _adapter(api);
    });
    tearDown(() => adapter.dispose());

    test('paths are normalized before reaching the engine', () async {
      await adapter.createDirectory('Docs//Reports/');
      expect(api.calls.last, contains('/Docs/Reports'));
    });

    test('delete trashes the item', () async {
      await adapter.delete('/a.txt');
      expect(api.calls.last, startsWith('trash'));
      expect(api.calls.last, contains('/a.txt'));
    });

    test('move within a folder renames only', () async {
      await adapter.move('/Docs/a.txt', '/Docs/b.txt');
      final ops = api.calls.where(
        (c) => c.startsWith('move') || c.startsWith('rename'),
      );
      expect(ops, hasLength(1));
      expect(ops.single, startsWith('rename'));
    });

    test('move to another folder keeps the name', () async {
      await adapter.move('/Docs/a.txt', '/Archive/a.txt');
      final ops = api.calls
          .where((c) => c.startsWith('move') || c.startsWith('rename'))
          .toList();
      expect(ops, hasLength(1));
      expect(ops.single, startsWith('move'));
    });

    test('move and rename together does both, in order', () async {
      await adapter.move('/Docs/a.txt', '/Archive/b.txt');
      final ops = api.calls
          .where((c) => c.startsWith('move') || c.startsWith('rename'))
          .toList();
      expect(ops.map((c) => c.split(':').first), ['move', 'rename']);
      expect(ops.last, contains('/Archive/a.txt'));
    });

    test(
      'in-memory uploads are spooled to a temp file and cleaned up',
      () async {
        String? spooled;
        api.onUploadFile = (path) {
          spooled = path;
          expect(File(path).readAsBytesSync(), utf8.encode('hello'));
        };
        await adapter.upload(utf8.encode('hello'), 'h.txt', '/Docs');
        expect(spooled, isNotNull);
        expect(File(spooled!).existsSync(), isFalse);
      },
    );

    test('streaming upload passes the local file through', () async {
      final dir = await Directory.systemTemp.createTemp('cli-rc-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/big.bin')..writeAsBytesSync([1, 2, 3]);
      String? seen;
      api.onUploadFile = (path) => seen = path;
      await uploadLocalFile(adapter, file, 'big.bin', '/');
      expect(seen, file.path);
    });

    test(
      'downloadBytes returns the content and removes the temp file',
      () async {
        String? written;
        api.onDownloadFile = (path) {
          written = path;
          File(path).writeAsBytesSync([9, 8, 7]);
        };
        expect(await adapter.downloadBytes('/x.bin'), [9, 8, 7]);
        expect(File(written!).existsSync(), isFalse);
      },
    );

    test('stat returns null for not-found and rethrows other errors', () async {
      await adapter.list('/'); // open the session first
      api.nextError = const RustCloudException(RustCloudErrorCode.notFound);
      expect(await adapter.stat('/missing'), isNull);
      api.nextError = const RustCloudException(RustCloudErrorCode.rateLimited);
      await expectLater(adapter.stat('/x'), throwsA(isA<RustCloudException>()));
    });

    test('share is not supported', () async {
      expect(() => adapter.share('/a'), throwsUnsupportedError);
    });
  });
}
