import 'dart:io';

import 'package:flutter/services.dart';

class MacosKeychainInfo {
  const MacosKeychainInfo({required this.path, required this.label});
  final String path;
  final String label;
}

/// Thin bridge to the native Security.framework keychain selection/creation.
class MacosKeychainService {
  static const _channel = MethodChannel('crispcloud/keychain');

  static bool get isSupported => Platform.isMacOS;

  static Future<List<MacosKeychainInfo>> listKeychains() async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeMethod<List<dynamic>>('listKeychains');
    return (raw ?? const [])
        .whereType<Map>()
        .map(
          (item) => MacosKeychainInfo(
            path: item['path'] as String? ?? '',
            label: item['label'] as String? ?? '',
          ),
        )
        .where((item) => item.path.isNotEmpty)
        .toList(growable: false);
  }

  static Future<void> selectKeychain(String path) async {
    if (!isSupported) {
      throw UnsupportedError('Keychain selection is macOS-only.');
    }
    await _channel.invokeMethod<void>('selectKeychain', {'path': path});
  }

  static Future<void> createKeychain(String path, String password) async {
    if (!isSupported) {
      throw UnsupportedError('Keychain creation is macOS-only.');
    }
    await _channel.invokeMethod<void>('createKeychain', {
      'path': path,
      'password': password,
    });
  }
}
