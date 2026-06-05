// lib/services/documents_provider_bridge.dart
//
// Flutter-side bridge for the Android DocumentsProvider.
//
// Responsibilities:
// 1. Write connected-provider metadata to SharedPreferences so the
//    CrispCloudDocumentsProvider Kotlin class can read it without going
//    through the Flutter engine (needed for cold-start and background
//    document queries).
// 2. Notify the Android system when the root list changes (provider
//    connected / disconnected) via a MethodChannel call.
// 3. Register a MethodChannel handler so the Kotlin side can call back
//    into Dart for file operations (listDirectory, readFile, writeFile,
//    createDocument, deleteDocument, renameDocument).
//
// Platform guard: all public methods are no-ops on non-Android platforms.
// This keeps callers clean — no `if (Platform.isAndroid)` scattered around.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_storage_interface.dart' show CloudStorageClient;
import 'log_service.dart';

const _log = Log('DocumentsProviderBridge');

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Metadata for a single connected cloud provider exposed to the Android
/// DocumentsProvider.
class DocumentsProviderConnection {
  /// Internal provider key (e.g. "s3", "dropbox").
  final String provider;

  /// Human-readable label shown in the Android file picker.
  final String label;

  /// Root document ID for this provider.  Defaults to "<provider>:/".
  final String rootDocumentId;

  const DocumentsProviderConnection({
    required this.provider,
    required this.label,
    String? rootDocumentId,
  }) : rootDocumentId = rootDocumentId ?? '$provider:/';

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'label': label,
        'rootDocumentId': rootDocumentId,
      };

  factory DocumentsProviderConnection.fromJson(Map<String, dynamic> json) =>
      DocumentsProviderConnection(
        provider: json['provider'] as String,
        label: json['label'] as String? ?? json['provider'] as String,
        rootDocumentId: json['rootDocumentId'] as String?,
      );

  @override
  String toString() =>
      'DocumentsProviderConnection(provider: $provider, label: $label, '
      'rootDocumentId: $rootDocumentId)';
}

// ---------------------------------------------------------------------------
// Bridge
// ---------------------------------------------------------------------------

/// Bridges the Flutter app and the Android [CrispCloudDocumentsProvider].
///
/// Typical usage:
/// ```dart
/// // After signing in to a provider:
/// await DocumentsProviderBridge.instance.syncConnections([
///   DocumentsProviderConnection(provider: 's3', label: 'My Bucket'),
/// ]);
///
/// // To signal root list changes:
/// await DocumentsProviderBridge.instance.refreshRoots();
///
/// // Register file-operation handlers (call once, e.g. in main.dart):
/// DocumentsProviderBridge.instance.registerHandlers(myStorageService);
/// ```
class DocumentsProviderBridge {
  DocumentsProviderBridge._();

  static final DocumentsProviderBridge instance = DocumentsProviderBridge._();

  // MethodChannel shared with CrispCloudDocumentsProvider.kt.
  static const _channel =
      MethodChannel('com.crispcloud/documents_provider');

  // SharedPreferences keys (must match CrispCloudDocumentsProvider.kt).
  // ignore: unused_field
  static const _prefsName = 'crisp_cloud_documents_provider';
  static const _prefsKeyProviders = 'connected_providers';

  // Cached list of connections for synchronous access.
  final List<DocumentsProviderConnection> _connections = [];

  // Optional storage-backend delegate for handling file operation callbacks.
  CloudStorageClient? _storageDelegate;

  // ---------------------------------------------------------------------------
  // Platform guard
  // ---------------------------------------------------------------------------

  /// Whether the DocumentsProvider bridge is available on the current platform.
  bool get isAvailable => !kIsWeb && !kIsTestEnvironment && Platform.isAndroid;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Pushes the current list of connected providers to SharedPreferences and
  /// notifies the system that the root list has changed.
  ///
  /// Call this whenever a provider is connected, disconnected, or its
  /// credentials are refreshed.
  ///
  /// On non-Android platforms this is a no-op.
  Future<void> syncConnections(
      List<DocumentsProviderConnection> connections) async {
    _connections
      ..clear()
      ..addAll(connections);

    if (!isAvailable) {
      _log.debug(
          'DocumentsProviderBridge: not Android — skipping syncConnections');
      return;
    }

    try {
      final payload =
          json.encode(connections.map((c) => c.toJson()).toList());

      // Write to SharedPreferences so the provider can read without the
      // Flutter engine being alive.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyProviders, payload);

      _log.info(
          'Synced ${connections.length} provider(s) to DocumentsProvider prefs');

      // Also notify via MethodChannel so the Kotlin side can call
      // notifyRootsChanged() immediately.
      await _channel.invokeMethod<void>('syncConnections', {
        'connections': payload,
      });
    } on PlatformException catch (e) {
      _log.warn('DocumentsProviderBridge syncConnections error: ${e.message}');
    } on MissingPluginException {
      _log.debug('DocumentsProvider channel not available (expected in tests)');
    } catch (e, st) {
      _log.error('DocumentsProviderBridge syncConnections unexpected error',
          e, st);
    }
  }

  /// Notifies Android that the list of available roots (providers) has changed.
  ///
  /// Should be called after connecting or disconnecting a provider so the
  /// file-picker sidebar updates without delay.
  ///
  /// On non-Android platforms this is a no-op.
  Future<void> refreshRoots() async {
    if (!isAvailable) {
      _log.debug('DocumentsProviderBridge: not Android — skipping refreshRoots');
      return;
    }

    try {
      await _channel.invokeMethod<void>('refreshRoots');
      _log.info('DocumentsProvider roots refresh requested');
    } on PlatformException catch (e) {
      _log.warn('DocumentsProviderBridge refreshRoots error: ${e.message}');
    } on MissingPluginException {
      _log.debug('DocumentsProvider channel not available (expected in tests)');
    }
  }

  /// Notifies Android that the document at [path] has changed.
  ///
  /// Use this after uploading, deleting, or renaming a file so any open
  /// file pickers reflect the latest state.
  ///
  /// On non-Android platforms this is a no-op.
  Future<void> notifyChange(String path) async {
    if (!isAvailable) return;

    try {
      await _channel.invokeMethod<void>('notifyChange', {'path': path});
      _log.debug('DocumentsProvider change notification sent for $path');
    } on PlatformException catch (e) {
      _log.warn('DocumentsProviderBridge notifyChange error: ${e.message}');
    } on MissingPluginException {
      // Silently ignore.
    }
  }

  /// Returns the current list of connected providers with their root IDs.
  ///
  /// This is the in-memory cached list; it reflects the last call to
  /// [syncConnections].  On non-Android platforms it still returns the
  /// cached list so callers can reason about state without platform checks.
  List<DocumentsProviderConnection> getConnectedProviders() =>
      List.unmodifiable(_connections);

  /// Registers file-operation handlers on the MethodChannel so the Kotlin
  /// DocumentsProvider can delegate operations to the Flutter storage layer.
  ///
  /// [storageClient] should implement [CloudStorageClient].
  ///
  /// On non-Android platforms the handler is still registered for test
  /// purposes but will never be called.
  void registerHandlers(CloudStorageClient storageClient) {
    _storageDelegate = storageClient;

    _channel.setMethodCallHandler((call) async {
      try {
        return await _handleMethodCall(call);
      } catch (e, st) {
        _log.error('DocumentsProvider handler error for ${call.method}', e, st);
        rethrow;
      }
    });

    _log.info('DocumentsProvider MethodChannel handlers registered');
  }

  /// Removes the MethodChannel handler.  Call when the storage client is
  /// disconnected.
  void unregisterHandlers() {
    _storageDelegate = null;
    _channel.setMethodCallHandler(null);
    _log.info('DocumentsProvider MethodChannel handlers unregistered');
  }

  // ---------------------------------------------------------------------------
  // Internal MethodChannel dispatch
  // ---------------------------------------------------------------------------

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    final args = call.arguments as Map<Object?, Object?>? ?? {};
    final provider = args['provider'] as String?;
    final path = args['path'] as String?;

    switch (call.method) {
      case 'listDirectory':
        return _handleListDirectory(provider, path);

      case 'readFile':
        return _handleReadFile(provider, path);

      case 'writeFile':
        final data = args['data'];
        return _handleWriteFile(provider, path, data);

      case 'createDocument':
        final isDir = args['isDirectory'] as bool? ?? false;
        return _handleCreateDocument(provider, path, isDir);

      case 'deleteDocument':
        return _handleDeleteDocument(provider, path);

      case 'renameDocument':
        final newPath = args['newPath'] as String?;
        return _handleRenameDocument(provider, path, newPath);

      default:
        throw PlatformException(
          code: 'NOT_IMPLEMENTED',
          message: 'Method ${call.method} not implemented',
        );
    }
  }

  Future<List<Map<String, dynamic>>> _handleListDirectory(
      String? provider, String? path) async {
    _requireArgs(provider: provider, path: path);
    final client = _requireDelegate();
    // listPath returns {"files": [...], "folders": [...]} shaped maps.
    final result = await client.listPath(path!);
    final files = result['files'] as List<dynamic>? ?? [];
    final folders = result['folders'] as List<dynamic>? ?? [];

    final items = <Map<String, dynamic>>[];
    for (final f in folders) {
      final m = f as Map<String, dynamic>;
      items.add({
        'name': m['name'] as String? ?? '',
        'isDirectory': true,
        'size': 0,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });
    }
    for (final f in files) {
      final m = f as Map<String, dynamic>;
      items.add({
        'name': m['name'] as String? ?? '',
        'isDirectory': false,
        'size': (m['size'] as num?)?.toInt() ?? 0,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });
    }
    return items;
  }

  Future<Uint8List> _handleReadFile(String? provider, String? path) async {
    _requireArgs(provider: provider, path: path);
    final client = _requireDelegate();
    return await client.downloadFileBytes(path!);
  }

  Future<void> _handleWriteFile(
      String? provider, String? path, Object? data) async {
    _requireArgs(provider: provider, path: path);
    if (data == null) {
      throw PlatformException(code: 'INVALID_ARGS', message: 'data is null');
    }
    final bytes = data is Uint8List ? data : Uint8List.fromList(data as List<int>);
    final client = _requireDelegate();
    final fileName = path!.split('/').last;
    final dir = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : '/';
    await client.uploadFile(bytes, fileName, dir);
  }

  Future<void> _handleCreateDocument(
      String? provider, String? path, bool isDirectory) async {
    _requireArgs(provider: provider, path: path);
    final client = _requireDelegate();
    if (isDirectory) {
      await client.createFolderPath(path!);
    } else {
      // Create an empty file by uploading zero bytes.
      final fileName = path!.split('/').last;
      final dir = path.contains('/')
          ? path.substring(0, path.lastIndexOf('/'))
          : '/';
      await client.uploadFile(const [], fileName, dir);
    }
  }

  Future<void> _handleDeleteDocument(String? provider, String? path) async {
    _requireArgs(provider: provider, path: path);
    final client = _requireDelegate();
    await client.deletePath(path!);
  }

  Future<void> _handleRenameDocument(
      String? provider, String? oldPath, String? newPath) async {
    if (provider == null || oldPath == null || newPath == null) {
      throw PlatformException(
          code: 'INVALID_ARGS', message: 'provider, path, and newPath required');
    }
    final client = _requireDelegate();
    final newName = newPath.split('/').last;
    await client.renamePath(oldPath, newName);
  }

  // ---------------------------------------------------------------------------
  // Guard helpers
  // ---------------------------------------------------------------------------

  void _requireArgs({required String? provider, required String? path}) {
    if (provider == null || path == null) {
      throw PlatformException(
          code: 'INVALID_ARGS', message: 'provider and path are required');
    }
  }

  CloudStorageClient _requireDelegate() {
    final d = _storageDelegate;
    if (d == null) {
      throw PlatformException(
          code: 'NO_DELEGATE',
          message: 'No storage delegate registered. '
              'Call registerHandlers() first.');
    }
    return d;
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Set to `true` in unit tests to suppress the Android platform check.
// ignore: prefer_const_declarations
bool kIsTestEnvironment = false;
