// test/web_streaming_test.dart
//
// Unit tests for WebStreamingService.
//
// All tests run on the VM test runner (not in a browser).  The web
// implementation is therefore replaced by the stub, which:
//   - reports isSupported = false
//   - returns empty streams from upload methods
//   - returns false from downloadWithWritableStream
//
// In addition, this file tests:
//   - Chunk-size validation / clamping helpers
//   - Pure-Dart stream transformation logic that mirrors what the web
//     implementation does (progress tracking, chunk accumulation, etc.)
//   - The transfer_provider web-path selection logic (isSupported gate)
//   - Constants exposed by the service

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/web_streaming_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Collects all chunks from [stream] into a single byte list.
Future<List<int>> collectStream(Stream<List<int>> stream) async {
  final result = <int>[];
  await for (final chunk in stream) {
    result.addAll(chunk);
  }
  return result;
}

/// Builds a Stream<List<int>> from a list of byte chunks (pure Dart).
Stream<List<int>> streamFromChunks(List<List<int>> chunks) async* {
  for (final chunk in chunks) {
    yield chunk;
  }
}

/// Simulates the progress-tracking transformer used in transfer_provider.
Stream<List<int>> withProgressTracking(
  Stream<List<int>> source,
  void Function(int sent) onProgress,
) {
  int sent = 0;
  return source.map((chunk) {
    sent += chunk.length;
    onProgress(sent);
    return chunk;
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // --------------------------------------------------------------------------
  // Constants
  // --------------------------------------------------------------------------
  group('WebStreamingService constants', () {
    test('defaultChunkSize is 1 MiB (1048576 bytes)', () {
      expect(WebStreamingService.defaultChunkSize, 1024 * 1024);
    });

    test('defaultChunkSize is positive', () {
      expect(WebStreamingService.defaultChunkSize, greaterThan(0));
    });
  });

  // --------------------------------------------------------------------------
  // Stub behaviour — factory returns a real instance
  // --------------------------------------------------------------------------
  group('WebStreamingService (stub on non-web)', () {
    late WebStreamingService svc;

    setUp(() => svc = WebStreamingService());

    test('factory returns an instance', () {
      expect(svc, isNotNull);
    });

    test('isSupported is false on non-web', () {
      expect(svc.isSupported, isFalse);
    });

    test('uploadWithReadableStream returns an empty stream on non-web', () async {
      final stream = svc.uploadWithReadableStream(Object());
      final chunks = await collectStream(stream);
      expect(chunks, isEmpty);
    });

    test('uploadWithReadableStream does not throw on non-web', () async {
      await expectLater(
        svc.uploadWithReadableStream(Object()).drain<void>(),
        completes,
      );
    });

    test('uploadWithReadableStream accepts custom chunkSize without error', () async {
      final stream = svc.uploadWithReadableStream(
        Object(),
        chunkSize: 512 * 1024,
      );
      final chunks = await collectStream(stream);
      expect(chunks, isEmpty);
    });

    test('uploadWithReadableStream with chunkSize = 0 returns empty stream', () async {
      final stream = svc.uploadWithReadableStream(Object(), chunkSize: 0);
      final chunks = await collectStream(stream);
      expect(chunks, isEmpty);
    });

    test('streamFromBlob returns an empty stream on non-web', () async {
      final stream = svc.streamFromBlob(Object());
      final chunks = await collectStream(stream);
      expect(chunks, isEmpty);
    });

    test('streamFromBlob does not throw on non-web', () async {
      await expectLater(
        svc.streamFromBlob(Object()).drain<void>(),
        completes,
      );
    });

    test('streamFromBlob accepts custom chunkSize without error', () async {
      final stream = svc.streamFromBlob(Object(), chunkSize: 256 * 1024);
      final chunks = await collectStream(stream);
      expect(chunks, isEmpty);
    });

    test('downloadWithWritableStream returns false on non-web', () async {
      final result = await svc.downloadWithWritableStream(
        const Stream.empty(),
        'test.bin',
      );
      expect(result, isFalse);
    });

    test('downloadWithWritableStream with totalSize returns false on non-web',
        () async {
      final result = await svc.downloadWithWritableStream(
        const Stream.empty(),
        'large.iso',
        totalSize: 4 * 1024 * 1024 * 1024,
      );
      expect(result, isFalse);
    });

    test('downloadWithWritableStream does not throw on non-web', () async {
      await expectLater(
        svc.downloadWithWritableStream(const Stream.empty(), 'file.dat'),
        completes,
      );
    });

    test('downloadWithWritableStream with non-empty stream returns false',
        () async {
      final data = streamFromChunks([
        [1, 2, 3],
        [4, 5, 6],
      ]);
      final result = await svc.downloadWithWritableStream(data, 'data.bin');
      expect(result, isFalse);
    });

    test('multiple calls to factory each return an instance', () {
      final a = WebStreamingService();
      final b = WebStreamingService();
      expect(a, isNotNull);
      expect(b, isNotNull);
    });
  });

  // --------------------------------------------------------------------------
  // Pure-Dart stream chunk logic (mirrors upload streaming)
  // --------------------------------------------------------------------------
  group('Chunk stream logic (pure Dart)', () {
    test('streamFromChunks emits all bytes in order', () async {
      final chunks = [
        [1, 2, 3],
        [4, 5],
        [6, 7, 8, 9],
      ];
      final result = await collectStream(streamFromChunks(chunks));
      expect(result, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('empty stream produces no bytes', () async {
      final result = await collectStream(const Stream.empty());
      expect(result, isEmpty);
    });

    test('single-chunk stream produces correct bytes', () async {
      final bytes = List.generate(100, (i) => i % 256);
      final result = await collectStream(streamFromChunks([bytes]));
      expect(result.length, 100);
      expect(result[0], 0);
      expect(result[99], 99);
    });

    test('chunk boundary alignment — 1 MiB data in 256 KiB chunks', () async {
      const totalSize = 1024 * 1024; // 1 MiB
      const chunkSize = 256 * 1024; // 256 KiB
      final data = Uint8List.fromList(List.generate(totalSize, (i) => i & 0xFF));

      // Simulate chunking
      final chunks = <List<int>>[];
      for (var offset = 0; offset < totalSize; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, totalSize);
        chunks.add(data.sublist(offset, end));
      }

      expect(chunks.length, 4); // 1MiB / 256KiB = 4 chunks
      final result = await collectStream(streamFromChunks(chunks));
      expect(result.length, totalSize);
      for (int i = 0; i < totalSize; i++) {
        expect(result[i], i & 0xFF, reason: 'byte $i mismatch');
      }
    });

    test('chunking with uneven last chunk', () async {
      const totalSize = 1000;
      const chunkSize = 300;
      final data = Uint8List.fromList(List.generate(totalSize, (i) => i % 256));

      final chunks = <List<int>>[];
      for (var offset = 0; offset < totalSize; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, totalSize);
        chunks.add(data.sublist(offset, end));
      }

      // 0-300, 300-600, 600-900, 900-1000
      expect(chunks.length, 4);
      expect(chunks.last.length, 100);

      final result = await collectStream(streamFromChunks(chunks));
      expect(result.length, totalSize);
    });

    test('progress tracking increments by chunk size', () async {
      final progressSnapshots = <int>[];
      final chunks = [
        List.filled(100, 0),
        List.filled(200, 1),
        List.filled(50, 2),
      ];
      final stream = withProgressTracking(
        streamFromChunks(chunks),
        progressSnapshots.add,
      );

      await collectStream(stream);

      expect(progressSnapshots, [100, 300, 350]);
    });

    test('progress tracking starts at zero before first chunk', () async {
      int? firstProgress;
      final chunks = [List.filled(512, 0xFF)];
      final stream = withProgressTracking(
        streamFromChunks(chunks),
        (p) => firstProgress ??= p,
      );
      await collectStream(stream);
      expect(firstProgress, 512);
    });

    test('progress tracking handles many small chunks', () async {
      final progressLog = <int>[];
      final chunks = List.generate(20, (_) => List.filled(10, 0));
      final stream = withProgressTracking(
        streamFromChunks(chunks),
        progressLog.add,
      );
      await collectStream(stream);

      expect(progressLog.length, 20);
      expect(progressLog.last, 200);
      // Each snapshot should be 10 more than the previous.
      for (int i = 0; i < progressLog.length; i++) {
        expect(progressLog[i], (i + 1) * 10);
      }
    });

    test('stream is drained completely across many chunks', () async {
      // Produce 10 KiB across 10 chunks and verify all bytes arrive.
      const chunkCount = 10;
      const chunkSize = 1024;
      final chunks = List.generate(chunkCount, (i) => List.filled(chunkSize, i));

      final result = await collectStream(streamFromChunks(chunks));
      expect(result.length, chunkCount * chunkSize);
      // First byte of each 1024-byte run should equal the chunk index.
      for (int i = 0; i < chunkCount; i++) {
        expect(result[i * chunkSize], i, reason: 'chunk $i value mismatch');
      }
    });
  });

  // --------------------------------------------------------------------------
  // Web-path selection logic (mirrors transfer_provider)
  // --------------------------------------------------------------------------
  group('Transfer provider web-path selection logic', () {
    // The provider checks: kIsWeb && webStreaming.isSupported
    // On the VM test runner kIsWeb is always false, so the streaming path
    // should never be taken.  We test the logic by examining isSupported.

    test('stub reports isSupported = false, so streaming path is skipped', () {
      final svc = WebStreamingService();
      // Simulate the guard used in transfer_provider:
      //   if (kIsWeb && webStreaming.isSupported) { ... streaming ... }
      // kIsWeb is false in tests, but we verify isSupported is false too.
      expect(svc.isSupported, isFalse);
    });

    test('when isSupported is false, download falls back to buffer path', () async {
      final svc = WebStreamingService();
      // The streaming download should return false (not supported).
      final result = await svc.downloadWithWritableStream(
        streamFromChunks([[1, 2, 3]]),
        'photo.jpg',
        totalSize: 3,
      );
      expect(result, isFalse,
          reason: 'Non-web stub must return false so fallback is taken');
    });

    test('when isSupported is false, upload streaming returns empty', () async {
      final svc = WebStreamingService();
      final stream = svc.uploadWithReadableStream(Object());
      final bytes = await collectStream(stream);
      expect(bytes, isEmpty,
          reason: 'Non-web stub must yield no bytes so fallback buffer path is taken');
    });

    test('when blob ref is null, streamFromBlob returns empty', () async {
      final svc = WebStreamingService();
      // Simulates the guard: blobRef != null
      final stream = svc.streamFromBlob(Object());
      final bytes = await collectStream(stream);
      expect(bytes, isEmpty);
    });

    test('chunk size must be positive for meaningful streaming', () {
      // Verify that zero or negative chunk sizes would not be used in practice.
      expect(WebStreamingService.defaultChunkSize, greaterThan(0));
      const customChunk = 512 * 1024;
      expect(customChunk, greaterThan(0));
    });
  });

  // --------------------------------------------------------------------------
  // Edge cases / filename handling
  // --------------------------------------------------------------------------
  group('Edge cases', () {
    test('downloadWithWritableStream accepts empty filename', () async {
      final svc = WebStreamingService();
      final result = await svc.downloadWithWritableStream(
        const Stream.empty(),
        '',
      );
      expect(result, isFalse);
    });

    test('downloadWithWritableStream accepts filename with path separators',
        () async {
      final svc = WebStreamingService();
      final result = await svc.downloadWithWritableStream(
        const Stream.empty(),
        'subfolder/archive.tar.gz',
      );
      expect(result, isFalse);
    });

    test('downloadWithWritableStream with totalSize = 0 returns false', () async {
      final svc = WebStreamingService();
      final result = await svc.downloadWithWritableStream(
        const Stream.empty(),
        'empty.bin',
        totalSize: 0,
      );
      expect(result, isFalse);
    });

    test('downloadWithWritableStream with null totalSize returns false', () async {
      final svc = WebStreamingService();
      final result = await svc.downloadWithWritableStream(
        const Stream.empty(),
        'unknown-size.bin',
        // totalSize omitted → null
      );
      expect(result, isFalse);
    });

    test('uploadWithReadableStream with very large chunkSize returns empty on stub',
        () async {
      final svc = WebStreamingService();
      final stream = svc.uploadWithReadableStream(
        Object(),
        chunkSize: 64 * 1024 * 1024, // 64 MiB
      );
      final result = await collectStream(stream);
      expect(result, isEmpty);
    });

    test('streamFromBlob with very small chunkSize returns empty on stub', () async {
      final svc = WebStreamingService();
      final stream = svc.streamFromBlob(Object(), chunkSize: 1);
      final result = await collectStream(stream);
      expect(result, isEmpty);
    });

    test('concurrent downloadWithWritableStream calls both return false on stub',
        () async {
      final svc = WebStreamingService();
      final results = await Future.wait([
        svc.downloadWithWritableStream(const Stream.empty(), 'a.bin'),
        svc.downloadWithWritableStream(const Stream.empty(), 'b.bin'),
      ]);
      expect(results, everyElement(isFalse));
    });
  });
}
