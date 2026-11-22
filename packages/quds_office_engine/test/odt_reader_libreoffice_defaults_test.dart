import 'package:quds_office_engine/src/word/model/wml_document.dart';
import 'package:quds_office_engine/src/word/model/word_notes.dart';
import 'package:quds_office_engine/src/word/serial/odt_reader_styles.dart';
import 'package:quds_office_engine/src/xml/xml_node.dart';
import 'package:test/test.dart';

const _namespaces = '''
xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
xmlns:loext="urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0"
xmlns:foreign="urn:foreign"''';

OdtReaderStyles _styles({
  String defaults = '',
  String textDefaults = 'fo:language="en" fo:country="US"',
  String paragraph = '',
  String page = '',
  String pageChildren = '',
  String layoutChildren = '',
  String drawing = '',
  String drawingStyle = '',
}) => OdtReaderStyles(
  XmlDocument.parse('''
<office:document-content $_namespaces>
<office:automatic-styles>
<style:style style:name="P" style:family="paragraph">
<style:paragraph-properties $paragraph/>
</style:style>
</office:automatic-styles>
</office:document-content>''').root!,
  styles: XmlDocument.parse('''
<office:document-styles $_namespaces>
<office:styles>
<style:default-style style:family="paragraph">
<style:paragraph-properties $defaults/>
<style:text-properties $textDefaults/>
</style:default-style>
$drawing
</office:styles>
<office:automatic-styles>
<style:page-layout style:name="Page">
<style:page-layout-properties fo:page-width="8in" fo:page-height="11in"
fo:margin="1in" $page>$pageChildren</style:page-layout-properties>
$layoutChildren
</style:page-layout>
</office:automatic-styles>
<office:master-styles>
<style:master-page style:name="Standard" style:page-layout-name="Page" $drawingStyle/>
</office:master-styles>
</office:document-styles>''').root!,
);

WmlParagraph _paragraph(OdtReaderStyles styles, String text) {
  final properties = styles.paragraphProperties('P');
  final paragraph = WmlParagraph(
    properties: properties,
    inlines: [
      WmlRun(text: text, properties: properties.importedParagraphMark!.copy()),
    ],
  );
  styles.validateParagraphContent('P', paragraph);
  return paragraph;
}

const _dormantParagraph = '''
fo:hyphenation-ladder-count="no-limit" fo:hyphenation-keep="auto"
loext:hyphenation-keep-type="column" loext:hyphenation-keep-line="false"
style:contextual-spacing="false" style:justify-single-word="false"
loext:paragraph-composer="false"
style:text-autospace="ideograph-alpha" style:punctuation-wrap="hanging"
style:line-break="strict" style:tab-stop-distance="0.4925in"''';

const _inactiveGrid = '''
style:layout-grid-mode="none" style:layout-grid-color="#c0c0c0"
style:layout-grid-lines="24620" style:layout-grid-base-height="0.0693in"
style:layout-grid-ruby-height="0in" style:layout-grid-base-width="0.1528in"
style:layout-grid-ruby-below="false" style:layout-grid-print="false"
style:layout-grid-display="false" style:layout-grid-snap-to="true"''';

const _separator = '''<style:footnote-sep style:width="0.0071in"
style:distance-before-sep="0.0398in" style:distance-after-sep="0.0398in"
style:line-style="solid" style:adjustment="left" style:rel-width="25%"
style:color="#000000"/>''';

void main() {
  group('qualified LibreOffice paragraph defaults', () {
    test('keeps Latin and Arabic prose under dormant inherited defaults', () {
      final styles = _styles(defaults: _dormantParagraph);
      final paragraph = _paragraph(styles, 'Latin العربية 😀.');
      expect(paragraph.text, 'Latin العربية 😀.');
      expect(paragraph.properties.spacingAfter, 0);
      expect(paragraph.properties.lineSpacing, 1);
    });

    test('evaluates a child override before refusing an active setting', () {
      final styles = _styles(
        defaults:
            'style:contextual-spacing="true" '
            'style:justify-single-word="true" '
            'loext:paragraph-composer="true" '
            'style:tab-stop-distance="0.4925in"',
        paragraph:
            'style:contextual-spacing="false" '
            'style:justify-single-word="false" '
            'loext:paragraph-composer="false" '
            'style:tab-stop-distance="0.5in"',
      );
      expect(_paragraph(styles, 'A\tB').text, 'A\tB');
    });

    for (final property in [
      'style:contextual-spacing="true"',
      'style:justify-single-word="true"',
      'loext:paragraph-composer="true"',
      'fo:hyphenation-ladder-count="2"',
      'fo:hyphenation-keep="page"',
      'loext:hyphenation-keep-type="page"',
      'loext:hyphenation-keep-line="true"',
      'style:text-autospace="unexpected"',
      'style:punctuation-wrap="unexpected"',
      'style:line-break="unexpected"',
      'foreign:contextual-spacing="false"',
    ]) {
      test('refuses unsupported active or foreign property $property', () {
        expect(
          () => _paragraph(_styles(paragraph: property), 'Text'),
          throwsUnsupportedError,
        );
      });
    }

    test('refuses actual CJK typography, including supplementary Han', () {
      for (final text in ['Latin 中文', 'かな', '한글', '𠀀', '。']) {
        expect(
          () => _paragraph(_styles(defaults: _dormantParagraph), text),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              contains('Asian paragraph typography'),
            ),
          ),
          reason: text,
        );
      }
    });

    test('does not reject CJK when conditional typography is absent', () {
      expect(_paragraph(_styles(), 'Latin 中文').text, 'Latin 中文');
    });

    test('ASCII punctuation with a CJK break locale remains active', () {
      final styles = _styles(defaults: _dormantParagraph);
      final paragraph = _paragraph(styles, 'ASCII punctuation.');
      final run = paragraph.inlines.single as WmlRun;
      run.properties.proofingLanguage = 'zh-CN';
      expect(
        () => styles.validateParagraphContent('P', paragraph),
        throwsUnsupportedError,
      );
      run.properties.proofingLanguage = 'en-US';
      run.properties.complexScriptLanguage = 'ja-JP';
      run.properties.complexScript = true;
      expect(
        () => styles.validateParagraphContent('P', paragraph),
        throwsUnsupportedError,
      );
    });

    test('checks a note anchor before its visible label is materialized', () {
      final styles = _styles(defaults: _dormantParagraph, textDefaults: '');
      final properties = styles.paragraphProperties('P');
      final paragraph = WmlParagraph(
        properties: properties,
        inlines: [
          WmlRun(
            noteRefId: 1,
            properties: properties.importedParagraphMark!.copy(),
          ),
        ],
      );
      expect(
        () => styles.validateParagraphContent('P', paragraph),
        throwsUnsupportedError,
      );
    });

    test('does not assume an ambient locale for conditional line breaking', () {
      expect(
        () => _paragraph(
          _styles(defaults: _dormantParagraph, textDefaults: ''),
          'Unknown language.',
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('explicit supported break locale'),
          ),
        ),
      );
    });

    test('refuses a nonstandard default tab interval only when used', () {
      final styles = _styles(defaults: 'style:tab-stop-distance="0.4925in"');
      expect(_paragraph(styles, 'No tab').text, 'No tab');
      expect(
        () => _paragraph(styles, 'Actual\ttab'),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('tab distance'),
          ),
        ),
      );
    });

    test('invalid dormant booleans and zero tab intervals still refuse', () {
      for (final property in [
        'style:contextual-spacing="invalid"',
        'loext:hyphenation-keep-line="invalid"',
        'style:tab-stop-distance="0in"',
      ]) {
        expect(
          () => _paragraph(_styles(paragraph: property), 'Text'),
          throwsFormatException,
          reason: property,
        );
      }
    });
  });

  group('qualified LibreOffice page defaults', () {
    test('retains geometry with disabled grid and inactive page metadata', () {
      final styles = _styles(
        page:
            '$_inactiveGrid style:num-format="1" '
            'style:footnote-max-height="0in" loext:margin-gutter="0in"',
        pageChildren: _separator,
        layoutChildren: '<style:header-style/><style:footer-style/>',
        drawing:
            '''<style:style style:name="Drawing" style:family="drawing-page">
<style:drawing-page-properties draw:background-size="full"/>
</style:style>''',
        drawingStyle: 'draw:style-name="Drawing"',
      );
      _paragraph(styles, 'Text');
      final section = WmlSection();
      styles.applyPageLayout(section);
      expect(section.pageSize.width, 576);
      expect(section.pageSize.height, 792);
      expect(section.margins.left, 72);
      expect(section.margins.top, 72);
    });

    test(
      'footnote activates explicitly represented native separator geometry',
      () {
        final styles = _styles(pageChildren: _separator);
        _paragraph(styles, 'Text');
        final separator = styles.applyPageLayout(
          WmlSection(),
          hasFootnotes: true,
        )!;
        expect(separator.thickness, closeTo(0.5112, 0.000001));
        expect(separator.beforeSpacing, closeTo(2.8656, 0.000001));
        expect(separator.afterSpacing, closeTo(2.8656, 0.000001));
        expect(separator.relativeWidth, 0.25);
        expect(separator.alignment, WmlFootnoteSeparatorAlignment.left);
        expect(separator.color, 0);
        expect(separator.lineStyle, WmlFootnoteSeparatorLineStyle.solid);
      },
    );

    for (final property in [
      'style:layout-grid-mode="both"',
      'style:layout-grid-mode="lines"',
      'style:layout-grid-color="#ffffff"',
      'loext:margin-gutter="0.5in"',
      'style:footnote-max-height="1in"',
      'style:num-format="i"',
      'foreign:layout-grid-mode="none"',
    ]) {
      test('refuses unrepresented page setting $property', () {
        final styles = _styles(page: property);
        _paragraph(styles, 'Text');
        expect(
          () => styles.applyPageLayout(WmlSection()),
          throwsUnsupportedError,
        );
      });
    }

    test('refuses malformed disabled-grid metadata and ambiguous owners', () {
      for (final styles in [
        _styles(
          page: 'style:layout-grid-mode="none" style:layout-grid-lines="0"',
        ),
        _styles(
          page:
              'style:layout-grid-mode="none" '
              'style:layout-grid-display="invalid"',
        ),
        _styles(layoutChildren: '<style:header-style/><style:header-style/>'),
        _styles(pageChildren: '$_separator$_separator'),
      ]) {
        _paragraph(styles, 'Text');
        expect(
          () => styles.applyPageLayout(WmlSection()),
          throwsFormatException,
        );
      }
    });

    test('refuses active drawing fills and missing background styles', () {
      for (final styles in [
        _styles(
          drawing:
              '''<style:style style:name="Drawing" style:family="drawing-page">
<style:drawing-page-properties draw:fill="solid"/>
</style:style>''',
          drawingStyle: 'draw:style-name="Drawing"',
        ),
        _styles(drawingStyle: 'draw:style-name="Missing"'),
      ]) {
        _paragraph(styles, 'Text');
        expect(
          () => styles.applyPageLayout(WmlSection()),
          throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
        );
      }
    });
  });
}
