import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:url_launcher/url_launcher.dart';

import 'office_controller.dart';
import 'word_zotero_format.dart';

/// Connection preferences belong to the host session, never to a document.
class ZoteroSession {
  String? apiKey;
  bool rememberKey = false;
  ZoteroLibrary? library;
  String style = 'apa';
  String locale = 'en-US';
}

/// Shared Quds citation workspace. The host supplies its own network transport
/// and may opt into its existing credential store. Without a transport, local
/// CSL import, field editing, and embedded-source export remain available.
Future<void> showWordZoteroDialog(
  BuildContext context, {
  required WordEditorController controller,
  ZoteroTransport? transport,
  ZoteroSession? session,
  Future<void> Function(String? apiKey)? persistApiKey,
}) {
  controller.commitPendingEdits();
  return showDialog<void>(
    context: context,
    builder: (_) => _WordZoteroDialog(
      controller: controller,
      transport: transport,
      session: session ?? ZoteroSession(),
      persistApiKey: persistApiKey,
    ),
  );
}

Object _editTarget(WordEditorController controller) => (
  document: controller.document,
  revision: controller.contentRevision,
  caret: controller.caret,
  paragraph: controller.caret.paragraphIndex,
  offset: controller.caret.logicalIndex,
  anchorParagraph: controller.caret.selectionAnchorParagraph,
  anchorOffset: controller.caret.selectionAnchor,
  headerFooter: controller.isEditingHeaderFooter,
  footer: controller.isEditingFooter,
  section: controller.isEditingHeaderFooter
      ? controller.editingSectionIndex
      : null,
  comment: controller.isEditingComment ? controller.selectedComment : null,
  frame: controller.selectedFrame,
  editingFrame: controller.editingFrame,
  table: controller.selectedTable,
  tableBand: controller.selectedTableBand,
  visual: controller.selectedVisual,
  equation: controller.selectedEquation,
);

class _WordZoteroDialog extends StatefulWidget {
  const _WordZoteroDialog({
    required this.controller,
    this.transport,
    required this.session,
    this.persistApiKey,
  });
  final WordEditorController controller;
  final ZoteroTransport? transport;
  final ZoteroSession session;
  final Future<void> Function(String? apiKey)? persistApiKey;
  @override
  State<_WordZoteroDialog> createState() => _WordZoteroDialogState();
}

class _WordZoteroDialogState extends State<_WordZoteroDialog> {
  late final TextEditingController _key;
  late final TextEditingController _style;
  late final TextEditingController _locale;
  final _search = TextEditingController();
  final _libraryId = TextEditingController();
  final _import = TextEditingController();
  late Object _target;
  ZoteroClient? _client;
  ZoteroKeyInfo? _identity;
  final _groups = <ZoteroGroup>[];
  final _collections = <ZoteroCollection>[];
  ZoteroPage<ZoteroItem>? _page;
  String? _collectionKey;
  int? _moreGroups;
  int? _moreCollections;
  var _publicGroup = true;
  var _busy = false;
  String? _error;
  String? _notice;
  final _selected = <String, ZoteroCitationItem>{};
  final _imported = <ZoteroCitationItem>[];
  WordEditorController get _controller => widget.controller;
  ZoteroSession get _session => widget.session;
  bool get _canEdit =>
      _controller.config.allowsMutation && !_controller.document.trackRevisions;
  List<ZoteroCitationItem> get _documentItems => [
    for (final field in _controller.zoteroFields) ...?field.citation?.items,
  ];

  @override
  void initState() {
    super.initState();
    _target = _editTarget(_controller);
    _key = TextEditingController(text: _session.apiKey ?? '');
    _style = TextEditingController(text: _session.style);
    _locale = TextEditingController(text: _session.locale);
    if (widget.transport != null) {
      _client = ZoteroClient(
        transport: widget.transport!,
        apiKey: _session.apiKey,
      );
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _key,
      _style,
      _locale,
      _search,
      _libraryId,
      _import,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted)
        setState(() {
          _error = switch (error) {
            ZoteroApiException e => e.message,
            FormatException e => e.message,
            UnsupportedError e =>
              e.message ?? 'This field cannot be changed safely.',
            StateError e => e.message,
            ArgumentError _ =>
              'Check the library ID, selected sources, style, and locale.',
            _ =>
              'The operation could not finish. Existing document content was kept.',
          };
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _checkTarget() {
    if (!mounted || !_canEdit || _target != _editTarget(_controller)) {
      throw StateError(
        'The document or insertion point changed. Close Zotero and reopen it to continue.',
      );
    }
  }

  void _write(VoidCallback action) {
    _checkTarget();
    action();
    _target = _editTarget(_controller);
    setState(() => _notice = 'Document updated. You can undo this change.');
  }

  Future<void> _connect() => _run(() async {
    final transport = widget.transport;
    if (transport == null)
      throw StateError(
        'This host has no Zotero network transport. Use CSL JSON import.',
      );
    final client = ZoteroClient(transport: transport, apiKey: _key.text);
    final identity = await client.verifyKey();
    if (!mounted) return;
    if (widget.persistApiKey != null) {
      await widget.persistApiKey!(
        _session.rememberKey ? _key.text.trim() : null,
      );
      if (!mounted) return;
    }
    _identity = identity;
    _client = client;
    _session.apiKey = _key.text.trim();
    _session.library = identity.canReadPersonalLibrary
        ? ZoteroLibrary.user(identity.userId)
        : null;
    _groups.clear();
    _collections.clear();
    _collectionKey = null;
    _page = null;
    final groups = await client.groups(identity.userId);
    if (!mounted) return;
    _groups.addAll(groups.items);
    _moreGroups = groups.nextStart;
    _session.library ??= _groups.isEmpty ? null : _groups.first.library;
    if (_session.library != null) await _loadLibrary();
    if (mounted)
      setState(
        () => _notice =
            'Connected as ${identity.username}. Library access is read-only.',
      );
  });

  Future<void> _loadLibrary() async {
    final library = _session.library;
    if (library == null || _client == null) return;
    _collectionKey = null;
    _collections.clear();
    _page = null;
    final collections = await _client!.collections(library, limit: 100);
    if (!mounted) return;
    _collections.addAll(collections.items);
    _moreCollections = collections.nextStart;
    await _loadItems();
  }

  Future<void> _loadItems({int start = 0}) async {
    final library = _session.library;
    if (library == null || _client == null) return;
    final page = await _client!.items(
      library,
      collectionKey: _collectionKey,
      query: _search.text,
      start: start,
    );
    if (mounted) setState(() => _page = page);
  }

  Future<void> _openPublic() => _run(() async {
    final id = int.tryParse(_libraryId.text.trim());
    if (id == null || id <= 0)
      throw const FormatException('Enter a numeric Zotero user or group ID.');
    _session.library = _publicGroup
        ? ZoteroLibrary.group(id)
        : ZoteroLibrary.user(id);
    _client = ZoteroClient(
      transport: widget.transport!,
      apiKey: _session.apiKey,
    );
    await _loadLibrary();
  });

  Future<void> _disconnect() => _run(() async {
    if (widget.persistApiKey != null) await widget.persistApiKey!(null);
    if (!mounted) return;
    _key.clear();
    _session
      ..apiKey = null
      ..library = null
      ..rememberKey = false;
    _identity = null;
    _groups.clear();
    _collections.clear();
    _page = null;
    _selected.clear();
    _client = widget.transport == null
        ? null
        : ZoteroClient(transport: widget.transport!);
    setState(
      () => _notice =
          'Disconnected. The saved key was removed; citations remain in the document.',
    );
  });

  Future<void> _selectItem(ZoteroItem item, bool selected) => _run(() async {
    if (!selected) {
      setState(() => _selected.remove(item.sourceId));
      return;
    }
    if (_selected.length >= 20)
      throw const FormatException('Select at most 20 sources per citation.');
    final full = item.cslJson == null
        ? await _client!.item(item.library, item.key)
        : item;
    if (!mounted) return;
    final data = full.cslJson;
    if (data == null)
      throw const FormatException('Zotero returned no CSL data for this item.');
    setState(
      () => _selected[item.sourceId] = ZoteroCitationItem.fromCsl(
        itemData: data,
        uris: [item.canonicalUri.toString()],
      ),
    );
  });

  Future<void> _compose(
    List<ZoteroCitationItem> items, {
    WmlZoteroField? field,
  }) => _run(() async {
    _checkTarget();
    final result = await showDialog<ZoteroCitation>(
      context: context,
      builder: (_) =>
          _CitationComposer(items: items, existing: field?.citation),
    );
    if (!mounted || result == null) return;
    _write(
      () => field == null
          ? _controller.insertZoteroCitation(result)
          : _controller.updateZoteroCitation(field, result),
    );
  });

  void _saveFormat() {
    _session.style = _style.text.trim();
    _session.locale = _locale.text.trim();
  }

  Future<void> _bibliography({
    required bool online,
    WmlZoteroField? field,
  }) => _run(() async {
    _checkTarget();
    _saveFormat();
    final items = _documentItems;
    if (items.isEmpty)
      throw const FormatException(
        'Insert a citation before creating its bibliography.',
      );
    String text;
    if (online) {
      final addresses = <String, ZoteroSourceAddress>{};
      for (final item in items) {
        final address = item.uris
            .map(ZoteroSourceAddress.parse)
            .whereType<ZoteroSourceAddress>()
            .firstOrNull;
        if (address == null)
          throw const FormatException(
            'Some sources are offline or unlinked. Use the basic bibliography.',
          );
        addresses['${address.library.apiPath}/${address.key}'] = address;
      }
      final library = addresses.values.first.library;
      if (addresses.values.any((item) => item.library != library) ||
          addresses.length > 50) {
        throw const FormatException(
          'A Zotero-formatted bibliography needs at most 50 sources in one library. Use basic format or export CSL JSON.',
        );
      }
      if (_client == null) throw StateError('Connect a Zotero library first.');
      text = zoteroHtmlToPlainText(
        await _client!.bibliography(
          library,
          itemKeys: addresses.values.map((item) => item.key).toList(),
          style: _session.style,
          locale: _session.locale,
        ),
      );
    } else {
      text = zoteroBasicBibliography(items);
    }
    if (!mounted) return;
    if (text.trim().isEmpty)
      throw const FormatException('No bibliography text was returned.');
    final reviewed = await _reviewText(
      online ? 'Zotero bibliography — plain text' : 'Basic bibliography',
      text,
    );
    if (!mounted || reviewed == null) return;
    _write(
      () => field == null
          ? _controller.insertZoteroBibliography(text: reviewed)
          : _controller.updateZoteroBibliography(field, text: reviewed),
    );
  });

  Future<void> _refresh() => _run(() async {
    _checkTarget();
    if (_client == null) throw StateError('Connect a Zotero library first.');
    final fields = _controller.zoteroFields
        .where(
          (field) =>
              field.citation != null &&
              field.citation!.properties['qudsFormat'] == 'basic-author-year',
        )
        .toList();
    if (fields.isEmpty)
      throw const FormatException(
        'No basic author–year citations to refresh. Imported or custom-formatted citations are kept as they are.',
      );
    if (fields.any((field) => !field.canEdit))
      throw const FormatException(
        'One or more citations cannot be safely edited.',
      );
    final fetched = <String, Map<String, dynamic>>{};
    final updates = <String, ZoteroCitation>{};
    for (final field in fields) {
      final citation = field.citation!;
      final items = <ZoteroCitationItem>[];
      for (final item in citation.items) {
        final address = item.uris
            .map(ZoteroSourceAddress.parse)
            .whereType<ZoteroSourceAddress>()
            .firstOrNull;
        if (address == null) {
          items.add(item);
          continue;
        }
        final uri = address.library.itemUri(address.key).toString();
        if (!fetched.containsKey(uri)) {
          if (fetched.length >= 50)
            throw const FormatException(
              'Refresh at most 50 linked sources at once.',
            );
          final remote = await _client!.item(address.library, address.key);
          if (!mounted) return;
          if (remote.cslJson == null)
            throw const FormatException(
              'A source has no CSL data. Existing citations were kept.',
            );
          fetched[uri] = remote.cslJson!;
        }
        items.add(
          ZoteroCitationItem.fromJson({
            ...item.toJson(),
            'itemData': {...fetched[uri]!, 'id': item.id},
          }),
        );
      }
      updates[citation.citationId] = citation.withItems(
        items,
        plainCitation: zoteroBasicCitation(items),
      );
    }
    if (!mounted) return;
    _write(() => _controller.refreshZoteroCitations(updates));
  });

  Future<void> _copySources({ZoteroExportFormat? format}) => _run(() async {
    String text;
    if (format == null) {
      text = const JsonEncoder.withIndent(
        '  ',
      ).convert(WordZotero.embeddedItems(_controller.document));
    } else {
      final addresses = _selected.values
          .map(
            (item) => item.uris
                .map(ZoteroSourceAddress.parse)
                .whereType<ZoteroSourceAddress>()
                .firstOrNull,
          )
          .toList();
      if (addresses.isEmpty ||
          addresses.any((address) => address == null) ||
          addresses.any(
            (address) => address!.library != addresses.first!.library,
          )) {
        throw const FormatException(
          'Select sources from one Zotero library to export.',
        );
      }
      text = await _client!.exportItems(
        addresses.first!.library,
        addresses.map((address) => address!.key).toList(),
        format: format,
      );
    }
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted)
      setState(() => _notice = 'Reference data copied to the clipboard.');
  });

  Future<String?> _reviewText(String title, String initial) async {
    final text = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 620,
            child: TextField(
              controller: text,
              minLines: 5,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'Review before inserting',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (text.text.trim().isNotEmpty)
                  Navigator.pop(context, text.text);
              },
              child: const Text('Use bibliography'),
            ),
          ],
        ),
      );
    } finally {
      text.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      child: SizedBox(
        width: 980,
        height: min(760, size.height - 64),
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_outlined),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Zotero references',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close Zotero',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Library'),
                  Tab(text: 'Document'),
                  Tab(text: 'Import CSL JSON'),
                ],
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (!_canEdit)
                _banner(
                  _controller.document.trackRevisions
                      ? 'Turn off Track changes to insert or edit citations. Existing fields remain preserved.'
                      : 'This document is read-only. You can browse and export reference data.',
                ),
              if (_error != null) _banner(_error!, error: true),
              if (_notice != null) _banner(_notice!),
              Expanded(
                child: TabBarView(
                  children: [_libraryTab(), _documentTab(), _importTab()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(String text, {bool error = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    color: error
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Text(text, maxLines: 4, overflow: TextOverflow.ellipsis),
  );

  Widget _libraryTab() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('zotero-api-key'),
                controller: _key,
                enabled: !_busy && widget.transport != null,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Read-only Zotero API key',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) {
                  if (!_busy && widget.transport != null) _connect();
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy || widget.transport == null ? null : _connect,
              child: const Text('Connect'),
            ),
          ],
        ),
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://www.zotero.org/settings/keys/new'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Create a read-only key'),
            ),
            if (widget.persistApiKey != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _session.rememberKey,
                    onChanged: _busy
                        ? null
                        : (value) => setState(
                            () => _session.rememberKey = value ?? false,
                          ),
                  ),
                  const Text('Remember key on this device'),
                ],
              ),
            if (_session.apiKey != null)
              TextButton(
                onPressed: _busy ? null : _disconnect,
                child: const Text('Disconnect & forget'),
              ),
          ],
        ),
        if (widget.transport == null)
          const Text(
            'Online access is unavailable in this host. Import CSL JSON to work offline.',
          ),
        if (_identity != null || _groups.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<ZoteroLibrary>(
                  key: ValueKey('library-${_session.library}'),
                  initialValue: _libraryOptions().containsKey(_session.library)
                      ? _session.library
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Library',
                    isDense: true,
                  ),
                  items: _libraryOptions().entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(
                            entry.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (library) {
                          if (library != null)
                            _run(() async {
                              _session.library = library;
                              await _loadLibrary();
                            });
                        },
                ),
              ),
              if (_moreGroups != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final page = await _client!.groups(
                            _identity!.userId,
                            start: _moreGroups!,
                          );
                          if (mounted)
                            setState(() {
                              _groups.addAll(page.items);
                              _moreGroups = page.nextStart;
                            });
                        }),
                  child: const Text('More groups'),
                ),
            ],
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'Open a library by ID',
            style: TextStyle(fontSize: 13),
          ),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<bool>(
                  value: _publicGroup,
                  items: const [
                    DropdownMenuItem(value: true, child: Text('Group')),
                    DropdownMenuItem(value: false, child: Text('User')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _publicGroup = value!),
                ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _libraryId,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Numeric library ID',
                      isDense: true,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: _busy || widget.transport == null
                      ? null
                      : _openPublic,
                  child: const Text('Open library'),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Public libraries work without a key. Private libraries need read access.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        if (_session.library != null) ...[
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'collections-${_session.library}-$_collectionKey-${_collections.length}',
                  ),
                  initialValue: _collectionKey ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Collection',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All items')),
                    ..._collections.map(
                      (collection) => DropdownMenuItem(
                        value: collection.key,
                        child: Text(
                          collection.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (key) => _run(() async {
                          _collectionKey = key == '' ? null : key;
                          await _loadItems();
                        }),
                ),
              ),
              if (_moreCollections != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final page = await _client!.collections(
                            _session.library!,
                            start: _moreCollections!,
                            limit: 100,
                          );
                          if (mounted)
                            setState(() {
                              _collections.addAll(page.items);
                              _moreCollections = page.nextStart;
                            });
                        }),
                  child: const Text('More collections'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'Search title, creator, or year',
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _busy ? null : () => _run(_loadItems),
                tooltip: 'Search',
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
            onSubmitted: (_) {
              if (!_busy) _run(_loadItems);
            },
          ),
        ],
        Expanded(
          child: _page == null
              ? const Center(
                  child: Text('Connect Zotero or open a public library.'),
                )
              : _page!.items.where((item) => item.isCitable).isEmpty
              ? const Center(child: Text('No citable references on this page.'))
              : ListView.builder(
                  itemCount: _page!.items.length,
                  itemBuilder: (context, index) {
                    final item = _page!.items[index];
                    if (!item.isCitable) return const SizedBox.shrink();
                    return CheckboxListTile(
                      value: _selected.containsKey(item.sourceId),
                      dense: true,
                      title: Text(
                        zoteroHtmlToPlainText(item.title),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          item.creatorSummary,
                          item.year,
                          item.itemType,
                        ].where((text) => text.isNotEmpty).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: _busy
                          ? null
                          : (selected) => _selectItem(item, selected ?? false),
                    );
                  },
                ),
        ),
        if (_page != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_page!.start + 1}–${_page!.start + _page!.items.length}${_page!.totalResults == null ? '' : ' of ${_page!.totalResults}'}',
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: _busy || _page!.start == 0
                        ? null
                        : () => _run(
                            () => _loadItems(
                              start: max(0, _page!.start - _page!.limit),
                            ),
                          ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: _busy || !_page!.hasMore
                        ? null
                        : () =>
                              _run(() => _loadItems(start: _page!.nextStart!)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${_selected.length} selected'),
            TextButton(
              onPressed: _busy || _selected.isEmpty
                  ? null
                  : () => setState(_selected.clear),
              child: const Text('Clear selection'),
            ),
            FilledButton.icon(
              onPressed: _busy || !_canEdit || _selected.isEmpty
                  ? null
                  : () => _compose(_selected.values.toList()),
              icon: const Icon(Icons.format_quote),
              label: const Text('Insert citation'),
            ),
            PopupMenuButton<ZoteroExportFormat>(
              enabled: !_busy && _selected.isNotEmpty,
              tooltip: 'Copy selected references',
              onSelected: (format) => _copySources(format: format),
              itemBuilder: (_) => ZoteroExportFormat.values
                  .map(
                    (format) => PopupMenuItem(
                      value: format,
                      child: Text('Copy ${format.name}'),
                    ),
                  )
                  .toList(),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Text('Export selected ▾'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Map<ZoteroLibrary, String> _libraryOptions() => {
    if (_identity?.canReadPersonalLibrary == true)
      ZoteroLibrary.user(_identity!.userId): 'My library',
    for (final group in _groups) group.library: group.name,
  };

  Widget _documentTab() {
    final fields = _controller.zoteroFields;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Citation fields retain source data in DOCX. Basic author–year text supports offline work; Zotero-formatted bibliographies use your selected style.',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _style,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Zotero style ID',
                    hintText: 'apa',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _locale,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Locale',
                    hintText: 'en-US',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton(
                onPressed:
                    _busy ||
                        !_canEdit ||
                        _documentItems.isEmpty ||
                        _client == null
                    ? null
                    : () => _bibliography(online: true),
                child: const Text('Zotero bibliography'),
              ),
              OutlinedButton(
                onPressed: _busy || !_canEdit || _documentItems.isEmpty
                    ? null
                    : () => _bibliography(online: false),
                child: const Text('Basic bibliography'),
              ),
              OutlinedButton(
                onPressed: _busy || !_canEdit || _client == null
                    ? null
                    : _refresh,
                child: const Text('Refresh basic citations'),
              ),
              TextButton(
                onPressed: _busy || _documentItems.isEmpty
                    ? null
                    : () => _copySources(),
                child: const Text('Copy embedded CSL JSON'),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Refresh updates only citations created with basic author–year format. Document-wide CSL numbering, disambiguation, and the Zotero desktop picker are not provided.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: fields.isEmpty
                ? const Center(
                    child: Text('No Zotero fields in this document.'),
                  )
                : ListView.separated(
                    itemCount: fields.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final field = fields[index];
                      final citation = field.citation;
                      return ListTile(
                        title: Text(
                          field.cachedText.isEmpty
                              ? '(Empty cached text)'
                              : field.cachedText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${field.kind.name}${field.canEdit ? '' : ' · preserved, read-only structure'}${citation == null ? '' : ' · ${citation.items.length} source(s)'}',
                        ),
                        trailing: PopupMenuButton<String>(
                          enabled: !_busy && _canEdit && field.isValid,
                          tooltip: 'Reference actions',
                          onSelected: (action) {
                            if (action == 'edit')
                              _compose(citation!.items, field: field);
                            if (action == 'basic')
                              _bibliography(online: false, field: field);
                            if (action == 'online')
                              _bibliography(online: true, field: field);
                            if (action == 'unlink')
                              _run(() async {
                                _write(
                                  () => _controller.unlinkZoteroField(field),
                                );
                              });
                          },
                          itemBuilder: (_) => [
                            if (citation != null && field.canEdit)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit citation'),
                              ),
                            if (field.kind == ZoteroFieldKind.bibliography &&
                                field.canEdit) ...[
                              const PopupMenuItem(
                                value: 'basic',
                                child: Text('Update basic bibliography'),
                              ),
                              if (_client != null)
                                const PopupMenuItem(
                                  value: 'online',
                                  child: Text('Update Zotero bibliography'),
                                ),
                            ],
                            if (!field.locked && !field.nested)
                              const PopupMenuItem(
                                value: 'unlink',
                                child: Text('Convert to text (undoable)'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _importTab() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'In Zotero, export references as CSL JSON, then paste the file contents here. Sources stay embedded in the document. Records without a Zotero item URI remain offline references.',
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            key: const ValueKey('zotero-csl-import'),
            controller: _import,
            expands: true,
            minLines: null,
            maxLines: null,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'CSL JSON (up to 1 MB / 500 sources)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final items = zoteroImportCslJson(_import.text);
                      setState(() {
                        _imported
                          ..clear()
                          ..addAll(items);
                        _notice =
                            '${items.length} references loaded. Choose a citation below.';
                      });
                    }),
              child: const Text('Load references'),
            ),
            if (_imported.isNotEmpty) Text('${_imported.length} loaded'),
          ],
        ),
        if (_imported.isNotEmpty)
          SizedBox(
            height: 160,
            child: ListView.builder(
              itemCount: _imported.length,
              itemBuilder: (context, index) {
                final item = _imported[index];
                final key = 'import:$index:${item.id}';
                return CheckboxListTile(
                  dense: true,
                  value: _selected.containsKey(key),
                  title: Text(
                    zoteroHtmlToPlainText(
                      '${item.itemData?['title'] ?? item.id}',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          if (value == false) {
                            _selected.remove(key);
                          } else if (_selected.length < 20) {
                            _selected[key] = item;
                          }
                        }),
                );
              },
            ),
          ),
        FilledButton(
          onPressed: _busy || !_canEdit || _selected.isEmpty
              ? null
              : () => _compose(_selected.values.toList()),
          child: Text('Insert ${_selected.length} selected source(s)'),
        ),
      ],
    ),
  );
}

class _CitationComposer extends StatefulWidget {
  const _CitationComposer({required this.items, this.existing});
  final List<ZoteroCitationItem> items;
  final ZoteroCitation? existing;
  @override
  State<_CitationComposer> createState() => _CitationComposerState();
}

class _CitationComposerState extends State<_CitationComposer> {
  late List<ZoteroCitationItem> _items;
  late final TextEditingController _text;
  var _basic = true;
  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
    _basic =
        widget.existing == null ||
        widget.existing!.properties['qudsFormat'] == 'basic-author-year';
    _text = TextEditingController(
      text: widget.existing?.plainCitation ?? zoteroBasicCitation(_items),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _update(int index, Map<String, dynamic> changes) {
    setState(() {
      _items[index] = ZoteroCitationItem.fromJson({
        ..._items[index].toJson(),
        ...changes,
      });
      if (_basic) _text.text = zoteroBasicCitation(_items);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null
          ? 'Insert Zotero citation'
          : 'Edit Zotero citation',
    ),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Source metadata stays linked. Review the visible text before inserting.',
            ),
            for (var index = 0; index < _items.length; index++)
              _sourceOptions(index),
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
              initialValue: _basic,
              decoration: const InputDecoration(
                labelText: 'Citation text format',
              ),
              items: const [
                DropdownMenuItem(value: true, child: Text('Basic author–year')),
                DropdownMenuItem(
                  value: false,
                  child: Text('Custom text / preserve current format'),
                ),
              ],
              onChanged: (value) => setState(() {
                _basic = value!;
                if (_basic) _text.text = zoteroBasicCitation(_items);
              }),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('zotero-citation-preview'),
              controller: _text,
              minLines: 2,
              maxLines: 5,
              readOnly: _basic,
              decoration: const InputDecoration(
                labelText: 'Visible citation text',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Basic format is a portable fallback, not a full CSL style. Imported citations keep their current text until you choose a replacement.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_text.text.trim().isEmpty) return;
          final existing = widget.existing;
          final citation = existing == null
              ? ZoteroCitation(
                  citationId:
                      'Q${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(1 << 30).toRadixString(36)}',
                  items: _items,
                  plainCitation: _text.text,
                )
              : existing.withItems(_items, plainCitation: _text.text);
          Navigator.pop(
            context,
            ZoteroCitation.fromJson({
              ...citation.toJson(),
              'properties': {
                ...citation.properties,
                'qudsFormat': _basic ? 'basic-author-year' : 'custom',
              },
            }),
          );
        },
        child: Text(
          widget.existing == null ? 'Insert citation' : 'Update citation',
        ),
      ),
    ],
  );

  Widget _sourceOptions(int index) {
    final item = _items[index];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        zoteroHtmlToPlainText('${item.itemData?['title'] ?? item.id}'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        item.uris.isEmpty ? 'Offline embedded source' : 'Linked Zotero source',
        style: const TextStyle(fontSize: 12),
      ),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 145,
              child: TextFormField(
                initialValue: item.locator,
                decoration: const InputDecoration(
                  labelText: 'Locator (e.g. 12–15)',
                  isDense: true,
                ),
                onChanged: (value) => _update(index, {'locator': value}),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                initialValue:
                    const [
                      '',
                      'page',
                      'chapter',
                      'section',
                      'paragraph',
                      'volume',
                      'figure',
                    ].contains(item.label)
                    ? item.label
                    : '',
                decoration: const InputDecoration(
                  labelText: 'Locator label',
                  isDense: true,
                ),
                items:
                    const [
                          '',
                          'page',
                          'chapter',
                          'section',
                          'paragraph',
                          'volume',
                          'figure',
                        ]
                        .map(
                          (label) => DropdownMenuItem(
                            value: label,
                            child: Text(
                              label.isEmpty ? 'Page (default)' : label,
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (value) => _update(index, {'label': value ?? ''}),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextFormField(
                initialValue: item.prefix,
                decoration: const InputDecoration(
                  labelText: 'Prefix',
                  isDense: true,
                ),
                onChanged: (value) => _update(index, {'prefix': value}),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextFormField(
                initialValue: item.suffix,
                decoration: const InputDecoration(
                  labelText: 'Suffix',
                  isDense: true,
                ),
                onChanged: (value) => _update(index, {'suffix': value}),
              ),
            ),
          ],
        ),
        CheckboxListTile(
          dense: true,
          title: const Text('Suppress author'),
          value: item.suppressAuthor,
          onChanged: (value) => _update(index, {
            'suppress-author': value ?? false,
            'author-only': false,
          }),
        ),
        CheckboxListTile(
          dense: true,
          title: const Text('Author only'),
          value: item.authorOnly,
          onChanged: (value) => _update(index, {
            'author-only': value ?? false,
            'suppress-author': false,
          }),
        ),
      ],
    );
  }
}
