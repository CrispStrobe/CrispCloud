import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _prefs =
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="2" name="ZOTERO_PREF_1"><vt:lpwstr>&lt;data data-version="3" zotero-version="7.0"&gt;&lt;session id="native"/&gt;&lt;style id="http://www.zotero.org/styles/apa" hasBibliography="1"/&gt;&lt;/data&gt;</vt:lpwstr></property></Properties>';

OpcPackage _fixture() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        File('test/fixtures/zotero/word_document.xml').readAsStringSync(),
      );
  package.createPart(
    '/docProps/custom.xml',
    'application/vnd.openxmlformats-officedocument.custom-properties+xml',
    utf8.encode(_prefs),
  );
  package
      .relationshipsFor('/')
      .add(
        type: RelationshipTypes.customProperties,
        target: 'docProps/custom.xml',
      );
  return package;
}

ZoteroCitation _citation(String id, String text) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  items: <ZoteroCitationItem>[
    ZoteroCitationItem.fromCsl(
      itemData: <String, dynamic>{
        'id': 'https://zotero.org/users/42/items/ABCD1234',
        'type': 'article-journal',
        'title': 'A & B <research>',
        'author': <Map<String, String>>[
          <String, String>{'family': 'Lovelace', 'given': 'Ada'},
        ],
        'issued': <String, dynamic>{
          'date-parts': <List<int>>[
            <int>[1843],
          ],
        },
      },
      uris: <String>['http://zotero.org/users/42/items/ABCD1234'],
      locator: '12–14',
      label: 'page',
      prefix: 'see ',
      suffix: ' et seq.',
      suppressAuthor: true,
    ),
  ],
);

void main() {
  test('CSL citation metadata is immutable and retains unknown fields', () {
    final field = WordZotero.fields(WordDeserializer().read(_fixture())).first;
    final citation = field.citation!;
    expect(citation.citationId, 'native-α');
    expect(citation.toJson()['futureRoot'], <String, int>{'version': 9});
    expect(citation.properties['futureProperty'], 'retain');
    expect(citation.items.single.itemData!['title'], 'A & B');
    expect(citation.items.single.toJson()['ignoreRetraction'], isTrue);
    expect(citation.items.single.locator, '12–14');
    expect(citation.items.single.suppressAuthor, isTrue);
    expect(
      () => citation.items.single.itemData!['title'] = 'changed',
      throwsUnsupportedError,
    );
    expect(
      () => (citation.toJson()['futureRoot'] as Map)['version'] = 10,
      throwsUnsupportedError,
    );
    final replacement = citation.withItems(
      citation.items,
      plainCitation: '(Ada, pp. 12–14)',
      noteIndex: 2,
    );
    expect(replacement.citationId, 'native-α');
    expect(replacement.toJson()['futureRoot'], citation.toJson()['futureRoot']);
    expect(replacement.properties['futureProperty'], 'retain');
    expect(replacement.noteIndex, 2);
  });

  for (final isolate in <bool>[false, true]) {
    test(
      'independent native fields and preferences survive three ${isolate ? 'isolate' : 'direct'} saves',
      () async {
        var document = WordDeserializer().read(_fixture());
        final original = WordZotero.fields(document);
        expect(original, hasLength(4));
        expect(original[0].run, isNotNull);
        expect(original[0].run!.fieldDirty, isFalse);
        expect(original[1].run, isNull);
        expect(original[1].cachedText, '(Hopper, 1952)');
        expect(original[2].kind, ZoteroFieldKind.bibliography);
        expect(original[2].paragraphs, hasLength(2));
        expect(original[2].canEdit, isFalse);
        expect(original[3].isValid, isFalse);
        final instructions = original
            .map((field) => field.instruction)
            .toList();
        for (var cycle = 0; cycle < 3; cycle++) {
          WordFields.update(document);
          final bytes = isolate
              ? await OfficeIsolateSave.word(document)
              : WordSerializer().writeBytes(document);
          final saved = OpcPackage.openBytes(bytes);
          final xml = saved.getPart('/word/document.xml')!.readText();
          expect(xml, isNot(contains('fldSimple')));
          expect('fldCharType="begin"'.allMatches(xml), hasLength(5));
          expect(xml, contains('Keep malformed cache'));
          expect(xml, contains('Keep other manager'));
          expect(saved.getPart('/docProps/custom.xml')!.readText(), _prefs);
          document = WordDeserializer().readBytes(bytes);
          final fields = WordZotero.fields(document);
          expect(fields.map((field) => field.instruction), instructions);
          expect(fields[0].cachedText, '(Lovelace, 1843)');
          expect(
            fields[1].paragraph.inlines
                .whereType<WmlRun>()
                .first
                .properties
                .italic,
            isTrue,
          );
          expect(fields[2].cachedText, 'Hopper. Compilers.\nLovelace. A & B.');
          expect(fields[2].metadata!['futureBibliography'], 'retain');
        }
        expect(WordZotero.embeddedItems(document), hasLength(2));
      },
    );
  }

  test('insert, save, edit and unlink preserve surrounding rich text', () {
    final document = WmlDocument.empty(text: 'LeftRight');
    final paragraph = document.paragraphs.single;
    paragraph.inlines.whereType<WmlRun>().single.properties.bold = true;
    WordZotero.insertCitation(paragraph, _citation('new-1', '(Ada)'), index: 4);
    expect(paragraph.text, 'Left(Ada)Right');
    var field = WordZotero.fields(document).single;
    expect(field.canEdit, isTrue);
    expect(field.run!.isAtomic, isTrue);
    WordFields.update(document);
    expect(field.run!.text, '(Ada)');
    WordZotero.updateCitation(
      field,
      field.citation!.withItems(
        field.citation!.items,
        plainCitation: '(Ada, 1843)',
      ),
    );
    expect(paragraph.text, 'Left(Ada, 1843)Right');
    field = WordZotero.fields(document).single;
    WordZotero.unlink(field);
    expect(WordZotero.fields(document), isEmpty);
    expect(paragraph.text, 'Left(Ada, 1843)Right');
    expect(
      paragraph.inlines.whereType<WmlRun>().every(
        (run) => run.properties.bold == true,
      ),
      isTrue,
    );
  });

  test(
    'new complex fields reopen as atomic runs including isolated saves',
    () async {
      var document = WmlDocument.empty(text: 'A B');
      WordZotero.insertCitation(
        document.paragraphs.single,
        _citation('created', '(Ada)'),
        index: 1,
      );
      document.sections.single.blocks.add(
        WordZotero.bibliography(text: 'Ada. A & B.'),
      );
      for (var i = 0; i < 3; i++) {
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
        final fields = WordZotero.fields(document);
        expect(fields, hasLength(2));
        expect(
          fields.every((field) => field.run != null && field.canEdit),
          isTrue,
        );
        expect(document.paragraphs.first.text, 'A(Ada) B');
        expect(
          fields.first.citation!.items.single.itemData!['title'],
          'A & B <research>',
        );
      }
      final bibliography = WordZotero.fields(document).last;
      WordZotero.updateBibliography(bibliography, text: 'Updated bibliography');
      expect(document.paragraphs.last.text, 'Updated bibliography');
    },
  );

  test('inserting at rich field boundaries does not nest or split fields', () {
    final document = WordDeserializer().read(_fixture());
    final rich = WordZotero.fields(document)[1];
    expect(
      () => WordZotero.insertCitation(
        rich.paragraph,
        _citation('inside', '(Inside)'),
        index: 3,
      ),
      throwsUnsupportedError,
    );
    WordZotero.insertCitation(
      rich.paragraph,
      _citation('before', '(Before)'),
      index: 0,
    );
    WordZotero.insertCitation(rich.paragraph, _citation('after', '(After)'));
    expect(rich.paragraph.text, '(Before)(Hopper, 1952)(After)');
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(
      WordZotero.fields(reopened)
          .where((field) => field.citation?.citationId == 'rich-cache')
          .single
          .nested,
      isFalse,
    );
  });

  test('explicit unlink of a multi-paragraph bibliography keeps its cache', () {
    final document = WordDeserializer().read(_fixture());
    final bibliography = WordZotero.fields(document)[2];
    expect(
      () => WordZotero.updateBibliography(bibliography, text: 'Replacement'),
      throwsUnsupportedError,
    );
    WordZotero.unlink(bibliography);
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(
      WordZotero.fields(
        reopened,
      ).where((field) => field.kind == ZoteroFieldKind.bibliography),
      isEmpty,
    );
    expect(
      reopened.paragraphs.map((paragraph) => paragraph.text),
      containsAll(<String>['Hopper. Compilers.', 'Lovelace. A & B.']),
    );
  });

  test(
    'malformed, locked, stale, and over-budget metadata are not rewritten',
    () {
      final document = WordDeserializer().read(_fixture());
      final malformed = WordZotero.fields(document).last;
      expect(
        () => WordZotero.updateCitation(
          malformed,
          _citation('repair', '(Repair)'),
        ),
        throwsUnsupportedError,
      );
      expect(() => WordZotero.unlink(malformed), throwsUnsupportedError);
      final valid = WordZotero.fields(document).first;
      valid.run!.fieldLocked = true;
      final locked = WordZotero.fields(document).first;
      expect(locked.canEdit, isFalse);
      expect(() => WordZotero.unlink(locked), throwsUnsupportedError);
      valid.run!.fieldLocked = false;
      final stale = WordZotero.fields(document).first;
      stale.run!.text = 'Edited externally';
      expect(
        () => WordZotero.updateCitation(stale, _citation('stale', '(Stale)')),
        throwsStateError,
      );
      expect(
        WordZotero.metadataOf(
          ' ADDIN ZOTERO_ITEM CSL_CITATION {"x":"${'a' * (1024 * 1024)}"}',
        ),
        isNull,
      );
      expect(
        WordZotero.kindOfInstruction(' IF "ZOTERO_ITEM CSL_CITATION" = "x" '),
        isNull,
      );
      expect(
        WordZotero.metadataOf(' ADDIN ZOTERO_BIBL {} unexpected '),
        isNull,
      );
    },
  );

  test('new source URIs and contradictory author options are validated', () {
    expect(
      () => ZoteroCitationItem.fromCsl(
        itemData: <String, dynamic>{'id': 'x'},
        uris: <String>['https://attacker.invalid/items/ABCD1234'],
      ),
      throwsArgumentError,
    );
    expect(
      () => ZoteroCitationItem.fromCsl(
        itemData: <String, dynamic>{'id': 'x'},
        uris: <String>['http://zotero.org/users/42/items/ABCD1234'],
        suppressAuthor: true,
        authorOnly: true,
      ),
      throwsArgumentError,
    );
    final personal = ZoteroCitationItem.fromCsl(
      itemData: <String, dynamic>{'id': 17},
      uris: <String>['http://zotero.org/users/42/items/ABCD1234'],
    );
    final group = ZoteroCitationItem.fromCsl(
      itemData: <String, dynamic>{'id': 17},
      uris: <String>['http://zotero.org/groups/77/items/ABCD1234'],
    );
    expect(personal.id, isNot(group.id));
    expect(personal.itemData!['id'], personal.id);
    expect(
      WordZotero.metadataOf(
        ' CSL_CITATION ${jsonEncode(_citation('legacy', '(Legacy)').toJson())} ',
      ),
      isNotNull,
    );
  });

  test('native field locks survive import and complex-field export', () {
    final package = _fixture();
    final source = package.getPart('/word/document.xml')!;
    source.writeText(
      source.readText().replaceFirst(
        'w:dirty="0"',
        'w:dirty="0" w:fldLock="true"',
      ),
    );
    var document = WordDeserializer().read(package);
    for (var cycle = 0; cycle < 3; cycle++) {
      final locked = WordZotero.fields(document).first;
      expect(locked.locked, isTrue);
      expect(locked.canEdit, isFalse);
      WordFields.update(document);
      expect(locked.cachedText, '(Lovelace, 1843)');
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
  });

  test('unknown field attributes and instruction-run properties stay opaque', () {
    final package = _fixture();
    final source = package.getPart('/word/document.xml')!;
    source.writeText(
      source
          .readText()
          .replaceFirst(
            'w:dirty="0"',
            'w:dirty="0" xmlns:future="urn:zotero:future" future:dirty="retain"',
          )
          .replaceFirst(
            '<w:r><w:instrText xml:space="preserve"> ADDIN',
            '<w:r><w:rPr><w:color w:val="123456"/></w:rPr><w:instrText xml:space="preserve"> ADDIN',
          ),
    );
    var document = WordDeserializer().read(package);
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(WordZotero.fields(document).first.run, isNull);
      expect(WordZotero.fields(document).first.canEdit, isFalse);
      final saved = WordSerializer().write(document);
      final xml = saved.getPart('/word/document.xml')!.readText();
      expect(xml, contains('future:dirty="retain"'));
      expect(xml, contains('w:color w:val="123456"'));
      document = WordDeserializer().readBytes(saved.save());
    }
  });

  test(
    'canonical URI aliases deduplicate embedded items without rewriting metadata',
    () {
      final document = WmlDocument.empty();
      final paragraph = document.paragraphs.single;
      for (final entry in <String, String>{
        'http': 'http://zotero.org/users/42/items/ABCD1234',
        'https': 'https://zotero.org/users/42/items/ABCD1234',
        'www': 'https://www.zotero.org/users/42/items/ABCD1234',
        'group': 'http://zotero.org/groups/42/items/ABCD1234',
      }.entries) {
        WordZotero.insertCitation(
          paragraph,
          ZoteroCitation(
            citationId: entry.key,
            plainCitation: '(${entry.key})',
            items: <ZoteroCitationItem>[
              ZoteroCitationItem.fromJson(<String, dynamic>{
                'id': 17,
                'uris': <String>[entry.value],
                'itemData': <String, dynamic>{
                  'id': 17,
                  'type': 'book',
                  'title': entry.key,
                },
              }),
            ],
          ),
        );
      }
      final before = WordZotero.fields(
        document,
      ).map((field) => field.instruction).toList();
      expect(
        WordZotero.embeddedItems(document).map((item) => item['title']),
        <String>['http', 'group'],
      );
      expect(
        WordZotero.fields(document).map((field) => field.instruction),
        before,
      );
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(WordZotero.embeddedItems(reopened), hasLength(2));
      expect(
        WordZotero.fields(reopened)[2].citation!.items.single.uris.single,
        'https://www.zotero.org/users/42/items/ABCD1234',
      );
    },
  );

  test(
    'citations in notes and header stories retain their ownership on save',
    () async {
      var document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: false,
        text: 'Note ',
      );
      WordZotero.insertCitation(
        note.paragraphs.single,
        _citation('note', '(Note source)'),
      );
      final header = WmlParagraph(
        inlines: <WmlInline>[WmlRun(text: 'Header ')],
      );
      document.sections.single.header.add(header);
      WordZotero.insertCitation(header, _citation('header', '(Header source)'));
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
        expect(
          WordZotero.fields(
            document,
          ).map((field) => field.citation!.citationId),
          <String>['header', 'note'],
        );
        expect(document.paragraphs.single.text, 'Body1');
        expect(document.footnotes.single.text, contains('Note (Note source)'));
        expect(
          document.sections.single.header.single.text,
          'Header (Header source)',
        );
      }
    },
  );
}
