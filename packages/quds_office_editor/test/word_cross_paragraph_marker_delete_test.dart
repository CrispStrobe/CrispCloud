// A delete across paragraph boundaries keeps paired markers consistent.
//
// Removing whole paragraphs used to drop the bookmark endpoints they carried,
// so a range cut by the deletion kept one half; the next full relayout or
// save then failed ("Bookmark end … has no matching start"). Word's rule: a
// range wholly inside the deletion goes, a range with one endpoint inside is
// kept and clamped to the remaining content.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const String _bookmarkCopy =
    '../quds_office_engine/test/fixtures/fidelity/bookmark_copy_expected.docx';
const String _attachments =
    '../legacy_doc_parser/test/fixtures/external/poi-20261114/poi/docx/'
    'WordWithAttachments.docx';

List<WmlParagraph> _paras(WordEditorController c) =>
    c.document.paragraphs.toList();

WordEditorController _open(String path) {
  final c = WordEditorController.fromBytes(File(path).readAsBytesSync());
  addTearDown(c.dispose);
  return c;
}

void _select(WordEditorController c, int p0, int o0, int p1, int o1) {
  c.caret
    ..selectionAnchorParagraph = p0
    ..selectionAnchor = o0
    ..paragraphIndex = p1
    ..logicalIndex = o1;
}

/// Name → selected text of every native range; throws on an orphan.
Map<String, String> _ranges(WmlDocument document) => <String, String>{
  for (final WmlBookmarkRange r in WordBookmarks.ranges(document))
    r.name: r.text,
};

/// The saved main part pairs every bookmark endpoint by id, each start
/// before its end, and reads back to the same ranges. With [comments], every
/// comment range end also closes an open start (the serializer writes a
/// range spanning paragraphs as one start/end pair per paragraph).
void _expectValidSave(WordEditorController c, {bool comments = false}) {
  final Map<String, String> before = _ranges(c.document);
  final bytes = c.saveBytes();
  final root = XmlDocument.parse(
    OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
  ).root!;
  for (final (String start, String end, bool unique)
      in <(String, String, bool)>[
        ('bookmarkStart', 'bookmarkEnd', true),
        if (comments) ('commentRangeStart', 'commentRangeEnd', false),
      ]) {
    final Set<String> open = <String>{};
    final Set<String> seen = <String>{};
    void walk(XmlElement e) {
      for (final XmlElement child in e.childElements) {
        if (child.namespaceUri == OfficeNamespaces.w &&
            (child.localName == start || child.localName == end)) {
          final String id = child.getAttribute('id')!;
          if (child.localName == start) {
            expect(open.add(id), isTrue, reason: '$start $id while open');
            if (unique) {
              expect(seen.add(id), isTrue, reason: '$start $id twice');
            }
          } else {
            expect(open.remove(id), isTrue, reason: '$end $id unmatched');
          }
        }
        walk(child);
      }
    }

    walk(root);
    expect(open, isEmpty, reason: '$start without $end');
  }
  final reopened = WordEditorController.fromBytes(bytes);
  addTearDown(reopened.dispose);
  expect(_ranges(reopened.document), before);
}

void main() {
  test('bookmark_copy_expected: a deletion removing a paragraph with '
      'endpoints clamps the cut ranges and drops the enclosed one', () {
    final c = _open(_bookmarkCopy);
    final Map<String, String> original = _ranges(c.document);
    final List<WmlParagraph> paras = _paras(c);
    // ¶3 holds start 3, start 4, end 3, start 8; ends 4 and 8 are in ¶4.
    final List<String> inThird = <String>[
      for (final WmlInline x in paras[3].inlines)
        if (x is WmlBookmarkBoundary) '${x.isStart ? 'S' : 'E'}${x.id}',
    ];
    expect(inThird, <String>['S3', 'S4', 'E3', 'S8']);
    final String name3 = WordBookmarks.ranges(
      c.document,
    ).firstWhere((r) => r.start.id == '3').name;
    final String name4 = WordBookmarks.ranges(
      c.document,
    ).firstWhere((r) => r.start.id == '4').name;
    final String name8 = WordBookmarks.ranges(
      c.document,
    ).firstWhere((r) => r.start.id == '8').name;

    final int cut2 = paras[2].text.length ~/ 2;
    final int cut4 = paras[4].text.length ~/ 3;
    final String kept4 = paras[4].text.substring(cut4);
    _select(c, 2, cut2, 4, cut4);
    c.deleteSelectionOr(backward: true);

    final Map<String, String> after = _ranges(c.document);
    expect(after.containsKey(name3), isFalse, reason: 'wholly inside');
    // Clamped: the range now starts at the deletion point (end of ¶2) and
    // still ends where it ended in the old ¶4.
    for (final String name in <String>[name4, name8]) {
      final WmlBookmarkRange r = WordBookmarks.byName(c.document, name)!;
      expect(identical(r.startParagraph, _paras(c)[2]), isTrue);
      expect(r.startOffset, cut2);
      expect(r.text.startsWith('\n'), isTrue);
      expect(kept4.startsWith(r.text.substring(1)), isTrue);
    }
    // Ranges outside the deletion are unchanged.
    for (final String name in original.keys) {
      if (<String>{name3, name4, name8}.contains(name)) continue;
      final WmlBookmarkRange r = WordBookmarks.byName(c.document, name)!;
      if (identical(r.startParagraph, _paras(c)[2])) continue;
      expect(after[name], original[name], reason: name);
    }
    _expectValidSave(c);

    // A full relayout (the path that used to reject the model) and undo.
    c.applyRunFormat((WmlRunProps p) => p.bold = true);
    c.undo();
    c.undo();
    expect(_ranges(c.document), original);
    c.redo();
    expect(_ranges(c.document).containsKey(name3), isFalse);
    _expectValidSave(c);
  });

  test('bookmark_copy_expected: ends removed with a paragraph clamp to the '
      'end of the paragraph the deletion started in', () {
    final c = _open(_bookmarkCopy);
    // ¶1 holds end 5, start 7, end 7, end 6; starts 5 and 6 are in ¶0.
    final int cut0 = _paras(c)[0].text.length - 2;
    _select(c, 0, cut0, 2, 3);
    c.deleteSelectionOr(backward: false);
    final List<WmlBookmarkRange> ranges = WordBookmarks.ranges(c.document);
    expect(ranges.where((r) => r.start.id == '7'), isEmpty);
    for (final String id in <String>['5', '6']) {
      final WmlBookmarkRange r = ranges.firstWhere((r) => r.start.id == id);
      expect(identical(r.endParagraph, _paras(c)[0]), isTrue);
      expect(r.endOffset, cut0);
    }
    _expectValidSave(c);
  });

  test('WordWithAttachments: a start removed with its paragraph clamps to '
      'the deletion point', () {
    final c = _open(_attachments);
    final WmlBookmarkRange before = WordBookmarks.ranges(
      c.document,
    ).firstWhere((r) => r.start.id == '1');
    expect(before.text, 'English\n');
    final List<WmlParagraph> paras = _paras(c);
    final int cut1 = paras[1].text.length ~/ 2;
    _select(c, 1, cut1, 3, 2);
    c.deleteSelectionOr(backward: true);
    final WmlBookmarkRange after = WordBookmarks.byName(
      c.document,
      before.name,
    )!;
    expect(identical(after.startParagraph, _paras(c)[1]), isTrue);
    expect(after.startOffset, cut1);
    expect(after.text, '\n');
    _expectValidSave(c);
  });

  test('a deletion containing a whole range removes both halves', () {
    final c = _open(_attachments);
    final String name = WordBookmarks.ranges(
      c.document,
    ).firstWhere((r) => r.start.id == '1').name;
    _select(c, 1, 1, 4, 2);
    c.deleteSelectionOr(backward: true);
    expect(WordBookmarks.byName(c.document, name), isNull);
    expect(
      WordBookmarks.boundariesIn(
        _paras(c),
      ).where((m) => m.id == '1' || m.id == '2'),
      isEmpty,
    );
    _expectValidSave(c);
  });

  WordEditorController synthetic() {
    WmlRun r(String text, {bool comment = false}) =>
        WmlRun(text: text, commentIds: comment ? <int>[0] : null);
    WmlBookmarkBoundary start(String id, String name) =>
        WmlBookmarkBoundary(id: id, isStart: true, name: name);
    WmlBookmarkBoundary end(String id) =>
        WmlBookmarkBoundary(id: id, isStart: false);
    final document = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[r('Erster Absatz ')]),
            WmlParagraph(
              inlines: <WmlInline>[
                r('Zweiter '),
                start('1', 'Cut'),
                r('Absatz'),
                r(' Kommentar', comment: true),
              ],
            ),
            WmlParagraph(
              inlines: <WmlInline>[
                r('Dritter ', comment: true),
                start('2', 'Inside'),
                r('Absatz', comment: true),
                end('2'),
              ],
            ),
            WmlTable(
              grid: <double>[200],
              rows: <WmlTableRow>[
                WmlTableRow(
                  cells: <WmlTableCell>[
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[
                            start('3', 'TableCut'),
                            r('Zelle', comment: true),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            WmlParagraph(
              inlines: <WmlInline>[
                r('Vierter ', comment: true),
                end('1'),
                r('Absatz', comment: true),
                end('3'),
                r(' Ende'),
              ],
            ),
            WmlParagraph(inlines: <WmlInline>[r('Letzter Absatz')]),
          ],
        ),
      ],
    );
    document.comments.add(WmlComment(id: 0, text: 'Notiz'));
    final c = WordEditorController(document: document);
    addTearDown(c.dispose);
    return c;
  }

  test('ranges cut by a deleted table are clamped; undo restores them', () {
    final c = synthetic();
    final Map<String, String> original = _ranges(c.document);
    expect(original['TableCut'], 'Zelle\nVierter Absatz');
    expect(
      original['Cut'],
      'Absatz Kommentar\nDritter Absatz\nZelle\nVierter ',
    );
    final WmlTable table = c.document.sections.first.blocks
        .whereType<WmlTable>()
        .single;
    c.deleteTable(table: table);
    final WmlBookmarkRange r = WordBookmarks.byName(c.document, 'TableCut')!;
    expect(r.startOffset, 0);
    expect(r.text, 'Vierter Absatz');
    expect(
      _ranges(c.document)['Cut'],
      'Absatz Kommentar\nDritter Absatz\nVierter ',
    );
    _expectValidSave(c, comments: true);
    c.undo();
    expect(_ranges(c.document), original);
  });

  test(
    'comment ranges and bookmarks stay paired across a structured delete',
    () {
      final c = synthetic();
      // From inside "Zweiter" to inside "Vierter": ¶2 and the table go.
      _select(c, 1, 3, 4, 3);
      c.deleteSelectionOr(backward: true);
      final Map<String, String> after = _ranges(c.document);
      expect(after.containsKey('Inside'), isFalse);
      expect(after['Cut'], '\nrter ');
      expect(after['TableCut'], '\nrter Absatz');
      expect(_paras(c)[1].text, 'Zwe');
      final WmlComment comment = c.document.comments.single;
      final List<WmlRun> anchored = <WmlRun>[
        for (final WmlParagraph p in _paras(c))
          ...p.inlines.whereType<WmlRun>().where(
            (run) => run.commentIds.contains(comment.id),
          ),
      ];
      expect(anchored.map((run) => run.text).join(), 'rter Absatz');
      _expectValidSave(c, comments: true);
    },
  );

  test('a cross-paragraph delete inside a header clamps cut ranges', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final c = synthetic();
    final WmlSection section = c.document.sections.first;
    section.header
      ..clear()
      ..addAll(<WmlParagraph>[
        WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Kopf eins')]),
        WmlParagraph(
          inlines: <WmlInline>[
            WmlBookmarkBoundary(id: '20', isStart: true, name: 'Head'),
            WmlRun(text: 'Kopf zwei'),
          ],
        ),
        WmlParagraph(
          inlines: <WmlInline>[
            WmlRun(text: 'Kopf drei'),
            WmlBookmarkBoundary(id: '20', isStart: false),
          ],
        ),
      ]);
    c.refresh();
    c.beginHeaderFooterEdit(0, footer: false);
    _select(c, 0, 4, 2, 4);
    c.deleteSelectionOr(backward: true);
    c.endHeaderFooterEdit();
    expect(section.header, hasLength(1));
    expect(section.header.single.text, 'Kopf drei');
    final WmlBookmarkRange r = WordBookmarks.byName(c.document, 'Head')!;
    expect(r.startOffset, 4);
    expect(r.text, ' drei');
    _expectValidSave(c);
  });
}
