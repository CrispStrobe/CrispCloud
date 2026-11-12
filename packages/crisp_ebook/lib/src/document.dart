part of '../crisp_ebook.dart';

/// An editable EPUB package. Unchanged resources retain their original ZIP
/// payloads. Source edits can temporarily be invalid; [validate] reports them
/// and [toBytes] refuses to save a changed package with structural errors.
class EpubDocument {
  final EpubLimits limits;
  _ZipContainer _zip;
  final Map<String, Uint8List> _changed = {};
  final Set<String> _removed = {};
  late String packagePath;
  late XmlDocument _package;
  late String _fontIdentifier;
  String? _packageParseError;
  int _revision = 0;
  int _savedRevision = 0;
  int? _serializedRevision;
  Uint8List? _serializedBytes;
  final List<String> importWarnings = [];
  String sourceFormat = 'epub';

  EpubDocument._(this._zip, this.limits);

  factory EpubDocument.open(
    Uint8List bytes, {
    EpubLimits limits = const EpubLimits(),
  }) {
    final document = EpubDocument._(_ZipContainer.open(bytes, limits), limits);
    final container = document._xml('META-INF/container.xml');
    if (container.rootElement.name.local != 'container') {
      throw const EpubException(
        'invalid_container',
        'The EPUB container root is invalid.',
      );
    }
    final rootfiles = _elements(container, 'rootfile');
    if (rootfiles.isEmpty) {
      throw const EpubException(
        'missing_package',
        'The EPUB container has no package document.',
      );
    }
    final selected = rootfiles.firstWhere(
      (e) => e.getAttribute('media-type') == 'application/oebps-package+xml',
      orElse: () => rootfiles.first,
    );
    final fullPath = selected.getAttribute('full-path');
    if (fullPath == null || fullPath.isEmpty) {
      throw const EpubException(
        'missing_package',
        'The EPUB package path is missing.',
      );
    }
    document.packagePath = _safeArchivePath(fullPath);
    document._package = document._xml(document.packagePath);
    document._fontIdentifier = document.identifier;
    if (document._package.rootElement.name.local != 'package') {
      throw const EpubException(
        'invalid_package',
        'The EPUB package root is invalid.',
      );
    }
    if (document._manifestElement == null || document._spineElement == null) {
      throw const EpubException(
        'invalid_package',
        'The EPUB package needs a manifest and spine.',
      );
    }
    return document;
  }

  factory EpubDocument.create({
    String title = 'Untitled book',
    List<String> authors = const [],
    String language = 'en',
    String description = '',
    EpubLimits limits = const EpubLimits(),
  }) {
    if (authors.any((author) => author.trim().isEmpty)) {
      throw const EpubException(
        'metadata_author',
        'An author must have a name; use an empty list for an unknown author.',
      );
    }
    final id =
        'urn:crispbook:${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${crypto.sha256.convert(utf8.encode('$title|$authors')).toString().substring(0, 16)}';
    final files = <String, Uint8List>{
      'META-INF/container.xml': _utf8(
        '<?xml version="1.0" encoding="UTF-8"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
      ),
      'EPUB/package.opf': _utf8(
        '<?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="pub-id">${_escape(id)}</dc:identifier><dc:title>${_escape(title)}</dc:title>${authors.map((a) => '<dc:creator>${_escape(a)}</dc:creator>').join()}<dc:language>${_escape(language)}</dc:language>${description.trim().isEmpty ? '' : '<dc:description>${_escape(description)}</dc:description>'}<meta property="dcterms:modified">${_modifiedNow()}</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="style" href="styles.css" media-type="text/css"/><item id="chapter-1" href="Text/chapter-1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter-1"/></spine></package>',
      ),
      'EPUB/nav.xhtml': _utf8(
        '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc" id="toc"><h1>Contents</h1><ol><li><a href="Text/chapter-1.xhtml">Chapter 1</a></li></ol></nav></body></html>',
      ),
      'EPUB/styles.css': _utf8(
        'body { line-height: 1.5; } img, svg { max-width: 100%; }\n',
      ),
      'EPUB/Text/chapter-1.xhtml': _utf8(
        _chapterXhtml('Chapter 1', '', stylesheet: '../styles.css'),
      ),
    };
    final result = EpubDocument.open(
      _writeZip({}, files, {}, limits),
      limits: limits,
    );
    result._revision = 1;
    return result;
  }

  /// Imports the reader's normalized, unencrypted publication representation.
  /// This is a new EPUB, not a round-trip save to MOBI/AZW3/FB2/CBZ.
  factory EpubDocument.fromPublication(
    Map<String, dynamic> payload, {
    EpubLimits limits = const EpubLimits(),
  }) {
    final metadata = payload['metadata'] is Map
        ? payload['metadata'] as Map
        : const {};
    final authorValue = metadata['authors'] ?? metadata['author'];
    final authors = authorValue is List
        ? authorValue
              .map((v) => v is Map ? '${v['name'] ?? ''}' : '$v')
              .where((s) => s.trim().isNotEmpty)
              .toList()
        : authorValue == null
        ? <String>[]
        : ['$authorValue'];
    final title = '${metadata['title'] ?? 'Imported book'}';
    final language = '${metadata['language'] ?? 'en'}';
    final description = '${metadata['description'] ?? ''}';
    final inputResources = payload['resources'];
    final order = payload['readingOrder'];
    if (inputResources is! List || order is! List || order.isEmpty) {
      throw const EpubException(
        'invalid_import',
        'The imported publication has no resources or reading order.',
      );
    }
    if (inputResources.length + 4 > limits.maxEntries) {
      throw const EpubException(
        'entry_limit',
        'The imported publication has too many resources.',
      );
    }
    final result = EpubDocument.create(
      title: title,
      authors: authors,
      language: language,
      description: description,
      limits: limits,
    );
    final files = <String, Uint8List>{};
    final types = <String, String>{};
    var total = 0;
    for (final resource in inputResources) {
      if (resource is! Map ||
          resource['href'] is! String ||
          resource['data'] is! String) {
        throw const EpubException(
          'invalid_import',
          'An imported resource is incomplete.',
        );
      }
      final resourcePath = _resolveLocal(
        'publication.opf',
        resource['href'] as String,
      );
      if (resourcePath == null ||
          resourcePath == 'mimetype' ||
          resourcePath.startsWith('META-INF/')) {
        throw const EpubException(
          'invalid_import',
          'An imported resource has an unsupported path.',
        );
      }
      if (files.containsKey(resourcePath)) {
        throw EpubException(
          'duplicate_path',
          'Duplicate imported resource.',
          path: resourcePath,
        );
      }
      final encoded = resource['data'] as String;
      final encoding = resource['encoding'] ?? 'base64';
      if (!{'base64', 'utf8', 'text'}.contains(encoding)) {
        throw const EpubException(
          'invalid_import',
          'Unsupported imported resource encoding.',
        );
      }
      if (encoded.length > limits.maxEntryBytes * 2) {
        throw EpubException(
          'entry_limit',
          'An imported resource is too large.',
          path: resourcePath,
        );
      }
      Uint8List bytes;
      try {
        bytes = encoding == 'base64' ? base64Decode(encoded) : _utf8(encoded);
      } on FormatException {
        throw EpubException(
          'invalid_import',
          'Invalid imported resource encoding.',
          path: resourcePath,
        );
      }
      var type = '${resource['mediaType'] ?? _mediaType(resourcePath)}';
      if (type == 'text/html' || type == 'application/xhtml+xml') {
        if (bytes.length > limits.maxTextBytes) {
          throw EpubException(
            'text_limit',
            'An imported chapter exceeds the text size limit.',
            path: resourcePath,
          );
        }
        final source = _decodeText(bytes, resourcePath);
        bytes = _utf8(_normaliseXhtml(source, title: title, limits: limits));
        type = 'application/xhtml+xml';
      }
      total += bytes.length;
      if (bytes.length > limits.maxEntryBytes ||
          total > limits.maxExpandedBytes) {
        throw const EpubException(
          'expanded_limit',
          'The imported publication exceeds its size limits.',
        );
      }
      files[resourcePath] = bytes;
      types[resourcePath] = type;
    }
    var packageName = 'crisp-package.opf';
    for (var i = 1; files.containsKey(packageName); i++) {
      packageName = 'crisp-package-$i.opf';
    }
    final package = result._package.copy();
    final manifest = _elements(package, 'manifest').first;
    final spine = _elements(package, 'spine').first;
    final importedIdentifier = metadata['identifier'];
    if (importedIdentifier is String && importedIdentifier.isNotEmpty) {
      final identifierElement = _elements(package, 'identifier').first;
      identifierElement.children
        ..clear()
        ..add(XmlText(importedIdentifier));
    }
    final importedMetadata = _elements(package, 'metadata').first;
    if (metadata['publisher'] is String) {
      importedMetadata.children.add(
        XmlElement(XmlName('publisher', 'dc'), [], [
          XmlText(metadata['publisher'] as String),
        ]),
      );
    }
    final layout = payload['layout'] ?? metadata['layout'];
    if (layout == 'pre-paginated' ||
        layout == 'fixed' ||
        layout == 'fixed-layout') {
      importedMetadata.children.add(
        XmlElement(
          XmlName('meta'),
          [XmlAttribute(XmlName('property'), 'rendition:layout')],
          [XmlText('pre-paginated')],
        ),
      );
    }
    final direction = payload['direction'];
    if (direction == 'rtl' || direction == 'ltr')
      spine.setAttribute('page-progression-direction', direction as String);
    manifest.children.clear();
    spine.children.clear();
    final ids = <String, String>{};
    var counter = 0;
    for (final entry in files.entries) {
      final id = 'resource-${++counter}';
      ids[entry.key] = id;
      manifest.children.add(
        XmlElement(XmlName('item'), [
          XmlAttribute(XmlName('id'), id),
          XmlAttribute(XmlName('href'), _encodedPath(entry.key)),
          XmlAttribute(XmlName('media-type'), types[entry.key]!),
        ]),
      );
    }
    final titles = <String, String>{};
    for (final chapter in order) {
      if (chapter is! Map || chapter['href'] is! String) {
        throw const EpubException(
          'invalid_import',
          'An imported chapter has no path.',
        );
      }
      final chapterPath = _resolveLocal(
        'publication.opf',
        chapter['href'] as String,
      );
      if (chapterPath == null ||
          ids[chapterPath] == null ||
          !{
            'application/xhtml+xml',
            'image/svg+xml',
          }.contains(types[chapterPath])) {
        throw const EpubException(
          'invalid_import',
          'An imported chapter is missing or not XHTML/SVG.',
        );
      }
      titles[chapterPath] =
          '${chapter['title'] ?? 'Chapter ${titles.length + 1}'}';
      spine.children.add(
        XmlElement(XmlName('itemref'), [
          XmlAttribute(XmlName('idref'), ids[chapterPath]!),
          if (chapter['linear'] == false || chapter['linear'] == 'no')
            XmlAttribute(XmlName('linear'), 'no'),
        ]),
      );
    }
    final coverHref =
        payload['coverHref'] ?? metadata['cover'] ?? payload['cover'];
    if (coverHref is String) {
      final cover = _resolveLocal('publication.opf', coverHref);
      for (final element in manifest.childElements) {
        if (element.getAttribute('id') == ids[cover] && ids[cover] != null) {
          element.setAttribute('properties', 'cover-image');
        }
      }
    }
    files[packageName] = _utf8(package.toXmlString());
    files['META-INF/container.xml'] = _utf8(
      '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="${_escape(packageName)}" media-type="application/oebps-package+xml"/></rootfiles></container>',
    );
    final imported = EpubDocument.open(
      _writeZip({}, files, {}, limits),
      limits: limits,
    );
    imported.sourceFormat = '${payload['sourceFormat'] ?? 'import'}';
    if (payload['warnings'] is List) {
      imported.importWarnings.addAll(
        (payload['warnings'] as List).map((v) => '$v'),
      );
    }
    imported.importWarnings.add(
      'Imported as a new EPUB; the original ${imported.sourceFormat.toUpperCase()} is unchanged.',
    );
    List<EpubTocEntry> parseToc(List values, int depth) {
      if (depth > 32)
        throw const EpubException(
          'toc_limit',
          'The imported contents tree is too deep.',
        );
      return values.whereType<Map>().map((item) {
        final href = '${item['href'] ?? ''}';
        final target = _resolveLocal('publication.opf', href);
        if (target == null || !files.containsKey(target)) {
          throw EpubException(
            'invalid_import',
            'An imported contents link has no local resource.',
            path: href,
          );
        }
        return EpubTocEntry(
          label:
              '${item['label'] ?? item['title'] ?? titles[target] ?? target}',
          href: _archiveHref(target, Uri.parse(href).fragment),
          children: item['children'] is List
              ? parseToc(item['children'] as List, depth + 1)
              : const [],
        );
      }).toList();
    }

    final toc = payload['toc'] is List && (payload['toc'] as List).isNotEmpty
        ? parseToc(payload['toc'] as List, 0)
        : titles.entries
              .map(
                (e) => EpubTocEntry(label: e.value, href: _encodedPath(e.key)),
              )
              .toList();
    imported.updateToc(toc);
    return imported;
  }

  int get revision => _revision;
  bool get dirty => _revision != _savedRevision;
  String get title => _metadataValue('title');
  List<String> get authors =>
      List.unmodifiable(_metadataElements('creator').map((e) => e.innerText));
  String get language => _metadataValue('language');
  String get description => _metadataValue('description');
  String get identifier {
    final selected = _package.rootElement.getAttribute('unique-identifier');
    final values = _metadataElements('identifier');
    for (final value in values) {
      if (value.getAttribute('id') == selected) return value.innerText;
    }
    return values.isEmpty ? '' : values.first.innerText;
  }

  String get version => _package.rootElement.getAttribute('version') ?? '';
  bool get fixedLayout => _elements(_package, 'meta').any(
    (e) =>
        e.getAttribute('property') == 'rendition:layout' &&
        e.innerText.trim() == 'pre-paginated',
  );

  EpubProtection get protection {
    if (_exists('META-INF/signatures.xml')) return EpubProtection.signed;
    final encryption = _encryption;
    if (encryption.entries.any(
      (e) => !_fontAlgorithms.contains(e.value) || !_isFontPath(e.key),
    ))
      return EpubProtection.drm;
    return encryption.isEmpty
        ? EpubProtection.none
        : EpubProtection.fontObfuscation;
  }

  bool get canEdit =>
      protection == EpubProtection.none ||
      protection == EpubProtection.fontObfuscation;

  List<EpubResource> get resources {
    final byPath = <String, _ManifestItem>{};
    for (final item in _manifest) {
      if (item.resourcePath != null) byPath[item.resourcePath!] = item;
    }
    final encrypted = _encryption;
    return List.unmodifiable(
      _paths.where((p) => !_directory(p)).map((p) {
        final item = byPath[p];
        return EpubResource(
          path: p,
          mediaType: item?.mediaType ?? _mediaType(p),
          size: _changed[p]?.length ?? _zip.members[p]?.size ?? 0,
          isEncrypted: encrypted.containsKey(p),
          isDirty: _changed.containsKey(p),
          id: item?.id,
          properties: Set.unmodifiable(item?.properties ?? const <String>{}),
        );
      }),
    );
  }

  List<EpubChapter> get chapters {
    final items = {for (final item in _manifest) item.id: item};
    final labels = <String, String>{};
    void collect(List<EpubTocEntry> entries) {
      for (final entry in entries) {
        final p = _resolveLocal('book.opf', entry.href);
        if (p != null) labels.putIfAbsent(p, () => entry.label);
        collect(entry.children);
      }
    }

    collect(toc);
    return List.unmodifiable(
      (_spineElement?.childElements ?? <XmlElement>[])
          .where((e) => e.name.local == 'itemref')
          .map((e) {
            final id = e.getAttribute('idref') ?? '';
            final item = items[id];
            final p = item?.resourcePath ?? '';
            return EpubChapter(
              id: id,
              path: p,
              title: labels[p] ?? _chapterTitle(p),
              linear: e.getAttribute('linear') != 'no',
            );
          }),
    );
  }

  List<EpubTocEntry> get toc {
    try {
      final nav = _navigationPath;
      if (nav != null && _exists(nav)) {
        final document = _xml(nav);
        final navs = _elements(document, 'nav');
        final selected = navs
            .where(
              (e) =>
                  _attribute(e, 'type').split(RegExp(r'\s+')).contains('toc'),
            )
            .toList();
        if (selected.isNotEmpty) {
          List<EpubTocEntry> parseList(XmlElement list) =>
              list.childElements.where((e) => e.name.local == 'li').map((li) {
                final links = li.childElements
                    .where((e) => e.name.local == 'a' || e.name.local == 'span')
                    .toList();
                final nested = li.childElements
                    .where((e) => e.name.local == 'ol')
                    .toList();
                final children = nested.isEmpty
                    ? <EpubTocEntry>[]
                    : parseList(nested.first);
                final link = links.isEmpty ? null : links.first;
                final href = link?.getAttribute('href');
                final target = href == null ? null : _resolveLocal(nav, href);
                return EpubTocEntry(
                  label: link?.innerText ?? '',
                  href: target == null
                      ? ''
                      : _archiveHref(target, Uri.parse(href!).fragment),
                  children: children,
                );
              }).toList();
          final lists = selected.first.childElements.where(
            (e) => e.name.local == 'ol',
          );
          if (lists.isNotEmpty)
            return List.unmodifiable(parseList(lists.first));
        }
      }
      final ncx = _ncxPath;
      if (ncx != null && _exists(ncx)) {
        final document = _xml(ncx);
        List<EpubTocEntry> parsePoints(XmlElement parent) => parent
            .childElements
            .where((e) => e.name.local == 'navPoint')
            .map((point) {
              final content = point.childElements
                  .where((e) => e.name.local == 'content')
                  .firstOrNull;
              final href = content?.getAttribute('src') ?? '';
              final target = _resolveLocal(ncx, href);
              return EpubTocEntry(
                label: _elements(point, 'text').firstOrNull?.innerText ?? '',
                href: target == null
                    ? ''
                    : _archiveHref(target, Uri.parse(href).fragment),
                children: parsePoints(point),
              );
            })
            .toList();
        final navMap = _elements(document, 'navMap').firstOrNull;
        if (navMap != null) return List.unmodifiable(parsePoints(navMap));
      }
    } on EpubException {
      // Invalid drafts stay editable; validate() reports the actual issue.
    }
    return const [];
  }

  String? get coverPath {
    final manifest = _manifest;
    for (final item in manifest) {
      if (item.properties.contains('cover-image')) return item.resourcePath;
    }
    final coverId = _elements(_package, 'meta')
        .where((e) => e.getAttribute('name') == 'cover')
        .firstOrNull
        ?.getAttribute('content');
    return manifest.where((e) => e.id == coverId).firstOrNull?.resourcePath;
  }

  Uint8List? get coverBytes =>
      coverPath == null || !_exists(coverPath!) ? null : readBytes(coverPath!);

  Uint8List readBytes(String resourcePath) {
    _safeArchivePath(resourcePath);
    if (!_exists(resourcePath) || _directory(resourcePath)) {
      throw EpubException(
        'missing_resource',
        'The ebook resource does not exist.',
        path: resourcePath,
      );
    }
    final change = _changed[resourcePath];
    return change == null
        ? _zip.members[resourcePath]!.read()
        : Uint8List.fromList(change);
  }

  String readText(String resourcePath) {
    final size =
        _changed[resourcePath]?.length ?? _zip.members[resourcePath]?.size ?? 0;
    if (size > limits.maxTextBytes) {
      throw EpubException(
        'text_limit',
        'The text resource exceeds the editor limit.',
        path: resourcePath,
      );
    }
    return _decodeText(readBytes(resourcePath), resourcePath);
  }

  /// Returns a display copy of standard obfuscated fonts, never changing their
  /// stored bytes or publication identifier. Other encryption is not decoded.
  Uint8List readDecodedBytes(String resourcePath) {
    final bytes = readBytes(resourcePath);
    final algorithm = _encryption[resourcePath];
    if (algorithm == null) return bytes;
    if (identifier != _fontIdentifier) {
      throw const EpubException(
        'font_identifier_changed',
        'Changing the publication identifier would break its obfuscated fonts.',
      );
    }
    List<int> key;
    int count;
    if (algorithm == _idpfObfuscation) {
      key = crypto.sha1
          .convert(utf8.encode(identifier.replaceAll(RegExp(r'[ \t\r\n]'), '')))
          .bytes;
      count = 1040;
    } else if (algorithm == _adobeObfuscation) {
      final uuid = identifier
          .replaceFirst(RegExp(r'^urn:uuid:', caseSensitive: false), '')
          .replaceAll('-', '');
      if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uuid)) {
        throw EpubException(
          'font_identifier',
          'The Adobe-obfuscated font has no UUID publication identifier.',
          path: resourcePath,
        );
      }
      key = List.generate(
        16,
        (i) => int.parse(uuid.substring(i * 2, i * 2 + 2), radix: 16),
      );
      count = 1024;
    } else {
      throw EpubException(
        'drm',
        'This resource is protected by unsupported encryption.',
        path: resourcePath,
      );
    }
    for (var i = 0; i < count && i < bytes.length; i++) {
      bytes[i] ^= key[i % key.length];
    }
    return bytes;
  }

  void updateText(String resourcePath, String text) => _transaction(() {
    _assertEditable();
    _safeArchivePath(resourcePath);
    if (!_exists(resourcePath)) {
      throw EpubException(
        'missing_resource',
        'The ebook resource does not exist.',
        path: resourcePath,
      );
    }
    final bytes = _utf8(_utf8Declaration(text));
    if (bytes.length > limits.maxTextBytes) {
      throw EpubException(
        'text_limit',
        'The text resource exceeds the editor limit.',
        path: resourcePath,
      );
    }
    if (_bytesEqual(bytes, readBytes(resourcePath))) return;
    if (_encryption.containsKey(resourcePath)) {
      throw EpubException(
        'encrypted_resource',
        'An obfuscated or encrypted resource cannot be edited as plain text.',
        path: resourcePath,
      );
    }
    if (resourcePath == 'META-INF/container.xml' ||
        resourcePath == 'mimetype' ||
        resourcePath == 'META-INF/encryption.xml' ||
        resourcePath == 'META-INF/signatures.xml') {
      throw EpubException(
        'protected_resource',
        'This package control resource cannot be edited directly.',
        path: resourcePath,
      );
    }
    _put(resourcePath, bytes);
    if (resourcePath == packagePath) {
      try {
        _package = _parseXml(text, resourcePath, limits);
        _packageParseError = _package.rootElement.name.local == 'package'
            ? null
            : 'The package root must be package.';
      } on EpubException catch (e) {
        _packageParseError = e.message;
      }
    }
    if (_packageParseError == null && version.startsWith('3')) {
      // EPUB 3 identifies a revision by its publication ID and modified time,
      // including revisions that change only a chapter or stylesheet.
      _storePackage();
    } else {
      _touch();
    }
  });

  void updateMetadata({
    String? title,
    List<String>? authors,
    String? language,
    String? description,
  }) => _transaction(() {
    _assertStructure();
    if (title != null && title.trim().isEmpty) {
      throw const EpubException(
        'metadata_title',
        'The book title must not be empty.',
      );
    }
    if (language != null && !_validLanguage(language)) {
      throw const EpubException(
        'metadata_language',
        'Enter a language tag such as en, de or en-GB.',
      );
    }
    if (authors != null && authors.any((author) => author.trim().isEmpty)) {
      throw const EpubException(
        'metadata_author',
        'An author must have a name; use an empty list for an unknown author.',
      );
    }
    final metadata = _metadataElement!;
    metadata.setAttribute('xmlns:dc', 'http://purl.org/dc/elements/1.1/');
    void setFirst(String name, String value) {
      final existing = _metadataElements(name);
      if (existing.isNotEmpty) {
        existing.first.children
          ..clear()
          ..add(XmlText(value));
      } else {
        metadata.children.add(
          XmlElement(XmlName(name, 'dc'), [], [XmlText(value)]),
        );
      }
    }

    void removeValue(XmlElement value) {
      final id = value.getAttribute('id');
      value.parent?.children.remove(value);
      if (id != null) {
        for (final refinement in _elements(
          metadata,
          'meta',
        ).where((e) => e.getAttribute('refines') == '#$id').toList()) {
          refinement.parent?.children.remove(refinement);
        }
      }
    }

    if (title != null) setFirst('title', title);
    if (language != null) setFirst('language', language);
    if (description != null) {
      if (description.trim().isEmpty) {
        // Dublin Core elements cannot contain an empty string. An omitted
        // optional value is represented by the absence of its element.
        for (final value in _metadataElements('description')) {
          removeValue(value);
        }
      } else {
        setFirst('description', description);
      }
    }
    if (authors != null) {
      final previous = _metadataElements('creator');
      for (var i = 0; i < authors.length; i++) {
        if (i < previous.length) {
          previous[i].children
            ..clear()
            ..add(XmlText(authors[i]));
        } else {
          metadata.children.add(
            XmlElement(XmlName('creator', 'dc'), [], [XmlText(authors[i])]),
          );
        }
      }
      for (var i = authors.length; i < previous.length; i++) {
        removeValue(previous[i]);
      }
    }
    _storePackage();
  });

  void replaceResource(
    String resourcePath,
    Uint8List bytes, {
    String? mediaType,
  }) => _transaction(() {
    _assertStructure();
    _safeArchivePath(resourcePath);
    if (!_exists(resourcePath)) {
      throw EpubException(
        'missing_resource',
        'Use addResource to add a new resource.',
        path: resourcePath,
      );
    }
    if (resourcePath == packagePath ||
        resourcePath == 'mimetype' ||
        resourcePath.startsWith('META-INF/')) {
      throw EpubException(
        'protected_resource',
        'This package resource cannot be replaced as binary data.',
        path: resourcePath,
      );
    }
    if (_encryption.containsKey(resourcePath)) {
      throw EpubException(
        'encrypted_resource',
        'Replacing an obfuscated/encrypted resource requires an explicit re-encoding workflow.',
        path: resourcePath,
      );
    }
    _put(resourcePath, bytes);
    if (mediaType != null) {
      for (final item in _manifest.where(
        (i) => i.resourcePath == resourcePath,
      )) {
        item.element.setAttribute('media-type', mediaType);
      }
    }
    _storePackage();
  });

  EpubResource addResource(
    String resourcePath,
    Uint8List bytes, {
    String? mediaType,
  }) => _transaction(() {
    _assertStructure();
    _safeArchivePath(resourcePath);
    if (_exists(resourcePath) ||
        resourcePath == 'mimetype' ||
        resourcePath.startsWith('META-INF/')) {
      throw EpubException(
        'duplicate_path',
        'The resource path already exists or is reserved.',
        path: resourcePath,
      );
    }
    final type = mediaType ?? _mediaType(resourcePath);
    _put(resourcePath, bytes);
    _manifestElement!.children.add(
      XmlElement(XmlName('item'), [
        XmlAttribute(XmlName('id'), _newId('resource')),
        XmlAttribute(XmlName('href'), _relativeHref(packagePath, resourcePath)),
        XmlAttribute(XmlName('media-type'), type),
      ]),
    );
    _storePackage();
    return resources.firstWhere((r) => r.path == resourcePath);
  });

  void replaceCover(Uint8List bytes, {String mediaType = 'image/jpeg'}) =>
      _transaction(() {
        _assertStructure();
        if (!{
          'image/jpeg',
          'image/png',
          'image/svg+xml',
          'image/gif',
          'image/webp',
        }.contains(mediaType)) {
          throw const EpubException(
            'cover_type',
            'Choose a supported image for the book cover.',
          );
        }
        final existing = coverPath;
        if (existing != null && _exists(existing)) {
          replaceResource(existing, bytes, mediaType: mediaType);
          return;
        }
        final extension = {
          'image/jpeg': 'jpg',
          'image/png': 'png',
          'image/svg+xml': 'svg',
          'image/gif': 'gif',
          'image/webp': 'webp',
        }[mediaType]!;
        final p = _unusedPath(
          path.posix.join(
            path.posix.dirname(packagePath),
            'Images',
            'cover.$extension',
          ),
        );
        final resource = addResource(p, bytes, mediaType: mediaType);
        final item = _manifest.firstWhere((i) => i.id == resource.id);
        if (version.startsWith('3'))
          item.element.setAttribute('properties', 'cover-image');
        final oldMeta = _elements(
          _package,
          'meta',
        ).where((e) => e.getAttribute('name') == 'cover').firstOrNull;
        if (oldMeta != null) {
          oldMeta.setAttribute('content', item.id);
        } else {
          _metadataElement!.children.add(
            XmlElement(XmlName('meta'), [
              XmlAttribute(XmlName('name'), 'cover'),
              XmlAttribute(XmlName('content'), item.id),
            ]),
          );
        }
        _storePackage();
      });

  EpubChapter addChapter({
    required String title,
    String? text,
    String? xhtml,
    int? index,
  }) => _transaction(() {
    _assertStructure();
    final before = chapters;
    final at = index ?? before.length;
    if (at < 0 || at > before.length)
      throw RangeError.index(at, before, 'index');
    final p = _unusedPath(
      path.posix.join(path.posix.dirname(packagePath), 'Text', 'chapter.xhtml'),
    );
    final content = xhtml ?? _chapterXhtml(title, text ?? '');
    final parsed = _parseXml(content, p, limits);
    if (parsed.rootElement.name.local != 'html') {
      throw const EpubException(
        'invalid_chapter',
        'A chapter must be a complete XHTML document.',
      );
    }
    final resource = addResource(
      p,
      _utf8(_utf8Declaration(content)),
      mediaType: 'application/xhtml+xml',
    );
    final spine = _spineElement!;
    final references = spine.childElements
        .where((e) => e.name.local == 'itemref')
        .toList();
    final entry = XmlElement(XmlName('itemref'), [
      XmlAttribute(XmlName('idref'), resource.id!),
    ]);
    if (at == references.length) {
      spine.children.add(entry);
    } else {
      spine.children.insert(spine.children.indexOf(references[at]), entry);
    }
    _storePackage();
    final entries = toc.toList();
    entries.insert(
      at <= entries.length ? at : entries.length,
      EpubTocEntry(label: title, href: _encodedPath(p)),
    );
    updateToc(entries);
    return chapters.firstWhere((c) => c.id == resource.id);
  });

  /// Removes the chapter from reading order and contents. By default the XHTML
  /// resource remains in the manifest so existing hyperlinks do not break.
  /// Deleting its bytes is explicit and is refused while other resources link it.
  void removeChapter(
    String id, {
    bool deleteResource = false,
  }) => _transaction(() {
    _assertStructure();
    final list = chapters;
    if (list.length <= 1)
      throw const EpubException(
        'last_chapter',
        'A book must retain at least one chapter.',
      );
    final chapter = list.where((c) => c.id == id).firstOrNull;
    if (chapter == null)
      throw const EpubException(
        'missing_chapter',
        'The chapter does not exist.',
      );
    final entries = _withoutTocPath(toc, chapter.path);
    if (deleteResource) {
      final refs = _findReferencesTo(
        chapter.path,
        excluding: {
          chapter.path,
          _navigationPath,
          _ncxPath,
        }.whereType<String>().toSet(),
      );
      if (refs.isNotEmpty)
        throw EpubException(
          'referenced_resource',
          'Other resources still link to this chapter; remove it from reading order or repair those links first.',
          path: refs.first,
        );
    }
    for (final element
        in _spineElement!.childElements
            .where((e) => e.getAttribute('idref') == id)
            .toList()) {
      _spineElement!.children.remove(element);
    }
    if (deleteResource) {
      for (final item in _manifest.where((i) => i.id == id).toList()) {
        _manifestElement!.children.remove(item.element);
      }
      _removed.add(chapter.path);
      _changed.remove(chapter.path);
    }
    _storePackage();
    updateToc(entries);
  });

  void moveChapter(String id, int newIndex) => _transaction(() {
    _assertStructure();
    final spine = _spineElement!;
    final refs = spine.childElements
        .where((e) => e.name.local == 'itemref')
        .toList();
    if (newIndex < 0 || newIndex >= refs.length)
      throw RangeError.index(newIndex, refs, 'newIndex');
    final old = refs.indexWhere((e) => e.getAttribute('idref') == id);
    if (old < 0)
      throw const EpubException(
        'missing_chapter',
        'The chapter does not exist.',
      );
    if (old == newIndex) return;
    final moving = refs.removeAt(old);
    refs.insert(newIndex, moving);
    final positions = spine.children
        .asMap()
        .entries
        .where(
          (e) =>
              e.value is XmlElement &&
              (e.value as XmlElement).name.local == 'itemref',
        )
        .map((e) => e.key)
        .toList();
    for (final node in refs) spine.children.remove(node);
    for (var i = 0; i < refs.length; i++) {
      final position = positions[i] <= spine.children.length
          ? positions[i]
          : spine.children.length;
      spine.children.insert(position, refs[i]);
    }
    _storePackage();
    // Preserve nested/user-authored contents rather than flattening them when
    // reading order changes. updateToc() is an explicit regeneration command.
  });

  void updateToc([List<EpubTocEntry>? entries]) => _transaction(() {
    _assertStructure();
    final contents =
        entries ??
        chapters
            .map(
              (c) => EpubTocEntry(label: c.title, href: _encodedPath(c.path)),
            )
            .toList();
    var nodeCount = 0;
    void check(List<EpubTocEntry> values, int depth) {
      if (depth > 32)
        throw const EpubException(
          'toc_limit',
          'The contents tree is too deep.',
        );
      for (final entry in values) {
        if (++nodeCount > limits.maxEntries)
          throw const EpubException(
            'toc_limit',
            'The contents tree is too large.',
          );
        if (entry.href.isNotEmpty) {
          final target = _resolveLocal('book.opf', entry.href);
          if (target == null || !_exists(target))
            throw EpubException(
              'toc_target',
              'The contents link has no local resource.',
              path: entry.href,
            );
        } else if (entry.children.isEmpty) {
          throw const EpubException(
            'toc_target',
            'A contents entry needs a link or children.',
          );
        }
        check(entry.children, depth + 1);
      }
    }

    check(contents, 0);
    if (version.startsWith('3')) {
      var navPath = _navigationPath;
      if (navPath == null) {
        navPath = _unusedPath(
          path.posix.join(path.posix.dirname(packagePath), 'nav.xhtml'),
        );
        _manifestElement!.children.add(
          XmlElement(XmlName('item'), [
            XmlAttribute(XmlName('id'), _newId('nav')),
            XmlAttribute(XmlName('href'), _relativeHref(packagePath, navPath)),
            XmlAttribute(XmlName('media-type'), 'application/xhtml+xml'),
            XmlAttribute(XmlName('properties'), 'nav'),
          ]),
        );
      }
      XmlDocument nav;
      if (_exists(navPath)) {
        nav = _xml(navPath);
      } else {
        nav = _parseXml(_chapterXhtml('Contents', ''), navPath, limits);
      }
      nav.rootElement.setAttribute(
        'xmlns:epub',
        'http://www.idpf.org/2007/ops',
      );
      final body = _elements(nav, 'body').firstOrNull;
      if (body == null)
        throw EpubException(
          'invalid_nav',
          'The navigation document has no body.',
          path: navPath,
        );
      final previous = _elements(nav, 'nav')
          .where(
            (e) => _attribute(e, 'type').split(RegExp(r'\s+')).contains('toc'),
          )
          .firstOrNull;
      final tocNode =
          previous ??
          XmlElement(XmlName('nav'), [
            XmlAttribute(XmlName('type', 'epub'), 'toc'),
            XmlAttribute(XmlName('id'), 'toc'),
          ]);
      if (previous == null) body.children.add(tocNode);
      final oldLists = tocNode.childElements
          .where((e) => e.name.local == 'ol')
          .toList();
      for (final list in oldLists) tocNode.children.remove(list);
      tocNode.children.add(_navList(contents, navPath));
      _put(navPath, _utf8(_utf8Declaration(nav.toXmlString())));
    }
    var ncxPath = _ncxPath;
    if (!version.startsWith('3') && ncxPath == null) {
      ncxPath = _unusedPath(
        path.posix.join(path.posix.dirname(packagePath), 'toc.ncx'),
      );
      final id = _newId('ncx');
      _manifestElement!.children.add(
        XmlElement(XmlName('item'), [
          XmlAttribute(XmlName('id'), id),
          XmlAttribute(XmlName('href'), _relativeHref(packagePath, ncxPath)),
          XmlAttribute(XmlName('media-type'), 'application/x-dtbncx+xml'),
        ]),
      );
      _spineElement!.setAttribute('toc', id);
    }
    if (ncxPath != null) {
      final ncx = _exists(ncxPath)
          ? _xml(ncxPath)
          : _parseXml(
              '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="${_escape(identifier)}"/></head><docTitle><text>${_escape(title)}</text></docTitle><navMap/></ncx>',
              ncxPath,
              limits,
            );
      final navMap = _elements(ncx, 'navMap').firstOrNull;
      if (navMap == null)
        throw EpubException(
          'invalid_ncx',
          'The NCX has no navigation map.',
          path: ncxPath,
        );
      navMap.children.clear();
      var order = 0;
      void addPoints(List<EpubTocEntry> values, XmlElement parent) {
        for (final entry in values) {
          final href = entry.href.isNotEmpty
              ? entry.href
              : _firstTocHref(entry.children);
          if (href == null) continue;
          final id = ++order;
          final point = XmlElement(
            XmlName('navPoint'),
            [
              XmlAttribute(XmlName('id'), 'nav-$id'),
              XmlAttribute(XmlName('playOrder'), '$id'),
            ],
            [
              XmlElement(XmlName('navLabel'), [], [
                XmlElement(XmlName('text'), [], [XmlText(entry.label)]),
              ]),
              XmlElement(XmlName('content'), [
                XmlAttribute(XmlName('src'), _tocRelative(ncxPath!, href)),
              ]),
            ],
          );
          parent.children.add(point);
          addPoints(entry.children, point);
        }
      }

      addPoints(contents, navMap);
      _put(ncxPath, _utf8(_utf8Declaration(ncx.toXmlString())));
    }
    _storePackage();
  });

  List<EpubProseBlock> readProse(String resourcePath) {
    final doc = _xml(resourcePath);
    final elements = _proseElements(doc);
    return List.unmodifiable(
      elements.asMap().entries.map(
        (e) => EpubProseBlock(
          index: e.key,
          tag: e.value.name.local,
          text: _proseText(e.value),
          editable: _plainProse(e.value),
          id: e.value.getAttribute('id'),
        ),
      ),
    );
  }

  /// Changes only a text-only block; nested formatting or embedded objects are
  /// protected, not silently flattened. [expectedText] guards a stale UI edit.
  void updateProseBlock(
    String resourcePath,
    int index,
    String text, {
    String? expectedText,
  }) {
    _assertStructure();
    if (fixedLayout)
      throw const EpubException(
        'fixed_layout',
        'Use source editing for fixed-layout books.',
      );
    final doc = _xml(resourcePath);
    final elements = _proseElements(doc);
    if (index < 0 || index >= elements.length)
      throw RangeError.index(index, elements, 'index');
    final block = elements[index];
    if (!_plainProse(block))
      throw const EpubException(
        'complex_prose',
        'This block contains formatting or embedded content; edit its source.',
      );
    if (expectedText != null && _proseText(block) != expectedText) {
      throw const EpubException(
        'stale_edit',
        'This paragraph changed after the editor was opened.',
      );
    }
    block.children.clear();
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i != 0) block.children.add(XmlElement(XmlName('br')));
      block.children.add(XmlText(lines[i]));
    }
    updateText(resourcePath, doc.toXmlString());
  }

  /// Independent undo checkpoint, including invalid source drafts. The immutable
  /// original ZIP is shared; editable byte buffers and XML trees are copied.
  EpubDocument snapshot() {
    final copy = EpubDocument._(_zip, limits)
      ..packagePath = packagePath
      .._package = _package.copy()
      .._fontIdentifier = _fontIdentifier
      .._packageParseError = _packageParseError
      .._revision = _revision
      .._savedRevision = _savedRevision
      ..sourceFormat = sourceFormat;
    copy._changed.addAll(
      _changed.map((k, v) => MapEntry(k, Uint8List.fromList(v))),
    );
    copy._removed.addAll(_removed);
    copy.importWarnings.addAll(importWarnings);
    return copy;
  }

  /// Call only after the host successfully commits the bytes from [toBytes]. A
  /// delayed completion cannot clear edits made after that serialization.
  bool markSaved({int? revision}) {
    final saved = revision ?? _serializedRevision;
    if (saved == null ||
        saved != _revision ||
        saved != _serializedRevision ||
        _serializedBytes == null)
      return false;
    _zip = _ZipContainer.open(_serializedBytes!, limits);
    _changed.clear();
    _removed.clear();
    _savedRevision = saved;
    _fontIdentifier = identifier;
    return true;
  }

  Uint8List toBytes() {
    if (!dirty) return Uint8List.fromList(_zip.bytes);
    _assertEditable();
    final errors = validate().where((i) => i.isError).toList();
    if (errors.isNotEmpty)
      throw EpubException(
        'invalid_epub',
        errors.first.message,
        path: errors.first.path,
      );
    final bytes = _writeZip(
      _zip.members,
      _changed,
      _removed,
      limits,
      archiveComment: _zip.comment,
    );
    _serializedRevision = _revision;
    _serializedBytes = bytes;
    return Uint8List.fromList(bytes);
  }

  /// Assets are a bounded display copy. Fonts are decoded for the reader while
  /// their original obfuscated bytes remain in the editing document.
  Map<String, dynamic> toPublication() {
    if (protection == EpubProtection.drm)
      throw const EpubException(
        'drm',
        'Encrypted books need a compatible licensed reading system.',
      );
    return {
      'schemaVersion': 1,
      'sourceFormat': 'epub',
      'metadata': {
        'title': title,
        'authors': authors,
        'language': language,
        'description': description,
        'identifier': identifier,
        'publisher': _metadataValue('publisher'),
        'layout': fixedLayout ? 'pre-paginated' : 'reflowable',
        if (coverPath != null) 'cover': _encodedPath(coverPath!),
      },
      'direction':
          _spineElement?.getAttribute('page-progression-direction') ?? 'ltr',
      'layout': fixedLayout ? 'pre-paginated' : 'reflowable',
      if (coverPath != null) 'coverHref': _encodedPath(coverPath!),
      'readingOrder': chapters
          .map(
            (c) => {
              'href': _encodedPath(c.path),
              'title': c.title,
              'linear': c.linear,
            },
          )
          .toList(),
      'toc': toc.map((e) => e.toJson()).toList(),
      'resources': resources
          .where(
            (r) =>
                r.path != 'mimetype' &&
                !r.path.startsWith('META-INF/') &&
                r.path != packagePath,
          )
          .map(
            (r) => {
              'href': _encodedPath(r.path),
              'mediaType': r.mediaType,
              'encoding': 'base64',
              'data': base64Encode(readDecodedBytes(r.path)),
            },
          )
          .toList(),
      'warnings': importWarnings.toList(),
    };
  }

  List<EpubIssue> validate() {
    final issues = <EpubIssue>[];
    void error(String code, String message, [String? p]) =>
        issues.add(EpubIssue(EpubIssueSeverity.error, code, message, path: p));
    void warning(String code, String message, [String? p]) => issues.add(
      EpubIssue(EpubIssueSeverity.warning, code, message, path: p),
    );
    if (_packageParseError != null) {
      error('invalid_package', _packageParseError!, packagePath);
      return issues;
    }
    if (protection == EpubProtection.fontObfuscation &&
        identifier != _fontIdentifier) {
      error(
        'font_identifier_changed',
        'Restore the original publication identifier to preserve obfuscated fonts.',
        packagePath,
      );
    }
    if (!canEdit)
      warning(
        'protected_book',
        protection == EpubProtection.signed
            ? 'Digital signatures prevent editing without invalidating the signature.'
            : 'The book uses unsupported encryption.',
      );
    if (title.trim().isEmpty)
      error('metadata_title', 'The book needs a title.', packagePath);
    if (!_validLanguage(language))
      error(
        'metadata_language',
        'The book needs a valid language tag.',
        packagePath,
      );
    if (identifier.trim().isEmpty)
      error(
        'metadata_identifier',
        'The book needs a publication identifier.',
        packagePath,
      );
    for (final value in _metadataElement?.childElements ?? <XmlElement>[]) {
      if (value.namespaceUri == 'http://purl.org/dc/elements/1.1/' &&
          value.innerText.trim().isEmpty) {
        error(
          'empty_metadata',
          'The dc:${value.name.local} metadata value must not be empty; remove optional empty values.',
          packagePath,
        );
      }
    }
    final selectedId = _package.rootElement.getAttribute('unique-identifier');
    if (selectedId == null ||
        !_metadataElements(
          'identifier',
        ).any((e) => e.getAttribute('id') == selectedId))
      error(
        'metadata_identifier',
        'The unique-identifier must reference an existing dc:identifier.',
        packagePath,
      );
    if (_manifestElement == null || _spineElement == null) {
      error(
        'invalid_package',
        'The package needs a manifest and spine.',
        packagePath,
      );
      return issues;
    }
    final items = _manifest;
    final ids = <String>{};
    final declaredPaths = <String>{};
    for (final item in items) {
      if (item.href.isEmpty) {
        error(
          'manifest_href',
          'A manifest item needs a resource href.',
          packagePath,
        );
      }
      if (item.id.isEmpty || !ids.add(item.id))
        error(
          'duplicate_id',
          'Manifest IDs must be present and unique.',
          packagePath,
        );
      if (item.resourcePath == null) {
        warning(
          'remote_resource',
          'A manifest resource requires network access: ${item.href}',
          packagePath,
        );
      } else if (!_exists(item.resourcePath!)) {
        error(
          'missing_resource',
          'A manifest resource is missing.',
          item.resourcePath,
        );
      } else if (!declaredPaths.add(item.resourcePath!)) {
        error(
          'duplicate_resource',
          'Multiple manifest items point to the same resource.',
          item.resourcePath,
        );
      }
      if (item.mediaType.isEmpty)
        error(
          'media_type',
          'A manifest resource needs a media type.',
          item.resourcePath,
        );
    }
    final refs = _spineElement!.childElements
        .where((e) => e.name.local == 'itemref')
        .toList();
    if (refs.isEmpty || !refs.any((e) => e.getAttribute('linear') != 'no'))
      error(
        'empty_spine',
        'The book needs at least one linear chapter.',
        packagePath,
      );
    final spineIds = <String>{};
    for (final ref in refs) {
      final id = ref.getAttribute('idref');
      if (!ids.contains(id))
        error(
          'spine_target',
          'A spine reference has no manifest item.',
          packagePath,
        );
      if (id != null && !spineIds.add(id))
        warning(
          'duplicate_spine',
          'A resource occurs more than once in reading order.',
          packagePath,
        );
    }
    if (version.startsWith('3') && _navigationPath == null)
      error('missing_nav', 'EPUB 3 needs a navigation document.', packagePath);
    if (version.startsWith('2') && _ncxPath == null)
      error(
        'missing_ncx',
        'EPUB 2 needs an NCX navigation document.',
        packagePath,
      );
    final targetIds = <String, Set<String>>{};
    Set<String> idsIn(XmlDocument doc) => doc.descendants
        .whereType<XmlElement>()
        .expand((e) => [e.getAttribute('id'), e.getAttribute('name')])
        .whereType<String>()
        .toSet();
    for (final resource in resources) {
      try {
        // CRC and declared output size are checked even for unknown resources.
        readBytes(resource.path);
        if (resource.isEncrypted) continue;
        if (resource.mediaType.endsWith('+xml') ||
            resource.mediaType == 'application/xml' ||
            resource.path.endsWith('.opf') ||
            resource.path.endsWith('.ncx') ||
            resource.path.endsWith('.xhtml')) {
          final doc = _xml(resource.path);
          targetIds[resource.path] = idsIn(doc);
          final localIds = <String>{};
          for (final element in doc.descendants.whereType<XmlElement>()) {
            final id = element.getAttribute('id');
            if (id != null && !localIds.add(id))
              error(
                'duplicate_element_id',
                'Duplicate element ID: $id',
                resource.path,
              );
            for (final attribute in element.attributes) {
              if (!{'src', 'href', 'poster'}.contains(attribute.name.local))
                continue;
              final href = attribute.value;
              if (href.isEmpty) continue;
              final target = _resolveLocal(resource.path, href);
              if (target == null) {
                final scheme = Uri.tryParse(href)?.scheme.toLowerCase();
                if (scheme == 'javascript' || scheme == 'file')
                  warning(
                    'unsafe_link',
                    'The reader blocks this link scheme.',
                    resource.path,
                  );
                continue;
              }
              if (!_exists(target)) {
                // OPF has idref/name attributes, not href links to non-resources.
                error(
                  'broken_reference',
                  'Missing link target: $href',
                  resource.path,
                );
              } else if (Uri.parse(href).fragment.isNotEmpty &&
                  (target.endsWith('.xhtml') ||
                      target.endsWith('.html') ||
                      target.endsWith('.svg'))) {
                final fragment = Uri.parse(href).fragment;
                try {
                  final available = targetIds.putIfAbsent(
                    target,
                    () => idsIn(_xml(target)),
                  );
                  if (!available.contains(fragment)) {
                    warning(
                      'missing_fragment',
                      'Link fragment not found: $href',
                      resource.path,
                    );
                  }
                } on EpubException {
                  /* Report the target's parse failure separately. */
                }
              }
            }
          }
        } else if (resource.mediaType == 'text/css') {
          for (final href in _cssReferences(readText(resource.path))) {
            final target = _resolveLocal(resource.path, href);
            if (target != null && !_exists(target))
              error(
                'broken_css_reference',
                'Missing stylesheet resource: $href',
                resource.path,
              );
          }
        }
      } on EpubException catch (e) {
        error(e.code, e.message, e.path ?? resource.path);
      }
    }
    if (fixedLayout)
      warning(
        'fixed_layout',
        'Fixed-layout books are available in source mode; visual prose editing is disabled.',
      );
    return List.unmodifiable(issues);
  }

  Iterable<String> get _paths => <String>{
    ..._zip.members.keys,
    ..._changed.keys,
  }.where((p) => !_removed.contains(p));
  bool _exists(String p) =>
      !_removed.contains(p) &&
      (_changed.containsKey(p) || _zip.members.containsKey(p));
  bool _directory(String p) => _zip.members[p]?.directory ?? false;
  XmlDocument _xml(String p) => _parseXml(readText(p), p, limits);
  XmlElement? get _metadataElement => _package.rootElement.childElements
      .where((e) => e.name.local == 'metadata')
      .firstOrNull;
  XmlElement? get _manifestElement => _package.rootElement.childElements
      .where((e) => e.name.local == 'manifest')
      .firstOrNull;
  XmlElement? get _spineElement => _package.rootElement.childElements
      .where((e) => e.name.local == 'spine')
      .firstOrNull;
  List<XmlElement> _metadataElements(String name) =>
      _metadataElement?.childElements
          .where(
            (e) =>
                e.name.local == name &&
                (e.namespaceUri == 'http://purl.org/dc/elements/1.1/' ||
                    e.name.prefix == 'dc'),
          )
          .toList() ??
      [];
  String _metadataValue(String name) =>
      _metadataElements(name).firstOrNull?.innerText ?? '';
  List<_ManifestItem> get _manifest =>
      (_manifestElement?.childElements ?? <XmlElement>[])
          .where((e) => e.name.local == 'item')
          .map((e) {
            final href = e.getAttribute('href') ?? '';
            String? p;
            try {
              p = href.isEmpty ? null : _resolveLocal(packagePath, href);
            } on EpubException {
              p = null;
            }
            return _ManifestItem(
              e.getAttribute('id') ?? '',
              href,
              p,
              e.getAttribute('media-type') ?? '',
              (e.getAttribute('properties') ?? '')
                  .split(RegExp(r'\s+'))
                  .where((s) => s.isNotEmpty)
                  .toSet(),
              e,
            );
          })
          .toList();
  String? get _navigationPath => _manifest
      .where((i) => i.properties.contains('nav'))
      .firstOrNull
      ?.resourcePath;
  String? get _ncxPath {
    final id = _spineElement?.getAttribute('toc');
    return _manifest.where((i) => i.id == id).firstOrNull?.resourcePath ??
        _manifest
            .where((i) => i.mediaType == 'application/x-dtbncx+xml')
            .firstOrNull
            ?.resourcePath;
  }

  Map<String, String> get _encryption {
    if (!_exists('META-INF/encryption.xml')) return const {};
    try {
      final result = <String, String>{};
      for (final entry in _elements(
        _xml('META-INF/encryption.xml'),
        'EncryptedData',
      )) {
        final algorithm =
            _elements(
              entry,
              'EncryptionMethod',
            ).firstOrNull?.getAttribute('Algorithm') ??
            'unknown';
        final href = _elements(
          entry,
          'CipherReference',
        ).firstOrNull?.getAttribute('URI');
        if (href == null) {
          result['?'] = 'unknown';
          continue;
        }
        final p = _resolveLocal('root.xml', href);
        if (p != null) result[p] = algorithm;
      }
      return result.isEmpty ? {'?': 'unknown'} : result;
    } on EpubException {
      return const {'?': 'unknown'};
    }
  }

  void _assertEditable() {
    if (!canEdit)
      throw EpubException(
        protection == EpubProtection.signed ? 'signed_book' : 'drm',
        protection == EpubProtection.signed
            ? 'Editing would invalidate this ebook’s digital signature.'
            : 'This ebook contains unsupported encrypted content.',
      );
  }

  bool _isFontPath(String p) {
    final item = _manifest.where((i) => i.resourcePath == p).firstOrNull;
    final type = item?.mediaType ?? _mediaType(p);
    return _exists(p) &&
        (type.startsWith('font/') ||
            {
              'application/vnd.ms-opentype',
              'application/x-font-ttf',
              'application/font-sfnt',
              'application/font-woff',
            }.contains(type));
  }

  T _transaction<T>(T Function() operation) {
    final previous = snapshot();
    final serializedRevision = _serializedRevision;
    final serializedBytes = _serializedBytes;
    try {
      return operation();
    } catch (_) {
      _package = previous._package;
      _packageParseError = previous._packageParseError;
      _changed
        ..clear()
        ..addAll(previous._changed);
      _removed
        ..clear()
        ..addAll(previous._removed);
      _revision = previous._revision;
      _savedRevision = previous._savedRevision;
      _serializedRevision = serializedRevision;
      _serializedBytes = serializedBytes;
      rethrow;
    }
  }

  void _assertStructure() {
    _assertEditable();
    if (_packageParseError != null ||
        _metadataElement == null ||
        _manifestElement == null ||
        _spineElement == null)
      throw const EpubException(
        'invalid_package',
        'Repair the package source before changing book structure.',
      );
  }

  void _touch() {
    _revision++;
    _serializedRevision = null;
    _serializedBytes = null;
  }

  void _put(String p, Uint8List bytes) {
    _safeArchivePath(p);
    if (bytes.length > limits.maxEntryBytes)
      throw EpubException(
        'entry_limit',
        'The resource exceeds the size limit.',
        path: p,
      );
    var total = bytes.length;
    var count = _exists(p) ? 0 : 1;
    for (final other in _paths) {
      count++;
      if (other != p)
        total += _changed[other]?.length ?? _zip.members[other]?.size ?? 0;
    }
    if (total > limits.maxExpandedBytes || count > limits.maxEntries)
      throw const EpubException(
        'expanded_limit',
        'The edited book exceeds its resource limits.',
      );
    _changed[p] = Uint8List.fromList(bytes);
    _removed.remove(p);
  }

  void _storePackage() {
    if (version.startsWith('3')) {
      final metadata = _metadataElement;
      if (metadata != null) {
        final modified = metadata.childElements
            .where(
              (e) =>
                  e.name.local == 'meta' &&
                  e.getAttribute('property') == 'dcterms:modified',
            )
            .firstOrNull;
        if (modified != null) {
          modified.children
            ..clear()
            ..add(XmlText(_modifiedNow()));
        } else {
          metadata.children.add(
            XmlElement(
              XmlName('meta'),
              [XmlAttribute(XmlName('property'), 'dcterms:modified')],
              [XmlText(_modifiedNow())],
            ),
          );
        }
      }
    }
    _put(packagePath, _utf8(_utf8Declaration(_package.toXmlString())));
    _touch();
  }

  String _newId(String prefix) {
    final ids = _package.descendants
        .whereType<XmlElement>()
        .map((e) => e.getAttribute('id'))
        .whereType<String>()
        .toSet();
    var i = 1;
    while (ids.contains('$prefix-$i')) {
      i++;
    }
    return '$prefix-$i';
  }

  String _unusedPath(String desired) {
    desired = path.posix.normalize(desired);
    if (!_exists(desired)) return desired;
    final extension = path.posix.extension(desired);
    final stem = desired.substring(0, desired.length - extension.length);
    var i = 2;
    while (_exists('$stem-$i$extension')) {
      i++;
    }
    return '$stem-$i$extension';
  }

  String _chapterTitle(String p) {
    if (p.isEmpty) return 'Missing chapter';
    try {
      final xml = _xml(p);
      final heading = xml.descendants
          .whereType<XmlElement>()
          .where((e) => {'h1', 'h2', 'title'}.contains(e.name.local))
          .firstOrNull;
      if (heading != null && heading.innerText.trim().isNotEmpty)
        return heading.innerText.trim();
    } on EpubException {
      /* The source editor can repair an invalid chapter. */
    }
    return path.posix.basenameWithoutExtension(p);
  }

  List<String> _findReferencesTo(
    String target, {
    required Set<String> excluding,
  }) {
    final refs = <String>[];
    for (final resource in resources.where(
      (r) =>
          !excluding.contains(r.path) &&
          r.path != packagePath &&
          (r.mediaType == 'text/css' ||
              r.mediaType.endsWith('+xml') ||
              r.mediaType == 'application/xml'),
    )) {
      final text = readText(resource.path);
      final values = resource.mediaType == 'text/css'
          ? _cssReferences(text)
          : _parseXml(text, resource.path, limits).descendants
                .whereType<XmlElement>()
                .expand((e) => e.attributes)
                .where((a) => {'src', 'href', 'poster'}.contains(a.name.local))
                .map((a) => a.value);
      if (values.any((href) => _resolveLocal(resource.path, href) == target))
        refs.add(resource.path);
    }
    return refs;
  }
}

const _idpfObfuscation = 'http://www.idpf.org/2008/embedding';
const _adobeObfuscation = 'http://ns.adobe.com/pdf/enc#RC';
const _fontAlgorithms = {_idpfObfuscation, _adobeObfuscation};

List<XmlElement> _elements(XmlNode root, String local) => root.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local)
    .toList();
String _attribute(XmlElement element, String local) =>
    element.attributes.where((a) => a.name.local == local).firstOrNull?.value ??
    '';
String _escape(String value) => const HtmlEscape(
  HtmlEscapeMode.element,
).convert(value).replaceAll('"', '&quot;').replaceAll("'", '&apos;');
Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));
String _modifiedNow() => DateTime.now().toUtc().toIso8601String().replaceFirst(
  RegExp(r'\.\d+Z$'),
  'Z',
);
bool _validLanguage(String value) =>
    RegExp(r'^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$').hasMatch(value);
String _utf8Declaration(String source) => source.replaceFirstMapped(
  RegExp(
    r'''(<\?xml\s[^?]*encoding\s*=\s*)["'][^"']*["']''',
    caseSensitive: false,
  ),
  (m) => '${m[1]}"UTF-8"',
);

String _decodeText(Uint8List bytes, String p) {
  try {
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      if (bytes.length.isOdd) throw const FormatException('Odd UTF-16 length');
      final data = ByteData.sublistView(bytes);
      final endian = bytes[0] == 0xff ? Endian.little : Endian.big;
      return String.fromCharCodes(
        List.generate(
          (bytes.length - 2) ~/ 2,
          (i) => data.getUint16(2 + i * 2, endian),
        ),
      );
    }
    return utf8.decode(bytes);
  } on FormatException {
    throw EpubException(
      'text_encoding',
      'This text resource is not valid UTF-8 or BOM-marked UTF-16.',
      path: p,
    );
  }
}

XmlDocument _parseXml(String source, String p, EpubLimits limits) {
  if (utf8.encode(source).length > limits.maxTextBytes)
    throw EpubException(
      'text_limit',
      'The XML resource exceeds the text size limit.',
      path: p,
    );
  if (RegExp(r'<!ENTITY\b', caseSensitive: false).hasMatch(source) ||
      RegExp(r'<!DOCTYPE[^>]*\[', caseSensitive: false).hasMatch(source)) {
    throw EpubException(
      'xml_entities',
      'Custom XML entity declarations are not accepted.',
      path: p,
    );
  }
  try {
    var depth = 0;
    var count = 0;
    for (final event in xml_events.parseEvents(source)) {
      if (++count > limits.maxXmlNodes)
        throw EpubException(
          'xml_limit',
          'The XML resource has too many nodes.',
          path: p,
        );
      if (event is xml_events.XmlStartElementEvent && !event.isSelfClosing) {
        if (++depth > limits.maxXmlDepth)
          throw EpubException(
            'xml_limit',
            'The XML resource is nested too deeply.',
            path: p,
          );
      } else if (event is xml_events.XmlEndElementEvent) {
        depth--;
      }
    }
    return XmlDocument.parse(source);
  } on EpubException {
    rethrow;
  } catch (e) {
    throw EpubException('invalid_xml', 'Invalid XML: $e', path: p);
  }
}

String? _resolveLocal(String base, String href) {
  Uri uri;
  try {
    uri = Uri.parse(href);
  } on FormatException {
    throw EpubException(
      'invalid_reference',
      'Invalid resource reference.',
      path: href,
    );
  }
  if (uri.hasScheme || uri.hasAuthority) return null;
  if (uri.hasAbsolutePath || uri.query.isNotEmpty)
    throw EpubException(
      'unsafe_reference',
      'Resource references must be relative archive paths.',
      path: href,
    );
  if (uri.path.isEmpty) return base;
  String decoded;
  try {
    decoded = uri.pathSegments.join('/');
  } on FormatException {
    throw EpubException(
      'invalid_reference',
      'A resource reference contains invalid UTF-8 escaping.',
      path: href,
    );
  }
  final resolved = path.posix.normalize(
    path.posix.join(path.posix.dirname(base), decoded),
  );
  return _safeArchivePath(resolved);
}

String _encodedPath(String p) => Uri(path: p).toString();
String _archiveHref(String p, String fragment) =>
    Uri(path: p, fragment: fragment.isEmpty ? null : fragment).toString();
String _relativeHref(String base, String p) => Uri(
  path: path.posix.relative(p, from: path.posix.dirname(base)),
).toString();
String _tocRelative(String base, String href) {
  final uri = Uri.parse(href);
  final p = _resolveLocal('book.opf', href)!;
  return Uri(
    path: path.posix.relative(p, from: path.posix.dirname(base)),
    fragment: uri.fragment.isEmpty ? null : uri.fragment,
  ).toString();
}

XmlElement _navList(List<EpubTocEntry> entries, String navPath) => XmlElement(
  XmlName('ol'),
  [],
  entries
      .map(
        (entry) => XmlElement(XmlName('li'), [], [
          XmlElement(
            XmlName(entry.href.isEmpty ? 'span' : 'a'),
            entry.href.isEmpty
                ? []
                : [
                    XmlAttribute(
                      XmlName('href'),
                      _tocRelative(navPath, entry.href),
                    ),
                  ],
            [XmlText(entry.label)],
          ),
          if (entry.children.isNotEmpty) _navList(entry.children, navPath),
        ]),
      )
      .toList(),
);
String? _firstTocHref(List<EpubTocEntry> entries) {
  for (final entry in entries) {
    if (entry.href.isNotEmpty) return entry.href;
    final nested = _firstTocHref(entry.children);
    if (nested != null) return nested;
  }
  return null;
}

List<EpubTocEntry> _withoutTocPath(List<EpubTocEntry> entries, String p) =>
    entries.expand((entry) {
      final children = _withoutTocPath(entry.children, p);
      if (entry.href.isNotEmpty && _resolveLocal('book.opf', entry.href) == p)
        return children;
      return [
        EpubTocEntry(label: entry.label, href: entry.href, children: children),
      ];
    }).toList();
String _chapterXhtml(String title, String text, {String? stylesheet}) =>
    '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>${_escape(title)}</title>${stylesheet == null ? '' : '<link rel="stylesheet" type="text/css" href="${_escape(stylesheet)}"/>'}</head><body><h1>${_escape(title)}</h1>${text.split(RegExp(r'\n\s*\n')).map((p) => '<p>${_escape(p).replaceAll('\n', '<br/>')}</p>').join()}</body></html>';
List<XmlElement> _proseElements(XmlDocument document) => document.descendants
    .whereType<XmlElement>()
    .where(
      (e) => {
        'p',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
        'li',
        'blockquote',
        'figcaption',
      }.contains(e.name.local),
    )
    .toList();
bool _plainProse(XmlElement element) => element.children.every(
  (node) =>
      node is XmlText ||
      (node is XmlElement &&
          node.name.local == 'br' &&
          node.attributes.isEmpty),
);
String _proseText(XmlElement element) => element.children
    .map((n) => n is XmlElement && n.name.local == 'br' ? '\n' : n.innerText)
    .join();
Iterable<String> _cssReferences(String css) sync* {
  for (final match in RegExp(
    r'''url\(\s*["']?([^\s)"']+)["']?\s*\)|@import\s+["']([^"']+)["']''',
    caseSensitive: false,
  ).allMatches(css)) {
    yield match[1] ?? match[2]!;
  }
}

String _mediaType(String p) =>
    const {
      '.xhtml': 'application/xhtml+xml',
      '.html': 'application/xhtml+xml',
      '.htm': 'application/xhtml+xml',
      '.opf': 'application/oebps-package+xml',
      '.ncx': 'application/x-dtbncx+xml',
      '.xml': 'application/xml',
      '.css': 'text/css',
      '.js': 'application/javascript',
      '.json': 'application/json',
      '.txt': 'text/plain',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.webp': 'image/webp',
      '.svg': 'image/svg+xml',
      '.woff': 'font/woff',
      '.woff2': 'font/woff2',
      '.ttf': 'font/ttf',
      '.otf': 'font/otf',
      '.mp3': 'audio/mpeg',
      '.m4a': 'audio/mp4',
      '.mp4': 'video/mp4',
      '.smil': 'application/smil+xml',
    }[path.posix.extension(p).toLowerCase()] ??
    'application/octet-stream';

String _normaliseXhtml(
  String source, {
  required String title,
  required EpubLimits limits,
}) {
  try {
    final parsed = _parseXml(source, 'imported chapter', limits);
    if (parsed.rootElement.name.local == 'html' &&
        parsed.rootElement.namespaceUri == 'http://www.w3.org/1999/xhtml') {
      return _utf8Declaration(source);
    }
  } on EpubException catch (e) {
    if (e.code != 'invalid_xml') rethrow;
    // A normalized legacy import can be HTML rather than XML.
  }
  final document = html_parser.parse(source);
  var nodes = 0;
  XmlNode? convert(html.Node node, [int depth = 0]) {
    if (++nodes > limits.maxXmlNodes || depth > limits.maxXmlDepth) {
      throw const EpubException(
        'xml_limit',
        'An imported chapter exceeds the structural limits.',
      );
    }
    if (node is html.Text) return XmlText(node.data);
    if (node is! html.Element ||
        {'script', 'iframe', 'object', 'embed'}.contains(node.localName))
      return null;
    final name = node.localName ?? 'span';
    final attributes = <XmlAttribute>[];
    if (node.namespaceUri != null &&
        node.namespaceUri != 'http://www.w3.org/1999/xhtml') {
      attributes.add(XmlAttribute(XmlName('xmlns'), node.namespaceUri!));
    }
    for (final entry in node.attributes.entries) {
      final key = entry.key.toString();
      if (key.toLowerCase().startsWith('on') || key == 'xmlns') continue;
      attributes.add(XmlAttribute(XmlName.fromString(key), entry.value));
    }
    return XmlElement(
      XmlName.fromString(name),
      attributes,
      node.nodes
          .map((child) => convert(child, depth + 1))
          .whereType<XmlNode>()
          .toList(),
    );
  }

  final root = convert(document.documentElement!) as XmlElement;
  root.setAttribute('xmlns', 'http://www.w3.org/1999/xhtml');
  root.setAttribute('xmlns:epub', 'http://www.idpf.org/2007/ops');
  final head = root.childElements
      .where((e) => e.name.local == 'head')
      .firstOrNull;
  if (head != null && !head.childElements.any((e) => e.name.local == 'title'))
    head.children.add(XmlElement(XmlName('title'), [], [XmlText(title)]));
  return '<?xml version="1.0" encoding="UTF-8"?>${root.toXmlString()}';
}
