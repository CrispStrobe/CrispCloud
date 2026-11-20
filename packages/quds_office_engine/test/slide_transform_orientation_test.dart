import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/office_operations.dart';
import 'package:test/test.dart';

const _emu = 12700;
const _orientations = <(bool, bool)>[
  (true, false),
  (false, true),
  (true, true),
  (false, false),
];

PmlShape _connector(
  int id,
  (bool, bool) orientation, {
  int x = 10,
  int y = 20,
  int width = 30,
  int height = 40,
}) => PmlShape(
  id: id,
  name: 'Connector $id',
  preset: PmlShapePreset.connector,
  transform: PmlTransform(
    x: x * _emu,
    y: y * _emu,
    cx: width * _emu,
    cy: height * _emu,
    rot: 5 * 60000,
    flipH: orientation.$1,
    flipV: orientation.$2,
  ),
);

List<PmlShape> _arrangement() => <PmlShape>[
  _connector(2, _orientations[0], x: 0, y: 0, width: 10, height: 20),
  _connector(3, _orientations[1], x: 40, y: 60, width: 30, height: 10),
  _connector(4, _orientations[2], x: 80, y: 100, width: 10, height: 20),
  _connector(5, _orientations[3], x: 120, y: 140, width: 20, height: 10),
];

(bool, bool) _orientation(PmlTransform transform) =>
    (transform.flipH, transform.flipV);

Map<String, double> _geometry(PmlTransform transform) => <String, double>{
  'x': transform.xPoints,
  'y': transform.yPoints,
  'width': transform.widthPoints,
  'height': transform.heightPoints,
  'rotation': transform.rotationDegrees,
};

void main() {
  const alignedPositions = <PmlAlignAxis, List<double>>{
    PmlAlignAxis.left: <double>[0, 0, 0, 0],
    PmlAlignAxis.center: <double>[65, 55, 65, 60],
    PmlAlignAxis.right: <double>[130, 110, 130, 120],
    PmlAlignAxis.top: <double>[0, 0, 0, 0],
    PmlAlignAxis.middle: <double>[65, 70, 65, 70],
    PmlAlignAxis.bottom: <double>[130, 140, 130, 140],
  };
  for (final axis in PmlAlignAxis.values) {
    test('${axis.name} alignment preserves each connector orientation', () {
      final shapes = _arrangement();
      final before = <PmlTransform>[
        for (final shape in shapes) shape.transform,
      ];
      PmlArrange.align(shapes, axis);
      final horizontal = <PmlAlignAxis>{
        PmlAlignAxis.left,
        PmlAlignAxis.center,
        PmlAlignAxis.right,
      }.contains(axis);
      expect(
        shapes.map(
          (shape) =>
              horizontal ? shape.transform.xPoints : shape.transform.yPoints,
        ),
        alignedPositions[axis],
      );
      for (var index = 0; index < shapes.length; index++) {
        final actual = shapes[index].transform;
        expect(_orientation(actual), _orientations[index]);
        expect(
          (actual.cx, actual.cy, actual.rot),
          (before[index].cx, before[index].cy, before[index].rot),
        );
        expect(
          horizontal ? actual.y : actual.x,
          horizontal ? before[index].y : before[index].x,
        );
      }
    });
  }

  for (final horizontal in <bool>[true, false]) {
    test(
      '${horizontal ? 'horizontal' : 'vertical'} distribution retains flips while changing gaps',
      () {
        final shapes = _arrangement();
        final before = <PmlTransform>[
          for (final shape in shapes) shape.transform,
        ];
        PmlArrange.distribute(shapes, horizontal: horizontal);
        int position(PmlTransform transform) =>
            horizontal ? transform.x : transform.y;
        expect(position(shapes.first.transform), position(before.first));
        expect(position(shapes.last.transform), position(before.last));
        expect(position(shapes[1].transform), isNot(position(before[1])));
        expect(position(shapes[2].transform), isNot(position(before[2])));
        for (var index = 0; index < shapes.length; index++) {
          final actual = shapes[index].transform;
          expect(_orientation(actual), _orientations[index]);
          expect(
            (actual.cx, actual.cy, actual.rot),
            (before[index].cx, before[index].cy, before[index].rot),
          );
        }
      },
    );
  }

  const partialUpdates = <String, double>{
    'x': 31,
    'y': 42,
    'width': 53,
    'height': 64,
    'rotation': 27,
  };
  for (final update in partialUpdates.entries) {
    test(
      'shapeGeometry ${update.key}-only update preserves orientation through PPTX save',
      () {
        for (final orientation in _orientations) {
          final shape = _connector(2, orientation);
          final deck = PmlPresentation(
            slides: <PmlSlide>[
              PmlSlide(id: 256, shapes: <PmlShape>[shape]),
            ],
          );
          final expected = _geometry(shape.transform)
            ..[update.key] = update.value;
          OfficeOperationCatalog.apply(
            deck,
            'pptx.shapeGeometry',
            <String, Object?>{'slide': 0, 'shape': 0, update.key: update.value},
          );
          expect(_geometry(shape.transform), expected);
          expect(_orientation(shape.transform), orientation);
          final reopened = SlideDeserializer().readBytes(
            SlideSerializer().writeBytes(deck),
          );
          final restored = reopened.slides.single.shapes.single;
          expect(restored.preset, PmlShapePreset.connector);
          expect(_geometry(restored.transform), expected);
          expect(_orientation(restored.transform), orientation);
        }
      },
    );
  }

  for (final orientation in _orientations) {
    test('morph retains shared flip state $orientation throughout a move', () {
      final from = PmlSlide(
        id: 256,
        shapes: <PmlShape>[_connector(2, orientation, x: 0, y: 0)],
      );
      final to = PmlSlide(
        id: 257,
        shapes: <PmlShape>[_connector(2, orientation, x: 100, y: 60)],
      );
      for (final progress in <double>[0, 0.25, 0.5, 0.75, 1]) {
        final frame = PmlMorph.frames(from, to, progress).single;
        expect(frame.role, PmlMorphRole.keep);
        expect(_orientation(frame.transform), orientation);
      }
      expect(PmlMorph.frames(from, to, 0).single.transform.xPoints, 0);
      expect(PmlMorph.frames(from, to, 0.5).single.transform.xPoints, 50);
      expect(PmlMorph.frames(from, to, 1).single.transform.xPoints, 100);
    });
  }

  test('morph endpoints retain their distinct authored orientations', () {
    final fromShape = _connector(2, (true, false));
    final toShape = _connector(2, (false, true), x: 100, y: 60);
    final from = PmlSlide(id: 256, shapes: <PmlShape>[fromShape]);
    final to = PmlSlide(id: 257, shapes: <PmlShape>[toShape]);
    expect(_orientation(PmlMorph.frames(from, to, 0).single.transform), (
      true,
      false,
    ));
    expect(_orientation(PmlMorph.frames(from, to, 1).single.transform), (
      false,
      true,
    ));
    expect(_orientation(fromShape.transform), (true, false));
    expect(_orientation(toShape.transform), (false, true));
  });
}
