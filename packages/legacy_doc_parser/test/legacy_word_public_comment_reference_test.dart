// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void main() {
  for (final scope in ['visible', 'hidden', 'hidden-parent']) {
    for (final (name, anchor) in [
      ('negative', -1),
      ('story-end', 4),
      ('story-gap', 6),
    ]) {
      test('$scope comment rejects $name anchor', () {
        expect(
          () => convertLegacyWordDocument(
            _commentDocument(scope: scope, anchorCp: anchor),
          ),
          throwsFormatException,
        );
      });
    }
    for (final (name, start, end) in <(String, int?, int?)>[
      ('missing-start', null, 2),
      ('missing-end', 1, null),
      ('reversed', 3, 1),
      ('negative-start', -1, 2),
      ('past-owner-end', 1, 5),
      ('other-story', 10, 12),
    ]) {
      test('$scope comment rejects $name range', () {
        expect(
          () => convertLegacyWordDocument(
            _commentDocument(
              scope: scope,
              rangeStartCp: start,
              rangeEndCp: end,
            ),
          ),
          throwsFormatException,
        );
      });
    }
    for (final (name, start, end) in <(String, int?, int?)>[
      ('absent', null, null),
      ('full-story', 0, 4),
      ('point-at-start', 0, 0),
      ('point-at-end', 4, 4),
    ]) {
      test('$scope comment preserves valid $name range', () {
        _checkOutput(
          _commentDocument(scope: scope, rangeStartCp: start, rangeEndCp: end),
          active: scope == 'visible',
          range: start != null,
        );
      });
    }
  }

  for (final (name, start, end) in <(String, int?, int?)>[
    ('absent', null, null),
    ('full-story', 10, 14),
    ('point-at-start', 10, 10),
    ('point-at-end', 14, 14),
  ]) {
    test('header comment preserves valid $name range', () {
      _checkOutput(
        _commentDocument(
          scope: 'visible',
          anchorCp: 11,
          rangeStartCp: start,
          rangeEndCp: end,
        ),
        active: true,
        range: start != null,
        part: 'word/header1.xml',
      );
    });
  }
}

LegacyWordDocument _commentDocument({
  required String scope,
  int anchorCp = 1,
  int? rangeStartCp,
  int? rangeEndCp,
}) {
  final hiddenParent = scope == 'hidden-parent';
  return LegacyWordDocument(
    blocks: [_paragraph(0, 'ABC')],
    sections: const [LegacyWordSection(startCp: 0, endCp: 4)],
    plainText: 'ABC',
    safeHtml: '',
    stories: [
      _story('header', LegacyWordStoryKind.header, 10, 'HDR'),
      _story('comment-target', LegacyWordStoryKind.comment, 20, 'Note'),
      if (hiddenParent)
        _story('comment-parent', LegacyWordStoryKind.comment, 30, 'Root'),
    ],
    commentReferences: [
      // The reply deliberately precedes its parent in the public input.
      LegacyWordCommentReference(
        id: 1,
        anchorCp: anchorCp,
        storyId: 'comment-target',
        rangeStartCp: rangeStartCp,
        rangeEndCp: rangeEndCp,
        parentId: hiddenParent ? 0 : null,
        presentation: LegacyWordMediaPresentation(hidden: scope == 'hidden'),
      ),
      if (hiddenParent)
        const LegacyWordCommentReference(
          id: 0,
          anchorCp: 0,
          storyId: 'comment-parent',
          presentation: LegacyWordMediaPresentation(hidden: true),
        ),
    ],
  );
}

LegacyWordParagraph _paragraph(int start, String text) => LegacyWordParagraph(
  startCp: start,
  endCp: start + text.length + 1,
  runs: [LegacyWordRun(startCp: start, endCp: start + text.length, text: text)],
);

LegacyWordStory _story(
  String id,
  LegacyWordStoryKind kind,
  int start,
  String text,
) => LegacyWordStory(
  id: id,
  kind: kind,
  startCp: start,
  endCp: start + text.length + 1,
  blocks: [_paragraph(start, text)],
  plainText: text,
  safeHtml: '',
);

void _checkOutput(
  LegacyWordDocument document, {
  required bool active,
  required bool range,
  String part = 'word/document.xml',
}) {
  final archive = ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  );
  final owner = XmlDocument.parse(utf8.decode(archive.findFile(part)!.content));
  final expectedReferences = active ? 1 : 0;
  final expectedRanges = active && range ? 1 : 0;
  for (final (tag, count) in [
    ('commentReference', expectedReferences),
    ('commentRangeStart', expectedRanges),
    ('commentRangeEnd', expectedRanges),
  ]) {
    expect(
      owner
          .findAllElements(tag, namespace: _w)
          .where((node) => node.getAttribute('id', namespace: _w) == '1'),
      hasLength(count),
      reason: '$part $tag',
    );
  }
  final comments = archive.findFile('word/comments.xml');
  if (active) expect(comments, isNotNull);
  if (comments != null) {
    final xml = XmlDocument.parse(utf8.decode(comments.content));
    expect(
      xml
          .findAllElements('comment', namespace: _w)
          .where((node) => node.getAttribute('id', namespace: _w) == '1'),
      hasLength(expectedReferences),
    );
  }
}
