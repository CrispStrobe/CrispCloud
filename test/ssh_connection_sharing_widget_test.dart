import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/ssh_connection_sharing_strings.dart';
import 'package:crisp_cloud/models/terminal_arrangement.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:crisp_cloud/widgets/terminal_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm2/xterm.dart';

void main() {
  late ProviderContainer container;
  late List<TerminalSession> sessions;
  late _Route route;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    route = _Route();
    sessions = [TerminalSession()];
    await sessions.first.connect(
      (_, _) async => _Connection(route),
      kind: TerminalSessionKind.ssh,
      label: 'alice@example.test · tmux: work',
    );
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
      ],
    );
    container.read(showTerminalProvider.notifier).state = true;
    container.read(terminalHeightProvider.notifier).state = 600;
    container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
  });

  tearDown(() async {
    for (final session in sessions) {
      session.dispose();
    }
    container.dispose();
    for (final connection in route.connections) {
      await connection.close();
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1100, 1000),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: TerminalTabs(
              session: sessions.first,
              sessionFactory: () {
                final session = TerminalSession();
                sessions.add(session);
                return session;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The panel publishes this same sanitized model after a successful SSH
    // form connection. Exercise the workspace boundary without another login.
    tester
        .widget<TerminalPanel>(find.byType(TerminalPanel))
        .onPaneStateChanged!(
      TerminalPaneState(
        fontSize: 19,
        sshConfig: const SshTerminalConfig(
          host: 'example.test',
          port: 2222,
          username: 'alice',
          password: 'not retained',
          forwardAgent: true,
          tmux: TmuxSessionOptions(sessionName: 'work', controlMode: true),
        ),
      ),
    );
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('terminal-layout')));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await openMenu(tester);
    final item = find.text(label).last;
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('new SSH shell copies presentation and plain destination only', (
    tester,
  ) async {
    await mount(tester);
    final originalIdentity = sessions.first.connectionIdentity;
    await choose(tester, 'New SSH shell');
    expect(sessions, hasLength(2));
    expect(sessions.every((session) => session.isConnected), isTrue);
    expect(route.connections, hasLength(2));
    expect(sessions.first.connectionIdentity, same(originalIdentity));
    expect(sessions.last.connectionIdentity, isNot(same(originalIdentity)));
    expect(find.byType(SshTerminalConnectDialog), findsNothing);
    expect(sessions.last.label, 'alice@example.test');

    final panel = tester.widget<TerminalPanel>(find.byType(TerminalPanel));
    final state = panel.initialPaneState!;
    expect(panel.autoStart, isFalse);
    expect(panel.sharedConnection, isTrue);
    expect(state.fontSize, 19);
    expect(state.sshConfig!.host, 'example.test');
    expect(state.sshConfig!.port, 2222);
    expect(state.sshConfig!.password, isEmpty);
    expect(state.sshConfig!.forwardAgent, isTrue);
    expect(state.sshConfig!.tmux, isNull);
    expect(state.sshConfig!.screen, isNull);
    expect(
      find.byKey(const ValueKey('terminal-shared-connection')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
    await tester.pump();
    expect(route.connections.first.writes, isEmpty);
    expect(route.connections.last.writes, ['x']);

    await tester.tap(find.byKey(const ValueKey('terminal-close-tab-1')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Other terminals keep the SSH connection'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Close terminal'));
    await tester.pumpAndSettle();
    expect(route.connections.first.closed, isTrue);
    expect(route.connections.last.closed, isFalse);
    expect(sessions.last.isConnected, isTrue);
    expect(
      find.byKey(const ValueKey('terminal-shared-connection')),
      findsNothing,
    );
    await unmount(tester);
    expect(route.connections.last.closed, isTrue);
  });

  for (final horizontal in [true, false]) {
    testWidgets(
      'explicit SSH split opens an independent ${horizontal ? 'side' : 'lower'} pane',
      (tester) async {
        await mount(tester);
        await choose(
          tester,
          horizontal ? 'Split SSH side by side' : 'Split SSH top and bottom',
        );
        expect(find.byType(TerminalView), findsNWidgets(2));
        expect(sessions.every((session) => session.isConnected), isTrue);
        final first = tester.getRect(
          find.byKey(const ValueKey('terminal-pane-1')),
        );
        final second = tester.getRect(
          find.byKey(const ValueKey('terminal-pane-2')),
        );
        if (horizontal) {
          expect(first.right, lessThan(second.left));
          expect(first.top, second.top);
        } else {
          expect(first.bottom, lessThan(second.top));
          expect(first.left, second.left);
        }
        route.connections.first.controller.add('first pane');
        route.connections.last.controller.add('second pane');
        await tester.pump();
        expect(
          sessions.first.terminal.buffer.getText(),
          contains('first pane'),
        );
        expect(
          sessions.last.terminal.buffer.getText(),
          contains('second pane'),
        );
        expect(
          sessions.last.terminal.buffer.getText(),
          isNot(contains('first pane')),
        );
        await unmount(tester);
      },
    );
  }

  testWidgets('ordinary new tab does not acquire SSH sharing authority', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('terminal-new-tab')));
    await tester.pumpAndSettle();
    expect(sessions, hasLength(2));
    expect(sessions.last.status, TerminalSessionStatus.idle);
    expect(route.connections, hasLength(1));
    await openMenu(tester);
    expect(find.text('New SSH shell'), findsNothing);
    await tester.tapAt(const Offset(10, 900));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('menu capability does not follow a reconnected source', (
    tester,
  ) async {
    await mount(tester);
    await openMenu(tester);
    await tester.runAsync(
      () => sessions.first.connect(
        (_, _) async => _Connection(route),
        kind: TerminalSessionKind.ssh,
        label: 'replacement@example.test',
      ),
    );
    await tester.pump();
    await tester.tap(find.text('New SSH shell'));
    await tester.pumpAndSettle();
    expect(sessions, hasLength(2));
    expect(sessions.last.status, TerminalSessionStatus.failed);
    expect(route.connections, hasLength(2));
    expect(route.connections.last.writes, isEmpty);
    expect(sessions.first.isConnected, isTrue);
    await unmount(tester);
  });

  testWidgets('pending sibling cancellation keeps the original route lease', (
    tester,
  ) async {
    await mount(tester);
    route.openGate = Completer<void>();
    await openMenu(tester);
    await tester.tap(find.text('New SSH shell'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(sessions.last.isConnecting, isTrue);
    expect(route.connections, hasLength(2));
    await sessions.last.disconnect();
    await tester.pumpAndSettle();
    expect(route.openGate!.isCompleted, isFalse);
    expect(route.connections.first.closed, isFalse);
    expect(route.connections.last.closed, isTrue);
    expect(sessions.first.isConnected, isTrue);
    expect(sessions.last.status, TerminalSessionStatus.disconnected);
    expect(sessions.last.canDisconnect, isFalse);
    route.openGate!.complete();
    await unmount(tester);
  });

  testWidgets('all eight translations retain shared lifetime and count', (
    tester,
  ) async {
    const messages = [
      'New SSH shell',
      'Split SSH side by side',
      'Split SSH top and bottom',
      'Shared SSH connection',
      'This SSH connection is shared by {count} terminals. Port forwards and permitted agent access stay active until the last terminal closes.',
      'Closing releases this terminal. Other terminals keep the SSH connection, port forwards and permitted agent access until the last terminal closes.',
    ];
    for (final locale in AppLocalizations.supportedLocales) {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      for (final message in messages) {
        final translated = context.sshSharingTr(message);
        if (locale.languageCode != 'en') expect(translated, isNot(message));
        if (message.contains('{count}')) {
          expect(translated, contains('{count}'));
        }
      }
    }
  });
}

class _Route {
  final connections = <_Connection>[];
  Completer<void>? openGate;
}

class _Connection implements TerminalConnection, TerminalConnectionSharing {
  _Connection(this.route) {
    route.connections.add(this);
  }

  final _Route route;
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
  bool get canOpenSibling => !closed && sharedSessionCount < 8;
  @override
  int get sharedSessionCount =>
      route.connections.where((connection) => !connection.closed).length;
  @override
  Future<TerminalConnection> openSibling(
    int columns,
    int rows, {
    TerminalConnectionCancellation? cancellation,
  }) async {
    final sibling = _Connection(route);
    final cancelled = Completer<void>();
    Future<void> release() async {
      await sibling.close();
      if (!cancelled.isCompleted) cancelled.complete();
    }

    await cancellation?.register(release);
    try {
      if (route.openGate != null) {
        await Future.any([
          route.openGate!.future,
          cancelled.future.then<void>((_) => throw StateError('cancelled')),
        ]);
      }
      if (cancellation?.isCancelled == true) throw StateError('cancelled');
      return sibling;
    } finally {
      cancellation?.unregister(release);
    }
  }

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
