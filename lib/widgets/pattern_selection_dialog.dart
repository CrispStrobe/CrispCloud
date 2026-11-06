import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/panel_side.dart';
import '../models/file_search_query.dart';
import '../services/saved_search_service.dart';
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
  final _minimum = TextEditingController();
  final _maximum = TextEditingController();
  final _after = TextEditingController();
  final _before = TextEditingController();
  final _extensions = TextEditingController();
  bool _includeHidden = true;
  List<SavedSearch> _presets = const [];

  List<FileSelectionPattern> _recentPatterns = const [];
  FilePatternMode _mode = FilePatternMode.wildcard;
  late SelectionAction _action = widget.initialAction;
  bool _caseSensitive = false;
  bool _matchFullPath = false;
  String _kind = 'all';
  String Function(BuildContext)? _memoryMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    try {
      final patterns = await _history.load();
      final presets = await SavedSearchService().getAll();
      if (mounted) {
        setState(() {
          _recentPatterns = patterns;
          _presets = presets;
        });
      }
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
    for (final c in [_minimum, _maximum, _after, _before, _extensions]) {
      c.dispose();
    }
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

  FileSearchQuery _criteria() {
    int? size(String raw) {
      if (raw.trim().isEmpty) return null;
      final value = int.tryParse(raw.trim());
      if (value == null || value < 0) {
        throw FormatException(
          context.commanderTr("Enter a nonnegative size in bytes."),
        );
      }
      return value;
    }

    DateTime? date(String raw) {
      if (raw.trim().isEmpty) return null;
      final value = DateTime.tryParse(raw.trim());
      if (value == null) {
        throw FormatException(
          context.commanderTr("Enter an ISO date or date and time."),
        );
      }
      return value;
    }

    final query = FileSearchQuery(
      namePattern: _controller.text,
      nameMode: _mode,
      caseSensitive: _caseSensitive,
      matchFullPath: _matchFullPath,
      includeFiles: _kind != 'folders',
      includeFolders: _kind != 'files',
      includeHidden: _includeHidden,
      minSize: size(_minimum.text),
      maxSize: size(_maximum.text),
      modifiedAfter: date(_after.text),
      modifiedBefore: date(_before.text),
      extensions: _extensions.text
          .split(RegExp(r'[,;\s]+'))
          .map((s) => s.replaceFirst(RegExp(r'^\.'), '').toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
    query.validate();
    return query;
  }

  void _loadPreset(SavedSearch saved) {
    final query =
        saved.settings ??
        FileSearchQuery(
          namePattern: saved.query.isEmpty ? '*' : saved.query,
          extensions: saved.filterByType,
          minSize: saved.filterByMinSize,
          maxSize: saved.filterByMaxSize,
          modifiedAfter: saved.filterByDateAfter,
          modifiedBefore: saved.filterByDateBefore,
        );
    if (query.contentPattern.isNotEmpty || query.searchArchives) {
      setState(
        () => _memoryMessage = (context) => context.commanderTr(
          "Run this content or archive search first, then select its result rows.",
        ),
      );
      return;
    }
    _recall(query.nameMatcher);
    setState(() {
      _minimum.text = query.minSize?.toString() ?? '';
      _maximum.text = query.maxSize?.toString() ?? '';
      _after.text = query.modifiedAfter?.toIso8601String() ?? '';
      _before.text = query.modifiedBefore?.toIso8601String() ?? '';
      _extensions.text = query.extensions.join('; ');
      _includeHidden = query.includeHidden;
      _memoryMessage = (context) => context.commanderTr(
        "Loaded {0}. Selection applies to visible rows only.",
        [saved.name],
      );
    });
  }

  Future<void> _savePreset() async {
    final criteria = _criteria();
    final name = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.commanderTr("Save shared criteria")),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: context.commanderTr("Preset name"),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.commanderTr("Cancel")),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) {
                Navigator.pop(context, name.text.trim());
              }
            },
            child: Text(context.commanderTr("Save")),
          ),
        ],
      ),
    );
    name.dispose();
    if (value == null) return;
    try {
      await SavedSearchService().save(
        SavedSearch(
          name: value,
          query: criteria.namePattern,
          settings: criteria,
          createdAt: DateTime.now(),
        ),
      );
      await _loadHistory();
      if (mounted) {
        setState(
          () => _memoryMessage = (context) => context.commanderTr(
            "Saved {0} for search, selection, and transfer filters.",
            [value],
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _memoryMessage = (context) =>
                  context.commanderTr("Could not save criteria: {0}", [error]),
        );
      }
    }
  }

  Widget _criterionField(
    TextEditingController controller,
    String label,
    String key,
  ) => SizedBox(
    width: 230,
    child: TextField(
      key: ValueKey(key),
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) => setState(() {}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(panelProvider(widget.side));
    FileSelectionPattern? pattern;
    FileSearchQuery? criteria;
    String? error;
    try {
      criteria = _criteria();
      pattern = _pattern();
    } on FormatException catch (e) {
      error = e.message;
    }
    final displayed = panel.displayedFiles ?? [];
    final matches = pattern == null
        ? 0
        : displayed
              .where(
                (file) =>
                    file.name != '..' &&
                    pattern!.matches(file) &&
                    criteria!.matchesMetadata(file) &&
                    (criteria.includeHidden || !file.name.startsWith('.')),
              )
              .length;
    final restorable = panel.restorableSelectionCount;

    return AlertDialog(
      title: Text(context.commanderTr("Select by pattern")),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<FilePatternMode>(
                direction:
                    MediaQuery.sizeOf(context).width < 640 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? Axis.vertical
                    : Axis.horizontal,
                segments: [
                  ButtonSegment(
                    value: FilePatternMode.wildcard,
                    label: Text(context.commanderTr("Wildcards")),
                  ),
                  ButtonSegment(
                    value: FilePatternMode.regex,
                    label: Text(context.commanderTr("Regular expression")),
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
                      ? context.commanderTr("Masks")
                      : context.commanderTr("Expression"),
                  border: const OutlineInputBorder(),
                  suffixIcon: PopupMenuButton<FileSelectionPattern>(
                    key: const ValueKey('selection-pattern-history'),
                    tooltip: context.commanderTr("Recent patterns"),
                    enabled: _recentPatterns.isNotEmpty,
                    icon: const Icon(Icons.history),
                    onSelected: _recall,
                    itemBuilder: (_) => [
                      for (final recent in _recentPatterns)
                        PopupMenuItem(
                          value: recent,
                          child: Text(
                            '${recent.mode == FilePatternMode.regex ? context.commanderTr("Regex") : context.commanderTr("Wildcards")}: ${recent.expression}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  errorText: error,
                  errorMaxLines: 3,
                  helperText: _mode == FilePatternMode.wildcard
                      ? context.commanderTr(
                          "* any characters · ? one character\nSeparate masks with ; and exclusions with |\nExample: *.jpg;*.png|thumb*",
                        )
                      : context.commanderTr(
                          "Regex searches within names. Use ^ and \$ for a full match.\nExample: ^report-\\d+\\.pdf\$",
                        ),
                  helperMaxLines: 4,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SelectionAction>(
                isExpanded: true,
                initialValue: _action,
                decoration: InputDecoration(
                  labelText: context.commanderTr("Action"),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: SelectionAction.select,
                    child: Text(
                      context.commanderTr("Add matches to selection"),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: SelectionAction.deselect,
                    child: Text(
                      context.commanderTr("Remove matches from selection"),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: SelectionAction.invert,
                    child: Text(
                      context.commanderTr("Invert matching marks"),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: SelectionAction.replace,
                    child: Text(
                      context.commanderTr("Replace selection with matches"),
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
                decoration: InputDecoration(
                  labelText: context.commanderTr("Include"),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text(
                      context.commanderTr("Files and folders"),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'files',
                    child: Text(
                      context.commanderTr("Files only"),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'folders',
                    child: Text(
                      context.commanderTr("Folders only"),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _kind = value!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.commanderTr("Case sensitive")),
                value: _caseSensitive,
                onChanged: (value) => setState(() => _caseSensitive = value!),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.commanderTr("Match full original paths")),
                value: _matchFullPath,
                onChanged: (value) => setState(() => _matchFullPath = value!),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(context.commanderTr("Shared criteria and presets")),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    children: [
                      _criterionField(
                        _minimum,
                        context.commanderTr("Minimum size (bytes)"),
                        'selection-minimum',
                      ),
                      _criterionField(
                        _maximum,
                        context.commanderTr("Maximum size (bytes)"),
                        'selection-maximum',
                      ),
                      _criterionField(
                        _after,
                        context.commanderTr("Modified on or after (ISO)"),
                        'selection-after',
                      ),
                      _criterionField(
                        _before,
                        context.commanderTr("Modified on or before (ISO)"),
                        'selection-before',
                      ),
                      _criterionField(
                        _extensions,
                        context.commanderTr("Extensions (; separated)"),
                        'selection-extensions',
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.commanderTr("Include hidden names")),
                    value: _includeHidden,
                    onChanged: (value) =>
                        setState(() => _includeHidden = value!),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      PopupMenuButton<SavedSearch>(
                        tooltip: context.commanderTr(
                          "Load saved search criteria",
                        ),
                        enabled: _presets.isNotEmpty,
                        onSelected: _loadPreset,
                        itemBuilder: (_) => _presets
                            .map(
                              (saved) => PopupMenuItem(
                                value: saved,
                                child: Text(saved.name),
                              ),
                            )
                            .toList(),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            context.commanderTr("Load shared criteria"),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: criteria == null ? null : _savePreset,
                        child: Text(
                          context.commanderTr("Save shared criteria"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                context.commanderTr(
                  "{0} matching item(s) in the visible list",
                  [matches],
                ),
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
                              _memoryMessage = (context) => count == 0
                                  ? context.commanderTr(
                                      "Refresh the source before remembering its selection.",
                                    )
                                  : context.commanderTr(
                                      "Remembered {0} selected item(s) for this tab.",
                                      [count],
                                    );
                            });
                          },
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(context.commanderTr("Remember selection")),
                  ),
                  TextButton.icon(
                    key: const ValueKey('restore-panel-selection'),
                    onPressed: restorable == 0
                        ? null
                        : () {
                            final count = panel.restoreSelection();
                            setState(() {
                              _memoryMessage = (context) => context.commanderTr(
                                "Restored {0} selected item(s).",
                                [count],
                              );
                            });
                          },
                    icon: const Icon(Icons.restore),
                    label: Text(
                      context.commanderTr("Restore selection ({0})", [
                        restorable,
                      ]),
                    ),
                  ),
                ],
              ),
              Text(
                _memoryMessage?.call(context) ??
                    context.commanderTr(
                      "Remembered marks stay in this tab for the current session. Restore includes only visible, verified original paths.",
                    ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.commanderTr("Cancel")),
        ),
        FilledButton(
          key: const ValueKey('apply-pattern-selection'),
          onPressed: pattern == null ? null : () => _apply(pattern!),
          child: Text(context.commanderTr("Apply")),
        ),
      ],
    );
  }

  void _apply(FileSelectionPattern pattern) {
    ref
        .read(panelProvider(widget.side))
        .applyCriteriaSelection(_criteria(), action: _action);
    unawaited(
      _history.remember(pattern).catchError((Object error) {
        _log.warn('Selection pattern history could not be saved', error);
      }),
    );
    Navigator.pop(context);
  }
}
