// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:test/test.dart';

import 'support/compound_tree_fixture.dart';

void main() {
  final rejected = throwsA(anyOf(isA<CfbfException>(), isA<FormatException>()));
  for (final mutation in compoundInvalidTrees) {
    for (final bounded in [false, true]) {
      test('directory graph bounded=$bounded $mutation', () {
        final bytes = compoundTreeFixture(mutation);
        final original = Uint8List.fromList(bytes);
        expect(
          () => bounded ? BoundedCfbReader(bytes) : CfbfFile.fromBytes(bytes),
          rejected,
        );
        expect(bytes, original);
      });
    }
  }
  final fixture = compoundTreeFixture('valid');
  final raw = CfbfFile.fromBytes(fixture);
  final bounded = BoundedCfbReader(fixture);
  for (final parent in [raw.root, raw.entryByName('First')!]) {
    for (final (name, forged) in compoundInvalidParents(
      parent,
      raw.entries.length,
    )) {
      test('raw caller parent ${parent.name}/$name must match directory', () {
        expect(() => raw.childrenOf(forged).toList(), rejected);
      });
      test(
        'bounded caller parent ${parent.name}/$name must match directory',
        () {
          expect(() => bounded.childrenOf(forged), rejected);
          expect(() => bounded.child(forged, 'Alpha'), rejected);
        },
      );
    }
  }
  test('equivalent caller metadata retains the same owned children', () {
    for (final parent in [raw.root, raw.entryByName('First')!]) {
      final copy = compoundEntryCopy(parent);
      expect(
        raw.childrenOf(copy).map((e) => e.index),
        raw.childrenOf(parent).map((e) => e.index),
      );
      expect(
        bounded.childrenOf(copy).map((e) => e.index),
        raw.childrenOf(parent).map((e) => e.index),
      );
    }
    expect(raw.readPath('First/Alpha'), [11]);
    expect(bounded.readPath('First/Alpha'), [11]);
    expect(raw.readPath('First/Bravo'), [22]);
    expect(bounded.readPath('Second/Charlie'), [33]);
  });
}
