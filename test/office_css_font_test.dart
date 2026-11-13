import 'package:crisp_cloud/services/office_css_font.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes the bounded font strings emitted by legacy-doc-parser', () {
    expect(decodeOfficeCssFont(r'\41 \72 \69 \61 \6c '), 'Arial');
    expect(
      decodeOfficeCssFont(
        r'\54 \69 \6d \65 \73 \20 \4e \65 \77 \20 \52 \6f \6d \61 \6e ',
      ),
      'Times New Roman',
    );
    expect(decodeOfficeCssFont(r'\000041rial'), 'Arial');
    expect(decodeOfficeCssFont(r'\41rial'), 'Arial');
    expect(decodeOfficeCssFont('Noto Naskh Arabic'), 'Noto Naskh Arabic');
    expect(decodeOfficeCssFont(r'\1f600 Font'), '😀Font');
    expect(decodeOfficeCssFont('A\\\r\nB'), 'AB');
    expect(decodeOfficeCssFont('A\\\nB'), 'AB');
  });

  test('decoded punctuation stays literal text for TextStyle', () {
    expect(decodeOfficeCssFont(r'X\27 \3b color\3a red'), "X';color:red");
    expect(
      decodeOfficeCssFont(r'\22 url(https://example.invalid)'),
      '"url(https://example.invalid)',
    );
    expect(decodeOfficeCssFont(r'An\, odd name'), 'An, odd name');
  });

  test(
    'rejects invalid scalar values, control characters and oversized names',
    () {
      for (final value in [
        '',
        ' ',
        '\\',
        r'\0 ',
        r'\d800 ',
        r'\110000 ',
        r'\a ',
        r'\7f ',
        'A\u0001B',
        'a' * 257,
        r'\41 ' * 513,
      ]) {
        expect(decodeOfficeCssFont(value), isNull, reason: value);
      }
      expect(decodeOfficeCssFont('a' * 256), 'a' * 256);
    },
  );
}
