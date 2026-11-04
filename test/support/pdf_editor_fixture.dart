import 'dart:convert';
import 'dart:typed_data';

/// Two blank pages with a real cross-reference table, independent of the
/// editor's writer. Optional form entries exercise host compatibility gates.
/// [signed] includes a signature dictionary, not a valid signing certificate.
Uint8List buildPdfEditorFixture({bool xfa = false, bool signed = false}) {
  assert(!xfa || !signed);
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R${xfa || signed ? ' /AcroForm 7 0 R' : ''} >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] '
        '/Resources << >> /Contents 5 0 R >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] '
        '/Resources << >> /Contents 6 0 R >>',
    '<< /Length 0 >>\nstream\n\nendstream',
    '<< /Length 0 >>\nstream\n\nendstream',
    if (xfa) ...[
      '<< /Fields [] /XFA 8 0 R >>',
      '<< /Length 6 >>\nstream\n<xfa/>\nendstream',
    ],
    if (signed) ...[
      '<< /Fields [8 0 R] >>',
      '<< /FT /Sig /T (Existing signature) /V 9 0 R >>',
      '<< /Type /Sig /Filter /Adobe.PPKLite '
          '/SubFilter /adbe.pkcs7.detached /ByteRange [0 0 0 0] /Contents <00> >>',
    ],
  ];
  final output = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[0];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(output.length);
    output.writeln('${index + 1} 0 obj\n${objects[index]}\nendobj');
  }
  final xref = output.length;
  output.writeln('xref\n0 ${objects.length + 1}\n0000000000 65535 f ');
  for (final offset in offsets.skip(1)) {
    output.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
  }
  output.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(output.toString()));
}
