import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:url_launcher/url_launcher.dart';

import 'office_controller.dart';
import 'word_zotero_children.dart';
import 'word_zotero_composer.dart';
import 'word_zotero_document_sources.dart';
import 'word_zotero_format.dart';
import 'word_zotero_import.dart';
import 'word_zotero_library.dart';
import 'word_zotero_snapshot.dart';
import 'word_zotero_sources.dart';
import 'word_zotero_tags.dart';

/// Connection preferences belong to the host session, never to a document.
class ZoteroSession {
  final _onlineBackoff = ZoteroBackoffState();
  String? apiKey;
  bool rememberKey = false;
  bool useLocal = false;
  ZoteroLibrary? library;
  String style = 'apa';
  String locale = 'en-US';
}

class _ZoteroSelectionExport {
  const _ZoteroSelectionExport.stored() : format = null;
  const _ZoteroSelectionExport.connected(ZoteroExportFormat value)
    : format = value;

  final ZoteroExportFormat? format;
}

/// The workspace page to show when opening Zotero references.
enum WordZoteroTab { library, document, importCslJson }

/// Shared Quds citation workspace. The host supplies its own network transport
/// and may opt into its existing credential store. [localTransport] explicitly
/// enables desktop access and must connect directly to localhost without a
/// remote proxy. It is never used as a fallback for the web transport.
/// Without a transport, local
/// CSL import, field editing, and embedded-source export remain available.
/// An existing field at the caret opens [WordZoteroTab.document] by default.
/// Hosts can set [initialTab] explicitly, or pass [initialCommand] to open the
/// Document page and immediately start an explicitly requested desktop action.
/// With [closeAfterCommand], a compact progress dialog returns to the editor
/// after success, cancellation or an unchanged result. Errors remain visible.
/// The ordinary references workspace stays open unless the user closes it or
/// chooses a reference to reveal in the document.
Future<void> showWordZoteroDialog(
  BuildContext context, {
  required WordEditorController controller,
  ZoteroTransport? transport,
  ZoteroTransport? localTransport,
  ZoteroSession? session,
  Future<void> Function(String? apiKey)? persistApiKey,
  WordZoteroTab? initialTab,
  ZoteroCitingCommand? initialCommand,
  bool closeAfterCommand = false,
}) async {
  if (closeAfterCommand && initialCommand == null) {
    throw ArgumentError('A direct Zotero command is required.');
  }
  if (_hasZoteroComposition(controller)) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Finish the current text composition before using Zotero.',
        ),
      ),
    );
    return;
  }
  controller.commitPendingEdits();
  final document = controller.document;
  final destination = await showDialog<WmlZoteroField>(
    context: context,
    builder: (_) => _WordZoteroDialog(
      controller: controller,
      transport: transport,
      localTransport: localTransport,
      session: session ?? ZoteroSession(),
      persistApiKey: persistApiKey,
      initialTab: initialTab,
      initialCommand: initialCommand,
      closeAfterCommand: closeAfterCommand,
    ),
  );
  if (!context.mounted ||
      controller.isDisposed ||
      !identical(document, controller.document) ||
      ModalRoute.of(context)?.isCurrent == false) {
    return;
  }
  if (destination != null) {
    controller.revealZoteroField(destination);
  } else if (closeAfterCommand && !_hasZoteroComposition(controller)) {
    controller.requestEditingFocus();
  }
}

bool _hasZoteroComposition(WordEditorController controller) {
  final body = controller.input.composing;
  final note = controller.noteEditingTarget?.composing;
  return (body.isValid && !body.isCollapsed) ||
      (note != null && note.isValid && !note.isCollapsed);
}

Object _editTarget(WordEditorController controller) => (
  document: controller.document,
  revision: controller.contentRevision,
  composing: controller.input.composing,
  caret: controller.caret,
  paragraph: controller.caret.paragraphIndex,
  offset: controller.caret.logicalIndex,
  anchorParagraph: controller.caret.selectionAnchorParagraph,
  anchorOffset: controller.caret.selectionAnchor,
  note: controller.noteEditingTarget,
  headerFooter: controller.isEditingHeaderFooter,
  footer: controller.isEditingFooter,
  headerFooterVariant: controller.editingHeaderFooterVariant,
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
    this.localTransport,
    required this.session,
    this.persistApiKey,
    required this.initialTab,
    this.initialCommand,
    required this.closeAfterCommand,
  });
  final WordEditorController controller;
  final ZoteroTransport? transport;
  final ZoteroTransport? localTransport;
  final ZoteroSession session;
  final Future<void> Function(String? apiKey)? persistApiKey;
  final WordZoteroTab? initialTab;
  final ZoteroCitingCommand? initialCommand;
  final bool closeAfterCommand;
  @override
  State<_WordZoteroDialog> createState() => _WordZoteroDialogState();
}

class _WordZoteroDialogState extends State<_WordZoteroDialog> {
  late final WordZoteroTab _initialTab;
  List<WmlZoteroField>? _initialFields;
  late final TextEditingController _key;
  late final TextEditingController _style;
  late final TextEditingController _locale;
  final _search = TextEditingController();
  final _tag = TextEditingController();
  final _libraryId = TextEditingController();
  final _import = TextEditingController();
  final _importSearch = TextEditingController();
  final _importResultsScroll = ScrollController();
  String _submittedSearch = '';
  List<String> _tags = const [];
  String? _tagError;
  var _searchMode = ZoteroSearchMode.titleCreatorYear;
  var _itemSort = ZoteroItemSort.dateModified;
  var _sortDirection = ZoteroSortDirection.descending;
  String? _itemType;
  var _searchOptionsExpanded = false;
  late Object _target;
  ZoteroClient? _client;
  ZoteroKeyInfo? _identity;
  final _groups = <ZoteroGroup>[];
  final _collections = <ZoteroCollection>[];
  final _savedSearches = <ZoteroSavedSearch>[];
  ZoteroPage<ZoteroItem>? _page;
  String? _collectionKey;
  String? _savedSearchKey;
  var _savedSearchMode = false;
  var _catalogGeneration = 0;
  int? _moreGroups;
  int? _moreCollections;
  int? _moreSavedSearches;
  var _publicGroup = true;
  var _busy = false;
  var _reviewing = false;
  ZoteroCitingCancellation? _citingCancellation;
  String? _error;
  String? _notice;
  final _selected = <String, ZoteroCitationItem>{};
  final _imported = <ZoteroImportedReference>[];
  WordEditorController get _controller => widget.controller;
  ZoteroSession get _session => widget.session;
  bool get _useLocal => _session.useLocal;
  bool get _canEdit =>
      !_controller.isDisposed &&
      _controller.config.allowsMutation &&
      !_controller.document.trackRevisions;
  List<ZoteroCitationItem> get _documentItems => [
    for (final field in _controller.zoteroFields) ...?field.citation?.items,
  ];

  @override
  void initState() {
    super.initState();
    _target = _editTarget(_controller);
    // Share the opening scan with the initial Document page. This keeps a
    // 1000-citation document to one parse even when choosing the page from the
    // current caret. Later builds always obtain fresh, short-lived handles.
    final fields = _initialFields = _controller.zoteroFields;
    _initialTab = widget.initialCommand != null
        ? WordZoteroTab.document
        : widget.initialTab ??
              (_controller.findZoteroFieldAtCaret(fields: fields) == null
                  ? WordZoteroTab.library
                  : WordZoteroTab.document);
    _key = TextEditingController(text: _session.apiKey ?? '');
    _style = TextEditingController(text: _session.style);
    _locale = TextEditingController(text: _session.locale);
    if (_session.useLocal && widget.localTransport == null) {
      _session.useLocal = false;
      _session.library = null;
    }
    if (_useLocal) {
      // Reconnect explicitly so a previous session never supplies an unpinned
      // local database to document refresh or bibliography requests.
      _session.library = null;
    } else if (widget.transport != null) {
      _client = ZoteroClient(
        transport: widget.transport!,
        apiKey: _session.apiKey,
        backoffState: _session._onlineBackoff,
      );
    }
    final command = widget.initialCommand;
    if (command != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _citeWithDesktop(command);
      });
    }
  }

  @override
  void dispose() {
    _citingCancellation?.cancel();
    for (final controller in [
      _key,
      _style,
      _locale,
      _search,
      _tag,
      _libraryId,
      _import,
      _importSearch,
    ]) {
      controller.dispose();
    }
    _importResultsScroll.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool closeOnSuccess = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    var returnToDocument = false;
    try {
      await action();
      returnToDocument = closeOnSuccess;
    } catch (error) {
      if (closeOnSuccess &&
          error is ZoteroCitingException &&
          error.kind == ZoteroCitingErrorKind.cancelled &&
          !error.desktopMayNeedRestart) {
        returnToDocument = true;
      }
      if (mounted) {
        setState(() {
          _error = switch (error) {
            ZoteroCitingException e =>
              e.desktopMayNeedRestart
                  ? '${e.message} Finish or cancel the open Zotero dialog. If Zotero remains busy, restart Zotero before trying again.'
                  : e.message,
            ZoteroApiException e => e.message,
            FormatException e => e.message,
            UnsupportedError e =>
              e.message ?? 'This field cannot be changed safely.',
            StateError e => e.message,
            ArgumentError _ =>
              'Check the library ID, search text, selected sources, style, and locale.',
            _ =>
              'The operation could not finish. Existing document content was kept.',
          };
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted &&
        returnToDocument &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
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

  Future<void> _unlinkAll() => _run(() async {
    _checkTarget();
    final fields = _controller.zoteroFields;
    if (fields.isEmpty) return;
    final citations = fields
        .where((field) => field.kind == ZoteroFieldKind.citation)
        .length;
    final bibliographies = fields.length - citations;
    final confirmed = await _showReview<bool>(
      (dialogContext) => AlertDialog(
        title: const Text('Unlink all Zotero citations?'),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Text(
            'Convert $citations citation field(s) and $bibliographies bibliography field(s) throughout this document to ordinary text.\n\n'
            'The visible text, formatting and notes will stay in place. Zotero will no longer be able to update these references. Save a linked copy first if you will need citation updates later.\n\n'
            'You can undo the complete conversion while this document remains open. If any field cannot be converted safely, the whole document will be kept unchanged.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('zotero-confirm-unlink-all'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unlink all'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    var count = 0;
    _write(() => count = _controller.unlinkZoteroFields());
    setState(
      () => _notice =
          '$count Zotero field(s) converted to ordinary text. You can undo the complete conversion.',
    );
  });

  void _clearLibrary() {
    _catalogGeneration++;
    _identity = null;
    _session.library = null;
    _groups.clear();
    _collections.clear();
    _savedSearches.clear();
    _collectionKey = null;
    _savedSearchKey = null;
    _savedSearchMode = false;
    _moreGroups = null;
    _moreCollections = null;
    _moreSavedSearches = null;
    _page = null;
    _selected.clear();
  }

  void _switchSource(bool local) {
    if (_busy || (local && widget.localTransport == null)) return;
    setState(() {
      _session.useLocal = local;
      _clearLibrary();
      _client = !local && widget.transport != null
          ? ZoteroClient(
              transport: widget.transport!,
              apiKey: _session.apiKey,
              backoffState: _session._onlineBackoff,
            )
          : null;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _connectLocal() => _run(() async {
    final transport = widget.localTransport;
    if (transport == null) {
      throw StateError('Desktop Zotero is unavailable in this host.');
    }
    final client = ZoteroClient.local(transport: transport);
    await client.probeLocal();
    final groups = await client.groups(0);
    if (!mounted) return;
    _clearLibrary();
    _client = client;
    _session.library = ZoteroLibrary.localUser();
    _groups.addAll(groups.items);
    _moreGroups = groups.nextStart;
    await _loadLibrary();
    if (mounted) {
      setState(
        () => _notice =
            'Connected to Zotero desktop. Local library access is read-only; no API key is used.',
      );
    }
  });

  void _disconnectLocal() {
    setState(() {
      _clearLibrary();
      _client = null;
      _error = null;
      _notice = 'Desktop Zotero disconnected. Citations stay in the document.';
    });
  }

  Future<void> _connect() => _run(() async {
    final transport = widget.transport;
    if (transport == null) {
      throw StateError(
        'This host has no Zotero network transport. Use CSL JSON import.',
      );
    }
    final client = ZoteroClient(
      transport: transport,
      apiKey: _key.text,
      backoffState: _session._onlineBackoff,
    );
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
    if (mounted) {
      setState(
        () => _notice =
            'Connected as ${identity.username}. Library access is read-only.',
      );
    }
  });

  Future<void> _loadLibrary() async {
    final library = _session.library;
    final client = _client;
    if (library == null || client == null) return;
    final generation = ++_catalogGeneration;
    _collectionKey = null;
    _savedSearchKey = null;
    _savedSearchMode = false;
    _collections.clear();
    _savedSearches.clear();
    _moreCollections = null;
    _moreSavedSearches = null;
    _page = null;
    final collections = await client.collections(library, limit: 100);
    if (!_catalogIsCurrent(client, library, generation)) return;
    _mergeCollections(collections.items);
    _moreCollections = collections.nextStart;
    await _loadItems();
  }

  void _mergeCollections(Iterable<ZoteroCollection> incoming) {
    // Collections can move between pages while the library changes. Replace
    // their metadata by key, retaining the original order and selection.
    final byKey = <String, ZoteroCollection>{
      for (final collection in _collections) collection.key: collection,
      for (final collection in incoming) collection.key: collection,
    };
    _collections
      ..clear()
      ..addAll(byKey.values);
  }

  Future<void> _loadMoreCollections() async {
    final library = _session.library;
    final client = _client;
    final start = _moreCollections;
    if (library == null || client == null || start == null) return;
    final generation = ++_catalogGeneration;
    final page = await client.collections(library, start: start, limit: 100);
    if (!_catalogIsCurrent(client, library, generation) || _savedSearchMode) {
      return;
    }
    setState(() {
      _mergeCollections(page.items);
      _moreCollections = page.nextStart;
    });
  }

  Future<void> _loadItems({
    int start = 0,
    bool useSubmittedQuery = false,
  }) async {
    final library = _session.library;
    final client = _client;
    if (library == null || client == null) return;
    final generation = ++_catalogGeneration;
    _page = null;
    final searchKey = _savedSearchKey;
    if (_savedSearchMode && searchKey == null) return;
    // Editing the search box does not change the query behind an existing
    // page. Both forward and backward paging use the last submitted text.
    if (!useSubmittedQuery) _submittedSearch = _search.text;
    final page = _savedSearchMode
        ? await client.savedSearchItems(
            library,
            searchKey!,
            query: _submittedSearch,
            start: start,
            searchMode: _searchMode,
            sort: _itemSort,
            direction: _sortDirection,
            itemType: _itemType,
            tags: _tags,
          )
        : await client.items(
            library,
            collectionKey: _collectionKey,
            query: _submittedSearch,
            start: start,
            searchMode: _searchMode,
            sort: _itemSort,
            direction: _sortDirection,
            itemType: _itemType,
            tags: _tags,
          );
    if (_catalogIsCurrent(client, library, generation)) {
      setState(() => _page = page);
    }
  }

  Future<void> _addTag() => _applyTag(_tag.text, clearDraft: true);

  Future<void> _applyTag(
    String value, {
    required bool clearDraft,
    bool requireExact = false,
  }) async {
    if (_busy || (_savedSearchMode && _savedSearchKey == null)) return;
    try {
      final tag = normalizeZoteroTags([value]).single;
      if (requireExact && tag != value) {
        throw const FormatException(
          'Tags with surrounding spaces cannot be filtered exactly here.',
        );
      }
      if (_tags.contains(tag)) {
        setState(() {
          if (clearDraft) _tag.clear();
          _tagError = null;
        });
        return;
      }
      final tags = normalizeZoteroTags([..._tags, tag]);
      setState(() {
        _tags = tags;
        if (clearDraft) _tag.clear();
        _tagError = null;
      });
    } on FormatException catch (error) {
      setState(() => _tagError = error.message);
      return;
    }
    // Tag actions filter the current search. Draft text in either input is
    // never silently submitted by paging, removing a tag or clearing filters.
    await _run(() => _loadItems(useSubmittedQuery: true));
  }

  Future<void> _showItemDetails(ZoteroItem item) async {
    if (_busy) return;
    final client = _client;
    final library = _session.library;
    final generation = _catalogGeneration;
    if (client == null || library == null) return;
    final tag = await showDialog<String>(
      context: context,
      builder: (_) => ZoteroItemDetailsDialog(
        item: item,
        activeTags: _tags,
        childrenUnavailableReason: client.isLocal && item.localServerId == null
            ? 'Use Zotero 10 or later and reconnect to inspect notes and attachments.'
            : null,
        onBrowseChildren: client.isLocal && item.localServerId == null
            ? null
            : () async {
                if (!_catalogIsCurrent(client, library, generation)) return;
                await showDialog<void>(
                  context: context,
                  builder: (_) => ZoteroItemChildrenDialog(
                    client: client,
                    parent: item,
                    isCurrent: () =>
                        _catalogIsCurrent(client, library, generation),
                  ),
                );
              },
      ),
    );
    if (tag == null || !_catalogIsCurrent(client, library, generation)) return;
    await _applyTag(tag, clearDraft: false, requireExact: true);
  }

  Future<void> _browseTags() async {
    if (_busy || (_savedSearchMode && _savedSearchKey == null)) return;
    final client = _client;
    final library = _session.library;
    final generation = _catalogGeneration;
    if (client == null || library == null) return;
    final collectionKey = _savedSearchMode ? null : _collectionKey;
    final collectionNames = _collections
        .where((collection) => collection.key == collectionKey)
        .map((collection) => collection.name);
    final tags = await showDialog<List<String>>(
      context: context,
      builder: (_) => ZoteroTagBrowserDialog(
        client: client,
        library: library,
        collectionKey: collectionKey,
        activeTags: _tags,
        scopeLabel: collectionKey != null
            ? 'Collection tags: ${collectionNames.firstOrNull ?? collectionKey}'
            : _savedSearchMode
            ? 'Library tags (not limited to the saved search)'
            : 'Library tags',
      ),
    );
    if (tags == null || !_catalogIsCurrent(client, library, generation)) return;
    if (_tags.length == tags.length &&
        Iterable<int>.generate(
          tags.length,
        ).every((index) => _tags[index] == tags[index])) {
      return;
    }
    setState(() {
      _tags = normalizeZoteroTags(tags);
      _tagError = null;
    });
    await _run(() => _loadItems(useSubmittedQuery: true));
  }

  Future<void> _reviewSelection() async {
    if (_busy || _selected.isEmpty) return;
    final selection = Map<String, ZoteroCitationItem>.of(_selected);
    final keys = await showDialog<List<String>>(
      context: context,
      builder: (_) => ZoteroSelectedReferencesDialog(selection: selection),
    );
    if (!mounted || keys == null) return;
    // Do not overwrite a selection changed while another route was open.
    if (_selected.length != selection.length ||
        selection.entries.any(
          (entry) => !identical(_selected[entry.key], entry.value),
        )) {
      return;
    }
    setState(() {
      _selected
        ..clear()
        ..addEntries(keys.map((key) => MapEntry(key, selection[key]!)));
    });
  }

  Future<void> _showDocumentSources() => _run(() async {
    final target = _editTarget(_controller);
    final selection = Map<String, ZoteroCitationItem>.of(_selected);
    final fields = _controller.zoteroFields;
    final references = zoteroDocumentReferences([
      for (final field in fields) ...?field.citation?.items,
    ]);
    final occurrences = zoteroDocumentCitationOccurrences(
      _controller.document,
      fields,
    );
    WmlZoteroField? destination;
    final keys = await _showReview<List<String>>(
      (_) => ZoteroDocumentSourcesDialog(
        references: references,
        occurrences: occurrences,
        canReveal: (field) =>
            !_controller.isDisposed &&
            target == _editTarget(_controller) &&
            _controller.canRevealZoteroField(field),
        onNavigate: (field) => destination = field,
        selectedKeys: {
          for (final reference in references)
            if (_selected.containsKey(reference.selectionKey))
              reference.selectionKey,
        },
        otherSelectionCount: _selected.keys
            .where((key) => !key.startsWith('document:'))
            .length,
      ),
    );
    if (!mounted || (keys == null && destination == null)) return;
    if (_controller.isDisposed ||
        target != _editTarget(_controller) ||
        _selected.length != selection.length ||
        selection.entries.any(
          (entry) => !identical(_selected[entry.key], entry.value),
        )) {
      throw StateError(
        'The document or source selection changed. Open cited references again to continue.',
      );
    }
    final field = destination;
    if (field != null) {
      if (!_controller.canRevealZoteroField(field)) {
        throw StateError(
          'This citation can no longer be shown. Open cited references again.',
        );
      }
      // Navigation does not apply the source picker's draft selection.
      Navigator.of(context).pop(field);
      return;
    }
    if (keys == null) return;
    final sources = {
      for (final reference in references)
        reference.selectionKey: reference.item,
    };
    setState(() {
      // Retained selections keep their place relative to other tabs. Append
      // newly selected sources in the order chosen in the cited-source dialog.
      _selected.removeWhere(
        (key, _) => key.startsWith('document:') && !keys.contains(key),
      );
      for (final key in keys) {
        _selected.putIfAbsent(key, () => sources[key]!);
      }
    });
  });

  Future<void> _showStoredReferenceDetails(ZoteroCitationItem item) async {
    if (_busy) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ZoteroStoredReferenceDetailsDialog(item: item),
    );
  }

  Widget _reviewSelectionButton(String key) => TextButton.icon(
    key: ValueKey(key),
    onPressed: _busy || _selected.isEmpty ? null : _reviewSelection,
    icon: const Icon(Icons.checklist),
    label: const Text('Review selected'),
  );

  Future<void> _removeTag(String tag) async {
    if (_busy) return;
    setState(
      () => _tags = List.unmodifiable(_tags.where((item) => item != tag)),
    );
    await _run(() => _loadItems(useSubmittedQuery: true));
  }

  Future<void> _clearTags() async {
    if (_busy || _tags.isEmpty) return;
    setState(() => _tags = const []);
    await _run(() => _loadItems(useSubmittedQuery: true));
  }

  bool _catalogIsCurrent(
    ZoteroClient client,
    ZoteroLibrary library,
    int generation,
  ) =>
      mounted &&
      identical(client, _client) &&
      library == _session.library &&
      generation == _catalogGeneration;

  Future<void> _showSavedSearches(bool show) => _run(() async {
    _savedSearchMode = show;
    if (show) {
      await _loadSavedSearches();
    } else {
      await _loadItems();
    }
  });

  Future<void> _loadSavedSearches({int start = 0}) async {
    final library = _session.library;
    final client = _client;
    if (library == null || client == null || !client.isLocal) return;
    final generation = ++_catalogGeneration;
    if (start == 0) {
      _savedSearchKey = null;
      _savedSearches.clear();
      _moreSavedSearches = null;
      _page = null;
    }
    final page = await client.savedSearches(library, start: start, limit: 100);
    if (!_catalogIsCurrent(client, library, generation) || !_savedSearchMode) {
      return;
    }
    setState(() {
      // A search can move between pages while its library is being edited.
      // Keep one menu entry per key without losing the current selection.
      for (final search in page.items) {
        final index = _savedSearches.indexWhere(
          (item) => item.key == search.key,
        );
        if (index < 0) {
          _savedSearches.add(search);
        } else {
          _savedSearches[index] = search;
        }
      }
      _moreSavedSearches = page.nextStart;
    });
  }

  Future<void> _openPublic() => _run(() async {
    final id = int.tryParse(_libraryId.text.trim());
    if (id == null || id <= 0) {
      throw const FormatException('Enter a numeric Zotero user or group ID.');
    }
    _session.library = _publicGroup
        ? ZoteroLibrary.group(id)
        : ZoteroLibrary.user(id);
    _client = ZoteroClient(
      transport: widget.transport!,
      apiKey: _session.apiKey,
      backoffState: _session._onlineBackoff,
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
    _clearLibrary();
    _client = widget.transport == null
        ? null
        : ZoteroClient(
            transport: widget.transport!,
            backoffState: _session._onlineBackoff,
          );
    setState(
      () => _notice =
          'Disconnected. The saved key was removed; citations remain in the document.',
    );
  });

  void _remember(bool remember) {
    if (remember) {
      setState(() => _session.rememberKey = true);
      return;
    }
    _run(() async {
      if (widget.persistApiKey != null) await widget.persistApiKey!(null);
      if (mounted) {
        setState(() {
          _session.rememberKey = false;
          _notice =
              'The saved key was removed. This connection is session-only.';
        });
      }
    });
  }

  ZoteroSourceAddress? _addressOf(ZoteroCitationItem item) {
    final addresses = item.uris
        .map(ZoteroSourceAddress.parse)
        .whereType<ZoteroSourceAddress>()
        .toList();
    // Zotero can retain an old local URI alongside a newer account URI.
    // Online connections keep using a numeric identity when one is present.
    return (!_useLocal
            ? addresses.where((address) => !address.isLocal).firstOrNull
            : null) ??
        addresses.firstOrNull;
  }

  ZoteroClient _connectedClient(ZoteroSourceAddress address) {
    final client = _client;
    if (client == null) throw StateError('Connect a Zotero library first.');
    if (address.isLocal && !client.isLocal) {
      throw const FormatException(
        'This source belongs to an unsynced desktop library. Choose Zotero desktop and connect to the matching library.',
      );
    }
    return client;
  }

  Future<void> _selectItem(ZoteroItem item, bool selected) => _run(() async {
    if (!selected) {
      setState(() => _selected.remove(item.sourceId));
      return;
    }
    if (_selected.length >= 20) {
      throw const FormatException('Select at most 20 sources per citation.');
    }
    if (item.cslJson == null && item.citationUri == null) {
      throw const FormatException(
        'Zotero did not provide enough source data. Refresh the library and select this item again.',
      );
    }
    final full = item.cslJson == null
        ? await _client!.item(
            item.library,
            item.key,
            expectedCitationUri: item.citationUri,
            includeFormatted: false,
          )
        : item;
    if (!mounted) return;
    final data = full.cslJson;
    if (data == null) {
      throw const FormatException('Zotero returned no CSL data for this item.');
    }
    final uri = full.citationUri;
    final offlineId =
        'quds-offline-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    setState(() {
      _selected[item.sourceId] = uri == null
          ? ZoteroCitationItem.fromJson({
              'id': offlineId,
              'uris': <String>[],
              'itemData': {...data, 'id': offlineId},
            })
          : ZoteroCitationItem.fromCsl(itemData: data, uris: [uri.toString()]);
    });
    if (uri == null) {
      setState(
        () => _notice =
            'This source will be embedded without a Zotero link because the desktop library did not provide a persistent item URI.',
      );
    }
  });

  Future<void> _compose(
    List<ZoteroCitationItem> items, {
    WmlZoteroField? field,
  }) => _run(() async {
    _checkTarget();
    _saveFormat();
    // Resolve before building a new route so metadata limits report through
    // the workspace's recoverable error handling, not Flutter's build errors.
    final availableSources = [
      for (final reference in zoteroDocumentReferences([
        ..._documentItems,
        ..._selected.values,
        for (final reference in _imported) reference.item,
      ]))
        reference.item,
    ];
    final searchClient = _client;
    final searchLibrary = _session.library;
    final offlineSearchIds = <String, String>{};
    final result = await _showReview<ZoteroCitation>(
      (_) => ZoteroCitationComposer(
        items: items,
        availableSources: availableSources,
        existing: field?.citation,
        existingCache: field?.cachedText,
        style: _session.style,
        searchZoteroSources: searchClient == null || searchLibrary == null
            ? null
            : (query, start) async {
                // Search the connected library, not just the currently viewed
                // collection. Only usable citable CSL records enter a draft.
                final page = await searchClient.items(
                  searchLibrary,
                  query: query,
                  start: start,
                  limit: 25,
                );
                final sources = <ZoteroCitationItem>[];
                for (final item in page.items) {
                  if (!item.isCitable || item.cslJson == null) continue;
                  final uri = item.citationUri;
                  if (uri != null) {
                    sources.add(
                      ZoteroCitationItem.fromCsl(
                        itemData: item.cslJson!,
                        uris: [uri.toString()],
                      ),
                    );
                  } else {
                    // Unsynced local sources cannot be identified by their
                    // API route; retain a fresh standalone CSL snapshot.
                    final id = offlineSearchIds.putIfAbsent(item.key, () {
                      final nonce = Random.secure().nextInt(1 << 30);
                      final time = DateTime.now().microsecondsSinceEpoch;
                      return 'quds-offline-$time-$nonce';
                    });
                    sources.add(
                      ZoteroCitationItem.fromJson({
                        'id': id,
                        'uris': <String>[],
                        'itemData': {...item.cslJson!, 'id': id},
                      }),
                    );
                  }
                }
                return ZoteroPage<ZoteroCitationItem>(
                  items: sources,
                  start: page.start,
                  limit: page.limit,
                  totalResults: page.totalResults,
                  nextStart: page.nextStart,
                );
              },
        loadStyleSnapshot: _client == null
            ? null
            : (source) async {
                final address = _addressOf(source);
                if (address == null) {
                  throw const FormatException(
                    'This source has no linked Zotero identity for a style preview.',
                  );
                }
                final item = await _connectedClient(address).item(
                  address.library,
                  address.key,
                  expectedCitationUri: address.canonicalUri,
                  style: _session.style,
                  locale: _session.locale,
                );
                final text = zoteroHtmlToPlainText(item.citationHtml ?? '');
                if (text.isEmpty) {
                  throw const FormatException(
                    'No formatted citation was returned.',
                  );
                }
                return text;
              },
      ),
    );
    if (!mounted || result == null) return;
    _write(
      () => field == null
          ? _controller.insertZoteroCitation(result)
          : _controller.updateZoteroCitation(field, result),
    );
  });

  Future<T?> _showReview<T>(
    WidgetBuilder builder, {
    bool barrierDismissible = true,
  }) async {
    setState(() => _reviewing = true);
    try {
      return await showDialog<T>(
        context: context,
        builder: builder,
        barrierDismissible: barrierDismissible,
      );
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Future<void> _citeWithDesktop(
    ZoteroCitingCommand command, {
    WmlZoteroField? field,
    List<ZoteroCitationItem>? items,
  }) => _run(() async {
    _checkTarget();
    final transport = widget.localTransport;
    if (transport == null) {
      throw StateError(
        'Zotero desktop citation tools are unavailable in this host.',
      );
    }
    final id =
        'quds-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    final seed = items == null
        ? null
        : ZoteroCitation(
            citationId: '$id-citation',
            items: List<ZoteroCitationItem>.of(items),
            plainCitation: zoteroBasicCitation(items),
          );
    final chooseStyle =
        seed != null &&
        WordZoteroDocumentData.stylePreferences(
              WordZoteroDocumentData.read(_controller.document),
            ) ==
            null;
    final current = items == null ? _controller.zoteroFieldAtCaret : null;
    final selectedField =
        field ??
        switch (command) {
          ZoteroCitingCommand.addEditCitation
              when current?.kind == ZoteroFieldKind.citation =>
            current,
          ZoteroCitingCommand.addEditBibliography
              when current?.kind == ZoteroFieldKind.bibliography =>
            current,
          _ => null,
        };
    final transaction = _controller.beginZoteroTransaction(
      documentId: id,
      selectedField: selectedField,
      seedCitation: chooseStyle ? null : seed,
      command: command,
    );
    final cancellation = ZoteroCitingCancellation();
    setState(() => _citingCancellation = cancellation);
    try {
      Future<void> execute(ZoteroCitingCommand operation) =>
          ZoteroCitingClient(transport: transport).execute(
            command: operation,
            documentId: id,
            cancellation: cancellation,
            guard: () {
              _checkTarget();
              transaction.assertCurrent();
            },
            handler: (name, arguments) async {
              if (name == 'Document.displayAlert') {
                if (arguments.length != 4 ||
                    arguments[0] != id ||
                    arguments[1] is! String ||
                    (arguments[1] as String).length > 20000 ||
                    arguments[3] is! int) {
                  throw const FormatException(
                    'Zotero returned an invalid dialog.',
                  );
                }
                final buttons = arguments[3] as int;
                final choices = switch (buttons) {
                  0 => <(String, int)>[('OK', 1)],
                  1 => <(String, int)>[('Cancel', 0), ('OK', 1)],
                  2 => <(String, int)>[('No', 0), ('Yes', 1)],
                  3 => <(String, int)>[('Cancel', 0), ('No', 1), ('Yes', 2)],
                  _ => throw const FormatException(
                    'Zotero requested an unsupported dialog.',
                  ),
                };
                final answer = await _showReview<int>(
                  (dialogContext) => PopScope(
                    canPop: false,
                    child: AlertDialog(
                      title: const Text('Zotero'),
                      content: SizedBox(
                        width: 560,
                        child: SingleChildScrollView(
                          child: SelectableText(arguments[1] as String),
                        ),
                      ),
                      actions: [
                        for (final (label, value) in choices)
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, value),
                            child: Text(label),
                          ),
                      ],
                    ),
                  ),
                  barrierDismissible: false,
                );
                transaction.assertCurrent();
                return answer ?? (buttons == 0 ? 1 : 0);
              }
              return transaction.session.handle(name, arguments);
            },
          );
      if (chooseStyle) {
        await execute(ZoteroCitingCommand.setDocPrefs);
        _checkTarget();
        transaction.assertCurrent();
        if (WordZoteroDocumentData.stylePreferences(
              transaction.session.documentData,
            ) ==
            null) {
          setState(
            () => _notice =
                'No document style was selected. The document and selected sources were kept.',
          );
          return;
        }
        transaction.session.continueWithCitation(seed);
      }
      await execute(command);
      _checkTarget();
      transaction.assertCurrent();
      final result = transaction.session;
      if (command.insertsNoteText && !result.hasInsertedNoteText) {
        final content = command == ZoteroCitingCommand.addAnnotation
            ? 'annotation'
            : 'note';
        setState(
          () => _notice =
              'No Zotero $content was inserted. The document was kept.',
        );
        return;
      }
      result.prepareReview();
      if (seed != null && !result.hasAcceptedSeedCitation) {
        setState(
          () => _notice =
              'No citation was inserted. The document and selected sources were kept.',
        );
        return;
      }
      if (!result.hasChanges) {
        setState(
          () => _notice = 'Zotero finished without changing the document.',
        );
        return;
      }
      if (result.formattingWarnings.isNotEmpty) {
        final apply = await _showReview<bool>(
          (dialogContext) => AlertDialog(
            title: const Text('Review Zotero formatting'),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${result.changedFieldCount} citation or bibliography field(s) will be updated.',
                    ),
                    const SizedBox(height: 12),
                    for (final warning in result.formattingWarnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(warning),
                      ),
                    const Text(
                      'Citation identity, source data and Zotero style preferences will be kept. Review the resulting text before applying.',
                    ),
                    const Divider(),
                    for (final text in result.previewTexts.take(20))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SelectableText(
                          text.length > 1000
                              ? '${text.substring(0, 1000)}…'
                              : text,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Apply Zotero result'),
              ),
            ],
          ),
        );
        if (apply != true) {
          if (mounted) {
            setState(
              () => _notice = 'Zotero result discarded. The document was kept.',
            );
          }
          return;
        }
      }
      _write(transaction.apply);
      if (items != null) _selected.clear();
      setState(
        () => _notice =
            'Zotero updated the document using its selected style. You can undo the complete operation.',
      );
    } finally {
      if (mounted) setState(() => _citingCancellation = null);
    }
  }, closeOnSuccess: widget.closeAfterCommand);

  Widget _desktopTools() => Card(
    key: const ValueKey('zotero-desktop-tools'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Zotero desktop citation tools',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Use Zotero’s source picker and installed citation styles. Refresh processes the whole document together, including numbering, disambiguation and style-dependent ibid. / Ebd. with page locators.',
          ),
          const SizedBox(height: 8),
          _documentStyleSummary(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton(
                onPressed: _busy || !_canEdit
                    ? null
                    : () =>
                          _citeWithDesktop(ZoteroCitingCommand.addEditCitation),
                child: const Text('Citation in Zotero…'),
              ),
              OutlinedButton(
                key: const ValueKey('zotero-add-note'),
                onPressed: _busy || !_canEdit
                    ? null
                    : () => _citeWithDesktop(ZoteroCitingCommand.addNote),
                child: const Text('Add note from Zotero…'),
              ),
              Tooltip(
                message:
                    'Insert text, image and ink annotations with active citations. Requires Zotero 9 or later.',
                child: OutlinedButton(
                  key: const ValueKey('zotero-add-annotation'),
                  onPressed: _busy || !_canEdit
                      ? null
                      : () =>
                            _citeWithDesktop(ZoteroCitingCommand.addAnnotation),
                  child: const Text('Add annotation from Zotero…'),
                ),
              ),
              OutlinedButton(
                onPressed: _busy || !_canEdit
                    ? null
                    : () => _citeWithDesktop(ZoteroCitingCommand.setDocPrefs),
                child: const Text('Document style…'),
              ),
              OutlinedButton(
                onPressed: _busy || !_canEdit
                    ? null
                    : () => _citeWithDesktop(ZoteroCitingCommand.refresh),
                child: const Text('Refresh all with Zotero'),
              ),
              OutlinedButton(
                onPressed: _busy || !_canEdit
                    ? null
                    : () => _citeWithDesktop(
                        ZoteroCitingCommand.addEditBibliography,
                      ),
                child: const Text('Bibliography in Zotero…'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Open Zotero on this computer. In Document style, choose a style that uses ibid. and German for Ebd.; the selected style controls punctuation and pages. Footnotes and endnotes are supported. Moving an existing note citation between formats requires a note containing only that citation.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _documentStyleSummary() {
    ({String id, String? locale, int noteType})? preferences;
    try {
      preferences = WordZoteroDocumentData.stylePreferences(
        WordZoteroDocumentData.read(_controller.document),
      );
    } on FormatException {
      return const Text(
        'The saved Zotero document style could not be read. Open Document style… to review it.',
        key: ValueKey('zotero-document-style-summary'),
      );
    }
    if (preferences == null) {
      return const Text(
        'No document style selected. Insert with Zotero… opens the style chooser before inserting your first catalog citation.',
        key: ValueKey('zotero-document-style-summary'),
      );
    }
    final id = preferences.id;
    final uri = Uri.tryParse(id);
    final style = uri != null && uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : id;
    final placement = switch (preferences.noteType) {
      1 => 'Footnotes',
      2 => 'Endnotes',
      _ => 'In text',
    };
    return Text(
      'Document style: $style\n'
      'Language: ${preferences.locale ?? 'Style default'} · $placement',
      key: const ValueKey('zotero-document-style-summary'),
    );
  }

  void _saveFormat() {
    _session.style = _style.text.trim();
    _session.locale = _locale.text.trim();
  }

  Future<void> _bibliography({
    required bool online,
    WmlZoteroField? field,
  }) => _run(() async {
    _checkTarget();
    if (field != null &&
        const ['uncited', 'omitted', 'custom'].any((name) {
          final value = field.metadata?[name];
          return value != null && (value is! List || value.isNotEmpty);
        })) {
      throw UnsupportedError(
        'This bibliography has Zotero additions, exclusions, or custom entries. Update it with Zotero to retain those choices.',
      );
    }
    _saveFormat();
    final items = _documentItems;
    if (items.isEmpty) {
      throw const FormatException(
        'Insert a citation before creating its bibliography.',
      );
    }
    String text;
    ZoteroFormattedText? formattedText;
    if (online) {
      final resolver = ZoteroSourceResolver(
        items,
        local: _client?.isLocal ?? _useLocal,
      );
      final addresses = <String, ZoteroSourceAddress>{};
      for (final item in items) {
        final address = resolver.addressOf(item);
        if (address == null) {
          throw const FormatException(
            'Some sources cannot be resolved through this library connection. Use the basic bibliography or copy embedded CSL JSON.',
          );
        }
        addresses[address.canonicalUri.toString()] = address;
      }
      final first = addresses.values.first;
      if (addresses.values.any((item) => item.scope != first.scope) ||
          addresses.length > 50) {
        throw const FormatException(
          'A Zotero-formatted bibliography needs at most 50 sources in one library. Use basic format or export CSL JSON.',
        );
      }
      formattedText = ZoteroFormattedText.fromHtml(
        await _connectedClient(first).bibliography(
          first.library,
          itemKeys: addresses.values.map((item) => item.key).toList(),
          expectedItemUris: {
            for (final address in addresses.values)
              address.key: address.canonicalUri,
          },
          style: _session.style,
          locale: _session.locale,
        ),
      );
      text = formattedText.plainText;
    } else {
      text = zoteroBasicBibliography(items);
    }
    if (!mounted) return;
    if (text.trim().isEmpty) {
      throw const FormatException('No bibliography text was returned.');
    }
    final reviewed = await _reviewBibliography(
      online ? 'Review Zotero bibliography' : 'Basic bibliography',
      text,
      formattedText: formattedText,
    );
    if (!mounted || reviewed == null) return;
    _write(
      () => field == null
          ? _controller.insertZoteroBibliography(
              text: reviewed.text,
              formattedText: reviewed.formattedText,
            )
          : _controller.updateZoteroBibliography(
              field,
              text: reviewed.text,
              formattedText: reviewed.formattedText,
            ),
    );
  });

  Future<void> _refresh() => _run(() async {
    _checkTarget();
    if (_client == null) throw StateError('Connect a Zotero library first.');
    final allFields = _controller.zoteroFields;
    final fields = allFields
        .where(
          (field) =>
              field.citation != null &&
              field.citation!.properties['qudsFormat'] == 'basic-author-year',
        )
        .toList();
    if (fields.isEmpty) {
      throw const FormatException(
        'No basic author–year citations to refresh. Imported or custom-formatted citations are kept as they are.',
      );
    }
    if (fields.any((field) => !field.canEdit)) {
      throw const FormatException(
        'One or more citations cannot be safely edited.',
      );
    }
    // Validate the whole operation before making a request. In particular, an
    // online connection must not partially fetch a document with local sources.
    // Custom/native citations may declare aliases for a basic source without
    // being eligible for replacement themselves.
    final resolver = ZoteroSourceResolver(
      allFields.expand(
        (field) => field.citation?.items ?? const <ZoteroCitationItem>[],
      ),
      local: _client!.isLocal,
    );
    final addresses = <String, ZoteroSourceAddress>{};
    for (final field in fields) {
      for (final item in field.citation!.items) {
        final address = resolver.addressOf(item);
        if (address == null) continue;
        _connectedClient(address);
        addresses[address.canonicalUri.toString()] = address;
      }
    }
    if (addresses.length > 1000) {
      throw const FormatException(
        'Refresh at most 1,000 distinct linked sources at once.',
      );
    }
    if (addresses.values
            .where((address) => address.isLocal)
            .map((address) => address.scope)
            .toSet()
            .length >
        1) {
      throw const FormatException(
        'These sources belong to different Zotero desktop libraries. Their embedded data was kept.',
      );
    }
    final fetched = <String, Map<String, dynamic>>{};
    final libraries = <String, List<ZoteroSourceAddress>>{};
    for (final address in addresses.values) {
      (libraries[address.scope] ??= []).add(address);
    }
    // Bound the whole operation to 1,000 distinct sources, but apply Zotero's
    // 50-key request limit separately within each durable library scope.
    // Item keys alone are not identities: different libraries can reuse them.
    // Sequential requests respect backoff, and every result stays staged until
    // all batches and the edit target verify. Never combine formatted
    // bibliography batches; this path fetches source metadata only.
    for (final sources in libraries.values) {
      final first = sources.first;
      for (var start = 0; start < sources.length; start += 50) {
        _checkTarget();
        final batch = sources.sublist(start, min(start + 50, sources.length));
        final items = await _connectedClient(first).metadataItems(
          first.library,
          expectedItemUris: {
            for (final address in batch) address.key: address.canonicalUri,
          },
        );
        if (!mounted) return;
        _checkTarget();
        for (final remote in items) {
          if (remote.cslJson == null) {
            throw const FormatException(
              'A source has no CSL data. Existing citations were kept.',
            );
          }
          fetched[remote.canonicalUri.toString()] = remote.cslJson!;
        }
      }
    }
    final updates = <String, ZoteroCitation>{};
    for (final field in fields) {
      final citation = field.citation!;
      final items = <ZoteroCitationItem>[];
      for (final item in citation.items) {
        final address = resolver.addressOf(item);
        final data = address == null
            ? null
            : fetched[address.canonicalUri.toString()];
        items.add(
          data == null
              ? item
              : ZoteroCitationItem.fromJson({
                  ...item.toJson(),
                  'itemData': {...data, 'id': item.id},
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
      final addresses = _selected.values.map(_addressOf).toList();
      if (addresses.isEmpty ||
          addresses.any((address) => address == null) ||
          addresses.any(
            (address) => address!.scope != addresses.first!.scope,
          )) {
        throw const FormatException(
          'Select sources from one Zotero library to export.',
        );
      }
      final sources = addresses.whereType<ZoteroSourceAddress>().toList();
      final first = sources.first;
      text = await _connectedClient(first).exportItems(
        first.library,
        sources.map((address) => address.key).toList(),
        expectedItemUris: {
          for (final address in sources) address.key: address.canonicalUri,
        },
        format: format,
      );
    }
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      setState(() => _notice = 'Reference data copied to the clipboard.');
    }
  });

  Future<void> _copyStoredSelection() => _run(() async {
    final text = zoteroSelectionCslJson(_selected.values);
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException {
      throw const FormatException(
        'Could not copy stored reference metadata to the clipboard.',
      );
    }
    if (mounted) {
      setState(
        () => _notice = 'Stored reference metadata copied to the clipboard.',
      );
    }
  });

  Future<({String text, ZoteroFormattedText? formattedText})?>
  _reviewBibliography(
    String title,
    String initial, {
    ZoteroFormattedText? formattedText,
  }) => _showReview<({String text, ZoteroFormattedText? formattedText})>(
    (_) => _BibliographyReview(
      title: title,
      initial: initial,
      formattedText: formattedText,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.closeAfterCommand) return _commandDialog();
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: _citingCancellation == null,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 980,
          height: max(160, min(760, size.height - 32)),
          child: DefaultTabController(
            length: 3,
            initialIndex: _initialTab.index,
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _citingCancellation != null
                            ? null
                            : () => Navigator.pop(context),
                        tooltip: 'Close Zotero',
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                if (_citingCancellation != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Finish or cancel the citation/style dialog in Zotero to continue. Changes are staged until the operation finishes.',
                          ),
                        ),
                        TextButton(
                          onPressed: _citingCancellation!.isCancelled
                              ? null
                              : () {
                                  setState(() => _citingCancellation!.cancel());
                                },
                          child: Text(
                            _citingCancellation!.isCancelled
                                ? 'Cancelling…'
                                : 'Cancel operation',
                          ),
                        ),
                      ],
                    ),
                  ),
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Library'),
                    Tab(text: 'Document'),
                    Tab(text: 'Import CSL JSON'),
                  ],
                ),
                if (_busy && !_reviewing)
                  const LinearProgressIndicator(minHeight: 2),
                if (!_canEdit || _error != null || _notice != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: min(160, size.height * 0.25),
                    ),
                    child: SingleChildScrollView(
                      key: const ValueKey('zotero-workspace-messages'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_canEdit)
                            _banner(
                              _controller.document.trackRevisions
                                  ? 'Turn off Track changes to insert or edit citations. Existing fields remain preserved.'
                                  : 'This document is read-only. You can browse and export reference data.',
                            ),
                          if (_error != null) _banner(_error!, error: true),
                          if (_notice != null) _banner(_notice!),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _scrollableTab(
                        _libraryTab(),
                        minHeight: _catalogMinHeight(size),
                      ),
                      _documentTab(),
                      _importTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _commandDialog() {
    final command = widget.initialCommand!;
    final title = switch (command) {
      ZoteroCitingCommand.addEditCitation => 'Zotero citation',
      ZoteroCitingCommand.addEditBibliography => 'Zotero bibliography',
      ZoteroCitingCommand.addNote => 'Add note from Zotero',
      ZoteroCitingCommand.addAnnotation => 'Add annotation from Zotero',
      ZoteroCitingCommand.refresh => 'Refresh Zotero citations',
      ZoteroCitingCommand.setDocPrefs => 'Zotero document style',
      ZoteroCitingCommand.removeCodes => 'Unlink Zotero citations',
    };
    final cancellation = _citingCancellation;
    return PopScope(
      canPop: !_busy && !_reviewing,
      child: AlertDialog(
        key: const ValueKey('zotero-direct-command'),
        title: Text(title),
        scrollable: true,
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy && !_reviewing) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
              ],
              Text(
                _error ??
                    _notice ??
                    'Finish or cancel the open dialog in Zotero. You will return to your document when Zotero finishes.',
                key: const ValueKey('zotero-command-status'),
              ),
              if (command == ZoteroCitingCommand.addAnnotation) ...[
                const SizedBox(height: 12),
                const Text(
                  'Requires Zotero 9 or later. Insert text, image or ink annotations with active citations.',
                  key: ValueKey('zotero-annotation-requirements'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (cancellation != null)
            TextButton(
              onPressed: cancellation.isCancelled
                  ? null
                  : () => setState(cancellation.cancel),
              child: Text(
                cancellation.isCancelled ? 'Cancelling…' : 'Cancel operation',
              ),
            )
          else
            TextButton(
              onPressed: _busy || _reviewing
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Return to document'),
            ),
        ],
      ),
    );
  }

  Widget _scrollableTab(Widget child, {required double minHeight}) =>
      LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: SizedBox(
            height: max(minHeight, constraints.maxHeight),
            child: child,
          ),
        ),
      );

  double _catalogMinHeight(Size size) {
    final narrow = size.width < 600;
    final textScale = max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14);
    // Selection review adds another wrapped action row on narrow screens.
    // Keep space for that row as well as the existing results viewport.
    final base = narrow
        ? (widget.localTransport == null ? 876.0 : 1016.0)
        : (widget.localTransport == null ? 660.0 : 800.0);
    if (_session.library == null || !_searchOptionsExpanded) {
      return base * textScale;
    }
    // Expanded options wrap at narrow widths. Preserve a usable results list
    // while keeping the default catalog and its paging controls compact.
    return (base +
            (size.width < 380 ? 520 : (narrow ? 340 : 180)) +
            188 +
            (_tags.isEmpty ? 0 : 220)) *
        textScale;
  }

  Widget _banner(String text, {bool error = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    color: error
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Text(text),
  );

  Widget _catalogSearchOptions() {
    final enabled = !_busy && (!_savedSearchMode || _savedSearchKey != null);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<ZoteroSearchMode>(
                  key: const ValueKey('zotero-search-mode'),
                  initialValue: _searchMode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Search in',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ZoteroSearchMode.titleCreatorYear,
                      child: Text('Titles, creators and years'),
                    ),
                    DropdownMenuItem(
                      value: ZoteroSearchMode.everything,
                      child: Text('Include full text'),
                    ),
                  ],
                  onChanged: !enabled
                      ? null
                      : (value) => _run(() async {
                          if (value == null) return;
                          _searchMode = value;
                          await _loadItems();
                        }),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('zotero-item-type'),
                  initialValue: _itemType ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Reference type',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All types')),
                    DropdownMenuItem(value: 'book', child: Text('Book')),
                    DropdownMenuItem(
                      value: 'bookSection',
                      child: Text('Book section'),
                    ),
                    DropdownMenuItem(
                      value: 'journalArticle',
                      child: Text('Journal article'),
                    ),
                    DropdownMenuItem(
                      value: 'conferencePaper',
                      child: Text('Conference paper'),
                    ),
                    DropdownMenuItem(value: 'thesis', child: Text('Thesis')),
                    DropdownMenuItem(value: 'report', child: Text('Report')),
                    DropdownMenuItem(value: 'webpage', child: Text('Web page')),
                  ],
                  onChanged: !enabled
                      ? null
                      : (value) => _run(() async {
                          _itemType = value == '' ? null : value;
                          await _loadItems();
                        }),
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<ZoteroItemSort>(
                  key: const ValueKey('zotero-item-sort'),
                  initialValue: _itemSort,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sort by',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ZoteroItemSort.dateModified,
                      child: Text('Date modified'),
                    ),
                    DropdownMenuItem(
                      value: ZoteroItemSort.dateAdded,
                      child: Text('Date added'),
                    ),
                    DropdownMenuItem(
                      value: ZoteroItemSort.title,
                      child: Text('Title'),
                    ),
                    DropdownMenuItem(
                      value: ZoteroItemSort.creator,
                      child: Text('Creator'),
                    ),
                    DropdownMenuItem(
                      value: ZoteroItemSort.date,
                      child: Text('Publication date'),
                    ),
                    DropdownMenuItem(
                      value: ZoteroItemSort.itemType,
                      child: Text('Reference type'),
                    ),
                  ],
                  onChanged: !enabled
                      ? null
                      : (value) => _run(() async {
                          if (value == null) return;
                          _itemSort = value;
                          await _loadItems();
                        }),
                ),
              ),
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<ZoteroSortDirection>(
                  key: const ValueKey('zotero-sort-direction'),
                  initialValue: _sortDirection,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Order',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ZoteroSortDirection.ascending,
                      child: Text('Ascending'),
                    ),
                    DropdownMenuItem(
                      value: ZoteroSortDirection.descending,
                      child: Text('Descending'),
                    ),
                  ],
                  onChanged: !enabled
                      ? null
                      : (value) => _run(() async {
                          if (value == null) return;
                          _sortDirection = value;
                          await _loadItems();
                        }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('zotero-tag-input'),
                  controller: _tag,
                  enabled: enabled,
                  decoration: InputDecoration(
                    labelText: 'Filter by tag',
                    hintText: 'Enter an exact tag name',
                    isDense: true,
                    errorText: _tagError,
                    errorMaxLines: 4,
                  ),
                  onChanged: (_) {
                    if (_tagError != null) setState(() => _tagError = null);
                  },
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              IconButton(
                key: const ValueKey('zotero-add-tag'),
                tooltip: 'Add tag',
                onPressed: enabled ? _addTag : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('zotero-browse-tags'),
              onPressed: enabled && _client != null && _session.library != null
                  ? _browseTags
                  : null,
              icon: const Icon(Icons.label_outline),
              label: const Text('Browse tags…'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              'Match every added tag. Press Enter or + to add one. Capitalization is kept as entered.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          if (_tags.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final tag in _tags)
                        InputChip(
                          key: ValueKey('zotero-tag-$tag'),
                          label: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: min(
                                240,
                                max(32, constraints.maxWidth - 80),
                              ),
                            ),
                            child: Text(
                              tag,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          tooltip: tag,
                          deleteButtonTooltipMessage: 'Remove tag $tag',
                          onDeleted: enabled ? () => _removeTag(tag) : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('zotero-clear-tags'),
                onPressed: enabled ? _clearTags : null,
                child: const Text('Clear tags'),
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Options apply to the complete result set. Full-text matches depend on what Zotero has indexed.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _savedSearchNavigation() => Row(
    children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          key: ValueKey(
            'saved-searches-${_session.library}-$_savedSearchKey-${_savedSearches.length}',
          ),
          initialValue: _savedSearchKey,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Saved search',
            isDense: true,
          ),
          hint: Text(
            _savedSearches.isEmpty
                ? 'No saved searches in this library'
                : 'Choose a saved search',
            overflow: TextOverflow.ellipsis,
          ),
          items: _savedSearches
              .map(
                (search) => DropdownMenuItem(
                  value: search.key,
                  child: Text(search.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: _busy
              ? null
              : (key) => _run(() async {
                  _savedSearchKey = key;
                  await _loadItems();
                }),
        ),
      ),
      if (_moreSavedSearches != null)
        TextButton(
          onPressed: _busy
              ? null
              : () =>
                    _run(() => _loadSavedSearches(start: _moreSavedSearches!)),
          child: const Text('More searches'),
        ),
      IconButton(
        tooltip: 'Refresh saved searches',
        onPressed: _busy ? null : () => _run(_loadSavedSearches),
        icon: const Icon(Icons.refresh),
      ),
    ],
  );

  Widget _libraryTab() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        if (widget.localTransport != null) ...[
          DropdownButtonFormField<bool>(
            key: const ValueKey('zotero-library-source'),
            initialValue: _useLocal,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Reference library source',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(
                value: false,
                child: Text('Online Zotero library'),
              ),
              DropdownMenuItem(
                value: true,
                child: Text('Zotero desktop (this computer)'),
              ),
            ],
            onChanged: _busy
                ? null
                : (local) {
                    if (local != null) _switchSource(local);
                  },
          ),
          const SizedBox(height: 12),
        ],
        if (_useLocal) ...[
          const Text(
            'Open Zotero on this computer. In Settings → Advanced, enable “Allow other applications on this computer to communicate with Zotero”. No API key is needed.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('zotero-connect-desktop'),
                onPressed: _busy ? null : _connectLocal,
                child: const Text('Connect desktop'),
              ),
              if (_client != null)
                TextButton(
                  onPressed: _busy ? null : _disconnectLocal,
                  child: const Text('Disconnect desktop'),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ] else ...[
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
                          : (value) => _remember(value ?? false),
                    ),
                    const Text('Remember key when connecting'),
                  ],
                ),
              if (_session.apiKey != null)
                TextButton(
                  onPressed: _busy ? null : _disconnect,
                  child: const Text('Disconnect & forget'),
                ),
            ],
          ),
        ],
        if (!_useLocal && widget.transport == null)
          const Text(
            'Online access is unavailable in this host. Import CSL JSON to work offline.',
          ),
        if ((_useLocal && _client != null) ||
            _identity != null ||
            _groups.isNotEmpty)
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
                          if (library != null) {
                            _run(() async {
                              _session.library = library;
                              await _loadLibrary();
                            });
                          }
                        },
                ),
              ),
              if (_moreGroups != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final page = await _client!.groups(
                            _useLocal ? 0 : _identity!.userId,
                            start: _moreGroups!,
                          );
                          if (mounted) {
                            setState(() {
                              _groups.addAll(page.items);
                              _moreGroups = page.nextStart;
                            });
                          }
                        }),
                  child: const Text('More groups'),
                ),
            ],
          ),
        if (!_useLocal)
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
          if (_useLocal) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Collections'),
                    selected: !_savedSearchMode,
                    onSelected: _busy ? null : (_) => _showSavedSearches(false),
                  ),
                  ChoiceChip(
                    label: const Text('Saved searches'),
                    selected: _savedSearchMode,
                    onSelected: _busy ? null : (_) => _showSavedSearches(true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (_savedSearchMode)
            _savedSearchNavigation()
          else
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
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All items'),
                      ),
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
                    onPressed: _busy ? null : () => _run(_loadMoreCollections),
                    child: const Text('More collections'),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  enabled:
                      !_busy && (!_savedSearchMode || _savedSearchKey != null),
                  decoration: InputDecoration(
                    labelText: _savedSearchMode
                        ? 'Search within saved search'
                        : _searchMode == ZoteroSearchMode.everything
                        ? 'Search references and full text'
                        : 'Search title, creator, or year',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed:
                          _busy || (_savedSearchMode && _savedSearchKey == null)
                          ? null
                          : () => _run(_loadItems),
                      tooltip: 'Search',
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (!_busy) _run(_loadItems);
                  },
                ),
              ),
              IconButton(
                key: const ValueKey('zotero-search-options'),
                tooltip: 'Search options',
                isSelected: _searchOptionsExpanded,
                onPressed: () => setState(
                  () => _searchOptionsExpanded = !_searchOptionsExpanded,
                ),
                icon: Badge(
                  isLabelVisible: _tags.isNotEmpty,
                  label: Text('${_tags.length}'),
                  child: const Icon(Icons.tune),
                ),
              ),
            ],
          ),
          if (_searchOptionsExpanded) _catalogSearchOptions(),
        ],
        Expanded(
          child: _page == null
              ? Center(
                  child: Text(
                    _session.library == null
                        ? 'Connect a Zotero library to browse references.'
                        : _savedSearchMode && _savedSearchKey == null
                        ? 'Choose a saved search to browse its references.'
                        : _busy
                        ? 'Loading references…'
                        : 'No references loaded. Choose a view or search again.',
                  ),
                )
              : _page!.items.where((item) => item.isCitable).isEmpty
              ? const Center(child: Text('No citable references on this page.'))
              : ListView.builder(
                  itemCount: _page!.items.length,
                  itemBuilder: (context, index) {
                    final item = _page!.items[index];
                    if (!item.isCitable) return const SizedBox.shrink();
                    return Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
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
                                if (item.citationUri == null)
                                  'Embedded source only',
                              ].where((text) => text.isNotEmpty).join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onChanged: _busy
                                ? null
                                : (selected) =>
                                      _selectItem(item, selected ?? false),
                          ),
                        ),
                        IconButton(
                          key: ValueKey('zotero-details-${item.sourceId}'),
                          tooltip: 'Reference details',
                          onPressed: _busy
                              ? null
                              : () => _showItemDetails(item),
                          icon: const Icon(Icons.info_outline),
                        ),
                      ],
                    );
                  },
                ),
        ),
        if (_page != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _page!.items.isEmpty
                      ? '0 references'
                      : '${_page!.start + 1}–${_page!.start + _page!.items.length}${_page!.totalResults == null ? '' : ' of ${_page!.totalResults}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
                              useSubmittedQuery: true,
                            ),
                          ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: _busy || !_page!.hasMore
                        ? null
                        : () => _run(
                            () => _loadItems(
                              start: _page!.nextStart!,
                              useSubmittedQuery: true,
                            ),
                          ),
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
            _reviewSelectionButton('zotero-review-library-selection'),
            TextButton(
              onPressed: _busy || _selected.isEmpty
                  ? null
                  : () => setState(_selected.clear),
              child: const Text('Clear selection'),
            ),
            if (widget.localTransport != null)
              FilledButton(
                onPressed:
                    _busy ||
                        !_canEdit ||
                        _selected.isEmpty ||
                        _selected.values.any((item) => item.uris.isEmpty)
                    ? null
                    : () => _citeWithDesktop(
                        ZoteroCitingCommand.addEditCitation,
                        items: _selected.values.toList(),
                      ),
                child: const Tooltip(
                  message:
                      'Insert selected sources using the document style. Zotero asks for a style when none has been selected.',
                  child: Text('Insert with Zotero…'),
                ),
              ),
            if (widget.localTransport != null)
              OutlinedButton.icon(
                onPressed: _busy || !_canEdit || _selected.isEmpty
                    ? null
                    : () => _compose(_selected.values.toList()),
                icon: const Icon(Icons.format_quote),
                label: const Text('Insert basic citation'),
              )
            else
              FilledButton.icon(
                onPressed: _busy || !_canEdit || _selected.isEmpty
                    ? null
                    : () => _compose(_selected.values.toList()),
                icon: const Icon(Icons.format_quote),
                label: const Text('Insert citation'),
              ),
            PopupMenuButton<_ZoteroSelectionExport>(
              enabled: !_busy && _selected.isNotEmpty,
              tooltip: 'Copy selected references',
              onSelected: (choice) {
                final format = choice.format;
                if (format == null) {
                  _copyStoredSelection();
                } else {
                  _copySources(format: format);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _ZoteroSelectionExport.stored(),
                  child: Text('Copy stored CSL JSON'),
                ),
                const PopupMenuDivider(),
                for (final format in ZoteroExportFormat.values)
                  PopupMenuItem(
                    value: _ZoteroSelectionExport.connected(format),
                    child: Text('Copy ${format.name}'),
                  ),
              ],
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
    if (_useLocal && _client != null)
      ZoteroLibrary.localUser(): 'My library (desktop)',
    if (_identity?.canReadPersonalLibrary == true)
      ZoteroLibrary.user(_identity!.userId): 'My library',
    for (final group in _groups) group.library: group.name,
  };

  Widget _documentTab() {
    final fields = _initialFields ?? _controller.zoteroFields;
    _initialFields = null;
    final current = _controller.findZoteroFieldAtCaret(fields: fields);
    // The field list already parsed every citation for this build. Reuse it
    // for action availability instead of rescanning the entire document for
    // each button, including while the Library tab is visible.
    final hasDocumentItems = fields.any(
      (field) => field.citation?.items.isNotEmpty ?? false,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (current != null) _currentFieldTools(current),
                if (widget.localTransport != null) _desktopTools(),
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
                          labelText: 'Preview / export style ID',
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
                    OutlinedButton.icon(
                      key: const ValueKey('zotero-cited-references'),
                      onPressed: _busy || !hasDocumentItems
                          ? null
                          : _showDocumentSources,
                      icon: const Icon(Icons.library_books_outlined),
                      label: const Text('Cited references…'),
                    ),
                    FilledButton(
                      onPressed:
                          _busy ||
                              !_canEdit ||
                              !hasDocumentItems ||
                              _client == null
                          ? null
                          : () => _bibliography(online: true),
                      child: const Text('Zotero bibliography'),
                    ),
                    OutlinedButton(
                      onPressed: _busy || !_canEdit || !hasDocumentItems
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
                      onPressed: _busy || !hasDocumentItems
                          ? null
                          : () => _copySources(),
                      child: const Text('Copy embedded CSL JSON'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('zotero-unlink-all'),
                      onPressed: _busy || !_canEdit || fields.isEmpty
                          ? null
                          : _unlinkAll,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Unlink all citations…'),
                    ),
                  ],
                ),
                if (_selected.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('${_selected.length} selected across all tabs'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _reviewSelectionButton(
                        'zotero-review-document-selection',
                      ),
                      TextButton.icon(
                        key: const ValueKey('zotero-copy-document-selection'),
                        onPressed: _busy ? null : _copyStoredSelection,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy stored CSL JSON'),
                      ),
                      if (widget.localTransport != null)
                        FilledButton(
                          key: const ValueKey(
                            'zotero-cite-document-selection-native',
                          ),
                          onPressed:
                              _busy ||
                                  !_canEdit ||
                                  _selected.values.any(
                                    (item) => item.uris.isEmpty,
                                  )
                              ? null
                              : () => _citeWithDesktop(
                                  ZoteroCitingCommand.addEditCitation,
                                  items: _selected.values.toList(),
                                ),
                          child: const Text('Insert with Zotero…'),
                        ),
                      OutlinedButton(
                        key: const ValueKey('zotero-cite-document-selection'),
                        onPressed: _busy || !_canEdit
                            ? null
                            : () => _compose(_selected.values.toList()),
                        child: const Text('Review and insert citation…'),
                      ),
                    ],
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Basic refresh updates only citations created with basic author–year format. Desktop citation tools process the document using Zotero’s selected CSL style; preview/export settings above are separate.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (fields.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No Zotero fields in this document.')),
            )
          else
            SliverList.separated(
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
                    key: ValueKey('zotero-reference-actions-$index'),
                    enabled: !_busy && !_controller.isDisposed && field.isValid,
                    tooltip: 'Reference actions',
                    onSelected: (action) {
                      if (action == 'reveal') {
                        Navigator.of(context).pop(field);
                      }
                      if (action == 'native') {
                        _citeWithDesktop(
                          field.kind == ZoteroFieldKind.citation
                              ? ZoteroCitingCommand.addEditCitation
                              : ZoteroCitingCommand.addEditBibliography,
                          field: field,
                        );
                      }
                      if (action == 'edit') {
                        _compose(citation!.items, field: field);
                      }
                      if (action == 'basic') {
                        _bibliography(online: false, field: field);
                      }
                      if (action == 'online') {
                        _bibliography(online: true, field: field);
                      }
                      if (action == 'unlink') {
                        _run(() async {
                          _write(() => _controller.unlinkZoteroField(field));
                        });
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'reveal',
                        enabled: _controller.canRevealZoteroField(field),
                        child: const Text('Go to reference'),
                      ),
                      if (_canEdit &&
                          widget.localTransport != null &&
                          field.canEdit)
                        const PopupMenuItem(
                          value: 'native',
                          child: Text('Edit in Zotero…'),
                        ),
                      if (_canEdit && citation != null && field.canEdit)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit citation'),
                        ),
                      if (_canEdit &&
                          field.kind == ZoteroFieldKind.bibliography &&
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
                      if (_canEdit && !field.locked && !field.nested)
                        const PopupMenuItem(
                          value: 'unlink',
                          child: Text('Convert to text (undoable)'),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _currentFieldTools(WmlZoteroField field) => Card(
    key: const ValueKey('zotero-current-field'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.kind == ZoteroFieldKind.citation
                ? 'Citation at the caret'
                : 'Bibliography at the caret',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (field.canEdit) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (widget.localTransport != null)
                  FilledButton(
                    key: const ValueKey('zotero-edit-current-native'),
                    onPressed: _busy || !_canEdit
                        ? null
                        : () => _citeWithDesktop(
                            field.kind == ZoteroFieldKind.citation
                                ? ZoteroCitingCommand.addEditCitation
                                : ZoteroCitingCommand.addEditBibliography,
                            field: field,
                          ),
                    child: const Text('Edit current reference in Zotero…'),
                  ),
                if (field.citation != null)
                  OutlinedButton(
                    key: const ValueKey('zotero-edit-current'),
                    onPressed: _busy || !_canEdit
                        ? null
                        : () => _compose(field.citation!.items, field: field),
                    child: const Text('Edit current citation…'),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  void _filterImportedReferences({bool clear = false}) {
    setState(() {
      if (clear) _importSearch.clear();
    });
    if (_importResultsScroll.hasClients) _importResultsScroll.jumpTo(0);
  }

  Widget _importTab() {
    final visible = filterZoteroImportedReferences(
      _imported,
      _importSearch.text,
    );
    final outsideResults =
        _selected.length -
        visible
            .where((entry) => _selected.containsKey(entry.selectionKey))
            .length;
    final textScale = max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const ValueKey('zotero-import-scroll'),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'In Zotero, export references as CSL JSON, then paste the file contents here. Sources stay embedded in the document. Records without a Zotero item URI remain offline references.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: max(160, min(300, constraints.maxHeight * 0.45)),
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
                          final references = [
                            for (final (index, item) in items.indexed)
                              ZoteroImportedReference(index: index, item: item),
                          ];
                          setState(() {
                            _selected.removeWhere(
                              (key, _) => key.startsWith('import:'),
                            );
                            _imported
                              ..clear()
                              ..addAll(references);
                            _importSearch.clear();
                            _notice =
                                '${items.length} references loaded. Search or choose sources below.';
                          });
                          if (_importResultsScroll.hasClients) {
                            _importResultsScroll.jumpTo(0);
                          }
                        }),
                  child: const Text('Load references'),
                ),
                _reviewSelectionButton('zotero-review-import-selection'),
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('zotero-copy-import-selection'),
                    onPressed: _busy ? null : _copyStoredSelection,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy stored CSL JSON'),
                  ),
              ],
            ),
            if (_imported.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('zotero-import-search'),
                controller: _importSearch,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Search imported references',
                  helperText:
                      'Title, creator, year or DOI. All words must match.',
                  helperMaxLines: 3,
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _importSearch.text.isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey('zotero-clear-import-search'),
                          tooltip: 'Clear imported reference search',
                          onPressed: _busy
                              ? null
                              : () => _filterImportedReferences(clear: true),
                          icon: const Icon(Icons.clear),
                        ),
                ),
                onChanged: (_) => _filterImportedReferences(),
              ),
              const SizedBox(height: 8),
              Text(
                '${visible.length} of ${_imported.length} shown · ${_selected.length} selected'
                '${outsideResults == 0 ? '' : ' ($outsideResults outside these results)'}',
                key: const ValueKey('zotero-import-result-count'),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 160 * textScale,
                child: visible.isEmpty
                    ? const Center(
                        child: Text(
                          'No imported references match this search.',
                          key: ValueKey('zotero-import-no-matches'),
                        ),
                      )
                    : ListView.builder(
                        key: const ValueKey('zotero-import-results'),
                        controller: _importResultsScroll,
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final entry = visible[index];
                          final key = entry.selectionKey;
                          return Row(
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  key: ValueKey(key),
                                  dense: true,
                                  value: _selected.containsKey(key),
                                  title: Text(
                                    entry.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: entry.subtitle.isEmpty
                                      ? null
                                      : Text(
                                          entry.subtitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(() {
                                          _error = null;
                                          if (value == false) {
                                            _selected.remove(key);
                                          } else if (_selected.length < 20) {
                                            _selected[key] = entry.item;
                                          } else {
                                            _error =
                                                'Select at most 20 sources per citation.';
                                          }
                                        }),
                                ),
                              ),
                              IconButton(
                                key: ValueKey('zotero-import-details-$key'),
                                tooltip: 'Stored reference details',
                                onPressed: _busy
                                    ? null
                                    : () => _showStoredReferenceDetails(
                                        entry.item,
                                      ),
                                icon: const Icon(Icons.info_outline),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
            FilledButton(
              onPressed: _busy || !_canEdit || _selected.isEmpty
                  ? null
                  : () => _compose(_selected.values.toList()),
              child: Text('Insert ${_selected.length} selected source(s)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BibliographyReview extends StatefulWidget {
  const _BibliographyReview({
    required this.title,
    required this.initial,
    this.formattedText,
  });

  final String title;
  final String initial;
  final ZoteroFormattedText? formattedText;

  @override
  State<_BibliographyReview> createState() => _BibliographyReviewState();
}

class _BibliographyReviewState extends State<_BibliographyReview> {
  late final TextEditingController _text;
  late bool _keepFormatting;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initial);
    _keepFormatting = widget.formattedText != null;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formatted = widget.formattedText;
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (formatted != null) ...[
              CheckboxListTile(
                key: const ValueKey('zotero-keep-formatting'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep Zotero formatting'),
                subtitle: const Text(
                  'Turn off to edit the bibliography as plain text.',
                ),
                value: _keepFormatting,
                onChanged: (value) => setState(() => _keepFormatting = value!),
              ),
              if (_keepFormatting && formatted.unsupportedFormatting.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Some source formatting is simplified: ${formatted.unsupportedFormatting.join(', ')}.',
                  ),
                ),
            ],
            if (_keepFormatting && formatted != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: max(120, MediaQuery.sizeOf(context).height * 0.45),
                ),
                child: SingleChildScrollView(
                  child: _ZoteroFormattedPreview(formatted: formatted),
                ),
              )
            else
              TextField(
                key: const ValueKey('zotero-bibliography-text'),
                controller: _text,
                minLines: 3,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Review before inserting',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final result = _keepFormatting ? formatted : null;
            final text = result?.plainText ?? _text.text;
            if (text.trim().isNotEmpty) {
              Navigator.pop(context, (text: text, formattedText: result));
            }
          },
          child: const Text('Use bibliography'),
        ),
      ],
    );
  }
}

/// Only the inert span model reaches Flutter. No HTML widget or external
/// resource is involved in the preview.
class _ZoteroFormattedPreview extends StatelessWidget {
  const _ZoteroFormattedPreview({required this.formatted});

  final ZoteroFormattedText formatted;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final size = base.fontSize ?? 14;
    return Text.rich(
      TextSpan(
        children: [
          for (final span in formatted.spans) _previewSpan(span, base, size),
        ],
      ),
      key: const ValueKey('zotero-formatted-preview'),
      semanticsLabel: formatted.plainText,
    );
  }

  InlineSpan _previewSpan(ZoteroTextSpan span, TextStyle base, double size) {
    final style = base.copyWith(
      fontWeight: span.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
      decoration: TextDecoration.combine([
        if (span.underline) TextDecoration.underline,
        if (span.strike) TextDecoration.lineThrough,
      ]),
    );
    TextSpan content(double scale) => span.smallCaps
        ? TextSpan(
            style: style,
            children: [
              for (final segment in WordSmallCaps.segments(span.text))
                TextSpan(
                  text: segment.text,
                  style: style.copyWith(fontSize: size * scale * segment.scale),
                ),
            ],
          )
        : TextSpan(
            text: span.text,
            style: style.copyWith(fontSize: size * scale),
          );
    if (span.verticalAlign == WmlVertAlign.baseline) {
      return content(1);
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Transform.translate(
        offset: Offset(
          0,
          span.verticalAlign == WmlVertAlign.superscript
              ? -size * 0.35
              : size * 0.14,
        ),
        child: Text.rich(content(0.65)),
      ),
    );
  }
}
