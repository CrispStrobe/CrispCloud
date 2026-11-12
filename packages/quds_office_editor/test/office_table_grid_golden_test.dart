import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../../quds_office_engine/tool/fidelity/step_input.dart';
import '../../quds_office_engine/tool/fidelity/word_steps.dart' as steps;

const _fixtures = '../quds_office_engine/test/fixtures/fidelity';
const _pageKey = ValueKey('table-grid-page');

WmlDocument _readFixture(String name) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(File('$_fixtures/$name').readAsStringSync());
  return WordDeserializer().read(package);
}

WmlDocument _scripted(String phase) {
  final document = _readFixture('table_grid_source.xml');
  for (final scriptPhase in [
    if (phase != 'unchanged') 'format',
    if (phase == 'replace' || phase == 'unmerge') phase,
  ]) {
    final script = '$_fixtures/scripts/table-grid-$scriptPhase.json';
    for (final step in readSteps(script)) {
      steps.applyStep(document, step);
    }
  }
  return document;
}

typedef _Pixels = ({int width, int height, Uint8List rgba, Uint8List png});

Future<_Pixels> _paint(
  WidgetTester tester,
  WmlDocument document,
  String phase,
) async {
  final layout = WordLayoutEngine(font: null).layout(document);
  expect(layout.pages, hasLength(1));
  expect(
    layout.pages.single.frames.where(
      (box) => box.kind == LaidOutBoxKind.tableCell,
    ),
    hasLength(phase == 'unmerge' ? 12 : 9),
    reason: 'Both the outer table and the nested grid must be laid out',
  );
  final paragraphs = document.paragraphs.toList();
  for (var index = 0; index < paragraphs.length; index++) {
    final lines = layout.pages.single.lines.where(
      (line) => line.paragraphIndex == index,
    );
    final offsets =
        lines
            .expand((line) => line.glyphs)
            .where((glyph) => !glyph.glyph.isSpace)
            .map((glyph) => glyph.glyph.logicalIndex)
            .toList()
          ..sort();
    expect(
      offsets,
      [
        for (var offset = 0; offset < paragraphs[index].text.length; offset++)
          if (paragraphs[index].text.codeUnitAt(offset) != 32) offset,
      ],
      reason:
          'Every authored Latin character must appear before pixel comparison',
    );
    final cells = layout.pages.single.frames.where(
      (box) =>
          box.kind == LaidOutBoxKind.tableCell &&
          box.paragraphIndex != null &&
          index >= box.paragraphIndex! &&
          index <= (box.paragraphEnd ?? box.paragraphIndex!),
    );
    if (cells.isEmpty) continue;
    final cell = cells.reduce((a, b) => a.width < b.width ? a : b);
    for (final line in lines) {
      expect(
        line.x + line.width,
        lessThanOrEqualTo(cell.x + cell.width - LaidOutLine.tableCellPad + .01),
        reason:
            'A reference cannot bless clipped text: ${paragraphs[index].text}',
      );
      expect(
        line.y + line.height,
        lessThanOrEqualTo(cell.y + cell.height + .01),
      );
    }
  }
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _pageKey,
        child: WordCanvas(
          // A new canvas prevents an earlier reference's cached picture from
          // accidentally satisfying the actual document's comparison.
          key: UniqueKey(),
          document: document,
          laidOut: layout,
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
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_pageKey),
  );
  final pixels = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      return (
        width: image.width,
        height: image.height,
        rgba: rgba.buffer.asUint8List(),
        png: png.buffer.asUint8List(),
      );
    } finally {
      image.dispose();
    }
  });
  return pixels!;
}

void _comparePixels(_Pixels actual, _Pixels reference, String scenario) {
  expect((actual.width, actual.height), (reference.width, reference.height));
  if (listEquals(actual.rgba, reference.rgba)) return;
  var first = 0;
  while (first < actual.rgba.length &&
      actual.rgba[first] == reference.rgba[first]) {
    first++;
  }
  final directory = Directory('build/fidelity-table-grid-goldens')
    ..createSync(recursive: true);
  File('${directory.path}/$scenario-actual.png').writeAsBytesSync(actual.png);
  File(
    '${directory.path}/$scenario-reference.png',
  ).writeAsBytesSync(reference.png);
  fail(
    '$scenario differs from independently authored reference pixels at '
    'x=${(first ~/ 4) % actual.width}, y=${(first ~/ 4) ~/ actual.width}; '
    'diagnostics: ${directory.path}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);
  for (final phase in ['unchanged', 'format', 'replace', 'unmerge']) {
    testWidgets(
      '$phase table grid matches authored pixels through three saves',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(640, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        // Only this independently authored raw input can create/update the PNG.
        // The actual scripted documents below always compare exact pixels, even
        // when this test is invoked deliberately with --update-goldens.
        final reference = await _paint(
          tester,
          _readFixture(
            phase == 'unchanged'
                ? 'table_grid_source.xml'
                : 'table_grid_${phase}_expected.xml',
          ),
          phase,
        );
        await expectLater(
          find.byKey(_pageKey),
          matchesGoldenFile('goldens/table_grid_$phase.png'),
          reason: 'Independently authored $phase visual reference',
        );

        for (final isolate in [false, true]) {
          var document = _scripted(phase);
          for (var cycle = 0; cycle <= 3; cycle++) {
            final actual = await _paint(tester, document, phase);
            _comparePixels(
              actual,
              reference,
              '$phase-${isolate ? 'isolate' : 'direct'}-$cycle',
            );
            if (cycle < 3) {
              final bytes = isolate
                  ? (await tester.runAsync(
                      () => OfficeIsolateSave.word(document),
                    ))!
                  : WordSerializer().writeBytes(document);
              document = WordDeserializer().readBytes(bytes);
            }
          }
        }
      },
    );
  }
}
