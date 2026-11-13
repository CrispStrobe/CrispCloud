// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:test/test.dart';

import 'support/compound_directory_fixture.dart';

void main() {
  final rejectsCompound = throwsA(
    anyOf(isA<CfbfException>(), isA<FormatException>()),
  );
  for (final mutation in compoundMalformedNames) {
    test('raw reader rejects malformed directory name $mutation', () {
      final bytes = compoundDirectoryNameFixture(mutation);
      final before = Uint8List.fromList(bytes);
      expect(() => CfbfFile.fromBytes(bytes), rejectsCompound);
      expect(bytes, before);
    });
    test('bounded reader rejects malformed directory name $mutation', () {
      final bytes = compoundDirectoryNameFixture(mutation);
      final before = Uint8List.fromList(bytes);
      expect(() => BoundedCfbReader(bytes), rejectsCompound);
      expect(bytes, before);
    });
  }

  for (final mutation in ['valid', 'unused-padding', 'stale-unused-slot']) {
    test('ignores unused name bytes: $mutation', () {
      final bytes = compoundDirectoryNameFixture(mutation);
      final before = Uint8List.fromList(bytes);
      expect(CfbfFile.fromBytes(bytes).readPath('folder/payload'), [
        11,
        12,
        13,
      ]);
      expect(BoundedCfbReader(bytes).readPath('folder/payload'), [11, 12, 13]);
      expect(bytes, before);
    });
  }

  test('retains maximum, control-prefixed and supplementary UTF-16 names', () {
    final names = ['x' * 31, '\u0005SummaryInformation', '\u{10400}Data'];
    final writer = CfbfWriter();
    for (var index = 0; index < names.length; index++) {
      writer.addStream(names[index], [index + 1]);
    }
    final bytes = writer.build();
    final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
    for (var index = 0; index < names.length; index++) {
      expect(raw.readPath(names[index]), [index + 1]);
      expect(bounded.readPath(names[index]), [index + 1]);
    }
  });
}
