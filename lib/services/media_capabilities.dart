import 'package:flutter/foundation.dart';

import 'media_edit_session.dart';

/// Filename routing is only a capability hint. Engines validate actual media.
MediaKind? mediaKindForFileName(String name) {
  final extension = name.split('.').last.toLowerCase();
  if (!name.contains('.')) return null;
  if (const {'wav', 'mp3', 'flac'}.contains(extension)) return MediaKind.audio;
  if (const {'mp4', 'mov', 'm4v'}.contains(extension)) return MediaKind.video;
  return null;
}

abstract final class MediaCapabilities {
  static bool canEdit(
    MediaKind kind, {
    TargetPlatform? platform,
    bool? isWeb,
  }) {
    if (isWeb ?? kIsWeb) return false;
    final target = platform ?? defaultTargetPlatform;
    if (kind == MediaKind.audio) return target != TargetPlatform.fuchsia;
    return target == TargetPlatform.android ||
        target == TargetPlatform.iOS ||
        target == TargetPlatform.macOS;
  }

  /// The existing video_player platform implementations also audition audio.
  /// Linux/Windows get waveform editing and real WAV export in this milestone.
  static bool get hasInlinePreview =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
}
