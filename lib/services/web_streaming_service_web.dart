// lib/services/web_streaming_service_web.dart
//
// Web implementation of WebStreamingService.
//
// Upload path
// -----------
// Given a FileSystemFileHandle (from the File System Access API), calls
// handle.getFile() to obtain a File blob, then reads it in [chunkSize]-byte
// slices with FileReader.readAsArrayBuffer(blob.slice(...)) so that only one
// slice at a time is held in memory.  The resulting Stream<List<int>> can be
// passed directly to any CloudStorageAdapter.uploadStream().
//
// Download path
// -------------
// Calls window.showSaveFilePicker() to get a FileSystemFileHandle chosen by
// the user, opens a FileSystemWritableFileStream via createWritable(), and
// writes each incoming chunk immediately.  No Blob is ever assembled — chunks
// flow straight to disk.

import 'dart:async';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;
import 'filen_web_stub.dart' if (dart.library.js_util) 'dart:js_util' as js;

import 'log_service.dart';
import 'web_streaming_service.dart';

WebStreamingService createWebStreamingService() => _WebStreamingService();

class _WebStreamingService implements WebStreamingService {
  static final _log = Log('WebStreamingService');

  // ---- isSupported --------------------------------------------------------

  @override
  bool get isSupported => js.hasProperty(html.window, 'showSaveFilePicker');

  // ---- Upload: chunked FileReader slice read --------------------------------

  @override
  Stream<List<int>> uploadWithReadableStream(
    Object fileHandle, {
    int chunkSize = WebStreamingService.defaultChunkSize,
  }) {
    if (chunkSize <= 0) chunkSize = WebStreamingService.defaultChunkSize;

    final controller = StreamController<List<int>>();

    controller.onListen = () => _runUploadStream(
          fileHandle,
          chunkSize,
          controller,
        );

    return controller.stream;
  }

  Future<void> _runUploadStream(
    Object fileHandle,
    int chunkSize,
    StreamController<List<int>> controller,
  ) async {
    try {
      // handle.getFile() → File (Blob subtype)
      final filePromise = js.callMethod(fileHandle, 'getFile', []);
      final file = await js.promiseToFuture(filePromise);

      final size = (js.getProperty(file, 'size') as num).toInt();
      _log.info('uploadWithReadableStream: starting', {
        'size': size,
        'chunkSize': chunkSize,
      });

      int offset = 0;
      while (offset < size) {
        if (controller.isClosed) break;

        final end = (offset + chunkSize).clamp(0, size);

        // blob.slice(start, end) → Blob
        final slice = js.callMethod(file as Object, 'slice', [offset, end]);

        // Read the slice via FileReader
        final reader = html.FileReader();
        reader.readAsArrayBuffer(slice as html.Blob);
        await reader.onLoadEnd.first;

        if (reader.error != null) {
          controller.addError(Exception('FileReader error at offset $offset'));
          break;
        }

        final result = reader.result;
        final bytes = result is ByteBuffer
            ? result.asUint8List()
            : result is Uint8List
                ? result
                : Uint8List.fromList(result as List<int>);

        controller.add(bytes);
        offset = end;
      }

      _log.info('uploadWithReadableStream: complete', {'bytesRead': offset});
    } catch (e, st) {
      _log.error('uploadWithReadableStream failed', e, st);
      if (!controller.isClosed) controller.addError(e, st);
    } finally {
      if (!controller.isClosed) await controller.close();
    }
  }

  // ---- Upload: read directly from a Blob (html.File) ----------------------

  @override
  Stream<List<int>> streamFromBlob(
    Object blob, {
    int chunkSize = WebStreamingService.defaultChunkSize,
  }) {
    if (chunkSize <= 0) chunkSize = WebStreamingService.defaultChunkSize;

    final controller = StreamController<List<int>>();
    controller.onListen = () => _runBlobStream(blob, chunkSize, controller);
    return controller.stream;
  }

  Future<void> _runBlobStream(
    Object blob,
    int chunkSize,
    StreamController<List<int>> controller,
  ) async {
    try {
      final size = (js.getProperty(blob, 'size') as num).toInt();
      _log.info('streamFromBlob: starting', {
        'size': size,
        'chunkSize': chunkSize,
      });

      int offset = 0;
      while (offset < size) {
        if (controller.isClosed) break;

        final end = (offset + chunkSize).clamp(0, size);
        final slice = js.callMethod(blob, 'slice', [offset, end]);

        final reader = html.FileReader();
        reader.readAsArrayBuffer(slice as html.Blob);
        await reader.onLoadEnd.first;

        if (reader.error != null) {
          controller.addError(Exception('FileReader error at offset $offset'));
          break;
        }

        final result = reader.result;
        final bytes = result is ByteBuffer
            ? result.asUint8List()
            : result is Uint8List
                ? result
                : Uint8List.fromList(result as List<int>);

        controller.add(bytes);
        offset = end;
      }

      _log.info('streamFromBlob: complete', {'bytesRead': offset});
    } catch (e, st) {
      _log.error('streamFromBlob failed', e, st);
      if (!controller.isClosed) controller.addError(e, st);
    } finally {
      if (!controller.isClosed) await controller.close();
    }
  }

  // ---- Download: showSaveFilePicker + WritableStream -----------------------

  @override
  Future<bool> downloadWithWritableStream(
    Stream<List<int>> data,
    String filename, {
    int? totalSize,
  }) async {
    if (!isSupported) {
      _log.warn('showSaveFilePicker not supported — download aborted');
      return false;
    }

    _log.info('downloadWithWritableStream: opening save picker', {
      'filename': filename,
      'totalSize': totalSize,
    });

    // 1. Open the save-file picker.
    final Object fileHandle;
    try {
      final opts = js.newObject();
      js.setProperty(opts, 'suggestedName', filename);

      final promise = js.callMethod(html.window, 'showSaveFilePicker', [opts]);
      fileHandle = await js.promiseToFuture(promise);
    } catch (e) {
      if (_isAbort(e)) {
        _log.info('downloadWithWritableStream: user cancelled picker');
        return false;
      }
      _log.error('downloadWithWritableStream: picker failed', e);
      return false;
    }

    // 2. Open a writable stream.
    final Object writable;
    try {
      final writablePromise = js.callMethod(fileHandle, 'createWritable', []);
      writable = await js.promiseToFuture(writablePromise);
    } catch (e, st) {
      _log.error('downloadWithWritableStream: createWritable failed', e, st);
      return false;
    }

    // 3. Pipe chunks into the writable stream.
    int written = 0;
    try {
      await for (final chunk in data) {
        final uint8 = chunk is Uint8List
            ? chunk
            : Uint8List.fromList(chunk);

        final writePromise = js.callMethod(writable, 'write', [uint8]);
        await js.promiseToFuture(writePromise);
        written += uint8.length;
        _log.debug('downloadWithWritableStream: wrote chunk', {
          'chunkBytes': uint8.length,
          'totalWritten': written,
        });
      }
    } catch (e, st) {
      _log.error('downloadWithWritableStream: write failed', e, st);
      // Attempt to abort the writable so the browser doesn't leave a partial
      // file on disk.
      try {
        final abortPromise = js.callMethod(writable, 'abort', []);
        await js.promiseToFuture(abortPromise);
      } catch (_) {}
      return false;
    }

    // 4. Close the writable stream to finalise the file.
    try {
      final closePromise = js.callMethod(writable, 'close', []);
      await js.promiseToFuture(closePromise);
    } catch (e, st) {
      _log.error('downloadWithWritableStream: close failed', e, st);
      return false;
    }

    _log.info('downloadWithWritableStream: complete', {
      'filename': filename,
      'bytesWritten': written,
    });
    return true;
  }

  // ---- Helpers -------------------------------------------------------------

  bool _isAbort(Object e) {
    final s = e.toString();
    return s.contains('AbortError') || s.contains('user aborted');
  }
}
