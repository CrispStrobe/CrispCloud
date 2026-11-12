import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);
  for (final wrap in WmlFrameWrap.values) {
    testWidgets('${wrap.name} frame wrap survives three native saves', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(640, 460);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final package = OpcPackage.create(OpcPackageKind.word);
      package
          .getPart('/word/document.xml')!
          .writeText(
            File(
              '../quds_office_engine/test/fixtures/fidelity/frame_wrap_source.xml',
            ).readAsStringSync(),
          );
      var document = WordDeserializer().read(package);
      document.sections.single.blocks.whereType<WmlFrame>().single.wrap = wrap;
      for (var cycle = 0; cycle < 4; cycle++) {
        final laid = WordLayoutEngine(font: null).layout(document);
        expect(laid.pages, hasLength(1));
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: const ValueKey('frame-page'),
              child: WordCanvas(
                document: document,
                laidOut: laid,
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
          find.byKey(const ValueKey('frame-page')),
          matchesGoldenFile('goldens/frame_wrap_${wrap.name}.png'),
          reason: '${wrap.name} cycle $cycle',
        );
        if (cycle < 3) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
      }
    });
  }
}
