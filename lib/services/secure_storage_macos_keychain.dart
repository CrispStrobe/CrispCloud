import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'secure_storage_service.dart';
import 'credential_storage_diagnostics.dart';

/// An explicitly selected macOS file-based keychain. Every native operation is
/// scoped to [path]; failure never retries in the user's default keychain.
class MacOsCustomKeychainStorage extends SecureStorage
    implements CredentialStorageIdentity {
  MacOsCustomKeychainStorage({required this.path, MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const methodChannelName = 'com.crispcloud/custom_keychain';
  static const _defaultChannel = MethodChannel(methodChannelName);

  final String path;

  @override
  String get credentialStoreName =>
      'Custom macOS keychain (service com.crispcloud.credentials.v1)';
  @override
  String get credentialStoreLocation => path;
  final MethodChannel _channel;
  bool _initialized = false;
  Future<void>? _unlocking;
  Object? _unlockFailure;
  StackTrace? _unlockFailureStack;

  /// A deliberate Retry may ask Security.framework again after cancellation.
  void allowUnlockRetry() {
    _unlockFailure = null;
    _unlockFailureStack = null;
  }

  Future<void> _unlockSelectedKeychain() async {
    if (_unlockFailure != null) {
      Error.throwWithStackTrace(_unlockFailure!, _unlockFailureStack!);
    }
    final pending = _unlocking;
    if (pending != null) return pending;
    final attempt = _channel.invokeMethod<void>('unlock', {'path': path});
    _unlocking = attempt;
    try {
      await attempt;
    } catch (error, stack) {
      _unlockFailure = error;
      _unlockFailureStack = stack;
      rethrow;
    } finally {
      _unlocking = null;
    }
  }

  Future<T> _withUnlock<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PlatformException catch (error) {
      // This native error is raised before the operation touches any item.
      // Other errors, including permission failures, never trigger a retry.
      if (error.code != 'custom_keychain_locked') rethrow;
      await _unlockSelectedKeychain();
      return operation();
    }
  }

  static void _checkPlatform() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      throw UnsupportedError(
        'Custom keychain files are available only on macOS.',
      );
    }
  }

  /// Opens and probes only the selected keychain. Locked, missing and
  /// inaccessible keychains are explicit errors for the startup/retry UI.
  Future<void> initialize() async {
    _checkPlatform();
    _initialized = false;
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'A keychain path is required.');
    }
    allowUnlockRetry();
    await _withUnlock(
      () => _channel.invokeMethod<void>('initialize', {'path': path}),
    );
    _initialized = true;
  }

  Map<String, Object> _arguments([String? key]) {
    _checkPlatform();
    if (!_initialized) {
      throw StateError('Initialize the selected keychain before using it.');
    }
    if (key != null && key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'A credential key is required.');
    }
    return {'path': path, if (key != null) 'key': key};
  }

  /// Grants access through the native file picker, retaining a security-scoped
  /// bookmark for sandboxed builds. It does not change preferences or backend.
  /// Cancellation returns null. Save the returned path only after confirmation.
  static Future<String?> chooseKeychain({
    String? initialPath,
    MethodChannel? channel,
  }) async {
    _checkPlatform();
    return (channel ?? _defaultChannel).invokeMethod<String>('chooseKeychain', {
      if (initialPath != null) 'initialPath': initialPath,
    });
  }

  /// Regrants access only to the same configured existing file. Native code
  /// verifies the selected path and identity before replacing its bookmark.
  /// This does not initialize/select a store or change its App Lock policy.
  /// Cancellation is false; malformed replies and failures are explicit errors.
  static Future<bool> restoreKeychainAccess(
    String originalPath, {
    MethodChannel? channel,
  }) async {
    _checkPlatform();
    if (originalPath.trim().isEmpty) {
      throw ArgumentError('A configured keychain path is required.');
    }
    final restored = await (channel ?? _defaultChannel).invokeMethod<bool>(
      'restoreKeychainAccess',
      {'path': originalPath},
    );
    if (restored == null) {
      throw const FormatException(
        'Keychain access restoration returned no result.',
      );
    }
    return restored;
  }

  @override
  Future<String?> read(String key) {
    final arguments = _arguments(key);
    return _withUnlock(() => _channel.invokeMethod<String>('read', arguments));
  }

  @override
  Future<void> write(String key, String value) {
    final arguments = {..._arguments(key), 'value': value};
    return _withUnlock(() => _channel.invokeMethod<void>('write', arguments));
  }

  @override
  Future<void> delete(String key) {
    final arguments = _arguments(key);
    return _withUnlock(() => _channel.invokeMethod<void>('delete', arguments));
  }

  @override
  Future<bool> containsKey(String key) async {
    final arguments = _arguments(key);
    final result = await _withUnlock(
      () => _channel.invokeMethod<bool>('containsKey', arguments),
    );
    if (result == null) {
      throw const FormatException('The selected keychain returned no result.');
    }
    return result;
  }

  @override
  Future<void> deleteAll() {
    final arguments = _arguments();
    return _withUnlock(
      () => _channel.invokeMethod<void>('deleteAll', arguments),
    );
  }

  Future<Map<String, String>> readAll() async {
    final arguments = _arguments();
    final result = await _withUnlock(
      () => _channel.invokeMapMethod<String, String>('readAll', arguments),
    );
    if (result == null) {
      throw const FormatException('The selected keychain returned no result.');
    }
    return result;
  }
}
