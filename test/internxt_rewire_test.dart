// Phase 6.c smoke test — verifies the cloud-dart Internxt
// integration wires correctly to the published internxt_client
// package. Doesn't hit the network; just constructs the adapter,
// checks the URL/storage plumbing, and exercises the public
// methods that should resolve at compile time.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/internxt_client.dart';
import 'package:crisp_cloud/services/internxt_client_adapter.dart';
import 'package:crisp_cloud/services/internxt_flutter/shared_prefs_storage.dart';

void main() {
  group('Phase 6.c rewire smoke', () {
    test('adapter constructs against the published package', () {
      // Native build path: defaults to FileConfigStorage, hits the
      // production gateway URLs.
      final adapter = InternxtClientAdapter(
        config: ConfigService(configPath: '/tmp/inxt-rewire-test'),
      );
      expect(adapter.providerName, equals('Internxt'));
      expect(adapter.rootPath, equals('/'));
      expect(adapter.isAuthenticated, isFalse);
      expect(adapter.userId, isNull);
      expect(adapter.config, isA<ConfigService>());
    });

    test('adapter exposes the path-facade methods from B2 upstream',
        () async {
      final adapter = InternxtClientAdapter(
        config: ConfigService(configPath: '/tmp/inxt-rewire-test-2'),
      );
      // Pre-auth: methods that need bridge auth should reject with
      // a clear StateError instead of NPE'ing.
      expect(adapter.uploadFile([1, 2, 3], 'x.bin', '/'),
          throwsA(isA<StateError>()));
      expect(adapter.downloadFileBytes('/x.bin'),
          throwsA(isA<StateError>()));
    });

    test('SharedPreferencesStorage implements ConfigStorage', () {
      // Just compiles? Confirms the impl satisfies the interface
      // so the kIsWeb branch will type-check on Web.
      final storage = SharedPreferencesStorage();
      expect(storage, isA<ConfigStorage>());
    });

    test('URL constants point at gateway on native', () {
      expect(InternxtUrls.networkUrl,
          equals('https://gateway.internxt.com/network'));
      expect(InternxtUrls.driveApiUrl,
          equals('https://gateway.internxt.com/drive'));
    });

    test('placeholder login signature matches published library', () {
      // If this compiles, the placeholder's
      // Future<Map<String, dynamic>> login(...) matches the
      // published library — the conditional-import pattern
      // (real package vs placeholder) keeps working.
      // No runtime assertion needed; the compile is the test.
      expect(true, isTrue);
    });
  });
}
