import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerCatalogueLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Crisp catalogue native engine and dependencies'],
      await rootBundle.loadString(
        'packages/crisp_catalog/THIRD_PARTY_NOTICES.txt',
      ),
    );
  });
}
