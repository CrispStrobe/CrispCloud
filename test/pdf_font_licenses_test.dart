import 'package:crisp_cloud/services/pdf_font_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  test('bundled font assets cover every family', () async {
    registerPdfFontLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final byFamily = <String, List<String>>{};
    for (final entry in entries) {
      final text = entry.paragraphs.map((p) => p.text).join('\n');
      expect(text.trim(), isNotEmpty);
      for (final family in entry.packages) {
        (byFamily[family] ??= []).add(text);
      }
    }

    const expectedLicenses = {
      'DejaVu Sans': 'Bitstream Vera',
      'DejaVu Serif': 'Bitstream Vera',
      'DejaVu Sans Mono': 'Bitstream Vera',
      'Fira Sans': 'SIL OPEN FONT LICENSE',
      'Spectral': 'SIL OPEN FONT LICENSE',
      'Lobster': 'SIL OPEN FONT LICENSE',
      'Carlito': 'SIL OPEN FONT LICENSE',
      'TeX Gyre Heros': 'LPPL Version 1.3c',
      'TeX Gyre Termes': 'LPPL Version 1.3c',
      'TeX Gyre Cursor': 'LPPL Version 1.3c',
      'TeX Gyre Adventor': 'LPPL Version 1.3c',
      'Roboto': 'Apache License',
      'Roboto Mono': 'Apache License',
      'Material Icons': 'Attribution 4.0 International',
      'Liberation Sans': 'SIL OPEN FONT LICENSE',
      'Liberation Serif': 'SIL OPEN FONT LICENSE',
      'Liberation Mono': 'SIL OPEN FONT LICENSE',
      'Noto Naskh Arabic': 'SIL OPEN FONT LICENSE',
      'Arimo': 'SIL OPEN FONT LICENSE',
      'Caladea': 'SIL OPEN FONT LICENSE',
      'Courier Prime': 'SIL OPEN FONT LICENSE',
      'Cousine': 'SIL OPEN FONT LICENSE',
      'DM Sans': 'SIL OPEN FONT LICENSE',
      'Inter': 'SIL OPEN FONT LICENSE',
      'Lato': 'SIL OPEN FONT LICENSE',
      'Noto Sans': 'SIL OPEN FONT LICENSE',
      'Open Sans': 'SIL OPEN FONT LICENSE',
      'PT Sans': 'SIL OPEN FONT LICENSE',
      'Source Serif 4': 'SIL OPEN FONT LICENSE',
      'Tinos': 'SIL OPEN FONT LICENSE',
    };
    expect(byFamily.keys, unorderedEquals(expectedLicenses.keys));
    for (final expected in expectedLicenses.entries) {
      expect(byFamily[expected.key]!.join('\n'), contains(expected.value));
      expect(byFamily[expected.key]!.join('\n'), contains('Copyright'));
    }
    expect(byFamily['DejaVu Sans']!.join('\n'), contains('Arev'));
  });
}
