import 'dart:async';

import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/ssh_terminal_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:crisp_storage/crisp_storage.dart' show HostKeyPrompt;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _RecordingSshService service;
  late TerminalSession terminal;
  late ProviderContainer container;

  setUp(() {
    service = _RecordingSshService();
    terminal = TerminalSession();
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        sshTerminalServiceProvider.overrideWithValue(service),
      ],
    );
  });

  tearDown(() async {
    terminal.dispose();
    container.dispose();
    await service.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: TerminalPanel(session: terminal)),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> chooseAction(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('terminal-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  // Dialog field validation has its own widget tests. This boundary returns
  // a chosen config so these tests exercise panel dispatch and ownership.
  Future<void> submit(
    WidgetTester tester,
    SshTerminalConfig config, {
    bool settle = true,
  }) async {
    Navigator.of(tester.element(find.byType(SshTerminalConnectDialog)))
        .pop(config);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  testWidgets(
    'tmux reconnect retains the target and asks for credentials before replacing the connection',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('terminal-connect-ssh')));
      await tester.pumpAndSettle();
      final config = SshTerminalConfig(
        host: 'ssh.example',
        port: 2222,
        username: 'alice',
        password: 'first-password',
        gateway: Uri.parse('wss://gateway.example/ssh'),
        tmux: const TmuxSessionOptions(
          sessionName: 'build-01',
          mode: TmuxSessionMode.attach,
        ),
      );
      await submit(tester, config);
      expect(terminal.isConnected, isTrue);
      expect(service.requests.single.password, 'first-password');
      expect(service.shellOptions.single?.sessionName, 'build-01');
      expect(service.shellOptions.single?.mode, TmuxSessionMode.attach);
      expect(find.textContaining('alice@ssh.example'), findsOneWidget);
      expect(find.textContaining('tmux: build-01'), findsOneWidget);

      await chooseAction(tester, 'Reconnect SSH');
      final dialog = tester.widget<SshTerminalConnectDialog>(
        find.byType(SshTerminalConnectDialog),
      );
      final remembered = dialog.initialConfig!;
      expect(remembered.host, 'ssh.example');
      expect(remembered.port, 2222);
      expect(remembered.username, 'alice');
      expect(remembered.gateway, config.gateway);
      expect(remembered.tmux?.sessionName, 'build-01');
      expect(remembered.tmux?.mode, TmuxSessionMode.attach);
      expect(remembered.password, isEmpty);
      expect(remembered.privateKey, isEmpty);
      expect(remembered.passphrase, isEmpty);
      expect(terminal.isConnected, isTrue);
      expect(service.disconnected, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(terminal.isConnected, isTrue);
      expect(service.requests, hasLength(1));
      expect(service.disconnected, isEmpty);

      await chooseAction(tester, 'Detach from tmux');
      expect(terminal.status, TerminalSessionStatus.disconnected);
      expect(service.disconnected, ['session-1']);
      await chooseAction(tester, 'Reconnect SSH');
      await submit(
        tester,
        SshTerminalConfig(
          host: remembered.host,
          port: remembered.port,
          username: remembered.username,
          password: 'new-password',
          gateway: remembered.gateway,
          tmux: remembered.tmux,
        ),
      );
      expect(service.requests, hasLength(2));
      expect(service.requests.last.password, 'new-password');
      expect(service.shellOptions.last?.sessionName, 'build-01');
      expect(terminal.isConnected, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'private-key authentication forwards the passphrase and never retains it for reconnect',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('terminal-connect-ssh')));
      await tester.pumpAndSettle();
      await submit(
        tester,
        const SshTerminalConfig(
          host: 'key.example',
          port: 22,
          username: 'bob',
          authentication: SshTerminalAuthentication.privateKey,
          privateKey: 'test-key-material',
          passphrase: 'test-key-passphrase',
        ),
      );
      expect(
        service.requests.single.authentication,
        SshTerminalAuthentication.privateKey,
      );
      expect(service.requests.single.privateKey, 'test-key-material');
      expect(service.requests.single.passphrase, 'test-key-passphrase');
      expect(service.requests.single.password, isEmpty);
      expect(service.shellOptions.single, isNull);

      await chooseAction(tester, 'Reconnect SSH');
      final dialog = tester.widget<SshTerminalConnectDialog>(
        find.byType(SshTerminalConnectDialog),
      );
      expect(
        dialog.initialConfig!.authentication,
        SshTerminalAuthentication.privateKey,
      );
      expect(dialog.initialConfig!.privateKey, isEmpty);
      expect(dialog.initialConfig!.passphrase, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.disconnected, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'screen detach and reconnect preserve the exact target without secrets',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('terminal-connect-ssh')));
      await tester.pumpAndSettle();
      await submit(
        tester,
        const SshTerminalConfig(
          host: 'screen.example',
          port: 2222,
          username: 'alice',
          password: 'first-secret',
          screen: ScreenSessionOptions(
            sessionName: '123.work',
            mode: ScreenSessionMode.attach,
          ),
        ),
      );
      expect(terminal.isConnected, isTrue);
      expect(service.screenOptions.single?.sessionName, '123.work');
      expect(service.screenOptions.single?.mode, ScreenSessionMode.attach);
      expect(service.shellOptions.single, isNull);
      expect(find.textContaining('screen: 123.work'), findsOneWidget);

      await chooseAction(tester, 'Reconnect SSH');
      final remembered = tester
          .widget<SshTerminalConnectDialog>(
            find.byType(SshTerminalConnectDialog),
          )
          .initialConfig!;
      expect(remembered.screen?.sessionName, '123.work');
      expect(remembered.password, isEmpty);
      expect(service.disconnected, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(terminal.isConnected, isTrue);

      await chooseAction(tester, 'Detach from screen');
      expect(terminal.status, TerminalSessionStatus.disconnected);
      expect(service.disconnected, ['session-1']);
      await chooseAction(tester, 'Reconnect SSH');
      await submit(
        tester,
        SshTerminalConfig(
          host: remembered.host,
          port: remembered.port,
          username: remembered.username,
          password: 'replacement-secret',
          screen: remembered.screen,
        ),
      );
      expect(service.requests.last.password, 'replacement-secret');
      expect(service.screenOptions.last?.sessionName, '123.work');
      expect(terminal.isConnected, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'conflicting multiplexer options do not replace a live connection',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('terminal-connect-ssh')));
      await tester.pumpAndSettle();
      await submit(
        tester,
        const SshTerminalConfig(
          host: 'live.example',
          port: 22,
          username: 'alice',
        ),
      );
      await chooseAction(tester, 'Reconnect SSH');
      await submit(
        tester,
        const SshTerminalConfig(
          host: 'replacement.example',
          port: 22,
          username: 'alice',
          tmux: TmuxSessionOptions(sessionName: 'work'),
          screen: ScreenSessionOptions(sessionName: 'work'),
        ),
      );
      expect(terminal.isConnected, isTrue);
      expect(service.requests, hasLength(1));
      expect(service.disconnected, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('failed startup can reconnect with the previous destination', (
    tester,
  ) async {
    service.failNextConnection = true;
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('terminal-connect-ssh')));
    await tester.pumpAndSettle();
    await submit(
      tester,
      const SshTerminalConfig(
        host: 'retry.example',
        port: 2222,
        username: 'alice',
        password: 'rejected-password',
      ),
    );
    expect(terminal.status, TerminalSessionStatus.failed);
    await chooseAction(tester, 'Reconnect SSH');
    final dialog = tester.widget<SshTerminalConnectDialog>(
      find.byType(SshTerminalConnectDialog),
    );
    expect(dialog.initialConfig!.host, 'retry.example');
    expect(dialog.initialConfig!.port, 2222);
    expect(dialog.initialConfig!.password, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.requests, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('overlapping reconnect attempts keep host-key prompts isolated', (
    tester,
  ) async {
    Future<bool> defaultPrompt(String _, String __) async => false;
    service.confirmHostKey = defaultPrompt;
    final firstAuthentication = Completer<void>();
    service.nextAuthentication = firstAuthentication;
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('terminal-connect-ssh')));
    await tester.pumpAndSettle();
    await submit(
      tester,
      const SshTerminalConfig(
        host: 'first.example',
        port: 22,
        username: 'alice',
      ),
      settle: false,
    );
    expect(terminal.isConnecting, isTrue);
    final firstPrompt = service.prompts.single!;
    expect(service.confirmHostKey, same(defaultPrompt));
    await terminal.disconnect();
    await tester.pumpAndSettle();

    final secondAuthentication = Completer<void>();
    service.nextAuthentication = secondAuthentication;
    await chooseAction(tester, 'Reconnect SSH');
    await submit(
      tester,
      const SshTerminalConfig(
        host: 'second.example',
        port: 22,
        username: 'bob',
      ),
      settle: false,
    );
    expect(service.prompts, hasLength(2));
    expect(service.prompts.last, isNot(same(firstPrompt)));
    expect(await firstPrompt('first.example:22', 'old-key'), isFalse);
    expect(find.text('Trust SSH host?'), findsNothing);

    firstAuthentication.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(service.disconnected, ['session-1']);
    expect(service.shellOptions, isEmpty);
    expect(terminal.isConnecting, isTrue);
    expect(service.confirmHostKey, same(defaultPrompt));

    secondAuthentication.complete();
    await tester.pumpAndSettle();
    expect(terminal.isConnected, isTrue);
    expect(terminal.label, 'bob@second.example');
    expect(service.shellOptions, hasLength(1));
    expect(service.confirmHostKey, same(defaultPrompt));
    expect(await firstPrompt('first.example:22', 'old-key'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

/// The real TerminalSession and panel own this fake transport service. Channel
/// creation, encoding and cleanup are covered at the SSH boundary separately.
class _RecordingSshService extends SshTerminalService {
  _RecordingSshService() : super(secureStorage: InMemorySecureStorage());

  final requests = <SshTerminalConfig>[];
  final prompts = <HostKeyPrompt?>[];
  final shellOptions = <TmuxSessionOptions?>[];
  final screenOptions = <ScreenSessionOptions?>[];
  final disconnected = <String>[];
  final _sessions = <String, SshSession>{};
  final _outputs = <String, StreamController<String>>{};
  bool failNextConnection = false;
  Completer<void>? nextAuthentication;

  Future<SshSession> _connect(
    SshTerminalConfig config, {
    HostKeyPrompt? hostKeyPrompt,
  }) async {
    requests.add(config);
    prompts.add(hostKeyPrompt);
    final id = 'session-${requests.length}';
    final authentication = nextAuthentication;
    nextAuthentication = null;
    if (authentication != null) await authentication.future;
    if (failNextConnection) {
      failNextConnection = false;
      throw StateError('Fixture authentication failed');
    }
    final now = DateTime.now();
    final session = SshSession(
      id: id,
      host: config.host,
      port: config.port,
      username: config.username,
      connected: true,
      startedAt: now,
      lastActivityAt: now,
    );
    _sessions[session.id] = session;
    return session;
  }

  @override
  Future<SshSession> connect(
    String host,
    int port,
    String username,
    String password, {
    Uri? gateway,
    HostKeyPrompt? hostKeyPrompt,
  }) => _connect(
    SshTerminalConfig(
      host: host,
      port: port,
      username: username,
      password: password,
      gateway: gateway,
    ),
    hostKeyPrompt: hostKeyPrompt,
  );

  @override
  Future<SshSession> connectWithKey(
    String host,
    int port,
    String username,
    String privateKey, {
    Uri? gateway,
    String? passphrase,
    HostKeyPrompt? hostKeyPrompt,
  }) => _connect(
    SshTerminalConfig(
      host: host,
      port: port,
      username: username,
      privateKey: privateKey,
      passphrase: passphrase ?? '',
      authentication: SshTerminalAuthentication.privateKey,
      gateway: gateway,
    ),
    hostKeyPrompt: hostKeyPrompt,
  );

  @override
  Future<Stream<String>> startShell(
    String sessionId, {
    int width = 80,
    int height = 24,
    TmuxSessionOptions? tmux,
    ScreenSessionOptions? screen,
  }) async {
    shellOptions.add(tmux);
    screenOptions.add(screen);
    final output = StreamController<String>();
    _outputs[sessionId] = output;
    return output.stream;
  }

  @override
  List<SshSession> getActiveSessions() => _sessions.values.toList();

  @override
  Future<void> resizeTerminal(String sessionId, int width, int height) async {}

  @override
  Future<void> disconnect(String sessionId) async {
    if (_sessions.remove(sessionId) == null) return;
    disconnected.add(sessionId);
    final output = _outputs.remove(sessionId);
    if (output != null) unawaited(output.close());
  }

  @override
  Future<void> dispose() async {
    for (final id in _sessions.keys.toList()) {
      await disconnect(id);
    }
    await super.dispose();
  }
}
