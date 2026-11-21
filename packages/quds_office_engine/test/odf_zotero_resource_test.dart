import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';

String _name(int identity, {bool bibliography = false}) {
  final suffix = identity.toRadixString(36).padLeft(10, '0');
  if (bibliography) {
    return 'ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]}'
        ' CSL_BIBLIOGRAPHY RND$suffix';
  }
  return 'ZOTERO_ITEM CSL_CITATION ${jsonEncode(<String, Object?>{
    'citationID': 'citation-$identity',
    'citationItems': <Map<String, Object?>>[
      <String, Object?>{'id': identity},
    ],
  })} RND$suffix';
}

String _start(String name) =>
    '<text:reference-mark-start text:name="${encodeXmlAttribute(name)}"/>';

String _end(String name) =>
    '<text:reference-mark-end text:name="${encodeXmlAttribute(name)}"/>';

String _mark(String name, String text) =>
    '${_start(name)}${encodeXmlText(text)}${_end(name)}';

String _paragraph(String contents) => '<text:p>$contents</text:p>';

String _section(String name, String contents) =>
    '<text:section text:name="${encodeXmlAttribute(name)}">'
    '$contents</text:section>';

Uint8List _package(String body) {
  final writer = ZipWriter();
  writer.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  writer.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content xmlns:office="$_office" xmlns:text="$_text" '
      'xmlns:table="$_table" xmlns:style="$_style">'
      '<office:body><office:text>$body</office:text></office:body>'
      '</office:document-content>',
    ),
  );
  return writer.close();
}

void main() {
  test(
    'empty sections do not spend range work scanning unrelated paragraphs',
    () async {
      final body = StringBuffer();
      for (var index = 0; index < 24; index++) {
        for (var paragraph = 0; paragraph < 50; paragraph++) {
          body.write(_paragraph('Unrelated $index/$paragraph'));
        }
        body.write(_section(_name(index, bibliography: true), ''));
      }
      final inventory = await OdfZotero.inspect(
        _package(body.toString()),
        limits: const OdfZoteroLimits(maxRangeWork: 1, maxFieldRanges: 1),
      );
      expect(inventory.paragraphCount, 1200);
      expect(inventory.fields, hasLength(24));
      for (final field in inventory.fields) {
        expect(field.ranges, isEmpty);
        expect(field.isValid, isTrue);
        expect(field.isImportCandidate, isFalse);
        expect(
          field.issues.map((issue) => issue.code),
          contains(OdfZoteroIssueCode.emptySection),
        );
      }
    },
  );

  test(
    'section paragraphs exactly meet cumulative work and output caps',
    () async {
      final bytes = _package(
        _section(
              _name(1, bibliography: true),
              '${_paragraph('First')}${_paragraph('Second')}',
            ) +
            _paragraph('Unrelated') +
            _section(_name(2, bibliography: true), _paragraph('Third')),
      );
      final inventory = await OdfZotero.inspect(
        bytes,
        limits: const OdfZoteroLimits(maxRangeWork: 3, maxFieldRanges: 3),
      );
      expect(inventory.fields.map((field) => field.cachedText), [
        'First\nSecond',
        'Third',
      ]);
      expect(
        inventory.fields.every((field) => field.isImportCandidate),
        isTrue,
      );
      expect(inventory.fields.expand((field) => field.ranges), hasLength(3));
    },
  );

  for (final workLimit in [true, false]) {
    test(
      'section paragraphs fail one beyond the ${workLimit ? 'work' : 'output'} cap',
      () async {
        final bytes = _package(
          _section(
                _name(1, bibliography: true),
                '${_paragraph('First')}${_paragraph('Second')}',
              ) +
              _section(_name(2, bibliography: true), _paragraph('Third')),
        );
        await expectLater(
          OdfZotero.inspect(
            bytes,
            limits: OdfZoteroLimits(
              maxRangeWork: workLimit ? 2 : 3,
              maxFieldRanges: workLimit ? 3 : 2,
            ),
          ),
          throwsA(isA<OdfZoteroLimitException>()),
        );
      },
    );
  }

  test(
    'reference marks each consume work even in one shared paragraph',
    () async {
      final bytes = _package(
        _paragraph('${_mark(_name(1), 'A')} ${_mark(_name(2), 'B')}'),
      );
      final inventory = await OdfZotero.inspect(
        bytes,
        limits: const OdfZoteroLimits(maxRangeWork: 2, maxFieldRanges: 2),
      );
      expect(inventory.fields.map((field) => field.cachedText), ['A', 'B']);
      expect(
        inventory.fields.every((field) => field.isImportCandidate),
        isTrue,
      );
      await expectLater(
        OdfZotero.inspect(
          bytes,
          limits: const OdfZoteroLimits(maxRangeWork: 1, maxFieldRanges: 2),
        ),
        throwsA(isA<OdfZoteroLimitException>()),
      );
      await expectLater(
        OdfZotero.inspect(
          bytes,
          limits: const OdfZoteroLimits(maxRangeWork: 2, maxFieldRanges: 1),
        ),
        throwsA(isA<OdfZoteroLimitException>()),
      );
    },
  );

  test(
    'nested empty sections account for every retained ownership range',
    () async {
      final bytes = _package(
        _section(
          _name(1, bibliography: true),
          _section(
            _name(2, bibliography: true),
            _section(_name(3, bibliography: true), _paragraph('')),
          ),
        ),
      );
      final inventory = await OdfZotero.inspect(
        bytes,
        limits: const OdfZoteroLimits(maxRangeWork: 3, maxFieldRanges: 3),
      );
      expect(inventory.paragraphCount, 1);
      expect(inventory.fields, hasLength(3));
      expect(
        inventory.fields.every((field) => !field.isImportCandidate),
        isTrue,
      );
      for (final field in inventory.fields) {
        expect(field.cachedText, '');
        expect(field.ranges, hasLength(1));
        expect(field.ranges.single.start, 0);
        expect(field.ranges.single.end, 0);
      }
      await expectLater(
        OdfZotero.inspect(
          bytes,
          limits: const OdfZoteroLimits(maxRangeWork: 2, maxFieldRanges: 3),
        ),
        throwsA(isA<OdfZoteroLimitException>()),
      );
      await expectLater(
        OdfZotero.inspect(
          bytes,
          limits: const OdfZoteroLimits(maxRangeWork: 3, maxFieldRanges: 2),
        ),
        throwsA(isA<OdfZoteroLimitException>()),
      );
    },
  );

  test(
    'overlapping zero-text marks cannot evade work or range-object caps',
    () async {
      final first = _name(1);
      final second = _name(2);
      final third = _name(3);
      final bytes = _package(
        _paragraph(
          '${_start(first)}${_start(second)}${_start(third)}'
          '${_end(second)}${_end(first)}${_end(third)}',
        ),
      );
      final inventory = await OdfZotero.inspect(
        bytes,
        limits: const OdfZoteroLimits(maxRangeWork: 3, maxFieldRanges: 3),
      );
      expect(inventory.fields, hasLength(3));
      for (final field in inventory.fields) {
        expect(field.cachedText, '');
        expect(field.ranges, hasLength(1));
        expect(field.isImportCandidate, isFalse);
        expect(
          field.issues.map((issue) => issue.code),
          contains(OdfZoteroIssueCode.overlappingFields),
        );
      }
      await expectLater(
        OdfZotero.inspect(
          bytes,
          limits: const OdfZoteroLimits(maxRangeWork: 2, maxFieldRanges: 3),
        ),
        throwsA(isA<OdfZoteroLimitException>()),
      );
      await expectLater(
        OdfZotero.inspect(
          bytes,
          limits: const OdfZoteroLimits(maxRangeWork: 3, maxFieldRanges: 2),
        ),
        throwsA(isA<OdfZoteroLimitException>()),
      );
    },
  );

  for (final owner in <({String prefix, String localName, String namespace})>[
    (prefix: 'table', localName: 'table-template', namespace: _table),
    (prefix: 'style', localName: 'style', namespace: _style),
  ]) {
    test(
      '${owner.prefix}:${owner.localName} remains an unsupported owner',
      () async {
        final tag = '${owner.prefix}:${owner.localName}';
        final inventory = await OdfZotero.inspect(
          _package('<$tag>${_paragraph(_mark(_name(1), 'Evidence'))}</$tag>'),
        );
        final field = inventory.fields.single;
        expect(field.isValid, isTrue);
        expect(field.isImportCandidate, isFalse);
        expect(field.cachedText, 'Evidence');
        expect(
          field.issues.map((issue) => issue.code),
          contains(OdfZoteroIssueCode.unsupportedContent),
        );
        final recordedOwner = field.starts.single.owners.last;
        expect(recordedOwner.namespaceUri, owner.namespace);
        expect(recordedOwner.localName, owner.localName);
        expect(field.ends.single.owners.last.path, recordedOwner.path);
      },
    );
  }

  for (final limit in <OdfZoteroLimits>[
    const OdfZoteroLimits(maxRangeWork: 0),
    const OdfZoteroLimits(maxRangeWork: -1),
    const OdfZoteroLimits(maxFieldRanges: 0),
    const OdfZoteroLimits(maxFieldRanges: -1),
  ]) {
    test('invalid range limits fail before producing an inventory '
        '${limit.maxRangeWork}/${limit.maxFieldRanges}', () async {
      await expectLater(
        OdfZotero.inspect(_package(_paragraph('Plain')), limits: limit),
        throwsArgumentError,
      );
    });
  }
}
