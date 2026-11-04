import 'dart:convert';
import 'dart:typed_data';

/// Independent, compact two-page AcroForm fixture. The cross-reference table
/// is generated from byte offsets; no PDF writer under test creates it.
Uint8List buildPdfOperationsFixture({int pageWidth = 300, bool multiline = false}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R /AcroForm 7 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageWidth 400] '
        '/Resources << /Font << /Helv 12 0 R >> >> /Contents 5 0 R '
        '/Annots [8 0 R 9 0 R 11 0 R 15 0 R 16 0 R 17 0 R 18 0 R] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageWidth 400] '
        '/Resources << >> /Contents 6 0 R >>',
    '<< /Length 0 >>\nstream\n\nendstream',
    '<< /Length 0 >>\nstream\n\nendstream',
    '<< /Fields [8 0 R 9 0 R 10 0 R 11 0 R 17 0 R 18 0 R] '
        '/DR << /Font << /Helv 12 0 R >> >> /DA (/Helv 12 Tf 0 g) >>',
    '<< /Type /Annot /Subtype /Widget /FT /Tx /T (customer.name) '
        '${multiline ? '/Ff 4096 ' : ''}'
        '/V (Alice) /Rect [10 300 210 330] /P 3 0 R /F 4 /DA (/Helv 12 Tf 0 g) >>',
    '<< /Type /Annot /Subtype /Widget /FT /Btn /T (consent) '
        '/V /Off /AS /Off /Rect [10 260 30 280] /P 3 0 R /F 4 '
        '/AP << /N << /Yes 13 0 R /Off 14 0 R >> >> >>',
    '<< /FT /Btn /Ff 32768 /T (delivery) /V /Email /Kids [15 0 R 16 0 R] >>',
    '<< /Type /Annot /Subtype /Widget /FT /Ch /Ff 131072 /T (country) '
        '/V (DE) /Opt [(DE) (FR)] /Rect [10 150 160 180] /P 3 0 R /F 4 '
        '/DA (/Helv 12 Tf 0 g) >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Type /XObject /Subtype /Form /BBox [0 0 20 20] /Resources << >> /Length 0 >>\nstream\n\nendstream',
    '<< /Type /XObject /Subtype /Form /BBox [0 0 20 20] /Resources << >> /Length 0 >>\nstream\n\nendstream',
    '<< /Type /Annot /Subtype /Widget /Parent 10 0 R /Rect [10 220 30 240] '
        '/P 3 0 R /F 4 /AS /Email /AP << /N << /Email 13 0 R /Off 14 0 R >> >> >>',
    '<< /Type /Annot /Subtype /Widget /Parent 10 0 R /Rect [40 220 60 240] '
        '/P 3 0 R /F 4 /AS /Off /AP << /N << /Post 13 0 R /Off 14 0 R >> >> >>',
    '<< /Type /Annot /Subtype /Widget /FT /Tx /Ff 8192 /T (secret) '
        '/V (pre-existing) /Rect [10 100 160 125] /P 3 0 R /F 4 >>',
    '<< /Type /Annot /Subtype /Widget /FT /Tx /Ff 1 /T (readonly) '
        '/V (fixed) /Rect [10 60 160 85] /P 3 0 R /F 4 >>',
  ];
  final output = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[0];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(latin1.encode(output.toString()).length);
    output.writeln('${index + 1} 0 obj\n${objects[index]}\nendobj');
  }
  final xref = latin1.encode(output.toString()).length;
  output.writeln('xref\n0 ${objects.length + 1}\n0000000000 65535 f ');
  for (final offset in offsets.skip(1)) {
    output.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
  }
  output.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(output.toString()));
}
