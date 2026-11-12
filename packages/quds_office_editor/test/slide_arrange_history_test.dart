import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

SlideEditorController _controller({OfficeInteractionMode? mode}) {
  final controller = SlideEditorController(
    config: OfficeSurfaceConfig(mode: mode ?? OfficeInteractionMode.editing),
    presentation: PmlPresentation(
      slides: [
        for (int slide = 0; slide < 2; slide++)
          PmlSlide(
            id: 256 + slide,
            shapes: [
              for (int index = 0; index < 4; index++)
                PmlShape(
                  id: index + 2,
                  name: 'Card $index',
                  text: 'Card $index',
                  transform: PmlTransform(
                    x: [0, 40, 80, 103][index],
                    y: [0, 50, 90, 103][index],
                    cx: [10, 17, 9, 11][index],
                    cy: [10, 17, 9, 11][index],
                  ),
                ),
            ],
          ),
      ],
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

List<(int, int, int, int, int)> _geometry(PmlSlide slide) => [
  for (final shape in slide.shapes)
    (
      shape.transform.x,
      shape.transform.y,
      shape.transform.cx,
      shape.transform.cy,
      shape.transform.rot,
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('independent groups never share a slide group identity', () {
    final controller = _controller();
    final shapes = controller.slide.shapes;
    final first = controller.groupShapes(shapes: shapes.sublist(0, 2));
    final second = controller.groupShapes(shapes: shapes.sublist(2, 4));
    expect(first, isNot(second));
    controller.selectShape(null);
    controller.selectShape(shapes[0]);
    expect(controller.selectedShapes, shapes.sublist(0, 2));
    controller.nudgeSelected(100, 0);
    expect(shapes.map((shape) => shape.transform.x), [100, 140, 80, 103]);
  });

  for (final axis in PmlAlignAxis.values) {
    test('${axis.name} alignment is one owning-slide undo command', () {
      final controller = _controller();
      final owning = controller.slide;
      final original = _geometry(owning);
      final other = controller.presentation.slides[1];
      final otherOriginal = _geometry(other);
      final revision = controller.contentRevision;
      controller.alignShapes(axis);
      final arranged = _geometry(owning);
      expect(arranged, isNot(original));
      expect(controller.canUndo, isTrue);
      expect(controller.isDirty, isTrue);
      expect(controller.contentRevision, revision + 1);
      controller.setActiveSlide(1);
      controller.undo();
      expect(_geometry(owning), original);
      expect(_geometry(other), otherOriginal);
      expect(controller.canUndo, isFalse);
      expect(controller.slide, same(other));
      controller.redo();
      expect(_geometry(owning), arranged);
      expect(_geometry(other), otherOriginal);
      expect(controller.slide, same(other));
    });
  }

  for (final horizontal in [true, false]) {
    test(
      '${horizontal ? 'horizontal' : 'vertical'} distribution preserves endpoints and history',
      () {
        final controller = _controller();
        final owning = controller.slide;
        final original = _geometry(owning);
        controller.distributeShapes(horizontal: horizontal);
        final arranged = _geometry(owning);
        expect(
          owning.shapes.map(
            (shape) => horizontal ? shape.transform.x : shape.transform.y,
          ),
          [0, 32, 72, 103],
        );
        expect(controller.canUndo, isTrue);
        controller.setActiveSlide(1);
        controller.undo();
        expect(_geometry(owning), original);
        controller.redo();
        expect(_geometry(owning), arranged);
      },
    );
  }

  test(
    'group and ungroup restore earlier membership through undo and redo',
    () {
      final controller = _controller();
      final owning = controller.slide;
      final shapes = owning.shapes;
      shapes[0].groupId = 7;
      shapes[1].groupId = 7;
      final id = controller.groupShapes(shapes: shapes);
      expect(shapes.map((shape) => shape.groupId), everyElement(id));
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(shapes.map((shape) => shape.groupId), [7, 7, null, null]);
      controller.redo();
      expect(shapes.map((shape) => shape.groupId), everyElement(id));
      controller.ungroupShapes(shapes: shapes);
      expect(shapes.map((shape) => shape.groupId), everyElement(isNull));
      controller.setActiveSlide(1);
      controller.undo();
      expect(shapes.map((shape) => shape.groupId), everyElement(id));
      expect(
        controller.slide.shapes.map((shape) => shape.groupId),
        everyElement(isNull),
      );
      controller.redo();
      expect(shapes.map((shape) => shape.groupId), everyElement(isNull));
    },
  );

  test('no-op arrangements retain clean state and redo history', () {
    final controller = _controller();
    final shapes = controller.slide.shapes;
    controller.alignShapes(PmlAlignAxis.left, shapes: [shapes[0]]);
    controller.distributeShapes(
      horizontal: false,
      shapes: shapes.sublist(0, 2),
    );
    controller.ungroupShapes();
    expect(controller.groupShapes(shapes: [shapes[0]]), isNull);
    expect(controller.canUndo, isFalse);
    expect(controller.isDirty, isFalse);
    expect(controller.contentRevision, 0);
    controller.groupShapes(shapes: shapes.sublist(0, 2));
    controller.undo();
    expect(controller.canRedo, isTrue);
    final revision = controller.contentRevision;
    controller.ungroupShapes();
    controller.alignShapes(PmlAlignAxis.left, shapes: [shapes[0]]);
    expect(controller.canRedo, isTrue);
    expect(controller.contentRevision, revision);
  });

  test('already arranged geometry does not consume another history step', () {
    final controller = _controller();
    controller.alignShapes(PmlAlignAxis.bottom);
    final revision = controller.contentRevision;
    controller.alignShapes(PmlAlignAxis.bottom);
    expect(controller.contentRevision, revision);
    controller.undo();
    expect(controller.canUndo, isFalse);
  });

  for (final mode in [
    OfficeInteractionMode.viewing,
    OfficeInteractionMode.selecting,
  ]) {
    test('$mode blocks arrangement and group changes', () {
      final controller = _controller(mode: mode);
      final original = _geometry(controller.slide);
      controller.alignShapes(PmlAlignAxis.center);
      controller.distributeShapes(horizontal: true);
      expect(controller.groupShapes(), isNull);
      controller.ungroupShapes();
      expect(_geometry(controller.slide), original);
      expect(
        controller.slide.shapes.map((shape) => shape.groupId),
        everyElement(isNull),
      );
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    });
  }

  test('noncontiguous groups reject without changing state or selection', () {
    final controller = _controller();
    final shapes = controller.slide.shapes;
    controller.selectShape(shapes[0]);
    expect(
      () => controller.groupShapes(shapes: [shapes[0], shapes[2]]),
      throwsStateError,
    );
    expect(shapes.map((shape) => shape.groupId), everyElement(isNull));
    expect(controller.selectedShapes, [shapes[0]]);
    expect(controller.canUndo, isFalse);
    expect(controller.isDirty, isFalse);
  });

  for (final ungroup in [false, true]) {
    test(
      '${ungroup ? 'ungroup' : 'regroup'} cannot split an existing group',
      () {
        final controller = _controller();
        final shapes = controller.slide.shapes;
        for (final shape in shapes) {
          shape.groupId = 9;
        }
        expect(
          () => ungroup
              ? controller.ungroupShapes(shapes: shapes.sublist(1, 3))
              : controller.groupShapes(shapes: shapes.sublist(1, 3)),
          throwsStateError,
        );
        expect(shapes.map((shape) => shape.groupId), everyElement(9));
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
        expect(controller.contentRevision, 0);
      },
    );
  }

  for (final operation in ['group', 'ungroup', 'align', 'distribute']) {
    test('$operation rejects duplicate and foreign shapes atomically', () {
      final controller = _controller();
      final own = controller.slide.shapes;
      final foreign = controller.presentation.slides[1].shapes.first;
      final original = _geometry(controller.slide);
      for (final shapes in [
        [own[0], foreign, own[1]],
        [own[0], own[1], own[0]],
      ]) {
        void arrange() {
          switch (operation) {
            case 'group':
              controller.groupShapes(shapes: shapes);
            case 'ungroup':
              controller.ungroupShapes(shapes: shapes);
            case 'align':
              controller.alignShapes(PmlAlignAxis.right, shapes: shapes);
            case 'distribute':
              controller.distributeShapes(horizontal: true, shapes: shapes);
          }
        }

        expect(arrange, throwsArgumentError);
        expect(_geometry(controller.slide), original);
        expect(own.map((shape) => shape.groupId), everyElement(isNull));
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
      }
    });
  }

  test('regrouping an entire existing group preserves identity and redo', () {
    final controller = _controller();
    final shapes = controller.slide.shapes;
    final id = controller.groupShapes(shapes: shapes.sublist(0, 2));
    controller.groupShapes(shapes: shapes.sublist(2, 4));
    controller.undo();
    final revision = controller.contentRevision;
    expect(controller.canRedo, isTrue);
    expect(controller.groupShapes(shapes: shapes.sublist(0, 2)), id);
    expect(controller.contentRevision, revision);
    expect(controller.canRedo, isTrue);
    controller.undo();
    expect(shapes.map((shape) => shape.groupId), everyElement(isNull));
  });
}
