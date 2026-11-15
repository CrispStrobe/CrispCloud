import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

ZoteroTextSpan _at(ZoteroFormattedText result, String text) {
  final index = result.plainText.indexOf(text);
  expect(index, greaterThanOrEqualTo(0));
  var offset = 0;
  for (final span in result.spans) {
    if (index < offset + span.text.length) return span;
    offset += span.text.length;
  }
  throw StateError('Missing result span');
}

void main() {
  test(
    'nested inline emphasis becomes independent supported Word properties',
    () {
      final result = ZoteroFormattedText.fromHtml(
        'A <i>italic <b>both</b> still</i> plain <u>under</u> '
        '<s>struck</s> H<sub>2</sub>O x<sup>3</sup>',
      );
      expect(result.plainText, 'A italic both still plain under struck H2O x3');
      expect(_at(result, 'italic').italic, isTrue);
      expect(_at(result, 'both').italic, isTrue);
      expect(_at(result, 'both').bold, isTrue);
      expect(_at(result, 'still').bold, isFalse);
      expect(_at(result, 'plain').italic, isFalse);
      expect(_at(result, 'under').underline, isTrue);
      expect(_at(result, 'struck').strike, isTrue);
      expect(_at(result, '2').verticalAlign, WmlVertAlign.subscript);
      expect(_at(result, '3').verticalAlign, WmlVertAlign.superscript);
      expect(result.unsupportedFormatting, isEmpty);
    },
  );

  test('explicit CSS resets and closing tags restore inherited emphasis', () {
    final result = ZoteroFormattedText.fromHtml(
      '<b><i>outer<span style="font-weight:normal; font-style:normal">reset</span>'
      'again</i></b><span style="font-weight:700; font-style:oblique; '
      'text-decoration: underline line-through; vertical-align:super">styled</span>',
    );
    expect(result.plainText, 'outerresetagainstyled');
    expect(_at(result, 'outer').bold, isTrue);
    expect(_at(result, 'reset').bold, isFalse);
    expect(_at(result, 'reset').italic, isFalse);
    expect(_at(result, 'again').italic, isTrue);
    final styled = _at(result, 'styled');
    expect(
      styled.bold && styled.italic && styled.underline && styled.strike,
      isTrue,
    );
    expect(styled.verticalAlign, WmlVertAlign.superscript);
  });

  test(
    'numeric margins stay beside entries while blocks retain line breaks',
    () {
      final result = ZoteroFormattedText.fromHtml('''
<div class="csl-bib-body">
  <div class="csl-entry"><div class="csl-left-margin">[1]</div><div class="csl-right-inline">Alpha <i>Book</i>.</div></div>
  <div class="csl-entry"><div class="csl-left-margin">[2]</div><div class="csl-right-inline">Beta.</div></div>
  <div class="csl-entry"><div class="csl-block">Gamma.</div><div class="csl-block">Details.</div></div>
</div>''');
      expect(result.plainText, '[1] Alpha Book.\n[2] Beta.\nGamma.\nDetails.');
      expect(_at(result, 'Book').italic, isTrue);
      expect(result.unsupportedFormatting, contains('paragraph layout'));
    },
  );

  test(
    'inline whitespace is collapsed without adding space between adjacent tags',
    () {
      final result = ZoteroFormattedText.fromHtml(
        '  Alpha\n  <i>beta</i><b>gamma</b>\t delta<br>next<br/><br />last  ',
      );
      expect(result.plainText, 'Alpha betagamma delta\nnext\n\nlast');
      expect(ZoteroFormattedText.fromHtml('a<br/>').plainText, 'a\n');
    },
  );

  test(
    'entities preserve no-break spaces Unicode and literal angle brackets',
    () {
      final result = ZoteroFormattedText.fromHtml(
        'A&nbsp;&amp; B &lt;i&gt; &#945; &#x1F4DA; &ndash; &thinsp; &hellip;',
      );
      expect(result.plainText, 'A\u00a0& B <i> α 📚 – \u2009 …');
      expect(result.spans.every((span) => !span.italic), isTrue);
    },
  );

  test(
    'CDATA literals and comments are not rewritten by entity normalization',
    () {
      final result = ZoteroFormattedText.fromHtml(
        '<i><![CDATA[A&amp; <br> B]]></i><!-- ignored &unknown; <br> --> end',
      );
      expect(result.plainText, 'A&amp; <br> B end');
      expect(_at(result, 'A&amp;').italic, isTrue);
      expect(
        () => ZoteroFormattedText.fromHtml('<!-- invalid -- comment -->'),
        throwsFormatException,
      );
      expect(
        () => ZoteroFormattedText.fromHtml('unterminated <!--' * 10000),
        throwsFormatException,
      );
    },
  );

  test(
    'resources active markup and attributes cannot become document objects',
    () {
      final result = ZoteroFormattedText.fromHtml(
        'Before<script>bad()</script><style>body {color:red}</style>'
        '<iframe src="https://invalid.test">frame</iframe>'
        '<object data="https://invalid.test">object</object>'
        '<svg><text>vector</text></svg>'
        '<img src="https://invalid.test" onerror="bad()"/>'
        '<a href="javascript:bad()" onclick="bad()">source</a>After',
      );
      expect(result.plainText, 'BeforesourceAfter');
      expect(result.unsupportedFormatting, contains('embedded content'));
      final runs = result.toRuns();
      expect(
        runs.every((run) => run.hyperlink == null && run.inlineVisual == null),
        isTrue,
      );
      expect(runs.every((run) => run.fieldInstruction == null), isTrue);
    },
  );

  test(
    'unsupported small caps and layout are reported without changing letters',
    () {
      final result = ZoteroFormattedText.fromHtml(
        '<div style="line-height:2; text-indent:-1em">'
        '<span style="font-variant:small-caps; color:red">Smith</span></div>',
      );
      expect(result.plainText, 'Smith');
      expect(
        result.unsupportedFormatting,
        containsAll([
          'small caps',
          'paragraph layout',
          'unsupported inline style',
        ]),
      );
      expect(result.toRuns().single.properties.color, '000000');
      expect(
        ZoteroFormattedText.fromHtml(
          '<small>Small</small>',
        ).unsupportedFormatting,
        contains('unsupported inline style'),
      );
    },
  );

  test(
    'result snapshots are immutable and fresh runs do not alias them or the base font',
    () {
      final result = ZoteroFormattedText.fromHtml('<i>Title</i> plain');
      expect(() => result.spans.clear(), throwsUnsupportedError);
      expect(
        () => result.unsupportedFormatting.add('other'),
        throwsUnsupportedError,
      );
      final base = WmlRunProps(
        asciiFont: 'Custom',
        fontSizeHalfPoints: 28,
        bold: true,
      );
      final first = result.toRuns(baseProperties: base);
      expect(first.first.properties.asciiFont, 'Custom');
      expect(first.first.properties.fontSizeHalfPoints, 28);
      expect(first.first.properties.bold, isFalse);
      first.first.text = 'changed';
      first.first.properties.asciiFont = 'Changed';
      expect(base.asciiFont, 'Custom');
      expect(base.bold, isTrue);
      expect(result.plainText, 'Title plain');
      expect(result.toRuns().first.text, 'Title');
    },
  );

  for (final markup in <String>[
    '<i>unclosed',
    '<i>x</b>',
    '<span title="x">x</span',
    '<span class="a" class="b">x</span>',
    '<!DOCTYPE x><i>Title</i>',
    '<?processing x?><i>Title</i>',
    '<i>&unknown;</i>',
    '<i>&#0;</i>',
    '<i>&#55296;</i>',
    '<i>\u0000</i>',
  ]) {
    test(
      'malformed or unsupported XHTML fails closed: ${markup.codeUnits}',
      () {
        expect(
          () => ZoteroFormattedText.fromHtml(markup),
          throwsFormatException,
        );
      },
    );
  }

  test('size bound measures UTF-8 bytes and nesting is bounded', () {
    expect(
      () => ZoteroFormattedText.fromHtml('α' * (4 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
    expect(
      () => ZoteroFormattedText.fromHtml('${'<span>' * 65}x${'</span>' * 65}'),
      throwsFormatException,
    );
    expect(
      ZoteroFormattedText.fromHtml(
        '${'<span>' * 64}x${'</span>' * 64}',
      ).plainText,
      'x',
    );
  });

  test('independent element and span bounds prevent tiny-node expansion', () {
    expect(
      () => ZoteroFormattedText.fromHtml('<span/>' * 50000),
      throwsFormatException,
    );
    final text = List<String>.generate(
      10001,
      (i) => i.isEven ? '<b>x</b>' : '<i>x</i>',
    ).join();
    expect(() => ZoteroFormattedText.fromHtml(text), throwsFormatException);
  });
}
