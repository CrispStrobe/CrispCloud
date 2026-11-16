import 'dart:async';

import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/services/tmux_control_client.dart';
import 'package:flutter/foundation.dart';

/// A view-only fixture. Protocol behavior is covered by the control-client
/// tests; these real TerminalSessions record the exact input emitted by UI.
class TmuxWorkspaceFixture extends ChangeNotifier implements TmuxControlClient {
  @override
  final windows = <TmuxControlWindow>[
    const TmuxControlWindow(
      id: '@1',
      index: 0,
      name: 'shell',
      width: 80,
      height: 24,
      paneIds: ['%1', '%2'],
      activePaneId: '%1',
    ),
    const TmuxControlWindow(
      id: '@2',
      index: 1,
      name: 'build server',
      width: 80,
      height: 24,
      paneIds: ['%3'],
      activePaneId: '%3',
    ),
  ];
  @override
  final panes = <String, TmuxControlPane>{};
  final connections = <String, TmuxWorkspaceConnection>{};
  final commands = <String>[];
  final sizes = <(int, int)>[];
  @override
  String? activeWindowId = '@1';
  @override
  String? activePaneId = '%1';
  @override
  bool ready = true;
  @override
  bool isClosed = false;
  @override
  Object? error;
  final exit = Completer<int?>();
  @override
  Future<int?> get done => exit.future;

  Future<void> initialize() async {
    for (final (id, window, x, width) in [
      ('%1', '@1', 0, 40),
      ('%2', '@1', 41, 39),
      ('%3', '@2', 0, 80),
    ]) {
      final connection = TmuxWorkspaceConnection();
      final session = TerminalSession();
      await session.connect(
        (_, __) async => connection,
        kind: TerminalSessionKind.ssh,
      );
      session.terminal.resize(width, 24);
      session.terminal.write('\x1b[32m$id\x1b[0m ready\r\n');
      panes[id] = _Pane(
        id: id,
        windowId: window,
        x: x,
        width: width,
        session: session,
      );
      connections[id] = connection;
    }
  }

  @override
  Future<void> selectPane(String id) async {
    commands.add('pane $id');
    selectFromRemote(id);
  }

  void selectFromRemote(String id) {
    activePaneId = id;
    activeWindowId = panes[id]!.windowId;
    notifyListeners();
  }

  @override
  Future<void> selectWindow(String id) async {
    commands.add('window $id');
    activeWindowId = id;
    activePaneId = windows.firstWhere((window) => window.id == id).activePaneId;
    notifyListeners();
  }

  @override
  Future<void> newWindow() async => commands.add('new window');
  @override
  Future<void> splitPane(String id, {required bool horizontal}) async =>
      commands.add('split $id $horizontal');
  @override
  Future<void> resize(int columns, int rows) async =>
      sizes.add((columns, rows));
  @override
  Future<void> detach() async {
    commands.add('detach');
    isClosed = true;
    ready = false;
    if (!exit.isCompleted) exit.complete(0);
    notifyListeners();
  }

  @override
  Future<void> close() => detach();

  @override
  void dispose() {
    for (final pane in panes.values) {
      pane.session.dispose();
    }
    if (!exit.isCompleted) exit.complete(0);
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pane implements TmuxControlPane {
  _Pane({
    required this.id,
    required this.windowId,
    required this.x,
    required this.width,
    required this.session,
  });
  @override
  final String id;
  @override
  String windowId;
  @override
  int x;
  @override
  int y = 0;
  @override
  int width;
  @override
  int height = 24;
  @override
  bool active = false;
  @override
  final TerminalSession session;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TmuxWorkspaceConnection implements TerminalConnection {
  final controller = StreamController<String>();
  final exit = Completer<int?>();
  final input = <String>[];
  bool closed = false;
  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => controller.stream;
  @override
  Future<int?> get exitCode => exit.future;
  @override
  Future<void> write(String value) async => input.add(value);
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!exit.isCompleted) exit.complete(0);
    unawaited(controller.close());
  }
}
