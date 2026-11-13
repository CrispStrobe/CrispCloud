// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/byte_source.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:test/test.dart';

import 'support/compound_allocation_fixture.dart';
import 'support/compound_size_fixture.dart';

void main() {
  final rejectsCompound = throwsA(
    anyOf(isA<CfbfException>(), isA<FormatException>()),
  );
  for (final mutation in [
    'duplicate-fat',
    'fat-count-zero',
    'fat-count-extra',
    'difat-count-extra',
    'minifat-count-extra',
    'minifat-free-terminal',
    'directory-count',
    'directory-free-terminal',
  ]) {
    test('raw reader rejects allocation metadata $mutation', () {
      final bytes = compoundAllocationFixture(mutation);
      expect(() => CfbfFile.fromBytes(bytes), rejectsCompound);
    });
    test('bounded reader rejects allocation metadata $mutation', () {
      final bytes = compoundAllocationFixture(mutation);
      expect(() => BoundedCfbReader(bytes), rejectsCompound);
    });
  }

  for (final (mutation, path) in [
    ('mini-cycle-tail', 'Small'),
    ('mini-free-tail', 'Small'),
    ('regular-cycle-tail', 'Large'),
    ('regular-free-tail', 'Large'),
    ('root-cycle-tail', 'Small'),
    ('mini-cycle-spare', 'Small'),
    ('regular-cycle-spare', 'Large'),
  ]) {
    test('raw reader rejects the final consumed allocation link $mutation', () {
      final file = CfbfFile.fromBytes(compoundAllocationFixture(mutation));
      expect(() => file.readPath(path), rejectsCompound);
    });
    test(
      'bounded reader rejects the final consumed allocation link $mutation',
      () {
        final file = BoundedCfbReader(compoundAllocationFixture(mutation));
        expect(() => file.readPath(path), rejectsCompound);
      },
    );
  }

  test('partly filled FAT and mini sectors preserve exact logical bytes', () {
    final bytes = compoundAllocationFixture('valid');
    final before = Uint8List.fromList(bytes);
    final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
    final small = List.generate(65, (index) => index);
    final large = List.generate(4097, (index) => index % 251);
    expect(raw.readPath('Small'), small);
    expect(bounded.readPath('Small'), small);
    expect(raw.readPath('Large'), large);
    expect(bounded.readPath('Large'), large);
    expect(bytes, before);
  });

  test('version 4 directory count is measured in 4096-byte sectors', () {
    final bytes = compoundSizeFixture(version4: true);
    final expected = List.generate(4096, (index) => index & 255);
    expect(CfbfFile.fromBytes(bytes).readPath('Large'), expected);
    expect(BoundedCfbReader(bytes).readPath('Large'), expected);
  });

  test('valid spare allocation capacity stays outside logical output', () {
    // MS-CFB §2.7 permits chain capacity >= stream size. Do not require the
    // final logical byte to occupy the final allocated sector.
    final bytes = compoundAllocationFixture('spare-capacity');
    final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
    final expected = List.generate(4096, (index) => index % 251);
    expect(raw.readPath('Large'), expected);
    expect(bounded.readPath('Large'), expected);
    expect(raw.readPath('Small'), [0]);
    expect(bounded.readPath('Small'), [0]);
  });

  for (final size in [1, 65, 127]) {
    test('retains partial final mini-container compatibility ($size)', () {
      final bytes = compoundPartialMiniFixture(size);
      final expected = List.generate(size, (index) => index & 255);
      expect(CfbfFile.fromBytes(bytes).readPath('Small'), expected);
      expect(BoundedCfbReader(bytes).readPath('Small'), expected);
    });
  }

  test('shared long tails are rejected without any payload reads', () {
    final bytes = compoundSharedChainFixture();
    final source = _CountedSource(bytes);
    final raw = CfbfFile.open(source), bounded = BoundedCfbReader(bytes);
    source.views = source.zeroLengthViews = 0;
    for (final entry in raw.entries.where((entry) => entry.isStream)) {
      expect(() => raw.readEntry(entry), rejectsCompound);
      expect(() => bounded.readPath(entry.name), rejectsCompound);
    }
    expect(source.views, 0);
    expect(source.zeroLengthViews, 0);
  });

  test('repeated overallocated stream reads skip spare payload capacity', () {
    final bytes = compoundOverallocatedFixture();
    final source = _CountedSource(bytes);
    final raw = CfbfFile.open(source), bounded = BoundedCfbReader(bytes);
    final expected = List.generate(4096, (index) => index % 251);
    source.views = 0;
    for (var index = 0; index < 4; index++) {
      expect(raw.readPath('Large'), expected);
      expect(bounded.readPath('Large'), expected);
    }
    expect(source.views, 4 * (4096 ~/ 512));
    expect(source.zeroLengthViews, 0);
  });

  test('cached topology uses immutable allocation and directory snapshots', () {
    final raw = CfbfFile.fromBytes(compoundAllocationFixture('valid'));
    expect(raw.readPath('Small'), List.generate(65, (index) => index));
    expect(() => raw.fat[0] = 0, throwsUnsupportedError);
    expect(() => raw.miniFat[0] = 0, throwsUnsupportedError);
    expect(() => raw.entries[0] = raw.entries[1], throwsUnsupportedError);
    final first = raw.readPath('Small')!;
    first[0] = 99;
    expect(raw.readPath('Small')!.first, 0);
  });

  test('valid external DIFAT and multiple mini FAT sectors still read', () {
    final large = List.generate(8 * 1024 * 1024, (index) => index % 251);
    final writer = CfbfWriter()..addStream('Large', large);
    for (var index = 0; index < 130; index++) {
      writer.addStream('Small$index', [index & 255]);
    }
    final bytes = writer.build();
    final data = ByteData.sublistView(bytes);
    expect(data.getUint32(72, Endian.little), greaterThan(0));
    expect(data.getUint32(64, Endian.little), 2);
    final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
    expect(raw.readPath('Large'), large);
    expect(bounded.readPath('Large'), large);
    expect(raw.readPath('Small129'), [129]);
    expect(bounded.readPath('Small129'), [129]);
  });
}

class _CountedSource extends MemoryByteSource {
  _CountedSource(super.bytes);

  var views = 0;
  var zeroLengthViews = 0;

  @override
  Uint8List view(int offset, int length) {
    views++;
    if (length == 0) zeroLengthViews++;
    return super.view(offset, length);
  }
}
