import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm2/xterm.dart';

import '../l10n/terminal_search_strings.dart';
import '../services/terminal_search.dart';

enum _SearchOption { matchCase, wholeWord }

/// A compact, independently focused search surface for one terminal viewport.
///
/// [lineHeight] must return the current TerminalView render cell height, so
/// navigation remains accurate after a font-size change or terminal resize.
class TerminalSearchBar extends StatefulWidget {
  const TerminalSearchBar({
    super.key,
    required this.terminal,
    required this.controller,
    required this.scrollController,
    required this.lineHeight,
    required this.onClose,
    this.autofocus = true,
    this.active = true,
    this.onActivate,
  });

  final Terminal terminal;
  final TerminalController controller;
  final ScrollController scrollController;
  final double Function() lineHeight;
  final VoidCallback onClose;
  final bool autofocus;
  final bool active;
  final VoidCallback? onActivate;

  @override
  State<TerminalSearchBar> createState() => _TerminalSearchBarState();
}

class _TerminalSearchBarState extends State<TerminalSearchBar> {
  final _query = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Terminal search');
  late TerminalScrollbackSearch _search;

  @override
  void initState() {
    super.initState();
    _attachSearch();
  }

  void _attachSearch() {
    _search =
        TerminalScrollbackSearch(
            terminal: widget.terminal,
            controller: widget.controller,
            onReveal: _revealCurrent,
          )
          ..setActive(widget.active)
          ..addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(TerminalSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.terminal, widget.terminal) ||
        !identical(oldWidget.controller, widget.controller)) {
      final matchCase = _search.caseSensitive;
      final wholeWord = _search.wholeWord;
      _search.removeListener(_onSearchChanged);
      _search.dispose();
      _attachSearch();
      // Defer controller notifications while the parent is rebuilding the new
      // viewport. The old model has already canceled every pending rescan.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _search.setCaseSensitive(matchCase);
        _search.setWholeWord(wholeWord);
        _search.setQuery(_query.text);
      });
    }
    if (oldWidget.active != widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _search.setActive(widget.active);
        if (widget.active && widget.autofocus) {
          _focus.requestFocus();
        } else if (!widget.active) {
          _focus.unfocus();
        }
      });
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _revealCurrent() {
    if (!widget.active) return;
    final search = _search;
    final revision = search.revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.active ||
          !identical(search, _search) ||
          revision != search.revision) {
        return;
      }
      final range = search.currentRange;
      final scroll = widget.scrollController;
      if (range == null || !scroll.hasClients) return;
      final position = scroll.position;
      if (!position.hasContentDimensions) return;
      final cellHeight = widget.lineHeight();
      if (!cellHeight.isFinite || cellHeight <= 0) return;
      // Center the hit when possible. Clamping also handles the alternate
      // screen, short buffers and matches in the final viewport.
      final target =
          range.begin.y * cellHeight -
          (position.viewportDimension - cellHeight) / 2;
      scroll.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _search.previous();
      } else {
        _search.next();
      }
      return KeyEventResult.handled;
    }
    // Search keystrokes belong to its text field, never the file browser's
    // shortcuts higher in the focus tree.
    return KeyEventResult.skipRemainingHandlers;
  }

  String get _count => _search.pending
      ? '…'
      : '${_search.currentIndex + 1}/${_search.matchCount}'
            '${_search.truncated ? '+' : ''}';

  String get _countLabel {
    if (_search.pending) return context.terminalSearchTr('Searching…');
    if (_search.truncated) {
      return context.terminalSearchTr('Showing the first 1000 matches');
    }
    if (_search.matchCount == 0) {
      return context.terminalSearchTr('No matches');
    }
    return context
        .terminalSearchTr('Match {current} of {total}')
        .replaceAll('{current}', '${_search.currentIndex + 1}')
        .replaceAll('{total}', '${_search.matchCount}');
  }

  Widget _button({
    required Key key,
    required String label,
    required Widget icon,
    required VoidCallback? onPressed,
    bool selected = false,
  }) => IconButton(
    key: key,
    tooltip: context.terminalSearchTr(label),
    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
    padding: EdgeInsets.zero,
    iconSize: 18,
    isSelected: selected,
    color: selected ? Theme.of(context).colorScheme.primary : null,
    onPressed: onPressed,
    icon: icon,
  );

  List<Widget> _controls({required bool compact}) => [
    Tooltip(
      message: _countLabel,
      child: Semantics(
        label: _countLabel,
        liveRegion: true,
        child: ExcludeSemantics(
          child: SizedBox(
            width: 52,
            child: Text(
              _count,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ),
    ),
    _button(
      key: const ValueKey('terminal-search-previous'),
      label: 'Previous match',
      icon: const Icon(Icons.keyboard_arrow_up),
      onPressed: _search.query.isEmpty ? null : _search.previous,
    ),
    _button(
      key: const ValueKey('terminal-search-next'),
      label: 'Next match',
      icon: const Icon(Icons.keyboard_arrow_down),
      onPressed: _search.query.isEmpty ? null : _search.next,
    ),
    if (compact)
      PopupMenuButton<_SearchOption>(
        key: const ValueKey('terminal-search-options'),
        tooltip: context.terminalSearchTr('Search options'),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 160),
        iconSize: 18,
        style: IconButton.styleFrom(
          fixedSize: const Size(36, 36),
          minimumSize: const Size(36, 36),
          maximumSize: const Size(36, 36),
        ),
        onSelected: (value) => switch (value) {
          _SearchOption.matchCase => _search.setCaseSensitive(
            !_search.caseSensitive,
          ),
          _SearchOption.wholeWord => _search.setWholeWord(!_search.wholeWord),
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            value: _SearchOption.matchCase,
            checked: _search.caseSensitive,
            child: Text(context.terminalSearchTr('Match case')),
          ),
          CheckedPopupMenuItem(
            value: _SearchOption.wholeWord,
            checked: _search.wholeWord,
            child: Text(context.terminalSearchTr('Whole words')),
          ),
        ],
        icon: const Icon(Icons.tune),
      )
    else ...[
      _button(
        key: const ValueKey('terminal-search-case'),
        label: 'Match case',
        selected: _search.caseSensitive,
        icon: const Text('Aa'),
        onPressed: () => _search.setCaseSensitive(!_search.caseSensitive),
      ),
      _button(
        key: const ValueKey('terminal-search-word'),
        label: 'Whole words',
        selected: _search.wholeWord,
        icon: const Icon(Icons.space_bar),
        onPressed: () => _search.setWholeWord(!_search.wholeWord),
      ),
    ],
    _button(
      key: const ValueKey('terminal-search-close'),
      label: 'Close search',
      icon: const Icon(Icons.close),
      onPressed: widget.onClose,
    ),
  ];

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final field = TextField(
            key: const ValueKey('terminal-search-query'),
            controller: _query,
            focusNode: _focus,
            autofocus: widget.autofocus && widget.active,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            maxLength: 512,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: context.terminalSearchTr('Find in terminal'),
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
            ),
            onChanged: _search.setQuery,
            onTap: widget.onActivate,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              _search.next();
              _focus.requestFocus();
            },
          );
          if (constraints.maxWidth < 300) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                field,
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: _controls(compact: true),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: field),
              ..._controls(compact: constraints.maxWidth < 460),
            ],
          );
        },
      ),
    ),
  );

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }
}
