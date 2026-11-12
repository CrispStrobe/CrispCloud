import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

PmlShape _shape(int id, int x, int y, int width, int height) => PmlShape(
  id: id,
  name: 'Shape $id',
  text: 'Shape $id',
  transform: PmlTransform(x: x, y: y, cx: width, cy: height, rot: 1200000),
);

List<(int, int, int, int, int)> _geometry(List<PmlShape> shapes) => [
  for (final shape in shapes)
    (
      shape.transform.x,
      shape.transform.y,
      shape.transform.cx,
      shape.transform.cy,
      shape.transform.rot,
    ),
];

Iterable<XmlElement> _elements(XmlElement root) sync* {
  yield root;
  for (final child in root.childElements) {
    yield* _elements(child);
  }
}

const _fixture = 'test/fixtures/fidelity/slide-arrange.pptx';

PmlPresentation _groupedDeck() {
  final deck = SlideDeserializer().readBytes(File(_fixture).readAsBytesSync());
  final shapes = deck.slides.single.shapes;
  PmlArrange.group(shapes.sublist(0, 2), allShapes: shapes);
  PmlArrange.group(shapes.sublist(2, 4), allShapes: shapes);
  return deck;
}

void _expectNativeGroups(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final root = XmlDocument.parse(
    package.getPart('/ppt/slides/slide1.xml')!.readText(),
  ).root!;
  final elements = _elements(root).toList();
  final ids = [
    for (final node in elements)
      if (node.localName == 'cNvPr' && node.namespaceUri == OfficeNamespaces.p)
        int.parse(node.getAttribute('id')!),
  ];
  expect(ids.toSet(), hasLength(ids.length), reason: 'Native IDs are unique.');
  final groups = [
    for (final node in elements)
      if (node.localName == 'grpSp' && node.namespaceUri == OfficeNamespaces.p)
        [
          for (final shape in node.childrenNamed(
            'sp',
            namespaceUri: OfficeNamespaces.p,
          ))
            shape
                .firstChild('nvSpPr', namespaceUri: OfficeNamespaces.p)!
                .firstChild('cNvPr', namespaceUri: OfficeNamespaces.p)!
                .getAttribute('name'),
        ],
  ];
  expect(groups, [
    ['Card 1', 'Card 2'],
    ['Card 3', 'Card 4'],
  ]);
  for (int index = 0; index < 5; index++) {
    final shape = elements.singleWhere(
      (node) =>
          node.localName == 'cNvPr' &&
          node.getAttribute('name') == 'Card ${index + 1}',
    );
    final transform = shape.parent!.parent!
        .firstChild('spPr', namespaceUri: OfficeNamespaces.p)!
        .firstChild('xfrm', namespaceUri: OfficeNamespaces.a)!;
    final offset = transform.firstChild(
      'off',
      namespaceUri: OfficeNamespaces.a,
    )!;
    final extent = transform.firstChild(
      'ext',
      namespaceUri: OfficeNamespaces.a,
    )!;
    expect(offset.getAttribute('x'), '${254000 + index * 1700000}');
    expect(offset.getAttribute('y'), '1000000');
    expect(extent.getAttribute('cx'), '1400000');
    expect(extent.getAttribute('cy'), '1000000');
  }
}

void main() {
  final alignmentCases = <PmlAlignAxis, List<(int, int)>>{
    PmlAlignAxis.left: [(-20, 30), (-20, -10), (-20, 70)],
    PmlAlignAxis.center: [(25, 30), (15, -10), (30, 70)],
    PmlAlignAxis.right: [(70, 30), (50, -10), (80, 70)],
    PmlAlignAxis.top: [(-20, -10), (50, -10), (10, -10)],
    PmlAlignAxis.middle: [(-20, 27), (50, 22), (10, 30)],
    PmlAlignAxis.bottom: [(-20, 65), (50, 55), (10, 70)],
  };
  for (final entry in alignmentCases.entries) {
    test(
      '${entry.key.name} aligns modeled bounds and preserves dimensions',
      () {
        final shapes = [
          _shape(2, -20, 30, 30, 20),
          _shape(3, 50, -10, 50, 30),
          _shape(4, 10, 70, 20, 15),
        ];
        PmlArrange.align(shapes, entry.key);
        expect(
          shapes.map((shape) => (shape.transform.x, shape.transform.y)),
          entry.value,
        );
        expect(shapes.map((shape) => shape.transform.cx), [30, 50, 20]);
        expect(shapes.map((shape) => shape.transform.cy), [20, 30, 15]);
        expect(
          shapes.map((shape) => shape.transform.rot),
          everyElement(1200000),
        );
      },
    );
  }

  for (final horizontal in [true, false]) {
    for (final overlap in [false, true]) {
      test(
        '${horizontal ? 'horizontal' : 'vertical'} ${overlap ? 'overlap' : 'gap'} distribution fixes both endpoints',
        () {
          final origins = overlap ? [-20, -10, 0, 10] : [-20, 0, 50, 83];
          // 67 EMUs across three gaps, or -34 across three overlaps. Each
          // cumulative position rounds once; both outer positions stay fixed.
          final expected = overlap ? [-20, -11, 2, 10] : [-20, 12, 52, 83];
          final sizes = overlap ? [20, 25, 19, 30] : [10, 17, 9, 11];
          final shapes = [
            for (int index = 0; index < 4; index++)
              _shape(
                index + 2,
                horizontal ? origins[index] : 100 + index,
                horizontal ? 100 + index : origins[index],
                horizontal ? sizes[index] : 20 + index,
                horizontal ? 20 + index : sizes[index],
              ),
          ];
          final input = [shapes[2], shapes[0], shapes[3], shapes[1]];
          final order = [...input];
          final before = _geometry(shapes);
          PmlArrange.distribute(input, horizontal: horizontal);
          expect(
            input,
            order,
            reason: 'Drawing order is independent of position.',
          );
          expect(
            shapes.map(
              (shape) => horizontal ? shape.transform.x : shape.transform.y,
            ),
            expected,
          );
          for (int index = 0; index < shapes.length; index++) {
            final transform = shapes[index].transform;
            expect(horizontal ? transform.y : transform.x, 100 + index);
            expect(transform.cx, before[index].$3);
            expect(transform.cy, before[index].$4);
            expect(transform.rot, before[index].$5);
          }
          final distributed = _geometry(shapes);
          PmlArrange.distribute(input, horizontal: horizontal);
          expect(
            _geometry(shapes),
            distributed,
            reason: 'Repeated distribution is stable.',
          );
        },
      );
    }
  }

  test(
    'insufficient selections leave original transform objects untouched',
    () {
      final shape = _shape(2, 4, 5, 6, 7);
      final transform = shape.transform;
      for (final axis in PmlAlignAxis.values) {
        PmlArrange.align([], axis);
        PmlArrange.align([shape], axis);
      }
      PmlArrange.distribute([], horizontal: true);
      PmlArrange.distribute([shape], horizontal: false);
      PmlArrange.distribute([shape, _shape(3, 8, 9, 10, 11)], horizontal: true);
      expect(shape.transform, same(transform));
    },
  );

  for (final mode in ['direct', 'isolate']) {
    test(
      '$mode flat group membership and unique native IDs survive three saves',
      () async {
        var deck = _groupedDeck();
        final output = Directory('build/fidelity-slide-arrange')
          ..createSync(recursive: true);
        File(
          '${output.path}/source.pptx',
        ).writeAsBytesSync(File(_fixture).readAsBytesSync());
        for (int cycle = 1; cycle <= 3; cycle++) {
          final bytes = mode == 'direct'
              ? SlideSerializer().writeBytes(deck)
              : await OfficeIsolateSave.presentation(deck);
          _expectNativeGroups(bytes);
          File('${output.path}/$mode-$cycle.pptx').writeAsBytesSync(bytes);
          deck = mode == 'direct'
              ? SlideDeserializer().readBytes(bytes)
              : await OfficeIsolateOpen.presentation(bytes);
          final shapes = deck.slides.single.shapes;
          expect(PmlArrange.mates(shapes, shapes[0]), shapes.sublist(0, 2));
          expect(PmlArrange.mates(shapes, shapes[2]), shapes.sublist(2, 4));
          expect(PmlArrange.mates(shapes, shapes[4]), [shapes[4]]);
        }
      },
    );
  }

  test(
    'noncontiguous membership rejects before changing imported package parts',
    () {
      final deck = SlideDeserializer().readBytes(
        SlideSerializer().writeBytes(_groupedDeck()),
      );
      final shapes = deck.slides.single.shapes;
      shapes[4].groupId = shapes[0].groupId;
      final before = {
        for (final part in deck.package!.parts) part.uri: [...part.readBytes()],
      };
      expect(() => SlideSerializer().write(deck), throwsStateError);
      expect({
        for (final part in deck.package!.parts) part.uri: [...part.readBytes()],
      }, before);
    },
  );
}
