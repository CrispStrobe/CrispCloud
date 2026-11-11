import 'dart:io';
import 'dart:typed_data';
import 'package:quds_office_engine/quds_office_engine.dart';

WmlDocument richNoteFixture({
  String fixturePath = 'test/fixtures/fidelity/word.docx',
}) {
  final OpcPackage pkg = OpcPackage.openBytes(
    File(fixturePath).readAsBytesSync(),
  );
  final String drawing = RegExp(
    r'<w:drawing>.*?</w:drawing>',
    dotAll: true,
  ).firstMatch(pkg.getPart('/word/document.xml')!.readText())!.group(0)!;
  final Uint8List png = PngBytes.rgb(
    width: 4,
    height: 4,
    plot: (int x, int y, List<int> rgb) {
      rgb.setAll(0, <int>[40, 170, 70]);
    },
  );
  pkg.createPart('/word/media/note.png', 'image/png', png);
  // Same rId as the body picture, but a different owning part and target.
  pkg
      .relationshipsFor('/word/footnotes.xml')
      .add(id: 'img', type: RelationshipTypes.image, target: 'media/note.png');
  pkg.getPart('/word/footnotes.xml')!.writeText('''
<w:footnotes xmlns:w="${OfficeNamespaces.w}" xmlns:r="${OfficeNamespaces.r}"
 xmlns:wp="${OfficeNamespaces.wp}" xmlns:a="${OfficeNamespaces.a}"
 xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
<w:footnote w:id="12">
<w:p><w:r><w:footnoteRef/></w:r><w:r><w:rPr><w:b/><w:color w:val="008844"/><w:sz w:val="24"/></w:rPr><w:t>Rich note</w:t></w:r></w:p>
<w:tbl><w:tblPr><w:tblW w:w="2000" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid><w:tr><w:tc><w:p><w:r><w:t>Note table</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
<w:p><w:r>$drawing</w:r></w:p>
<w:p><w:hyperlink r:id="noteLink"><w:r><w:t>Note link</w:t></w:r></w:hyperlink></w:p>
</w:footnote></w:footnotes>''');
  return WordDeserializer().read(pkg);
}
