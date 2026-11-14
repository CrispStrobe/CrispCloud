// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/public_note_reference_fixture.dart';

Map<String, Object?> verifyPublicNoteReferenceWebAcceptance() {
  var rejected = 0, valid = 0;
  for (final endnote in [false, true]) {
    for (final mutation in publicNoteInvalidCases) {
      var failed = false;
      try {
        convertLegacyWordDocument(
          publicNoteReferenceDocument(mutation, endnote),
        );
      } on FormatException {
        failed = true;
      }
      if (!failed) throw StateError('$endnote/$mutation was not rejected');
      rejected++;
    }
    for (final mutation in ['valid', 'reverse', 'one-hidden']) {
      final result = convertLegacyWordDocument(
        publicNoteReferenceDocument(mutation, endnote),
      );
      final archive = ZipDecoder().decodeBytes(result.bytes);
      XmlDocument part(String name) =>
          XmlDocument.parse(utf8.decode(archive.findFile(name)!.content));
      final name = endnote ? 'endnote' : 'footnote';
      final references = part('word/document.xml')
          .findAllElements('w:${name}Reference')
          .map((e) => e.getAttribute('w:id'))
          .toList();
      final notes = part('word/${name}s.xml')
          .findAllElements('w:$name')
          .where((e) => e.getAttribute('w:type') == null)
          .toList();
      final ids = notes.map((e) => e.getAttribute('w:id')).toSet();
      final expected = mutation == 'one-hidden' ? 1 : 2;
      if (references.length != expected ||
          notes.length != expected ||
          references.any((id) => !ids.contains(id)) ||
          notes.any((n) => n.findAllElements('w:${name}Ref').length != 1)) {
        throw StateError('$endnote/$mutation has a dangling or aliased note');
      }
      valid++;
    }
  }
  return {
    'rejectedCases': rejected,
    'validCases': valid,
    'danglingReferences': 0,
  };
}
