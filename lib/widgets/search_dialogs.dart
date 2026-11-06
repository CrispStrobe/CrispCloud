import '../l10n/commander_strings.dart';
// lib/widgets/search_dialogs.dart
//
// Search and find dialogs, extracted from file_context_menu.dart.
// Used by both the context menu and the toolbar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/file_search_query.dart';
import '../services/file_selection_pattern.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/file_list_paths.dart';
import 'file_list_view.dart' show getFileIcon;
import 'saved_searches_dialog.dart'
    show showSavedSearchesDialog, showSaveSearchDialog;
import '../l10n/app_localizations.dart';
import '../l10n/search_dialog_strings.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

void showSearchDialog(BuildContext context, WidgetRef ref) =>
    showFindDialog(context, ref);

void showFindDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (dialogContext) => _FindDialog(panelContext: context, ref: ref),
  );
}

void showSearchResultsDialog(
  BuildContext context,
  WidgetRef ref,
  String query,
  List<FileItem> folders,
  List<FileItem> files, {
  Map<String, String>? snippets,
  PanelSide side = PanelSide.remote,
  List<String> messages = const [],
}) {
  final allItems = [...folders, ...files];
  final selected = Set<FileItem>.identity();

  Future<void> openParent(BuildContext dialogContext, FileItem item) async {
    try {
      final panel = ref.read(panelProvider(side));
      final origin =
          ref.read(searchProvider).originForResult(item) ??
          panel.originForOperation(item);
      if (origin == null || !origin.isCurrent || item.path == null) {
        throw StateError(
          'The original source is no longer current. Run the search again.',
        );
      }
      await panel.navigateToPath(
        p.dirname(item.path!),
        selectItem: item,
        origin: origin,
      );
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      panel.focusList();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: Text(SearchDialogStrings(ctx).value('results', query)),
        content: SizedBox(
          width: 720,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (messages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    messages.join('\n'),
                    maxLines: 4,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ),
              if (allItems.isNotEmpty)
                Row(
                  children: [
                    Checkbox(
                      tristate: true,
                      value: selected.isEmpty
                          ? false
                          : selected.length == allItems.length
                          ? true
                          : null,
                      onChanged: (_) => update(() {
                        if (selected.length == allItems.length) {
                          selected.clear();
                        } else {
                          selected.addAll(allItems);
                        }
                      }),
                    ),
                    Expanded(
                      child: Text(
                        '${allItems.length} result(s) · ${selected.length} selected',
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy paths'),
                      onPressed: () async {
                        try {
                          final targets = selected.isEmpty
                              ? allItems
                              : selected;
                          final paths = targets.map((item) {
                            if (item.path == null) {
                              throw StateError(
                                'A result has no original path.',
                              );
                            }
                            return item.path!;
                          });
                          await Clipboard.setData(
                            ClipboardData(text: FileListPaths.encode(paths)),
                          );
                        } catch (error) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(error.toString())),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              Expanded(
                child: allItems.isEmpty
                    ? Center(child: Text(SearchDialogStrings(ctx).text('none')))
                    : ListView.builder(
                        itemCount: allItems.length,
                        itemBuilder: (ctx2, index) {
                          final item = allItems[index];
                          final snippet = snippets?[item.path ?? item.name];
                          return ListTile(
                            selected: selected.contains(item),
                            leading: Checkbox(
                              value: selected.contains(item),
                              onChanged: (_) => update(() {
                                if (!selected.remove(item)) selected.add(item);
                              }),
                            ),
                            title: Row(
                              children: [
                                Icon(
                                  item.isFolder
                                      ? Icons.folder
                                      : getFileIcon(item.name),
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Expanded(child: Text(p.basename(item.name))),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message:
                                      item.path ?? 'Original path unavailable',
                                  child: Text(
                                    item.path ?? 'Original path unavailable',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (snippet != null && snippet.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      snippet,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: IconButton(
                              tooltip: 'Open containing folder',
                              onPressed: item.path == null
                                  ? null
                                  : () => openParent(ctx, item),
                              icon: const Icon(Icons.folder_open),
                            ),
                            onTap: () => update(() {
                              if (!selected.remove(item)) selected.add(item);
                            }),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          if (allItems.isNotEmpty)
            FilledButton.icon(
              icon: const Icon(Icons.playlist_add, size: 16),
              label: Text(
                selected.isEmpty
                    ? 'Feed all to panel'
                    : 'Feed selected to panel',
              ),
              onPressed: () {
                final targets = selected.isEmpty
                    ? allItems
                    : allItems.where(selected.contains).toList();
                ref
                    .read(searchProvider)
                    .setSearchResults(
                      targets,
                      asFolder: true,
                      side: side,
                      title: 'Search: $query',
                    );
                ref.read(activePanelProvider.notifier).state = side;
                Navigator.pop(ctx);
                ref.read(panelProvider(side)).focusList();
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.close),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Find dialog with advanced filters
// ---------------------------------------------------------------------------

class _FindDialog extends StatefulWidget {
  final BuildContext panelContext;
  final WidgetRef ref;

  const _FindDialog({required this.panelContext, required this.ref});

  @override
  State<_FindDialog> createState() => _FindDialogState();
}

class _FindDialogState extends State<_FindDialog> {
  final _patternCtrl = TextEditingController(text: '*');
  final _contentCtrl = TextEditingController();
  final _rootsCtrl = TextEditingController();
  final _excludeCtrl = TextEditingController();
  final _depthCtrl = TextEditingController();
  final _minSizeCtrl = TextEditingController();
  final _maxSizeCtrl = TextEditingController();
  bool _useRegex = false;
  bool _searchContents = false;
  bool _caseSensitive = false;
  bool _fullPath = false;
  bool _recursive = true;
  bool _includeFiles = true;
  bool _includeFolders = true;
  bool _includeHidden = true;
  bool _contentRegex = false;
  bool _contentCaseSensitive = false;
  bool _contentNegated = false;
  bool _searchArchives = false;
  bool _running = false;
  String _encoding = 'auto';
  String? _error;
  final Set<FileTypeCategory> _selectedCategories = {};
  _SizeUnit _minSizeUnit = _SizeUnit.kb;
  _SizeUnit _maxSizeUnit = _SizeUnit.mb;
  DateTime? _dateAfter;
  DateTime? _dateBefore;
  late final PanelSide _side;
  late final SearchNotifier _search;

  @override
  void initState() {
    super.initState();
    _side = widget.ref.read(activePanelProvider);
    _search = widget.ref.read(searchProvider)..addListener(_changed);
    _rootsCtrl.text = widget.ref.read(panelProvider(_side)).currentPath;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _search.removeListener(_changed);
    if (_running) _search.cancelSearch();
    for (final controller in [
      _patternCtrl,
      _contentCtrl,
      _rootsCtrl,
      _excludeCtrl,
      _depthCtrl,
      _minSizeCtrl,
      _maxSizeCtrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  FileSearchQuery _query() {
    int? bytes(TextEditingController controller, _SizeUnit unit) {
      if (controller.text.trim().isEmpty) return null;
      final value = double.tryParse(controller.text);
      if (value == null || !value.isFinite || value < 0) {
        throw const FormatException('Enter valid non-negative file sizes.');
      }
      return (value * unit.multiplier).round();
    }

    final depth = _depthCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_depthCtrl.text);
    if (_depthCtrl.text.trim().isNotEmpty && depth == null) {
      throw const FormatException('Depth must be a whole number.');
    }
    if (_searchContents && _contentCtrl.text.isEmpty) {
      throw const FormatException('Enter the content to find.');
    }
    final query = FileSearchQuery(
      namePattern: _patternCtrl.text,
      nameMode: _useRegex ? FilePatternMode.regex : FilePatternMode.wildcard,
      caseSensitive: _caseSensitive,
      matchFullPath: _fullPath,
      roots: _rootsCtrl.text
          .split('\n')
          .map((root) => root.trim())
          .where((root) => root.isNotEmpty)
          .toList(),
      recursive: _recursive,
      maxDepth: depth,
      includeFiles: _includeFiles,
      includeFolders: _includeFolders,
      includeHidden: _includeHidden,
      excludeDirectories: _excludeCtrl.text.trim(),
      contentPattern: _searchContents ? _contentCtrl.text : '',
      contentRegex: _contentRegex,
      contentCaseSensitive: _contentCaseSensitive,
      contentEncoding: _encoding,
      contentNegated: _contentNegated,
      searchArchives: _searchArchives,
      extensions: extensionsForCategories(_selectedCategories),
      minSize: bytes(_minSizeCtrl, _minSizeUnit),
      maxSize: bytes(_maxSizeCtrl, _maxSizeUnit),
      modifiedAfter: _dateAfter,
      modifiedBefore: _dateBefore,
    );
    query.validate();
    return query;
  }

  Future<void> _doFind() async {
    if (_running) return;
    try {
      final query = _query();
      setState(() {
        _running = true;
        _error = null;
      });
      final results = await _search.runQuery(query, side: _side);
      if (!mounted) return;
      setState(() => _running = false);
      if (results.isEmpty && _search.searchErrors.isNotEmpty) {
        setState(() => _error = _search.searchErrors.join('\n'));
        return;
      }
      final messages = [
        if (_search.wasCancelled)
          'Search cancelled; showing the results collected so far.',
        ..._search.searchErrors,
      ];
      Navigator.pop(context);
      if (widget.panelContext.mounted) {
        showSearchResultsDialog(
          widget.panelContext,
          widget.ref,
          query.namePattern,
          [],
          results,
          side: _side,
          snippets: _search.lastSnippets,
          messages: messages,
        );
      }
    } catch (error) {
      if (mounted)
        setState(() {
          _running = false;
          _error = error.toString();
        });
    }
  }

  Future<void> _save() async {
    try {
      final query = _query();
      _search.configureQuery(query);
      await showSaveSearchDialog(
        context,
        widget.ref,
        query: query.contentPattern.isEmpty
            ? query.namePattern
            : query.contentPattern,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _pickDate({required bool isAfter}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isAfter ? _dateAfter : _dateBefore) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted)
      setState(() {
        if (isAfter) {
          _dateAfter = picked;
        } else {
          _dateBefore = picked;
        }
      });
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> change) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Checkbox(
        value: value,
        onChanged: _running
            ? null
            : (value) => setState(() => change(value ?? false)),
      ),
      Text(label),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      'Find in ${_side == PanelSide.local ? 'left' : 'right'} panel source',
    ),
    content: SizedBox(
      width: 700,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _patternCtrl,
              enabled: !_running,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Filename mask or regex',
                helperText: '*.jpg;*.png|thumb*   •   Regex uses ^ and \$ for whole names',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _doFind(),
            ),
            Wrap(
              children: [
                _toggle('Regex', _useRegex, (v) => _useRegex = v),
                _toggle(
                  'Case sensitive',
                  _caseSensitive,
                  (v) => _caseSensitive = v,
                ),
                _toggle('Full path', _fullPath, (v) => _fullPath = v),
              ],
            ),
            TextField(
              controller: _rootsCtrl,
              enabled: !_running,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Search directories (one absolute path per line)',
                border: OutlineInputBorder(),
              ),
            ),
            Wrap(
              children: [
                _toggle('Subdirectories', _recursive, (v) => _recursive = v),
                _toggle('Files', _includeFiles, (v) => _includeFiles = v),
                _toggle('Folders', _includeFolders, (v) => _includeFolders = v),
                _toggle(
                  'Hidden items',
                  _includeHidden,
                  (v) => _includeHidden = v,
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _excludeCtrl,
                    enabled: !_running,
                    decoration: const InputDecoration(
                      labelText: 'Exclude directories (e.g. .git;node_modules)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _depthCtrl,
                    enabled: !_running && _recursive,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Maximum depth',
                      hintText: 'Unlimited',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            Wrap(
              children: [
                _toggle(
                  'Search contents',
                  _searchContents,
                  (v) => _searchContents = v,
                ),
                _toggle(
                  'Search inside archives',
                  _searchArchives,
                  (v) => _searchArchives = v,
                ),
              ],
            ),
            if (_searchContents) ...[
              TextField(
                controller: _contentCtrl,
                enabled: !_running,
                decoration: const InputDecoration(
                  labelText: 'Containing text or regex',
                  border: OutlineInputBorder(),
                ),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _toggle(
                    'Content regex',
                    _contentRegex,
                    (v) => _contentRegex = v,
                  ),
                  _toggle(
                    'Case sensitive',
                    _contentCaseSensitive,
                    (v) => _contentCaseSensitive = v,
                  ),
                  _toggle(
                    'Does not contain',
                    _contentNegated,
                    (v) => _contentNegated = v,
                  ),
                  DropdownButton<String>(
                    value: _encoding,
                    items: [
                      for (final encoding in [
                        'auto',
                        'utf8',
                        'utf16le',
                        'utf16be',
                        'utf32le',
                        'utf32be',
                        'latin1',
                      ])
                        DropdownMenuItem(
                          value: encoding,
                          child: Text(encoding),
                        ),
                    ],
                    onChanged: _running
                        ? null
                        : (value) => setState(() => _encoding = value!),
                  ),
                ],
              ),
              Text(
                context.commanderTr(
                  "Literal text search scans the complete file with bounded memory. Regex, Office documents, and archive members use a 64 MiB text limit; files beyond it are reported. Symbolic links are not followed.",
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (_searchArchives)
              const Text(
                'Archive hits refer to the containing archive. The matching member appears in the result details.',
                style: const TextStyle(fontSize: 12),
              ),
            const Divider(),
            Wrap(
              spacing: 6,
              children: [
                for (final category in FileTypeCategory.values)
                  FilterChip(
                    label: Text(_categoryLabel(context, category)),
                    selected: _selectedCategories.contains(category),
                    onSelected: _running
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              _selectedCategories.add(category);
                            } else {
                              _selectedCategories.remove(category);
                            }
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minSizeCtrl,
                    enabled: !_running,
                    decoration: const InputDecoration(
                      labelText: 'Minimum size',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                _SizeUnitDropdown(
                  value: _minSizeUnit,
                  onChanged: (value) => setState(() => _minSizeUnit = value),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _maxSizeCtrl,
                    enabled: !_running,
                    decoration: const InputDecoration(
                      labelText: 'Maximum size',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                _SizeUnitDropdown(
                  value: _maxSizeUnit,
                  onChanged: (value) => setState(() => _maxSizeUnit = value),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _DatePickerTile(
                    label: 'Modified after',
                    date: _dateAfter,
                    onTap: () => _pickDate(isAfter: true),
                    onClear: () => setState(() => _dateAfter = null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DatePickerTile(
                    label: 'Modified before',
                    date: _dateBefore,
                    onTap: () => _pickDate(isAfter: false),
                    onClear: () => setState(() => _dateBefore = null),
                  ),
                ),
              ],
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_running) ...[
              const LinearProgressIndicator(),
              Text(
                '${_search.scannedCount} items searched • ${_search.searchResults.length} results',
              ),
              for (final item in _search.searchResults.reversed.take(6))
                Text(
                  item.path ?? item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _running
            ? null
            : () {
                Navigator.pop(context);
                showSavedSearchesDialog(widget.panelContext, widget.ref);
              },
        child: const Text('Saved searches'),
      ),
      TextButton(
        onPressed: _running ? null : _save,
        child: const Text('Save query'),
      ),
      TextButton(
        onPressed: _running
            ? _search.cancelSearch
            : () => Navigator.pop(context),
        child: Text(_running ? 'Stop search' : 'Cancel'),
      ),
      FilledButton(
        onPressed: _running ? null : _doFind,
        child: const Text('Find'),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Small helper widgets
// ---------------------------------------------------------------------------

enum _SizeUnit {
  kb('KB', 1024),
  mb('MB', 1024 * 1024),
  gb('GB', 1024 * 1024 * 1024);

  const _SizeUnit(this.label, this.multiplier);
  final String label;
  final int multiplier;
}

class _SizeUnitDropdown extends StatelessWidget {
  final _SizeUnit value;
  final ValueChanged<_SizeUnit> onChanged;

  const _SizeUnitDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<_SizeUnit>(
      value: value,
      isDense: true,
      underline: const SizedBox(),
      items: _SizeUnit.values
          .map((u) => DropdownMenuItem(value: u, child: Text(u.label)))
          .toList(),
      onChanged: (u) {
        if (u != null) onChanged(u);
      },
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        side: BorderSide(color: colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 14,
            color: colorScheme.onSurface,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              date != null ? '$label: ${_fmt(date!)}' : label,
              style: TextStyle(
                fontSize: 12,
                color: date != null
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: Icon(
                Icons.close,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _categoryLabel(BuildContext context, FileTypeCategory cat) {
  switch (cat) {
    case FileTypeCategory.documents:
      return SearchDialogStrings(context).text('documents');
    case FileTypeCategory.images:
      return SearchDialogStrings(context).text('images');
    case FileTypeCategory.videos:
      return SearchDialogStrings(context).text('videos');
    case FileTypeCategory.audio:
      return SearchDialogStrings(context).text('audio');
    case FileTypeCategory.archives:
      return SearchDialogStrings(context).text('archives');
    case FileTypeCategory.code:
      return SearchDialogStrings(context).text('code');
  }
}
