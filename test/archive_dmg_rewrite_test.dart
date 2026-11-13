import 'package:flutter_test/flutter_test.dart';

import 'support/dmg_rewrite_checks.dart';

void main() {
  for (final check in dmgRewriteChecks().entries) {
    test(check.key, check.value, timeout: const Timeout(Duration(minutes: 5)));
  }
}
