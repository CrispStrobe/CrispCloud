// SPDX-License-Identifier: MPL-2.0
import 'package:test/test.dart';
import '../tool/field_instruction_visibility_web_acceptance.dart';
import 'support/field_marker_formatting_fixture.dart';

void main() {
  for (final fixture in fieldInstructionFormattingCases()) {
    test(
      'exact instruction visibility ${fixture.name}',
      () => verifyFieldInstructionVisibilityCase(fixture),
    );
  }
  test(
    'public instruction visibility is immutable and validated in both modes',
    () {
      expect(verifyPublicFieldInstructionVisibility(), 21);
    },
  );
}
