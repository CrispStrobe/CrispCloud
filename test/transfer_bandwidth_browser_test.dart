import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_storage/src/cloud/bounded_http_transfer.dart';
import 'package:crisp_storage/src/cloud/transfer_bandwidth_http.dart';
import 'package:crisp_storage/src/transfer_bandwidth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/transfer_bandwidth_test_clock.dart';

// Run this cohort on both the VM and Chrome. The mock transport qualifies the
// real platform-specific hook policy without claiming browser wire pacing.
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
  for (var step = 0; step < 1000 && !settled; step++) {
    await Future<void>.delayed(Duration.zero);
    if (clock.activeTimers != 0) clock.advanceToNextTimer();
  }
  if (!settled) throw StateError('HTTP hooks did not settle under the clock.');
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  return value as T;
}

Future<List<int>> _collect(Stream<List<int>> input) async {
  final result = BytesBuilder(copy: false);
  await for (final chunk in input) {
    result.add(chunk);
  }
  return result.takeBytes();
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
    ..fields['label'] = 'browser fixture'
    ..files.add(
      http.MultipartFile.fromBytes('payload', payload, filename: 'part.bin'),
    );
}

void main() {
  for (final kind in ['buffered', 'streamed', 'multipart']) {
    test('$kind upload uses the captured platform coverage policy', () async {
      final clock = ManualBandwidthClock();
      final owner = _allocator(clock, up: 1000);
      final other = TransferBandwidthAllocator();
      addTearDown(owner.dispose);
      addTearDown(other.dispose);
      final context = owner.openContext('created-upload');
      final later = other.openContext('later-finalization');
      final payload = List<int>.generate(53, (i) => 65 + i % 26);
      final request = bindHttpTransferBandwidth(
        _upload(kind, payload),
        context,
      );
      late List<int> sent;
      final client = MockClient.streaming((request, body) async {
        sent = await body.toBytes();
        expect(request.contentLength, sent.length);
        if (kind == 'multipart') {
          final contentType = request.headers['content-type']!;
          expect(contentType, startsWith('multipart/form-data; boundary='));
          final boundary = contentType.split('boundary=').last;
          final decoded = utf8.decode(sent);
          expect(decoded, startsWith('--$boundary\r\n'));
          expect(decoded, endsWith('--$boundary--\r\n'));
          expect(decoded, contains('filename="part.bin"'));
          expect(decoded, contains(utf8.decode(payload)));
        } else {
          expect(sent, payload);
        }
        return http.StreamedResponse(const Stream.empty(), 201);
      });
      addTearDown(client.close);

      final response = await _drive(
        clock,
        later.run(() => client.send(request)),
      );
      expect(response.statusCode, 201);
      expect(owner.snapshot.uploadBytes, kIsWeb ? 0 : sent.length);
      expect(owner.snapshot.unsupportedUploadJobs, kIsWeb ? 1 : 0);
      expect(owner.snapshot.downloadBytes, 0);
      expect(other.snapshot.uploadBytes, 0);
      expect(other.snapshot.unsupportedUploadJobs, 0);
      expect(clock.activeTimers, 0);
      if (kIsWeb) {
        // Preparation reaches the mock transport immediately. Neither the
        // browser's future fetch nor its socket writes are being paced.
        expect(clock.elapsed, Duration.zero);
      } else {
        expect(
          clock.elapsed.inMicroseconds,
          greaterThanOrEqualTo(sent.length * 1000),
        );
      }
    });
  }

  test('upload metadata consumption remains paced on both platforms', () async {
    final clock = ManualBandwidthClock();
    final allocator = _allocator(clock, up: 1000, down: 100);
    addTearDown(allocator.dispose);
    final context = allocator.openContext('metadata');
    final payload = List<int>.generate(16, (i) => i);
    final metadata = List<int>.generate(24, (i) => i + 32);
    late Duration uploadDeliveredAt;
    final client = MockClient.streaming((request, body) async {
      expect(await body.toBytes(), payload);
      uploadDeliveredAt = clock.elapsed;
      expect(allocator.snapshot.downloadBytes, 0);
      return http.StreamedResponse(Stream.value(metadata), 201);
    });
    addTearDown(client.close);

    final response = await _drive(
      clock,
      context.run(
        () => sendTransferRequest(
          client,
          http.Request('PUT', _endpoint)..bodyBytes = payload,
          operation: 'fixture upload',
        ),
      ),
    );
    expect(response.bodyBytes, metadata);
    expect(
      uploadDeliveredAt,
      kIsWeb ? Duration.zero : const Duration(milliseconds: 16),
    );
    expect(
      clock.elapsed - uploadDeliveredAt,
      const Duration(milliseconds: 240),
    );
    expect(allocator.snapshot.uploadBytes, kIsWeb ? 0 : payload.length);
    expect(allocator.snapshot.downloadBytes, metadata.length);
    expect(allocator.snapshot.unsupportedUploadJobs, kIsWeb ? 1 : 0);
    expect(allocator.snapshot.unsupportedDownloadJobs, 0);
    expect(clock.activeTimers, 0);
  });

  test(
    'lazy download stays captured when subscribed in another zone',
    () async {
      final clock = ManualBandwidthClock();
      final owner = _allocator(clock, down: 4);
      final other = TransferBandwidthAllocator();
      addTearDown(owner.dispose);
      addTearDown(other.dispose);
      final context = owner.openContext('created-download');
      final later = other.openContext('subscribed-download');
      final headers = {'x-version': 'original'};
      final payload = [1, 2, 3, 4];
      var sourceStarted = false;
      Stream<List<int>> responseBody() async* {
        sourceStarted = true;
        expect(TransferBandwidthContext.current, same(context));
        yield payload;
      }

      final client = MockClient.streaming((request, body) async {
        expect(request.headers['x-version'], 'original');
        expect(await body.toBytes(), isEmpty);
        return http.StreamedResponse(responseBody(), 200);
      });
      addTearDown(client.close);
      final stream = context.run(
        () => streamHttpDownload(
          _endpoint,
          operation: 'fixture download',
          headers: headers,
          expectedLength: payload.length,
        ),
      );
      headers['x-version'] = 'changed';
      expect(sourceStarted, isFalse);
      final received = await _drive(
        clock,
        http.runWithClient(
          () => later.run(() => _collect(stream)),
          () => client,
        ),
      );
      expect(sourceStarted, isTrue);
      expect(received, payload);
      expect(clock.elapsed, const Duration(seconds: 1));
      expect(owner.snapshot.downloadBytes, payload.length);
      expect(owner.snapshot.uploadBytes, 0);
      expect(owner.snapshot.unsupportedUploadJobs, 0);
      expect(other.snapshot.downloadBytes, 0);
      expect(clock.activeTimers, 0);
    },
  );

  for (final close in [false, true]) {
    test(
      '${close ? 'closed' : 'cancelled'} context rejects empty request handoff',
      () async {
        final allocator = TransferBandwidthAllocator();
        addTearDown(allocator.dispose);
        final context = allocator.openContext('ended-request');
        final bound = bindHttpTransferBandwidth(
          http.Request('GET', _endpoint),
          context,
        );
        if (close) {
          context.close();
        } else {
          context.cancel();
        }
        var sends = 0;
        final client = MockClient((request) async {
          sends++;
          return http.Response('', 200);
        });
        addTearDown(client.close);
        expect(
          () => bindHttpTransferBandwidth(
            http.Request('GET', _endpoint),
            context,
          ),
          throwsA(isA<TransferBandwidthCancelled>()),
        );
        await expectLater(
          client.send(bound),
          throwsA(isA<TransferBandwidthCancelled>()),
        );
        expect(sends, 0);
        expect(allocator.snapshot.uploadBytes, 0);
        expect(allocator.snapshot.downloadBytes, 0);
      },
    );
  }

  test(
    'closed captured download fails before the client sends a GET',
    () async {
      final allocator = TransferBandwidthAllocator();
      final other = TransferBandwidthAllocator();
      addTearDown(allocator.dispose);
      addTearDown(other.dispose);
      final context = allocator.openContext('ended-download');
      final later = other.openContext('later-download');
      final stream = context.run(
        () => streamHttpDownload(_endpoint, operation: 'fixture download'),
      );
      context.close();
      var sends = 0;
      final client = MockClient((request) async {
        sends++;
        return http.Response('unexpected', 200);
      });
      addTearDown(client.close);
      await expectLater(
        http.runWithClient(
          () => later.run(() => _collect(stream)),
          () => client,
        ),
        throwsA(isA<TransferBandwidthCancelled>()),
      );
      expect(sends, 0);
      expect(allocator.snapshot.downloadBytes, 0);
      expect(other.snapshot.downloadBytes, 0);
    },
  );
}
