import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'secure_storage_macos_keychain.dart';

class MacosKeychainInfo {
  const MacosKeychainInfo({required this.path, required this.label});
  final String path;
  final String label;
}

/// Discovery and explicit file-keychain setup. These operations never change
/// the user's default keychain/search list or save the app's backend choice.
class MacosKeychainService {
  static const _channel = MethodChannel(
    MacOsCustomKeychainStorage.methodChannelName,
  );

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static Future<List<MacosKeychainInfo>> listKeychains({
    MethodChannel? channel,
  }) async {
    if (!isSupported) return const [];
    final raw = await (channel ?? _channel).invokeMethod<List<dynamic>>(
      'listKeychains',
    );
    if (raw == null) {
      throw const FormatException('The keychain list returned no result.');
    }
    return raw
        .map((item) {
          if (item is! Map ||
              item['path'] is! String ||
              item['label'] is! String ||
              (item['path'] as String).isEmpty) {
            throw const FormatException(
              'The keychain list contains an invalid entry.',
            );
          }
          return MacosKeychainInfo(
            path: item['path'] as String,
            label: item['label'] as String,
          );
        })
        .toList(growable: false);
  }

  /// Validates only this file with the scoped adapter. The caller decides
  /// whether to save it as the app's selection after the probe succeeds.
  static Future<void> selectKeychain(
    String path, {
    MethodChannel? channel,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Keychain selection is macOS-only.');
    }
    await MacOsCustomKeychainStorage(path: path, channel: channel).initialize();
  }

  static Future<String?> chooseKeychain({
    String? initialPath,
    MethodChannel? channel,
  }) => MacOsCustomKeychainStorage.chooseKeychain(
    initialPath: initialPath,
    channel: channel,
  );

  /// Repairs sandbox access to the configured file without changing stores.
  static Future<bool> restoreKeychainAccess(
    String path, {
    MethodChannel? channel,
  }) =>
      MacOsCustomKeychainStorage.restoreKeychainAccess(path, channel: channel);

  /// Shows the native save panel and creates a new private keychain with the
  /// exact password supplied. Returns the actual bookmarked file path, or null
  /// on cancellation. Existing files are never replaced; no backend is saved.
  static Future<String?> createKeychain(
    String initialPath,
    String password, {
    MethodChannel? channel,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Keychain creation is macOS-only.');
    }
    if (password.isEmpty) {
      throw ArgumentError('Enter a password for the new keychain.');
    }
    final path = await (channel ?? _channel).invokeMethod<String>(
      'createKeychain',
      {'initialPath': initialPath, 'password': password},
    );
    if (path != null && path.isEmpty) {
      throw const FormatException('Keychain creation returned an empty path.');
    }
    return path;
  }
}
