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
}
