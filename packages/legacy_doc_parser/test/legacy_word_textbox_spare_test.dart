// SPDX-License-Identifier: MPL-2.0
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:test/test.dart';

Uint8List _source() => File(
  'test/fixtures/word_native/word14-margin-origin.doc',
).readAsBytesSync();

Uint8List _mutate(void Function(ByteData word, ByteData table) edit) {
  final source = BoundedCfbReader(_source());
  final word = Uint8List.fromList(source.readPath('WordDocument')!);
  final table = Uint8List.fromList(source.readPath('1Table')!);
  edit(ByteData.sublistView(word), ByteData.sublistView(table));
  final writer = CfbfWriter();
  void copy(CfbfDirectoryEntry parent, String prefix) {
    for (final entry in source.childrenOf(parent)) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (entry.isStorage) {
        writer.addStorage(path);
        copy(entry, path);
      } else {
        writer.addStream(path, switch (path) {
          'WordDocument' => word,
          '1Table' => table,
          _ => source.readEntry(entry),
        });
      }
    }
  }

  copy(source.root, '');
  return writer.build();
}

void _cp(ByteData word, ByteData table, int index, int value) {
  final offset = word.getUint32(154 + 56 * 8, Endian.little);
  expect(word.getUint32(158 + 56 * 8, Endian.little), 186);
  table.setUint32(offset + index * 4, value, Endian.little);
}

void main() {
  test(
    'Word14 global spare sentinel imports all six independently bounded boxes',
    () {
      final document = parseLegacyWordDocument(_source());
      expect(document.textboxReferences, hasLength(6));
      expect(
        document.stories.where((s) => s.kind == LegacyWordStoryKind.textbox),
        hasLength(6),
      );
      expect(
        document.warnings,
        contains(LegacyWordWarning.recoveredGlobalTextboxSentinel),
      );
      expect(document.textboxReferences.map((r) => r.shapeId), [
        1031,
        1030,
        1029,
        1028,
        1027,
        1026,
      ]);
      final result = convertLegacyWordDocument(document);
      expect(result.preservedCounts['textboxes'], 6);
    },
  );

  test('a normal bounded spare endpoint needs no sentinel recovery', () {
    final document = parseLegacyWordDocument(
      _mutate((word, table) => _cp(word, table, 7, 119)),
    );
    expect(document.textboxReferences, hasLength(6));
    expect(
      document.warnings,
      isNot(contains(LegacyWordWarning.recoveredGlobalTextboxSentinel)),
    );
  });

  for (final terminal in [0, 117, 118, 120, 134, 136, 0xffffffff]) {
    test('rejects nonmatching or unsorted spare endpoint $terminal', () {
      expect(
        () => parseLegacyWordDocument(
          _mutate((word, table) => _cp(word, table, 7, terminal)),
        ),
        throwsFormatException,
      );
    });
  }

  for (final end in [117, 119, 120]) {
    test('global sentinel cannot hide changed real textbox endpoint $end', () {
      expect(
        () => parseLegacyWordDocument(
          _mutate((word, table) => _cp(word, table, 6, end)),
        ),
        throwsFormatException,
      );
    });
  }

  test('global sentinel does not exempt real box ordering from validation', () {
    expect(
      () => parseLegacyWordDocument(
        _mutate((word, table) => _cp(word, table, 2, 18)),
      ),
      throwsFormatException,
    );
  });
}
