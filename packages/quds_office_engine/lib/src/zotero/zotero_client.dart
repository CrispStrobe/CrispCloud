import 'dart:convert';

import 'zotero_models.dart';

export 'zotero_models.dart';

/// The host owns network timeouts, cancellation and connection disposal.
/// A web host can implement this with package:http; the engine never imports
/// dart:io or Flutter, and never persists the API key.
/// Transports must disable redirects, so a custom API-key header cannot be
/// forwarded to another origin. Honor [ZoteroHttpRequest.followRedirects].
typedef ZoteroTransport =
    Future<ZoteroHttpResponse> Function(ZoteroHttpRequest request);

class ZoteroHttpRequest {
  ZoteroHttpRequest({
    required this.uri,
    required Map<String, String> headers,
    this.method = 'GET',
    this.body,
    this.timeout,
  }) : headers = Map.unmodifiable(headers);

  final Uri uri;
  Uri get url => uri;
  final Map<String, String> headers;
  final String method;

  /// Encoded request data. Catalog requests never have a body. Citing requests
  /// use JSON on the fixed desktop connector endpoints only.
  final String? body;

  /// Optional host-enforced request bound. A native Zotero picker can keep a
  /// citing request pending while the user chooses sources or a citation style.
  /// Hosts must still enforce their own maximum and reject unsupported routes.
  final Duration? timeout;
  bool get followRedirects => false;

  // Deliberately omit headers and body, which can contain credentials or data.
  @override
  String toString() => 'ZoteroHttpRequest($method ${uri.path})';
}

class ZoteroHttpResponse {
  ZoteroHttpResponse({
    required this.statusCode,
    required this.body,
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(
         headers.map((key, value) => MapEntry(key.toLowerCase(), value)),
       );

  final int statusCode;
  final String body;
  final Map<String, String> headers;
  String? header(String name) => headers[name.toLowerCase()];
}

enum ZoteroApiErrorKind {
  authentication,
  notFound,
  rateLimited,
  unavailable,
  invalidResponse,
  network,
  request,
}

/// A safe, user-displayable error. It never contains a response body, API key,
/// transport exception, request headers or a URL query string.
class ZoteroApiException implements Exception {
  const ZoteroApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.retryAfter,
  });

  final ZoteroApiErrorKind kind;
  final String message;
  final int? statusCode;
  final Duration? retryAfter;

  @override
  String toString() => message;
}

/// A session's pause requested by the online Zotero API.
///
/// Reuse this state when replacing online clients so reconnecting, changing a
/// library or closing a dialog cannot discard an unexpired server backoff.
/// It contains only a deadline, never credentials or library/document data,
/// and schedules no timer or retry. Clients sharing it must use the same clock.
/// Desktop clients retain their own independent pause state.
class ZoteroBackoffState {
  DateTime? _until;
}

/// Read-only client for Zotero Web API v3 and the opt-in desktop local API.
///
/// The default constructor uses only Zotero's fixed HTTPS origin. [ZoteroClient.local]
/// uses only `http://localhost:23119/api/` and never accepts an API key.
/// Neither client accepts arbitrary origins, follows redirects, or changes a library.
class ZoteroClient {
  ZoteroClient({
    required this.transport,
    String? apiKey,
    DateTime Function()? clock,
    ZoteroBackoffState? backoffState,
  }) : isLocal = false,
       _apiKey = apiKey?.trim(),
       _clock = clock ?? DateTime.now,
       _backoffState = backoffState ?? ZoteroBackoffState() {
    if (_apiKey != null && RegExp(r'[\r\n\x00-\x1f\x7f]').hasMatch(_apiKey)) {
      throw ArgumentError('The Zotero API key contains invalid characters.');
    }
  }

  /// Desktop access must be explicitly enabled by the user in Zotero.
  /// Hosts must provide a direct loopback transport, without an external proxy.
  ZoteroClient.local({required this.transport, DateTime Function()? clock})
    : isLocal = true,
      _apiKey = null,
      _clock = clock ?? DateTime.now,
      _backoffState = ZoteroBackoffState();

  final ZoteroTransport transport;
  final bool isLocal;
  final String? _apiKey;
  String? _localServerId;
  final DateTime Function() _clock;
  final ZoteroBackoffState _backoffState;

  /// If Zotero requests a pause, later calls fail immediately with a typed
  /// retry duration until it expires. The host can present a retry affordance;
  /// this client never waits or retries indefinitely.
  DateTime? get backoffUntil => _backoffState._until;
  Duration? get retryAfter {
    final until = backoffUntil;
    if (until == null) return null;
    final remaining = until.difference(_clock());
    return remaining > Duration.zero ? remaining : null;
  }

  /// Checks the local API using its plain-text root response. Zotero 10's
  /// server identifier is pinned for this client so a database change requires
  /// reconnecting instead of silently reusing a different desktop library.
  Future<void> probeLocal() async {
    if (!isLocal) {
      throw StateError('Only a local Zotero client can probe the desktop.');
    }
    final response = await _get('/');
    if (response.header('Zotero-API-Version') != '3') {
      throw _invalidResponse();
    }
  }

  Future<ZoteroKeyInfo> verifyKey() async {
    if (isLocal) {
      throw StateError('Zotero desktop does not use a Web API key.');
    }
    if (_apiKey == null || _apiKey.isEmpty) {
      throw const ZoteroApiException(
        kind: ZoteroApiErrorKind.authentication,
        message: 'Enter a Zotero API key to connect your library.',
      );
    }
    final response = await _get('/keys/current');
    final json = _object(_decode(response));
    final userId = _integer(json['userID']);
    if (userId == null || userId <= 0) throw _invalidResponse();
    final access = _optionalObject(json['access']);
    final user = _optionalObject(access['user']);
    final groups = _optionalObject(access['groups']);
    return ZoteroKeyInfo(
      userId: userId,
      username: _string(json['username']),
      canReadPersonalLibrary: user['library'] == true,
      groupAccess: groups.map(
        (key, value) =>
            MapEntry(key, _optionalObject(value)['library'] == true),
      ),
    );
  }

  Future<ZoteroPage<ZoteroGroup>> groups(
    int userId, {
    int start = 0,
    int limit = 50,
  }) async {
    final library = isLocal && userId == 0
        ? ZoteroLibrary.localUser()
        : ZoteroLibrary.user(userId);
    final uri = _uri(
      '${_libraryPath(library)}/groups',
      _pagination(start, limit),
    );
    final response = await _request(uri);
    final groups = _array(_decode(response)).map((value) {
      final json = _object(value);
      final data = _optionalObject(json['data']);
      final id = _integer(json['id']) ?? _integer(data['id']);
      if (id == null || id <= 0) throw _invalidResponse();
      return ZoteroGroup(
        id: id,
        name: _string(data['name'], _string(json['name'], 'Group $id')),
        description: _string(data['description']),
      );
    }).toList();
    return _page(groups, response, uri, start, limit);
  }

  Future<ZoteroPage<ZoteroCollection>> collections(
    ZoteroLibrary library, {
    int start = 0,
    int limit = 50,
  }) async {
    final uri = _uri(
      '${_libraryPath(library)}/collections',
      _pagination(start, limit),
    );
    final response = await _request(uri);
    final collections = _array(_decode(response)).map((value) {
      final json = _object(value);
      final data = _object(json['data']);
      final key = _responseKey(json['key'] ?? data['key']);
      final parent = data['parentCollection'];
      return ZoteroCollection(
        key: key,
        name: _string(data['name'], 'Untitled collection'),
        parentKey: parent is String && parent.isNotEmpty
            ? _responseKey(parent)
            : null,
        version: _integer(json['version']) ?? 0,
      );
    }).toList();
    return _page(collections, response, uri, start, limit);
  }

  /// Lists saved searches from the connected desktop library. The online API
  /// cannot execute these searches, so this workflow is local-only.
  Future<ZoteroPage<ZoteroSavedSearch>> savedSearches(
    ZoteroLibrary library, {
    int start = 0,
    int limit = 50,
  }) async {
    _requireLocalSearches();
    final uri = _uri(
      '${_libraryPath(library)}/searches',
      _pagination(start, limit),
    );
    final response = await _request(uri);
    final seen = <String>{};
    final searches = _array(_decode(response)).map((value) {
      final json = _object(value);
      final data = _object(json['data']);
      final key = _responseKey(json['key'] ?? data['key']);
      if ((data['key'] != null && data['key'] != key) || !seen.add(key)) {
        throw _invalidResponse();
      }
      if (json['library'] != null) {
        final source = _object(json['library']);
        final id = _integer(source['id']);
        if (source['type'] != library.type.name ||
            id == null ||
            id < 0 ||
            (!library.isLocalUser && id != library.id)) {
          throw _invalidResponse();
        }
      }
      return ZoteroSavedSearch(
        library: library,
        key: key,
        name: _string(data['name'], 'Untitled saved search'),
        version: _integer(json['version']) ?? 0,
      );
    }).toList();
    return _page(searches, response, uri, start, limit);
  }

  /// Executes an existing saved search in Zotero, with an optional additional
  /// quick-search, single item-type filter and literal [tags]. Every tag must
  /// match. Pagination and sorting happen in Zotero before results are returned.
  /// Notes/attachments may be returned by the saved search; callers should use
  /// [ZoteroItem.isCitable] for citation selection. See [normalizeZoteroTags] for
  /// tag input limits and names that Zotero cannot represent literally.
  Future<ZoteroPage<ZoteroItem>> savedSearchItems(
    ZoteroLibrary library,
    String searchKey, {
    String query = '',
    int start = 0,
    int limit = 50,
    ZoteroSearchMode searchMode = ZoteroSearchMode.titleCreatorYear,
    ZoteroItemSort sort = ZoteroItemSort.dateModified,
    ZoteroSortDirection direction = ZoteroSortDirection.descending,
    String? itemType,
    List<String> tags = const [],
  }) async {
    _requireLocalSearches();
    validateZoteroKey(searchKey);
    try {
      return await _items(
        library,
        '${_libraryPath(library)}/searches/$searchKey/items',
        query: query,
        start: start,
        limit: limit,
        searchMode: searchMode,
        sort: sort,
        direction: direction,
        itemType: itemType,
        tags: tags,
      );
    } on ZoteroApiException catch (error) {
      if (error.kind != ZoteroApiErrorKind.notFound) rethrow;
      throw const ZoteroApiException(
        kind: ZoteroApiErrorKind.notFound,
        statusCode: 404,
        message:
            'This saved search is no longer available. Refresh saved searches and choose again.',
      );
    }
  }

  void _requireLocalSearches() {
    if (!isLocal) {
      throw StateError('Saved searches require a Zotero desktop connection.');
    }
  }

  /// Browses/searches top-level items. [ZoteroItem.isCitable] distinguishes
  /// bibliographic items from standalone notes and attachments.
  /// Filters and ordering apply to the whole library or collection, before
  /// pagination. [itemType] accepts one Zotero type name, such as `book` or
  /// `journalArticle`; it does not accept Boolean search expressions.
  /// Every literal [tags] value must match. See [normalizeZoteroTags] for input
  /// limits and names that Zotero cannot represent literally.
  Future<ZoteroPage<ZoteroItem>> items(
    ZoteroLibrary library, {
    String? collectionKey,
    String query = '',
    int start = 0,
    int limit = 50,
    ZoteroSearchMode searchMode = ZoteroSearchMode.titleCreatorYear,
    ZoteroItemSort sort = ZoteroItemSort.dateModified,
    ZoteroSortDirection direction = ZoteroSortDirection.descending,
    String? itemType,
    List<String> tags = const [],
  }) async {
    if (collectionKey != null) validateZoteroKey(collectionKey);
    final path = collectionKey == null
        ? '${_libraryPath(library)}/items/top'
        : '${_libraryPath(library)}/collections/$collectionKey/items/top';
    return _items(
      library,
      path,
      query: query,
      start: start,
      limit: limit,
      searchMode: searchMode,
      sort: sort,
      direction: direction,
      itemType: itemType,
      tags: tags,
    );
  }

  Future<ZoteroPage<ZoteroItem>> _items(
    ZoteroLibrary library,
    String path, {
    required String query,
    required int start,
    required int limit,
    required ZoteroSearchMode searchMode,
    required ZoteroItemSort sort,
    required ZoteroSortDirection direction,
    required String? itemType,
    required List<String> tags,
  }) async {
    if (query.length > 1024 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(query)) {
      throw ArgumentError('Use a Zotero search of at most 1024 characters.');
    }
    if (itemType != null &&
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9]{0,63}$').hasMatch(itemType)) {
      throw ArgumentError('Use a single Zotero item type, such as book.');
    }
    final text = query.trim();
    final tagFilters = normalizeZoteroTags(tags);
    final parameters = <String, Object>{
      ..._pagination(start, limit),
      'include': 'data,csljson',
      'sort': sort.name,
      'direction': direction.apiValue,
      'itemType': ?itemType,
      if (text.isNotEmpty) 'q': text,
      if (text.isNotEmpty) 'qmode': searchMode.name,
      if (tagFilters.isNotEmpty)
        'tag': [
          for (final tag in tagFilters)
            // Repeated parameters mean AND. Escape an initial hyphen so a
            // literal name never becomes Zotero's exclusion operator.
            tag.startsWith('-') ? '\\$tag' : tag,
        ],
    };
    final uri = _uri(path, parameters);
    final response = await _request(uri);
    final items = _array(
      _decode(response),
    ).map((json) => _item(_object(json), library)).toList();
    return _page(items, response, uri, start, limit);
  }

  /// Retrieves CSL data and a formatted *individual* citation snapshot.
  /// This does not perform document-wide numbering, ibid or disambiguation.
  /// When [expectedCitationUri] is supplied, the same response must prove that
  /// identity. In particular, a local route and item key cannot identify a
  /// source from another unsynced desktop database.
  /// Set [includeFormatted] to false for metadata refresh: this requests only
  /// item data and CSL, without loading a style or rendering a citation.
  Future<ZoteroItem> item(
    ZoteroLibrary library,
    String key, {
    String style = 'apa',
    String locale = 'en-US',
    Uri? expectedCitationUri,
    bool includeFormatted = true,
  }) async {
    validateZoteroKey(key);
    final expected = expectedCitationUri == null
        ? null
        : _expectedIdentity(library, key, expectedCitationUri);
    final response = await _get('${_libraryPath(library)}/items/$key', {
      'include': includeFormatted
          ? 'data,csljson,citation,bib'
          : 'data,csljson',
      if (includeFormatted) ..._formatting(style, locale),
    });
    final item = _item(_object(_decode(response)), library);
    if (item.key != key) throw _invalidResponse();
    if (expected != null && item.citationUri != expected) {
      throw _identityMismatch();
    }
    return item;
  }

  /// Retrieves metadata for 1–50 linked sources in one library identity.
  ///
  /// Every returned key and durable URI must match [expectedItemUris]. Missing,
  /// duplicate or substituted records refuse the entire result. Results retain
  /// the map's insertion order even when Zotero returns another order.
  ///
  /// This makes one bounded request without loading a style or rendering a
  /// citation. Unlike a subsequent raw export, the same response proves every
  /// source identity, so older desktop versions need no database/version header.
  /// Hosts refreshing multiple libraries should group by durable library scope
  /// (including the local profile), then apply changes only after every group
  /// succeeds. Local and online versions are never compared.
  Future<List<ZoteroItem>> metadataItems(
    ZoteroLibrary library, {
    required Map<String, Uri> expectedItemUris,
  }) async {
    final keys = _selection(expectedItemUris.keys.toList());
    final expected = _expectedSelection(library, keys, expectedItemUris)!;
    final response = await _selectionMetadata(
      '${_libraryPath(library)}/items',
      expected,
    );
    return _verifiedSelection(response, library, expected);
  }

  Future<List<Map<String, dynamic>>> cslItems(
    ZoteroLibrary library,
    List<String> itemKeys,
  ) async {
    final text = await exportItems(
      library,
      itemKeys,
      format: ZoteroExportFormat.cslJson,
    );
    try {
      final decoded = jsonDecode(text);
      // Web API v3 wraps format=csljson in {"items": [...]}; include=csljson
      // above is a single object. Accept plain CSL arrays as well.
      final items = decoded is Map<String, dynamic>
          ? decoded['items']
          : decoded;
      return List.unmodifiable(_array(items).map(_object));
    } on FormatException {
      throw _invalidResponse();
    }
  }

  /// Renders one globally sorted bibliography for a selection in one library.
  ///
  /// The itemKey endpoint accepts at most 50 keys. Larger selections are refused
  /// rather than concatenating independently formatted bibliographies, which
  /// would silently break CSL sorting/disambiguation. HTML must be sanitized by
  /// the host before display or insertion as markup.
  ///
  /// Supply [expectedItemUris] when the selection comes from document links.
  /// All identities are checked before the single formatted request. Local
  /// verification also requires a pinned desktop database identity.
  Future<String> bibliography(
    ZoteroLibrary library, {
    required List<String> itemKeys,
    String style = 'apa',
    String locale = 'en-US',
    Map<String, Uri>? expectedItemUris,
  }) async {
    final keys = _selection(itemKeys);
    final path = '${_libraryPath(library)}/items';
    final formatting = _formatting(style, locale);
    final expected = _expectedSelection(library, keys, expectedItemUris);
    final version = expected == null
        ? null
        : await _verifySelection(path, library, expected);
    final response = await _get(path, {
      'itemKey': keys.join(','),
      'format': 'bib',
      'linkwrap': '0',
      ...formatting,
    });
    if (expected != null) {
      _verifyAggregateResponse(response, expected.length, version);
    }
    return response.body;
  }

  /// Exports selected records without converting or dropping their metadata.
  /// Selections are limited to Zotero's 50-key request maximum.
  /// [expectedItemUris] verifies every document-linked source before export;
  /// missing, duplicate or substituted sources fail the whole selection.
  Future<String> exportItems(
    ZoteroLibrary library,
    List<String> itemKeys, {
    ZoteroExportFormat format = ZoteroExportFormat.cslJson,
    Map<String, Uri>? expectedItemUris,
  }) async {
    final keys = _selection(itemKeys);
    final path = '${_libraryPath(library)}/items';
    final expected = _expectedSelection(library, keys, expectedItemUris);
    final version = expected == null
        ? null
        : await _verifySelection(path, library, expected);
    final response = await _get(path, {
      'itemKey': keys.join(','),
      'format': format.apiValue,
      'limit': '${keys.length}',
    });
    if (expected != null) {
      _verifyAggregateResponse(response, expected.length, version);
    }
    return response.body;
  }

  /// Check identity arguments before making a request. The library is only a
  /// route; a local source URI must still be proven by returned item metadata.
  Uri _expectedIdentity(ZoteroLibrary library, String key, Uri expected) {
    _libraryPath(library);
    final uri = _canonicalItemUri(expected, key);
    if (uri == null ||
        (library.isLocalUser
            ? !isLocal || !uri.path.startsWith('/users/')
            : uri != library.itemUri(key))) {
      throw ArgumentError(
        'The expected Zotero source must match the selected library and key.',
      );
    }
    return uri;
  }

  Map<String, Uri>? _expectedSelection(
    ZoteroLibrary library,
    List<String> keys,
    Map<String, Uri>? expectedItemUris,
  ) {
    if (expectedItemUris == null) return null;
    if (expectedItemUris.length != keys.length ||
        keys.any((key) => !expectedItemUris.containsKey(key))) {
      throw ArgumentError(
        'Provide an identity for every selected Zotero item.',
      );
    }
    final expected = <String, Uri>{
      for (final key in keys)
        key: _expectedIdentity(library, key, expectedItemUris[key]!),
    };
    // Two unsynced profiles can have identical item keys and /users/0 routes.
    // Do not combine them or deduplicate them by the request address.
    final scopes = expected.values
        .map((uri) => uri.path.substring(0, uri.path.lastIndexOf('/items/')))
        .toSet();
    if (scopes.length != 1) {
      throw ArgumentError('Choose Zotero sources from one library identity.');
    }
    return Map.unmodifiable(expected);
  }

  /// Raw bibliography/export output has no usable identity envelope. Verify
  /// the exact selection in one bounded metadata response before requesting it.
  /// Local aggregate operations additionally need Zotero's database pin so a
  /// profile switch between the two requests cannot export another library.
  Future<int?> _verifySelection(
    String path,
    ZoteroLibrary library,
    Map<String, Uri> expected,
  ) async {
    final response = await _selectionMetadata(path, expected);
    _verifiedSelection(response, library, expected);
    final versionHeader = response.header('Last-Modified-Version');
    final version = int.tryParse(versionHeader ?? '');
    if (versionHeader != null && (version == null || version < 0)) {
      throw _invalidResponse();
    }
    if (isLocal && (_localServerId == null || version == null)) {
      throw const ZoteroApiException(
        kind: ZoteroApiErrorKind.unavailable,
        message:
            'This Zotero desktop does not provide a database identity and library version. Use Zotero 10 or later and reconnect to export or format these sources safely. Individual previews and metadata refresh remain available.',
      );
    }
    return version;
  }

  Future<ZoteroHttpResponse> _selectionMetadata(
    String path,
    Map<String, Uri> expected,
  ) => _get(path, {
    'itemKey': expected.keys.join(','),
    'format': 'json',
    'include': 'data,csljson',
    'limit': '${expected.length}',
  });

  List<ZoteroItem> _verifiedSelection(
    ZoteroHttpResponse response,
    ZoteroLibrary library,
    Map<String, Uri> expected,
  ) {
    final records = _array(_decode(response));
    _verifyAggregateResponse(response, expected.length, null);
    if (records.length != expected.length) throw _identityMismatch();
    final items = <String, ZoteroItem>{};
    for (final record in records) {
      final item = _item(_object(record), library);
      if (items.containsKey(item.key) ||
          !expected.containsKey(item.key) ||
          item.citationUri != expected[item.key]) {
        throw _identityMismatch();
      }
      items[item.key] = item;
    }
    return List.unmodifiable(expected.keys.map((key) => items[key]!));
  }

  static void _verifyAggregateResponse(
    ZoteroHttpResponse response,
    int expectedCount,
    int? expectedVersion,
  ) {
    final total = response.header('Total-Results');
    if (total != null && int.tryParse(total) != expectedCount) {
      throw _identityMismatch();
    }
    // This version belongs to this connection and library only. Never compare
    // object versions from the desktop with versions from the online API.
    if (expectedVersion != null &&
        int.tryParse(response.header('Last-Modified-Version') ?? '') !=
            expectedVersion) {
      throw const ZoteroApiException(
        kind: ZoteroApiErrorKind.invalidResponse,
        message:
            'The Zotero library changed while preparing the selection. Try again; existing citations were kept.',
      );
    }
  }

  static ZoteroApiException _identityMismatch() => const ZoteroApiException(
    kind: ZoteroApiErrorKind.invalidResponse,
    message:
        'Zotero did not return the selected source identities. Check the connected library; existing citations were kept.',
  );

  static List<String> _selection(List<String> itemKeys) {
    final keys = itemKeys.toSet().toList(growable: false);
    if (keys.isEmpty || keys.length > 50) {
      throw ArgumentError(
        'Choose between 1 and 50 Zotero items from one library.',
      );
    }
    keys.forEach(validateZoteroKey);
    return keys;
  }

  static Map<String, String> _pagination(int start, int limit) {
    if (start < 0 || limit < 1 || limit > 100) {
      throw ArgumentError(
        'Zotero pages require start >= 0 and a limit of 1–100.',
      );
    }
    return {'start': '$start', 'limit': '$limit', 'format': 'json'};
  }

  static Map<String, String> _formatting(String style, String locale) {
    // Use a Zotero Style Repository identifier, not an arbitrary remote URL.
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,199}$').hasMatch(style)) {
      throw ArgumentError(
        'Use a Zotero citation style identifier, such as apa.',
      );
    }
    if (!RegExp(
      r'^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8}){0,3}$',
    ).hasMatch(locale)) {
      throw ArgumentError('Use a citation locale such as en-US.');
    }
    return {'style': style, 'locale': locale};
  }

  String _libraryPath(ZoteroLibrary library) {
    if (library.isLocalUser && !isLocal) {
      throw ArgumentError('The local library alias requires Zotero desktop.');
    }
    return library.apiPath;
  }

  Uri _uri(String path, [Map<String, Object> parameters = const {}]) => isLocal
      ? Uri.http(
          'localhost:23119',
          '/api$path',
          parameters.isEmpty ? null : parameters,
        )
      : Uri.https(
          'api.zotero.org',
          path,
          parameters.isEmpty ? null : parameters,
        );

  Future<ZoteroHttpResponse> _get(
    String path, [
    Map<String, String> parameters = const {},
  ]) => _request(_uri(path, parameters));

  Future<ZoteroHttpResponse> _request(Uri uri) async {
    final pause = retryAfter;
    if (pause != null) {
      throw ZoteroApiException(
        kind: ZoteroApiErrorKind.rateLimited,
        message: 'Zotero requested a pause. Try again after the retry period.',
        retryAfter: pause,
      );
    }
    final request = ZoteroHttpRequest(
      uri: uri,
      headers: {
        'Zotero-API-Version': '3',
        if (isLocal) 'Zotero-Allowed-Request': '1',
        if (isLocal && _localServerId != null)
          'Zotero-Server-ID': _localServerId!,
        if (!isLocal && _apiKey != null && _apiKey.isNotEmpty)
          'Zotero-API-Key': _apiKey,
      },
    );
    ZoteroHttpResponse response;
    try {
      response = await transport(request);
    } catch (_) {
      // Transport exceptions may contain URLs or headers. Never surface them.
      throw ZoteroApiException(
        kind: ZoteroApiErrorKind.network,
        message: isLocal
            ? 'Could not reach Zotero desktop. Open Zotero on this computer and try again.'
            : 'Could not reach Zotero. Check the connection and try again.',
      );
    }
    var backoff = _seconds(response.header('Backoff'));
    final retry = _seconds(response.header('Retry-After'));
    if (retry != null && (backoff == null || retry > backoff)) backoff = retry;
    if (response.statusCode == 429 && backoff == null) {
      backoff = const Duration(seconds: 30);
    }
    if (backoff != null && backoff > Duration.zero) {
      final until = _clock().add(backoff);
      // Concurrent in-flight responses must not shorten an existing pause.
      if (backoffUntil == null || until.isAfter(backoffUntil!)) {
        _backoffState._until = until;
      }
    }
    if (isLocal && response.statusCode == 412) {
      throw _localConnectionChanged(response.statusCode);
    }
    if (response.statusCode == 200) {
      if (isLocal) {
        final serverId = response.header('Zotero-Server-ID');
        if (_localServerId != null && serverId != _localServerId) {
          throw _localConnectionChanged(response.statusCode);
        }
        if (serverId != null) {
          if (serverId.isEmpty ||
              serverId.length > 256 ||
              RegExp(r'[^\x21-\x7e]').hasMatch(serverId)) {
            throw _invalidResponse();
          }
          _localServerId ??= serverId;
        }
      }
      return response;
    }
    final (kind, message) = switch (response.statusCode) {
      401 || 403 => (
        ZoteroApiErrorKind.authentication,
        isLocal
            ? 'Zotero desktop denied access. In Zotero Settings → Advanced, enable “Allow other applications on this computer to communicate with Zotero”.'
            : 'Zotero denied access. Check the API key and its library permissions.',
      ),
      404 => (
        ZoteroApiErrorKind.notFound,
        'The Zotero library or item was not found.',
      ),
      429 => (
        ZoteroApiErrorKind.rateLimited,
        'Zotero is limiting requests. Try again after the retry period.',
      ),
      >= 500 => (
        ZoteroApiErrorKind.unavailable,
        'Zotero is temporarily unavailable. Try again later.',
      ),
      _ => (
        ZoteroApiErrorKind.request,
        'Zotero could not complete this request.',
      ),
    };
    final remaining = retryAfter;
    final retryDuration =
        remaining != null && (backoff == null || remaining > backoff)
        ? remaining
        : backoff;
    throw ZoteroApiException(
      kind: kind,
      message: message,
      statusCode: response.statusCode,
      retryAfter: retryDuration,
    );
  }

  ZoteroPage<T> _page<T>(
    List<T> items,
    ZoteroHttpResponse response,
    Uri request,
    int start,
    int limit,
  ) {
    final total = int.tryParse(response.header('Total-Results') ?? '');
    int? next;
    final link = response.header('Link');
    if (link != null) {
      for (final match in RegExp(
        r'<([^>]+)>\s*;\s*rel="?([^",; ]+)"?',
      ).allMatches(link)) {
        if (match.group(2) != 'next') continue;
        final uri = Uri.tryParse(match.group(1)!);
        // Only extract an offset; never follow an arbitrary URL with the key.
        if (uri == null ||
            uri.scheme != request.scheme ||
            uri.host != request.host ||
            uri.port != request.port ||
            uri.userInfo.isNotEmpty ||
            uri.path != request.path ||
            uri.hasFragment ||
            uri.queryParameters.containsKey('key')) {
          throw _invalidResponse();
        }
        next = int.tryParse(uri.queryParameters['start'] ?? '');
        if (next == null || next <= start) throw _invalidResponse();
        break;
      }
    }
    if (next == null && total != null && total > start + limit) {
      next = start + limit;
    }
    return ZoteroPage(
      items: items,
      start: start,
      limit: limit,
      totalResults: total != null && total >= 0 ? total : null,
      nextStart: next,
      lastModifiedVersion: int.tryParse(
        response.header('Last-Modified-Version') ?? '',
      ),
      backoff: _seconds(response.header('Backoff')),
    );
  }

  ZoteroItem _item(Map<String, dynamic> json, ZoteroLibrary library) {
    final data = _object(json['data']);
    final key = _responseKey(json['key'] ?? data['key']);
    if (data['key'] != null && data['key'] != key) throw _invalidResponse();
    final itemType = _string(data['itemType']);
    if (itemType.isEmpty) throw _invalidResponse();
    var sourceLibrary = library;
    if (json['library'] != null) {
      final source = _object(json['library']);
      final id = _integer(source['id']);
      if (source['type'] != library.type.name ||
          id == null ||
          id < 0 ||
          (!library.isLocalUser && id != library.id)) {
        throw _invalidResponse();
      }
      if (library.isLocalUser && id > 0) sourceLibrary = ZoteroLibrary.user(id);
    } else if (library.isLocalUser) {
      // The routing alias alone says nothing about the persistent identity.
      throw _invalidResponse();
    }
    final creators = data['creators'];
    // Saved searches can return child notes, attachments, or annotations.
    // Zotero's CSL exporter can omit these records (an empty CSL array), and
    // they are never citation candidates. Do not let their missing CSL block
    // the bibliographic items on the same catalog page.
    final cslJson =
        const {'attachment', 'note', 'annotation'}.contains(itemType)
        ? null
        : _singleCsl(json['csljson']);
    final cslUri = _cslUri(cslJson?['id'], key);
    final canonicalUri = sourceLibrary.isLocalUser
        ? cslUri
        : sourceLibrary.itemUri(key);
    if (cslUri != null &&
        (sourceLibrary.isLocalUser
            ? !cslUri.path.startsWith('/users/local/')
            : cslUri != canonicalUri)) {
      throw _invalidResponse();
    }
    return ZoteroItem(
      library: library,
      key: key,
      title: _string(data['title'], 'Untitled item'),
      itemType: itemType,
      date: _string(data['date']),
      version: _integer(json['version']) ?? 0,
      doi: _string(data['DOI']),
      url: _string(data['url']),
      abstractNote: _string(data['abstractNote']),
      publicationTitle: _publicationTitle(data, itemType),
      publisher: _string(data['publisher']),
      tags: _itemTags(data['tags']),
      creators: creators is List
          ? creators.map((value) {
              final creator = _object(value);
              return ZoteroCreator(
                firstName: _string(creator['firstName']),
                lastName: _string(creator['lastName']),
                name: _string(creator['name']),
                creatorType: _string(creator['creatorType'], 'author'),
              );
            }).toList()
          : const [],
      cslJson: cslJson,
      citationUri: canonicalUri,
      citationHtml: json['citation'] is String
          ? json['citation'] as String
          : null,
      bibliographyHtml: json['bib'] is String ? json['bib'] as String : null,
    );
  }

  static String _publicationTitle(Map<String, dynamic> data, String itemType) {
    // Zotero's schema maps these type-specific fields to publicationTitle.
    final field = switch (itemType) {
      'blogPost' => 'blogTitle',
      'bookSection' => 'bookTitle',
      'conferencePaper' => 'proceedingsTitle',
      'dictionaryEntry' => 'dictionaryTitle',
      'encyclopediaArticle' => 'encyclopediaTitle',
      'forumPost' => 'forumTitle',
      'presentation' => 'sessionTitle',
      'radioBroadcast' || 'tvBroadcast' => 'programTitle',
      'webpage' => 'websiteTitle',
      _ => 'publicationTitle',
    };
    final title = _string(data[field]);
    return title.isEmpty ? _string(data['publicationTitle']) : title;
  }

  static List<String> _itemTags(Object? value) {
    if (value is! List<Object?>) return const [];
    final tags = <String>[];
    for (final entry in value) {
      if (entry is! Map<String, dynamic>) continue;
      final name = entry['tag'];
      if (name is String && name.isNotEmpty) tags.add(name);
    }
    return tags;
  }

  /// Desktop exports include a one-element CSL array as a JSON string;
  /// Web API responses normally include the object directly. Never select an
  /// arbitrary first record from an unexpected multi-item export.
  static Map<String, dynamic>? _singleCsl(dynamic value) {
    if (value == null || value == '') return null;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        throw _invalidResponse();
      }
    }
    if (value is Map<String, dynamic> && value.containsKey('items')) {
      value = value['items'];
    }
    if (value is List) {
      if (value.length != 1) throw _invalidResponse();
      value = value.single;
    }
    return _object(value);
  }

  /// Canonical URI IDs are verified, while citation keys and Zotero's numeric
  /// export IDs remain ordinary CSL IDs. In particular users/0 is not an ID.
  static Uri? _cslUri(Object? value, String key) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        !const ['zotero.org', 'www.zotero.org'].contains(uri.host)) {
      return null;
    }
    // Uri normalizes explicit default ports. Inspect the original authority
    // as well so an exported :80 or :443 identity is not silently accepted.
    final authority = RegExp(r'^[^:]+://([^/?#]*)').firstMatch(value)?.group(1);
    final canonical = _canonicalItemUri(uri, key);
    if (canonical == null || authority == null || authority.contains(':')) {
      throw _invalidResponse();
    }
    return canonical;
  }

  static Uri? _canonicalItemUri(Uri uri, String key) {
    if (!const ['http', 'https'].contains(uri.scheme) ||
        !const ['zotero.org', 'www.zotero.org'].contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final match = RegExp(
      r'^/(?:users/[1-9][0-9]*|groups/[1-9][0-9]*|users/local/[A-Za-z0-9]{8})/items/([A-Z0-9]{8})$',
    ).firstMatch(uri.path);
    if (match == null || match.group(1) != key) return null;
    return Uri.parse('http://zotero.org${uri.path}');
  }

  static ZoteroApiException _localConnectionChanged(int status) =>
      ZoteroApiException(
        kind: ZoteroApiErrorKind.unavailable,
        message:
            'Zotero desktop library changed. Reconnect to its local library.',
        statusCode: status,
      );

  static dynamic _decode(ZoteroHttpResponse response) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw _invalidResponse();
    }
  }

  static Map<String, dynamic> _object(dynamic value) {
    if (value is! Map<String, dynamic>) throw _invalidResponse();
    return value;
  }

  static Map<String, dynamic> _optionalObject(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};

  static List<dynamic> _array(dynamic value) {
    if (value is! List) throw _invalidResponse();
    return value;
  }

  static String _string(dynamic value, [String fallback = '']) =>
      value is String && value.isNotEmpty ? value : fallback;

  static int? _integer(dynamic value) => value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;

  static String _responseKey(dynamic value) {
    if (value is! String || !RegExp(r'^[A-Z0-9]{8}$').hasMatch(value)) {
      throw _invalidResponse();
    }
    return value;
  }

  static Duration? _seconds(String? value) {
    final seconds = int.tryParse(value?.trim() ?? '');
    // Ignore malformed/overflowing headers instead of creating absurd timers.
    return seconds != null && seconds >= 0 && seconds <= 86400 * 30
        ? Duration(seconds: seconds)
        : null;
  }

  static ZoteroApiException _invalidResponse() => const ZoteroApiException(
    kind: ZoteroApiErrorKind.invalidResponse,
    message: 'Zotero returned an unexpected response. Try again later.',
  );
}
