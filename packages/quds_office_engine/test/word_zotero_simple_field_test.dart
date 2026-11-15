import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

ZoteroCitation _citation(String id, String text) => ZoteroCitation.fromJson({
  'citationID': id,
  'properties': {
    'plainCitation': text,
    'formattedCitation': '<i>$text</i>',
    'noteIndex': 0,
    'futureSetting': 'retain',
  },
  'citationItems': [
    {
      'id': 'http://zotero.org/users/42/items/ABCD1234',
      'uris': ['http://zotero.org/users/42/items/ABCD1234'],
      'itemData': {'id': 17, 'type': 'book', 'title': 'A & B'},
    },
  ],
});

String _simple(String instruction, String cache, {String attributes = ''}) =>
    '<w:fldSimple w:instr="${const HtmlEscape(HtmlEscapeMode.attribute).convert(instruction)}" $attributes>$cache</w:fldSimple>';

String _complex(String instruction, String cache, {List<String>? fragments}) =>
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
    '${(fragments ?? [instruction]).map((part) => '<w:r><w:instrText xml:space="preserve">${const HtmlEscape().convert(part)}</w:instrText></w:r>').join()}'
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
    '$cache<w:r><w:fldChar w:fldCharType="end"/></w:r>';

WmlDocument _document(String field, {bool surroundingText = true}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:future="urn:quds:zotero-test">'
        '<w:body><w:p>'
        '${surroundingText ? '<w:r><w:t xml:space="preserve">Before </w:t></w:r>' : ''}'
        '$field'
        '${surroundingText ? '<w:r><w:t xml:space="preserve"> After</w:t></w:r>' : ''}'
        '</w:p></w:body></w:document>',
      );
  return WordDeserializer().read(package);
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

const _richCache =
    '<w:r><w:rPr><w:i/></w:rPr><w:t>Alpha</w:t></w:r>'
    '<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve"> Beta</w:t></w:r>';

void main() {
  test('rich simple citations retain one linked field and styled cache', () {
    final citation = _citation('rich-simple', 'Alpha Beta');
    var document = _document(_simple(citation.fieldInstruction, _richCache));
    for (var cycle = 0; cycle < 3; cycle++) {
      final field = WordZotero.fields(document).single;
      expect(field.citation!.toJson(), citation.toJson());
      expect(field.instruction, citation.fieldInstruction);
      expect(field.cachedText, 'Alpha Beta');
      expect(field.run, isNull);
      expect(field.nested, isFalse);
      final runs = document.paragraphs.single.inlines.whereType<WmlRun>();
      expect(
        runs.singleWhere((run) => run.text == 'Alpha').properties.italic,
        isTrue,
      );
      expect(
        runs.singleWhere((run) => run.text == ' Beta').properties.bold,
        isTrue,
      );
      WordFields.update(document);
      expect(document.paragraphs.single.text, 'Before Alpha Beta After');
      expect(
        WordZotero.fields(document).single.instruction,
        citation.fieldInstruction,
      );
      document = _reopen(document);
    }
  });

  test(
    'ordinary one-run simple citations keep their atomic representation',
    () {
      final citation = _citation('plain-simple', '(Alpha)');
      var document = _document(
        _simple(
          citation.fieldInstruction,
          '<w:r><w:t>(Alpha)</w:t></w:r>',
          attributes: 'w:dirty="0"',
        ),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        final field = WordZotero.fields(document).single;
        expect(field.run, isNotNull);
        expect(field.canEdit, isTrue);
        expect(field.run!.fieldDirty, isFalse);
        expect(field.cachedText, '(Alpha)');
        document = _reopen(document);
      }
    },
  );

  test('locked rich simple citations refuse replacement and unlinking', () {
    final citation = _citation('locked-simple', 'Alpha Beta');
    var document = _document(
      _simple(
        citation.fieldInstruction,
        _richCache,
        attributes: 'w:fldLock="true" w:dirty="0"',
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      final field = WordZotero.fields(document).single;
      expect(field.locked, isTrue);
      expect(field.canEdit, isFalse);
      expect(
        () => WordZotero.updateCitation(field, citation),
        throwsUnsupportedError,
      );
      expect(() => WordZotero.unlink(field), throwsUnsupportedError);
      expect(field.cachedText, 'Alpha Beta');
      document = _reopen(document);
    }
  });

  test('nested simple citations retain both identities and refuse edits', () {
    final outer = _citation('outer-simple', 'Outer (Inner)');
    final inner = _citation('inner-simple', '(Inner)');
    var document = _document(
      _simple(
        outer.fieldInstruction,
        '<w:r><w:t xml:space="preserve">Outer </w:t></w:r>'
        '${_simple(inner.fieldInstruction, '<w:r><w:t>(Inner)</w:t></w:r>')}',
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      final fields = WordZotero.fields(document);
      expect(
        fields.map((field) => field.citation!.citationId),
        unorderedEquals(['outer-simple', 'inner-simple']),
      );
      for (final field in fields) {
        expect(field.nested, isTrue);
        expect(field.canEdit, isFalse);
        expect(
          () => WordZotero.updateCitation(field, field.citation!),
          throwsUnsupportedError,
        );
        expect(() => WordZotero.unlink(field), throwsUnsupportedError);
      }
      expect(document.paragraphs.single.text, 'Before Outer (Inner) After');
      document = _reopen(document);
    }
  });

  test('a generic simple parent does not expose its nested Zotero cache', () {
    final citation = _citation('nested-in-generic', '(Alpha)');
    var document = _document(
      _simple(
        ' IF 1 = 1 "yes" "no" ',
        _simple(citation.fieldInstruction, '<w:r><w:t>(Alpha)</w:t></w:r>'),
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      final field = WordZotero.fields(document).single;
      expect(field.citation!.citationId, 'nested-in-generic');
      expect(field.nested, isTrue);
      expect(field.canEdit, isFalse);
      expect(() => WordZotero.unlink(field), throwsUnsupportedError);
      final xml = WordSerializer()
          .write(document)
          .getPart('/word/document.xml')!
          .readText();
      expect(xml, contains(' IF 1 = 1 '));
      document = _reopen(document);
    }
  });

  for (final rich in [false, true]) {
    test(
      'simple extension attributes stay opaque through saves: rich=$rich',
      () {
        final citation = _citation('opaque-simple', 'Alpha Beta');
        var document = _document(
          _simple(
            citation.fieldInstruction,
            rich ? _richCache : '<w:r><w:t>Alpha Beta</w:t></w:r>',
            attributes: 'future:instr="keep-instr" future:dirty="keep-dirty"',
          ),
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          final field = WordZotero.fields(document).single;
          expect(field.opaqueMetadata, isTrue);
          expect(field.canEdit, isFalse);
          expect(field.run, isNull);
          expect(
            () => WordZotero.updateCitation(field, citation),
            throwsUnsupportedError,
          );
          final xml = WordSerializer()
              .write(document)
              .getPart('/word/document.xml')!
              .readText();
          expect(xml, contains('future:instr="keep-instr"'));
          expect(xml, contains('future:dirty="keep-dirty"'));
          expect(xml, contains('urn:quds:zotero-test'));
          document = _reopen(document);
        }
      },
    );
  }

  test('rich simple bibliographies keep their field metadata and styles', () {
    const instruction =
        ' ADDIN ZOTERO_BIBL '
        '{"uncited":[],"omitted":[],"custom":[],"future":"keep"} '
        'CSL_BIBLIOGRAPHY ';
    var document = _document(_simple(instruction, _richCache));
    for (var cycle = 0; cycle < 3; cycle++) {
      final field = WordZotero.fields(document).single;
      expect(field.kind, ZoteroFieldKind.bibliography);
      expect(field.metadata!['future'], 'keep');
      expect(field.cachedText, 'Alpha Beta');
      expect(field.run, isNull);
      WordFields.update(document);
      expect(WordZotero.fields(document).single.instruction, instruction);
      document = _reopen(document);
    }
  });

  test('tracked rich simple cache retains real paragraph revision offsets', () {
    final citation = _citation('tracked-simple', 'Alpha Beta');
    var document = _document(
      _simple(
        citation.fieldInstruction,
        '<w:ins w:id="9" w:author="Reviewer" w:date="2026-11-15T12:00:00Z">'
        '<w:r><w:rPr><w:i/></w:rPr><w:t>Alpha</w:t></w:r></w:ins>'
        '<w:r><w:t xml:space="preserve"> Beta</w:t></w:r>',
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      final revision = document.revisions.single;
      expect(revision.targetParagraph, same(document.paragraphs.single));
      expect(revision.start, 7);
      expect(revision.end, 12);
      expect(revision.accepted, isNull);
      expect(WordZotero.fields(document).single.cachedText, 'Alpha Beta');
      document = _reopen(document);
    }
  });

  test('malformed rich simple metadata stays a preserved uneditable field', () {
    const instruction = ' ADDIN ZOTERO_ITEM CSL_CITATION {broken JSON} ';
    var document = _document(_simple(instruction, _richCache));
    for (var cycle = 0; cycle < 3; cycle++) {
      final field = WordZotero.fields(document).single;
      expect(field.instruction, instruction);
      expect(field.isValid, isFalse);
      expect(field.canEdit, isFalse);
      expect(field.cachedText, 'Alpha Beta');
      expect(() => WordZotero.unlink(field), throwsUnsupportedError);
      WordFields.update(document);
      expect(WordZotero.fields(document).single.instruction, instruction);
      document = _reopen(document);
    }
  });

  final base = _citation('page-locator', 'Ada 1843');
  final pageCitation = base.withItems([
    ZoteroCitationItem.fromJson({
      ...base.items.single.toJson(),
      'label': 'page',
      'locator': '12',
    }),
  ], plainCitation: 'Ada 1843');
  const numberCache =
      '<w:r><w:rPr><w:i/></w:rPr><w:t>Ada</w:t></w:r>'
      '<w:r><w:t xml:space="preserve"> </w:t></w:r>'
      '<w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr>'
      '<w:t>1843</w:t></w:r>';
  for (final isolate in [false, true]) {
    test(
      'page locator does not discard numeric citation cache: isolate=$isolate',
      () async {
        var document = _document(
          _complex(pageCitation.fieldInstruction, numberCache),
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          final field = WordZotero.fields(document).single;
          expect(field.cachedText, 'Ada 1843');
          expect(field.citation!.items.single.label, 'page');
          expect(
            document.paragraphs.single.properties.pageNumberField,
            isFalse,
          );
          final year = document.paragraphs.single.inlines
              .whereType<WmlRun>()
              .singleWhere((run) => run.text == '1843');
          expect(year.properties.vertAlign, WmlVertAlign.superscript);
          document = WordDeserializer().readBytes(
            isolate
                ? await OfficeIsolateSave.word(document)
                : WordSerializer().writeBytes(document),
          );
        }
      },
    );

    test(
      'an earlier PAGE field does not consume later numbers: isolate=$isolate',
      () async {
        var document = _document(
          '${_complex(' PAGE ', '<w:r><w:t>7</w:t></w:r>')}'
          '${_complex(pageCitation.fieldInstruction, numberCache)}',
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(document.paragraphs.single.text, 'Before 7Ada 1843 After');
          expect(WordZotero.fields(document).single.cachedText, 'Ada 1843');
          expect(
            document.paragraphs.single.properties.pageNumberField,
            isFalse,
          );
          document = WordDeserializer().readBytes(
            isolate
                ? await OfficeIsolateSave.word(document)
                : WordSerializer().writeBytes(document),
          );
        }
      },
    );
  }

  test('PAGE used as a field argument keeps its numeric result', () {
    var document = _document(
      _complex(' REF PAGE ', '<w:r><w:t>123</w:t></w:r>'),
      surroundingText: false,
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(document.paragraphs.single.text, '123');
      expect(document.paragraphs.single.properties.pageNumberField, isFalse);
      expect(
        document.paragraphs.single.properties.fieldInstruction,
        ' REF PAGE ',
      );
      document = _reopen(document);
    }
  });

  test('whole-paragraph native PAGE remains a dynamic page field', () {
    var document = _document(
      _complex(' PAGE \\* MERGEFORMAT ', '<w:r><w:t>7</w:t></w:r>'),
      surroundingText: false,
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(document.paragraphs.single.text, isEmpty);
      expect(document.paragraphs.single.properties.pageNumberField, isTrue);
      expect(
        WordFields.kindOf(
          document.paragraphs.single.properties.fieldInstruction,
        ),
        WmlFieldKind.page,
      );
      document = _reopen(document);
    }
  });

  test('a PAGE fragment inside citation JSON is not a PAGE command', () {
    final instruction = pageCitation.fieldInstruction;
    final page = instruction.indexOf('page"');
    expect(page, greaterThan(0));
    var document = _document(
      _complex(
        instruction,
        numberCache,
        fragments: [
          instruction.substring(0, page),
          'page',
          instruction.substring(page + 4),
        ],
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(WordZotero.fields(document).single.cachedText, 'Ada 1843');
      expect(document.paragraphs.single.properties.pageNumberField, isFalse);
      document = _reopen(document);
    }
  });

  test(
    'tracked native PAGE cache keeps valid revision text and boundaries',
    () {
      var document = _document(
        _complex(
          ' PAGE ',
          '<w:ins w:id="10" w:author="Reviewer" w:date="2026-11-15T12:00:00Z">'
              '<w:r><w:t>7</w:t></w:r></w:ins>',
        ),
        surroundingText: false,
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        final paragraph = document.paragraphs.single;
        final revision = document.revisions.single;
        expect(paragraph.text, '7');
        expect(revision.targetParagraph, same(paragraph));
        expect(revision.start, 0);
        expect(revision.end, 1);
        expect(revision.accepted, isNull);
        expect(paragraph.properties.pageNumberField, isFalse);
        expect(paragraph.inlines.whereType<WmlFieldBoundary>(), hasLength(4));
        document = _reopen(document);
      }
    },
  );
}
