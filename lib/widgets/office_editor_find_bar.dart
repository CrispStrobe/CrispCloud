// lib/widgets/office_editor_find_bar.dart
//
// Find / replace chrome for the Quds Office surfaces. The editors expose a
// `findBarBuilder`; this widget is returned from it while `findSession.active`.

import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../l10n/office_editor_strings.dart';

class OfficeFindBar extends StatefulWidget {
  const OfficeFindBar({
    super.key,
    required this.controller,
    this.showReplace = true,
  });

  final OfficeController controller;
  final bool showReplace;

  @override
  State<OfficeFindBar> createState() => _OfficeFindBarState();
}

class _OfficeFindBarState extends State<OfficeFindBar> {
  final TextEditingController _query = TextEditingController();
  final TextEditingController _replaceWith = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  bool _matchCase = false;
  bool _wholeWord = false;
  bool _replaceOpen = false;

  @override
  void initState() {
    super.initState();
    final OfficeFindOptions? options = widget.controller.findSession.options;
    if (options != null) {
      _query.text = options.query;
      _replaceWith.text = options.replaceWith;
      _matchCase = options.matchCase;
      _wholeWord = options.wholeWord;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _queryFocus.requestFocus();
      if (_query.text.isNotEmpty) _search();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _replaceWith.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  OfficeFindOptions get _options => OfficeFindOptions(
        query: _query.text,
        replaceWith: _replaceWith.text,
        matchCase: _matchCase,
        wholeWord: _wholeWord,
      );

  void _search() {
    final String query = _query.text;
    if (query.isEmpty) {
      widget.controller.findSession
        ..hits = <OfficeFindHit>[]
        ..index = -1
        ..options = null
        ..active = true;
      setState(() {});
      widget.controller.refresh();
      return;
    }
    widget.controller.find(_options);
    setState(() {});
  }

  void _next() {
    if (_query.text.isEmpty) return;
    if (widget.controller.findSession.options?.query != _query.text) {
      _search();
    }
    widget.controller.findNext();
    setState(() {});
  }

  void _previous() {
    if (_query.text.isEmpty) return;
    if (widget.controller.findSession.options?.query != _query.text) {
      _search();
    }
    widget.controller.findPrevious();
    setState(() {});
  }

  void _replace() {
    if (_query.text.isEmpty) return;
    widget.controller.replace(_options);
    setState(() {});
  }

  void _replaceAll() {
    if (_query.text.isEmpty) return;
    final int count = widget.controller.replaceAll(_options);
    setState(() {});
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          '${context.tr('Replaced')} $count ${context.tr('occurrence(s).')}',
        ),
      ),
    );
  }

  void _close() {
    widget.controller.closeFind();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OfficeFindSession session = widget.controller.findSession;
    final int total = session.hits.length;
    final String count = _query.text.isEmpty
        ? ''
        : total == 0
            ? context.tr('No results')
            : '${session.index + 1} / $total';

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 220,
                height: 32,
                child: TextField(
                  controller: _query,
                  focusNode: _queryFocus,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: context.tr('Find'),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: const OutlineInputBorder(),
                    suffixText: count,
                    suffixStyle: const TextStyle(fontSize: 10),
                  ),
                  onChanged: (_) => _search(),
                  onSubmitted: (_) => _next(),
                ),
              ),
              const SizedBox(width: 4),
              _IconAction(
                icon: Icons.keyboard_arrow_up,
                tooltip: context.tr('Previous match'),
                onPressed: _previous,
              ),
              _IconAction(
                icon: Icons.keyboard_arrow_down,
                tooltip: context.tr('Next match'),
                onPressed: _next,
              ),
              _ToggleAction(
                label: 'Aa',
                tooltip: context.tr('Match case'),
                selected: _matchCase,
                onPressed: () {
                  setState(() => _matchCase = !_matchCase);
                  _search();
                },
              ),
              _ToggleAction(
                label: 'ab',
                tooltip: context.tr('Whole words'),
                selected: _wholeWord,
                onPressed: () {
                  setState(() => _wholeWord = !_wholeWord);
                  _search();
                },
              ),
              if (widget.showReplace) ...<Widget>[
                const SizedBox(width: 6),
                _ToggleAction(
                  icon: Icons.find_replace,
                  tooltip: context.tr('Replace'),
                  selected: _replaceOpen,
                  onPressed: () =>
                      setState(() => _replaceOpen = !_replaceOpen),
                ),
                if (_replaceOpen) ...<Widget>[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 190,
                    height: 32,
                    child: TextField(
                      controller: _replaceWith,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: context.tr('Replace with'),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _replace,
                    child: Text(context.tr('Replace')),
                  ),
                  TextButton(
                    onPressed: _replaceAll,
                    child: Text(context.tr('All')),
                  ),
                ],
              ],
              const SizedBox(width: 4),
              _IconAction(
                icon: Icons.close,
                tooltip: context.tr('Close find'),
                onPressed: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: 17,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

class _ToggleAction extends StatelessWidget {
  const _ToggleAction({
    required this.selected,
    required this.onPressed,
    this.label,
    this.icon,
    this.tooltip,
  });

  final bool selected;
  final VoidCallback onPressed;
  final String? label;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 28,
          constraints: const BoxConstraints(minWidth: 28),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: icon != null
              ? Icon(icon, size: 17)
              : Text(label ?? '', style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}
