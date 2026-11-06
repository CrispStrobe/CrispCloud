import 'dart:convert';
import 'dart:typed_data';

import 'file_bytes_loader.dart';
import 'internal_viewer_service.dart';
import 'viewer_text_decoder.dart';

class ViewerSearchCancelled implements Exception {
  const ViewerSearchCancelled();
}

class ViewerSearchResult {
  const ViewerSearchResult(
    this.offsets,
    this.totalMatches,
    this.scannedBytes, {
    this.endOffsets = const [],
    this.textOffsets = const [],
    this.textEndOffsets = const [],
    this.nextOffset,
    this.nextTextOffset,
  });
  final List<int> offsets;
  final int totalMatches;
  final int scannedBytes;
  final List<int> endOffsets;
  final List<int> textOffsets;
  final List<int> textEndOffsets;
  final int? nextOffset;
  final int? nextTextOffset;
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
  int skipMatches = 0,
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
      skipMatches < 0 ||
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
          if (total > skipMatches && offsets.length < maximumOffsets) {
            offsets.add(offset);
          }
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
  return ViewerSearchResult(
    List.unmodifiable(offsets),
    total,
    position,
    endOffsets: List.unmodifiable(
      offsets.map((offset) => offset + pattern.length),
    ),
    nextOffset: offsets.isEmpty ? null : offsets.last + 1,
  );
}

/// Searches decoded literal text with the same Unicode case rules in small
/// and streamed views. Offset maps retain exact encoded ranges for highlighting
/// even when a caseless match uses a different byte length (for example K/k).
/// Only one decode chunk, a pattern-sized overlap and one result page survive.
Future<ViewerSearchResult> searchViewerText(
  ViewBytesSource source,
  String query, {
  required String encoding,
  bool caseSensitive = false,
  bool skipBom = true,
  int maximumOffsets = 2000,
  int startOffset = 0,
  int startTextOffset = 0,
  int skipMatches = 0,
  bool Function()? isCancelled,
  void Function()? checkSource,
  void Function(int bytes, int total)? onProgress,
}) async {
  if (query.isEmpty || query.length > 1024 * 1024) {
    throw const FormatException(
      'Text search requires 1 character to 1 MiB of text.',
    );
  }
  if (maximumOffsets < 1 ||
      skipMatches < 0 ||
      startTextOffset < 0 ||
      startOffset < 0 ||
      startOffset > source.size) {
    throw ArgumentError('Invalid text search bounds.');
  }
  void check() {
    if (isCancelled?.call() == true) throw const ViewerSearchCancelled();
    checkSource?.call();
  }

  check();
  await source.validateUnchanged();
  check();
  final decoder = ViewerTextDecoder(encoding, skipBom: skipBom);
  final expression = RegExp(
    '(?=(${RegExp.escape(query)}))',
    caseSensitive: caseSensitive,
    unicode: true,
  );
  final offsets = <int>[],
      ends = <int>[],
      textOffsets = <int>[],
      textEnds = <int>[];
  var total = 0, processed = startTextOffset, lastReported = -1;
  int? nextOffset, nextTextOffset;
  var tail = '';
  var tailStarts = <int>[], tailEnds = <int>[];

  void match(ViewerDecodedText part) {
    final window = '$tail${part.text}';
    final starts = [...tailStarts, ...part.starts];
    final byteEnds = [...tailEnds, ...part.ends];
    final base = processed - tail.length;
    for (final hit in expression.allMatches(window)) {
      final absolute = base + hit.start;
      if (absolute <= lastReported) continue;
      lastReported = absolute;
      total++;
      if (total <= skipMatches || offsets.length >= maximumOffsets) continue;
      final end = hit.start + hit.group(1)!.length;
      offsets.add(starts[hit.start]);
      ends.add(byteEnds[end - 1]);
      textOffsets.add(absolute);
      textEnds.add(base + end);
      nextOffset = byteEnds[hit.start];
      final first = window.codeUnitAt(hit.start);
      nextTextOffset =
          absolute +
          (first >= 0xd800 &&
                  first <= 0xdbff &&
                  hit.start + 1 < window.length &&
                  window.codeUnitAt(hit.start + 1) >= 0xdc00 &&
                  window.codeUnitAt(hit.start + 1) <= 0xdfff
              ? 2
              : 1);
    }
    processed += part.text.length;
    var keepFrom = (window.length - query.length - 2).clamp(0, window.length);
    if (keepFrom > 0 &&
        window.codeUnitAt(keepFrom) >= 0xdc00 &&
        window.codeUnitAt(keepFrom) <= 0xdfff &&
        window.codeUnitAt(keepFrom - 1) >= 0xd800 &&
        window.codeUnitAt(keepFrom - 1) <= 0xdbff) {
      keepFrom--;
    }
    tail = window.substring(keepFrom);
    tailStarts = starts.sublist(keepFrom);
    tailEnds = byteEnds.sublist(keepFrom);
  }

  var position = alignViewerTextOffset(
    source,
    startOffset,
    encoding,
    forward: true,
  );
  while (position < source.size) {
    check();
    final length = (source.size - position).clamp(0, 128 * 1024);
    final bytes = source.readSync(position, length);
    if (bytes.length != length) {
      throw StateError('The file changed during search.');
    }
    match(decoder.add(bytes, position));
    position += bytes.length;
    onProgress?.call(position, source.size);
    await Future<void>.delayed(Duration.zero);
  }
  match(decoder.add(Uint8List(0), position, last: true));
  check();
  await source.validateUnchanged();
  check();
  return ViewerSearchResult(
    List.unmodifiable(offsets),
    total,
    position,
    endOffsets: List.unmodifiable(ends),
    textOffsets: List.unmodifiable(textOffsets),
    textEndOffsets: List.unmodifiable(textEnds),
    nextOffset: nextOffset,
    nextTextOffset: nextTextOffset,
  );
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
