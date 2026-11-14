// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import '../tool/display_field_evidence_web_acceptance.dart';
import 'support/display_field_evidence_fixture.dart';

void main() {
  for (final name in displayFieldEvidenceCases) {
    for (final raw in [false, true]) {
      for (final mode in LegacyWordFieldMode.values) {
        test(
          '$name $mode sourceRecord=$raw retains complete revision evidence',
          () {
            verifyDisplayFieldEvidenceCase(name, sourceRecord: raw, mode: mode);
          },
        );
      }
    }
  }
  test(
    'display history shared gate includes unchanged no-history controls',
    () {
      expect(verifyDisplayFieldEvidenceWebAcceptance(), {
        'cases': 44,
        'nativeHistoryCases': 6,
        'inertHistoryCases': 38,
        'noHistoryControls': 2,
        'completeMetadata': true,
        'originalRecordsExact': true,
      });
    },
  );
}
