@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../packages/flutter_pty2/tool/verify_mobile_assets.dart' as checks;

void main() {
  test(
    'iOS device builds emit no local PTY native asset',
    checks.verifyIosAssets,
  );
  test(
    'Android builds emit no local PTY native asset',
    checks.verifyAndroidAssets,
  );
}
