import 'package:flutter_test/flutter_test.dart';

import 'support/archive_zip_recovery_web_acceptance.dart' as acceptance;

void main() {
  test(
    'independent Python ZIP streams, immutable selection and bounded output',
    () => acceptance.main(const []),
  );
}
