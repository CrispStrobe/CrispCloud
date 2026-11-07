import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'secure_storage_service.dart';

/// An explicitly selected macOS file-based keychain. Every native operation is
/// scoped to [path]; failure never retries in the user's default keychain.
class MacOsCustomKeychainStorage extends SecureStorage {
  MacOsCustomKeychainStorage({required this.path, MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const methodChannelName = 'com.crispcloud/custom_keychain';
  static const _defaultChannel = MethodChannel(methodChannelName);

  final String path;
  final MethodChannel _channel;
  bool _initialized = false;

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
    await _channel.invokeMethod<void>('initialize', {'path': path});
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
  Future<String?> read(String key) =>
      _channel.invokeMethod<String>('read', _arguments(key));

  @override
  Future<void> write(String key, String value) => _channel.invokeMethod<void>(
    'write',
    {..._arguments(key), 'value': value},
  );

  @override
  Future<void> delete(String key) =>
      _channel.invokeMethod<void>('delete', _arguments(key));

  @override
  Future<bool> containsKey(String key) async {
    final result = await _channel.invokeMethod<bool>(
      'containsKey',
      _arguments(key),
    );
    if (result == null) {
      throw const FormatException('The selected keychain returned no result.');
    }
    return result;
  }

  @override
  Future<void> deleteAll() =>
      _channel.invokeMethod<void>('deleteAll', _arguments());

  Future<Map<String, String>> readAll() async {
    final result = await _channel.invokeMapMethod<String, String>(
      'readAll',
      _arguments(),
    );
    if (result == null) {
      throw const FormatException('The selected keychain returned no result.');
    }
    return result;
  }
}
