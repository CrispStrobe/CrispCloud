// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _w14 = 'http://schemas.microsoft.com/office/word/2010/wordml';
const _w15 = 'http://schemas.microsoft.com/office/word/2012/wordml';
const _r = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _date = 45 | (8 << 6) | (12 << 11) | (11 << 16) | (126 << 20);
List<int> _record({int depth = 0, int parent = 0, int flags = 0}) => [
  ...wordU32(_date),
  ...wordU16(0),
  ...wordU32(depth),
  ...wordU32(parent),
  ...wordU32(flags),
];
Uint8List _source({
  List<int>? records,
  bool ink = false,
  bool privateParent = false,
}) {
  final main = privateParent
      ? 'A\x13 REF X\x14\x05\x15B\x05C\r'
      : 'A\x05B\x05C\r';
  const parent = '\x05Parent first\rSecond\r', reply = '\x05Reply\r';
  final markers = [
    main.indexOf('\x13'),
    main.indexOf('\x14'),
    main.indexOf('\x15'),
  ];
  return storyWordFixture(
    main: main,
    comments: '$parent$reply\r',
    tablePairs: {
      4: storyPlc(
        [main.indexOf('\x05'), main.lastIndexOf('\x05'), 0xffffffff],
        [
          ...storyCommentRecord(),
          ...storyCommentRecord(initials: 'CD', author: 1),
        ],
      ),
      5: storyPlc([0, parent.length, parent.length + reply.length, 0xffffffff]),
      36: [...storyXst('Alice'), ...storyXst('Bob')],
      112:
          records ??
          [..._record(), ..._record(depth: 1, parent: -1, flags: ink ? 2 : 0)],
      if (privateParent)
        16: storyPlc([...markers, 0xffffffff], [0x13, 0, 0x14, 0, 0x15, 0xa0]),
    },
    mutate: (fib, _) {
      fib.setUint16(2, 0x101, Endian.little);
      fib.setUint16(152, 136, Endian.little);
    },
  );
}

Map<String, Uint8List> _parts(Uint8List bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes))
    if (file.isFile) file.name: file.content,
};
XmlDocument _xml(Map<String, Uint8List> files, String name) =>
    XmlDocument.parse(utf8.decode(files[name]!));
Iterable<XmlElement> _elements(XmlNode node, String name, [String ns = _w]) =>
    node.findAllElements(name, namespace: ns);
String? _attr(XmlElement node, String name, [String ns = _w]) =>
    node.getAttribute(name, namespace: ns);
LegacyWordCommentReference _reference(
  LegacyWordCommentReference old, {
  int? id,
  int? parent,
}) => LegacyWordCommentReference(
  id: id ?? old.id,
  anchorCp: old.anchorCp,
  storyId: old.storyId,
  rangeStartCp: old.rangeStartCp,
  rangeEndCp: old.rangeEndCp,
  author: old.author,
  initials: old.initials,
  time: old.time,
  parentId: parent,
  ink: old.ink,
  sourceRecord: old.sourceRecord,
  presentation: old.presentation,
);
LegacyWordDocument _copy(
  LegacyWordDocument old,
  List<LegacyWordCommentReference> comments,
) => LegacyWordDocument(
  blocks: old.blocks,
  sections: old.sections,
  plainText: old.plainText,
  safeHtml: old.safeHtml,
  stories: old.stories,
  fields: old.fields,
  commentReferences: comments,
  media: old.media,
);

void main() {
  test(
    'ATRDExtra links author/time/reply and keeps byte-exact immutable records',
    () {
      final original = _source(ink: true);
      final before = Uint8List.fromList(original);
      final document = parseLegacyWordDocument(original);
      final root = document.commentReferences.first,
          reply = document.commentReferences.last;
      expect(root.parentId, isNull);
      expect(reply.parentId, root.id);
      expect(reply.author, 'Bob');
      expect(reply.time, DateTime.utc(2026, 11, 12, 8, 45));
      expect(reply.ink, isTrue);
      final record = reply.sourceRecord!;
      expect(record.bytes, _record(depth: 1, parent: -1, flags: 2));
      expect(record.depth, 1);
      expect(record.relativeParent, -1);
      expect(record.rawDate, _date);
      expect(record.tableOffset, root.sourceRecord!.tableOffset + 18);
      expect(() => record.bytes[0] = 0, throwsUnsupportedError);
      expect(original, before);
    },
  );

  test(
    'native comment threads join the last paragraph of a multi-paragraph parent',
    () {
      final result = convertLegacyWord(_source());
      final files = _parts(result.bytes);
      final comments = _xml(files, 'word/comments.xml');
      final rows = _elements(comments, 'comment').toList();
      expect(rows, hasLength(2));
      final parentParagraphs = _elements(rows.first, 'p').toList();
      expect(parentParagraphs, hasLength(2));
      final firstId = _attr(parentParagraphs.first, 'paraId', _w14);
      final lastId = _attr(parentParagraphs.last, 'paraId', _w14);
      expect(lastId, matches(RegExp(r'^[0-9A-F]{8}$')));
      expect(firstId, isNot(lastId));
      final replyId = _attr(_elements(rows.last, 'p').last, 'paraId', _w14);
      final extended = _xml(files, 'word/commentsExtended.xml');
      final joins = _elements(extended, 'commentEx', _w15).toList();
      expect(joins, hasLength(2));
      final reply = joins.singleWhere(
        (e) => _attr(e, 'paraId', _w15) == replyId,
      );
      expect(_attr(reply, 'paraIdParent', _w15), lastId);
      expect(
        joins.every((e) => _attr(e, 'done', _w15) == null),
        isTrue,
        reason: 'binary source has no resolved flag',
      );
      expect(_elements(rows.first, 't').map((e) => e.innerText), [
        'Parent first',
        'Second',
      ]);
      expect(_elements(rows.last, 't').single.innerText, 'Reply');
      expect(result.preservedCounts['commentReplies'], 1);
      final types = _xml(files, '[Content_Types].xml');
      final contentType = types.rootElement.childElements.singleWhere(
        (node) => node.getAttribute('PartName') == '/word/commentsExtended.xml',
      );
      expect(
        contentType.getAttribute('ContentType'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.commentsExtended+xml',
      );
      final relationships = _xml(files, 'word/_rels/document.xml.rels');
      final relation = _elements(relationships, 'Relationship', _r).singleWhere(
        (node) =>
            node.getAttribute('Type') ==
            'http://schemas.microsoft.com/office/2011/relationships/commentsExtended',
      );
      expect(relation.getAttribute('Target'), 'commentsExtended.xml');
      expect(relation.getAttribute('TargetMode'), isNull);
    },
  );

  test('public-model writer accepts a reply listed before its parent', () {
    final document = parseLegacyWordDocument(_source());
    final reordered = _copy(document, [
      _reference(document.commentReferences.last, id: 7, parent: 42),
      _reference(document.commentReferences.first, id: 42),
    ]);
    final files = _parts(convertLegacyWordDocument(reordered).bytes);
    final comments = _elements(_xml(files, 'word/comments.xml'), 'comment');
    final byId = {
      for (final c in comments)
        _attr(c, 'id'): _attr(_elements(c, 'p').last, 'paraId', _w14),
    };
    final joins = _elements(
      _xml(files, 'word/commentsExtended.xml'),
      'commentEx',
      _w15,
    );
    final reply = joins.singleWhere(
      (e) => _attr(e, 'paraId', _w15) == byId['7'],
    );
    expect(_attr(reply, 'paraIdParent', _w15), byId['42']);
    expect(byId.values.toSet(), hasLength(2));
  });

  test('table-ending comments join the generated final paragraph', () {
    final document = parseLegacyWordDocument(_source());
    final original = document.stories.first;
    final table = LegacyWordTable(
      startCp: original.startCp,
      endCp: original.endCp,
      rows: [
        LegacyWordTableRow(
          cells: [
            LegacyWordTableCell(
              paragraphs: original.blocks.cast<LegacyWordParagraph>(),
            ),
          ],
        ),
      ],
    );
    final rich = LegacyWordDocument(
      blocks: document.blocks,
      sections: document.sections,
      plainText: document.plainText,
      safeHtml: document.safeHtml,
      commentReferences: document.commentReferences,
      stories: [
        LegacyWordStory(
          id: original.id,
          kind: original.kind,
          startCp: original.startCp,
          endCp: original.endCp,
          blocks: [table],
          plainText: original.plainText,
          safeHtml: original.safeHtml,
        ),
        ...document.stories.skip(1),
      ],
    );
    final files = _parts(convertLegacyWordDocument(rich).bytes);
    final root = _elements(_xml(files, 'word/comments.xml'), 'comment').first;
    final finalParagraph = root.childElements.last;
    expect(finalParagraph.name.local, 'p');
    expect(finalParagraph.childElements, isEmpty);
    final finalId = _attr(finalParagraph, 'paraId', _w14);
    expect(finalId, isNotNull);
    final joins = _elements(
      _xml(files, 'word/commentsExtended.xml'),
      'commentEx',
      _w15,
    );
    expect(_attr(joins.last, 'paraIdParent', _w15), finalId);
  });

  test(
    'ink flag and source record remain evidence without invented ink markup',
    () {
      final files = _parts(convertLegacyWord(_source(ink: true)).bytes);
      final manifest =
          jsonDecode(utf8.decode(files['word/evidence/manifest.json']!)) as Map;
      final records = (manifest['records'] as List).cast<Map>();
      final ink = records.singleWhere((entry) => entry['kind'] == 'inkComment');
      expect(ink['commentId'], 1);
      final binary = records.singleWhere(
        (entry) => entry['kind'] == 'commentRecord' && entry['commentId'] == 1,
      );
      expect(files[binary['part']], _record(depth: 1, parent: -1, flags: 2));
      expect(
        _xml(files, 'word/comments.xml').findAllElements('ink', namespace: '*'),
        isEmpty,
      );
    },
  );

  test('a private parent keeps the entire reply branch inert', () {
    final document = parseLegacyWordDocument(_source(privateParent: true));
    expect(document.commentReferences.first.presentation.hidden, isTrue);
    expect(document.commentReferences.last.presentation.hidden, isFalse);
    final files = _parts(convertLegacyWordDocument(document).bytes);
    expect(files, isNot(contains('word/comments.xml')));
    expect(files, isNot(contains('word/commentsExtended.xml')));
    final main = _xml(files, 'word/document.xml');
    expect(_elements(main, 'commentReference'), isEmpty);
    expect(_elements(main, 't').map((e) => e.innerText).join(), 'ABC');
    final manifest = utf8.decode(files['word/evidence/manifest.json']!);
    expect(manifest, contains('inertStory'));
  });

  test(
    'rejects truncated, cyclic, wrong-depth and non-preorder binary threads',
    () {
      for (final records in [
        [..._record(), ..._record().take(17)],
        [..._record(), ..._record(depth: 1, parent: 0)],
        [..._record(), ..._record(depth: 2, parent: -1)],
        [..._record(depth: 1, parent: 1), ..._record()],
        [..._record(), ..._record(depth: 65, parent: -1)],
      ]) {
        expect(
          () => parseLegacyWordDocument(_source(records: records)),
          throwsFormatException,
        );
      }
    },
  );

  test('public-model thread validation rejects cycles and missing parents', () {
    final original = parseLegacyWordDocument(_source());
    for (final parent in [1, 999]) {
      final invalid = _copy(original, [
        _reference(original.commentReferences.first, parent: parent),
        _reference(original.commentReferences.last, parent: 0),
      ]);
      expect(() => convertLegacyWordDocument(invalid), throwsFormatException);
    }
  });
}
