import 'dart:async';

import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/terminal_backends.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/tmux_control_client.dart';
import 'package:crisp_cloud/services/tmux_terminal_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Service service;

  setUp(() => service = _Service());
  tearDown(() => service.dispose());

  test(
    'SSH adapter reserves a new ID and always opens an ordinary shell',
    () async {
      final source = SshTerminalConnection(
        service,
        'source',
        const Stream.empty(),
      );
      expect(source.canOpenSibling, isTrue);
      expect(source.sharedSessionCount, 1);
      final sibling = await source.openSibling(120, 38);
      expect(sibling, isA<SshTerminalConnection>());
      expect((sibling as SshTerminalConnection).sessionId, 'sibling-1');
      expect(service.opened, [('sibling-1', 120, 38, null, null)]);
      expect(source.sharedSessionCount, 2);
      expect(sibling.sharedSessionCount, 2);
      await sibling.write('hello');
      await sibling.resize(132, 44);
      expect(service.writes, [('sibling-1', 'hello')]);
      expect(service.resizes, [('sibling-1', 132, 44)]);
      await source.close();
      expect(service.active.keys, ['sibling-1']);
      await sibling.write('survives');
      expect(service.writes.last, ('sibling-1', 'survives'));
      await sibling.close();
      expect(service.active, isEmpty);
    },
  );

  test('native tmux adapter opens a plain sibling without using its control client', () async {
    final client = _TmuxClient();
    final source = TmuxTerminalConnection(service, 'source', client);
    addTearDown(client.finish);
    expect(source.canOpenSibling, isTrue);
    final sibling = await source.openSibling(96, 28);
    expect(sibling, isA<SshTerminalConnection>());
    expect(service.opened, [('sibling-1', 96, 28, null, null)]);
    expect(source.sharedSessionCount, 2);
    expect(client.closeCalls, 0);
    expect(client.disposeCalls, 0);
    await sibling.close();
    expect(service.active.keys, ['source']);
    expect(client.closeCalls, 0);
    source.disposeWorkspace();
  });

  test(
    'opening failure releases the sibling and preserves the source',
    () async {
      service.openError = StateError('server refused channel');
      final source = SshTerminalConnection(
        service,
        'source',
        const Stream.empty(),
      );
      await expectLater(source.openSibling(80, 24), throwsStateError);
      expect(service.active.keys, ['source']);
      expect(service.disconnected, ['sibling-1']);
      expect(source.canOpenSibling, isTrue);
    },
  );

  test('a closed source cannot create a sibling', () async {
    final source = SshTerminalConnection(
      service,
      'source',
      const Stream.empty(),
    );
    await source.close();
    expect(source.canOpenSibling, isFalse);
    expect(source.sharedSessionCount, 0);
    await expectLater(source.openSibling(80, 24), throwsStateError);
    expect(service.opened, isEmpty);
    expect(service.serial, 0);
  });

  test(
    'source can close while the separately reserved channel opens',
    () async {
      final gate = Completer<void>();
      service.openGate = gate;
      final source = SshTerminalConnection(
        service,
        'source',
        const Stream.empty(),
      );
      final opening = source.openSibling(80, 24);
      // shareSession reserves synchronously, before shell startup awaits the peer.
      expect(service.active.keys, ['source', 'sibling-1']);
      await source.close();
      gate.complete();
      final sibling = await opening;
      expect(service.active.keys, ['sibling-1']);
      await sibling.write('independent lease');
      expect(service.writes, [('sibling-1', 'independent lease')]);
      await sibling.close();
    },
  );

  test(
    'cancellation closes the acquired child before a remote channel reply',
    () async {
      service.openGate = Completer<void>();
      final cancellation = TerminalConnectionCancellation();
      final source = SshTerminalConnection(
        service,
        'source',
        const Stream.empty(),
      );
      final opening = source.openSibling(80, 24, cancellation: cancellation);
      final rejected = expectLater(opening, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(service.active.keys, ['source', 'sibling-1']);
      await cancellation.cancel();
      await rejected.timeout(const Duration(seconds: 1));
      expect(service.active.keys, ['source']);
      expect(service.openGate!.isCompleted, isFalse);
      service.openGate!.complete();
    },
  );

  test('cancellation between reservation and handler registration releases the child', () async {
    final cancellation = TerminalConnectionCancellation();
    final source = SshTerminalConnection(
      service,
      'source',
      const Stream.empty(),
    );
    final opening = source.openSibling(80, 24, cancellation: cancellation);
    final rejected = expectLater(opening, throwsStateError);
    expect(service.active.keys, ['source', 'sibling-1']);
    await cancellation.cancel();
    await rejected;
    expect(service.active.keys, ['source']);
    expect(service.opened, isEmpty);
  });
}

class _Service extends SshTerminalService {
  _Service() : super(secureStorage: InMemorySecureStorage()) {
    active['source'] = _session('source');
  }

  final active = <String, SshSession>{};
  final opened =
      <(String, int, int, TmuxSessionOptions?, ScreenSessionOptions?)>[];
  final writes = <(String, String)>[];
  final resizes = <(String, int, int)>[];
  final disconnected = <String>[];
  final streams = <String, StreamController<String>>{};
  final pendingOpens = <String, Completer<void>>{};
  int serial = 0;
  Object? openError;
  Completer<void>? openGate;

  SshSession _session(String id) => SshSession(
    id: id,
    host: 'example.test',
    port: 22,
    username: 'alice',
    connected: true,
    startedAt: DateTime.utc(2026),
    lastActivityAt: DateTime.utc(2026),
  );

  @override
  bool canShareSession(String sessionId) => active.containsKey(sessionId);
  @override
  int connectionSessionCount(String sessionId) =>
      active.containsKey(sessionId) ? active.length : 0;
  @override
  Future<SshSession> shareSession(
    String sourceSessionId, {
    bool Function()? isCurrent,
  }) async {
    if (!canShareSession(sourceSessionId) || !(isCurrent?.call() ?? true)) {
      throw StateError('source unavailable');
    }
    final session = _session('sibling-${++serial}');
    active[session.id] = session;
    return session;
  }

  @override
  List<SshSession> getActiveSessions() => active.values.toList();

  @override
  Future<Stream<String>> startShell(
    String sessionId, {
    int width = 80,
    int height = 24,
    TmuxSessionOptions? tmux,
    ScreenSessionOptions? screen,
  }) async {
    opened.add((sessionId, width, height, tmux, screen));
    if (openGate != null) {
      final cancelled = Completer<void>();
      pendingOpens[sessionId] = cancelled;
      try {
        await Future.any([
          openGate!.future,
          cancelled.future.then<void>((_) => throw StateError('cancelled')),
        ]);
      } finally {
        pendingOpens.remove(sessionId);
      }
    }
    if (openError case final error?) throw error;
    final output = StreamController<String>();
    streams[sessionId] = output;
    return output.stream;
  }

  @override
  Future<void> writeToShell(String sessionId, String input) async =>
      writes.add((sessionId, input));
  @override
  Future<void> resizeTerminal(String sessionId, int width, int height) async =>
      resizes.add((sessionId, width, height));
  @override
  Future<void> disconnect(String sessionId) async {
    if (active.remove(sessionId) == null) return;
    final cancelled = pendingOpens[sessionId];
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
    disconnected.add(sessionId);
    final stream = streams.remove(sessionId);
    if (stream != null) unawaited(stream.close());
  }

  @override
  Future<void> dispose() async {
    for (final id in active.keys.toList()) {
      await disconnect(id);
    }
    await super.dispose();
  }
}

class _TmuxClient extends Fake implements TmuxControlClient {
  final ended = Completer<int?>();
  int closeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<int?> get done => ended.future;
  @override
  Object? get error => null;
  @override
  Future<void> close() async {
    closeCalls++;
    finish();
  }

  void finish() {
    if (!ended.isCompleted) ended.complete(0);
  }

  @override
  void dispose() {
    disposeCalls++;
    finish();
  }
}
