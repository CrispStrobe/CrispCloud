// One packaged-app launch exercises both native media backends and their real
// plugin loading paths. These tests need no cloud account or media permissions.
import 'media_audio_export_test.dart' as audio;
import 'media_video_export_test.dart' as video;

void main() {
  audio.main();
  video.main();
}
