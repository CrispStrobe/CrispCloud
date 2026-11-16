import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _id = 'catalog-style-flow';
const _style =
    'http://www.zotero.org/styles/chicago-notes-bibliography-subsequent-ibid';

String _preferences(int noteType, {String? locale = 'de-DE'}) => jsonEncode({
  'dataVersion': 4,
  'style': {'styleID': _style, 'locale': locale},
  'prefs': {'fieldType': 'Http', 'noteType': noteType},
  'extension': {'keep': 'unchanged'},
});

ZoteroCitation _citation() => ZoteroCitation(
  citationId: 'catalog-source',
  plainCitation: '(Müller)',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': 'source', 'type': 'book', 'title': 'Source'},
      uris: ['http://zotero.org/users/local/LOCALKEY/items/ABCD1234'],
      locator: '34',
      label: 'page',
    ),
  ],
);

WordZoteroCitingSession _session(WmlDocument document) =>
    WordZoteroCitingSession(
      document: document,
      documentId: _id,
      insertionParagraph: document.paragraphs.single,
      insertionOffset: 7,
    );

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_id, ...args]);

void main() {
  for (final noteType in [0, 1, 2]) {
    test('reads native JSON style, locale and placement $noteType', () {
      final data = _preferences(noteType);
      expect(WordZoteroDocumentData.stylePreferences(data), (
        id: _style,
        locale: 'de-DE',
        noteType: noteType,
      ));
      expect(WordZoteroDocumentData.citationNoteType(data), noteType);
      expect((jsonDecode(data) as Map<String, dynamic>)['extension'], {
        'keep': 'unchanged',
      });
    });

    test('style then seeded placement $noteType remain staged until apply', () {
      final document = WmlDocument.empty(text: 'Before after');
      final session = _session(document);
      _call(session, 'Document.setDocumentData', [_preferences(noteType)]);
      _call(session, 'Document.complete');
      session.continueWithCitation(_citation());
      expect(session.isComplete, isFalse);
      expect(WordZoteroDocumentData.read(document), isEmpty);
      expect(WordZotero.fields(document), isEmpty);
      expect(document.footnotes, isEmpty);
      expect(document.endnotes, isEmpty);
      final seed = _call(session, 'Document.cursorInField', ['Http']) as Map;
      final fieldId = seed['id'] as String;
      expect(seed['noteIndex'], noteType == 0 ? 0 : 1);
      _call(session, 'Field.setCode', [fieldId, seed['code']]);
      _call(session, 'Field.setText', [fieldId, 'Ebd., 34.', true]);
      _call(session, 'Document.complete');
      expect(session.hasAcceptedSeedCitation, isTrue);
      session.apply();
      expect(WordZotero.fields(document).single.cachedText, 'Ebd., 34.');
      expect(document.footnotes, hasLength(noteType == 1 ? 1 : 0));
      expect(document.endnotes, hasLength(noteType == 2 ? 1 : 0));
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(WordZotero.fields(reopened).single.cachedText, 'Ebd., 34.');
      expect(
        WordZoteroDocumentData.stylePreferences(
          WordZoteroDocumentData.read(reopened),
        ),
        (id: _style, locale: 'de-DE', noteType: noteType),
      );
      expect(
        WordZotero.fields(reopened).single.citation!.items.single.locator,
        '34',
      );
    });
  }

  test('native XML summary handles omitted inline placement and locale', () {
    const data =
        '<data data-version="3"><style id="$_style"/>'
        '<prefs><pref name="fieldType" value="Field"/></prefs></data>';
    expect(WordZoteroDocumentData.stylePreferences(data), (
      id: _style,
      locale: null,
      noteType: 0,
    ));
    expect(
      WordZoteroDocumentData.stylePreferences(_preferences(2, locale: '')),
      (id: _style, locale: null, noteType: 2),
    );
  });

  test('unset and incomplete styles cannot place catalog seeds', () {
    for (final data in [
      '',
      '{"prefs":{"fieldType":"Http"}}',
      '{"style":{"styleID":""},"prefs":{"fieldType":"Field","noteType":1}}',
    ]) {
      expect(WordZoteroDocumentData.stylePreferences(data), isNull);
      expect(
        () => WordZoteroDocumentData.citationNoteType(data),
        throwsFormatException,
      );
    }
    expect(
      () => WordZoteroDocumentData.stylePreferences('{broken'),
      throwsFormatException,
    );
    expect(
      () => WordZoteroDocumentData.stylePreferences(_preferences(3)),
      throwsFormatException,
    );
  });

  test('cancelled second picker leaves preferences and sources detached', () {
    final document = WmlDocument.empty(text: 'Before after');
    final session = _session(document);
    _call(session, 'Document.setDocumentData', [_preferences(1)]);
    _call(session, 'Document.complete');
    session.continueWithCitation(_citation());
    _call(session, 'Document.complete');
    expect(session.hasAcceptedSeedCitation, isFalse);
    expect(document.paragraphs.single.text, 'Before after');
    expect(WordZoteroDocumentData.read(document), isEmpty);
    expect(WordZotero.fields(document), isEmpty);
  });

  test('preferences must finish before continuing with catalog sources', () {
    final session = _session(WmlDocument.empty(text: 'Before after'));
    _call(session, 'Document.setDocumentData', [_preferences(1)]);
    expect(() => session.continueWithCitation(_citation()), throwsStateError);
    _call(session, 'Document.complete');
    session.apply();
    expect(() => session.continueWithCitation(_citation()), throwsStateError);
  });

  test('continuation refuses a changed document before creating a seed', () {
    final document = WmlDocument.empty(text: 'Before after');
    final session = _session(document);
    _call(session, 'Document.setDocumentData', [_preferences(1)]);
    _call(session, 'Document.complete');
    document.paragraphs.single.inlines.add(WmlRun(text: ' changed'));
    expect(() => session.continueWithCitation(_citation()), throwsStateError);
    expect(WordZotero.fields(document), isEmpty);
    expect(WordZoteroDocumentData.read(document), isEmpty);
  });
}
