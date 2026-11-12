import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/visual/paint_office_visual.dart';

ui.Image _image() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 1, 1),
    ui.Paint()..color = const ui.Color(0xff336699),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(1, 1);
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one pending decode serves a picture and its cache owns the image', () {
    final callbacks = <void Function(ui.Image)>[];
    final cache = VisualImageCache(
      decodeImage: (_, onDecoded) => callbacks.add(onDecoded),
    );
    final bytes = Uint8List.fromList([1, 2, 3]);
    var repaints = 0;
    cache.load(bytes, () => repaints++);
    cache.load(bytes, () => repaints++);
    expect(callbacks, hasLength(1));
    final image = _image();
    callbacks.single(image);
    expect(repaints, 1);
    expect(cache.get(bytes), same(image));
    cache.load(bytes, () => repaints++);
    expect(callbacks, hasLength(1));
    cache.dispose();
    expect(image.debugDisposed, isTrue);
    expect(cache.get(bytes), isNull);
    expect(cache.dispose, returnsNormally);
  });

  test(
    'decode finishing after owner disposal releases pixels without repaint',
    () {
      final callbacks = <void Function(ui.Image)>[];
      final cache = VisualImageCache(
        decodeImage: (_, onDecoded) => callbacks.add(onDecoded),
      );
      final bytes = Uint8List.fromList([4, 5, 6]);
      var repaints = 0;
      cache.load(bytes, () => repaints++);
      cache.dispose();
      final image = _image();
      callbacks.single(image);
      expect(image.debugDisposed, isTrue);
      expect(repaints, 0);
      expect(cache.get(bytes), isNull);
      cache.load(bytes, () => repaints++);
      expect(callbacks, hasLength(1));
      expect(cache.dispose, returnsNormally);
    },
  );
}
