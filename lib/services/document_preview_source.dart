import 'dart:typed_data';

import 'file_bytes_loader.dart';

enum DocumentSourceError { readLimit, sourceChanged, readFailed }

class DocumentSourceException implements Exception {
  const DocumentSourceException(this.code);
  final DocumentSourceError code;
  @override
  String toString() => 'Document preview: ${code.name}';
}

/// Takes a complete bounded snapshot from an already-open viewer source.
/// The source owner retains its handle. No partial document reaches a parser.
Future<Uint8List> readDocumentPreviewSource(
  ViewBytesSource source, {
  required int maxBytes,
  bool Function()? isCurrent,
}) async {
  final length = source.size;
  void checkCurrent() {
    if (source.size != length || (isCurrent != null && !isCurrent())) {
      throw const DocumentSourceException(DocumentSourceError.sourceChanged);
    }
  }

  Future<void> validate() async {
    try {
      await source.validateUnchanged();
    } catch (_) {
      throw const DocumentSourceException(DocumentSourceError.sourceChanged);
    }
    checkCurrent();
  }

  checkCurrent();
  if (maxBytes < 0 || length > maxBytes) {
    throw const DocumentSourceException(DocumentSourceError.readLimit);
  }
  if (length < 0) {
    throw const DocumentSourceException(DocumentSourceError.readFailed);
  }
  await validate();
  final bytes = Uint8List(length);
  const windowBytes = 256 * 1024;
  var offset = 0;
  while (offset < length) {
    checkCurrent();
    final count = length - offset < windowBytes ? length - offset : windowBytes;
    final Uint8List window;
    try {
      window = source.readSync(offset, count);
    } on StateError {
      throw const DocumentSourceException(DocumentSourceError.sourceChanged);
    } catch (_) {
      throw const DocumentSourceException(DocumentSourceError.readFailed);
    }
    if (window.length != count) {
      throw const DocumentSourceException(DocumentSourceError.readFailed);
    }
    bytes.setRange(offset, offset + count, window);
    offset += count;
    checkCurrent();
    if (offset < length) await Future<void>.delayed(Duration.zero);
  }
  await validate();
  return bytes;
}
