// lib/widgets/search_dialogs.dart
//
// Search and find dialogs, extracted from file_context_menu.dart.
// Used by both the context menu and the toolbar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../providers/search_provider.dart';
import 'file_list_view.dart' show getFileIcon;
import 'saved_searches_dialog.dart'
    show showSavedSearchesDialog, showSaveSearchDialog;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

void showSearchDialog(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  final panelContext = context;

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Fuzzy Search (All Files)'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Search query',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.search),
        ),
        autofocus: true,
        onSubmitted: (value) async {
          if (value.isNotEmpty) {
            Navigator.pop(dialogContext);
            final results = await ref.read(searchProvider).searchFiles(value);
            if (panelContext.mounted) {
              showSearchResultsDialog(panelContext, ref, value,
                  results['folders'] ?? [], results['files'] ?? []);
            }
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (controller.text.isNotEmpty) {
              Navigator.pop(dialogContext);
              final results =
                  await ref.read(searchProvider).searchFiles(controller.text);
              if (panelContext.mounted) {
                showSearchResultsDialog(panelContext, ref, controller.text,
                    results['folders'] ?? [], results['files'] ?? []);
              }
            }
          },
          child: const Text('Search'),
        ),
      ],
    ),
  );
}

void showFindDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (dialogContext) => _FindDialog(panelContext: context, ref: ref),
  );
}

void showSearchResultsDialog(BuildContext context, WidgetRef ref,
    String query, List<FileItem> folders, List<FileItem> files) {
  final allItems = [...folders, ...files];

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Search Results for "$query"'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: allItems.isEmpty
            ? const Center(child: Text('No results found.'))
            : ListView.builder(
                itemCount: allItems.length,
                itemBuilder: (ctx2, index) {
                  final item = allItems[index];
                  return ListTile(
                    leading:
                        Icon(item.isFolder ? Icons.folder : getFileIcon(item.name)),
                    title: Text(p.basename(item.name)),
                    subtitle: Text(
                      p.dirname(item.path ?? '/'),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      if (item.path != null) {
                        final parentPath = p.dirname(item.path!);
                        ref
                            .read(panelProvider(PanelSide.remote))
                            .navigateToPath(parentPath, selectItem: item);
                        Navigator.pop(ctx);
                      }
                    },
                  );
                },
              ),
      ),
      actions: [
        if (allItems.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.folder_special_outlined, size: 16),
            label: const Text('Show as Folder'),
            onPressed: () {
              ref
                  .read(searchProvider)
                  .setSearchResults(allItems, asFolder: true);
              Navigator.pop(ctx);
            },
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
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
  final _patternCtrl = TextEditingController();
  final _minSizeCtrl = TextEditingController();
  final _maxSizeCtrl = TextEditingController();

  bool _useRegex = false;

  // Type-filter chips
  final Set<FileTypeCategory> _selectedCategories = {};

  // Size units
  _SizeUnit _minSizeUnit = _SizeUnit.kb;
  _SizeUnit _maxSizeUnit = _SizeUnit.mb;

  // Date range
  DateTime? _dateAfter;
  DateTime? _dateBefore;

  @override
  void initState() {
    super.initState();
    _patternCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _patternCtrl.dispose();
    _minSizeCtrl.dispose();
    _maxSizeCtrl.dispose();
    super.dispose();
  }

  String get _remotePath =>
      widget.ref.read(panelProvider(PanelSide.remote)).currentPath;

  // Build filters from UI state and push them to the search provider
  void _applyFiltersToProvider() {
    final search = widget.ref.read(searchProvider);
    // Start from a clean slate so stale values from a previous search are gone.
    search.clearFilters();

    final extensions = extensionsForCategories(_selectedCategories);

    int? minBytes;
    if (_minSizeCtrl.text.isNotEmpty) {
      final v = double.tryParse(_minSizeCtrl.text);
      if (v != null) minBytes = (v * _minSizeUnit.multiplier).round();
    }
    int? maxBytes;
    if (_maxSizeCtrl.text.isNotEmpty) {
      final v = double.tryParse(_maxSizeCtrl.text);
      if (v != null) maxBytes = (v * _maxSizeUnit.multiplier).round();
    }

    search.setFilters(
      filterByType: extensions,
      filterByMinSize: minBytes,
      filterByMaxSize: maxBytes,
      filterByDateAfter: _dateAfter,
      filterByDateBefore: _dateBefore,
    );
  }

  Future<void> _doFind() async {
    if (_patternCtrl.text.isEmpty) return;
    _applyFiltersToProvider();
    Navigator.pop(context);

    final ref = widget.ref;
    final panelCtx = widget.panelContext;

    if (_useRegex) {
      try {
        final regex = RegExp(_patternCtrl.text, caseSensitive: false);
        final activePanel = ref.read(activePanelProvider);
        final panel = ref.read(panelProvider(activePanel));
        final allFiles =
            panel.files?.where((f) => regex.hasMatch(f.name)).toList() ?? [];
        final filtered = ref.read(searchProvider).applyFilters(allFiles);
        if (panelCtx.mounted) {
          showSearchResultsDialog(panelCtx, ref, _patternCtrl.text, [], filtered);
        }
      } catch (e) {
        if (panelCtx.mounted) {
          ScaffoldMessenger.of(panelCtx).showSnackBar(
            SnackBar(content: Text('Invalid regex: $e')),
          );
        }
      }
    } else {
      final results = await ref.read(searchProvider).findFiles(_patternCtrl.text);
      if (panelCtx.mounted) {
        showSearchResultsDialog(panelCtx, ref, _patternCtrl.text, [], results);
      }
    }
  }

  Future<void> _pickDate({required bool isAfter}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isAfter ? _dateAfter : _dateBefore) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isAfter) {
          _dateAfter = picked;
        } else {
          _dateBefore = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Find in "${p.basename(_remotePath)}"'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pattern field
            TextField(
              controller: _patternCtrl,
              decoration: InputDecoration(
                labelText: _useRegex
                    ? 'Regex pattern'
                    : 'Pattern (e.g. *.pdf, report-*)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.find_in_page),
              ),
              autofocus: true,
              onSubmitted: (_) => _doFind(),
            ),
            const SizedBox(height: 8),

            // Regex toggle
            Row(
              children: [
                Checkbox(
                  value: _useRegex,
                  onChanged: (v) => setState(() => _useRegex = v ?? false),
                ),
                const Text('Use regex', style: TextStyle(fontSize: 13)),
                const Spacer(),
                if (_useRegex)
                  Text(
                    'Filters current listing',
                    style: TextStyle(
                        fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),

            const Divider(height: 20),

            // --- File type chips ---
            Text('File type',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: FileTypeCategory.values.map((cat) {
                final selected = _selectedCategories.contains(cat);
                return FilterChip(
                  label: Text(_categoryLabel(cat)),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _selectedCategories.add(cat);
                    } else {
                      _selectedCategories.remove(cat);
                    }
                  }),
                );
              }).toList(),
            ),

            const Divider(height: 20),

            // --- Size range ---
            Text('Size',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minSizeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Min',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'))
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _SizeUnitDropdown(
                  value: _minSizeUnit,
                  onChanged: (u) => setState(() => _minSizeUnit = u),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxSizeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Max',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'))
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _SizeUnitDropdown(
                  value: _maxSizeUnit,
                  onChanged: (u) => setState(() => _maxSizeUnit = u),
                ),
              ],
            ),

            const Divider(height: 20),

            // --- Date range ---
            Text('Modified date',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _DatePickerTile(
                    label: 'After',
                    date: _dateAfter,
                    onTap: () => _pickDate(isAfter: true),
                    onClear: _dateAfter != null
                        ? () => setState(() => _dateAfter = null)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DatePickerTile(
                    label: 'Before',
                    date: _dateBefore,
                    onTap: () => _pickDate(isAfter: false),
                    onClear: _dateBefore != null
                        ? () => setState(() => _dateBefore = null)
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        // Saved Searches
        TextButton.icon(
          icon: const Icon(Icons.bookmarks_outlined, size: 16),
          label: const Text('Saved'),
          onPressed: () {
            Navigator.pop(context);
            showSavedSearchesDialog(widget.panelContext, widget.ref);
          },
        ),
        // Save Current Search
        TextButton.icon(
          icon: const Icon(Icons.bookmark_add_outlined, size: 16),
          label: const Text('Save'),
          onPressed: _patternCtrl.text.isEmpty
              ? null
              : () async {
                  // Apply filters before saving so state is captured
                  _applyFiltersToProvider();
                  await showSaveSearchDialog(
                    context,
                    widget.ref,
                    query: _patternCtrl.text,
                  );
                },
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _doFind,
          child: const Text('Find'),
        ),
      ],
    );
  }
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
          Icon(Icons.calendar_today_outlined, size: 14,
              color: colorScheme.onSurface),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              date != null
                  ? '$label: ${_fmt(date!)}'
                  : label,
              style: TextStyle(
                  fontSize: 12,
                  color: date != null
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: Icon(Icons.close, size: 14, color: colorScheme.onSurfaceVariant),
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

String _categoryLabel(FileTypeCategory cat) {
  switch (cat) {
    case FileTypeCategory.documents:
      return 'Documents';
    case FileTypeCategory.images:
      return 'Images';
    case FileTypeCategory.videos:
      return 'Videos';
    case FileTypeCategory.audio:
      return 'Audio';
    case FileTypeCategory.archives:
      return 'Archives';
    case FileTypeCategory.code:
      return 'Code';
  }
}
