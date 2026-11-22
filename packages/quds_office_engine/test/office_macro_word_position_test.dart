import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:position-tests';
const _text = 'Aé😀 العربية';

Uint8List _fixture({
  String run = '',
  String paragraph = '',
  String? body,
  String? styles,
  String? settings,
  String prefix = 'w',
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<$prefix:document xmlns:$prefix="$_w" xmlns:x="$_x"'
        '${prefix == 'q' ? ' xmlns:w="urn:foreign-word-prefix"' : ''}>'
        '<$prefix:body>'
        '${body ?? '<$prefix:p><$prefix:pPr>$paragraph</$prefix:pPr>'
                '<$prefix:r><$prefix:rPr>$run</$prefix:rPr>'
                '<$prefix:t>$_text</$prefix:t></$prefix:r></$prefix:p>'}'
        '<$prefix:sectPr/></$prefix:body></$prefix:document>',
      );
  if (styles != null) {
    package
        .getPart('/word/styles.xml')!
        .writeText('<w:styles xmlns:w="$_w" xmlns:x="$_x">$styles</w:styles>');
  }
  if (settings != null) {
    package
        .getPart('/word/settings.xml')!
        .writeText(
          '<w:settings xmlns:w="$_w" xmlns:q="$_w" xmlns:x="$_x" '
          'xmlns:mc="${OfficeNamespaces.mc}">$settings</w:settings>',
        );
  }
  return package.save();
}

WmlDocument _read(Uint8List bytes) => WordDeserializer().readBytes(bytes);
WmlRunProps _props(WmlDocument document) =>
    document.paragraphs.single.inlines.whereType<WmlRun>().single.properties;
XmlElement _rPr(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .firstChild('p', namespaceUri: _w)!
        .firstChild('r', namespaceUri: _w)!
        .firstChild('rPr', namespaceUri: _w)!;
String? _position(Uint8List bytes) => _rPr(bytes)
    .firstChild('position', namespaceUri: _w)
    ?.getAttribute('val', namespaceUri: _w);
void _run(WmlDocument document, Map<String, Object?> fields) =>
    native.applyStep(document, {'op': 'runFormat', 'paragraph': 0, ...fields});

void main() {
  for (final points in [-1584, -2.5, 0, 3, 1584]) {
    test('native position $points points survives save/reopen and copying', () {
      var document = _read(_fixture(run: '<w:sz w:val="28"/><w:i/>'));
      _run(document, {'position': points});
      for (var cycle = 0; cycle < 3; cycle++) {
        final props = _props(document);
        expect(props.positionHalfPoints, points * 2);
        expect(props.copy().positionHalfPoints, points * 2);
        expect(props.fontSizeHalfPoints, 28);
        expect(props.italic, isTrue);
        final bytes = WordSerializer().writeBytes(document);
        expect(_position(bytes), '${(points * 2).toInt()}');
        document = _read(bytes);
        expect(document.paragraphs.single.text, _text);
      }
    });
  }

  test('authored default omits position; explicit zero emits an override', () {
    final document = WmlDocument.empty(text: _text);
    expect(_position(WordSerializer().writeBytes(document)), isNull);
    _run(document, {'position': 0});
    expect(_position(WordSerializer().writeBytes(document)), '0');
  });

  for (final entry in [
    ('<w:compat><w:noSpaceRaiseLower/></w:compat>', true),
    ('<q:compat><q:noSpaceRaiseLower q:val="on"/></q:compat>', true),
    ('<w:compat><w:noSpaceRaiseLower w:val="0"/></w:compat>', false),
    ('<w:compat><x:noSpaceRaiseLower/></w:compat>', false),
    ('<x:compat><w:noSpaceRaiseLower/></x:compat>', false),
    ('<w:compat><x:opaque><w:noSpaceRaiseLower/></x:opaque></w:compat>', false),
  ]) {
    test('native noSpaceRaiseLower setting ${entry.$1} stays preserved', () {
      final source = _fixture(settings: entry.$1);
      final document = _read(source);
      expect(document.sourceNoSpaceRaiseLower, entry.$2);
      _run(document, {'position': -30});
      final saved = WordSerializer().writeBytes(document);
      expect(_props(_read(saved)).positionHalfPoints, -60);
      expect(_read(saved).sourceNoSpaceRaiseLower, entry.$2);
      expect(
        OpcPackage.openBytes(saved).getPart('/word/settings.xml')!.readText(),
        OpcPackage.openBytes(source).getPart('/word/settings.xml')!.readText(),
      );
    });
  }

  test(
    'position refuses ambiguous compatibility settings before formatting',
    () {
      final document = _read(
        _fixture(
          settings:
              '<w:compat><mc:AlternateContent><mc:Choice Requires="x">'
              '<w:noSpaceRaiseLower/></mc:Choice><mc:Fallback/>'
              '</mc:AlternateContent></w:compat>',
        ),
      );
      expect(
        () => _run(document, {'position': 2, 'bold': true}),
        throwsUnsupportedError,
      );
      expect(_props(document).positionHalfPoints, 0);
      expect(_props(document).bold, isFalse);
      expect(document.paragraphs.single.inlines, hasLength(1));
    },
  );

  for (final properties in [
    '<x:rPr/>',
    '<x:rPr><w:position w:val="6"/></x:rPr>',
    '<w:rPr><w:position w:val="2"/></w:rPr>'
        '<w:rPr><w:position w:val="4"/></w:rPr>',
    '<w:rPr/><x:rPr><w:position w:val="6"/></x:rPr>',
    '<x:opaque><w:rPr><w:position w:val="4"/></w:rPr></x:opaque>',
  ]) {
    test('position refuses ambiguous run-property ownership: $properties', () {
      final document = _read(
        _fixture(
          body:
              '<w:p>'
              '<w:r><w:t>First</w:t></w:r>'
              '<w:r>$properties<w:t>Second</w:t></w:r></w:p>',
        ),
      );
      final runs = document.paragraphs.single.inlines
          .whereType<WmlRun>()
          .toList();
      final before = runs
          .map((run) => run.properties.positionHalfPoints)
          .toList();
      expect(
        () => _run(document, {'position': 2, 'bold': true}),
        throwsUnsupportedError,
      );
      expect(document.paragraphs.single.inlines, hasLength(2));
      expect(runs.map((run) => run.properties.positionHalfPoints), before);
      expect(runs.map((run) => run.properties.bold), everyElement(isFalse));
    });
  }

  for (final points in [-4, 0, 4]) {
    test('inherited position $points becomes direct without pinning color', () {
      final document = _read(
        _fixture(
          run: '<w:rStyle w:val="Character"/>',
          styles:
              '<w:style w:type="character" w:styleId="Character"><w:rPr>'
              '<w:position w:val="8"/><w:color w:val="112233"/>'
              '</w:rPr></w:style>',
        ),
      );
      expect(_props(document).positionHalfPoints, 8);
      _run(document, {'position': points});
      final bytes = WordSerializer().writeBytes(document);
      expect(_position(bytes), '${points * 2}');
      expect(_rPr(bytes).firstChild('color', namespaceUri: _w), isNull);
      final package = OpcPackage.openBytes(bytes);
      final styles = package.getPart('/word/styles.xml')!;
      styles.writeText(
        styles
            .readText()
            .replaceAll('112233', '445566')
            .replaceAll('w:val="8"', 'w:val="12"'),
      );
      final changed = WordDeserializer().read(package);
      expect(_props(changed).positionHalfPoints, points * 2);
      expect(_props(changed).color, '445566');
    });
  }

  test(
    'default and paragraph style position remains sparse on unrelated edits',
    () {
      final document = _read(
        _fixture(
          paragraph: '<w:pStyle w:val="Body"/>',
          styles:
              '<w:docDefaults><w:rPrDefault><w:rPr>'
              '<w:position w:val="-3"/></w:rPr></w:rPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:styleId="Body"><w:rPr>'
              '<w:color w:val="112233"/></w:rPr></w:style>',
        ),
      );
      expect(_props(document).positionHalfPoints, -3);
      _run(document, {'bold': true});
      final bytes = WordSerializer().writeBytes(document);
      expect(_position(bytes), isNull);
      expect(_props(_read(bytes)).positionHalfPoints, -3);
      _props(document).positionHalfPoints = 0;
      final reset = WordSerializer().writeBytes(document);
      expect(_position(reset), '0');
      expect(_props(_read(reset)).positionHalfPoints, 0);
    },
  );

  for (final prefix in ['w', 'q']) {
    test(
      'position preserves namespace aliases and foreign metadata ($prefix)',
      () {
        final document = _read(
          _fixture(
            prefix: prefix,
            run:
                '<$prefix:position $prefix:val="3" x:val="foreign" x:keep="yes">'
                '<x:child/></$prefix:position>'
                '<x:position $prefix:val="20"/>'
                '<x:opaque><$prefix:position $prefix:val="30"/></x:opaque>'
                '<$prefix:lang $prefix:val="de-DE" $prefix:bidi="ar-SA"/>'
                '<$prefix:sz $prefix:val="28"/>',
          ),
        );
        expect(_props(document).positionHalfPoints, 3);
        _run(document, {'position': -2.5});
        var bytes = WordSerializer().writeBytes(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          final props = _rPr(bytes);
          final position = props.firstChild('position', namespaceUri: _w)!;
          expect(position.getAttribute('val', namespaceUri: _w), '-5');
          expect(position.getAttribute('val', namespaceUri: _x), 'foreign');
          expect(position.getAttribute('keep', namespaceUri: _x), 'yes');
          expect(position.firstChild('child', namespaceUri: _x), isNotNull);
          expect(props.firstChild('position', namespaceUri: _x), isNotNull);
          expect(props.firstChild('opaque', namespaceUri: _x), isNotNull);
          final reopened = _read(bytes);
          expect(_props(reopened).positionHalfPoints, -5);
          expect(_props(reopened).fontSizeHalfPoints, 28);
          expect(_props(reopened).proofingLanguage, 'de-DE');
          bytes = WordSerializer().writeBytes(reopened);
        }
      },
    );
  }

  test('foreign and nested position lookalikes never become formatting', () {
    final document = _read(
      _fixture(
        run:
            '<x:position w:val="40"/>'
            '<x:opaque><w:position w:val="50"/></x:opaque>',
      ),
    );
    expect(_props(document).positionHalfPoints, 0);
    _run(document, {'position': 1});
    expect(
      _props(_read(WordSerializer().writeBytes(document))).positionHalfPoints,
      2,
    );
  });

  test(
    'style inheritance uses native position identity and arithmetic values',
    () {
      final document = _read(
        _fixture(
          run: '<w:rStyle w:val="Derived"/>',
          styles:
              '<w:style w:type="character" w:styleId="Base">'
              '<w:rPr><w:position w:val="10"/></w:rPr></w:style>'
              '<w:style xmlns:q="$_w" w:type="character" w:styleId="Derived">'
              '<w:basedOn w:val="Base"/><w:rPr><q:position q:val="-3"/>'
              '<x:position q:val="80"/>'
              '<x:opaque><q:position q:val="100"/></x:opaque>'
              '</w:rPr></w:style>',
        ),
      );
      expect(_props(document).positionHalfPoints, -3);
      _run(document, {'position': 0});
      expect(
        _props(_read(WordSerializer().writeBytes(document))).positionHalfPoints,
        0,
      );
    },
  );

  for (final value in <Object?>[
    -1584.5,
    1584.5,
    0.25,
    double.nan,
    double.infinity,
    null,
    true,
    '2',
    <Object?>[],
  ]) {
    test(
      'invalid native position $value refuses before splitting or formatting',
      () {
        final document = _read(_fixture());
        final paragraph = document.paragraphs.single;
        final run = paragraph.inlines.whereType<WmlRun>().single;
        final before = WordSerializer().runPropertiesXml(run.properties);
        expect(
          () => _run(document, {
            'start': 0,
            'end': 1,
            'bold': true,
            'position': value,
          }),
          throwsArgumentError,
        );
        expect(paragraph.inlines.whereType<WmlRun>().single, same(run));
        expect(WordSerializer().runPropertiesXml(run.properties), before);
      },
    );
  }

  for (final invalid in [
    '<w:position/>',
    '<w:position val="2"/>',
    '<w:position w:val="2pt"/>',
    '<w:position w:val="2.5"/>',
    '<w:position w:val="0x10"/>',
    '<w:position w:val="2147483648"/>',
    '<w:position w:val="2"/><w:position w:val="4"/>',
    '<w:position w:val="2" xmlns:q="$_w" q:val="4"/>',
    '<w:position w:val="2"><w:position w:val="4"/></w:position>',
  ]) {
    test(
      'late unsupported native position is refused before any run changes: $invalid',
      () {
        final document = _read(
          _fixture(
            body:
                '<w:p><w:r><w:t>first</w:t></w:r>'
                '<w:r><w:rPr>$invalid</w:rPr><w:t>last</w:t></w:r></w:p>',
          ),
        );
        final runs = document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .toList();
        final before = runs
            .map((run) => WordSerializer().runPropertiesXml(run.properties))
            .toList();
        expect(
          () => _run(document, {'bold': true, 'position': 2}),
          throwsUnsupportedError,
        );
        expect(
          document.paragraphs.single.inlines.whereType<WmlRun>(),
          orderedEquals(runs),
        );
        expect(
          runs.map((run) => WordSerializer().runPropertiesXml(run.properties)),
          before,
        );
      },
    );
  }

  test(
    'partial positions preserve source boundaries, text and other formats',
    () {
      final document = _read(_fixture(run: '<w:i/><w:color w:val="123456"/>'));
      _run(document, {'start': 1, 'end': 4, 'position': 2});
      final reopened = _read(WordSerializer().writeBytes(document));
      final runs = reopened.paragraphs.single.inlines
          .whereType<WmlRun>()
          .toList();
      expect(runs.map((run) => run.text), ['A', 'é😀', ' العربية']);
      expect(runs.map((run) => run.properties.positionHalfPoints), [0, 4, 0]);
      expect(runs.map((run) => run.properties.italic), everyElement(isTrue));
      expect(runs.map((run) => run.properties.color), everyElement('123456'));
    },
  );

  test(
    'unlike authored positions cannot coalesce even without source metadata',
    () {
      final paragraph = WmlParagraph(
        inlines: [
          WmlRun(text: 'a', properties: WmlRunProps(positionHalfPoints: 4)),
          WmlRun(text: 'b', properties: WmlRunProps(positionHalfPoints: -4)),
        ],
      );
      WmlRunEdit.coalesce(paragraph);
      expect(paragraph.inlines, hasLength(2));
    },
  );

  test(
    'position and superscript/subscript remain independent through publication',
    () {
      for (final script in ['superscript', 'subscript']) {
        final document = _read(_fixture(run: '<w:sz w:val="28"/>'));
        _run(document, {script: true, 'position': 3});
        final reopened = _read(WordSerializer().writeBytes(document));
        final props = _props(reopened);
        expect(props.positionHalfPoints, 6);
        expect(props.vertAlign.name, script);
        expect(props.fontSizeHalfPoints, 28);
        _run(reopened, {script: false});
        expect(_props(reopened).positionHalfPoints, 6);
        expect(_props(reopened).vertAlign, WmlVertAlign.baseline);
      }
    },
  );
}
