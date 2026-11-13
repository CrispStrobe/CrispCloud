// SPDX-License-Identifier: MPL-2.0
// The same ownership controls run on the Dart VM and in compiled JavaScript.

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

import '../test/support/compound_ownership_fixture.dart';

Map<String, Object?> verifyCompoundOwnershipWebCases() {
  var rejections = 0;
  var comparisons = 0;
  void rejects(void Function() read, String label) {
    try {
      read();
    } on CfbfException {
      rejections++;
      return;
    } on FormatException {
      rejections++;
      return;
    }
    throw StateError('Accepted malformed compound ownership: $label');
  }

  void equal(List<int>? actual, List<int> expected, String label) {
    if (actual == null || actual.length != expected.length) {
      throw StateError('$label length ${actual?.length} != ${expected.length}');
    }
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) {
        throw StateError('$label differs at $index');
      }
    }
  }

  void valid(
    CfbfFile raw,
    BoundedCfbReader bounded,
    String name,
    List<int> data,
  ) {
    equal(raw.readPath(name), data, 'raw $name');
    equal(bounded.readPath(name), data, 'bounded $name');
    comparisons += 2;
  }

  for (final (mutation, first, second) in compoundOverlappingStreams) {
    final bytes = compoundOwnershipFixture(mutation);
    final before = Uint8List.fromList(bytes);
    for (final order in [
      [first, second],
      [second, first],
    ]) {
      final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
      for (final name in order) {
        rejects(() => raw.readPath(name), 'raw $mutation $name');
        rejects(() => bounded.readPath(name), 'bounded $mutation $name');
      }
    }
    equal(bytes, before, 'source $mutation');
  }
  for (final (mutation, name) in compoundMetadataOverlaps) {
    final bytes = compoundOwnershipFixture(mutation);
    final before = Uint8List.fromList(bytes);
    final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
    rejects(() => raw.readPath(name), 'raw $mutation');
    rejects(() => bounded.readPath(name), 'bounded $mutation');
    valid(
      raw,
      bounded,
      'Bravo',
      List.generate(4097, (index) => 255 - index % 251),
    );
    equal(bytes, before, 'source $mutation');
  }
  final metadata = compoundOwnershipFixture('directory-minifat');
  rejects(() => CfbfFile.fromBytes(metadata), 'raw directory-minifat');
  rejects(() => BoundedCfbReader(metadata), 'bounded directory-minifat');

  for (final mutation in ['unrelated-regular-cycle', 'unrelated-mini-cycle']) {
    final bytes = compoundOwnershipFixture(mutation);
    final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
    valid(raw, bounded, 'Alpha', List.generate(4097, (index) => index % 251));
    valid(raw, bounded, 'SmallA', List.generate(65, (index) => index + 10));
    final bad = mutation.contains('regular') ? 'Bravo' : 'SmallB';
    rejects(() => raw.readPath(bad), 'raw unrelated $bad');
    rejects(() => bounded.readPath(bad), 'bounded unrelated $bad');
  }
  final bytes = compoundOwnershipFixture('valid');
  final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
  if (raw.entryByName('Alpha')!.startSector != 0 ||
      raw.entryByName('SmallA')!.startSector != 0) {
    throw StateError('Fixture must reuse sector number 0 across namespaces');
  }
  for (final (name, expected) in [
    ('Alpha', List.generate(4097, (index) => index % 251)),
    ('Bravo', List.generate(4097, (index) => 255 - index % 251)),
    ('SmallA', List.generate(65, (index) => index + 10)),
    ('SmallB', List.generate(65, (index) => index + 100)),
  ]) {
    valid(raw, bounded, name, expected);
  }
  final other = CfbfFile.fromBytes(
    (CfbfWriter()..addStream('Other', [1])).build(),
  ).entryByName('Other')!;
  rejects(() => raw.readEntry(other), 'raw substituted entry');
  rejects(() => bounded.readEntry(other), 'bounded substituted entry');
  final limited = BoundedCfbReader(bytes, maxTotalReadBytes: 130);
  final entry = limited.child(limited.root, 'SmallA')!;
  equal(
    limited.readPath('SmallA'),
    List.generate(65, (index) => index + 10),
    'first budgeted read',
  );
  rejects(
    () => limited.readEntry(compoundNegativeSizeEntry(entry)),
    'negative-size budget credit',
  );
  equal(
    limited.readPath('SmallB'),
    List.generate(65, (index) => index + 100),
    'exact aggregate budget',
  );
  rejects(() => limited.readPath('SmallA'), 'exhausted aggregate budget');
  comparisons += 2;
  return {
    'malformedOverlapCases': 15,
    'readerRejections': rejections,
    'compatibilityCases': 3,
    'streamComparisons': comparisons,
    'negativeSizePreservesBudget': true,
    'sourceUnchanged': true,
  };
}
