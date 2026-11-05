import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_export_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'support/image_editor_fixture.dart';

void main() {
  test('PNG conversion resizes and preserves transparent pixels', () {
    final bytes = encodeImageExport(
      buildImageEditorFixture(),
      ImageFileFormat.png,
      const ImageExportOptions(
        format: ImageFileFormat.png,
        width: 12,
        height: 8,
      ),
    );
    final result = image.decodePng(bytes)!;
    expect((result.width, result.height), (12, 8));
    expect(result.getPixel(0, 0).a, lessThan(255));
  });

  test('JPEG export composites transparent pixels on white', () {
    final pixels = image.Image(width: 8, height: 8, numChannels: 4);
    image.fill(pixels, color: image.ColorRgba8(0, 0, 0, 0));
    final bytes = encodeImageExport(
      image.encodePng(pixels),
      ImageFileFormat.png,
      const ImageExportOptions(format: ImageFileFormat.jpeg, jpegQuality: 95),
    );
    final pixel = image.decodeJpg(bytes)!.getPixel(0, 0);
    expect(pixel.r, greaterThan(245));
    expect(pixel.g, greaterThan(245));
    expect(pixel.b, greaterThan(245));
  });

  test('rejects invalid dimensions and quality', () {
    final source = buildImageEditorFixture();
    for (final options in [
      const ImageExportOptions(format: ImageFileFormat.png, width: 5),
      const ImageExportOptions(
        format: ImageFileFormat.png,
        width: 0,
        height: 1,
      ),
      const ImageExportOptions(format: ImageFileFormat.jpeg, jpegQuality: 0),
      const ImageExportOptions(
        format: ImageFileFormat.png,
        width: 16384,
        height: 16384,
      ),
    ]) {
      expect(
        () => encodeImageExport(source, ImageFileFormat.png, options),
        throwsArgumentError,
      );
    }
  });
}
