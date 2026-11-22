import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:all-caps-tests';

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
                '<$prefix:t>Straße Ελληνικά العربية</$prefix:t></$prefix:r></$prefix:p>'}'
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

String? _val(XmlElement properties, String name) => properties
    .firstChild(name, namespaceUri: _w)
    ?.getAttribute('val', namespaceUri: _w);

void _run(WmlDocument document, Map<String, Object?> fields) =>
    native.applyStep(document, {'op': 'runFormat', 'paragraph': 0, ...fields});

void main() {
  for (final value in [true, false]) {
    test('authored allCaps $value survives native save and reopen', () async {
      var document = WmlDocument.empty(text: 'Straße Ελληνικά العربية');
      _props(document).allCaps = value;
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(document);
        expect(_val(_rPr(bytes), 'caps'), value ? '1' : '0');
        document = _read(bytes);
        expect(_props(document).allCaps, value);
        expect(document.paragraphs.single.text, 'Straße Ελληνικά العربية');
      }
    });
  }

  for (final (source, enabled) in [
    ('<w:caps/>', true),
    ('<w:caps w:val="1"/>', true),
    ('<w:caps w:val="true"/>', true),
    ('<w:caps w:val="on"/>', true),
    ('<w:caps w:val="0"/>', false),
    ('<w:caps w:val="false"/>', false),
    ('<w:caps w:val="off"/>', false),
  ]) {
    test('native on/off projection accepts $source without rewriting it', () {
      var bytes = _fixture(run: source);
      final original = XmlDocument(
        root: _rPr(bytes).firstChild('caps', namespaceUri: _w)!,
      ).toXmlString(declaration: false);
      for (var cycle = 0; cycle < 3; cycle++) {
        final document = _read(bytes);
        expect(_props(document).allCaps, enabled);
        bytes = WordSerializer().writeBytes(document);
        expect(
          XmlDocument(
            root: _rPr(bytes).firstChild('caps', namespaceUri: _w)!,
          ).toXmlString(declaration: false),
          original,
        );
      }
    });
  }

  for (final (property, opposite) in [
    ('allCaps', 'smallCaps'),
    ('smallCaps', 'allCaps'),
  ]) {
    test('$property true clears the opposite mode; false leaves it intact', () {
      final document = _read(_fixture(run: '<w:caps/><w:smallCaps/>'));
      _run(document, {property: false});
      final before = _props(document);
      expect(
        property == 'allCaps' ? before.allCaps : before.smallCaps,
        isFalse,
      );
      expect(opposite == 'allCaps' ? before.allCaps : before.smallCaps, isTrue);
      _run(document, {property: true});
      var bytes = WordSerializer().writeBytes(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(
          _val(_rPr(bytes), property == 'allCaps' ? 'caps' : 'smallCaps'),
          '1',
        );
        expect(
          _val(_rPr(bytes), opposite == 'allCaps' ? 'caps' : 'smallCaps'),
          '0',
        );
        final reopened = _read(bytes);
        final props = _props(reopened);
        expect(property == 'allCaps' ? props.allCaps : props.smallCaps, isTrue);
        expect(
          opposite == 'allCaps' ? props.allCaps : props.smallCaps,
          isFalse,
        );
        expect(reopened.paragraphs.single.text, 'Straße Ελληνικά العربية');
        bytes = WordSerializer().writeBytes(reopened);
      }
    });
  }

  for (final fields in <Map<String, Object?>>[
    {'allCaps': true, 'smallCaps': false},
    {'allCaps': false, 'smallCaps': true},
    {'allCaps': false, 'smallCaps': false},
  ]) {
    test('consistent combined capitalization values $fields compose', () {
      final document = _read(_fixture());
      _run(document, fields);
      final reopened = _read(WordSerializer().writeBytes(document));
      expect(_props(reopened).allCaps, fields['allCaps']);
      expect(_props(reopened).smallCaps, fields['smallCaps']);
    });
  }

  for (final fields in <Map<String, Object?>>[
    {'allCaps': true, 'smallCaps': true},
    {'allCaps': null},
    {'allCaps': 0},
    {'allCaps': -1},
    {'allCaps': 'True'},
    {'allCaps': true, 'color': 'invalid'},
  ]) {
    test(
      'invalid capitalization $fields refuses before splitting or mutation',
      () {
        final document = _read(_fixture());
        final paragraph = document.paragraphs.single;
        final run = paragraph.inlines.whereType<WmlRun>().single;
        final before = WordSerializer().runPropertiesXml(run.properties);
        expect(
          () => _run(document, {'start': 1, 'end': 4, 'bold': true, ...fields}),
          throwsArgumentError,
        );
        expect(paragraph.inlines.whereType<WmlRun>().single, same(run));
        expect(WordSerializer().runPropertiesXml(run.properties), before);
      },
    );
  }

  test(
    'partial capitalization retains text, mixed formatting and source boundaries',
    () {
      final document = _read(_fixture(run: '<w:i/><w:color w:val="123456"/>'));
      _run(document, {'start': 1, 'end': 6, 'allCaps': true});
      final reopened = _read(WordSerializer().writeBytes(document));
      final runs = reopened.paragraphs.single.inlines
          .whereType<WmlRun>()
          .toList();
      expect(runs.map((run) => run.text), ['S', 'traße', ' Ελληνικά العربية']);
      expect(runs.map((run) => run.properties.allCaps), [false, true, false]);
      expect(runs.map((run) => run.properties.italic), everyElement(isTrue));
      expect(runs.map((run) => run.properties.color), everyElement('123456'));
    },
  );

  for (final value in [true, false]) {
    test(
      'same inherited allCaps $value becomes direct without pinning other styles',
      () {
        final document = _read(
          _fixture(
            run: '<w:rStyle w:val="Character"/>',
            styles:
                '<w:style w:type="character" w:styleId="Character"><w:rPr>'
                '<w:caps w:val="${value ? 1 : 0}"/><w:smallCaps w:val="0"/>'
                '<w:color w:val="112233"/></w:rPr></w:style>',
          ),
        );
        expect(_props(document).allCaps, value);
        _run(document, {'allCaps': value});
        final bytes = WordSerializer().writeBytes(document);
        final direct = _rPr(bytes);
        expect(_val(direct, 'caps'), value ? '1' : '0');
        expect(direct.firstChild('color', namespaceUri: _w), isNull);
        expect(_val(direct, 'smallCaps'), value ? '0' : isNull);
        final package = OpcPackage.openBytes(bytes);
        final styles = package.getPart('/word/styles.xml')!;
        styles.writeText(
          styles
              .readText()
              .replaceAll(
                '<w:caps w:val="${value ? 1 : 0}"/>',
                '<w:caps w:val="${value ? 0 : 1}"/>',
              )
              .replaceAll('<w:smallCaps w:val="0"/>', '<w:smallCaps/>')
              .replaceAll('112233', '445566'),
        );
        final changed = WordDeserializer().read(package);
        expect(_props(changed).allCaps, value);
        expect(_props(changed).smallCaps, !value);
        expect(_props(changed).color, '445566');
      },
    );
  }

  for (final (derived, expected) in [
    ('<q:caps/>', false),
    ('<q:caps q:val="0"/>', true),
  ]) {
    test(
      'style caps toggles respect basedOn and alternate namespaces: $derived',
      () {
        final document = _read(
          _fixture(
            run: '<w:rStyle w:val="Derived"/>',
            styles:
                '<w:style w:type="character" w:styleId="Base"><w:rPr><w:caps/></w:rPr></w:style>'
                '<w:style xmlns:q="$_w" w:type="character" w:styleId="Derived">'
                '<w:basedOn w:val="Base"/><w:rPr>$derived'
                '<x:caps q:val="0"/><x:opaque><q:caps q:val="0"/></x:opaque>'
                '</w:rPr></w:style>',
          ),
        );
        expect(_props(document).allCaps, expected);
        _run(document, {'allCaps': false});
        final reopened = _read(WordSerializer().writeBytes(document));
        expect(_props(reopened).allCaps, isFalse);
      },
    );
  }

  test(
    'default and paragraph style capitalization remains sparse on unrelated writes',
    () {
      final document = _read(
        _fixture(
          paragraph: '<w:pStyle w:val="Body"/>',
          styles:
              '<w:docDefaults><w:rPrDefault><w:rPr><w:caps/></w:rPr></w:rPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:styleId="Body"><w:rPr><w:color w:val="112233"/></w:rPr></w:style>',
        ),
      );
      expect(_props(document).allCaps, isTrue);
      _run(document, {'bold': true});
      final bytes = WordSerializer().writeBytes(document);
      expect(_rPr(bytes).firstChild('caps', namespaceUri: _w), isNull);
      expect(_props(_read(bytes)).allCaps, isTrue);
    },
  );

  for (final prefix in ['w', 'q']) {
    test('allCaps preserves namespace aliases and foreign metadata ($prefix)', () {
      final document = _read(
        _fixture(
          prefix: prefix,
          shadowWordPrefix: prefix == 'q',
          run:
              '<$prefix:caps $prefix:val="0" x:val="foreign" x:keep="caps"><x:child/></$prefix:caps>'
              '<$prefix:smallCaps $prefix:val="1" x:keep="small"><x:child/></$prefix:smallCaps>'
              '<x:caps $prefix:val="0"/>'
              '<x:container><$prefix:caps $prefix:val="0"/></x:container>'
              '${prefix == 'q' ? '<w:caps w:val="0"/>' : ''}'
              '<$prefix:lang $prefix:val="de-DE" $prefix:bidi="ar-SA" $prefix:eastAsia="ja-JP"/>'
              '<$prefix:rFonts $prefix:ascii="Latin" $prefix:cs="Complex" $prefix:eastAsia="East"/>',
        ),
      );
      _run(document, {'allCaps': true, 'bold': true});
      var bytes = WordSerializer().writeBytes(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        final direct = _rPr(bytes);
        final caps = direct.firstChild('caps', namespaceUri: _w)!;
        expect(caps.getAttribute('val', namespaceUri: _w), '1');
        expect(caps.getAttribute('val', namespaceUri: _x), 'foreign');
        expect(caps.getAttribute('keep', namespaceUri: _x), 'caps');
        expect(caps.firstChild('child', namespaceUri: _x), isNotNull);
        final small = direct.firstChild('smallCaps', namespaceUri: _w)!;
        expect(small.getAttribute('val', namespaceUri: _w), '0');
        expect(small.getAttribute('keep', namespaceUri: _x), 'small');
        expect(small.firstChild('child', namespaceUri: _x), isNotNull);
        expect(direct.firstChild('caps', namespaceUri: _x), isNotNull);
        expect(direct.firstChild('container', namespaceUri: _x), isNotNull);
        if (prefix == 'q') {
          expect(
            direct.firstChild('caps', namespaceUri: 'urn:foreign-word-prefix'),
            isNotNull,
          );
        }
        final reopened = _read(bytes);
        expect(_props(reopened).allCaps, isTrue);
        expect(_props(reopened).smallCaps, isFalse);
        expect(_props(reopened).bold, isTrue);
        expect(_props(reopened).proofingLanguage, 'de-DE');
        expect(_props(reopened).complexScriptLanguage, 'ar-SA');
        expect(_props(reopened).csFont, 'Complex');
        bytes = WordSerializer().writeBytes(reopened);
      }
    });
  }

  test('foreign and nested caps lookalikes do not activate the live model', () {
    final document = _read(
      _fixture(run: '<x:caps w:val="1"/><x:opaque><w:caps/></x:opaque>'),
    );
    expect(_props(document).allCaps, isFalse);
    _run(document, {'allCaps': false});
    final bytes = WordSerializer().writeBytes(document);
    expect(_val(_rPr(bytes), 'caps'), '0');
    expect(_rPr(bytes).firstChild('caps', namespaceUri: _x), isNotNull);
    expect(_rPr(bytes).firstChild('opaque', namespaceUri: _x), isNotNull);
    expect(_props(_read(bytes)).allCaps, isFalse);
  });

  test(
    'pending native property changes survive capitalization mode changes',
    () {
      final document = _read(
        _fixture(run: '<w:caps/><w:color w:val="112233"/>'),
      );
      final props = _props(document);
      props.color = '445566';
      props.asciiFont = 'Changed Latin';
      _run(document, {'smallCaps': true});
      _run(document, {'allCaps': true});
      final reopened = _read(WordSerializer().writeBytes(document));
      expect(_props(reopened).allCaps, isTrue);
      expect(_props(reopened).smallCaps, isFalse);
      expect(_props(reopened).color, '445566');
      expect(_props(reopened).asciiFont, 'Changed Latin');
    },
  );

  for (final (property, markup) in [
    ('caps', '<w:caps/><w:caps w:val="0"/>'),
    ('smallCaps', '<w:smallCaps/><w:smallCaps w:val="0"/>'),
    ('caps', '<w:caps xmlns:q="$_w" w:val="1" q:val="0"/>'),
    ('smallCaps', '<w:smallCaps xmlns:q="$_w" w:val="1" q:val="0"/>'),
  ]) {
    test(
      'allCaps preflights late duplicate $property before editing any run',
      () {
        final document = _read(
          _fixture(
            body:
                '<w:p><w:r><w:t>Early</w:t></w:r>'
                '<w:r><w:rPr>$markup</w:rPr><w:t>Late</w:t></w:r></w:p>',
          ),
        );
        final paragraph = document.paragraphs.single;
        final runs = paragraph.inlines.whereType<WmlRun>().toList();
        final before = [
          for (final run in runs)
            WordSerializer().runPropertiesXml(run.properties),
        ];
        expect(
          () => _run(document, {
            'start': 1,
            'end': 8,
            'allCaps': true,
            'bold': true,
          }),
          throwsUnsupportedError,
        );
        expect(paragraph.inlines.whereType<WmlRun>().toList(), runs);
        expect([
          for (final run in runs)
            WordSerializer().runPropertiesXml(run.properties),
        ], before);
      },
    );
  }

  for (final property in ['caps', 'smallCaps']) {
    test(
      'allCaps refuses raw package alternatives owning $property before mutation',
      () {
        final alternate =
            '<mc:AlternateContent xmlns:mc="${OfficeNamespaces.mc}" xmlns:other="urn:unsupported">'
            '<mc:Choice Requires="other"><w:$property/></mc:Choice>'
            '<mc:Fallback><w:$property w:val="0"/></mc:Fallback></mc:AlternateContent>';
        final document = _read(_fixture(run: alternate));
        final run = document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single;
        final before = WordSerializer().runPropertiesXml(run.properties);
        expect(
          () => _run(document, {'allCaps': true, 'bold': true}),
          throwsUnsupportedError,
        );
        expect(WordSerializer().runPropertiesXml(run.properties), before);
        expect(
          document.paragraphs.single.inlines.whereType<WmlRun>().single,
          same(run),
        );
      },
    );
  }

  test(
    'failed allCaps plans do not publish or record earlier operations',
    () async {
      final input = _fixture();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('all caps rollback');
      final plan = OfficeMacro(
        name: 'all caps rollback',
        format: OfficeMacroFormat.docx,
        steps: [
          OfficeMacroStep(
            tool: 'docx.runFormat',
            arguments: {'paragraph': 0, 'allCaps': true},
          ),
          OfficeMacroStep(
            tool: 'docx.runFormat',
            arguments: {'paragraph': 99, 'bold': true},
          ),
        ],
      );
      await expectLater(
        session.run(plan),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
      expect(session.stopRecording().steps, isEmpty);
    },
  );
}
