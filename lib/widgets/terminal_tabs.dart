import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/terminal_controls_strings.dart';
import '../l10n/terminal_arrangement_strings.dart';
import '../l10n/terminal_broadcast_strings.dart';
import '../l10n/terminal_strings.dart';
import '../l10n/ssh_connection_sharing_strings.dart';
import '../models/terminal_arrangement.dart';
import '../providers/terminal_provider.dart';
import '../providers/focus_area_provider.dart';
import '../services/terminal_session.dart';
import '../services/terminal_broadcast.dart';
import '../services/terminal_connection.dart';
import 'terminal_panel.dart';
import 'terminal_arrangements_dialog.dart';
import 'terminal_broadcast_dialog.dart';

class _TerminalTab {
  _TerminalTab(
    this.id,
    this.session, {
    required this.owned,
    required this.start,
    this.sharedConnection = false,
    TerminalPaneState? paneState,
    this.name,
  }) : paneState = paneState ?? TerminalPaneState();

  final int id;
  final TerminalSession session;
  final bool owned;
  final bool start;
  final bool sharedConnection;
  final key = GlobalKey();
  String? name;
  TerminalPaneState paneState;
}

class _SharedShellRequest {
  const _SharedShellRequest(this.source, this.opening, this.paneState);

  final _TerminalTab source;
  final TerminalConnectionOpening opening;
  final TerminalPaneState paneState;
}

/// Keeps independent sessions and view state alive while tabs or panes change.
/// Only the active, visible pane can reclaim terminal keyboard focus.
class TerminalTabs extends ConsumerStatefulWidget {
  const TerminalTabs({
    super.key,
    this.session,
    this.visible = true,
    @visibleForTesting this.sessionFactory,
  });

  final TerminalSession? session;
  final bool visible;
  final TerminalSession Function()? sessionFactory;

  static const maxTabs = TerminalArrangement.maxTabs;

  @override
  ConsumerState<TerminalTabs> createState() => _TerminalTabsState();
}

class _TerminalTabsState extends ConsumerState<TerminalTabs> {
  final _tabs = <_TerminalTab>[];
  int _nextId = 1;
  late TerminalPaneLayout _layout;
  late int _active;
  bool _zoomed = false;
  final _lastPaneBounds = <int, Rect>{};
  Map<int, Rect> _visiblePaneBounds = const {};
  bool _closing = false;
  bool _arranging = false;
  int _focusRequest = 0;
  late final TerminalBroadcast _broadcast;
  int _broadcastStopSerial = 0;
  _SharedShellRequest? _sharedShellRequest;

  @override
  void initState() {
    super.initState();
    _broadcast = TerminalBroadcast(
      canSend: (id) =>
          mounted &&
          widget.visible &&
          !_arranging &&
          _active == id &&
          ref.read(focusAreaProvider) == FocusArea.terminal,
    )..addListener(_broadcastChanged);
    final tab = _makeTab(initial: widget.session);
    _active = tab.id;
    _layout = TerminalPaneLeaf(tab.id);
  }

  _TerminalTab _makeTab({
    TerminalSession? initial,
    bool? start,
    bool sharedConnection = false,
    TerminalPaneState? paneState,
  }) {
    final tab = _TerminalTab(
      _nextId++,
      initial ?? widget.sessionFactory?.call() ?? TerminalSession(),
      owned: initial == null,
      start: start ?? (initial == null && widget.sessionFactory == null),
      sharedConnection: sharedConnection,
      paneState: paneState,
    );
    tab.session.addListener(_changed);
    _tabs.add(tab);
    return tab;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _broadcastChanged() {
    if (!mounted) return;
    setState(() {});
    if (_broadcast.stopSerial == _broadcastStopSerial) return;
    _broadcastStopSerial = _broadcast.stopSerial;
    final message = switch (_broadcast.lastStopReason) {
      TerminalBroadcastStopReason.connectionChanged =>
        'Broadcast stopped because a connection changed.',
      TerminalBroadcastStopReason.inputTooLarge =>
        'Broadcast stopped because the input was too large.',
      TerminalBroadcastStopReason.forwardingFailed =>
        'Broadcast stopped because input could not be delivered.',
      _ => null,
    };
    if (message == null) return;
    final serial = _broadcastStopSerial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_broadcast.isArmed && _broadcastStopSerial == serial) {
        _broadcastNotice(message);
      }
    });
  }

  void _broadcastNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.terminalBroadcastTr(message))),
    );
  }

  @override
  void didUpdateWidget(TerminalTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) {
      _broadcast.stop(reason: TerminalBroadcastStopReason.workspaceHidden);
    }
    if (!identical(oldWidget.session, widget.session)) {
      _releaseTabs();
      final tab = _makeTab(initial: widget.session);
      _active = tab.id;
      _layout = TerminalPaneLeaf(tab.id);
      _zoomed = false;
    }
  }

  void _releaseTabs() {
    _broadcast.stop(reason: TerminalBroadcastStopReason.connectionChanged);
    for (final tab in _tabs) {
      tab.session.removeListener(_changed);
      if (tab.owned) tab.session.dispose();
    }
    _tabs.clear();
    _lastPaneBounds.clear();
    _visiblePaneBounds = const {};
  }

  void _activate(int id) {
    if (_arranging) return;
    if (!_tabs.any((tab) => tab.id == id)) return;
    ref.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    setState(() {
      _focusRequest++;
      if (!_layout.contains(id)) {
        _layout = _layout.replaceLeaf(_active, id);
      }
      _active = id;
    });
  }

  void _addTab() {
    if (_arranging || _closing || _tabs.length >= TerminalTabs.maxTabs) return;
    final tab = _makeTab();
    _activate(tab.id);
  }

  void _split(Axis axis) {
    if (_arranging || _closing) return;
    if (_tabs.length >= TerminalTabs.maxTabs) return;
    ref.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    setState(() {
      final tab = _makeTab();
      _layout = _layout.splitLeaf(
        _active,
        tab.id,
        axis == Axis.horizontal
            ? TerminalSplitAxis.horizontal
            : TerminalSplitAxis.vertical,
      );
      _active = tab.id;
      _zoomed = false;
      _focusRequest++;
    });
  }

  void _captureSharedShellRequest() {
    _sharedShellRequest = null;
    if (!widget.visible || _arranging || _closing) return;
    final source = _tabs.firstWhere((tab) => tab.id == _active);
    final opening = source.session.siblingConnectionOpening;
    if (opening == null) return;
    _sharedShellRequest = _SharedShellRequest(
      source,
      opening,
      TerminalPaneState(
        fontSize: source.paneState.fontSize,
        sshConfig: source.paneState.sshConfig?.forSharedShell(),
      ),
    );
  }

  Future<void> _openSharedShell({Axis? split}) async {
    final request = _sharedShellRequest;
    _sharedShellRequest = null;
    if (request == null ||
        !mounted ||
        !widget.visible ||
        _arranging ||
        _closing ||
        _tabs.length >= TerminalTabs.maxTabs ||
        !_tabs.contains(request.source) ||
        request.source.id != _active) {
      return;
    }
    ref.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    late final _TerminalTab tab;
    setState(() {
      tab = _makeTab(
        start: false,
        sharedConnection: true,
        paneState: request.paneState,
      );
      _layout = split == null
          ? _layout.replaceLeaf(_active, tab.id)
          : _layout.splitLeaf(
              _active,
              tab.id,
              split == Axis.horizontal
                  ? TerminalSplitAxis.horizontal
                  : TerminalSplitAxis.vertical,
            );
      _active = tab.id;
      _zoomed = false;
      _focusRequest++;
    });
    final config = request.paneState.sshConfig;
    // This factory is bound to the source connection captured when the menu
    // opened. The destination session owns any late result after cancellation.
    await tab.session.connectOpening(
      request.opening,
      kind: TerminalSessionKind.ssh,
      label: config == null
          ? context.sshSharingTr('New SSH shell')
          : '${config.username}@${config.host}',
    );
  }

  void _singlePane() {
    if (_arranging || _closing) return;
    setState(() {
      _layout = TerminalPaneLeaf(_active);
      _zoomed = false;
      _focusRequest++;
    });
  }

  void _toggleZoom() {
    if (_arranging || _closing || _layout.leafIds.length < 2) return;
    setState(() {
      _zoomed = !_zoomed;
      _focusRequest++;
    });
  }

  void _cyclePane(int step) {
    final ids = _layout.leafIds;
    if (ids.length < 2) return;
    _activate(ids[(ids.indexOf(_active) + step) % ids.length]);
  }

  void _navigatePane(LogicalKeyboardKey direction) {
    final current = _visiblePaneBounds[_active];
    if (current == null || _visiblePaneBounds.length < 2) {
      // Zoom and compact layouts keep the full pane order available.
      _cyclePane(
        direction == LogicalKeyboardKey.arrowLeft ||
                direction == LogicalKeyboardKey.arrowUp
            ? -1
            : 1,
      );
      return;
    }
    final horizontal =
        direction == LogicalKeyboardKey.arrowLeft ||
        direction == LogicalKeyboardKey.arrowRight;
    final positive =
        direction == LogicalKeyboardKey.arrowRight ||
        direction == LogicalKeyboardKey.arrowDown;
    int? next;
    var nearest = double.infinity;
    for (final entry in _visiblePaneBounds.entries) {
      if (entry.key == _active) continue;
      final delta = entry.value.center - current.center;
      final along = horizontal ? delta.dx : delta.dy;
      if (positive ? along <= 0 : along >= 0) continue;
      final across = horizontal ? delta.dy.abs() : delta.dx.abs();
      final score = along.abs() + across * 2;
      if (score < nearest) {
        next = entry.key;
        nearest = score;
      }
    }
    if (next != null) _activate(next);
  }

  String _label(_TerminalTab tab) {
    final destination = tab.paneState.sshConfig;
    return tab.name ??
        tab.session.label ??
        (destination == null
            ? '${context.terminalTr('Terminal')} ${tab.id}'
            : '${destination.username}@${destination.host}');
  }

  Future<void> _rename(_TerminalTab tab) async {
    if (_arranging || _closing) return;
    var edited = _label(tab);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.terminalControlsTr('Rename terminal')),
        content: TextFormField(
          key: const ValueKey('terminal-tab-name'),
          initialValue: edited,
          onChanged: (value) => edited = value,
          autofocus: true,
          maxLength: 60,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1f\x7f]')),
          ],
          onFieldSubmitted: (text) => Navigator.pop(context, text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.terminalTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, edited),
            child: Text(context.terminalControlsTr('Rename')),
          ),
        ],
      ),
    );
    if (!mounted || name == null || !_tabs.contains(tab)) return;
    setState(() => tab.name = name.trim().isEmpty ? null : name.trim());
  }

  Future<void> _closeTab(_TerminalTab tab) async {
    if (_closing || _arranging || _tabs.length <= 1) return;
    _closing = true;
    try {
      if (tab.session.canDisconnect) {
        final close = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.terminalControlsTr('Close terminal?')),
            content: Text(
              tab.session.sharedConnectionSessionCount > 1
                  ? context.sshSharingTr(
                      'Closing releases this terminal. Other terminals keep the SSH connection, port forwards and permitted agent access until the last terminal closes.',
                    )
                  : context.terminalControlsTr(
                      'Closing ends this connection. Use tmux or screen to keep remote work running.',
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.terminalTr('Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.terminalControlsTr('Close terminal')),
              ),
            ],
          ),
        );
        if (close != true) return;
      }
      if (!mounted || !_tabs.contains(tab)) return;
      _broadcast.stop(reason: TerminalBroadcastStopReason.tabClosed);
      await tab.session.disconnect();
      if (!mounted || !_tabs.contains(tab)) return;
      // Failed cleanup leaves the tab available to retry disconnect.
      if (tab.session.canDisconnect) return;
      tab.session.removeListener(_changed);
      setState(() {
        _tabs.remove(tab);
        _layout =
            _layout.removeLeaf(tab.id) ?? TerminalPaneLeaf(_tabs.first.id);
        if (_active == tab.id) _active = _layout.leafIds.first;
        if (_layout.leafIds.length == 1) _zoomed = false;
        _lastPaneBounds.remove(tab.id);
        _focusRequest++;
      });
      if (tab.owned) tab.session.dispose();
    } finally {
      _closing = false;
    }
  }

  void _moveTab(int direction) {
    if (_arranging || _closing) return;
    final index = _tabs.indexWhere((tab) => tab.id == _active);
    final target = index + direction;
    if (target < 0 || target >= _tabs.length) return;
    setState(() {
      final tab = _tabs.removeAt(index);
      _tabs.insert(target, tab);
    });
  }

  TerminalArrangement _captureArrangement(String name) => TerminalArrangement(
    name: name,
    tabs: [
      for (final tab in _tabs)
        TerminalArrangementTab(name: tab.name, paneState: tab.paneState),
    ],
    activeIndex: _tabs.indexWhere((tab) => tab.id == _active),
    layout: _layout.mapIds((id) => _tabs.indexWhere((tab) => tab.id == id)),
  );

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.terminalArrangementTr(message))),
    );
  }

  Future<void> _saveArrangement() async {
    if (_arranging || _closing) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          SaveTerminalArrangementDialog(createArrangement: _captureArrangement),
    );
    if (saved == true) _notice('Saved arrangement');
  }

  Future<void> _chooseArrangement() async {
    if (_arranging || _closing) return;
    final arrangement = await showDialog<TerminalArrangement>(
      context: context,
      builder: (_) => const TerminalArrangementsDialog(),
    );
    if (!mounted || arrangement == null || _arranging || _closing) return;
    await _restoreArrangement(arrangement);
  }

  Future<void> _restoreArrangement(TerminalArrangement arrangement) async {
    final previous = _tabs.toList();
    setState(() => _arranging = true);
    try {
      // Replacing disconnected tabs also discards their scrollback, so every
      // restoration requires an explicit choice, even without a live shell.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            context.terminalArrangementTr('Replace current terminals?'),
          ),
          content: Text(
            context.terminalArrangementTr(
              'Restoring ends the current connections. New tabs open disconnected; reconnect each destination when ready.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.terminalTr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.terminalArrangementTr('Restore')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !listEquals(previous, _tabs)) {
        return;
      }
      _broadcast.stop(reason: TerminalBroadcastStopReason.arrangementRestored);
      // An opener may still be creating a native process/SSH connection. Keep
      // its pane until it settles so a delayed cleanup failure stays visible.
      if (previous.any((tab) => tab.session.isConnecting)) {
        _notice('Could not restore arrangement. All existing tabs were kept.');
        return;
      }
      for (final tab in previous) {
        await tab.session.disconnect();
        if (!mounted || !listEquals(previous, _tabs)) return;
        if (tab.session.canDisconnect) {
          _notice(
            'Could not restore arrangement. All existing tabs were kept.',
          );
          return;
        }
      }
      if (previous.any((tab) => tab.session.canDisconnect)) {
        _notice('Could not restore arrangement. All existing tabs were kept.');
        return;
      }
      final restored = <_TerminalTab>[];
      try {
        for (final saved in arrangement.tabs) {
          restored.add(
            _TerminalTab(
              _nextId++,
              TerminalSession(),
              owned: true,
              start: false,
              name: saved.name,
              paneState: saved.paneState,
            ),
          );
        }
      } catch (_) {
        for (final tab in restored) {
          tab.session.dispose();
        }
        rethrow;
      }
      // Dispose nothing until every old connection has confirmed cleanup.
      // A failed attempt above leaves the complete tab list and screens intact.
      for (final tab in previous) {
        tab.session.removeListener(_changed);
      }
      for (final tab in restored) {
        tab.session.addListener(_changed);
      }
      setState(() {
        _tabs
          ..clear()
          ..addAll(restored);
        _layout = arrangement.layout.mapIds((index) => restored[index].id);
        _active = restored[arrangement.activeIndex].id;
        _zoomed = false;
        _lastPaneBounds.clear();
        _focusRequest++;
      });
      for (final tab in previous) {
        if (tab.owned) tab.session.dispose();
      }
      ref.read(focusAreaProvider.notifier).state = FocusArea.terminal;
      _notice('Arrangement restored. Connect each terminal when ready.');
    } catch (_) {
      _notice('Could not restore arrangement. All existing tabs were kept.');
    } finally {
      if (mounted) setState(() => _arranging = false);
    }
  }

  Future<void> _chooseBroadcastGroup() async {
    if (_arranging || _closing) return;
    final candidates = <TerminalBroadcastTarget>[];
    for (final tab in _tabs) {
      if (!tab.session.acceptsDirectInput) continue;
      final label = _label(tab);
      final destination = tab.session.label;
      candidates.add(
        TerminalBroadcastTarget(
          id: tab.id,
          label:
              '${_tabs.indexOf(tab) + 1}. $label'
              '${destination == null || destination == label ? '' : ' — $destination'}',
          session: tab.session,
        ),
      );
    }
    if (candidates.length < 2) {
      _broadcastNotice('Select at least two connected terminals.');
      return;
    }
    final chosen = await showDialog<List<TerminalBroadcastTarget>>(
      context: context,
      builder: (_) => TerminalBroadcastDialog(
        candidates: candidates,
        initiallySelected: _broadcast.targets
            .map((target) => target.id)
            .toSet(),
      ),
    );
    if (!mounted ||
        chosen == null ||
        !widget.visible ||
        _arranging ||
        _closing) {
      return;
    }
    if (!_broadcast.start(chosen)) {
      _broadcastNotice(
        'Connections changed. Choose the broadcast group again.',
      );
    }
  }

  Widget _broadcastBar({bool compact = false}) {
    final targets = _broadcast.targets;
    final colors = Theme.of(context).colorScheme;
    final bar = Semantics(
      liveRegion: true,
      child: Material(
        key: const ValueKey('terminal-broadcast-banner'),
        color: colors.errorContainer,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: compact ? 0 : 4,
          ),
          child: Row(
            children: [
              Icon(
                Icons.campaign_outlined,
                color: colors.onErrorContainer,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: targets.map((target) => target.label).join('\n'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context
                            .terminalBroadcastTr(
                              'Broadcasting to {count} terminals',
                            )
                            .replaceAll('{count}', '${targets.length}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!compact)
                        Text(
                          targets.map((target) => target.label).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onErrorContainer,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: context.terminalBroadcastTr('Stop broadcast'),
                child: TextButton.icon(
                  key: const ValueKey('terminal-stop-broadcast'),
                  onPressed: () => _broadcast.stop(),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onErrorContainer,
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: Text(context.terminalBroadcastTr('Stop')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return compact ? SizedBox(height: 40, child: bar) : bar;
  }

  KeyEventResult _onWorkspaceKey(KeyEvent event) {
    if (_arranging) return KeyEventResult.handled;
    final keyboard = HardwareKeyboard.instance;
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final direction = const [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ].contains(event.logicalKey);
    if (keyboard.isAltPressed) {
      final paneModifier =
          (keyboard.isControlPressed && !keyboard.isMetaPressed) ||
          (apple && keyboard.isMetaPressed && !keyboard.isControlPressed);
      if (direction && paneModifier && !keyboard.isShiftPressed) {
        if (event is KeyDownEvent) _navigatePane(event.logicalKey);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final command = apple
        ? keyboard.isMetaPressed && !keyboard.isControlPressed
        : keyboard.isControlPressed &&
              !keyboard.isMetaPressed &&
              keyboard.isShiftPressed;
    final newTab = command && event.logicalKey == LogicalKeyboardKey.keyT;
    final closeTab = command && event.logicalKey == LogicalKeyboardKey.keyW;
    final splitSide =
        command &&
        event.logicalKey == LogicalKeyboardKey.keyD &&
        (!apple || !keyboard.isShiftPressed);
    final splitBelow =
        command &&
        (apple
            ? keyboard.isShiftPressed &&
                  event.logicalKey == LogicalKeyboardKey.keyD
            : event.logicalKey == LogicalKeyboardKey.keyE);
    final zoom =
        command &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        keyboard.isShiftPressed;
    final cyclePane =
        command &&
        (event.logicalKey == LogicalKeyboardKey.bracketLeft ||
            event.logicalKey == LogicalKeyboardKey.bracketRight) &&
        (!apple || !keyboard.isShiftPressed);
    final cycle =
        keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.tab;
    if (!newTab &&
        !closeTab &&
        !cycle &&
        !splitSide &&
        !splitBelow &&
        !zoom &&
        !cyclePane) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (newTab) _addTab();
      if (splitSide) _split(Axis.horizontal);
      if (splitBelow) _split(Axis.vertical);
      if (zoom) _toggleZoom();
      if (cyclePane) {
        _cyclePane(event.logicalKey == LogicalKeyboardKey.bracketLeft ? -1 : 1);
      }
      if (closeTab) {
        unawaited(_closeTab(_tabs.firstWhere((tab) => tab.id == _active)));
      }
      if (cycle) {
        final index = _tabs.indexWhere((tab) => tab.id == _active);
        final step = keyboard.isShiftPressed ? -1 : 1;
        _activate(_tabs[(index + step) % _tabs.length].id);
      }
    }
    return KeyEventResult.handled;
  }

  void _resizePaneSplit(
    _PaneDivider divider,
    double delta, {
    bool balance = false,
  }) {
    if (_arranging || _closing || !widget.visible) return;
    final current = _layout.splitAt(divider.path);
    if (current == null ||
        current.axis != divider.split.axis ||
        !listEquals(current.first.leafIds, divider.split.first.leafIds) ||
        !listEquals(current.second.leafIds, divider.split.second.leafIds)) {
      return;
    }
    final effective = current.fraction.clamp(divider.lower, divider.upper);
    var fraction = 0.5;
    if (!balance) {
      fraction = (effective + delta / divider.usable)
          .clamp(
            TerminalPaneLayout.minimumFraction,
            TerminalPaneLayout.maximumFraction,
          )
          .clamp(divider.lower, divider.upper)
          .toDouble();
      // A window constraint may hide the saved ratio. Keep that ratio when a
      // drag cannot move the divider, so widening restores the user's layout.
      if (fraction == effective) return;
    }
    if (fraction == current.fraction) return;
    setState(() => _layout = _layout.withSplitFraction(divider.path, fraction));
  }

  Widget _buildPanes(Size size) {
    final geometry = _PaneGeometry(
      _layout,
      size,
      active: _active,
      zoomed: _zoomed,
    );
    final full = Offset.zero & size;
    _visiblePaneBounds = geometry.panes;
    _lastPaneBounds.addAll(geometry.panes);
    return ColoredBox(
      color: Theme.of(context).dividerColor,
      child: Stack(
        children: [
          // Keep every viewport under the same parent and stable key. Only its
          // rectangle changes; nested splits never reparent terminal state.
          for (final tab in _tabs)
            Positioned.fromRect(
              key: ValueKey('terminal-pane-${tab.id}'),
              rect: geometry.panes[tab.id] ?? _lastPaneBounds[tab.id] ?? full,
              child: Offstage(
                offstage: !geometry.panes.containsKey(tab.id),
                child: ExcludeFocus(
                  excluding: !widget.visible || _arranging || tab.id != _active,
                  child: IgnorePointer(
                    ignoring: _arranging,
                    child: TerminalPanel(
                      key: tab.key,
                      session: tab.session,
                      autoStart: tab.start,
                      sharedConnection: tab.sharedConnection,
                      initialPaneState: tab.paneState,
                      onPaneStateChanged: (state) {
                        if (_tabs.contains(tab)) tab.paneState = state;
                      },
                      embedded: true,
                      visible:
                          widget.visible && geometry.panes.containsKey(tab.id),
                      active: tab.id == _active && !_arranging,
                      focusRequest: _focusRequest,
                      isActivePane: () =>
                          mounted &&
                          widget.visible &&
                          !_arranging &&
                          _active == tab.id,
                      onActivate: () => _activate(tab.id),
                      onWorkspaceKey: _onWorkspaceKey,
                    ),
                  ),
                ),
              ),
            ),
          for (final divider in geometry.dividers)
            Positioned.fromRect(
              key: ValueKey('terminal-divider-position-${divider.path}'),
              rect: divider.bounds,
              child: Semantics(
                label: context.terminalArrangementTr('Resize split'),
                value: '${(divider.fraction * 100).round()}%',
                increasedValue:
                    '${(divider.adjustedFraction(0.05) * 100).round()}%',
                decreasedValue:
                    '${(divider.adjustedFraction(-0.05) * 100).round()}%',
                onIncrease: () =>
                    _resizePaneSplit(divider, divider.usable * 0.05),
                onDecrease: () =>
                    _resizePaneSplit(divider, -divider.usable * 0.05),
                child: MouseRegion(
                  cursor: divider.horizontal
                      ? SystemMouseCursors.resizeLeftRight
                      : SystemMouseCursors.resizeUpDown,
                  child: Tooltip(
                    message: context.terminalArrangementTr(
                      'Drag to resize. Double-click to balance.',
                    ),
                    child: GestureDetector(
                      key: ValueKey(
                        divider.path.isEmpty
                            ? 'terminal-split-divider'
                            : 'terminal-split-divider-${divider.path}',
                      ),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: divider.horizontal
                          ? (details) =>
                                _resizePaneSplit(divider, details.delta.dx)
                          : null,
                      onVerticalDragUpdate: !divider.horizontal
                          ? (details) =>
                                _resizePaneSplit(divider, details.delta.dy)
                          : null,
                      onDoubleTap: () =>
                          _resizePaneSplit(divider, 0, balance: true),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabBar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in _tabs)
                    Semantics(
                      selected: tab.id == _active,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 200),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              width: 2,
                              color: tab.id == _active
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Flexible(
                              child: InkWell(
                                key: ValueKey('terminal-tab-${tab.id}'),
                                onTap: () => _activate(tab.id),
                                onDoubleTap: () => unawaited(_rename(tab)),
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 10,
                                    right: 6,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        tab.session.isConnected
                                            ? Icons.circle
                                            : Icons.circle_outlined,
                                        size: 8,
                                        color:
                                            tab.session.status ==
                                                TerminalSessionStatus.failed
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .error
                                            : null,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Tooltip(
                                          message: _label(tab),
                                          child: Text(
                                            _label(tab),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Keep close outside the double-tap rename target:
                            // a fast retry must always close, never rename.
                            IconButton(
                              key: ValueKey('terminal-close-tab-${tab.id}'),
                              tooltip: context.terminalControlsTr(
                                'Close terminal',
                              ),
                              icon: const Icon(Icons.close, size: 14),
                              onPressed: _tabs.length > 1 && !_arranging
                                  ? () => unawaited(_closeTab(tab))
                                  : null,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_zoomed)
            IconButton(
              key: const ValueKey('terminal-restore-panes'),
              tooltip: context.terminalControlsTr('Restore panes'),
              onPressed: _toggleZoom,
              icon: const Icon(Icons.zoom_in_map, size: 20),
            ),
          IconButton(
            key: const ValueKey('terminal-new-tab'),
            tooltip: context.terminalControlsTr('New terminal'),
            onPressed: _tabs.length < TerminalTabs.maxTabs && !_arranging
                ? _addTab
                : null,
            icon: const Icon(Icons.add, size: 20),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('terminal-layout'),
            tooltip: context.terminalControlsTr('Terminal layout'),
            enabled: !_arranging,
            icon: const Icon(Icons.space_dashboard_outlined, size: 20),
            onCanceled: () => _sharedShellRequest = null,
            onSelected: (value) {
              switch (value) {
                case 'horizontal':
                  _split(Axis.horizontal);
                case 'vertical':
                  _split(Axis.vertical);
                case 'shared-ssh-tab':
                  unawaited(_openSharedShell());
                case 'shared-ssh-horizontal':
                  unawaited(_openSharedShell(split: Axis.horizontal));
                case 'shared-ssh-vertical':
                  unawaited(_openSharedShell(split: Axis.vertical));
                case 'single':
                  _singlePane();
                case 'zoom':
                  _toggleZoom();
                case 'previous-pane':
                  _cyclePane(-1);
                case 'next-pane':
                  _cyclePane(1);
                case 'rename':
                  unawaited(
                    _rename(_tabs.firstWhere((tab) => tab.id == _active)),
                  );
                case 'save-arrangement':
                  unawaited(_saveArrangement());
                case 'arrangements':
                  unawaited(_chooseArrangement());
                case 'move-left':
                  _moveTab(-1);
                case 'move-right':
                  _moveTab(1);
                case 'balance':
                  setState(() => _layout = _layout.balance());
                case 'broadcast':
                  unawaited(_chooseBroadcastGroup());
              }
            },
            itemBuilder: (_) {
              _captureSharedShellRequest();
              return [
                if (_sharedShellRequest != null) ...[
                  PopupMenuItem(
                    value: 'shared-ssh-tab',
                    enabled: _tabs.length < TerminalTabs.maxTabs,
                    child: Text(context.sshSharingTr('New SSH shell')),
                  ),
                  PopupMenuItem(
                    value: 'shared-ssh-horizontal',
                    enabled: _tabs.length < TerminalTabs.maxTabs,
                    child: Text(context.sshSharingTr('Split SSH side by side')),
                  ),
                  PopupMenuItem(
                    value: 'shared-ssh-vertical',
                    enabled: _tabs.length < TerminalTabs.maxTabs,
                    child: Text(
                      context.sshSharingTr('Split SSH top and bottom'),
                    ),
                  ),
                  const PopupMenuDivider(),
                ],
                PopupMenuItem(
                  value: 'horizontal',
                  enabled: _tabs.length < TerminalTabs.maxTabs,
                  child: Text(context.terminalControlsTr('Split side by side')),
                ),
                PopupMenuItem(
                  value: 'vertical',
                  enabled: _tabs.length < TerminalTabs.maxTabs,
                  child: Text(
                    context.terminalControlsTr('Split top and bottom'),
                  ),
                ),
                PopupMenuItem(
                  value: 'single',
                  enabled: _layout.leafIds.length > 1,
                  child: Text(context.terminalControlsTr('Single pane')),
                ),
                PopupMenuItem(
                  value: 'zoom',
                  enabled: _layout.leafIds.length > 1,
                  child: Text(
                    context.terminalControlsTr(
                      _zoomed ? 'Restore panes' : 'Zoom active pane',
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'previous-pane',
                  enabled: _layout.leafIds.length > 1,
                  child: Text(context.terminalControlsTr('Previous pane')),
                ),
                PopupMenuItem(
                  value: 'next-pane',
                  enabled: _layout.leafIds.length > 1,
                  child: Text(context.terminalControlsTr('Next pane')),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: Text(context.terminalControlsTr('Rename terminal')),
                ),
                PopupMenuItem(
                  value: 'move-left',
                  enabled: _tabs.first.id != _active,
                  child: Text(
                    context.terminalArrangementTr('Move terminal left'),
                  ),
                ),
                PopupMenuItem(
                  value: 'move-right',
                  enabled: _tabs.last.id != _active,
                  child: Text(
                    context.terminalArrangementTr('Move terminal right'),
                  ),
                ),
                PopupMenuItem(
                  value: 'balance',
                  enabled: _layout.leafIds.length > 1,
                  child: Text(context.terminalArrangementTr('Balance panes')),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'save-arrangement',
                  child: Text(
                    context.terminalArrangementTr('Save arrangement'),
                  ),
                ),
                PopupMenuItem(
                  value: 'arrangements',
                  child: Text(
                    context.terminalArrangementTr('Saved arrangements'),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'broadcast',
                  enabled:
                      _tabs
                          .where((tab) => tab.session.acceptsDirectInput)
                          .length >=
                      2,
                  child: Text(context.terminalBroadcastTr('Broadcast input')),
                ),
              ];
            },
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final view = View.of(context);
    final inset = math.max(
      media.viewInsets.bottom,
      view.viewInsets.bottom / view.devicePixelRatio,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(
          100.0,
          media.size.height - inset - media.padding.vertical - 160,
        );
        final maximum = math.min(
          800.0,
          constraints.hasBoundedHeight
              ? math.min(available, constraints.maxHeight)
              : available,
        );
        final height = ref
            .watch(terminalHeightProvider)
            .clamp(math.min(180.0, maximum), maximum)
            .toDouble();
        return SizedBox(
          key: const ValueKey('terminal-tabs'),
          height: height,
          child: Column(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    ref
                        .read(terminalHeightProvider.notifier)
                        .state = (height - details.delta.dy)
                        .clamp(math.min(180.0, maximum), maximum)
                        .toDouble();
                  },
                  child: Container(
                    height: 6,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              // With very little height, keep the broadcast warning and Stop
              // control in the normal tab-bar slot so the terminal still fits.
              if (!_broadcast.isArmed || height >= 220) _tabBar(),
              if (_broadcast.isArmed) _broadcastBar(compact: height < 220),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, area) {
                    return _buildPanes(area.biggest);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _broadcast.removeListener(_broadcastChanged);
    _broadcast.dispose();
    _releaseTabs();
    super.dispose();
  }
}

/// Layout geometry is separate from the widget hierarchy so a split never
/// destroys a terminal view. When the requested layout cannot fit, only the
/// active pane is shown; its topology and the other live sessions are retained.
class _PaneGeometry {
  _PaneGeometry(
    TerminalPaneLayout layout,
    Size size, {
    required int active,
    required bool zoomed,
  }) {
    final minimum = _minimum(layout);
    final bounds = Offset.zero & size;
    if (zoomed || size.width < minimum.width || size.height < minimum.height) {
      panes[active] = bounds;
    } else {
      _place(layout, bounds, '');
    }
  }

  static const gap = 8.0;
  final panes = <int, Rect>{};
  final dividers = <_PaneDivider>[];

  static Size _minimum(TerminalPaneLayout node) => switch (node) {
    TerminalPaneLeaf() => const Size(220, 120),
    TerminalPaneSplit(:final axis, :final first, :final second) =>
      switch (axis) {
        TerminalSplitAxis.horizontal => Size(
          _minimum(first).width + gap + _minimum(second).width,
          math.max(_minimum(first).height, _minimum(second).height),
        ),
        TerminalSplitAxis.vertical => Size(
          math.max(_minimum(first).width, _minimum(second).width),
          _minimum(first).height + gap + _minimum(second).height,
        ),
      },
  };

  void _place(TerminalPaneLayout node, Rect bounds, String path) {
    if (node is TerminalPaneLeaf) {
      panes[node.id] = bounds;
      return;
    }
    final split = node as TerminalPaneSplit;
    final horizontal = split.axis == TerminalSplitAxis.horizontal;
    final firstMinimum = _minimum(split.first);
    final secondMinimum = _minimum(split.second);
    final usable = (horizontal ? bounds.width : bounds.height) - gap;
    final lower =
        (horizontal ? firstMinimum.width : firstMinimum.height) / usable;
    final upper =
        1 - (horizontal ? secondMinimum.width : secondMinimum.height) / usable;
    // Minimum pane sizes can temporarily clamp a saved proportion. Keep the
    // saved value so widening the workspace restores the user's original ratio.
    final fraction = split.fraction
        .clamp(lower, math.max(lower, upper))
        .toDouble();
    final firstExtent = usable * fraction;
    final secondExtent = usable - firstExtent;
    final first = horizontal
        ? Rect.fromLTWH(bounds.left, bounds.top, firstExtent, bounds.height)
        : Rect.fromLTWH(bounds.left, bounds.top, bounds.width, firstExtent);
    final divider = horizontal
        ? Rect.fromLTWH(first.right, bounds.top, gap, bounds.height)
        : Rect.fromLTWH(bounds.left, first.bottom, bounds.width, gap);
    final second = horizontal
        ? Rect.fromLTWH(divider.right, bounds.top, secondExtent, bounds.height)
        : Rect.fromLTWH(
            bounds.left,
            divider.bottom,
            bounds.width,
            secondExtent,
          );
    dividers.add(
      _PaneDivider(
        path: path,
        split: split,
        bounds: divider,
        usable: usable,
        lower: lower,
        upper: math.max(lower, upper),
        fraction: fraction,
      ),
    );
    _place(split.first, first, '${path}0');
    _place(split.second, second, '${path}1');
  }
}

class _PaneDivider {
  const _PaneDivider({
    required this.path,
    required this.split,
    required this.bounds,
    required this.usable,
    required this.lower,
    required this.upper,
    required this.fraction,
  });
  final String path;
  final TerminalPaneSplit split;
  final Rect bounds;
  final double usable;
  final double lower;
  final double upper;
  final double fraction;
  bool get horizontal => split.axis == TerminalSplitAxis.horizontal;
  double adjustedFraction(double step) => (fraction + step)
      .clamp(
        TerminalPaneLayout.minimumFraction,
        TerminalPaneLayout.maximumFraction,
      )
      .clamp(lower, upper)
      .toDouble();
}
