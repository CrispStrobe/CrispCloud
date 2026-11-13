// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:test/test.dart';

void main() {
  test(
    'preserves storage class, state, exact timestamps and opaque streams',
    () {
      final clsid = Uint8List.fromList(List.generate(16, (i) => 255 - i));
      // A documented FILETIME with an additional 100ns tick: DateTime alone
      // cannot preserve this last decimal digit on either VM or JavaScript.
      final time = Uint8List.fromList([
        1,
        0x88,
        0xf9,
        0x12,
        0x4b,
        0xb4,
        0xba,
        1,
      ]);
      final writer = CfbfWriter(
        clsid: clsid,
        stateBits: 123,
        modifiedFiletime: time,
      );
      writer.addStorage(
        'VBA',
        clsid: clsid,
        stateBits: 456,
        createdFiletime: time,
        modifiedFiletime: time,
      );
      writer.addStream('VBA/dir', [1, 2, 3, 255]);
      writer.addStream('large', List.generate(5000, (i) => i % 256));
      clsid[0] = 0;
      time[0] = 0;
      final file = BoundedCfbReader(writer.build());
      expect(file.root.clsid.first, 255);
      expect(file.root.stateBits, 123);
      expect(file.root.modifiedFiletime.first, 1);
      final storage = file.child(file.root, 'VBA')!;
      expect(storage.clsid.first, 255);
      expect(storage.stateBits, 456);
      expect(storage.createdFiletime.first, 1);
      expect(storage.modifiedFiletime.first, 1);
      expect(file.readPath('VBA/dir'), [1, 2, 3, 255]);
      expect(file.readPath('large'), List.generate(5000, (i) => i % 256));
    },
  );

  test('sibling ordering follows name length before uppercase code units', () {
    final writer = CfbfWriter();
    for (final name in ['AAA', 'Z', 'BB', 'A', 'b']) {
      writer.addStream(name, [1]);
    }
    final file = CfbfFile.fromBytes(writer.build());
    final names = <String>[];
    void visit(int index) {
      if (index == cfbfNoStream) return;
      final entry = file.entries[index];
      visit(entry.leftSibling);
      names.add(entry.name);
      visit(entry.rightSibling);
    }

    visit(file.root.child);
    expect(names, ['A', 'b', 'Z', 'BB', 'AAA']);
  });

  test('rejects metadata truncation, invalid names and case collisions', () {
    expect(() => CfbfWriter(clsid: Uint8List(15)), throwsArgumentError);
    expect(
      () => CfbfWriter(createdFiletime: Uint8List(7)),
      throwsArgumentError,
    );
    expect(() => CfbfWriter(stateBits: -1), throwsArgumentError);
    final writer = CfbfWriter()..addStream('VBA/dir', [1]);
    expect(() => writer.addStream('VBA/DIR', [2]), throwsArgumentError);
    expect(() => writer.addStream('x' * 32, [1]), throwsArgumentError);
    expect(() => writer.addStream('bad!name', [1]), throwsArgumentError);
  });

  test('keeps distinct names whose full uppercase expansions match', () {
    final writer = CfbfWriter()
      ..addStream('ß', [1])
      ..addStream('SS', [2]);
    final source = writer.build();
    final original = Uint8List.fromList(source);
    final file = BoundedCfbReader(source);
    expect(file.childrenOf(file.root), hasLength(2));
    expect(file.readPath('ß'), [1]);
    expect(file.readPath('ss'), [2]);
    expect(source, original);
  });

  test('lookup cannot cross a differently sized full-uppercase alias', () {
    final source = (CfbfWriter()..addStream('ß', [1])).build();
    expect(CfbfFile.fromBytes(source).readPath('SS'), isNull);
    expect(BoundedCfbReader(source).readPath('SS'), isNull);
  });

  test(
    'equal-length names use per-unit simple uppercase without expansion',
    () {
      final writer = CfbfWriter()
        ..addStream('ßs', [1])
        ..addStream('sß', [2])
        ..addStream('ﬃ', [3]);
      final source = writer.build();
      for (final (name, data) in [('ßS', 1), ('Sß', 2), ('ﬃ', 3)]) {
        expect(CfbfFile.fromBytes(source).readPath(name), [data]);
        expect(BoundedCfbReader(source).readPath(name), [data]);
      }
      expect(BoundedCfbReader(source).readPath('FFI'), isNull);
    },
  );

  test(
    'supplementary case pairs retain distinct UTF-16 names and storages',
    () {
      // MS-CFB uppercases individual UTF-16 units; surrogate pairs never fold.
      final writer = CfbfWriter()
        ..addStream('\u{10400}/Value', [1])
        ..addStream('\u{10428}/Value', [2]);
      final source = writer.build();
      final bounded = BoundedCfbReader(source);
      final raw = CfbfFile.fromBytes(source);
      expect(bounded.childrenOf(bounded.root), hasLength(2));
      expect(bounded.readPath('\u{10400}/value'), [1]);
      expect(bounded.readPath('\u{10428}/VALUE'), [2]);
      expect(raw.readPath('\u{10400}/value'), [1]);
      expect(raw.readPath('\u{10428}/VALUE'), [2]);
    },
  );

  test('retains Greek simple uppercase mappings with full-case expansions', () {
    // UnicodeData.txt's simple uppercase column, independently enumerated.
    const mappings = <int, int>{
      0x1f80: 0x1f88,
      0x1f81: 0x1f89,
      0x1f82: 0x1f8a,
      0x1f83: 0x1f8b,
      0x1f84: 0x1f8c,
      0x1f85: 0x1f8d,
      0x1f86: 0x1f8e,
      0x1f87: 0x1f8f,
      0x1f90: 0x1f98,
      0x1f91: 0x1f99,
      0x1f92: 0x1f9a,
      0x1f93: 0x1f9b,
      0x1f94: 0x1f9c,
      0x1f95: 0x1f9d,
      0x1f96: 0x1f9e,
      0x1f97: 0x1f9f,
      0x1fa0: 0x1fa8,
      0x1fa1: 0x1fa9,
      0x1fa2: 0x1faa,
      0x1fa3: 0x1fab,
      0x1fa4: 0x1fac,
      0x1fa5: 0x1fad,
      0x1fa6: 0x1fae,
      0x1fa7: 0x1faf,
      0x1fb3: 0x1fbc,
      0x1fc3: 0x1fcc,
      0x1ff3: 0x1ffc,
    };
    final writer = CfbfWriter();
    for (final lower in mappings.keys) {
      writer.addStream(String.fromCharCode(lower), [lower & 255]);
    }
    final source = writer.build();
    final bounded = BoundedCfbReader(source);
    final raw = CfbfFile.fromBytes(source);
    for (final entry in mappings.entries) {
      final name = String.fromCharCode(entry.value);
      expect(bounded.readPath(name), [entry.key & 255]);
      expect(raw.readPath(name), [entry.key & 255]);
      expect(() => writer.addStream(name, [0]), throwsArgumentError);
    }
  });
}
