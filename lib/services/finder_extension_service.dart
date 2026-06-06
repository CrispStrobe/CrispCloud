// lib/services/finder_extension_service.dart
//
// Flutter-side handler for URLs opened by the macOS Finder Sync extension.
//
// The Finder extension encodes selected file paths into:
//   crispcloud://upload?paths=<percent-encoded,comma-joined absolute paths>
//
// and calls NSWorkspace.open(_:) to activate this app.  The native
// AppDelegate receives the URL via application(_:open:) and forwards it
// here over a Flutter MethodChannel.
//
// Usage:
//   final svc = FinderExtensionService(storageClient: myClient);
//   await svc.initialize();
//   svc.dispose();

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'cloud_storage_interface.dart';
import 'log_service.dart';

/// Result of handling a single upload URL from the Finder extension.
class FinderUploadResult {
  /// Total number of paths received in the URL.
  final int totalPaths;

  /// Number of paths successfully uploaded.
  final int uploaded;

  /// Paths that failed to upload, mapped to their error messages.
  final Map<String, String> failures;

  const FinderUploadResult({
    required this.totalPaths,
    required this.uploaded,
    required this.failures,
  });

  bool get isSuccess => failures.isEmpty;

  @override
  String toString() =>
      'FinderUploadResult(total:$totalPaths uploaded:$uploaded failures:${failures.length})';
}

/// Listens for incoming crispcloud:// URLs on macOS and triggers uploads.
///
/// Platform guard: [initialize] is a no-op on non-macOS platforms, so it is
/// safe to instantiate and call unconditionally in the app bootstrap.
class FinderExtensionService {
  static const _log = Log('FinderExtensionService');

  /// The channel name matches the one declared in AppDelegate.swift.
  static const _channel = MethodChannel('com.crispcloud/finder_extension');

  /// The cloud storage client to use for uploads.
  final CloudStorageClient? storageClient;

  /// Callback invoked when the service has finished handling an upload URL.
  /// Useful for showing progress UI or notifications in the app layer.
  final void Function(FinderUploadResult)? onUploadComplete;

  /// Callback invoked when the service starts processing a URL.
  /// Receives the list of local paths about to be uploaded.
  final void Function(List<String>)? onUploadStarted;

  bool _initialized = false;

  FinderExtensionService({
    this.storageClient,
    this.onUploadComplete,
    this.onUploadStarted,
  });

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns true when the service is active on this platform.
  static bool get isSupported => !kIsWebPlatform && Platform.isMacOS;

  /// Registers the MethodChannel handler.  Safe to call multiple times; only
  /// the first call does real work.
  ///
  /// On non-macOS platforms this is a no-op.
  void initialize() {
    if (_initialized) return;
    if (!isSupported) {
      _log.debug('FinderExtensionService not supported on this platform — skipped.');
      return;
    }

    _channel.setMethodCallHandler(_handleMethodCall);
    _initialized = true;
    _log.info('FinderExtensionService initialized — listening on $_channel');
  }

  /// Removes the MethodChannel handler.
  void dispose() {
    if (!_initialized) return;
    _channel.setMethodCallHandler(null);
    _initialized = false;
    _log.debug('FinderExtensionService disposed.');
  }

  // ---------------------------------------------------------------------------
  // URL parsing (public for testability)
  // ---------------------------------------------------------------------------

  /// Parses a `crispcloud://upload?paths=...` URL string and returns the list
  /// of decoded absolute file paths, or an empty list on failure.
  ///
  /// The `paths` query parameter contains percent-encoded absolute paths
  /// joined by commas.  Each path is individually percent-decoded.
  static List<String> parseUploadUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      _log.warn('FinderExtensionService: invalid URL — $rawUrl');
      return [];
    }

    if (uri.scheme.toLowerCase() != 'crispcloud' ||
        uri.host.toLowerCase() != 'upload') {
      _log.warn('FinderExtensionService: unexpected URL format — $rawUrl');
      return [];
    }

    // Use the raw query string to extract `paths=` before any auto-decoding,
    // so that we can correctly split on literal commas (which are the
    // delimiters) while safely decoding commas that appear within individual
    // path components (encoded as %2C by the Swift extension).
    final rawQuery = uri.query;
    if (rawQuery.isEmpty) return [];

    // Extract the raw value of the `paths` parameter.
    const prefix = 'paths=';
    final paramIndex = rawQuery.indexOf(prefix);
    if (paramIndex < 0) return [];

    final rawPaths = rawQuery.substring(paramIndex + prefix.length);
    if (rawPaths.isEmpty) return [];

    // Split on literal ',' (the delimiter), then percent-decode each
    // individual path component.
    final decoded = rawPaths
        .split(',')
        .map((p) {
          try {
            return Uri.decodeComponent(p);
          } catch (_) {
            return p; // return as-is if decoding fails
          }
        })
        .where((p) => p.isNotEmpty)
        .toList();

    return decoded;
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  /// Handles MethodChannel calls from AppDelegate.swift.
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onUrl':
        final rawUrl = call.arguments as String? ?? '';
        _log.info('Received Finder extension URL', {'url': rawUrl});
        await _processUrl(rawUrl);
        return null;

      default:
        _log.warn('FinderExtensionService: unknown method — ${call.method}');
        return null;
    }
  }

  Future<void> _processUrl(String rawUrl) async {
    final paths = parseUploadUrl(rawUrl);

    if (paths.isEmpty) {
      _log.warn('FinderExtensionService: no valid paths in URL — $rawUrl');
      return;
    }

    _log.info('FinderExtensionService: uploading ${paths.length} file(s)', {
      'paths': paths,
    });

    onUploadStarted?.call(paths);

    final client = storageClient;
    if (client == null) {
      _log.warn('FinderExtensionService: no storage client configured — '
          'cannot upload ${paths.length} file(s).');
      onUploadComplete?.call(FinderUploadResult(
        totalPaths: paths.length,
        uploaded: 0,
        failures: {
          for (final p in paths) p: 'No storage client configured',
        },
      ));
      return;
    }

    if (!client.isAuthenticated) {
      _log.warn('FinderExtensionService: storage client is not authenticated.');
      onUploadComplete?.call(FinderUploadResult(
        totalPaths: paths.length,
        uploaded: 0,
        failures: {
          for (final p in paths) p: 'Not authenticated',
        },
      ));
      return;
    }

    int uploaded = 0;
    final failures = <String, String>{};

    for (final localPath in paths) {
      try {
        final file = File(localPath);
        if (!file.existsSync()) {
          throw FileSystemException('File not found', localPath);
        }

        final bytes = await file.readAsBytes();
        final fileName = localPath.split('/').last;
        final remotePath = '${client.rootPath}/$fileName';

        _log.debug('FinderExtensionService: uploading "$fileName" '
            '(${bytes.length} bytes) → $remotePath');

        await client.uploadFile(bytes, fileName, remotePath);
        uploaded++;

        _log.info('FinderExtensionService: uploaded "$fileName"');
      } catch (e, st) {
        _log.error(
          'FinderExtensionService: upload failed for $localPath',
          e,
          st,
        );
        failures[localPath] = e.toString();
      }
    }

    final result = FinderUploadResult(
      totalPaths: paths.length,
      uploaded: uploaded,
      failures: failures,
    );

    _log.info('FinderExtensionService: upload batch complete', {
      'result': result.toString(),
    });

    onUploadComplete?.call(result);
  }
}

// ---------------------------------------------------------------------------
// Web detection shim
// ---------------------------------------------------------------------------

/// Whether we are running as a web app.
///
/// On web, dart:io is not available and Platform calls throw, so we use
/// package:flutter/foundation.dart's [kIsWeb] constant instead, which is
/// a compile-time constant that tree-shakes away the dart:io import on web.
bool get kIsWebPlatform => kIsWeb;
