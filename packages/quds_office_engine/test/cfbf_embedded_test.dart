import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  group('CFBF', () {
    test('writes and reads named streams including mini-stream', () {
      final CfbfWriter writer = CfbfWriter();
      writer.addStream('Package', Uint8List.fromList(List<int>.filled(80, 7)));
      writer.addStream('Big', Uint8List.fromList(List<int>.filled(5000, 9)));
      writer.addStorage('ObjectPool/obj1');
      writer.addStream(
        'ObjectPool/obj1/CONTENTS',
        Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      final Uint8List bytes = writer.build();
      expect(CfbfFile.isCfbf(bytes), isTrue);

      final CfbfFile file = CfbfFile.fromBytes(bytes);
      expect(file.readStream('Package'), everyElement(7));
      expect(file.readStream('Package')!.length, 80);
      expect(file.readStream('Big')!.length, 5000);
      expect(file.readStream('Big')!.first, 9);
      expect(file.readPath('ObjectPool/obj1/CONTENTS'), <int>[1, 2, 3, 4]);
      expect(file.root.name, 'Root Entry');
    });

    test('packs and unpacks an embedded Excel workbook', () {
      final IsolatedEmbeddedPackage child = EmbeddedPart.create(
        OpcPackageKind.sheet,
      );
      child.package
          .getPart('/xl/worksheets/sheet1.xml')!
          .writeText(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<sheetData><row r="1"><c r="A1"><v>42</v></c></row></sheetData>'
            '</worksheet>',
          );

      final Uint8List bin = child.pack();
      expect(CfbfFile.isCfbf(bin), isTrue);

      final IsolatedEmbeddedPackage opened = EmbeddedPart.unpack(bin);
      expect(opened.kind, OpcPackageKind.sheet);
      expect(opened.displayName, contains('Excel'));
      expect(
        opened.package.getPart('/xl/worksheets/sheet1.xml')!.readText(),
        contains('42'),
      );

      final OpcPackage parent = OpcPackage.create(OpcPackageKind.word);
      parent.createPart(
        '/word/embeddings/oleObject1.bin',
        OfficeContentTypes.oleObject,
        bin,
      );
      parent
          .relationshipsFor('/word/document.xml')
          .add(
            type: RelationshipTypes.oleObject,
            target: 'embeddings/oleObject1.bin',
          );
      final OpcPackage reopened = OpcPackage.openBytes(parent.save());
      final PackagePart ole = reopened.getPart(
        '/word/embeddings/oleObject1.bin',
      )!;
      final IsolatedEmbeddedPackage nested = EmbeddedPart.unpack(
        ole.readBytes(),
      );
      expect(nested.kind, OpcPackageKind.sheet);
      expect(
        nested.package.getPart('/xl/worksheets/sheet1.xml')!.readText(),
        contains('42'),
      );
    });
  });
}
