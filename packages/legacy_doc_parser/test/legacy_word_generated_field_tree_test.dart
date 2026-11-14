// SPDX-License-Identifier: MPL-2.0

import 'package:test/test.dart';

import '../tool/generated_field_tree_web_acceptance.dart';

void main() {
  for (var seed = 1; seed <= 96; seed++) {
    test(
      'ASCII generated field tree $seed isolates native field semantics',
      () {
        expect(verifyGeneratedFieldTreeCase(seed, ascii: true)['layouts'], 2);
      },
    );
    test(
      'generated field tree $seed preserves source, result and DOCX text',
      () {
        expect(verifyGeneratedFieldTreeCase(seed)['layouts'], 2);
      },
    );
  }
}
