import 'dart:async';

import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/terminal_arrangement.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_arrangements_provider.dart';
import 'package:crisp_cloud/providers/terminal_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/terminal_arrangements.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_arrangements_dialog.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:crisp_cloud/widgets/terminal_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late TerminalArrangements store;
  late List<_TrackedSession> sessions;
  late String? raw;
  late _TrackedSession first;

  setUp(() {
    raw = null;
    sessions = [];
    first = _TrackedSession();
    sessions.add(first);
    store = TerminalArrangements(
      read: () async => raw,
      write: (value) async => raw = value,
    );
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        terminalArrangementsProvider.overrideWithValue(store),
      ],
    );
    container.read(showTerminalProvider.notifier).state = true;
    container.read(terminalHeightProvider.notifier).state = 480;
    container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
  });

  tearDown(() async {
    for (final session in sessions) {
      if (session.disposals == 0) session.dispose();
    }
    container.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  Future<void> pumpUi(WidgetTester tester) async {
    if (sessions.any((session) => session.isConnecting)) {
      // This fixture deliberately keeps an opener pending. Its indeterminate
      // progress indicator cannot settle; finish finite route animations only.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: TerminalTabs(
              session: first,
              sessionFactory: () {
                final session = _TrackedSession();
                sessions.add(session);
                return session;
              },
            ),
          ),
        ),
      ),
    );
    await pumpUi(tester);
  }

  Future<void> layout(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('terminal-layout')));
    await pumpUi(tester);
    final item = find.text(label).last;
    await tester.ensureVisible(item);
    await tester.tap(item);
    await pumpUi(tester);
  }

  Future<void> chooseSaved(WidgetTester tester, String name) async {
    await layout(tester, 'Saved arrangements');
    await tester.tap(find.byKey(ValueKey('terminal-arrangement-$name')));
    await pumpUi(tester);
  }

  Future<void> restore(WidgetTester tester, String name) async {
    await chooseSaved(tester, name);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await pumpUi(tester);
  }

  Future<void> save(WidgetTester tester, String name) async {
    await layout(tester, 'Save arrangement');
    await tester.enterText(
      find.byKey(const ValueKey('terminal-arrangement-name')),
      name,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpUi(tester);
  }

  Iterable<TerminalPanel> panels(WidgetTester tester) =>
      tester.widgetList<TerminalPanel>(
        find.byType(TerminalPanel, skipOffstage: false),
      );

  Future<void> paneAction(WidgetTester tester, String label) async {
    final active = find.byWidgetPredicate(
      (widget) => widget is TerminalPanel && widget.active,
    );
    await tester.tap(
      find.descendant(
        of: active,
        matching: find.byKey(const ValueKey('terminal-actions')),
      ),
    );
    await pumpUi(tester);
    final item = find.text(label).last;
    await tester.ensureVisible(item);
    await tester.tap(item);
    await pumpUi(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  TerminalArrangement remoteArrangement() => TerminalArrangement(
    name: 'Remote work',
    tabs: [
      TerminalArrangementTab(
        name: 'Remote',
        paneState: TerminalPaneState(
          fontSize: 21,
          sshConfig: const SshTerminalConfig(
            host: 'ssh.example',
            port: 2222,
            username: 'alice',
            password: 'never-persist-me',
            screen: ScreenSessionOptions(
              sessionName: '142.work',
              mode: ScreenSessionMode.attach,
            ),
          ),
        ),
      ),
      TerminalArrangementTab(name: 'Local'),
    ],
    firstIndex: 1,
    secondIndex: 0,
    activeIndex: 0,
    splitAxis: TerminalSplitAxis.vertical,
    splitFraction: 0.6,
  );

  testWidgets(
    'save and restore preserve order, names, zoom and resized split',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('terminal-new-tab')));
      await pumpUi(tester);
      await layout(tester, 'Split side by side');
      await layout(tester, 'Rename terminal');
      await tester.enterText(
        find.byKey(const ValueKey('terminal-tab-name')),
        'Build pane',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await pumpUi(tester);
      await paneAction(tester, 'Increase font size');
      await paneAction(tester, 'Increase font size');
      await layout(tester, 'Move terminal left');
      await tester.drag(
        find.byKey(const ValueKey('terminal-split-divider')),
        const Offset(100, 0),
      );
      await pumpUi(tester);
      await save(tester, 'Daily');
      final captured = (await store.load()).single;
      expect(captured.tabs, hasLength(3));
      expect(captured.tabs[1].name, 'Build pane');
      expect(captured.tabs[1].paneState.fontSize, 15);
      expect(captured.firstIndex, 2);
      expect(captured.secondIndex, 1);
      expect(captured.activeIndex, 1);
      expect(captured.splitFraction, greaterThan(0.5));
      expect(
        captured.tabs.every((tab) => tab.paneState.sshConfig == null),
        isTrue,
      );

      await unmount(tester);
      await mount(tester);
      await restore(tester, 'Daily');
      final restored = panels(tester).toList();
      expect(restored, hasLength(3));
      expect(restored.every((panel) => !panel.autoStart), isTrue);
      expect(
        restored.every(
          (panel) => panel.session!.status == TerminalSessionStatus.idle,
        ),
        isTrue,
      );
      expect(restored[1].initialPaneState!.fontSize, 15);
      expect(restored[1].active, isTrue);
      expect(find.text('Build pane'), findsOneWidget);
      await save(tester, 'Restored');
      final again = (await store.load()).singleWhere(
        (item) => item.name == 'Restored',
      );
      expect(again.toJson()..remove('name'), captured.toJson()..remove('name'));
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('SSH arrangements stay disconnected and reconnect asks again', (
    tester,
  ) async {
    await store.save(remoteArrangement());
    expect(raw, isNot(contains('never-persist-me')));
    await mount(tester);
    await restore(tester, 'Remote work');
    final restored = panels(tester).toList();
    expect(restored, hasLength(2));
    expect(
      restored.every(
        (panel) => panel.session!.status == TerminalSessionStatus.idle,
      ),
      isTrue,
    );
    expect(restored.every((panel) => !panel.autoStart), isTrue);
    expect(restored.first.initialPaneState!.fontSize, 21);
    expect(restored.first.initialPaneState!.sshConfig!.host, 'ssh.example');
    expect(restored.first.initialPaneState!.sshConfig!.password, isEmpty);
    expect(restored.last.initialPaneState!.sshConfig, isNull);
    await paneAction(tester, 'Reconnect SSH');
    final dialog = tester.widget<SshTerminalConnectDialog>(
      find.byType(SshTerminalConnectDialog),
    );
    expect(dialog.initialConfig!.host, 'ssh.example');
    expect(dialog.initialConfig!.port, 2222);
    expect(dialog.initialConfig!.password, isEmpty);
    expect(dialog.initialConfig!.screen!.sessionName, '142.work');
    await tester.tap(find.text('Cancel').last);
    await pumpUi(tester);
    expect(
      restored.every(
        (panel) => panel.session!.status == TerminalSessionStatus.idle,
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('cancel keeps live sessions and every existing screen', (
    tester,
  ) async {
    final connection = _Connection();
    await first.connect(
      (_, __) async => connection,
      kind: TerminalSessionKind.ssh,
    );
    await store.save(remoteArrangement());
    await mount(tester);
    first.terminal.write('valuable existing output');
    await chooseSaved(tester, 'Remote work');
    expect(find.text('Replace current terminals?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await pumpUi(tester);
    expect(connection.closes, 0);
    expect(first.isConnected, isTrue);
    expect(
      first.terminal.buffer.getText(),
      contains('valuable existing output'),
    );
    expect(panels(tester).single.session, same(first));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('cleanup failure retains every tab and permits a later retry', (
    tester,
  ) async {
    final connection = _Connection()..failures = 1;
    await first.connect(
      (_, __) async => connection,
      kind: TerminalSessionKind.ssh,
    );
    await store.save(remoteArrangement());
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('terminal-new-tab')));
    await pumpUi(tester);
    first.terminal.write('keep first');
    sessions[1].terminal.write('keep second');
    await restore(tester, 'Remote work');
    expect(connection.closes, 1);
    expect(first.canDisconnect, isTrue);
    expect(panels(tester).map((panel) => panel.session), [first, sessions[1]]);
    expect(sessions.every((session) => session.disposals == 0), isTrue);
    expect(first.terminal.buffer.getText(), contains('keep first'));
    expect(sessions[1].terminal.buffer.getText(), contains('keep second'));
    expect(
      find.text('Could not restore arrangement. All existing tabs were kept.'),
      findsOneWidget,
    );
    await restore(tester, 'Remote work');
    expect(connection.closes, 2);
    expect(first.disposals, 0); // The injected session stays caller-owned.
    expect(sessions[1].disposals, 1);
    expect(
      panels(
        tester,
      ).every((panel) => panel.session!.status == TerminalSessionStatus.idle),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('pending connection is kept until its opener settles', (
    tester,
  ) async {
    final opening = Completer<TerminalConnection>();
    final connection = _Connection();
    final pending = first.connect(
      (_, __) => opening.future,
      kind: TerminalSessionKind.ssh,
    );
    await store.save(remoteArrangement());
    await mount(tester);
    expect(first.isConnecting, isTrue);
    await restore(tester, 'Remote work');
    expect(panels(tester).single.session, same(first));
    expect(first.isConnecting, isTrue);
    expect(first.disposals, 0);
    opening.complete(connection);
    await pumpUi(tester);
    await pending;
    expect(first.isConnected, isTrue);
    expect(connection.closes, 0);
    await unmount(tester);
  });

  testWidgets('failed load cannot save over an unreadable store', (
    tester,
  ) async {
    raw = '{"version":99,"arrangements":[]}';
    await mount(tester);
    await layout(tester, 'Save arrangement');
    expect(find.text('Could not load arrangements.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(raw, '{"version":99,"arrangements":[]}');
    await tester.tap(find.text('Cancel'));
    await pumpUi(tester);
    await layout(tester, 'Saved arrangements');
    expect(find.byType(TerminalArrangementsDialog), findsOneWidget);
    expect(find.text('Could not load arrangements.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await pumpUi(tester);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('delete confirms without affecting the current workspace', (
    tester,
  ) async {
    await store.save(remoteArrangement());
    await mount(tester);
    await layout(tester, 'Saved arrangements');
    await tester.tap(find.byTooltip('Delete'));
    await pumpUi(tester);
    expect(find.text('Delete arrangement?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await pumpUi(tester);
    expect(await store.load(), hasLength(1));
    await tester.tap(find.byTooltip('Delete'));
    await pumpUi(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await pumpUi(tester);
    expect(await store.load(), isEmpty);
    expect(find.text('No saved arrangements'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await pumpUi(tester);
    expect(panels(tester).single.session, same(first));
    expect(first.status, TerminalSessionStatus.idle);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}

class _TrackedSession extends TerminalSession {
  int disposals = 0;

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _Connection implements TerminalConnection {
  final _output = StreamController<String>(onCancel: () async {});
  final _exit = Completer<int?>();
  int closes = 0;
  int failures = 0;

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
    closes++;
    if (failures > 0) {
      failures--;
      throw StateError('Fixture cleanup failed');
    }
    if (!_exit.isCompleted) _exit.complete(0);
    if (!_output.isClosed) unawaited(_output.close());
  }
}
