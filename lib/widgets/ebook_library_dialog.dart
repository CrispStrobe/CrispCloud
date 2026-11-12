import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/ebook_library.dart';

String _identity(String value) => value;

/// A catalog browser only. The host owns account resolution and file access.
class EbookLibraryDialog extends StatefulWidget {
  const EbookLibraryDialog({
    super.key,
    required this.library,
    required this.onOpen,
    required this.onLocate,
    this.translate = _identity,
    this.errorMessage,
    this.currentEntryId,
  });

  final EbookLibrary library;
  final FutureOr<void> Function(EbookLibraryEntry entry) onOpen;
  final FutureOr<void> Function(EbookLibraryEntry entry) onLocate;
  final String Function(String value) translate;
  final String Function(Object error)? errorMessage;
  final String? currentEntryId;

  @override
  State<EbookLibraryDialog> createState() => _EbookLibraryDialogState();
}

class _EbookLibraryDialogState extends State<EbookLibraryDialog> {
  final _search = TextEditingController();
  final _shelf = TextEditingController();
  final _tag = TextEditingController();
  bool _favoritesOnly = false;
  EbookReadingStatus? _status;
  EbookLibrarySort _sort = EbookLibrarySort.recent;
  bool _working = false;
  String? _error;

  String _tr(String text) => widget.translate(text);

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant EbookLibraryDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != widget.library) {
      oldWidget.library.removeListener(_changed);
      widget.library.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(FutureOr<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _errorText(error, widget.errorMessage, _tr));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _edit(EbookLibraryEntry entry) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LibraryEntryEditor(
      library: widget.library,
      entry: entry,
      translate: widget.translate,
      errorMessage: widget.errorMessage,
    ),
  );

  Future<void> _remove(EbookLibraryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tr('Remove this book from the library?')),
        content: SingleChildScrollView(
          child: Text(
            '${entry.title}\n\n${_tr('The book file and its reading data will remain available.')}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('ebook-library-confirm-remove'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_tr('Remove')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => widget.library.remove(entry.id));
    }
  }

  @override
  void dispose() {
    widget.library.removeListener(_changed);
    _search.dispose();
    _shelf.dispose();
    _tag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final available = media.size.height - media.viewInsets.bottom;
    final entries = widget.library.query(
      text: _search.text,
      favoritesOnly: _favoritesOnly,
      shelf: _shelf.text.trim().isEmpty ? null : _shelf.text.trim(),
      tag: _tag.text.trim().isEmpty ? null : _tag.text.trim(),
      status: _status,
      sort: _sort,
    );
    return PopScope(
      canPop: !_working,
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(12),
        title: Row(
          children: [
            Expanded(child: Text(_tr('Ebook library'))),
            IconButton(
              key: const ValueKey('ebook-library-refresh'),
              tooltip: _tr('Refresh'),
              onPressed: _working ? null : () => _run(widget.library.reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        content: SizedBox(
          width: 900,
          height: math.max(80, math.min(640, available - 180)).toDouble(),
          child: Column(
            children: [
              if (_working) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    key: const ValueKey('ebook-library-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: CustomScrollView(
                  key: const ValueKey('ebook-library-scroll'),
                  slivers: [
                    SliverToBoxAdapter(child: _filters()),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('${_tr('Books')}: ${entries.length}'),
                      ),
                    ),
                    if (entries.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            _tr(
                              widget.library.entries.isEmpty
                                  ? 'Books you open appear here.'
                                  : 'No books match these filters.',
                            ),
                          ),
                        ),
                      ),
                    SliverList.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) => _row(entries[index]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _working ? null : () => Navigator.pop(context),
            child: Text(_tr('Close')),
          ),
        ],
      ),
    );
  }

  Widget _filters() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        key: const ValueKey('ebook-library-search'),
        controller: _search,
        maxLength: 256,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: _tr('Search books, authors, tags or shelves'),
          prefixIcon: const Icon(Icons.search),
          counterText: '',
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            key: const ValueKey('ebook-library-filter-favorites'),
            label: Text(_tr('Favorites only')),
            selected: _favoritesOnly,
            onSelected: (value) => setState(() => _favoritesOnly = value),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<EbookReadingStatus?>(
              key: const ValueKey('ebook-library-status-filter'),
              initialValue: _status,
              isExpanded: true,
              decoration: InputDecoration(labelText: _tr('Reading status')),
              items: [
                DropdownMenuItem(value: null, child: Text(_tr('All statuses'))),
                for (final status in EbookReadingStatus.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(_tr(_statusText(status))),
                  ),
              ],
              onChanged: (value) => setState(() => _status = value),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<EbookLibrarySort>(
              key: const ValueKey('ebook-library-sort'),
              initialValue: _sort,
              isExpanded: true,
              decoration: InputDecoration(labelText: _tr('Sort')),
              items: [
                for (final sort in EbookLibrarySort.values)
                  DropdownMenuItem(
                    value: sort,
                    child: Text(_tr(_sortText(sort))),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _sort = value);
              },
            ),
          ),
          _labelFilter(
            controller: _shelf,
            name: 'Shelf',
            keyName: 'shelf',
            suggestions: widget.library.shelves,
          ),
          _labelFilter(
            controller: _tag,
            name: 'Tag',
            keyName: 'tag',
            suggestions: widget.library.tags,
          ),
        ],
      ),
    ],
  );

  /// A free-text exact filter can reach every label. Suggestions are bounded;
  /// a catalog with many unique tags never creates a giant popup widget tree.
  Widget _labelFilter({
    required TextEditingController controller,
    required String name,
    required String keyName,
    required List<String> suggestions,
  }) => SizedBox(
    width: 170,
    child: Autocomplete<String>(
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        return suggestions
            .where((item) => item.toLowerCase().contains(query))
            .take(30);
      },
      onSelected: (value) {
        controller.text = value;
        setState(() {});
      },
      fieldViewBuilder: (context, textController, focus, onSubmit) => TextField(
        key: ValueKey('ebook-library-$keyName-filter'),
        controller: textController,
        focusNode: focus,
        maxLength: 100,
        decoration: InputDecoration(
          labelText: _tr(name),
          hintText: _tr('Exact name'),
          counterText: '',
        ),
        onChanged: (value) {
          controller.text = value;
          setState(() {});
        },
        onSubmitted: (_) => onSubmit(),
      ),
    ),
  );

  Widget _row(EbookLibraryEntry entry) {
    final current = entry.id == widget.currentEntryId;
    final progress = entry.progress;
    final date = MaterialLocalizations.of(context)
        .formatCompactDate(entry.lastOpenedAt.toLocal());
    return Card(
      key: ValueKey('ebook-library-entry-${entry.id}'),
      color: current ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (entry.authors.isNotEmpty)
              Text(
                entry.authors.join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Text(
              '${entry.format.toUpperCase()} · ${_tr(_statusText(entry.status))} · ${progress == null ? _tr('Progress not recorded') : '${(progress * 100).round()}%'}',
            ),
            if (progress != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: LinearProgressIndicator(value: progress),
              ),
            Text('${_tr('Last opened')}: $date'),
            if (current)
              Text(
                _tr('Current book'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            if (entry.shelves.isNotEmpty)
              Text(
                '${_tr('Shelf')}: ${entry.shelves.join(', ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (entry.tags.isNotEmpty)
              Text(
                '${_tr('Tag')}: ${entry.tags.join(', ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (!entry.canLocateSource)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_tr('Locate this file manually to read it again.')),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  key: ValueKey('ebook-library-favorite-${entry.id}'),
                  tooltip: _tr('Favorite'),
                  isSelected: entry.favorite,
                  icon: const Icon(Icons.star_border),
                  selectedIcon: const Icon(Icons.star),
                  onPressed: _working
                      ? null
                      : () => _run(() async {
                          await widget.library.update(
                            entry.id,
                            favorite: !entry.favorite,
                          );
                        }),
                ),
                OutlinedButton.icon(
                  key: ValueKey('ebook-library-open-${entry.id}'),
                  onPressed: _working || !entry.canLocateSource
                      ? null
                      : () => _run(() => widget.onOpen(entry)),
                  icon: const Icon(Icons.menu_book),
                  label: Text(_tr('Open book')),
                ),
                TextButton.icon(
                  key: ValueKey('ebook-library-locate-${entry.id}'),
                  onPressed: _working
                      ? null
                      : () => _run(() => widget.onLocate(entry)),
                  icon: const Icon(Icons.folder_open),
                  label: Text(_tr('Locate file')),
                ),
                IconButton(
                  key: ValueKey('ebook-library-edit-${entry.id}'),
                  tooltip: _tr('Edit library entry'),
                  onPressed: _working ? null : () => _edit(entry),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  key: ValueKey('ebook-library-remove-${entry.id}'),
                  tooltip: _tr('Remove from library'),
                  onPressed: _working ? null : () => _remove(entry),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryEntryEditor extends StatefulWidget {
  const _LibraryEntryEditor({
    required this.library,
    required this.entry,
    required this.translate,
    this.errorMessage,
  });
  final EbookLibrary library;
  final EbookLibraryEntry entry;
  final String Function(String) translate;
  final String Function(Object)? errorMessage;
  @override
  State<_LibraryEntryEditor> createState() => _LibraryEntryEditorState();
}

class _LibraryEntryEditorState extends State<_LibraryEntryEditor> {
  late final TextEditingController _tags;
  late final TextEditingController _shelves;
  late bool _favorite;
  late EbookReadingStatus _status;
  bool _saving = false;
  String? _error;
  String _tr(String value) => widget.translate(value);

  @override
  void initState() {
    super.initState();
    _tags = TextEditingController(text: widget.entry.tags.join('\n'));
    _shelves = TextEditingController(text: widget.entry.shelves.join('\n'));
    _favorite = widget.entry.favorite;
    _status = widget.entry.status;
  }

  bool get _changed =>
      _tags.text != widget.entry.tags.join('\n') ||
      _shelves.text != widget.entry.shelves.join('\n') ||
      _favorite != widget.entry.favorite ||
      _status != widget.entry.status;

  Future<void> _save() async {
    if (_saving || !_changed) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.library.update(
        widget.entry.id,
        favorite: _favorite == widget.entry.favorite ? null : _favorite,
        status: _status == widget.entry.status ? null : _status,
        tags: _tags.text == widget.entry.tags.join('\n')
            ? null
            : _tags.text.split(RegExp(r'\r?\n')),
        shelves: _shelves.text == widget.entry.shelves.join('\n')
            ? null
            : _shelves.text.split(RegExp(r'\r?\n')),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _error = _errorText(error, widget.errorMessage, _tr));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _tags.dispose();
    _shelves.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(_tr('Edit library entry')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _error!,
                    key: const ValueKey('ebook-library-edit-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_tr('Favorite')),
                value: _favorite,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _favorite = value ?? false),
              ),
              DropdownButtonFormField<EbookReadingStatus>(
                key: const ValueKey('ebook-library-edit-status'),
                initialValue: _status,
                decoration: InputDecoration(labelText: _tr('Reading status')),
                items: [
                  for (final status in EbookReadingStatus.values)
                    DropdownMenuItem(
                      value: status,
                      child: Text(_tr(_statusText(status))),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _status = value);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('ebook-library-edit-shelves'),
                controller: _shelves,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                maxLength: 5100,
                decoration: InputDecoration(
                  labelText: _tr('Shelves (one per line)'),
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                key: const ValueKey('ebook-library-edit-tags'),
                controller: _tags,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                maxLength: 5100,
                decoration: InputDecoration(
                  labelText: _tr('Tags (one per line)'),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(_tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('ebook-library-edit-save'),
          onPressed: _saving || !_changed ? null : _save,
          child: Text(_tr('Save')),
        ),
      ],
    ),
  );
}

String _statusText(EbookReadingStatus status) => switch (status) {
  EbookReadingStatus.unread => 'Unread',
  EbookReadingStatus.reading => 'Reading',
  EbookReadingStatus.completed => 'Completed',
};

String _sortText(EbookLibrarySort sort) => switch (sort) {
  EbookLibrarySort.recent => 'Recently opened',
  EbookLibrarySort.title => 'Title',
  EbookLibrarySort.author => 'Author',
  EbookLibrarySort.progress => 'Reading progress',
};

String _errorText(
  Object error,
  String Function(Object)? formatter,
  String Function(String) translate,
) =>
    formatter?.call(error) ??
    translate(switch (error) {
      FormatException() => error.message,
      StateError() => error.message,
      _ => error.toString(),
    });
