// lib/services/file_provider_bridge.dart
//
// Flutter-side bridge for the iOS FileProvider extension.
//
// Responsibilities:
// 1. Sync connected-provider metadata (provider name, label, auth tokens)
//    to the shared App Group container via a platform MethodChannel.
// 2. Register/unregister the NSFileProviderDomain on connect/disconnect.
// 3. Signal the FileProvider extension to re-enumerate after changes.
//
// This service is iOS-only. On other platforms the methods are no-ops.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'log_service.dart';

const _log = Log('FileProviderBridge');

/// Descriptor for a connected cloud provider, serialised to the shared
/// App Group UserDefaults so the FileProvider extension can read it.
class FileProviderConnection {
  /// Internal provider key (matches [CloudProvider] enum name).
  final String provider;

  /// Human-readable label shown in the Files app (e.g. "My S3 Bucket").
  final String label;

  /// Serialised credentials the extension can use to authenticate.
  /// The exact shape depends on the provider; typically includes an
  /// auth token or API key.
  final Map<String, String> credentials;

  const FileProviderConnection({
    required this.provider,
    required this.label,
    required this.credentials,
  });

  Map<String, String> toJson() => {
        'provider': provider,
        'label': label,
        ...credentials,
      };
}

/// Bridge between the Flutter app and the iOS FileProvider extension.
///
/// Usage (typically from AuthNotifier or a connection manager):
/// ```dart
/// await FileProviderBridge.instance.syncConnections([
///   FileProviderConnection(
///     provider: 's3',
///     label: 'Work S3',
///     credentials: {'token': '...', 'listEndpoint': '...'},
///   ),
/// ]);
/// ```
class FileProviderBridge {
  FileProviderBridge._();

  static final FileProviderBridge instance = FileProviderBridge._();

  /// The method channel shared with the native iOS AppDelegate.
  static const _channel = MethodChannel('com.crispcloud/file_provider');

  /// Whether the FileProvider bridge is available on the current platform.
  bool get isAvailable => !kIsWeb && Platform.isIOS;

  /// Push the current list of connected providers to the shared App Group
  /// container. Call this whenever a connection is added, removed, or
  /// its credentials are refreshed.
  ///
  /// On non-iOS platforms this is a no-op.
  Future<void> syncConnections(List<FileProviderConnection> connections) async {
    if (!isAvailable) return;

    try {
      final payload = connections.map((c) => c.toJson()).toList();
      await _channel.invokeMethod('syncConnections', {
        'connections': json.encode(payload),
      });
      _log.info(
          'Synced ${connections.length} connection(s) to FileProvider shared container');
    } on PlatformException catch (e) {
      _log.warn('Failed to sync connections to FileProvider: ${e.message}');
    } on MissingPluginException {
      // Expected when running on simulator without native side configured.
      _log.debug('FileProvider method channel not available (expected on simulator)');
    }
  }

  /// Register the CrispCloud domain with the system FileProvider manager.
  /// Call once after the app starts and at least one provider is connected.
  Future<void> registerDomain() async {
    if (!isAvailable) return;

    try {
      await _channel.invokeMethod('registerFileProviderDomain');
      _log.info('FileProvider domain registered');
    } on PlatformException catch (e) {
      _log.warn('Failed to register FileProvider domain: ${e.message}');
    } on MissingPluginException {
      _log.debug('FileProvider method channel not available');
    }
  }

  /// Remove the CrispCloud domain from the system FileProvider manager.
  /// Call when the user logs out of all providers.
  Future<void> unregisterDomain() async {
    if (!isAvailable) return;

    try {
      await _channel.invokeMethod('unregisterFileProviderDomain');
      _log.info('FileProvider domain unregistered');
    } on PlatformException catch (e) {
      _log.warn('Failed to unregister FileProvider domain: ${e.message}');
    } on MissingPluginException {
      _log.debug('FileProvider method channel not available');
    }
  }

  /// Ask the system to re-enumerate the FileProvider contents.
  /// Call after uploading, deleting, or renaming files so the Files app
  /// reflects the latest state.
  Future<void> signalEnumeratorChanged() async {
    if (!isAvailable) return;

    try {
      await _channel.invokeMethod('signalEnumeratorChanged');
    } on PlatformException catch (e) {
      _log.warn('Failed to signal enumerator change: ${e.message}');
    } on MissingPluginException {
      // Silently ignore on simulator.
    }
  }

  /// Check whether the extension has flagged that credentials need refreshing.
  Future<bool> needsCredentialRefresh() async {
    if (!isAvailable) return false;

    try {
      final result =
          await _channel.invokeMethod<bool>('needsCredentialRefresh');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Clear the credential-refresh flag after the main app has re-authenticated.
  Future<void> clearCredentialRefreshFlag() async {
    if (!isAvailable) return;

    try {
      await _channel.invokeMethod('clearCredentialRefreshFlag');
    } on PlatformException catch (e) {
      _log.warn('Failed to clear credential refresh flag: ${e.message}');
    } on MissingPluginException {
      // Silently ignore.
    }
  }
}
