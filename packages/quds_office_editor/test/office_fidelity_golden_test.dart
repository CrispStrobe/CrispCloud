import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);
  testWidgets('DOCX import and exported reopen match reviewed page golden', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1120);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final Uint8List input = File(
      '../quds_office_engine/test/fixtures/fidelity/word.docx',
    ).readAsBytesSync();
    WmlDocument doc = WordDeserializer().readBytes(input);
    for (var cycle = 0; cycle < 2; cycle++) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: const ValueKey<String>('document'),
            child: WordCanvas(
              document: doc,
              laidOut: WordLayoutEngine(font: null).layout(doc),
              caret: CaretEngine(),
              config: OfficeSurfaceConfig(
                mode: OfficeInteractionMode.viewing,
                theme: OfficeTheme.light.copyWith(fontFamily: 'Arial'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Native image decoding runs outside the test's fake clock. Wait for
      // actual fixture pixels, so a blank image can never become the baseline.
      final RenderRepaintBoundary boundary = tester.renderObject(
        find.byKey(const ValueKey<String>('document')),
      );
      var picturePainted = false;
      for (var attempt = 0; attempt < 100 && !picturePainted; attempt++) {
        picturePainted =
            await tester.runAsync(() async {
              final ui.Image image = await boundary.toImage();
              final ByteData pixels = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              image.dispose();
              for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
                if ((pixels.getUint8(offset) - 35).abs() <= 2 &&
                    (pixels.getUint8(offset + 1) - 100).abs() <= 2 &&
                    (pixels.getUint8(offset + 2) - 170).abs() <= 2) {
                  return true;
                }
              }
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return false;
            }) ??
            false;
        await tester.pumpAndSettle();
      }
      if (!picturePainted) {
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          Directory('build/fidelity-diagnostics').createSync(recursive: true);
          File(
            'build/fidelity-diagnostics/missing-picture.png',
          ).writeAsBytesSync(bytes.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(picturePainted, isTrue, reason: 'Fixture picture must be visible');
      await expectLater(
        find.byKey(const ValueKey<String>('document')),
        matchesGoldenFile('goldens/office_fidelity_word.png'),
      );
      doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
    }
  });
}
