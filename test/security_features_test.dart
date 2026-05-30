// test/security_features_test.dart
//
// Tests for security and power user features:
// - ProxyConfig model
// - ProxyService
// - AppLockService (PIN/password + biometric)
// - Diff computation
// - Permissions dialog parsing

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/proxy_service.dart';
import 'package:crisp_cloud/services/app_lock_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  // --- ProxyConfig Tests ---
  group('ProxyConfig', () {
    test('disabled by default', () {
      const config = ProxyConfig();
      expect(config.isEnabled, false);
      expect(config.toProxyString(), 'DIRECT');
    });

    test('HTTP proxy is enabled', () {
      const config = ProxyConfig(
        type: ProxyType.http,
        host: 'proxy.example.com',
        port: 8080,
      );
      expect(config.isEnabled, true);
      expect(config.toProxyString(), 'PROXY proxy.example.com:8080');
    });

    test('SOCKS5 proxy is enabled', () {
      const config = ProxyConfig(
        type: ProxyType.socks5,
        host: '127.0.0.1',
        port: 1080,
      );
      expect(config.isEnabled, true);
      expect(config.toProxyString(), 'PROXY 127.0.0.1:1080');
    });

    test('not enabled without host', () {
      const config = ProxyConfig(type: ProxyType.http, port: 8080);
      expect(config.isEnabled, false);
    });

    test('not enabled without port', () {
      const config = ProxyConfig(type: ProxyType.http, host: 'proxy.example.com');
      expect(config.isEnabled, false);
    });

    test('toJson/fromJson round-trip', () {
      const config = ProxyConfig(
        type: ProxyType.socks5,
        host: '10.0.0.1',
        port: 1080,
        username: 'user',
        password: 'pass',
        noProxy: 'localhost, .local',
      );
      final json = config.toJson();
      final restored = ProxyConfig.fromJson(json);
      expect(restored.type, ProxyType.socks5);
      expect(restored.host, '10.0.0.1');
      expect(restored.port, 1080);
      expect(restored.username, 'user');
      expect(restored.password, 'pass');
      expect(restored.noProxy, 'localhost, .local');
    });

    test('fromJson handles missing fields', () {
      final config = ProxyConfig.fromJson({});
      expect(config.type, ProxyType.none);
      expect(config.host, '');
      expect(config.port, 0);
      expect(config.username, null);
      expect(config.isEnabled, false);
    });

    test('fromJson handles unknown type', () {
      final config = ProxyConfig.fromJson({'type': 'bogus', 'host': 'x', 'port': 1});
      expect(config.type, ProxyType.none);
    });

    test('disabled constant', () {
      expect(ProxyConfig.disabled.isEnabled, false);
      expect(ProxyConfig.disabled.type, ProxyType.none);
    });

    test('toJson omits null username/password', () {
      const config = ProxyConfig(type: ProxyType.http, host: 'h', port: 80);
      final json = config.toJson();
      expect(json.containsKey('username'), false);
      expect(json.containsKey('password'), false);
    });
  });

  // --- ProxyService Tests ---
  group('ProxyService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('default config is disabled', () {
      final service = ProxyService();
      expect(service.config.isEnabled, false);
    });

    test('save and load round-trip', () async {
      final service = ProxyService();
      const config = ProxyConfig(
        type: ProxyType.http,
        host: 'myproxy.com',
        port: 3128,
        username: 'admin',
        noProxy: 'internal.company.com',
      );
      await service.save(config);

      // Create new service and load
      final service2 = ProxyService();
      await service2.load();
      expect(service2.config.type, ProxyType.http);
      expect(service2.config.host, 'myproxy.com');
      expect(service2.config.port, 3128);
      expect(service2.config.username, 'admin');
      expect(service2.config.noProxy, 'internal.company.com');
    });

    test('clear removes config', () async {
      final service = ProxyService();
      await service.save(const ProxyConfig(type: ProxyType.http, host: 'x', port: 8080));
      await service.clear();
      expect(service.config.isEnabled, false);

      // New instance should also be disabled
      final service2 = ProxyService();
      await service2.load();
      expect(service2.config.isEnabled, false);
    });

    test('createHttpClient returns a client', () {
      final service = ProxyService();
      final client = service.createHttpClient();
      expect(client, isNotNull);
      client.close();
    });
  });

  // --- AppLockService Tests ---
  group('AppLockService', () {
    late InMemorySecureStorage storage;
    late AppLockService lockService;

    setUp(() {
      storage = InMemorySecureStorage();
      lockService = AppLockService(storage);
    });

    test('not enabled by default', () async {
      expect(await lockService.isEnabled(), false);
    });

    test('setup enables lock', () async {
      await lockService.setup('1234');
      expect(await lockService.isEnabled(), true);
    });

    test('verify correct code', () async {
      await lockService.setup('mypassword');
      expect(await lockService.verify('mypassword'), true);
    });

    test('verify wrong code', () async {
      await lockService.setup('correct');
      expect(await lockService.verify('wrong'), false);
    });

    test('verify empty storage returns false', () async {
      expect(await lockService.verify('anything'), false);
    });

    test('disable clears lock', () async {
      await lockService.setup('1234');
      expect(await lockService.isEnabled(), true);
      await lockService.disable();
      expect(await lockService.isEnabled(), false);
    });

    test('changeCode with correct current code', () async {
      await lockService.setup('old');
      final ok = await lockService.changeCode('old', 'new');
      expect(ok, true);
      expect(await lockService.verify('new'), true);
      expect(await lockService.verify('old'), false);
    });

    test('changeCode with wrong current code fails', () async {
      await lockService.setup('correct');
      final ok = await lockService.changeCode('wrong', 'new');
      expect(ok, false);
      // Original code still works
      expect(await lockService.verify('correct'), true);
    });

    test('setup rejects short codes', () async {
      expect(
        () => lockService.setup('123'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('timeout defaults to 300', () async {
      expect(await lockService.getTimeout(), 300);
    });

    test('setTimeout and getTimeout', () async {
      await lockService.setTimeout(60);
      expect(await lockService.getTimeout(), 60);
    });

    test('different codes produce different hashes', () async {
      await lockService.setup('password1');
      expect(await lockService.verify('password1'), true);
      expect(await lockService.verify('password2'), false);
    });

    test('setup twice changes the code', () async {
      await lockService.setup('first');
      await lockService.setup('second');
      expect(await lockService.verify('first'), false);
      expect(await lockService.verify('second'), true);
    });

    test('biometric not enabled by default', () async {
      expect(await lockService.isBiometricEnabled(), false);
    });

    test('setBiometricEnabled persists', () async {
      await lockService.setBiometricEnabled(true);
      expect(await lockService.isBiometricEnabled(), true);
      await lockService.setBiometricEnabled(false);
      expect(await lockService.isBiometricEnabled(), false);
    });

    test('disable clears biometric setting', () async {
      await lockService.setup('1234');
      await lockService.setBiometricEnabled(true);
      expect(await lockService.isBiometricEnabled(), true);
      await lockService.disable();
      expect(await lockService.isBiometricEnabled(), false);
    });

    test('biometric enabled survives new service instance', () async {
      await lockService.setBiometricEnabled(true);
      final lockService2 = AppLockService(storage);
      expect(await lockService2.isBiometricEnabled(), true);
    });
  });

  // --- Diff Algorithm Tests ---
  group('Diff Computation', () {
    // We test the LCS-based diff logic inline since it's private in the widget.
    // Replicate the algorithm here for testing.

    List<_TestDiffLine> computeDiff(List<String> left, List<String> right) {
      final m = left.length;
      final n = right.length;
      final lcs = List.generate(m + 1, (_) => List.filled(n + 1, 0));

      for (int i = 1; i <= m; i++) {
        for (int j = 1; j <= n; j++) {
          if (left[i - 1] == right[j - 1]) {
            lcs[i][j] = lcs[i - 1][j - 1] + 1;
          } else {
            lcs[i][j] = lcs[i - 1][j] > lcs[i][j - 1] ? lcs[i - 1][j] : lcs[i][j - 1];
          }
        }
      }

      int i = m, j = n;
      final stack = <_TestDiffLine>[];

      while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && left[i - 1] == right[j - 1]) {
          stack.add(_TestDiffLine('equal', left[i - 1]));
          i--;
          j--;
        } else if (j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j])) {
          stack.add(_TestDiffLine('added', right[j - 1]));
          j--;
        } else {
          stack.add(_TestDiffLine('removed', left[i - 1]));
          i--;
        }
      }

      return stack.reversed.toList();
    }

    test('identical files produce all-equal', () {
      final result = computeDiff(['a', 'b', 'c'], ['a', 'b', 'c']);
      expect(result.length, 3);
      expect(result.every((d) => d.type == 'equal'), true);
    });

    test('empty files produce empty diff', () {
      final result = computeDiff([], []);
      expect(result, isEmpty);
    });

    test('added lines', () {
      final result = computeDiff([], ['a', 'b']);
      expect(result.length, 2);
      expect(result.every((d) => d.type == 'added'), true);
    });

    test('removed lines', () {
      final result = computeDiff(['a', 'b'], []);
      expect(result.length, 2);
      expect(result.every((d) => d.type == 'removed'), true);
    });

    test('mixed changes', () {
      final result = computeDiff(['a', 'b', 'c'], ['a', 'x', 'c']);
      final types = result.map((d) => d.type).toList();
      // a=equal, b=removed, x=added, c=equal
      expect(types, contains('equal'));
      expect(types, contains('removed'));
      expect(types, contains('added'));
    });

    test('line inserted in middle', () {
      final result = computeDiff(['a', 'c'], ['a', 'b', 'c']);
      final added = result.where((d) => d.type == 'added').toList();
      expect(added.length, 1);
      expect(added.first.text, 'b');
    });

    test('line deleted from middle', () {
      final result = computeDiff(['a', 'b', 'c'], ['a', 'c']);
      final removed = result.where((d) => d.type == 'removed').toList();
      expect(removed.length, 1);
      expect(removed.first.text, 'b');
    });
  });

  // --- Permission Octal Parsing Tests ---
  group('Permission Parsing', () {
    // Test the logic used in the permissions dialog
    int parseOctal(String octal) => int.parse(octal, radix: 8);

    List<bool> parseMode(int mode) {
      final perms = List.filled(9, false);
      for (int i = 0; i < 9; i++) {
        perms[8 - i] = (mode >> i) & 1 == 1;
      }
      return perms;
    }

    int toMode(List<bool> perms) {
      int mode = 0;
      for (int i = 0; i < 9; i++) {
        if (perms[8 - i]) mode |= (1 << i);
      }
      return mode;
    }

    String toSymbolic(List<bool> perms) {
      const chars = 'rwxrwxrwx';
      final buf = StringBuffer();
      for (int i = 0; i < 9; i++) {
        buf.write(perms[i] ? chars[i] : '-');
      }
      return buf.toString();
    }

    test('755 parses correctly', () {
      final perms = parseMode(parseOctal('755'));
      expect(toSymbolic(perms), 'rwxr-xr-x');
    });

    test('644 parses correctly', () {
      final perms = parseMode(parseOctal('644'));
      expect(toSymbolic(perms), 'rw-r--r--');
    });

    test('700 parses correctly', () {
      final perms = parseMode(parseOctal('700'));
      expect(toSymbolic(perms), 'rwx------');
    });

    test('777 parses correctly', () {
      final perms = parseMode(parseOctal('777'));
      expect(toSymbolic(perms), 'rwxrwxrwx');
    });

    test('000 parses correctly', () {
      final perms = parseMode(parseOctal('000'));
      expect(toSymbolic(perms), '---------');
    });

    test('round-trip mode parsing', () {
      for (final octal in ['644', '755', '700', '600', '777', '400', '666']) {
        final mode = parseOctal(octal);
        final perms = parseMode(mode);
        final restored = toMode(perms);
        expect(restored, mode, reason: 'Failed for $octal');
      }
    });

    test('symbolic to octal', () {
      final perms = parseMode(parseOctal('750'));
      expect(toSymbolic(perms), 'rwxr-x---');
      expect(toMode(perms).toRadixString(8), '750');
    });
  });
}

/// Simple test diff line model.
class _TestDiffLine {
  final String type;
  final String text;
  _TestDiffLine(this.type, this.text);
}
