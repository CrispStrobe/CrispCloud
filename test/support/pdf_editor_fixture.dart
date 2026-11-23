import 'dart:convert';
import 'dart:typed_data';

/// Two blank pages with a real cross-reference table, independent of the
/// editor's writer. Optional form entries exercise host compatibility gates.
/// [signed] includes a signature dictionary, not a valid signing certificate.
Uint8List buildPdfEditorFixture({
  bool xfa = false,
  bool signed = false,
  bool faxScan = false,
  int rotation = 0,
}) {
  assert(!xfa || !signed);
  assert(!faxScan || (!xfa && !signed));
  const faxPage = 'q\n300 0 0 400 0 0 cm\n/Scan Do\nQ';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R${xfa || signed ? ' /AcroForm 7 0 R' : ''} >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] '
        '/Rotate $rotation /Resources << ${faxScan ? '/XObject << /Scan 7 0 R >>' : ''} >> '
        '/Contents 5 0 R >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] '
        '/Resources << >> /Contents 6 0 R >>',
    if (faxScan)
      '<< /Length ${faxPage.length} >>\nstream\n$faxPage\nendstream'
    else
      '<< /Length 0 >>\nstream\n\nendstream',
    '<< /Length 0 >>\nstream\n\nendstream',
    if (faxScan)
      '<< /Type /XObject /Subtype /Image /Width 8 /Height 1 '
          '/ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /CCITTFaxDecode '
          '/DecodeParms << /Columns 8 /Rows 1 >> /Length 2 >>\n'
          'stream\n\x35\x14\nendstream',
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
  output.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(output.toString()));
}
