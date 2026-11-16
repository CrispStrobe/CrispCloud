import 'dart:async';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

ZoteroHttpResponse _empty({Map<String, String> headers = const {}}) =>
    ZoteroHttpResponse(statusCode: 200, body: '[]', headers: headers);

Matcher _paused(int seconds) => isA<ZoteroApiException>()
    .having((error) => error.kind, 'kind', ZoteroApiErrorKind.rateLimited)
    .having(
      (error) => error.retryAfter,
      'remaining',
      Duration(seconds: seconds),
    );

void main() {
  final library = ZoteroLibrary.user(42);

  test(
    'shared 429 pause survives new credentials and expires exactly',
    () async {
      var now = DateTime.utc(2026, 11, 16);
      var calls = 0;
      final state = ZoteroBackoffState();
      final first = ZoteroClient(
        apiKey: 'first-session-key',
        clock: () => now,
        backoffState: state,
        transport: (_) async {
          calls++;
          return ZoteroHttpResponse(
            statusCode: 429,
            body: '',
            headers: {'Retry-After': '60'},
          );
        },
      );
      await expectLater(first.verifyKey(), throwsA(_paused(60)));
      final replacement = ZoteroClient(
        apiKey: 'replacement-session-key',
        clock: () => now,
        backoffState: state,
        transport: (_) async {
          calls++;
          return ZoteroHttpResponse(
            statusCode: 200,
            body: '{"userID":42,"username":"reader"}',
          );
        },
      );
      now = now.add(const Duration(seconds: 59));
      await expectLater(replacement.verifyKey(), throwsA(_paused(1)));
      expect(calls, 1);
      expect(replacement.backoffUntil, first.backoffUntil);
      now = now.add(const Duration(seconds: 1));
      expect((await replacement.verifyKey()).userId, 42);
      expect(replacement.retryAfter, isNull);
      expect(calls, 2);
    },
  );

  test(
    'successful Backoff also pauses replacement clients and libraries',
    () async {
      var now = DateTime.utc(2026, 11, 16);
      var calls = 0;
      final state = ZoteroBackoffState();
      final first = ZoteroClient(
        clock: () => now,
        backoffState: state,
        transport: (_) async {
          calls++;
          return _empty(headers: {'Backoff': '10'});
        },
      );
      expect((await first.items(library)).items, isEmpty);
      final replacement = ZoteroClient(
        clock: () => now,
        backoffState: state,
        transport: (_) async {
          calls++;
          return _empty();
        },
      );
      await expectLater(
        replacement.collections(ZoteroLibrary.group(77)),
        throwsA(_paused(10)),
      );
      expect(calls, 1);
      now = now.add(const Duration(seconds: 10));
      expect(
        (await replacement.collections(ZoteroLibrary.group(77))).items,
        isEmpty,
      );
      expect(calls, 2);
    },
  );

  for (final (status, headers, seconds) in [
    (429, <String, String>{}, 30),
    (503, {'Retry-After': '20'}, 20),
    (429, {'Retry-After': '20', 'Backoff': '40'}, 40),
  ]) {
    test(
      'replacement preserves pause for HTTP $status with $headers',
      () async {
        final now = DateTime.utc(2026, 11, 16);
        final state = ZoteroBackoffState();
        var calls = 0;
        final first = ZoteroClient(
          clock: () => now,
          backoffState: state,
          transport: (_) async {
            calls++;
            return ZoteroHttpResponse(
              statusCode: status,
              body: '',
              headers: headers,
            );
          },
        );
        await expectLater(
          first.collections(library),
          throwsA(
            isA<ZoteroApiException>().having(
              (error) => error.statusCode,
              'status',
              status,
            ),
          ),
        );
        final replacement = ZoteroClient(
          clock: () => now,
          backoffState: state,
          transport: (_) async {
            calls++;
            return _empty();
          },
        );
        await expectLater(
          replacement.items(library),
          throwsA(_paused(seconds)),
        );
        expect(calls, 1);
      },
    );
  }

  test('late responses across clients cannot shorten a shared pause', () async {
    final now = DateTime.utc(2026, 11, 16);
    final state = ZoteroBackoffState();
    final firstResponse = Completer<ZoteroHttpResponse>();
    final nextResponse = Completer<ZoteroHttpResponse>();
    var calls = 0;
    final oldClient = ZoteroClient(
      clock: () => now,
      backoffState: state,
      transport: (_) {
        calls++;
        return firstResponse.future;
      },
    );
    final replacement = ZoteroClient(
      clock: () => now,
      backoffState: state,
      transport: (_) {
        calls++;
        return nextResponse.future;
      },
    );
    final oldRequest = oldClient.items(library);
    final newRequest = replacement.collections(library);
    firstResponse.complete(_empty(headers: {'Backoff': '60'}));
    await oldRequest;
    nextResponse.complete(_empty(headers: {'Backoff': '1'}));
    await newRequest;
    expect(replacement.retryAfter, const Duration(seconds: 60));
    await expectLater(replacement.items(library), throwsA(_paused(60)));
    expect(calls, 2);
  });

  test(
    'online shared state does not pause desktop or independent sessions',
    () async {
      final now = DateTime.utc(2026, 11, 16);
      final shared = ZoteroBackoffState();
      final online = ZoteroClient(
        clock: () => now,
        backoffState: shared,
        transport: (_) async => _empty(headers: {'Backoff': '60'}),
      );
      await online.items(library);
      var desktopCalls = 0;
      final desktop = ZoteroClient.local(
        clock: () => now,
        transport: (request) async {
          desktopCalls++;
          expect(request.uri.host, 'localhost');
          expect(request.headers['Zotero-API-Key'], isNull);
          return ZoteroHttpResponse(
            statusCode: 200,
            body: 'Local API',
            headers: {'Zotero-API-Version': '3'},
          );
        },
      );
      await desktop.probeLocal();
      expect(desktopCalls, 1);
      final independent = ZoteroClient(
        clock: () => now,
        transport: (_) async => _empty(),
      );
      expect((await independent.items(library)).items, isEmpty);
      expect(independent.retryAfter, isNull);
      expect(online.retryAfter, const Duration(seconds: 60));
    },
  );
}
