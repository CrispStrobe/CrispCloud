import 'dart:async';

import 'package:crisp_cloud/services/terminal_broadcast.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_broadcast_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<TerminalSession> sessions;
  late List<TerminalBroadcastTarget> candidates;
  List<TerminalBroadcastTarget>? selected;

  setUp(() async {
    selected = null;
    sessions = [TerminalSession(), TerminalSession(), TerminalSession()];
    for (final session in sessions) {
      await session.connect(
        (_, __) async => _Connection(),
        kind: TerminalSessionKind.ssh,
      );
    }
    candidates = [
      for (var i = 0; i < sessions.length; i++)
        TerminalBroadcastTarget(
          id: i,
          label: '${i + 1}. alice@host-$i',
          session: sessions[i],
        ),
    ];
  });

  tearDown(() async {
    for (final session in sessions) {
      session.dispose();
    }
    await Future<void>.delayed(Duration.zero);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showDialog<List<TerminalBroadcastTarget>>(
                  context: context,
                  builder: (_) => TerminalBroadcastDialog(candidates: candidates),
                );
              },
              child: const Text('Choose group'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose group'));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, int id) async {
    final checkbox = find.byKey(ValueKey('terminal-broadcast-target-$id'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
  }

  FilledButton start(WidgetTester tester) => tester.widget<FilledButton>(
    find.byKey(const ValueKey('terminal-start-broadcast')),
  );

  testWidgets('requires explicit selection of two exact connected destinations', (
    tester,
  ) async {
    await mount(tester);
    expect(start(tester).onPressed, isNull);
    expect(find.text('Typed keys and pasted text will be sent to every selected terminal.'), findsOneWidget);
    await select(tester, 0);
    expect(start(tester).onPressed, isNull);
    await select(tester, 1);
    expect(start(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('terminal-start-broadcast')));
    await tester.pumpAndSettle();
    expect(selected!.map((target) => target.id), [0, 1]);
    expect(selected!.first.connectionIdentity, same(candidates.first.connectionIdentity));
    expect(sessions.every((session) => session.onUserInput == null), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed connection is deselected and cannot be silently replaced', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, 0);
    await select(tester, 1);
    await sessions[1].disconnect();
    await tester.pumpAndSettle();
    expect(start(tester).onPressed, isNull);
    expect(find.text('Connections changed. Choose the broadcast group again.'), findsOneWidget);
    await sessions[1].connect((_, __) async => _Connection(), kind: TerminalSessionKind.ssh);
    await tester.pumpAndSettle();
    final changed = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('terminal-broadcast-target-1')),
    );
    expect(changed.value, isFalse);
    expect(changed.onChanged, isNull);
    await select(tester, 2);
    await tester.tap(find.byKey(const ValueKey('terminal-start-broadcast')));
    await tester.pumpAndSettle();
    expect(selected!.map((target) => target.id), [0, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel leaves connections and existing observers intact', (
    tester,
  ) async {
    void observer(_) {}
    sessions.first.onUserInput = observer;
    await mount(tester);
    await select(tester, 0);
    await select(tester, 1);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(sessions.every((session) => session.isConnected), isTrue);
    expect(sessions.first.onUserInput, same(observer));
    expect(tester.takeException(), isNull);
  });
}

class _Connection implements TerminalConnection {
  final _output = StreamController<String>(onCancel: () async {});
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
    if (!_output.isClosed) unawaited(_output.close());
  }
}
