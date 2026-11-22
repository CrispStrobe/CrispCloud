import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:url_launcher/url_launcher.dart';

import 'word_zotero_format.dart';
import 'word_zotero_stored_details.dart';

/// Opens an item in a Zotero desktop library; hosts may override this for
/// platform integration or deterministic widget tests.
typedef ZoteroItemOpener = Future<bool> Function(Uri uri);

/// Explicit navigation only: opening Zotero never fetches, edits, or links a
/// citation. A failed protocol-handler launch leaves the details dialog open.
class _ZoteroOpenItemButton extends StatefulWidget {
  const _ZoteroOpenItemButton({required this.uri, this.onOpen});

  final Uri uri;
  final ZoteroItemOpener? onOpen;

  @override
  State<_ZoteroOpenItemButton> createState() => _ZoteroOpenItemButtonState();
}

class _ZoteroOpenItemButtonState extends State<_ZoteroOpenItemButton> {
  bool _opening = false;
  String? _failure;

  Future<void> _open() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failure = null;
    });
    try {
      final success = widget.onOpen != null
          ? await widget.onOpen!(widget.uri)
          : await launchUrl(
              widget.uri,
              mode: LaunchMode.externalApplication,
            );
      if (mounted && !success) {
        setState(() => _failure = 'Zotero could not be opened on this device.');
      }
    } on Exception {
      if (mounted) {
        setState(() => _failure = 'Zotero could not be opened on this device.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextButton.icon(
        key: const ValueKey('zotero-open-in-desktop'),
        onPressed: _opening ? null : _open,
        icon: const Icon(Icons.open_in_new),
        label: const Text('Open in Zotero'),
      ),
      if (_failure != null)
        Semantics(
          liveRegion: true,
          child: SizedBox(
            width: 180,
            child: Text(
              _failure!,
              textAlign: TextAlign.center,
              key: const ValueKey('zotero-desktop-selection-error'),
            ),
          ),
        ),
    ],
  );
}

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
    this.onOpenInZotero,
  });

  final ZoteroItem item;
  final List<String> activeTags;
  final Future<void> Function()? onBrowseChildren;
  final String? childrenUnavailableReason;
  final ZoteroItemOpener? onOpenInZotero;

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
    final selectionUri = zoteroCatalogItemSelectionUri(item);
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
        if (selectionUri != null)
          _ZoteroOpenItemButton(
            uri: selectionUri,
            onOpen: widget.onOpenInZotero,
          ),
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
  const ZoteroStoredReferenceDetailsDialog({
    super.key,
    required this.item,
    this.onOpenInZotero,
  });

  final ZoteroCitationItem item;
  final ZoteroItemOpener? onOpenInZotero;

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
      if (zoteroStoredItemSelectionUri(widget.item) != null)
        _ZoteroOpenItemButton(
          uri: zoteroStoredItemSelectionUri(widget.item)!,
          onOpen: widget.onOpenInZotero,
        ),
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
