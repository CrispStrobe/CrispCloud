import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

Iterable<XmlElement> _elements(XmlElement parent, String name) sync* {
  for (final child in parent.childElements) {
    if (child.namespaceUri == OfficeNamespaces.w && child.localName == name) {
      yield child;
    }
    yield* _elements(child, name);
  }
}

void main() {
  for (final tableBorders in [false, true]) {
    test(
      'mixed cell edge overrides and inherited edges survive repeated DOCX reopen tableBorders=$tableBorders',
      () {
        var document = WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlTable(
                  grid: [80, 80, 80],
                  properties: WmlTableProps(
                    borders: tableBorders,
                    borderColor: tableBorders ? '123456' : null,
                    borderWidth: tableBorders ? 1.5 : 0.5,
                  ),
                  rows: [
                    WmlTableRow(
                      cells: [
                        WmlTableCell(
                          borderTop: true,
                          borderLeft: false,
                          borderRight: true,
                          blocks: [WmlParagraph()],
                        ),
                        WmlTableCell(
                          borderTop: false,
                          borderLeft: true,
                          borderBottom: true,
                          blocks: [WmlParagraph()],
                        ),
                        WmlTableCell(blocks: [WmlParagraph()]),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        for (var cycle = 0; cycle < 2; cycle++) {
          final bytes = WordSerializer().writeBytes(document);
          final package = OpcPackage.openBytes(bytes);
          final root = XmlDocument.parse(
            package.getPart('/word/document.xml')!.readText(),
          ).root!;
          final borders = _elements(root, 'tcBorders').toList();
          expect(borders, hasLength(2));
          expect(borders.first.childElements.map((edge) => edge.localName), [
            'top',
            'left',
            'right',
          ]);
          expect(borders.last.childElements.map((edge) => edge.localName), [
            'top',
            'left',
            'bottom',
          ]);
          expect(
            borders.first.childElements.map(
              (edge) =>
                  edge.getAttribute('val', namespaceUri: OfficeNamespaces.w),
            ),
            ['single', 'nil', 'single'],
          );
          expect(
            borders.last.childElements.map(
              (edge) =>
                  edge.getAttribute('val', namespaceUri: OfficeNamespaces.w),
            ),
            ['nil', 'single', 'single'],
          );
          for (final edge in borders.expand((node) => node.childElements)) {
            final enabled =
                edge.getAttribute('val', namespaceUri: OfficeNamespaces.w) ==
                'single';
            expect(
              edge.getAttribute('sz', namespaceUri: OfficeNamespaces.w),
              enabled ? (tableBorders ? '12' : '4') : null,
            );
            expect(
              edge.getAttribute('color', namespaceUri: OfficeNamespaces.w),
              enabled ? (tableBorders ? '123456' : '000000') : null,
            );
          }
          document = WordDeserializer().readBytes(bytes);
          final table = document.sections.single.blocks.single as WmlTable;
          expect(table.properties.borders, tableBorders);
          expect(
            [
              for (final cell in table.rows.single.cells)
                [
                  cell.borderTop,
                  cell.borderLeft,
                  cell.borderBottom,
                  cell.borderRight,
                ],
            ],
            [
              [true, false, null, true],
              [false, true, true, null],
              [null, null, null, null],
            ],
          );
        }
      },
    );
  }
}
