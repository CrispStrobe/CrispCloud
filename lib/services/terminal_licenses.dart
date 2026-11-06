import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Package LICENSE files are collected by Flutter. Preserve the separate BSD
/// notice required by the Dart API sources embedded in flutter_pty2 as well.
void registerTerminalLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Dart native API (flutter_pty2)'],
      await rootBundle.loadString(
        'assets/licenses/terminal/DART_BSD_LICENSE.txt',
      ),
    );
  });
}
