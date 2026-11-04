import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _fontLicenseDirectory = 'assets/licenses/pdf_fonts';

const _bundledFontFamilies = [
  'DejaVu Sans',
  'DejaVu Serif',
  'DejaVu Sans Mono',
  'Fira Sans',
  'Spectral',
  'Lobster',
  'Carlito',
  'TeX Gyre Heros',
  'TeX Gyre Termes',
  'TeX Gyre Cursor',
  'TeX Gyre Adventor',
  'Roboto',
  'Roboto Mono',
  'Material Icons',
];

class _FontNotice {
  const _FontNotice(this.families, this.assets);

  final List<String> families;
  final List<String> assets;
}

const _fontNotices = [
  _FontNotice(_bundledFontFamilies, [
    '$_fontLicenseDirectory/FONT-COPYRIGHTS.txt',
    '$_fontLicenseDirectory/README.md',
  ]),
  _FontNotice(['DejaVu Sans'], [
    '$_fontLicenseDirectory/DejaVuSans-font-metadata-LICENSE.txt',
  ]),
  _FontNotice(['DejaVu Serif'], [
    '$_fontLicenseDirectory/DejaVuSerif-font-metadata-LICENSE.txt',
  ]),
  _FontNotice(['DejaVu Sans Mono'], [
    '$_fontLicenseDirectory/DejaVuSansMono-font-metadata-LICENSE.txt',
  ]),
  _FontNotice(['Fira Sans'], ['$_fontLicenseDirectory/FiraSans-LICENSE.txt']),
  _FontNotice(['Spectral'], ['$_fontLicenseDirectory/Spectral-LICENSE.txt']),
  _FontNotice(['Lobster'], ['$_fontLicenseDirectory/Lobster-LICENSE.txt']),
  _FontNotice(['Carlito'], ['$_fontLicenseDirectory/Carlito-LICENSE.txt']),
  _FontNotice(
    [
      'TeX Gyre Heros',
      'TeX Gyre Termes',
      'TeX Gyre Cursor',
      'TeX Gyre Adventor',
    ],
    [
      '$_fontLicenseDirectory/TeXGyre-LICENSE.txt',
      '$_fontLicenseDirectory/LPPL-1.3c.txt',
    ],
  ),
  _FontNotice(['Roboto'], ['assets/fonts/Roboto_LICENSE.txt']),
  _FontNotice(['Roboto Mono'], ['assets/fonts/RobotoMono_LICENSE.txt']),
  _FontNotice(['Material Icons'], ['assets/fonts/MaterialIcons_LICENSE.txt']),
];

/// Makes the bundled fonts' separate notices available in the existing
/// application license page. Text is loaded only when licenses are requested.
void registerPdfFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final notice in _fontNotices) {
      final texts = <String>[];
      for (final asset in notice.assets) {
        texts.add(await rootBundle.loadString(asset));
      }
      yield LicenseEntryWithLineBreaks(notice.families, texts.join('\n\n'));
    }
  });
}
