import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerMeshPreviewLicense() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Brickwright CAD STL reader (Dart adaptation)',
    ], await rootBundle.loadString('assets/licenses/brickwright/LICENSE.txt'));
  });
}
