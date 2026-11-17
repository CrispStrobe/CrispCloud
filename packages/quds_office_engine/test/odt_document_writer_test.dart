import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

void main() {
  test('writes modeled Word text, runs, tables and pictures as ODT', () {
    final document = WmlDocument(
      properties: OfficeDocumentProperties(title: 'Writer smoke'),
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              properties: WmlParagraphProps(headingLevel: 1),
              inlines: [WmlRun(text: 'Quarterly review')],
            ),
            WmlParagraph(
              properties: WmlParagraphProps(
                justification: WmlJustification.center,
              ),
              inlines: [
                WmlRun(text: 'Plain '),
                WmlRun(
                  text: 'bold',
                  properties: WmlRunProps(
                    bold: true,
                    color: 'FF0000',
                    fontSizeHalfPoints: 28,
                  ),
                ),
                WmlRun(text: ' tail'),
              ],
            ),
            WmlTable(
              grid: [120, 180],
              rows: [
                WmlTableRow(
                  cells: [
                    WmlTableCell(
                      blocks: [
                        WmlParagraph(inlines: [WmlRun(text: 'A')]),
                      ],
                    ),
                    WmlTableCell(
                      blocks: [
                        WmlParagraph(inlines: [WmlRun(text: 'B')]),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                title: 'Logo',
                imageBytes: _png,
                width: 72,
                height: 72,
              ),
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    final styles = package.getPart('/styles.xml')!.readText();
    expect(content, contains('<text:h'));
    expect(content, contains('Quarterly review'));
    expect(content, contains('Plain '));
    expect(content, contains('bold'));
    expect(content, contains('fo:font-weight="bold"'));
    expect(content, contains('<table:table'));
    expect(content, contains('Pictures/image1.png'));
    expect(styles, contains('fo:page-width'));
    expect(package.getPart('/Pictures/image1.png'), isNotNull);
  });
}
