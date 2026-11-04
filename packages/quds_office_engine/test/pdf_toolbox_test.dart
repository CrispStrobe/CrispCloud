import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/pdf_file.dart';
import 'package:test/test.dart';

void main() {
  test('graft keeps an image XObject and text through extract and merge', () {
    final Uint8List bytes = _labeledImagePdf();
    final Uint8List extracted = PdfToolbox.extract(<PdfPageSource>[
      PdfPageSource(bytes),
    ]).single;
    _expectKept(extracted);

    final Uint8List merged = PdfToolbox.merge(<PdfPageSource>[
      PdfPageSource(bytes),
      PdfPageSource(bytes),
    ]);
    final PdfFile file = PdfFile.open(merged);
    expect(file.pageCount, 2);
    _expectKept(PdfToolbox.reorder(merged, <int>[1]));
  });

  test('inherited page Resources are stamped onto the grafted page', () {
    final PdfFile file = PdfFile.open(
      PdfToolbox.extract(<PdfPageSource>[
        PdfPageSource(_inheritedImagePdf()),
      ]).single,
    );
    expect(file.displayList(0).plainText, contains('KeepMe'));
    expect(
      file
          .displayList(0)
          .ops
          .whereType<PdfDrawImage>()
          .where((PdfDrawImage op) => !op.placeholder && op.bytes.isNotEmpty),
      isNotEmpty,
    );
  });

  test('one file can contribute several ranges, one PDF or one file each', () {
    final Uint8List bytes = _threePages();
    final PdfPageSource source = PdfPageSource(
      bytes,
      ranges: <String>['1', '3'],
    );
    final Uint8List one = PdfToolbox.extract(<PdfPageSource>[source]).single;
    final PdfFile joined = PdfFile.open(one);
    expect(joined.pageCount, 2);
    expect(joined.displayList(0).plainText, contains('P1'));
    expect(joined.displayList(1).plainText, contains('P3'));

    final List<Uint8List> each = PdfToolbox.extract(<PdfPageSource>[
      source,
    ], mode: PdfExtractMode.perRange);
    expect(each, hasLength(2));
    expect(PdfFile.open(each[0]).displayList(0).plainText, contains('P1'));
    expect(PdfFile.open(each[1]).displayList(0).plainText, contains('P3'));
  });

  test('rotate is a quarter-turn and does not rewrite MediaBox', () {
    final Uint8List bytes = _boxPdf(200, 400);
    final PdfFile turned = PdfFile.open(PdfToolbox.rotate(bytes, degrees: 90));
    final PdfPageInfo page = turned.pageAt(0);
    expect(page.rotate, 90);
    expect(page.mediaBox.width, 200);
    expect(page.mediaBox.height, 400);
    expect(page.width, 400);
    expect(page.height, 200);
    final ({double x, double y}) view = PdfPageView.toView(page, 10, 20);
    expect(view.x, closeTo(380, 0.01));
    expect(view.y, closeTo(10, 0.01));
    final ({double x, double y}) back = PdfPageView.fromView(
      page,
      view.x,
      view.y,
    );
    expect(back.x, closeTo(10, 0.01));
    expect(back.y, closeTo(20, 0.01));

    final PdfFile left = PdfFile.open(
      PdfToolbox.rotate(bytes, degrees: -90, ranges: <String>['1']),
    );
    expect(left.pageAt(0).rotate, 270);
    expect(left.pageAt(0).mediaBox.width, 200);
    expect(() => PdfPageView.normalizeQuarter(45), throwsArgumentError);
  });

  test('split reorder remove reverse insert and mix keep page identity', () {
    final Uint8List bytes = _threePages();
    final List<Uint8List> chunks = PdfToolbox.split(
      bytes,
      const PdfSplitSpec.every(2),
    );
    expect(chunks.map((Uint8List part) => PdfFile.open(part).pageCount), <int>[
      2,
      1,
    ]);
    expect(
      PdfFile.open(PdfToolbox.reorder(bytes, <int>[2, 0, 0])).pageCount,
      3,
    );
    final PdfFile removed = PdfFile.open(
      PdfToolbox.remove(bytes, <String>['2']),
    );
    expect(removed.pageCount, 2);
    expect(removed.displayList(0).plainText, contains('P1'));
    expect(removed.displayList(1).plainText, contains('P3'));
    expect(
      PdfFile.open(PdfToolbox.reverse(bytes)).displayList(0).plainText,
      contains('P3'),
    );
    expect(PdfFile.open(PdfToolbox.insertBlank(bytes, 1)).pageCount, 4);
    expect(PdfToolbox.resolveRange('1-2,3', 3), <int>[0, 1, 2]);

    final Uint8List mixed = PdfToolbox.mix(
      PdfPageSource(_twoPages('A')),
      PdfPageSource(_twoPages('B')),
    );
    final PdfFile mix = PdfFile.open(mixed);
    expect(mix.pageCount, 4);
    expect(mix.displayList(0).plainText, contains('A1'));
    expect(mix.displayList(1).plainText, contains('B1'));
    expect(mix.displayList(2).plainText, contains('A2'));
    expect(mix.displayList(3).plainText, contains('B2'));
  });

  test(
    'stamp and numbers paint over the page; crop does not rewrite MediaBox',
    () {
      final Uint8List bytes = _threePages();
      final PdfFile stamped = PdfFile.open(
        PdfToolbox.stamp(bytes, text: 'DRAFT', ranges: <String>['2']),
      );
      expect(stamped.displayList(0).plainText, isNot(contains('DRAFT')));
      expect(stamped.displayList(1).plainText, contains('DRAFT'));
      expect(stamped.pageAt(1).mediaBox.width, 200);

      final PdfFile numbered = PdfFile.open(
        PdfToolbox.numberPages(bytes, bates: 'QD', header: 'Brief'),
      );
      expect(numbered.displayList(0).plainText, contains('1 / 3'));
      expect(numbered.displayList(2).plainText, contains('QD-000003'));
      expect(numbered.displayList(0).plainText, contains('Brief'));
      expect(numbered.displayList(0).plainText, contains('P1'));

      final PdfFile cropped = PdfFile.open(
        PdfToolbox.crop(bytes, left: 10, bottom: 12, right: 8, top: 6),
      );
      expect(cropped.pageAt(0).mediaBox.width, 200);
      expect(cropped.pageAt(0).mediaBox.height, 400);
      expect(cropped.pageAt(0).cropBox.width, closeTo(182, 0.01));
      expect(cropped.pageAt(0).cropBox.height, closeTo(382, 0.01));
      expect(() => PdfToolbox.stamp(bytes, text: 'مسودة'), throwsArgumentError);
    },
  );
}

void _expectKept(Uint8List bytes) {
  final PdfDisplayList list = PdfFile.open(bytes).displayList(0);
  expect(list.plainText, contains('KeepMe'));
  final Iterable<PdfDrawImage> images = list.ops.whereType<PdfDrawImage>();
  expect(images, isNotEmpty);
  expect(images.every((PdfDrawImage op) => !op.placeholder), isTrue);
  expect(images.first.bytes, isNotEmpty);
}

Uint8List _labeledImagePdf() {
  const String content =
      'BT /F1 12 Tf 72 700 Td (KeepMe) Tj ET\n'
      'q 10 0 0 10 72 400 cm /Im1 Do Q\n';
  return _pdfParts(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode('2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 200 400] '
      '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> '
      '/XObject << /Im1 6 0 R >> >> >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    ),
    utf8.encode(
      '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n',
    ),
    <int>[
      ...utf8.encode(
        '6 0 obj << /Type /XObject /Subtype /Image /Width 1 /Height 1 '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Length 3 >> stream\n',
      ),
      12,
      34,
      56,
      ...utf8.encode('\nendstream\nendobj\n'),
    ],
  ]);
}

Uint8List _inheritedImagePdf() {
  const String content =
      'BT /F1 12 Tf 72 700 Td (KeepMe) Tj ET\n'
      'q 8 0 0 8 40 40 cm /Im1 Do Q\n';
  return _pdfParts(<List<int>>[
    utf8.encode('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'),
    utf8.encode(
      '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 '
      '/Resources << /Font << /F1 5 0 R >> /XObject << /Im1 6 0 R >> >> >> endobj\n',
    ),
    utf8.encode(
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 200 400] '
      '/Contents 4 0 R >> endobj\n',
    ),
    utf8.encode(
      '4 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    ),
    utf8.encode(
      '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n',
    ),
    <int>[
      ...utf8.encode(
        '6 0 obj << /Type /XObject /Subtype /Image /Width 1 /Height 1 '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Length 3 >> stream\n',
      ),
      9,
      8,
      7,
      ...utf8.encode('\nendstream\nendobj\n'),
    ],
  ]);
}

Uint8List _threePages() {
  return _pages(<String>['P1', 'P2', 'P3']);
}

Uint8List _twoPages(String prefix) {
  return _pages(<String>['${prefix}1', '${prefix}2']);
}

Uint8List _boxPdf(double width, double height) {
  return _pdfObjects(<String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height] '
        '/Resources << >> >> endobj\n',
  ]);
}

Uint8List _pages(List<String> labels) {
  final int n = labels.length;
  final int fontId = 3 + n * 2;
  final List<String> kids = <String>[
    for (int i = 0; i < n; i++) '${i + 3} 0 R',
  ];
  final List<String> objects = <String>[
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [${kids.join(' ')}] /Count $n >> endobj\n',
  ];
  final List<String> contents = <String>[];
  for (int i = 0; i < n; i++) {
    final int pageId = i + 3;
    final int contentId = 3 + n + i;
    final String content = 'BT /F1 18 Tf 72 700 Td (${labels[i]}) Tj ET\n';
    objects.add(
      '$pageId 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 200 400] '
      '/Contents $contentId 0 R /Resources << /Font << /F1 $fontId 0 R >> >> >> endobj\n',
    );
    contents.add(
      '$contentId 0 obj << /Length ${content.length} >> stream\n$content\nendstream\nendobj\n',
    );
  }
  objects
    ..addAll(contents)
    ..add(
      '$fontId 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n',
    );
  return _pdfObjects(objects);
}

Uint8List _pdfObjects(List<String> objs) {
  return _pdfParts(<List<int>>[
    for (final String obj in objs) utf8.encode(obj),
  ]);
}

Uint8List _pdfParts(List<List<int>> parts) {
  final BytesBuilder out = BytesBuilder()..add(utf8.encode('%PDF-1.7\n%\n'));
  final List<int> offsets = <int>[];
  for (final List<int> part in parts) {
    offsets.add(out.length);
    out.add(part);
  }
  final int xrefAt = out.length;
  final StringBuffer xref = StringBuffer(
    'xref\n0 ${parts.length + 1}\n0000000000 65535 f \n',
  );
  for (final int off in offsets) {
    xref.write('${off.toString().padLeft(10, '0')} 00000 n \n');
  }
  xref.write(
    'trailer\n<</Size ${parts.length + 1}/Root 1 0 R>>\nstartxref\n$xrefAt\n%%EOF\n',
  );
  out.add(utf8.encode(xref.toString()));
  return out.takeBytes();
}
