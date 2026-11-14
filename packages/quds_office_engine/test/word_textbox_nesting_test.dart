import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Several text boxes anchored in one paragraph used to nest: each box's
// content swallowed the frames already collected for the host paragraph, so
// export wrote 2^n - 1 boxes (a real document grew from 18 boxes to 4,101).
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String _box(int id, String text) =>
    '<w:r><w:drawing><wp:anchor xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="$id" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">'
    '<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="column"><wp:posOffset>${id * 100000}</wp:posOffset></wp:positionH>'
    '<wp:positionV relativeFrom="paragraph"><wp:posOffset>0</wp:posOffset></wp:positionV><wp:extent cx="914400" cy="914400"/>'
    '<wp:wrapNone/><wp:docPr id="$id" name="Box$id"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
    '<a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">'
    '<wps:wsp xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:spPr/>'
    '<wps:txbx><w:txbxContent><w:p><w:r><w:t>$text</w:t></w:r></w:p></w:txbxContent></wps:txbx><wps:bodyPr/></wps:wsp>'
    '</a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>';

OpcPackage _package(int boxes) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w"><w:body><w:p>'
        '${[for (var i = 1; i <= boxes; i++) _box(i, 'Box $i')].join()}'
        '<w:r><w:t>Host</w:t></w:r></w:p><w:sectPr/></w:body></w:document>',
      );
  return package;
}

List<String> _frameTexts(WmlDocument doc) => [
  for (final frame in WordTree.descendants(
    doc.sections.expand((s) => s.blocks),
  ).whereType<WmlFrame>())
    frame.blocks.whereType<WmlParagraph>().map((p) => p.text).join('|'),
];

int _nestedFrames(WmlDocument doc) => WordTree.descendants(
  doc.sections.expand((s) => s.blocks),
).whereType<WmlFrame>().where((f) => f.blocks.any((b) => b is WmlFrame)).length;

void main() {
  test('boxes anchored in one paragraph stay siblings', () {
    final doc = WordDeserializer().read(_package(4));
    expect(_frameTexts(doc), ['Box 1', 'Box 2', 'Box 3', 'Box 4']);
    expect(_nestedFrames(doc), 0);
    expect(doc.paragraphs.map((p) => p.text), contains('Host'));
  });

  test('box count stays linear through repeated saves', () async {
    var doc = WordDeserializer().read(_package(12));
    for (var cycle = 0; cycle < 3; cycle++) {
      final xml = WordSerializer()
          .write(doc)
          .getPart('/word/document.xml')!
          .readText();
      // Each box is written once as DrawingML and once as its VML fallback.
      expect('<w:txbxContent'.allMatches(xml), hasLength(24), reason: '$cycle');
      doc = WordDeserializer().readBytes(await OfficeIsolateSave.word(doc));
      expect(_frameTexts(doc), [for (var i = 1; i <= 12; i++) 'Box $i']);
    }
  });
}
