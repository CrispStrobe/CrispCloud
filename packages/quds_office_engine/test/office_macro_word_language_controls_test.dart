import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:quds_office_engine/src/word/serial/word_property_io.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:language-control-tests';

Uint8List _fixture({
  String run = '',
  String paragraph = '',
  String? body,
  String? styles,
  String prefix = 'w',
  bool shadowWordPrefix = false,
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<$prefix:document xmlns:$prefix="$_w" xmlns:x="$_x"'
        '${shadowWordPrefix ? ' xmlns:w="urn:foreign-word-prefix"' : ''}>'
        '<$prefix:body>'
        '${body ?? '<$prefix:p><$prefix:pPr>$paragraph</$prefix:pPr>'
                '<$prefix:r><$prefix:rPr>$run</$prefix:rPr>'
                '<$prefix:t>English العربية</$prefix:t></$prefix:r></$prefix:p>'}'
        '<$prefix:sectPr/></$prefix:body></$prefix:document>',
      );
  if (styles != null) {
    package
        .getPart('/word/styles.xml')!
        .writeText('<w:styles xmlns:w="$_w" xmlns:x="$_x">$styles</w:styles>');
  }
  return package.save();
}

WmlDocument _read(Uint8List bytes) => WordDeserializer().readBytes(bytes);

XmlElement _rPr(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .firstChild('p', namespaceUri: _w)!
        .firstChild('r', namespaceUri: _w)!
        .firstChild('rPr', namespaceUri: _w)!;

WmlRunProps _props(WmlDocument document) =>
    document.paragraphs.single.inlines.whereType<WmlRun>().single.properties;

String? _attribute(XmlElement properties, String property, String attribute) =>
    properties
        .firstChild(property, namespaceUri: _w)
        ?.getAttribute(attribute, namespaceUri: _w);

void _run(WmlDocument document, Map<String, Object?> fields) =>
    native.applyStep(document, {'op': 'runFormat', 'paragraph': 0, ...fields});

void main() {
  for (final sourcePlan in [false, true]) {
    test(
      'small capitals compose without rebinding foreign prefixes (source $sourcePlan)',
      () async {
        final input = _fixture(
          prefix: 'q',
          shadowWordPrefix: true,
          run:
              '<w:keep w:val="foreign"/><w:smallCaps w:val="0"/>'
              '<x:sectPr x:keep="opaque-section-metadata"/>'
              '<q:caps q:val="1" x:keep="caps-metadata"><x:child/></q:caps>'
              '<q:strike/><q:u q:val="single"/>'
              '<q:rFonts q:ascii="Latin" q:cs="Old"/>'
              '<q:lang q:val="en-US" q:bidi="ar-SA"/>'
              '<x:container><q:smallCaps q:val="0"/></x:container>',
        );
        Uint8List bytes;
        if (sourcePlan) {
          final session = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.docx,
          );
          final plan = OfficeMacroLanguages().compile(
            OfficeMacroSource(
              language: 'vba-word',
              format: OfficeMacroFormat.docx,
              source: '''
Sub Main()
  With ActiveDocument.Paragraphs(1).Range
    .Font.SmallCaps = True
    .Font.Bold = True
    .Font.Color = RGB(20, 30, 40)
    .Font.StrikeThrough = False
    .Font.Underline = wdUnderlineNone
    .Font.NameBi = "Amiri"
    .LanguageID = wdGerman
  End With
End Sub
''',
            ),
          );
          await session.run(plan);
          bytes = session.bytes;
        } else {
          final document = _read(input);
          _run(document, {
            'smallCaps': true,
            'bold': true,
            'color': '141E28',
            'strike': false,
            'underline': 'none',
            'csFont': 'Amiri',
            'language': 'de-DE',
          });
          bytes = WordSerializer().writeBytes(document);
        }
        for (var cycle = 0; cycle < 3; cycle++) {
          final properties = _rPr(bytes);
          final caps = properties.firstChild('caps', namespaceUri: _w)!;
          expect(caps.getAttribute('val', namespaceUri: _w), '0');
          expect(caps.getAttribute('keep', namespaceUri: _x), 'caps-metadata');
          expect(caps.firstChild('child', namespaceUri: _x), isNotNull);
          expect(
            properties.firstChild(
              'keep',
              namespaceUri: 'urn:foreign-word-prefix',
            ),
            isNotNull,
          );
          expect(properties.firstChild('keep', namespaceUri: _w), isNull);
          expect(
            properties.firstChild(
              'smallCaps',
              namespaceUri: 'urn:foreign-word-prefix',
            ),
            isNotNull,
          );
          expect(_attribute(properties, 'smallCaps', 'val'), '1');
          expect(
            properties
                .firstChild('sectPr', namespaceUri: _x)
                ?.getAttribute('keep', namespaceUri: _x),
            'opaque-section-metadata',
          );
          final document = _read(bytes);
          expect(_props(document).smallCaps, isTrue);
          expect(_props(document).bold, isTrue);
          expect(_props(document).color, '141E28');
          expect(_props(document).strike, isFalse);
          expect(_props(document).underline, WmlUnderline.none);
          expect(_props(document).csFont, 'Amiri');
          expect(_props(document).proofingLanguage, 'de-DE');
          expect(_props(document).complexScriptLanguage, 'ar-SA');
          bytes = WordSerializer().writeBytes(document);
        }
      },
    );
  }

  for (final property in ['smallCaps', 'caps']) {
    test(
      'small-capital native override refuses duplicate $property before mutation',
      () {
        final document = _read(
          _fixture(run: '<w:$property w:val="1"/><w:$property w:val="0"/>'),
        );
        final props = _props(document);
        final before = WordSerializer().runPropertiesXml(props);
        expect(
          () => _run(document, {
            'smallCaps': true,
            'language': 'de-DE',
            'csFont': 'Amiri',
          }),
          throwsUnsupportedError,
        );
        expect(WordSerializer().runPropertiesXml(props), before);
      },
    );
  }

  test(
    'section property insertion keeps foreign namespace and native section identity',
    () {
      final source =
          '<q:pPr xmlns:q="$_w" xmlns:w="urn:foreign-word-prefix">'
          '<w:sectPr w:keep="opaque"/><q:sectPr><q:pgSz q:w="100"/></q:sectPr></q:pPr>';
      final generated = WordPropertyIo.parse(
        '<w:pPr xmlns:w="$_w">'
            '<w:sectPr><w:pgSz w:w="200"/></w:sectPr></w:pPr>',
        'pPr',
      );
      final result = WordPropertyIo.preserve(generated, source, {}, {});
      final reopened = XmlDocument.parse(
        XmlDocument(root: result).toXmlString(),
      ).root!;
      expect(reopened.childrenNamed('sectPr', namespaceUri: _w), hasLength(1));
      expect(
        reopened
            .firstChild('sectPr', namespaceUri: _w)!
            .firstChild('pgSz', namespaceUri: _w)!
            .getAttribute('w', namespaceUri: _w),
        '200',
      );
      expect(
        reopened
            .firstChild('sectPr', namespaceUri: 'urn:foreign-word-prefix')
            ?.getAttribute('keep', namespaceUri: 'urn:foreign-word-prefix'),
        'opaque',
      );
    },
  );

  test('language and complex font round trip independently of other slots', () {
    final document = _read(
      _fixture(
        run:
            '<w:lang w:val="en-US" w:bidi="ar-SA" w:eastAsia="ja-JP"/>'
            '<w:rFonts w:ascii="Latin" w:hAnsi="High" w:cs="Complex" '
            'w:eastAsia="East" w:asciiTheme="minorHAnsi" '
            'w:hAnsiTheme="majorHAnsi" w:eastAsiaTheme="majorEastAsia" '
            'w:cstheme="majorBidi" w:hint="eastAsia"/>'
            '<w:noProof/><w:sz w:val="26"/><w:szCs w:val="34"/>',
      ),
    );
    _run(document, {'language': 'de-DE', 'csFont': 'Amiri'});
    var bytes = WordSerializer().writeBytes(document);
    for (var cycle = 0; cycle < 3; cycle++) {
      final properties = _rPr(bytes);
      expect(_attribute(properties, 'lang', 'val'), 'de-DE');
      expect(_attribute(properties, 'lang', 'bidi'), 'ar-SA');
      expect(_attribute(properties, 'lang', 'eastAsia'), 'ja-JP');
      for (final entry in {
        'ascii': 'Latin',
        'hAnsi': 'High',
        'cs': 'Amiri',
        'eastAsia': 'East',
        'asciiTheme': 'minorHAnsi',
        'hAnsiTheme': 'majorHAnsi',
        'eastAsiaTheme': 'majorEastAsia',
        'hint': 'eastAsia',
      }.entries) {
        expect(_attribute(properties, 'rFonts', entry.key), entry.value);
      }
      expect(_attribute(properties, 'rFonts', 'cstheme'), isNull);
      expect(_attribute(properties, 'szCs', 'val'), '34');
      final reopened = _read(bytes);
      expect(_props(reopened).proofingLanguage, 'de-DE');
      expect(_props(reopened).complexScriptLanguage, 'ar-SA');
      expect(_props(reopened).csFont, 'Amiri');
      expect(_props(reopened).noProof, isTrue);
      expect(_props(reopened).fontSizeHalfPoints, 26);
      expect(reopened.paragraphs.single.text, 'English العربية');
      bytes = WordSerializer().writeBytes(reopened);
    }
  });

  for (final csFirst in [true, false]) {
    test('regular and complex font writes compose in either order ($csFirst)', () {
      final document = _read(
        _fixture(
          run:
              '<w:rFonts w:ascii="Old Latin" w:hAnsi="Old High" w:cs="Old Complex" '
              'w:eastAsia="East" w:cstheme="majorBidi" w:asciiTheme="majorHAnsi" '
              'w:hAnsiTheme="majorHAnsi" x:keep="font-metadata"/>',
        ),
      );
      final edits = [
        <String, Object?>{'csFont': 'Amiri'},
        <String, Object?>{'font': 'New Latin'},
      ];
      for (final edit in csFirst ? edits : edits.reversed) {
        _run(document, edit);
      }
      final bytes = WordSerializer().writeBytes(document);
      final fonts = _rPr(bytes).firstChild('rFonts', namespaceUri: _w)!;
      expect(fonts.getAttribute('ascii', namespaceUri: _w), 'New Latin');
      expect(fonts.getAttribute('hAnsi', namespaceUri: _w), 'New Latin');
      expect(fonts.getAttribute('cs', namespaceUri: _w), 'Amiri');
      expect(fonts.getAttribute('eastAsia', namespaceUri: _w), 'East');
      expect(fonts.getAttribute('keep', namespaceUri: _x), 'font-metadata');
      for (final theme in ['asciiTheme', 'hAnsiTheme', 'cstheme']) {
        expect(fonts.getAttribute(theme, namespaceUri: _w), isNull);
      }
      final props = _props(_read(bytes));
      expect(props.asciiFont, 'New Latin');
      expect(props.csFont, 'Amiri');
    });
  }

  test(
    'same inherited values become direct without pinning other style fields',
    () {
      final document = _read(
        _fixture(
          run: '<w:rStyle w:val="Character"/>',
          styles:
              '<w:style w:type="character" w:styleId="Character">'
              '<w:name w:val="Character"/><w:rPr>'
              '<w:lang w:val="de-DE" w:bidi="ar-SA"/>'
              '<w:rFonts w:ascii="Latin" w:hAnsi="High" w:cs="Amiri" w:eastAsia="East"/>'
              '<w:color w:val="112233"/></w:rPr></w:style>',
        ),
      );
      expect(_props(document).csFont, 'Amiri');
      expect(_props(document).proofingLanguage, 'de-DE');
      _run(document, {'csFont': 'Amiri', 'language': 'de-DE'});
      final bytes = WordSerializer().writeBytes(document);
      final direct = _rPr(bytes);
      expect(_attribute(direct, 'rFonts', 'cs'), 'Amiri');
      for (final attribute in ['ascii', 'hAnsi', 'eastAsia']) {
        expect(_attribute(direct, 'rFonts', attribute), isNull);
      }
      expect(_attribute(direct, 'lang', 'val'), 'de-DE');
      expect(_attribute(direct, 'lang', 'bidi'), isNull);
      expect(direct.firstChild('color', namespaceUri: _w), isNull);
      final package = OpcPackage.openBytes(bytes);
      final styles = package.getPart('/word/styles.xml')!;
      styles.writeText(
        styles
            .readText()
            .replaceAll('Amiri', 'Other Complex')
            .replaceAll('Latin', 'Other Latin')
            .replaceAll('de-DE', 'fr-FR')
            .replaceAll('ar-SA', 'ar-EG')
            .replaceAll('112233', '445566'),
      );
      final props = _props(WordDeserializer().read(package));
      expect(props.csFont, 'Amiri');
      expect(props.asciiFont, 'Other Latin');
      expect(props.proofingLanguage, 'de-DE');
      expect(props.complexScriptLanguage, 'ar-EG');
      expect(props.color, '445566');
    },
  );

  for (final prefix in ['w', 'q']) {
    test('aliases and foreign/nested lookalikes remain opaque ($prefix)', () {
      final document = _read(
        _fixture(
          prefix: prefix,
          shadowWordPrefix: prefix == 'q',
          run:
              '<$prefix:lang x:val="foreign" $prefix:val="en-US" '
              '$prefix:bidi="ar-SA" x:keep="language"><x:child/></$prefix:lang>'
              '<$prefix:rFonts x:cs="foreign" $prefix:ascii="Latin" '
              '$prefix:cs="Old" $prefix:cstheme="majorBidi" x:cstheme="opaque">'
              '<x:child/></$prefix:rFonts>'
              '<x:lang $prefix:val="fr-FR"/><x:rFonts $prefix:cs="Wrong"/>'
              '<x:container><$prefix:lang $prefix:val="it-IT"/>'
              '<$prefix:rFonts $prefix:cs="Nested"/></x:container>',
        ),
      );
      _run(document, {'language': 'de-DE', 'csFont': 'Amiri'});
      var bytes = WordSerializer().writeBytes(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        final properties = _rPr(bytes);
        final language = properties.firstChild('lang', namespaceUri: _w)!;
        final fonts = properties.firstChild('rFonts', namespaceUri: _w)!;
        expect(language.getAttribute('val', namespaceUri: _x), 'foreign');
        expect(language.getAttribute('keep', namespaceUri: _x), 'language');
        expect(language.firstChild('child', namespaceUri: _x), isNotNull);
        expect(fonts.getAttribute('cs', namespaceUri: _x), 'foreign');
        expect(fonts.getAttribute('cstheme', namespaceUri: _x), 'opaque');
        expect(fonts.firstChild('child', namespaceUri: _x), isNotNull);
        expect(properties.firstChild('lang', namespaceUri: _x), isNotNull);
        expect(properties.firstChild('rFonts', namespaceUri: _x), isNotNull);
        expect(properties.firstChild('container', namespaceUri: _x), isNotNull);
        expect(
          language.attributes.where(
            (a) => a.namespaceUri == _w && a.localName == 'val',
          ),
          hasLength(1),
        );
        expect(
          fonts.attributes.where(
            (a) => a.namespaceUri == _w && a.localName == 'cs',
          ),
          hasLength(1),
        );
        final reopened = _read(bytes);
        expect(_props(reopened).proofingLanguage, 'de-DE');
        expect(_props(reopened).complexScriptLanguage, 'ar-SA');
        expect(_props(reopened).csFont, 'Amiri');
        expect(_props(reopened).asciiFont, 'Latin');
        bytes = WordSerializer().writeBytes(reopened);
      }
    });
  }

  test('old aggregate font snapshots retain legacy font changes', () {
    final document = _read(
      _fixture(run: '<w:rFonts w:ascii="Latin" w:cs="Old" w:eastAsia="East"/>'),
    );
    final props = _props(document);
    props.importedValues!.removeWhere((key, _) => key.startsWith('rFonts:'));
    props.csFont = 'Amiri';
    final direct = _rPr(WordSerializer().writeBytes(document));
    expect(_attribute(direct, 'rFonts', 'ascii'), 'Latin');
    expect(_attribute(direct, 'rFonts', 'cs'), 'Amiri');
    expect(_attribute(direct, 'rFonts', 'eastAsia'), 'East');
  });

  test('same-value native setter upgrades legacy inherited font snapshots', () {
    final document = _read(
      _fixture(
        run: '<w:rStyle w:val="Character"/>',
        styles:
            '<w:style w:type="character" w:styleId="Character">'
            '<w:rPr><w:rFonts w:ascii="Latin" w:cs="Amiri"/></w:rPr></w:style>',
      ),
    );
    _props(
      document,
    ).importedValues!.removeWhere((key, _) => key.startsWith('rFonts:'));
    _run(document, {'csFont': 'Amiri'});
    final direct = _rPr(WordSerializer().writeBytes(document));
    expect(_attribute(direct, 'rFonts', 'cs'), 'Amiri');
    expect(_attribute(direct, 'rFonts', 'ascii'), isNull);
  });

  test(
    'fresh native runs and missing-style fallback retain explicit fonts',
    () {
      final document = WmlDocument.empty(text: 'Text العربية');
      _run(document, {'font': 'Arial', 'csFont': 'Arial', 'language': 'de-DE'});
      final props = _props(document);
      document.styles.add(
        const WmlStyle(
          id: 'Different',
          name: 'Different',
          nameAr: 'Different',
          font: 'Inherited Latin',
          csFont: 'Inherited Complex',
        ),
      );
      document.paragraphs.single.properties.styleId = 'Different';
      WordStyles.resolveOntoParagraph(
        document.paragraphs.single,
        document: document,
      );
      expect(props.asciiFont, 'Arial');
      expect(props.csFont, 'Arial');
      final reopened = _read(WordSerializer().writeBytes(document));
      expect(_props(reopened).asciiFont, 'Arial');
      expect(_props(reopened).csFont, 'Arial');
      expect(_props(reopened).proofingLanguage, 'de-DE');
    },
  );

  test('complex font fallback override leaves the Latin style live', () {
    final document = WmlDocument.empty(text: 'Text العربية');
    document.styles.add(
      const WmlStyle(
        id: 'Different',
        name: 'Different',
        nameAr: 'Different',
        font: 'Inherited Latin',
        csFont: 'Inherited Complex',
      ),
    );
    document.paragraphs.single.properties.styleId = 'Different';
    _run(document, {'csFont': 'Arial'});
    WordStyles.resolveOntoParagraph(
      document.paragraphs.single,
      document: document,
    );
    expect(_props(document).csFont, 'Arial');
    expect(_props(document).asciiFont, 'Inherited Latin');
  });

  for (final slot in ['ascii', 'cs']) {
    test(
      'imported $slot-only font keeps the other fallback style slot live',
      () {
        final package = OpcPackage.create(OpcPackageKind.word);
        package
            .getPart('/word/document.xml')!
            .writeText(
              '<w:document xmlns:w="$_w"><w:body><w:p><w:r><w:rPr>'
              '<w:rFonts w:$slot="Arial"/></w:rPr><w:t>Text العربية</w:t>'
              '</w:r></w:p></w:body></w:document>',
            );
        final document = WordDeserializer().read(package);
        document.styles.add(
          const WmlStyle(
            id: 'Different',
            name: 'Different',
            nameAr: 'Different',
            font: 'Inherited Latin',
            csFont: 'Inherited Complex',
          ),
        );
        document.paragraphs.single.properties.styleId = 'Different';
        WordStyles.resolveOntoParagraph(
          document.paragraphs.single,
          document: document,
        );
        expect(
          _props(document).asciiFont,
          slot == 'ascii' ? 'Arial' : 'Inherited Latin',
        );
        expect(
          _props(document).csFont,
          slot == 'cs' ? 'Arial' : 'Inherited Complex',
        );
      },
    );
  }

  test('foreign style font and language metadata cannot override native slots', () {
    final document = _read(
      _fixture(
        run: '<w:rStyle w:val="Character"/>',
        styles:
            '<w:style w:type="character" w:styleId="Character"><w:rPr>'
            '<w:lang x:val="fr-FR" w:val="de-DE" x:bidi="he-IL" w:bidi="ar-SA"/>'
            '<w:rFonts x:cs="Wrong" w:cs="Amiri" x:ascii="Wrong" w:ascii="Latin"/>'
            '<x:lang w:val="it-IT"/><x:rFonts w:cs="Other"/>'
            '<x:container><w:lang w:val="es-ES"/><w:rFonts w:cs="Nested"/></x:container>'
            '</w:rPr></w:style>',
      ),
    );
    expect(_props(document).proofingLanguage, 'de-DE');
    expect(_props(document).complexScriptLanguage, 'ar-SA');
    expect(_props(document).csFont, 'Amiri');
    expect(_props(document).asciiFont, 'Latin');
    _run(document, {'language': 'en-GB', 'csFont': 'Other Complex'});
    final props = _props(_read(WordSerializer().writeBytes(document)));
    expect(props.proofingLanguage, 'en-GB');
    expect(props.complexScriptLanguage, 'ar-SA');
    expect(props.csFont, 'Other Complex');
    expect(props.asciiFont, 'Latin');
  });

  for (final tag in ['de-DE', 'en-GB', 'sr-Latn-RS', 'es-419', 'de-DE-1996']) {
    test('canonical native language tag $tag is preserved exactly', () {
      final document = _read(_fixture());
      _run(document, {'language': tag});
      expect(
        _props(_read(WordSerializer().writeBytes(document))).proofingLanguage,
        tag,
      );
    });
  }

  for (final entry in <String, List<Object?>>{
    'language': [
      null,
      1031,
      true,
      '',
      'de_de',
      'DE-de',
      'en-US\n',
      'en-US ',
      ' en-US',
      'x-private',
      'de-DE-u-co-phonebk',
      'de-DE-1996-1996',
      'abcd-DE',
      'en-XYZ',
      'a' * 64,
    ],
    'csFont': [
      null,
      12,
      true,
      '',
      'Font\nName',
      'Font\tName',
      'Font\u0000Name',
      '\ud800',
      '\udc00',
      '\ufffe',
    ],
  }.entries) {
    for (final value in entry.value) {
      test('invalid ${entry.key} $value refuses before any run mutation', () {
        final document = _read(_fixture());
        final paragraph = document.paragraphs.single;
        final run = paragraph.inlines.whereType<WmlRun>().single;
        final before = WordSerializer().runPropertiesXml(run.properties);
        expect(
          () => _run(document, {
            'start': 1,
            'end': 4,
            'bold': true,
            entry.key: value,
          }),
          throwsArgumentError,
        );
        expect(paragraph.inlines.whereType<WmlRun>().single, same(run));
        expect(WordSerializer().runPropertiesXml(run.properties), before);
      });
    }
  }

  for (final (name, attributes) in [
    ('lang', '<w:lang w:val="en-US"/><w:lang w:val="de-DE"/>'),
    ('rFonts', '<w:rFonts w:cs="Old"/><w:rFonts w:cs="Other"/>'),
    ('lang', '<w:lang xmlns:q="$_w" q:val="en-US" w:val="de-DE"/>'),
    ('rFonts', '<w:rFonts xmlns:q="$_w" q:cs="Old" w:cs="Other"/>'),
    (
      'rFonts',
      '<w:rFonts xmlns:q="$_w" q:cstheme="majorBidi" w:cstheme="minorBidi"/>',
    ),
  ]) {
    test(
      'duplicate $name property or owned attribute is rejected before splitting: $attributes',
      () {
        final document = _read(
          _fixture(
            body:
                '<w:p><w:r><w:t>First</w:t></w:r><w:r><w:rPr>$attributes</w:rPr>'
                '<w:t>Second</w:t></w:r></w:p>',
          ),
        );
        final paragraph = document.paragraphs.single;
        final runs = paragraph.inlines.whereType<WmlRun>().toList();
        final before = runs
            .map((r) => WordSerializer().runPropertiesXml(r.properties))
            .toList();
        expect(
          () => _run(document, {
            'start': 1,
            'bold': true,
            'language': 'de-DE',
            'csFont': 'Amiri',
          }),
          throwsUnsupportedError,
        );
        expect(paragraph.inlines.whereType<WmlRun>(), runs);
        expect(
          runs.map((r) => WordSerializer().runPropertiesXml(r.properties)),
          before,
        );
      },
    );
  }

  for (final name in ['lang', 'rFonts']) {
    for (final stylePart in [false, true]) {
      test(
        '$name in retained MC alternatives rejects (style part $stylePart)',
        () {
          final attr = name == 'lang' ? 'val' : 'cs';
          final value = name == 'lang' ? 'en-US' : 'Old';
          final alternative =
              '<mc:AlternateContent xmlns:mc="${OfficeNamespaces.mc}">'
              '<mc:Choice Requires="x"><w:$name w:$attr="$value"/></mc:Choice>'
              '<mc:Fallback><w:$name w:$attr="$value"/></mc:Fallback></mc:AlternateContent>';
          final document = _read(
            _fixture(
              run: stylePart ? '' : alternative,
              styles: stylePart
                  ? '<w:style w:type="character" w:styleId="Unused">'
                        '<w:rPr>$alternative</w:rPr></w:style>'
                  : null,
            ),
          );
          final run = document.paragraphs.single.inlines
              .whereType<WmlRun>()
              .single;
          final before = WordSerializer().runPropertiesXml(run.properties);
          expect(
            () => _run(document, {
              'start': 1,
              'bold': true,
              'language': 'de-DE',
              'csFont': 'Amiri',
            }),
            throwsUnsupportedError,
          );
          expect(
            document.paragraphs.single.inlines.whereType<WmlRun>().single,
            same(run),
          );
          expect(WordSerializer().runPropertiesXml(run.properties), before);
        },
      );
    }
  }

  test('preflight covers a citation-expanded range before any formatting', () {
    final document = WmlDocument.empty();
    final paragraph = document.paragraphs.single;
    final citation = ZoteroCitation(
      citationId: 'language-controls',
      plainCitation: 'Book 12',
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {'type': 'book', 'title': 'Book'},
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
        ),
      ],
    );
    final formatted = ZoteroFormattedText.fromHtml('<i>Book</i> 12');
    WordZotero.insertNativeCitation(
      paragraph,
      instruction: citation.fieldInstruction,
      text: formatted.plainText,
      formattedText: formatted,
      index: 0,
    );
    final tail = paragraph.inlines.whereType<WmlRun>().singleWhere(
      (r) => r.text == ' 12',
    );
    tail.properties.sourcePropertiesXml =
        '<w:rPr xmlns:w="$_w">'
        '<w:lang w:val="en-US"/><w:lang w:val="de-DE"/></w:rPr>';
    expect(WmlRunEdit.normalizeRange(paragraph, 1, 2), (start: 0, end: 7));
    final inlines = List<WmlInline>.of(paragraph.inlines);
    expect(
      () => _run(document, {
        'start': 1,
        'end': 2,
        'bold': true,
        'language': 'de-DE',
        'csFont': 'Amiri',
      }),
      throwsUnsupportedError,
    );
    expect(paragraph.inlines, inlines);
    expect(
      paragraph.inlines.whereType<WmlRun>().any((r) => r.properties.bold),
      isFalse,
    );
  });

  test(
    'failed later language write leaves session bytes and recording unchanged',
    () async {
      final input = _fixture();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Language controls');
      final plan = OfficeMacro(
        name: 'Atomic language edits',
        format: OfficeMacroFormat.docx,
        steps: [
          OfficeMacroStep(
            tool: 'docx.runFormat',
            arguments: {'paragraph': 0, 'csFont': 'Amiri'},
          ),
          OfficeMacroStep(
            tool: 'docx.runFormat',
            arguments: {'paragraph': 0, 'language': 'en_US'},
          ),
        ],
      );
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(
            isA<OfficeMacroException>().having(
              (e) => e.stepIndex,
              'stepIndex',
              1,
            ),
          ),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );
}
