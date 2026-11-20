import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

SlideEditorController _controller({bool grouped = false}) {
  final controller = SlideEditorController(
    presentation: PmlPresentation(
      slides: [
        PmlSlide(
          id: 256,
          shapes: [
            PmlShape(
              id: 2,
              name: 'Flipped connector',
              preset: PmlShapePreset.connector,
              strokeColor: 'FF0000',
              fillColor: '',
              groupId: grouped ? 7 : null,
              transform: const PmlTransform(
                x: 100 * 12700,
                y: 100 * 12700,
                cx: 120 * 12700,
                cy: 60 * 12700,
                flipH: true,
              ),
            ),
            if (grouped)
              PmlShape(
                id: 3,
                name: 'Vertically flipped connector',
                preset: PmlShapePreset.connector,
                strokeColor: '0000FF',
                fillColor: '',
                groupId: 7,
                transform: const PmlTransform(
                  x: 280 * 12700,
                  y: 180 * 12700,
                  cx: 100 * 12700,
                  cy: 60 * 12700,
                  flipV: true,
                ),
              ),
          ],
        ),
      ],
    ),
  );
  controller.selectShape(controller.slide.shapes.first);
  addTearDown(controller.dispose);
  return controller;
}

List<(bool, bool)> _orientation(Iterable<PmlShape> shapes) => [
  for (final shape in shapes) (shape.transform.flipH, shape.transform.flipV),
];

void _expectSavedOrientation(SlideEditorController controller) {
  final saved = SlideDeserializer().readBytes(
    SlideSerializer().writeBytes(controller.presentation),
  );
  expect(
    _orientation(saved.slides.single.shapes),
    _orientation(controller.slide.shapes),
  );
}

Future<void> _mount(
  WidgetTester tester,
  SlideEditorController controller,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 768,
          height: 453,
          child: SlideStage(
            slide: controller.slide,
            selected: controller.selected,
            selectedShapes: controller.selectedShapes,
            onSelect: controller.selectShape,
            onTransforms: controller.applyTransforms,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final grouped in [false, true]) {
    for (final action in ['move', 'resize', 'rotate']) {
      testWidgets(
        '${grouped ? 'group' : 'single'} $action retains connector orientation through history and saving',
        (tester) async {
          final controller = _controller(grouped: grouped);
          final shapes = controller.slide.shapes;
          final original = [for (final shape in shapes) shape.transform];
          final orientations = _orientation(shapes);
          await _mount(tester, controller);
          final bounds = grouped
              ? const Rect.fromLTWH(100, 100, 280, 140)
              : const Rect.fromLTWH(100, 100, 120, 60);
          final Offset from;
          final Offset to;
          switch (action) {
            case 'move':
              from = const Offset(160, 130);
              to = from + const Offset(37, 23);
            case 'resize':
              from = bounds.bottomRight;
              to = from + const Offset(50, 30);
            case 'rotate':
              from = Offset(bounds.center.dx, bounds.top - 18);
              to = bounds.center + Offset(bounds.height / 2 + 18, 0);
            default:
              throw StateError(action);
          }
          // The 768x453 stage leaves 24 points around a 720x405 slide.
          final gesture = await tester.startGesture(
            from + const Offset(24, 24),
          );
          await gesture.moveTo(to + const Offset(24, 24));
          await gesture.up();
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(controller.canUndo, isTrue);
          expect(_orientation(shapes), orientations);
          for (var index = 0; index < shapes.length; index++) {
            final transformed = shapes[index].transform;
            switch (action) {
              case 'move':
                expect(transformed.x, isNot(original[index].x));
              case 'resize':
                expect(transformed.cx, greaterThan(original[index].cx));
              case 'rotate':
                expect(transformed.rotationDegrees, closeTo(90, 0.01));
            }
          }
          _expectSavedOrientation(controller);
          controller.undo();
          expect([for (final shape in shapes) shape.transform], original);
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(_orientation(shapes), orientations);
          _expectSavedOrientation(controller);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  test('keyboard and group moves retain each connector orientation', () {
    final controller = _controller(grouped: true);
    final shapes = controller.slide.shapes;
    final original = [for (final shape in shapes) shape.transform];
    final orientations = _orientation(shapes);
    controller.nudgeSelected(11 * 12700, 7 * 12700);
    expect(shapes.map((shape) => shape.transform.xPoints), [111, 291]);
    expect(_orientation(shapes), orientations);
    controller.undo();
    expect([for (final shape in shapes) shape.transform], original);
    controller.applyTransform(
      shapes.first,
      original.first.copyWith(x: original.first.x + 23 * 12700),
    );
    expect(shapes.map((shape) => shape.transform.xPoints), [123, 303]);
    expect(_orientation(shapes), orientations);
    controller.undo();
    expect([for (final shape in shapes) shape.transform], original);
    controller.redo();
    expect(_orientation(shapes), orientations);
    _expectSavedOrientation(controller);
  });

  test('copy and paste retain frozen connector orientation', () async {
    final clipboard = OfficeClipboard.instance;
    final useSystem = clipboard.useSystem;
    clipboard.useSystem = false;
    clipboard.clear();
    addTearDown(() {
      clipboard.clear();
      clipboard.useSystem = useSystem;
    });
    final controller = _controller();
    final source = controller.slide.shapes.single;
    source.transform = source.transform.copyWith(flipV: true, rot: 15 * 60000);
    await controller.copyToClipboard();
    source.transform = source.transform.copyWith(x: 300 * 12700, flipH: false);
    await controller.pasteFromClipboard();
    final pasted = controller.slide.shapes.last;
    expect(controller.slide.shapes, hasLength(2));
    expect(pasted.id, isNot(source.id));
    expect(pasted.preset, PmlShapePreset.connector);
    expect(pasted.transform.xPoints, 110);
    expect(pasted.transform.yPoints, 110);
    expect(pasted.transform.rotationDegrees, 15);
    expect(_orientation([pasted]), [(true, true)]);
    _expectSavedOrientation(controller);
    controller.undo();
    expect(controller.slide.shapes, [source]);
    controller.redo();
    expect(_orientation([controller.slide.shapes.last]), [(true, true)]);
  });
}
