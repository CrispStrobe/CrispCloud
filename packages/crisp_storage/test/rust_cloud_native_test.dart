// Exercises the real FFI bridge without network access. Skips unless
// CRISP_CLOUD_LIBRARY points at a built crisp_cloud_bridge library:
//   dart run bin/build_cloud.dart   (prints the path)
import 'dart:convert';
import 'dart:io';

import 'package:crisp_storage/rust_cloud.dart';
import 'package:test/test.dart';

String _filenEnvelope({String account = 'f@example.com'}) => jsonEncode({
  'format': 'crisp-cloud-rust-session',
  'version': 1,
  'provider': 'filen',
  'account': account,
  'session': {
    'gateway_url': 'http://127.0.0.1:9',
    'ingest_url': 'http://127.0.0.1:9',
    'egest_url': 'http://127.0.0.1:9',
    'email': 'f@example.com',
    'api_key': 'key',
    'auth_version': 2,
    'file_encryption_version': 2,
    'metadata_encryption_version': 2,
    'root_folder_uuid': 'root-f',
    'master_keys': [
      [1, 2, 3],
    ],
    'dek': null,
    'kek': null,
    'private_key': null,
    'hmac_key': null,
  },
});

void main() {
  final library = Platform.environment['CRISP_CLOUD_LIBRARY'];
  final skip = library == null || library.isEmpty
      ? 'Set CRISP_CLOUD_LIBRARY to the built crisp_cloud_bridge library'
      : null;

  group('native Rust cloud bridge', skip: skip, () {
    final api = defaultRustCloudApi();
    setUpAll(api.initialize);

    test('initialize is idempotent', () async {
      await api.initialize();
      await api.initialize();
    });

    test('opens a stored envelope without network and reports info', () async {
      final session = await RustCloudSession.restore(
        api,
        RustCloudProvider.filen,
        _filenEnvelope(),
      );
      expect(session.account, 'f@example.com');
      expect(session.rootId, 'root-f');
      expect(await session.takeRenewedEnvelope(), isNull);
      await expectLater(
        api.export(-1 >>> 1),
        throwsA(
          isA<RustCloudException>().having(
            (e) => e.code,
            'code',
            RustCloudErrorCode.closed,
          ),
        ),
      );
      session.close();
      await expectLater(
        session.list('/'),
        throwsA(isA<RustCloudException>()),
      );
    });

    test('native validation rejects identity mismatch', () async {
      await expectLater(
        api.open(RustCloudProvider.filen, _filenEnvelope(account: 'x@y.z')),
        throwsA(
          isA<RustCloudException>().having(
            (e) => e.code,
            'code',
            RustCloudErrorCode.invalidSession,
          ),
        ),
      );
    });

    test('native validation rejects provider mismatch', () async {
      await expectLater(
        api.open(RustCloudProvider.internxt, _filenEnvelope()),
        throwsA(
          isA<RustCloudException>().having(
            (e) => e.code,
            'code',
            RustCloudErrorCode.providerMismatch,
          ),
        ),
      );
    });

    test('login validates arguments before any network request', () async {
      await expectLater(
        api.login(RustCloudProvider.filen, '', 'pw', null),
        throwsA(
          isA<RustCloudException>().having(
            (e) => e.code,
            'code',
            RustCloudErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('unreachable gateway maps to a typed error, not a crash', () async {
      final session = await RustCloudSession.restore(
        api,
        RustCloudProvider.filen,
        _filenEnvelope(),
      );
      try {
        await expectLater(
          session.list('/'),
          throwsA(isA<RustCloudException>()),
        );
      } finally {
        session.close();
      }
    });

    test('transfer handles: progress, cancel, release', () {
      final t = api.newTransfer();
      expect(api.progress(t), [0, 0]);
      api.cancel(t);
      api.release(t);
      expect(
        () => api.progress(t),
        throwsA(
          isA<RustCloudException>().having(
            (e) => e.code,
            'code',
            RustCloudErrorCode.closed,
          ),
        ),
      );
    });

    test('download into a missing local folder fails without network side '
        'effects', () async {
      final session = await RustCloudSession.restore(
        api,
        RustCloudProvider.filen,
        _filenEnvelope(),
      );
      try {
        await expectLater(
          session.download('/x', '/nonexistent-dir-crisp/x'),
          throwsA(isA<RustCloudException>()),
        );
      } finally {
        session.close();
      }
    });
  });
}
