import 'dart:io';

import 'package:crisp_cloud/widgets/preview_media.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  testWidgets('a failed player creation does not hang viewer cleanup', (
    tester,
  ) async {
    final previous = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _FailingPlayer();
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    final controller = VideoPlayerController.file(File('sample.mp4'));
    await expectLater(
      initializePreviewVideo(controller),
      throwsA(isA<PlatformException>()),
    );
    final cleanup = disposeFailedPreviewVideo(controller);
    await tester.pump(const Duration(seconds: 1));
    await cleanup;
  });
}

class _FailingPlayer extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    throw PlatformException(code: 'initialization-failed');
  }
}
