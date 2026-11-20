import 'dart:math';

import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

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
    this.occurrences = const {},
    this.canReveal,
    this.onNavigate,
  });

  final List<ZoteroDocumentReference> references;
  final Set<String> selectedKeys;
  final int otherSelectionCount;
  final Map<String, List<ZoteroDocumentOccurrence>> occurrences;
  final bool Function(WmlZoteroField field)? canReveal;

  /// Called after this dialog closes without applying its staged selection.
  /// The host must revalidate the document and field before navigating.
  final ValueChanged<WmlZoteroField>? onNavigate;

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

  Future<void> _showOccurrences(
    ZoteroDocumentReference reference,
    String title,
  ) async {
    final occurrences = widget.occurrences[reference.selectionKey];
    if (occurrences == null || occurrences.isEmpty) return;
    final destination = await showDialog<WmlZoteroField>(
      context: context,
      builder: (_) => ZoteroSourceOccurrencesDialog(
        title: title,
        occurrences: occurrences,
        canReveal: widget.onNavigate == null ? null : widget.canReveal,
      ),
    );
    if (!mounted || destination == null || widget.onNavigate == null) return;
    // Going back from the occurrence list leaves _selected untouched. Going
    // to a citation explicitly leaves the staged source selection unapplied.
    Navigator.pop(context);
    widget.onNavigate!(destination);
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
                  Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      if (widget
                              .occurrences[reference.selectionKey]
                              ?.isNotEmpty ==
                          true)
                        TextButton.icon(
                          key: ValueKey(
                            'zotero-document-source-occurrences-${display.index}',
                          ),
                          onPressed: () =>
                              _showOccurrences(reference, display.title),
                          icon: const Icon(Icons.find_in_page_outlined),
                          label: const Text('Show citations'),
                        ),
                      TextButton.icon(
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
                    ],
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

/// Inspects distinct citation fields for a source without touching document
/// content or the parent dialog's pending source selection.
class ZoteroSourceOccurrencesDialog extends StatefulWidget {
  const ZoteroSourceOccurrencesDialog({
    super.key,
    required this.title,
    required this.occurrences,
    this.canReveal,
  });

  final String title;
  final List<ZoteroDocumentOccurrence> occurrences;
  final bool Function(WmlZoteroField field)? canReveal;

  @override
  State<ZoteroSourceOccurrencesDialog> createState() =>
      _ZoteroSourceOccurrencesDialogState();
}

class _ZoteroSourceOccurrencesDialogState
    extends State<ZoteroSourceOccurrencesDialog> {
  String? _error;

  void _go(WmlZoteroField field) {
    // Recheck the availability hint at click time. The host still performs
    // full handle/content validation after all dialogs have closed.
    if (widget.canReveal?.call(field) != true) {
      setState(() {
        _error =
            'This citation is no longer available. Close this list and open cited references again.';
      });
      return;
    }
    Navigator.pop(context, field);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('zotero-source-occurrences-dialog'),
    insetPadding: const EdgeInsets.all(16),
    scrollable: true,
    title: const Text('Citation occurrences'),
    content: SizedBox(
      width: 650,
      height: max(160, min(480, MediaQuery.sizeOf(context).height - 260)),
      child: ListView.builder(
        key: const ValueKey('zotero-source-occurrences-list'),
        itemCount: widget.occurrences.length + 1,
        itemBuilder: (context, row) {
          if (row == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.occurrences.length} distinct citation field(s). A source repeated inside one citation appears once here.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Going to a citation closes the workspace without applying changes to selected sources.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: const ValueKey('zotero-source-occurrences-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            );
          }
          final index = row - 1;
          final occurrence = widget.occurrences[index];
          final available = widget.canReveal?.call(occurrence.field) == true;
          final preview = occurrence.field.cachedText.isEmpty
              ? '(Empty citation text)'
              : occurrence.field.cachedText;
          return Card(
            key: ValueKey('zotero-source-occurrence-$index'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    occurrence.location,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Tooltip(
                    message: preview,
                    child: Text(
                      preview,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!available) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Navigation is unavailable for this citation or document mode.',
                    ),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      key: ValueKey('zotero-source-occurrence-go-$index'),
                      onPressed: available ? () => _go(occurrence.field) : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Go to citation'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('zotero-source-occurrences-back'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Back to cited references'),
      ),
    ],
  );
}
