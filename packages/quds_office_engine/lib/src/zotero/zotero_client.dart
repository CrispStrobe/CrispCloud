import 'dart:convert';

import 'zotero_models.dart';

export 'zotero_models.dart';

/// The host owns network timeouts, cancellation and connection disposal.
/// A web host can implement this with package:http; the engine never imports
/// dart:io or Flutter, and never persists the API key.
/// Transports must disable redirects, so a custom API-key header cannot be
/// forwarded to another origin. Honor [ZoteroHttpRequest.followRedirects].
typedef ZoteroTransport = Future<ZoteroHttpResponse> Function(
  ZoteroHttpRequest request,
);

class ZoteroHttpRequest {
  ZoteroHttpRequest({required this.uri, required Map<String, String> headers})
    : headers = Map.unmodifiable(headers);

  final Uri uri;
  Uri get url => uri;
  final Map<String, String> headers;
  String get method => 'GET';
  bool get followRedirects => false;

  // Deliberately omit headers, which may contain a secret API key.
  @override
  String toString() => 'ZoteroHttpRequest(GET ${uri.path})';
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
  }) : isLocal = false,
       _apiKey = apiKey?.trim(),
       _clock = clock ?? DateTime.now {
    if (_apiKey != null && RegExp(r'[\r\n\x00-\x1f\x7f]').hasMatch(_apiKey)) {
      throw ArgumentError('The Zotero API key contains invalid characters.');
    }
  }

  /// Desktop access must be explicitly enabled by the user in Zotero.
  /// Hosts must provide a direct loopback transport, without an external proxy.
  ZoteroClient.local({required this.transport, DateTime Function()? clock})
    : isLocal = true,
      _apiKey = null,
      _clock = clock ?? DateTime.now;

  final ZoteroTransport transport;
  final bool isLocal;
  final String? _apiKey;
  String? _localServerId;
  final DateTime Function() _clock;
  DateTime? _backoffUntil;

  /// If Zotero requests a pause, later calls fail immediately with a typed
  /// retry duration until it expires. The host can present a retry affordance;
  /// this client never waits or retries indefinitely.
  DateTime? get backoffUntil => _backoffUntil;
  Duration? get retryAfter {
    final until = _backoffUntil;
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

  /// Browses/searches top-level items. [ZoteroItem.isCitable] distinguishes
  /// bibliographic items from standalone notes and attachments.
  Future<ZoteroPage<ZoteroItem>> items(
    ZoteroLibrary library, {
    String? collectionKey,
    String query = '',
    int start = 0,
    int limit = 50,
  }) async {
    if (collectionKey != null) validateZoteroKey(collectionKey);
    final path = collectionKey == null
        ? '${_libraryPath(library)}/items/top'
        : '${_libraryPath(library)}/collections/$collectionKey/items/top';
    final parameters = {
      ..._pagination(start, limit),
      'include': 'data,csljson',
      'sort': 'dateModified',
      'direction': 'desc',
      if (query.trim().isNotEmpty) 'q': query.trim(),
      if (query.trim().isNotEmpty) 'qmode': 'titleCreatorYear',
    };
    final uri = _uri(path, parameters);
    final response = await _request(uri);
    final items = _array(_decode(response))
        .map((json) => _item(_object(json), library))
        .toList();
    return _page(items, response, uri, start, limit);
  }

  /// Retrieves CSL data and a formatted *individual* citation snapshot.
  /// This does not perform document-wide numbering, ibid or disambiguation.
  Future<ZoteroItem> item(
    ZoteroLibrary library,
    String key, {
    String style = 'apa',
    String locale = 'en-US',
  }) async {
    validateZoteroKey(key);
    final response = await _get('${_libraryPath(library)}/items/$key', {
      'include': 'data,csljson,citation,bib',
      ..._formatting(style, locale),
    });
    final item = _item(_object(_decode(response)), library);
    if (item.key != key) throw _invalidResponse();
    return item;
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
  Future<String> bibliography(
    ZoteroLibrary library, {
    required List<String> itemKeys,
    String style = 'apa',
    String locale = 'en-US',
  }) async {
    final keys = _selection(itemKeys);
    final response = await _get('${_libraryPath(library)}/items', {
      'itemKey': keys.join(','),
      'format': 'bib',
      'linkwrap': '0',
      ..._formatting(style, locale),
    });
    return response.body;
  }

  /// Exports selected records without converting or dropping their metadata.
  /// Selections are limited to Zotero's 50-key request maximum.
  Future<String> exportItems(
    ZoteroLibrary library,
    List<String> itemKeys, {
    ZoteroExportFormat format = ZoteroExportFormat.cslJson,
  }) async {
    final keys = _selection(itemKeys);
    final response = await _get('${_libraryPath(library)}/items', {
      'itemKey': keys.join(','),
      'format': format.apiValue,
      'limit': '${keys.length}',
    });
    return response.body;
  }

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
    if (!RegExp(r'^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8}){0,3}$')
        .hasMatch(locale)) {
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

  Uri _uri(String path, [Map<String, String> parameters = const {}]) => isLocal
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
      if (_backoffUntil == null || until.isAfter(_backoffUntil!)) {
        _backoffUntil = until;
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
    final cslJson = _singleCsl(json['csljson']);
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
  static Uri? _cslUri(dynamic value, String key) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host != 'zotero.org') return null;
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port != (uri.scheme == 'https' ? 443 : 80)) {
      throw _invalidResponse();
    }
    final match = RegExp(
      r'^/(?:users/[1-9][0-9]*|groups/[1-9][0-9]*|users/local/[A-Za-z0-9]{8})/items/([A-Z0-9]{8})$',
    ).firstMatch(uri.path);
    if (match == null || match.group(1) != key) throw _invalidResponse();
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
