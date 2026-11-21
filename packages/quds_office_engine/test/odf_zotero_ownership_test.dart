import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';

String _escape(String value) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

String _name(String identity, {bool bibliography = false}) {
  final code = bibliography
      ? 'BIBL {} CSL_BIBLIOGRAPHY'
      : 'ITEM CSL_CITATION ${jsonEncode({
          'citationID': identity,
          'citationItems': [
            {'id': identity},
          ],
          'properties': <String, Object?>{},
        })}';
  return 'ZOTERO_$code RND${identity.padRight(10, '0').substring(0, 10)}';
}

String _start(String name) =>
    '<text:reference-mark-start text:name="${_escape(name)}"/>';

String _end(String name) =>
    '<text:reference-mark-end text:name="${_escape(name)}"/>';

String _mark(String name, String text) => '${_start(name)}$text${_end(name)}';

String _paragraph(String content) => '<text:p>$content</text:p>';

String _note(String content, {String kind = 'footnote'}) =>
    '<text:note text:note-class="$kind"><text:note-citation>1</text:note-citation>'
    '<text:note-body>$content</text:note-body></text:note>';

String _section(String name, String body, {String attributes = ''}) =>
    '<text:section text:name="${_escape(name)}" $attributes>'
    '$body</text:section>';

String _cell(String body, {String attributes = ''}) =>
    '<table:table-cell $attributes>$body</table:table-cell>';

String _tableWithCells(String cells) =>
    '<table:table><table:table-row>$cells</table:table-row></table:table>';

String _namespaces() =>
    'xmlns:office="$_office" xmlns:text="$_text" xmlns:t="$_text" '
    'xmlns:table="$_table" xmlns:draw="$_draw" xmlns:style="$_style" '
    'xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:foreign="urn:foreign"';

Uint8List _package(String body, {String? styles}) {
  final writer = ZipWriter();
  writer.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  writer.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content ${_namespaces()}>'
      '<office:body><office:text>$body</office:text></office:body>'
      '</office:document-content>',
    ),
  );
  if (styles != null) {
    writer.addFile(
      'styles.xml',
      utf8.encode(
        '<office:document-styles ${_namespaces()}>'
        '<office:master-styles><style:master-page style:name="Default">'
        '$styles</style:master-page></office:master-styles>'
        '</office:document-styles>',
      ),
    );
  }
  return writer.close();
}

Set<OdfZoteroIssueCode> _codes(OdfZoteroField field) =>
    field.issues.map((issue) => issue.code).toSet();

void _ineligible(OdfZoteroField field, OdfZoteroIssueCode reason) {
  expect(
    field.isValid,
    isTrue,
    reason: 'Metadata remains valid: ${field.name}',
  );
  expect(field.isImportCandidate, isFalse);
  expect(_codes(field), contains(reason));
}

void main() {
  group('native ODT Zotero endpoint ambiguity', () {
    test(
      'missing endpoints remain valid metadata with no invented range',
      () async {
        final first = _name('missingEnd');
        final second = _name('missingBeg');
        final inventory = await OdfZotero.inspect(
          _package(_paragraph('${_start(first)}One${_end(second)}')),
        );
        expect(inventory.fields, hasLength(2));
        _ineligible(inventory.fields[0], OdfZoteroIssueCode.missingEnd);
        _ineligible(inventory.fields[1], OdfZoteroIssueCode.missingStart);
        expect(inventory.fields.every((field) => field.ranges.isEmpty), isTrue);
      },
    );

    test(
      'reused name preserves all endpoints without choosing a pair',
      () async {
        final name = _name('duplicate');
        final inventory = await OdfZotero.inspect(
          _package(_paragraph('${_mark(name, 'One')} ${_mark(name, 'Two')}')),
        );
        final field = inventory.fields.single;
        _ineligible(field, OdfZoteroIssueCode.duplicateName);
        expect(
          _codes(field),
          containsAll([
            OdfZoteroIssueCode.duplicateStart,
            OdfZoteroIssueCode.duplicateEnd,
          ]),
        );
        expect(field.starts, hasLength(2));
        expect(field.ends, hasLength(2));
        expect(field.ranges, isEmpty);
      },
    );

    test(
      'same name in body and authored note is not paired by convenience',
      () async {
        final name = _name('sameName');
        final inventory = await OdfZotero.inspect(
          _package(
            _paragraph(
              '${_mark(name, 'Body')}${_note(_paragraph(_mark(name, 'Note')))}',
            ),
          ),
        );
        final field = inventory.fields.single;
        _ineligible(field, OdfZoteroIssueCode.duplicateName);
        expect(field.starts.map((location) => location.story), [
          OdfZoteroStory.body,
          OdfZoteroStory.footnote,
        ]);
        expect(field.ranges, isEmpty);
      },
    );

    test(
      'duplicate names across content and styles retain separate part identities',
      () async {
        final name = _name('parts');
        final inventory = await OdfZotero.inspect(
          _package(
            _paragraph(_mark(name, 'Body')),
            styles:
                '<style:header>${_paragraph(_mark(name, 'Header'))}</style:header>',
          ),
        );
        expect(inventory.fields, hasLength(2));
        for (final field in inventory.fields) {
          _ineligible(field, OdfZoteroIssueCode.duplicateName);
        }
        expect(inventory.fields.map((field) => field.starts.single.part), [
          'content.xml',
          'styles.xml',
        ]);
        expect(
          inventory.fields.last.starts.single.story,
          OdfZoteroStory.header,
        );
        expect(
          _codes(inventory.fields.last),
          contains(OdfZoteroIssueCode.unsupportedStory),
        );
      },
    );

    test('end before start never becomes a positive range', () async {
      final name = _name('reverse');
      final field = (await OdfZotero.inspect(
        _package(_paragraph('${_end(name)}Text${_start(name)}')),
      )).fields.single;
      _ineligible(field, OdfZoteroIssueCode.reversedRange);
      expect(field.ranges, isEmpty);
    });

    for (final nested in [false, true]) {
      test(
        '${nested ? 'nested' : 'crossed'} fields guard both owners',
        () async {
          final first = _name('first');
          final second = _name('second');
          final endings = nested
              ? '${_end(second)}C${_end(first)}'
              : '${_end(first)}C${_end(second)}';
          final fields = (await OdfZotero.inspect(
            _package(_paragraph('${_start(first)}A${_start(second)}B$endings')),
          )).fields;
          expect(fields, hasLength(2));
          for (final field in fields) {
            _ineligible(
              field,
              nested
                  ? OdfZoteroIssueCode.nestedRange
                  : OdfZoteroIssueCode.crossedRange,
            );
            expect(
              _codes(field),
              contains(OdfZoteroIssueCode.overlappingFields),
            );
          }
        },
      );
    }

    test('adjacent fields with separate names stay independent', () async {
      final fields = (await OdfZotero.inspect(
        _package(
          _paragraph(
            '${_mark(_name('adjacentA'), 'A')}${_mark(_name('adjacentB'), 'B')}',
          ),
        ),
      )).fields;
      expect(fields.map((field) => field.cachedText), ['A', 'B']);
      expect(fields.every((field) => field.isImportCandidate), isTrue);
      expect(fields[0].ends.single.offset, fields[1].starts.single.offset);
    });
  });

  group('native ODT Zotero physical ownership', () {
    test('body endpoint cannot pair with an authored note endpoint', () async {
      final name = _name('crossStory');
      final field = (await OdfZotero.inspect(
        _package(
          _paragraph(
            '${_start(name)}Body${_note(_paragraph('Note${_end(name)}'))}',
          ),
        ),
      )).fields.single;
      _ineligible(field, OdfZoteroIssueCode.crossStory);
      expect(field.starts.single.story, OdfZoteroStory.body);
      expect(field.ends.single.story, OdfZoteroStory.footnote);
      expect(field.ranges, isEmpty);
    });

    test(
      'separate footnotes are separate stories even with equal visible text',
      () async {
        final name = _name('twoNotes');
        final field = (await OdfZotero.inspect(
          _package(
            _paragraph(
              '${_note(_paragraph('${_start(name)}Same'))}'
              '${_note(_paragraph('Same${_end(name)}'))}',
            ),
          ),
        )).fields.single;
        _ineligible(field, OdfZoteroIssueCode.crossStory);
        expect(field.starts.single.story, field.ends.single.story);
        expect(
          field.starts.single.storyPath,
          isNot(field.ends.single.storyPath),
        );
        expect(field.ranges, isEmpty);
      },
    );

    test(
      'complete citations in footnotes and endnotes retain note-body ownership',
      () async {
        final fields = (await OdfZotero.inspect(
          _package(
            _paragraph(
              '${_note(_paragraph(_mark(_name('foot'), 'Foot')))}'
              '${_note(_paragraph(_mark(_name('end'), 'End')), kind: 'endnote')}',
            ),
          ),
        )).fields;
        expect(fields.map((field) => field.starts.single.story), [
          OdfZoteroStory.footnote,
          OdfZoteroStory.endnote,
        ]);
        expect(fields.every((field) => field.isImportCandidate), isTrue);
        expect(fields.map((field) => field.cachedText), ['Foot', 'End']);
        for (final field in fields) {
          expect(
            field.starts.single.owners.map((owner) => owner.localName),
            containsAllInOrder(['text', 'note', 'note-body']),
          );
        }
      },
    );

    test('sibling table cells cannot share a reference range', () async {
      final name = _name('crossCell');
      final field = (await OdfZotero.inspect(
        _package(
          _tableWithCells(
            '${_cell(_paragraph('${_start(name)}A'))}'
            '${_cell(_paragraph('B${_end(name)}'))}',
          ),
        ),
      )).fields.single;
      _ineligible(field, OdfZoteroIssueCode.crossOwner);
      expect(
        field.starts.single.owners.last.path,
        isNot(field.ends.single.owners.last.path),
      );
      expect(field.ranges, isEmpty);
    });

    test('ordinary and nested cells have stable distinct owner chains', () async {
      final bytes = _package(
        _tableWithCells(
          _cell(
            '${_paragraph(_mark(_name('outerCell'), 'Same'))}'
            '${_tableWithCells(_cell(_paragraph(_mark(_name('innerCell'), 'Same'))))}',
          ),
        ),
      );
      final snapshot = Uint8List.fromList(bytes);
      final first = await OdfZotero.inspect(bytes);
      final second = await OdfZotero.inspect(bytes);
      expect(bytes, orderedEquals(snapshot));
      expect(first.toJson(), equals(second.toJson()));
      expect(first.fields.every((field) => field.isImportCandidate), isTrue);
      expect(first.fields.map((field) => field.cachedText), ['Same', 'Same']);
      expect(
        first.fields[0].starts.single.owners.where(
          (owner) => owner.localName == 'table-cell',
        ),
        hasLength(1),
      );
      expect(
        first.fields[1].starts.single.owners.where(
          (owner) => owner.localName == 'table-cell',
        ),
        hasLength(2),
      );
      expect(() => first.fields.clear(), throwsUnsupportedError);
      expect(() => first.fields.first.starts.clear(), throwsUnsupportedError);
      expect(
        () => first.fields.first.starts.single.owners.clear(),
        throwsUnsupportedError,
      );
    });

    test(
      'covered and repeated cells preserve evidence while refusing eligibility',
      () async {
        final fields = (await OdfZotero.inspect(
          _package(
            _tableWithCells(
              '<table:covered-table-cell>'
              '${_paragraph(_mark(_name('covered'), 'Hidden'))}'
              '</table:covered-table-cell>'
              '${_cell(_paragraph(_mark(_name('repeat'), 'Repeated')), attributes: 'table:number-columns-repeated="2"')}',
            ),
          ),
        )).fields;
        expect(fields, hasLength(2));
        _ineligible(fields[0], OdfZoteroIssueCode.unsupportedContent);
        _ineligible(fields[1], OdfZoteroIssueCode.repeatedContent);
        expect(fields.map((field) => field.cachedText), ['Hidden', 'Repeated']);
      },
    );

    test(
      'annotation, text-box and stored revisions remain inventoried',
      () async {
        final anchored = _paragraph(
          '<office:annotation>${_paragraph(_mark(_name('comment'), 'Comment'))}'
          '</office:annotation><draw:frame><draw:text-box>'
          '${_paragraph(_mark(_name('drawing'), 'Drawing'))}'
          '</draw:text-box></draw:frame>',
        );
        final fields = (await OdfZotero.inspect(
          _package(
            '$anchored<text:tracked-changes><text:changed-region text:id="c1">'
            '<text:deletion>${_paragraph(_mark(_name('revision'), 'Deleted'))}'
            '</text:deletion></text:changed-region></text:tracked-changes>',
          ),
        )).fields;
        expect(fields.map((field) => field.starts.single.story), [
          OdfZoteroStory.annotation,
          OdfZoteroStory.textBox,
          OdfZoteroStory.revision,
        ]);
        for (final field in fields) {
          _ineligible(field, OdfZoteroIssueCode.unsupportedStory);
          expect(field.cachedText, isNotEmpty);
        }
      },
    );

    test(
      'a note inside stored deleted content retains the revision guard',
      () async {
        final field = (await OdfZotero.inspect(
          _package(
            '<text:tracked-changes><text:changed-region text:id="deletedNote">'
            '<text:deletion>'
            '${_paragraph(_note(_paragraph(_mark(_name('deletedN'), 'Deleted footnote'))))}'
            '</text:deletion></text:changed-region></text:tracked-changes>',
          ),
        )).fields.single;
        expect(field.isValid, isTrue);
        expect(field.isImportCandidate, isFalse);
        expect(field.issues, isNotEmpty);
        expect(
          field.starts.single.owners.map((owner) => owner.localName),
          containsAllInOrder(['tracked-changes', 'note']),
        );
      },
    );

    test(
      'embedded object descendants cannot masquerade as body candidates',
      () async {
        final inventory = await OdfZotero.inspect(
          _package(
            '<draw:frame><draw:object>'
            '${_paragraph(_mark(_name('object'), 'Embedded'))}'
            '</draw:object></draw:frame>',
          ),
        );
        expect(inventory.fields, hasLength(1));
        final field = inventory.fields.single;
        expect(field.isImportCandidate, isFalse);
        expect(field.issues, isNotEmpty);
        expect(
          field.starts.single.owners.map((owner) => owner.localName),
          contains('object'),
        );
        expect(inventory.issues, isNotEmpty);
      },
    );

    test(
      'foreign structural wrappers are detected rather than trusted as body',
      () async {
        final field = (await OdfZotero.inspect(
          _package(
            '<foreign:note>${_paragraph(_mark(_name('foreign'), 'Untrusted'))}'
            '</foreign:note>',
          ),
        )).fields.single;
        expect(field.isValid, isTrue);
        expect(field.isImportCandidate, isFalse);
        expect(field.issues, isNotEmpty);
      },
    );

    test(
      'nested paragraph endpoints cannot reverse paragraph index slicing',
      () async {
        final name = _name('nestedPara');
        final field = (await OdfZotero.inspect(
          _package(
            _paragraph(
              '${_paragraph('First nested paragraph')}'
              '${_paragraph('${_start(name)}Second nested paragraph')}'
              '${_end(name)}',
            ),
          ),
        )).fields.single;
        _ineligible(field, OdfZoteroIssueCode.unsupportedContent);
        expect(field.ranges, isEmpty);
      },
    );
  });

  group('native ODT Zotero bibliography sections', () {
    test(
      'plain section preserves paragraph boundaries and block endpoints',
      () async {
        final field = (await OdfZotero.inspect(
          _package(
            _section(
              _name('bibliog', bibliography: true),
              '${_paragraph('First entry')}${_paragraph('Second entry')}',
            ),
          ),
        )).fields.single;
        expect(field.storage, OdfZoteroStorage.section);
        expect(field.kind, ZoteroFieldKind.bibliography);
        expect(field.isImportCandidate, isTrue);
        expect(field.starts.single.paragraphPath, isNull);
        expect(field.ends.single.offset, isNull);
        expect(field.ranges.map((range) => range.text), [
          'First entry',
          'Second entry',
        ]);
        expect(field.cachedText, 'First entry\nSecond entry');
      },
    );

    test(
      'section and reference mark with same name are both ambiguous',
      () async {
        final name = _name('sharedBibl', bibliography: true);
        final fields = (await OdfZotero.inspect(
          _package(_section(name, _paragraph(_mark(name, 'Entry')))),
        )).fields;
        expect(fields, hasLength(2));
        for (final field in fields) {
          _ineligible(field, OdfZoteroIssueCode.duplicateName);
          expect(_codes(field), contains(OdfZoteroIssueCode.overlappingFields));
        }
      },
    );

    test(
      'point mark inside a section still overlaps its block ownership',
      () async {
        final pointName = _name('point');
        final fields = (await OdfZotero.inspect(
          _package(
            _section(
              _name('pointBibl', bibliography: true),
              _paragraph(
                'Before<text:reference-mark text:name="${_escape(pointName)}"/>After',
              ),
            ),
          ),
        )).fields;
        expect(fields, hasLength(2));
        _ineligible(fields[0], OdfZoteroIssueCode.overlappingFields);
        _ineligible(fields[1], OdfZoteroIssueCode.pointMark);
        expect(fields[1].ranges, isEmpty);
        expect(fields[1].cachedText, isEmpty);
      },
    );

    test(
      'nested Zotero sections preserve both identities and reject overlap',
      () async {
        final fields = (await OdfZotero.inspect(
          _package(
            _section(
              _name('outerBibl', bibliography: true),
              _section(
                _name('innerBibl', bibliography: true),
                _paragraph('Entry'),
              ),
            ),
          ),
        )).fields;
        expect(fields, hasLength(2));
        _ineligible(fields[0], OdfZoteroIssueCode.unsupportedSectionStructure);
        _ineligible(fields[1], OdfZoteroIssueCode.nestedSection);
        for (final field in fields) {
          expect(_codes(field), contains(OdfZoteroIssueCode.overlappingFields));
        }
      },
    );

    test(
      'bibliography nested in an ordinary section is explicitly guarded',
      () async {
        final field = (await OdfZotero.inspect(
          _package(
            _section(
              'Ordinary section',
              _section(
                _name('nested', bibliography: true),
                _paragraph('Entry'),
              ),
            ),
          ),
        )).fields.single;
        _ineligible(field, OdfZoteroIssueCode.nestedSection);
      },
    );

    for (final value in ['true', '1', 'invalid']) {
      test('protected section attribute $value refuses import', () async {
        final field = (await OdfZotero.inspect(
          _package(
            _section(
              _name('protected', bibliography: true),
              _paragraph('Entry'),
              attributes: 'text:protected="$value"',
            ),
          ),
        )).fields.single;
        if (value == 'true') {
          _ineligible(field, OdfZoteroIssueCode.protectedSection);
        } else {
          // ODF's own boolean type permits only true/false. Malformed
          // protection metadata must not silently make content importable.
          expect(field.isImportCandidate, isFalse);
          expect(field.issues, isNotEmpty);
        }
      });
    }

    for (final sourceChild in [false, true]) {
      test(
        'linked section ${sourceChild ? 'source child' : 'href'} refuses import',
        () async {
          final field = (await OdfZotero.inspect(
            _package(
              _section(
                _name('linked', bibliography: true),
                '${sourceChild ? '<text:section-source xlink:href="https://example.invalid/source.odt"/>' : ''}'
                '${_paragraph('Entry')}',
                attributes: sourceChild
                    ? ''
                    : 'xlink:href="https://example.invalid/source.odt"',
              ),
            ),
          )).fields.single;
          _ineligible(field, OdfZoteroIssueCode.linkedSection);
        },
      );
    }

    test('DDE-linked section retains its external source finding', () async {
      final field = (await OdfZotero.inspect(
        _package(
          _section(
            _name('ddeSource', bibliography: true),
            '<office:dde-source office:dde-application="Writer" '
            'office:dde-topic="external.odt" office:dde-item="Section1"/>'
            '${_paragraph('Cached entry')}',
          ),
        ),
      )).fields.single;
      _ineligible(field, OdfZoteroIssueCode.linkedSection);
    });

    test(
      'nonparagraph drawing content blocks bibliography section eligibility',
      () async {
        final inventory = await OdfZotero.inspect(
          _package(
            _section(
              _name('withImage', bibliography: true),
              '${_paragraph('Entry')}'
              '<draw:frame><draw:image xlink:href="Pictures/image.png"/></draw:frame>',
            ),
          ),
        );
        expect(inventory.fields.single.isValid, isTrue);
        expect(inventory.fields.single.isImportCandidate, isFalse);
        expect(inventory.fields.single.issues, isNotEmpty);
        expect(inventory.issues, isNotEmpty);
      },
    );

    test(
      'citation-coded and empty sections do not qualify as bibliographies',
      () async {
        final fields = (await OdfZotero.inspect(
          _package(
            _section(_name('citation'), _paragraph('Citation')) +
                _section(_name('empty', bibliography: true), ''),
          ),
        )).fields;
        expect(fields, hasLength(2));
        _ineligible(fields[0], OdfZoteroIssueCode.sectionKind);
        _ineligible(fields[1], OdfZoteroIssueCode.emptySection);
      },
    );

    test(
      'hidden section boolean 1 does not become an import candidate',
      () async {
        final field = (await OdfZotero.inspect(
          _package(
            _section(
              _name('hidden', bibliography: true),
              _paragraph('Hidden entry'),
              attributes: 'text:is-hidden="1"',
            ),
          ),
        )).fields.single;
        _ineligible(field, OdfZoteroIssueCode.unsupportedContent);
      },
    );
  });

  group('native ODT Zotero namespaces and bounds', () {
    test('element and attribute namespace decoys do not create fields', () async {
      final escaped = _escape(_name('decoy'));
      final decoys = _paragraph(
        '<foreign:reference-mark-start text:name="$escaped"/>'
        'A<foreign:reference-mark-end text:name="$escaped"/>'
        '<text:reference-mark-start foreign:name="$escaped"/>'
        'B<text:reference-mark-end foreign:name="$escaped"/>',
      );
      final inventory = await OdfZotero.inspect(
        _package(
          '$decoys<foreign:section text:name="$escaped">${_paragraph('C')}</foreign:section>'
          '<text:section foreign:name="$escaped">${_paragraph('D')}</text:section>',
        ),
      );
      expect(inventory.fields, isEmpty);
    });

    test('equivalent prefix bindings pair by expanded names', () async {
      final name = _name('namespace');
      final field = (await OdfZotero.inspect(
        _package(
          _paragraph(
            '<t:reference-mark-start t:name="${_escape(name)}"/>'
            'Citation${_end(name)}',
          ),
        ),
      )).fields.single;
      expect(field.isImportCandidate, isTrue);
      expect(field.cachedText, 'Citation');
    });

    test(
      'duplicated endpoints cannot evade the configured field limit',
      () async {
        final name = _name('manyStarts');
        await expectLater(
          OdfZotero.inspect(
            _package(
              _paragraph('${_start(name)}${_start(name)}${_start(name)}'),
            ),
            limits: const OdfZoteroLimits(maxFields: 1),
          ),
          throwsA(isA<OdfZoteroLimitException>()),
        );
      },
    );

    test(
      'paragraph bound fails the inventory instead of truncating later fields',
      () async {
        await expectLater(
          OdfZotero.inspect(
            _package(
              '${_paragraph('Lead')}${_paragraph(_mark(_name('later'), 'Later'))}',
            ),
            limits: const OdfZoteroLimits(maxParagraphs: 1),
          ),
          throwsA(isA<OdfZoteroLimitException>()),
        );
      },
    );

    test('deep ownership fails the bounded XML parse', () async {
      final body =
          '${List.filled(20, '<text:section text:name="Ordinary">').join()}'
          '${_paragraph(_mark(_name('deep'), 'Deep'))}'
          '${List.filled(20, '</text:section>').join()}';
      await expectLater(
        OdfZotero.inspect(
          _package(body),
          limits: const OdfZoteroLimits(maxXmlDepth: 12),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
