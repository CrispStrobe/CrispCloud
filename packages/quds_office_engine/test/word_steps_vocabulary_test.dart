import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/office_steps.dart' as cli;

// The steering vocabulary accepts OOXML names (`both`, `wave`) next to the
// Dart names; Word's 18 underline styles survive open/save; a paragraph
// split at its end continues the formatting of the text before it, the way
// pressing Return does in Word.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

WmlDocument _read(String body) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w"><w:body>$body<w:sectPr/></w:body></w:document>',
      );
  return WordDeserializer().read(package);
}

String _xml(WmlDocument doc) =>
    WordSerializer().write(doc).getPart('/word/document.xml')!.readText();

void main() {
  test('alignment accepts both, start and end', () {
    final doc = _read('<w:p><w:r><w:t>a</w:t></w:r></w:p>');
    cli.applyStep(doc, {
      'op': 'paragraphFormat',
      'paragraph': 0,
      'alignment': 'both',
    });
    expect(
      doc.paragraphs.single.properties.justification,
      WmlJustification.justify,
    );
    final paragraph = XmlDocument.parse(_xml(doc)).root!
        .firstChild('body', namespaceUri: _w)!
        .firstChild('p', namespaceUri: _w)!;
    final alignment = paragraph
        .firstChild('pPr', namespaceUri: _w)!
        .firstChild('jc', namespaceUri: _w)!;
    expect(alignment.getAttribute('val', namespaceUri: _w), 'both');
    cli.applyStep(doc, {
      'op': 'paragraphFormat',
      'paragraph': 0,
      'alignment': 'end',
    });
    expect(
      doc.paragraphs.single.properties.justification,
      WmlJustification.right,
    );
    expect(
      () => cli.applyStep(doc, {
        'op': 'paragraphFormat',
        'paragraph': 0,
        'alignment': 'sideways',
      }),
      throwsArgumentError,
    );
  });

  test('every Word underline style survives a save', () async {
    for (final u in WmlUnderline.values.where((u) => u != WmlUnderline.none)) {
      final doc = _read(
        '<w:p><w:r><w:rPr><w:u w:val="${u.xmlValue}"/></w:rPr><w:t>a</w:t></w:r></w:p>',
      );
      final again = WordDeserializer().readBytes(
        await OfficeIsolateSave.word(doc),
      );
      expect(
        _xml(again),
        contains('<w:u w:val="${u.xmlValue}"/>'),
        reason: u.name,
      );
    }
  });

  test('underline steps accept Dart and OOXML names', () {
    final doc = _read('<w:p><w:r><w:t>abc</w:t></w:r></w:p>');
    cli.applyStep(doc, {
      'op': 'runFormat',
      'paragraph': 0,
      'start': 0,
      'end': 3,
      'underline': 'wave',
    });
    expect(_xml(doc), contains('<w:u w:val="wave"/>'));
    cli.applyStep(doc, {
      'op': 'runFormat',
      'paragraph': 0,
      'start': 0,
      'end': 3,
      'underline': 'dashLong',
    });
    expect(_xml(doc), contains('<w:u w:val="dashLong"/>'));
  });

  test('text in a paragraph split off at the end keeps the run format', () {
    final doc = _read(
      '<w:p><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="28"/></w:rPr>'
      '<w:t>Heading text</w:t></w:r></w:p>',
    );
    cli.applyStep(doc, {'op': 'paragraphSplit', 'paragraph': 0, 'offset': 12});
    cli.applyStep(doc, {
      'op': 'replaceText',
      'paragraph': 1,
      'start': 0,
      'end': 0,
      'text': 'New',
    });
    final props = WmlRunEdit.propsAt(doc.paragraphs.elementAt(1), 0);
    expect(doc.paragraphs.elementAt(1).text, 'New');
    expect(props.fontSizeHalfPoints, 28);
    expect(props.asciiFont, 'Arial');
  });
}
