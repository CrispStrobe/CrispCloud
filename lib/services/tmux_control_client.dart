import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'terminal_connection.dart';
import 'terminal_session.dart';
import 'terminal_user_input.dart';
import 'tmux_control_protocol.dart';

class TmuxControlException implements Exception {
  const TmuxControlException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A server window. IDs, not user-supplied names, address protocol commands.
class TmuxControlWindow {
  const TmuxControlWindow({
    required this.id,
    required this.index,
    required this.name,
    required this.width,
    required this.height,
    required this.paneIds,
    required this.activePaneId,
    this.zoomed = false,
  });

  final String id;
  final int index;
  final String name;
  final int width;
  final int height;

  /// Visible panes. A remotely zoomed window has only its active pane here.
  final List<String> paneIds;
  final String activePaneId;
  final bool zoomed;
}

/// Pane geometry and emulator survive window selection and metadata refreshes.
class TmuxControlPane {
  TmuxControlPane._({
    required this.id,
    required this.windowId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.active,
    required this.session,
    required _TmuxPaneConnection connection,
    // Keep the public-facing argument independent of the private transport field.
    // ignore: prefer_initializing_formals
  }) : _connection = connection;

  final String id;
  String windowId;
  int x;
  int y;
  int width;
  int height;
  bool active;
  final TerminalSession session;
  final _TmuxPaneConnection _connection;
  bool _capturing = true;
}

/// Owns a single tmux 3.2+ control client on an already verified transport.
///
/// Local windows/panes are a view of the remote session. Closing this client
/// never sends kill-session, kill-window, or kill-pane. The transport callback
/// must release the exact SSH route which created it, even after cancellation.
class TmuxControlClient extends ChangeNotifier {
  TmuxControlClient({
    required Stream<List<int>> output,
    required Future<void> Function(String) write,
    required Future<void> Function() close,
    required Future<int?> exitCode,
    this.commandTimeout = const Duration(seconds: 10),
  }) : _source = output,
       // The transport callback is intentionally a private implementation field.
       // ignore: prefer_initializing_formals
       _write = write,
       _closeTransport = close,
       _transportExit = exitCode {
    _parser = TmuxControlParser(onEvent: _event);
    // Observe the transport status immediately, even if startup fails first.
    unawaited(
      exitCode.then<void>(
        (value) => _exitCode = value,
        onError: (Object failure, StackTrace stack) => _fail(failure, stack),
      ),
    );
    unawaited(_startup.future.then<void>((_) {}, onError: (Object _) {}));
    unawaited(_done.future.then<void>((_) {}, onError: (Object _) {}));
  }

  static const maximumWindows = 16;
  static const maximumPanes = 64;
  static const maximumColumns = 1000;
  static const maximumRows = 500;
  static const maximumPaneCells = 2 * 1024 * 1024;
  static const historyLines = 200;
  static const maximumInputBytes = 64 * 1024;
  static const _maximumPendingCommands = 256;
  // Seven synchronous commands capture one pane. A group of eight keeps the
  // command budget bounded while amortizing high-latency SSH round trips.
  static const _maximumCaptureGroup = 8;

  final Duration commandTimeout;
  final Stream<List<int>> _source;
  final Future<void> Function(String) _write;
  final Future<void> Function() _closeTransport;
  final Future<int?> _transportExit;
  late final TmuxControlParser _parser;
  StreamSubscription<List<int>>? _subscription;
  final _startup = Completer<void>();
  final _done = Completer<int?>();
  final _pending = Queue<_PendingCommand>();
  final _ownedPanes = <String, TmuxControlPane>{};
  final _retiredPanes = Queue<TmuxControlPane>();
  List<TmuxControlWindow> _windows = const [];
  Map<String, TmuxControlPane> _panes = const {};
  String? _activeWindowId;
  String? _activePaneId;
  bool _ready = false;
  bool _closed = false;
  bool _disposed = false;
  Object? _error;
  int? _exitCode;
  bool _started = false;
  bool _refreshAgain = false;
  Future<void>? _refreshing;
  Future<void>? _closing;
  Future<void> _writing = Future<void>.value();
  Timer? _refreshTimer;
  Timer? _resizeTimer;
  bool _resizing = false;
  int _columns = 80;
  int _rows = 24;
  int _layoutRevision = 0;
  (int, int)? _requestedSize;
  Completer<void>? _resizeCompletion;

  List<TmuxControlWindow> get windows => _windows;
  Map<String, TmuxControlPane> get panes => _panes;
  String? get activeWindowId => _activeWindowId;
  String? get activePaneId => _activePaneId;
  bool get ready => _ready && !_closed;
  bool get isClosed => _closed;
  Object? get error => _error;
  Future<int?> get done => _done.future;

  Future<void> start({int columns = 80, int rows = 24}) async {
    if (_started) throw StateError('The tmux client was already started.');
    _checkDimensions(columns, rows);
    _started = true;
    _columns = columns;
    _rows = rows;
    final startupTimer = Timer(
      commandTimeout,
      () => _fail(
        const TmuxControlException('The tmux control handshake timed out.'),
      ),
    );
    _subscription = _source.listen(
      (bytes) {
        if (_closed) return;
        try {
          _parser.add(bytes);
        } catch (failure, stack) {
          _fail(failure, stack);
        }
      },
      onError: (Object failure, StackTrace stack) => _fail(failure, stack),
      onDone: _sourceEnded,
    );
    try {
      await _startup.future;
      startupTimer.cancel();
      _checkOpen();
      final version = (await _command("display-message -p '#{version}'")).text;
      final parsed = RegExp(r'^(?:next-)?([0-9]+)\.([0-9]+)(?:[a-z]|[-.].*)?$')
          .firstMatch(version.trim());
      if (parsed == null ||
          int.parse(parsed[1]!) < 3 ||
          (int.parse(parsed[1]!) == 3 && int.parse(parsed[2]!) < 2)) {
        throw const TmuxControlException(
          'Native tmux requires tmux 3.2 or newer.',
        );
      }
      await _command('refresh-client -C ${columns}x$rows');
      await _refresh();
      _checkOpen();
      _ready = true;
      _notify();
    } catch (failure, stack) {
      _fail(failure, stack);
      await close();
      rethrow;
    } finally {
      startupTimer.cancel();
    }
  }

  void _event(TmuxControlEvent event) {
    if (_closed) return;
    if (event is TmuxControlBlock) {
      if (!_startup.isCompleted) {
        if (!event.success) {
          throw TmuxControlException(
            _message(event.text, 'tmux could not start.'),
          );
        }
        _startup.complete();
        return;
      }
      // Commands from hooks and the initial launch have flag zero. They must
      // never consume a reply belonging to a command sent on stdin (flag one).
      if (event.flags == '0') return;
      if (event.flags != '1' || _pending.isEmpty) {
        throw const TmuxControlProtocolException(
          'Unexpected command response.',
        );
      }
      final pending = _pending.removeFirst();
      if (_pending.isEmpty ||
          !identical(pending.deadline, _pending.first.deadline)) {
        pending.deadline.timer?.cancel();
        _startPendingDeadline();
      }
      if (!event.success) {
        final failure = TmuxControlException(
          _message(event.text, 'tmux rejected the command.'),
        );
        pending.completer.completeError(failure);
        // A tmux command-list error skips the rest of that list. Continuing
        // would misassociate later replies, so fail the whole transport.
        if (pending.batch) _fail(failure);
        return;
      }
      try {
        pending.onSuccess?.call(event);
        pending.completer.complete(event);
      } catch (failure, stack) {
        pending.completer.completeError(failure, stack);
        _fail(failure, stack);
      }
      return;
    }
    final notification = event as TmuxControlNotification;
    if (notification.name == '%exit') {
      // A clean detach is expected; failure during startup remains visible.
      if (!_startup.isCompleted || !_ready) {
        _fail(
          TmuxControlException(
            _message(
              notification.text,
              'tmux exited before the workspace opened.',
            ),
          ),
        );
      } else {
        _closeInBackground();
      }
      return;
    }
    if (notification.name == '%output' ||
        notification.name == '%extended-output') {
      _output(notification);
      return;
    }
    if (notification.name == '%pause') {
      // This client does not enable pause-after. An unsolicited pause means
      // output is incomplete; refresh the pane before displaying more bytes.
      final pane = _ownedPanes[notification.text.trim()];
      if (pane != null) pane._capturing = true;
    }
    if (notification.name == '%layout-change') {
      _layoutChanged(notification.text);
    }
    if (const {
      '%layout-change',
      '%window-add',
      '%window-close',
      '%window-renamed',
      '%window-pane-changed',
      '%session-window-changed',
      '%session-changed',
      '%session-renamed',
      '%pane-mode-changed',
      '%pane-exited',
      '%pause',
    }.contains(notification.name)) {
      _scheduleRefresh();
    }
  }

  void _layoutChanged(String arguments) {
    _layoutRevision++;
    final fields = arguments.split(' ');
    if (fields.isEmpty || !_windowId.hasMatch(fields.first)) {
      throw const TmuxControlProtocolException('Invalid layout window.');
    }
    // Geometry is consumed at the notification boundary, before the next
    // %output in this same packet can be interpreted at the old dimensions.
    // Visible layout accounts for remote zoom. Unchanged cells, including
    // panes merely moved within a window, keep their existing history.
    final sizes = fields.length >= 3 ? _LayoutPaneSizes.parse(fields[2]) : null;
    for (final pane in _ownedPanes.values) {
      if (pane.windowId != fields.first) continue;
      final size = sizes?[pane.id];
      if (sizes == null ||
          (size != null &&
              (size.$1 != pane.session.terminal.viewWidth ||
                  size.$2 != pane.session.terminal.viewHeight))) {
        pane._capturing = true;
      }
    }
  }

  void _output(TmuxControlNotification notification) {
    final bytes = notification.arguments;
    final separator = bytes.indexOf(32);
    if (separator < 2 || separator > 12) {
      throw const TmuxControlProtocolException('Invalid pane output target.');
    }
    final id = ascii.decode(bytes.sublist(0, separator), allowInvalid: true);
    if (!_paneId.hasMatch(id)) {
      throw const TmuxControlProtocolException('Invalid pane output target.');
    }
    var start = separator + 1;
    if (notification.name == '%extended-output') {
      // Future fields may be inserted before the literal " : " separator.
      var colon = -1;
      for (var i = start; i + 1 < bytes.length; i++) {
        if (bytes[i] == 58 &&
            i > 0 &&
            bytes[i - 1] == 32 &&
            bytes[i + 1] == 32) {
          colon = i;
          break;
        }
      }
      if (colon < 0 || colon - start > 256) {
        throw const TmuxControlProtocolException('Invalid extended output.');
      }
      start = colon + 2;
    }
    final pane = _ownedPanes[id];
    if (pane == null) {
      _scheduleRefresh();
      return; // Its bounded initial capture supplies output before discovery.
    }
    if (pane._capturing) return;
    pane._connection.addBytes(decodeTmuxOctal(bytes.sublist(start)));
  }

  Future<TmuxControlBlock> _command(
    String command, {
    void Function(TmuxControlBlock)? onSuccess,
  }) => _batch([_Command(command, onSuccess)]).then((blocks) => blocks.single);

  Future<List<TmuxControlBlock>> _batch(
    List<_Command> commands, {
    int? deadlineGroupSize,
  }) {
    _checkOpen();
    if (commands.isEmpty ||
        _pending.length + commands.length > _maximumPendingCommands) {
      throw const TmuxControlException('Too many pending tmux commands.');
    }
    final groupSize = deadlineGroupSize ?? commands.length;
    if (groupSize < 1 || groupSize > commands.length) {
      throw ArgumentError('Invalid tmux command deadline group.');
    }
    // Validate the whole list before reserving any reply slots. A rejected
    // later command must not leave earlier slots without a write or timer.
    if (commands.any(
      (command) =>
          command.text.contains('\n') ||
          command.text.contains('\r') ||
          command.text.length > 16384,
    )) {
      throw ArgumentError('Invalid tmux control command.');
    }
    final pending = <_PendingCommand>[];
    var deadline = _PendingCommandDeadline();
    for (var index = 0; index < commands.length; index++) {
      final command = commands[index];
      if (index != 0 && index % groupSize == 0) {
        deadline = _PendingCommandDeadline();
      }
      final item = _PendingCommand(
        command.onSuccess,
        commands.length > 1,
        deadline,
      );
      // A later command may fail before its caller has awaited earlier replies.
      unawaited(
        item.completer.future.then<void>((_) {}, onError: (Object _) {}),
      );
      _pending.add(item);
      pending.add(item);
    }
    _startPendingDeadline();
    final line = '${commands.map((command) => command.text).join(' ; ')}\n';
    _writing = _writing
        .then((_) async {
          if (_closed) return;
          await _write(line);
        })
        .catchError(
          (Object failure, StackTrace stack) => _fail(failure, stack),
        );
    return Future.wait(pending.map((item) => item.completer.future));
  }

  void _startPendingDeadline() {
    if (_closed || _pending.isEmpty) return;
    // Replies are strictly ordered. A queued command must not spend its
    // timeout behind another valid snapshot. Each ordinary command list, or
    // each pane inside a grouped capture, retains one hard timeout starting
    // when it reaches the reply queue head. Partial replies do not reset it.
    // With eight panes per capture and 256 pending commands, both the active
    // capture budget and the total queued work remain bounded.
    _pending.first.deadline.timer ??= Timer(
      commandTimeout,
      () => _fail(
        const TmuxControlException(
          'A tmux command timed out. Reconnect to continue.',
        ),
      ),
    );
  }

  void _scheduleRefresh() {
    if (_closed || !_started) return;
    if (_refreshing != null) {
      _refreshAgain = true;
      return;
    }
    _refreshTimer ??= Timer(const Duration(milliseconds: 35), () {
      _refreshTimer = null;
      if (_closed || !_ready) return;
      unawaited(
        _refresh().catchError(
          (Object failure, StackTrace stack) => _fail(failure, stack),
        ),
      );
    });
  }

  Future<void> _refresh() {
    final existing = _refreshing;
    if (existing != null) {
      _refreshAgain = true;
      return existing;
    }
    final operation = _refreshSnapshot();
    _refreshing = operation;
    return operation.whenComplete(() {
      _refreshing = null;
      if (_refreshAgain && !_closed) {
        _refreshAgain = false;
        _scheduleRefresh();
      }
    });
  }

  Future<void> _refreshSnapshot() async {
    // A notification can arrive while metadata or a pane capture is in flight.
    // Never publish a mixture of revisions or un-gate output with stale sizes.
    for (var attempt = 0; attempt < 16; attempt++) {
      if (await _refreshSnapshotAttempt()) return;
    }
    throw const TmuxControlException(
      'The tmux layout kept changing during refresh. Reconnect to continue.',
    );
  }

  Future<bool> _refreshSnapshotAttempt() async {
    final revision = _layoutRevision;
    // The names are display-only. POSIX cntrl replacement prevents a remote
    // window name from injecting a metadata row or a protocol record.
    final results = await _batch([
      const _Command(
        "list-windows -F '#{window_id} #{window_index} #{window_width} #{window_height} #{window_active} #{pane_id} #{window_zoomed_flag} #{s/[[:cntrl:]]/ /:window_name}'",
      ),
      const _Command(
        "list-panes -s -F '#{window_id} #{pane_id} #{pane_width} #{pane_height} #{pane_left} #{pane_top} #{pane_active}'",
      ),
    ]);
    _checkOpen();
    if (revision != _layoutRevision) return false;
    final windows = results[0].lines
        .map(
          (line) =>
              _WindowRecord.parse(utf8.decode(line, allowMalformed: true)),
        )
        .toList();
    final paneRecords = results[1].lines
        .map(
          (line) => _PaneRecord.parse(ascii.decode(line, allowInvalid: true)),
        )
        .toList();
    if (windows.isEmpty ||
        windows.length > maximumWindows ||
        paneRecords.isEmpty ||
        paneRecords.length > maximumPanes) {
      throw const TmuxControlException(
        'The tmux session exceeds 16 windows or 64 panes.',
      );
    }
    final windowIds = windows.map((window) => window.id).toSet();
    final paneIds = paneRecords.map((pane) => pane.id).toSet();
    if (windowIds.length != windows.length ||
        paneIds.length != paneRecords.length ||
        paneRecords.any((pane) => !windowIds.contains(pane.windowId)) ||
        windows.where((window) => window.active).length != 1 ||
        paneRecords.fold<int>(
              0,
              (sum, pane) => sum + pane.width * pane.height,
            ) >
            maximumPaneCells) {
      throw const TmuxControlProtocolException('Invalid workspace metadata.');
    }
    final nextWindows = <TmuxControlWindow>[];
    for (final window in windows) {
      final children =
          paneRecords.where((pane) => pane.windowId == window.id).toList()
            ..sort(
              (a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x),
            );
      if (children.isEmpty ||
          !children.any((pane) => pane.id == window.activePaneId) ||
          children.where((pane) => pane.active).length != 1 ||
          children.singleWhere((pane) => pane.active).id !=
              window.activePaneId) {
        throw const TmuxControlProtocolException(
          'Invalid active pane metadata.',
        );
      }
      final visible = window.zoomed
          ? children.where((pane) => pane.id == window.activePaneId).toList()
          : children;
      if (visible.any(
        (pane) =>
            pane.x + pane.width > window.width ||
            pane.y + pane.height > window.height,
      )) {
        throw const TmuxControlProtocolException(
          'Pane geometry exceeds its window.',
        );
      }
      for (var i = 0; i < visible.length; i++) {
        for (var j = i + 1; j < visible.length; j++) {
          final a = visible[i];
          final b = visible[j];
          if (a.x < b.x + b.width &&
              b.x < a.x + a.width &&
              a.y < b.y + b.height &&
              b.y < a.y + a.height) {
            throw const TmuxControlProtocolException('Pane geometry overlaps.');
          }
        }
      }
      nextWindows.add(
        TmuxControlWindow(
          id: window.id,
          index: window.index,
          name: window.name,
          width: window.width,
          height: window.height,
          paneIds: List.unmodifiable(visible.map((pane) => pane.id)),
          activePaneId: window.activePaneId,
          zoomed: window.zoomed,
        ),
      );
    }
    nextWindows.sort((a, b) => a.index.compareTo(b.index));
    // A superseded capture may have created sessions which no viewport ever
    // received. Release those before constructing another replacement. Keep
    // every published pane alive until the complete snapshot replaces it.
    for (final id
        in _ownedPanes.keys
            .where((id) => !paneIds.contains(id) && !_panes.containsKey(id))
            .toList()) {
      final abandoned = _ownedPanes.remove(id)!;
      abandoned._connection.finish();
      abandoned.session.dispose();
    }
    // Publish only a complete, mutually consistent window/pane snapshot.
    final nextPanes = <String, TmuxControlPane>{};
    for (final record in paneRecords) {
      var pane = _ownedPanes[record.id];
      if (pane == null) {
        if (_ownedPanes.length >= maximumPanes * 2) {
          throw const TmuxControlException(
            'The tmux workspace has too many pending replacement panes.',
          );
        }
        final session = TerminalSession(
          maxLines: (200000 ~/ record.width).clamp(record.height, 500),
          maximumPendingInputCodeUnits: 16384,
        );
        final connection = _TmuxPaneConnection(
          (text) => _sendInput(record.id, text),
        );
        pane = TmuxControlPane._(
          id: record.id,
          windowId: record.windowId,
          x: record.x,
          y: record.y,
          width: record.width,
          height: record.height,
          active: record.active,
          session: session,
          connection: connection,
        );
        _ownedPanes[record.id] = pane;
        await session.connect(
          (_, __) async => connection,
          kind: TerminalSessionKind.ssh,
          label: record.id,
        );
        _checkOpen();
        final terminal = session.terminal;
        final send = terminal.onOutput;
        // tmux itself already answers application queries. Never feed a
        // second emulator's status replies back into the remote application.
        terminal.onOutput = (data) {
          if (terminal is InputAwareTerminal && terminal.hasActiveUserInput) {
            send?.call(data);
          }
        };
        if (revision != _layoutRevision) return false;
      }
      if (pane.session.terminal.viewWidth != record.width ||
          pane.session.terminal.viewHeight != record.height) {
        pane._capturing = true;
      }
      _checkOpen();
      if (revision != _layoutRevision) return false;
      nextPanes[record.id] = pane;
    }
    final captures = <_PaneCapture>[];
    for (var index = 0; index < paneRecords.length; index++) {
      final record = paneRecords[index];
      final pane = nextPanes[record.id]!;
      if (pane._capturing) {
        captures.add(_prepareCapture(pane, record, revision));
      }
      if (captures.isNotEmpty &&
          (captures.length == _maximumCaptureGroup ||
              index == paneRecords.length - 1)) {
        // tmux executes this complete command list synchronously. Snapshot
        // groups therefore share a server event-loop boundary, without
        // holding 64 independent reply batches or one RTT for every pane.
        await _batch([
          for (final capture in captures) ...capture.commands,
        ], deadlineGroupSize: captures.first.commands.length);
        _checkOpen();
        if (revision != _layoutRevision ||
            captures.any((capture) => !capture.wasInstalled())) {
          return false;
        }
        captures.clear();
      }
    }
    for (final record in paneRecords) {
      final pane = nextPanes[record.id]!;
      pane.windowId = record.windowId;
      pane.x = record.x;
      pane.y = record.y;
      pane.width = record.width;
      pane.height = record.height;
      pane.active = record.active;
    }
    for (final id
        in _ownedPanes.keys.where((id) => !paneIds.contains(id)).toList()) {
      final pane = _ownedPanes.remove(id)!;
      pane._connection.finish();
      _retiredPanes.add(pane);
    }
    _windows = List.unmodifiable(nextWindows);
    _panes = Map.unmodifiable(nextPanes);
    _activeWindowId = windows.singleWhere((window) => window.active).id;
    _activePaneId = _windows
        .singleWhere((window) => window.id == _activeWindowId)
        .activePaneId;
    _notify();
    // A bounded retirement list keeps the just-removed emulator alive while
    // its last viewport is being rebuilt. None owns a live transport.
    while (_retiredPanes.length > maximumPanes) {
      _retiredPanes.removeFirst().session.dispose();
    }
    return true;
  }

  _PaneCapture _prepareCapture(
    TmuxControlPane pane,
    _PaneRecord record,
    int revision,
  ) {
    TmuxControlBlock? screen;
    TmuxControlBlock? savedScreen;
    TmuxControlBlock? parserPending;
    List<String>? state;
    var installed = false;
    // All commands are synchronous in one tmux command list. Turn off this
    // client's output first, discard its pre-capture backlog, then re-enable
    // it at the same server event-loop boundary as the snapshot. Capture is
    // applied in the reply callback, before subsequent records in that packet.
    final commands = <_Command>[
      _Command('refresh-client -A ${pane.id}:off'),
      _Command(
        'capture-pane -p -e -C -t ${pane.id} -S -$historyLines',
        (block) => screen = block,
      ),
      _Command(
        'capture-pane -p -e -C -a -q -t ${pane.id} -S -$historyLines',
        (block) => savedScreen = block,
      ),
      _Command(
        'capture-pane -p -P -C -t ${pane.id}',
        (block) => parserPending = block,
      ),
      _Command(
        // Older tmux releases have no bracket_paste_flag format. Only that
        // field may be empty; restore the pane's last observed live mode then.
        "display-message -p -t ${pane.id} '#{cursor_x} #{cursor_y} #{alternate_on} #{cursor_flag} #{keypad_cursor_flag} #{keypad_flag} #{insert_flag} #{wrap_flag} #{origin_flag} #{bracket_paste_flag} #{scroll_region_upper} #{scroll_region_lower} #{alternate_saved_x} #{alternate_saved_y} #{pane_width} #{pane_height}'",
        (block) {
          state = block.text.split(' ');
        },
      ),
      _Command('refresh-client -A ${pane.id}:on'),
      _Command('refresh-client -A ${pane.id}:continue', (_) {
        if (_closed || !identical(_ownedPanes[pane.id], pane)) return;
        if (revision != _layoutRevision) return;
        if (screen == null ||
            state == null ||
            savedScreen == null ||
            parserPending == null) {
          throw const TmuxControlProtocolException('Incomplete pane capture.');
        }
        final capturedState = state!;
        if (capturedState.length != 16 ||
            !_number.hasMatch(capturedState[14]) ||
            !_number.hasMatch(capturedState[15])) {
          throw const TmuxControlProtocolException(
            'Invalid captured terminal dimensions.',
          );
        }
        final width = int.parse(capturedState[14]);
        final height = int.parse(capturedState[15]);
        _checkDimensions(width, height);
        // These dimensions were sampled in the same synchronous command list
        // as the grid. A resize after list-panes requires a fresh metadata pass.
        if (width != record.width || height != record.height) return;
        _installCapture(
          pane,
          screen!,
          savedScreen!,
          parserPending!,
          capturedState,
          width,
          height,
        );
        pane._capturing = false;
        installed = true;
      }),
    ];
    return _PaneCapture(commands, () => installed);
  }

  void _installCapture(
    TmuxControlPane pane,
    TmuxControlBlock capture,
    TmuxControlBlock savedCapture,
    TmuxControlBlock parserPending,
    List<String> state,
    int width,
    int height,
  ) {
    if (state.length != 16 ||
        state.take(2).any((value) => !_number.hasMatch(value)) ||
        state.skip(2).take(7).any((value) => value != '0' && value != '1') ||
        (state[9].isNotEmpty && state[9] != '0' && state[9] != '1') ||
        state.skip(10).any((value) => !_number.hasMatch(value))) {
      throw const TmuxControlProtocolException(
        'Invalid captured terminal state.',
      );
    }
    final x = int.parse(state[0]);
    final y = int.parse(state[1]);
    final top = int.parse(state[10]);
    final bottom = int.parse(state[11]);
    final savedX = int.parse(state[12]);
    final savedY = int.parse(state[13]);
    if (x > width ||
        y >= height ||
        top > bottom ||
        bottom >= height ||
        capture.lines.length > historyLines + height + 1 ||
        savedCapture.lines.length > historyLines + height + 1 ||
        parserPending.lines.length > 1 ||
        savedX > maximumColumns ||
        savedY > maximumRows) {
      throw const TmuxControlProtocolException(
        'Captured terminal state exceeds its pane.',
      );
    }
    final text = StringBuffer('\x1bc');
    // No trailing newline: the last captured row must remain the last screen
    // row, rather than creating an extra blank line and scrolling the screen.
    void appendScreen(TmuxControlBlock screen) {
      for (var i = 0; i < screen.lines.length; i++) {
        if (i != 0) text.write('\r\n');
        text.write(
          utf8.decode(decodeTmuxCapture(screen.lines[i]), allowMalformed: true),
        );
      }
    }

    if (state[2] == '1') {
      // tmux's saved grid is the primary screen while an alternate is active.
      // Populate it before entering 1049 so leaving vim/less restores it.
      appendScreen(savedCapture);
      text.write(
        '\x1b[${savedY.clamp(0, height - 1) + 1};${savedX.clamp(0, width - 1) + 1}H',
      );
      text.write('\x1b[?1049h');
    }
    appendScreen(capture);
    text.write('\x1b[${top + 1};${bottom + 1}r');
    void mode(int number, String flag) =>
        text.write('\x1b[?$number${flag == '1' ? 'h' : 'l'}');
    mode(25, state[3]);
    mode(1, state[4]);
    text.write(state[5] == '1' ? '\x1b=' : '\x1b>');
    text.write('\x1b[4${state[6] == '1' ? 'h' : 'l'}');
    mode(7, state[7]);
    mode(6, state[8]);
    mode(
      2004,
      state[9].isNotEmpty
          ? state[9]
          : pane.session.terminal.bracketedPasteMode
          ? '1'
          : '0',
    );
    final cursorRow = state[8] == '1' ? y - top + 1 : y + 1;
    if (cursorRow < 1) {
      throw const TmuxControlProtocolException('Cursor precedes the origin.');
    }
    text.write('\x1b[$cursorRow;${x.clamp(0, width - 1) + 1}H');
    // Captured state cannot run triggers or send terminal replies.
    pane._connection.resetDecoder();
    pane.session.terminal.resize(width, height);
    pane.session.terminal.write(text.toString());
    // Continue an escape sequence or UTF-8 code point interrupted at attach.
    // `capture-pane -P -C` uses octal escapes, unlike its screen-capture mode.
    if (parserPending.lines.isNotEmpty) {
      pane._connection.addBytes(decodeTmuxOctal(parserPending.lines.single));
    }
  }

  Future<void> _sendInput(String id, String text) async {
    if (text.isEmpty) return;
    final pane = _ownedPanes[id];
    if (!ready || pane == null || !pane.session.isConnected) {
      return;
    }
    // A geometry recapture gates display bytes, not explicit user input.
    // Commands still target the same live pane and queue between atomic
    // capture batches, so a resize cannot silently discard typed characters.
    final bytes = utf8.encode(text);
    if (bytes.length > maximumInputBytes) {
      throw const TmuxControlException('The tmux input is too large.');
    }
    // Literal hex bytes cannot introduce tmux command separators or formats.
    // Await each bounded chunk to limit queued commands and honor revocation.
    for (var start = 0; start < bytes.length; start += 1024) {
      if (!ready ||
          !identical(_ownedPanes[id], pane) ||
          !pane.session.isConnected) {
        return;
      }
      final end = (start + 1024).clamp(0, bytes.length);
      final hex = bytes
          .sublist(start, end)
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      await _command('send-keys -H -t $id $hex');
    }
  }

  Future<void> selectWindow(String id) async {
    _checkReady();
    if (!_windowId.hasMatch(id) || !_windows.any((window) => window.id == id)) {
      throw ArgumentError('Unknown tmux window.');
    }
    await _command('select-window -t $id');
    await _refresh();
  }

  Future<void> selectPane(String id) async {
    _checkReady();
    if (!_paneId.hasMatch(id) || !_panes.containsKey(id)) {
      throw ArgumentError('Unknown tmux pane.');
    }
    await _command('select-pane -t $id');
    await _refresh();
  }

  Future<void> newWindow() async {
    _checkReady();
    if (_windows.length >= maximumWindows || _panes.length >= maximumPanes) {
      throw const TmuxControlException(
        'The tmux workspace is at its window or pane limit.',
      );
    }
    await _command('new-window');
    await _refresh();
  }

  Future<void> splitPane(String id, {required bool horizontal}) async {
    _checkReady();
    if (!_paneId.hasMatch(id) || !_panes.containsKey(id)) {
      throw ArgumentError('Unknown tmux pane.');
    }
    if (_panes.length >= maximumPanes) {
      throw const TmuxControlException(
        'The tmux workspace is at its pane limit.',
      );
    }
    await _command('split-window -${horizontal ? 'h' : 'v'} -t $id');
    await _refresh();
  }

  /// Updates this client's overall cell geometry, allowing tmux's window-size
  /// policy to decide the actual shared remote size. It does not force a resize
  /// of another client's windows or independently resize every child pane.
  Future<void> resize(int columns, int rows) {
    _checkDimensions(columns, rows);
    if (_closed ||
        !_ready ||
        (!_resizing &&
            columns == _columns &&
            rows == _rows &&
            _requestedSize == null)) {
      return Future<void>.value();
    }
    _requestedSize = (columns, rows);
    final completion = _resizeCompletion ??= Completer<void>();
    _scheduleResize();
    return completion.future;
  }

  void _scheduleResize() {
    // Keep at most one resize on the wire and one latest requested size. In
    // particular, returning to the last completed size while another resize
    // is in flight must not lose that final viewport geometry.
    if (_closed || _resizing || _requestedSize == null) return;
    _resizeTimer ??= Timer(const Duration(milliseconds: 80), () async {
      _resizeTimer = null;
      _resizing = true;
      final size = _requestedSize;
      _requestedSize = null;
      final completion = _resizeCompletion;
      _resizeCompletion = null;
      try {
        if (!_closed &&
            size != null &&
            (size.$1 != _columns || size.$2 != _rows)) {
          await _command('refresh-client -C ${size.$1}x${size.$2}');
          _columns = size.$1;
          _rows = size.$2;
          await _refresh();
        }
        completion?.complete();
      } catch (failure, stack) {
        completion?.completeError(failure, stack);
      } finally {
        _resizing = false;
        _scheduleResize();
      }
    });
  }

  Future<void> detach() async {
    if (_closed) return close();
    try {
      if (_ready) await _command('detach-client');
    } finally {
      await close();
    }
  }

  void _sourceEnded() {
    if (_closed) return;
    try {
      _parser.finish();
      if (!_ready) {
        throw const TmuxControlException(
          'tmux closed before the workspace opened.',
        );
      }
      _closeInBackground();
    } catch (failure, stack) {
      _fail(failure, stack);
    }
  }

  void _fail(Object failure, [StackTrace? stack]) {
    if (_closed) return;
    _error = failure;
    _closeInBackground();
  }

  void _closeInBackground() {
    unawaited(
      close().catchError((Object failure, StackTrace stack) {
        _error ??= failure;
        _notify();
      }),
    );
  }

  /// Revokes writes immediately, releases the SSH owner, and preserves buffers
  /// for read-only viewports. Call dispose only after those viewports unmount.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _ready = false;
    _parser.stop();
    _refreshTimer?.cancel();
    _resizeTimer?.cancel();
    final failure =
        _error ?? const TmuxControlException('The tmux connection is closed.');
    if (!_startup.isCompleted) _startup.completeError(failure);
    while (_pending.isNotEmpty) {
      final pending = _pending.removeFirst();
      pending.deadline.timer?.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(failure);
      }
    }
    _resizeCompletion?.complete();
    _resizeCompletion = null;
    for (final pane in _ownedPanes.values) {
      pane._connection.finish();
    }
    _notify();
    try {
      // Begin closing the route before canceling a source whose cancellation
      // may itself wait for that route's channel shutdown.
      await Future.wait<void>([
        Future<void>.sync(_closeTransport),
        Future<void>.sync(() => _subscription?.cancel()),
      ]);
      try {
        _exitCode = await _transportExit.timeout(const Duration(seconds: 2));
      } catch (_) {}
    } catch (failure) {
      _error ??= failure;
      _closing = null; // An explicit owner can retry unconfirmed cleanup.
      _notify();
      rethrow;
    } finally {
      if (!_done.isCompleted) _done.complete(_exitCode);
    }
  }

  void _checkOpen() {
    if (_closed || _disposed) {
      throw const TmuxControlException('The tmux connection is closed.');
    }
  }

  void _checkReady() {
    _checkOpen();
    if (!_ready) {
      throw const TmuxControlException('The tmux workspace is still loading.');
    }
  }

  static void _checkDimensions(int columns, int rows) {
    if (columns < 1 ||
        columns > maximumColumns ||
        rows < 1 ||
        rows > maximumRows) {
      throw ArgumentError('Invalid tmux client dimensions.');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closeInBackground();
    for (final pane in [..._ownedPanes.values, ..._retiredPanes]) {
      pane.session.dispose();
    }
    _ownedPanes.clear();
    _retiredPanes.clear();
    super.dispose();
  }

  static String _message(String text, String fallback) {
    final cleaned = text.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    return cleaned.isEmpty
        ? fallback
        : cleaned.substring(0, cleaned.length.clamp(0, 512));
  }

  static final _paneId = RegExp(r'^%[0-9]{1,10}$');
  static final _windowId = RegExp(r'^@[0-9]{1,10}$');
  static final _number = RegExp(r'^[0-9]{1,5}$');
}

class _Command {
  const _Command(this.text, [this.onSuccess]);
  final String text;
  final void Function(TmuxControlBlock)? onSuccess;
}

class _PaneCapture {
  const _PaneCapture(this.commands, this.wasInstalled);
  final List<_Command> commands;
  final bool Function() wasInstalled;
}

class _PendingCommand {
  _PendingCommand(this.onSuccess, this.batch, this.deadline);
  final completer = Completer<TmuxControlBlock>();
  final void Function(TmuxControlBlock)? onSuccess;
  final bool batch;
  final _PendingCommandDeadline deadline;
}

class _PendingCommandDeadline {
  Timer? timer;
}

class _TmuxPaneConnection
    implements TerminalConnection, TerminalConnectionMetadata {
  _TmuxPaneConnection(this.send) {
    resetDecoder();
  }
  final Future<void> Function(String) send;
  final _output = StreamController<String>(sync: true);
  final _exit = Completer<int?>();
  late ByteConversionSink _decoder;
  bool _closed = false;
  @override
  bool get isSandbox => false;
  @override
  TerminalBackend get backend => TerminalBackend.ssh;
  @override
  Stream<String> get output => _output.stream;
  @override
  Future<int?> get exitCode => _exit.future;
  void resetDecoder() {
    _decoder = const Utf8Decoder(allowMalformed: true).startChunkedConversion(
      StringConversionSink.fromStringSink(
        _OutputSink((text) {
          if (!_closed && text.isNotEmpty) _output.add(text);
        }),
      ),
    );
  }

  void addBytes(List<int> bytes) {
    if (!_closed) _decoder.add(bytes);
  }

  void finish() {
    if (_closed) return;
    _decoder.close();
    _closed = true;
    if (!_exit.isCompleted) _exit.complete(null);
    unawaited(_output.close());
  }

  @override
  Future<void> write(String data) async {
    if (!_closed) await send(data);
  }

  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async => finish();
}

class _OutputSink implements StringSink {
  _OutputSink(this.emit);
  final void Function(String) emit;
  @override
  void write(Object? value) => emit(value.toString());
  @override
  void writeAll(Iterable<Object?> values, [String separator = '']) =>
      emit(values.join(separator));
  @override
  void writeCharCode(int charCode) => emit(String.fromCharCode(charCode));
  @override
  void writeln([Object? value = '']) => emit('$value\n');
}

/// Only a bounded geometry hint; list-panes remains the authoritative model.
/// The recursive tmux layout grammar has a four-hex checksum, then leaf panes
/// or horizontal/vertical groups. Unknown syntax safely requests recapture.
class _LayoutPaneSizes {
  _LayoutPaneSizes(this.source);
  final String source;
  final sizes = <String, (int, int)>{};
  int position = 5;
  int nodes = 0;
  static final _prefix = RegExp(r'^[0-9a-fA-F]{4},');
  static final _geometry = RegExp(
    r'([0-9]{1,5})x([0-9]{1,5}),([0-9]{1,5}),([0-9]{1,5})',
  );
  static final _id = RegExp(r'[0-9]{1,10}');

  static Map<String, (int, int)>? parse(String source) {
    if (source.length > 16384 || !_prefix.hasMatch(source)) return null;
    final parser = _LayoutPaneSizes(source);
    try {
      parser.node(0);
      if (parser.position != source.length || parser.sizes.isEmpty) {
        return null;
      }
      return parser.sizes;
    } on FormatException {
      return null;
    }
  }

  void node(int depth) {
    if (depth > TmuxControlClient.maximumPanes ||
        ++nodes > TmuxControlClient.maximumPanes * 2) {
      throw const FormatException('Layout is too deep.');
    }
    final geometry = _geometry.matchAsPrefix(source, position);
    if (geometry == null) throw const FormatException('Missing geometry.');
    final width = int.parse(geometry[1]!);
    final height = int.parse(geometry[2]!);
    if (width < 1 ||
        width > TmuxControlClient.maximumColumns ||
        height < 1 ||
        height > TmuxControlClient.maximumRows) {
      throw const FormatException('Invalid layout dimensions.');
    }
    position = geometry.end;
    if (position == source.length) {
      throw const FormatException('Missing layout pane.');
    }
    final next = source[position++];
    if (next == ',') {
      final id = _id.matchAsPrefix(source, position);
      if (id == null || sizes.length == TmuxControlClient.maximumPanes) {
        throw const FormatException('Invalid layout pane.');
      }
      position = id.end;
      if (sizes.containsKey('%${id[0]}')) {
        throw const FormatException('Duplicate layout pane.');
      }
      sizes['%${id[0]}'] = (width, height);
      return;
    }
    if (next != '[' && next != '{') {
      throw const FormatException('Invalid layout group.');
    }
    final end = next == '[' ? ']' : '}';
    while (true) {
      node(depth + 1);
      if (position == source.length) {
        throw const FormatException('Unterminated layout group.');
      }
      final delimiter = source[position++];
      if (delimiter == end) return;
      if (delimiter != ',') {
        throw const FormatException('Invalid layout delimiter.');
      }
    }
  }
}

class _WindowRecord {
  _WindowRecord(
    this.id,
    this.index,
    this.width,
    this.height,
    this.active,
    this.activePaneId,
    this.zoomed,
    this.name,
  );
  final String id, activePaneId, name;
  final int index, width, height;
  final bool active, zoomed;
  factory _WindowRecord.parse(String value) {
    final match = RegExp(
      r'^(@[0-9]{1,10}) ([0-9]{1,10}) ([0-9]{1,4}) ([0-9]{1,4}) ([01]) (%[0-9]{1,10}) ([01]) (.*)$',
    ).firstMatch(value);
    if (match == null) {
      throw const TmuxControlProtocolException('Invalid window metadata.');
    }
    final width = int.parse(match[3]!);
    final height = int.parse(match[4]!);
    TmuxControlClient._checkDimensions(width, height);
    final name = match[8]!.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');
    return _WindowRecord(
      match[1]!,
      int.parse(match[2]!),
      width,
      height,
      match[5] == '1',
      match[6]!,
      match[7] == '1',
      name.substring(0, name.length.clamp(0, 160)),
    );
  }
}

class _PaneRecord {
  _PaneRecord(
    this.windowId,
    this.id,
    this.width,
    this.height,
    this.x,
    this.y,
    this.active,
  );
  final String windowId, id;
  final int width, height, x, y;
  final bool active;
  factory _PaneRecord.parse(String value) {
    final match = RegExp(
      r'^(@[0-9]{1,10}) (%[0-9]{1,10}) ([0-9]{1,4}) ([0-9]{1,4}) ([0-9]{1,4}) ([0-9]{1,4}) ([01])$',
    ).firstMatch(value);
    if (match == null) {
      throw const TmuxControlProtocolException('Invalid pane metadata.');
    }
    final width = int.parse(match[3]!);
    final height = int.parse(match[4]!);
    TmuxControlClient._checkDimensions(width, height);
    return _PaneRecord(
      match[1]!,
      match[2]!,
      width,
      height,
      int.parse(match[5]!),
      int.parse(match[6]!),
      match[7] == '1',
    );
  }
}
