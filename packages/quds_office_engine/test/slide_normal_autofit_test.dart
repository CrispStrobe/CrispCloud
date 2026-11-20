import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

PmlPresentation _import({
  String body = '<a:normAutofit fontScale="80000" lnSpcReduction="20000"/>',
  String spacing = '',
  List<String> paragraphs = const ['A', 'B'],
  bool mixed = false,
}) {
  final package = OpcPackage.create(OpcPackageKind.slide);
  final content = StringBuffer();
  for (final text in paragraphs) {
    content.write('<a:p><a:pPr rtl="0">$spacing</a:pPr>');
    if (mixed) {
      content.write(
        '<a:r><a:rPr sz="2000" b="1"/><a:t>A</a:t></a:r>'
        '<a:r><a:rPr sz="2000" i="1"/><a:t>\nB</a:t></a:r>',
      );
    } else {
      content.write('<a:r><a:rPr sz="2000"/><a:t>$text</a:t></a:r>');
    }
    content.write('</a:p>');
  }
  package
      .getPart('/ppt/slides/slide1.xml')!
      .writeText(
        '<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}" '
        'xmlns:other="urn:not-drawingml"><p:cSld><p:spTree><p:sp>'
        '<p:nvSpPr><p:cNvPr id="2" name="Text"/><p:cNvSpPr/><p:nvPr/>'
        '</p:nvSpPr><p:spPr><a:xfrm><a:off x="381000" y="508000"/>'
        '<a:ext cx="3810000" cy="2540000"/></a:xfrm><a:noFill/></p:spPr>'
        '<p:txBody><a:bodyPr anchor="t">$body</a:bodyPr>$content</p:txBody>'
        '</p:sp></p:spTree></p:cSld></p:sld>',
      );
  return SlideDeserializer().read(package);
}

PmlShape _shape(PmlPresentation deck) => deck.slides.single.shapes.single;

PmlPresentation _reopen(PmlPresentation deck) =>
    SlideDeserializer().readBytes(SlideSerializer().writeBytes(deck));

String _xml(PmlPresentation deck) => OpcPackage.open(
  MemoryByteSource(SlideSerializer().writeBytes(deck)),
).getPart('/ppt/slides/slide1.xml')!.readText();

List<PdfDrawText> _text(PmlPresentation deck) => PdfFile.open(
  OfficePdfExport.presentation(deck),
).displayList(0).ops.whereType<PdfDrawText>().toList();

double _lineDistance(PmlPresentation deck) {
  final text = _text(deck);
  final first = text.firstWhere((glyph) => glyph.text.contains('A'));
  final last = text.lastWhere((glyph) => glyph.text.contains('B'));
  return (last.y - first.y).abs();
}

void main() {
  test('fresh autofit values survive shape copy and two native saves', () {
    final original = PmlShape(
      id: 2,
      name: 'Native fitted text',
      text: 'Saved',
      fontSizePt: 20,
      textScale: 0.075,
      lineSpacingReduction: 1,
    );
    var deck = PmlPresentation(
      slides: [
        PmlSlide(id: 256, shapes: [original.copy()]),
      ],
    );
    for (var i = 0; i < 2; i++) {
      deck = _reopen(deck);
      expect(_shape(deck).textScale, 0.075);
      expect(_shape(deck).lineSpacingReduction, 1);
      expect(_xml(deck), contains('fontScale="7500"'));
      expect(_xml(deck), contains('lnSpcReduction="100000"'));
    }
    expect(original.textScale, 0.075);
  });

  test(
    'modified imported values override retained source without losing text',
    () {
      var deck = _import();
      _shape(deck)
        ..text = 'Edited'
        ..textScale = 0.6
        ..lineSpacingReduction = 0.35;
      deck = PmlPresentation(slides: [deck.slides.single.copy(id: 300)]);
      for (var i = 0; i < 2; i++) {
        deck = _reopen(deck);
        expect(_shape(deck).text, 'Edited');
        expect(_shape(deck).textScale, 0.6);
        expect(_shape(deck).lineSpacingReduction, 0.35);
        expect(_xml(deck), contains('anchor="t"'));
      }
      _shape(deck)
        ..textScale = 1
        ..lineSpacingReduction = 0;
      deck = _reopen(_reopen(deck));
      expect(_shape(deck).textScale, 1);
      expect(_shape(deck).lineSpacingReduction, 0);
      expect(_xml(deck), contains('fontScale="100000"'));
      expect(_xml(deck), contains('lnSpcReduction="0"'));
    },
  );

  test('zero font scale is retained and does not paint invalid glyphs', () {
    var deck = _import(body: '<a:normAutofit fontScale="0"/>');
    expect(_shape(deck).textScale, 0);
    deck = _reopen(_reopen(deck));
    expect(_shape(deck).textScale, 0);
    expect(_text(deck), isEmpty);
  });

  test(
    'strict percent strings and explicit full reduction survive unchanged',
    () {
      var deck = _import(
        body: '<a:normAutofit fontScale="1.000%" lnSpcReduction="100%"/>',
      );
      for (var i = 0; i < 2; i++) {
        expect(_shape(deck).textScale, 0.01);
        expect(_shape(deck).lineSpacingReduction, 1);
        expect(_xml(deck), contains('fontScale="1.000%"'));
        deck = _reopen(deck);
      }
    },
  );

  for (final body in ['', '<a:noAutofit/>', '<a:spAutoFit/>']) {
    test('saving ordinary body properties preserves mode: $body', () {
      var deck = _import(body: body);
      for (var i = 0; i < 2; i++) {
        final xml = _xml(deck);
        expect(xml, isNot(contains('normAutofit')));
        if (body.isNotEmpty) expect(xml, contains(body));
        deck = _reopen(deck);
      }
    });
  }

  test('authored native values replace competing source autofit mode', () {
    var deck = _import(body: '<a:spAutoFit/><a:extLst/>');
    _shape(deck).textScale = 0.5;
    final xml = _xml(deck);
    expect(xml, isNot(contains('spAutoFit')));
    expect(xml.indexOf('normAutofit'), lessThan(xml.indexOf('extLst')));
    deck = _reopen(deck);
    expect(_shape(deck).textScale, 0.5);
  });

  test(
    'extension and foreign normal-autofit nodes cannot override the body',
    () {
      final deck = _import(
        body:
            '<other:normAutofit fontScale="1"/>'
            '<a:extLst><a:ext uri="test"><a:normAutofit fontScale="2"/>'
            '</a:ext></a:extLst>',
      );
      expect(_shape(deck).textScale, 1);
      expect(_shape(deck).lineSpacingReduction, 0);
    },
  );

  test('native autofit rejects nonfinite and out-of-range mutations', () {
    final shape = PmlShape(id: 2, name: 'Safe');
    for (final value in [-0.1, 1.1, double.nan, double.infinity]) {
      expect(() => shape.textScale = value, throwsRangeError);
      expect(() => shape.lineSpacingReduction = value, throwsRangeError);
      expect(
        () => PmlShape(id: 3, name: 'Invalid', textScale: value),
        throwsRangeError,
      );
    }
    expect(shape.textScale, 1);
    expect(shape.lineSpacingReduction, 0);
  });

  test('PDF applies font scale to fresh plain and imported rich text', () {
    final imported = _import(body: '<a:normAutofit fontScale="50000"/>');
    final fresh = PmlPresentation(
      slides: [
        PmlSlide(
          id: 256,
          shapes: [
            PmlShape(
              id: 2,
              name: 'Plain',
              text: 'A\nB',
              fontSizePt: 20,
              textScale: 0.5,
              transform: const PmlTransform(cx: 3810000, cy: 2540000),
            ),
          ],
        ),
      ],
    );
    for (final deck in [imported, fresh]) {
      expect(_text(deck), isNotEmpty);
      expect(_text(deck).map((glyph) => glyph.size), everyElement(10));
    }
  });

  for (final kind in ['paragraphs', 'multiline', 'mixed']) {
    test('PDF reduces actual $kind baselines consistently', () {
      final deck = _import(
        body: '<a:normAutofit fontScale="80000"/>',
        paragraphs: kind == 'paragraphs' ? ['A', 'B'] : ['A\nB'],
        mixed: kind == 'mixed',
      );
      final original = _lineDistance(deck);
      expect(original, greaterThan(0));
      _shape(deck).lineSpacingReduction = 0.25;
      expect(_lineDistance(deck), closeTo(original * 0.75, 0.01));
      _shape(deck).lineSpacingReduction = 1;
      expect(_lineDistance(deck), closeTo(0, 0.01));
    });
  }

  test('PDF subtracts reduction from percentage paragraph spacing', () {
    final deck = _import(
      body: '<a:normAutofit fontScale="80000"/>',
      spacing: '<a:lnSpc><a:spcPct val="150000"/></a:lnSpc>',
    );
    final original = _lineDistance(deck);
    _shape(deck).lineSpacingReduction = 0.25;
    expect(_lineDistance(deck), closeTo(original * 1.25 / 1.5, 0.01));
  });

  test('fixed point line spacing excludes reduction and survives copies', () {
    var deck = _import(spacing: '<a:lnSpc><a:spcPts val="3600"/></a:lnSpc>');
    expect(_shape(deck).richText.first.copy().lineSpacingPt, 36);
    expect(_lineDistance(deck), closeTo(36, 0.01));
    _shape(deck).lineSpacingReduction = 1;
    deck = _reopen(_reopen(deck));
    expect(_lineDistance(deck), closeTo(36, 0.01));
  });
}
