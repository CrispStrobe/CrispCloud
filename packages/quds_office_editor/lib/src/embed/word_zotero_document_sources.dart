import 'dart:math';

import 'package:flutter/material.dart';

import 'word_zotero_import.dart';
import 'word_zotero_library.dart';
import 'word_zotero_sources.dart';

/// Searches and selects stored document sources without fetching metadata or
/// changing the document. Selection is staged until the user applies it.
class ZoteroDocumentSourcesDialog extends StatefulWidget {
  const ZoteroDocumentSourcesDialog({
    super.key,
    required this.references,
    required this.selectedKeys,
    required this.otherSelectionCount,
  });

  final List<ZoteroDocumentReference> references;
  final Set<String> selectedKeys;
  final int otherSelectionCount;

  @override
  State<ZoteroDocumentSourcesDialog> createState() =>
      _ZoteroDocumentSourcesDialogState();
}

class _ZoteroDocumentSourcesDialogState
    extends State<ZoteroDocumentSourcesDialog> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  late final _selected = <String>{...widget.selectedKeys};
  late final _references = [
    for (var index = 0; index < widget.references.length; index++)
      ZoteroImportedReference(
        index: index,
        item: widget.references[index].item,
      ),
  ];
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter({bool clear = false}) {
    setState(() {
      if (clear) _search.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _select(String key, bool selected) {
    setState(() {
      if (!selected) {
        _selected.remove(key);
        _error = null;
      } else if (_selected.length + widget.otherSelectionCount >= 20) {
        _error = 'Select at most 20 sources per citation across all tabs.';
      } else {
        _selected.add(key);
        _error = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = filterZoteroImportedReferences(_references, _search.text);
    final visibleSelected = visible
        .where(
          (reference) => _selected.contains(
            widget.references[reference.index].selectionKey,
          ),
        )
        .length;
    final hidden = _selected.length - visibleSelected;
    return AlertDialog(
      key: const ValueKey('zotero-document-sources-dialog'),
      insetPadding: const EdgeInsets.all(16),
      scrollable: true,
      title: const Text('Cited references'),
      content: SizedBox(
        width: 650,
        height: max(160, min(500, MediaQuery.sizeOf(context).height - 240)),
        child: ListView.builder(
          key: const ValueKey('zotero-document-source-list'),
          controller: _scroll,
          itemCount: visible.length + 1,
          itemBuilder: (context, row) {
            if (row == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Reuse references already cited in this document. Stored metadata works offline; page numbers and other citation options start fresh.',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('zotero-document-source-search'),
                    controller: _search,
                    onChanged: (_) => _filter(),
                    decoration: InputDecoration(
                      labelText: 'Search cited references',
                      hintText: 'Title, creator, year or DOI',
                      border: const OutlineInputBorder(),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear cited reference search',
                              onPressed: () => _filter(clear: true),
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${visible.length} of ${widget.references.length} shown · ${_selected.length} selected here'
                    '${widget.otherSelectionCount == 0 ? '' : ' · ${widget.otherSelectionCount} selected in other tabs'}',
                    key: const ValueKey('zotero-document-source-count'),
                  ),
                  if (hidden > 0)
                    Text(
                      '$hidden selected reference(s) outside these results.',
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      key: const ValueKey('zotero-document-source-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        widget.references.isEmpty
                            ? 'No cited references in this document.'
                            : 'No cited references match this search.',
                      ),
                    ),
                ],
              );
            }
            final display = visible[row - 1];
            final reference = widget.references[display.index];
            return Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    key: ValueKey('zotero-document-source-${display.index}'),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selected.contains(reference.selectionKey),
                    onChanged: (value) =>
                        _select(reference.selectionKey, value ?? false),
                    title: Text(
                      display.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if (display.subtitle.isNotEmpty) display.subtitle,
                        '${reference.occurrences} citation occurrence(s)',
                        if (reference.item.itemData == null ||
                            reference.item.itemData!.isEmpty)
                          'No stored bibliographic details; retained source identity only',
                      ].join('\n'),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      key: ValueKey(
                        'zotero-document-source-details-${display.index}',
                      ),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => ZoteroStoredReferenceDetailsDialog(
                          item: reference.item,
                        ),
                      ),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Stored reference details'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('zotero-document-sources-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('zotero-document-sources-apply'),
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: const Text('Use selected sources'),
        ),
      ],
    );
  }
}
