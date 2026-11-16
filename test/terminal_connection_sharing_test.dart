import 'dart:async';

import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TerminalSession source;
  late TerminalSession target;
  late _Route route;
  late _Connection original;

  setUp(() async {
    source = TerminalSession();
    target = TerminalSession();
    route = _Route();
    original = _Connection(route);
    await source.connect(
      (_, _) async => original,
      kind: TerminalSessionKind.ssh,
      label: 'alice@example.test',
    );
  });

  tearDown(() async {
    source.dispose();
    target.dispose();
    for (final connection in route.connections) {
      await connection.close();
    }
  });

  test('a sibling gets its own emulator, input and lifecycle', () async {
    final identity = source.connectionIdentity;
    final open = source.siblingConnectionFactory!;
    target.terminal.resize(112, 34);
    await target.connect(open, kind: TerminalSessionKind.ssh);
    final sibling = route.connections.last;
    expect(original.openSizes, [(112, 34)]);
    expect(source.sharedConnectionSessionCount, 2);
    expect(target.sharedConnectionSessionCount, 2);
    expect(source.connectionIdentity, same(identity));
    expect(target.connectionIdentity, isNot(same(identity)));

    original.controller.add('original output\r\n');
    sibling.controller.add('sibling output\r\n');
    target.terminal.textInput('independent');
    await _events();
    expect(original.writes, isEmpty);
    expect(sibling.writes, ['independent']);
    expect(source.terminal.buffer.getText(), contains('original output'));
    expect(source.terminal.buffer.getText(), isNot(contains('sibling output')));
    expect(target.terminal.buffer.getText(), contains('sibling output'));

    await source.disconnect();
    expect(target.isConnected, isTrue);
    expect(target.sharedConnectionSessionCount, 1);
    expect(sibling.closed, isFalse);
    target.terminal.textInput('still running');
    await _events();
    expect(sibling.writes.last, 'still running');
  });

  test(
    'a captured factory rejects a replaced source before acquiring',
    () async {
      final open = source.siblingConnectionFactory!;
      final replacement = _Connection(route);
      await source.connect(
        (_, _) async => replacement,
        kind: TerminalSessionKind.ssh,
      );
      await expectLater(open(80, 24), throwsStateError);
      expect(original.openSizes, isEmpty);
      expect(replacement.openSizes, isEmpty);
    },
  );

  test('a captured factory rejects a disconnected source', () async {
    final open = source.siblingConnectionFactory!;
    await source.disconnect();
    expect(source.siblingConnectionFactory, isNull);
    expect(source.sharedConnectionSessionCount, 0);
    await expectLater(open(80, 24), throwsStateError);
    expect(original.openSizes, isEmpty);
  });

  test('a captured factory rechecks route availability at use time', () async {
    final open = source.siblingConnectionFactory!;
    route.available = false;
    expect(source.siblingConnectionFactory, isNull);
    await expectLater(open(80, 24), throwsStateError);
    expect(original.openSizes, isEmpty);
  });

  test(
    'source disposal after acquisition preserves the pending sibling',
    () async {
      original.openGate = Completer<void>();
      final pending = target.connect(
        source.siblingConnectionFactory!,
        kind: TerminalSessionKind.ssh,
      );
      await _events();
      final sibling = route.connections.last;
      expect(route.connections, hasLength(2));
      source.dispose();
      await _events();
      expect(original.closed, isTrue);
      expect(sibling.closed, isFalse);
      original.openGate!.complete();
      await pending;
      expect(target.isConnected, isTrue);
      expect(target.sharedConnectionSessionCount, 1);
    },
  );

  test('destination cancellation releases its late sibling only', () async {
    original.openGate = Completer<void>();
    final pending = target.connect(
      source.siblingConnectionFactory!,
      kind: TerminalSessionKind.ssh,
    );
    await _events();
    final sibling = route.connections.last;
    await target.disconnect();
    original.openGate!.complete();
    await pending;
    expect(sibling.closed, isTrue);
    expect(original.closed, isFalse);
    expect(source.isConnected, isTrue);
    expect(target.status, TerminalSessionStatus.disconnected);
    expect(source.sharedConnectionSessionCount, 1);
  });

  test('ordinary transports keep the capability absent', () async {
    final basic = _BasicConnection();
    await target.connect(
      (_, _) async => basic,
      kind: TerminalSessionKind.local,
    );
    expect(target.siblingConnectionFactory, isNull);
    expect(target.sharedConnectionSessionCount, 0);
  });

  test('plain sibling metadata strips every secret and multiplexer option', () {
    final configs = [
      const SshTerminalConfig(
        host: 'example.test',
        port: 2222,
        username: 'alice',
        password: 'secret',
        privateKey: 'private',
        passphrase: 'phrase',
        forwardAgent: true,
        authentication: SshTerminalAuthentication.agent,
        jumpHosts: [
          SshJumpHost(
            host: 'jump.test',
            username: 'bob',
            authentication: SshTerminalAuthentication.privateKey,
            password: 'jump secret',
            privateKey: 'jump private',
            passphrase: 'jump phrase',
          ),
        ],
        tmux: TmuxSessionOptions(sessionName: 'work', controlMode: true),
      ),
      const SshTerminalConfig(
        host: 'example.test',
        port: 22,
        username: 'alice',
        screen: ScreenSessionOptions(sessionName: 'work'),
      ),
    ];
    for (final config in configs) {
      final shared = config.forSharedShell();
      expect(shared.host, config.host);
      expect(shared.port, config.port);
      expect(shared.username, config.username);
      expect(shared.authentication, config.authentication);
      expect(shared.forwardAgent, config.forwardAgent);
      expect(shared.password, isEmpty);
      expect(shared.privateKey, isEmpty);
      expect(shared.passphrase, isEmpty);
      expect(shared.tmux, isNull);
      expect(shared.screen, isNull);
      for (final jump in shared.jumpHosts) {
        expect(jump.password, isEmpty);
        expect(jump.privateKey, isEmpty);
        expect(jump.passphrase, isEmpty);
      }
    }
    expect(configs.first.password, 'secret');
    expect(configs.first.jumpHosts.first.privateKey, 'jump private');
  });
}

Future<void> _events() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Route {
  bool available = true;
  final connections = <_Connection>[];
}

class _BasicConnection implements TerminalConnection {
  final controller = StreamController<String>();
  final ended = Completer<int?>();
  final writes = <String>[];
  bool closed = false;

  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => controller.stream;
  @override
  Future<int?> get exitCode => ended.future;
  @override
  Future<void> write(String data) async => writes.add(data);
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    ended.complete(0);
    unawaited(controller.close());
  }
}

class _Connection extends _BasicConnection
    implements TerminalConnectionSharing {
  _Connection(this.route) {
    route.connections.add(this);
  }

  final _Route route;
  final openSizes = <(int, int)>[];
  Completer<void>? openGate;

  @override
  bool get canOpenSibling => !closed && route.available;
  @override
  int get sharedSessionCount =>
      route.connections.where((connection) => !connection.closed).length;
  @override
  Future<TerminalConnection> openSibling(int columns, int rows) async {
    openSizes.add((columns, rows));
    final sibling = _Connection(route);
    await openGate?.future;
    return sibling;
  }
}
