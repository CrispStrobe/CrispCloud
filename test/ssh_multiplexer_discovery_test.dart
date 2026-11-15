import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/ssh_multiplexer_session.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher discoveryFails(SshMultiplexerDiscoveryFailure reason) => throwsA(
  isA<SshMultiplexerDiscoveryException>().having(
    (error) => error.failure, 'failure', reason,
  ),
);

void main() {
  test('uses only the fixed no-PTY command and closes a successful channel', () async {
    final fixture = await _fixture();
    final listing = fixture.list();
    await fixture.client.channel.finish('work\t2\t1\n');
    final rows = await listing;
    expect(rows.single.target, 'work');
    expect(fixture.client.commands, [sshMultiplexerListCommand(SshMultiplexer.tmux)]);
    expect(fixture.client.ptys, [null]);
    expect(fixture.client.channel.closed, isTrue);
    expect(fixture.client.isClosed, isFalse);
  });

  test('waits for a late exit status after both streams reach EOF', () async {
    final fixture = await _fixture();
    var completed = false;
    final listing = fixture.list();
    unawaited(listing.then<void>((_) { completed = true; }));
    fixture.client.channel.output.add(Uint8List.fromList(utf8.encode('work\t1\t0\n')));
    await fixture.client.channel.endOutput();
    await _flush();
    expect(completed, isFalse);
    fixture.client.channel.finishStatus(0);
    expect((await listing).single.target, 'work');
    expect(fixture.client.channel.closed, isTrue);
  });

  test('exit status never discards output queued afterwards', () async {
    final fixture = await _fixture();
    final listing = fixture.list();
    fixture.client.channel.finishStatus(0);
    await _flush();
    fixture.client.channel.output.add(Uint8List.fromList(utf8.encode('最後\t1\t0\n')));
    await fixture.client.channel.endOutput();
    final row = (await listing).single;
    expect(row.name, '最後');
    expect(row.selectable, isFalse);
  });

  test('stdout and stderr share one byte budget', () async {
    final fixture = await _fixture();
    final failed = expectLater(fixture.list(),
        discoveryFails(SshMultiplexerDiscoveryFailure.tooMuchOutput));
    fixture.client.channel.output.add(Uint8List.fromList(utf8.encode('work\t1\t0\n')));
    fixture.client.channel.errors.add(Uint8List(sshMultiplexerMaxOutputBytes));
    await failed;
    expect(fixture.client.channel.closed, isTrue);
    expect(fixture.client.isClosed, isFalse);
  });

  test('missing tool errors remain errors and still close the channel', () async {
    final fixture = await _fixture();
    final failed = expectLater(fixture.list(kind: SshMultiplexer.screen),
        discoveryFails(SshMultiplexerDiscoveryFailure.missingTool));
    await fixture.client.channel.finish('', code: 127);
    await failed;
    expect(fixture.client.channel.closed, isTrue);
    expect(fixture.client.commands, [sshMultiplexerListCommand(SshMultiplexer.screen)]);
  });

  test('screen discovery uses full IDs without opening an interactive shell', () async {
    final fixture = await _fixture();
    final listing = fixture.list(kind: SshMultiplexer.screen);
    await fixture.client.channel.finish(
      'There is a screen on:\n\t123.work\t(Detached)\n'
      '1 Socket in /run/screen/S-alice.\n',
    );
    expect((await listing).single.screenOptions!.sessionName, '123.work');
    expect(fixture.client.ptys.single, isNull);
  });

  test('invalid UTF-8 is rejected instead of changing an attach target', () async {
    final fixture = await _fixture();
    final failed = expectLater(fixture.list(),
        discoveryFails(SshMultiplexerDiscoveryFailure.invalidListing));
    fixture.client.channel.output.add(Uint8List.fromList([0xff]));
    fixture.client.channel.finishStatus(0);
    await fixture.client.channel.endOutput();
    await failed;
    expect(fixture.client.channel.closed, isTrue);
  });

  test('a quiet stale tab cancels without killing the verified connection', () async {
    final fixture = await _fixture();
    var current = true;
    final failed = expectLater(fixture.list(isCurrent: () => current), throwsStateError);
    await _flush();
    current = false;
    await failed;
    expect(fixture.client.channel.closed, isTrue);
    expect(fixture.client.isClosed, isFalse);
  });

  test('a request returning after cancellation closes its late channel', () async {
    final fixture = await _fixture();
    final request = Completer<SSHSession>();
    fixture.client.pendingExecution = request.future;
    var current = true;
    final failed = expectLater(fixture.list(isCurrent: () => current), throwsStateError);
    await _flush();
    current = false;
    await failed;
    final late = _Channel();
    request.complete(late);
    await _flush();
    expect(late.closed, isTrue);
    expect(fixture.client.isClosed, isFalse);
  });

  test('disconnecting the connection cancels an in-flight listing', () async {
    final fixture = await _fixture();
    final failed = expectLater(fixture.list(), throwsStateError);
    await _flush();
    await fixture.service.disconnect(fixture.id);
    await failed;
    expect(fixture.client.channel.closed, isTrue);
    expect(fixture.service.getActiveSessions(), isEmpty);
  });

  test('one session cannot accumulate concurrent discovery channels', () async {
    final fixture = await _fixture();
    final first = fixture.list();
    await expectLater(fixture.list(), throwsStateError);
    expect(fixture.client.commands, hasLength(1));
    await fixture.client.channel.finish('work\t1\t0\n');
    await first;
    fixture.client.channel = _Channel();
    final second = fixture.list();
    await fixture.client.channel.finish('other\t1\t0\n');
    expect((await second).single.target, 'other');
    expect(fixture.client.commands, hasLength(2));
  });

  test('transport stream errors fail and release the listing channel', () async {
    final fixture = await _fixture();
    final failed = expectLater(fixture.list(),
        discoveryFails(SshMultiplexerDiscoveryFailure.commandFailed));
    fixture.client.channel.errors.addError(StateError('remote stream failed'));
    await failed;
    expect(fixture.client.channel.closed, isTrue);
  });

  test('request timeout also owns and closes a later returned channel', () async {
    final fixture = await _fixture();
    final request = Completer<SSHSession>();
    fixture.client.pendingExecution = request.future;
    await expectLater(
      fixture.list().timeout(const Duration(seconds: 15)),
      discoveryFails(SshMultiplexerDiscoveryFailure.timeout),
    );
    final late = _Channel();
    request.complete(late);
    await _flush();
    expect(late.closed, isTrue);
  });

  test('synchronous exec failures use the same bounded cleanup path', () async {
    final fixture = await _fixture();
    fixture.client.throwOnExecute = true;
    await expectLater(fixture.list(),
        discoveryFails(SshMultiplexerDiscoveryFailure.commandFailed));
    fixture.client.throwOnExecute = false;
    final retry = fixture.list();
    await fixture.client.channel.finish('work\t1\t0\n');
    expect((await retry).single.target, 'work');
  });

  test('already stale requests never send a server command', () async {
    final fixture = await _fixture();
    await expectLater(fixture.list(isCurrent: () => false), throwsStateError);
    expect(fixture.client.commands, isEmpty);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<_Fixture> _fixture() async {
  final fixture = _Fixture();
  addTearDown(fixture.service.dispose);
  fixture.id = (await fixture.service.connect(
    'host.example', 22, 'alice', 'password',
    gateway: Uri.parse('wss://gateway.example/ssh'),
  )).id;
  return fixture;
}

class _Fixture {
  final client = _Client();
  late String id;
  late final service = SshTerminalService(
    secureStorage: InMemorySecureStorage(),
    clientConnector: (_, __, {
      required username, password, identities, gateway,
    }) async => client,
  );

  Future<List<SshMultiplexerSession>> list({
    SshMultiplexer kind = SshMultiplexer.tmux,
    bool Function()? isCurrent,
  }) => service.listMultiplexerSessions(id, kind: kind, isCurrent: isCurrent);
}

class _Client implements SSHClient {
  _Channel channel = _Channel();
  final commands = <String>[];
  final ptys = <SSHPtyConfig?>[];
  final _done = Completer<void>();
  Future<SSHSession>? pendingExecution;
  bool throwOnExecute = false;
  bool _closed = false;

  @override
  bool get isClosed => _closed;
  @override
  Future<void> get authenticated => Future<void>.value();
  @override
  Future<void> get done => _done.future;

  @override
  Future<SSHSession> execute(String command, {
    SSHPtyConfig? pty, SSHX11Config? x11, Map<String, String>? environment,
  }) {
    commands.add(command);
    ptys.add(pty);
    if (throwOnExecute) throw StateError('exec failed synchronously');
    return pendingExecution ?? Future<SSHSession>.value(channel);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    channel.close();
    if (!_done.isCompleted) _done.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Channel implements SSHSession {
  final output = StreamController<Uint8List>(onCancel: () async {});
  final errors = StreamController<Uint8List>(onCancel: () async {});
  final _done = Completer<void>();
  int? _exitCode;
  bool closed = false;

  @override
  Stream<Uint8List> get stdout => output.stream;
  @override
  Stream<Uint8List> get stderr => errors.stream;
  @override
  Future<void> get done => _done.future;
  @override
  int? get exitCode => _exitCode;

  void finishStatus(int? code) {
    _exitCode = code;
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> endOutput() async {
    await Future.wait([output.close(), errors.close()]);
  }

  Future<void> finish(String text, {String stderr = '', int? code = 0}) async {
    if (text.isNotEmpty) output.add(Uint8List.fromList(utf8.encode(text)));
    if (stderr.isNotEmpty) errors.add(Uint8List.fromList(utf8.encode(stderr)));
    finishStatus(code);
    await endOutput();
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    if (!_done.isCompleted) _done.complete();
    unawaited(output.close());
    unawaited(errors.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
