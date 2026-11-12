import 'dart:typed_data';

import '../models/file_item.dart';
import 'file_operation_service.dart';

class ViewerTailWindow {
  const ViewerTailWindow(
    this.bytes,
    this.offset,
    this.totalBytes, {
    required this.replacedOrTruncated,
    this.encoding,
  });
  final Uint8List bytes;
  final int offset;
  final int totalBytes;
  final bool replacedOrTruncated;
  final String? encoding;
}

/// Follows a captured path, including log rotation/truncation. Each poll keeps
/// at most [windowBytes] bytes and closes a range stream at its sampled end.
class ViewerTailService {
  ViewerTailService(this.source, this.file, {this.windowBytes = 256 * 1024}) {
    if (windowBytes <= 0) {
      throw ArgumentError.value(windowBytes, 'windowBytes');
    }
    if (file.path == null) throw ArgumentError('A tail source needs a path.');
  }
  final FileOperationBackend source;
  final FileItem file;
  final int windowBytes;
  FileItem? _previous;

  void _check(bool Function()? isCancelled) {
    if (!source.isCurrent) {
      throw StateError('The original viewer source changed.');
    }
    if (isCancelled?.call() ?? false) throw StateError('Following stopped.');
  }

  Future<Uint8List> _range(
    FileItem current,
    int offset,
    int length,
    bool Function()? isCancelled,
  ) async {
    final bytes = BytesBuilder(copy: false);
    if (length == 0) return bytes.takeBytes();
    await for (final chunk in source.readRange(current, offset)) {
      _check(isCancelled);
      final remaining = length - bytes.length;
      bytes.add(chunk.length > remaining ? chunk.sublist(0, remaining) : chunk);
      if (bytes.length == length) break;
    }
    _check(isCancelled);
    return bytes.takeBytes();
  }

  Future<ViewerTailWindow> read({
    bool Function()? isCancelled,
    String? encodingOverride,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      _check(isCancelled);
      final current = await source.stat(file.path!);
      if (current == null || current.isFolder || current.isSymlink == true) {
        throw StateError(
          'The followed file is missing or no longer a regular file.',
        );
      }
      final size = current.size;
      if (size == null) {
        throw UnsupportedError(
          'This storage does not report the file size needed for tail mode.',
        );
      }
      if (!source.capabilities.readRanges && size > windowBytes) {
        throw UnsupportedError(
          'This storage cannot read file ranges. Download this file to follow it locally.',
        );
      }
      final header = await _range(current, 0, size < 4 ? size : 4, isCancelled);
      String? encoding;
      var unit = 1;
      if (header.length >= 4 &&
          header[0] == 0xff &&
          header[1] == 0xfe &&
          header[2] == 0 &&
          header[3] == 0) {
        encoding = 'utf32le';
        unit = 4;
      } else if (header.length >= 4 &&
          header[0] == 0 &&
          header[1] == 0 &&
          header[2] == 0xfe &&
          header[3] == 0xff) {
        encoding = 'utf32be';
        unit = 4;
      } else if (header.length >= 2 && header[0] == 0xff && header[1] == 0xfe) {
        encoding = 'utf16le';
        unit = 2;
      } else if (header.length >= 2 && header[0] == 0xfe && header[1] == 0xff) {
        encoding = 'utf16be';
        unit = 2;
      }
      encoding = encodingOverride ?? encoding;
      unit = switch (encoding) {
        'utf32le' || 'utf32be' => 4,
        'utf16le' || 'utf16be' => 2,
        _ => 1,
      };
      var start = size > windowBytes ? size - windowBytes : 0;
      start += (unit - start % unit) % unit;
      if (start > size) start = size;
      final count = size - start;
      var bytes = await _range(current, start, count, isCancelled);
      final after = await source.stat(file.path!);
      _check(isCancelled);
      if (after == null ||
          after.isFolder ||
          (after.size ?? 0) < size ||
          bytes.length != count ||
          current.uuid != after.uuid) {
        if (attempt == 0) continue;
        throw StateError(
          'The followed file changed during the read. Reload to try again.',
        );
      }
      if (unit == 1 &&
          (encoding == null || encoding == 'utf8') &&
          start > 0) {
        var cut = 0;
        while (cut < bytes.length && (bytes[cut] & 0xc0) == 0x80) {
          cut++;
        }
        if (cut > 0) {
          bytes = Uint8List.sublistView(bytes, cut);
          start += cut;
        }
      }
      final previous = _previous;
      _previous = current;
      return ViewerTailWindow(
        bytes,
        start,
        size,
        replacedOrTruncated:
            previous != null &&
            ((previous.size ?? 0) > size || previous.uuid != current.uuid),
        encoding: encoding,
      );
    }
    throw StateError('The followed file could not be read.');
  }
}
