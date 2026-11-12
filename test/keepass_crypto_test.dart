import 'package:flutter_test/flutter_test.dart';

import '../tool/verify_keepass_crypto.dart';

void main() {
  test('KeePass Argon2 adapter matches the upstream known answer', () {
    verifyKeePassArgon2();
  });
}
