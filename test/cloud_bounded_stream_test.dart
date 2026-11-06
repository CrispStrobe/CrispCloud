import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/bounded_transfer_stream.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/gdrive_client_adapter.dart';
import 'package:crisp_cloud/services/gdrive_config_service.dart';
import 'package:crisp_cloud/services/onedrive_client_adapter.dart';
import 'package:crisp_cloud/services/onedrive_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

Future<CloudStorageClient> _adapter(bool google) async {
  final credentials = {
    'client_id': 'fixture-app',
    'refresh_token': 'fixture-refresh',
    'email': 'fixture@example.test',
  };
  if (google) {
    final config = GDriveConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    await config.saveCredentials(credentials);
    final adapter = GDriveClientAdapter(config: config);
    expect(await adapter.restoreCredentials(), isTrue);
    return adapter;
  }
  final config = OneDriveConfigService(
    configPath: '',
    secureStorage: InMemorySecureStorage(),
  );
  await config.saveCredentials(credentials);
  final adapter = OneDriveClientAdapter(config: config);
  expect(await adapter.restoreCredentials(), isTrue);
  return adapter;
}

bool _isToken(http.BaseRequest request) =>
    request.url.host == 'oauth2.googleapis.com' ||
    request.url.host == 'login.microsoftonline.com';

http.Response? _setup(
  http.Request request,
  bool google, {
  bool download = false,
}) {
  if (_isToken(request)) {
    return _json({'access_token': 'fixture-access', 'expires_in': 3600});
  }
  if (google &&
      request.method == 'GET' &&
      request.url.path.endsWith('/files')) {
    return _json({
      'files': download
          ? [
              {'id': 'fixture-file'},
            ]
          : [],
    });
  }
  if (!google &&
      request.method == 'GET' &&
      request.url.path.endsWith('/root')) {
    return _json({'id': 'fixture-root', 'folder': {}});
  }
  if (request.method == 'POST' || request.method == 'PATCH') {
    if (google) {
      expect(request.url.queryParameters['uploadType'], 'resumable');
      return http.Response(
        '',
        200,
        headers: {
          'location': 'https://www.googleapis.com/upload/session-fixture',
        },
      );
    }
    expect(request.url.path, contains('createUploadSession'));
    return _json({'uploadUrl': 'https://fixture.up.1drv.com/session-fixture'});
  }
  if (request.method == 'DELETE') return http.Response('', 204);
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'length validation holds final part until EOF and rejects extra bytes',
    () async {
      final emitted = <List<int>>[];
      await expectLater(
        validatedTransferParts(
          Stream.fromIterable([
            [1, 2],
            [3, 4],
            [5],
          ]),
          4,
          2,
        ).forEach(emitted.add),
        throwsStateError,
      );
      expect(emitted, [
        [1, 2],
      ]);
      await expectLater(
        validatedTransferParts(Stream.value([1]), 2, 2).drain<void>(),
        throwsStateError,
      );
    },
  );

  for (final google in [true, false]) {
    final provider = google ? 'Google Drive' : 'OneDrive';
    final chunkSize = google ? 2 * 1024 * 1024 : 10 * 320 * 1024;
    group(provider, () {
      test(
        'uploads bounded sequential ranges before consuming the whole source',
        () async {
          final requests = <http.Request>[];
          var consumedTail = false;
          final length = chunkSize + 3;
          Stream<List<int>> source() async* {
            yield Uint8List(chunkSize);
            consumedTail = true;
            yield [1, 2, 3];
          }

          await http.runWithClient(
            () async {
              final adapter = await _adapter(google);
              expect(adapter.supportsStreaming, isTrue);
              await adapter.uploadStream(
                source(),
                length,
                'edited #1%20.bin',
                '/',
              );
            },
            () => MockClient((request) async {
              final setup = _setup(request, google);
              if (setup != null) return setup;
              expect(request.method, 'PUT');
              expect(request.bodyBytes.length, lessThanOrEqualTo(chunkSize));
              expect(
                request.headers['authorization'],
                google ? 'Bearer fixture-access' : isNull,
              );
              requests.add(request);
              if (requests.length == 1) {
                expect(consumedTail, isFalse);
                return google
                    ? http.Response(
                        '',
                        308,
                        headers: {'range': 'bytes=0-${chunkSize - 1}'},
                      )
                    : _json({
                        'nextExpectedRanges': ['$chunkSize-'],
                      }, 202);
              }
              return _json({
                'id': 'uploaded',
                'size': google ? '$length' : length,
              }, 201);
            }),
          );
          expect(requests.length, 2);
          expect(
            requests.first.headers['content-range'],
            'bytes 0-${chunkSize - 1}/$length',
          );
          expect(
            requests.last.headers['content-range'],
            'bytes $chunkSize-${length - 1}/$length',
          );
          expect(requests.last.bodyBytes, [1, 2, 3]);
        },
      );

      for (final extra in [false, true]) {
        test(
          '${extra ? 'extra' : 'missing'} source bytes cannot commit the final part',
          () async {
            var puts = 0;
            var aborts = 0;
            await http.runWithClient(
              () async {
                final adapter = await _adapter(google);
                await expectLater(
                  adapter.uploadStream(
                    Stream.value(extra ? [1, 2, 3] : [1]),
                    2,
                    'x.bin',
                    '/',
                  ),
                  throwsStateError,
                );
              },
              () => MockClient((request) async {
                if (request.method == 'PUT') puts++;
                if (request.method == 'DELETE') aborts++;
                return _setup(request, google) ??
                    _json({'id': 'unexpected', 'size': 2});
              }),
            );
            expect(puts, 0);
            expect(aborts, google ? 0 : 1);
          },
        );
      }

      test(
        'an accepted final range is not reported as a completed upload',
        () async {
          await http.runWithClient(
            () async {
              final adapter = await _adapter(google);
              await expectLater(
                adapter.uploadStream(Stream.value([1, 2]), 2, 'x.bin', '/'),
                throwsStateError,
              );
            },
            () => MockClient(
              (request) async =>
                  _setup(request, google) ??
                  (google
                      ? http.Response('', 308, headers: {'range': 'bytes=0-1'})
                      : _json({
                          'nextExpectedRanges': ['2-'],
                        }, 202)),
            ),
          );
        },
      );

      test('wrong completed size is rejected', () async {
        await http.runWithClient(
          () async {
            final adapter = await _adapter(google);
            await expectLater(
              adapter.uploadStream(Stream.value([1, 2]), 2, 'x.bin', '/'),
              throwsStateError,
            );
          },
          () => MockClient(
            (request) async =>
                _setup(request, google) ??
                _json({'id': 'uploaded', 'size': google ? '3' : 3}, 201),
          ),
        );
      });

      test(
        'unexpected acknowledged offset stops before the next part',
        () async {
          var puts = 0;
          await http.runWithClient(
            () async {
              final adapter = await _adapter(google);
              await expectLater(
                adapter.uploadStream(
                  Stream.fromIterable([
                    Uint8List(chunkSize),
                    [1],
                  ]),
                  chunkSize + 1,
                  'x.bin',
                  '/',
                ),
                throwsStateError,
              );
            },
            () => MockClient((request) async {
              final setup = _setup(request, google);
              if (setup != null) return setup;
              puts++;
              return google
                  ? http.Response('', 308, headers: {'range': 'bytes=0-1'})
                  : _json({
                      'nextExpectedRanges': ['2-'],
                    }, 202);
            }),
          );
          expect(puts, 1);
        },
      );

      test(
        'download yields before EOF and releases its response on cancellation',
        () async {
          var sourceCancelled = false;
          var sourceReachedEnd = false;
          final releaseTail = Completer<void>();
          Stream<List<int>> bytes() async* {
            try {
              yield [1, 2];
              await releaseTail.future;
              sourceReachedEnd = true;
              yield [3, 4];
            } finally {
              sourceCancelled = true;
            }
          }

          await http.runWithClient(
            () async {
              final adapter = await _adapter(google);
              expect(await adapter.downloadStream('/x #1%20.bin').first, [
                1,
                2,
              ]);
              expect(sourceReachedEnd, isFalse);
              expect(sourceCancelled, isTrue);
            },
            () => MockClient.streaming((request, body) async {
              await body.drain<void>();
              Object? value;
              if (_isToken(request)) {
                value = {'access_token': 'fixture-access', 'expires_in': 3600};
              } else if (google && request.url.path.endsWith('/files')) {
                value = {
                  'files': [
                    {'id': 'fixture-file'},
                  ],
                };
              } else if (google &&
                  request.url.queryParameters['fields'] != null) {
                value = {'mimeType': 'application/octet-stream', 'size': '4'};
              } else if (!google && request.url.host == 'graph.microsoft.com') {
                expect(request.url.toString(), contains('x%20%231%2520.bin'));
                expect(request.url.fragment, isEmpty);
                value = {
                  'size': 4,
                  '@microsoft.graph.downloadUrl':
                      'https://fixture.1drv.com/file',
                };
              }
              if (value != null) {
                return http.StreamedResponse(
                  Stream.value(utf8.encode(jsonEncode(value))),
                  200,
                );
              }
              expect(
                request.headers['authorization'],
                google ? 'Bearer fixture-access' : isNull,
              );
              return http.StreamedResponse(bytes(), 200);
            }),
          );
        },
      );

      test(
        'truncated downloads fail instead of silently returning a partial file',
        () async {
          await http.runWithClient(
            () async {
              final adapter = await _adapter(google);
              await expectLater(
                adapter.downloadStream('/x.bin').drain<void>(),
                throwsStateError,
              );
            },
            () => MockClient((request) async {
              if (_isToken(request)) {
                return _json({
                  'access_token': 'fixture-access',
                  'expires_in': 3600,
                });
              }
              if (google && request.url.path.endsWith('/files')) {
                return _json({
                  'files': [
                    {'id': 'fixture-file'},
                  ],
                });
              }
              if (google && request.url.queryParameters['fields'] != null) {
                return _json({
                  'mimeType': 'application/octet-stream',
                  'size': '3',
                });
              }
              if (!google && request.url.host == 'graph.microsoft.com') {
                return _json({
                  'size': 3,
                  '@microsoft.graph.downloadUrl':
                      'https://fixture.1drv.com/file',
                });
              }
              return http.Response.bytes([1], 200);
            }),
          );
        },
      );
    });
  }

  test('Google Drive rejects duplicate file names instead of choosing an arbitrary object', () async {
    await http.runWithClient(
      () async {
        final adapter = await _adapter(true);
        await expectLater(
          adapter.uploadStream(Stream.value([1]), 1, 'x.bin', '/'),
          throwsStateError,
        );
      },
      () => MockClient((request) async {
        if (_isToken(request)) {
          return _json({'access_token': 'fixture-access', 'expires_in': 3600});
        }
        expect(request.method, 'GET');
        return _json({
          'files': [
            {'id': 'one'},
            {'id': 'two'},
          ],
        });
      }),
    );
  });

  test(
    'Google Drive does not upload to root when the requested parent is missing',
    () async {
      await http.runWithClient(
        () async {
          final adapter = await _adapter(true);
          await expectLater(
            adapter.uploadStream(Stream.value([1]), 1, 'x.bin', '/gone'),
            throwsStateError,
          );
          await expectLater(
            adapter.uploadFile([1], 'x.bin', '/gone'),
            throwsStateError,
          );
        },
        () => MockClient((request) async {
          if (_isToken(request)) {
            return _json({
              'access_token': 'fixture-access',
              'expires_in': 3600,
            });
          }
          expect(request.method, 'GET');
          return _json({'files': []});
        }),
      );
    },
  );
}
