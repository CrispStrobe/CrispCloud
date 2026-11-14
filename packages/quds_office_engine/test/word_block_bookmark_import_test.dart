import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Word writes bookmark endpoints between blocks — directly in the body,
// between table rows and between paragraphs of a cell (CT_Body, CT_Tbl,
// CT_Row and CT_Tc all admit EG_RangeMarkupElements). Such documents used to
// be refused on import (about one in ten real-world .docx files).
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String _p(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

const _body =
    '<w:bookmarkStart w:id="1" w:name="Before"/>'
    '<w:p><w:r><w:t>Alpha</w:t></w:r></w:p>'
    '<w:bookmarkEnd w:id="1"/>'
    '<w:bookmarkStart w:id="2" w:name="AroundTable"/>'
    '<w:tbl><w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid>'
    '<w:tr><w:tc><w:p><w:r><w:t>Cell A</w:t></w:r></w:p>'
    '<w:bookmarkStart w:id="3" w:name="InCell"/>'
    '<w:p><w:r><w:t>Cell B</w:t></w:r></w:p>'
    '<w:bookmarkEnd w:id="3"/></w:tc></w:tr>'
    '<w:bookmarkStart w:id="4" w:name="RowLevel"/>'
    '<w:tr><w:tc><w:p><w:r><w:t>Row two</w:t></w:r></w:p></w:tc></w:tr>'
    '<w:bookmarkEnd w:id="4"/>'
    '</w:tbl>'
    '<w:bookmarkEnd w:id="2"/>'
    '<w:bookmarkStart w:id="5" w:name="Empty"/><w:bookmarkEnd w:id="5"/>'
    '<w:p><w:r><w:t>Omega</w:t></w:r></w:p>';

OpcPackage _package(String body) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="$_w"><w:body>$body<w:sectPr/></w:body></w:document>',
      );
  return package;
}

Map<String, String> _texts(WmlDocument doc) => {
  for (final range in WordBookmarks.ranges(doc)) range.name: range.text,
};

void main() {
  test('block-level bookmark endpoints import and cover the same text', () {
    final doc = WordDeserializer().read(_package(_body));
    expect(doc.paragraphs.map((p) => p.text), [
      'Alpha',
      'Cell A',
      'Cell B',
      'Row two',
      'Omega',
    ]);
    expect(_texts(doc), {
      'Before': 'Alpha',
      'AroundTable': 'Cell A\nCell B\nRow two',
      'InCell': 'Cell B',
      'RowLevel': 'Row two',
      'Empty': '',
    });
  });

  test('relocated bookmarks survive repeated export and reimport', () {
    var doc = WordDeserializer().read(_package(_body));
    final expected = _texts(doc);
    for (var cycle = 0; cycle < 3; cycle++) {
      final bytes = WordSerializer().writeBytes(doc);
      doc = WordDeserializer().readBytes(bytes);
      expect(_texts(doc), expected, reason: 'cycle $cycle');
    }
    // Exported markers now live inside paragraphs.
    final xml = WordSerializer()
        .write(doc)
        .getPart('/word/document.xml')!
        .readText();
    expect(xml, isNot(contains('<w:body><w:bookmark')));
    expect(xml, isNot(contains('</w:p><w:bookmark')));
  });

  test('a marker between blocks never moves into a text box story', () {
    // The start precedes a paragraph whose drawing holds a text box; it must
    // attach to that host paragraph, not to the text box's own paragraph.
    const box =
        '<w:p><w:r><w:drawing><wp:anchor xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="1" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">'
        '<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="column"><wp:posOffset>0</wp:posOffset></wp:positionH>'
        '<wp:positionV relativeFrom="paragraph"><wp:posOffset>0</wp:posOffset></wp:positionV><wp:extent cx="914400" cy="914400"/>'
        '<wp:wrapNone/><wp:docPr id="1" name="Box"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">'
        '<wps:wsp xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:spPr/>'
        '<wps:txbx><w:txbxContent><w:p><w:r><w:t>Inside</w:t></w:r></w:p></w:txbxContent></wps:txbx><wps:bodyPr/></wps:wsp>'
        '</a:graphicData></a:graphic></wp:anchor></w:drawing></w:r><w:r><w:t>Host</w:t></w:r></w:p>';
    final doc = WordDeserializer().read(
      _package(
        '<w:bookmarkStart w:id="7" w:name="Host"/>$box<w:bookmarkEnd w:id="7"/>${_p('After')}',
      ),
    );
    expect(_texts(doc)['Host'], 'Host');
  });
}
