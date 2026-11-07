// Real loopback TLS handshakes: a settings value or a matching issuer name must
// never make an untrusted, expired, or wrong-host certificate acceptable.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/cert_pinning_service.dart';
import 'package:crisp_cloud/services/proxy_service.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/tls/$name').readAsBytesSync();

class _TlsTestServer {
  final HttpServer server;
  int requests = 0;

  _TlsTestServer._(this.server) {
    server.listen(
      (request) {
        requests++;
        request.response.write('verified');
        unawaited(request.response.close());
      },
      onError: (Object error) {
        // TLS alerts from clients rejecting our intentionally invalid fixtures
        // are expected; other server failures must still fail the test.
        if (error is! TlsException) {
          fail('Unexpected local TLS server error: $error');
        }
      },
    );
  }

  static Future<_TlsTestServer> start(String certificate) async {
    final context = SecurityContext()
      ..useCertificateChainBytes(_fixture(certificate))
      ..usePrivateKeyBytes(_fixture('server.key'));
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final fixture = _TlsTestServer._(server);
    addTearDown(() => server.close(force: true));
    return fixture;
  }

  Uri get uri => Uri.parse('https://127.0.0.1:${server.port}/');
}

HttpClient _client(CertPinningService trust) {
  final client = ProxyHttpOverrides(
    ProxyConfig.disabled,
    certPinning: trust,
  ).createHttpClient(null);
  client.connectionTimeout = const Duration(seconds: 5);
  client.findProxy = (_) => 'DIRECT';
  addTearDown(() => client.close(force: true));
  return client;
}

Future<String> _read(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  final response = await request.close();
  return response.transform(utf8.decoder).join();
}

void main() {
  HttpOverrides? previousOverrides;
  late CertPinningService trust;

  setUp(() {
    previousOverrides = HttpOverrides.current;
    SharedPreferences.setMockInitialValues({});
    trust = CertPinningService();
  });
  tearDown(() => HttpOverrides.global = previousOverrides);

  test(
    'legacy pinning setting cannot allow an untrusted unpinned host',
    () async {
      SharedPreferences.setMockInitialValues({'cert_pinning_enabled': true});
      await trust.load();
      final endpoint = await _TlsTestServer.start('server.pem');
      await expectLater(
        _read(_client(trust), endpoint.uri),
        throwsA(isA<TlsException>()),
      );
      expect(endpoint.requests, 0);
    },
  );

  for (final version in TlsVersion.values) {
    test(
      'imported CA validates a matching host with TLS setting ${version.name}',
      () async {
        await trust.addCustomCaCert(_fixture('ca.pem'));
        await trust.setMinTlsVersion(version);
        final endpoint = await _TlsTestServer.start('server.pem');
        expect(await _read(_client(trust), endpoint.uri), 'verified');
        expect(endpoint.requests, 1);
      },
    );
  }

  test('same issuer name with a forged signature is rejected', () async {
    // This metadata triggered the old issuer-substring trust bypass. Only the
    // embedded certificate's actual public key is now used as a trust anchor.
    final annotatedCa = Uint8List.fromList([
      ...utf8.encode('Subject: CN=CrispCloud Test Root\n'),
      ..._fixture('ca.pem'),
    ]);
    await trust.addCustomCaCert(annotatedCa);
    final endpoint = await _TlsTestServer.start('forged-issuer.pem');
    await expectLater(
      _read(_client(trust), endpoint.uri),
      throwsA(isA<TlsException>()),
    );
    expect(endpoint.requests, 0);
  });

  for (final certificate in ['wrong-host.pem', 'expired.pem']) {
    test('imported CA does not bypass verification of $certificate', () async {
      await trust.addCustomCaCert(_fixture('ca.pem'));
      final endpoint = await _TlsTestServer.start(certificate);
      await expectLater(
        _read(_client(trust), endpoint.uri),
        throwsA(isA<TlsException>()),
      );
      expect(endpoint.requests, 0);
    });
  }

  test('custom CA is applied globally without a proxy or pinning', () async {
    await trust.addCustomCaCert(_fixture('ca.pem'));
    final endpoint = await _TlsTestServer.start('server.pem');
    ProxyService(ProxyConfig.disabled, trust).applyGlobally();
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    expect(await _read(client, endpoint.uri), 'verified');
  });

  test(
    'explicit client factory applies custom CA without global overrides',
    () async {
      await trust.addCustomCaCert(_fixture('ca.pem'));
      final endpoint = await _TlsTestServer.start('server.pem');
      final client = ProxyService(
        ProxyConfig.disabled,
        trust,
      ).createHttpClient();
      addTearDown(client.close);
      final response = await client.get(endpoint.uri);
      expect(response.statusCode, 200);
      expect(response.body, 'verified');
    },
  );
}
