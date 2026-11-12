// lib/services/rust_cloud_delegate.dart
//
// CloudStorageClient operations backed by the optional Rust Filen/Internxt
// engine. FilenClientAdapter and InternxtClientAdapter route to this delegate
// when the effective engine is Rust; their public types stay the same so the
// app's provider-specific restore/logout code keeps working.
import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_storage/rust_cloud.dart';

import 'internxt_transfer_platform.dart' show saveInternxtDownload;
import 'rust_cloud_temp_file_stub.dart'
    if (dart.library.io) 'rust_cloud_temp_file_io.dart';

typedef RustSessionPersister = Future<void> Function(String envelope);

class RustCloudDelegate {
  RustCloudDelegate(this.session, {required this.persist});

  final RustCloudSession session;

  /// Called with a fresh envelope after the engine renewed its tokens.
  final RustSessionPersister persist;

  String get account => session.account;
  String get rootId => session.rootId;

  void _checkCurrent() {
    if (session.isClosed) {
      throw StateError('The original account is no longer available.');
    }
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    _checkCurrent();
    try {
      return await action();
    } finally {
      await _persistRenewed();
    }
  }

  Future<void> _persistRenewed() async {
    final renewed = await session.takeRenewedEnvelope();
    if (renewed != null) await persist(renewed);
  }

  static Map<String, dynamic> _row(RustCloudEntry entry) => {
    'name': entry.name,
    'uuid': entry.uuid,
    if (!entry.isDirectory) 'size': entry.size,
    if (entry.modified != null)
      'lastModified': entry.modified!.millisecondsSinceEpoch,
    if (entry.mime != null) 'mime': entry.mime,
  };

  Future<Map<String, dynamic>> listPath(String path, {bool fresh = false}) =>
      _run(() async {
        final entries = await session.list(path, fresh: fresh);
        return {
          'folders': [
            for (final e in entries)
              if (e.isDirectory) _row(e),
          ],
          'files': [
            for (final e in entries)
              if (!e.isDirectory) _row(e),
          ],
        };
      });

  Future<Map<String, dynamic>?> resolvePath(String path) => _run(() async {
    try {
      final entry = await session.stat(path);
      return {
        'type': entry.isDirectory ? 'folder' : 'file',
        'uuid': entry.uuid,
        'name': entry.name,
        'size': entry.size,
        if (entry.modified != null)
          'lastModified': entry.modified!.millisecondsSinceEpoch,
      };
    } on RustCloudException catch (e) {
      if (e.code == RustCloudErrorCode.notFound) return null;
      rethrow;
    }
  });

  Future<void> createFolderPath(String path) =>
      _run(() async => session.mkdir(path));

  Future<void> deletePath(String path) => _run(() => session.trash(path));

  Future<void> movePath(String source, String targetFolder) =>
      _run(() => session.move(source, targetFolder));

  Future<void> renamePath(String path, String newName) =>
      _run(() => session.rename(path, newName));

  Future<void> uploadBytes(
    List<int> bytes,
    String fileName,
    String targetPath, {
    void Function(int, int)? onProgress,
  }) => _run(() async {
    final temp = await RustCloudTempFile.create(fileName);
    try {
      await temp.writeBytes(bytes);
      await session.upload(
        temp.path,
        targetPath,
        fileName,
        onProgress: onProgress,
      );
    } finally {
      await temp.delete();
    }
  });

  Future<void> uploadStream(
    Stream<List<int>> source,
    int length,
    String fileName,
    String targetPath, {
    void Function(int, int)? onProgress,
  }) => _run(() async {
    final temp = await RustCloudTempFile.create(fileName);
    try {
      await temp.writeStream(source, length);
      await session.upload(
        temp.path,
        targetPath,
        fileName,
        onProgress: onProgress,
      );
    } finally {
      await temp.delete();
    }
  });

  /// Rust downloads into a private temporary file (bounded memory), which is
  /// then streamed. Cancelling the subscription cancels the native transfer.
  Stream<List<int>> downloadStream(
    String remotePath, {
    void Function(int, int)? onProgress,
  }) {
    final cancellation = RustCloudCancellation();
    late final StreamController<List<int>> controller;
    RustCloudTempFile? temp;
    StreamSubscription<List<int>>? reading;
    Future<void> start() async {
      try {
        _checkCurrent();
        temp = await RustCloudTempFile.create(
          remotePath.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => 'download'),
        );
        await session.download(
          remotePath,
          temp!.path,
          onProgress: onProgress,
          cancellation: cancellation,
        );
        await _persistRenewed();
        if (cancellation.isCancelled) return;
        reading = temp!.openRead().listen(
          controller.add,
          onError: controller.addError,
          onDone: () async {
            await temp?.delete();
            await controller.close();
          },
          cancelOnError: true,
        );
      } catch (error, stack) {
        await temp?.delete();
        if (!cancellation.isCancelled) controller.addError(error, stack);
        await controller.close();
      }
    }

    controller = StreamController<List<int>>(
      onListen: start,
      onPause: () => reading?.pause(),
      onResume: () => reading?.resume(),
      onCancel: () async {
        cancellation.cancel();
        await reading?.cancel();
        await temp?.delete();
      },
    );
    return controller.stream;
  }

  Future<Uint8List> downloadBytes(
    String remotePath, {
    void Function(int, int)? onProgress,
    int? maxBytes,
  }) async {
    if (maxBytes != null) {
      final entry = await _run(() => session.stat(remotePath));
      if (entry.size > maxBytes) {
        throw StateError('This file requires a streaming download.');
      }
    }
    final result = BytesBuilder(copy: false);
    await for (final chunk in downloadStream(
      remotePath,
      onProgress: onProgress,
    )) {
      result.add(chunk);
    }
    return result.takeBytes();
  }

  /// Publish through the app's existing download publisher (private staging,
  /// atomic replacement or verified copy for selected-file access).
  Future<void> downloadToPath(
    String remotePath,
    String localPath, {
    void Function(int, int)? onProgress,
  }) async {
    await saveInternxtDownload(
      downloadStream(remotePath, onProgress: onProgress),
      localPath,
      checkCurrent: _checkCurrent,
    );
  }

  void close() => session.close();

}
