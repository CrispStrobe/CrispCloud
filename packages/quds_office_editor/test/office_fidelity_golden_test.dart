import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);
  testWidgets('DOCX import and exported reopen match reviewed page golden', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
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
      await expectLater(
        find.byKey(const ValueKey<String>('document')),
        matchesGoldenFile('goldens/office_fidelity_word.png'),
      );
      doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
    }
  });
}
