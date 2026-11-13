// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:test/test.dart';

import 'support/compound_ownership_fixture.dart';

void main() {
  final rejectsCompound = throwsA(
    anyOf(isA<CfbfException>(), isA<FormatException>()),
  );
  for (final (mutation, first, second) in compoundOverlappingStreams) {
    test('rejects both stream owners independent of read order: $mutation', () {
      final bytes = compoundOwnershipFixture(mutation);
      final before = Uint8List.fromList(bytes);
      for (final order in [
        [first, second],
        [second, first],
      ]) {
        final raw = CfbfFile.fromBytes(bytes),
            bounded = BoundedCfbReader(bytes);
        for (final name in order) {
          expect(() => raw.readPath(name), rejectsCompound, reason: name);
          expect(() => bounded.readPath(name), rejectsCompound, reason: name);
        }
      }
      expect(bytes, before);
    });
  }

  for (final (mutation, name) in compoundMetadataOverlaps) {
    test('rejects stream allocation crossing metadata: $mutation', () {
      final bytes = compoundOwnershipFixture(mutation);
      final before = Uint8List.fromList(bytes);
      final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
      expect(() => raw.readPath(name), rejectsCompound);
      expect(() => bounded.readPath(name), rejectsCompound);
      // A disjoint user stream still has one unambiguous owner.
      final expected = List.generate(4097, (index) => 255 - index % 251);
      expect(raw.readPath('Bravo'), expected);
      expect(bounded.readPath('Bravo'), expected);
      expect(bytes, before);
    });
  }

  test(
    'rejects directory and mini-FAT sector overlap before materializing',
    () {
      final bytes = compoundOwnershipFixture('directory-minifat');
      expect(() => CfbfFile.fromBytes(bytes), rejectsCompound);
      expect(() => BoundedCfbReader(bytes), rejectsCompound);
    },
  );

  for (final mutation in ['unrelated-regular-cycle', 'unrelated-mini-cycle']) {
    test('keeps validation lazy for unrelated malformed chains: $mutation', () {
      final bytes = compoundOwnershipFixture(mutation);
      final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
      final alpha = List.generate(4097, (index) => index % 251);
      final small = List.generate(65, (index) => index + 10);
      expect(raw.readPath('Alpha'), alpha);
      expect(bounded.readPath('Alpha'), alpha);
      expect(raw.readPath('SmallA'), small);
      expect(bounded.readPath('SmallA'), small);
      final bad = mutation.contains('regular') ? 'Bravo' : 'SmallB';
      expect(() => raw.readPath(bad), rejectsCompound);
      expect(() => bounded.readPath(bad), rejectsCompound);
    });
  }

  test(
    'mini-sector and physical-sector numbers are independent namespaces',
    () {
      final bytes = compoundOwnershipFixture('valid');
      final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
      expect(raw.entryByName('Alpha')!.startSector, 0);
      expect(raw.entryByName('SmallA')!.startSector, 0);
      for (final (name, expected) in [
        ('Alpha', List.generate(4097, (index) => index % 251)),
        ('Bravo', List.generate(4097, (index) => 255 - index % 251)),
        ('SmallA', List.generate(65, (index) => index + 10)),
        ('SmallB', List.generate(65, (index) => index + 100)),
      ]) {
        expect(raw.readPath(name), expected);
        expect(bounded.readPath(name), expected);
      }
    },
  );

  test('negative caller sizes cannot credit the aggregate read budget', () {
    final bytes = compoundOwnershipFixture('valid');
    final bounded = BoundedCfbReader(bytes, maxTotalReadBytes: 130);
    final entry = bounded.child(bounded.root, 'SmallA')!;
    expect(
      bounded.readPath('SmallA'),
      List.generate(65, (index) => index + 10),
    );
    expect(
      () => bounded.readEntry(compoundNegativeSizeEntry(entry)),
      rejectsCompound,
    );
    expect(
      bounded.readPath('SmallB'),
      List.generate(65, (index) => index + 100),
    );
    expect(() => bounded.readPath('SmallA'), throwsFormatException);
  });

  test('caller entry cannot substitute allocation under a parsed index', () {
    final bytes = compoundOwnershipFixture('valid');
    final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
    final other = CfbfFile.fromBytes(
      (CfbfWriter()..addStream('Other', [1])).build(),
    ).entryByName('Other')!;
    expect(other.index, raw.entryByName('Alpha')!.index);
    expect(() => raw.readEntry(other), rejectsCompound);
    expect(() => bounded.readEntry(other), rejectsCompound);
    expect(raw.readPath('SmallA'), List.generate(65, (index) => index + 10));
    expect(
      bounded.readPath('SmallA'),
      List.generate(65, (index) => index + 10),
    );
  });
}
