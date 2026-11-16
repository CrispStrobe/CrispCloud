import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);
  for (final scale in [1.0, 2.0]) {
    test(
      'underline gaps preserve glyph ink and geometry at scale $scale',
      () async {
        const text = 'Hyperlink typography gypq';
        final document = WmlDocument.empty(text: text);
        document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties = WmlRunProps(
          fontSizeHalfPoints: 48,
          underline: WmlUnderline.single,
        );
        final controller = WordEditorController(document: document);
        addTearDown(controller.dispose);
        final first =
            controller.documentLaidOut.pages.first.lines.first.glyphs.first;
        final painter = PaintRunText.painterFor(
          text: text,
          first: first,
          color: const Color(0xFF0066CC),
          decoration: TextDecoration.underline,
        )..layout();
        addTearDown(painter.dispose);
        final baseline = painter.computeDistanceToActualBaseline(
          TextBaseline.alphabetic,
        );
        Future<ui.Image> render(bool gaps) async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..scale(scale);
          canvas.drawColor(const Color(0xFFFFFFFF), BlendMode.src);
          if (gaps) {
            PaintRunText.paintUnderlined(
              canvas,
              const Offset(10, 10),
              decorated: painter,
              text: text,
              first: first,
              color: const Color(0xFF0066CC),
            );
          } else {
            painter.paint(canvas, const Offset(10, 10));
          }
          final picture = recorder.endRecording();
          final result = await picture.toImage(
            (400 * scale).toInt(),
            (65 * scale).toInt(),
          );
          picture.dispose();
          return result;
        }

        final before = await render(false);
        final after = await render(true);
        final oldPixels = (await before.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final newPixels = (await after.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final above = ((10 + baseline - 1) * scale).floor() * before.width * 4;
        expect(newPixels.take(above), orderedEquals(oldPixels.take(above)));
        var oldInk = 0;
        var newInk = 0;
        for (var i = above; i < oldPixels.length; i += 4) {
          if (oldPixels[i] < 128) oldInk++;
          if (newPixels[i] < 128) newInk++;
        }
        expect(newInk, greaterThan(0));
        expect(
          newInk,
          lessThan(oldInk),
          reason: 'Descenders need visible gaps in the underline',
        );
        final output = Directory('build/underline-preview')
          ..createSync(recursive: true);
        File('${output.path}/before-$scale.png').writeAsBytesSync(
          (await before.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
        File('${output.path}/after-$scale.png').writeAsBytesSync(
          (await after.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
        before.dispose();
        after.dispose();
      },
    );
  }
}
