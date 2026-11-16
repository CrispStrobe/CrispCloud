import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/models/terminal_arrangement.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_provider.dart';
import 'package:crisp_cloud/providers/terminal_workspace_recovery_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/services/terminal_workspace_recovery.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:crisp_cloud/widgets/terminal_tabs.dart';
import 'package:crisp_cloud/widgets/terminal_workspace_recovery_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String? raw;
  late int writes;
  late bool failWrites;
  late Future<String?> Function()? deferredRead;
  late TerminalWorkspaceRecovery store;
  late ProviderContainer container;
  late List<_Session> sessions;

  setUp(() {
    raw = null;
    writes = 0;
    failWrites = false;
    deferredRead = null;
    sessions = [];
    store = TerminalWorkspaceRecovery(
      read: () => deferredRead?.call() ?? Future.value(raw),
      write: (value) async {
        if (failWrites) throw StateError('disk unavailable');
        writes++;
        raw = value;
      },
    );
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        terminalWorkspaceRecoveryProvider.overrideWithValue(store),
      ],
    );
    container.read(showTerminalProvider.notifier).state = true;
    container.read(terminalHeightProvider.notifier).state = 480;
    container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
  });

  tearDown(() async {
    for (final session in sessions) {
      if (!session.disposed) session.dispose();
    }
    container.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  _Session createSession() {
    final session = _Session();
    sessions.add(session);
    return session;
  }

  Future<void> mount(
    WidgetTester tester, {
    TerminalSession? injected,
    Key? key,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: TerminalTabs(
              key: key,
              session: injected,
              sessionFactory: createSession,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  List<TerminalPanel> panels(WidgetTester tester) => tester
      .widgetList<TerminalPanel>(
        find.byType(TerminalPanel, skipOffstage: false),
      )
      .toList();

  Future<void> action(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('terminal-layout')));
    await tester.pumpAndSettle();
    final choice = find.text(label).last;
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String name) async {
    final target = find.byKey(ValueKey(name));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> checkpoint(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  TerminalWorkspaceRecoveryRecord record() =>
      TerminalWorkspaceRecoveryRecord.fromJson(
        jsonDecode(raw!) as Map<String, dynamic>,
      );

  void seed(TerminalArrangement snapshot, {bool relaunch = false}) {
    raw = jsonEncode(
      TerminalWorkspaceRecoveryRecord(
        enabled: true,
        relaunchLocalShells: relaunch,
        snapshot: snapshot,
        savedAt: DateTime.utc(2026, 11, 16),
      ).toJson(),
    );
  }

  TerminalArrangement savedWorkspace() => TerminalArrangement(
    name: 'Recovered workspace',
    tabs: [
      TerminalArrangementTab(name: 'Local work'),
      TerminalArrangementTab(
        name: 'Remote tmux',
        paneState: TerminalPaneState(
          fontSize: 19,
          sshConfig: const SshTerminalConfig(
            host: 'build.example',
            port: 22,
            username: 'alice',
            password: 'DO-NOT-PERSIST',
            tmux: TmuxSessionOptions(
              sessionName: 'compile',
              mode: TmuxSessionMode.attach,
              controlMode: true,
            ),
            jumpHosts: [
              SshJumpHost(
                host: 'bastion.example',
                username: 'jump',
                password: 'JUMP-SECRET',
              ),
            ],
          ),
        ),
      ),
      TerminalArrangementTab(name: 'Hidden tab'),
    ],
    layout: TerminalPaneSplit(
      axis: TerminalSplitAxis.horizontal,
      fraction: 0.62,
      first: TerminalPaneLeaf(0),
      second: TerminalPaneLeaf(1),
    ),
    activeIndex: 1,
  );

  testWidgets(
    'disabled by default and enabling captures the current workspace',
    (tester) async {
      await mount(tester);
      await tester.pumpAndSettle();
      expect(raw, isNull);
      await action(tester, 'Split side by side');
      await checkpoint(tester);
      expect(writes, 0);
      await action(tester, 'Session recovery');
      await tapKey(tester, 'terminal-recovery-enabled');
      await tapKey(tester, 'terminal-recovery-save');
      expect(record().enabled, isTrue);
      expect(record().relaunchLocalShells, isFalse);
      expect(record().snapshot!.tabs, hasLength(2));
      expect(record().snapshot!.layout.leafIds, [0, 1]);
      expect(panels(tester), hasLength(2));
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'recovery restores the complete workspace before any shell starts',
    (tester) async {
      final original = savedWorkspace();
      seed(original);
      await mount(tester);
      await tester.pumpAndSettle();
      final restored = panels(tester);
      expect(restored, hasLength(3));
      expect(restored[1].active, isTrue);
      expect(restored[1].initialPaneState!.fontSize, 19);
      expect(
        restored[1].initialPaneState!.sshConfig!.tmux!.controlMode,
        isTrue,
      );
      expect(
        restored[1].initialPaneState!.sshConfig!.jumpHosts.single.host,
        'bastion.example',
      );
      expect(restored.every((panel) => !panel.autoStart), isTrue);
      expect(sessions.every((session) => session.starts == 0), isTrue);
      expect(
        restored.every((panel) => !panel.session!.acceptsDirectInput),
        isTrue,
      );
      expect(record().snapshot!.toJson(), original.toJson());
      expect(writes, 0);
      expect(raw, isNot(contains('DO-NOT-PERSIST')));
      expect(raw, isNot(contains('JUMP-SECRET')));
      expect(
        find.byKey(const ValueKey('terminal-split-divider')),
        findsOneWidget,
      );
      expect(find.text('Remote tmux'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('separate relaunch choice opens local shells but never SSH', (
    tester,
  ) async {
    seed(savedWorkspace(), relaunch: true);
    await mount(tester);
    await tester.pumpAndSettle();
    final restored = panels(tester);
    expect(restored.map((panel) => panel.autoStart), [true, false, true]);
    expect((restored[0].session! as _Session).starts, 1);
    expect((restored[2].session! as _Session).starts, 1);
    expect((restored[1].session! as _Session).starts, 0);
    expect(restored[1].session!.canDisconnect, isFalse);
    expect(sessions.first.disposed, isTrue);
    expect(sessions.first.starts, 0);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('recovered SSH still opens the ordinary authentication dialog', (
    tester,
  ) async {
    seed(savedWorkspace());
    await mount(tester);
    await tester.pumpAndSettle();
    final remote = find.byWidgetPredicate(
      (widget) => widget is TerminalPanel && widget.active,
    );
    await tester.tap(
      find.descendant(
        of: remote,
        matching: find.byKey(const ValueKey('terminal-actions')),
      ),
    );
    await tester.pumpAndSettle();
    final reconnect = find.text('Reconnect SSH').last;
    await tester.ensureVisible(reconnect);
    await tester.tap(reconnect);
    await tester.pumpAndSettle();
    expect(find.byType(SshTerminalConnectDialog), findsOneWidget);
    final dialog = tester.widget<SshTerminalConnectDialog>(
      find.byType(SshTerminalConnectDialog),
    );
    expect(dialog.initialConfig!.host, 'build.example');
    expect(dialog.initialConfig!.password, isEmpty);
    expect(dialog.initialConfig!.jumpHosts.single.password, isEmpty);
    expect(sessions.every((session) => session.starts == 0), isTrue);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets(
    'changes autosave but output and focus notifications do not write',
    (tester) async {
      seed(savedWorkspace());
      await mount(tester);
      await tester.pumpAndSettle();
      await action(tester, 'Rename terminal');
      await tester.enterText(
        find.byKey(const ValueKey('terminal-tab-name')),
        'Deploy',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      await action(tester, 'Move terminal left');
      await checkpoint(tester);
      expect(record().snapshot!.tabs.first.name, 'Deploy');
      expect(record().snapshot!.activeIndex, 0);
      final savedWrites = writes;
      for (final panel in panels(tester)) {
        panel.session!.terminal.write('never save output\r\n');
        (panel.session! as _Session).signal();
      }
      await checkpoint(tester);
      expect(writes, savedWrites);
      expect(raw, isNot(contains('never save output')));
      await unmount(tester);
    },
  );

  testWidgets('instant remount receives the final pre-debounce checkpoint', (
    tester,
  ) async {
    seed(savedWorkspace());
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('terminal-new-tab')));
    await tester.pump();
    expect(panels(tester), hasLength(4));
    // A different key destroys and recreates the owner in the same frame.
    await mount(tester, key: const ValueKey('new-owner'));
    await tester.pumpAndSettle();
    expect(panels(tester), hasLength(4));
    expect(record().snapshot!.tabs, hasLength(4));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('background lifecycle flushes pending changes', (tester) async {
    seed(savedWorkspace());
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('terminal-new-tab')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(record().snapshot!.tabs, hasLength(4));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await unmount(tester);
  });

  testWidgets(
    'forget fences pending saves and leaves current terminals intact',
    (tester) async {
      seed(savedWorkspace());
      await mount(tester);
      await tester.pumpAndSettle();
      final originals = panels(tester).map((panel) => panel.session).toList();
      await action(tester, 'Session recovery');
      await tapKey(tester, 'terminal-recovery-forget');
      await tapKey(tester, 'terminal-recovery-confirm-forget');
      expect(record().enabled, isFalse);
      expect(record().snapshot, isNull);
      expect(panels(tester).map((panel) => panel.session), originals);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'terminal-new-tab');
      await checkpoint(tester);
      await unmount(tester);
      expect(record().snapshot, isNull);
      await mount(tester);
      await tester.pumpAndSettle();
      expect(panels(tester), hasLength(1));
      await unmount(tester);
    },
  );

  testWidgets('corrupt settings stay intact until explicit forget', (
    tester,
  ) async {
    raw = '{"version":999,"future":"preserve me"}';
    final corrupt = raw;
    await mount(tester);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('terminal-recovery-status')),
      findsOneWidget,
    );
    expect(raw, corrupt);
    expect(panels(tester), hasLength(1));
    await action(tester, 'Session recovery');
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('terminal-recovery-save')),
          )
          .onPressed,
      isNull,
    );
    await tapKey(tester, 'terminal-recovery-forget');
    await tapKey(tester, 'terminal-recovery-confirm-forget');
    expect(record().snapshot, isNull);
    expect(record().enabled, isFalse);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('terminal-recovery-status')),
      findsNothing,
    );
    await unmount(tester);
  });

  testWidgets('save failure pauses recovery without closing healthy sessions', (
    tester,
  ) async {
    seed(savedWorkspace(), relaunch: true);
    await mount(tester);
    await tester.pumpAndSettle();
    final live = panels(tester).first.session!;
    expect(live.isConnected, isTrue);
    failWrites = true;
    await tapKey(tester, 'terminal-new-tab');
    await checkpoint(tester);
    expect(
      find.byKey(const ValueKey('terminal-recovery-status')),
      findsOneWidget,
    );
    expect(live.isConnected, isTrue);
    expect(record().snapshot!.tabs, hasLength(3));
    failWrites = false;
    await action(tester, 'Session recovery');
    await tapKey(tester, 'terminal-recovery-retry');
    expect(record().snapshot!.tabs, hasLength(4));
    expect(live.isConnected, isTrue);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('delayed startup cannot overwrite a caller-owned replacement', (
    tester,
  ) async {
    seed(savedWorkspace());
    final pending = Completer<String?>();
    deferredRead = () => pending.future;
    await mount(tester);
    expect(find.text('Loading saved workspace…'), findsOneWidget);
    expect(panels(tester), isEmpty);
    final injected = createSession();
    await mount(tester, injected: injected);
    pending.complete(raw);
    deferredRead = null;
    await tester.pumpAndSettle();
    expect(panels(tester).single.session, same(injected));
    expect(writes, 0);
    await unmount(tester);
    expect(injected.disposed, isFalse);
  });

  testWidgets(
    'superseded loading owner opens normally without stale restoration',
    (tester) async {
      seed(savedWorkspace());
      final pending = Completer<String?>();
      deferredRead = () => pending.future;
      await mount(tester);
      final nextOwner = store.acquireLease();
      pending.complete(raw);
      deferredRead = null;
      await tester.pumpAndSettle();
      expect(find.text('Loading saved workspace…'), findsNothing);
      expect(panels(tester), hasLength(1));
      expect(
        find.byTooltip('Another terminal workspace is managing recovery.'),
        findsOneWidget,
      );
      expect(writes, 0);
      nextOwner.close();
      await unmount(tester);
    },
  );

  testWidgets('late read after timeout never restores over newly opened tabs', (
    tester,
  ) async {
    seed(savedWorkspace());
    final pending = Completer<String?>();
    deferredRead = () => pending.future;
    await mount(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(panels(tester), hasLength(1));
    await tapKey(tester, 'terminal-new-tab');
    pending.complete(raw);
    deferredRead = null;
    await tester.pumpAndSettle();
    expect(panels(tester), hasLength(2));
    expect(find.text('Remote tmux'), findsNothing);
    expect(writes, 0);
    await unmount(tester);
  });

  testWidgets('old settings dialog cannot configure a replacement workspace', (
    tester,
  ) async {
    seed(savedWorkspace());
    await mount(tester);
    await tester.pumpAndSettle();
    await action(tester, 'Session recovery');
    final dialog = tester.widget<TerminalWorkspaceRecoveryDialog>(
      find.byType(TerminalWorkspaceRecoveryDialog),
    );
    final original = raw;
    // Capture callback authority, then replace the owner and reenter owned mode.
    await mount(tester, injected: createSession());
    await mount(tester);
    await tester.pumpAndSettle();
    await expectLater(
      Future.sync(() => dialog.onForget()),
      throwsA(isA<TerminalWorkspaceRecoveryLeaseExpired>()),
    );
    expect(raw, original);
    await unmount(tester);
  });

  testWidgets('caller-owned terminal never reads or overwrites recovery', (
    tester,
  ) async {
    seed(savedWorkspace());
    final original = raw;
    deferredRead = () async => throw StateError('must not read');
    final caller = createSession();
    await mount(tester, injected: caller);
    await tester.pumpAndSettle();
    expect(panels(tester).single.session, same(caller));
    await tapKey(tester, 'terminal-new-tab');
    await checkpoint(tester);
    await unmount(tester);
    expect(raw, original);
    expect(writes, 0);
    expect(caller.disposed, isFalse);
  });
}

class _Session extends TerminalSession {
  int starts = 0;
  bool disposed = false;

  @override
  Future<void> connect(
    TerminalConnectionFactory open, {
    required TerminalSessionKind kind,
    String? label,
    TerminalCloseable? openingCleanup,
  }) {
    starts++;
    return super.connect(
      (_, __) async => _Connection(),
      kind: kind,
      label: label,
      openingCleanup: openingCleanup,
    );
  }

  void signal() => notifyListeners();

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Connection implements TerminalConnection {
  final _output = StreamController<String>();
  final _exit = Completer<int?>();

  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => _output.stream;
  @override
  Future<int?> get exitCode => _exit.future;
  @override
  Future<void> write(String data) async {}
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    if (!_exit.isCompleted) _exit.complete(0);
    if (!_output.isClosed) await _output.close();
  }
}
