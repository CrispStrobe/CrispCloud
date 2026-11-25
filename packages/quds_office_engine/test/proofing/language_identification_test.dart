import 'dart:async';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

final class _Identifier implements LanguageIdentifier {
  _Identifier(this.answer);

  final Future<List<List<LanguageGuess>>> Function(List<String>) answer;
  final calls = <List<String>>[];
  bool available = true;

  @override
  bool get isAvailable => available;

  @override
  Future<List<List<LanguageGuess>>> identify(List<String> texts) {
    calls.add(List.of(texts));
    return answer(texts);
  }
}

const _longLatin = 'This paragraph contains enough letters to classify.';

void main() {
  test('script segments cover UTF-16 text without splitting scalar values', () {
    const text = '🙂 Aé\u0301 ١، ع\u{1EE00}؟ א\u05B0.Ж Ω 漢';
    final segments = scriptSegments(text);
    expect(segments.map((segment) => segment.script), [
      TextScript.latin,
      TextScript.arabic,
      TextScript.hebrew,
      TextScript.cyrillic,
      TextScript.greek,
      TextScript.other,
    ]);
    expect(segments.map((segment) => segment.letters), [2, 2, 1, 1, 1, 1]);
    expect(
      segments.map((segment) => text.substring(segment.start, segment.end)),
      ['🙂 Aé\u0301 ١، ', 'ع\u{1EE00}؟ ', 'א\u05B0.', 'Ж ', 'Ω ', '漢'],
    );
    expect(segments.first.start, 0);
    expect(segments.last.end, text.length);
    for (var i = 1; i < segments.length; i++) {
      expect(segments[i].start, segments[i - 1].end);
    }
  });

  test('returning to a script resets the letter count and keeps neutrals', () {
    const first = '🙂ab٢→';
    const middle = 'ع\u064e…🙂';
    const last = 'Aéz!🙂';
    const text = '$first$middle$last';
    final middleEnd = first.length + middle.length;
    expect(
      scriptSegments(text).map((s) => (s.start, s.end, s.script, s.letters)),
      [
        (0, first.length, TextScript.latin, 2),
        (first.length, middleEnd, TextScript.arabic, 1),
        (middleEnd, text.length, TextScript.latin, 3),
      ],
    );
  });

  test('digits, punctuation, marks and emoji alone do not create scripts', () {
    for (final text in ['', '١۲1，؟🙂\u064e\u05b0', '\u200d\u202e']) {
      expect(scriptSegments(text), isEmpty, reason: text);
    }
  });

  test('letter preflight agrees with script runs for Unicode text', () {
    for (final (text, hasLetters) in [
      ('', false),
      ('🙂١!\u0301\u200d', false),
      ('\ud800?\udcff', false),
      ('123 A', true),
      ('\u0301é', true),
      ('؟ع', true),
      ('\u{10400}', true),
      ('漢', true),
    ]) {
      expect(hasScriptLetters(text), hasLetters, reason: text);
      expect(scriptSegments(text).isNotEmpty, hasLetters, reason: text);
    }
  });

  test('language script honors normalized explicit script subtags', () {
    for (final entry in {
      'EN_us': TextScript.latin,
      ' SR ': TextScript.cyrillic,
      'sr-Latn': TextScript.latin,
      'JA-lAtN': TextScript.latin,
      'az-Arab': TextScript.arabic,
      'he-Hebr': TextScript.hebrew,
      'en-Cyrl': TextScript.cyrillic,
      'xx-Grek': TextScript.greek,
      'zh-Hant': TextScript.other,
      'unknown': TextScript.latin,
    }.entries) {
      expect(languageScript(entry.key), entry.value, reason: entry.key);
    }
  });

  test('Latin detection needs letters, confidence and a matching script', () {
    const policy = LanguageDetectionPolicy();
    const long = ScriptSegment(0, 20, TextScript.latin, 20);
    const short = ScriptSegment(0, 19, TextScript.latin, 19);
    expect(policy.needsClassifier(short), isFalse);
    expect(policy.needsClassifier(long), isTrue);
    expect(
      policy.decide(long, const [LanguageGuess('fr', 0.95)]).language,
      'fr',
    );
    expect(
      policy.decide(long, const [LanguageGuess('fr', 0.949)]).language,
      isNull,
    );
    expect(
      policy.decide(short, const [LanguageGuess('fr', 1)]).language,
      isNull,
    );
    expect(
      policy.decide(long, const [LanguageGuess('ar', 1)]).language,
      isNull,
    );
    expect(
      policy.decide(long, const [LanguageGuess('ru-Latn', 1)]).language,
      'ru-Latn',
    );
  });

  test('short complex-script text has a deterministic script fallback', () {
    const policy = LanguageDetectionPolicy();
    for (final (script, fallback) in [
      (TextScript.arabic, 'ar'),
      (TextScript.hebrew, 'he'),
    ]) {
      final segment = ScriptSegment(0, 2, script, 2);
      final result = policy.decide(segment, const []);
      expect(policy.needsClassifier(segment), isFalse);
      expect(result.language, fallback);
      expect(result.byScript, isTrue);
      expect(result.confidence, 1);
    }
  });

  test('complex-script alternatives require a long confident matching run', () {
    const policy = LanguageDetectionPolicy();
    const arabic = ScriptSegment(0, 20, TextScript.arabic, 20);
    const hebrew = ScriptSegment(0, 20, TextScript.hebrew, 20);
    final persian = policy.decide(arabic, const [LanguageGuess('fa', 0.95)]);
    expect(persian.language, 'fa');
    expect(persian.byScript, isFalse);
    expect(
      policy.decide(arabic, const [LanguageGuess('fa', 0.949)]).language,
      'ar',
    );
    expect(
      policy.decide(arabic, const [LanguageGuess('en', 1)]).language,
      'ar',
    );
    expect(
      policy.decide(hebrew, const [LanguageGuess('yi', 0.95)]).language,
      'yi',
    );
    expect(
      policy.decide(hebrew, const [LanguageGuess('fa', 1)]).language,
      'he',
    );
    expect(
      policy.decide(const ScriptSegment(0, 2, TextScript.arabic, 2), const [
        LanguageGuess('fa', 1),
      ]).language,
      'ar',
    );
  });

  test('invalid classifier probabilities cannot certify a language', () {
    const policy = LanguageDetectionPolicy();
    for (final confidence in [double.nan, double.infinity, -0.1, 1.1]) {
      expect(
        policy.decide(const ScriptSegment(0, 20, TextScript.latin, 20), [
          LanguageGuess('en', confidence),
        ]).language,
        isNull,
      );
      final fallback = policy.decide(
        const ScriptSegment(0, 20, TextScript.arabic, 20),
        [LanguageGuess('fa', confidence), LanguageGuess('ar', confidence)],
      );
      expect(fallback.language, 'ar');
      expect(fallback.confidence, 1);
    }
  });

  test(
    'batching deduplicates text and skips short or neutral-only inputs',
    () async {
      final identifier = _Identifier(
        (texts) async => [
          for (final _ in texts) const [LanguageGuess('fr', 0.99)],
        ],
      );
      final detector = ParagraphLanguageDetector(identifier);
      const later = '$_longLatin Second paragraph.';
      final result = await detector.detectAll([
        _longLatin,
        'عربي',
        '123🙂',
        later,
        _longLatin,
        later,
      ]);
      expect(identifier.calls, [
        [_longLatin, later],
      ]);
      expect(result[0].segments.single.language, 'fr');
      expect(result[1].segments.single.language, 'ar');
      expect(result[2].segments, isEmpty);
      expect(result[3].text, later);
      expect(result[4], same(result[0]));
      expect(result[5], same(result[3]));
      await detector.detect(_longLatin);
      expect(identifier.calls, hasLength(1));
      expect(result.first.segmentAt(0), same(result.first.segments.single));
      expect(result.first.segmentAt(_longLatin.length), isNull);
      expect(result.first.languagesByScript, {
        TextScript.latin: {'fr'},
      });
    },
  );

  test(
    'concurrent callers share a pending classification and freeze their list',
    () async {
      final pending = Completer<List<List<LanguageGuess>>>();
      final identifier = _Identifier((_) => pending.future);
      final detector = ParagraphLanguageDetector(identifier);
      final inputs = [_longLatin];
      final first = detector.detectAll(inputs);
      final second = detector.detect(_longLatin);
      inputs[0] = 'changed';
      expect(identifier.calls, [
        [_longLatin],
      ]);
      pending.complete(const [
        [LanguageGuess('de', 0.99)],
      ]);
      final original = (await first).single;
      expect(original.text, _longLatin);
      expect(await second, same(original));
    },
  );

  test(
    'cache reset isolates old completions from a new pending request',
    () async {
      final requests = <Completer<List<List<LanguageGuess>>>>[];
      final identifier = _Identifier((_) {
        final request = Completer<List<List<LanguageGuess>>>();
        requests.add(request);
        return request.future;
      });
      final detector = ParagraphLanguageDetector(identifier);
      final old = detector.detect(_longLatin);
      detector.clearCache();
      final current = detector.detect(_longLatin);
      expect(requests, hasLength(2));
      requests.first.complete(const [
        [LanguageGuess('de', 0.99)],
      ]);
      expect((await old).segments.single.language, 'de');
      expect(detector.cached(_longLatin), isNull);
      final duplicate = detector.detect(_longLatin);
      expect(requests, hasLength(2));
      requests.last.complete(const [
        [LanguageGuess('fr', 0.99)],
      ]);
      expect((await current).segments.single.language, 'fr');
      expect((await duplicate).segments.single.language, 'fr');
      expect(detector.cached(_longLatin)!.segments.single.language, 'fr');
    },
  );

  test(
    'unavailable, failed and malformed classifiers retain script fallback',
    () async {
      for (final identifier in [
        const UnavailableLanguageIdentifier(),
        _Identifier((_) async => throw StateError('failed')),
        _Identifier((_) async => const []),
      ]) {
        final result = await ParagraphLanguageDetector(
          identifier,
        ).detectAll([_longLatin, 'هذا نص عربي طويل بما يكفي لاختبار التصنيف']);
        expect(result.first.segments.single.language, isNull);
        expect(result.last.segments.single.language, 'ar');
      }
    },
  );

  test('explicit cache reset uses a newly available classifier', () async {
    final identifier = _Identifier(
      (texts) async => [
        for (final _ in texts) const [LanguageGuess('en', 0.99)],
      ],
    )..available = false;
    final detector = ParagraphLanguageDetector(identifier);
    expect(
      (await detector.detect(_longLatin)).segments.single.language,
      isNull,
    );
    identifier.available = true;
    detector.clearCache();
    expect((await detector.detect(_longLatin)).segments.single.language, 'en');
    expect(identifier.calls, hasLength(1));
  });

  test('cache eviction retains the most recently accessed texts', () async {
    final identifier = _Identifier(
      (texts) async => [
        for (final _ in texts) const [LanguageGuess('en', 0.99)],
      ],
    );
    final detector = ParagraphLanguageDetector(identifier, cacheSize: 2);
    await detector.detect('${_longLatin}A');
    await detector.detect('${_longLatin}B');
    expect(detector.cached('${_longLatin}A'), isNotNull);
    await detector.detect('${_longLatin}C');
    expect(detector.cached('${_longLatin}A'), isNotNull);
    expect(detector.cached('${_longLatin}B'), isNull);
    expect(detector.cached('${_longLatin}C'), isNotNull);
  });

  test(
    'detected languages yield to explicit values and retain default regions',
    () {
      for (final (current, isDefault, detected, expected)
          in <(String?, bool, String?, String?)>[
            ('en-GB', false, 'fr', 'en-GB'),
            ('en-GB', true, 'en', 'en-GB'),
            ('en-GB', true, 'fr', 'fr'),
            ('de-CH', true, 'de', 'de-CH'),
            (null, true, 'de', 'de-DE'),
            ('ar-SA', true, null, 'ar-SA'),
            (null, true, null, null),
          ]) {
        expect(
          resolveDetectedLanguage(
            current: current,
            currentIsDefault: isDefault,
            detection: detected == null
                ? null
                : DetectedSegment(
                    start: 0,
                    end: 20,
                    script: languageScript(detected),
                    language: detected,
                    confidence: 1,
                    byScript: false,
                  ),
          ),
          expected,
        );
      }
    },
  );

  test(
    'Word language slot inspection preserves independent explicit values',
    () {
      final run = WmlRun(
        text: 'English عربي',
        properties: WmlRunProps(
          proofingLanguage: 'EN_gb',
          complexScriptLanguage: 'fa-IR',
        ),
      );
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps(proofingLanguage: 'fr-FR'),
      );
      expect(
        wordRunLanguageSlot(
          run,
          paragraph,
          complexScript: false,
          documentLanguage: 'en-GB',
        ),
        (language: 'EN_gb', isDefault: true),
      );
      expect(
        wordRunLanguageSlot(
          run,
          paragraph,
          complexScript: true,
          documentComplexScriptLanguage: 'ar-SA',
        ),
        (language: 'fa-IR', isDefault: false),
      );
      run.properties.proofingLanguage = null;
      expect(
        wordRunLanguageSlot(
          run,
          paragraph,
          complexScript: false,
          documentLanguage: 'en-GB',
        ),
        (language: 'fr-FR', isDefault: false),
      );
      run.properties.complexScriptLanguage = null;
      expect(
        wordRunLanguageSlot(
          run,
          paragraph,
          complexScript: true,
          documentComplexScriptLanguage: 'ar-SA',
        ),
        (language: null, isDefault: true),
      );
      expect(paragraph.properties.proofingLanguage, 'fr-FR');
    },
  );

  test(
    'detected Word tags use known regional defaults without hiding other tags',
    () {
      expect(wordLanguageTagForDetected('de'), 'de-DE');
      expect(wordLanguageTagForDetected('ar'), 'ar-SA');
      expect(wordLanguageTagForDetected('he'), 'he-IL');
      expect(wordLanguageTagForDetected('ru-Latn'), 'ru-Latn');
    },
  );
}
