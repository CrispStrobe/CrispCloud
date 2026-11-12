import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'table direction uses native on/off values across edits and saves',
    () async {
      var document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlTable(
                grid: [120],
                properties: WmlTableProps(rightToLeft: true),
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(
                        blocks: [
                          WmlParagraph(inlines: [WmlRun(text: 'Direction')]),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      for (final rightToLeft in [true, false, true]) {
        document.sections.single.blocks
                .whereType<WmlTable>()
                .single
                .properties
                .rightToLeft =
            rightToLeft;
        for (var cycle = 0; cycle < 3; cycle++) {
          final package = OpcPackage.openBytes(
            await OfficeIsolateSave.word(document),
          );
          final table = XmlDocument.parse(
            package.getPart('/word/document.xml')!.readText(),
          ).root!.firstChild('body')!.firstChild('tbl')!;
          expect(
            table
                .firstChild('tblPr')!
                .firstChild('bidiVisual')!
                .getAttribute('val'),
            rightToLeft ? 'on' : 'off',
          );
          document = WordDeserializer().read(package);
          expect(
            document.sections.single.blocks
                .whereType<WmlTable>()
                .single
                .properties
                .rightToLeft,
            rightToLeft,
          );
        }
      }
    },
  );
}
