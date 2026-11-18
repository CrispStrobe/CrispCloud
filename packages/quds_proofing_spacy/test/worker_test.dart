import 'dart:async';
import 'dart:isolate';

import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';
import 'package:quds_proofing_spacy/src/source_text.dart';
import 'package:quds_proofing_spacy/src/worker_unsupported.dart' as unsupported;
import 'package:test/test.dart';

// Synthetic backends exercise the real isolate protocol. Native inference
// qualification is a separate explicit command using authenticated assets.
const _identity = SpacyBackendIdentity(
  librarySha256:
      '1111111111111111111111111111111111111111111111111111111111111111',
);
const _wrongIdentity = SpacyBackendIdentity(
  librarySha256:
      '2222222222222222222222222222222222222222222222222222222222222222',
);

LinguisticAnalysisRequest _request(
  String text, {
  String block = 'paragraph',
  int revision = 1,
  String locale = 'de-DE',
  int origin = 7,
}) => LinguisticAnalysisRequest(
  text: text,
  documentId: 'document',
  blockId: block,
  revision: revision,
  locale: locale,
  startOffset: origin,
);

LinguisticAnalysisResult _success(
  LinguisticAnalysisRequest request, [
  SpacyBackendIdentity identity = _identity,
]) {
  final source = SpacySourceText(request.text);
  return LinguisticAnalysisResult.success(
    request: request,
    identity: identity,
    tokens: request.text.isEmpty
        ? const []
        : [
            LinguisticToken(
              index: 0,
              text: request.text,
              byteStart: 0,
              byteEnd: source.bytes.length,
              scalarStart: 0,
              scalarEnd: request.text.runes.length,
              start: 0,
              end: request.text.length,
              lemma: request.text,
              tag: 'NN',
              pos: 'NOUN',
              morphology: '',
              dependency: 'ROOT',
              head: 0,
              sentenceStart: true,
              sentenceEnd: true,
            ),
          ],
  );
}

final class _Started {
  const _Started(this.call, this.request, this.release);
  final int call;
  final LinguisticAnalysisRequest request;
  final SendPort release;
}

final class _Opening {
  const _Opening(this.release);
  final SendPort release;
}

final class _Closed {
  const _Closed();
}

final class _Factory implements SpacyBackendFactory {
  const _Factory(
    this.events, {
    this.controlOpen = false,
    this.failOpen = false,
    this.failClose = false,
  });
  final SendPort events;
  final bool controlOpen;
  final bool failOpen;
  final bool failClose;
  @override
  Future<SpacyBackend> open(SpacyBundle bundle) async {
    if (failOpen) throw StateError('Injected initialization failure');
    if (controlOpen) {
      final port = ReceivePort();
      events.send(_Opening(port.sendPort));
      await port.first;
      port.close();
    }
    return _Backend(events, failClose: failClose);
  }
}

final class _UnsendableFactory implements SpacyBackendFactory {
  const _UnsendableFactory(this.port);
  final ReceivePort port;
  @override
  Future<SpacyBackend> open(SpacyBundle bundle) async =>
      throw StateError('Unsendable factory cannot reach the worker.');
}

final class _Backend implements SpacyBackend {
  _Backend(this.events, {this.failClose = false});
  final SendPort events;
  final bool failClose;
  int calls = 0;
  bool active = false;
  bool disposed = false;
  @override
  SpacyBackendIdentity get identity => _identity;
  @override
  Future<LinguisticAnalysisResult> analyze(
    LinguisticAnalysisRequest request,
  ) async {
    if (active || disposed) throw StateError('Overlapping native ownership');
    active = true;
    final gate = ReceivePort();
    events.send(_Started(++calls, request, gate.sendPort));
    try {
      final mode = await gate.first;
      if (mode == 'exit') Isolate.exit();
      if (mode == 'throw') throw StateError('Injected inference failure');
      if (mode == 'wrong-snapshot') {
        return _success(_request(request.text, revision: request.revision + 1));
      }
      return _success(
        request,
        mode == 'wrong-identity' ? _wrongIdentity : identity,
      );
    } finally {
      active = false;
      gate.close();
    }
  }

  @override
  Future<void> dispose() async {
    if (active || disposed) {
      throw StateError('Unsafe or duplicate context free');
    }
    disposed = true;
    events.send(const _Closed());
    if (failClose) throw StateError('Injected cleanup failure');
  }
}

final class _Probe {
  final ReceivePort events = ReceivePort();
  late final StreamIterator<Object?> iterator = StreamIterator(events);
  final List<SendPort> releases = [];
  SpacyTransport? worker;

  Future<void> start({
    int capacity = 2,
    int units = 100,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    worker = await startSpacyWorker(
      bundle: const SpacyBundle.germanF32(),
      backendFactory: _Factory(events.sendPort),
      maximumPendingRequests: capacity,
      maximumTextCodeUnits: units,
      requestTimeout: timeout,
    );
  }

  Future<Object?> next() async {
    if (!await iterator.moveNext().timeout(const Duration(seconds: 5))) {
      throw StateError('Expected worker event');
    }
    final event = iterator.current;
    if (event is _Started) releases.add(event.release);
    if (event is _Opening) releases.add(event.release);
    return event;
  }

  Future<_Started> started() async => (await next())! as _Started;
  Future<void> close() async {
    for (final port in releases) {
      port.send(null);
    }
    await worker?.dispose();
    await iterator.cancel();
    events.close();
  }
}

void main() {
  late _Probe probe;
  setUp(() {
    probe = _Probe();
  });
  tearDown(() => probe.close());

  test(
    'persistent native ownership serializes calls and recovers after failure',
    () async {
      await probe.start();
      expect(probe.worker!.identity, _identity);
      for (var call = 1; call <= 3; call++) {
        final result = probe.worker!.analyze(_request('Haus'));
        final start = await probe.started();
        expect(start.call, call);
        start.release.send(call == 2 ? 'throw' : null);
        expect(
          (await result).status,
          call == 2
              ? LinguisticAnalysisStatus.failed
              : LinguisticAnalysisStatus.success,
        );
      }
      await probe.worker!.dispose();
      expect(await probe.next(), isA<_Closed>());
      await probe.worker!.dispose();
    },
  );

  test(
    '200 superseding snapshots retain one physical slot and other-key order',
    () async {
      await probe.start(capacity: 2);
      final obsolete = <Future<LinguisticAnalysisResult>>[
        probe.worker!.analyze(_request('Alt')),
      ];
      final first = await probe.started();
      final other = probe.worker!.analyze(_request('Anders', block: 'other'));
      for (var i = 0; i < 200; i++) {
        obsolete.add(probe.worker!.analyze(_request('Alt$i', revision: i + 2)));
      }
      final latest = probe.worker!.analyze(_request('Neu', revision: 300));
      expect(
        (await Future.wait(obsolete)).map((r) => r.status),
        everyElement(LinguisticAnalysisStatus.stale),
      );
      expect(
        (await probe.worker!.analyze(_request('Full', block: 'third'))).status,
        LinguisticAnalysisStatus.capacity,
      );
      first.release.send(null);
      final second = await probe.started();
      expect(second.call, 2);
      expect(second.request.text, 'Anders');
      second.release.send(null);
      expect((await other).isSuccess, isTrue);
      final third = await probe.started();
      expect(third.call, 3);
      expect(third.request.text, 'Neu');
      third.release.send(null);
      expect((await latest).request.revision, 300);
    },
  );

  test('invalid replacement does not cancel valid in-flight source', () async {
    await probe.start(units: 8);
    final valid = probe.worker!.analyze(_request('Haus'));
    final started = await probe.started();
    expect(
      (await probe.worker!.analyze(_request('x' * 9))).status,
      LinguisticAnalysisStatus.capacity,
    );
    expect(
      (await probe.worker!.analyze(_request('Haus', locale: 'de-CH'))).status,
      LinguisticAnalysisStatus.unsupported,
    );
    expect(
      (await probe.worker!.analyze(_request('\ud800'))).status,
      LinguisticAnalysisStatus.failed,
    );
    started.release.send(null);
    expect((await valid).isSuccess, isTrue);
  });

  test(
    'cancel releases caller but preserves slot until native acknowledgement',
    () async {
      await probe.start(capacity: 1);
      final request = _request('Alt');
      final old = probe.worker!.analyze(request);
      final blocked = await probe.started();
      probe.worker!.cancel(request.key);
      expect((await old).status, LinguisticAnalysisStatus.cancelled);
      final replacement = probe.worker!.analyze(_request('Neu'));
      blocked.release.send(null);
      final next = await probe.started();
      expect(next.call, 2);
      next.release.send(null);
      expect((await replacement).isSuccess, isTrue);
    },
  );

  test(
    'timeout retains physical slot and never publishes a late result',
    () async {
      await probe.start(
        capacity: 1,
        timeout: const Duration(milliseconds: 100),
      );
      final old = probe.worker!.analyze(_request('Alt'));
      final blocked = await probe.started();
      expect((await old).status, LinguisticAnalysisStatus.timeout);
      final fresh = probe.worker!.analyze(_request('Neu', revision: 2));
      blocked.release.send(null);
      final next = await probe.started();
      expect(next.call, 2);
      next.release.send(null);
      expect((await fresh).status, LinguisticAnalysisStatus.success);
    },
  );

  test(
    'dispose rejects callers immediately and joins the active context safely',
    () async {
      await probe.start();
      final active = probe.worker!.analyze(_request('Aktiv'));
      final started = await probe.started();
      final waiting = probe.worker!.analyze(
        _request('Wartend', block: 'other'),
      );
      var joined = false;
      final closing = probe.worker!.dispose().then((_) {
        joined = true;
      });
      expect((await active).status, LinguisticAnalysisStatus.unavailable);
      expect((await waiting).status, LinguisticAnalysisStatus.unavailable);
      await Future<void>.delayed(Duration.zero);
      expect(joined, isFalse);
      started.release.send(null);
      await closing;
      expect(await probe.next(), isA<_Closed>());
      expect(
        (await probe.worker!.analyze(_request('Später'))).status,
        LinguisticAnalysisStatus.unavailable,
      );
    },
  );

  test('snapshot and runtime mismatch cannot become success', () async {
    await probe.start();
    for (final mode in ['wrong-snapshot', 'wrong-identity']) {
      final result = probe.worker!.analyze(_request('Haus'));
      (await probe.started()).release.send(mode);
      expect((await result).status, LinguisticAnalysisStatus.failed);
    }
  });

  test('unexpected isolate exit rejects all callers', () async {
    await probe.start();
    final active = probe.worker!.analyze(_request('Haus'));
    final started = await probe.started();
    final waiting = probe.worker!.analyze(_request('Bäume', block: 'other'));
    started.release.send('exit');
    expect((await active).status, LinguisticAnalysisStatus.unavailable);
    expect((await waiting).status, LinguisticAnalysisStatus.unavailable);
    await probe.worker!.dispose();
  });

  test('startup failure returns explicit unavailable', () async {
    await expectLater(
      startSpacyWorker(
        bundle: const SpacyBundle.germanF32(),
        backendFactory: _Factory(probe.events.sendPort, failOpen: true),
      ),
      throwsA(isA<SpacyUnavailableException>()),
    );
  });

  test(
    'cleanup failure is explicit and repeated disposal preserves the error',
    () async {
      final worker = await startSpacyWorker(
        bundle: const SpacyBundle.germanF32(),
        backendFactory: _Factory(probe.events.sendPort, failClose: true),
      );
      await expectLater(
        worker.dispose(),
        throwsA(isA<SpacyUnavailableException>()),
      );
      expect(await probe.next(), isA<_Closed>());
      await expectLater(
        worker.dispose(),
        throwsA(isA<SpacyUnavailableException>()),
      );
      expect(
        (await worker.analyze(_request('Haus'))).status,
        LinguisticAnalysisStatus.unavailable,
      );
    },
  );

  test('spawn failure has no unhandled readiness error', () async {
    await expectLater(
      startSpacyWorker(
        bundle: const SpacyBundle.germanF32(),
        backendFactory: _UnsendableFactory(probe.events),
      ),
      throwsArgumentError,
    );
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'startup timeout returns promptly then releases late initialized context',
    () async {
      final starting = startSpacyWorker(
        bundle: const SpacyBundle.germanF32(),
        backendFactory: _Factory(probe.events.sendPort, controlOpen: true),
        startupTimeout: const Duration(milliseconds: 150),
      );
      final assertion = expectLater(starting, throwsA(isA<TimeoutException>()));
      final opening = (await probe.next())! as _Opening;
      await assertion;
      opening.release.send(null);
      expect(await probe.next(), isA<_Closed>());
    },
  );

  test(
    'web worker boundary reports unavailable without opening backend',
    () async {
      await expectLater(
        unsupported.startWorker(
          bundle: const SpacyBundle.germanF32(),
          backendFactory: _Factory(probe.events.sendPort),
          maximumPendingRequests: 1,
          maximumTextCodeUnits: 100,
          startupTimeout: const Duration(seconds: 1),
          requestTimeout: const Duration(seconds: 1),
        ),
        throwsA(isA<SpacyUnavailableException>()),
      );
    },
  );

  test('worker limit admission is explicit', () {
    for (final capacity in [0, 9]) {
      expect(
        () => startSpacyWorker(
          bundle: const SpacyBundle.germanF32(),
          backendFactory: _Factory(probe.events.sendPort),
          maximumPendingRequests: capacity,
        ),
        throwsArgumentError,
      );
    }
  });
}
