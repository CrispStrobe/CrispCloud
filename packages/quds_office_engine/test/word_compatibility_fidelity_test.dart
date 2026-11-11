import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_markup_compatibility.dart';
import 'package:test/test.dart';

const String _fixture = 'test/fixtures/fidelity/word-compatibility.docx';
const String _output = 'build/fidelity-word-compatibility';

WmlDocument _readFixture() =>
    WordDeserializer().readBytes(File(_fixture).readAsBytesSync());

List<String> _paragraphs(WmlDocument document) => <String>[
  for (final WmlParagraph paragraph in document.paragraphs) paragraph.text,
];

List<XmlElement> _sections(OpcPackage package) {
  final XmlElement body = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!.firstChild('body')!;
  return <XmlElement>[
    for (final XmlElement child in body.childElements)
      if (child.localName == 'sectPr')
        child
      else if (child.localName == 'p' &&
          child.firstChild('pPr')?.firstChild('sectPr') != null)
        child.firstChild('pPr')!.firstChild('sectPr')!,
  ];
}

String? _attribute(XmlElement section, String child, String attribute) =>
    section.firstChild(child)?.getAttribute(attribute);

void _assertSourceProperties(OpcPackage package, {required bool edited}) {
  final List<XmlElement> sections = _sections(package);
  expect(sections, hasLength(2));
  for (int index = 0; index < sections.length; index++) {
    final XmlElement section = sections[index];
    expect(_attribute(section, 'pgNumType', 'start'), index == 0 ? '17' : '31');
    expect(_attribute(section, 'pgSz', 'code'), '9');
    expect(_attribute(section, 'pgMar', 'gutter'), index == 0 ? '240' : '120');
    expect(
      _attribute(section, 'docGrid', 'linePitch'),
      index == 0 ? '360' : '400',
    );
    expect(
      _attribute(section, 'docGrid', 'type'),
      index == 0 ? 'lines' : 'linesAndChars',
    );
  }
  final XmlElement first = sections.first;
  expect(first.getAttribute('rsidSect'), '44556677');
  expect(_attribute(first, 'paperSrc', 'first'), '256');
  expect(
    first.firstChild('pgBorders')!.firstChild('top')!.getAttribute('color'),
    '884422',
  );
  expect(
    first.firstChild('footnotePr')!.firstChild('numStart')!.getAttribute('val'),
    '4',
  );
  expect(_attribute(first, 'vAlign', 'val'), 'center');
  expect(first.firstChild('bidi'), isNotNull);
  expect(first.firstChild('rtlGutter'), isNotNull);
  expect(
    first
        .firstChild('sectPrChange')!
        .firstChild('sectPr')!
        .firstChild('pgNumType')!
        .getAttribute('start'),
    '99',
  );
  if (edited) {
    expect(_attribute(first, 'pgSz', 'w'), '12240');
    expect(_attribute(first, 'pgMar', 'left'), '1800');
    expect(_attribute(first, 'cols', 'num'), '3');
    expect(_attribute(first, 'cols', 'equalWidth'), '1');
    expect(first.firstChild('cols')!.childrenNamed('col'), isEmpty);
    expect(first.firstChild('lnNumType'), isNull);
    expect(first.firstChild('titlePg'), isNull);
  } else {
    expect(_attribute(first, 'pgSz', 'w'), '15840');
    expect(_attribute(first, 'lnNumType', 'countBy'), '5');
    expect(_attribute(first, 'lnNumType', 'distance'), '240');
    expect(_attribute(first, 'lnNumType', 'restart'), 'newSection');
    expect(first.firstChild('cols')!.childrenNamed('col'), hasLength(2));
    expect(first.firstChild('titlePg'), isNotNull);
  }
  // An explicitly disabled setting remains sparse and is not enabled merely
  // because its on/off element was present in the input.
  expect(_attribute(sections.last, 'titlePg', 'val'), '0');
}

void main() {
  test('MC selects one supported Choice or Fallback in every Word story', () {
    final WmlDocument document = _readFixture();
    final Map<String, Object?> expected =
        jsonDecode(
              File(
                'test/fixtures/fidelity/word_compatibility_expected.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(_paragraphs(document), expected['body_paragraphs']);
    expect(document.sections, hasLength(2));
    expect(
      document.sections.first.header.single.text,
      expected['default_header'],
    );
    expect(
      document.sections.first.firstHeader.single.text,
      expected['first_header'],
    );
    expect(
      document.footnotes.single.paragraphs.single.text,
      expected['footnote'],
    );
    expect(document.sections.first.pageSize.width, 792);
    expect(document.sections.first.pageSize.height, 612);
    expect(document.sections.first.lineNumbers, isTrue);
    expect(document.sections.first.differentFirstPage, isTrue);
    expect(document.sections.last.differentFirstPage, isFalse);
  });

  test(
    'Requires resolves aliases in scope and rejects unbound or partial namespaces',
    () {
      final String xml =
          '<root xmlns:mc="${OfficeNamespaces.mc}" '
          'xmlns:alias="urn:unsupported">'
          '<mc:AlternateContent>'
          '<mc:Choice Requires="unbound"><value>unbound</value></mc:Choice>'
          '<mc:Choice Requires="alias"><value>wrong namespace</value></mc:Choice>'
          '<mc:Choice xmlns:alias="${OfficeNamespaces.w}" Requires="alias">'
          '<value>selected</value></mc:Choice>'
          '<mc:Fallback><value>fallback</value></mc:Fallback>'
          '</mc:AlternateContent></root>';
      final WordMarkupCompatibilityReader reader =
          WordMarkupCompatibilityReader(xml);
      final List<String> text = <String>[];
      while (reader.next()) {
        if (reader.eventType == XmlEventType.characters) text.add(reader.text);
      }
      expect(text, <String>['selected']);
    },
  );

  for (final bool edited in <bool>[false, true]) {
    test(
      'source section properties survive ${edited ? 'modeled edits' : 'unrelated edits'} over three saves',
      () async {
        WmlDocument document = _readFixture();
        document.paragraphs.first.inlines.whereType<WmlRun>().first.text =
            'Edited compatibility text';
        if (edited) {
          final WmlSection first = document.sections.first;
          first.pageSize = WmlPageSize.letter();
          first.margins = first.margins.copyWith(left: 90);
          first.columnCount = 3;
          first.columnSpace = 24;
          first.columnSep = false;
          first.lineNumbers = false;
          first.differentFirstPage = false;
        }
        for (int cycle = 1; cycle <= 3; cycle++) {
          final Uint8List bytes = await OfficeIsolateSave.word(document);
          final OpcPackage package = OpcPackage.openBytes(bytes);
          _assertSourceProperties(package, edited: edited);
          final String xml = package.getPart('/word/document.xml')!.readText();
          expect(xml, isNot(contains('UNSELECTED')));
          expect(xml, contains('Edited compatibility text'));
          final File output = File(
            '$_output/compatibility-${edited ? 'edited' : 'imported'}-$cycle.docx',
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes);
          document = WordDeserializer().read(package);
          expect(
            document.sections.first.firstHeader.single.text,
            'First page header retained',
          );
          expect(document.sections.first.pageSize.width, edited ? 612 : 792);
        }
      },
    );
  }

  test(
    'section clone carries independent stories and immutable imported metadata',
    () {
      final WmlSection source = _readFixture().sections.first;
      final WmlSection copy = WmlClone.section(source);
      expect(copy.sourceProperties, same(source.sourceProperties));
      expect(copy.firstHeader.single, isNot(same(source.firstHeader.single)));
      copy.firstHeader.single.inlines.whereType<WmlRun>().first.text =
          'Changed copy';
      expect(source.firstHeader.single.text, 'First page header retained');
      expect(copy.lineNumbers, isTrue);
      expect(copy.differentFirstPage, isTrue);
      expect(
        () => copy.sourceProperties!.values['pgSz'] = 'changed',
        throwsUnsupportedError,
      );
    },
  );
}
