import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_gif_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('exact GIF preserves palette colors and transparency', () {
    final pixels = image.Image(width: 4, height: 3, numChannels: 4);
    image.fill(pixels, color: image.ColorRgba8(20, 30, 40, 255));
    pixels.setPixelRgba(0, 0, 0, 0, 0, 0);
    final output = encodeExactGif(pixels);
    final decoded = decodeStaticGif(output);
    expect((decoded.width, decoded.height), (4, 3));
    expect(decoded.getPixel(0, 0).a, 0);
    expect(decoded.getPixel(1, 1).r, 20);
    expect(decoded.getPixel(1, 1).g, 30);
    expect(decoded.getPixel(1, 1).b, 40);
  });
  test('GIF rejects partial transparency or more than 256 colors', () {
    final partial = image.Image(width: 1, height: 1, numChannels: 4);
    partial.setPixelRgba(0, 0, 0, 0, 0, 128);
    expect(
      () => encodeExactGif(partial),
      throwsA(
        isA<ImageEditException>().having(
          (e) => e.reason,
          'reason',
          ImageEditFailure.gifColorLimit,
        ),
      ),
    );
    final colors = image.Image(width: 257, height: 1, numChannels: 4);
    for (var x = 0; x < 257; x++) {
      colors.setPixelRgba(x, 0, x % 256, x ~/ 256, 0, 255);
    }
    expect(
      () => encodeExactGif(colors),
      throwsA(
        isA<ImageEditException>().having(
          (e) => e.reason,
          'reason',
          ImageEditFailure.gifColorLimit,
        ),
      ),
    );
  });
  test('animated GIF is rejected', () {
    final pixels = image.Image(width: 2, height: 2, numChannels: 4);
    pixels.addFrame(image.Image.from(pixels));
    final bytes = image.encodeGif(pixels);
    expect(
      () => decodeStaticGif(bytes),
      throwsA(
        isA<ImageEditException>().having(
          (e) => e.reason,
          'reason',
          ImageEditFailure.animatedImage,
        ),
      ),
    );
  });
}
