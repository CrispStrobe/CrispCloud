// SPDX-License-Identifier: MPL-2.0

import 'package:test/test.dart';

import '../tool/field_visibility_web_acceptance.dart';
import 'support/field_visibility_fixture.dart';

void main() {
  for (final name in fieldVisibilityCases) {
    test('shared field visibility gate $name', () {
      final result = verifyFieldVisibilityCase(name);
      expect(result['visibleText'], fieldVisibilityExpectedText[name]);
    });
  }
}
