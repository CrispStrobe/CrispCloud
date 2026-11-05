import 'dart:typed_data';

import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_file_store.dart';
import 'package:crisp_cloud/services/pdf_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'support/image_editor_fixture.dart';

class _WebPStore implements PdfFileStore {
  _WebPStore(this.bytes);
  Uint8List bytes;
  bool conflict = false;
  @override
  String get documentId => 'test:webp';
  @override
  String get displayName => 'photo.webp';
  @override
  String get path => '/photo.webp';
  @override
  bool get isRemote => false;
  @override
  Future<Uint8List> load() async => Uint8List.fromList(bytes);
  @override
  Future<PdfSaveOutcome> save(Uint8List data) async {
    if (conflict) throw const PdfSaveConflictException('changed');
    bytes = Uint8List.fromList(data);
    return PdfSaveOutcome.savedOriginal;
  }

  @override
  Future<PdfSaveOutcome> saveCopy(Uint8List data, String name) =>
      throw UnimplementedError();
}

void main() {
  test(
    'WebP load and save preserves encoding, dimensions and transparency',
    () async {
      final png = buildImageEditorFixture();
      final backing = _WebPStore(image.encodeWebP(image.decodePng(png)!));
      final store = WebPImageFileStore(backing);
      final editable = await store.load();
      final decoded = image.decodePng(editable)!;
      expect((decoded.width, decoded.height), (24, 16));
      expect(decoded.getPixel(0, 0).a, 0);
      decoded.setPixelRgba(3, 3, 200, 20, 30, 255);
      expect(
        await store.save(image.encodePng(decoded)),
        ImageSaveOutcome.savedOriginal,
      );
      final saved = image.decodeWebP(backing.bytes)!;
      expect((saved.width, saved.height), (24, 16));
      expect(saved.getPixel(0, 0).a, 0);
      expect(saved.getPixel(3, 3).r, 200);
    },
  );
  test('conflicts do not write the source and keep their host error', () async {
    final pixels = image.decodePng(buildImageEditorFixture())!;
    final backing = _WebPStore(image.encodeWebP(pixels));
    final store = WebPImageFileStore(backing);
    final png = await store.load();
    final original = Uint8List.fromList(backing.bytes);
    backing.conflict = true;
    await expectLater(
      store.save(png),
      throwsA(isA<ImageSaveConflictException>()),
    );
    expect(backing.bytes, orderedEquals(original));
  });
}
