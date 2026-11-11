import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// Three distinct pages prove first/even/default header and footer pictures,
/// forced page breaks and two-column layout survive asynchronous save/reopen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);
  testWidgets('first even and default stories retain reviewed page goldens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1120);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var doc = WordDeserializer().readBytes(
      File(
        '../quds_office_engine/test/fixtures/fidelity/story-media.docx',
      ).readAsBytesSync(),
    );
    final section = doc.sections.single;
    section.columnCount = 2;
    section.columnSpace = 18;
    section.columnSep = true;
    for (var page = 2; page <= 3; page++) {
      section.blocks.add(
        WmlParagraph(
          properties: WmlParagraphProps(pageBreakBefore: true),
          inlines: [WmlRun(text: 'Page $page: header and footer ownership')],
        ),
      );
      section.blocks.add(
        WmlParagraph(
          inlines: [
            WmlRun(
              text: List.filled(
                45,
                'Column text stays readable after export.',
              ).join(' '),
            ),
          ],
        ),
      );
    }
    const colors = <List<List<int>>>[
      [
        [255, 255, 0],
        [0, 255, 255],
      ],
      [
        [255, 0, 255],
        [255, 165, 0],
      ],
      [
        [0, 128, 0],
        [0, 0, 255],
      ],
    ];
    for (var cycle = 0; cycle < 2; cycle++) {
      // The authored fixture has no styles part or paragraph spacing. Keep
      // that source layout explicit when reviewing its page image; imported
      // paragraphs must not acquire the defaults used for newly created ones.
      expect(doc.paragraphs.first.properties.spacingAfter, 0);
      expect(doc.paragraphs.first.properties.lineSpacing, 1);
      final layout = WordLayoutEngine(font: null).layout(doc);
      expect(layout.pages, hasLength(3));
      for (var page = 0; page < 3; page++) {
        final viewport = VirtualViewport(
          origin: Offset(0, layout.pageStackTop(page, 4 / 3) - 24),
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: const ValueKey('page'),
              child: WordCanvas(
                document: doc,
                laidOut: layout,
                caret: CaretEngine(),
                viewport: viewport,
                config: OfficeSurfaceConfig(
                  mode: OfficeInteractionMode.viewing,
                  theme: OfficeTheme.light.copyWith(fontFamily: 'Arial'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final RenderRepaintBoundary boundary = tester.renderObject(
          find.byKey(const ValueKey('page')),
        );
        var painted = false;
        for (var attempt = 0; attempt < 100 && !painted; attempt++) {
          painted =
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                final found = <bool>[false, false];
                for (
                  var offset = 0;
                  offset < bytes.lengthInBytes;
                  offset += 4
                ) {
                  final y = offset ~/ (image.width * 4);
                  for (var band = 0; band < 2; band++) {
                    if ((band == 0 && y > 180) || (band == 1 && y < 900)) {
                      continue;
                    }
                    final color = colors[page][band];
                    if ((bytes.getUint8(offset) - color[0]).abs() < 3 &&
                        (bytes.getUint8(offset + 1) - color[1]).abs() < 3 &&
                        (bytes.getUint8(offset + 2) - color[2]).abs() < 3) {
                      found[band] = true;
                    }
                  }
                }
                image.dispose();
                if (!found.every((value) => value)) {
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                }
                return found.every((value) => value);
              }) ??
              false;
          await tester.pumpAndSettle();
        }
        if (!painted) {
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            final output = File(
              'build/fidelity-diagnostics/story-page-${page + 1}-$cycle.png',
            );
            output.parent.createSync(recursive: true);
            output.writeAsBytesSync(bytes.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(
          painted,
          isTrue,
          reason:
              'Both owning-part pictures must paint on page ${page + 1}, cycle $cycle',
        );
        await expectLater(
          find.byKey(const ValueKey('page')),
          matchesGoldenFile('goldens/office_stories_page_${page + 1}.png'),
        );
      }
      if (cycle == 0) {
        final bytes = (await tester.runAsync(
          () => OfficeIsolateSave.word(doc),
        ))!;
        final output = File('build/fidelity-story-goldens/three-pages.docx');
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes);
        doc = WordDeserializer().readBytes(bytes);
      }
    }
  });
}
