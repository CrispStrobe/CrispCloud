// Touch ID unlock for the encrypted credential vault (macOS; iOS-ready API).
//
// Secret: the vault's 32-byte AES key derived from the master password
// (PBKDF2-HMAC-SHA256), never the password itself. The vault can be opened
// with that key directly (WebEncryptedStorage.initializeWithKey verifies it
// against the vault's verification token), so the password never leaves the
// unlock prompt. The key is only as powerful as the password for this one
// vault, cannot be reused elsewhere, and is invalidated by any re-keying.
//
// Storage and enforcement are native (macos/Runner/BiometricVaultKeychain.swift):
// a data-protection-keychain generic password with
// SecAccessControl(kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
// .biometryCurrentSet). The OS shows the Touch ID sheet when the item is read
// and refuses it after the enrolled fingers change. This class is not a
// boolean gate; it only decides when to ask and how to fall back.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';
import 'secure_storage_web.dart';

const _log = Log('BiometricVaultUnlock');

enum BiometricAvailability {
  available,

  /// Touch ID hardware exists but no finger is enrolled.
  notEnrolled,

  /// No biometric sensor (or none usable right now, e.g. lid closed).
  noBiometrics,

  /// The build lacks the keychain-access-groups entitlement (-34018);
  /// typical of ad-hoc/local builds without a team provisioning profile.
  missingEntitlement,

  /// Not implemented for this platform (only macOS is enabled).
  unsupportedPlatform,
  unavailable,
}

enum BiometricReadStatus {
  ok,
  cancelled,
  notFound,
  invalidated,
  failed,
  unavailable,
  error,
}

class BiometricReadResult {
  const BiometricReadResult(this.status, [this.secret]);
  final BiometricReadStatus status;
  final Uint8List? secret;
}

/// Platform store for one biometry-protected secret.
abstract class BiometricSecretStore {
  /// Whether this platform has an implementation at all.
  bool get isSupported;
  Future<BiometricAvailability> availability();

  /// Returns the availability-style failure, or null on success.
  Future<BiometricAvailability?> store(Uint8List secret);
  Future<BiometricReadResult> read(String reason);
  Future<void> delete();
}

class MethodChannelBiometricSecretStore implements BiometricSecretStore {
  MethodChannelBiometricSecretStore({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel(channelName),
      _supported =
          supported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS);

  static const channelName = 'crispcloud/biometric_vault';
  final MethodChannel _channel;
  final bool _supported;

  @override
  bool get isSupported => _supported;

  Future<Map<Object?, Object?>> _call(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final reply = await _channel.invokeMethod<Object?>(method, arguments);
    if (reply is! Map) throw StateError('Malformed biometric reply');
    return reply;
  }

  static BiometricAvailability _availability(Object? status) =>
      switch (status) {
        'available' => BiometricAvailability.available,
        'notEnrolled' => BiometricAvailability.notEnrolled,
        'noBiometrics' => BiometricAvailability.noBiometrics,
        'missingEntitlement' => BiometricAvailability.missingEntitlement,
        _ => BiometricAvailability.unavailable,
      };

  @override
  Future<BiometricAvailability> availability() async {
    if (!_supported) return BiometricAvailability.unsupportedPlatform;
    try {
      return _availability((await _call('isAvailable'))['status']);
    } on MissingPluginException {
      return BiometricAvailability.unsupportedPlatform;
    } catch (_) {
      return BiometricAvailability.unavailable;
    }
  }

  @override
  Future<BiometricAvailability?> store(Uint8List secret) async {
    if (!_supported) return BiometricAvailability.unsupportedPlatform;
    final reply = await _call('store', {'secret': secret});
    final status = reply['status'];
    if (status == 'ok') return null;
    return status == 'error'
        ? BiometricAvailability.unavailable
        : _availability(status);
  }

  @override
  Future<BiometricReadResult> read(String reason) async {
    if (!_supported) {
      return const BiometricReadResult(BiometricReadStatus.unavailable);
    }
    final Map<Object?, Object?> reply;
    try {
      reply = await _call('read', {'reason': reason});
    } on MissingPluginException {
      return const BiometricReadResult(BiometricReadStatus.unavailable);
    }
    final status = BiometricReadStatus.values.firstWhere(
      (value) => value.name == reply['status'],
      orElse: () => BiometricReadStatus.error,
    );
    final secret = reply['secret'];
    if (status == BiometricReadStatus.ok) {
      if (secret is! Uint8List) {
        return const BiometricReadResult(BiometricReadStatus.error);
      }
      return BiometricReadResult(status, secret);
    }
    return BiometricReadResult(status);
  }

  @override
  Future<void> delete() async {
    if (!_supported) return;
    try {
      final reply = await _call('delete');
      if (reply['status'] != 'ok') {
        throw StateError('Touch ID unlock item could not be removed');
      }
    } on MissingPluginException {
      // No native side: nothing can have been stored.
    }
  }
}

enum BiometricUnlockOutcome {
  /// The vault is unlocked.
  unlocked,

  /// Not enabled, or Touch ID is not usable right now; ask for the password.
  notAttempted,

  /// The user dismissed the sheet or authentication failed; still enabled.
  cancelled,

  /// The stored key is gone or no longer matches (biometry or vault changed).
  /// It was removed; the next password unlock offers re-enrolment.
  invalidated,
}

/// Decides when to use, offer, and remove the Touch ID unlock secret.
class BiometricVaultUnlock {
  BiometricVaultUnlock({
    BiometricSecretStore? store,
    Future<SharedPreferences> Function()? preferences,
  }) : _store = store ?? MethodChannelBiometricSecretStore(),
       _preferences = preferences ?? SharedPreferences.getInstance;

  static const enabledKey = 'credential_vault_touch_id_v1';
  static const offerDeclinedKey = 'credential_vault_touch_id_declined_v1';

  /// [WebEncryptedStorage.initializeWithKey] failures meaning the stored key
  /// can never open this vault again.
  @visibleForTesting
  static const staleKeyErrors = {
    'Incorrect master password or damaged vault',
    'Credential vault is missing',
  };

  final BiometricSecretStore _store;
  final Future<SharedPreferences> Function() _preferences;

  bool get isSupported => _store.isSupported;

  Future<bool> isEnabled() async =>
      _store.isSupported &&
      ((await _preferences()).getBool(enabledKey) ?? false);

  Future<BiometricAvailability> availability() => _store.availability();

  /// After a successful password unlock: offer only when usable, not already
  /// on, and the user has not said "Not now" since the last invalidation.
  Future<bool> shouldOffer() async {
    if (!_store.isSupported || await isEnabled()) return false;
    if ((await _preferences()).getBool(offerDeclinedKey) ?? false) return false;
    return await _store.availability() == BiometricAvailability.available;
  }

  Future<void> declineOffer() async {
    await (await _preferences()).setBool(offerDeclinedKey, true);
  }

  /// Store the unlocked vault's key behind Touch ID. Returns null on success,
  /// else why it is unavailable. The key copy is zeroed after the native call.
  Future<BiometricAvailability?> enable(WebEncryptedStorage storage) async {
    final available = await _store.availability();
    if (available != BiometricAvailability.available) return available;
    final key = await storage.exportUnlockKey();
    if (key == null) return BiometricAvailability.unavailable;
    try {
      final failure = await _store.store(key);
      if (failure != null) return failure;
    } finally {
      key.fillRange(0, key.length, 0);
    }
    final preferences = await _preferences();
    await preferences.setBool(enabledKey, true);
    await preferences.remove(offerDeclinedKey);
    _log.info('Touch ID vault unlock enabled');
    return null;
  }

  /// Remove the keychain item and the preference. Used when the user turns it
  /// off, the vault is reset or missing, or the storage mode changes.
  Future<void> disable({bool reoffer = false}) async {
    final preferences = await _preferences();
    await preferences.remove(enabledKey);
    if (reoffer) await preferences.remove(offerDeclinedKey);
    await _store.delete();
  }

  /// Remove a leftover item when it is enabled. Never throws.
  Future<void> removeIfEnabled() async {
    try {
      if (await isEnabled()) await disable();
    } catch (error) {
      _log.warn('Could not remove Touch ID vault unlock', error);
    }
  }

  /// Touch ID first. Any non-success leaves [storage] locked for the password
  /// prompt; stale secrets are removed so the next password unlock re-offers.
  Future<BiometricUnlockOutcome> tryUnlock(
    WebEncryptedStorage storage,
    String reason,
  ) async {
    if (!await isEnabled()) return BiometricUnlockOutcome.notAttempted;
    final BiometricReadResult result;
    try {
      result = await _store.read(reason);
    } catch (error) {
      _log.warn('Touch ID vault unlock failed', error);
      return BiometricUnlockOutcome.notAttempted;
    }
    switch (result.status) {
      case BiometricReadStatus.ok:
        final secret = result.secret!;
        try {
          await storage.initializeWithKey(secret);
          return BiometricUnlockOutcome.unlocked;
        } on StateError catch (error) {
          if (!staleKeyErrors.contains(error.message)) {
            // Lock contention, I/O or a damaged file: keep the item and let
            // the password prompt (and its diagnostics) handle the vault.
            _log.warn('Touch ID vault unlock could not open the vault', error);
            return BiometricUnlockOutcome.notAttempted;
          }
          // The vault was re-keyed, replaced or removed: this key is useless.
          _log.info('Stored Touch ID vault key no longer matches the vault');
          await _invalidate();
          return BiometricUnlockOutcome.invalidated;
        } finally {
          secret.fillRange(0, secret.length, 0);
        }
      case BiometricReadStatus.notFound:
      case BiometricReadStatus.invalidated:
        await _invalidate();
        return BiometricUnlockOutcome.invalidated;
      case BiometricReadStatus.cancelled:
      case BiometricReadStatus.failed:
        return BiometricUnlockOutcome.cancelled;
      case BiometricReadStatus.unavailable:
      case BiometricReadStatus.error:
        return BiometricUnlockOutcome.notAttempted;
    }
  }

  Future<void> _invalidate() async {
    try {
      await disable(reoffer: true);
    } catch (error) {
      _log.warn('Could not remove stale Touch ID vault unlock', error);
    }
  }
}

final biometricVaultUnlockProvider = Provider<BiometricVaultUnlock>(
  (ref) => BiometricVaultUnlock(),
);
