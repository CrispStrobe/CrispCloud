// SPDX-License-Identifier: MPL-2.0
// Authored binary media/review records, also used by semantic projection tests.
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/media_revision_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  for (final kind in mediaReviewKinds) {
    for (final (state, inserted, deleted) in [
      ('inserted', true, false),
      ('deleted', false, true),
      ('overlapping', true, true),
    ]) {
      final name = '$kind-$state';
      final source = mediaReviewFixture(
        kind,
        inserted: inserted,
        deleted: deleted,
      );
      File('${root.path}/$name.doc').writeAsBytesSync(source);
      File(
        '${root.path}/$name.docx',
      ).writeAsBytesSync(convertLegacyWordToStructuredDocx(source).bytes);
    }
  }
}
