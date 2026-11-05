import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/file_action_requests.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.handle);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handle;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handle(request);
}

void main() {
  final uri = Uri.https('api.example.test', '/file');
  test('disconnected source makes no request', () async {
    var requests = 0;
    final action = FileActionRequests(
      ensureCurrent: () => throw StateError('Disconnected'),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(action.request('POST', uri), throwsStateError);
    expect(requests, 0);
  });
  test('disconnection after headers cancels body', () async {
    var connected = true;
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final action = FileActionRequests(
      ensureCurrent: () {
        if (!connected) {
          throw StateError('Disconnected');
        }
      },
      client: _StreamingClient((_) async {
        connected = false;
        return http.StreamedResponse(stream.stream, 200);
      }),
    );
    await expectLater(action.request('GET', uri), throwsStateError);
    expect(cancelled, isTrue);
    await stream.close();
  });
  test('oversized metadata cancels a still-producing response', () async {
    var consumed = 0;
    var finished = false;
    Stream<List<int>> data() async* {
      try {
        for (var i = 0; i < 10; i++) {
          consumed++;
          yield List.filled(8, 1);
        }
      } finally {
        finished = true;
      }
    }

    final action = FileActionRequests(
      ensureCurrent: () {},
      client: _StreamingClient((_) async => http.StreamedResponse(data(), 200)),
    );
    await expectLater(
      action.request('GET', uri, maxBytes: 10),
      throwsStateError,
    );
    expect(consumed, 2);
    expect(finished, isTrue);
  });
  test('cross-origin GET redirects strip all account credentials', () async {
    final requests = <http.Request>[];
    final action = FileActionRequests(
      ensureCurrent: () {},
      client: MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://download.example.test/content?signature=secret',
            },
          );
        }
        return http.Response('content', 200);
      }),
    );
    expect(
      (await action.request(
        'GET',
        uri,
        headers: {
          'Authorization': 'Bearer account-b',
          'Dropbox-API-Arg': 'secret',
        },
      )).body,
      'content',
    );
    expect(requests.last.headers, isEmpty);
  });
  test(
    'POST redirects are not followed and GET cannot downgrade to HTTP',
    () async {
      var calls = 0;
      final action = FileActionRequests(
        ensureCurrent: () {},
        client: MockClient((_) async {
          calls++;
          return http.Response(
            '',
            307,
            headers: {'location': 'http://unsafe.test/file'},
          );
        }),
      );
      expect((await action.request('POST', uri)).statusCode, 307);
      expect(calls, 1);
      await expectLater(action.request('GET', uri), throwsStateError);
      expect(calls, 2);
    },
  );
  test('closed action refuses follow-up requests', () async {
    var calls = 0;
    final action = FileActionRequests(
      ensureCurrent: () {},
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    action.close();
    await expectLater(action.request('PATCH', uri), throwsStateError);
    expect(calls, 0);
  });
  test(
    'Drive restore streams bounded parts to the exact captured file ID',
    () async {
      const length = 2 * 1024 * 1024 + 3;
      final requests = <http.Request>[];
      final action = FileActionRequests(
        ensureCurrent: () {},
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response.bytes(Uint8List(length), 200);
          }
          if (request.method == 'PATCH') {
            return http.Response(
              '',
              200,
              headers: {
                'location': 'https://www.googleapis.com/upload/session',
              },
            );
          }
          if (request.bodyBytes.length == 2 * 1024 * 1024) {
            return http.Response(
              '',
              308,
              headers: {'range': 'bytes=0-2097151'},
            );
          }
          return http.Response(
            json.encode({'id': 'exact/id', 'size': '$length'}),
            200,
          );
        }),
      );
      await action.restoreDriveRevision(
        fileId: 'exact/id',
        revisionId: 'r/2',
        token: 'account-b',
        expectedLength: length,
      );
      expect(requests.first.url.pathSegments, [
        'drive',
        'v3',
        'files',
        'exact/id',
        'revisions',
        'r/2',
      ]);
      expect(requests[1].url.pathSegments.last, 'exact/id');
      final parts = requests.where((r) => r.method == 'PUT').toList();
      expect(parts.map((r) => r.bodyBytes.length), [2 * 1024 * 1024, 3]);
      expect(
        parts.last.headers['Content-Range'],
        'bytes 2097152-2097154/$length',
      );
      expect(
        requests.every((r) => r.headers['Authorization'] == 'Bearer account-b'),
        isTrue,
      );
    },
  );
  test('Drive restore rejects extra bytes before the final commit', () async {
    var puts = 0;
    final action = FileActionRequests(
      ensureCurrent: () {},
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response.bytes([1, 2, 3, 4], 200);
        }
        if (request.method == 'PATCH') {
          return http.Response(
            '',
            200,
            headers: {'location': 'https://www.googleapis.com/session'},
          );
        }
        puts++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      action.restoreDriveRevision(
        fileId: 'a',
        revisionId: 'r',
        token: 't',
        expectedLength: 3,
      ),
      throwsStateError,
    );
    expect(puts, 0);
  });
  test('Drive restore rejects an unrelated upload host', () async {
    var puts = 0;
    final action = FileActionRequests(
      ensureCurrent: () {},
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response.bytes([1], 200);
        }
        if (request.method == 'PATCH') {
          return http.Response(
            '',
            200,
            headers: {
              'location': 'https://googleapis.com.attacker.test/session',
            },
          );
        }
        puts++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      action.restoreDriveRevision(
        fileId: 'a',
        revisionId: 'r',
        token: 't',
        expectedLength: 1,
      ),
      throwsStateError,
    );
    expect(puts, 0);
  });
  test('Drive restore validates completed identity and length', () async {
    final action = FileActionRequests(
      ensureCurrent: () {},
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response.bytes([], 200);
        }
        return http.Response('{"id":"other","size":"0"}', 200);
      }),
    );
    await expectLater(
      action.restoreDriveRevision(
        fileId: 'a',
        revisionId: 'r',
        token: 't',
        expectedLength: 0,
      ),
      throwsStateError,
    );
  });
}
