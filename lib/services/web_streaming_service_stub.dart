// lib/services/web_streaming_service_stub.dart
//
// No-op stub for non-web platforms.

import 'web_streaming_service.dart';

WebStreamingService createWebStreamingService() => _StubWebStreamingService();

class _StubWebStreamingService implements WebStreamingService {
  @override
  bool get isSupported => false;

  @override
  Stream<List<int>> uploadWithReadableStream(
    Object fileHandle, {
    int chunkSize = WebStreamingService.defaultChunkSize,
  }) =>
      const Stream.empty();

  @override
  Stream<List<int>> streamFromBlob(
    Object blob, {
    int chunkSize = WebStreamingService.defaultChunkSize,
  }) =>
      const Stream.empty();

  @override
  Future<bool> downloadWithWritableStream(
    Stream<List<int>> data,
    String filename, {
    int? totalSize,
  }) async =>
      false;
}
