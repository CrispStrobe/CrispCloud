// lib/services/share_extension_service.dart
//
// Flutter-side processor for items shared from other iOS apps via the
// CrispCloud Share Extension.
//
// When a user taps "Share → CrispCloud" in Photos, Safari, Files, etc. the
// Share Extension writes a JSON manifest to the App Group shared container
// under the key "cc_pending_uploads".  On the next launch (or foreground)
// this service reads that manifest, uploads each file to the user's active
// cloud provider, then removes the consumed entries.
//
// Architecture
// ─────────────
//  iOS only — all public methods are no-ops on other platforms.
//  Uses a MethodChannel ("com.crispcloud/share_extension") backed by a small
//  native helper in AppDelegate to read/write the App Group UserDefaults
//  from the main app process (direct UserDefaults access in Flutter is not
//  available without a platform channel).
//
// Typical call-site (e.g. inside AppState.init or a Riverpod provider):
//   await ShareExtensionService.instance.processPendingUploads(
//     upload: (path, name, mime) => myCloudClient.uploadFile(path, name),
//   );

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'log_service.dart';

const _log = Log('ShareExtensionService');

/// A single file item queued by the Share Extension.
class ShareExtensionItem {
  /// Absolute path inside the App Group shared container inbox.
  final String localPath;

  /// Original filename as reported by the source app.
  final String originalName;

  /// MIME type determined by the extension (e.g. "image/jpeg").
  final String mimeType;

  /// ISO-8601 timestamp when the item was added by the extension.
  final DateTime addedAt;

  const ShareExtensionItem({
    required this.localPath,
    required this.originalName,
    required this.mimeType,
    required this.addedAt,
  });

  factory ShareExtensionItem.fromJson(Map<String, dynamic> json) {
    return ShareExtensionItem(
      localPath:    (json['localPath']    as String?) ?? '',
      originalName: (json['originalName'] as String?) ?? 'unknown',
      mimeType:     (json['mimeType']     as String?) ?? 'application/octet-stream',
      addedAt:      DateTime.tryParse((json['addedAt'] as String?) ?? '') ?? DateTime.now(),
    );
  }

  @override
  String toString() =>
      'ShareExtensionItem(name: $originalName, mime: $mimeType, addedAt: $addedAt)';
}

/// Callback signature used by [ShareExtensionService.processPendingUploads].
///
/// [localPath]    — absolute path to the file in the App Group inbox.
/// [originalName] — filename to use when storing in the cloud.
/// [mimeType]     — MIME type of the file.
///
/// Return `true` if the upload succeeded (the item will be removed from the
/// pending queue); return `false` or throw to leave it for the next attempt.
typedef ShareUploadCallback = Future<bool> Function(
  String localPath,
  String originalName,
  String mimeType,
);

/// Service that bridges the iOS Share Extension and the main Flutter app.
///
/// Instantiate once and keep alive for the app's lifetime (or use the
/// provided singleton [instance]).
class ShareExtensionService {
  ShareExtensionService._();

  static final ShareExtensionService instance = ShareExtensionService._();

  static const _channel = MethodChannel('com.crispcloud/share_extension');

  /// Whether this service is available on the current platform.
  ///
  /// Always `false` on Android, macOS, Windows, Linux, and Web.
  bool get isAvailable => !kIsWeb && Platform.isIOS;

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Read all items queued by the Share Extension, call [upload] for each
  /// one, and remove successfully processed items from the shared container.
  ///
  /// Safe to call on non-iOS platforms — it is a no-op.
  ///
  /// [upload] receives the local path, original filename, and MIME type.
  /// Return `true` from [upload] to mark the item as done; return `false` or
  /// throw to leave it for the next attempt.
  Future<void> processPendingUploads({required ShareUploadCallback upload}) async {
    if (!isAvailable) return;

    final items = await _readPendingItems();
    if (items.isEmpty) {
      _log.debug('No pending Share Extension uploads');
      return;
    }

    _log.info('Processing ${items.length} pending Share Extension upload(s)');
    final remaining = <ShareExtensionItem>[];

    for (final item in items) {
      _log.info('Uploading shared item', {
        'name': item.originalName,
        'mime': item.mimeType,
        'path': item.localPath,
      });

      try {
        final ok = await upload(item.localPath, item.originalName, item.mimeType);
        if (ok) {
          _log.info('Shared item uploaded successfully', {'name': item.originalName});
          await _deleteInboxFile(item.localPath);
        } else {
          _log.warn('Upload returned false for ${item.originalName}; will retry later');
          remaining.add(item);
        }
      } catch (e, st) {
        _log.error('Failed to upload shared item ${item.originalName}', e, st);
        remaining.add(item);
      }
    }

    await _writePendingItems(remaining);
    _log.info('Share Extension processing complete',
        {'uploaded': items.length - remaining.length, 'remaining': remaining.length});
  }

  /// Return the list of items currently queued by the Share Extension without
  /// modifying the queue.  Useful for displaying a badge or preview.
  Future<List<ShareExtensionItem>> peekPendingItems() async {
    if (!isAvailable) return const [];
    return _readPendingItems();
  }

  /// Remove all pending items without uploading them.
  Future<void> clearPendingItems() async {
    if (!isAvailable) return;

    final items = await _readPendingItems();
    for (final item in items) {
      await _deleteInboxFile(item.localPath);
    }
    await _writePendingItems(const []);
    _log.info('Cleared ${items.length} pending Share Extension item(s)');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private helpers — platform channel calls
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<ShareExtensionItem>> _readPendingItems() async {
    try {
      final jsonString = await _channel.invokeMethod<String>('readPendingUploads');
      if (jsonString == null || jsonString.isEmpty) return const [];

      final decoded = json.decode(jsonString) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ShareExtensionItem.fromJson)
          .where((item) => item.localPath.isNotEmpty)
          .toList();
    } on PlatformException catch (e) {
      _log.warn('Failed to read pending uploads from shared container: ${e.message}');
      return const [];
    } on MissingPluginException {
      _log.debug('ShareExtension channel not available (expected on simulator/non-iOS)');
      return const [];
    } catch (e) {
      _log.warn('Unexpected error reading pending uploads', e);
      return const [];
    }
  }

  Future<void> _writePendingItems(List<ShareExtensionItem> items) async {
    try {
      final payload = items
          .map((i) => {
                'localPath':    i.localPath,
                'originalName': i.originalName,
                'mimeType':     i.mimeType,
                'addedAt':      i.addedAt.toIso8601String(),
              })
          .toList();
      await _channel.invokeMethod('writePendingUploads', {
        'json': json.encode(payload),
      });
    } on PlatformException catch (e) {
      _log.warn('Failed to write pending uploads: ${e.message}');
    } on MissingPluginException {
      // Expected on simulator.
    }
  }

  Future<void> _deleteInboxFile(String path) async {
    try {
      await _channel.invokeMethod('deleteShareInboxFile', {'path': path});
    } on PlatformException catch (e) {
      _log.warn('Failed to delete inbox file "$path": ${e.message}');
    } on MissingPluginException {
      // Silently ignore.
    }
  }
}
