// The host opens a real DOCX and the Word canvas must behave like an office
// suite when the user presses Enter: the inserted paragraph keeps the source
// paragraph's spacing, line spacing, indentation, alignment and list identity,
// typing continues the active character formatting, and numbered lists
// renumber instead of repeating a label.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pr = 'http://schemas.openxmlformats.org/package/2006/relationships';

Uint8List _documentXml(String body) => Uint8List.fromList(
  utf8.encode('''<w:document xmlns:w="$_w"><w:body>$body
<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1531" w:bottom="1441" w:left="1453" w:header="725" w:footer="715" w:gutter="33"/></w:sectPr>
</w:body></w:document>'''),
);

Uint8List _docx({required String body, String? numbering}) {
  final parts = <String, String>{
    '[Content_Types].xml': '''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
${numbering == null ? '' : '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'}
</Types>''',
    '_rels/.rels':
        '<Relationships xmlns="$_pr"><Relationship Id="office" Type="$_r/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/_rels/document.xml.rels':
        '''<Relationships xmlns="$_pr">${numbering == null ? '' : '<Relationship Id="numbering" Type="$_r/numbering" Target="numbering.xml"/>'}</Relationships>''',
    if (numbering != null) 'word/numbering.xml': numbering,
  };
  final archive = Archive();
  for (final part in parts.entries) {
    archive.addFile(ArchiveFile.bytes(part.key, utf8.encode(part.value)));
  }
  archive.addFile(
    ArchiveFile.bytes('word/document.xml', _documentXml(body)),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _numbering = '''<w:numbering xmlns:w="$_w">
<w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>
<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>
</w:abstractNum>
<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>''';

void _expectFormatted(WmlParagraphProps props) {
  expect(props.spacingBefore, 12);
  expect(props.spacingAfter, 18);
  expect(props.lineSpacing, 1.5);
  expect(props.indent.left, 24);
  expect(props.indent.firstLine, 6);
  expect(props.justification, WmlJustification.center);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Enter keeps the host document paragraph format', () async {
    final controller = WordEditorController.fromBytes(
      _docx(
        body:
            '''<w:p><w:pPr><w:spacing w:before="240" w:after="360" w:line="360" w:lineRule="auto"/><w:ind w:left="480" w:firstLine="120"/><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="40"/><w:color w:val="C00000"/></w:rPr><w:t>Bold large</w:t></w:r></w:p>''',
      ),
    );
    addTearDown(controller.dispose);
    controller.caret
      ..logicalIndex = 10
      ..collapseSelection();

    controller.insertParagraphBreak();

    final paragraphs = controller.document.paragraphs.toList();
    expect(paragraphs.map((WmlParagraph p) => p.text), <String>[
      'Bold large',
      '',
    ]);
    _expectFormatted(paragraphs[1].properties);

    controller.insertText('Typed');
    final run = paragraphs[1].inlines.single as WmlRun;
    expect(run.properties.bold, isTrue);
    expect(run.properties.fontSizeHalfPoints, 40);
    expect(run.properties.color, 'C00000');

    final reopened = WordDeserializer().readBytes(
      await controller.saveBytesAsync(),
    );
    expect(reopened.paragraphs.map((WmlParagraph p) => p.text), <String>[
      'Bold large',
      'Typed',
    ]);
    expect(reopened.paragraphs.last.properties.spacingAfter, 18);
  });

  test('Enter in an imported numbered list renumbers the list', () {
    final controller = WordEditorController.fromBytes(
      _docx(
        numbering: _numbering,
        body:
            '''<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr></w:pPr><w:r><w:t>One</w:t></w:r></w:p>
<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr></w:pPr><w:r><w:t>Two</w:t></w:r></w:p>''',
      ),
    );
    addTearDown(controller.dispose);
    expect(
      controller.document.paragraphs.map(
        (WmlParagraph p) => p.properties.listLabel,
      ),
      <String>['1. ', '2. '],
    );

    controller.jumpToParagraph(0);
    controller.caret
      ..logicalIndex = 3
      ..collapseSelection();
    controller.insertParagraphBreak();
    controller.insertText('One and a half');

    expect(
      controller.document.paragraphs.map(
        (WmlParagraph p) => p.properties.listLabel,
      ),
      <String>['1. ', '2. ', '3. '],
    );
    expect(
      controller.document.paragraphs.map((WmlParagraph p) => p.text),
      <String>['One', 'One and a half', 'Two'],
    );
  });

  test('typing over a multi-paragraph selection replaces it with one', () {
    final controller = WordEditorController.fromBytes(
      _docx(
        body:
            '''<w:p><w:pPr><w:spacing w:before="240" w:after="360"/><w:ind w:left="480"/></w:pPr><w:r><w:t>One</w:t></w:r></w:p>
<w:p><w:pPr><w:spacing w:before="240" w:after="360"/><w:ind w:left="480"/></w:pPr><w:r><w:t>Two</w:t></w:r></w:p>''',
      ),
    );
    addTearDown(controller.dispose);
    controller.caret
      ..paragraphIndex = 0
      ..logicalIndex = 1
      ..selectionAnchorParagraph = 1
      ..selectionAnchor = 2;

    controller.insertText('X');

    expect(controller.document.paragraphs, hasLength(1));
    expect(controller.document.paragraphs.single.text, 'OXo');
    final props = controller.document.paragraphs.single.properties;
    expect(props.spacingBefore, 12);
    expect(props.spacingAfter, 18);
    expect(props.indent.left, 24);
  });
}
