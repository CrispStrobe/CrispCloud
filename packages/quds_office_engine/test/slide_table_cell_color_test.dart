import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

PmlSlide _coloredTableSlide() => PmlSlide(
  id: 256,
  shapes: <PmlShape>[
    PmlShape(
      id: 2,
      name: 'Table',
      table: PmlTable(
        rows: <List<PmlTableCell>>[
          <PmlTableCell>[
            PmlTableCell(
              text: 'Black on white',
              fillColor: 'FFFFFF',
              textColor: '000000',
            ),
            PmlTableCell(
              text: 'Light on dark',
              fillColor: '303030',
              textColor: 'F2F2F2',
            ),
          ],
          <PmlTableCell>[
            PmlTableCell(text: 'Colored unfilled', textColor: '123ABC'),
            PmlTableCell(text: 'Automatic', fillColor: 'FFF3CD'),
          ],
        ],
      ),
    ),
    PmlShape(id: 3, name: 'Neighbor', text: 'Shape ink', textColor: 'AABBCC'),
  ],
);

void _expectColors(List<PmlShape> shapes) {
  final table = shapes.first.table!;
  expect(
    table.rows.expand((row) => row).map((cell) => cell.textColor),
    <String>['000000', 'F2F2F2', '123ABC', ''],
  );
  expect(
    table.rows.expand((row) => row).map((cell) => cell.fillColor),
    <String>['FFFFFF', '303030', '', 'FFF3CD'],
  );
  expect(
    shapes.first.textColor,
    isEmpty,
    reason: 'Cell ink belongs to its cell.',
  );
  expect(shapes.last.textColor, 'AABBCC');
}

void main() {
  test('DrawingML keeps table-cell ink separate from fills and shape ink', () {
    _expectColors(parseSlideShapes(slideToXml(_coloredTableSlide())));
  });

  test('PPTX save and reopen preserve each table-cell color repeatedly', () {
    var deck = PmlPresentation(slides: <PmlSlide>[_coloredTableSlide()]);
    for (var cycle = 0; cycle < 2; cycle++) {
      deck = SlideDeserializer().readBytes(SlideSerializer().writeBytes(deck));
      _expectColors(deck.slides.single.shapes);
    }
  });

  test('table-cell theme ink resolves independently from theme fill', () {
    const xml = '''
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
 xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
 <p:cSld><p:spTree><p:graphicFrame>
  <p:nvGraphicFramePr><p:cNvPr id="2" name="Table"/></p:nvGraphicFramePr>
  <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">
   <a:tbl><a:tblPr/><a:tblGrid><a:gridCol w="100"/></a:tblGrid><a:tr h="100"><a:tc>
    <a:txBody><a:bodyPr/><a:p><a:r><a:rPr><a:solidFill><a:schemeClr val="accent1"/></a:solidFill></a:rPr><a:t>Theme ink</a:t></a:r></a:p></a:txBody>
    <a:tcPr><a:solidFill><a:schemeClr val="bg1"/></a:solidFill></a:tcPr>
   </a:tc></a:tr></a:tbl>
  </a:graphicData></a:graphic>
 </p:graphicFrame></p:spTree></p:cSld>
</p:sld>''';
    final shapes = parseSlideShapes(
      xml,
      colors: <String, String>{'accent1': '112233', 'bg1': 'FFFFFF'},
    );
    final cell = shapes.single.table!.cellAt(0, 0);
    expect(cell.text, 'Theme ink');
    expect(cell.textColor, '112233');
    expect(cell.fillColor, 'FFFFFF');
    expect(shapes.single.textColor, isEmpty);
  });
}
