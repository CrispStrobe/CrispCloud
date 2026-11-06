import 'dart:convert';
import 'dart:typed_data';

import 'file_bytes_loader.dart';
import 'internal_viewer_service.dart';

class ViewerSearchCancelled implements Exception {
  const ViewerSearchCancelled();
}

class ViewerSearchResult {
  const ViewerSearchResult(this.offsets, this.totalMatches, this.scannedBytes);
  final List<int> offsets;
  final int totalMatches;
  final int scannedBytes;
}

/// Linear-time byte search. A KMP prefix table carries partial matches across
/// reads without rereading overlap or retaining file-sized buffers. The result
/// index is bounded; totalMatches still counts the complete scanned file.
Future<ViewerSearchResult> searchViewerBytes(
  ViewBytesSource source,
  Uint8List pattern, {
  int maximumOffsets = 2000,
  int startOffset = 0,
  int alignment = 1,
  bool Function()? isCancelled,
  void Function()? checkSource,
  void Function(int bytes, int total)? onProgress,
}) async {
  if (pattern.isEmpty || pattern.length > 1024 * 1024) {
    throw const FormatException(
      'Search requires a pattern of 1 byte to 1 MiB.',
    );
  }
  if (maximumOffsets < 1 ||
      startOffset < 0 ||
      startOffset > source.size ||
      ![1, 2, 4].contains(alignment)) {
    throw ArgumentError('Invalid search bounds.');
  }
  void check() {
    if (isCancelled?.call() == true) throw const ViewerSearchCancelled();
    checkSource?.call();
  }

  check();
  await source.validateUnchanged();
  final prefixes = Uint32List(pattern.length);
  for (var index = 1, matched = 0; index < pattern.length; index++) {
    while (matched > 0 && pattern[index] != pattern[matched]) {
      matched = prefixes[matched - 1];
    }
    if (pattern[index] == pattern[matched]) matched++;
    prefixes[index] = matched;
  }
  final offsets = <int>[];
  var total = 0;
  var matched = 0;
  var position = startOffset;
  const chunkSize = 128 * 1024;
  while (position < source.size) {
    check();
    final length = (source.size - position).clamp(0, chunkSize);
    final bytes = source.readSync(position, length);
    if (bytes.length != length) {
      throw StateError('The file changed during search.');
    }
    for (var index = 0; index < bytes.length; index++) {
      while (matched > 0 && bytes[index] != pattern[matched]) {
        matched = prefixes[matched - 1];
      }
      if (bytes[index] == pattern[matched]) matched++;
      if (matched == pattern.length) {
        final offset = position + index + 1 - pattern.length;
        if (offset % alignment == 0) {
          total++;
          if (offsets.length < maximumOffsets) offsets.add(offset);
        }
        matched = prefixes[matched - 1];
      }
    }
    position += bytes.length;
    onProgress?.call(position, source.size);
    // Yield to navigation, cancellation and source-disconnect events.
    await Future<void>.delayed(Duration.zero);
  }
  check();
  await source.validateUnchanged();
  check();
  return ViewerSearchResult(List.unmodifiable(offsets), total, position);
}

int viewerCodeUnitBytes(String encoding) => switch (encoding) {
  'utf16le' || 'utf16be' => 2,
  'utf32le' || 'utf32be' => 4,
  _ => 1,
};

String viewerSourceEncoding(ViewBytesSource source, {String? override}) {
  if (override != null) return override;
  final sample = source.readSync(0, source.size.clamp(0, 4096));
  final detected = InternalViewerService.decodeTextForView(sample).encoding;
  if (detected != 'latin1') return detected;
  if (sample.length == source.size) return detected;
  // A sample may end in the middle of a UTF-8 code point. That incomplete tail
  // must not change the encoding of an otherwise valid streamed text file.
  for (var trim = 1; trim <= 3 && sample.length > trim; trim++) {
    try {
      utf8.decode(Uint8List.sublistView(sample, 0, sample.length - trim));
      return 'utf8';
    } on FormatException {
      /* Try the next possible UTF-8 suffix. */
    }
  }
  return detected;
}

Uint8List encodeViewerSearchText(String text, String encoding) {
  switch (encoding) {
    case 'utf8':
      return Uint8List.fromList(utf8.encode(text));
    case 'latin1':
      return Uint8List.fromList(latin1.encode(text));
    case 'utf16le':
    case 'utf16be':
      final data = ByteData(text.codeUnits.length * 2);
      final endian = encoding == 'utf16be' ? Endian.big : Endian.little;
      for (final (index, unit) in text.codeUnits.indexed) {
        data.setUint16(index * 2, unit, endian);
      }
      return data.buffer.asUint8List();
    case 'utf32le':
    case 'utf32be':
      final runes = text.runes.toList();
      final data = ByteData(runes.length * 4);
      final endian = encoding == 'utf32be' ? Endian.big : Endian.little;
      for (final (index, rune) in runes.indexed) {
        data.setUint32(index * 4, rune, endian);
      }
      return data.buffer.asUint8List();
    default:
      throw FormatException('Unsupported text encoding: $encoding');
  }
}
