import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  for (final kind in [OpcPackageKind.sheet, OpcPackageKind.slide]) {
    for (final marker in [
      'path',
      'encoded-path',
      'mime',
      'root-rel',
      'part-rel',
      'orphan-rel',
    ]) {
      test('${kind.name} refuses $marker before opening or serializing', () async {
        final package = OpcPackage.create(kind);
        const signatureType =
            'http://schemas.openxmlformats.org/package/2006/relationships/digital-signature/origin';
        switch (marker) {
          case 'path':
            package.createPart(
              '/_xmlsignatures/sig1.xml',
              'application/xml',
              utf8.encode('<signature/>'),
            );
          case 'encoded-path':
            package.createPart(
              '/%5Fxmlsignatures/sig1.xml',
              'application/xml',
              utf8.encode('<signature/>'),
            );
          case 'mime':
            package.contentTypes.setOverride(
              '/custom/signature.xml',
              'application/vnd.openxmlformats-package.digital-signature-xmlsignature+xml',
            );
          case 'root-rel':
            package.packageRelationships.add(
              type: signatureType,
              target: 'custom/origin.sigs',
            );
          case 'part-rel':
            package
                .relationshipsFor(
                  kind == OpcPackageKind.sheet
                      ? '/xl/workbook.xml'
                      : '/ppt/presentation.xml',
                )
                .add(type: signatureType, target: '../custom/origin.sigs');
          case 'orphan-rel':
            package
                .relationshipsFor('/missing/owner.xml')
                .add(type: signatureType, target: '../custom/origin.sigs');
        }
        final before = package.save();
        final reopened = OpcPackage.openBytes(before);
        expect(reopened.assertUnsignedForEditing, throwsFormatException);
        if (kind == OpcPackageKind.sheet) {
          expect(
            () => SheetDeserializer().read(reopened),
            throwsFormatException,
          );
          final workbook = SmlWorkbook(package: reopened);
          expect(
            () => SheetSerializer().writeBytes(workbook),
            throwsFormatException,
          );
          await expectLater(
            OfficeIsolateSave.workbook(workbook),
            throwsA(anything),
          );
          await expectLater(OfficeIsolateOpen.workbook(before), throwsA(anything));
        } else {
          expect(
            () => SlideDeserializer().read(reopened),
            throwsFormatException,
          );
          final presentation = PmlPresentation(package: reopened);
          expect(
            () => SlideSerializer().writeBytes(presentation),
            throwsFormatException,
          );
          await expectLater(
            OfficeIsolateSave.presentation(presentation),
            throwsA(anything),
          );
          await expectLater(OfficeIsolateOpen.presentation(before), throwsA(anything));
        }
        expect(reopened.save(), before);
      });
    }

    test('${kind.name} unsigned payloads remain lazy and editable', () {
      final package = OpcPackage.create(kind);
      package.createPart(
        '/custom/unrelated.bin',
        'application/octet-stream',
        List.filled(1024, 42),
      );
      final reopened = OpcPackage.openBytes(package.save());
      final opaque = reopened.parts.singleWhere(
        (part) => part.uri == '/custom/unrelated.bin',
      );
      expect(opaque.isLoaded, isFalse);
      reopened.assertUnsignedForEditing();
      expect(opaque.isLoaded, isFalse);
      if (kind == OpcPackageKind.sheet) {
        final workbook = SheetDeserializer().read(reopened);
        workbook.firstSheet.cellA1('A1').value = 'Edited';
        expect(
          SheetDeserializer()
              .readBytes(SheetSerializer().writeBytes(workbook))
              .firstSheet
              .cellA1('A1')
              .value,
          'Edited',
        );
      } else {
        final presentation = SlideDeserializer().read(reopened);
        expect(SlideSerializer().writeBytes(presentation), isNotEmpty);
      }
    });
  }
}
