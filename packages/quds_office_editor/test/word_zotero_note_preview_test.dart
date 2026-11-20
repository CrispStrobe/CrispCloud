import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_note_preview.dart';

void main() {
  test(
    'plain scientific comparisons and authored line breaks remain literal',
    () {
      const note = 'A < B and C > D\n2 <= 3; 4 >= 2\n<3 and a final <';
      final preview = ZoteroNotePreview.fromHtml(note);
      expect(preview.plainText, note);
      expect(preview.hasOmittedContent, isFalse);
      expect(
        ZoteroNotePreview.fromHtml('<p>A < B and C > D</p>').plainText,
        'A < B and C > D',
      );
    },
  );

  test(
    'plain notes preserve whitespace and normalize platform line endings',
    () {
      expect(
        ZoteroNotePreview.fromHtml('  first\r\n  second\rlast\t ').plainText,
        '  first\n  second\nlast\t ',
      );
    },
  );

  test('paragraphs headings lists and soft breaks retain their boundaries', () {
    final preview = ZoteroNotePreview.fromHtml(
      '<div data-schema-version="9"><h2>Heading</h2>\n'
      '<p>First <em>paragraph</em><br>second line</p>'
      '<ul><li>One</li><li>Two <strong>items</strong></li></ul>'
      '<blockquote>Quotation</blockquote></div>',
    );
    expect(
      preview.plainText,
      'Heading\nFirst paragraph\nsecond line\nOne\nTwo items\nQuotation',
    );
    expect(preview.hasOmittedContent, isFalse);
  });

  test('explicit repeated and trailing breaks are retained', () {
    expect(
      ZoteroNotePreview.fromHtml('<p>First<br/><br>Second<br /></p>').plainText,
      'First\n\nSecond\n',
    );
  });

  test('leading explicit breaks survive without phantom block boundaries', () {
    expect(
      ZoteroNotePreview.fromHtml('<p><br><br>Text</p>').plainText,
      '\n\nText',
    );
    expect(ZoteroNotePreview.fromHtml('<p><br></p>').plainText, '\n');
    expect(
      ZoteroNotePreview.fromHtml('<div><p></p><p>Text</p></div>').plainText,
      'Text',
    );
  });

  test('table rows and cells remain distinguishable', () {
    expect(
      ZoteroNotePreview.fromHtml(
        '<table><tr><th>Source</th><th>Year</th></tr>'
        '<tr><td>Ali</td><td>2026</td></tr></table>',
      ).plainText,
      'Source\tYear\nAli\t2026',
    );
  });

  test('preformatted text retains indentation, tabs and comparisons', () {
    expect(
      ZoteroNotePreview.fromHtml(
        '<p>Code</p><pre>  if (a &lt; b) {\r\n\treturn 1;\n}</pre><p>End</p>',
      ).plainText,
      'Code\n  if (a < b) {\n\treturn 1;\n}\nEnd',
    );
  });

  test('normal inline whitespace collapses without joining adjacent words', () {
    expect(
      ZoteroNotePreview.fromHtml(
        '<p>  One \n <b> two </b> three\t </p>',
      ).plainText,
      'One two three',
    );
  });

  test('entities decode once and decoded markup stays literal', () {
    expect(
      ZoteroNotePreview.fromHtml(
        '<p>&lt;script&gt;literal&lt;/script&gt; &amp;lt;b&amp;gt; '
        '&AMP; &LT; &GT; &quot;quote&quot; &apos;x&apos;</p>',
      ).plainText,
      '<script>literal</script> &lt;b&gt; & < > "quote" \'x\'',
    );
  });

  test('entities separated by markup never become a newly decoded entity', () {
    expect(
      ZoteroNotePreview.fromHtml(
        '<p>&am<i></i>p; &l<!-- split -->t;</p>',
      ).plainText,
      '&amp; &lt;',
    );
  });

  test('multilingual text and numeric Unicode references are retained', () {
    expect(
      ZoteroNotePreview.fromHtml(
        '<p>القدس 東京 e\u0301 &#233; &#x1F600; &#X03B1; &mdash; &copy; &nbsp;x</p>',
      ).plainText,
      'القدس 東京 e\u0301 é 😀 α — © \u00A0x',
    );
  });

  test(
    'unknown named entities remain visible and invalid numeric ones are replaced',
    () {
      expect(
        ZoteroNotePreview.fromHtml(
          '<p>&unknown; &Alpha; &#0; &#xD800; &#x110000; &#1;</p>',
        ).plainText,
        '&unknown; &Alpha; � � � �',
      );
    },
  );

  test('unquoted HTML void images are omitted and disclosed', () {
    final preview = ZoteroNotePreview.fromHtml(
      '<p>Before<img src=https://invalid.example/image.png alt="Image" '
      'onerror="never()">after</p>',
    );
    expect(preview.plainText, 'Beforeafter');
    expect(preview.hasOmittedContent, isTrue);
  });

  test('quoted attribute brackets do not end a tag or become note text', () {
    final preview = ZoteroNotePreview.fromHtml(
      '<p title="A > B and <img src=bad>" data-marker=example hidden>'
      '<a href="javascript:never()" onclick=never()>Visible label</a></p>',
    );
    expect(preview.plainText, 'Visible label');
    expect(preview.hasOmittedContent, isFalse);
  });

  test('script and style raw text can contain comparisons and invalid XML', () {
    final preview = ZoteroNotePreview.fromHtml(
      '<p>Before</p><ScRiPt>if (a < b && c > d) { "<span>"; }</sCrIpT >'
      '<STYLE>.x > p { content: "<unclosed>"; }</style><p>After</p>',
    );
    expect(preview.plainText, 'Before\nAfter');
    expect(preview.hasOmittedContent, isTrue);
  });

  test('raw-text closing names require an exact tag name', () {
    final preview = ZoteroNotePreview.fromHtml(
      'Before<script>ignored</scripture>still ignored</script>After',
    );
    expect(preview.plainText, 'BeforeAfter');
    expect(preview.hasOmittedContent, isTrue);
  });

  test('embedded and hidden container descendants are omitted together', () {
    final preview = ZoteroNotePreview.fromHtml(
      '<head><title>Hidden title</title></head><p>Visible</p>'
      '<svg><text>Hidden diagram</text><script>a < b</script></svg>'
      '<template><p>Hidden template</p></template>'
      '<iframe src="https://invalid.example">Hidden frame</iframe>'
      '<object data="file:///secret">Hidden object</object>'
      '<math><mi>x</mi></math><audio>Hidden audio</audio><p>End</p>',
    );
    expect(preview.plainText, 'Visible\nEnd');
    expect(preview.hasOmittedContent, isTrue);
  });

  test('comments disappear without interpreting their content', () {
    final preview = ZoteroNotePreview.fromHtml(
      '<p>One<!-- <script>unclosed &bad; <img src=x> --> two</p>',
    );
    expect(preview.plainText, 'One two');
    expect(preview.hasOmittedContent, isFalse);
  });

  test('empty and formatting-only notes remain empty', () {
    for (final html in [
      '',
      '<p> </p>',
      '<div><!-- comment --></div>',
      '<span/>',
    ]) {
      final preview = ZoteroNotePreview.fromHtml(html);
      expect(preview.plainText, isEmpty, reason: html);
      expect(preview.hasOmittedContent, isFalse, reason: html);
    }
  });

  test(
    'misnested incomplete and ambiguous markup refuses the whole preview',
    () {
      for (final html in [
        '<p>Before<b>bold</p>',
        '<p>Unclosed',
        '<p title="unterminated>text</p>',
        '<p title="quoted"next="missing separator">text</p>',
        '<p title=>text</p>',
        '<p>text</p attribute=value>',
        '<!-- unterminated',
        'Before<script>unclosed',
        'Before<style/>visible',
        '<!DOCTYPE html><p>text</p>',
        '<?xml version="1.0"?><p>text</p>',
        '<![CDATA[raw]]>',
        'A <y && z > 0',
        '<p>text\u0000</p>',
      ]) {
        expect(
          () => ZoteroNotePreview.fromHtml(html),
          throwsFormatException,
          reason: html,
        );
      }
    },
  );

  test(
    'UTF-8 byte budget accepts the boundary and refuses excess multibyte text',
    () {
      final exactlyOneMiB = 'é' * (512 * 1024);
      expect(
        ZoteroNotePreview.fromHtml(exactlyOneMiB).plainText,
        exactlyOneMiB,
      );
      expect(
        () => ZoteroNotePreview.fromHtml('$exactlyOneMiBé'),
        throwsFormatException,
      );
      expect(
        () => ZoteroNotePreview.fromHtml('x' * (1024 * 1024 + 1)),
        throwsFormatException,
      );
    },
  );

  test(
    'depth attribute and token budgets bound work even for empty markup',
    () {
      expect(
        ZoteroNotePreview.fromHtml(
          '${'<div>' * 64}text${'</div>' * 64}',
        ).plainText,
        'text',
      );
      expect(
        () => ZoteroNotePreview.fromHtml('${'<div>' * 65}text${'</div>' * 65}'),
        throwsFormatException,
      );
      expect(ZoteroNotePreview.fromHtml('<span/>' * 10000).plainText, isEmpty);
      expect(
        () => ZoteroNotePreview.fromHtml('<span/>' * 10001),
        throwsFormatException,
      );
      final attributes = List.generate(
        65,
        (index) => 'data-$index="value"',
      ).join(' ');
      expect(
        () => ZoteroNotePreview.fromHtml('<p $attributes>text</p>'),
        throwsFormatException,
      );
    },
  );

  test(
    'many literal less-than signs do not trigger quadratic tag scanning',
    () {
      final literal = '< ' * 100000;
      expect(ZoteroNotePreview.fromHtml(literal).plainText, literal);
      expect(
        () => ZoteroNotePreview.fromHtml('<p title="${'<' * 100000}'),
        throwsFormatException,
      );
    },
  );
}
