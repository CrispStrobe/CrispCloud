import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/terminal_controls_strings.dart';
import '../l10n/terminal_strings.dart';
import '../providers/terminal_provider.dart';
import '../services/terminal_session.dart';
import 'terminal_panel.dart';

class _TerminalTab {
  _TerminalTab(
    this.id,
    this.session, {
    required this.owned,
    required this.start,
  });

  final int id;
  final TerminalSession session;
  final bool owned;
  final bool start;
  final key = GlobalKey();
  String? name;
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

  static const maxTabs = 8;

  @override
  ConsumerState<TerminalTabs> createState() => _TerminalTabsState();
}

class _TerminalTabsState extends ConsumerState<TerminalTabs> {
  final _tabs = <_TerminalTab>[];
  int _nextId = 1;
  late int _first;
  int? _second;
  late int _active;
  Axis _axis = Axis.horizontal;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final tab = _makeTab(widget.session);
    _first = _active = tab.id;
  }

  _TerminalTab _makeTab([TerminalSession? initial]) {
    final tab = _TerminalTab(
      _nextId++,
      initial ?? widget.sessionFactory?.call() ?? TerminalSession(),
      owned: initial == null,
      start: initial == null && widget.sessionFactory == null,
    );
    tab.session.addListener(_changed);
    _tabs.add(tab);
    return tab;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(TerminalTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _releaseTabs();
      final tab = _makeTab(widget.session);
      _first = _active = tab.id;
      _second = null;
    }
  }

  void _releaseTabs() {
    for (final tab in _tabs) {
      tab.session.removeListener(_changed);
      if (tab.owned) tab.session.dispose();
    }
    _tabs.clear();
  }

  void _activate(int id) {
    if (_active == id || !_tabs.any((tab) => tab.id == id)) return;
    setState(() {
      if (id != _first && id != _second) {
        if (_active == _second) {
          _second = id;
        } else {
          _first = id;
        }
      }
      _active = id;
    });
  }

  void _addTab() {
    if (_tabs.length >= TerminalTabs.maxTabs) return;
    final tab = _makeTab();
    _activate(tab.id);
  }

  void _split(Axis axis) {
    if (_second == null && _tabs.length >= TerminalTabs.maxTabs) return;
    setState(() {
      _axis = axis;
      if (_second == null) {
        final tab = _makeTab();
        _second = _active = tab.id;
      }
    });
  }

  void _singlePane() {
    setState(() {
      _first = _active;
      _second = null;
    });
  }

  String _label(_TerminalTab tab) =>
      tab.name ??
      tab.session.label ??
      '${context.terminalTr('Terminal')} ${tab.id}';

  Future<void> _rename(_TerminalTab tab) async {
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
    if (_closing || _tabs.length <= 1) return;
    _closing = true;
    try {
      if (tab.session.canDisconnect) {
        final close = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.terminalControlsTr('Close terminal?')),
            content: Text(
              context.terminalControlsTr(
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
      await tab.session.disconnect();
      if (!mounted || !_tabs.contains(tab)) return;
      // Failed cleanup leaves the tab available to retry disconnect.
      if (tab.session.canDisconnect) return;
      tab.session.removeListener(_changed);
      setState(() {
        _tabs.remove(tab);
        if (_first == tab.id) {
          _first = _second ?? _tabs.first.id;
          _second = null;
        } else if (_second == tab.id) {
          _second = null;
        }
        if (_active == tab.id) _active = _first;
      });
      if (tab.owned) tab.session.dispose();
    } finally {
      _closing = false;
    }
  }

  KeyEventResult _onWorkspaceKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed) return KeyEventResult.ignored;
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final command = apple
        ? keyboard.isMetaPressed && !keyboard.isControlPressed
        : keyboard.isControlPressed &&
              !keyboard.isMetaPressed &&
              keyboard.isShiftPressed;
    final newTab = command && event.logicalKey == LogicalKeyboardKey.keyT;
    final closeTab = command && event.logicalKey == LogicalKeyboardKey.keyW;
    final cycle =
        keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.tab;
    if (!newTab && !closeTab && !cycle) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      if (newTab) _addTab();
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
                      child: InkWell(
                        key: ValueKey('terminal-tab-${tab.id}'),
                        onTap: () => _activate(tab.id),
                        onDoubleTap: () => unawaited(_rename(tab)),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 200),
                          padding: const EdgeInsets.only(left: 10),
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
                            children: [
                              Icon(
                                tab.session.isConnected
                                    ? Icons.circle
                                    : Icons.circle_outlined,
                                size: 8,
                                color:
                                    tab.session.status ==
                                        TerminalSessionStatus.failed
                                    ? Theme.of(context).colorScheme.error
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
                              IconButton(
                                key: ValueKey('terminal-close-tab-${tab.id}'),
                                tooltip: context.terminalControlsTr(
                                  'Close terminal',
                                ),
                                icon: const Icon(Icons.close, size: 14),
                                onPressed: _tabs.length > 1
                                    ? () => unawaited(_closeTab(tab))
                                    : null,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('terminal-new-tab'),
            tooltip: context.terminalControlsTr('New terminal'),
            onPressed: _tabs.length < TerminalTabs.maxTabs ? _addTab : null,
            icon: const Icon(Icons.add, size: 20),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('terminal-layout'),
            tooltip: context.terminalControlsTr('Terminal layout'),
            icon: const Icon(Icons.space_dashboard_outlined, size: 20),
            onSelected: (value) {
              switch (value) {
                case 'horizontal':
                  _split(Axis.horizontal);
                case 'vertical':
                  _split(Axis.vertical);
                case 'single':
                  _singlePane();
                case 'rename':
                  unawaited(
                    _rename(_tabs.firstWhere((tab) => tab.id == _active)),
                  );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'horizontal',
                enabled: _second != null || _tabs.length < TerminalTabs.maxTabs,
                child: Text(context.terminalControlsTr('Split side by side')),
              ),
              PopupMenuItem(
                value: 'vertical',
                enabled: _second != null || _tabs.length < TerminalTabs.maxTabs,
                child: Text(context.terminalControlsTr('Split top and bottom')),
              ),
              PopupMenuItem(
                value: 'single',
                enabled: _second != null,
                child: Text(context.terminalControlsTr('Single pane')),
              ),
              PopupMenuItem(
                value: 'rename',
                child: Text(context.terminalControlsTr('Rename terminal')),
              ),
            ],
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
              _tabBar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, area) {
                    // A narrow/short viewport presents the active pane alone while
                    // preserving the requested split and both live connections.
                    final split =
                        _second != null &&
                        (_axis == Axis.horizontal
                            ? area.maxWidth >= 560
                            : area.maxHeight >= 260);
                    const gap = 4.0;
                    final width = split && _axis == Axis.horizontal
                        ? (area.maxWidth - gap) / 2
                        : area.maxWidth;
                    final paneHeight = split && _axis == Axis.vertical
                        ? (area.maxHeight - gap) / 2
                        : area.maxHeight;
                    return ColoredBox(
                      color: Theme.of(context).dividerColor,
                      child: Stack(
                        children: [
                          for (final tab in _tabs)
                            Positioned(
                              key: ValueKey('terminal-pane-${tab.id}'),
                              left:
                                  split &&
                                      tab.id == _second &&
                                      _axis == Axis.horizontal
                                  ? width + gap
                                  : 0,
                              top:
                                  split &&
                                      tab.id == _second &&
                                      _axis == Axis.vertical
                                  ? paneHeight + gap
                                  : 0,
                              width: width,
                              height: paneHeight,
                              child: Offstage(
                                offstage: split
                                    ? tab.id != _first && tab.id != _second
                                    : tab.id != _active,
                                child: ExcludeFocus(
                                  excluding:
                                      !widget.visible || tab.id != _active,
                                  child: TerminalPanel(
                                    key: tab.key,
                                    session: tab.session,
                                    autoStart: tab.start,
                                    embedded: true,
                                    visible:
                                        widget.visible &&
                                        (split
                                            ? tab.id == _first ||
                                                  tab.id == _second
                                            : tab.id == _active),
                                    active: tab.id == _active,
                                    onActivate: () => _activate(tab.id),
                                    onWorkspaceKey: _onWorkspaceKey,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
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
    _releaseTabs();
    super.dispose();
  }
}
