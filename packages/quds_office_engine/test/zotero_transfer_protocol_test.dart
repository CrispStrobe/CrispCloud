import 'dart:convert';

import 'package:quds_office_engine/src/zotero/zotero_citing.dart';
import 'package:quds_office_engine/src/zotero/zotero_client.dart';
import 'package:test/test.dart';

const _doc = 'quds-transfer-document';
const _marker = 'ZOTERO_TRANSFER_DOCUMENT';
const _preferences =
    '{"dataVersion":4,"prefs":{"fieldType":"Http"},'
    '"style":{"bibliographyStyleHasBeenSet":false}}';
const _instructions = 'Open this copy in another word processor and refresh.';

ZoteroHttpResponse _command(String command, List<Object?> arguments) =>
    ZoteroHttpResponse(
      statusCode: 200,
      body: jsonEncode(<String, Object?>{
        'command': command,
        'arguments': arguments,
      }),
    );

Map<String, Object?> _active({bool supportsTransfer = true}) =>
    <String, Object?>{
      'documentID': _doc,
      'outputFormat': 'html',
      'supportedNotes': <String>['footnotes', 'endnotes'],
      'supportsImportExport': supportsTransfer,
      'processorName': 'Quds Office',
    };

Map<String, Object?> _field(String id, {int noteIndex = 0}) =>
    <String, Object?>{
      'id': id,
      'code': 'ITEM CSL_CITATION {"citationID":"$id"}',
      'text': '{Imported field}',
      'noteIndex': noteIndex,
    };

TypeMatcher<ZoteroCitingException> _invalid() => isA<ZoteroCitingException>()
    .having(
      (error) => error.kind,
      'kind',
      ZoteroCitingErrorKind.invalidResponse,
    )
    .having(
      (error) => error.desktopMayNeedRestart,
      'desktopMayNeedRestart',
      isFalse,
    );

typedef _Step = ({String command, List<Object?> arguments, Object? result});

Future<void> _replay(
  List<_Step> transcript, {
  ZoteroCitingCommand operation = ZoteroCitingCommand.refresh,
}) async {
  var requestIndex = 0;
  var handlerIndex = 0;
  await ZoteroCitingClient(
    transport: (request) async {
      expect(
        request.uri.path,
        requestIndex == 0
            ? '/connector/document/execCommand'
            : '/connector/document/respond',
      );
      expect(
        jsonDecode(request.body!),
        requestIndex == 0
            ? <String, Object?>{'command': operation.name, 'docId': _doc}
            : transcript[requestIndex - 1].result,
      );
      final step = transcript[requestIndex++];
      return _command(step.command, step.arguments);
    },
  ).execute(
    command: operation,
    documentId: _doc,
    handler: (command, arguments) {
      final step = transcript[handlerIndex++];
      expect(command, step.command);
      expect(arguments, step.arguments);
      return step.result;
    },
  );
  // Document.complete is terminal: no HTTP acknowledgement follows it.
  expect(requestIndex, transcript.length);
  expect(handlerIndex, transcript.length);
}

void main() {
  // The core invokes exportDocument(fieldType, importInstructions). The HTTP
  // wrapper prepends documentId. Verified in zotero/zotero at commit
  // ebdf94eda5257292967ebe39ea06a9a5ed31d15c, integration.js and
  // httpIntegrationClient.js; the serialized preferences remain opaque.
  test(
    'export command preserves field type, instructions and preferences',
    () async {
      await _replay(<_Step>[
        (
          command: 'Application.getActiveDocument',
          arguments: <Object?>[],
          result: _active(),
        ),
        (
          command: 'Document.setDocumentData',
          arguments: <Object?>[_doc, _preferences],
          result: null,
        ),
        (
          command: 'Document.exportDocument',
          arguments: <Object?>[_doc, 'Http', _instructions],
          result: null,
        ),
        (
          command: 'Document.setDocumentData',
          arguments: <Object?>[_doc, _preferences],
          result: null,
        ),
        (
          command: 'Document.activate',
          arguments: <Object?>[_doc],
          result: null,
        ),
        (
          command: 'Document.complete',
          arguments: <Object?>[_doc],
          result: null,
        ),
      ], operation: ZoteroCitingCommand.exportDocument);
    },
  );

  test(
    'refresh imports transfer data then updates freshly enumerated fields',
    () async {
      await _replay(<_Step>[
        (
          command: 'Application.getActiveDocument',
          arguments: <Object?>[],
          result: _active(),
        ),
        (
          command: 'Document.getFields',
          arguments: <Object?>[_doc, 'Http'],
          result: <Object?>[_field('before-import')],
        ),
        (
          command: 'Document.getDocumentData',
          arguments: <Object?>[_doc],
          result: _marker,
        ),
        (
          command: 'Document.importDocument',
          arguments: <Object?>[_doc, 'Http'],
          result: true,
        ),
        (
          command: 'Document.getDocumentData',
          arguments: <Object?>[_doc],
          result: _preferences,
        ),
        (
          command: 'Document.getFields',
          arguments: <Object?>[_doc, 'Http'],
          result: <Object?>[
            _field('imported-body'),
            _field('imported-note', noteIndex: 2),
          ],
        ),
        (
          command: 'Field.setText',
          arguments: <Object?>[
            _doc,
            'imported-note',
            '<i>Source</i> (2026)',
            true,
          ],
          result: null,
        ),
        (
          command: 'Document.complete',
          arguments: <Object?>[_doc],
          result: null,
        ),
      ]);
    },
  );

  test('false import result preserves the existing field identities', () async {
    await _replay(<_Step>[
      (
        command: 'Document.getFields',
        arguments: <Object?>[_doc, 'Http'],
        result: <Object?>[_field('existing')],
      ),
      (
        command: 'Document.importDocument',
        arguments: <Object?>[_doc, 'Http'],
        result: false,
      ),
      (
        command: 'Field.select',
        arguments: <Object?>[_doc, 'existing'],
        result: null,
      ),
      (command: 'Document.complete', arguments: <Object?>[_doc], result: null),
    ]);
  });

  for (final capability in <bool>[false, true]) {
    test('transfer capability $capability is sent as a boolean', () async {
      await _replay(<_Step>[
        (
          command: 'Application.getActiveDocument',
          arguments: <Object?>[],
          result: _active(supportsTransfer: capability),
        ),
        (
          command: 'Document.complete',
          arguments: <Object?>[_doc],
          result: null,
        ),
      ]);
    });
  }

  for (final invalid in <({String name, List<Object?> arguments})>[
    (
      name: 'Document.exportDocument',
      arguments: <Object?>[_doc, _instructions],
    ),
    (
      name: 'Document.exportDocument',
      arguments: <Object?>[_doc, 'Field', _instructions],
    ),
    (name: 'Document.exportDocument', arguments: <Object?>[_doc, 'Http', null]),
    (name: 'Document.exportDocument', arguments: <Object?>[_doc, 'Http', 42]),
    (
      name: 'Document.exportDocument',
      arguments: <Object?>[_doc, 'Http', _instructions, 'extra'],
    ),
    (
      name: 'Document.exportDocument',
      arguments: <Object?>['another-document', 'Http', _instructions],
    ),
    (name: 'Document.importDocument', arguments: <Object?>[_doc]),
    (
      name: 'Document.importDocument',
      arguments: <Object?>[_doc, 'ReferenceMark'],
    ),
    (
      name: 'Document.importDocument',
      arguments: <Object?>[_doc, 'Http', 'extra'],
    ),
    (
      name: 'Document.importDocument',
      arguments: <Object?>['another-document', 'Http'],
    ),
  ]) {
    test(
      'rejects malformed ${invalid.name} arguments ${invalid.arguments}',
      () async {
        var requests = 0;
        var handled = false;
        await expectLater(
          ZoteroCitingClient(
            transport: (request) async {
              if (++requests == 1) {
                return _command(invalid.name, invalid.arguments);
              }
              expect(jsonDecode(request.body!), containsPair('error', 'Alert'));
              return _command('Document.complete', <Object?>[_doc]);
            },
          ).execute(
            command: ZoteroCitingCommand.refresh,
            documentId: _doc,
            handler: (_, _) {
              handled = true;
              return null;
            },
          ),
          throwsA(_invalid()),
        );
        expect(handled, isFalse);
        expect(requests, 2);
      },
    );
  }

  for (final value in <Object?>[null, 1, 'true', <Object?>[]]) {
    test('import requires a boolean result instead of $value', () async {
      var requests = 0;
      await expectLater(
        ZoteroCitingClient(
          transport: (request) async => ++requests == 1
              ? _command('Document.importDocument', <Object?>[_doc, 'Http'])
              : _command('Document.complete', <Object?>[_doc]),
        ).execute(
          command: ZoteroCitingCommand.refresh,
          documentId: _doc,
          handler: (_, _) => value,
        ),
        throwsA(_invalid()),
      );
      expect(requests, 2);
    });
  }

  for (final callback in <String>[
    'Document.importDocument',
    'Document.exportDocument',
  ]) {
    test('$callback invalidates field identities until rediscovered', () async {
      var requests = 0;
      final handled = <String>[];
      final replies = <ZoteroHttpResponse>[
        _command('Document.getFields', <Object?>[_doc, 'Http']),
        _command(callback, <Object?>[
          _doc,
          'Http',
          if (callback == 'Document.exportDocument') _instructions,
        ]),
        _command('Field.setText', <Object?>[
          _doc,
          'stale',
          'Wrong field',
          true,
        ]),
        _command('Document.complete', <Object?>[_doc]),
      ];
      await expectLater(
        ZoteroCitingClient(
          transport: (request) async {
            if (requests == 3) {
              expect(jsonDecode(request.body!), containsPair('error', 'Alert'));
            }
            return replies[requests++];
          },
        ).execute(
          command: ZoteroCitingCommand.refresh,
          documentId: _doc,
          handler: (name, _) {
            handled.add(name);
            return switch (name) {
              'Document.getFields' => <Object?>[_field('stale')],
              'Document.importDocument' => true,
              _ => null,
            };
          },
        ),
        throwsA(_invalid()),
      );
      expect(handled, <String>['Document.getFields', callback]);
      expect(requests, replies.length);
    });
  }

  test(
    'failed transfer drains desktop callbacks without mutating the adapter',
    () async {
      var requests = 0;
      final handled = <String>[];
      final replies = <ZoteroHttpResponse>[
        _command('Document.exportDocument', <Object?>[
          _doc,
          'Http',
          _instructions,
        ]),
        _command('Document.setDocumentData', <Object?>[_doc, _preferences]),
        _command('Document.complete', <Object?>[_doc]),
      ];
      await expectLater(
        ZoteroCitingClient(
          transport: (request) async {
            if (requests > 0) {
              expect(jsonDecode(request.body!), containsPair('error', 'Alert'));
            }
            return replies[requests++];
          },
        ).execute(
          command: ZoteroCitingCommand.exportDocument,
          documentId: _doc,
          handler: (name, _) {
            handled.add(name);
            throw StateError('Transfer cannot be represented safely');
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
      expect(handled, <String>['Document.exportDocument']);
      expect(requests, replies.length);
    },
  );
}
