import 'dart:typed_data';

import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_file_store.dart';
import 'package:crisp_cloud/services/image_gif_codec.dart';
import 'package:crisp_cloud/services/pdf_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

class _GifStore implements PdfFileStore {
  _GifStore(this.bytes);
  Uint8List bytes;
  int writes = 0;
  @override
  String get documentId => 'test:gif';
  @override
  String get displayName => 'sample.gif';
  @override
  String get path => '/sample.gif';
  @override
  bool get isRemote => false;
  @override
  Future<Uint8List> load() async => Uint8List.fromList(bytes);
  @override
  Future<PdfSaveOutcome> save(Uint8List value) async {
    bytes = Uint8List.fromList(value);
    writes++;
    return PdfSaveOutcome.savedOriginal;
  }

  @override
  Future<PdfSaveOutcome> saveCopy(Uint8List value, String name) =>
      throw UnimplementedError();
}

void main() {
  test('static GIF saves exact edits without changing its format', () async {
    final pixels = image.Image(width: 4, height: 3, numChannels: 4);
    image.fill(pixels, color: image.ColorRgba8(10, 20, 30, 255));
    pixels.setPixelRgba(0, 0, 0, 0, 0, 0);
    final backing = _GifStore(encodeExactGif(pixels));
    final store = GifImageFileStore(backing);
    final edited = image.decodePng(await store.load())!.convert(numChannels: 4);
    edited.setPixelRgba(1, 1, 200, 30, 40, 255);
    expect(
      await store.save(image.encodePng(edited)),
      ImageSaveOutcome.savedOriginal,
    );
    final saved = decodeStaticGif(backing.bytes);
    expect(saved.getPixel(0, 0).a, 0);
    expect(saved.getPixel(1, 1).r, 200);
  });
  test('unrepresentable pixels never overwrite the original', () async {
    final pixels = image.Image(width: 2, height: 2, numChannels: 4);
    image.fill(pixels, color: image.ColorRgba8(10, 20, 30, 255));
    final original = encodeExactGif(pixels);
    final backing = _GifStore(original);
    final store = GifImageFileStore(backing);
    final edited = image.decodePng(await store.load())!.convert(numChannels: 4);
    edited.setPixelRgba(0, 0, 1, 2, 3, 128);
    await expectLater(
      store.save(image.encodePng(edited)),
      throwsA(
        isA<ImageEditException>().having(
          (e) => e.reason,
          'reason',
          ImageEditFailure.gifColorLimit,
        ),
      ),
    );
    expect(backing.writes, 0);
    expect(backing.bytes, orderedEquals(original));
  });
}
