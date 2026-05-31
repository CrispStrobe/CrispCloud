// lib/services/web_streaming_service.dart
//
// Web streaming file transfer service.
//
// On web, large file uploads read the source via the File System Access API
// FileReader slice API so that the browser never buffers the whole file.
// Large downloads use showSaveFilePicker() + a WritableStream so the browser
// pipes chunks directly to disk without creating an in-memory Blob.
//
// On non-web platforms the stub implementation is compiled in, providing the
// same interface as no-ops / false returns.

import 'web_streaming_service_stub.dart'
    if (dart.library.html) 'web_streaming_service_web.dart' as _impl;

/// Default chunk size used for chunked FileReader slice reads (1 MiB).
const int _kDefaultChunkSize = 1024 * 1024;

/// Service for streaming file transfers on the web platform.
abstract class WebStreamingService {
  /// Default slice size for chunked reads (1 MiB).
  static const int defaultChunkSize = _kDefaultChunkSize;

  /// Whether the browser supports writable streams via showSaveFilePicker.
  bool get isSupported;

  /// Returns a [Stream<List<int>>] that reads [fileHandle] (a
  /// FileSystemFileHandle JS object obtained from the File System Access API)
  /// in [chunkSize]-byte slices using the FileReader API.
  ///
  /// On non-web this returns an empty stream.
  Stream<List<int>> uploadWithReadableStream(
    Object fileHandle, {
    int chunkSize = defaultChunkSize,
  });

  /// Returns a [Stream<List<int>>] that reads [blob] (an [html.File] or any
  /// Blob-like JS object that supports `.slice(start, end)`) in [chunkSize]-byte
  /// chunks using the FileReader API.
  ///
  /// This is the upload streaming path used when the local file service has
  /// stored an [html.File] reference (e.g. from directory picker grant), as
  /// opposed to a FileSystemFileHandle.
  ///
  /// On non-web this returns an empty stream.
  Stream<List<int>> streamFromBlob(
    Object blob, {
    int chunkSize = defaultChunkSize,
  });

  /// Opens a save-file picker (showSaveFilePicker) and pipes [data] chunks
  /// directly into the chosen file via a WritableStream, without buffering the
  /// whole content in memory as a Blob.
  ///
  /// Returns `true` when the stream was fully written, `false` when the user
  /// cancelled the picker or the API is not available.
  ///
  /// On non-web this returns `false`.
  Future<bool> downloadWithWritableStream(
    Stream<List<int>> data,
    String filename, {
    int? totalSize,
  });

  factory WebStreamingService() => _impl.createWebStreamingService();
}
