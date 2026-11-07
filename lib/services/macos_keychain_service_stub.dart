import 'package:flutter/services.dart';

class MacosKeychainInfo {
  const MacosKeychainInfo({required this.path, required this.label});
  final String path;
  final String label;
}

class MacosKeychainService {
  static bool get isSupported => false;
  static Future<List<MacosKeychainInfo>> listKeychains({
    MethodChannel? channel,
  }) async => const [];
  static Future<void> selectKeychain(
    String path, {
    MethodChannel? channel,
  }) async => throw UnsupportedError('Keychain selection is macOS-only.');
  static Future<String?> chooseKeychain({
    String? initialPath,
    MethodChannel? channel,
  }) async => throw UnsupportedError('Keychain selection is macOS-only.');
  static Future<bool> restoreKeychainAccess(
    String path, {
    MethodChannel? channel,
  }) async =>
      throw UnsupportedError('Keychain access restoration is macOS-only.');
  static Future<String?> createKeychain(
    String initialPath,
    String password, {
    MethodChannel? channel,
  }) async => throw UnsupportedError('Keychain creation is macOS-only.');
}
