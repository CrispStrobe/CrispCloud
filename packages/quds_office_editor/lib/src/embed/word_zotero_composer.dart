import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'word_zotero_format.dart';
import 'word_zotero_import.dart';
import 'word_zotero_library.dart';
import 'word_zotero_sources.dart';

/// Stages a citation, including source membership and order, until it is applied.
/// The caller owns document/current-target checks around the returned result.
class ZoteroCitationComposer extends StatefulWidget {
  const ZoteroCitationComposer({
    super.key,
    required this.items,
    this.availableSources = const [],
    this.existing,
    this.existingCache,
    this.loadStyleSnapshot,
    this.searchZoteroSources,
    this.style = 'apa',
  });

  final List<ZoteroCitationItem> items;
  final List<ZoteroCitationItem> availableSources;
  final ZoteroCitation? existing;
  final String? existingCache;

  /// Formats the current single source, never the list at workspace entry.
  final Future<String> Function(ZoteroCitationItem item)? loadStyleSnapshot;

  /// Searches the currently connected library without changing the workspace
  /// selection. The caller pins the connection and returns citable CSL data.
  final Future<ZoteroPage<ZoteroCitationItem>> Function(
    String query,
    int start,
  )?
  searchZoteroSources;
  final String style;

  @override
  State<ZoteroCitationComposer> createState() => _ZoteroCitationComposerState();
}

class _ComposerSource {
  _ComposerSource(this.key, this.item);

  final int key;
  ZoteroCitationItem item;
}

class _ZoteroCitationComposerState extends State<ZoteroCitationComposer> {
  late final List<_ComposerSource> _sources;
  late final List<ZoteroCitationItem> _availableSources;
  late final TextEditingController _text;
  var _nextSourceKey = 0;
  var _basic = true;
  var _loading = false;
  var _customTextReviewed = false;
  String? _error;

  List<ZoteroCitationItem> get _items => [
    for (final source in _sources) source.item,
  ];

  bool get _sourceOrderChanged =>
      _sources.length != widget.items.length ||
      _sources.indexed.any((entry) => entry.$1 != entry.$2.key);

  // A native or custom citation's visible text and formatted cache depend on
  // the options of each occurrence, not just which sources are present. Keys
  // identify the original occurrence even after a reorder (IDs may repeat).
  bool get _sourceOptionsChanged => _sources.any((source) {
    if (source.key >= widget.items.length) return false;
    final before = widget.items[source.key];
    final after = source.item;
    return before.locator != after.locator ||
        before.label != after.label ||
        before.prefix != after.prefix ||
        before.suffix != after.suffix ||
        before.suppressAuthor != after.suppressAuthor ||
        before.authorOnly != after.authorOnly;
  });

  bool get _citationChanged => _sourceOrderChanged || _sourceOptionsChanged;

  bool get _needsTextReview =>
      !_basic && _citationChanged && !_customTextReviewed;

  bool get _canApply =>
      !_loading &&
      _sources.isNotEmpty &&
      _text.text.trim().isNotEmpty &&
      !_needsTextReview;

  bool get _canPreview =>
      widget.loadStyleSnapshot != null &&
      _sources.length == 1 &&
      _sources.single.item.uris.any(
        (uri) => ZoteroSourceAddress.parse(uri) != null,
      );

  @override
  void initState() {
    super.initState();
    _sources = [
      for (final item in widget.items) _ComposerSource(_nextSourceKey++, item),
    ];
    _availableSources = List.unmodifiable(widget.availableSources);
    _basic =
        widget.existing == null ||
        widget.existing!.properties['qudsFormat'] == 'basic-author-year';
    _text = TextEditingController(
      text:
          widget.existingCache ??
          widget.existing?.plainCitation ??
          zoteroBasicCitation(_items),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _sourcesChanged() {
    _customTextReviewed = false;
    _error = null;
    if (_basic) {
      _text.text = _sources.isEmpty ? '' : zoteroBasicCitation(_items);
    }
  }

  void _update(_ComposerSource source, Map<String, dynamic> changes) {
    if (_loading) return;
    setState(() {
      source.item = ZoteroCitationItem.fromJson({
        ...source.item.toJson(),
        ...changes,
      });
      _sourcesChanged();
    });
  }

  void _move(int index, int offset) {
    if (_loading) return;
    setState(() {
      final source = _sources.removeAt(index);
      _sources.insert(index + offset, source);
      _sourcesChanged();
    });
  }

  void _remove(_ComposerSource source) {
    if (_loading) return;
    setState(() {
      _sources.remove(source);
      _sourcesChanged();
    });
  }

  Future<void> _addSources() async {
    if (_loading || _sources.length >= 20) return;
    final result = await showDialog<List<ZoteroCitationItem>>(
      context: context,
      builder: (_) => _CitationSourceChooser(
        sources: _availableSources,
        capacity: 20 - _sources.length,
      ),
    );
    if (!mounted || result == null || result.isEmpty) return;
    // The modal owns no document or parent state; only a complete, accepted
    // selection becomes part of this still-detached citation draft.
    setState(() {
      _sources.addAll([
        for (final item in result)
          _ComposerSource(_nextSourceKey++, zoteroReusableCitationItem(item)),
      ]);
      _sourcesChanged();
    });
  }

  Future<void> _searchZoteroSources() async {
    final search = widget.searchZoteroSources;
    if (_loading || search == null || _sources.length >= 20) return;
    final result = await showDialog<List<ZoteroCitationItem>>(
      context: context,
      builder: (_) => _ConnectedZoteroSourceChooser(
        search: search,
        capacity: 20 - _sources.length,
      ),
    );
    if (!mounted || result == null || result.isEmpty) return;
    setState(() {
      _sources.addAll([
        for (final item in result)
          _ComposerSource(_nextSourceKey++, zoteroReusableCitationItem(item)),
      ]);
      _sourcesChanged();
    });
  }

  Future<void> _showDetails(ZoteroCitationItem item) => showDialog<void>(
    context: context,
    builder: (_) => ZoteroStoredReferenceDetailsDialog(item: item),
  );

  Future<void> _loadStyle() async {
    if (_loading || !_canPreview) return;
    final item = _sources.single.item;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await widget.loadStyleSnapshot!(item);
      if (text.trim().isEmpty) {
        throw const FormatException('No formatted citation was returned.');
      }
      if (mounted) {
        setState(() {
          _basic = false;
          _text.text = text;
          // A style preview is still an individual rendering. After changing
          // membership the user must review locators and document numbering.
          _customTextReviewed = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error) {
            ZoteroApiException e => e.message,
            FormatException e => e.message,
            StateError e => e.message,
            _ =>
              'The style preview could not be loaded. Your current text was kept.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply() {
    if (!_canApply) return;
    try {
      final existing = widget.existing;
      // Existing formattedCitation may use RTF or another processor dialect.
      // Keep it only when both the source sequence and visible cache are intact.
      final formattedCitation =
          !_basic &&
              !_citationChanged &&
              existing != null &&
              _text.text == (widget.existingCache ?? existing.plainCitation)
          ? existing.formattedCitation
          : null;
      final citation = existing == null
          ? ZoteroCitation(
              citationId:
                  'Q${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(1 << 30).toRadixString(36)}',
              items: _items,
              plainCitation: _text.text,
            )
          : existing.withItems(
              _items,
              plainCitation: _text.text,
              formattedCitation: formattedCitation,
            );
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
    } on FormatException catch (error) {
      // Individual source snapshots can fit their limits while the complete
      // citation exceeds the size or nesting bound. Keep the draft editable.
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('zotero-citation-composer'),
    insetPadding: const EdgeInsets.all(16),
    scrollable: true,
    title: Text(
      widget.existing == null
          ? 'Insert Zotero citation'
          : 'Edit Zotero citation',
    ),
    content: SizedBox(
      width: 650,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Source metadata stays linked. Review the visible text before inserting.',
          ),
          const SizedBox(height: 8),
          Text(
            '${_sources.length} source(s)',
            key: const ValueKey('zotero-composer-source-count'),
          ),
          if (_sources.isEmpty)
            const Text('Add at least one source to continue.'),
          for (var index = 0; index < _sources.length; index++)
            _sourceOptions(index),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('zotero-composer-add-sources'),
                  onPressed:
                      _loading ||
                          _sources.length >= 20 ||
                          _availableSources.isEmpty
                      ? null
                      : _addSources,
                  icon: const Icon(Icons.add),
                  label: const Text('Add stored sources'),
                ),
                if (widget.searchZoteroSources != null)
                  OutlinedButton.icon(
                    key: const ValueKey('zotero-composer-search-zotero'),
                    onPressed: _loading || _sources.length >= 20
                        ? null
                        : _searchZoteroSources,
                    icon: const Icon(Icons.search),
                    label: const Text('Search Zotero…'),
                  ),
              ],
            ),
          ),
          if (_sources.length >= 20)
            const Text(
              'Adding sources is limited to 20 per citation. Existing sources stay available to edit, reorder or remove.',
            )
          else if (_availableSources.isEmpty &&
              widget.searchZoteroSources == null)
            const Text(
              'To add sources, select library references or load CSL JSON in the workspace first.',
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<bool>(
            key: ValueKey(_basic),
            initialValue: _basic,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Citation text format',
            ),
            items: const [
              DropdownMenuItem(
                value: true,
                child: Text(
                  'Basic author–year',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: false,
                child: Text(
                  'Custom text / preserve current format',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            onChanged: _loading
                ? null
                : (value) => setState(() {
                    _basic = value!;
                    _customTextReviewed = false;
                    if (_basic) {
                      _text.text = _sources.isEmpty
                          ? ''
                          : zoteroBasicCitation(_items);
                    }
                  }),
          ),
          const SizedBox(height: 10),
          if (_canPreview) ...[
            OutlinedButton(
              key: const ValueKey('zotero-composer-style-preview'),
              onPressed: _loading ? null : _loadStyle,
              child: Text(
                _loading
                    ? 'Loading style preview…'
                    : 'Use ${widget.style} single-source preview',
              ),
            ),
            const Text(
              'Individual preview only. Review locators and document numbering before inserting.',
              style: TextStyle(fontSize: 12),
            ),
          ],
          if (_error != null)
            Text(
              _error!,
              key: const ValueKey('zotero-composer-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          TextField(
            key: const ValueKey('zotero-citation-preview'),
            controller: _text,
            minLines: 2,
            maxLines: 5,
            readOnly: _basic || _loading,
            onChanged: (_) => setState(() => _customTextReviewed = true),
            decoration: const InputDecoration(
              labelText: 'Visible citation text',
              border: OutlineInputBorder(),
            ),
          ),
          if (!_basic && _citationChanged) ...[
            const SizedBox(height: 8),
            const Text(
              'Sources, order or citation options changed. Edit the visible text or confirm that it matches the current sources and options before applying. Previous formatted styling will be discarded.',
              key: ValueKey('zotero-composer-text-review-message'),
            ),
            CheckboxListTile(
              key: const ValueKey('zotero-composer-confirm-text'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I reviewed this text for the current sources.',
              ),
              value: _customTextReviewed,
              onChanged: _loading
                  ? null
                  : (value) =>
                        setState(() => _customTextReviewed = value ?? false),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Basic format is a portable fallback, not a full CSL style. Imported citations keep their current text until you choose a replacement.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('zotero-composer-cancel'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('zotero-composer-apply'),
        onPressed: _canApply ? _apply : null,
        child: Text(
          widget.existing == null ? 'Insert citation' : 'Update citation',
        ),
      ),
    ],
  );

  Widget _sourceOptions(int index) {
    final source = _sources[index];
    final item = source.item;
    final labels = [
      '',
      'page',
      'chapter',
      'section',
      'paragraph',
      'volume',
      'figure',
    ];
    if (!labels.contains(item.label)) labels.add(item.label);
    return Column(
      key: ValueKey('zotero-composer-source-${source.key}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpansionTile(
          key: ValueKey('zotero-composer-options-${source.key}'),
          tilePadding: EdgeInsets.zero,
          title: Text(
            zoteroHtmlToPlainText('${item.itemData?['title'] ?? item.id}'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            item.uris.isEmpty
                ? 'Offline embedded source'
                : 'Linked Zotero source',
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
                    key: ValueKey('zotero-composer-locator-${source.key}'),
                    initialValue: item.locator,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Locator (e.g. 12–15)',
                      isDense: true,
                    ),
                    onChanged: (value) => _update(source, {'locator': value}),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('zotero-composer-label-${source.key}'),
                    isExpanded: true,
                    initialValue: item.label,
                    decoration: const InputDecoration(
                      labelText: 'Locator label',
                      isDense: true,
                    ),
                    items: [
                      for (final label in labels)
                        DropdownMenuItem(
                          value: label,
                          child: Text(
                            label.isEmpty ? 'Page (default)' : label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _loading
                        ? null
                        : (value) => _update(source, {'label': value ?? ''}),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: TextFormField(
                    key: ValueKey('zotero-composer-prefix-${source.key}'),
                    initialValue: item.prefix,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Prefix',
                      isDense: true,
                    ),
                    onChanged: (value) => _update(source, {'prefix': value}),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: TextFormField(
                    key: ValueKey('zotero-composer-suffix-${source.key}'),
                    initialValue: item.suffix,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Suffix',
                      isDense: true,
                    ),
                    onChanged: (value) => _update(source, {'suffix': value}),
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              key: ValueKey('zotero-composer-suppress-author-${source.key}'),
              dense: true,
              title: const Text('Suppress author'),
              value: item.suppressAuthor,
              onChanged: _loading
                  ? null
                  : (value) => _update(source, {
                      'suppress-author': value ?? false,
                      'author-only': false,
                    }),
            ),
            CheckboxListTile(
              key: ValueKey('zotero-composer-author-only-${source.key}'),
              dense: true,
              title: const Text('Author only'),
              value: item.authorOnly,
              onChanged: _loading
                  ? null
                  : (value) => _update(source, {
                      'author-only': value ?? false,
                      'suppress-author': false,
                    }),
            ),
          ],
        ),
        Wrap(
          spacing: 4,
          children: [
            IconButton(
              key: ValueKey('zotero-composer-details-${source.key}'),
              onPressed: _loading ? null : () => _showDetails(item),
              tooltip: 'Stored reference details',
              icon: const Icon(Icons.info_outline),
            ),
            IconButton(
              key: ValueKey('zotero-composer-up-${source.key}'),
              onPressed: _loading || index == 0 ? null : () => _move(index, -1),
              tooltip: 'Move source up',
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              key: ValueKey('zotero-composer-down-${source.key}'),
              onPressed: _loading || index == _sources.length - 1
                  ? null
                  : () => _move(index, 1),
              tooltip: 'Move source down',
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              key: ValueKey('zotero-composer-remove-${source.key}'),
              onPressed: _loading ? null : () => _remove(source),
              tooltip: 'Remove source from citation',
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
        const Divider(),
      ],
    );
  }
}

class _CitationSourceChooser extends StatefulWidget {
  const _CitationSourceChooser({required this.sources, required this.capacity});

  final List<ZoteroCitationItem> sources;
  final int capacity;

  @override
  State<_CitationSourceChooser> createState() => _CitationSourceChooserState();
}

class _CitationSourceChooserState extends State<_CitationSourceChooser> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _selected = <int>{};
  late final _references = [
    for (var index = 0; index < widget.sources.length; index++)
      ZoteroImportedReference(index: index, item: widget.sources[index]),
  ];
  String? _notice;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _select(int index, bool selected) => setState(() {
    if (!selected) {
      _selected.remove(index);
      _notice = null;
    } else if (_selected.length >= widget.capacity) {
      _notice = 'Select at most ${widget.capacity} additional source(s).';
    } else {
      _selected.add(index);
      _notice = null;
    }
  });

  @override
  Widget build(BuildContext context) {
    final visible = filterZoteroImportedReferences(_references, _search.text);
    final visibleIndexes = visible.map((reference) => reference.index).toSet();
    final hidden = _selected.where((index) => !visibleIndexes.contains(index));
    return AlertDialog(
      key: const ValueKey('zotero-composer-source-chooser'),
      insetPadding: const EdgeInsets.all(16),
      scrollable: true,
      title: const Text('Add citation sources'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose stored references from the document, your selection or loaded CSL JSON. New sources start without earlier citation options.',
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('zotero-composer-source-search'),
              controller: _search,
              onChanged: (_) => setState(() {
                if (_scroll.hasClients) _scroll.jumpTo(0);
              }),
              decoration: const InputDecoration(
                labelText: 'Search available sources',
                hintText: 'Title, creator, year or DOI',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${visible.length} of ${_references.length} references · ${_selected.length} selected',
              key: const ValueKey('zotero-composer-candidate-count'),
            ),
            if (hidden.isNotEmpty)
              Text(
                '${hidden.length} selected outside these results',
                key: const ValueKey('zotero-composer-hidden-selection'),
              ),
            if (_notice != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _notice!,
                  key: const ValueKey('zotero-composer-selection-notice'),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: max(
                120,
                min(360, MediaQuery.sizeOf(context).height * .4),
              ),
              child: visible.isEmpty
                  ? const Center(child: Text('No matching references.'))
                  : ListView.builder(
                      key: const ValueKey('zotero-composer-candidate-list'),
                      controller: _scroll,
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final reference = visible[index];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: CheckboxListTile(
                                key: ValueKey(
                                  'zotero-composer-candidate-${reference.index}',
                                ),
                                contentPadding: EdgeInsets.zero,
                                value: _selected.contains(reference.index),
                                title: Text(
                                  reference.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: reference.subtitle.isEmpty
                                    ? null
                                    : Text(
                                        reference.subtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                onChanged: (value) =>
                                    _select(reference.index, value ?? false),
                              ),
                            ),
                            IconButton(
                              key: ValueKey(
                                'zotero-composer-candidate-details-${reference.index}',
                              ),
                              tooltip: 'Stored reference details',
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) =>
                                    ZoteroStoredReferenceDetailsDialog(
                                      item: reference.item,
                                    ),
                              ),
                              icon: const Icon(Icons.info_outline),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('zotero-composer-source-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('zotero-composer-source-add'),
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final index in _selected) widget.sources[index],
                ]),
          child: Text('Add ${_selected.length} source(s)'),
        ),
      ],
    );
  }
}

/// A deliberately detached, query-on-submit source picker. Searching and
/// paging never alter the citation; only accepting the chosen records does.
class _ConnectedZoteroSourceChooser extends StatefulWidget {
  const _ConnectedZoteroSourceChooser({
    required this.search,
    required this.capacity,
  });

  final Future<ZoteroPage<ZoteroCitationItem>> Function(String query, int start)
  search;
  final int capacity;

  @override
  State<_ConnectedZoteroSourceChooser> createState() =>
      _ConnectedZoteroSourceChooserState();
}

class _ConnectedZoteroSourceChooserState
    extends State<_ConnectedZoteroSourceChooser> {
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  final _scroll = ScrollController();
  final _selected = <String, ZoteroCitationItem>{};
  final _resultFocus = <String, ({FocusNode node, GlobalKey anchor})>{};
  List<ZoteroCitationItem> _results = const [];
  String _submittedQuery = '';
  String? _error;
  int? _nextStart;
  bool _loading = false;
  bool _searched = false;
  int _focusRequest = 0;

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    _scroll.dispose();
    for (final focus in _resultFocus.values) {
      focus.node.dispose();
    }
    super.dispose();
  }

  String _key(ZoteroCitationItem item) {
    for (final uri in item.uris) {
      final address = ZoteroSourceAddress.parse(uri);
      if (address != null) return address.canonicalUri.toString();
    }
    // Offline snapshots returned by one connected library use their CSL ID.
    return 'offline:${item.id}';
  }

  void _focusQuery() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    _focusRequest++;
    _queryFocus.requestFocus();
    final queryContext = _queryFocus.context;
    if (queryContext != null) Scrollable.ensureVisible(queryContext);
  }

  Future<void> _focusResult(int index) async {
    if (_loading || index < 0 || index >= _results.length) return;
    final request = ++_focusRequest;
    final target = _resultFocus[_key(_results[index])]!;
    if (_queryFocus.hasFocus && _scroll.hasClients) {
      _scroll.jumpTo(0);
    } else {
      // Restore the current row before moving from it, even after a pointer
      // scroll. This also lets the next lazy row be built beside that row.
      final current = _resultFocus.values
          .where((focus) => focus.node.hasFocus)
          .firstOrNull;
      final currentContext = current?.anchor.currentContext;
      if (currentContext != null) {
        await Scrollable.ensureVisible(currentContext);
      }
    }
    while (mounted && request == _focusRequest) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          _loading ||
          request != _focusRequest ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final targetContext = target.anchor.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(targetContext, alignment: 0.5);
        if (mounted && request == _focusRequest) target.node.requestFocus();
        return;
      }
      if (!_scroll.hasClients) return;
      final firstBuilt = _results.indexWhere(
        (item) => _resultFocus[_key(item)]!.anchor.currentContext != null,
      );
      if (firstBuilt < 0) return;
      final position = _scroll.position;
      final direction = index < firstBuilt ? -1 : 1;
      final next = (position.pixels + direction * position.viewportDimension)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (next == position.pixels) return;
      // Results have variable height, especially at enlarged text sizes. Move
      // by a viewport until the requested adjacent row exists, then reveal it.
      _scroll.jumpTo(next);
    }
  }

  Future<void> _search({bool more = false}) async {
    if (_loading) return;
    final query = more ? _submittedQuery : _query.text.trim();
    final start = more ? _nextStart : 0;
    if (query.isEmpty || start == null) return;
    setState(() {
      _focusRequest++;
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.search(query, start);
      if (!mounted) return;
      setState(() {
        _submittedQuery = query;
        _searched = true;
        _nextStart = page.nextStart;
        final unique = <String, ZoteroCitationItem>{
          if (more)
            for (final item in _results) _key(item): item,
          for (final item in page.items) _key(item): item,
        };
        for (final key in _resultFocus.keys.toList()) {
          if (!unique.containsKey(key)) {
            _resultFocus.remove(key)!.node.dispose();
          }
        }
        for (final key in unique.keys) {
          _resultFocus.putIfAbsent(
            key,
            () => (node: FocusNode(), anchor: GlobalKey()),
          );
        }
        _results = List.unmodifiable(unique.values);
      });
      if (!more && _scroll.hasClients) _scroll.jumpTo(0);
    } on ZoteroApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not search Zotero. Check the connection and try again. '
              'Your selections are kept.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (!more) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _focusQuery());
        }
      }
    }
  }

  void _select(ZoteroCitationItem item, bool checked) {
    final key = _key(item);
    setState(() {
      if (!checked) {
        _selected.remove(key);
        _error = null;
      } else if (_selected.length >= widget.capacity) {
        _error = 'Select at most ${widget.capacity} additional source(s).';
      } else {
        _selected[key] = item;
        _error = null;
      }
    });
  }

  Future<void> _reviewSelection() async {
    if (_loading || _selected.isEmpty) return;
    final selection = Map<String, ZoteroCitationItem>.of(_selected);
    final keys = await showDialog<List<String>>(
      context: context,
      builder: (_) => ZoteroSelectedReferencesDialog(selection: selection),
    );
    if (!mounted || keys == null) return;
    setState(() {
      _selected
        ..clear()
        ..addAll({for (final key in keys) key: selection[key]!});
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleKeys = {for (final item in _results) _key(item)};
    final hidden = _selected.keys.where((key) => !visibleKeys.contains(key));
    final hiddenCount = hidden.length;
    return AlertDialog(
      key: const ValueKey('zotero-connected-source-chooser'),
      insetPadding: const EdgeInsets.all(16),
      scrollable: true,
      title: const Text('Search Zotero library'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Search the connected library without leaving this citation. '
              'Results are staged until you add them; the document stays '
              'unchanged until you update the citation.',
            ),
            const SizedBox(height: 8),
            CallbackShortcuts(
              bindings: {
                if (!_loading && _results.isNotEmpty)
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _focusResult(0),
              },
              child: TextField(
                key: const ValueKey('zotero-connected-source-query'),
                controller: _query,
                focusNode: _queryFocus,
                autofocus: true,
                enabled: !_loading,
                maxLength: 1024,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(
                  labelText: 'Search titles, creators or years',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: const ValueKey('zotero-connected-source-search'),
                onPressed: _loading || _query.text.trim().isEmpty
                    ? null
                    : _search,
                child: Text(_loading ? 'Searching…' : 'Search'),
              ),
            ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const ValueKey('zotero-connected-source-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '${_results.length} results loaded · ${_selected.length} selected'
              '${hiddenCount == 0 ? '' : ' · $hiddenCount hidden'}',
              key: const ValueKey('zotero-connected-source-count'),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('zotero-connected-source-review'),
                onPressed: _loading || _selected.isEmpty
                    ? null
                    : _reviewSelection,
                icon: const Icon(Icons.checklist),
                label: const Text('Review selected'),
              ),
            ),
            if (_results.isNotEmpty)
              Text(
                'Use the arrow keys to browse results and Enter or Space to select.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            SizedBox(
              height: max(
                120,
                min(310, MediaQuery.sizeOf(context).height - 310),
              ),
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        !_searched
                            ? 'Enter a query to search your connected library.'
                            : 'No citable sources with CSL data were returned.',
                      ),
                    )
                  : ListView.builder(
                      key: const ValueKey('zotero-connected-source-list'),
                      controller: _scroll,
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        final reference = ZoteroImportedReference(
                          index: index,
                          item: item,
                        );
                        final focus = _resultFocus[_key(item)]!;
                        return CallbackShortcuts(
                          bindings: {
                            if (!_loading) ...{
                              const SingleActivator(
                                LogicalKeyboardKey.arrowDown,
                              ): () => _focusResult(
                                min(index + 1, _results.length - 1),
                              ),
                              const SingleActivator(
                                LogicalKeyboardKey.arrowUp,
                              ): () => index == 0
                                  ? _focusQuery()
                                  : _focusResult(index - 1),
                            },
                          },
                          child: Row(
                            key: focus.anchor,
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  key: ValueKey(
                                    'zotero-connected-source-$index',
                                  ),
                                  focusNode: focus.node,
                                  value: _selected.containsKey(_key(item)),
                                  title: Text(
                                    reference.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: reference.subtitle.isEmpty
                                      ? null
                                      : Text(
                                          reference.subtitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                  onChanged: _loading
                                      ? null
                                      : (value) =>
                                            _select(item, value ?? false),
                                ),
                              ),
                              IconButton(
                                key: ValueKey(
                                  'zotero-connected-source-details-$index',
                                ),
                                tooltip: 'Stored reference details',
                                onPressed: () => showDialog<void>(
                                  context: context,
                                  builder: (_) =>
                                      ZoteroStoredReferenceDetailsDialog(
                                        item: item,
                                      ),
                                ),
                                icon: const Icon(Icons.info_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (_nextStart != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: const ValueKey('zotero-connected-source-more'),
                  onPressed: _loading ? null : () => _search(more: true),
                  icon: const Icon(Icons.more_horiz),
                  label: const Text('Load more'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('zotero-connected-source-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('zotero-connected-source-add'),
          onPressed: _loading || _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected.values.toList()),
          child: Text('Add ${_selected.length} source(s)'),
        ),
      ],
    );
  }
}
