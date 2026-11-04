import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OmmlFrac? _firstFrac(OmmlNode node) {
  switch (node) {
    case OmmlFrac():
      return node;
    case OmmlSeq():
      for (final OmmlNode child in node.children) {
        final OmmlFrac? found = _firstFrac(child);
        if (found != null) {
          return found;
        }
      }
      return null;
    case OmmlDelim():
      return _firstFrac(node.e);
    case OmmlRad():
      return _firstFrac(node.e);
    default:
      return null;
  }
}

void main() {
  test('UnicodeMath parses quadratic and pythagorean gallery items', () {
    final OmmlSeq quad = OmmlLinear.parse('x=(-b±√(b^2-4ac))/2a');
    expect(OmmlLinear.write(quad), contains('/'));
    expect(OmmlEdit.slots(quad), isNotEmpty);
    final OmmlFrac? frac = _firstFrac(quad);
    expect(frac, isNotNull);
    expect(OmmlLinear.write(frac!.den), contains('2'));
    expect(OmmlLinear.write(frac.den), contains('a'));
    expect(OmmlLinear.write(frac.num), isNot(contains('2a')));

    final OmmlEquation pyth = OmmlGallery.byId('pythagorean').build();
    expect(OmmlLinear.write(pyth.root), contains('a'));
    expect(OmmlLinear.write(pyth.root), contains('^'));
  });

  test('professional layout sizes stacked fractions and integrals', () {
    final OmmlEquation frac = OmmlEquation(root: OmmlLinear.parse('(a+b)/c'));
    final LaidOutOmml stacked = OmmlLayout.layout(frac, fontSize: 16);
    expect(stacked.width, greaterThan(20));
    expect(stacked.height, greaterThan(20));
    expect(stacked.items.whereType<LaidOutOmmlRule>(), isNotEmpty);

    final OmmlEquation integral = OmmlGallery.byId('integral').build();
    final LaidOutOmml box = OmmlLayout.layout(integral, fontSize: 16);
    expect(box.width, greaterThan(40));
    expect(box.items.whereType<LaidOutOmmlText>(), isNotEmpty);
  });

  test('quadratic layout keeps the bar off the equals and 2a in the den', () {
    final OmmlEquation equation = OmmlGallery.byId('quadratic').build();
    final OmmlFrac? frac = _firstFrac(equation.root);
    expect(frac, isNotNull);
    expect(
      OmmlLinear.write(frac!.den).replaceAll('(', '').replaceAll(')', ''),
      '2a',
    );

    final LaidOutOmml box = OmmlLayout.layout(equation, fontSize: 16);
    final Iterable<LaidOutOmmlText> texts = box.items
        .whereType<LaidOutOmmlText>();
    final LaidOutOmmlText eq = texts.firstWhere(
      (LaidOutOmmlText t) => t.text == '=',
    );
    final LaidOutOmmlRule bar = box.items.whereType<LaidOutOmmlRule>().first;
    expect(bar.x, greaterThan(eq.x + eq.width - 0.5));
    expect(OmmlEdit.cells(equation.root).length, greaterThan(3));
  });

  test('reading cells expose owned characters for caret movement', () {
    final OmmlSeq root = OmmlGallery.byId('quadratic').build().root;
    final OmmlSeq den = OmmlEdit.cells(root).firstWhere((OmmlSeq cell) {
      final String plain = OmmlEdit.cellPlain(root, cell);
      return plain.contains('2') && plain.contains('a');
    });
    final List<OmmlSeq> order = OmmlEdit.readingCells(root);
    expect(order.length, greaterThan(2));
    final int denSlot = OmmlEdit.slotIndexOf(root, den);
    final int prev = OmmlEdit.stepReading(root, denSlot, -1);
    expect(prev, isNot(denSlot));
    OmmlEdit.insertAt(root, den, 1, 'x');
    expect(OmmlEdit.cellPlain(root, den), contains('x'));
  });

  test('empty structures have no user text and start at the first cell', () {
    final OmmlEquation empty = OmmlEquation.empty();
    expect(OmmlEdit.hasUserText(empty.root), isFalse);
    expect(OmmlEdit.isFirstReadingCell(empty.root, 0), isTrue);

    OmmlEdit.applyStructure(empty.root, OmmlStructure.fractionBar);
    OmmlEdit.applyStructure(
      (empty.root.children.single as OmmlFrac).num,
      OmmlStructure.squareRoot,
    );
    expect(OmmlEdit.hasUserText(empty.root), isFalse);
    expect(OmmlEdit.isFirstReadingCell(empty.root, 0), isTrue);

    final OmmlSeq first = OmmlEdit.readingCells(empty.root).first;
    OmmlEdit.insertText(first, 'x');
    expect(OmmlEdit.hasUserText(empty.root), isTrue);
  });

  test('structure insert wraps the current slot', () {
    final OmmlEquation eq = OmmlEquation.empty();
    OmmlEdit.insertText(eq.root, 'x');
    OmmlEdit.applyStructure(eq.root, OmmlStructure.fractionBar);
    expect(eq.root.children.single, isA<OmmlFrac>());
    final OmmlFrac frac = eq.root.children.single as OmmlFrac;
    expect(OmmlLinear.write(frac.num), 'x');
    expect(frac.den.isEmpty, isTrue);
  });

  test('OMML round-trips through Word serializer', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Before')]),
            WmlEquation(math: OmmlGallery.byId('quadratic').build()),
          ],
        ),
      ],
    );
    final WordSerializer serializer = WordSerializer();
    final WordDeserializer deserializer = WordDeserializer();
    final WmlDocument copy = deserializer.read(serializer.write(doc));
    expect(copy.equations, isNotEmpty);
    final String linear = OmmlLinear.write(copy.equations.first.math.root);
    expect(linear, contains('x'));
    expect(linear.contains('/') || linear.contains('√'), isTrue);
    final OmmlFrac? frac = _firstFrac(copy.equations.first.math.root);
    expect(frac, isNotNull);
    expect(OmmlLinear.write(frac!.den), contains('a'));
    expect(OmmlEdit.cells(copy.equations.first.math.root), isNotEmpty);
  });

  test('Word layout emits an equation frame', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlEquation(math: OmmlGallery.byId('circle-area').build()),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages, isNotEmpty);
    expect(
      laid.pages.first.frames.any(
        (LaidOutBox b) => b.kind == LaidOutBoxKind.equation && b.omml != null,
      ),
      isTrue,
    );
  });
}
