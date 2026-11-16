import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm2/xterm.dart';

import '../l10n/terminal_controls_strings.dart';
import '../l10n/terminal_search_strings.dart';
import '../l10n/terminal_strings.dart';
import '../l10n/tmux_control_strings.dart';
import '../providers/focus_area_provider.dart';
import '../providers/keyboard_shortcut_provider.dart';
import '../providers/terminal_key_bindings_provider.dart';
import '../providers/terminal_provider.dart';
import '../providers/terminal_triggers_provider.dart';
import '../services/keyboard_shortcut_service.dart';
import '../services/terminal_session.dart';
import '../services/terminal_user_input.dart';
import '../services/tmux_control_client.dart';
import 'terminal_search_bar.dart';

/// Native views for one tmux control client. The client owns the remote
/// windows, pane emulators and transport; this widget owns only view state.
///
/// Remote cell geometry remains authoritative. In particular, hiding a window,
/// temporarily zooming a pane, or falling back to the active pane on a small
/// display does not resize individual remote panes or close their processes.
class TmuxControlWorkspace extends ConsumerStatefulWidget {
  const TmuxControlWorkspace({
    super.key,
    required this.client,
    this.visible = true,
    this.active = true,
    this.fontSize = 13,
    this.focusRequest = 0,
    this.onActivate,
    this.onDetach,
    this.onPaneFocusChanged,
    this.onWorkspaceKey,
    this.onFontSizeChanged,
  });

  final TmuxControlClient client;
  final bool visible;
  final bool active;
  final double fontSize;
  final int focusRequest;
  final VoidCallback? onActivate;
  final VoidCallback? onDetach;
  final ValueChanged<bool>? onPaneFocusChanged;
  final KeyEventResult Function(KeyEvent event)? onWorkspaceKey;
  final ValueChanged<double>? onFontSizeChanged;

  @override
  ConsumerState<TmuxControlWorkspace> createState() =>
      _TmuxControlWorkspaceState();
}

enum _TmuxAction {
  newWindow,
  previousPane,
  nextPane,
  splitHorizontal,
  splitVertical,
  zoom,
  copy,
  paste,
  find,
  detach,
}

class _PaneView {
  _PaneView(
    this.session,
    VoidCallback onFocus,
    VoidCallback onSelection,
    this.onSession,
  ) {
    focus.addListener(onFocus);
    controller.addListener(onSelection);
    session.addListener(onSession);
  }

  final TerminalSession session;
  final VoidCallback onSession;
  int triggerSerial = 0;
  final focus = FocusNode(debugLabel: 'tmux pane input');
  final controller = TerminalController();
  final scroll = ScrollController();
  final key = GlobalKey<TerminalViewState>();

  void dispose() {
    session.removeListener(onSession);
    focus.dispose();
    controller.dispose();
    scroll.dispose();
  }
}

class _TmuxControlWorkspaceState extends ConsumerState<TmuxControlWorkspace> {
  final _views = <String, _PaneView>{};
  final _retiringViews = <_PaneView>{};
  bool _zoomed = false;
  bool _showSearch = false;
  bool _busy = false;
  String? _actionError;
  String? _lastActivePane;
  String? _retainedWindowId;
  final _retainedPaneIds = <String, String>{};
  bool _reportedFocus = false;
  bool _focusScheduled = false;
  int _searchFocusRequest = 0;
  int _inputLease = 0;
  bool _triggerNoticeScheduled = false;
  (TerminalSession, Object, String)? _triggerNotice;
  Timer? _resizeTimer;
  (int, int)? _pendingResize;
  (int, int)? _lastResize;

  bool get _enabled =>
      widget.visible &&
      widget.active &&
      widget.client.ready &&
      !widget.client.isClosed;

  // Once the transport closes, browsing retained buffers is entirely local.
  // Never mutate the client's last remote selection or send select commands.
  String? get _selectedWindowId => widget.client.isClosed
      ? _retainedWindowId ?? widget.client.activeWindowId
      : widget.client.activeWindowId;

  String? get _selectedPaneId {
    if (!widget.client.isClosed) return widget.client.activePaneId;
    final windowId = _selectedWindowId;
    final retained = _retainedPaneIds[windowId];
    if (retained != null) return retained;
    if (windowId == widget.client.activeWindowId) {
      return widget.client.activePaneId;
    }
    for (final window in widget.client.windows) {
      if (window.id == windowId) return window.activePaneId;
    }
    return null;
  }

  _PaneView? get _activeView => _views[_selectedPaneId];

  List<String> get _windowPaneIds => [
    for (final pane in widget.client.panes.values)
      if (pane.windowId == _selectedWindowId) pane.id,
  ];

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_clientChanged);
    _syncViews();
    _scheduleFocus();
  }

  @override
  void didUpdateWidget(TmuxControlWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client)) {
      oldWidget.client.removeListener(_clientChanged);
      _inputLease++;
      _cancelResize();
      _lastResize = null;
      _busy = false;
      _actionError = null;
      _zoomed = false;
      _showSearch = false;
      _retainedWindowId = null;
      _retainedPaneIds.clear();
      _retireAllViews();
      widget.client.addListener(_clientChanged);
      _syncViews();
    }
    if (!widget.visible || !widget.active) {
      _inputLease++;
      _unfocusAll();
      _cancelResize();
    } else if (!oldWidget.visible ||
        !oldWidget.active ||
        oldWidget.focusRequest != widget.focusRequest ||
        !identical(oldWidget.client, widget.client)) {
      _scheduleFocus();
    }
  }

  void _syncViews() {
    final panes = widget.client.panes;
    for (final id in _views.keys.toList()) {
      if (!identical(panes[id]?.session, _views[id]!.session)) {
        _retire(_views.remove(id)!);
      }
    }
    for (final entry in panes.entries) {
      _views.putIfAbsent(
        entry.key,
        () => _PaneView(
          entry.value.session,
          _focusChanged,
          _selectionChanged,
          () => _paneSessionChanged(entry.key),
        ),
      );
      _updatePointerPolicy(_views[entry.key]!);
    }
    final active = _selectedPaneId;
    if (_lastActivePane != active) {
      _inputLease++;
      _lastActivePane = active;
      for (final entry in _views.entries) {
        if (entry.key != active) entry.value.focus.unfocus();
      }
      _scheduleFocus();
    }
  }

  void _clientChanged() {
    if (!mounted) return;
    _syncViews();
    if (!widget.client.ready || widget.client.isClosed) {
      if (widget.client.isClosed) _busy = false;
      _inputLease++;
      _unfocusAll();
      _cancelResize();
    }
    setState(() {});
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  void _updatePointerPolicy(_PaneView view) {
    // xterm's readOnly flag does not suppress wheel reports. Suspending the
    // controller's pointer input makes mouse-enabled retained buffers scroll
    // locally as well, without reporting gestures to a closed connection.
    final suspended = widget.client.isClosed || !view.session.isConnected;
    if (view.controller.suspendedPointerInputs != suspended) {
      view.controller.setSuspendPointerInput(suspended);
    }
  }

  void _paneSessionChanged(String id) {
    if (!mounted) return;
    final view = _views[id];
    if (view == null) return;
    _updatePointerPolicy(view);
    final session = view.session;
    if (view.triggerSerial != session.triggerNotificationSerial) {
      view.triggerSerial = session.triggerNotificationSerial;
      final match = session.triggerNotification;
      if (match != null) {
        final line = match.line.length > 160
            ? '${match.line.substring(0, 160)}…'
            : match.line;
        _triggerNotice = (
          session,
          session.connectionIdentity,
          '$id · ${match.trigger.name} · $line',
        );
        if (!_triggerNoticeScheduled) {
          _triggerNoticeScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _triggerNoticeScheduled = false;
            final notice = _triggerNotice;
            _triggerNotice = null;
            if (!mounted ||
                notice == null ||
                !identical(notice.$1.connectionIdentity, notice.$2) ||
                !_views.values.any(
                  (view) => identical(view.session, notice.$1),
                )) {
              return;
            }
            final messenger = ScaffoldMessenger.maybeOf(context);
            messenger?.hideCurrentSnackBar();
            messenger?.showSnackBar(SnackBar(content: Text(notice.$3)));
          });
        }
      }
    }
    setState(() {});
  }

  void _focusChanged() {
    final focused =
        _enabled &&
        ref.read(focusAreaProvider) == FocusArea.terminal &&
        (_activeView?.focus.hasFocus ?? false);
    if (focused == _reportedFocus) return;
    _reportedFocus = focused;
    widget.onPaneFocusChanged?.call(focused);
  }

  void _unfocusAll() {
    for (final view in _views.values) {
      view.focus.unfocus();
    }
    if (_reportedFocus) {
      _reportedFocus = false;
      widget.onPaneFocusChanged?.call(false);
    }
  }

  void _scheduleFocus() {
    if (_focusScheduled) return;
    _focusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScheduled = false;
      if (!mounted ||
          !_enabled ||
          _busy ||
          _showSearch ||
          ref.read(focusAreaProvider) != FocusArea.terminal) {
        return;
      }
      _activeView?.focus.requestFocus();
    });
  }

  void _retire(_PaneView view) {
    view.focus.unfocus();
    _retiringViews.add(view);
    // A removed pane may still have a mounted TerminalView until this frame
    // finishes. Dispose view resources after the child has detached them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_retiringViews.remove(view)) view.dispose();
    });
  }

  void _retireAllViews() {
    for (final view in _views.values) {
      _retire(view);
    }
    _views.clear();
  }

  Future<void> _command(
    Future<void> Function() action, {
    bool changesSelection = false,
  }) async {
    if (!widget.visible ||
        _busy ||
        !widget.client.ready ||
        widget.client.isClosed) {
      return;
    }
    widget.onActivate?.call();
    final client = widget.client;
    if (changesSelection) {
      _inputLease++;
      _unfocusAll();
    }
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted && identical(client, widget.client)) {
        _actionError = 'The tmux action could not be completed.';
      }
    } finally {
      if (mounted && identical(client, widget.client)) {
        setState(() => _busy = false);
        _scheduleFocus();
      }
    }
  }

  void _selectPane(String id) {
    if (!widget.visible || _busy || !widget.client.panes.containsKey(id)) {
      return;
    }
    widget.onActivate?.call();
    if (_selectedPaneId == id) {
      _scheduleFocus();
    } else if (widget.client.isClosed) {
      _inputLease++;
      _unfocusAll();
      setState(() {
        final windowId = widget.client.panes[id]!.windowId;
        _retainedWindowId = windowId;
        _retainedPaneIds[windowId] = id;
      });
    } else {
      unawaited(
        _command(() => widget.client.selectPane(id), changesSelection: true),
      );
    }
  }

  void _selectWindow(String id) {
    if (!widget.visible ||
        _busy ||
        !widget.client.windows.any((window) => window.id == id)) {
      return;
    }
    widget.onActivate?.call();
    if (_selectedWindowId == id) {
      _scheduleFocus();
      return;
    }
    if (widget.client.isClosed) {
      _inputLease++;
      _unfocusAll();
      setState(() => _retainedWindowId = id);
      return;
    }
    unawaited(
      _command(() => widget.client.selectWindow(id), changesSelection: true),
    );
  }

  void _toggleZoom() {
    widget.onActivate?.call();
    setState(() => _zoomed = !_zoomed);
    _scheduleFocus();
  }

  void _openSearch() {
    widget.onActivate?.call();
    _inputLease++;
    _activeView?.focus.unfocus();
    setState(() {
      _showSearch = true;
      _searchFocusRequest++;
    });
  }

  void _closeSearch() {
    setState(() => _showSearch = false);
    _scheduleFocus();
  }

  Future<void> _copyText(String text) async {
    if (widget.visible && text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<void> _copySelection() async {
    final view = _activeView;
    if (view == null || !widget.visible) return;
    final terminal = view.session.terminal;
    final selection = view.controller.selectionFor(terminal.buffer);
    if (selection != null) {
      await _copyText(terminal.buffer.getText(selection, true));
    }
  }

  Future<void> _paste() async {
    final view = _activeView;
    if (view == null || !_enabled || _busy || !view.session.isConnected) return;
    widget.onActivate?.call();
    view.focus.requestFocus();
    final client = widget.client;
    final paneId = client.activePaneId;
    final terminal = view.session.terminal;
    final lease = _inputLease;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted ||
        !_enabled ||
        _busy ||
        lease != _inputLease ||
        !identical(client, widget.client) ||
        client.activePaneId != paneId ||
        !identical(view, _activeView) ||
        !identical(terminal, view.session.terminal) ||
        !view.session.isConnected ||
        !view.focus.hasFocus ||
        ref.read(focusAreaProvider) != FocusArea.terminal) {
      return;
    }
    if (data?.text case final text?) {
      terminal.paste(text);
      view.controller.clearSelection();
      if (view.scroll.hasClients) {
        view.scroll.jumpTo(view.scroll.position.maxScrollExtent);
      }
    }
  }

  KeyEventResult _onKey(String id, KeyEvent event) {
    final mappedPresses = ref.read(terminalKeyBindingPressesProvider);
    if (event is KeyDownEvent) {
      mappedPresses.remove(event.physicalKey);
    } else if (mappedPresses.contains(event.physicalKey)) {
      if (event is KeyUpEvent) mappedPresses.remove(event.physicalKey);
      return KeyEventResult.handled;
    }
    final view = _views[id];
    if (!_enabled ||
        _busy ||
        id != widget.client.activePaneId ||
        view == null ||
        !view.focus.hasFocus ||
        ref.read(focusAreaProvider) != FocusArea.terminal ||
        !view.session.isConnected) {
      return KeyEventResult.handled;
    }
    final workspace = widget.onWorkspaceKey?.call(event);
    if (workspace != null && workspace != KeyEventResult.ignored) {
      return workspace;
    }
    final keyboard = HardwareKeyboard.instance;
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final command =
        !keyboard.isAltPressed &&
        (apple
            ? keyboard.isMetaPressed && !keyboard.isControlPressed
            : keyboard.isControlPressed &&
                  keyboard.isShiftPressed &&
                  !keyboard.isMetaPressed);
    if (command) {
      final fontSize = switch (event.logicalKey) {
        LogicalKeyboardKey.equal ||
        LogicalKeyboardKey.add ||
        LogicalKeyboardKey.numpadAdd => widget.fontSize + 1,
        LogicalKeyboardKey.minus ||
        LogicalKeyboardKey.numpadSubtract => widget.fontSize - 1,
        LogicalKeyboardKey.digit0 || LogicalKeyboardKey.numpad0 => 13.0,
        _ => null,
      };
      if (fontSize != null) {
        if (event is KeyDownEvent) {
          widget.onFontSizeChanged?.call(fontSize.clamp(8.0, 32.0));
        }
        return KeyEventResult.handled;
      }
      final action = switch (event.logicalKey) {
        LogicalKeyboardKey.keyC => _TmuxAction.copy,
        LogicalKeyboardKey.keyV => _TmuxAction.paste,
        LogicalKeyboardKey.keyF => _TmuxAction.find,
        _ => null,
      };
      if (action != null) {
        if (event is KeyDownEvent) _action(action);
        return KeyEventResult.handled;
      }
    }
    final shortcut = ref
        .read(keyboardShortcutServiceProvider)
        .resolveBrowser(
          event,
          isCtrl: keyboard.isControlPressed,
          isMeta: keyboard.isMetaPressed,
          isShift: keyboard.isShiftPressed,
          isAlt: keyboard.isAltPressed,
        );
    if (shortcut == ShortcutAction.terminal) {
      setTerminalVisible(ref, false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC &&
        keyboard.isControlPressed &&
        !keyboard.isShiftPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      view.session.terminal.keyInput(
        TerminalKey.keyC,
        ctrl: true,
        text: 'c',
        type: switch (event) {
          KeyUpEvent() => TerminalKeyEventType.release,
          KeyRepeatEvent() => TerminalKeyEventType.repeat,
          _ => TerminalKeyEventType.press,
        },
      );
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        !event.synthesized &&
        ref.read(focusAreaProvider) == FocusArea.terminal) {
      final mappings = ref.read(terminalKeyBindingListProvider);
      if (!mappings.isLoading && !mappings.hasError) {
        for (final binding in mappings.valueOrNull ?? const []) {
          if (!binding.enabled ||
              binding.chord.isReserved(apple: apple) ||
              !binding.chord.matches(
                event,
                ctrl: keyboard.isControlPressed,
                alt: keyboard.isAltPressed,
                shift: keyboard.isShiftPressed,
                meta: keyboard.isMetaPressed,
              )) {
            continue;
          }
          mappedPresses.add(event.physicalKey);
          final terminal = view.session.terminal;
          if (terminal is InputAwareTerminal) {
            terminal.submitUserInput(binding.input);
          } else {
            binding.input.applyTo(terminal);
          }
          view.controller.clearSelection();
          if (view.scroll.hasClients) {
            view.scroll.jumpTo(view.scroll.position.maxScrollExtent);
          }
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _action(_TmuxAction action) {
    final pane = _selectedPaneId;
    switch (action) {
      case _TmuxAction.newWindow:
        unawaited(_command(widget.client.newWindow, changesSelection: true));
      case _TmuxAction.previousPane:
      case _TmuxAction.nextPane:
        final panes = _windowPaneIds;
        if (panes.length > 1 && pane != null) {
          final step = action == _TmuxAction.nextPane ? 1 : -1;
          _selectPane(panes[(panes.indexOf(pane) + step) % panes.length]);
        }
      case _TmuxAction.splitHorizontal:
      case _TmuxAction.splitVertical:
        if (pane != null) {
          unawaited(
            _command(
              () => widget.client.splitPane(
                pane,
                horizontal: action == _TmuxAction.splitHorizontal,
              ),
              changesSelection: true,
            ),
          );
        }
      case _TmuxAction.zoom:
        _toggleZoom();
      case _TmuxAction.copy:
        unawaited(_copySelection());
      case _TmuxAction.paste:
        unawaited(_paste());
      case _TmuxAction.find:
        _openSearch();
      case _TmuxAction.detach:
        _inputLease++;
        _unfocusAll();
        if (widget.onDetach case final detach?) {
          detach();
        } else {
          unawaited(widget.client.detach());
        }
    }
  }

  void _cancelResize() {
    _resizeTimer?.cancel();
    _resizeTimer = null;
    _pendingResize = null;
  }

  void _queueResize(Size size, Size cell) {
    if (!_enabled || size.width <= 0 || size.height <= 0) return;
    final next = (
      (size.width / cell.width).floor().clamp(20, 500),
      (size.height / cell.height).floor().clamp(5, 200),
    );
    if (next == _lastResize) {
      // A quick A -> B -> A drag supersedes the pending B resize even though
      // the final dimensions need no new command. Letting its timer survive
      // would leave tmux at an obsolete size after the viewport has settled.
      _cancelResize();
      return;
    }
    if (next == _pendingResize) return;
    _resizeTimer?.cancel();
    _pendingResize = next;
    final client = widget.client;
    _resizeTimer = Timer(const Duration(milliseconds: 180), () async {
      _resizeTimer = null;
      _pendingResize = null;
      if (!mounted || !_enabled || !identical(client, widget.client)) return;
      _lastResize = next;
      try {
        await client.resize(next.$1, next.$2);
      } catch (_) {
        if (mounted && identical(client, widget.client) && !client.isClosed) {
          setState(
            () => _actionError = 'The tmux action could not be completed.',
          );
        }
      }
    });
  }

  String _actionLabel(_TmuxAction action) => switch (action) {
    _TmuxAction.newWindow => context.tmuxControlTr('New tmux window'),
    _TmuxAction.previousPane => context.terminalControlsTr('Previous pane'),
    _TmuxAction.nextPane => context.terminalControlsTr('Next pane'),
    _TmuxAction.splitHorizontal => context.terminalControlsTr(
      'Split side by side',
    ),
    _TmuxAction.splitVertical => context.terminalControlsTr(
      'Split top and bottom',
    ),
    _TmuxAction.zoom => context.terminalControlsTr(
      _zoomed ? 'Restore panes' : 'Zoom active pane',
    ),
    _TmuxAction.copy => context.terminalTr('Copy selection'),
    _TmuxAction.paste => context.terminalTr('Paste'),
    _TmuxAction.find => context.terminalSearchTr('Find in terminal'),
    _TmuxAction.detach => context.terminalTr('Detach from tmux'),
  };

  bool _actionEnabled(_TmuxAction action) {
    if (!widget.visible) return false;
    final view = _activeView;
    if (action == _TmuxAction.detach) return !widget.client.isClosed;
    if (action == _TmuxAction.copy) {
      return view != null &&
          view.controller.selectionFor(view.session.terminal.buffer) != null;
    }
    if (action == _TmuxAction.find || action == _TmuxAction.zoom) {
      return view != null;
    }
    if (action == _TmuxAction.paste && view?.session.isConnected != true) {
      return false;
    }
    if (action == _TmuxAction.previousPane || action == _TmuxAction.nextPane) {
      return _windowPaneIds.length > 1 &&
          !_busy &&
          (widget.client.ready || widget.client.isClosed);
    }
    return widget.client.ready && !widget.client.isClosed && !_busy;
  }

  Widget _button(_TmuxAction action, IconData icon) => IconButton(
    key: ValueKey('tmux-action-${action.name}'),
    tooltip: _actionLabel(action),
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
    padding: const EdgeInsets.all(6),
    icon: Icon(icon, size: 19),
    onPressed: _actionEnabled(action) ? () => _action(action) : null,
  );

  Widget _header() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('tmux-window-tabs'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final window in widget.client.windows)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Semantics(
                      selected: window.id == _selectedWindowId,
                      child: TextButton(
                        key: ValueKey('tmux-window-${window.id}'),
                        onPressed:
                            !_busy &&
                                widget.visible &&
                                (widget.client.ready || widget.client.isClosed)
                            ? () => _selectWindow(window.id)
                            : null,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(40, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          backgroundColor: window.id == _selectedWindowId
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            '${window.index}: ${window.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _button(_TmuxAction.newWindow, Icons.add),
        PopupMenuButton<_TmuxAction>(
          key: const ValueKey('tmux-actions'),
          tooltip: context.tmuxControlTr('tmux actions'),
          onSelected: _action,
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_vert, size: 20),
          itemBuilder: (_) => [
            for (final action in _TmuxAction.values)
              PopupMenuItem(
                value: action,
                enabled: _actionEnabled(action),
                child: Text(_actionLabel(action)),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _toolbar(List<String> paneIds) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: PopupMenuButton<String>(
                key: const ValueKey('tmux-pane-selector'),
                tooltip: context.tmuxControlTr('Select tmux pane'),
                enabled:
                    paneIds.isNotEmpty &&
                    !_busy &&
                    widget.visible &&
                    (widget.client.ready || widget.client.isClosed),
                onSelected: _selectPane,
                itemBuilder: (_) => [
                  for (final id in paneIds)
                    CheckedPopupMenuItem(
                      value: id,
                      checked: id == _selectedPaneId,
                      child: Text(
                        context
                            .tmuxControlTr('Pane {id}')
                            .replaceAll('{id}', id),
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          context
                              .tmuxControlTr('Pane {id}')
                              .replaceAll('{id}', _selectedPaneId ?? '—'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (constraints.maxWidth >= 300) ...[
            _button(_TmuxAction.splitHorizontal, Icons.vertical_split_outlined),
            _button(_TmuxAction.splitVertical, Icons.horizontal_split_outlined),
          ],
          if (constraints.maxWidth >= 130) ...[
            _button(
              _TmuxAction.zoom,
              _zoomed ? Icons.close_fullscreen : Icons.open_in_full,
            ),
            _button(_TmuxAction.find, Icons.search),
          ],
          if (constraints.maxWidth >= 260) ...[
            _button(_TmuxAction.copy, Icons.copy_outlined),
            _button(_TmuxAction.paste, Icons.paste_outlined),
          ],
        ],
      ),
    ),
  );

  Widget _pane(String id, {required bool selected}) {
    final view = _views[id]!;
    final canInteract = widget.visible && widget.active && selected && !_busy;
    final canInput = _enabled && selected && !_busy && view.session.isConnected;
    return Semantics(
      label: context.tmuxControlTr('Pane {id}').replaceAll('{id}', id),
      selected: selected,
      child: Stack(
        key: ValueKey('tmux-pane-$id'),
        children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !canInteract,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _selectPane(id),
                child: ExcludeFocus(
                  excluding: !canInput,
                  child: TerminalView(
                    view.session.terminal,
                    key: view.key,
                    controller: view.controller,
                    focusNode: view.focus,
                    scrollController: view.scroll,
                    autoResize: false,
                    autofocus: false,
                    readOnly: !canInput,
                    simulateScroll: canInput,
                    deleteDetection:
                        !kIsWeb &&
                        (defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.iOS),
                    keyboardType: TextInputType.multiline,
                    keyboardAppearance: Brightness.dark,
                    textStyle: TerminalStyle(
                      fontFamily: 'AppMono',
                      fontSize: widget.fontSize,
                    ),
                    padding: EdgeInsets.zero,
                    shiftOverridesMouseReporting: true,
                    dragOverridesMouseReporting:
                        !kIsWeb &&
                        (defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.iOS),
                    onCopy: _copyText,
                    onPaste: _paste,
                    onKeyEvent: (_, event) => _onKey(id, event),
                  ),
                ),
              ),
            ),
          ),
          if (!canInteract)
            Positioned.fill(
              child: GestureDetector(
                key: ValueKey('tmux-activate-$id'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.visible && !_busy ? () => _selectPane(id) : null,
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: selected ? 2 : 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    List<String> paneIds,
    int windowWidth,
    int windowHeight,
    Size cell,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      _queueResize(size, cell);
      if (paneIds.isEmpty || _activeView == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              context.tmuxControlTr(
                widget.client.isClosed
                    ? 'tmux connection closed'
                    : 'Loading tmux windows…',
              ),
              style: const TextStyle(color: Color(0xffcccccc)),
            ),
          ),
        );
      }
      final compact = paneIds.any((id) {
        final pane = widget.client.panes[id]!;
        return size.width * pane.width / windowWidth < 180 ||
            size.height * pane.height / windowHeight < 72;
      });
      final active = _selectedPaneId!;
      if (_zoomed || compact || !paneIds.contains(active)) {
        return KeyedSubtree(
          key: const ValueKey('tmux-single-pane-view'),
          child: _pane(active, selected: true),
        );
      }
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          for (final id in paneIds)
            Positioned(
              left: size.width * widget.client.panes[id]!.x / windowWidth,
              top: size.height * widget.client.panes[id]!.y / windowHeight,
              width: size.width * widget.client.panes[id]!.width / windowWidth,
              height:
                  size.height * widget.client.panes[id]!.height / windowHeight,
              child: _pane(id, selected: id == active),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(terminalKeyBindingListProvider);
    final ownsKeyboard = ref.watch(focusAreaProvider) == FocusArea.terminal;
    final triggers =
        ref.watch(terminalTriggerListProvider).valueOrNull ?? const [];
    for (final view in _views.values) {
      view.session.updateTriggers(triggers);
    }
    final windows = widget.client.windows.where(
      (window) => window.id == _selectedWindowId,
    );
    final window = windows.isEmpty ? null : windows.first;
    final paneIds =
        window?.paneIds.where((id) => _views.containsKey(id)).toList() ??
        <String>[];
    final view = _activeView;
    final paneError = view?.session.error;
    final errorMessage = paneError != null
        ? context.tmuxControlTr('Pane failed. Reconnect to continue.')
        : _actionError == null
        ? null
        : context.tmuxControlTr(_actionError!);
    final painter = TextPainter(
      text: TextSpan(
        text: 'M',
        style: TerminalStyle(
          fontFamily: 'AppMono',
          fontSize: widget.fontSize,
        ).toTextStyle(),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final cell = Size(math.max(1, painter.width), math.max(1, painter.height));
    painter.dispose();
    return ExcludeFocus(
      excluding: !widget.active || !widget.visible || !ownsKeyboard,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, __) => KeyEventResult.skipRemainingHandlers,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final toolbar = constraints.maxHeight >= 130;
            final search =
                _showSearch && view != null && constraints.maxHeight >= 180;
            return ColoredBox(
              color: const Color(0xff1e1e1e),
              child: Column(
                children: [
                  SizedBox(
                    height: math.min(36, constraints.maxHeight),
                    child: _header(),
                  ),
                  if (toolbar)
                    SizedBox(height: 36, child: _toolbar(_windowPaneIds)),
                  if (search)
                    TerminalSearchBar(
                      key: const ValueKey('tmux-search'),
                      terminal: view.session.terminal,
                      controller: view.controller,
                      scrollController: view.scroll,
                      lineHeight: () =>
                          view.key.currentState?.renderTerminal.lineHeight ??
                          cell.height,
                      active: widget.visible && widget.active && ownsKeyboard,
                      autofocus: true,
                      focusRequest: widget.focusRequest + _searchFocusRequest,
                      onActivate: widget.onActivate,
                      onWorkspaceKey: widget.onWorkspaceKey,
                      onClose: _closeSearch,
                    ),
                  if (errorMessage != null && constraints.maxHeight >= 130)
                    Tooltip(
                      message: paneError == null
                          ? errorMessage
                          : '$errorMessage\n$paneError',
                      child: Semantics(
                        liveRegion: true,
                        child: Material(
                          key: const ValueKey('tmux-error'),
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: SizedBox(
                            height: paneError == null ? 32 : 48,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      errorMessage,
                                      maxLines: paneError == null ? 1 : 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (paneError == null)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () =>
                                        setState(() => _actionError = null),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: _body(
                      paneIds,
                      math.max(1, window?.width ?? 80),
                      math.max(1, window?.height ?? 24),
                      cell,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inputLease++;
    _cancelResize();
    widget.client.removeListener(_clientChanged);
    // The parent owns the transport, pane sessions and focus publication.
    // Do not notify its providers during the ancestor's disposal traversal.
    for (final view in _views.values) {
      view.dispose();
    }
    for (final view in _retiringViews) {
      view.dispose();
    }
    _retiringViews.clear();
    super.dispose();
  }
}
