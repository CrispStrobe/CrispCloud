import 'dart:math';

import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Browses a fixed catalog scope without changing its active tag filters.
/// The caller rechecks the connection and catalog before applying the result.
class ZoteroTagBrowserDialog extends StatefulWidget {
  const ZoteroTagBrowserDialog({
    super.key,
    required this.client,
    required this.library,
    required this.activeTags,
    this.collectionKey,
    this.scopeLabel = 'Library tags',
  });

  final ZoteroClient client;
  final ZoteroLibrary library;
  final String? collectionKey;
  final String scopeLabel;
  final List<String> activeTags;

  @override
  State<ZoteroTagBrowserDialog> createState() => _ZoteroTagBrowserDialogState();
}

class _ZoteroTagBrowserDialogState extends State<ZoteroTagBrowserDialog> {
  final _query = TextEditingController();
  final _resultsScroll = ScrollController();
  late final List<String> _selected;
  List<ZoteroTag> _tags = const [];
  ZoteroPage<ZoteroTag>? _page;
  var _mode = ZoteroTagSearchMode.contains;
  String _submittedQuery = '';
  String? _error;
  String? _selectionError;
  var _busy = false;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _selected = List.of(widget.activeTags);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  Future<void> _load({int start = 0, bool submit = false}) async {
    if (_busy) return;
    final generation = ++_generation;
    if (submit) _submittedQuery = _query.text;
    setState(() {
      _busy = true;
      _error = null;
      _tags = const [];
      _page = null;
    });
    try {
      final page = await widget.client.tags(
        widget.library,
        collectionKey: widget.collectionKey,
        query: _submittedQuery,
        searchMode: _mode,
        start: start,
        limit: 50,
      );
      if (!mounted || generation != _generation) return;
      // A name can occur as both an automatic and a manual tag. Filters use
      // literal names, so show one choice and never add the counts together.
      final byName = <String, ZoteroTag>{};
      for (final tag in page.items) {
        final existing = byName[tag.name];
        byName[tag.name] = existing == null ? tag : ZoteroTag(name: tag.name);
      }
      setState(() {
        _page = page;
        _tags = List.unmodifiable(byName.values);
      });
      if (_resultsScroll.hasClients) _resultsScroll.jumpTo(0);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = switch (error) {
          ZoteroApiException value => value.message,
          FormatException value => value.message,
          ArgumentError _ =>
            'Use a shorter tag search without control characters.',
          _ =>
            'Could not load tags. Try searching again when Zotero is available.',
        };
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  String? _unavailableReason(String name) {
    if (_selected.contains(name)) return null;
    try {
      if (normalizeZoteroTags([name]).single != name) {
        return 'Tags with surrounding spaces cannot be filtered exactly here.';
      }
      normalizeZoteroTags([..._selected, name]);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  void _toggle(String name) {
    if (_busy) return;
    final reason = _unavailableReason(name);
    if (reason != null) {
      setState(() => _selectionError = reason);
      return;
    }
    setState(() {
      if (!_selected.remove(name)) _selected.add(name);
      _selectionError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return AlertDialog(
      key: const ValueKey('zotero-tag-browser'),
      insetPadding: const EdgeInsets.all(16),
      scrollable: true,
      title: const Text('Browse tags'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.scopeLabel),
            const SizedBox(height: 4),
            const Text(
              'Choose tags to require every selected name. Zotero usage counts '
              'may cover the whole library, including notes and attachments.',
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('zotero-tag-browser-query'),
                    controller: _query,
                    enabled: !_busy,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      labelText: 'Search tag names',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _load(submit: true),
                  ),
                ),
                IconButton(
                  key: const ValueKey('zotero-tag-browser-search'),
                  tooltip: 'Search tags',
                  onPressed: _busy ? null : () => _load(submit: true),
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ZoteroTagSearchMode>(
              key: const ValueKey('zotero-tag-browser-mode'),
              initialValue: _mode,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Match tag names',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: ZoteroTagSearchMode.contains,
                  child: Text('Containing the search'),
                ),
                DropdownMenuItem(
                  value: ZoteroTagSearchMode.startsWith,
                  child: Text('Starting with the search'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (mode) {
                      if (mode == null || mode == _mode) return;
                      setState(() => _mode = mode);
                      _load();
                    },
            ),
            const SizedBox(height: 12),
            Text(
              '${_selected.length} tag filters selected',
              key: const ValueKey('zotero-tag-browser-selection-count'),
            ),
            if (_selected.isNotEmpty)
              SizedBox(
                height: min(128, _selected.length * 48.0),
                child: SingleChildScrollView(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final name in _selected)
                          InputChip(
                            key: ValueKey('zotero-tag-browser-selected-$name'),
                            label: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: max(
                                  32,
                                  min(240, constraints.maxWidth - 80),
                                ),
                              ),
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            tooltip: name,
                            deleteButtonTooltipMessage:
                                'Remove selected tag $name',
                            onDeleted: _busy ? null : () => _toggle(name),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_selected.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('zotero-tag-browser-clear'),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _selected.clear();
                          _selectionError = null;
                        }),
                  child: const Text('Clear selection'),
                ),
              ),
            if (_selectionError != null)
              Text(
                _selectionError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                key: const ValueKey('zotero-tag-browser-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (!_busy && _tags.isEmpty)
              const Text('No tags match this search.')
            else
              SizedBox(
                height: max(
                  128,
                  min(288, MediaQuery.sizeOf(context).height * .32),
                ),
                child: ListView.builder(
                  key: const ValueKey('zotero-tag-browser-results'),
                  controller: _resultsScroll,
                  itemCount: _tags.length,
                  itemBuilder: (context, index) {
                    final tag = _tags[index];
                    final reason = _unavailableReason(tag.name);
                    return Tooltip(
                      message: reason == null
                          ? tag.name
                          : '${tag.name}\n$reason',
                      child: CheckboxListTile(
                        key: ValueKey('zotero-tag-browser-choice-${tag.name}'),
                        value: _selected.contains(tag.name),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          tag.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: reason != null
                            ? Text(reason)
                            : tag.numItems == null
                            ? null
                            : Text('${tag.numItems} items reported by Zotero'),
                        onChanged: _busy || reason != null
                            ? null
                            : (_) => _toggle(tag.name),
                      ),
                    );
                  },
                ),
              ),
            if (page != null)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Page ${page.start ~/ page.limit + 1}'),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('zotero-tag-browser-previous'),
                        tooltip: 'Previous tags',
                        onPressed: _busy || page.start == 0
                            ? null
                            : () =>
                                  _load(start: max(0, page.start - page.limit)),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        key: const ValueKey('zotero-tag-browser-next'),
                        tooltip: 'Next tags',
                        onPressed: _busy || page.nextStart == null
                            ? null
                            : () => _load(start: page.nextStart!),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('zotero-tag-browser-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('zotero-tag-browser-apply'),
          onPressed: _busy
              ? null
              : () => Navigator.pop(
                  context,
                  List<String>.unmodifiable(_selected),
                ),
          child: const Text('Apply tags'),
        ),
      ],
    );
  }
}
