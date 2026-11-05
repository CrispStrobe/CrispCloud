import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_gif_codec.dart';
import 'package:crisp_cloud/services/image_overlay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'support/image_editor_fixture.dart';

void main() {
  test('accepts static PNG, WebP and GIF overlays', () {
    final png = buildImageEditorFixture();
    final pixels = image.decodePng(png)!;
    final limited = image.Image(width: 2, height: 2, numChannels: 4);
    image.fill(limited, color: image.ColorRgba8(1, 2, 3, 255));
    expect(ImageOverlay(name: 'a.png', bytes: png).bytes, orderedEquals(png));
    expect(
      ImageOverlay(name: 'a.webp', bytes: image.encodeWebP(pixels)).name,
      'a.webp',
    );
    expect(
      ImageOverlay(name: 'a.gif', bytes: encodeExactGif(limited)).name,
      'a.gif',
    );
  });
  test('rejects animated overlays instead of silently flattening them', () {
    final pixels = image.Image(width: 2, height: 2, numChannels: 4);
    pixels.addFrame(image.Image.from(pixels));
    for (final entry in {
      'a.gif': image.encodeGif(pixels),
      'a.webp': image.encodeWebP(pixels),
    }.entries) {
      expect(
        () => ImageOverlay(name: entry.key, bytes: entry.value),
        throwsA(
          isA<ImageEditException>().having(
            (e) => e.reason,
            'reason',
            ImageEditFailure.animatedImage,
          ),
        ),
      );
    }
  });
}
