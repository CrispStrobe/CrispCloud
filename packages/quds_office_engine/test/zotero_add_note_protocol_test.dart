import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _id = 'native-research-note';
ZoteroHttpResponse _command(String name, List<Object?> args) =>
    ZoteroHttpResponse(
      statusCode: 200,
      body: jsonEncode(<String, Object?>{'command': name, 'arguments': args}),
    );
Map<String, Object?> _active() => <String, Object?>{
  'documentID': _id,
  'outputFormat': 'html',
  'supportedNotes': ['footnotes', 'endnotes'],
  'supportsTextInsertion': true,
  'supportsImportExport': false,
  'supportsCitationMerging': false,
};
Map<String, Object?> _field(String id) => <String, Object?>{
  'id': id,
  'code': 'TEMP',
  'text': '(Citation)',
  'noteIndex': 0,
};

void main() {
  for (final operation in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    test(
      '${operation.name} uses Zotero text insertion and returns fields in request order',
      () async {
        final document = WmlDocument.empty(text: 'Body');
        final session = WordZoteroCitingSession(
          document: document,
          documentId: _id,
          insertionParagraph: document.paragraphs.first,
          insertionOffset: 4,
        );
        final citation = ZoteroCitation(
          citationId: 'source',
          plainCitation: '(Source)',
          items: [
            ZoteroCitationItem.fromCsl(
              itemData: <String, Object?>{
                'id': 'source',
                'type': 'book',
                'title': 'Source',
              },
              uris: ['http://zotero.org/users/42/items/ABCD1234'],
            ),
          ],
        );
        final commands = <(String, List<Object?>)>[
          ('Application.getActiveDocument', []),
          ('Document.canInsertField', [_id, 'Http']),
          ('Document.insertField', [_id, 'Http', 0]),
          ('Field.delete', [_id, 'f0']),
          (
            'Document.insertText',
            [
              _id,
              '<p>A quote <a href="https://www.zotero.org/?ABC123">(Citation)</a></p>',
            ],
          ),
          (
            'Document.convertPlaceholdersToFields',
            [
              _id,
              ['ABC123'],
              0,
              'Http',
            ],
          ),
          (
            'Field.setCode',
            [_id, 'f1', 'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}'],
          ),
          ('Field.setText', [_id, 'f1', '<i>Source</i> (2026)', true]),
          ('Document.complete', [_id]),
        ];
        final requests = <ZoteroHttpRequest>[];
        await ZoteroCitingClient(
          transport: (request) async {
            requests.add(request);
            if (requests.length == 1) {
              expect(jsonDecode(request.body!), {
                'command': operation.name,
                'docId': _id,
              });
            }
            if (requests.length == 2) {
              expect(
                (jsonDecode(request.body!)
                    as Map<String, Object?>)['supportsTextInsertion'],
                isTrue,
              );
            }
            if (requests.length == 7) {
              final fields = (jsonDecode(request.body!) as List<Object?>)
                  .cast<Map<String, Object?>>();
              expect(fields.single['id'], 'f1');
              expect(fields.single['text'], '(Citation)');
            }
            final command = commands[requests.length - 1];
            return _command(command.$1, command.$2);
          },
        ).execute(command: operation, documentId: _id, handler: session.handle);
        expect(requests.length, commands.length);
        expect(document.paragraphs.single.text, 'Body');
        session.apply();
        expect(document.paragraphs.single.text, 'BodyA quote Source (2026)');
        expect(
          WordZotero.fields(document).single.citation!.citationId,
          'source',
        );
      },
    );
  }

  test(
    'Add Annotation error alert drains and refuses staged preferences',
    () async {
      final document = WmlDocument.empty(text: 'Unchanged');
      final beforeData = WordZoteroDocumentData.read(document);
      final session = WordZoteroCitingSession(
        document: document,
        documentId: _id,
        insertionParagraph: document.paragraphs.single,
        insertionOffset: 0,
      );
      final stagedData = jsonEncode({
        'dataVersion': 4,
        'sessionID': 'annotation-error',
        'zoteroVersion': '8.0',
        'style': {
          'styleID': 'http://www.zotero.org/styles/apa',
          'locale': 'de-DE',
        },
        'prefs': {'fieldType': 'Http', 'noteType': 0},
      });
      // Zotero's unknown-command dispatch reaches its STOP/YES_NO error path.
      // Stage preferences first to prove that cleanup cannot apply pending data.
      final commands = <(String, List<Object?>)>[
        ('Application.getActiveDocument', []),
        ('Document.setDocumentData', [_id, stagedData]),
        ('Document.displayAlert', [_id, 'Native operation unavailable', 0, 2]),
        ('Document.setDocumentData', [_id, stagedData]),
        ('Document.complete', [_id]),
      ];
      final requests = <ZoteroHttpRequest>[];
      final handled = <String>[];
      await expectLater(
        ZoteroCitingClient(
          transport: (request) async {
            requests.add(request);
            final command = commands[requests.length - 1];
            return _command(command.$1, command.$2);
          },
        ).execute(
          command: ZoteroCitingCommand.addAnnotation,
          documentId: _id,
          handler: (name, arguments) {
            handled.add(name);
            if (name == 'Document.displayAlert') return 0;
            return session.handle(name, arguments);
          },
        ),
        throwsA(
          isA<ZoteroCitingException>()
              .having(
                (error) => error.kind,
                'kind',
                ZoteroCitingErrorKind.document,
              )
              .having(
                (error) => error.desktopMayNeedRestart,
                'desktopMayNeedRestart',
                isFalse,
              ),
        ),
      );
      expect(handled, [
        'Application.getActiveDocument',
        'Document.setDocumentData',
        'Document.displayAlert',
      ]);
      expect(requests, hasLength(commands.length));
      expect(jsonDecode(requests.first.body!), {
        'command': 'addAnnotation',
        'docId': _id,
      });
      expect(
        requests.where((request) => request.uri.path.endsWith('/execCommand')),
        hasLength(1),
      );
      expect(jsonDecode(requests[3].body!), 0);
      expect(jsonDecode(requests[4].body!), containsPair('error', 'Alert'));
      expect(session.documentData, contains('annotation-error'));
      expect(session.isComplete, isFalse);
      expect(session.apply, throwsStateError);
      expect(document.paragraphs.single.text, 'Unchanged');
      expect(WordZoteroDocumentData.read(document), beforeData);
      expect(WordZotero.fields(document), isEmpty);
    },
  );

  for (final args in <List<Object?>>[
    [_id, 42],
    [_id, '<p>text</p>', 'extra'],
  ]) {
    test(
      'malformed insertText arguments are rejected before handler: $args',
      () async {
        var requests = 0;
        var handled = false;
        await expectLater(
          ZoteroCitingClient(
            transport: (_) async => ++requests == 1
                ? _command('Document.insertText', args)
                : _command('Document.complete', [_id]),
          ).execute(
            command: ZoteroCitingCommand.addNote,
            documentId: _id,
            handler: (_, _) {
              handled = true;
              return null;
            },
          ),
          throwsA(
            isA<ZoteroCitingException>().having(
              (e) => e.kind,
              'kind',
              ZoteroCitingErrorKind.invalidResponse,
            ),
          ),
        );
        expect(handled, isFalse);
        expect(requests, 2);
      },
    );
  }

  for (final args in <List<Object?>>[
    [
      _id,
      ['ABC123', 'ABC123'],
      0,
      'Http',
    ],
    [
      _id,
      ['ABC123'],
      '0',
      'Http',
    ],
    [
      _id,
      ['ABC123'],
      3,
      'Http',
    ],
    [
      _id,
      ['ABC123'],
      0,
      'Field',
    ],
    [
      _id,
      ['ABC/123'],
      0,
      'Http',
    ],
    [_id, 'ABC123', 0, 'Http'],
  ]) {
    test('invalid placeholder conversion shape is drained: $args', () async {
      var n = 0;
      var handled = false;
      await expectLater(
        ZoteroCitingClient(
          transport: (_) async => ++n == 1
              ? _command('Document.convertPlaceholdersToFields', args)
              : _command('Document.complete', [_id]),
        ).execute(
          command: ZoteroCitingCommand.addNote,
          documentId: _id,
          handler: (_, _) {
            handled = true;
            return null;
          },
        ),
        throwsA(
          isA<ZoteroCitingException>().having(
            (e) => e.kind,
            'kind',
            ZoteroCitingErrorKind.invalidResponse,
          ),
        ),
      );
      expect(handled, isFalse);
      expect(n, 2);
    });
  }

  for (final response in <List<Object?>>[
    [],
    [_field('same'), _field('same')],
    [_field('known'), _field('new')],
  ]) {
    test(
      'conversion must return exactly distinct new field identities: $response',
      () async {
        var n = 0;
        await expectLater(
          ZoteroCitingClient(
            transport: (_) async {
              n++;
              return switch (n) {
                1 => _command('Document.getFields', [_id, 'Http']),
                2 => _command('Document.convertPlaceholdersToFields', [
                  _id,
                  ['ABC123', 'DEF456'],
                  0,
                  'Http',
                ]),
                _ => _command('Document.complete', [_id]),
              };
            },
          ).execute(
            command: ZoteroCitingCommand.addNote,
            documentId: _id,
            handler: (name, _) =>
                name == 'Document.getFields' ? [_field('known')] : response,
          ),
          throwsA(
            isA<ZoteroCitingException>().having(
              (e) => e.kind,
              'kind',
              ZoteroCitingErrorKind.invalidResponse,
            ),
          ),
        );
        expect(n, 3);
      },
    );
  }

  test('text insertion capability must be a boolean', () async {
    var n = 0;
    await expectLater(
      ZoteroCitingClient(
        transport: (_) async => ++n == 1
            ? _command('Application.getActiveDocument', [])
            : _command('Document.complete', [_id]),
      ).execute(
        command: ZoteroCitingCommand.addNote,
        documentId: _id,
        handler: (_, _) => {..._active(), 'supportsTextInsertion': 'yes'},
      ),
      throwsA(
        isA<ZoteroCitingException>().having(
          (e) => e.kind,
          'kind',
          ZoteroCitingErrorKind.invalidResponse,
        ),
      ),
    );
    expect(n, 2);
  });
}
