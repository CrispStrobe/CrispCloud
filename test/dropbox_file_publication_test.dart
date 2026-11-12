import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/conditional_file_publication.dart';
import 'package:crisp_cloud/services/dropbox_client_adapter.dart';
import 'package:crisp_cloud/services/dropbox_file_publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const originalPath = '/notes/café #1 😀.txt';
const originalId = 'id:original';
const originalRevision = 'abc123456';
final original = Uint8List.fromList([1, 2]);
final account = sha256
    .convert(utf8.encode('dropbox-account:dbid:original'))
    .toString();

Map<String, Object> metadata(
  List<int> bytes, {
  String id = originalId,
  String revision = originalRevision,
  String path = originalPath,
}) => {
  '.tag': 'file',
  'path_lower': path.toLowerCase(),
  'path_display': path,
  'id': id,
  'rev': revision,
  'size': bytes.length,
  'content_hash': DropboxClientAdapter.computeContentHash(bytes),
  'is_downloadable': true,
};

http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);

Matcher failure(FilePublicationFailure value) => isA<FilePublicationException>()
    .having((error) => error.failure, 'failure', value);

FilePublicationVersion version() => FilePublicationVersion(
  accountIdentity: account,
  path: originalPath.toLowerCase(),
  objectId: originalId,
  revision: originalRevision,
  length: original.length,
  contentHash: DropboxClientAdapter.computeContentHash(original),
);

class Transport {
  final requests = <http.Request>[];
  final uploaded = <int>[];
  Map<String, Object> current = metadata(original);
  String accountId = 'dbid:original';
  Future<http.Response?> Function(http.Request)? intercept;
  bool prepared = false;
  int finishes = 0;

  Future<http.Response> send(http.Request request) async {
    requests.add(request);
    final intercepted = await intercept?.call(request);
    if (intercepted != null) return intercepted;
    final path = request.url.path;
    if (path.endsWith('/get_current_account')) {
      return response({'account_id': accountId});
    }
    if (path.endsWith('/get_metadata')) return response(current);
    if (path.endsWith('/start')) return response({'session_id': 'session'});
    if (path.endsWith('/append_v2')) {
      uploaded.addAll(request.bodyBytes);
      return response({});
    }
    if (path.endsWith('/finish')) {
      expect(prepared, isTrue);
      finishes++;
      current = metadata(uploaded, revision: 'abc123457');
      return response(current);
    }
    if (path.endsWith('/download')) {
      return http.Response.bytes(
        original,
        200,
        headers: {
          'dropbox-api-result': jsonEncode(current),
          'content-length': original.length.toString(),
        },
      );
    }
    fail('Unexpected request ${request.url.path}');
  }

  Future<T> run<T>(Future<T> Function(DropboxFilePublication) action) =>
      http.runWithClient(
        () => action(
          DropboxFilePublication(accessToken: () async => 'captured-token'),
        ),
        () => MockClient(send),
      );
}

void main() {
  test(
    'whole publication deadline stops a source that continues to drip bytes',
    () async {
      final transport = Transport();
      var now = DateTime.utc(2026);
      Stream<List<int>> contents() async* {
        yield [3];
        now = now.add(const Duration(minutes: 3));
        yield [4];
      }

      await transport.run((_) async {
        final publisher = DropboxFilePublication(
          accessToken: () async => 'captured-token',
          now: () => now,
        );
        await expectLater(
          publisher.publishFileVersion(
            version(),
            contents(),
            length: 2,
            checkCurrent: () {},
            prepareCommit: (_) async {
              fail('Deadline must precede durable commit');
            },
          ),
          throwsA(failure(FilePublicationFailure.unavailable)),
        );
      });
      expect(transport.finishes, 0);
    },
  );

  test(
    'fresh version binds immutable account, exact path, object and revision',
    () async {
      final transport = Transport();
      await transport.run((publisher) async {
        expect(
          await publisher.inspectForPublication(
            originalPath,
            checkCurrent: () {},
          ),
          version(),
        );
        expect(FilePublicationVersion.fromJson(version().toJson()), version());
      });
      for (final request in transport.requests) {
        expect(request.headers['authorization'], 'Bearer captured-token');
      }
    },
  );

  test('conditional commit is bounded, literal, revision guarded and durably prepared', () async {
    final transport = Transport();
    final bytes = Uint8List(4 * 1024 * 1024 + 3)..[0] = 7;
    await transport.run((publisher) async {
      final result = await publisher.publishFileVersion(
        version(),
        Stream.value(bytes),
        length: bytes.length,
        checkCurrent: () {},
        prepareCommit: (hash) async {
          expect(transport.finishes, 0);
          expect(transport.uploaded, bytes);
          expect(hash, DropboxClientAdapter.computeContentHash(bytes));
          transport.prepared = true;
        },
      );
      expect(result.sameObject(version()), isTrue);
      expect(result.revision, 'abc123457');
      expect(result.length, bytes.length);
    });
    final content = transport.requests.where(
      (r) => r.url.host == 'content.dropboxapi.com',
    );
    for (final request in content) {
      expect(request.followRedirects, isFalse);
      expect(request.bodyBytes.length, lessThanOrEqualTo(4 * 1024 * 1024));
      expect(
        request.headers['dropbox-api-arg']!.codeUnits.every(
          (unit) => unit < 127,
        ),
        isTrue,
      );
    }
    final finish = jsonDecode(content.last.headers['dropbox-api-arg']!) as Map;
    expect(finish['commit'], {
      'path': originalPath.toLowerCase(),
      'mode': {'.tag': 'update', 'update': originalRevision},
      'autorename': false,
      'strict_conflict': true,
      'mute': false,
    });
    expect(content.last.bodyBytes, isEmpty);
    expect(transport.finishes, 1);
  });

  test(
    'revision download uses revision identity and verifies complete content',
    () async {
      final transport = Transport();
      await transport.run((publisher) async {
        final bytes = await publisher
            .readForPublication(version(), checkCurrent: () {})
            .fold<List<int>>([], (all, part) => all..addAll(part));
        expect(bytes, original);
      });
      final request = transport.requests.last;
      expect(jsonDecode(request.headers['dropbox-api-arg']!), {
        'path': 'rev:$originalRevision',
      });
    },
  );

  test(
    'same email with another immutable account never downloads or uploads',
    () async {
      final transport = Transport()..accountId = 'dbid:replacement';
      await transport.run((publisher) async {
        await expectLater(
          publisher.publishFileVersion(
            version(),
            Stream.value([3]),
            length: 1,
            checkCurrent: () {},
            prepareCommit: (_) async {},
          ),
          throwsA(failure(FilePublicationFailure.changed)),
        );
        await expectLater(
          publisher
              .readForPublication(version(), checkCurrent: () {})
              .drain<void>(),
          throwsA(failure(FilePublicationFailure.changed)),
        );
      });
      expect(
        transport.requests.every((r) => r.url.host == 'api.dropboxapi.com'),
        isTrue,
      );
    },
  );

  for (final change in ['id', 'rev', 'path', 'deleted']) {
    test('fresh $change conflict cannot start a replacement upload', () async {
      final transport = Transport();
      if (change == 'id') transport.current['id'] = 'id:replacement';
      if (change == 'rev') transport.current['rev'] = 'abc123499';
      if (change == 'path') transport.current['path_lower'] = '/another.txt';
      if (change == 'deleted') transport.current['.tag'] = 'deleted';
      await transport.run((publisher) async {
        await expectLater(
          publisher.publishFileVersion(
            version(),
            Stream.value([3]),
            length: 1,
            checkCurrent: () {},
            prepareCommit: (_) async {},
          ),
          throwsA(isA<FilePublicationException>()),
        );
      });
      expect(
        transport.requests.any((r) => r.url.host == 'content.dropboxapi.com'),
        isFalse,
      );
    });
  }

  test('late stream failure and length mismatch never reach commit', () async {
    for (final source in [
      Stream<List<int>>.error(StateError('snapshot changed')),
      Stream<List<int>>.value([3, 4]),
    ]) {
      final transport = Transport();
      await transport.run((publisher) async {
        await expectLater(
          publisher.publishFileVersion(
            version(),
            source,
            length: 1,
            checkCurrent: () {},
            prepareCommit: (_) async {
              fail('Must not prepare a failed stream');
            },
          ),
          throwsA(anything),
        );
      });
      expect(transport.finishes, 0);
    }
  });

  test(
    'cancelled or changed prepared review leaves original untouched',
    () async {
      final transport = Transport();
      await transport.run((publisher) async {
        await expectLater(
          publisher.publishFileVersion(
            version(),
            Stream.value([3]),
            length: 1,
            checkCurrent: () {},
            prepareCommit: (_) async {
              throw StateError('New local generation or cancelled review');
            },
          ),
          throwsStateError,
        );
      });
      expect(transport.finishes, 0);
    },
  );

  test(
    'revision race at finish is a conflict, with no overwrite retry',
    () async {
      final transport = Transport()..prepared = true;
      transport.intercept = (request) async =>
          request.url.path.endsWith('/finish')
          ? response({
              'error': {
                '.tag': 'path',
                'path': {'.tag': 'conflict'},
              },
            }, 409)
          : null;
      await transport.run((publisher) async {
        await expectLater(
          publisher.publishFileVersion(
            version(),
            Stream.value([3]),
            length: 1,
            checkCurrent: () {},
            prepareCommit: (_) async {},
          ),
          throwsA(failure(FilePublicationFailure.conflict)),
        );
      });
      expect(
        transport.requests.where((r) => r.url.path.endsWith('/finish')).length,
        1,
      );
    },
  );

  for (final outcome in [
    'lost acknowledgement',
    'other object',
    'wrong hash',
    'properties_error',
    'other',
  ]) {
    test(
      '$outcome retains an uncertain result and never compensates',
      () async {
        final transport = Transport()..prepared = true;
        transport.intercept = (request) async {
          if (!request.url.path.endsWith('/finish')) return null;
          if (outcome == 'lost acknowledgement') {
            throw http.ClientException('offline');
          }
          if (outcome == 'properties_error' || outcome == 'other') {
            return response({
              'error': {'.tag': outcome},
            }, 409);
          }
          final value = metadata([3], revision: 'abc123457');
          if (outcome == 'other object') value['id'] = 'id:replacement';
          if (outcome == 'wrong hash') value['content_hash'] = '0' * 64;
          return response(value);
        };
        await transport.run((publisher) async {
          await expectLater(
            publisher.publishFileVersion(
              version(),
              Stream.value([3]),
              length: 1,
              checkCurrent: () {},
              prepareCommit: (_) async {},
            ),
            throwsA(failure(FilePublicationFailure.uncertain)),
          );
        });
        expect(
          transport.requests.any((r) => r.url.path.contains('/delete')),
          isFalse,
        );
        expect(
          transport.requests
              .where((r) => r.url.path.endsWith('/finish'))
              .length,
          1,
        );
      },
    );
  }

  test(
    'source guard is checked at request boundary after durable preparation',
    () async {
      final transport = Transport();
      var current = true;
      await transport.run((publisher) async {
        await expectLater(
          publisher.publishFileVersion(
            version(),
            Stream.value([3]),
            length: 1,
            checkCurrent: () {
              if (!current) throw StateError('account changed');
            },
            prepareCommit: (_) async {
              current = false;
            },
          ),
          throwsStateError,
        );
      });
      expect(transport.finishes, 0);
    },
  );
}
