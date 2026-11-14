// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:test/test.dart';

import 'support/compound_root_fixture.dart';

void main() {
  final rejected = throwsA(anyOf(isA<CfbfException>(), isA<FormatException>()));
  for (final version4 in [false, true]) {
    for (final mutation in compoundInvalidRoots) {
      test('raw root identity v4=$version4 $mutation', () {
        final bytes = compoundRootFixture(mutation, version4: version4);
        expect(() => CfbfFile.fromBytes(bytes), rejected);
      });
      test('bounded root identity v4=$version4 $mutation', () {
        final bytes = compoundRootFixture(mutation, version4: version4);
        expect(() => BoundedCfbReader(bytes), rejected);
      });
    }
  }
  test('an empty container retains its actual root', () {
    final bytes = CfbfWriter().build();
    final raw = CfbfFile.fromBytes(bytes);
    final bounded = BoundedCfbReader(bytes);
    expect(raw.root.index, 0);
    expect(bounded.root.index, 0);
    expect(raw.childrenOf(raw.root), isEmpty);
    expect(bounded.childrenOf(bounded.root), isEmpty);
  });
}
