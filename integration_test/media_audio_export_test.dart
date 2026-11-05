import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crisp_cloud/services/media_audio_backend.dart';
import 'package:crisp_cloud/services/media_edit_session.dart';
import 'package:crisp_cloud/services/media_editor_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('packaged audio plugin loads, exports PCM, cancels and retries',
      (tester) async {
    final temp = await getTemporaryDirectory();
    final directory = await Directory(temp.path)
        .createTemp('crisp-audio-integration-');
    try {
      final source = File('${directory.path}/source.wav');
      final input = _fixture();
      await source.writeAsBytes(input, flush: true);
      // No test library override: Apple must find symbols in the linked
      // process and Android must load its packaged libcrisp_audio.so.
      final backend = MediaAudioBackend();
      final info = await backend.probe(source.path);
      expect(info.kind, MediaKind.audio);
      expect(info.duration, const Duration(seconds: 1));
      expect(info.sampleRate, 8000);
      expect(info.channels, 2);
      final peaks = await backend.waveform(source.path, points: 16);
      expect(peaks, everyElement(closeTo(10000 / 32768, 0.000001)));

      final output = File('${directory.path}/edited.wav');
      const edit = MediaEdit(
        start: Duration(milliseconds: 100),
        end: Duration(milliseconds: 700),
        gainDb: -6,
        fadeIn: Duration(milliseconds: 100),
        fadeOut: Duration(milliseconds: 200),
      );
      final cancellation = MediaCancellation();
      await expectLater(
        backend.render(
          inputPath: source.path,
          outputPath: output.path,
          edit: edit,
          cancellation: cancellation,
          // Delivered after the native job is created, before the worker runs.
          // Active cancellation mid-render is covered by the native thread test.
          onProgress: (_) => cancellation.cancel(),
        ),
        throwsA(isA<MediaOperationCancelled>()),
      );
      expect(await output.exists(), isFalse);

      await backend.render(
        inputPath: source.path,
        outputPath: output.path,
        edit: edit,
        cancellation: MediaCancellation(),
      );
      final bytes = await output.readAsBytes();
      final wav = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(wav.getUint32(4, Endian.little), bytes.length - 8);
      expect(wav.getUint16(20, Endian.little), 1); // Uncompressed PCM.
      expect(wav.getUint16(22, Endian.little), 2);
      expect(wav.getUint32(24, Endian.little), 8000);
      expect(wav.getUint16(34, Endian.little), 16);
      expect(wav.getUint32(40, Endian.little), 4800 * 4);
      expect(bytes.length, 44 + 4800 * 4);
      for (final frame in [0, 400, 1000, 3300, 4000, 4799]) {
        var fade = 1.0;
        if (frame < 800) fade *= frame / 799;
        if (4800 - frame <= 1600) fade *= (4799 - frame) / 1599;
        final gain = math.pow(10, -6 / 20) * fade;
        expect(wav.getInt16(44 + frame * 4, Endian.little),
            closeTo((10000 * gain).round(), 1));
        expect(wav.getInt16(46 + frame * 4, Endian.little),
            closeTo((-5000 * gain).round(), 1));
      }
      final reopened = await backend.probe(output.path);
      expect(reopened.duration, const Duration(milliseconds: 600));
      expect(reopened.sampleRate, 8000);
      expect(reopened.channels, 2);
      expect(await source.readAsBytes(), input);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

Uint8List _fixture() {
  const frames = 8000;
  final result = Uint8List(44 + frames * 4);
  final data = ByteData.sublistView(result);
  result.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, result.length - 8, Endian.little);
  result.setRange(8, 16, 'WAVEfmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 2, Endian.little);
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 4, Endian.little);
  data.setUint16(34, 16, Endian.little);
  result.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, frames * 4, Endian.little);
  for (var frame = 0; frame < frames; frame++) {
    data.setInt16(44 + frame * 4, 10000, Endian.little);
    data.setInt16(46 + frame * 4, -5000, Endian.little);
  }
  return result;
}
