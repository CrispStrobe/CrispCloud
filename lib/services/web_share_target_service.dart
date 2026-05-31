// lib/services/web_share_target_service.dart
//
// Web Share Target API handler.
//
// When the user shares files or URLs to CrispCloud from another app (mobile
// browser / OS share sheet), the browser POST-es to /share-target as defined
// in manifest.json.  This service detects that scenario on startup and exposes
// the shared data so the UI can act on it (e.g. upload the shared files).
//
// Non-web platforms get a no-op stub.

import 'dart:typed_data';

import 'web_share_target_service_stub.dart'
    if (dart.library.html) 'web_share_target_service_web.dart' as _impl;

/// Data received via the Share Target API.
class SharedContent {
  final String? title;
  final String? text;
  final String? url;
  final List<SharedFile> files;

  const SharedContent({
    this.title,
    this.text,
    this.url,
    this.files = const [],
  });

  bool get hasFiles => files.isNotEmpty;
  bool get hasUrl => url != null && url!.isNotEmpty;
  bool get isEmpty => title == null && text == null && url == null && files.isEmpty;

  @override
  String toString() =>
      'SharedContent(title: $title, text: $text, url: $url, files: ${files.length})';
}

/// A file shared via the Share Target API.
class SharedFile {
  final String name;
  final String mimeType;
  final Uint8List bytes;

  const SharedFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });
}

/// Abstract interface for the Web Share Target handler.
abstract class WebShareTargetService {
  /// Whether this launch was triggered by a share action.
  bool get hasSharedContent;

  /// The shared content for this session (null if not a share launch).
  SharedContent? get sharedContent;

  /// Parse the share-target POST payload from the current page URL / body.
  /// Must be called once during app startup.
  Future<void> initialize();

  /// Clear the shared content after the UI has consumed it.
  void clear();

  factory WebShareTargetService() => _impl.createWebShareTargetService();
}
