import 'dart:async';

import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/ssh_terminal_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/ssh_tmux_control_output.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/services/tmux_terminal_connection.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:crisp_cloud/widgets/tmux_control_workspace.dart';
import 'package:crisp_storage/crisp_storage.dart' show HostKeyPrompt;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tmux_control_workspace_fixture.dart';

void main() {
  late _PendingSshService service;
  late TerminalSession terminal;
  late ProviderContainer container;

  setUp(() {
    service = _PendingSshService();
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

  Future<void> drainCleanup(WidgetTester tester) async {
    // StreamController cancellation can return a root-zone future. Let that
    // real microtask settle between pumps of the widget's fake async zone.
    for (var i = 0; i < 8; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
  }

  Future<(_Workspace, TmuxTerminalConnection)> connectWorkspace() async {
    final client = _Workspace();
    await client.initialize();
    final connection = TmuxTerminalConnection(service, 'fixture', client);
    await terminal.connect(
      (_, __) async => connection,
      kind: TerminalSessionKind.ssh,
      label: 'alice@host · tmux: work',
    );
    return (client, connection);
  }

  Future<void> beginPendingStart(WidgetTester tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('terminal-connect-ssh')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(SshTerminalConnectDialog))).pop(
      const SshTerminalConfig(
        host: 'host.example',
        port: 22,
        username: 'alice',
        password: 'fixture',
        tmux: TmuxSessionOptions(sessionName: 'work', controlMode: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(terminal.isConnecting, isTrue);
    expect(service.controlRequests, 1);
  }

  testWidgets('caller-owned tmux survives viewport removal and remount', (
    tester,
  ) async {
    final (client, connection) = await connectWorkspace();
    final pane = client.panes['%1']!.session;
    await mount(tester);
    expect(find.byType(TmuxControlWorkspace), findsOneWidget);
    expect(terminal.workspaceConnection, same(connection));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(client.closeCalls, 0);
    expect(client.disposeCalls, 0);
    expect(terminal.isConnected, isTrue);
    pane.terminal.write('while view absent\r\n');

    await mount(tester);
    expect(find.byType(TmuxControlWorkspace), findsOneWidget);
    expect(
      tester
          .widget<TmuxControlWorkspace>(find.byType(TmuxControlWorkspace))
          .client,
      same(client),
    );
    expect(client.panes['%1']!.session, same(pane));
    expect(pane.terminal.buffer.getText(), contains('while view absent'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('disconnect retains the readonly workspace across remount', (
    tester,
  ) async {
    final (client, connection) = await connectWorkspace();
    await mount(tester);
    final disconnecting = terminal.disconnect();
    await drainCleanup(tester);
    await disconnecting;
    expect(terminal.status, TerminalSessionStatus.disconnected);
    expect(terminal.workspaceConnection, same(connection));
    expect(client.closeCalls, 1);
    expect(client.disposeCalls, 0);
    expect(client.ready, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await mount(tester);
    expect(find.byType(TmuxControlWorkspace), findsOneWidget);
    expect(
      client.panes['%1']!.session.terminal.buffer.getText(),
      contains('%1'),
    );
    expect(client.closeCalls, 1);
    expect(client.disposeCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('replacement waits for old pane views before releasing buffers', (
    tester,
  ) async {
    final (client, _) = await connectWorkspace();
    await mount(tester);
    final replacement = terminal.connect(
      (_, __) async => TmuxWorkspaceConnection(),
      kind: TerminalSessionKind.local,
    );
    expect(terminal.workspaceConnection, isNull);
    expect(client.disposeCalls, 0);
    await drainCleanup(tester);
    await replacement;
    await tester.pump();
    expect(find.byType(TmuxControlWorkspace), findsNothing);
    expect(client.closeCalls, 1);
    expect(client.disposeCalls, 1);
    expect(terminal.isConnected, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('session disposal defers workspace disposal until view unmount', (
    tester,
  ) async {
    final (client, _) = await connectWorkspace();
    await mount(tester);
    terminal.dispose();
    expect(client.disposeCalls, 0);
    await tester.pumpWidget(const SizedBox());
    await drainCleanup(tester);
    expect(client.closeCalls, 1);
    expect(client.disposeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('client protocol failure is visible on the outer session', (
    tester,
  ) async {
    final (client, connection) = await connectWorkspace();
    await mount(tester);
    final error = StateError('fixture protocol failure');
    client.error = error;
    await client.detach();
    await drainCleanup(tester);
    expect(terminal.status, TerminalSessionStatus.failed);
    expect(terminal.error, same(error));
    expect(terminal.workspaceConnection, same(connection));
    expect(client.disposeCalls, 0);
    expect(find.textContaining('fixture protocol failure'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('removing a caller-owned panel cancels a pending handshake', (
    tester,
  ) async {
    await beginPendingStart(tester);
    expect(service.rawOpened, isTrue);
    await tester.pumpWidget(const SizedBox());
    await drainCleanup(tester);
    expect(service.disconnected, ['pending']);
    expect(service.active, isFalse);
    expect(terminal.workspaceConnection, isNull);
    expect(terminal.isConnected, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removing a panel cancels the route before control exec returns',
    (tester) async {
      service.execGate = Completer<void>();
      await beginPendingStart(tester);
      expect(service.rawOpened, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(service.disconnected, ['pending']);
      expect(service.active, isFalse);
      service.execGate!.complete();
      await drainCleanup(tester);
      expect(terminal.workspaceConnection, isNull);
      expect(terminal.isConnected, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  test('adapter retries a failed transport close', () async {
    final client = _Workspace()..failFirstClose = true;
    final connection = TmuxTerminalConnection(service, 'fixture', client);
    await expectLater(connection.close(), throwsStateError);
    await connection.close();
    expect(client.closeCalls, 2);
    connection.disposeWorkspace();
    expect(client.disposeCalls, 1);
  });
}

class _Workspace extends TmuxWorkspaceFixture {
  int closeCalls = 0;
  int disposeCalls = 0;
  bool failFirstClose = false;

  @override
  Future<void> close() async {
    closeCalls++;
    if (failFirstClose && closeCalls == 1) {
      throw StateError('fixture cleanup failed');
    }
    if (!isClosed) await super.close();
  }

  @override
  void dispose() {
    if (disposeCalls != 0) return;
    disposeCalls++;
    super.dispose();
  }
}

class _PendingSshService extends SshTerminalService {
  _PendingSshService() : super(secureStorage: InMemorySecureStorage());
  final disconnected = <String>[];
  final stdout = StreamController<List<int>>(onCancel: () async {});
  final stderr = StreamController<List<int>>(onCancel: () async {});
  final exit = Completer<int?>();
  Completer<void>? execGate;
  int controlRequests = 0;
  bool rawOpened = false;
  bool active = false;

  @override
  Future<SshSession> connect(
    String host,
    int port,
    String username,
    String password, {
    Uri? gateway,
    List<SshJumpHost> jumpHosts = const [],
    bool forwardAgent = false,
    HostKeyPrompt? hostKeyPrompt,
    bool Function()? isCurrent,
  }) async {
    active = true;
    return SshSession(
      id: 'pending',
      host: host,
      port: port,
      username: username,
      connected: true,
      startedAt: DateTime.now(),
      lastActivityAt: DateTime.now(),
    );
  }

  @override
  Future<SshTmuxControlOutput> startTmuxControl(
    String sessionId, {
    required TmuxSessionOptions tmux,
    int width = 80,
    int height = 24,
  }) async {
    controlRequests++;
    await execGate?.future;
    rawOpened = true;
    return SshTmuxControlOutput(
      stdout: stdout.stream,
      stderr: stderr.stream,
      exitCode: exit.future,
      write: (_) async {},
      close: () => disconnect(sessionId),
    );
  }

  @override
  Future<void> disconnect(String sessionId) async {
    if (!active) return;
    active = false;
    disconnected.add(sessionId);
    if (!stdout.isClosed) unawaited(stdout.close());
    if (!stderr.isClosed) unawaited(stderr.close());
    if (!exit.isCompleted) exit.complete(0);
  }

  @override
  Future<void> dispose() async {
    await disconnect('pending');
    if (!stdout.isClosed) unawaited(stdout.close());
    if (!stderr.isClosed) unawaited(stderr.close());
    if (!exit.isCompleted) exit.complete(0);
    await super.dispose();
  }
}
