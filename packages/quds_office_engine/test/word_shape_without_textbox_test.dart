import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Shapes without text (rectangles, lines, callouts) used to gain an empty
// text-box body (wps:txbx / v:textbox) on every save.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String _shape(int id, {String? text}) =>
    '<w:r><w:drawing><wp:anchor xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="$id" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">'
    '<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="column"><wp:posOffset>0</wp:posOffset></wp:positionH>'
    '<wp:positionV relativeFrom="paragraph"><wp:posOffset>0</wp:posOffset></wp:positionV><wp:extent cx="914400" cy="457200"/>'
    '<wp:wrapNone/><wp:docPr id="$id" name="Shape$id"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
    '<a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">'
    '<wps:wsp xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:spPr>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></wps:spPr>'
    '${text == null ? '' : '<wps:txbx><w:txbxContent><w:p><w:r><w:t>$text</w:t></w:r></w:p></w:txbxContent></wps:txbx>'}'
    '<wps:bodyPr/></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>';

OpcPackage _package() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w"><w:body><w:p>${_shape(1)}${_shape(2, text: 'Boxed')}'
        '<w:r><w:t>Host</w:t></w:r></w:p><w:sectPr/></w:body></w:document>',
      );
  return package;
}

String _xml(WmlDocument doc) =>
    WordSerializer().write(doc).getPart('/word/document.xml')!.readText();

void main() {
  test('a shape without text keeps no text box through saves', () async {
    var doc = WordDeserializer().read(_package());
    for (var cycle = 0; cycle < 3; cycle++) {
      final xml = _xml(doc);
      // Only the real text box (DrawingML + its VML fallback).
      expect('<w:txbxContent'.allMatches(xml), hasLength(2), reason: '$cycle');
      expect(xml, contains('Boxed'));
      doc = WordDeserializer().readBytes(await OfficeIsolateSave.word(doc));
    }
  });

  test('adding content to such a shape gives it a text box', () {
    final doc = WordDeserializer().read(_package());
    final empty = WordTree.descendants(doc.sections.single.blocks)
        .whereType<WmlFrame>()
        .firstWhere((f) => f.blocks.isEmpty);
    expect(empty.hasTextBox, isFalse);
    empty.blocks.add(WmlParagraph(inlines: [WmlRun(text: 'Now with text')]));
    final xml = _xml(doc);
    expect('<w:txbxContent'.allMatches(xml), hasLength(4));
    expect(xml, contains('Now with text'));
  });
}
