import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The bounded Dart decoder is a source port, so its BSD license is bundled
/// explicitly rather than relying on Pub's dependency license discovery.
void registerArchiveLzfseLicense() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Apple LZFSE decoder (bounded Dart adaptation)'],
      'Adapted for CrispCloud from lzfse/lzfse at '
      'e634ca58b4821d9f3d560cdc6df5dec02ffc93fd.\n'
      'Modified: portable Dart decoding, bounded resources, exact stream and '
      'output completion, and malformed-input validation. '
      'See packages/apple_lzfse/UPSTREAM.md in the source.\n\n'
      '${await rootBundle.loadString('packages/apple_lzfse/LICENSE')}',
    );
  });
}
