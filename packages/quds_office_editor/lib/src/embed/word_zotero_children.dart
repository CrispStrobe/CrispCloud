import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'word_zotero_format.dart';
import 'word_zotero_note_preview.dart';

const _staleConnection =
    'The Zotero connection or library changed. Close this view and reopen the reference details.';

/// An explicitly requested, read-only view of one catalog reference's children.
/// The caller supplies the original catalog guard; no document state is used.
class ZoteroItemChildrenDialog extends StatefulWidget {
  const ZoteroItemChildrenDialog({
    super.key,
    required this.client,
    required this.parent,
    required this.isCurrent,
  });

  final ZoteroClient client;
  final ZoteroItem parent;
  final bool Function() isCurrent;

  @override
  State<ZoteroItemChildrenDialog> createState() =>
      _ZoteroItemChildrenDialogState();
}

class _ZoteroItemChildrenDialogState extends State<ZoteroItemChildrenDialog> {
  final _scroll = ScrollController();
  ZoteroPage<ZoteroItemChild>? _page;
  List<_PreparedChild> _children = const [];
  List<int> _previousStarts = const [];
  List<int> _retryPreviousStarts = const [];
  int _retryStart = 0;
  int _generation = 0;
  bool _busy = false;
  bool _stale = false;
  bool _reloadNeeded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(0, const []);
  }

  @override
  void didUpdateWidget(ZoteroItemChildrenDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client) ||
        !identical(oldWidget.parent, widget.parent)) {
      _generation++;
      _busy = false;
      _stale = false;
      _reloadNeeded = false;
      _page = null;
      _children = const [];
      _previousStarts = const [];
      _load(0, const []);
    }
  }

  @override
  void dispose() {
    _generation++;
    _scroll.dispose();
    super.dispose();
  }

  bool _checkCurrent() {
    if (!mounted) return false;
    if (!_stale && widget.isCurrent()) return true;
    setState(() {
      _stale = true;
      _page = null;
      _children = const [];
      _error = _staleConnection;
    });
    return false;
  }

  Future<void> _load(int start, List<int> previousStarts) async {
    if (_busy || !_checkCurrent()) return;
    final generation = ++_generation;
    final client = widget.client;
    final parent = widget.parent;
    final previousVersion = _page?.lastModifiedVersion;
    setState(() {
      _busy = true;
      _error = null;
      _reloadNeeded = false;
      _retryStart = start;
      _retryPreviousStarts = List.unmodifiable(previousStarts);
    });
    try {
      final page = await client.itemChildren(
        parent.library,
        parent.key,
        expectedLocalServerId: parent.localServerId,
        start: start,
        limit: 25,
      );
      if (!mounted || generation != _generation || !_checkCurrent()) return;
      if (start != 0 &&
          previousVersion != null &&
          page.lastModifiedVersion != previousVersion) {
        setState(() {
          _page = null;
          _children = const [];
          _previousStarts = const [];
          _retryStart = 0;
          _retryPreviousStarts = const [];
          _reloadNeeded = true;
          _error =
              'The Zotero library may have changed while paging. Reload to start again at the first page.';
        });
        return;
      }
      final children = page.items.map(_PreparedChild.new).toList();
      setState(() {
        _page = page;
        _children = List.unmodifiable(children);
        _previousStarts = List.unmodifiable(previousStarts);
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (error) {
      if (!mounted || generation != _generation || !_checkCurrent()) return;
      setState(() {
        _error = switch (error) {
          ZoteroApiException value =>
            value.retryAfter == null
                ? value.message
                : '${value.message} Retry in ${max(1, (value.retryAfter!.inMilliseconds / 1000).ceil())} seconds.',
          _ => 'Could not load notes and attachments. Try again later.',
        };
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _inspect(_PreparedChild child) async {
    if (_busy || !_checkCurrent()) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ZoteroChildDetailsDialog(
        child: child,
        isCurrent: () => mounted && !_stale && widget.isCurrent(),
      ),
    );
    if (mounted) _checkCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final parentTitle = zoteroHtmlToPlainText(widget.parent.title);
    return AlertDialog(
      key: const ValueKey('zotero-item-children-dialog'),
      insetPadding: const EdgeInsets.all(16),
      scrollable: true,
      title: const Text('Notes and attachments'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              parentTitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Read research notes and attachment details. Only items visible '
              'to this Zotero connection are shown.',
            ),
            const SizedBox(height: 12),
            if (_busy)
              const LinearProgressIndicator(
                key: ValueKey('zotero-children-loading'),
              ),
            if (_error != null) ...[
              Text(
                _error!,
                key: const ValueKey('zotero-children-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (!_stale)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('zotero-children-retry'),
                    onPressed: _busy
                        ? null
                        : () => _load(_retryStart, _retryPreviousStarts),
                    icon: const Icon(Icons.refresh),
                    label: Text(_reloadNeeded ? 'Reload' : 'Retry'),
                  ),
                ),
              if (page != null)
                const Text('The previously loaded page is still shown.'),
              const SizedBox(height: 8),
            ],
            if (!_busy && _error == null && _children.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No notes or attachments were returned. Note access depends '
                  'on the library and API-key permissions.',
                  key: ValueKey('zotero-children-empty'),
                ),
              ),
            if (_children.isNotEmpty)
              SizedBox(
                height: max(
                  120,
                  min(420, MediaQuery.sizeOf(context).height * .42),
                ),
                child: ListView.separated(
                  key: const ValueKey('zotero-children-list'),
                  controller: _scroll,
                  itemCount: _children.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final child = _children[index];
                    return ListTile(
                      key: ValueKey('zotero-child-${child.item.key}'),
                      enabled: !_busy && !_stale,
                      leading: Icon(
                        child.item.kind == ZoteroItemChildKind.note
                            ? Icons.description_outlined
                            : Icons.attach_file,
                      ),
                      title: Text(
                        child.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        child.item.kind == ZoteroItemChildKind.note
                            ? child.error == null
                                  ? 'Note · Plain-text preview'
                                  : 'Note · Preview unavailable'
                            : [
                                'Attachment',
                                child.item.contentType,
                              ].where((value) => value.isNotEmpty).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy || _stale ? null : () => _inspect(child),
                    );
                  },
                ),
              ),
            if (page != null) ...[
              const SizedBox(height: 8),
              Text(
                page.items.isEmpty
                    ? '0 items on this page'
                    : '${page.start + 1}–${page.start + page.items.length}'
                          '${page.totalResults == null ? '' : ' of ${page.totalResults}'}',
                key: const ValueKey('zotero-children-count'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: const ValueKey('zotero-children-previous'),
                    onPressed: _busy || _stale || _previousStarts.isEmpty
                        ? null
                        : () => _load(
                            _previousStarts.last,
                            _previousStarts.sublist(
                              0,
                              _previousStarts.length - 1,
                            ),
                          ),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Previous page'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('zotero-children-next'),
                    onPressed: _busy || _stale || page.nextStart == null
                        ? null
                        : () => _load(page.nextStart!, [
                            ..._previousStarts,
                            page.start,
                          ]),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Next page'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('zotero-children-reload'),
                    onPressed: _busy || _stale
                        ? null
                        : () => _load(0, const []),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('zotero-children-close'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to reference details'),
        ),
      ],
    );
  }
}

class _PreparedChild {
  _PreparedChild(this.item) {
    try {
      preview = ZoteroNotePreview.fromHtml(item.noteHtml);
    } on FormatException {
      error = 'This note cannot be shown as plain text. Open it in Zotero.';
    }
    final text = preview?.plainText.trim() ?? '';
    title = item.title.isNotEmpty
        ? item.title
        : item.kind == ZoteroItemChildKind.note && text.isNotEmpty
        ? _derivedNoteTitle(text)
        : item.filename.isNotEmpty
        ? item.filename
        : item.kind == ZoteroItemChildKind.note
        ? 'Untitled note'
        : 'Untitled attachment';
  }

  final ZoteroItemChild item;
  ZoteroNotePreview? preview;
  String? error;
  late final String title;
}

String _derivedNoteTitle(String text) {
  final title = StringBuffer();
  var count = 0;
  for (final rune in text.runes) {
    if (rune == 10 || rune == 13) break;
    if (count++ == 200) {
      title.write('…');
      break;
    }
    title.writeCharCode(rune);
  }
  return title.toString();
}

String _linkModeLabel(String value) => switch (value) {
  'imported_file' => 'Stored file',
  'imported_url' => 'Stored from URL',
  'linked_file' => 'Linked file',
  'linked_url' => 'Web link',
  'embedded_image' => 'Embedded image',
  _ => value,
};

List<(String, String)> _childDetails(_PreparedChild child) => [
  ('Title', child.title),
  ('Type', child.item.kind == ZoteroItemChildKind.note ? 'Note' : 'Attachment'),
  if (child.item.kind == ZoteroItemChildKind.attachment) ...[
    ('Filename', child.item.filename),
    ('Content type', child.item.contentType),
    ('Storage', _linkModeLabel(child.item.linkMode)),
    ('URL', child.item.url),
  ],
];

class _ZoteroChildDetailsDialog extends StatefulWidget {
  const _ZoteroChildDetailsDialog({
    required this.child,
    required this.isCurrent,
  });

  final _PreparedChild child;
  final bool Function() isCurrent;

  @override
  State<_ZoteroChildDetailsDialog> createState() =>
      _ZoteroChildDetailsDialogState();
}

class _ZoteroChildDetailsDialogState extends State<_ZoteroChildDetailsDialog> {
  String? _status;
  bool _copying = false;
  bool _stale = false;

  Future<void> _copy(String text, String success) async {
    if (_copying) return;
    if (!widget.isCurrent()) {
      setState(() {
        _stale = true;
        _status = _staleConnection;
      });
      return;
    }
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) setState(() => _status = success);
    } on PlatformException {
      if (mounted) {
        setState(() {
          _status = 'Could not copy. Select the text to copy it manually.';
        });
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final note = child.preview?.plainText ?? '';
    return AlertDialog(
      key: const ValueKey('zotero-child-details-dialog'),
      insetPadding: const EdgeInsets.all(16),
      scrollable: true,
      title: Text(
        child.item.kind == ZoteroItemChildKind.note
            ? 'Research note'
            : 'Attachment details',
      ),
      content: SizedBox(
        width: 620,
        height: max(120, min(520, MediaQuery.sizeOf(context).height * .52)),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value) in _childDetails(child))
                if (value.isNotEmpty) ...[
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  SelectableText(value),
                  const SizedBox(height: 12),
                ],
              if (child.item.kind == ZoteroItemChildKind.attachment) ...[
                const Text(
                  'Attachment metadata. File contents remain in Zotero.',
                ),
                const SizedBox(height: 12),
              ],
              if (child.item.kind == ZoteroItemChildKind.note ||
                  child.item.noteHtml.isNotEmpty) ...[
                Text(
                  child.item.kind == ZoteroItemChildKind.note
                      ? 'Note text'
                      : 'Attachment note',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Text(
                  'Plain-text preview. Formatting and active citation links '
                  'are not copied.',
                ),
                if (child.preview?.hasOmittedContent == true)
                  const Text(
                    'Images or other embedded content are omitted from this preview.',
                    key: ValueKey('zotero-child-omitted-content'),
                  ),
                const SizedBox(height: 8),
                if (child.error != null)
                  Text(
                    child.error!,
                    key: const ValueKey('zotero-child-preview-error'),
                  )
                else if (note.isEmpty)
                  const Text('No plain-text note content was returned.')
                else
                  SelectableText(
                    note,
                    key: const ValueKey('zotero-child-note-text'),
                  ),
              ],
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(_status!, key: const ValueKey('zotero-child-copy-status')),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (note.isNotEmpty && child.error == null)
          TextButton.icon(
            key: const ValueKey('zotero-copy-child-note'),
            onPressed: _copying || _stale
                ? null
                : () => _copy(note, 'Note text copied.'),
            icon: const Icon(Icons.copy),
            label: const Text('Copy note text'),
          ),
        if (child.item.kind == ZoteroItemChildKind.attachment)
          TextButton.icon(
            key: const ValueKey('zotero-copy-child-details'),
            onPressed: _copying || _stale
                ? null
                : () => _copy(
                    [
                      for (final (label, value) in _childDetails(child))
                        if (value.isNotEmpty) '$label: $value',
                    ].join('\n\n'),
                    'Attachment details copied.',
                  ),
            icon: const Icon(Icons.copy),
            label: const Text('Copy details'),
          ),
        TextButton(
          key: const ValueKey('zotero-child-details-back'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to notes and attachments'),
        ),
      ],
    );
  }
}
