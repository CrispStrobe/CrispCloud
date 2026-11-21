import 'dart:io';
import 'support/office_golden.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import '../../quds_office_engine/tool/fidelity/layout_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);
  for (final entry in layoutCases().entries) {
    testWidgets(
      '${entry.key} pages match reviewed goldens before and after three exports',
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
          // The 85-twip table padding introduced in e975cec1 fits the authored
          // row into three pages. Verify every character below as well as the
          // page count so a shorter result cannot hide dropped table content.
          'tall_table': 3,
        }[entry.key]!;
        const exportCycles = 3;
        // Check the original and every reopened export, including the last one.
        for (int cycle = 0; cycle <= exportCycles; cycle++) {
          final laid = WordLayoutEngine(font: null).layout(doc);
          expect(laid.pages.length, pageCount);
          expect(laid.pages, isNotEmpty);
          if (entry.key == 'tall_table') {
            final paragraphs = doc.paragraphs.toList();
            final tallIndex = paragraphs.indexWhere(
              (paragraph) => paragraph.text.contains('T000'),
            );
            expect(tallIndex, greaterThanOrEqualTo(0));
            final text = paragraphs[tallIndex].text;
            expect(
              RegExp(r'T\d{3}').allMatches(text).map((match) => match[0]),
              [
                for (var index = 0; index < 120; index++)
                  'T${index.toString().padLeft(3, '0')}',
              ],
            );
            final offsets =
                laid.pages
                    .expand((page) => page.lines)
                    .where((line) => line.paragraphIndex == tallIndex)
                    .expand((line) => line.glyphs)
                    .where((glyph) => !glyph.glyph.isSpace)
                    .map((glyph) => glyph.glyph.logicalIndex)
                    .toList()
                  ..sort();
            expect(offsets, [
              for (var offset = 0; offset < text.length; offset++)
                if (text.codeUnitAt(offset) != 32) offset,
            ], reason: 'Every tall-cell character appears exactly once');
            expect(
              laid.pages.last.lines.any(
                (line) => line.sourceText == 'After the table',
              ),
              isTrue,
            );
            expect(
              laid.pages
                  .expand((page) => page.notes)
                  .any(
                    (line) =>
                        line.sourceText?.contains('Late table note') ?? false,
                  ),
              isTrue,
            );
          }
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
              matchesGoldenFile(officeGolden('${entry.key}_${page + 1}.png')),
            );
          }
          if (cycle == exportCycles) break;
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
