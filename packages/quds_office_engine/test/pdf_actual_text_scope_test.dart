import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('final text operator does not require trailing whitespace', () {
    final file = _file('BT /F1 12 Tf (x) Tj ET', trailingNewline: false);
    expect(PdfExtract.pageText(file, 0), 'x');
  });

  test('nested ordinary marks share one ActualText replacement', () {
    final file = _file('''
BT /F1 12 Tf 1 0 0 1 30 100 Tm
/Span << /ActualText (source) >> BDC
(a) Tj /Artifact BMC (b) Tj EMC (c) Tj
EMC (z) Tj ET
''');
    expect(PdfExtract.pageText(file, 0), 'sourcez');
    expect(_painted(file), 'abcz');
  });

  test('replacement first emitted in nested marks stays consumed', () {
    final file = _file('''
BT /F1 12 Tf 1 0 0 1 30 100 Tm
/Span << /ActualText (source) >> BDC
/Span << /Lang (en) >> BDC /Artifact BMC (a) Tj EMC EMC
(b) Tj EMC (z) Tj ET
''');
    expect(PdfExtract.pageText(file, 0), 'sourcez');
    expect(_painted(file), 'abz');
  });

  test('outer ActualText owns its complete nested replacement', () {
    final file = _file('''
BT /F1 12 Tf 1 0 0 1 30 100 Tm
/Span << /ActualText (outer) >> BDC
(a) Tj /Span << /ActualText (inner) >> BDC (b) Tj EMC
(c) Tj EMC (z) Tj ET
''');
    expect(PdfExtract.pageText(file, 0), 'outerz');
    expect(_painted(file), 'abcz');
  });

  test('empty outer replacement suppresses nested replacement text', () {
    final file = _file('''
BT /F1 12 Tf 1 0 0 1 30 100 Tm
/Span << /ActualText () >> BDC
(a) Tj /Span << /ActualText (inner) >> BDC (b) Tj EMC
(c) Tj EMC (z) Tj ET
''');
    expect(PdfExtract.pageText(file, 0), 'z');
    expect(_painted(file), 'abcz');
  });

  test('adjacent identical replacements each emit once', () {
    final file = _file('''
BT /F1 12 Tf 1 0 0 1 30 100 Tm
/Span << /ActualText (same) >> BDC (a) Tj (b) Tj EMC
/Span << /ActualText (same) >> BDC (c) Tj (d) Tj EMC
(z) Tj ET
''');
    expect(PdfExtract.pageText(file, 0), 'samesamez');
    expect(_painted(file), 'abcdz');
  });

  test('named indirect property lists retain replacement text', () {
    final file = _file(
      'BT /F1 12 Tf /Span /Named BDC (xx) Tj EMC ET',
      properties: '/Named 6 0 R',
      extraObjects: <String>['<< /ActualText (indirect) >>'],
    );
    expect(PdfExtract.pageText(file, 0), 'indirect');
    expect(_painted(file), 'xx');
  });

  test('UTF-16 literal and hex strings carry the same source text', () {
    final literal = _file(
      r'BT /F1 12 Tf /Span << /ActualText (\376\377\000A\330\075\336\000) >> BDC (x) Tj EMC ET',
    );
    final hex = _file(
      'BT /F1 12 Tf /Span << /ActualText <FEFF0041D83DDE00> >> BDC (x) Tj EMC ET',
    );
    expect(PdfExtract.pageText(literal, 0), 'A😀');
    expect(PdfExtract.pageText(hex, 0), 'A😀');
  });

  test('hidden first showing does not consume or enlarge a replacement', () {
    final file = _file(
      '''
BT /F1 12 Tf
/Span << /ActualText (visible source) >> BDC
/OC /Hidden BDC 1 0 0 1 5 200 Tm (hidden) Tj EMC
1 0 0 1 100 100 Tm (visible) Tj EMC ET
''',
      properties: '/Hidden 6 0 R',
      catalog: '/OCProperties << /OCGs [6 0 R] /D << /OFF [6 0 R] >> >>',
      extraObjects: <String>['<< /Type /OCG /Name (Hidden) >>'],
    );
    expect(PdfExtract.pageText(file, 0), 'visible source');
    expect(_painted(file), 'visible');
    expect(file.displayList(0).runs.single.x, 100);
  });

  test('replacement bounds include all showing operators and TJ gaps', () {
    const body = '''
BT /F1 12 Tf 1 0 0 1 10 100 Tm
[(a) -500 (b)] TJ 1 0 0 1 80 100 Tm (c) Tj ET
''';
    final plain = _file(body).displayList(0).runs;
    final file = _file('/Span << /ActualText (source) >> BDC $body EMC');
    final run = file.displayList(0).runs.single;
    final left = plain.map((run) => run.x).reduce(math.min);
    final right = plain.map((run) => run.x + run.width).reduce(math.max);
    expect(run.text, 'source');
    expect(run.x, left);
    expect(run.width, closeTo(right - left, 0.0001));
    expect(
      run.contains(plain.last.x + plain.last.width / 2, run.y + 1),
      isTrue,
    );
  });

  test(
    'replacement geometry accumulates across baselines and nested marks',
    () {
      final file = _file('''
BT /F1 12 Tf /Span << /ActualText (two lines) >> BDC
1 0 0 1 30 150 Tm (a) Tj
/Artifact BMC 1 0 0 1 60 100 Tm (b) Tj EMC
EMC ET
''');
      final run = file.displayList(0).runs.single;
      expect(run.text, 'two lines');
      expect(run.x, 30);
      expect(run.y, 138);
      expect(run.height, 62);
      expect(run.width, greaterThan(30));
    },
  );

  test('generic rotated ActualText never changes painted glyphs', () {
    const body = 'BT /F1 12 Tf 0 1 -1 0 80 100 Tm (a) Tj (b) Tj ET';
    final plain = _file(body);
    final marked = _file('/Span << /ActualText (source) >> BDC $body EMC');
    expect(PdfExtract.pageText(marked, 0), 'source');
    expect(_painted(marked), 'ab');
    expect(_paintSignature(marked), _paintSignature(plain));
    final run = marked.displayList(0).runs.single;
    expect(run.width, closeTo(12, 0.0001));
    expect(run.height, greaterThan(12));
  });

  test('empty rotated replacement suppresses extraction only', () {
    final file = _file('''
/Span << /ActualText () >> BDC
BT /F1 12 Tf 0 1 -1 0 80 100 Tm (a) Tj (b) Tj ET
EMC
''');
    expect(PdfExtract.pageText(file, 0), isEmpty);
    expect(_painted(file), 'ab');
  });

  test('invisible text still contributes source and span bounds', () {
    final file = _file('''
BT /F1 12 Tf 1 0 0 1 10 100 Tm
/Span << /ActualText (source) >> BDC
3 Tr (a) Tj 1 0 0 1 70 100 Tm (b) Tj EMC ET
''');
    expect(PdfExtract.pageText(file, 0), 'source');
    expect(_painted(file), isEmpty);
    expect(file.displayList(0).runs.single.width, greaterThan(60));
  });

  test('empty showing retains source without losing later span bounds', () {
    final file = _file('''
BT /F1 12 Tf 1 0 0 1 10 100 Tm
/Span << /ActualText (source) >> BDC
() Tj 1 0 0 1 60 100 Tm (x) Tj EMC ET
''');
    expect(PdfExtract.pageText(file, 0), 'source');
    expect(_painted(file), 'x');
    expect(file.displayList(0).runs.single.width, greaterThan(50));
  });

  test('explicit marked-line writer keeps logical watermark painting', () {
    final canvas = PdfCanvas(300, 300)
      ..rotateAround(150, 150, -45)
      ..showMarkedLine(
        x: 50,
        y: 150,
        fontSize: 20,
        logical: 'ملاحظة',
        visual: ' ',
        color: '000000',
        fontName: 'F2',
      );
    final doc = PdfDocument()
      ..addPage(PdfPage(width: 300, height: 300, content: canvas.toStream()));
    final file = PdfFile.open(doc.save());
    expect(PdfExtract.pageText(file, 0), 'ملاحظة');
    expect(_painted(file), 'ملاحظة');
    expect(file.displayList(0).ops.whereType<PdfDrawText>(), hasLength(1));
  });
}

String _painted(PdfFile file) => file
    .displayList(0)
    .ops
    .whereType<PdfDrawText>()
    .map((op) => op.text)
    .join();

List<(String, double, double, double, double)> _paintSignature(PdfFile file) =>
    file.displayList(0).ops.whereType<PdfDrawText>().map((op) {
      return (op.text, op.x, op.y, op.size, op.angle);
    }).toList();

PdfFile _file(
  String content, {
  String properties = '',
  String catalog = '',
  List<String> extraObjects = const <String>[],
  bool trailingNewline = true,
}) {
  if (trailingNewline) content = '$content\n';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R $catalog >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> '
        '/Properties << $properties >> >> >>',
    '<< /Length ${latin1.encode(content).length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ...extraObjects,
  ];
  final out = BytesBuilder()..add(ascii.encode('%PDF-1.7\n'));
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.add(latin1.encode('${i + 1} 0 obj\n${objects[i]}\nendobj\n'));
  }
  final xrefAt = out.length;
  final xref = StringBuffer('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    xref.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
  }
  xref.write(
    'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\n'
    'startxref\n$xrefAt\n%%EOF\n',
  );
  out.add(ascii.encode(xref.toString()));
  return PdfFile.open(out.takeBytes());
}
