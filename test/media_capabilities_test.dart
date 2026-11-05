import 'package:crisp_cloud/services/media_capabilities.dart';
import 'package:crisp_cloud/services/media_edit_session.dart';
import 'package:crisp_cloud/utils/file_editability.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capability matrix exposes only implemented native backends', () {
    for (final platform in TargetPlatform.values) {
      expect(
        MediaCapabilities.canEdit(
          MediaKind.audio,
          platform: platform,
          isWeb: false,
        ),
        platform != TargetPlatform.fuchsia,
      );
      expect(
        MediaCapabilities.canEdit(
          MediaKind.video,
          platform: platform,
          isWeb: false,
        ),
        {
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        }.contains(platform),
      );
      for (final kind in MediaKind.values) {
        expect(
          MediaCapabilities.canEdit(kind, platform: platform, isWeb: true),
          isFalse,
        );
      }
    }
  });

  test('routing recognizes only the supported filename suffixes', () {
    for (final name in ['voice.WAV', 'music.mp3', 'master.flac']) {
      expect(mediaKindForFileName(name), MediaKind.audio);
    }
    for (final name in ['clip.MOV', 'clip.mp4', 'clip.m4v']) {
      expect(mediaKindForFileName(name), MediaKind.video);
    }
    for (final name in [
      'clip.avi',
      'voice.aac',
      'voice.m4a',
      'clip.mp4.exe',
      'voice.wav.',
      'mp4',
    ]) {
      expect(mediaKindForFileName(name), isNull);
    }
  });

  test('F4 capability follows the target platform without affecting text', () {
    final previous = debugDefaultTargetPlatformOverride;
    addTearDown(() => debugDefaultTargetPlatformOverride = previous);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(isEditableInBuiltInEditor('clip.mp4'), isFalse);
    expect(isEditableInBuiltInEditor('voice.wav'), !kIsWeb);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(isEditableInBuiltInEditor('clip.mp4'), !kIsWeb);
    expect(isEditableInBuiltInEditor('README'), isTrue);
  });
}
