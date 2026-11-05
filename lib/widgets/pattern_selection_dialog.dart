import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/panel_provider.dart';
import '../services/file_selection_pattern.dart';

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
  final _controller = TextEditingController(text: '*');
  FilePatternMode _mode = FilePatternMode.wildcard;
  late SelectionAction _action = widget.initialAction;
  bool _caseSensitive = false;
  bool _matchFullPath = false;
  String _kind = 'all';

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
                initialValue: _action,
                decoration: const InputDecoration(
                  labelText: 'Action',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: SelectionAction.select,
                    child: Text('Add matches to selection'),
                  ),
                  DropdownMenuItem(
                    value: SelectionAction.deselect,
                    child: Text('Remove matches from selection'),
                  ),
                  DropdownMenuItem(
                    value: SelectionAction.invert,
                    child: Text('Invert matching marks'),
                  ),
                  DropdownMenuItem(
                    value: SelectionAction.replace,
                    child: Text('Replace selection with matches'),
                  ),
                ],
                onChanged: (value) => setState(() => _action = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Include',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text('Files and folders'),
                  ),
                  DropdownMenuItem(value: 'files', child: Text('Files only')),
                  DropdownMenuItem(
                    value: 'folders',
                    child: Text('Folders only'),
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
    Navigator.pop(context);
  }
}
