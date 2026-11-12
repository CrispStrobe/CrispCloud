import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/proxy_service.dart';
import 'package:crisp_cloud/services/socks5_connector.dart';

import 'support/socks5_fixture.dart';

SecurityContext _trust() =>
    SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/fixtures/tls/ca.pem');

SecurityContext _serverContext([String certificate = 'server.pem']) =>
    SecurityContext()
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
      final bytes = await request.fold<List<int>>(
        [],
        (body, chunk) => body..addAll(chunk),
      );
      request.response.add(
        bytes.isEmpty ? utf8.encode('through SOCKS5') : bytes,
      );
      await request.response.close();
    },
    onError: (Object error) {
      if (error is! TlsException && error is! SocketException) throw error;
    },
  );
  addTearDown(() => server.close(force: true));
  return server;
}

Future<Socks5Fixture> _proxy({
  bool authenticated = false,
  int? method,
  bool acceptAuthentication = true,
  int connectReply = 0,
  bool fragmented = false,
  bool stallGreeting = false,
  bool stallAfterConnect = false,
  bool malformedReply = false,
  List<int>? inlinePayload,
}) async {
  final proxy = await Socks5Fixture.start(
    requireAuthentication: authenticated,
    selectedMethod: method,
    acceptAuthentication: acceptAuthentication,
    connectReply: connectReply,
    fragmentReplies: fragmented,
    stallGreeting: stallGreeting,
    stallAfterConnect: stallAfterConnect,
    malformedReply: malformedReply,
    inlinePayload: inlinePayload,
  );
  addTearDown(() async {
    await proxy.close();
    expect(proxy.errors, isEmpty);
  });
  return proxy;
}

HttpClient _client(
  Socks5Fixture proxy, {
  bool authenticated = false,
  SecurityContext? trust,
  String noProxy = '',
}) {
  final client = ProxyHttpOverrides(
    ProxyConfig(
      type: ProxyType.socks5,
      host: '127.0.0.1',
      port: proxy.port,
      username: authenticated ? 'test-user' : null,
      password: authenticated ? 'päss:word' : null,
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

  for (final secure in [false, true]) {
    for (final authenticated in [false, true]) {
      test(
        '${secure ? 'HTTPS' : 'HTTP'} via SOCKS5 with ${authenticated ? 'password auth' : 'no auth'} and fragmented replies',
        () async {
          final origin = await _origin(secure: secure);
          final proxy = await _proxy(
            authenticated: authenticated,
            fragmented: true,
          );
          final client = _client(
            proxy,
            authenticated: authenticated,
            trust: _trust(),
          );
          final host = secure ? 'localhost' : 'no-local-dns.invalid';
          final uri = Uri.parse(
            '${secure ? 'https' : 'http'}://$host:${origin.port}/item',
          );
          expect(await _get(client, uri), 'through SOCKS5');
          expect(proxy.requests.single.addressType, 3);
          expect(proxy.requests.single.host, host);
          expect(proxy.requests.single.port, origin.port);
          expect(proxy.offeredMethods.single, authenticated ? [2] : [0]);
          if (authenticated) {
            expect(proxy.username, 'test-user');
            expect(proxy.password, 'päss:word');
          }
          // Reusing the connection for a multi-chunk body also exercises the raw
          // socket's backpressure and its ordinary HttpClient keep-alive path.
          final upload = await client.postUrl(uri);
          final chunk = List<int>.generate(32 * 1024, (i) => i & 255);
          await upload.addStream(Stream.fromIterable(List.filled(64, chunk)));
          final response = await upload.close();
          var offset = 0;
          final body = StreamIterator(response);
          while (await body.moveNext()) {
            if (offset == 0) {
              // Pause reception while the peer continues sending. Every byte
              // must survive the resumed stream without eager full buffering.
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            final bytes = body.current;
            for (final byte in bytes) {
              if (byte != (offset & 255)) {
                fail('Transfer payload changed at $offset');
              }
              offset++;
            }
          }
          await body.cancel();
          expect(offset, 2 * 1024 * 1024);
        },
      );
    }
  }

  for (final address in ['127.0.0.1', '[::1]']) {
    test('CONNECT encodes literal address $address without DNS', () async {
      final origin = await _origin();
      final proxy = await _proxy();
      expect(
        await _get(_client(proxy), Uri.parse('http://$address:${origin.port}')),
        'through SOCKS5',
      );
      expect(proxy.requests.single.addressType, address == '127.0.0.1' ? 1 : 4);
      expect(
        proxy.requests.single.host,
        address == '127.0.0.1' ? address : '::1',
      );
    });
  }

  test('coalesced CONNECT reply preserves the first payload bytes', () async {
    final bytes = utf8.encode('already available');
    final proxy = await _proxy(inlinePayload: bytes);
    final task = await Socks5Connector(
      host: '127.0.0.1',
      port: proxy.port,
    ).connect(Uri.parse('http://remote.invalid:80'));
    final socket = await task.socket;
    expect(await socket.first, bytes);
    socket.destroy();
  });

  for (final certificate in [
    'wrong-host.pem',
    'expired.pem',
    'forged-issuer.pem',
  ]) {
    test('SOCKS HTTPS rejects $certificate before HTTP data', () async {
      var requests = 0;
      final origin = await _origin(
        secure: true,
        certificate: certificate,
        onRequest: () => requests++,
      );
      final proxy = await _proxy();
      await expectLater(
        _get(
          _client(proxy, trust: _trust()),
          Uri.parse('https://localhost:${origin.port}'),
        ),
        throwsA(isA<HandshakeException>()),
      );
      expect(requests, 0);
      expect(proxy.originsOpened, 1);
    });
  }

  test('SOCKS HTTPS does not trust an unknown issuer by default', () async {
    var requests = 0;
    final origin = await _origin(secure: true, onRequest: () => requests++);
    final proxy = await _proxy();
    await expectLater(
      _get(_client(proxy), Uri.parse('https://localhost:${origin.port}')),
      throwsA(isA<HandshakeException>()),
    );
    expect(requests, 0);
  });

  test(
    'configured authentication cannot downgrade to no authentication',
    () async {
      final proxy = await _proxy(method: 0);
      await expectLater(
        _get(
          _client(proxy, authenticated: true),
          Uri.parse('http://remote.invalid'),
        ),
        throwsA(isA<SocketException>()),
      );
      expect(proxy.offeredMethods.single, [2]);
      expect(proxy.requests, isEmpty);
      expect(proxy.originsOpened, 0);
    },
  );

  test('bad credentials stop before CONNECT without direct fallback', () async {
    final proxy = await _proxy(
      authenticated: true,
      acceptAuthentication: false,
    );
    final origin = await _origin();
    await expectLater(
      _get(
        _client(proxy, authenticated: true),
        Uri.parse('http://127.0.0.1:${origin.port}'),
      ),
      throwsA(isA<SocketException>()),
    );
    expect(proxy.requests, isEmpty);
    expect(proxy.originsOpened, 0);
  });

  for (final malformed in [false, true]) {
    test(
      '${malformed ? 'malformed' : 'refused'} CONNECT cannot fall back directly',
      () async {
        var requests = 0;
        final origin = await _origin(onRequest: () => requests++);
        final proxy = await _proxy(
          connectReply: malformed ? 0 : 5,
          malformedReply: malformed,
        );
        await expectLater(
          _get(_client(proxy), Uri.parse('http://127.0.0.1:${origin.port}')),
          throwsA(isA<SocketException>()),
        );
        expect(requests, 0);
        expect(proxy.originsOpened, 0);
      },
    );
  }

  for (final tls in [false, true]) {
    test(
      'timeout closes a stalled ${tls ? 'TLS' : 'SOCKS'} handshake',
      () async {
        final proxy = await _proxy(stallGreeting: !tls, stallAfterConnect: tls);
        final task = await Socks5Connector(host: '127.0.0.1', port: proxy.port)
            .connect(
              Uri.parse('${tls ? 'https' : 'http'}://stalled.invalid:443'),
              timeout: const Duration(milliseconds: 300),
            );
        await expectLater(task.socket, throwsA(isA<SocketException>()));
        await proxy.firstClosed.future.timeout(const Duration(seconds: 2));
        if (tls) expect(proxy.tunnelData.isCompleted, isTrue);
        expect(proxy.originsOpened, 0);
      },
    );

    test(
      'cancellation closes a stalled ${tls ? 'TLS' : 'SOCKS'} handshake',
      () async {
        final proxy = await _proxy(stallGreeting: !tls, stallAfterConnect: tls);
        final task = await Socks5Connector(
          host: '127.0.0.1',
          port: proxy.port,
        ).connect(Uri.parse('${tls ? 'https' : 'http'}://stalled.invalid:443'));
        final rejected = expectLater(
          task.socket,
          throwsA(isA<SocketException>()),
        );
        await proxy.connected.future;
        if (tls) {
          // The fixture has received ClientHello, so this is inside TLS itself.
          await proxy.tunnelData.future.timeout(const Duration(seconds: 2));
        }
        task.cancel();
        await rejected;
        await proxy.firstClosed.future.timeout(const Duration(seconds: 2));
      },
    );
  }

  test(
    'explicit bypass goes directly; the same target otherwise stays proxied',
    () async {
      final origin = await _origin();
      final proxy = await _proxy(connectReply: 2);
      final uri = Uri.parse('http://127.0.0.1:${origin.port}');
      expect(
        await _get(_client(proxy, noProxy: '127.0.0.1'), uri),
        'through SOCKS5',
      );
      expect(proxy.requests, isEmpty);
      await expectLater(
        _get(_client(proxy), uri),
        throwsA(isA<SocketException>()),
      );
      expect(proxy.requests, hasLength(1));
    },
  );

  test(
    'invalid selected SOCKS configuration fails before a client is created',
    () {
      for (final config in [
        const ProxyConfig(type: ProxyType.socks5, host: '127.0.0.1', port: 0),
        const ProxyConfig(
          type: ProxyType.socks5,
          host: '127.0.0.1',
          port: 65536,
        ),
        const ProxyConfig(
          type: ProxyType.socks5,
          host: '127.0.0.1',
          port: 1080,
          username: 'user',
        ),
        ProxyConfig(
          type: ProxyType.socks5,
          host: '127.0.0.1',
          port: 1080,
          username: 'user',
          password: List.filled(128, 'é').join(),
        ),
      ]) {
        expect(
          () => ProxyHttpOverrides(config).createHttpClient(null),
          throwsFormatException,
        );
      }
    },
  );

  test('bypass supports leading dots, case, canonical IPs and boundaries', () {
    const config = ProxyConfig(
      noProxy: '.Example.com, localhost, 127.0.0.1, [::1]',
    );
    for (final host in [
      'example.com',
      'sub.EXAMPLE.com.',
      'localhost',
      '127.0.0.1',
      '::1',
      '0:0:0:0:0:0:0:1',
    ]) {
      expect(config.bypassesHost(host), isTrue, reason: host);
    }
    for (final host in [
      'notexample.com',
      'example.com.evil.invalid',
      '127.0.0.2',
      'sub.127.0.0.1',
    ]) {
      expect(config.bypassesHost(host), isFalse, reason: host);
    }
    expect(const ProxyConfig(noProxy: '*').bypassesHost('any.invalid'), isTrue);
  });

  for (final stored in [
    '{broken',
    jsonEncode({'type': 'socks55', 'host': '127.0.0.1', 'port': 1080}),
    jsonEncode({'type': 'socks5', 'host': '127.0.0.1', 'port': 0}),
    jsonEncode({
      'type': 'socks5',
      'host': '127.0.0.1',
      'port': 1080,
      'username': 'user',
    }),
  ]) {
    test(
      'invalid restored proxy blocks HTTP until explicitly corrected: $stored',
      () async {
        SharedPreferences.setMockInitialValues({'proxy_config': stored});
        final service = ProxyService();
        await service.load();
        expect(service.config.isInvalid, isTrue);
        expect(service.config.toProxyString, throwsFormatException);
        expect(service.createHttpClient, throwsFormatException);
        service.applyGlobally();
        expect(() => HttpClient(), throwsFormatException);
        await service.save(ProxyConfig.disabled);
        expect(service.config.isInvalid, isFalse);
        final client = service.createHttpClient();
        client.close();
      },
    );
  }

  test('environment SOCKS settings preserve encoded credentials and remote DNS mode', () {
    final config = ProxyConfig.fromEnvironment(
      environment: {
        'HTTPS_PROXY': 'socks5h://user:p%C3%A4ss%3Aword@127.0.0.1:1080',
        'NO_PROXY': '.example.com',
      },
    );
    expect(config.type, ProxyType.socks5);
    expect(config.password, 'päss:word');
    expect(config.bypassesHost('sub.example.com'), isTrue);
  });

  test('unsupported or malformed configured proxy URLs block routing', () {
    for (final url in [
      'socks4://localhost:1080',
      'https://localhost:8080',
      'unexpected://localhost:1080',
      'socks5://user@localhost:1080',
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
