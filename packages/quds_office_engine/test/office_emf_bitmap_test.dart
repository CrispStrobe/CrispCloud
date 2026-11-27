import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'embedded EMF decodes padded bottom-up BGR rows and their placement',
    () {
      final preview = OfficeEmfBitmap.decode(_emf())!;
      expect((preview.width, preview.height), (3, 3));
      expect(preview.alpha, [0, 0, 0, 0, 255, 0, 0, 255, 0]);
      expect(preview.rgb.sublist(12, 15), [255, 0, 0]);
      expect(preview.rgb.sublist(21, 24), [0, 0, 255]);
      expect(PdfImageCodec.decode(_emf())!.rgb, preview.rgb);
    },
  );

  test(
    'EMF rejects unsupported operations and bitmap lengths outside the record',
    () {
      final foreignRecord = _emf();
      ByteData.sublistView(foreignRecord).setUint32(88, 42, Endian.little);
      expect(OfficeEmfBitmap.decode(foreignRecord), isNull);
      final invalidOffset = _emf();
      ByteData.sublistView(
        invalidOffset,
      ).setUint32(88 + 56, 2048, Endian.little);
      expect(OfficeEmfBitmap.decode(invalidOffset), isNull);
    },
  );

  test(
    'workbook saves the original EMF and prints the actual small anchor',
    () {
      final sheet = SmlWorksheet(name: 'Drawing', sheetId: 1)
        ..pageSetup = SmlPageSetup()
        ..cellA1('A1').value = 'Marker';
      sheet.drawings.add(
        SmlDrawing(
          col: 0,
          row: 0,
          importedEndMarker: (col: 0, row: 0, colEmu: 101600, rowEmu: 76200),
          visual: OfficeVisual(
            kind: OfficeVisualKind.picture,
            imageBytes: _emf(),
          ),
        ),
      );
      final package = SheetSerializer().write(SmlWorkbook(sheets: [sheet]));
      final media = package.parts.singleWhere(
        (part) => part.uri.endsWith('.emf'),
      );
      expect(media.contentType, 'image/x-emf');
      expect(media.readBytes(), _emf());

      final workbook = SheetDeserializer().read(package);
      final pdf = PdfFile.open(OfficePrint.workbook(workbook));
      final image = pdf.displayList(0).ops.whereType<PdfDrawImage>().single;
      expect(image.placeholder, isFalse);
      expect(image.width, closeTo(8, .01));
      expect(image.height, closeTo(6, .01));
      expect((image.pixelWidth, image.pixelHeight), (3, 3));
    },
  );
}

Uint8List _emf() {
  const header = 88;
  const copy = 128;
  const eof = 20;
  final bytes = Uint8List(header + copy + eof);
  final data = ByteData.sublistView(bytes);
  void dword(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  void word(int offset, int value) =>
      data.setUint16(offset, value, Endian.little);
  dword(0, 1);
  dword(4, header);
  dword(16, 2);
  dword(20, 2);
  dword(40, 0x464d4520);
  dword(44, 0x10000);
  dword(48, bytes.length);
  dword(52, 3);

  void record(int index, int value) => dword(header + index * 4, value);
  record(0, 81);
  record(1, copy);
  record(6, 1);
  record(7, 1);
  record(10, 1);
  record(11, 2);
  record(12, 80);
  record(13, 40);
  record(14, 120);
  record(15, 8);
  record(17, 0x00cc0020);
  record(18, 1);
  record(19, 2);
  dword(header + 80, 40);
  dword(header + 84, 1);
  dword(header + 88, 2);
  word(header + 92, 1);
  word(header + 94, 24);
  bytes.setRange(header + 120, header + 128, [255, 0, 0, 0, 0, 0, 255, 0]);
  dword(header + copy, 14);
  dword(header + copy + 4, eof);
  dword(header + copy + 16, eof);
  return bytes;
}
