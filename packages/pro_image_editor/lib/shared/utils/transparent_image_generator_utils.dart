import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

/// Creates a transparent PNG image with the specified dimensions.
///
/// This function generates a completely transparent image by drawing a
/// transparent rectangle on a canvas and converting it to PNG format.
///
/// Parameters:
/// * [size] - The dimensions (width and height) of the transparent image to
/// create
///
/// Returns:
/// A [Future<Uint8List>] containing the PNG image data as bytes.
///
/// Example:
/// ```dart
/// final imageSize = Size(100, 100);
/// final transparentImageBytes = await createTransparentImage(imageSize);
/// ```
///
/// The resulting image will be completely transparent (alpha channel = 0)
/// and can be used as a base layer or placeholder in image editing operations.
Future<Uint8List> createTransparentImage(Size size) async {
  final width = size.width;
  final height = size.height;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
  final paint = Paint()..color = const ui.Color.fromARGB(0, 0, 0, 0);
  canvas.drawRect(Rect.fromLTWH(0.0, 0.0, width, height), paint);

  final picture = recorder.endRecording();
  final img = await picture.toImage(width.toInt(), height.toInt());
  final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);

  return pngBytes!.buffer.asUint8List();
}
