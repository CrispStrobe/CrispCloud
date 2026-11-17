import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Emits source-generated ODP fixtures for schema and consumer geometry checks.
///
/// Run from this package with an output directory as the only argument. The
/// regression tests remain IO-free and run on both the VM and JavaScript/Node.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Expected an output directory.');
  }
  final output = Directory(arguments.single)..createSync(recursive: true);
  PmlShape shape(int degrees) => PmlShape(
    id: 2,
    name: 'Rotation',
    transform: PmlTransform(
      x: 60 * 12700,
      y: 80 * 12700,
      cx: 120 * 12700,
      cy: 40 * 12700,
      rot: degrees * 60000,
    ),
    fillColor: 'FF0000',
    text: 'Rotation',
    textColor: '000000',
    fontSizePt: 12,
  );

  void save(String name, PmlShape value) {
    final bytes = OdpPresentationWriter.writeBytes(
      PmlPresentation(
        slides: [
          PmlSlide(id: 1, shapes: [value]),
        ],
      ),
    );
    File('${output.path}/$name.odp').writeAsBytesSync(bytes);
  }

  for (final degrees in [90, 180, 270, -90, 45, -30]) {
    save('slide-rotation-$degrees', shape(degrees));
  }
  final picture = shape(90)
    ..visual = OfficeVisual(
      kind: OfficeVisualKind.picture,
      title: 'RGB direction',
      imageBytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAHgAAAAoCAIAAAC6iKlyAAAAdElEQVR4nO3QQQ0AIBDAMMC/Z3AxHtcaWLJ91x97WPh8qQ5kdMToiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI4YHTE6YnTE6IjREaMjRkeMjhgdMTpidMToiNERoyNGR4yOGB0xOmJ0xOiI0RGjI0ZHjI48pJMDT5SKBXEAAAAASUVORK5CYII=',
      ),
      width: 120,
      height: 40,
    );
  save('slide-rotation-picture', picture);
  for (final degrees in [90, -90, 45]) {
    for (final rtl in [false, true]) {
      save(
        'slide-rotation-table-$degrees${rtl ? '-rtl' : ''}',
        shape(degrees)
          ..table = PmlTable(
            headerRow: false,
            rightToLeft: rtl,
            rows: [
              [
                PmlTableCell(text: 'R', fillColor: 'FF0000'),
                PmlTableCell(text: 'G', fillColor: '00FF00'),
                PmlTableCell(text: 'B', fillColor: '0000FF'),
              ],
            ],
          ),
      );
    }
  }
  save('slide-rotation-table-empty', shape(90)..table = PmlTable());
  save(
    'slide-rotation-table-stroke',
    shape(90)
      ..strokeColor = 'FF00FF'
      ..strokeWidth = 2
      ..table = PmlTable(
        headerRow: false,
        rows: [
          [
            PmlTableCell(text: 'R', fillColor: 'FF0000'),
            PmlTableCell(text: 'G', fillColor: '00FF00'),
            PmlTableCell(text: 'B', fillColor: '0000FF'),
          ],
        ],
      ),
  );
  save(
    'slide-rotation-table-ragged',
    shape(90)
      ..table = PmlTable(
        rightToLeft: true,
        rows: [
          [
            PmlTableCell(text: 'R', fillColor: 'FF0000'),
            PmlTableCell(text: 'G', fillColor: '00FF00'),
            PmlTableCell(text: 'B', fillColor: '0000FF'),
          ],
          [PmlTableCell(text: 'Tail', fillColor: 'FFFF00')],
          [],
        ],
      ),
  );
}
