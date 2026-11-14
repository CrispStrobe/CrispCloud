// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/public_bookmark_fixture.dart';

const publicBookmarkHiddenValidCases = ['valid', 'first-column', 'last-column'];
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

Map<String, Object> verifyPublicBookmarkWebAcceptance() {
  var visible = 0, auxiliary = 0, hidden = 0, rejected = 0;
  for (final mutation in publicBookmarkValidCases) {
    final document = publicBookmarkDocument(mutation);
    final before = jsonEncode(publicBookmarkSourceMetadata(document));
    final source = document.bookmarks.single;
    final result = convertLegacyWordDocument(document);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final part = publicBookmarkOutputPart(mutation);
    final xml = _xml(archive, part);
    final starts = xml.findAllElements('bookmarkStart', namespace: _w).toList();
    final ends = xml.findAllElements('bookmarkEnd', namespace: _w).toList();
    _require(
      starts.length == 1 && ends.length == 1,
      'Missing or duplicated bookmark in $part: $mutation',
    );
    final start = starts.single;
    final end = ends.single;
    _require(
      start.getAttribute('name', namespace: _w) == source.name &&
          start.getAttribute('id', namespace: _w) != null &&
          start.getAttribute('id', namespace: _w) ==
              end.getAttribute('id', namespace: _w) &&
          start.getAttribute('colFirst', namespace: _w) ==
              source.firstCell?.toString() &&
          start.getAttribute('colLast', namespace: _w) ==
              source.lastCell?.toString(),
      'Bookmark name, pairing, or columns changed: $mutation',
    );
    final nodes = xml.descendants.toList();
    _require(
      nodes.indexOf(start) < nodes.indexOf(end),
      'Bookmark end precedes its start: $mutation',
    );
    _requireNoBookmarksOutside(archive, part, mutation);
    _require(
      result.preservedCounts['bookmarks'] == 1 &&
          before == jsonEncode(publicBookmarkSourceMetadata(document)),
      'Bookmark count or source metadata changed: $mutation',
    );
    visible++;
    if (part != 'word/document.xml') auxiliary++;
  }
  for (final mutation in publicBookmarkHiddenValidCases) {
    final document = publicBookmarkDocument(mutation, hidden: true);
    final before = jsonEncode(publicBookmarkSourceMetadata(document));
    final source = document.bookmarks.single;
    final result = convertLegacyWordDocument(document);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    _requireNoBookmarksOutside(archive, null, mutation);
    final manifest = archive.findFile('word/evidence/manifest.json');
    _require(manifest != null, 'Missing hidden bookmark evidence: $mutation');
    final records =
        (jsonDecode(utf8.decode(manifest!.content))['records'] as List)
            .cast<Map>()
            .where((record) => record['kind'] == 'bookmark')
            .toList();
    _require(records.length == 1, 'Ambiguous hidden bookmark evidence');
    final record = records.single;
    _require(
      record['name'] == source.name &&
          record['startCp'] == source.startCp &&
          record['endCp'] == source.endCp &&
          record['firstCell'] == source.firstCell &&
          record['lastCell'] == source.lastCell &&
          (result.preservedCounts['bookmarks'] ?? 0) == 0 &&
          before == jsonEncode(publicBookmarkSourceMetadata(document)),
      'Hidden bookmark metadata changed or became active: $mutation',
    );
    hidden++;
  }
  for (final hidden in [false, true]) {
    for (final mutation in publicBookmarkInvalidCases) {
      _reject(mutation, hidden: hidden);
      rejected++;
    }
  }
  return {
    'visibleCases': visible,
    'auxiliaryOwnerCases': auxiliary,
    'hiddenEvidenceCases': hidden,
    'malformedInputsRejected': rejected,
    'convertedPackages': visible + hidden,
    'sourceMetadataUnchanged': true,
  };
}

Map<String, Object?> publicBookmarkSourceMetadata(
  LegacyWordDocument document,
) => {
  'bookmarks': [
    for (final bookmark in document.bookmarks)
      {
        'name': bookmark.name,
        'startCp': bookmark.startCp,
        'endCp': bookmark.endCp,
        'firstCell': bookmark.firstCell,
        'lastCell': bookmark.lastCell,
      },
  ],
  'stories': [
    for (final story in document.stories)
      {
        'id': story.id,
        'kind': story.kind.name,
        'startCp': story.startCp,
        'endCp': story.endCp,
      },
  ],
};

void _requireNoBookmarksOutside(
  Archive archive,
  String? owner,
  String mutation,
) {
  final activePart = RegExp(
    r'^word/(document|header\d+|footer\d+|footnotes|endnotes|comments)\.xml$',
  );
  for (final file in archive.files) {
    if (file.name == owner || !activePart.hasMatch(file.name)) continue;
    final xml = XmlDocument.parse(utf8.decode(file.content));
    _require(
      xml.findAllElements('bookmarkStart', namespace: _w).isEmpty &&
          xml.findAllElements('bookmarkEnd', namespace: _w).isEmpty,
      'Bookmark leaked into ${file.name}: $mutation',
    );
  }
}

XmlDocument _xml(Archive archive, String path) {
  final file = archive.findFile(path);
  _require(file != null, 'Missing bookmark output part: $path');
  return XmlDocument.parse(utf8.decode(file!.content));
}

void _reject(String mutation, {required bool hidden}) {
  try {
    convertLegacyWordDocument(publicBookmarkDocument(mutation, hidden: hidden));
  } on FormatException {
    return;
  } on LegacyWordConversionException {
    return;
  }
  throw StateError('Malformed bookmark accepted: $mutation, hidden=$hidden');
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
