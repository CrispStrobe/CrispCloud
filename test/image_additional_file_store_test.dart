import 'dart:typed_data';

import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_file_store.dart';
import 'package:crisp_cloud/services/image_raster_codec.dart';
import 'package:crisp_cloud/services/pdf_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'support/image_editor_fixture.dart';

class _MemoryStore implements PdfFileStore {
  _MemoryStore(this.bytes);
  Uint8List bytes;
  bool conflict = false;
  @override
  String get documentId => 'test';
  @override
  String get displayName => 'test';
  @override
  String get path => '/test';
  @override
  bool get isRemote => false;
  @override
  Future<Uint8List> load() async => Uint8List.fromList(bytes);
  @override
  Future<PdfSaveOutcome> save(Uint8List value) async {
    if (conflict) throw const PdfSaveConflictException('changed');
    bytes = Uint8List.fromList(value);
    return PdfSaveOutcome.savedOriginal;
  }

  @override
  Future<PdfSaveOutcome> saveCopy(Uint8List value, String name) =>
      throw UnimplementedError();
}

void main() {
  for (final format in AdditionalRasterFormat.values) {
    test(
      '$format load and save preserves pixels and source conflicts',
      () async {
        final pixels = image.decodePng(buildImageEditorFixture())!;
        final backing = _MemoryStore(encodeAdditionalRaster(pixels, format));
        final ImageFileStore store = format == AdditionalRasterFormat.bmp
            ? BmpImageFileStore(backing)
            : TiffImageFileStore(backing);
        final png = await store.load();
        final edited = image.decodePng(png)!.convert(numChannels: 4);
        edited.setPixelRgba(3, 3, 200, 20, 30, 255);
        expect(
          await store.save(image.encodePng(edited)),
          ImageSaveOutcome.savedOriginal,
        );
        final saved = decodeAdditionalRaster(backing.bytes, format);
        expect((saved.width, saved.height), (24, 16));
        expect(saved.getPixel(0, 0).a, 0);
        expect(saved.getPixel(3, 3).r, 200);
        final snapshot = Uint8List.fromList(backing.bytes);
        backing.conflict = true;
        await expectLater(
          store.save(image.encodePng(edited)),
          throwsA(isA<ImageSaveConflictException>()),
        );
        expect(backing.bytes, orderedEquals(snapshot));
      },
    );
  }
}
