import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../opc/zip/deflate_codec.dart';
import '../proofing/german_morphology.dart';
import '../proofing/german_spelling.dart' show normalizeGermanWord;
import '../proofing/office_proofing.dart' show normalizeProofingLanguage;

/// Offline outcomes, deliberately independent of spelling/grammar findings.
enum OfficeThesaurusStatus {
  ready,
  noEntry,
  unsupportedLanguage,
  missingPack,
  failedPack,
}

/// The original text is retained; normalization only affects lookup copies.
final class OfficeThesaurusQuery {
  const OfficeThesaurusQuery({required this.text, required this.language});

  final String text;
  final String language;
}

/// A literal alternative within one source meaning, not a generated correction.
final class OfficeThesaurusTerm {
  OfficeThesaurusTerm({
    required this.id,
    required this.text,
    Iterable<String> labels = const <String>[],
    Iterable<String> sourceIds = const <String>[],
    Iterable<OfficeThesaurusRelation> relations =
        const <OfficeThesaurusRelation>[],
    this.note,
  }) : labels = List<String>.unmodifiable(labels),
       sourceIds = List<String>.unmodifiable(sourceIds),
       relations = List<OfficeThesaurusRelation>.unmodifiable(relations);

  final String id;
  final String text;
  final List<String> labels;
  final List<String> sourceIds;
  final List<OfficeThesaurusRelation> relations;
  final String? note;
}

/// Related concepts stay separate from the alternatives of a meaning.
final class OfficeThesaurusRelation {
  const OfficeThesaurusRelation({required this.type, required this.target});

  final String type;
  final String target;
}

final class OfficeThesaurusSense {
  OfficeThesaurusSense({
    required this.id,
    required this.source,
    required Iterable<OfficeThesaurusTerm> terms,
    this.pos,
    this.gloss,
    Iterable<String> examples = const <String>[],
    Iterable<String> labels = const <String>[],
    Iterable<OfficeThesaurusRelation> relations =
        const <OfficeThesaurusRelation>[],
  }) : terms = List<OfficeThesaurusTerm>.unmodifiable(terms),
       examples = List<String>.unmodifiable(examples),
       labels = List<String>.unmodifiable(labels),
       relations = List<OfficeThesaurusRelation>.unmodifiable(relations);

  final String id;
  final String source;
  final String? pos;
  final String? gloss;
  final List<String> examples;
  final List<String> labels;
  final List<OfficeThesaurusTerm> terms;
  final List<OfficeThesaurusRelation> relations;
}

/// A matched spelling or a qualified lookup lemma. It does not reinflect terms.
final class OfficeThesaurusMatch {
  const OfficeThesaurusMatch({
    required this.text,
    required this.reason,
    this.pos,
  });

  final String text;
  final String reason;
  final String? pos;
}

final class OfficeThesaurusFile {
  const OfficeThesaurusFile({
    required this.sha256,
    required this.size,
    this.compressedSha256,
    this.compressedSize,
  });

  final String sha256;
  final int size;
  final String? compressedSha256;
  final int? compressedSize;
}

/// The manifest and its digest bind a result to the installed corpus bytes.
final class OfficeThesaurusPackManifest {
  OfficeThesaurusPackManifest._({
    required this.packId,
    required this.version,
    required this.locale,
    required this.source,
    required this.name,
    required this.license,
    required this.sourceUrl,
    required this.attribution,
    required this.digest,
    required Iterable<String> noticePaths,
    required Map<String, OfficeThesaurusFile> files,
  }) : noticePaths = List<String>.unmodifiable(noticePaths),
       files = Map<String, OfficeThesaurusFile>.unmodifiable(files);

  final String packId;
  final String version;
  final String locale;
  final String source;
  final String name;
  final String license;
  final String sourceUrl;
  final String attribution;
  final String digest;
  final List<String> noticePaths;
  final Map<String, OfficeThesaurusFile> files;

  String get identity => '$packId:$digest';
}

final class OfficeThesaurusNotice {
  const OfficeThesaurusNotice({required this.path, required this.text});

  final String path;
  final String text;
}

final class OfficeThesaurusResult {
  OfficeThesaurusResult({
    required this.query,
    required this.status,
    this.pack,
    Iterable<OfficeThesaurusSense> senses = const <OfficeThesaurusSense>[],
    Iterable<OfficeThesaurusMatch> matchedTerms =
        const <OfficeThesaurusMatch>[],
    this.message,
  }) : senses = List<OfficeThesaurusSense>.unmodifiable(senses),
       matchedTerms = List<OfficeThesaurusMatch>.unmodifiable(matchedTerms);

  final OfficeThesaurusQuery query;
  final OfficeThesaurusStatus status;
  final OfficeThesaurusPackManifest? pack;
  final List<OfficeThesaurusSense> senses;
  final List<OfficeThesaurusMatch> matchedTerms;
  final String? message;

  String? get packId => pack?.packId;
  String? get packVersion => pack?.version;
  String? get packIdentity => pack?.identity;

  bool containsTerm(OfficeThesaurusTerm term) => senses.any(
    (sense) => sense.terms.any((candidate) => identical(candidate, term)),
  );
}

/// Read one UTF-8 asset relative to the installed pack root (e.g. en/index/ab.json).
/// Return null for an absent asset; throw for other I/O failures. The engine has
/// no Flutter, filesystem, network, native runtime, or model dependency.
typedef OfficeThesaurusAssetLoader = Future<String?> Function(String path);

/// Read one compressed asset. The service verifies its compressed digest before
/// bounded inflation, then verifies the logical UTF-8 file digest and size.
typedef OfficeThesaurusCompressedAssetLoader =
    Future<List<int>?> Function(String path);

/// Unicode whitespace from Python's str.split, used by the pack compiler.
final RegExp _lookupWhitespace = RegExp(
  r'[\u0009-\u000d\u001c-\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+',
);

String normalizeThesaurusTerm(String text) => text
    .replaceAll('\u00ad', '')
    .replaceAll(_lookupWhitespace, ' ')
    .trim()
    .toLowerCase();

/// Low byte of FNV-1a over UTF-8. Computing only that byte is exactly equivalent
/// to the compiler's uint32 hash, and avoids JavaScript's 53-bit multiply limit.
String thesaurusShard(String key) {
  var hash = 0xc5;
  for (final byte in utf8.encode(key)) {
    hash = ((hash ^ byte) * 0x93) & 255;
  }
  return hash.toRadixString(16).padLeft(2, '0');
}

/// Lazy, bounded, verified offline lookup. Call [clear] after installing or
/// replacing any pack; in-flight old reads cannot repopulate the new caches.
final class OfficeThesaurusService {
  OfficeThesaurusService({
    required this.loadAsset,
    this.loadCompressedAsset,
    Map<String, String> manifestSha256 = const <String, String>{},
    this.maxCachedShards = 64,
    this.maxCachedResults = 64,
  }) : manifestSha256 = Map<String, String>.unmodifiable(manifestSha256) {
    if (maxCachedShards < 1 || maxCachedResults < 1) {
      throw ArgumentError('Thesaurus cache limits must be positive');
    }
    for (final digest in manifestSha256.values) {
      if (!_digestPattern.hasMatch(digest)) {
        throw ArgumentError('Invalid pinned thesaurus manifest digest');
      }
    }
  }

  final OfficeThesaurusAssetLoader loadAsset;
  final OfficeThesaurusCompressedAssetLoader? loadCompressedAsset;
  final Map<String, String> manifestSha256;
  final int maxCachedShards;
  final int maxCachedResults;
  final _manifests = <String, Future<OfficeThesaurusPackManifest?>>{};
  final _shards = <String, Map<String, Object?>>{};
  final _pendingShards = <String, Future<Map<String, Object?>>>{};
  final _results = <String, OfficeThesaurusResult>{};
  var _revision = 0;

  int get revision => _revision;
  int get cachedShardCount => _shards.length;
  int get cachedResultCount => _results.length;

  void clear() {
    _revision++;
    _manifests.clear();
    _shards.clear();
    _pendingShards.clear();
    _results.clear();
  }

  static const _languages = <String, String>{
    'en-US': 'en',
    'en-GB': 'en',
    'en-CA': 'en',
    'en-AU': 'en',
    'en-IN': 'en',
    'de-DE': 'de',
    'de-AT': 'de',
    'de-CH': 'de',
  };
  static final _digestPattern = RegExp(r'^[0-9a-f]{64}$');
  static final _pathPattern = RegExp(
    r'^(?:index|senses)/[0-9a-f]{2}\.json$|^notices/[A-Za-z0-9_.-]+$|^morphology\.json$',
  );
  static const _maximumFileBytes = 16 * 1024 * 1024;

  Future<OfficeThesaurusResult> lookup(OfficeThesaurusQuery query) async {
    final locale = _languages[normalizeProofingLanguage(query.language)];
    if (locale == null) {
      return OfficeThesaurusResult(
        query: query,
        status: OfficeThesaurusStatus.unsupportedLanguage,
        message: 'Thesaurus packs are available for English and German.',
      );
    }
    final key = normalizeThesaurusTerm(query.text);
    final sourceForm = query.text
        .replaceAll('\u00ad', '')
        .replaceAll(_lookupWhitespace, ' ')
        .trim();
    if (key.isEmpty || key.length > 512 || !_safeTerm(key)) {
      return OfficeThesaurusResult(
        query: query,
        status: OfficeThesaurusStatus.noEntry,
        message: 'Select a word or a short phrase to look up.',
      );
    }
    final epoch = _revision;
    final cacheKey = '${query.language}\u0000${query.text}';
    final cached = _results.remove(cacheKey);
    if (cached != null) {
      _results[cacheKey] = cached;
      return cached;
    }
    OfficeThesaurusPackManifest? pack;
    try {
      pack = await _manifest(locale, epoch);
      _checkEpoch(epoch);
      if (pack == null) {
        return OfficeThesaurusResult(
          query: query,
          status: OfficeThesaurusStatus.missingPack,
          message: 'The $locale thesaurus pack is not installed.',
        );
      }
      final matches = <OfficeThesaurusMatch>[];
      final senses = <String, OfficeThesaurusSense>{};
      final entry = await _indexEntry(pack, key, epoch);
      await _addSenses(pack, entry, senses, epoch);
      if (senses.isNotEmpty) {
        matches.add(OfficeThesaurusMatch(text: query.text, reason: 'lexical'));
      }
      {
        // A source Form records a lookup alias. It never becomes another
        // synonym group, and one alias never recursively follows another.
        for (final alias in _aliases(entry)) {
          final before = senses.length;
          final lemmaEntry = await _indexEntry(
            pack,
            normalizeThesaurusTerm(alias.text),
            epoch,
          );
          await _addSenses(pack, lemmaEntry, senses, epoch, pos: alias.pos);
          if (senses.length > before) matches.add(alias);
        }
        if (locale == 'en' &&
            senses.isEmpty &&
            !key.contains(' ') &&
            pack.files.containsKey('morphology.json')) {
          final morphology = await _shard(pack, 'morphology.json', epoch);
          if (morphology['source'] != 'princeton-wordnet' ||
              morphology['version'] != '3.0') {
            throw const FormatException('Unsupported English morphology');
          }
          final rules = _list(morphology['rules']);
          if (rules.length > 64) {
            throw const FormatException('Too many morphology rules');
          }
          final tried = <String>{};
          for (final value in rules) {
            final rule = _object(value);
            final suffix = _string(rule['suffix']);
            final ending = rule['ending'];
            final pos = _string(rule['pos']);
            if (ending is! String ||
                ending.length > 16 ||
                suffix.length > 16 ||
                !const <String>{'n', 'v', 'a'}.contains(pos)) {
              throw const FormatException('Invalid morphology rule');
            }
            if (key.length <= suffix.length || !key.endsWith(suffix)) continue;
            final lemma =
                '${key.substring(0, key.length - suffix.length)}$ending';
            if (!tried.add('$pos:$lemma')) continue;
            final before = senses.length;
            await _addSenses(
              pack,
              await _indexEntry(pack, lemma, epoch),
              senses,
              epoch,
              pos: pos,
            );
            if (senses.length > before) {
              matches.add(
                OfficeThesaurusMatch(
                  text: lemma,
                  reason: 'wordnet-detachment',
                  pos: pos,
                ),
              );
            }
          }
        }
        if (locale == 'de' && !key.contains(' ') && senses.isEmpty) {
          final morphology = GermanNounMorphology.shared;
          await morphology.prepareWords(<String>[sourceForm]);
          _checkEpoch(epoch);
          if (!morphology.hasUnresolvedReading(sourceForm)) {
            // Do not use the spelling allowlist to prune thesaurus entries.
            // Preserve all finite noun readings, including ambiguity.
            final lemmas = <String>{
              for (final reading in morphology.lookup(sourceForm))
                reading.lemma,
            };
            for (final lemma in lemmas) {
              final before = senses.length;
              final lemmaEntry = await _indexEntry(
                pack,
                normalizeThesaurusTerm(lemma),
                epoch,
              );
              await _addSenses(pack, lemmaEntry, senses, epoch, pos: 'n');
              if (senses.length > before) {
                matches.add(
                  OfficeThesaurusMatch(
                    text: lemma,
                    reason: 'unicode-noun-form',
                    pos: 'n',
                  ),
                );
              }
            }
          }
        }
        // The fork's finite canonical-composition mapping is a lookup fallback
        // only. It neither strips accents nor equates German sharp-s with ss.
        if (locale == 'de' && senses.isEmpty) {
          final composed = normalizeThesaurusTerm(
            normalizeGermanWord(sourceForm),
          );
          if (composed != key) {
            await _addSenses(
              pack,
              await _indexEntry(pack, composed, epoch),
              senses,
              epoch,
            );
            if (senses.isNotEmpty) {
              matches.add(
                OfficeThesaurusMatch(
                  text: normalizeGermanWord(sourceForm),
                  reason: 'canonical-form',
                ),
              );
            }
          }
        }
      }
      _checkEpoch(epoch);
      final ordered = senses.values.toList();
      final display = sourceForm;
      ordered.sort((a, b) {
        final aExact = a.terms.any((term) => term.text == display);
        final bExact = b.terms.any((term) => term.text == display);
        if (aExact != bExact) return aExact ? -1 : 1;
        return a.id.compareTo(b.id);
      });
      final result = OfficeThesaurusResult(
        query: query,
        status: ordered.isEmpty
            ? OfficeThesaurusStatus.noEntry
            : OfficeThesaurusStatus.ready,
        pack: pack,
        senses: ordered,
        matchedTerms: matches,
        message: ordered.isEmpty
            ? 'No entry was found in this pack or its supported word forms.'
            : null,
      );
      _results[cacheKey] = result;
      while (_results.length > maxCachedResults) {
        _results.remove(_results.keys.first);
      }
      return result;
    } on Object {
      return OfficeThesaurusResult(
        query: query,
        status: OfficeThesaurusStatus.failedPack,
        pack: pack,
        message: epoch == _revision
            ? 'The thesaurus pack could not be read or verified. Reinstall it and try again.'
            : 'The thesaurus pack changed. Look up the selection again.',
      );
    }
  }

  /// Read the actual bundled licenses through the same digest checks as data.
  Future<List<OfficeThesaurusNotice>> notices(
    OfficeThesaurusResult result,
  ) async {
    final pack = result.pack;
    if (pack == null) return const <OfficeThesaurusNotice>[];
    final epoch = _revision;
    final current = await _manifest(pack.locale, epoch);
    _checkEpoch(epoch);
    if (current?.identity != pack.identity) {
      throw StateError('The thesaurus pack changed');
    }
    final notices = <OfficeThesaurusNotice>[];
    for (final path in pack.noticePaths) {
      notices.add(
        OfficeThesaurusNotice(
          path: path,
          text: await _verifiedFile(pack, path, epoch),
        ),
      );
    }
    return List<OfficeThesaurusNotice>.unmodifiable(notices);
  }

  void _checkEpoch(int epoch) {
    if (epoch != _revision) {
      throw StateError('Thesaurus pack changed during read');
    }
  }

  Future<OfficeThesaurusPackManifest?> _manifest(String locale, int epoch) =>
      _manifests.putIfAbsent(locale, () => _readManifest(locale, epoch));

  Future<OfficeThesaurusPackManifest?> _readManifest(
    String locale,
    int epoch,
  ) async {
    final text = await loadAsset('$locale/manifest.json');
    _checkEpoch(epoch);
    if (text == null) return null;
    final bytes = utf8.encode(text);
    if (bytes.length > 1024 * 1024) {
      throw const FormatException('Oversized thesaurus manifest');
    }
    final digest = sha256.convert(bytes).toString();
    final expected = manifestSha256[locale];
    if (expected != null && expected != digest) {
      throw const FormatException('Thesaurus manifest digest mismatch');
    }
    final json = _object(jsonDecode(text));
    if (json['schemaVersion'] != 1 ||
        json['locale'] != locale ||
        json['normalization'] != 'lower-whitespace-v1' ||
        json['shardAlgorithm'] != 'fnv1a32-utf8-low8') {
      throw const FormatException('Unsupported thesaurus manifest');
    }
    final files = <String, OfficeThesaurusFile>{};
    for (final entry in _object(json['files']).entries) {
      if (!_pathPattern.hasMatch(entry.key) || entry.key.contains('..')) {
        throw const FormatException('Unsafe thesaurus asset path');
      }
      final file = _object(entry.value);
      final fileDigest = _string(file['sha256']);
      final size = file['size'];
      if (!_digestPattern.hasMatch(fileDigest) ||
          size is! int ||
          size < 0 ||
          size > _maximumFileBytes) {
        throw const FormatException('Invalid thesaurus file metadata');
      }
      final compression = file['compression'];
      final compressedDigest = file['compressedSha256'];
      final compressedSize = file['compressedSize'];
      if (compression != null ||
          compressedDigest != null ||
          compressedSize != null) {
        if (compression != 'deflate-raw' ||
            compressedDigest is! String ||
            !_digestPattern.hasMatch(compressedDigest) ||
            compressedSize is! int ||
            compressedSize < 1 ||
            compressedSize > _maximumFileBytes) {
          throw const FormatException('Invalid compressed thesaurus metadata');
        }
      }
      files[entry.key] = OfficeThesaurusFile(
        sha256: fileDigest,
        size: size,
        compressedSha256: compressedDigest as String?,
        compressedSize: compressedSize as int?,
      );
    }
    for (var i = 0; i < 256; i++) {
      final shard = i.toRadixString(16).padLeft(2, '0');
      if (!files.containsKey('index/$shard.json') ||
          !files.containsKey('senses/$shard.json')) {
        throw const FormatException('Incomplete thesaurus pack');
      }
    }
    final noticePaths = _strings(json['noticePaths']);
    if (noticePaths.isEmpty ||
        noticePaths.any(
          (path) => !path.startsWith('notices/') || !files.containsKey(path),
        )) {
      throw const FormatException('Missing thesaurus notices');
    }
    return OfficeThesaurusPackManifest._(
      packId: _string(json['packId']),
      version: _string(json['version']),
      locale: locale,
      source: _string(json['source']),
      name: _string(json['name']),
      license: _string(json['license']),
      sourceUrl: _string(json['sourceUrl']),
      attribution: _string(json['attribution']),
      digest: digest,
      noticePaths: noticePaths,
      files: files,
    );
  }

  Future<String> _verifiedFile(
    OfficeThesaurusPackManifest pack,
    String path,
    int epoch,
  ) async {
    final file = pack.files[path];
    if (file == null) throw const FormatException('Unlisted thesaurus asset');
    late final List<int> bytes;
    if (file.compressedSha256 != null) {
      final loader = loadCompressedAsset;
      if (loader == null) {
        throw const FormatException('No compressed thesaurus asset loader');
      }
      final compressed = await loader('${pack.locale}/$path.deflate');
      _checkEpoch(epoch);
      if (compressed == null ||
          compressed.length != file.compressedSize ||
          sha256.convert(compressed).toString() != file.compressedSha256) {
        throw const FormatException('Compressed thesaurus digest mismatch');
      }
      bytes = RawDeflate.inflate(compressed, maxOutputBytes: file.size);
    } else {
      final text = await loadAsset('${pack.locale}/$path');
      _checkEpoch(epoch);
      if (text == null) throw const FormatException('Missing thesaurus asset');
      bytes = utf8.encode(text);
    }
    if (bytes.length != file.size ||
        sha256.convert(bytes).toString() != file.sha256) {
      throw const FormatException('Thesaurus asset digest mismatch');
    }
    return utf8.decode(bytes);
  }

  Future<Map<String, Object?>> _shard(
    OfficeThesaurusPackManifest pack,
    String path,
    int epoch,
  ) async {
    _checkEpoch(epoch);
    final cacheKey = '${pack.identity}/$path';
    final cached = _shards.remove(cacheKey);
    if (cached != null) {
      _shards[cacheKey] = cached;
      return cached;
    }
    final pending = _pendingShards[cacheKey];
    if (pending != null) return pending;
    final future = _readShard(pack, path, cacheKey, epoch);
    // Share the future before awaiting it to deduplicate concurrent I/O.
    _pendingShards[cacheKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_pendingShards[cacheKey], future)) {
        unawaited(_pendingShards.remove(cacheKey));
      }
    }
  }

  Future<Map<String, Object?>> _readShard(
    OfficeThesaurusPackManifest pack,
    String path,
    String key,
    int epoch,
  ) async {
    final text = await _verifiedFile(pack, path, epoch);
    final json = _object(jsonDecode(text));
    _checkEpoch(epoch);
    _shards[key] = json;
    while (_shards.length > maxCachedShards) {
      _shards.remove(_shards.keys.first);
    }
    return json;
  }

  Future<Map<String, Object?>?> _indexEntry(
    OfficeThesaurusPackManifest pack,
    String key,
    int epoch,
  ) async {
    final shard = await _shard(
      pack,
      'index/${thesaurusShard(key)}.json',
      epoch,
    );
    final value = shard[key];
    if (!shard.containsKey(key)) return null;
    final entry = _object(value);
    if (entry['senseIds'] is! List<Object?> ||
        (entry.containsKey('aliases') && entry['aliases'] is! List<Object?>)) {
      throw const FormatException('Malformed thesaurus index entry');
    }
    return entry;
  }

  List<OfficeThesaurusMatch> _aliases(Map<String, Object?>? entry) {
    if (entry == null || entry['aliases'] == null) return const [];
    final aliases = _list(entry['aliases']);
    if (aliases.length > 128) {
      throw const FormatException('Too many lookup aliases');
    }
    return <OfficeThesaurusMatch>[
      for (final value in aliases)
        OfficeThesaurusMatch(
          text: _string(_object(value)['lemma']),
          reason: _string(_object(value)['reason']),
          pos: _optionalString(_object(value)['pos']),
        ),
    ];
  }

  Future<void> _addSenses(
    OfficeThesaurusPackManifest pack,
    Map<String, Object?>? entry,
    Map<String, OfficeThesaurusSense> output,
    int epoch, {
    String? pos,
  }) async {
    if (entry == null) return;
    final ids = _strings(entry['senseIds']);
    if (ids.length > 1024) {
      throw const FormatException('Too many thesaurus senses');
    }
    for (final id in ids) {
      if (output.containsKey(id)) continue;
      final shard = await _shard(
        pack,
        'senses/${thesaurusShard(id)}.json',
        epoch,
      );
      final sense = _parseSense(_object(shard[id]));
      if (sense.id != id || sense.source != pack.source) {
        throw const FormatException('Thesaurus source identity mismatch');
      }
      // German has no systematic source POS; a qualified noun lemma remains
      // useful without inventing a POS for the OpenThesaurus group.
      if (pos != null &&
          sense.pos != null &&
          sense.pos != pos &&
          !(pos == 'a' && sense.pos == 's')) {
        continue;
      }
      output[id] = sense;
    }
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected object');
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) throw const FormatException('Expected list');
  return value;
}

String _string(Object? value) {
  if (value is! String || value.isEmpty || value.length > 65536) {
    throw const FormatException('Invalid thesaurus string');
  }
  return value;
}

String? _optionalString(Object? value) => value == null ? null : _string(value);

List<String> _strings(Object? value) => value == null
    ? const <String>[]
    : _list(value).map(_string).toList(growable: false);

bool _safeTerm(String text) {
  if (text.isEmpty || text.length > 2048 || text.trim() != text) return false;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit < 32 || (unit >= 127 && unit <= 159)) return false;
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= text.length) return false;
      final low = text.codeUnitAt(i);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

List<OfficeThesaurusRelation> _relations(Object? values) => values == null
    ? const <OfficeThesaurusRelation>[]
    : <OfficeThesaurusRelation>[
        for (final value in _list(values))
          OfficeThesaurusRelation(
            type: _string(_object(value)['type']),
            target: _string(_object(value)['target']),
          ),
      ];

OfficeThesaurusSense _parseSense(Map<String, Object?> json) {
  final terms = <OfficeThesaurusTerm>[];
  final ids = <String>{};
  final values = _list(json['terms']);
  if (values.isEmpty || values.length > 4096) {
    throw const FormatException('Invalid thesaurus term count');
  }
  for (final value in values) {
    final term = _object(value);
    final id = _string(term['id']);
    final text = _string(term['text']);
    if (!ids.add(id) || !_safeTerm(text)) {
      throw const FormatException('Invalid or duplicate thesaurus term');
    }
    terms.add(
      OfficeThesaurusTerm(
        id: id,
        text: text,
        labels: _strings(term['labels']),
        sourceIds: _strings(term['sourceIds']),
        relations: _relations(term['relations']),
        note: _optionalString(term['note']),
      ),
    );
  }
  return OfficeThesaurusSense(
    id: _string(json['id']),
    source: _string(json['source']),
    pos: _optionalString(json['pos']),
    gloss: _optionalString(json['gloss']),
    examples: _strings(json['examples']),
    labels: _strings(json['labels']),
    terms: terms,
    relations: _relations(json['relations']),
  );
}
