// SPDX-License-Identifier: MPL-2.0

import 'package:test/test.dart';

import '../tool/compound_property_acceptance.dart';

void main() {
  for (final version4 in [false, true]) {
    for (var seed = 0; seed < 128; seed++) {
      test('generated CFB v${version4 ? 4 : 3} exact payloads seed $seed', () {
        final result = verifyCompoundGeneratedCase(seed, version4: version4);
        expect(result['streams'], version4 ? 2 : 8);
        expect(result['reads'], version4 ? 16 : 64);
        expect(result['publicEntryRejections'], version4 ? 28 : 112);
      });
    }
  }
  test('seeded CFB mutation, geometry and source-work matrix', () {
    final report = verifyCompoundPropertyAcceptance();
    expect(report['mutationCases'], 4096);
    expect(report['unexpectedFailures'], 0);
    expect(report['outsideReadAttempts'], 0);
  });
}
