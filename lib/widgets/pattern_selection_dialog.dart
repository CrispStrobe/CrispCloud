import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/panel_provider.dart';
import '../services/file_selection_pattern.dart';
import '../services/log_service.dart';
import '../services/selection_pattern_history.dart';

export '../services/file_selection_pattern.dart' show SelectionAction;

/// Commander selection tool, shared by menus and the keypad shortcuts.
Future<void> showPatternSelectionDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side, {
  SelectionAction initialAction = SelectionAction.select,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) =>
        _PatternSelectionDialog(side: side, initialAction: initialAction),
  );
  if (context.mounted) ref.read(panelProvider(side)).focusList();
}

class _PatternSelectionDialog extends ConsumerStatefulWidget {
  const _PatternSelectionDialog({
    required this.side,
    required this.initialAction,
  });

  final PanelSide side;
  final SelectionAction initialAction;

  @override
  ConsumerState<_PatternSelectionDialog> createState() =>
      _PatternSelectionDialogState();
}

class _PatternSelectionDialogState
    extends ConsumerState<_PatternSelectionDialog> {
  static const _log = Log('PatternSelectionDialog');
  final _controller = TextEditingController(text: '*');
  final _history = SelectionPatternHistory();
  List<FileSelectionPattern> _recentPatterns = const [];
  FilePatternMode _mode = FilePatternMode.wildcard;
  late SelectionAction _action = widget.initialAction;
  bool _caseSensitive = false;
  bool _matchFullPath = false;
  String _kind = 'all';
  String? _memoryMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    try {
      final patterns = await _history.load();
      if (mounted) setState(() => _recentPatterns = patterns);
    } catch (error) {
      _log.warn('Selection pattern history could not be loaded', error);
    }
  }

  void _recall(FileSelectionPattern pattern) {
    setState(() {
      _controller.text = pattern.expression;
      _mode = pattern.mode;
      _caseSensitive = pattern.caseSensitive;
      _matchFullPath = pattern.matchFullPath;
      _kind = pattern.includeFiles
          ? (pattern.includeFolders ? 'all' : 'files')
          : 'folders';
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  FileSelectionPattern _pattern() => FileSelectionPattern(
    _controller.text,
    mode: _mode,
    caseSensitive: _caseSensitive,
    matchFullPath: _matchFullPath,
    includeFiles: _kind != 'folders',
    includeFolders: _kind != 'files',
  );

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(panelProvider(widget.side));
    FileSelectionPattern? pattern;
    String? error;
    try {
      pattern = _pattern();
    } on FormatException catch (e) {
      error = e.message;
    }
    final displayed = panel.displayedFiles ?? [];
    final matches = pattern == null
        ? 0
        : displayed.where(pattern.matches).length;
    final restorable = panel.restorableSelectionCount;

    return AlertDialog(
      title: const Text('Select by pattern'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<FilePatternMode>(
                segments: const [
                  ButtonSegment(
                    value: FilePatternMode.wildcard,
                    label: Text('Wildcards'),
                  ),
                  ButtonSegment(
                    value: FilePatternMode.regex,
                    label: Text('Regular expression'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.single),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('selection-pattern'),
                controller: _controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (pattern != null) _apply(pattern);
                },
                decoration: InputDecoration(
                  labelText: _mode == FilePatternMode.wildcard
                      ? 'Masks'
                      : 'Expression',
                  border: const OutlineInputBorder(),
                  suffixIcon: PopupMenuButton<FileSelectionPattern>(
                    key: const ValueKey('selection-pattern-history'),
                    tooltip: 'Recent patterns',
                    enabled: _recentPatterns.isNotEmpty,
                    icon: const Icon(Icons.history),
                    onSelected: _recall,
                    itemBuilder: (_) => [
                      for (final recent in _recentPatterns)
                        PopupMenuItem(
                          value: recent,
                          child: Text(
                            '${recent.mode == FilePatternMode.regex ? 'Regex' : 'Wildcards'}: ${recent.expression}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  errorText: error,
                  errorMaxLines: 3,
                  helperText: _mode == FilePatternMode.wildcard
                      ? '* any characters · ? one character\nSeparate masks with ; and exclusions with |\nExample: *.jpg;*.png|thumb*'
                      : r'Regex searches within names. Use ^ and $ for a full match.'
                            '\nExample: ^report-\\d+\\.pdf\$',
                  helperMaxLines: 4,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SelectionAction>(
                isExpanded: true,
                initialValue: _action,
                decoration: const InputDecoration(
                  labelText: 'Action',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: SelectionAction.select,
                    child: Text(
                      'Add matches to selection',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: SelectionAction.deselect,
                    child: Text(
                      'Remove matches from selection',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: SelectionAction.invert,
                    child: Text(
                      'Invert matching marks',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: SelectionAction.replace,
                    child: Text(
                      'Replace selection with matches',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _action = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('selection-kind-$_kind'),
                isExpanded: true,
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Include',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text(
                      'Files and folders',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'files',
                    child: Text(
                      'Files only',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'folders',
                    child: Text(
                      'Folders only',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _kind = value!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Case sensitive'),
                value: _caseSensitive,
                onChanged: (value) => setState(() => _caseSensitive = value!),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Match full original paths'),
                value: _matchFullPath,
                onChanged: (value) => setState(() => _matchFullPath = value!),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              Text(
                '$matches matching item(s) in the visible list',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    key: const ValueKey('remember-panel-selection'),
                    onPressed: panel.selection.isEmpty
                        ? null
                        : () {
                            final count = panel.rememberSelection();
                            setState(() {
                              _memoryMessage = count == 0
                                  ? 'Refresh the source before remembering its selection.'
                                  : 'Remembered $count selected item(s) for this tab.';
                            });
                          },
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Remember selection'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('restore-panel-selection'),
                    onPressed: restorable == 0
                        ? null
                        : () {
                            final count = panel.restoreSelection();
                            setState(() {
                              _memoryMessage = 'Restored $count selected item(s).';
                            });
                          },
                    icon: const Icon(Icons.restore),
                    label: Text('Restore selection ($restorable)'),
                  ),
                ],
              ),
              Text(
                _memoryMessage ??
                    'Remembered marks stay in this tab for the current session. '
                        'Restore includes only visible, verified original paths.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('apply-pattern-selection'),
          onPressed: pattern == null ? null : () => _apply(pattern!),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  void _apply(FileSelectionPattern pattern) {
    ref
        .read(panelProvider(widget.side))
        .applyPatternSelection(pattern, action: _action);
    unawaited(
      _history.remember(pattern).catchError((Object error) {
        _log.warn('Selection pattern history could not be saved', error);
      }),
    );
    Navigator.pop(context);
  }
}
