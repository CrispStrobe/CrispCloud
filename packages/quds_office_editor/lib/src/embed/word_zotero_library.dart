import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'word_zotero_format.dart';
import 'word_zotero_stored_details.dart';

List<(String, String)> _detailFields(ZoteroItem item) => [
  ('Title', zoteroHtmlToPlainText(item.title)),
  (
    'Creators',
    item.creators
        .map(
          (creator) =>
              '${creator.displayName}${creator.creatorType.isEmpty || creator.creatorType == 'author' ? '' : ' (${creator.creatorType})'}',
        )
        .where((name) => name.isNotEmpty)
        .join('\n'),
  ),
  ('Reference type', item.itemType),
  ('Publication', zoteroHtmlToPlainText(item.publicationTitle)),
  ('Date', item.date),
  ('Publisher', zoteroHtmlToPlainText(item.publisher)),
  ('DOI', item.doi),
  ('URL', item.url),
  ('Zotero item', item.citationUri?.toString() ?? 'Embedded source only'),
];

/// A plain-text metadata summary. URLs and tags remain inert, literal data.
String zoteroItemDetailsText(ZoteroItem item) => [
  for (final (label, value) in _detailFields(item))
    if (value.isNotEmpty) '$label: $value',
  if (item.tags.isNotEmpty)
    'Tags:\n${item.tags.map((tag) => '• $tag').join('\n')}',
  if (item.abstractNote.isNotEmpty) 'Abstract:\n${item.abstractNote}',
].join('\n\n');

/// Inspects an already loaded item without fetching or selecting it. A returned
/// tag is an explicit filter request; the caller rechecks its catalog context.
class ZoteroItemDetailsDialog extends StatefulWidget {
  const ZoteroItemDetailsDialog({
    super.key,
    required this.item,
    required this.activeTags,
    this.onBrowseChildren,
    this.childrenUnavailableReason,
  });

  final ZoteroItem item;
  final List<String> activeTags;
  final Future<void> Function()? onBrowseChildren;
  final String? childrenUnavailableReason;

  @override
  State<ZoteroItemDetailsDialog> createState() =>
      _ZoteroItemDetailsDialogState();
}

class _ZoteroItemDetailsDialogState extends State<ZoteroItemDetailsDialog> {
  String? _copyStatus;
  bool _copying = false;
  bool _browsingChildren = false;

  Future<void> _browseChildren() async {
    final browse = widget.onBrowseChildren;
    if (browse == null || _browsingChildren) return;
    setState(() => _browsingChildren = true);
    try {
      await browse();
    } finally {
      if (mounted) setState(() => _browsingChildren = false);
    }
  }

  String? _tagUnavailableReason(String tag) {
    if (widget.activeTags.contains(tag)) {
      return 'This tag filter is already active.';
    }
    try {
      if (normalizeZoteroTags([tag]).single != tag) {
        return 'Tags with surrounding spaces cannot be filtered exactly here.';
      }
      normalizeZoteroTags([...widget.activeTags, tag]);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  Future<void> _copyDetails() async {
    setState(() => _copying = true);
    try {
      await Clipboard.setData(
        ClipboardData(text: zoteroItemDetailsText(widget.item)),
      );
      if (mounted) setState(() => _copyStatus = 'Reference details copied.');
    } on PlatformException {
      if (mounted) {
        setState(
          () => _copyStatus =
              'Could not copy. Select the text to copy it manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AlertDialog(
      key: const ValueKey('zotero-item-details-dialog'),
      insetPadding: const EdgeInsets.all(16),
      scrollable: true,
      title: const Text('Reference details'),
      content: SizedBox(
        width: 620,
        height: max(120, min(520, MediaQuery.sizeOf(context).height - 240)),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value) in _detailFields(item))
                if (value.isNotEmpty) ...[
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  SelectableText(value),
                  const SizedBox(height: 12),
                ],
              if (widget.onBrowseChildren != null ||
                  widget.childrenUnavailableReason != null) ...[
                TextButton.icon(
                  key: const ValueKey('zotero-browse-item-children'),
                  onPressed:
                      widget.onBrowseChildren == null || _browsingChildren
                      ? null
                      : _browseChildren,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Notes and attachments…'),
                ),
                if (widget.childrenUnavailableReason != null)
                  Text(widget.childrenUnavailableReason!),
                const SizedBox(height: 12),
              ],
              if (item.tags.isNotEmpty) ...[
                Text(
                  'Tags (${item.tags.length})',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Text('Choose a tag to filter the current search.'),
                const SizedBox(height: 4),
                SizedBox(
                  height: min(176, item.tags.length * 44.0),
                  child: ListView.builder(
                    key: const ValueKey('zotero-item-tags'),
                    itemCount: item.tags.length,
                    itemBuilder: (context, index) {
                      final tag = item.tags[index];
                      final reason = _tagUnavailableReason(tag);
                      return Tooltip(
                        message: reason == null ? tag : '$tag\n$reason',
                        child: TextButton.icon(
                          key: ValueKey('zotero-item-tag-$index'),
                          onPressed: reason == null
                              ? () => Navigator.pop(context, tag)
                              : null,
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                          ),
                          icon: Icon(
                            widget.activeTags.contains(tag)
                                ? Icons.check
                                : Icons.label_outline,
                            size: 18,
                          ),
                          label: Text(
                            tag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (item.abstractNote.isNotEmpty) ...[
                Text('Abstract', style: Theme.of(context).textTheme.labelLarge),
                SelectableText(item.abstractNote),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_copyStatus != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              _copyStatus!,
              key: const ValueKey('zotero-details-copy-status'),
            ),
          ),
        TextButton.icon(
          key: const ValueKey('zotero-copy-item-details'),
          onPressed: _copying ? null : _copyDetails,
          icon: const Icon(Icons.copy),
          label: const Text('Copy details'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Inspects the stored CSL snapshot, including offline and mixed-library
/// sources. Opening or copying details never fetches or changes a reference.
class ZoteroStoredReferenceDetailsDialog extends StatefulWidget {
  const ZoteroStoredReferenceDetailsDialog({super.key, required this.item});

  final ZoteroCitationItem item;

  @override
  State<ZoteroStoredReferenceDetailsDialog> createState() =>
      _ZoteroStoredReferenceDetailsDialogState();
}

class _ZoteroStoredReferenceDetailsDialogState
    extends State<ZoteroStoredReferenceDetailsDialog> {
  String? _copyStatus;
  bool _copying = false;

  Future<void> _copyDetails() async {
    setState(() => _copying = true);
    try {
      await Clipboard.setData(
        ClipboardData(text: zoteroStoredReferenceDetailsText(widget.item)),
      );
      if (mounted) setState(() => _copyStatus = 'Reference details copied.');
    } on PlatformException {
      if (mounted) {
        setState(
          () => _copyStatus =
              'Could not copy. Select the text to copy it manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('zotero-stored-reference-details-dialog'),
    insetPadding: const EdgeInsets.all(16),
    scrollable: true,
    title: const Text('Stored reference details'),
    content: SizedBox(
      width: 620,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Metadata stored with this reference. No updates are fetched.',
          ),
          const SizedBox(height: 12),
          if (_copyStatus != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                _copyStatus!,
                key: const ValueKey('zotero-stored-details-copy-status'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final (label, value) in zoteroStoredReferenceDetailFields(
            widget.item,
          )) ...[
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            SelectableText(value),
            const SizedBox(height: 12),
          ],
        ],
      ),
    ),
    actions: [
      TextButton.icon(
        key: const ValueKey('zotero-copy-stored-reference-details'),
        onPressed: _copying ? null : _copyDetails,
        icon: const Icon(Icons.copy),
        label: const Text('Copy details'),
      ),
      TextButton(
        key: const ValueKey('zotero-stored-details-close'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

/// Stages selection changes using the caller's original keys. Reusing immutable
/// citation values retains source identities, locators and unknown metadata.
class ZoteroSelectedReferencesDialog extends StatefulWidget {
  const ZoteroSelectedReferencesDialog({super.key, required this.selection});

  final Map<String, ZoteroCitationItem> selection;

  @override
  State<ZoteroSelectedReferencesDialog> createState() =>
      _ZoteroSelectedReferencesDialogState();
}

class _ZoteroSelectedReferencesDialogState
    extends State<ZoteroSelectedReferencesDialog> {
  late final List<String> _keys = widget.selection.keys.toList();

  void _move(int index, int offset) => setState(() {
    final key = _keys.removeAt(index);
    _keys.insert(index + offset, key);
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('zotero-selected-references-dialog'),
    insetPadding: const EdgeInsets.all(16),
    scrollable: true,
    title: const Text('Selected references'),
    content: SizedBox(
      width: 620,
      height: max(120, min(440, MediaQuery.sizeOf(context).height - 260)),
      child: ListView.builder(
        key: const ValueKey('zotero-selected-reference-list'),
        itemCount: _keys.length + 1,
        itemBuilder: (context, row) {
          if (row == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review references from every page. Move them to change citation order, or remove individual sources. Zotero styles may apply their own order.',
                ),
                const SizedBox(height: 8),
                Text(
                  '${_keys.length} selected',
                  key: const ValueKey('zotero-review-selected-count'),
                ),
                const SizedBox(height: 8),
                if (_keys.isEmpty) const Text('No references selected.'),
              ],
            );
          }
          final index = row - 1;
          final key = _keys[index];
          final item = widget.selection[key]!;
          final title = zoteroHtmlToPlainText(
            '${item.itemData?['title'] ?? item.id}',
          );
          return Card(
            key: ValueKey('zotero-selected-$key'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}. $title',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    zoteroBasicCitation([item]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        IconButton(
                          key: ValueKey('zotero-selection-details-$key'),
                          tooltip: 'Stored reference details',
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                ZoteroStoredReferenceDetailsDialog(item: item),
                          ),
                          icon: const Icon(Icons.info_outline),
                        ),
                        IconButton(
                          key: ValueKey('zotero-selection-up-$key'),
                          tooltip: 'Move reference up',
                          onPressed: index == 0 ? null : () => _move(index, -1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          key: ValueKey('zotero-selection-down-$key'),
                          tooltip: 'Move reference down',
                          onPressed: index == _keys.length - 1
                              ? null
                              : () => _move(index, 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        IconButton(
                          key: ValueKey('zotero-selection-remove-$key'),
                          tooltip: 'Remove selected reference',
                          onPressed: () =>
                              setState(() => _keys.removeAt(index)),
                          icon: const Icon(Icons.close),
                        ),
                      ],
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
        key: const ValueKey('zotero-selection-cancel'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('zotero-selection-apply'),
        onPressed: () => Navigator.pop(context, List<String>.of(_keys)),
        child: const Text('Apply selection'),
      ),
    ],
  );
}
