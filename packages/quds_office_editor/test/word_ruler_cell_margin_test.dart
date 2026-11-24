import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  const margins = WmlPageMargins(left: 20, right: 20);
  for (final margin in [0.0, 4.0, 12.0]) {
    test('ruler uses configured cell margin $margin without a text line', () {
      expect(
        WordRuler.paragraphContentBox(
          margins: margins,
          pageWidth: 400,
          cellX: 35,
          cellWidth: 100,
          cellMargin: margin,
        ),
        (left: 35 + margin, right: 135 - margin),
      );
    });
  }

  test('zero-margin narrow empty cells retain their own ruler box', () {
    expect(
      WordRuler.paragraphContentBox(
        margins: margins,
        pageWidth: 400,
        cellX: 35,
        cellWidth: 8,
        cellMargin: 0,
      ),
      (left: 35, right: 43),
    );
  });

  test('empty cells use their own left and right ruler insets', () {
    expect(
      WordRuler.paragraphContentBox(
        margins: margins,
        pageWidth: 400,
        cellX: 35,
        cellWidth: 100,
        cellInsets: const WmlTableCellInsets(
          left: 3.5,
          top: 2,
          right: 6,
          bottom: 9,
        ),
      ),
      (left: 38.5, right: 129),
    );
  });

  test('actual line box takes precedence over fallback cell padding', () {
    expect(
      WordRuler.paragraphContentBox(
        margins: margins,
        pageWidth: 400,
        lineBoxX: 70,
        lineBoxWidth: 100,
        cellX: 35,
        cellWidth: 200,
        cellMargin: 12,
      ),
      (left: 70, right: 170),
    );
  });

  for (final margin in [-1.0, double.nan, double.infinity, 50.0]) {
    test('invalid cell ruler margin $margin fails explicitly', () {
      expect(
        () => WordRuler.paragraphContentBox(
          margins: margins,
          pageWidth: 400,
          cellX: 35,
          cellWidth: 100,
          cellMargin: margin,
        ),
        throwsArgumentError,
      );
    });
  }

  testWidgets('ruler markers preserve line and selected-frame precedence', (
    tester,
  ) async {
    const indent = WmlIndent(firstLine: 15);
    final body = WmlParagraph(
      properties: WmlParagraphProps(indent: indent),
      inlines: [WmlRun(text: 'Body')],
    );
    final frame = WmlFrame(
      x: 170,
      width: 96,
      blocks: [
        WmlParagraph(inlines: [WmlRun(text: 'Frame')]),
      ],
    );
    final section = WmlSection(
      pageSize: const WmlPageSize(width: 320, height: 300),
      margins: margins,
      blocks: [body, frame],
    );
    final document = WmlDocument(sections: [section]);
    final layout = WordLayoutEngine(font: null).layout(document);
    final line = layout.firstBodyLine(0)!.line;
    expect(line.boxWidth, greaterThan(0));
    expect(layout.pages.first.frames.any((box) => box.frame == frame), isTrue);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WordCanvas(
          document: document,
          laidOut: layout,
          caret: CaretEngine(),
          bodyLayoutIsCurrent: true,
          config: const OfficeSurfaceConfig(showRulers: true),
        ),
      ),
    );
    final canvas = tester.renderObject<RenderWordCanvas>(
      find.byType(WordCanvas),
    );
    final resize = WordRuler.cursorFor(const RulerHit(RulerHitKind.firstLine));
    MouseCursor cursorAt(double pageX) => canvas.cursorFor(
      Offset(canvas.windowForPagePoint(0, Offset(pageX, 0)).dx, 5),
    );

    final bodyMarker = line.boxX + indent.firstLine;
    final frameMarker =
        frame.pageX(section) + frame.insetLeft + indent.firstLine;
    expect(cursorAt(bodyMarker), resize);
    canvas.selectedFrame = frame;
    expect(cursorAt(frameMarker), resize);
    expect(cursorAt(bodyMarker), isNot(resize));
    frame.width = 12;
    expect(cursorAt(bodyMarker), resize);
    expect(cursorAt(frameMarker), isNot(resize));
  });
}
