import '../lib/services/lrc_parser.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  check(
    parseLrcTimestamp('99999999:59.999') == 5999999999999,
    'maximum parsed timestamp',
  );
  check(
    parseLrcTimestamp('-99999999:59.999') == -5999999999999,
    'minimum parsed timestamp',
  );
  final maximum = parseLrc(
    '[offset:-1000000000000]\n'
    '[-99999999:59.999][99999999:59.999]<99999999:59.999>X',
  );
  check(
    maximum.cues[1].words.single.timeMs == 18999999999997,
    'exact maximum combined word clock',
  );
  check(
    formatLrcTimestamp(maximum.cues[1].words.single.timeMs!) ==
        '316666666:39.997',
    'exact large-clock formatting',
  );

  for (final offset in [120, -250]) {
    final lyrics = parseLrc(
      '[00:01][00:03]<00:01>A <00:01.5>B\n'
      '[offset:$offset]',
    );
    check(lyrics.offsetMs == offset, 'signed late offset');
    check(lyrics.cues[0].timeMs == 1000 - offset, 'first line offset');
    check(lyrics.cues[1].timeMs == 3000 - offset, 'repeated line offset');
    check(
      lyrics.cues[0].words[1].timeMs == 1500 - offset,
      'first word offset applied once',
    );
    check(
      lyrics.cues[1].words[1].timeMs == 3500 - offset,
      'repeated word shift and offset applied once',
    );
  }
  check(formatLrcTimestamp(-1250) == '-00:01.250', 'negative formatting');

  final ordered = parseLrc(
    '[00:03][00:01]first\nplain\n'
    '[00:01]second\n[00:02]third',
  );
  check(
    ordered.cues[2].text == 'plain' && ordered.cues[2].timeMs == null,
    'untimed source-order line',
  );
  check(
    ordered.timedCues.map((cue) => cue.sourceOrder).join(',') == '1,3,4,0',
    'stable equal-time ordering',
  );

  const malformed = '\uFEFF[00:99]  <not-a-time>🌊\r\n';
  final literal = parseLrc(malformed);
  check(literal.source == malformed, 'exact original source');
  check(
    literal.cues.first.text == '[00:99]  <not-a-time>🌊',
    'malformed marker and whitespace preservation',
  );
  check(parseLrcTimestamp('00:01\n') == null, 'trailing newline rejection');
  check(parseLrcTimestamp('100000000:00') == null, 'timestamp digit bound');

  final oversized = parseLrc('x' * (lrcMaxSourceCodeUnits + 1));
  check(
    oversized.isTruncated &&
        oversized.limitReason == LrcLimitReason.sourceSize &&
        oversized.cues.isEmpty,
    'source fallback',
  );
  final cueOverflow = parseLrc('${'[00:01]' * (lrcMaxCues + 1)}X');
  check(
    cueOverflow.limitReason == LrcLimitReason.cueCount &&
        cueOverflow.cues.isEmpty,
    'cue expansion fallback',
  );
  final wordOverflow = parseLrc('${'[00:01]' * 1000}${'<00:01>X' * 51}');
  check(
    wordOverflow.limitReason == LrcLimitReason.wordCount &&
        wordOverflow.cues.isEmpty,
    'word multiplication fallback',
  );
  final metadataOverflow = parseLrc(
    List.filled(lrcMaxMetadata + 1, '[x:value]').join('\n'),
  );
  check(
    metadataOverflow.limitReason == LrcLimitReason.metadataCount &&
        metadataOverflow.metadata.length == lrcMaxMetadata,
    'metadata fallback',
  );

  print(
    'LRC portability checks passed: exact clocks, offsets, repeated words, '
    'stable ordering, literal source and bounded fallback.',
  );
}
