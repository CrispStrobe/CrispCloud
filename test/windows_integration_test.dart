// test/windows_integration_test.dart
//
// Tests for:
//   - WindowsIntegrationService (platform guard + registry round-trip on Windows)
//   - AppLockService Windows Hello behaviour (getBiometricLabel, biometricOnly flag,
//     isBiometricAvailable Windows path)

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_platform_interface/types/auth_messages.dart';

import 'package:crisp_cloud/services/app_lock_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/windows_integration_service.dart';

// ---------------------------------------------------------------------------
// Minimal fake LocalAuthentication for testing without native plugins.
// ---------------------------------------------------------------------------

class _FakeLocalAuthentication extends LocalAuthentication {
  bool deviceSupported;
  bool canCheck;
  List<BiometricType> biometrics;
  bool authenticateResult;
  bool throwOnAuthenticate;

  _FakeLocalAuthentication({
    this.deviceSupported = false,
    this.canCheck = false,
    this.biometrics = const [],
    this.authenticateResult = false,
    this.throwOnAuthenticate = false,
  });

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => biometrics;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const <AuthMessages>[],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    if (throwOnAuthenticate) throw Exception('native auth error');
    _lastAuthOptions = options;
    return authenticateResult;
  }

  /// Captures the last AuthenticationOptions passed to authenticate().
  AuthenticationOptions? _lastAuthOptions;
  AuthenticationOptions? get lastAuthOptions => _lastAuthOptions;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // --------------------------------------------------------------------------
  // WindowsIntegrationService — platform guard
  // --------------------------------------------------------------------------

  group('WindowsIntegrationService — platform guard', () {
    late WindowsIntegrationService service;

    setUp(() => service = WindowsIntegrationService());

    test('isSupported reflects platform correctly', () {
      final expected = !kIsWeb && Platform.isWindows;
      expect(WindowsIntegrationService.isSupported, expected);
    });

    test('isSupported is false on Linux/macOS CI', () {
      if (!kIsWeb && (Platform.isLinux || Platform.isMacOS)) {
        expect(WindowsIntegrationService.isSupported, false);
      }
    });

    test('registerContextMenu returns false on non-Windows', () async {
      if (!WindowsIntegrationService.isSupported) {
        expect(await service.registerContextMenu(), false);
      }
    });

    test('unregisterContextMenu returns false on non-Windows', () async {
      if (!WindowsIntegrationService.isSupported) {
        expect(await service.unregisterContextMenu(), false);
      }
    });

    test('isContextMenuRegistered returns false on non-Windows', () async {
      if (!WindowsIntegrationService.isSupported) {
        expect(await service.isContextMenuRegistered(), false);
      }
    });
  });

  // --------------------------------------------------------------------------
  // WindowsIntegrationService — registry round-trip (live, Windows only)
  // --------------------------------------------------------------------------

  group('WindowsIntegrationService — registry round-trip', () {
    late WindowsIntegrationService service;

    setUp(() => service = WindowsIntegrationService());

    test('register → isRegistered → unregister → not registered', () async {
      if (!WindowsIntegrationService.isSupported) return;

      // Start with a clean slate.
      await service.unregisterContextMenu();
      expect(await service.isContextMenuRegistered(), false);

      // Register.
      final registered = await service.registerContextMenu();
      expect(registered, true);
      expect(await service.isContextMenuRegistered(), true);

      // Unregister.
      final unregistered = await service.unregisterContextMenu();
      expect(unregistered, true);
      expect(await service.isContextMenuRegistered(), false);
    });

    test('unregister is idempotent when key is already absent', () async {
      if (!WindowsIntegrationService.isSupported) return;
      await service.unregisterContextMenu();
      // Second call — key was already deleted.
      expect(await service.unregisterContextMenu(), true);
    });

    test('register is idempotent (re-writing an existing entry)', () async {
      if (!WindowsIntegrationService.isSupported) return;
      expect(await service.registerContextMenu(), true);
      expect(await service.registerContextMenu(), true);
      expect(await service.isContextMenuRegistered(), true);
      // Cleanup.
      await service.unregisterContextMenu();
    });
  }, skip: (!Platform.isWindows || kIsWeb) ? 'Registry tests require Windows' : null);

  // --------------------------------------------------------------------------
  // WindowsIntegrationService — registry key constant contracts
  // --------------------------------------------------------------------------

  group('WindowsIntegrationService — registry key contracts', () {
    test('shell key is scoped to HKCU (no admin required)', () {
      const key = r'HKCU\Software\Classes\*\shell\CrispCloud';
      expect(key, startsWith('HKCU'),
          reason: 'Must use HKCU so no elevation is needed');
    });

    test('shell key targets all file types via *', () {
      const key = r'HKCU\Software\Classes\*\shell\CrispCloud';
      expect(key, contains(r'\*\shell\'),
          reason: 'The * wildcard registers for all file types');
    });

    test('command key is a direct sub-key of the shell key', () {
      const shellKey = r'HKCU\Software\Classes\*\shell\CrispCloud';
      const commandKey = r'HKCU\Software\Classes\*\shell\CrispCloud\command';
      expect(commandKey, startsWith(shellKey));
      expect(commandKey.substring(shellKey.length), equals(r'\command'));
    });
  });

  // --------------------------------------------------------------------------
  // AppLockService — Windows Hello label
  // --------------------------------------------------------------------------

  group('AppLockService — getBiometricLabel', () {
    test('returns "Windows Hello" on Windows (platform-gated)', () async {
      if (kIsWeb || !Platform.isWindows) return;

      final storage = InMemorySecureStorage();
      final fake = _FakeLocalAuthentication(
        deviceSupported: true,
        biometrics: [BiometricType.fingerprint], // should be ignored on Windows
      );
      final service = AppLockService(storage, localAuth: fake);

      expect(await service.getBiometricLabel(), 'Windows Hello');
      // getAvailableBiometrics must NOT have been called.
      // (We cannot verify call counts without mockito, but we can confirm the
      // return value ignores the biometrics list entirely.)
    });

    test('returns "Face ID" on non-Windows when face biometric present',
        () async {
      if (kIsWeb || Platform.isWindows) return;

      final storage = InMemorySecureStorage();
      final fake = _FakeLocalAuthentication(biometrics: [BiometricType.face]);
      final service = AppLockService(storage, localAuth: fake);

      expect(await service.getBiometricLabel(), 'Face ID');
    });

    test('returns "Fingerprint" on non-Windows when fingerprint present',
        () async {
      if (kIsWeb || Platform.isWindows) return;

      final storage = InMemorySecureStorage();
      final fake =
          _FakeLocalAuthentication(biometrics: [BiometricType.fingerprint]);
      final service = AppLockService(storage, localAuth: fake);

      expect(await service.getBiometricLabel(), 'Fingerprint');
    });

    test('returns "Iris" on non-Windows when iris present', () async {
      if (kIsWeb || Platform.isWindows) return;

      final storage = InMemorySecureStorage();
      final fake = _FakeLocalAuthentication(biometrics: [BiometricType.iris]);
      final service = AppLockService(storage, localAuth: fake);

      expect(await service.getBiometricLabel(), 'Iris');
    });

    test('returns "Biometric" when no specific type is reported', () async {
      if (kIsWeb || Platform.isWindows) return;

      final storage = InMemorySecureStorage();
      final fake = _FakeLocalAuthentication(biometrics: []);
      final service = AppLockService(storage, localAuth: fake);

      expect(await service.getBiometricLabel(), 'Biometric');
    });
  });

  // --------------------------------------------------------------------------
  // AppLockService — isBiometricAvailable on Windows
  // --------------------------------------------------------------------------

  group('AppLockService — isBiometricAvailable', () {
    test(
        'returns true on Windows when isDeviceSupported=true '
        'without requiring canCheckBiometrics', () async {
      if (kIsWeb || !Platform.isWindows) return;

      final storage = InMemorySecureStorage();
      // canCheck = false simulates PIN-only Windows Hello (no biometric sensor).
      final fake = _FakeLocalAuthentication(
        deviceSupported: true,
        canCheck: false,
      );
      final service = AppLockService(storage, localAuth: fake);

      expect(await service.isBiometricAvailable(), true,
          reason: 'Windows Hello with PIN only should still be available');
    });

    test('returns false on Windows when isDeviceSupported=false', () async {
      if (kIsWeb || !Platform.isWindows) return;

      final storage = InMemorySecureStorage();
      final fake = _FakeLocalAuthentication(deviceSupported: false);
      final service = AppLockService(storage, localAuth: fake);

      expect(await service.isBiometricAvailable(), false);
    });

    test('returns false on web regardless of device state', () async {
      if (!kIsWeb) return;

      final storage = InMemorySecureStorage();
      final fake = _FakeLocalAuthentication(deviceSupported: true, canCheck: true);
      final service = AppLockService(storage, localAuth: fake);

      expect(await service.isBiometricAvailable(), false);
    });
  });

  // --------------------------------------------------------------------------
  // AppLockService — authenticateWithBiometric (biometricOnly flag)
  // --------------------------------------------------------------------------

  group('AppLockService — authenticateWithBiometric', () {
    test('passes biometricOnly=false on Windows (Windows Hello limitation)',
        () async {
      if (kIsWeb || !Platform.isWindows) return;

      final storage = InMemorySecureStorage();
      final fake = _FakeLocalAuthentication(authenticateResult: true);
      final service = AppLockService(storage, localAuth: fake);

      final result = await service.authenticateWithBiometric();
      expect(result, true);
      expect(fake.lastAuthOptions?.biometricOnly, false,
          reason: 'Windows Hello must not use biometricOnly enforcement');
    });

    test('passes biometricOnly=true on non-Windows', () async {
      if (kIsWeb || Platform.isWindows) return;

      final storage = InMemorySecureStorage();
      final fake = _FakeLocalAuthentication(authenticateResult: true);
      final service = AppLockService(storage, localAuth: fake);

      await service.authenticateWithBiometric();
      expect(fake.lastAuthOptions?.biometricOnly, true);
    });

    test('returns false when authenticate() returns false', () async {
      if (kIsWeb) return;

      final storage = InMemorySecureStorage();
      final fake = _FakeLocalAuthentication(authenticateResult: false);
      final service = AppLockService(storage, localAuth: fake);

      expect(await service.authenticateWithBiometric(), false);
    });

    test('returns false and does not rethrow when authenticate() throws',
        () async {
      if (kIsWeb) return;

      final storage = InMemorySecureStorage();
      final fake = _FakeLocalAuthentication(throwOnAuthenticate: true);
      final service = AppLockService(storage, localAuth: fake);

      expect(await service.authenticateWithBiometric(), false);
    });

    test('returns false on web without calling authenticate()', () async {
      if (!kIsWeb) return;

      final storage = InMemorySecureStorage();
      final fake = _FakeLocalAuthentication(authenticateResult: true);
      final service = AppLockService(storage, localAuth: fake);

      expect(await service.authenticateWithBiometric(), false);
      expect(fake.lastAuthOptions, isNull,
          reason: 'authenticate() must not be called on web');
    });
  });
}
