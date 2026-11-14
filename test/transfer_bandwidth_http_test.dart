import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_storage/src/cloud/bounded_http_transfer.dart';
import 'package:crisp_storage/src/cloud/transfer_bandwidth_http.dart';
import 'package:crisp_storage/src/transfer_bandwidth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';

import 'support/transfer_bandwidth_test_clock.dart';

final _endpoint = Uri.https('transport.example.test', '/object');

TransferBandwidthAllocator _allocator(
  ManualBandwidthClock clock, {
  int up = 0,
  int down = 0,
}) => TransferBandwidthAllocator(
  limits: TransferBandwidthLimits(
    uploadBytesPerSecond: up,
    downloadBytesPerSecond: down,
  ),
  clock: () => clock.elapsed,
  createTimer: clock.timer,
);

Future<Uint8List> _collect(Stream<List<int>> input) async {
  final result = BytesBuilder(copy: false);
  await for (final chunk in input) {
    result.add(chunk);
  }
  return result.takeBytes();
}

/// Drive only the allocator's injected pacing timers. Real asynchronous stream
/// continuations still run, so blocked body reads cannot be mistaken for quota.
Future<T> _drive<T>(ManualBandwidthClock clock, Future<T> future) async {
  var settled = false;
  Object? value;
  Object? failure;
  StackTrace? failureStack;
  unawaited(
    future.then<void>(
      (result) {
        value = result;
        settled = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
        settled = true;
      },
    ),
  );
  for (var step = 0; step < 2000 && !settled; step++) {
    await Future<void>.delayed(Duration.zero);
    if (clock.activeTimers != 0) clock.advanceToNextTimer();
  }
  if (!settled) {
    throw StateError('Transport did not settle under the test clock.');
  }
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  return value as T;
}

http.BaseRequest _upload(String kind, List<int> payload) {
  if (kind == 'buffered') {
    return http.Request('PUT', _endpoint)..bodyBytes = payload;
  }
  if (kind == 'streamed') {
    final request = http.StreamedRequest('PUT', _endpoint)
      ..contentLength = payload.length;
    request.sink
      ..add(payload.sublist(0, 7))
      ..add(payload.sublist(7));
    unawaited(request.sink.close());
    return request;
  }
  return http.MultipartRequest('POST', _endpoint)
    ..fields['label'] = 'café'
    ..files.add(
      http.MultipartFile.fromBytes('payload', payload, filename: 'part.bin'),
    );
}

class _TrackedClient extends http.BaseClient {
  _TrackedClient(this.delegate);
  final http.Client delegate;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      delegate.send(request);

  @override
  void close() {
    closed = true;
    delegate.close();
  }
}

/// Deliberately ignores Abortable and never finalizes the request. The helper
/// must reject an ended operation before handing any request to this client.
class _IgnoringAbortClient extends http.BaseClient {
  int sends = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    return http.StreamedResponse(const Stream.empty(), 200);
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  test(
    'empty requests reject a closed operation before binding or finalizing',
    () {
      final allocator = TransferBandwidthAllocator();
      addTearDown(allocator.dispose);
      final context = allocator.openContext('ended-empty-request');
      final request = http.Request('GET', _endpoint);
      final bound = bindHttpTransferBandwidth(request, context);
      context.close();

      expect(bound.finalize, throwsA(isA<TransferBandwidthCancelled>()));
      expect(request.finalized, isFalse);
      expect(
        () =>
            bindHttpTransferBandwidth(http.Request('GET', _endpoint), context),
        throwsA(isA<TransferBandwidthCancelled>()),
      );
      expect(allocator.snapshot.uploadBytes, 0);
      expect(allocator.snapshot.downloadBytes, 0);
    },
  );

  test(
    'a download captured before close sends nothing when listened to later',
    () async {
      final allocator = TransferBandwidthAllocator();
      addTearDown(allocator.dispose);
      final context = allocator.openContext('ended-before-subscription');
      final stream = context.run(
        () => streamHttpDownload(
          _endpoint,
          operation: 'late download',
          expectedLength: 0,
        ),
      );
      context.close();
      final client = _IgnoringAbortClient();

      await http.runWithClient(
        () => expectLater(
          _collect(stream),
          throwsA(isA<TransferBandwidthCancelled>()),
        ),
        () => client,
      );
      expect(client.sends, 0);
      expect(client.closed, isTrue);
      expect(allocator.snapshot.uploadBytes, 0);
      expect(allocator.snapshot.downloadBytes, 0);
    },
  );

  for (final kind in ['buffered', 'streamed', 'multipart']) {
    test(
      '$kind body and final policies stay bound to the captured operation',
      () async {
        final clock = ManualBandwidthClock();
        final owner = _allocator(clock, up: 1000);
        final other = TransferBandwidthAllocator();
        addTearDown(owner.dispose);
        addTearDown(other.dispose);
        final context = owner.openContext('captured-a');
        final later = other.openContext('later-b');
        final payload = Uint8List.fromList(
          List.generate(53, (i) => 65 + i % 26),
        );
        final original = Uint8List.fromList(payload);
        final request = _upload(kind, payload)
          ..followRedirects = false
          ..maxRedirects = 3
          ..persistentConnection = false;
        request.headers['x-object-version'] = 'fixture-version';
        final bound = bindHttpTransferBandwidth(request, context);
        late Uint8List sent;
        final client = MockClient.streaming((transport, body) async {
          expect(transport.followRedirects, isFalse);
          expect(transport.maxRedirects, 3);
          expect(transport.persistentConnection, isFalse);
          expect(transport.headers['x-object-version'], 'fixture-version');
          sent = await body.toBytes();
          expect(transport.contentLength, sent.length);
          if (kind == 'multipart') {
            final type = transport.headers['content-type']!;
            expect(type, startsWith('multipart/form-data; boundary='));
            final boundary = type.split('boundary=').last;
            final text = utf8.decode(sent);
            expect(text, startsWith('--$boundary\r\n'));
            expect(text, endsWith('--$boundary--\r\n'));
            expect(text, contains('filename="part.bin"'));
            expect(text, contains('café'));
            expect(text, contains(utf8.decode(payload)));
            expect(sent.length, greaterThan(payload.length));
          } else {
            expect(sent, original);
          }
          return http.StreamedResponse(const Stream.empty(), 201);
        });
        addTearDown(client.close);
        final response = await _drive(
          clock,
          later.run(() => client.send(bound)),
        );
        expect(response.statusCode, 201);
        expect(owner.snapshot.uploadBytes, sent.length);
        expect(owner.snapshot.downloadBytes, 0);
        expect(other.snapshot.uploadBytes, 0);
        expect(
          clock.elapsed.inMicroseconds,
          greaterThanOrEqualTo(sent.length * 1000),
        );
        expect(payload, original);
      },
    );
  }

  test(
    'independent pools charge simultaneous uploads, downloads and metadata',
    () async {
      final clock = ManualBandwidthClock();
      final allocator = _allocator(clock, up: 100, down: 200);
      addTearDown(allocator.dispose);
      final upload = allocator.openContext('upload');
      final download = allocator.openContext('download');
      final uploadBody = Uint8List.fromList(List.generate(30, (i) => i));
      final downloadBody = Uint8List.fromList(List.generate(40, (i) => i + 40));
      final metadata = Uint8List.fromList(List.generate(20, (i) => i + 100));
      final uploadClient = MockClient.streaming((request, body) async {
        expect(await body.toBytes(), uploadBody);
        return http.StreamedResponse(Stream.value(metadata), 201);
      });
      final downloadClient = _TrackedClient(
        MockClient.streaming((request, body) async {
          expect(await body.toBytes(), isEmpty);
          return http.StreamedResponse(Stream.value(downloadBody), 200);
        }),
      );
      addTearDown(uploadClient.close);
      final uploading = upload.run(
        () => sendTransferRequest(
          uploadClient,
          http.Request('PUT', _endpoint)..bodyBytes = uploadBody,
          operation: 'fixture upload',
        ),
      );
      final downloading = http.runWithClient(
        () => download.run(
          () => _collect(
            streamHttpDownload(
              _endpoint,
              operation: 'fixture download',
              expectedLength: downloadBody.length,
            ),
          ),
        ),
        () => downloadClient,
      );
      final results = await _drive<Object?>(
        clock,
        Future.wait<Object?>([uploading, downloading]),
      ) as List<Object?>;
      expect((results[0] as http.Response).bodyBytes, metadata);
      expect(results[1], downloadBody);
      expect(allocator.snapshot.uploadBytes, 30);
      expect(allocator.snapshot.downloadBytes, 60);
      expect(clock.elapsed, const Duration(milliseconds: 400));
      expect(allocator.snapshot.pendingUploadJobs, 0);
      expect(allocator.snapshot.pendingDownloadJobs, 0);
      expect(downloadClient.closed, isTrue);
    },
  );

  test(
    'download captures its operation and headers before a later subscription',
    () async {
      final clock = ManualBandwidthClock();
      final owner = _allocator(clock, down: 5);
      final other = TransferBandwidthAllocator();
      addTearDown(owner.dispose);
      addTearDown(other.dispose);
      final context = owner.openContext('created-a');
      final later = other.openContext('subscribed-b');
      final headers = {'x-version': 'original'};
      final client = _TrackedClient(
        MockClient((request) async {
          expect(request.headers['x-version'], 'original');
          expect(request.bodyBytes, isEmpty);
          return http.Response.bytes([1, 2, 3, 4], 200);
        }),
      );
      await http.runWithClient(() async {
        final stream = context.run(
          () => streamHttpDownload(
            _endpoint,
            operation: 'fixture download',
            expectedLength: 4,
            headers: headers,
          ),
        );
        headers['x-version'] = 'changed after creation';
        expect(await _drive(clock, later.run(() => _collect(stream))), [
          1,
          2,
          3,
          4,
        ]);
      }, () => client);
      expect(owner.snapshot.downloadBytes, 4);
      expect(other.snapshot.downloadBytes, 0);
      expect(owner.snapshot.uploadBytes, 0);
      expect(owner.snapshot.unsupportedUploadJobs, 0);
      expect(clock.elapsed, const Duration(milliseconds: 800));
      expect(client.closed, isTrue);
    },
  );

  test(
    'each retry pays for its actual request body and response metadata again',
    () async {
      final clock = ManualBandwidthClock();
      final allocator = _allocator(clock, up: 120, down: 20);
      addTearDown(allocator.dispose);
      final context = allocator.openContext('retrying-job');
      final bytes = Uint8List.fromList(List.generate(12, (i) => i));
      var sends = 0;
      final client = MockClient.streaming((request, body) async {
        expect(await body.toBytes(), bytes);
        sends++;
        return http.StreamedResponse(
          Stream.value([sends]),
          sends == 1 ? 503 : 200,
        );
      });
      addTearDown(client.close);
      for (var attempt = 1; attempt <= 2; attempt++) {
        final response = await _drive(
          clock,
          context.run(
            () => sendTransferRequest(
              client,
              http.Request('PUT', _endpoint)..bodyBytes = bytes,
              operation: 'fixture retry',
            ),
          ),
        );
        expect(response.statusCode, attempt == 1 ? 503 : 200);
        expect(response.bodyBytes, [attempt]);
      }
      expect(sends, 2);
      expect(allocator.snapshot.uploadBytes, 24);
      expect(allocator.snapshot.downloadBytes, 2);
      expect(clock.elapsed, const Duration(milliseconds: 300));
    },
  );

  test(
    'oversized raw response metadata fails before a low quota can delay it',
    () async {
      final clock = ManualBandwidthClock();
      final allocator = _allocator(clock, down: 1);
      addTearDown(allocator.dispose);
      final context = allocator.openContext('oversized-metadata');
      final client = MockClient.streaming((request, body) async {
        expect(await body.toBytes(), isEmpty);
        return http.StreamedResponse(
          Stream.value(Uint8List(256 * 1024 + 1)),
          200,
        );
      });
      addTearDown(client.close);
      await expectLater(
        _drive(
          clock,
          context.run(
            () => sendTransferRequest(
              client,
              http.Request('POST', _endpoint),
              operation: 'fixture upload',
            ),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('oversized metadata'),
          ),
        ),
      );
      expect(clock.elapsed, Duration.zero);
      expect(clock.activeTimers, 0);
      expect(allocator.snapshot.downloadBytes, 0);
    },
  );

  for (final body in [
    const [1, 2],
    const [1, 2, 3, 4],
  ]) {
    test(
      'a ${body.length}-byte download cannot satisfy a declared length of 3',
      () async {
        final clock = ManualBandwidthClock();
        final allocator = _allocator(clock, down: 10);
        addTearDown(allocator.dispose);
        final context = allocator.openContext('wrong-length');
        final client = _TrackedClient(
          MockClient((request) async => http.Response.bytes(body, 200)),
        );
        await http.runWithClient(() async {
          await expectLater(
            _drive(
              clock,
              context.run(
                () => _collect(
                  streamHttpDownload(
                    _endpoint,
                    operation: 'fixture download',
                    expectedLength: 3,
                  ),
                ),
              ),
            ),
            throwsStateError,
          );
        }, () => client);
        expect(client.closed, isTrue);
        expect(
          allocator.snapshot.downloadBytes,
          body.length < 3 ? body.length : 0,
        );
        expect(clock.activeTimers, 0);
      },
    );
  }

  for (final signal in ['operation', 'original request']) {
    test(
      '$signal cancellation aborts an IOClient waiting for response headers',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final arrived = Completer<void>();
        final subscription = server.listen((request) {
          unawaited(
            request.drain<void>().then<void>(
              (_) {
                if (!arrived.isCompleted) arrived.complete();
              },
              onError: (Object error, StackTrace stack) {
                if (!arrived.isCompleted) arrived.completeError(error, stack);
              },
            ),
          );
          // Deliberately leave response headers unsent until the client aborts.
        });
        final allocator = TransferBandwidthAllocator();
        final context = allocator.openContext('waiting-for-headers');
        final original = Completer<void>();
        final client = IOClient();
        try {
          final request = http.AbortableRequest(
            'GET',
            Uri.http('127.0.0.1:${server.port}', '/waiting'),
            abortTrigger: original.future,
          );
          final pending = client.send(
            bindHttpTransferBandwidth(request, context),
          );
          final failed = expectLater(
            pending.timeout(const Duration(seconds: 4)),
            throwsA(isA<http.RequestAbortedException>()),
          );
          await arrived.future.timeout(const Duration(seconds: 4));
          if (signal == 'operation') {
            context.cancel();
          } else {
            original.complete();
          }
          await failed;
          expect(context.isCancelled, signal == 'operation');
          expect(allocator.snapshot.pendingUploadJobs, 0);
          expect(allocator.snapshot.pendingDownloadJobs, 0);
        } finally {
          client.close();
          allocator.dispose();
          await server.close(force: true);
          await subscription.cancel();
        }
      },
      timeout: const Timeout(Duration(seconds: 12)),
    );
  }

  test('two real loopback operations share aggregate upload and download caps', () async {
    const limit = 32768;
    const size = 16384;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final watch = Stopwatch()..start();
    final received = <String, Uint8List>{};
    final uploadFinished = <Duration>[];
    final handlers = <Future<void>>[];
    final serverErrors = <Object>[];
    Duration? firstResponse;
    final subscription = server.listen((request) {
      final handler = () async {
        final bytes = await _collect(request);
        received[request.uri.path] = bytes;
        uploadFinished.add(watch.elapsed);
        firstResponse ??= watch.elapsed;
        request.response
          ..statusCode = 200
          ..contentLength = bytes.length
          ..add(bytes);
        await request.response.close();
      }();
      handlers.add(handler);
      unawaited(
        handler.catchError((Object error, StackTrace _) {
          serverErrors.add(error);
        }),
      );
    });
    final allocator = TransferBandwidthAllocator(
      limits: const TransferBandwidthLimits(
        uploadBytesPerSecond: limit,
        downloadBytesPerSecond: limit,
      ),
    );
    final client = IOClient();
    final first = Uint8List.fromList(List.generate(size, (i) => i % 251));
    final second = Uint8List.fromList(
      List.generate(size, (i) => 250 - i % 251),
    );
    final originals = [Uint8List.fromList(first), Uint8List.fromList(second)];
    try {
      Future<http.Response> transfer(String path, Uint8List payload) {
        final context = allocator.openContext(path);
        return context.run(
          () => sendTransferRequest(
            client,
            http.Request('PUT', Uri.http('127.0.0.1:${server.port}', path))
              ..bodyBytes = payload,
            operation: 'loopback upload',
          ),
        );
      }

      final responses = await Future.wait([
        transfer('/one', first),
        transfer('/two', second),
      ]).timeout(const Duration(seconds: 10));
      final finished = watch.elapsed;
      await Future.wait(handlers);
      expect(serverErrors, isEmpty);
      expect(received['/one'], originals[0]);
      expect(received['/two'], originals[1]);
      expect(responses[0].bodyBytes, originals[0]);
      expect(responses[1].bodyBytes, originals[1]);
      expect(first, originals[0]);
      expect(second, originals[1]);
      expect(allocator.snapshot.uploadBytes, size * 2);
      expect(allocator.snapshot.downloadBytes, size * 2);
      expect(uploadFinished, hasLength(2));
      final lastUpload = uploadFinished.reduce((a, b) => a > b ? a : b);
      final downloadElapsed = finished - firstResponse!;
      // Preserve measured handoff timings in the machine-readable test log.
      // ignore: avoid_print
      print(
        jsonEncode({
          'measurement': 'aggregate_http_loopback',
          'operations': 2,
          'upload_bytes': allocator.snapshot.uploadBytes,
          'download_bytes': allocator.snapshot.downloadBytes,
          'upload_limit_bytes_per_second': limit,
          'download_limit_bytes_per_second': limit,
          'last_upload_ms': lastUpload.inMicroseconds / 1000,
          'response_consumption_ms': downloadElapsed.inMicroseconds / 1000,
          'total_ms': finished.inMicroseconds / 1000,
        }),
      );
      // Each direction transfers 32768 bytes at 32768 B/s in total. These wide
      // lower bounds catch accidental per-operation caps; upper bounds tolerate
      // scheduler and loopback overhead on loaded CI hosts.
      expect(lastUpload.inMilliseconds, inInclusiveRange(800, 8000));
      expect(downloadElapsed.inMilliseconds, inInclusiveRange(800, 8000));
    } finally {
      client.close();
      allocator.dispose();
      await server.close(force: true);
      await subscription.cancel();
    }
  }, timeout: const Timeout(Duration(seconds: 15)));
}
