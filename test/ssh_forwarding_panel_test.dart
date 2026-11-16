import 'dart:async';

import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/ssh_forwarding_profiles_provider.dart';
import 'package:crisp_cloud/providers/ssh_terminal_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_forwarding_profiles.dart';
import 'package:crisp_cloud/services/ssh_port_forwarding.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/ssh_port_forwarding_dialog.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:crisp_storage/crisp_storage.dart' show HostKeyPrompt;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ssh_forwarding_profile_fixture.dart';

void main() {
  late ForwardingMemory memory;
  late SshForwardingProfiles store;
  late _ForwardingSshService service;
  late TerminalSession terminal;
  late ProviderContainer container;
  const config = SshTerminalConfig(
    host: 'server.example',
    port: 22,
    username: 'alice',
    password: 'ephemeral',
  );

  setUp(() {
    memory = ForwardingMemory();
    store = memory.store();
    service = _ForwardingSshService();
    terminal = TerminalSession();
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        sshTerminalServiceProvider.overrideWithValue(service),
        sshForwardingProfilesProvider.overrideWithValue(store),
      ],
    );
  });
  tearDown(() async {
    terminal.dispose();
    container.dispose();
    await service.dispose();
    store.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    TerminalSession? selected,
    bool visible = true,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: TerminalPanel(
              session: selected ?? terminal,
              visible: visible,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> action(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('terminal-actions')));
    await tester.pumpAndSettle();
    final item = find.text(label).last;
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    expect(item.hitTestable(), findsOneWidget);
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  Future<void> submit(
    WidgetTester tester, {
    SshTerminalConfig selected = config,
    bool settle = true,
  }) async {
    Navigator.of(tester.element(find.byType(SshTerminalConnectDialog)))
        .pop(selected);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  Future<void> connect(
    WidgetTester tester, {
    SshTerminalConfig selected = config,
    bool settle = true,
  }) async {
    await tester.tap(find.byKey(const ValueKey('terminal-connect-ssh')));
    await tester.pumpAndSettle();
    await submit(tester, selected: selected, settle: settle);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find
            .descendant(
              of: find.byType(SshPortForwardingDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
  }

  testWidgets(
    'saved listeners start only after authentication and shell acceptance',
    (tester) async {
      await store.save(forwardingProfile(autoStart: true));
      final authenticated = service.nextAuthentication = Completer<void>();
      final shell = service.nextShell = Completer<void>();
      await mount(tester);
      await connect(tester, settle: false);
      expect(terminal.isConnecting, isTrue);
      expect(service.managers, isEmpty);
      expect(service.prompts.single, isNotNull);
      authenticated.complete();
      await tester.pump();
      expect(service.managers.single.requests, isEmpty);
      expect(terminal.isConnected, isFalse);
      shell.complete();
      await tester.pumpAndSettle();
      expect(terminal.isConnected, isTrue);
      expect(service.managers.single.requests.length, 1);
      await action(tester, 'Port forwarding');
      expect(
        tester
            .widget<SshPortForwardingDialog>(
              find.byType(SshPortForwardingDialog),
            )
            .profiles,
        isNotNull,
      );
      expect(find.text('Saved for this SSH route'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'Stop is respected until reconnect creates one new owned listener',
    (tester) async {
      await store.save(forwardingProfile(autoStart: true));
      await mount(tester);
      await connect(tester);
      final first = service.managers.single;
      await action(tester, 'Port forwarding');
      await tester.tap(find.text('Stop').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await mount(tester, visible: false);
      await mount(tester);
      await tester.pumpAndSettle();
      expect(first.requests.length, 1);
      expect(first.forwards, isEmpty);
      await action(tester, 'Reconnect SSH');
      await submit(tester);
      expect(service.managers.length, 2);
      expect(first.isClosed, isTrue);
      expect(service.managers.last.requests.length, 1);
      expect(service.managers.last.forwards.length, 1);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  for (final stage in ['authentication', 'shell']) {
    testWidgets('$stage failure never starts saved forwarding', (tester) async {
      await store.save(forwardingProfile(autoStart: true));
      service.failAuthentication = stage == 'authentication';
      service.failShell = stage == 'shell';
      await mount(tester);
      await connect(tester);
      expect(terminal.isConnected, isFalse);
      expect(terminal.status, TerminalSessionStatus.failed);
      expect(
        service.managers.every((manager) => manager.requests.isEmpty),
        isTrue,
      );
      expect(service.managers.every((manager) => manager.isClosed), isTrue);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

  testWidgets(
    'a changed SSH username does not inherit another route’s profiles',
    (tester) async {
      await store.save(forwardingProfile(autoStart: true));
      await mount(tester);
      await connect(
        tester,
        selected: const SshTerminalConfig(
          host: 'server.example',
          port: 22,
          username: 'bob',
        ),
      );
      expect(terminal.isConnected, isTrue);
      expect(service.managers.single.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('load failure shows a snackbar and leaves SSH usable', (
    tester,
  ) async {
    memory.raw = '{unsupported-data';
    await mount(tester);
    await connect(tester);
    expect(terminal.isConnected, isTrue);
    expect(service.managers.single.requests, isEmpty);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(
          'Saved forwarding could not be loaded. Existing data was preserved.',
        ),
      ),
      findsOneWidget,
    );
    expect(memory.raw, '{unsupported-data');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
    'disconnect during profile loading cancels automatic listener creation',
    (tester) async {
      await store.save(forwardingProfile(autoStart: true));
      final loaded = memory.pendingRead = Completer<void>();
      await mount(tester);
      await connect(tester);
      expect(terminal.isConnected, isTrue);
      final manager = service.managers.single;
      await terminal.disconnect();
      await tester.pump();
      loaded.complete();
      await tester.pumpAndSettle();
      expect(manager.requests, isEmpty);
      expect(manager.isClosed, isTrue);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'switching panel sessions cancels late starts without touching the new terminal',
    (tester) async {
      await store.save(forwardingProfile(autoStart: true));
      await store.save(
        forwardingProfile(id: 'web', targetPort: 80, autoStart: true),
      );
      final opened = service.nextForwardStart = Completer<void>();
      await mount(tester);
      await connect(tester);
      final manager = service.managers.single;
      expect(manager.requests.length, 1);
      final other = TerminalSession();
      await mount(tester, selected: other);
      opened.complete();
      await tester.pumpAndSettle();
      expect(manager.requests.length, 1);
      expect(manager.forwards, isEmpty);
      expect(manager.stops, ['listener-1']);
      expect(other.status, TerminalSessionStatus.idle);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
      other.dispose();
    },
  );

  testWidgets(
    'disconnect with profile editor open permits saved edits and deletion without new listeners',
    (tester) async {
      final profile = forwardingProfile(autoStart: true);
      await store.save(profile);
      await mount(tester);
      await connect(tester);
      final manager = service.managers.single;
      expect(manager.requests.length, 1);
      await action(tester, 'Port forwarding');
      final edit = find.byKey(
        ValueKey('ssh-forward-profile-edit-${profile.id}'),
      );
      await reveal(tester, edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.byType(AddSshPortForwardDialog), findsOneWidget);

      await terminal.disconnect();
      await tester.pumpAndSettle();
      expect(manager.isClosed, isTrue);
      expect(manager.forwards, isEmpty);
      expect(find.byType(AddSshPortForwardDialog), findsOneWidget);
      final name = find.byKey(const ValueKey('ssh-forward-profile-name'));
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Database renamed');
      final port = find.byKey(const ValueKey('ssh-forward-target-port'));
      await tester.ensureVisible(port);
      await tester.enterText(port, '5433');
      await tester.tap(find.byKey(const ValueKey('ssh-forward-start')));
      await tester.pumpAndSettle();
      final saved = (await store.load()).single;
      expect(saved.name, 'Database renamed');
      expect(saved.spec.targetPort, 5433);
      expect(find.byType(AddSshPortForwardDialog), findsNothing);
      await reveal(tester, find.text('Database renamed'));
      final start = find.byKey(
        ValueKey('ssh-forward-profile-start-${profile.id}'),
      );
      await reveal(tester, start);
      expect(tester.widget<TextButton>(start).onPressed, isNull);
      final delete = find.byKey(
        ValueKey('ssh-forward-profile-delete-${profile.id}'),
      );
      await reveal(tester, delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(await store.load(), isEmpty);
      expect(find.text('No saved forwarding profiles'), findsOneWidget);
      expect(manager.requests.length, 1);
      expect(manager.forwards, isEmpty);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'profile deletion can finish while the disconnected manager is closing',
    (tester) async {
      final profile = forwardingProfile(autoStart: true);
      await store.save(profile);
      await mount(tester);
      await connect(tester);
      final manager = service.managers.single;
      await action(tester, 'Port forwarding');
      final delete = find.byKey(
        ValueKey('ssh-forward-profile-delete-${profile.id}'),
      );
      await reveal(tester, delete);
      final stopped = manager.pendingStop = Completer<void>();
      await tester.tap(delete);
      await tester.pump();
      expect(manager.stops, ['listener-1']);
      await terminal.disconnect();
      await tester.pump();
      expect(manager.isClosed, isTrue);
      await tester.tap(find.text('Done'));
      await tester.pump();
      // Navigator.pop completes before the route's reverse transition. The
      // pending action must still be able to update its mounted dialog.
      stopped.complete();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(await store.load(), isEmpty);
      expect(find.byType(SshPortForwardingDialog), findsNothing);
      expect(manager.requests.length, 1);
      expect(manager.forwards, isEmpty);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
}

/// The real panel, TerminalSession and SSH TerminalConnection own this fixture.
/// Real host verification, authentication and socket forwarding have separate
/// transport tests; the gates here verify exactly when the UI may activate them.
class _ForwardingSshService extends SshTerminalService {
  _ForwardingSshService() : super(secureStorage: InMemorySecureStorage());
  final _sessions = <String, SshSession>{};
  final _outputs = <String, StreamController<String>>{};
  final _managers = <String, ProfileTestForwarding>{};
  final requests = <SshTerminalConfig>[];
  final prompts = <HostKeyPrompt?>[];
  final managers = <ProfileTestForwarding>[];
  Completer<void>? nextAuthentication;
  Completer<void>? nextShell;
  Completer<void>? nextForwardStart;
  bool failAuthentication = false;
  bool failShell = false;

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
    requests.add(
      SshTerminalConfig(
        host: host,
        port: port,
        username: username,
        password: password,
        gateway: gateway,
        jumpHosts: jumpHosts,
        forwardAgent: forwardAgent,
      ),
    );
    prompts.add(hostKeyPrompt);
    final gate = nextAuthentication;
    nextAuthentication = null;
    await gate?.future;
    if (failAuthentication) throw StateError('Fixture authentication refused');
    final id = 'session-${requests.length}';
    final now = DateTime.now();
    final session = SshSession(
      id: id,
      host: host,
      port: port,
      username: username,
      connected: true,
      startedAt: now,
      lastActivityAt: now,
    );
    _sessions[id] = session;
    final manager = ProfileTestForwarding()..pendingStart = nextForwardStart;
    nextForwardStart = null;
    _managers[id] = manager;
    managers.add(manager);
    return session;
  }

  @override
  Future<Stream<String>> startShell(
    String sessionId, {
    int width = 80,
    int height = 24,
    TmuxSessionOptions? tmux,
    ScreenSessionOptions? screen,
  }) async {
    final gate = nextShell;
    nextShell = null;
    await gate?.future;
    if (failShell) throw StateError('Fixture shell refused');
    final output = StreamController<String>(onCancel: () async {});
    _outputs[sessionId] = output;
    return output.stream;
  }

  @override
  bool canForwardPorts(String sessionId) => _sessions.containsKey(sessionId);
  @override
  SshPortForwarding forwarding(String sessionId) => _managers[sessionId]!;
  @override
  List<SshSession> getActiveSessions() => _sessions.values.toList();
  @override
  Future<void> resizeTerminal(String sessionId, int width, int height) async {}
  @override
  Future<void> writeToShell(String sessionId, String data) async {}
  @override
  Future<void> disconnect(String sessionId) async {
    if (_sessions.remove(sessionId) == null) return;
    await _managers[sessionId]?.close();
    final output = _outputs.remove(sessionId);
    if (output != null) unawaited(output.close());
  }

  @override
  Future<void> dispose() async {
    for (final id in _sessions.keys.toList()) {
      await disconnect(id);
    }
    for (final manager in managers) {
      manager.dispose();
    }
    await super.dispose();
  }
}
