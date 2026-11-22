import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _extension = 'urn:quds:test:selector-direction';
const _header = '/word/selector-direction-header.xml';

// The native layout expectations below come from authored XML, not a native
// serializer round trip: logical start=60/end=15 in RTL means physical
// right=60/left=15, and start alignment is physical right alignment.
const _styles =
    '<w:styles xmlns:w="${OfficeNamespaces.w}">'
    '<w:style w:type="paragraph" w:styleId="RtlBase">'
    '<w:name w:val="RTL reference"/><w:pPr>'
    '<w:ind w:start="1200" w:end="300" w:hanging="180"/>'
    '<w:jc w:val="start"/><w:bidi/>'
    '</w:pPr></w:style></w:styles>';

String _paragraph(String text, {bool metadata = false}) =>
    '<w:p><w:pPr><w:pStyle w:val="RtlBase"/>'
    '${metadata ? '<w:ind e:left="keep-physical-metadata"/>' : ''}'
    '</w:pPr><w:r><w:t>$text</w:t></w:r></w:p>';

Uint8List _fixture() {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package.getPart('/word/styles.xml')!.writeText(_styles);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}" '
        'xmlns:r="${OfficeNamespaces.r}" xmlns:e="$_extension">'
        '<w:body>${_paragraph('Body 1', metadata: true)}'
        '${_paragraph('Body 2')}<w:sectPr>'
        '<w:headerReference w:type="default" r:id="rIdDirectionalHeader"/>'
        '</w:sectPr></w:body></w:document>',
      );
  package
      .createPart(
        _header,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml',
        Uint8List(0),
      )
      .writeText(
        '<w:hdr xmlns:w="${OfficeNamespaces.w}" xmlns:e="$_extension">'
        '${_paragraph('Header 1', metadata: true)}'
        '${_paragraph('Header 2')}</w:hdr>',
      );
  package
      .relationshipsFor('/word/document.xml')
      .add(
        type: RelationshipTypes.header,
        target: 'selector-direction-header.xml',
        id: 'rIdDirectionalHeader',
      );
  return package.save();
}

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'DirectionalSelectors',
    source: source,
  ),
);

XmlElement _properties(Uint8List bytes, {required bool header}) {
  final package = OpcPackage.openBytes(bytes);
  final body = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!.firstChild('body', namespaceUri: OfficeNamespaces.w)!;
  var node = body;
  if (header) {
    final reference = body
        .firstChild('sectPr', namespaceUri: OfficeNamespaces.w)!
        .firstChild('headerReference', namespaceUri: OfficeNamespaces.w)!;
    final relationships = package.relationshipsFor('/word/document.xml');
    final relation = relationships.byId(
      reference.getAttribute('id', namespaceUri: OfficeNamespaces.r)!,
    )!;
    expect(relation.type, RelationshipTypes.header);
    node = XmlDocument.parse(
      package.getPart(relationships.resolve(relation))!.readText(),
    ).root!;
  }
  return node
      .firstChild('p', namespaceUri: OfficeNamespaces.w)!
      .firstChild('pPr', namespaceUri: OfficeNamespaces.w)!;
}

String? _w(XmlElement node, String name) =>
    node.getAttribute(name, namespaceUri: OfficeNamespaces.w);

void _expectPhysical(
  WmlParagraph paragraph, {
  required bool rtl,
  double left = 15,
}) {
  expect(paragraph.properties.rightToLeft, rtl);
  expect(paragraph.properties.justification, WmlJustification.right);
  expect(paragraph.properties.indent.left, left);
  expect(paragraph.properties.indent.right, 60);
  expect(paragraph.properties.indent.firstLine, 0);
  expect(paragraph.properties.indent.hanging, 9);
}

void _expectIndependentXml(
  Uint8List bytes, {
  required bool header,
  required String physicalLeftTwips,
}) {
  final properties = _properties(bytes, header: header);
  final indent = properties.firstChild(
    'ind',
    namespaceUri: OfficeNamespaces.w,
  )!;
  expect(_w(indent, 'left'), physicalLeftTwips);
  expect(_w(indent, 'right'), '1200');
  expect(_w(indent, 'start'), isNull);
  expect(_w(indent, 'end'), isNull);
  expect(
    indent.getAttribute('left', namespaceUri: _extension),
    'keep-physical-metadata',
  );
  expect(
    _w(properties.firstChild('jc', namespaceUri: OfficeNamespaces.w)!, 'val'),
    'right',
  );
  expect(
    _w(properties.firstChild('bidi', namespaceUri: OfficeNamespaces.w)!, 'val'),
    '0',
  );
  expect(
    XmlDocument.parse(
      OpcPackage.openBytes(bytes).getPart('/word/styles.xml')!.readText(),
    ).toXmlString(declaration: false),
    _styles,
    reason: 'Direct macro formatting must leave the authored style untouched.',
  );
}

void main() {
  test(
    'named body selector keeps physical style layout when reading order changes',
    () async {
      final input = _fixture();
      final original = WordDeserializer().readBytes(input);
      _expectPhysical(original.paragraphs.first, rtl: true);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        _compile('''
Option Explicit
Sub Main()
  Dim items As Paragraphs, layout As ParagraphFormat
  Set items = ActiveDocument.Paragraphs
  Set layout = items.Item(Index:=1).Range.ParagraphFormat
  layout.ReadingOrder = wdReadingOrderLtr
End Sub
'''),
      );
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        _expectIndependentXml(saved, header: false, physicalLeftTwips: '300');
        final paragraphProperties = _properties(saved, header: false);
        final indent = paragraphProperties.firstChild(
          'ind',
          namespaceUri: OfficeNamespaces.w,
        )!;
        expect(_w(indent, 'firstLine'), isNull);
        expect(_w(indent, 'hanging'), isNull);
        final document = WordDeserializer().readBytes(saved);
        _expectPhysical(document.paragraphs.first, rtl: false);
        _expectPhysical(document.paragraphs.elementAt(1), rtl: true);
        expect(document.paragraphs.map((p) => p.text), ['Body 1', 'Body 2']);
        for (final paragraph in document.sections.single.header) {
          _expectPhysical(paragraph, rtl: true);
        }
        expect(document.sections.single.header.map((p) => p.text), [
          'Header 1',
          'Header 2',
        ]);
        saved = WordSerializer().writeBytes(document);
      }
    },
  );

  test(
    'ByVal named story selector keeps physical sides and caller header identity',
    () async {
      final session = OfficeMacroSession(
        _fixture(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _compile('''
Option Explicit
Sub Main()
  Dim parts As Sections, targets As Paragraphs
  Set parts = ActiveDocument.Sections
  Set targets = parts.Item(Index:=1).Headers(Index:=wdHeaderFooterPrimary).Range.Paragraphs
  Adjust items:=targets
  targets.Item(Index:=2).Range.InsertBefore Text:=Left("Ready", 2) & ": "
End Sub
Sub Adjust(ByVal items As Paragraphs)
  With items.Item(Index:=1).Range.ParagraphFormat
    .ReadingOrder = wdReadingOrderLtr
    .LeftIndent = 24
  End With
  Set items = ActiveDocument.Paragraphs
End Sub
'''),
      );
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        _expectIndependentXml(saved, header: true, physicalLeftTwips: '480');
        final document = WordDeserializer().readBytes(saved);
        final story = document.sections.single.header;
        _expectPhysical(story[0], rtl: false, left: 24);
        _expectPhysical(story[1], rtl: true);
        expect(story.map((p) => p.text), ['Header 1', 'Re: Header 2']);
        for (final paragraph in document.paragraphs) {
          _expectPhysical(paragraph, rtl: true);
        }
        expect(document.paragraphs.map((p) => p.text), ['Body 1', 'Body 2']);
        saved = WordSerializer().writeBytes(document);
      }
    },
  );
}
