// SPDX-License-Identifier: MPL-2.0

import 'package:test/test.dart';

import '../tool/scalar_sprm_web_acceptance.dart';
import 'support/scalar_sprm_fixture.dart';

void main() {
  for (final property in scalarSprmProperties) {
    for (final scope in property.scopes) {
      for (final valid in [false, true]) {
        final values = valid ? property.validValues : property.invalidValues;
        for (final value in values) {
          test('${property.name} $scope $value valid=$valid', () {
            verifyScalarSprmCase(property, value, scope, valid: valid);
          });
        }
      }
    }
  }
  test('scalar SPRM shared gate verifies all injection paths', () {
    expect(verifyScalarSprmWebAcceptance(), {
      'operandKinds': 11,
      'invalidSourcesRejected': 136,
      'validSourcesPreserved': 220,
      'sourceBytesUnchanged': true,
      'exactXmlAndTypedValues': true,
    });
  });
}
