// SPDX-License-Identifier: MPL-2.0
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';

import '../tool/fidelity/metafile_records.dart';
import '../tool/media_web_acceptance.dart';

void main() {
  test('committed vector controls match independent record authoring', () {
    for (final (format, raw) in [
      ('emf', authoredEmfVectors()),
      ('wmf', authoredWmfVectors()),
    ]) {
      final base = 'test/fixtures/fidelity/media/$format-vectors';
      expect(File('$base.$format').readAsBytesSync(), orderedEquals(raw));
      final package = ZipDecoder().decodeBytes(
        File('$base.docx').readAsBytesSync(),
      );
      expect(
        package.findFile('word/media/control.$format')!.content,
        orderedEquals(raw),
      );
      expect(
        package.files.where((file) => file.name.startsWith('word/media/')),
        hasLength(1),
      );
    }
  });

  test('portable media smoke also runs unchanged on the VM', () {
    final result = verifyMediaWebAcceptance();
    expect(result['checks'], 40);
    expect(result['recordCounts'], {'emf': 21, 'wmf': 17});
  });
}
