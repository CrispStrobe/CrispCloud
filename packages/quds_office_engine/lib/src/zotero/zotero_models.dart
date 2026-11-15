/// Transport-neutral models for Zotero Web API v3.
///
/// These types deliberately contain no account credentials. Keep API keys in
/// the host's connection/session state, never in document metadata.
library;

enum ZoteroLibraryType { user, group }

/// A Zotero library is identified by its kind and numeric ID, not its name.
class ZoteroLibrary {
  ZoteroLibrary({required this.type, required this.id}) {
    if (id <= 0) {
      throw ArgumentError('A positive Zotero library ID is required.');
    }
  }

  factory ZoteroLibrary.user(int id) =>
      ZoteroLibrary(type: ZoteroLibraryType.user, id: id);

  factory ZoteroLibrary.group(int id) =>
      ZoteroLibrary(type: ZoteroLibraryType.group, id: id);

  /// Routing alias for the current user's Zotero desktop library.
  /// Zero is never a persistent Zotero account or citation identifier.
  ZoteroLibrary.localUser() : type = ZoteroLibraryType.user, id = 0;

  final ZoteroLibraryType type;
  final int id;

  bool get isLocalUser => type == ZoteroLibraryType.user && id == 0;

  String get apiPath =>
      '/${type == ZoteroLibraryType.user ? 'users' : 'groups'}/$id';

  /// Zotero's persistent item identifiers use http://zotero.org, even though
  /// all network access to the Web API uses HTTPS.
  Uri itemUri(String key) {
    validateZoteroKey(key);
    if (isLocalUser) {
      throw StateError('The local library alias has no persistent item URI.');
    }
    return Uri.parse('http://zotero.org$apiPath/items/$key');
  }

  @override
  bool operator ==(Object other) =>
      other is ZoteroLibrary && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => 'ZoteroLibrary(${type.name}, $id)';
}

/// Rejects path/query injection and accidental use of a title as an item key.
void validateZoteroKey(String key) {
  if (!RegExp(r'^[A-Z0-9]{8}$').hasMatch(key)) {
    throw ArgumentError(
      'A Zotero item or collection key must have 8 uppercase letters or digits.',
    );
  }
}

class ZoteroKeyInfo {
  ZoteroKeyInfo({
    required this.userId,
    required this.username,
    required this.canReadPersonalLibrary,
    Map<String, bool> groupAccess = const {},
  }) : groupAccess = Map.unmodifiable(groupAccess);

  final int userId;
  final String username;
  final bool canReadPersonalLibrary;
  final Map<String, bool> groupAccess;

  bool canReadGroup(int groupId) =>
      groupAccess['all'] == true || groupAccess['$groupId'] == true;

  bool canRead(ZoteroLibrary library) => library.type == ZoteroLibraryType.group
      ? canReadGroup(library.id)
      : library.id == userId && canReadPersonalLibrary;
}

class ZoteroGroup {
  const ZoteroGroup({
    required this.id,
    required this.name,
    this.description = '',
  });

  final int id;
  final String name;
  final String description;

  ZoteroLibrary get library => ZoteroLibrary.group(id);
}

class ZoteroCollection {
  const ZoteroCollection({
    required this.key,
    required this.name,
    this.parentKey,
    this.version = 0,
  });

  final String key;
  final String name;
  final String? parentKey;
  final int version;
}

class ZoteroCreator {
  const ZoteroCreator({
    this.firstName = '',
    this.lastName = '',
    this.name = '',
    this.creatorType = 'author',
  });

  final String firstName;
  final String lastName;
  final String name;
  final String creatorType;

  String get displayName => name.isNotEmpty
      ? name
      : [firstName, lastName].where((part) => part.isNotEmpty).join(' ');
}

class ZoteroItem {
  ZoteroItem({
    required this.library,
    required this.key,
    required this.title,
    required this.itemType,
    this.version = 0,
    this.date = '',
    this.doi = '',
    this.url = '',
    List<ZoteroCreator> creators = const [],
    Map<String, dynamic>? cslJson,
    Uri? citationUri,
    this.citationHtml,
    this.bibliographyHtml,
  }) : creators = List.unmodifiable(creators),
       _citationUri = citationUri,
       cslJson = cslJson == null ? null : Map.unmodifiable(cslJson) {
    validateZoteroKey(key);
  }

  final ZoteroLibrary library;
  final String key;
  final String title;
  final String itemType;
  final int version;
  final String date;
  final String doi;
  final String url;
  final List<ZoteroCreator> creators;

  /// CSL JSON snapshot supplied by Zotero; suitable for embedding in a field.
  final Map<String, dynamic>? cslJson;

  /// An individual citation snapshot, not a document-wide citation processor.
  /// The host must sanitize HTML before using it as markup.
  final String? citationHtml;
  final String? bibliographyHtml;

  final Uri? _citationUri;

  /// Durable citation identity, independent of desktop's `/users/0` alias.
  /// An unsynced item whose export replaces its URI with a citation key may
  /// have no recoverable identity. Embed that item as an offline reference.
  Uri? get citationUri =>
      _citationUri ?? (library.isLocalUser ? null : library.itemUri(key));

  Uri get canonicalUri =>
      citationUri ??
      (throw StateError('This local item has no persistent Zotero URI.'));

  /// The fallback is for selection state only; never embed it as an item URI.
  String get sourceId =>
      citationUri?.toString() ?? 'zotero-local:${library.apiPath}/items/$key';
  String get creatorSummary => creators.map((c) => c.displayName).join(', ');
  String get year => RegExp(r'\b\d{4}\b').firstMatch(date)?.group(0) ?? '';
  bool get isCitable =>
      !const {'attachment', 'note', 'annotation'}.contains(itemType);
}

class ZoteroPage<T> {
  ZoteroPage({
    required List<T> items,
    required this.start,
    required this.limit,
    this.totalResults,
    this.nextStart,
    this.lastModifiedVersion,
    this.backoff,
  }) : items = List.unmodifiable(items);

  final List<T> items;
  final int start;
  final int limit;
  final int? totalResults;
  final int? nextStart;
  final int? lastModifiedVersion;
  final Duration? backoff;
  bool get hasMore => nextStart != null;
}

enum ZoteroExportFormat {
  cslJson('csljson', 'application/vnd.citationstyles.csl+json', 'json'),
  bibtex('bibtex', 'application/x-bibtex', 'bib'),
  biblatex('biblatex', 'application/x-bibtex', 'bib'),
  ris('ris', 'application/x-research-info-systems', 'ris');

  const ZoteroExportFormat(this.apiValue, this.mimeType, this.extension);
  final String apiValue;
  final String mimeType;
  final String extension;
}
