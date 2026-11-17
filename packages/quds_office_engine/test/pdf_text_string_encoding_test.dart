import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('PDFDocEncoding covers all 256 slots with explicit recovery', () {
    // ISO 32000-1:2008 Table D.2, with C0 controls retained for compatibility
    // and U+FFFD for the unassigned 7F, 9F and AD slots. These expectations
    // include the often-missed low accents and distinguish PDFDoc from WinAnsi.
    const expected =
        '\u0000\u0001\u0002\u0003\u0004\u0005\u0006\u0007'
        '\u0008\t\n\u000b\f\r\u000e\u000f'
        '\u0010\u0011\u0012\u0013\u0014\u0015\u0016\u0017'
        '˘ˇˆ˙˝˛˚˜'
        ' !"#\$%&\'()*+,-./0123456789:;<=>?'
        '@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_'
        '`abcdefghijklmnopqrstuvwxyz{|}~\ufffd'
        '•†‡…—–ƒ⁄‹›−‰„“”‘’‚™ﬁﬂŁŒŠŸŽıłœšž\ufffd'
        '€¡¢£¤¥¦§¨©ª«¬\ufffd®¯'
        '°±²³´µ¶·¸¹º»¼½¾¿'
        'ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏ'
        'ÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞß'
        'àáâãäåæçèéêëìíîï'
        'ðñòóôõö÷øùúûüýþÿ';
    expect(expected.length, 256);
    final decoded = PdfCosString(
      Uint8List.fromList(List<int>.generate(256, (index) => index)),
    ).asText;
    for (var byte = 0; byte < 256; byte++) {
      expect(
        decoded.codeUnitAt(byte),
        expected.codeUnitAt(byte),
        reason: 'PDFDocEncoding byte 0x${byte.toRadixString(16)}',
      );
    }
  });

  for (final vector in _vectors) {
    test('COS text strings: ${vector.name}', () {
      final bytes = Uint8List.fromList(vector.bytes);
      final before = bytes.toList();
      final string = PdfCosString(bytes);
      expect(string.asText, vector.text);
      expect(pdfCosText(string), vector.text);
      expect(bytes, before, reason: 'Decoding must not mutate the raw bytes.');
    });
  }

  for (final vector in _integrationVectors) {
    for (final hex in <bool>[false, true]) {
      for (final named in <bool>[false, true]) {
        final representation = hex ? 'hex' : 'literal';
        final owner = named ? 'named indirect' : 'inline';
        test(
          '$owner $representation ActualText and metadata: ${vector.name}',
          () {
            final encoded = hex ? _hex(vector.bytes) : _literal(vector.bytes);
            final marked = _file(encoded, named: named);
            final plain = _file(null);
            expect(marked.info.title, vector.text);
            expect(PdfExtract.pageText(marked, 0), vector.text);
            expect(_paintSignature(marked), _paintSignature(plain));
            final actualRun = marked.displayList(0).runs.single;
            final plainRun = plain.displayList(0).runs.single;
            expect(
              (actualRun.x, actualRun.y, actualRun.width, actualRun.height),
              (plainRun.x, plainRun.y, plainRun.width, plainRun.height),
            );
          },
        );
      }
    }
  }

  test('metadata decoding does not reinterpret font-encoded showing bytes', () {
    final plain = _file(null, showing: r'(\200\223\240)');
    final marked = _file(r'(\200\223\240)', showing: r'(\200\223\240)');
    expect(marked.info.title, '•ﬁ€');
    expect(PdfExtract.pageText(marked, 0), '•ﬁ€');
    expect(_paintSignature(marked), _paintSignature(plain));
    expect(
      plain
          .displayList(0)
          .ops
          .whereType<PdfDrawText>()
          .map((op) => op.text)
          .join(),
      isNot('•ﬁ€'),
    );
  });

  test('each marked span chooses its own encoding within one PDF', () {
    final file = _document('''
BT /F1 12 Tf 1 0 0 1 30 100 Tm
/Span << /ActualText <80A0> >> BDC (a) Tj EMC
/Span << /ActualText <FEFF0627D83DDE00> >> BDC (b) Tj EMC
/Span << /ActualText <EFBBBFC3A9F09F9880> >> BDC (c) Tj EMC
ET
''');
    expect(PdfExtract.pageText(file, 0), '•€ا😀é😀');
    expect(
      file
          .displayList(0)
          .ops
          .whereType<PdfDrawText>()
          .map((op) => op.text)
          .join(),
      'abc',
    );
  });
}

typedef _Vector = ({String name, List<int> bytes, String text});

const _vectors = <_Vector>[
  (name: 'empty', bytes: <int>[], text: ''),
  (
    name: 'ASCII with whitespace',
    bytes: <int>[65, 9, 10, 13, 90],
    text: 'A\t\n\rZ',
  ),
  (
    name: 'low accents',
    bytes: <int>[24, 25, 26, 27, 28, 29, 30, 31],
    text: '˘ˇˆ˙˝˛˚˜',
  ),
  (
    name: 'typography',
    bytes: <int>[0x80, 0x8a, 0x8d, 0x8e, 0x93, 0x94, 0xa0],
    text: '•−“”ﬁﬂ€',
  ),
  (
    name: 'unassigned slots',
    bytes: <int>[0x7f, 0x9f, 0xad],
    text: '\ufffd\ufffd\ufffd',
  ),
  (name: 'UTF16 empty', bytes: <int>[0xfe, 0xff], text: ''),
  (
    name: 'UTF16 BMP and supplementary',
    bytes: <int>[
      0xfe,
      0xff,
      0,
      65,
      6,
      0x27,
      0xd8,
      0x3d,
      0xde,
      0,
      0xd8,
      0,
      0xdc,
      0,
    ],
    text: 'Aا😀\u{10000}',
  ),
  (
    name: 'UTF16 largest scalar',
    bytes: <int>[0xfe, 0xff, 0xdb, 0xff, 0xdf, 0xff],
    text: '\u{10ffff}',
  ),
  (
    name: 'UTF16 isolated high surrogate',
    bytes: <int>[0xfe, 0xff, 0xd8, 0, 0, 65],
    text: '\ufffdA',
  ),
  (
    name: 'UTF16 isolated low surrogate',
    bytes: <int>[0xfe, 0xff, 0xdc, 0, 0, 65],
    text: '\ufffdA',
  ),
  (
    name: 'UTF16 high followed by valid pair',
    bytes: <int>[0xfe, 0xff, 0xd8, 0, 0xd8, 0x3d, 0xde, 0],
    text: '\ufffd😀',
  ),
  (
    name: 'UTF16 odd trailing byte',
    bytes: <int>[0xfe, 0xff, 0, 65, 0],
    text: 'A\ufffd',
  ),
  (
    name: 'UTF16 isolated surrogate and trailing byte',
    bytes: <int>[0xfe, 0xff, 0xd8, 0, 0x41],
    text: '\ufffd\ufffd',
  ),
  (
    name: 'UTF16 content BOM and NUL',
    bytes: <int>[0xfe, 0xff, 0xfe, 0xff, 0, 0, 0, 65],
    text: '\ufeff\u0000A',
  ),
  (name: 'UTF8 empty', bytes: <int>[0xef, 0xbb, 0xbf], text: ''),
  (
    name: 'UTF8 BMP and supplementary',
    bytes: <int>[
      0xef,
      0xbb,
      0xbf,
      65,
      0xc3,
      0xa9,
      0xd8,
      0xa7,
      0xf0,
      0x9f,
      0x98,
      0x80,
    ],
    text: 'Aéا😀',
  ),
  (
    name: 'UTF8 largest scalar',
    bytes: <int>[0xef, 0xbb, 0xbf, 0xf4, 0x8f, 0xbf, 0xbf],
    text: '\u{10ffff}',
  ),
  (
    name: 'UTF8 malformed continuation',
    bytes: <int>[0xef, 0xbb, 0xbf, 0xe2, 0x28, 0xa1, 65],
    text: '\ufffd(\ufffdA',
  ),
  (
    name: 'UTF8 truncated sequence',
    bytes: <int>[0xef, 0xbb, 0xbf, 65, 0xf0, 0x9f],
    text: 'A\ufffd',
  ),
  (
    name: 'UTF8 content BOM and NUL',
    bytes: <int>[0xef, 0xbb, 0xbf, 0xef, 0xbb, 0xbf, 0, 65],
    text: '\ufeff\u0000A',
  ),
  (name: 'no UTF8 detection without BOM', bytes: <int>[0xc3, 0xa9], text: 'Ã©'),
  (name: 'partial UTF16 BOM', bytes: <int>[0xfe], text: 'þ'),
  (name: 'partial UTF8 BOM', bytes: <int>[0xef, 0xbb], text: 'ï»'),
  (
    name: 'UTF16LE is not a PDF Unicode text encoding',
    bytes: <int>[0xff, 0xfe, 65, 0],
    text: 'ÿþA\u0000',
  ),
];

final _integrationVectors = _vectors.where(
  (vector) => <String>{
    'low accents',
    'typography',
    'unassigned slots',
    'UTF16 BMP and supplementary',
    'UTF16 isolated high surrogate',
    'UTF16 odd trailing byte',
    'UTF8 BMP and supplementary',
    'UTF8 malformed continuation',
  }.contains(vector.name),
);

String _hex(List<int> bytes) =>
    '<${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}>';

String _literal(List<int> bytes) =>
    '(${bytes.map((byte) => '\\${byte.toRadixString(8).padLeft(3, '0')}').join()})';

List<(String, double, double, double, double)> _paintSignature(PdfFile file) =>
    file.displayList(0).ops.whereType<PdfDrawText>().map((op) {
      return (op.text, op.x, op.y, op.size, op.angle);
    }).toList();

PdfFile _file(String? encoded, {bool named = false, String showing = '(abc)'}) {
  final marker = encoded == null
      ? ''
      : '/Span ${named ? '/Named' : '<< /ActualText $encoded >>'} BDC';
  return _document(
    'BT /F1 12 Tf 1 0 0 1 30 100 Tm $marker $showing Tj '
    '${encoded == null ? '' : 'EMC'} ET',
    properties: named ? '/Named 6 0 R' : '',
    extraObjects: <String>[
      '<< /ActualText ${encoded ?? '()'} >>',
      '<< /Title ${encoded ?? '()'} >>',
    ],
    trailer: '/Info 7 0 R',
  );
}

PdfFile _document(
  String content, {
  String properties = '',
  String trailer = '',
  List<String> extraObjects = const <String>[],
}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> '
        '/Properties << $properties >> >> >>',
    '<< /Length ${latin1.encode(content).length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding >>',
    ...extraObjects,
  ];
  final out = BytesBuilder()..add(ascii.encode('%PDF-2.0\n'));
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
    'trailer\n<< /Size ${offsets.length} /Root 1 0 R $trailer >>\n'
    'startxref\n$xrefAt\n%%EOF\n',
  );
  out.add(ascii.encode(xref.toString()));
  return PdfFile.open(out.takeBytes());
}
