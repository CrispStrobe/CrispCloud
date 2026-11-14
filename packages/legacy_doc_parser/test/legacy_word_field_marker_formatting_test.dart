// SPDX-License-Identifier: MPL-2.0

import 'package:test/test.dart';
import '../tool/field_marker_formatting_web_acceptance.dart';

void main() {
  for (final compressed in [true, false]) {
    for (var mask = 0; mask < 8; mask++) {
      for (final resultMask in [0, 1, 3]) {
        for (final instructionHidden in [true, false]) {
          test(
            'field marker mask $mask result mask $resultMask compressed $compressed instruction $instructionHidden',
            () {
              verifyFieldMarkerFormattingCase(
                mask,
                resultMask,
                compressed,
                instructionHidden,
              );
            },
          );
        }
      }
    }
  }
}
