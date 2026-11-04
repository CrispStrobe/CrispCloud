import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

void main() {
  test('studio card PNG decodes', () async {
    final bytes = PngBytes.studioCard(width: 48, height: 32);
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    expect(frame.image.width, 48);
    expect(frame.image.height, 32);
  });
}
