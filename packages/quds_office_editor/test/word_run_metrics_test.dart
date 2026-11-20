import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/editor_word/word_run_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);
  setUp(WordRunMetrics.clearCache);

  test('Word line-fit kerning honors the half-point threshold and cache', () {
    const text = 'AVATAR To';
    final props = WmlRunProps(asciiFont: 'Liberation Serif');
    double width(int? threshold) {
      props.kerningHalfPoints = threshold;
      return _width(
        WordRunMetrics.measure(
          text,
          12,
          props,
          0,
          respectKerningThreshold: true,
        )!,
      );
    }

    final disabled = width(null);
    expect(width(0), closeTo(disabled, .001));
    expect(width(28), closeTo(disabled, .001));
    final enabled = width(1);
    expect(enabled, lessThan(disabled - .1));
    expect(width(24), closeTo(enabled, .001));
    expect(width(25), closeTo(disabled, .001));
    expect(width(null), closeTo(disabled, .001));
  });

  test('run advances retain kerning instead of adding isolated characters', () {
    final props = WmlRunProps(asciiFont: 'Liberation Serif');
    const text = 'AVATAR To';
    final measured = WordRunMetrics.measure(text, 32, props, 0)!;
    final actual = _width(measured);
    expect(actual, closeTo(_paintWidth(text, 32, props, 0), 0.001));
    final isolated = text.runes.fold<double>(
      0,
      (sum, cp) => sum + PaintRunText.advanceOf(cp, 32, props),
    );
    expect(actual, lessThan(isolated - 0.1));
    _expectSourceRanges(text, measured);
  });

  for (final sample in <({String name, String text, int level})>[
    (name: 'ligatures', text: 'office ffi fi fl', level: 0),
    (name: 'Arabic joining and marks', text: 'السَّلَامُ عَلَيْكُمْ', level: 1),
    (name: 'combining marks', text: 'a\u0301 e\u0327\u0301', level: 0),
    (name: 'supplementary and emoji sequences', text: '😀👍🏽👩‍💻', level: 0),
    (name: 'Indic graphemes', text: 'क्षि', level: 0),
    (name: 'trailing spaces', text: 'A V   ', level: 0),
    (name: 'RTL trailing spaces', text: 'مرحبا   ', level: 1),
  ]) {
    test('${sample.name} preserve source and match complete paint width', () {
      final props = WmlRunProps(
        asciiFont: 'Liberation Serif',
        csFont: 'Noto Naskh Arabic',
      );
      final measured = WordRunMetrics.measure(
        sample.text,
        20,
        props,
        sample.level,
      );
      expect(measured, isNotNull);
      _expectSourceRanges(sample.text, measured!);
      expect(
        _width(measured),
        closeTo(_paintWidth(sample.text, 20, props, sample.level), 0.001),
      );
    });
  }

  test('different face styles and sizes use independent shaped metrics', () {
    const text = 'A variable width sample';
    final regular = WmlRunProps(asciiFont: 'Liberation Serif');
    final boldItalic = WmlRunProps(
      asciiFont: 'Liberation Serif',
      bold: true,
      italic: true,
    );
    final a = WordRunMetrics.measure(text, 16, regular, 0)!;
    final b = WordRunMetrics.measure(text, 16, boldItalic, 0)!;
    final c = WordRunMetrics.measure(text, 24, regular, 0)!;
    expect(identical(a, b), isFalse);
    expect(_width(b), closeTo(_paintWidth(text, 16, boldItalic, 0), 0.001));
    expect(_width(c), closeTo(_paintWidth(text, 24, regular, 0), 0.001));
    expect((_width(a) - _width(b)).abs(), greaterThan(0.1));
    expect(_width(c), greaterThan(_width(a)));
  });

  test(
    'font registration invalidates cached values and earlier fallback',
    () async {
      const text = 'iiiiiiiiWW';
      final regular = WmlRunProps(asciiFont: 'Arial');
      final lateFont = WmlRunProps(asciiFont: 'Run Metrics Late Mono');
      final before = WordRunMetrics.measure(text, 20, regular, 0)!;
      final fallback = WordRunMetrics.measure(text, 20, lateFont, 0)!;
      expect(
        identical(before, WordRunMetrics.measure(text, 20, regular, 0)),
        isTrue,
      );
      final revision = OfficeHostFonts.registrationRevision;
      final mono = await rootBundle.load(
        'packages/quds_office_editor/fonts/LiberationMono-Regular.ttf',
      );
      await OfficeHostFonts.registerFamily(
        family: 'Run Metrics Late Mono',
        faces: [mono],
      );
      expect(OfficeHostFonts.registrationRevision, greaterThan(revision));
      final after = WordRunMetrics.measure(text, 20, regular, 0)!;
      final loaded = WordRunMetrics.measure(text, 20, lateFont, 0)!;
      expect(identical(before, after), isFalse);
      expect(_width(after), closeTo(_width(before), 0.001));
      expect((_width(loaded) - _width(fallback)).abs(), greaterThan(0.1));
      expect(
        _width(loaded),
        closeTo(_paintWidth(text, 20, lateFont, 0), 0.001),
      );
    },
  );

  test('cache retains immutable values and evicts old runs', () {
    final props = WmlRunProps();
    final first = WordRunMetrics.measure('Original cached run', 12, props, 0)!;
    expect(() => first.clear(), throwsUnsupportedError);
    for (var i = 0; i < 300; i++) {
      expect(
        WordRunMetrics.measure('Different run $i', 12, props, 0),
        isNotNull,
      );
    }
    final again = WordRunMetrics.measure('Original cached run', 12, props, 0)!;
    expect(identical(first, again), isFalse);
    expect(_width(again), closeTo(_width(first), 0.001));
  });

  test(
    'unbounded document font names are measured without retaining cache keys',
    () {
      final props = WmlRunProps(asciiFont: 'Missing ${'x' * 300}');
      final first = WordRunMetrics.measure('Text', 12, props, 0)!;
      final second = WordRunMetrics.measure('Text', 12, props, 0)!;
      expect(identical(first, second), isFalse);
      expect(_width(first), closeTo(_width(second), 0.001));
    },
  );

  test(
    'layout controls and malformed input decline without invented metrics',
    () {
      final props = WmlRunProps();
      expect(WordRunMetrics.measure('', 12, props, 0), isEmpty);
      for (final text in ['A\tB', 'A\nB', 'A\r\nB', 'A\u2028B']) {
        expect(WordRunMetrics.measure(text, 12, props, 0), isNull);
      }
      for (final text in [
        String.fromCharCode(0xD800),
        String.fromCharCode(0xDC00),
      ]) {
        expect(WordRunMetrics.measure(text, 12, props, 0), isNull);
      }
      for (final size in [double.nan, double.infinity, -1.0, 0.0]) {
        expect(WordRunMetrics.measure('Text', size, props, 0), isNull);
      }
    },
  );
}

double _width(List<WordMeasuredCluster> clusters) =>
    clusters.fold(0.0, (sum, cluster) => sum + cluster.advance);

void _expectSourceRanges(String text, List<WordMeasuredCluster> measured) {
  final boundaries = <int>{
    0,
    for (final cluster in GraphemeClusters.segment(text)) cluster.end,
  };
  var next = 0;
  final restored = StringBuffer();
  for (final cluster in measured) {
    expect(cluster.start, next);
    expect(cluster.end, greaterThan(cluster.start));
    expect(boundaries, containsAll([cluster.start, cluster.end]));
    expect(cluster.advance.isFinite, isTrue);
    expect(cluster.advance, greaterThanOrEqualTo(0));
    restored.write(text.substring(cluster.start, cluster.end));
    next = cluster.end;
  }
  expect(next, text.length);
  expect(restored.toString(), text);
}

double _paintWidth(String text, double size, WmlRunProps props, int level) {
  final requested = OfficeTypeface.familyForRun(props, text.runes.first);
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        fontFamily: PaintRunText.familyFor(text: text, runFamily: requested),
        fontFamilyFallback: PaintRunText.fallbacksFor(
          text,
          runFamily: requested,
        ),
        fontWeight: props.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: props.italic ? FontStyle.italic : FontStyle.normal,
        height: 1.0,
      ),
    ),
    textDirection: PaintRunText.directionFor(bidiLevel: level, text: text),
    maxLines: 1,
  );
  try {
    painter.layout();
    return painter.width;
  } finally {
    painter.dispose();
  }
}
