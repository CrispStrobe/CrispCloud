import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _id = 'transfer-session';
const _instructions =
    'Open this document in the destination and click Refresh.';

String _prefs([String type = 'Field']) => jsonEncode(<String, Object?>{
  'dataVersion': 4,
  'sessionID': 'transfer-test',
  'style': <String, Object?>{
    'styleID': 'http://www.zotero.org/styles/apa',
    'locale': 'de-DE',
    'hasBibliography': true,
    'bibliographyStyleHasBeenSet': false,
  },
  'prefs': <String, Object?>{'fieldType': type, 'noteType': 0},
  'extension': <String, Object?>{'keep': 'Ä 😀'},
});

ZoteroCitation _citation(String id) => ZoteroCitation(
  citationId: id,
  plainCitation: '($id)',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: <String, Object?>{
        'id': id,
        'type': 'book',
        'title': 'Übertragung 😀 $id',
      },
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
      locator: '27',
      label: 'page',
    ),
  ],
);

WmlDocument _document() {
  final document = WmlDocument.empty(text: 'Before ')
    ..zoteroDocumentData = _prefs();
  final paragraph = document.paragraphs.single;
  WordZotero.insertCitation(paragraph, _citation('first'));
  paragraph.inlines.add(WmlRun(text: ' between '));
  WordZotero.insertCitation(paragraph, _citation('second'));
  paragraph.inlines.add(WmlRun(text: ' after'));
  document.sections.single.blocks.addAll(
    WordZotero.nativeBibliographyParagraphs(
      instruction:
          ' ADDIN ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY ',
      text: 'Original bibliography',
    ),
  );
  return document;
}

WordZoteroCitingSession _session(WmlDocument document) =>
    WordZoteroCitingSession(document: document, documentId: _id);

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, [_id, ...arguments]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object>>();

void _export(WmlDocument document) {
  final session = _session(document);
  _call(session, 'Document.setDocumentData', [_prefs('Http')]);
  _call(session, 'Document.exportDocument', ['Http', _instructions]);
  _call(session, 'Document.setDocumentData', [_prefs('Http')]);
  _call(session, 'Document.activate');
  _call(session, 'Document.complete');
  session.apply();
}

void _format(WordZoteroCitingSession session) {
  for (final field in _fields(session)) {
    final bibliography = (field['code']! as String).startsWith('BIBL ');
    _call(session, 'Field.setText', [
      field['id'],
      bibliography
          ? '<div class="csl-bib-body"><div class="csl-entry"><i>Source one</i>.</div><div class="csl-entry">Source two.</div></div>'
          : '<i>(Formatted ${field['id']})</i>',
      true,
    ]);
  }
}

void main() {
  test(
    'export is detached, uses the real callback, and persists the marker',
    () {
      final document = _document();
      final first = document.paragraphs.first;
      final before = first.text;
      final session = _session(document);
      final application =
          session.handle('Application.getActiveDocument', [])!
              as Map<String, Object>;
      expect(application['supportsImportExport'], isTrue);
      _call(session, 'Document.setDocumentData', [_prefs('Http')]);
      _call(session, 'Document.exportDocument', ['Http', _instructions]);
      expect(session.hasExportedDocument, isTrue);
      expect(session.hasImportedDocument, isFalse);
      expect(session.changedFieldCount, 3);
      expect(
        _call(session, 'Document.getDocumentData'),
        'ZOTERO_TRANSFER_DOCUMENT',
      );
      expect(WordZotero.fields(document), hasLength(3));
      expect(document.paragraphs.first, same(first));
      expect(first.text, before);
      expect(session.apply, throwsStateError);
      _call(session, 'Document.complete');
      session.apply();
      expect(WordZotero.fields(document), isEmpty);
      expect(WordZoteroTransfer.isTransferDocument(document), isTrue);
      expect(document.paragraphs, contains(same(first)));
      final reopened = WordDeserializer().read(
        WordSerializer().write(document),
      );
      expect(
        _call(_session(reopened), 'Document.getDocumentData'),
        'ZOTERO_TRANSFER_DOCUMENT',
      );
    },
  );

  test(
    'import waits for complete formatting and keeps all fields active on reopen',
    () {
      final document = _document();
      _export(document);
      final sourceParagraph = document.paragraphs.elementAt(4);
      final transferText = document.paragraphs.map((p) => p.text).toList();
      final session = _session(document);
      expect(_call(session, 'Document.importDocument', ['Http']), isTrue);
      expect(session.hasImportedDocument, isTrue);
      expect(session.hasExportedDocument, isFalse);
      expect(_fields(session), hasLength(3));
      expect(_call(session, 'Document.getDocumentData'), contains('Http'));
      expect(document.paragraphs.map((p) => p.text), transferText);
      _format(session);
      _call(session, 'Document.complete');
      session.prepareReview();
      expect(session.formattingWarnings, isEmpty);
      session.apply();
      expect(WordZoteroTransfer.isTransferDocument(document), isFalse);
      expect(document.paragraphs.first, same(sourceParagraph));
      final fields = WordZotero.fields(document);
      expect(fields, hasLength(3));
      expect(fields.first.citation!.items.single.locator, '27');
      expect(
        fields.first.citation!.items.single.itemData!['title'],
        'Übertragung 😀 first',
      );
      expect(document.paragraphs.first.text, startsWith('Before '));
      expect(document.paragraphs.first.text, endsWith(' after'));
      final reopened = WordDeserializer().read(
        WordSerializer().write(document),
      );
      expect(WordZotero.fields(reopened), hasLength(3));
      expect(WordZoteroDocumentData.read(reopened), contains('"keep":"Ä 😀"'));
      expect(_fields(_session(reopened)), hasLength(3));
    },
  );

  test('transfer marker overrides damaged stale stored preferences', () {
    final document = _document();
    _export(document);
    document.zoteroDocumentData = 'not valid old native data';
    final session = _session(document);
    expect(
      _call(session, 'Document.getDocumentData'),
      'ZOTERO_TRANSFER_DOCUMENT',
    );
    expect(_call(session, 'Document.importDocument', ['Http']), isTrue);
    _format(session);
    _call(session, 'Document.complete');
    session.apply();
    expect(WordZoteroDocumentData.read(document), contains('Field'));
  });

  test('incomplete import never commits placeholder text', () {
    final document = _document();
    _export(document);
    final before = document.paragraphs.map((p) => p.text).toList();
    final session = _session(document);
    _call(session, 'Document.importDocument', ['Http']);
    final fields = _fields(session);
    _call(session, 'Field.setText', [
      fields.first['id'],
      '(Only first)',
      false,
    ]);
    expect(() => _call(session, 'Document.complete'), throwsFormatException);
    expect(session.isComplete, isFalse);
    expect(session.apply, throwsStateError);
    _call(session, 'Document.setDocumentData', [_prefs('Http')]);
    _call(session, 'Document.activate');
    expect(document.paragraphs.map((p) => p.text), before);
  });

  test(
    'cancelled import prompt completes without mutating transfer content',
    () {
      final document = _document();
      _export(document);
      final before = document.paragraphs.map((p) => p.text).toList();
      final session = _session(document);
      expect(
        _call(session, 'Document.getDocumentData'),
        'ZOTERO_TRANSFER_DOCUMENT',
      );
      _call(session, 'Document.complete');
      expect(session.hasChanges, isFalse);
      expect(document.paragraphs.map((p) => p.text), before);
    },
  );

  test('a transfer cannot be nested or mutated after export', () {
    final document = _document();
    final session = _session(document);
    _call(session, 'Document.exportDocument', ['Http', _instructions]);
    expect(
      () => _call(session, 'Document.setDocumentData', [
        _prefs().replaceAll('de-DE', 'en-US'),
      ]),
      throwsStateError,
    );
    expect(
      () => _call(session, 'Document.importDocument', ['Http']),
      throwsUnsupportedError,
    );
    _call(session, 'Document.complete');
    session.apply();
    final imported = _session(document);
    _call(imported, 'Document.importDocument', ['Http']);
    expect(
      () => _call(imported, 'Document.importDocument', ['Http']),
      throwsUnsupportedError,
    );
    expect(
      () => _call(imported, 'Document.exportDocument', ['Http', _instructions]),
      throwsUnsupportedError,
    );
  });

  test('ordinary documents report false for import without changes', () {
    final document = _document();
    final session = _session(document);
    expect(_call(session, 'Document.importDocument', ['Http']), isFalse);
    expect(session.hasChanges, isFalse);
    expect(
      () => _call(session, 'Document.importDocument', ['Field']),
      throwsUnsupportedError,
    );
  });

  test('pending transfer cannot accept active fields before import', () {
    final document = _document();
    _export(document);
    final session = WordZoteroCitingSession(
      document: document,
      documentId: _id,
      insertionParagraph: document.paragraphs.elementAt(4),
    );
    expect(_call(session, 'Document.canInsertField', ['Http']), isFalse);
    expect(
      () => _call(session, 'Document.insertField', ['Http', 0]),
      throwsUnsupportedError,
    );
    expect(
      () => _call(session, 'Document.setDocumentData', [_prefs()]),
      throwsUnsupportedError,
    );
    expect(session.hasChanges, isFalse);
  });
}
