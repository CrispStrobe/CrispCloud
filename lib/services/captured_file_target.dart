import 'dart:typed_data';

import '../models/file_item.dart';
import '../models/storage_reference.dart';
import 'cloud_storage_interface.dart';
import 'file_cache_service.dart';
import 'local_file_service.dart';
import 'pdf_file_store.dart';

enum FileWriteOutcome { savedOriginal, downloadedCopy }

class FileTargetConflict implements Exception {
  const FileTargetConflict(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A captured editor target exceeded its existing input or output budget.
/// Keep the numeric limit so each editor can localize the presentation.
class FileTargetTooLarge extends FileTargetConflict {
  FileTargetTooLarge(this.limitBytes)
    : super(
        'This file exceeds the ${limitBytes ~/ (1024 * 1024)} MiB editing limit.',
      );

  final int limitBytes;
}

/// Shared editor target with captured storage, fresh reads and content checks.
/// The established PDF/image store supplies the staged-write/conflict contract;
/// the host sees format-neutral errors and never treats a download as a save.
class CapturedFileTarget {
  CapturedFileTarget.local({
    required this.reference,
    required LocalFileService service,
    required FileItem file,
    required this.isCurrent,
    int maxBytes = 64 * 1024 * 1024,
  }) : _store = PdfFileStore.local(
         service: service,
         file: file,
         inputLimitBytes: maxBytes,
         outputLimitBytes: maxBytes * 2,
       );

  CapturedFileTarget.remote({
    required this.reference,
    required CloudStorageClient client,
    required FileCacheService cache,
    required FileItem file,
    required this.isCurrent,
    int maxBytes = 64 * 1024 * 1024,
  }) : _store = PdfFileStore.remote(
         client: client,
         providerName: reference.storage.id,
         cache: cache,
         file: file,
         isCurrentAccount: isCurrent,
         inputLimitBytes: maxBytes,
         outputLimitBytes: maxBytes * 2,
       );

  final FileReference reference;
  final bool Function() isCurrent;
  final PdfFileStore _store;

  void _assertCurrent() {
    if (!isCurrent()) {
      throw const FileTargetConflict(
        'The original storage is disconnected or changed. Reopen the file before saving.',
      );
    }
  }

  Future<Uint8List> load() async {
    _assertCurrent();
    final bytes = await _translate(_store.load);
    _assertCurrent();
    return bytes;
  }

  Future<FileWriteOutcome> save(Uint8List bytes) async {
    _assertCurrent();
    final result = await _translate(() => _store.save(bytes));
    return result == PdfSaveOutcome.savedOriginal
        ? FileWriteOutcome.savedOriginal
        : FileWriteOutcome.downloadedCopy;
  }

  Future<T> _translate<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PdfSaveConflictException catch (error) {
      throw FileTargetConflict(error.message.replaceAll('PDF', 'file'));
    } on PdfAccountChangedException {
      throw const FileTargetConflict(
        'The original storage account changed. Reopen this file.',
      );
    } on PdfFileTooLargeException catch (error) {
      throw FileTargetTooLarge(error.limitBytes);
    }
  }
}
