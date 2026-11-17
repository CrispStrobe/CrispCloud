import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

void main() {
  test('writes modeled slides, text, tables and pictures as ODP', () {
    final presentation = PmlPresentation(
      properties: OfficeDocumentProperties(title: 'Deck smoke'),
      slides: [
        PmlSlide(
          id: 1,
          notes: 'Speaker note',
          transition: const PmlSlideTransition(
            kind: PmlTransitionKind.push,
            direction: PmlTransitionDir.left,
            durationMs: 800,
            advanceAfterMs: 5000,
          ),
          shapes: [
            PmlShape(
              id: 2,
              name: 'Title',
              transform: const PmlTransform(
                x: 457200,
                y: 457200,
                cx: 4572000,
                cy: 914400,
              ),
              text: 'Hello deck',
              fillColor: 'FFFFFF',
              textColor: '000000',
              fontSizePt: 28,
              textAlign: PmlTextAlign.center,
            ),
            PmlShape(
              id: 3,
              name: 'Table',
              transform: const PmlTransform(
                x: 457200,
                y: 1600200,
                cx: 5486400,
                cy: 1600200,
              ),
              table: PmlTable(
                rows: [
                  [PmlTableCell(text: 'A'), PmlTableCell(text: 'B')],
                  [PmlTableCell(text: '1'), PmlTableCell(text: '2')],
                ],
              ),
            ),
            PmlShape(
              id: 4,
              name: 'Logo',
              transform: const PmlTransform(
                x: 6400800,
                y: 457200,
                cx: 914400,
                cy: 914400,
              ),
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
      OdpPresentationWriter.writeBytes(presentation),
    );
    final content = package.getPart('/content.xml')!.readText();
    final styles = package.getPart('/styles.xml')!.readText();
    expect(content, contains('<draw:page'));
    expect(content, contains('Hello deck'));
    expect(content, contains('<table:table'));
    expect(content, contains('Pictures/image1.png'));
    expect(content, contains('Speaker note'));
    expect(content, contains('presentation:transition-style="push-left"'));
    expect(content, contains('presentation:duration="PT5.00S"'));
    expect(styles, contains('fo:page-width'));
    expect(package.getPart('/Pictures/image1.png'), isNotNull);
  });
}
