import 'dart:typed_data';

import '../models/file_item.dart';
import 'cloud_storage_interface.dart';
import 'file_cache_service.dart';
import 'image_edit_session.dart';
import 'local_file_service.dart';
import 'pdf_edit_session.dart' show PdfSaveInProgressException, PdfSaveOutcome;
import 'pdf_file_store.dart';

export 'image_edit_session.dart' show ImageSaveOutcome;

class ImageSaveConflictException implements Exception {
  const ImageSaveConflictException();

  @override
  String toString() => 'ImageSaveConflictException';
}

class ImageAccountChangedException implements Exception {
  const ImageAccountChangedException();

  @override
  String toString() => 'ImageAccountChangedException';
}

/// Storage captured when the image opens, sharing the existing editor write
/// contract: fresh reads, hash/revision conflict checks, account binding, native
/// atomic replacement, cache invalidation, and honest browser-download results.
///
/// Only original-file persistence is exposed. PDF-specific copy naming and
/// messages remain private to the delegate. Remote saves inherit the generic
/// cloud API's preflight check/write race; they are not conditional writes.
abstract class ImageFileStore {
  factory ImageFileStore.local({
    required LocalFileService service,
    required FileItem file,
  }) => _ImageFileStore(
    PdfFileStore.local(
      service: service,
      file: file,
      inputLimitBytes: kImageEditorInputLimitBytes,
      outputLimitBytes: kImageEditorOutputLimitBytes,
    ),
  );

  factory ImageFileStore.remote({
    required CloudStorageClient client,
    required String providerName,
    required FileCacheService cache,
    required FileItem file,
    bool Function()? isCurrentAccount,
  }) => _ImageFileStore(
    PdfFileStore.remote(
      client: client,
      providerName: providerName,
      cache: cache,
      file: file,
      isCurrentAccount: isCurrentAccount,
      inputLimitBytes: kImageEditorInputLimitBytes,
      outputLimitBytes: kImageEditorOutputLimitBytes,
    ),
  );

  String get documentId;
  String get displayName;
  String get path;
  bool get isRemote;

  Future<Uint8List> load();
  Future<ImageSaveOutcome> save(Uint8List bytes);
}

class _ImageFileStore implements ImageFileStore {
  _ImageFileStore(this._delegate);

  final PdfFileStore _delegate;
  ImageFileFormat? _format;
  bool _loading = false;
  bool _saving = false;

  @override
  String get documentId => _delegate.documentId;
  @override
  String get displayName => _delegate.displayName;
  @override
  String get path => _delegate.path;
  @override
  bool get isRemote => _delegate.isRemote;

  @override
  Future<Uint8List> load() => _translate(() async {
    if (_loading || _saving) throw const ImageSaveInProgressException();
    _loading = true;
    // A failed reload must not authorize a write using an old format check.
    try {
      _format = null;
      final bytes = await _delegate.load();
      _format = inspectEditableImage(bytes, fileName: displayName).format;
      return bytes;
    } finally {
      _loading = false;
    }
  });

  @override
  Future<ImageSaveOutcome> save(Uint8List bytes) => _translate(() async {
    if (_loading || _saving) throw const ImageSaveInProgressException();
    final format = _format;
    if (format == null) throw StateError('Load the image before saving it.');
    // Defend the storage boundary even if an embedding host bypasses the
    // session. Pixel decoding is the session's job; here validate encoding,
    // dimensions, CRC/marker structure and the original filename.
    if (bytes.length > kImageEditorOutputLimitBytes) {
      throw const ImageEditException(ImageEditFailure.outputTooLarge);
    }
    final snapshot = Uint8List.fromList(bytes).asUnmodifiableView();
    final info = inspectEditableImage(
      snapshot,
      fileName: displayName,
      maxBytes: kImageEditorOutputLimitBytes,
    );
    if (info.format != format) {
      throw const ImageEditException(ImageEditFailure.formatMismatch);
    }
    _saving = true;
    try {
      return switch (await _delegate.save(snapshot)) {
        PdfSaveOutcome.savedOriginal => ImageSaveOutcome.savedOriginal,
        PdfSaveOutcome.savedCopy => ImageSaveOutcome.savedCopy,
        PdfSaveOutcome.downloadedCopy => ImageSaveOutcome.downloadedCopy,
      };
    } finally {
      _saving = false;
    }
  });

  Future<T> _translate<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PdfSaveConflictException {
      throw const ImageSaveConflictException();
    } on PdfAccountChangedException {
      throw const ImageAccountChangedException();
    } on PdfSaveInProgressException {
      throw const ImageSaveInProgressException();
    } on PdfFileTooLargeException catch (error) {
      throw ImageEditException(
        error.limitBytes == kImageEditorInputLimitBytes
            ? ImageEditFailure.inputTooLarge
            : ImageEditFailure.outputTooLarge,
      );
    }
  }
}
