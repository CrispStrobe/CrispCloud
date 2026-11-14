import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// An imported picture whose part is not named the way the allocator would
// name it (picture.png, image1.jpg, footer images, …) used to be written a
// second time under the allocator's name on every save.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

String _picture(String rid, int id) =>
    '<w:r><w:drawing><wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
    '<wp:extent cx="95250" cy="95250"/><wp:docPr id="$id" name="Picture $id"/>'
    '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
    '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    '<pic:nvPicPr><pic:cNvPr id="$id" name="p$id"/><pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="$rid"/>'
    '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
    '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="95250" cy="95250"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
    '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';

OpcPackage _package() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.createPart('/word/media/picture.png', 'image/png', _png);
  package
      .relationshipsFor('/word/document.xml')
      .add(id: 'rId9', type: RelationshipTypes.image, target: 'media/picture.png');
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w"><w:body>'
        '<w:p>${_picture('rId9', 1)}</w:p><w:p>${_picture('rId9', 2)}</w:p>'
        '<w:sectPr/></w:body></w:document>',
      );
  return package;
}

List<String> _media(OpcPackage package) => [
  for (final part in package.parts)
    if (part.uri.startsWith('/word/media/')) part.uri,
];

void main() {
  test('an imported picture is not stored twice on save', () async {
    var doc = WordDeserializer().read(_package());
    expect(doc.visuals, hasLength(2));
    for (var cycle = 0; cycle < 3; cycle++) {
      final bytes = await OfficeIsolateSave.word(doc);
      final saved = OpcPackage.openBytes(bytes);
      expect(_media(saved), ['/word/media/picture.png'], reason: '$cycle');
      doc = WordDeserializer().readBytes(bytes);
      expect(doc.visuals, hasLength(2));
    }
  });
}
