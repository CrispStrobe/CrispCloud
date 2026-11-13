// Copyright 2026 Flyfish Viewer
// SPDX-License-Identifier: Apache-2.0
//
// Modified Dart port of File Viewer's standalone LRC parser. This version uses
// immutable models, lazy line scanning, pre-allocation expansion bounds,
// explicit limit results and a stable timeline. It never opens or plays media.
// Exact upstream source, license and changes: packages/file_viewer_lrc/UPSTREAM.md

const int lrcMaxSourceCodeUnits = 2_000_000;
const int lrcMaxCues = 10_000;
const int lrcMaxExpandedWords = 50_000;
const int lrcMaxMetadata = 1_000;

/// Includes the largest supported word timestamp, repeat shift and offset.
/// All parser arithmetic remains well below JavaScript's exact-integer limit.
const int lrcMaxTimelineMilliseconds = 20_000_000_000_000;

enum LrcLimitReason { sourceSize, cueCount, wordCount, metadataCount }

class LrcMetadata {
  const LrcMetadata({
    required this.key,
    required this.value,
    required this.line,
  });

  final String key;
  final String value;
  final int line;
}

class LrcWord {
  const LrcWord({required this.text, required this.timeMs});

  final String text;
  final int? timeMs;
}

class LrcCue {
  const LrcCue({
    required this.line,
    required this.timeMs,
    required this.text,
    required this.role,
    required this.words,
    required this.sourceOrder,
  });

  /// One-based original source line, shared by repeated timestamps on a line.
  final int line;
  final int? timeMs;
  final String text;

  /// Optional LRC voice marker: M, F or D. Untimed lines have no voice marker.
  final String? role;
  final List<LrcWord> words;

  /// Stable expansion order, also used to break equal-time timeline ties.
  final int sourceOrder;
}

class LrcDocument {
  const LrcDocument({
    required this.source,
    required this.offsetMs,
    required this.metadata,
    required this.cues,
    required this.timedCues,
    this.limitReason,
  });

  /// The exact supplied source, including BOM, line endings and spacing.
  final String source;
  final int offsetMs;
  final List<LrcMetadata> metadata;

  /// Source order, including empty and untimed lines.
  final List<LrcCue> cues;

  /// Timed cues only, ordered by time and then original expansion order.
  final List<LrcCue> timedCues;
  final LrcLimitReason? limitReason;
  bool get isTruncated => limitReason != null;
}

final _timestamp = RegExp(r'^(-?)(\d{1,8}):([0-5]\d)(?:[.:](\d{1,3}))?$');
final _metadata = RegExp(
  r'^\[([a-z][a-z0-9_-]*):(.*)\]\s*$',
  caseSensitive: false,
);
final _offset = RegExp(r'^[+-]?\d{1,13}$');
final _voice = RegExp(r'^([MFD]):');
final _wordMarker = RegExp(r'<(-?\d{1,8}:[0-5]\d(?:[.:]\d{1,3})?)>');
final _lineBreak = RegExp(r'\r\n|\r|\n');

/// Strict, bounded LRC timestamp recognition. Unknown markers remain source
/// text; whitespace, excess digits, invalid seconds and suffixes are rejected.
int? parseLrcTimestamp(String value) {
  if (value.isEmpty || value.length > 16) return null;
  final match = _timestamp.firstMatch(value);
  if (match == null || match.end != value.length) return null;
  final milliseconds =
      int.parse(match[2]!) * 60000 +
      int.parse(match[3]!) * 1000 +
      int.parse((match[4] ?? '').padRight(3, '0'));
  return match[1] == '-' ? -milliseconds : milliseconds;
}

String formatLrcTimestamp(int milliseconds) {
  if (milliseconds < -lrcMaxTimelineMilliseconds ||
      milliseconds > lrcMaxTimelineMilliseconds) {
    throw RangeError.range(
      milliseconds,
      -lrcMaxTimelineMilliseconds,
      lrcMaxTimelineMilliseconds,
      'milliseconds',
    );
  }
  final absolute = milliseconds.abs();
  final minutes = (absolute ~/ 60000).toString().padLeft(2, '0');
  final seconds = ((absolute ~/ 1000) % 60).toString().padLeft(2, '0');
  final fraction = (absolute % 1000).toString().padLeft(3, '0');
  return '${milliseconds < 0 ? '-' : ''}$minutes:$seconds.$fraction';
}

/// Parse a static lyrics document without evaluating markup or loading media.
///
/// Positive offset advances lyrics, so it is subtracted exactly once from both
/// line and word clocks. The last valid offset applies to the entire document,
/// including earlier lines. Invalid/oversized offsets remain visible metadata.
///
/// A limit returns a bounded partial model and the unchanged source. Consumers
/// must not present a truncated model as a complete timed preview: a later
/// offset or cue might be missing. Offer the original source view instead.
LrcDocument parseLrc(String source) {
  final metadata = <LrcMetadata>[];
  final pending = <_PendingCue>[];
  var offsetMs = 0;
  var expandedWords = 0;
  String? role;

  LrcDocument finish([LrcLimitReason? reason]) =>
      _finish(source, offsetMs, metadata, pending, reason);

  if (source.length > lrcMaxSourceCodeUnits) {
    return finish(LrcLimitReason.sourceSize);
  }

  for (final (lineNumber, line) in _lines(source)) {
    final meta = _metadata.firstMatch(line);
    if (meta != null && meta.end == line.length) {
      if (metadata.length >= lrcMaxMetadata) {
        return finish(LrcLimitReason.metadataCount);
      }
      final key = meta[1]!;
      final value = meta[2]!;
      metadata.add(LrcMetadata(key: key, value: value, line: lineNumber));
      if (key.toLowerCase() == 'offset') {
        final normalized = value.trim();
        // Check width before integer parsing; huge digit strings are preserved
        // as metadata without expensive or platform-dependent conversion.
        final match = normalized.length <= 14
            ? _offset.firstMatch(normalized)
            : null;
        if (match != null && match.end == normalized.length) {
          final value = int.parse(normalized);
          if (value >= -1000000000000 && value <= 1000000000000) {
            offsetMs = value;
          }
        }
      }
      continue;
    }

    var cursor = 0;
    final timestamps = <int>[];
    while (cursor < line.length && line.codeUnitAt(cursor) == 0x5b) {
      final end = line.indexOf(']', cursor + 1);
      if (end < 0 || end - cursor > 17) break;
      final timestamp = parseLrcTimestamp(line.substring(cursor + 1, end));
      if (timestamp == null) break;
      if (timestamps.length >= lrcMaxCues - pending.length) {
        return finish(LrcLimitReason.cueCount);
      }
      timestamps.add(timestamp);
      cursor = end + 1;
    }
    final copies = timestamps.isEmpty ? 1 : timestamps.length;
    if (copies > lrcMaxCues - pending.length) {
      return finish(LrcLimitReason.cueCount);
    }

    var body = line.substring(cursor);
    final speaker = timestamps.isNotEmpty ? _voice.firstMatch(body) : null;
    if (speaker != null) {
      role = speaker[1];
      body = body.substring(2);
    }
    // Bound the multiplied output before allocating segments or repeated cues.
    final availableWords = (lrcMaxExpandedWords - expandedWords) ~/ copies;
    if (availableWords == 0) return finish(LrcLimitReason.wordCount);
    final words = <LrcWord>[];
    var wordStart = 0;
    int? wordTime;
    for (final match in _wordMarker.allMatches(body)) {
      if (match.start > wordStart) {
        if (words.length >= availableWords) {
          return finish(LrcLimitReason.wordCount);
        }
        words.add(
          LrcWord(
            text: body.substring(wordStart, match.start),
            timeMs: wordTime,
          ),
        );
      }
      wordTime = parseLrcTimestamp(match[1]!);
      wordStart = match.end;
    }
    if (wordStart < body.length || words.isEmpty) {
      if (words.length >= availableWords) {
        return finish(LrcLimitReason.wordCount);
      }
      words.add(LrcWord(text: body.substring(wordStart), timeMs: wordTime));
    }
    expandedWords += words.length * copies;
    final text = words.map((word) => word.text).join();
    final stableWords = List<LrcWord>.unmodifiable(words);
    for (var index = 0; index < copies; index++) {
      final timestamp = timestamps.isEmpty ? null : timestamps[index];
      pending.add(
        _PendingCue(
          line: lineNumber,
          timeMs: timestamp,
          shiftMs: timestamp == null ? 0 : timestamp - timestamps.first,
          text: text,
          role: timestamp == null ? null : role,
          words: stableWords,
        ),
      );
    }
  }
  return finish();
}

Iterable<(int, String)> _lines(String source) sync* {
  var start = source.startsWith('\uFEFF') ? 1 : 0;
  var number = 1;
  for (final match in _lineBreak.allMatches(source, start)) {
    yield (number++, source.substring(start, match.start));
    start = match.end;
  }
  yield (number, source.substring(start));
}

class _PendingCue {
  const _PendingCue({
    required this.line,
    required this.timeMs,
    required this.shiftMs,
    required this.text,
    required this.role,
    required this.words,
  });
  final int line;
  final int? timeMs;
  final int shiftMs;
  final String text;
  final String? role;
  final List<LrcWord> words;
}

LrcDocument _finish(
  String source,
  int offsetMs,
  List<LrcMetadata> metadata,
  List<_PendingCue> pending,
  LrcLimitReason? reason,
) {
  final cues = <LrcCue>[];
  for (final cue in pending) {
    cues.add(
      LrcCue(
        line: cue.line,
        timeMs: cue.timeMs == null ? null : cue.timeMs! - offsetMs,
        text: cue.text,
        role: cue.role,
        words: List.unmodifiable([
          for (final word in cue.words)
            LrcWord(
              text: word.text,
              timeMs: word.timeMs == null
                  ? null
                  : word.timeMs! + cue.shiftMs - offsetMs,
            ),
        ]),
        sourceOrder: cues.length,
      ),
    );
  }
  final timed = cues.where((cue) => cue.timeMs != null).toList();
  timed.sort((a, b) {
    final byTime = a.timeMs!.compareTo(b.timeMs!);
    return byTime == 0 ? a.sourceOrder.compareTo(b.sourceOrder) : byTime;
  });
  return LrcDocument(
    source: source,
    offsetMs: offsetMs,
    metadata: List.unmodifiable(metadata),
    cues: List.unmodifiable(cues),
    timedCues: List.unmodifiable(timed),
    limitReason: reason,
  );
}
