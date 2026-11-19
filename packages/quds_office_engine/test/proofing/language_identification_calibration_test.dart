import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// Answers from a fixed table; records every call.
final class _FakeIdentifier implements LanguageIdentifier {
  _FakeIdentifier(this.answers, {this.available = true, this.fail = false});

  final Map<String, List<LanguageGuess>> answers;
  final bool available;
  final bool fail;
  final calls = <List<String>>[];

  @override
  bool get isAvailable => available;

  @override
  Future<List<List<LanguageGuess>>> identify(List<String> texts) async {
    calls.add(texts);
    if (fail) throw StateError('worker stopped');
    return [for (final t in texts) answers[t.trim()] ?? const []];
  }
}

const _german = 'Der Bericht wurde gestern veröffentlicht.';
const _english = 'The report was published yesterday afternoon.';
const _arabic = 'وقد نشر التقرير أمس وأثار ضجة كبيرة.';
const _persian = 'این گزارش دیروز منتشر شد و سر و صدا کرد.';

ScriptSegment _segment(TextScript script, int letters) =>
    ScriptSegment(0, letters, script, letters);

DetectedSegment _detected(
  String? language, {
  List<LanguageGuess> guesses = const [],
  bool byScript = false,
}) => DetectedSegment(
  start: 0,
  end: 10,
  script: TextScript.latin,
  language: language,
  confidence: guesses.isEmpty ? 1 : guesses.first.confidence,
  byScript: byScript,
  guesses: guesses,
);

void main() {
  group('scriptSegments', () {
    test('splits scripts and attaches neutral characters', () {
      const text = '«Hallo Welt», 2024: مرحبا بالعالم! שלום';
      final segments = scriptSegments(text);
      expect(
        [for (final s in segments) s.script],
        [TextScript.latin, TextScript.arabic, TextScript.hebrew],
      );
      expect(segments.first.start, 0, reason: 'leading « joins the first run');
      expect(text.substring(0, segments.first.end), '«Hallo Welt», 2024: ');
      expect(
        text.substring(segments[1].start, segments[1].end),
        'مرحبا بالعالم! ',
      );
      expect(segments.last.end, text.length);
      expect(segments.first.letters, 9);
      for (var i = 1; i < segments.length; i++) {
        expect(segments[i].start, segments[i - 1].end);
      }
    });

    test('text without letters has no segments', () {
      expect(scriptSegments(''), isEmpty);
      expect(scriptSegments(' 12,5 % – !'), isEmpty);
    });

    test('marks and astral characters keep UTF-16 offsets', () {
      const text = 'Café 😀 Привет';
      final segments = scriptSegments(text);
      expect(
        [for (final s in segments) s.script],
        [TextScript.latin, TextScript.cyrillic],
      );
      expect(segments.last.end, text.length);
      expect(text.substring(segments.last.start), 'Привет');
    });
  });

  group('LanguageDetectionPolicy', () {
    const policy = LanguageDetectionPolicy();

    test('Arabic script is ar unless confidently fa/ur/ps/ku/sd/ug', () {
      final short = _segment(TextScript.arabic, 5);
      expect(policy.needsClassifier(short), isFalse);
      final decided = policy.decide(short, const []);
      expect(decided.language, 'ar');
      expect(decided.byScript, isTrue);

      final long = _segment(TextScript.arabic, 40);
      expect(
        policy.decide(long, const [LanguageGuess('fa', 0.99)]).language,
        'fa',
      );
      expect(
        policy.decide(long, const [LanguageGuess('ur', 0.96)]).language,
        'ur',
      );
      expect(
        policy.decide(long, const [LanguageGuess('fa', 0.80)]).language,
        'ar',
        reason: 'not confident',
      );
      expect(
        policy.decide(long, const [LanguageGuess('en', 0.99)]).language,
        'ar',
        reason: 'not an Arabic-script language',
      );
      expect(
        policy.decide(_segment(TextScript.arabic, 10), const [
          LanguageGuess('fa', 0.99),
        ]).language,
        'ar',
        reason: 'too short to trust',
      );
    });

    test('Hebrew script is he unless confidently yi', () {
      final long = _segment(TextScript.hebrew, 30);
      expect(policy.decide(long, const []).language, 'he');
      expect(
        policy.decide(long, const [LanguageGuess('yi', 0.97)]).language,
        'yi',
      );
      expect(
        policy.decide(long, const [LanguageGuess('he', 0.99)]).language,
        'he',
      );
    });

    test('Latin needs enough letters, confidence and a Latin language', () {
      expect(policy.needsClassifier(_segment(TextScript.latin, 19)), isFalse);
      expect(
        policy.decide(_segment(TextScript.latin, 19), const [
          LanguageGuess('de', 0.999),
        ]).language,
        isNull,
      );
      final long = _segment(TextScript.latin, 60);
      expect(policy.needsClassifier(long), isTrue);
      expect(
        policy.decide(long, const [LanguageGuess('de', 0.97)]).language,
        'de',
      );
      expect(
        policy.decide(long, const [LanguageGuess('la', 0.94)]).language,
        isNull,
      );
      expect(
        policy.decide(long, const [LanguageGuess('ru', 0.99)]).language,
        isNull,
        reason: 'Cyrillic language for Latin text',
      );
      expect(
        policy.decide(long, const [LanguageGuess('zh-Latn', 0.99)]).language,
        'zh-Latn',
      );
      expect(policy.decide(long, const []).language, isNull);
    });

    test('custom thresholds apply', () {
      const loose = LanguageDetectionPolicy(minLetters: 5, minConfidence: 0.5);
      expect(
        loose.decide(_segment(TextScript.latin, 6), const [
          LanguageGuess('fr', 0.6),
        ]).language,
        'fr',
      );
    });
  });

  group('ParagraphLanguageDetector', () {
    test(
      'one classifier call for all uncached segments, then cached',
      () async {
        final fake = _FakeIdentifier({
          _german: const [LanguageGuess('de', 0.999)],
          _english: const [
            LanguageGuess('en', 0.99),
            LanguageGuess('de', 0.001),
          ],
          _arabic: const [LanguageGuess('ar', 0.998)],
        });
        final detector = ParagraphLanguageDetector(fake);
        final mixed = '$_german $_arabic';
        final results = await detector.detectAll([_english, mixed, _english]);
        expect(fake.calls, hasLength(1));
        expect(
          fake.calls.single,
          hasLength(3),
          reason: 'distinct segments only',
        );
        expect(results[0].segments.single.language, 'en');
        expect([for (final s in results[1].segments) s.language], ['de', 'ar']);
        expect(results[1].languagesByScript, {
          TextScript.latin: {'de'},
          TextScript.arabic: {'ar'},
        });
        expect(results[1].segmentAt(0)!.language, 'de');
        expect(results[1].segmentAt(mixed.length - 1)!.language, 'ar');
        expect(identical(detector.cached(mixed), results[1]), isTrue);
        await detector.detect(mixed);
        expect(fake.calls, hasLength(1));
      },
    );

    test('concurrent requests share one classifier call', () async {
      final fake = _FakeIdentifier({
        _german: const [LanguageGuess('de', 0.999)],
      });
      final detector = ParagraphLanguageDetector(fake);
      final both = await Future.wait([
        detector.detect(_german),
        detector.detect(_german),
      ]);
      expect(fake.calls, hasLength(1));
      expect(identical(both[0], both[1]), isTrue);
    });

    test('without a classifier only the script decides', () async {
      for (final fake in [
        _FakeIdentifier(const {}, available: false),
        _FakeIdentifier(const {}, fail: true),
      ]) {
        final detector = ParagraphLanguageDetector(fake);
        final result = await detector.detect('$_german $_persian');
        expect([for (final s in result.segments) s.language], [null, 'ar']);
      }
      final idle = await ParagraphLanguageDetector(
        const UnavailableLanguageIdentifier(),
      ).detect('שלום עולם');
      expect(idle.segments.single.language, 'he');
    });

    test('a confident Persian paragraph is fa', () async {
      final detector = ParagraphLanguageDetector(
        _FakeIdentifier({
          _persian: const [LanguageGuess('fa', 0.9999)],
        }),
      );
      expect((await detector.detect(_persian)).segments.single.language, 'fa');
    });

    test('the cache is bounded', () async {
      final detector = ParagraphLanguageDetector(
        _FakeIdentifier(const {}),
        cacheSize: 2,
      );
      await detector.detectAll(['a', 'b', 'c']);
      expect(detector.cached('a'), isNull);
      expect(detector.cached('c'), isNotNull);
    });
  });

  group('resolveDetectedLanguage', () {
    final german = _detected(
      'de',
      guesses: const [LanguageGuess('de', 0.99), LanguageGuess('en', 0.002)],
    );

    test('an explicit language wins', () {
      expect(
        resolveDetectedLanguage(
          current: 'fr-FR',
          currentIsDefault: false,
          detection: german,
        ),
        'fr-FR',
      );
    });

    test('a default yields to a confident detection', () {
      expect(
        resolveDetectedLanguage(
          current: 'en-US',
          currentIsDefault: true,
          detection: german,
        ),
        'de-DE',
      );
      expect(
        resolveDetectedLanguage(
          current: null,
          currentIsDefault: true,
          detection: german,
        ),
        'de-DE',
      );
    });

    test('the same primary language keeps its region', () {
      expect(
        resolveDetectedLanguage(
          current: 'de-CH',
          currentIsDefault: true,
          detection: german,
        ),
        'de-CH',
      );
    });

    test('a default the classifier still considers is kept', () {
      final close = _detected(
        'lb',
        guesses: const [LanguageGuess('lb', 0.96), LanguageGuess('de', 0.03)],
      );
      expect(
        resolveDetectedLanguage(
          current: 'de-DE',
          currentIsDefault: true,
          detection: close,
        ),
        'de-DE',
      );
      expect(
        resolveDetectedLanguage(
          current: 'de-DE',
          currentIsDefault: true,
          detection: close,
          keepDefaultConfidence: 0.05,
        ),
        'lb',
      );
    });

    test('no detection keeps the current language', () {
      expect(
        resolveDetectedLanguage(
          current: 'en-US',
          currentIsDefault: true,
          detection: _detected(null),
        ),
        'en-US',
      );
      expect(
        resolveDetectedLanguage(
          current: 'en-US',
          currentIsDefault: true,
          detection: null,
        ),
        'en-US',
      );
    });

    test('a script decision overrides a Latin default', () {
      expect(
        resolveDetectedLanguage(
          current: 'en-US',
          currentIsDefault: true,
          detection: _detected('ar', byScript: true),
        ),
        'ar',
      );
    });
  });

  group('wordRunLanguageSlot', () {
    WmlParagraph paragraph(WmlRun run, {String? language}) =>
        WmlParagraph(inlines: [run])..properties.proofingLanguage = language;

    test('unset and docDefault values are defaults; others explicit', () {
      final unset = WmlRun(text: 'Text');
      expect(
        wordRunLanguageSlot(
          unset,
          paragraph(unset),
          complexScript: false,
          documentLanguage: 'en-US',
        ),
        (language: null, isDefault: true),
      );
      final asDefault = WmlRun(text: 'Text')
        ..properties.proofingLanguage = 'en-us';
      expect(
        wordRunLanguageSlot(
          asDefault,
          paragraph(asDefault),
          complexScript: false,
          documentLanguage: 'en-US',
        ).isDefault,
        isTrue,
      );
      final explicit = WmlRun(text: 'Text')
        ..properties.proofingLanguage = 'fr-FR';
      expect(
        wordRunLanguageSlot(
          explicit,
          paragraph(explicit),
          complexScript: false,
          documentLanguage: 'en-US',
        ),
        (language: 'fr-FR', isDefault: false),
      );
      final inherited = WmlRun(text: 'Text');
      expect(
        wordRunLanguageSlot(
          inherited,
          paragraph(inherited, language: 'it-IT'),
          complexScript: false,
          documentLanguage: 'en-US',
        ),
        (language: 'it-IT', isDefault: false),
      );
    });

    test('the complex-script slot reads w:bidi only', () {
      final run = WmlRun(text: 'نص')
        ..properties.proofingLanguage = 'fr-FR'
        ..properties.complexScriptLanguage = 'ar-SA';
      expect(
        wordRunLanguageSlot(
          run,
          paragraph(run),
          complexScript: true,
          documentComplexScriptLanguage: 'ar-SA',
        ),
        (language: 'ar-SA', isDefault: true),
      );
      final unset = WmlRun(text: 'نص')..properties.proofingLanguage = 'fr-FR';
      expect(
        wordRunLanguageSlot(unset, paragraph(unset), complexScript: true),
        (language: null, isDefault: true),
      );
      final explicit = WmlRun(text: 'نص')
        ..properties.complexScriptLanguage = 'fa-IR';
      expect(
        wordRunLanguageSlot(
          explicit,
          paragraph(explicit),
          complexScript: true,
          documentComplexScriptLanguage: 'ar-SA',
        ).isDefault,
        isFalse,
      );
    });
  });
}
