import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import '../../quds_office_engine/tool/fidelity/layout_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);
  for (final entry in layoutCases().entries) {
    testWidgets(
      '${entry.key} pages match reviewed goldens before and after export',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(640, 460);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var doc = entry.value;
        final pageCount = {
          'rtl': 1,
          'columns_sections': 3,
          'continued_notes': 3,
          'tall_table': 4,
        }[entry.key]!;
        for (int cycle = 0; cycle < 3; cycle++) {
          final laid = WordLayoutEngine(font: null).layout(doc);
          expect(laid.pages.length, pageCount);
          expect(laid.pages, isNotEmpty);
          for (int page = 0; page < laid.pages.length; page++) {
            final selected = laid.pages[page];
            // A page-sized viewport makes every continuation and section visible.
            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: RepaintBoundary(
                  key: const ValueKey('page'),
                  child: WordCanvas(
                    document: doc,
                    laidOut: LaidOutDocument(
                      pages: [selected],
                      pageSize: WmlPageSize(
                        width: selected.width,
                        height: selected.height,
                      ),
                    ),
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
              find.byKey(const ValueKey('page')),
              matchesGoldenFile('goldens/${entry.key}_${page + 1}.png'),
            );
          }
          final bytes = WordSerializer().writeBytes(doc);
          Directory('build/fidelity-layout').createSync(recursive: true);
          File(
            'build/fidelity-layout/${entry.key}-${cycle + 1}.docx',
          ).writeAsBytesSync(bytes);
          doc = WordDeserializer().readBytes(bytes);
        }
      },
    );
  }
}
