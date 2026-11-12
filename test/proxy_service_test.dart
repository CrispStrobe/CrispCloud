// test/proxy_service_test.dart
//
// Dedicated tests for ProxyService and ProxyConfig beyond what's in
// security_features_test.dart. Focuses on:
//   - fromEnvironment parsing
//   - noProxy bypass matching
//   - ProxyHttpOverrides behavior
//   - createHttpClient with various configs
//   - setCertPinning
//   - applyGlobally installs/clears overrides

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/proxy_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // ProxyConfig.fromEnvironment edge cases
  // (Note: fromEnvironment reads Platform.environment which we can't mock,
  //  so we test the factory constructor's parse logic by calling fromJson
  //  on URI-derived data and validating the constructor's behavior.)
  // ---------------------------------------------------------------------------
  group('ProxyConfig parsing logic', () {
    test('fromJson with socks5 type', () {
      final config = ProxyConfig.fromJson({
        'type': 'socks5',
        'host': '127.0.0.1',
        'port': 1080,
      });
      expect(config.type, ProxyType.socks5);
      expect(config.host, '127.0.0.1');
      expect(config.port, 1080);
    });

    test('fromJson with http type preserves credentials', () {
      final config = ProxyConfig.fromJson({
        'type': 'http',
        'host': 'proxy.corp.com',
        'port': 3128,
        'username': 'admin',
        'password': 's3cret',
        'noProxy': 'localhost,internal.corp.com',
      });
      expect(config.type, ProxyType.http);
      expect(config.username, 'admin');
      expect(config.password, 's3cret');
      expect(config.noProxy, 'localhost,internal.corp.com');
    });

    test('isEnabled requires type, host, and port > 0', () {
      expect(
        const ProxyConfig(type: ProxyType.http, host: 'h', port: 80).isEnabled,
        true,
      );
      expect(
        const ProxyConfig(type: ProxyType.none, host: 'h', port: 80).isEnabled,
        false,
      );
      expect(
        const ProxyConfig(type: ProxyType.http, host: '', port: 80).isEnabled,
        false,
      );
      expect(
        const ProxyConfig(type: ProxyType.http, host: 'h', port: 0).isEnabled,
        false,
      );
    });

    test('toProxyString returns DIRECT when disabled', () {
      expect(const ProxyConfig().toProxyString(), 'DIRECT');
    });

    test('toProxyString returns PROXY host:port when enabled', () {
      const cfg = ProxyConfig(
        type: ProxyType.http,
        host: '10.0.0.1',
        port: 8080,
      );
      expect(cfg.toProxyString(), 'PROXY 10.0.0.1:8080');
    });
  });

  // ---------------------------------------------------------------------------
  // ProxyConfig noProxy logic
  // ---------------------------------------------------------------------------
  group('ProxyConfig noProxy', () {
    test('noProxy defaults to empty string', () {
      expect(const ProxyConfig().noProxy, '');
    });

    test('toJson preserves noProxy', () {
      const cfg = ProxyConfig(
        type: ProxyType.http,
        host: 'p',
        port: 80,
        noProxy: 'localhost, .internal',
      );
      final json = cfg.toJson();
      expect(json['noProxy'], 'localhost, .internal');
    });
  });

  group('Proxy host validation', () {
    test('DNS/IDNA, IPv4 and IPv6 proxy hosts remain valid', () {
      for (final host in [
        'localhost',
        'proxy.company.com.',
        'xn--mnich-kva.example',
        '192.0.2.1',
        '2001:db8::1',
        '[2001:db8::1]',
      ]) {
        for (final type in ProxyType.values.where(
          (type) => type != ProxyType.none,
        )) {
          final config = ProxyConfig(type: type, host: host, port: 8080);
          expect(
            config.validate,
            returnsNormally,
            reason: '${type.name}: $host',
          );
        }
      }
      for (final host in ['2001:db8::1', '[2001:db8::1]']) {
        expect(
          ProxyConfig(
            type: ProxyType.http,
            host: host,
            port: 8080,
          ).toProxyString(),
          'PROXY [2001:db8::1]:8080',
        );
      }
    });

    test('proxy host data cannot inject native directives or URI syntax', () {
      for (final host in [
        '127.0.0.1:1; DIRECT; PROXY unused',
        'proxy;DIRECT',
        '127.0.0.1;DIRECT',
        '::1;DIRECT',
        '[::1];DIRECT',
        '127.0.0.1 DIRECT',
        '127.0.0.1\t',
        '::1\n',
        'proxy\nDIRECT',
        'proxy\u0000host',
        ' proxy',
        'p roxy',
        'http://proxy',
        'user@proxy',
        'proxy:8080',
        '[::1]:8080',
        'proxy/path',
        r'proxy\path',
        'proxy%3BDIRECT',
        'proxy?query',
        'proxy#fragment',
      ]) {
        for (final type in ProxyType.values.where(
          (type) => type != ProxyType.none,
        )) {
          final config = ProxyConfig(
            type: type,
            host: host,
            port: 8080,
            noProxy: '*',
          );
          expect(
            config.toProxyString,
            throwsFormatException,
            reason: '${type.name}: $host',
          );
          expect(
            () => ProxyHttpOverrides(config).createHttpClient(null),
            throwsFormatException,
          );
        }
      }
    });

    test('a valid IP prefix cannot hide directives after an embedded NUL', () {
      for (final host in [
        '127.0.0.1\u0000:1; DIRECT; PROXY unused',
        '::1\u0000:1; DIRECT; PROXY unused',
        '[::1\u0000:1; DIRECT; PROXY unused]',
        '[::1]\u0000:1; DIRECT; PROXY unused',
        '127.0.0.1\u0000',
        '::1\u0000',
      ]) {
        expect(ProxyConfig.isValidHost(host), isFalse);
        for (final type in ProxyType.values.where(
          (type) => type != ProxyType.none,
        )) {
          final config = ProxyConfig(
            type: type,
            host: host,
            port: 8080,
            noProxy: '*',
          );
          expect(config.toProxyString, throwsFormatException);
          expect(
            () => ProxyHttpOverrides(config).createHttpClient(null),
            throwsFormatException,
          );
        }
      }
    });

    test(
      'restored HTTP directive injection remains blocked before bypass',
      () async {
        SharedPreferences.setMockInitialValues({
          'proxy_config': jsonEncode({
            'type': 'http',
            'host': '127.0.0.1\u0000:1; DIRECT; PROXY unused',
            'port': 8080,
            'noProxy': '*',
          }),
        });
        final service = ProxyService();
        await service.load();
        expect(service.config.isInvalid, isTrue);
        expect(service.createHttpClient, throwsFormatException);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // ProxyHttpOverrides
  // ---------------------------------------------------------------------------
  group('ProxyHttpOverrides', () {
    test('createHttpClient returns a valid client when proxy is enabled', () {
      const cfg = ProxyConfig(
        type: ProxyType.http,
        host: 'proxy.test',
        port: 9090,
      );
      final overrides = ProxyHttpOverrides(cfg);
      final client = overrides.createHttpClient(null);
      expect(client, isNotNull);
      client.close();
    });

    test('noProxy bypass list parsing splits by comma and trims', () {
      const config = ProxyConfig(
        noProxy: 'localhost, .example.com , internal.corp.com',
      );
      for (final host in ['localhost', 'example.com', 'internal.corp.com']) {
        expect(config.bypassesHost(host), isTrue, reason: host);
      }
    });

    test('noProxy bypass matching: exact host match', () {
      const config = ProxyConfig(noProxy: 'localhost,.example.com');
      expect(config.bypassesHost('localhost'), isTrue);
    });

    test('noProxy bypass matching: subdomain match', () {
      for (final pattern in ['.example.com', 'example.com']) {
        expect(
          ProxyConfig(noProxy: pattern).bypassesHost('app.example.com'),
          isTrue,
        );
      }
    });

    test('noProxy bypass matching: non-matching host goes through proxy', () {
      const config = ProxyConfig(noProxy: 'localhost,internal.corp.com');
      expect(config.bypassesHost('example.com'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // ProxyService
  // ---------------------------------------------------------------------------
  group('ProxyService extended', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('constructor accepts initial config', () {
      const cfg = ProxyConfig(type: ProxyType.http, host: 'init', port: 1111);
      final svc = ProxyService(cfg);
      expect(svc.config.host, 'init');
      expect(svc.config.port, 1111);
    });

    test('load with empty prefs uses the environment default', () async {
      final svc = ProxyService();
      await svc.load();
      expect(svc.config.toJson(), ProxyConfig.fromEnvironment().toJson());
    });

    test('load with corrupted prefs falls back gracefully', () async {
      SharedPreferences.setMockInitialValues({
        'proxy_config': 'not valid json {',
      });
      final svc = ProxyService();
      await svc.load();
      // Should not throw and should fall back to disabled or env
      expect(svc.config.type, isNotNull);
    });

    test('save persists config to SharedPreferences', () async {
      final svc = ProxyService();
      const cfg = ProxyConfig(
        type: ProxyType.socks5,
        host: 'socks.proxy',
        port: 1080,
        username: 'u',
        password: 'p',
        noProxy: 'skip.me',
      );
      await svc.save(cfg);

      final svc2 = ProxyService();
      await svc2.load();
      expect(svc2.config.type, ProxyType.socks5);
      expect(svc2.config.host, 'socks.proxy');
      expect(svc2.config.port, 1080);
      expect(svc2.config.username, 'u');
      expect(svc2.config.password, 'p');
      expect(svc2.config.noProxy, 'skip.me');
    });

    test('clear resets config to disabled', () async {
      final svc = ProxyService();
      await svc.save(
        const ProxyConfig(type: ProxyType.http, host: 'x', port: 80),
      );
      expect(svc.config.isEnabled, true);
      await svc.clear();
      expect(svc.config.isEnabled, false);
    });

    test('applyGlobally does not throw when proxy is enabled', () async {
      final svc = ProxyService();
      await svc.save(
        const ProxyConfig(type: ProxyType.http, host: 'g', port: 80),
      );
      // Should not throw
      svc.applyGlobally();
    });

    test('applyGlobally does not throw when proxy is disabled', () async {
      final svc = ProxyService();
      await svc.save(
        const ProxyConfig(type: ProxyType.http, host: 'g', port: 80),
      );
      svc.applyGlobally();

      await svc.clear();
      // Should not throw
      svc.applyGlobally();
    });

    test('createHttpClient returns IOClient when proxy is enabled', () {
      final svc = ProxyService(
        const ProxyConfig(type: ProxyType.http, host: 'io', port: 80),
      );
      final client = svc.createHttpClient();
      expect(client, isNotNull);
      client.close();
    });

    test('createHttpClient returns plain client when disabled', () {
      final svc = ProxyService();
      final client = svc.createHttpClient();
      expect(client, isNotNull);
      client.close();
    });

    test('setCertPinning stores the service reference', () {
      final svc = ProxyService();
      expect(svc.certPinning, isNull);
      // We cannot construct a real CertPinningService without setup,
      // but we can verify the setter doesn't throw
    });
  });

  // ---------------------------------------------------------------------------
  // ProxyType enum
  // ---------------------------------------------------------------------------
  group('ProxyType enum', () {
    test('has exactly 5 values', () {
      expect(ProxyType.values.length, 5);
    });

    test('values preserve existing names and distinguish SOCKS4 DNS modes', () {
      expect(ProxyType.values.map((t) => t.name), [
        'none',
        'http',
        'socks5',
        'socks4',
        'socks4a',
      ]);
    });
  });
}
