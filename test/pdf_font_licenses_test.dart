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
    };
    expect(byFamily.keys, unorderedEquals(expectedLicenses.keys));
    for (final expected in expectedLicenses.entries) {
      expect(byFamily[expected.key]!.join('\n'), contains(expected.value));
      expect(byFamily[expected.key]!.join('\n'), contains('Copyright'));
    }
    expect(byFamily['DejaVu Sans']!.join('\n'), contains('Arev'));
  });
}
