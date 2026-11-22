import 'package:quds_office_engine/src/word/model/wml_document.dart';
import 'package:quds_office_engine/src/word/properties/wml_properties.dart';
import 'package:quds_office_engine/src/word/serial/odt_reader_styles.dart';
import 'package:quds_office_engine/src/xml/xml_node.dart';
import 'package:test/test.dart';

const _namespaces = '''
xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
xmlns:fake="urn:unrelated"''';

XmlElement _content(String definitions, {String fonts = ''}) =>
    XmlDocument.parse('''
<office:document-content $_namespaces>
<office:font-face-decls>$fonts</office:font-face-decls>
<office:automatic-styles>$definitions</office:automatic-styles>
<office:body><office:text/></office:body>
</office:document-content>''').root!;

XmlElement _styles(
  String definitions, {
  String automatic = '',
  String masters = '',
}) => XmlDocument.parse('''
<office:document-styles $_namespaces>
<office:styles>$definitions</office:styles>
<office:automatic-styles>$automatic</office:automatic-styles>
<office:master-styles>$masters</office:master-styles>
</office:document-styles>''').root!;

String _textStyle(String name, String properties, {String parent = ''}) =>
    '''
<style:style style:name="$name" style:family="text" ${parent.isEmpty ? '' : 'style:parent-style-name="$parent"'}>
<style:text-properties $properties/>
</style:style>''';

String _paragraphStyle(
  String name,
  String properties, {
  String parent = '',
  String text = '',
  String extra = '',
}) =>
    '''
<style:style style:name="$name" style:family="paragraph" ${parent.isEmpty ? '' : 'style:parent-style-name="$parent"'} $extra>
<style:paragraph-properties $properties/>
<style:text-properties $text/>
</style:style>''';

void main() {
  group('ODT style inheritance', () {
    test('rejects family-name collisions from malformed definitions', () {
      final styles = OdtReaderStyles(
        _content(
          '<style:style style:name="B" style:family="text/A"><style:text-properties fo:font-weight="bold"/></style:style>',
        ),
      );
      expect(() => styles.runProperties('A/B'), throwsFormatException);
    });
    test('uses ODF paragraph spacing defaults', () {
      final props = OdtReaderStyles(_content('')).paragraphProperties(null);
      expect(props.spacingAfter, 0);
      expect(props.lineSpacing, 1);
      expect(props.explicitLineSpacing, isFalse);
      expect(props.importedParagraphMark!.kerningHalfPoints, 0);
    });

    test(
      'resolves named parent and default into automatic paragraph style',
      () {
        final styles = OdtReaderStyles(
          _content(
            _paragraphStyle(
              'Automatic',
              'fo:margin-bottom="6pt"',
              parent: 'Child',
            ),
          ),
          styles: _styles('''
<style:default-style style:family="paragraph"><style:text-properties fo:font-size="12pt" fo:font-family="Times New Roman"/></style:default-style>
${_paragraphStyle('Parent', 'fo:text-align="center"', text: 'fo:font-weight="bold"')}
${_paragraphStyle('Child', '', parent: 'Parent', text: 'fo:font-style="italic"')}
'''),
        );
        final paragraph = styles.paragraphProperties('Automatic');
        final run = styles.paragraphRunProperties('Automatic');
        expect(paragraph.justification, WmlJustification.center);
        expect(paragraph.spacingAfter, 6);
        expect(run.asciiFont, 'Times New Roman');
        expect(run.fontSizePoints, 12);
        expect(run.bold, isTrue);
        expect(run.italic, isTrue);
        expect(run.styleId, isNull);
        expect(paragraph.styleId, isNull);
      },
    );

    test(
      'span explicit normal overrides inherited bold without losing italic',
      () {
        final styles = OdtReaderStyles(
          _content(_textStyle('Normal', 'fo:font-weight="normal"')),
        );
        final inherited = WmlRunProps(
          bold: true,
          italic: true,
          fontSizeHalfPoints: 28,
        );
        final run = styles.runProperties('Normal', inherited: inherited);
        expect(run.bold, isFalse);
        expect(run.italic, isTrue);
        expect(run.fontSizeHalfPoints, 28);
        expect(inherited.bold, isTrue);
        expect(run.explicitProperties, contains('bold'));
      },
    );

    test('returns independent property objects and immutable chains', () {
      final styles = OdtReaderStyles(
        _content(_textStyle('Red', 'fo:color="#ff0000"')),
      );
      styles.runProperties('Red').color = 'FFFFFF';
      expect(styles.runProperties('Red').color, 'FF0000');
      expect(
        () => styles.styleChain('text', 'Red').clear(),
        throwsUnsupportedError,
      );
    });

    test('style names are scoped by family', () {
      final styles = OdtReaderStyles(
        _content(
          '${_textStyle('Same', 'fo:font-weight="bold"')}${_paragraphStyle('Same', 'fo:text-align="right"')}',
        ),
      );
      expect(styles.hasParagraphStyle('Same'), isTrue);
      expect(styles.runProperties('Same').bold, isTrue);
      expect(
        styles.paragraphProperties('Same').justification,
        WmlJustification.right,
      );
    });

    test('missing and cyclic parents fail only when used', () {
      final missing = OdtReaderStyles(
        _content(_textStyle('Missing', '', parent: 'Absent')),
      );
      expect(missing.runProperties(null).bold, isFalse);
      expect(() => missing.runProperties('Missing'), throwsFormatException);
      final cycle = OdtReaderStyles(
        _content(
          '${_textStyle('A', '', parent: 'B')}${_textStyle('B', '', parent: 'A')}',
        ),
      );
      expect(() => cycle.runProperties('A'), throwsFormatException);
    });

    test('bounds parent traversal and total definitions', () {
      final chain = StringBuffer();
      for (var index = 0; index < 65; index++) {
        chain.write(
          _textStyle('T$index', '', parent: index == 64 ? '' : 'T${index + 1}'),
        );
      }
      final styles = OdtReaderStyles(_content(chain.toString()));
      expect(() => styles.runProperties('T0'), throwsFormatException);
      final many = List.generate(
        OdtReaderStyles.maxDefinitions + 1,
        (index) => _textStyle('T$index', ''),
      ).join();
      expect(() => OdtReaderStyles(_content(many)), throwsFormatException);
    });

    test('rejects duplicate definitions instead of choosing one', () {
      expect(
        () => OdtReaderStyles(
          _content('${_textStyle('A', '')}${_textStyle('A', '')}'),
        ),
        throwsFormatException,
      );
    });

    test(
      'rejects foreign property lookalikes and unsupported active formatting',
      () {
        for (final attribute in [
          'fake:color="#ffffff"',
          'fo:text-shadow="1pt 1pt"',
          'fo:font-stretch="condensed"',
        ]) {
          final styles = OdtReaderStyles(
            _content(_textStyle('Unsupported', attribute)),
          );
          expect(
            () => styles.runProperties('Unsupported'),
            throwsUnsupportedError,
          );
        }
      },
    );

    test('unused unsupported formatting does not block supported content', () {
      final styles = OdtReaderStyles(
        _content(
          '${_textStyle('Unused', 'fo:text-shadow="1pt 1pt"')}${_textStyle('Used', 'fo:font-style="italic"')}',
        ),
      );
      expect(styles.runProperties('Used').italic, isTrue);
    });

    test('requires namespace identity, regardless of prefix spelling', () {
      final other = XmlDocument.parse(
        '''
<o:document-content xmlns:o="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:s="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:f="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"><o:automatic-styles><s:style s:name="T" s:family="text"><s:text-properties f:font-weight="bold"/></s:style></o:automatic-styles></o:document-content>''',
      ).root!;
      expect(OdtReaderStyles(other).runProperties('T').bold, isTrue);
    });
  });

  group('ODT character formatting', () {
    test(
      'projects independent script proofing suppression onto actual text',
      () {
        for (final scenario in [
          (
            properties: 'fo:language="none" style:language-complex="ar"',
            text: 'Aب',
            flags: [true, false],
          ),
          (
            properties: 'fo:language="en" style:language-complex="none"',
            text: 'Aب',
            flags: [false, true],
          ),
          (
            properties: 'style:language-asian="none"',
            text: 'A漢',
            flags: [null, true],
          ),
        ]) {
          final style = OdtReaderStyles(
            _content(_textStyle('T', scenario.properties)),
          ).runProperties('T');
          final runs = style.materialize(scenario.text).toList();
          expect(runs.map((run) => run.text).join(), scenario.text);
          expect(runs.map((run) => run.properties.noProof), scenario.flags);
        }
      },
    );
    test('keeps explicit complex font when descendant changes Latin font', () {
      final styles = OdtReaderStyles(
        _content(
          '${_textStyle('Parent', 'style:font-name-complex="Arabic"')}${_textStyle('Child', 'fo:font-family="Liberation Sans"', parent: 'Parent')}',
          fonts:
              '<style:font-face style:name="Arabic" svg:font-family="Amiri"/>',
        ),
      );
      final run = styles.runProperties('Child');
      expect(run.asciiFont, 'Liberation Sans');
      expect(run.csFont, 'Amiri');
    });

    test('rejects used embedded font sources instead of substituting', () {
      final styles = OdtReaderStyles(
        _content(
          _textStyle('T', 'style:font-name="Embedded"'),
          fonts:
              '<style:font-face style:name="Embedded" svg:font-family="Custom"><svg:font-face-src/></style:font-face>',
        ),
      );
      expect(styles.runProperties(null).bold, isFalse);
      expect(() => styles.runProperties('T'), throwsUnsupportedError);
    });

    test(
      'rejects independent underline color even when initially equal to text',
      () {
        final styles = OdtReaderStyles(
          _content(
            _textStyle(
              'T',
              'fo:color="#ff0000" style:text-underline-color="#ff0000" style:text-underline-style="solid"',
            ),
          ),
        );
        expect(() => styles.runProperties('T'), throwsUnsupportedError);
      },
    );

    test('resolves declared font aliases including quoted font families', () {
      final styles = OdtReaderStyles(
        _content(
          _textStyle(
            'T',
            'style:font-name="Latin" style:font-name-complex="Arabic"',
          ),
          fonts:
              '''<style:font-face style:name="Latin" svg:font-family="'Liberation Serif'"/><style:font-face style:name="Arabic" svg:font-family="Amiri"/>''',
        ),
      );
      final run = styles.runProperties('T');
      expect(run.asciiFont, 'Liberation Serif');
      expect(run.csFont, 'Amiri');
    });

    test('rejects undeclared font aliases and conflicting declarations', () {
      final missing = OdtReaderStyles(
        _content(_textStyle('T', 'style:font-name="Missing"')),
      );
      expect(() => missing.runProperties('T'), throwsFormatException);
      expect(
        () => OdtReaderStyles(
          _content(
            '',
            fonts:
                '<style:font-face style:name="F" svg:font-family="Arial"/><style:font-face style:name="F" svg:font-family="Amiri"/>',
          ),
        ),
        throwsFormatException,
      );
    });

    test(
      'applies proportional size to inherited size with exact half points',
      () {
        final styles = OdtReaderStyles(
          _content(
            '${_textStyle('A', 'fo:font-size="16pt"')}${_textStyle('B', 'fo:font-size="125%"', parent: 'A')}',
          ),
        );
        expect(styles.runProperties('B').fontSizePoints, 20);
        final lossy = OdtReaderStyles(
          _content(_textStyle('Lossy', 'fo:font-size="11.1pt"')),
        );
        expect(() => lossy.runProperties('Lossy'), throwsUnsupportedError);
      },
    );

    test('preserves color highlight small caps and kerning flags', () {
      final props = OdtReaderStyles(
        _content(
          _textStyle(
            'T',
            'fo:color="#aabbcc" fo:background-color="#112233" fo:font-variant="small-caps" style:letter-kerning="true"',
          ),
        ),
      ).runProperties('T');
      expect(props.color, 'AABBCC');
      expect(props.highlight, '112233');
      expect(props.smallCaps, isTrue);
      expect(props.kerningHalfPoints, 1);
    });

    test('maps underline families and inherited width changes', () {
      final styles = OdtReaderStyles(
        _content(
          '${_textStyle('A', 'style:text-underline-style="wave"')}${_textStyle('B', 'style:text-underline-width="bold"', parent: 'A')}${_textStyle('C', 'style:text-underline-style="solid" style:text-underline-type="double"')}',
        ),
      );
      expect(styles.runProperties('A').underline, WmlUnderline.wavy);
      expect(styles.runProperties('B').underline, WmlUnderline.wavyHeavy);
      expect(styles.runProperties('C').underline, WmlUnderline.double);
    });

    test('maps semantic scripts and rejects unmodeled exact offsets', () {
      for (final pair in {
        'super': WmlVertAlign.superscript,
        'sub': WmlVertAlign.subscript,
        '0% 100%': WmlVertAlign.baseline,
      }.entries) {
        expect(
          OdtReaderStyles(
            _content(_textStyle('T', 'style:text-position="${pair.key}"')),
          ).runProperties('T').vertAlign,
          pair.value,
        );
      }
      expect(
        () => OdtReaderStyles(
          _content(_textStyle('T', 'style:text-position="20% 70%"')),
        ).runProperties('T'),
        throwsUnsupportedError,
      );
    });

    test('keeps Latin and complex-script language and inherited country', () {
      final styles = OdtReaderStyles(
        _content(
          '${_textStyle('A', 'fo:language="en" fo:country="GB" style:language-complex="ar" style:country-complex="EG"')}${_textStyle('B', 'fo:language="de"', parent: 'A')}',
        ),
      );
      final run = styles.runProperties('B');
      expect(run.proofingLanguage, 'de-GB');
      expect(run.complexScriptLanguage, 'ar-EG');
      expect(run.noProof, isFalse);
    });

    test(
      'explicit no-language suppresses proofing rather than inheriting document language',
      () {
        final run = OdtReaderStyles(
          _content(_textStyle('T', 'fo:language="none" fo:country="none"')),
        ).runProperties('T');
        expect(run.proofingLanguage, isNull);
        expect(run.noProof, isTrue);
      },
    );

    test('materializes distinct script scalar formatting as native runs', () {
      final style = OdtReaderStyles(
        _content(
          _textStyle(
            'T',
            'style:font-size-complex="20pt" style:font-weight-complex="bold" style:font-style-asian="italic"',
          ),
        ),
      ).runProperties('T');
      final runs = style.materialize('Aب漢').toList();
      expect(runs.map((run) => run.text), ['A', 'ب', '漢']);
      expect(runs.map((run) => run.properties.fontSizeHalfPoints), [
        22,
        40,
        22,
      ]);
      expect(runs.map((run) => run.properties.bold), [false, true, false]);
      expect(runs.map((run) => run.properties.italic), [false, false, true]);
    });
  });

  group('ODT document configuration guards', () {
    OdtReaderStyles configured(String definitions) =>
        OdtReaderStyles(_content(''), styles: _styles(definitions));

    test('accepts absent and canonical decimal note configurations', () {
      configured('').validateNoteConfiguration(false);
      configured('').validateNoteConfiguration(true);
      configured(
        '<text:notes-configuration text:note-class="footnote" style:num-format="1" style:num-prefix="" style:num-suffix="" text:start-value="1" text:start-numbering-at="document" text:footnotes-position="page"><text:note-continuation-notice-forward/></text:notes-configuration>',
      ).validateNoteConfiguration(false);
    });

    for (final format in ['i', 'I']) {
      for (final endnote in [false, true]) {
        test('accepts exact $format numbering for endnote=$endnote', () {
          final configuration = configured(
            '<text:notes-configuration '
            'text:note-class="${endnote ? 'endnote' : 'footnote'}" '
            'style:num-format="$format" text:start-value="1"/>',
          ).validateNoteConfiguration(endnote);
          expect(
            configuration.nativeFormat,
            format == 'i' ? 'lowerRoman' : 'upperRoman',
          );
          expect(configuration.labelFor(4), format == 'i' ? 'iv' : 'IV');
          expect(configuration.labelFor(0), isNull);
          expect(configuration.labelFor(4000), isNull);
          expect(configuration.verifyCachedOrdinal, isFalse);
        });
      }
    }

    test('non-one note starts preserve physical ordinal validation', () {
      final configuration = configured(
        '<text:notes-configuration text:note-class="footnote" '
        'style:num-format="i" text:start-value="8"/>',
      ).validateNoteConfiguration(false);
      expect(configuration.start, 8);
      expect(configuration.labelFor(1), 'viii');
      expect(configuration.labelFor(2), 'ix');
      expect(configuration.labelFor(0), isNull);
      expect(configuration.labelFor(-1), isNull);
      expect(configuration.verifyCachedOrdinal, isTrue);
    });

    test(
      'rejects active note numbering or positioning outside canonical scope',
      () {
        for (final attribute in [
          'text:start-value="0"',
          'text:start-value="2"',
          'style:num-format="a"',
          'style:num-prefix="["',
          'style:num-suffix="]"',
          'text:start-numbering-at="page"',
          'text:footnotes-position="text"',
        ]) {
          expect(
            () => configured(
              '<text:notes-configuration text:note-class="footnote" $attribute/>',
            ).validateNoteConfiguration(false),
            throwsUnsupportedError,
          );
        }
      },
    );

    test(
      'rejects missing note marker styles and unsupported paragraph/master settings',
      () {
        for (final name in [
          'citation-style-name',
          'citation-body-style-name',
          'default-style-name',
          'master-page-name',
        ]) {
          expect(
            () => configured(
              '<text:notes-configuration text:note-class="footnote" style:num-format="1" text:$name="Custom"/>',
            ).validateNoteConfiguration(false),
            // Marker styles now have a supported, validated form. An absent
            // referenced definition is malformed; paragraph/master settings
            // outside this footnote model remain unsupported capabilities.
            name.startsWith('citation-')
                ? throwsFormatException
                : throwsUnsupportedError,
          );
        }
      },
    );

    test('rejects duplicate note configurations and continuation labels', () {
      expect(
        () => configured(
          '<text:notes-configuration text:note-class="footnote"/><text:notes-configuration text:note-class="footnote"/>',
        ).validateNoteConfiguration(false),
        throwsFormatException,
      );
      expect(
        () => configured(
          '<text:notes-configuration text:note-class="footnote"><text:note-continuation-notice-forward>continued</text:note-continuation-notice-forward></text:notes-configuration>',
        ).validateNoteConfiguration(false),
        throwsUnsupportedError,
      );
    });

    test('unused other note class does not block the supported class', () {
      final styles = configured(
        '<text:notes-configuration text:note-class="endnote" style:num-format="a"/>',
      );
      styles.validateNoteConfiguration(false);
      expect(
        () => styles.validateNoteConfiguration(true),
        throwsUnsupportedError,
      );
    });

    test('rejects numbered outlines while admitting empty numbering levels', () {
      configured(
        '<text:outline-style style:name="Outline"><text:outline-level-style text:level="1" style:num-format=""/></text:outline-style>',
      ).validateHeadingConfiguration();
      expect(
        () => configured(
          '<text:outline-style style:name="Outline"><text:outline-level-style text:level="1" style:num-format="1"/></text:outline-style>',
        ).validateHeadingConfiguration(),
        throwsUnsupportedError,
      );
    });

    test('used table definitions reject active master and update metadata', () {
      for (final attribute in [
        'style:master-page-name="Other"',
        'style:auto-update="true"',
        'style:hidden="true"',
      ]) {
        final styles = OdtReaderStyles(
          _content(
            '<style:style style:name="T" style:family="table" $attribute><style:table-properties/></style:style>',
          ),
        );
        expect(() => styles.styleChain('table', 'T'), throwsUnsupportedError);
      }
      final conditional = OdtReaderStyles(
        _content(
          '<style:style style:name="T" style:family="table-cell"><style:map style:condition="cell-content()=1" style:apply-style-name="Other"/></style:style>',
        ),
      );
      expect(
        () => conditional.styleChain('table-cell', 'T'),
        throwsUnsupportedError,
      );
    });

    test(
      'list definitions reject consecutive numbering instead of ignoring it',
      () {
        final styles = OdtReaderStyles(
          _content(
            '<text:list-style style:name="L" text:consecutive-numbering="true"/><text:list-style style:name="N" text:consecutive-numbering="false"/>',
          ),
        );
        expect(() => styles.listStyle('L'), throwsUnsupportedError);
        expect(styles.listStyle('N'), isNotNull);
      },
    );
  });

  group('ODT paragraph and page geometry', () {
    test('explicit tab leader none suppresses the supplied leader pattern', () {
      final styles = OdtReaderStyles(
        _content(
          '<style:style style:name="P" style:family="paragraph"><style:paragraph-properties><style:tab-stops><style:tab-stop style:position="1in" style:leader-type="none" style:leader-style="dotted" style:leader-text="."/></style:tab-stops></style:paragraph-properties></style:style>',
        ),
      );
      expect(
        styles.paragraphProperties('P').tabs.single.leader,
        WmlTabLeader.none,
      );
    });

    test('rejects ambiguous repeated page column configurations', () {
      final styles = OdtReaderStyles(
        _content(''),
        styles: _styles(
          '',
          automatic:
              '<style:page-layout style:name="P"><style:page-layout-properties><style:columns fo:column-count="1"/><style:columns fo:column-count="2"/></style:page-layout-properties></style:page-layout>',
          masters: _master('M', 'P'),
        ),
      );
      expect(() => styles.applyPageLayout(WmlSection()), throwsFormatException);
    });

    test('resolves RTL logical alignment and physical margins', () {
      final props = OdtReaderStyles(
        _content(
          _paragraphStyle(
            'P',
            'style:writing-mode="rl-tb" fo:text-align="start" fo:margin-left="18pt" fo:margin-right="9pt" fo:text-indent="-6pt"',
          ),
        ),
      ).paragraphProperties('P');
      expect(props.rightToLeft, isTrue);
      expect(props.justification, WmlJustification.right);
      expect(props.indent.left, 9);
      expect(props.indent.right, 18);
      expect(props.indent.hanging, 6);
    });

    test('resolves line-height modes and explicit zero spacing', () {
      for (final sample in [
        ('fo:line-height="150%"', WmlLineSpacingRule.auto, 1.5),
        ('fo:line-height="18pt"', WmlLineSpacingRule.exact, 18.0),
        ('style:line-height-at-least="12pt"', WmlLineSpacingRule.atLeast, 12.0),
      ]) {
        final props = OdtReaderStyles(
          _content(
            _paragraphStyle(
              'P',
              '${sample.$1} fo:margin-top="0pt" fo:margin-bottom="0pt"',
            ),
          ),
        ).paragraphProperties('P');
        expect(props.lineSpacingRule, sample.$2);
        expect(props.lineSpacing, sample.$3);
        expect(props.explicitSpacingBefore, isTrue);
        expect(props.explicitSpacingAfter, isTrue);
      }
    });

    test('preserves heading level breaks keep and shading', () {
      final props = OdtReaderStyles(
        _content(
          _paragraphStyle(
            'P',
            'fo:break-before="page" fo:keep-together="always" fo:background-color="#ffeeaa"',
            extra: 'style:default-outline-level="2"',
          ),
        ),
      ).paragraphProperties('P');
      expect(props.headingLevel, 2);
      expect(props.pageBreakBefore, isTrue);
      expect(props.keepTogether, isTrue);
      expect(props.shadingFill, 'FFEEAA');
    });

    test('retains decimal tab position and dotted leader', () {
      final styles = OdtReaderStyles(
        _content(
          '''<style:style style:name="P" style:family="paragraph"><style:paragraph-properties><style:tab-stops><style:tab-stop style:position="1in" style:type="char" style:char="." style:leader-type="single" style:leader-style="dotted" style:leader-text="."/></style:tab-stops></style:paragraph-properties></style:style>''',
        ),
      );
      final tab = styles.paragraphProperties('P').tabs.single;
      expect(tab.position, 72);
      expect(tab.alignment, WmlTabAlignment.decimal);
      expect(tab.leader, WmlTabLeader.dot);
    });

    test('rejects unmodeled active pagination controls', () {
      for (final attribute in [
        'fo:keep-with-next="always"',
        'fo:break-after="page"',
        'fo:orphans="2"',
        'style:writing-mode="tb-rl"',
      ]) {
        expect(
          () => OdtReaderStyles(
            _content(_paragraphStyle('P', attribute)),
          ).paragraphProperties('P'),
          throwsUnsupportedError,
        );
      }
    });

    test(
      'converts absolute length units and rejects invalid or relative lengths',
      () {
        for (final value in ['1in', '2.54cm', '25.4mm', '6pc', '72pt']) {
          expect(OdtReaderStyles.lengthPoints(value), closeTo(72, 0.000001));
        }
        expect(OdtReaderStyles.lengthPoints('-1pt', allowNegative: true), -1);
        expect(
          () => OdtReaderStyles.lengthPoints('-1pt'),
          throwsFormatException,
        );
        for (final value in ['100%', 'NaNpt', 'Infinitypt', '12px', '1e9pt']) {
          expect(
            () => OdtReaderStyles.lengthPoints(value),
            throwsUnsupportedError,
          );
        }
      },
    );

    test('applies chosen master geometry and margins', () {
      final styles = OdtReaderStyles(
        _content(
          _paragraphStyle('P', '', extra: 'style:master-page-name="Standard"'),
        ),
        styles: _styles(
          '',
          automatic: _layout('Page', '210mm', '297mm'),
          masters: _master('Standard', 'Page'),
        ),
      );
      styles.paragraphProperties('P');
      final section = WmlSection();
      styles.applyPageLayout(section);
      expect(section.pageSize.width, closeTo(595.27559, 0.0001));
      expect(section.pageSize.height, closeTo(841.88976, 0.0001));
      expect(section.margins.left, 36);
    });

    test('accepts multiple used masters with equivalent geometry', () {
      final styles = OdtReaderStyles(
        _content(
          '${_paragraphStyle('A', '', extra: 'style:master-page-name="M1"')}${_paragraphStyle('B', '', extra: 'style:master-page-name="M2"')}',
        ),
        styles: _styles(
          '',
          automatic:
              '${_layout('P1', '612pt', '792pt')}${_layout('P2', '8.5in', '11in')}',
          masters: '${_master('M1', 'P1')}${_master('M2', 'P2')}',
        ),
      );
      styles.paragraphProperties('A');
      styles.paragraphProperties('B');
      final section = WmlSection();
      styles.applyPageLayout(section);
      expect(section.pageSize.width, 612);
    });

    test('rejects multiple applied geometries before mutating target section', () {
      final styles = OdtReaderStyles(
        _content(
          '${_paragraphStyle('A', '', extra: 'style:master-page-name="M1"')}${_paragraphStyle('B', '', extra: 'style:master-page-name="M2"')}',
        ),
        styles: _styles(
          '',
          automatic:
              '${_layout('P1', '612pt', '792pt')}${_layout('P2', '500pt', '700pt')}',
          masters: '${_master('M1', 'P1')}${_master('M2', 'P2')}',
        ),
      );
      styles.paragraphProperties('A');
      styles.paragraphProperties('B');
      final section = WmlSection();
      final before = section.pageSize;
      expect(() => styles.applyPageLayout(section), throwsUnsupportedError);
      expect(section.pageSize, same(before));
    });

    test('rejects used header content and missing masters', () {
      final header = OdtReaderStyles(
        _content(''),
        styles: _styles(
          '',
          automatic: _layout('P', '612pt', '792pt'),
          masters:
              '<style:master-page style:name="M" style:page-layout-name="P"><style:header><text:p>Header</text:p></style:header></style:master-page>',
        ),
      );
      expect(
        () => header.applyPageLayout(WmlSection()),
        throwsUnsupportedError,
      );
      final missing = OdtReaderStyles(
        _content(
          _paragraphStyle('P', '', extra: 'style:master-page-name="Missing"'),
        ),
      );
      missing.paragraphProperties('P');
      expect(
        () => missing.applyPageLayout(WmlSection()),
        throwsFormatException,
      );
    });

    test(
      'exposes bounded list and table style definitions for structural reader',
      () {
        final styles = OdtReaderStyles(
          _content(
            '''<text:list-style style:name="L"><text:list-level-style-bullet text:level="1" text:bullet-char="•"/></text:list-style><style:style style:name="C" style:family="table-column"><style:table-column-properties style:column-width="2cm"/></style:style>''',
          ),
        );
        expect(
          styles.listStyle('L')!.childElements.single.localName,
          'list-level-style-bullet',
        );
        expect(
          styles
              .styleChain('table-column', 'C')
              .single
              .childElements
              .single
              .localName,
          'table-column-properties',
        );
        expect(() => styles.listStyle('Unknown'), throwsFormatException);
      },
    );
  });
}

String _layout(String name, String width, String height) =>
    '''<style:page-layout style:name="$name"><style:page-layout-properties fo:page-width="$width" fo:page-height="$height" fo:margin="0.5in"/></style:page-layout>''';
String _master(String name, String layout) =>
    '<style:master-page style:name="$name" style:page-layout-name="$layout"/>';
