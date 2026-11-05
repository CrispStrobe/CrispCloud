import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crisp_audio/crisp_audio.dart';
import 'package:crisp_cloud/services/media_audio_backend.dart';
import 'package:crisp_cloud/services/media_edit_session.dart';
import 'package:crisp_cloud/services/media_editor_backend.dart';
import 'package:flutter_test/flutter_test.dart';

/// The native workflow compiles the same shipped C++ implementation and passes
/// its path here. Ordinary unit suites keep the plugin-independent host tests;
/// this suite exercises the actual FFI, isolates, decoder, DSP and file output.
void main() {
  final library = Platform.environment['CRISP_AUDIO_LIBRARY'];
  group('native audio backend', () {
    late Directory directory;
    late File source;
    late MediaAudioBackend backend;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('crisp-audio-ffi-');
      source = File('${directory.path}/source.wav');
      await source.writeAsBytes(_fixture());
      backend = MediaAudioBackend(engine: CrispAudio(libraryPath: library));
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('probe and waveform cross the real isolate/FFI boundary', () async {
      final info = await backend.probe(source.path);
      expect(info.kind, MediaKind.audio);
      expect(info.duration, const Duration(seconds: 1));
      expect(info.sampleRate, 8000);
      expect(info.channels, 2);
      final peaks = await backend.waveform(source.path, points: 53);
      expect(peaks, hasLength(53));
      expect(peaks, everyElement(closeTo(10000 / 32768, 0.000001)));
    });

    test('trim, gain, fades export a complete independently parsed WAV', () async {
      final output = File('${directory.path}/trimmed.wav');
      final progress = <double>[];
      await backend.render(
        inputPath: source.path,
        outputPath: output.path,
        edit: const MediaEdit(
          start: Duration(milliseconds: 200),
          end: Duration(milliseconds: 800),
          gainDb: -6,
          fadeIn: Duration(milliseconds: 100),
          fadeOut: Duration(milliseconds: 200),
        ),
        cancellation: MediaCancellation(),
        onProgress: progress.add,
      );
      final bytes = await output.readAsBytes();
      final wav = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(wav.getUint32(4, Endian.little), bytes.length - 8);
      expect(wav.getUint16(20, Endian.little), 1);
      expect(wav.getUint16(22, Endian.little), 2);
      expect(wav.getUint32(24, Endian.little), 8000);
      expect(wav.getUint16(34, Endian.little), 16);
      expect(wav.getUint32(40, Endian.little), 4800 * 2 * 2);
      expect(bytes.length, 44 + 4800 * 2 * 2);
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
      expect(reopened.channels, 2);
      expect(await source.readAsBytes(), _fixture());
      expect(progress.first, 0);
      expect(progress.last, 1);
      expect(progress, everyElement(inInclusiveRange(0, 1)));
    });

    test('mute writes silence instead of merely changing playback state', () async {
      final output = File('${directory.path}/muted.wav');
      await backend.render(
        inputPath: source.path,
        outputPath: output.path,
        edit: const MediaEdit(
          start: Duration.zero,
          end: Duration(milliseconds: 100),
          muted: true,
        ),
        cancellation: MediaCancellation(),
      );
      final bytes = await output.readAsBytes();
      expect(bytes.length, 44 + 800 * 4);
      expect(bytes.sublist(44), everyElement(0));
    });

    test('cancellation crosses native job boundaries and permits retry', () async {
      final output = File('${directory.path}/cancelled.wav');
      final cancellation = MediaCancellation();
      const edit = MediaEdit(start: Duration.zero, end: Duration(seconds: 1));
      await expectLater(
        backend.render(
          inputPath: source.path,
          outputPath: output.path,
          edit: edit,
          cancellation: cancellation,
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
      expect((await backend.probe(output.path)).duration,
          const Duration(seconds: 1));
    });

    test('an existing destination survives a failed export', () async {
      final output = File('${directory.path}/existing.wav');
      await output.writeAsString('existing content');
      await expectLater(
        backend.render(
          inputPath: source.path,
          outputPath: output.path,
          edit: const MediaEdit(start: Duration.zero, end: Duration(seconds: 1)),
          cancellation: MediaCancellation(),
        ),
        throwsA(isA<AudioException>().having(
          (error) => error.reason, 'reason', AudioFailure.outputExists,
        )),
      );
      expect(await output.readAsString(), 'existing content');
    });

    test('video-only edits fail explicitly before writing audio', () async {
      final output = File('${directory.path}/unsupported.wav');
      await expectLater(
        backend.render(
          inputPath: source.path,
          outputPath: output.path,
          edit: const MediaEdit(
            start: Duration.zero,
            end: Duration(seconds: 1),
            quarterTurns: 1,
          ),
          cancellation: MediaCancellation(),
        ),
        throwsA(isA<MediaEditException>().having(
          (error) => error.reason, 'reason', MediaEditFailure.unsupportedEdit,
        )),
      );
      expect(await output.exists(), isFalse);
    });
  }, skip: library == null
      ? 'Set CRISP_AUDIO_LIBRARY to the compiled native test library.'
      : false);
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
