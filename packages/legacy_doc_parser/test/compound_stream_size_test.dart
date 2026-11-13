// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:test/test.dart';

import 'support/compound_size_fixture.dart';

void main() {
  // MS-CFB §2.6.3 requires readers to accept uninitialized high DWORDs in
  // version 3. Version 4 uses the complete 64-bit size and cannot ignore them.
  // https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/b37413bb-f3ef-4adc-b18e-29bddd62c26e
  for (final highWord in [1, 0x80000000, 0xffffffff]) {
    test('version 3 ignores stream-size high DWORD $highWord', () {
      final source = compoundSizeFixture(highWord: highWord);
      final before = Uint8List.fromList(source);
      final bounded = BoundedCfbReader(source);
      final raw = CfbfFile.fromBytes(source);
      expect(bounded.root.streamSize, 64);
      expect(raw.root.streamSize, 64);
      expect(bounded.readPath('Small'), [1, 2, 3]);
      expect(raw.readPath('Small'), [1, 2, 3]);
      final expected = List.generate(4096, (index) => index & 255);
      expect(bounded.readPath('Large'), expected);
      expect(raw.readPath('Large'), expected);
      expect(source, before);
    });

    for (final root in [false, true]) {
      test(
        'version 4 rejects oversized ${root ? 'root' : 'stream'} $highWord',
        () {
          final source = compoundSizeFixture(
            version4: true,
            highWord: highWord,
            root: root,
            streams: !root,
          );
          expect(() => BoundedCfbReader(source), throwsFormatException);
        },
      );
    }
  }

  for (final version4 in [false, true]) {
    test('version ${version4 ? 4 : 3} keeps physical low-word bounds', () {
      final source = compoundSizeFixture(
        version4: version4,
        highWord: version4 ? 0 : 0xffffffff,
        oversizedLowWord: true,
      );
      expect(() => BoundedCfbReader(source), throwsFormatException);
    });
  }

  test('version 4 reads an independently authored bounded stream', () {
    final source = compoundSizeFixture(version4: true);
    final before = Uint8List.fromList(source);
    final expected = List.generate(4096, (index) => index & 255);
    expect(BoundedCfbReader(source).readPath('Large'), expected);
    expect(CfbfFile.fromBytes(source).readPath('Large'), expected);
    expect(source, before);
  });

  for (final (high, low, expected) in [
    (1, 4096, 4294971392),
    (0, 0x80000000, 2147483648),
    (0, 0xffffffff, 4294967295),
    (0x1fffff, 0xffffffff, 9007199254740991),
  ]) {
    test('raw version 4 retains portable 64-bit metadata $expected', () {
      final source = compoundSizeFixture(
        version4: true,
        root: false,
        highWord: high,
        lowWord: low,
      );
      // Both readers reject materializing this oversized declaration before
      // allocation, but the raw reader retains its exact portable metadata.
      final raw = CfbfFile.fromBytes(source);
      expect(raw.entryByName('Large')!.streamSize, expected);
      expect(() => raw.readPath('Large'), throwsA(isA<CfbfException>()));
      expect(() => BoundedCfbReader(source), throwsFormatException);
    });
  }

  for (final highWord in [0x200000, 0x80000000, 0xffffffff]) {
    test('raw version 4 rejects inexact portable stream size $highWord', () {
      final source = compoundSizeFixture(
        version4: true,
        root: false,
        highWord: highWord,
        lowWord: 0,
      );
      expect(() => CfbfFile.fromBytes(source), throwsA(isA<CfbfException>()));
    });
  }

  test('raw mini-stream reads bound the root container before allocation', () {
    final source = compoundSizeFixture(streams: false, oversizedLowWord: true);
    final raw = CfbfFile.fromBytes(source);
    expect(raw.entryByName('Small')!.streamSize, 3);
    expect(() => raw.readPath('Small'), throwsA(isA<CfbfException>()));
    expect(() => raw.readEntry(raw.root), throwsA(isA<CfbfException>()));
  });
}
