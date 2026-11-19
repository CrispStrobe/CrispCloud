import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Future<ui.Image> _rulerImage(OfficeTheme theme, {bool readout = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(theme.canvasBackground, ui.BlendMode.src);
  WordRuler.paint(
    canvas,
    const ui.Size(700, 420),
    pageLeft: 40,
    pageTop: 40,
    scale: 1,
    pageWidth: 612,
    pageHeight: 792,
    margins: const WmlPageMargins(),
    indent: const WmlIndent(),
    tabs: const <WmlTabStop>[WmlTabStop(position: 36)],
    rtl: false,
    theme: theme,
    active: readout ? const RulerHit(RulerHitKind.firstLine) : null,
    readout: readout ? '1.00 in' : null,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(700, 420);
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final entry in <String, OfficeTheme>{
    'dark': OfficeTheme.dark,
    'high contrast': OfficeTheme.highContrast,
    'dark chrome with white paper': OfficeTheme.dark.copyWith(
      pageBackground: const ui.Color(0xFFFFFFFF),
    ),
  }.entries) {
    test(
      '${entry.key} rulers and drag readouts follow chrome colors',
      () async {
        final theme = entry.value;
        final image = await _rulerImage(theme, readout: true);
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          ui.Color pixel(int x, int y) {
            final offset = (y * image.width + x) * 4;
            return ui.Color.fromARGB(
              pixels.getUint8(offset + 3),
              pixels.getUint8(offset),
              pixels.getUint8(offset + 1),
              pixels.getUint8(offset + 2),
            );
          }

          expect(pixel(680, 2), theme.chromeFill);
          expect(pixel(44, 18), theme.frozenFill);
          expect(pixel(206, 18), theme.headerFill);
          expect(pixel(18, 206), theme.headerFill);
          expect(pixel(84, 44), theme.chromeFill);
          var readableReadoutPixels = 0;
          for (var y = 33; y < 44; y++) {
            for (var x = 87; x < 137; x++) {
              if (pixel(x, y).computeLuminance() > 0.5) {
                readableReadoutPixels++;
              }
            }
          }
          expect(readableReadoutPixels, greaterThan(15));
        } finally {
          image.dispose();
        }
      },
    );
  }

  test('light ruler surfaces retain their established palette', () async {
    final image = await _rulerImage(OfficeTheme.light);
    try {
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      int rgb(int x, int y) {
        final offset = (y * image.width + x) * 4;
        return pixels.getUint8(offset) << 16 |
            pixels.getUint8(offset + 1) << 8 |
            pixels.getUint8(offset + 2);
      }

      expect(rgb(680, 2), 0xEEEEEE);
      expect(rgb(44, 18), 0xD0D0D0);
      expect(rgb(206, 18), 0xFAFAFA);
      expect(rgb(18, 206), 0xFAFAFA);
    } finally {
      image.dispose();
    }
  });
}
