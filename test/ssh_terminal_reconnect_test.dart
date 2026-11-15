import 'dart:async';

import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/ssh_multiplexer_session.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/ssh_terminal_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:crisp_cloud/widgets/ssh_multiplexer_sessions_dialog.dart';
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

  Future<void> mount(WidgetTester tester, {bool visible = true}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: TerminalPanel(session: terminal, visible: visible),
          ),
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

  testWidgets(
    'browsing tmux starts no shell before an exact selection and keeps a secret-free reconnect route',
    (tester) async {
      service.discoveryResults = parseSshMultiplexerSessions(
        SshMultiplexer.tmux,
        'build-01\t3\t1\nother\t1\t0\n',
      );
      await mount(tester);
      await chooseAction(tester, 'Browse tmux sessions');
      await submit(
        tester,
        const SshTerminalConfig(
          host: 'target.example',
          port: 2222,
          username: 'alice',
          authentication: SshTerminalAuthentication.privateKey,
          privateKey: 'target-private-key',
          passphrase: 'target-passphrase',
          jumpHosts: [
            SshJumpHost(
              host: 'bastion.example',
              username: 'outer',
              password: 'hop-secret',
            ),
          ],
        ),
        settle: false,
      );
      expect(terminal.isConnecting, isTrue);
      expect(service.discoveries, [SshMultiplexer.tmux]);
      expect(service.discoverySessions, ['session-1']);
      expect(service.shellOptions, isEmpty);
      expect(service.requests.single.jumpHosts.single.password, 'hop-secret');
      expect(service.requests.single.privateKey, 'target-private-key');
      expect(find.byType(SshMultiplexerSessionsDialog), findsOneWidget);

      final tile = find.byKey(
        const ValueKey('ssh-multiplexer-session-build-01'),
      );
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(terminal.isConnected, isTrue);
      expect(service.shellOptions.single?.sessionName, 'build-01');
      expect(service.shellOptions.single?.mode, TmuxSessionMode.attach);
      expect(service.screenOptions.single, isNull);
      expect(terminal.label, 'alice@target.example · tmux: build-01');

      await chooseAction(tester, 'Reconnect SSH');
      final remembered = tester
          .widget<SshTerminalConnectDialog>(
            find.byType(SshTerminalConnectDialog),
          )
          .initialConfig!;
      expect(remembered.tmux?.sessionName, 'build-01');
      expect(remembered.tmux?.mode, TmuxSessionMode.attach);
      expect(remembered.port, 2222);
      expect(remembered.authentication, SshTerminalAuthentication.privateKey);
      expect(remembered.privateKey, isEmpty);
      expect(remembered.passphrase, isEmpty);
      expect(remembered.jumpHosts.single.host, 'bastion.example');
      expect(remembered.jumpHosts.single.password, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.disconnected, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('screen browsing attaches the selected full ID among duplicate names', (tester) async {
    service.discoveryResults = parseSshMultiplexerSessions(
      SshMultiplexer.screen,
      'There are screens on:\n'
      '\t123.work\t(Detached)\n'
      '\t456.work\t(Attached)\n'
      '2 Sockets in /run/screen/S-alice.\n',
    );
    await mount(tester);
    await chooseAction(tester, 'Browse screen sessions');
    await submit(
      tester,
      const SshTerminalConfig(
        host: 'screen.example', port: 22, username: 'alice',
      ),
      settle: false,
    );
    expect(service.shellOptions, isEmpty);
    final tile = find.byKey(
      const ValueKey('ssh-multiplexer-session-456.work'),
    );
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(service.discoveries, [SshMultiplexer.screen]);
    expect(service.screenOptions.single?.sessionName, '456.work');
    expect(service.screenOptions.single?.mode, ScreenSessionMode.attach);
    expect(service.shellOptions.single, isNull);
    expect(terminal.label, 'alice@screen.example · screen: 456.work');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('cancelling a session picker closes its authenticated connection', (tester) async {
    service.discoveryResults = parseSshMultiplexerSessions(
      SshMultiplexer.tmux, 'work\t1\t0\n',
    );
    await mount(tester);
    await chooseAction(tester, 'Browse tmux sessions');
    await submit(
      tester,
      const SshTerminalConfig(
        host: 'host.example', port: 22, username: 'alice',
      ),
      settle: false,
    );
    expect(service.getActiveSessions(), hasLength(1));
    await tester.tap(find.byKey(const ValueKey('ssh-multiplexer-cancel')));
    await tester.pumpAndSettle();
    expect(service.disconnected, ['session-1']);
    expect(service.getActiveSessions(), isEmpty);
    expect(service.shellOptions, isEmpty);
    expect(terminal.status, TerminalSessionStatus.disconnected);
    expect(terminal.error, isNull);
    expect(find.byType(SshMultiplexerSessionsDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a stale listing never displays a picker or opens a shell', (tester) async {
    final pending = Completer<List<SshMultiplexerSession>>();
    service.nextDiscovery = pending;
    await mount(tester);
    await chooseAction(tester, 'Browse tmux sessions');
    await submit(
      tester,
      const SshTerminalConfig(
        host: 'host.example', port: 22, username: 'alice',
      ),
      settle: false,
    );
    expect(terminal.isConnecting, isTrue);
    expect(service.discoveryLeases.single!(), isTrue);
    await terminal.disconnect();
    await tester.pump();
    expect(service.discoveryLeases.single!(), isFalse);
    pending.complete(parseSshMultiplexerSessions(
      SshMultiplexer.tmux, 'late\t1\t0\n',
    ));
    await tester.pumpAndSettle();
    expect(service.disconnected, ['session-1']);
    expect(service.shellOptions, isEmpty);
    expect(find.byType(SshMultiplexerSessionsDialog), findsNothing);
    expect(terminal.status, TerminalSessionStatus.disconnected);
    expect(terminal.error, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('hiding a panel dismisses only its owned picker and closes the route', (tester) async {
    service.discoveryResults = parseSshMultiplexerSessions(
      SshMultiplexer.tmux, 'work\t1\t0\n',
    );
    await mount(tester);
    await chooseAction(tester, 'Browse tmux sessions');
    await submit(
      tester,
      const SshTerminalConfig(
        host: 'host.example', port: 22, username: 'alice',
      ),
      settle: false,
    );
    expect(find.byType(SshMultiplexerSessionsDialog), findsOneWidget);
    await mount(tester, visible: false);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.byType(SshMultiplexerSessionsDialog), findsNothing);
    expect(service.disconnected, ['session-1']);
    expect(service.shellOptions, isEmpty);
    expect(terminal.status, TerminalSessionStatus.disconnected);
    expect(terminal.error, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('browse credentials hide old session settings but retain the jump editor', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('terminal-connect-ssh')));
    await tester.pumpAndSettle();
    await submit(
      tester,
      SshTerminalConfig(
        host: 'host.example',
        port: 22,
        username: 'alice',
        gateway: Uri.parse('wss://gateway.example/ssh'),
        tmux: const TmuxSessionOptions(
          sessionName: 'previous', mode: TmuxSessionMode.attach,
        ),
      ),
    );
    service.discoveryResults = parseSshMultiplexerSessions(
      SshMultiplexer.screen,
      'There is a screen on:\n'
      '\t123.work\t(Detached)\n'
      '1 Socket in /run/screen/S-alice.\n',
    );
    await chooseAction(tester, 'Browse screen sessions');
    final dialog = tester.widget<SshTerminalConnectDialog>(
      find.byType(SshTerminalConnectDialog),
    );
    expect(dialog.showSessionOptions, isFalse);
    expect(dialog.initialConfig?.tmux?.sessionName, 'previous');
    expect(find.byKey(const ValueKey('terminal-ssh-session-mode')), findsNothing);
    expect(find.byKey(const ValueKey('terminal-ssh-tmux-name')), findsNothing);
    expect(find.byKey(const ValueKey('terminal-ssh-screen-name')), findsNothing);
    expect(find.byKey(const ValueKey('terminal-ssh-add-jump')), findsOneWidget);
    // Use the real form submission to prove hidden old mode is cleared.
    await tester.tap(find.text('Connect'));
    // Drain reconnect cleanup until the picker appears. The terminal remains
    // connecting while that picker is open, so its progress cannot settle.
    for (var frame = 0;
        frame < 30 && find.byType(SshMultiplexerSessionsDialog).evaluate().isEmpty;
        frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SshMultiplexerSessionsDialog), findsOneWidget,
        reason: 'status=${terminal.status}, requests=${service.requests.length}, '
            'discoveries=${service.discoveries.length}');
    expect(service.discoveries, [SshMultiplexer.screen]);
    expect(terminal.label, 'alice@host.example');
    expect(service.shellOptions, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('ssh-multiplexer-cancel')));
    await tester.pumpAndSettle();
    expect(service.disconnected, ['session-1', 'session-2']);
    expect(service.shellOptions, hasLength(1));
    expect(terminal.error, isNull);
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
  List<SshMultiplexerSession> discoveryResults = const [];
  Completer<List<SshMultiplexerSession>>? nextDiscovery;
  final discoveries = <SshMultiplexer>[];
  final discoverySessions = <String>[];
  final discoveryLeases = <bool Function()?>[];

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
    List<SshJumpHost> jumpHosts = const [],
    HostKeyPrompt? hostKeyPrompt,
    bool Function()? isCurrent,
  }) => _connect(
    SshTerminalConfig(
      host: host,
      port: port,
      username: username,
      password: password,
      gateway: gateway,
      jumpHosts: jumpHosts,
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
    List<SshJumpHost> jumpHosts = const [],
    String? passphrase,
    HostKeyPrompt? hostKeyPrompt,
    bool Function()? isCurrent,
  }) => _connect(
    SshTerminalConfig(
      host: host,
      port: port,
      username: username,
      privateKey: privateKey,
      passphrase: passphrase ?? '',
      authentication: SshTerminalAuthentication.privateKey,
      gateway: gateway,
      jumpHosts: jumpHosts,
    ),
    hostKeyPrompt: hostKeyPrompt,
  );

  @override
  Future<List<SshMultiplexerSession>> listMultiplexerSessions(
    String sessionId, {
    required SshMultiplexer kind,
    bool Function()? isCurrent,
  }) async {
    discoveries.add(kind);
    discoverySessions.add(sessionId);
    discoveryLeases.add(isCurrent);
    final pending = nextDiscovery;
    nextDiscovery = null;
    // Deliberately allow stale completion: the panel must guard its own
    // generation even if an injected transport does not cancel immediately.
    return pending == null ? discoveryResults : await pending.future;
  }

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
