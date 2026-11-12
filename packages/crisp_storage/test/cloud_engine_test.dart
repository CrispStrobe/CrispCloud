import 'dart:async';

import 'package:crisp_storage/rust_cloud.dart';
import 'package:crisp_storage/rust_cloud_testing.dart';
import 'package:test/test.dart';

void main() {
  group('engine selection', () {
    test('parseCloudEngine accepts only known names', () {
      expect(parseCloudEngine(null), isNull);
      expect(parseCloudEngine(''), isNull);
      expect(parseCloudEngine('dart'), CloudEngine.dart);
      expect(parseCloudEngine('rust'), CloudEngine.rust);
      expect(parseCloudEngine('auto'), CloudEngine.auto);
      expect(() => parseCloudEngine('Rust'), throwsFormatException);
      expect(() => parseCloudEngine('libsmb2'), throwsFormatException);
      expect(() => parseCloudEngine(1), throwsFormatException);
    });

    test('build default is dart and overrides are validated', () {
      expect(configuredCloudEngine(RustCloudProvider.filen), CloudEngine.dart);
      expect(
        configuredCloudEngine(RustCloudProvider.internxt),
        CloudEngine.dart,
      );
      expect(
        configuredCloudEngine(RustCloudProvider.filen, override: 'auto'),
        CloudEngine.auto,
      );
      expect(
        () => configuredCloudEngine(RustCloudProvider.internxt, override: 'x'),
        throwsArgumentError,
      );
    });

    test('dart never loads rust', () async {
      var loads = 0;
      expect(
        await selectCloudEngine(CloudEngine.dart, () async => loads++),
        CloudEngine.dart,
      );
      expect(loads, 0);
    });

    test('rust and auto use rust when it loads', () async {
      for (final requested in [CloudEngine.rust, CloudEngine.auto]) {
        expect(
          await selectCloudEngine(requested, () async {}),
          CloudEngine.rust,
        );
      }
    });

    test('auto falls back only for unavailability', () async {
      expect(
        await selectCloudEngine(
          CloudEngine.auto,
          () async => throw const RustCloudUnavailable(),
        ),
        CloudEngine.dart,
      );
      await expectLater(
        selectCloudEngine(CloudEngine.auto, () async => throw StateError('x')),
        throwsStateError,
      );
    });

    test('strict rust surfaces unavailability', () async {
      await expectLater(
        selectCloudEngine(
          CloudEngine.rust,
          () async => throw const RustCloudUnavailable(),
        ),
        throwsA(isA<RustCloudUnavailable>()),
      );
    });

    test('unavailable message is actionable and secret-free', () {
      expect(
        const RustCloudUnavailable().toString(),
        contains('not available'),
      );
      expect(
        const RustCloudUnavailable('browser build').toString(),
        contains('browser build'),
      );
    });
  });

  group('errors', () {
    test('parses native JSON codes', () {
      final e = RustCloudException.fromNative(
        '{"code":"RateLimited","retryable":true,"status":429}',
      );
      expect(e.code, RustCloudErrorCode.rateLimited);
      expect(e.retryable, isTrue);
      expect(e.status, 429);
    });

    test('maps every native code name', () {
      for (final code in RustCloudErrorCode.values) {
        final native = code.name[0].toUpperCase() + code.name.substring(1);
        expect(
          RustCloudException.fromNative('{"code":"$native"}').code,
          code,
          reason: native,
        );
      }
    });

    test('unknown codes and garbage never echo the message', () {
      expect(
        RustCloudException.fromNative('{"code":"Brand New"}').code,
        RustCloudErrorCode.provider,
      );
      final e = RustCloudException.fromNative('secret /private/path');
      expect(e.code, RustCloudErrorCode.internal);
      expect(e.toString(), isNot(contains('secret')));
    });

    test('requiresLogin classifies session problems', () {
      expect(
        const RustCloudException(RustCloudErrorCode.authFailed).requiresLogin,
        isTrue,
      );
      expect(
        const RustCloudException(
          RustCloudErrorCode.sessionExpired,
        ).requiresLogin,
        isTrue,
      );
      expect(
        const RustCloudException(
          RustCloudErrorCode.sessionExpired,
          retryable: true,
        ).requiresLogin,
        isFalse,
      );
      expect(
        const RustCloudException(RustCloudErrorCode.network).requiresLogin,
        isFalse,
      );
    });

    test('messages name provider and engine', () {
      const e = RustCloudException(
        RustCloudErrorCode.twoFactorRequired,
        provider: RustCloudProvider.internxt,
      );
      expect(e.toString(), contains('Internxt (Rust engine)'));
      expect(e.toString(), contains('two-factor'));
    });
  });

  group('session envelope', () {
    test('accepts a v1 envelope for the expected provider', () {
      final parsed = RustCloudSessionEnvelope.parse(
        FakeRustCloudApi.envelope('filen'),
        RustCloudProvider.filen,
      );
      expect(parsed.account, 'a@b.c');
      expect(parsed.provider, RustCloudProvider.filen);
    });

    RustCloudErrorCode codeOf(String raw, RustCloudProvider p) {
      try {
        RustCloudSessionEnvelope.parse(raw, p);
      } on RustCloudException catch (e) {
        return e.code;
      }
      fail('accepted $raw');
    }

    test('rejects provider mismatch', () {
      expect(
        codeOf(FakeRustCloudApi.envelope('filen'), RustCloudProvider.internxt),
        RustCloudErrorCode.providerMismatch,
      );
    });

    test('rejects future versions', () {
      final raw = FakeRustCloudApi.envelope('filen').replaceFirst(
        '"version":1',
        '"version":2',
      );
      expect(
        codeOf(raw, RustCloudProvider.filen),
        RustCloudErrorCode.unsupportedSessionVersion,
      );
    });

    test('rejects Dart credential maps and malformed data', () {
      for (final raw in [
        '{"email":"a","apiKey":"k","masterKeys":"m"}',
        '{"token":"t","mnemonic":"m"}',
        'nope',
        '[]',
        '{"format":"crisp-cloud-rust-session","version":"1"}',
        '{"format":"crisp-cloud-rust-session","version":1,"provider":"x","account":"a","session":{}}',
        '{"format":"crisp-cloud-rust-session","version":1,"provider":"filen","account":"a","session":"s"}',
      ]) {
        expect(
          codeOf(raw, RustCloudProvider.filen),
          RustCloudErrorCode.invalidSession,
          reason: raw,
        );
      }
    });
  });

  group('RustCloudSession', () {
    late FakeRustCloudApi api;
    setUp(() {
      api = FakeRustCloudApi();
      RustCloudSession.progressInterval = const Duration(milliseconds: 5);
    });

    test('login passes the 2FA code and opens the returned envelope', () async {
      final session = await RustCloudSession.login(
        api,
        RustCloudProvider.filen,
        'me@x.y',
        'pw',
        twoFactorCode: '123456',
      );
      expect(api.calls, ['login:filen:me@x.y:123456', 'open:filen']);
      expect(session.envelope, contains('me@x.y'));
      expect(session.account, 'a@b.c');
      expect(session.rootId, 'root-uuid');
    });

    test('login errors carry the provider and do not open', () async {
      api.loginError = const RustCloudException(RustCloudErrorCode.authFailed);
      await expectLater(
        RustCloudSession.login(api, RustCloudProvider.internxt, 'a', 'b'),
        throwsA(
          isA<RustCloudException>()
              .having((e) => e.code, 'code', RustCloudErrorCode.authFailed)
              .having(
                (e) => e.provider,
                'provider',
                RustCloudProvider.internxt,
              ),
        ),
      );
      expect(api.calls.where((c) => c.startsWith('open')), isEmpty);
    });

    test('restore validates the envelope before calling native code', () async {
      await expectLater(
        RustCloudSession.restore(
          api,
          RustCloudProvider.filen,
          '{"apiKey":"legacy"}',
        ),
        throwsA(isA<RustCloudException>()),
      );
      expect(api.calls, isEmpty);
    });

    test('list decodes entries', () async {
      final session = await RustCloudSession.restore(
        api,
        RustCloudProvider.filen,
        FakeRustCloudApi.envelope('filen'),
      );
      final entries = await session.list('/', fresh: true);
      expect(api.calls.last, 'list:/:true');
      expect(entries.map((e) => e.name), ['Docs', 'a.txt']);
      expect(entries.first.isDirectory, isTrue);
      expect(entries.last.size, 3);
      expect(entries.last.mime, 'text/plain');
      expect(
        entries.last.modified,
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
    });

    test('mutations forward paths', () async {
      final session = await RustCloudSession.restore(
        api,
        RustCloudProvider.filen,
        FakeRustCloudApi.envelope('filen'),
      );
      expect((await session.mkdir('/a/b')).name, 'b');
      await session.rename('/a/b', 'c');
      await session.move('/a/c', '/z');
      await session.trash('/z/c');
      expect((await session.stat('/z/x')).name, 'x');
      expect(api.calls.skip(1), [
        'mkdir:/a/b',
        'rename:/a/b:c',
        'move:/a/c:/z',
        'trash:/z/c',
        'stat:/z/x',
      ]);
    });

    test('transfers report final progress and release handles', () async {
      final session = await RustCloudSession.restore(
        api,
        RustCloudProvider.filen,
        FakeRustCloudApi.envelope('filen'),
      );
      final seen = <List<int>>[];
      final bytes = await session.upload(
        '/tmp/x',
        '/',
        'x',
        onProgress: (d, t) => seen.add([d, t]),
      );
      expect(bytes, 10);
      expect(seen.last, [10, 10]);
      expect(api.released, hasLength(1));
    });

    test('cancellation reaches the native transfer', () async {
      final session = await RustCloudSession.restore(
        api,
        RustCloudProvider.filen,
        FakeRustCloudApi.envelope('filen'),
      );
      api.downloadGate = Completer<int>();
      final cancellation = RustCloudCancellation();
      final progress = <int>[];
      final future = session.download(
        '/a',
        '/tmp/a',
        cancellation: cancellation,
        onProgress: (d, _) => progress.add(d),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(progress, contains(5));
      cancellation.cancel();
      api.downloadGate!.complete(0);
      await expectLater(
        future,
        throwsA(
          isA<RustCloudException>().having(
            (e) => e.code,
            'code',
            RustCloudErrorCode.cancelled,
          ),
        ),
      );
      expect(api.cancelled, hasLength(1));
      expect(api.released, hasLength(1));
    });

    test('cancellation listeners fire once, also when late', () {
      final c = RustCloudCancellation();
      var calls = 0;
      final remove = c.listen(() => calls++);
      c.cancel();
      c.cancel();
      expect(calls, 1);
      remove();
      c.listen(() => calls++);
      expect(calls, 2);
      expect(c.isCancelled, isTrue);
    });

    test('renewed envelopes are reported once per revision', () async {
      final session = await RustCloudSession.restore(
        api,
        RustCloudProvider.filen,
        FakeRustCloudApi.envelope('filen'),
      );
      expect(await session.takeRenewedEnvelope(), isNull);
      api.revisionValue = 2;
      final renewed = await session.takeRenewedEnvelope();
      expect(renewed, contains('renewed@b.c'));
      expect(session.envelope, renewed);
      expect(await session.takeRenewedEnvelope(), isNull);
    });

    test('closed sessions reject calls and close natively once', () async {
      final session = await RustCloudSession.restore(
        api,
        RustCloudProvider.internxt,
        FakeRustCloudApi.envelope('internxt'),
      );
      session.close();
      session.close();
      expect(api.closed, hasLength(1));
      await expectLater(
        session.list('/'),
        throwsA(
          isA<RustCloudException>().having(
            (e) => e.code,
            'code',
            RustCloudErrorCode.closed,
          ),
        ),
      );
      expect(await session.takeRenewedEnvelope(), isNull);
    });

    test('native errors get the session provider attached', () async {
      final session = await RustCloudSession.restore(
        api,
        RustCloudProvider.internxt,
        FakeRustCloudApi.envelope('internxt'),
      );
      api.nextError = const RustCloudException(
        RustCloudErrorCode.notFound,
      );
      await expectLater(
        session.stat('/missing'),
        throwsA(
          isA<RustCloudException>().having(
            (e) => e.provider,
            'provider',
            RustCloudProvider.internxt,
          ),
        ),
      );
    });
  });
}
