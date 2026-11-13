import 'package:crisp_cloud/services/lrc_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timestamps accept bounded minute, second and fraction forms', () {
    const cases = {
      '0:00': 0,
      '01:02': 62000,
      '01:02.1': 62100,
      '01:02.12': 62120,
      '01:02.123': 62123,
      '01:02:9': 62900,
      '01:02:045': 62045,
      '-00:01.250': -1250,
      '99999999:59.999': 5999999999999,
      '-99999999:59.999': -5999999999999,
    };
    for (final entry in cases.entries) {
      expect(parseLrcTimestamp(entry.key), entry.value, reason: entry.key);
    }
  });

  test(
    'malformed timestamps are rejected without trimming or prefix matches',
    () {
      for (final source in [
        '',
        '1:2',
        '00:60',
        '00:99',
        '1:00.1234',
        '100000000:00',
        '00:01x',
        ' 00:01',
        '00:01 ',
        '00:01\n',
        '00:01\r',
        '+00:01',
        '--01:01',
        'NaN:00',
        '${'9' * 100000}:00',
      ]) {
        expect(parseLrcTimestamp(source), isNull);
      }
    },
  );

  test('formatting preserves sign and exact milliseconds within bounds', () {
    expect(formatLrcTimestamp(0), '00:00.000');
    expect(formatLrcTimestamp(62123), '01:02.123');
    expect(formatLrcTimestamp(-1), '-00:00.001');
    expect(formatLrcTimestamp(5999999999999), '99999999:59.999');
    expect(
      () => formatLrcTimestamp(lrcMaxTimelineMilliseconds + 1),
      throwsRangeError,
    );
    expect(
      () => formatLrcTimestamp(-lrcMaxTimelineMilliseconds - 1),
      throwsRangeError,
    );
  });

  test(
    'preserves source BOM, line endings, whitespace and original line indices',
    () {
      const source = '\uFEFF[ti:  Example  ]\r\n[00:01]  Hello\t🌊  \rplain\n';
      final document = parseLrc(source);
      expect(document.source, source);
      expect(document.metadata.single.key, 'ti');
      expect(document.metadata.single.value, '  Example  ');
      expect(document.metadata.single.line, 1);
      expect(document.cues.map((cue) => cue.line), [2, 3, 4]);
      expect(document.cues.map((cue) => cue.text), [
        '  Hello\t🌊  ',
        'plain',
        '',
      ]);
      expect(document.cues.first.timeMs, 1000);
      expect(document.isTruncated, isFalse);
    },
  );

  test(
    'metadata-only and untimed documents remain usable without playback',
    () {
      final metadata = parseLrc('[ar:Name]\n[x-custom:unknown metadata]');
      expect(metadata.metadata.length, 2);
      expect(metadata.cues, isEmpty);
      expect(metadata.timedCues, isEmpty);
      final plain = parseLrc(' First line\n\nLast line ');
      expect(plain.cues.map((cue) => cue.text), [
        ' First line',
        '',
        'Last line ',
      ]);
      expect(plain.cues.every((cue) => cue.timeMs == null), isTrue);
      expect(plain.timedCues, isEmpty);
    },
  );

  test('unknown markers and active-looking markup remain literal text', () {
    const body =
        '[00:99]<not-a-time><00:01.1234>'
        '<img src="https://invalid.test/x" onerror="run()">';
    final document = parseLrc(body);
    expect(document.cues.single.text, body);
    expect(document.cues.single.timeMs, isNull);
    expect(document.cues.single.words.single.timeMs, isNull);
  });

  test(
    'repeated line tags shift inline clocks before applying offset once',
    () {
      final document = parseLrc(
        '[00:01][00:03]M:<00:01>A <00:01.50>B\n[offset:120]',
      );
      expect(document.offsetMs, 120);
      expect(document.cues.map((cue) => cue.timeMs), [880, 2880]);
      expect(document.cues.map((cue) => cue.text), ['A B', 'A B']);
      expect(document.cues.map((cue) => cue.line), [1, 1]);
      expect(document.cues.map((cue) => cue.role), ['M', 'M']);
      expect(document.cues[0].words.map((word) => word.timeMs), [880, 1380]);
      expect(document.cues[1].words.map((word) => word.timeMs), [2880, 3380]);
    },
  );

  test(
    'voice markers persist across timed lines but do not consume plain text',
    () {
      final document = parseLrc(
        '[00:01]M:A\n[00:02]B\nM:untimed\n'
        '[00:03]F:C\n[00:04]D:D\n[00:05]E',
      );
      expect(document.cues.map((cue) => cue.role), [
        'M',
        'M',
        null,
        'F',
        'D',
        'D',
      ]);
      expect(document.cues[2].text, 'M:untimed');
    },
  );

  test(
    'last valid offset wins; malformed and oversized offsets remain metadata',
    () {
      final document = parseLrc(
        '[offset:100]\n[00:00.050]A\n'
        '[OFFSET:-250]\n[offset:1000000000001]\n[offset:nope]\n'
        '[offset:${'9' * 10000}]',
      );
      expect(document.offsetMs, -250);
      expect(document.cues.single.timeMs, 300);
      expect(document.metadata.length, 5);
      expect(document.metadata.last.value.length, 10000);
      expect(document.isTruncated, isFalse);
    },
  );

  test(
    'positive offsets may legitimately produce negative line/word times',
    () {
      final document = parseLrc('[offset:2000]\n[00:01]<00:01.250>A');
      expect(document.cues.single.timeMs, -1000);
      expect(document.cues.single.words.single.timeMs, -750);
      expect(formatLrcTimestamp(document.cues.single.timeMs!), '-00:01.000');
    },
  );

  test(
    'line order is preserved and timed ordering is stable for equal clocks',
    () {
      final document = parseLrc(
        '[00:03][00:01]first\nplain\n'
        '[00:01]second\n[00:02]third',
      );
      expect(document.cues.map((cue) => cue.text), [
        'first',
        'first',
        'plain',
        'second',
        'third',
      ]);
      expect(document.timedCues.map((cue) => cue.text), [
        'first',
        'second',
        'third',
        'first',
      ]);
      expect(document.timedCues.map((cue) => cue.sourceOrder), [1, 3, 4, 0]);
      expect(document.cues.map((cue) => cue.line), [1, 1, 2, 3, 4]);
    },
  );

  test('keeps empty phrases, adjacent markers and untimed word-clock text', () {
    final document = parseLrc(
      '[00:01]\n[00:02]<00:02><00:03>X\n'
      'before <00:04>after',
    );
    expect(document.cues[0].text, '');
    expect(document.cues[0].words.single.timeMs, isNull);
    expect(document.cues[1].text, 'X');
    expect(document.cues[1].words.single.timeMs, 3000);
    expect(document.cues[2].timeMs, isNull);
    expect(document.cues[2].text, 'before after');
    expect(document.cues[2].words.map((word) => word.timeMs), [null, 4000]);
  });

  test(
    'extreme valid clocks remain exact and within the documented safe bound',
    () {
      final document = parseLrc(
        '[offset:-1000000000000]\n'
        '[-99999999:59.999][99999999:59.999]<99999999:59.999>X',
      );
      expect(document.cues[1].words.single.timeMs, 18999999999997);
      expect(
        document.cues[1].words.single.timeMs!,
        lessThan(lrcMaxTimelineMilliseconds),
      );
      expect(
        formatLrcTimestamp(document.cues[1].words.single.timeMs!),
        '316666666:39.997',
      );
    },
  );

  test(
    'source cap returns an explicit incomplete result and the exact source',
    () {
      final source = 'x' * (lrcMaxSourceCodeUnits + 1);
      final document = parseLrc(source);
      expect(document.isTruncated, isTrue);
      expect(document.limitReason, LrcLimitReason.sourceSize);
      expect(document.source, same(source));
      expect(document.cues, isEmpty);
      expect(document.metadata, isEmpty);
      final exact = parseLrc('x' * lrcMaxSourceCodeUnits);
      expect(exact.isTruncated, isFalse);
      expect(exact.cues.single.text.length, lrcMaxSourceCodeUnits);
    },
  );

  test(
    'source cap does not cut a surrogate pair into a falsely complete model',
    () {
      final source = '${'x' * (lrcMaxSourceCodeUnits - 1)}🌊';
      final document = parseLrc(source);
      expect(document.limitReason, LrcLimitReason.sourceSize);
      expect(document.source.endsWith('🌊'), isTrue);
      expect(document.cues, isEmpty);
    },
  );

  test('cue expansion is bounded before allocating repeated output', () {
    final exact = parseLrc('${'[00:01]' * lrcMaxCues}one');
    expect(exact.isTruncated, isFalse);
    expect(exact.cues.length, lrcMaxCues);
    final overflow = parseLrc('${'[00:01]' * (lrcMaxCues + 1)}one');
    expect(overflow.limitReason, LrcLimitReason.cueCount);
    expect(overflow.cues, isEmpty);
  });

  test(
    'line scanning stops at cue cap without eagerly splitting all lines',
    () {
      final document = parseLrc('x\n' * (lrcMaxCues + 1));
      expect(document.limitReason, LrcLimitReason.cueCount);
      expect(document.cues.length, lrcMaxCues);
      expect(document.cues.last.line, lrcMaxCues);
    },
  );

  test('metadata has its own cap even when no lyric cues are emitted', () {
    final source = List.filled(lrcMaxMetadata + 1, '[x:v]').join('\n');
    final document = parseLrc(source);
    expect(document.limitReason, LrcLimitReason.metadataCount);
    expect(document.metadata.length, lrcMaxMetadata);
    expect(document.cues, isEmpty);
    expect(document.source, source);
  });

  test('individual word segments are capped before excess allocation', () {
    final exact = parseLrc('[00:01]${'<00:01>x' * lrcMaxExpandedWords}');
    expect(exact.isTruncated, isFalse);
    expect(exact.cues.single.words.length, lrcMaxExpandedWords);
    final over = parseLrc('[00:01]${'<00:01>x' * (lrcMaxExpandedWords + 1)}');
    expect(over.limitReason, LrcLimitReason.wordCount);
    expect(over.cues, isEmpty);
  });

  test(
    'repeated cues multiply word budget before allocating expanded words',
    () {
      final exact = parseLrc('${'[00:01]' * 100}${'<00:01>x' * 500}');
      expect(exact.isTruncated, isFalse);
      expect(
        exact.cues.fold<int>(0, (sum, cue) => sum + cue.words.length),
        lrcMaxExpandedWords,
      );
      final over = parseLrc('${'[00:01]' * 100}${'<00:01>x' * 501}');
      expect(over.limitReason, LrcLimitReason.wordCount);
      expect(over.cues, isEmpty);
      // A naive port would attempt 500 million output word objects here.
      final adversarial = parseLrc(
        '${'[00:01]' * lrcMaxCues}${'<00:01>x' * lrcMaxExpandedWords}',
      );
      expect(adversarial.limitReason, LrcLimitReason.wordCount);
      expect(adversarial.cues, isEmpty);
    },
  );

  test('partial output is disclosed if a later line exceeds a bound', () {
    final document = parseLrc(
      'plain\n'
      '${'[00:01]' * lrcMaxCues}too many\n[offset:123]',
    );
    expect(document.limitReason, LrcLimitReason.cueCount);
    expect(document.cues.single.text, 'plain');
    expect(document.offsetMs, 0);
    expect(document.source, contains('[offset:123]'));
  });

  test('all model lists are immutable', () {
    final document = parseLrc('[ti:Example]\n[00:01]<00:01>Hello');
    expect(() => document.metadata.clear(), throwsUnsupportedError);
    expect(() => document.cues.clear(), throwsUnsupportedError);
    expect(() => document.timedCues.clear(), throwsUnsupportedError);
    expect(() => document.cues.single.words.clear(), throwsUnsupportedError);
  });
}
