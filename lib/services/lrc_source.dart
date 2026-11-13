import 'dart:typed_data';

import 'file_bytes_loader.dart';
import 'internal_viewer_service.dart';
import 'lrc_parser.dart';

/// The preview reads the complete lyric file so late metadata and offsets apply.
/// Larger inputs stay available in the existing source and hex views.
const int lrcSourceMaxBytes = 4 * 1024 * 1024;

enum LrcSourceError { readLimit, sourceChanged, readFailed }

/// App-authored failures translated by the viewer at its UI boundary.
class LrcSourceException implements Exception {
  const LrcSourceException(this.code);

  final LrcSourceError code;

  @override
  String toString() => 'LRC preview: ${code.name}';
}

class LrcSourceResult {
  const LrcSourceResult({required this.document, required this.encoding});

  final LrcDocument document;
  final String encoding;
}

/// Borrows an already-open viewer source without opening a new provider or
/// taking ownership of its handle. [isCurrent] can bind the read to the host's
/// captured source identity, mode, encoding, and load generation.
///
/// No partial document is parsed: the byte limit is checked before reading,
/// native snapshots are validated before and after reading, and copied windows
/// remain independent of the source's scroll cache. Parser limits are retained
/// in [LrcDocument.isTruncated] for the caller to show the source fallback.
Future<LrcSourceResult> readLrcSource(
  ViewBytesSource source, {
  String? encodingOverride,
  bool Function()? isCurrent,
}) async {
  final length = source.size;

  void checkCurrent() {
    if (source.size != length || (isCurrent != null && !isCurrent())) {
      throw const LrcSourceException(LrcSourceError.sourceChanged);
    }
  }

  Future<void> validate() async {
    try {
      await source.validateUnchanged();
    } catch (_) {
      throw const LrcSourceException(LrcSourceError.sourceChanged);
    }
    checkCurrent();
  }

  checkCurrent();
  if (length > lrcSourceMaxBytes) {
    throw const LrcSourceException(LrcSourceError.readLimit);
  }
  if (length < 0) {
    throw const LrcSourceException(LrcSourceError.readFailed);
  }
  await validate();

  final bytes = Uint8List(length);
  const windowBytes = 256 * 1024;
  var copied = 0;
  while (copied < length) {
    checkCurrent();
    final remaining = length - copied;
    final count = remaining < windowBytes ? remaining : windowBytes;
    final Uint8List window;
    try {
      window = source.readSync(copied, count);
    } on StateError {
      throw const LrcSourceException(LrcSourceError.sourceChanged);
    } catch (_) {
      throw const LrcSourceException(LrcSourceError.readFailed);
    }
    if (window.length != count) {
      throw const LrcSourceException(LrcSourceError.readFailed);
    }
    bytes.setRange(copied, copied + count, window);
    copied += count;
    checkCurrent();
    if (copied < length) {
      // Allow host mode/encoding changes to cancel between bounded windows.
      await Future<void>.delayed(Duration.zero);
    }
  }

  await validate();
  final decoded = InternalViewerService.decodeTextForView(
    bytes,
    encoding: encodingOverride,
  );
  return LrcSourceResult(
    document: parseLrc(decoded.text),
    encoding: decoded.encoding,
  );
}
