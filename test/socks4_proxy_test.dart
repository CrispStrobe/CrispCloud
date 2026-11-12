import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/proxy_service.dart';
import 'package:crisp_cloud/services/socks4_connector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/socks4_fixture.dart';

SecurityContext _trust() =>
    SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/fixtures/tls/ca.pem');

SecurityContext _serverContext(String certificate) => SecurityContext()
  ..useCertificateChain('test/fixtures/tls/$certificate')
  ..usePrivateKey('test/fixtures/tls/server.key');

Future<HttpServer> _origin({
  bool secure = false,
  String certificate = 'server.pem',
  void Function()? onRequest,
}) async {
  final server = secure
      ? await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          _serverContext(certificate),
        )
      : await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(
    (request) async {
      onRequest?.call();
      final body = await request.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      request.response.add(body.isEmpty ? utf8.encode('through SOCKS4') : body);
      await request.response.close();
    },
    onError: (Object error) {
      if (error is! TlsException && error is! SocketException) throw error;
    },
  );
  addTearDown(() => server.close(force: true));
  return server;
}

Future<Socks4Fixture> _proxy({
  int replyVersion = 0,
  int replyCode = 90,
  int replyLength = 8,
  bool fragmented = false,
  bool stallReply = false,
  bool stallAfterConnect = false,
  List<int>? inlinePayload,
}) async {
  final fixture = await Socks4Fixture.start(
    replyVersion: replyVersion,
    replyCode: replyCode,
    replyLength: replyLength,
    fragmentReplies: fragmented,
    stallReply: stallReply,
    stallAfterConnect: stallAfterConnect,
    inlinePayload: inlinePayload,
  );
  addTearDown(() async {
    await fixture.close();
    expect(fixture.errors, isEmpty);
  });
  return fixture;
}

HttpClient _client(
  Socks4Fixture fixture,
  ProxyType type, {
  SecurityContext? trust,
  String noProxy = '',
}) {
  final client = ProxyHttpOverrides(
    ProxyConfig(
      type: type,
      host: '127.0.0.1',
      port: fixture.port,
      username: 'test-user',
      noProxy: noProxy,
    ),
  ).createHttpClient(trust);
  addTearDown(() => client.close(force: true));
  return client;
}

Future<String> _get(HttpClient client, Uri uri) async =>
    utf8.decodeStream(await (await client.getUrl(uri)).close());

void main() {
  setUp(() => HttpOverrides.global = null);
  tearDown(() => HttpOverrides.global = null);

  for (final type in [ProxyType.socks4, ProxyType.socks4a]) {
    final remoteDns = type == ProxyType.socks4a;
    for (final secure in [false, true]) {
      test(
        '${type.name} ${secure ? 'HTTPS' : 'HTTP'} with fragmented reply, streaming and reuse',
        () async {
          final origin = await _origin(secure: secure);
          final proxy = await _proxy(fragmented: true);
          final client = _client(proxy, type, trust: _trust());
          final hostname = remoteDns && !secure
              ? 'no-local-dns.invalid'
              : 'localhost';
          final uri = Uri.parse(
            '${secure ? 'https' : 'http'}://$hostname:${origin.port}/item',
          );
          expect(await _get(client, uri), 'through SOCKS4');
          final request = proxy.requests.single;
          expect(request.remoteDns, remoteDns);
          expect(request.host, remoteDns ? hostname : '127.0.0.1');
          expect(request.address, remoteDns ? [0, 0, 0, 1] : [127, 0, 0, 1]);
          expect(request.port, origin.port);
          expect(request.userId, 'test-user');

          final upload = await client.postUrl(uri);
          final chunk = List<int>.generate(32 * 1024, (i) => i & 255);
          await upload.addStream(Stream.fromIterable(List.filled(64, chunk)));
          final body = StreamIterator(await upload.close());
          var offset = 0;
          while (await body.moveNext()) {
            if (offset == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            for (final byte in body.current) {
              if (byte != (offset & 255)) {
                fail('Payload changed at byte $offset');
              }
              offset++;
            }
          }
          await body.cancel();
          expect(offset, 2 * 1024 * 1024);
          expect(
            proxy.requests,
            hasLength(1),
            reason: 'The tunnel is reusable.',
          );
        },
      );
    }

    test(
      '${type.name} IPv4 literals skip DNS and retain coalesced bytes',
      () async {
        final payload = utf8.encode('ready without another read');
        final proxy = await _proxy(inlinePayload: payload);
        final task = await Socks4Connector(
          host: '127.0.0.1',
          port: proxy.port,
          remoteDns: remoteDns,
          lookup: (_) => throw StateError('Literal address must not resolve.'),
        ).connect(Uri.parse('http://192.0.2.25:8080'));
        final socket = await task.socket;
        expect(await socket.first, payload);
        socket.destroy();
        expect(proxy.requests.single.address, [192, 0, 2, 25]);
        expect(proxy.requests.single.userId, isEmpty);
        expect(proxy.requests.single.remoteDns, isFalse);
      },
    );

    for (final certificate in [
      'wrong-host.pem',
      'expired.pem',
      'forged-issuer.pem',
    ]) {
      test(
        '${type.name} HTTPS rejects $certificate before HTTP data',
        () async {
          var requests = 0;
          final origin = await _origin(
            secure: true,
            certificate: certificate,
            onRequest: () => requests++,
          );
          final proxy = await _proxy();
          await expectLater(
            _get(
              _client(proxy, type, trust: _trust()),
              Uri.parse('https://localhost:${origin.port}'),
            ),
            throwsA(isA<HandshakeException>()),
          );
          expect(requests, 0);
          expect(proxy.originsOpened, 1);
        },
      );
    }

    test(
      '${type.name} HTTPS keeps platform trust verification by default',
      () async {
        var requests = 0;
        final origin = await _origin(secure: true, onRequest: () => requests++);
        final proxy = await _proxy();
        await expectLater(
          _get(
            _client(proxy, type),
            Uri.parse('https://localhost:${origin.port}'),
          ),
          throwsA(isA<HandshakeException>()),
        );
        expect(requests, 0);
      },
    );

    for (final code in [91, 92, 93, 0, 95]) {
      test(
        '${type.name} rejects status $code without another protocol or direct fallback',
        () async {
          var requests = 0;
          final origin = await _origin(onRequest: () => requests++);
          final proxy = await _proxy(replyCode: code);
          await expectLater(
            _get(
              _client(proxy, type),
              Uri.parse('http://127.0.0.1:${origin.port}'),
            ),
            throwsA(isA<SocketException>()),
          );
          expect(requests, 0);
          expect(proxy.originsOpened, 0);
          expect(proxy.acceptedConnections, 1);
        },
      );
    }

    for (final replyLength in [0, 7]) {
      test(
        '${type.name} rejects a truncated $replyLength-byte reply',
        () async {
          final proxy = await _proxy(replyLength: replyLength);
          await expectLater(
            _get(_client(proxy, type), Uri.parse('http://127.0.0.1:80')),
            throwsA(isA<SocketException>()),
          );
          expect(proxy.originsOpened, 0);
        },
      );
    }

    test('${type.name} requires the specified reply version', () async {
      final proxy = await _proxy(replyVersion: 4);
      await expectLater(
        _get(_client(proxy, type), Uri.parse('http://127.0.0.1:80')),
        throwsA(isA<SocketException>()),
      );
      expect(proxy.originsOpened, 0);
    });

    test(
      '${type.name} rejects surplus reply bytes before a TLS upgrade',
      () async {
        final proxy = await _proxy(inlinePayload: [1, 2, 3]);
        await expectLater(
          _get(
            _client(proxy, type, trust: _trust()),
            Uri.parse('https://localhost:443'),
          ),
          throwsA(isA<SocketException>()),
        );
        expect(proxy.tunnelData.isCompleted, isFalse);
      },
    );

    for (final tls in [false, true]) {
      for (final cancel in [false, true]) {
        test(
          '${type.name} ${cancel ? 'cancellation' : 'timeout'} closes stalled ${tls ? 'TLS' : 'SOCKS'} transport',
          () async {
            final proxy = await _proxy(
              stallReply: !tls,
              stallAfterConnect: tls,
            );
            final task =
                await Socks4Connector(
                  host: '127.0.0.1',
                  port: proxy.port,
                  remoteDns: remoteDns,
                ).connect(
                  Uri.parse('${tls ? 'https' : 'http'}://127.0.0.1:443'),
                  timeout: cancel
                      ? const Duration(seconds: 5)
                      : const Duration(milliseconds: 300),
                );
            final rejected = expectLater(
              task.socket,
              throwsA(isA<SocketException>()),
            );
            await proxy.connected.future.timeout(const Duration(seconds: 2));
            if (tls) {
              await proxy.tunnelData.future.timeout(const Duration(seconds: 2));
            }
            if (cancel) task.cancel();
            await rejected;
            await proxy.firstClosed.future.timeout(const Duration(seconds: 2));
            expect(proxy.originsOpened, 0);
          },
        );
      }
    }

    test(
      '${type.name} bypass is explicit and does not follow a refused request',
      () async {
        final origin = await _origin();
        final proxy = await _proxy(replyCode: 91);
        final uri = Uri.parse('http://127.0.0.1:${origin.port}');
        expect(
          await _get(_client(proxy, type, noProxy: '127.0.0.1'), uri),
          'through SOCKS4',
        );
        expect(proxy.requests, isEmpty);
        await expectLater(
          _get(_client(proxy, type), uri),
          throwsA(isA<SocketException>()),
        );
        expect(proxy.requests, hasLength(1));
      },
    );

    for (final destination in [
      'http://[::1]',
      'http://0.0.0.1',
      'http://münich.invalid',
    ]) {
      test(
        '${type.name} rejects unsupported destination $destination before connecting',
        () async {
          final proxy = await _proxy();
          await expectLater(
            Socks4Connector(
              host: '127.0.0.1',
              port: proxy.port,
              remoteDns: remoteDns,
            ).connect(Uri.parse(destination)),
            throwsA(isA<SocketException>()),
          );
          expect(proxy.acceptedConnections, 0);
        },
      );
    }

    test(
      '${type.name} saved user ID round-trips and retains protocol choice',
      () async {
        SharedPreferences.setMockInitialValues({});
        final saved = ProxyConfig(
          type: type,
          host: '127.0.0.1',
          port: 1080,
          username: 'a user',
        );
        final service = ProxyService();
        await service.save(saved);
        final restored = ProxyService();
        await restored.load();
        expect(restored.config.toJson(), saved.toJson());
        expect(restored.config.toProxyString, throwsUnsupportedError);
      },
    );

    for (final (label, userId) in [
      ('NUL', 'invalid\u0000id'),
      ('newline', 'line\nbreak'),
      ('non-ASCII', 'é'),
      ('oversized', List.filled(256, 'a').join()),
    ]) {
      test('${type.name} rejects $label user ID', () {
        final config = ProxyConfig(
          type: type,
          host: '127.0.0.1',
          port: 1080,
          username: userId,
        );
        expect(
          () => ProxyHttpOverrides(config).createHttpClient(null),
          throwsFormatException,
        );
      });
    }

    for (final password in ['', 'secret']) {
      test(
        '${type.name} restored password cannot be silently ignored: ${password.isEmpty ? 'empty' : 'present'}',
        () async {
          SharedPreferences.setMockInitialValues({
            'proxy_config': jsonEncode({
              'type': type.name,
              'host': '127.0.0.1',
              'port': 1080,
              'username': 'user',
              'password': password,
              'noProxy': '*',
            }),
          });
          final service = ProxyService();
          await service.load();
          expect(service.config.isInvalid, isTrue);
          expect(service.createHttpClient, throwsFormatException);
          service.applyGlobally();
          expect(() => HttpClient(), throwsFormatException);
          await service.save(ProxyConfig.disabled);
          service.createHttpClient().close();
        },
      );
    }
  }

  test(
    'SOCKS4 resolves a name locally and transmits only the IPv4 address',
    () async {
      final proxy = await _proxy(inlinePayload: [42]);
      final lookedUp = <String>[];
      final task = await Socks4Connector(
        host: '127.0.0.1',
        port: proxy.port,
        userId: 'desktop',
        lookup: (name) async {
          lookedUp.add(name);
          return [InternetAddress('::1'), InternetAddress('192.0.2.42')];
        },
      ).connect(Uri.parse('http://resolve-me.invalid:80'));
      final socket = await task.socket;
      expect(await socket.first, [42]);
      socket.destroy();
      expect(lookedUp, ['resolve-me.invalid']);
      expect(proxy.requests.single.remoteDns, isFalse);
      expect(proxy.requests.single.host, '192.0.2.42');
      expect(proxy.requests.single.userId, 'desktop');
    },
  );

  test('SOCKS4a sends a hostname without calling the local resolver', () async {
    final proxy = await _proxy(inlinePayload: [42]);
    final task = await Socks4Connector(
      host: '127.0.0.1',
      port: proxy.port,
      remoteDns: true,
      userId: List.filled(255, 'a').join(),
      lookup: (_) => throw StateError('Remote DNS must never resolve locally.'),
    ).connect(Uri.parse('http://remote-only.invalid:80'));
    final socket = await task.socket;
    expect(await socket.first, [42]);
    socket.destroy();
    expect(proxy.requests.single.remoteDns, isTrue);
    expect(proxy.requests.single.host, 'remote-only.invalid');
    expect(proxy.requests.single.userId, hasLength(255));
  });

  test(
    'SOCKS4 without an IPv4 answer fails before contacting the proxy',
    () async {
      final proxy = await _proxy();
      final task = await Socks4Connector(
        host: '127.0.0.1',
        port: proxy.port,
        lookup: (_) async => [InternetAddress('::1')],
      ).connect(Uri.parse('http://ipv6-only.invalid'));
      await expectLater(task.socket, throwsA(isA<SocketException>()));
      expect(proxy.acceptedConnections, 0);
    },
  );

  for (final cancel in [false, true]) {
    test(
      'SOCKS4 ${cancel ? 'cancellation' : 'deadline'} prevents a late DNS lookup from opening TCP',
      () async {
        final proxy = await _proxy();
        final lookup = Completer<List<InternetAddress>>();
        final task =
            await Socks4Connector(
              host: '127.0.0.1',
              port: proxy.port,
              lookup: (_) => lookup.future,
            ).connect(
              Uri.parse('http://pending.invalid'),
              timeout: const Duration(milliseconds: 100),
            );
        final rejected = expectLater(
          task.socket,
          throwsA(isA<SocketException>()),
        );
        if (cancel) task.cancel();
        await rejected;
        lookup.complete([InternetAddress.loopbackIPv4]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(proxy.acceptedConnections, 0);
      },
    );
  }

  test(
    'immediate cancellation observes a late native connection task',
    () async {
      final proxy = await _proxy(stallReply: true);
      final task = await Socks4Connector(
        host: '127.0.0.1',
        port: proxy.port,
        remoteDns: true,
      ).connect(Uri.parse('http://pending.invalid'));
      final rejected = expectLater(
        task.socket,
        throwsA(isA<SocketException>()),
      );
      task.cancel();
      await rejected;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (proxy.acceptedConnections > 0) {
        await proxy.firstClosed.future.timeout(const Duration(seconds: 2));
      }
    },
  );

  test(
    'environment settings preserve explicit SOCKS4 versus SOCKS4a DNS choice',
    () {
      for (final type in [ProxyType.socks4, ProxyType.socks4a]) {
        final config = ProxyConfig.fromEnvironment(
          environment: {
            'HTTPS_PROXY': '${type.name}://test%20user@[::1]',
            'NO_PROXY': '.example.com',
          },
        );
        expect(config.type, type);
        expect(config.host, '::1');
        expect(config.port, 1080);
        expect(config.username, 'test user');
        expect(config.password, isNull);
        expect(config.bypassesHost('sub.example.com'), isTrue);
        expect(config.isInvalid, isFalse);
      }
    },
  );

  test('malformed SOCKS4 environment settings stay blocked', () {
    for (final url in [
      'socks4://user:password@localhost:1080',
      'socks4a://user:@localhost:1080',
      'socks4://invalid%00id@localhost:1080',
      'socks4a://localhost:0',
      'socks4://localhost:',
      'socks4a://localhost:65536',
    ]) {
      final config = ProxyConfig.fromEnvironment(
        environment: {'HTTPS_PROXY': url},
      );
      expect(config.isInvalid, isTrue, reason: url);
      expect(
        () => ProxyHttpOverrides(config).createHttpClient(null),
        throwsFormatException,
      );
    }
  });
}
