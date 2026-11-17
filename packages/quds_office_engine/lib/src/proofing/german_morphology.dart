import 'dart:async';
import 'dart:convert';

import '../opc/zip/deflate_codec.dart';
import 'data/german_morphology_data.dart';
import 'german_spelling.dart' show normalizeGermanWord;

/// A noun analysis with all licensed alternatives for one gender and number.
///
/// Gender indexes are masculine, feminine, neuter, plural (0..3). Case indexes
/// are nominative, accusative, dative, genitive (0..3). These stable internal
/// indexes match the phrase analyzer without making its private enums public.
/// A reading is evidence, not a spelling guarantee or a sentence parse.
final class GermanNounReading {
  GermanNounReading._(
    this.lemma,
    this._stem,
    this._pattern,
    this._standardMask,
    this._swissMask,
  );

  final String lemma;
  final String _stem;
  final _GermanNounPattern _pattern;
  final int _standardMask;
  final int _swissMask;
  List<Set<String>?>? _forms;

  int get gender => _pattern.gender;

  /// All valid recorded alternatives. The collection cannot be mutated by a
  /// caller, and is constructed only when this reading is actually inspected.
  Set<String> formsForCase(int caseIndex) {
    RangeError.checkValidIndex(caseIndex, _pattern.endings, 'caseIndex');
    final List<Set<String>?> forms = _forms ??= List<Set<String>?>.filled(
      4,
      null,
    );
    return forms[caseIndex] ??= Set<String>.unmodifiable(
      _pattern.endings[caseIndex].map((String ending) => '$_stem$ending'),
    );
  }
}

final class _GermanNounPattern {
  _GermanNounPattern(String encoded) {
    final List<String> fields = encoded.split('\t');
    if (fields.length != 5) {
      throw const FormatException('Invalid German noun pattern');
    }
    gender = int.parse(fields.first);
    if (gender < 0 || gender > 3) {
      throw const FormatException('Invalid German noun gender');
    }
    endings = <List<String>>[
      for (final String field in fields.skip(1))
        List<String>.unmodifiable(field.split('|')),
    ];
    // The generator's spelling masks use the same sorted unique suffix order.
    // Thirty bits are portable through JavaScript's bitwise operations.
    allEndings = (<String>{
      for (final List<String> values in endings) ...values,
    }.toList(growable: false)..sort());
    if (allEndings.length > 30) {
      throw const FormatException('Too many German noun alternatives');
    }
  }

  late final int gender;
  late final List<List<String>> endings;
  late final List<String> allEndings;
}

/// Offline German lexical morphology derived from Unicode Inflection.
///
/// The generated resource has separately pinned Unicode-3.0 provenance and
/// includes its full notice. Noun suggestions must pass [acceptsSpelling];
/// lexical evidence never adds words to [GermanSpellingProvider]'s dictionary.
/// Unknown words return no readings. Homographs retain every selected reading.
///
/// [ensureLoaded] initializes only the small pattern metadata. [prepareWords]
/// loads the bounded surface buckets needed by a request, yielding between
/// them. [lookup] can load one missing bucket synchronously as a fallback.
/// Native and web use the same data without files, network, FFI or isolates.
final class GermanNounMorphology {
  GermanNounMorphology._();

  static final GermanNounMorphology shared = GermanNounMorphology._();

  Future<void>? _loading;
  bool _loaded = false;
  late final List<_GermanNounPattern> _patterns;
  final List<bool> _bucketsLoaded = List<bool>.filled(256, false);
  int _loadedBucketCount = 0;
  final Map<String, List<GermanNounReading>> _forms =
      <String, List<GermanNounReading>>{};
  final Map<int, GermanNounReading> _readings = <int, GermanNounReading>{};
  final Set<String> _standardSpellings = <String>{};
  final Set<String> _swissSpellings = <String>{};
  final Set<String> _unresolvedForms = <String>{};

  int get lemmaCount => germanMorphologyLemmaCount;
  int get readingCount => germanMorphologyReadingCount;

  /// Whether pattern metadata is ready; surface buckets remain demand-loaded.
  bool get isLoaded => _loaded;

  /// Diagnostic counts for checking that short requests do not load the corpus.
  int get loadedBucketCount => _loadedBucketCount;
  int get cachedReadingCount => _readings.length;

  Future<void> ensureLoaded() {
    // A completed future can retain the zone of the initial caller (notably
    // a disposed Flutter test zone). Warm callers get their own completion.
    if (_loaded) return Future<void>.value();
    return _loading ??= _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    if (germanMorphologySurfaceChunks.length != 256) {
      throw const FormatException('Incomplete German surface bucket index');
    }
    _patterns = germanMorphologyPatterns
        .map(_GermanNounPattern.new)
        .toList(growable: false);
    _loaded = true;
  }

  static String _key(String word) => normalizeGermanWord(word).toLowerCase();

  static int _bucket(String key) {
    int hash = 0;
    for (final int unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 255;
    }
    return hash;
  }

  static List<String> _decode(String chunk) => utf8
      .decode(RawDeflate.inflate(base64Decode(chunk), maxOutputBytes: 1048576))
      .split('\n');

  /// Prepare only the words relevant to a request. Duplicate words, aliases
  /// and concurrent callers share the same immutable loaded buckets.
  Future<void> prepareWords(Iterable<String> words) async {
    await ensureLoaded();
    final Set<int> needed = <int>{
      for (final String word in words)
        if (word.isNotEmpty) _bucket(_key(word)),
    };
    for (final int bucket in needed) {
      if (_bucketsLoaded[bucket]) continue;
      _loadBucket(bucket);
      await Future<void>.delayed(Duration.zero);
    }
  }

  void _loadBucket(int bucket) {
    if (_bucketsLoaded[bucket]) return;
    // Parse into private staging collections. A malformed bucket cannot publish
    // partial analyses or spelling allowances before validation completes.
    final Map<String, List<GermanNounReading>> forms =
        <String, List<GermanNounReading>>{};
    final Map<int, GermanNounReading> readings = <int, GermanNounReading>{};
    final Set<String> standard = <String>{};
    final Set<String> swiss = <String>{};
    final Set<String> unresolved = <String>{};
    for (final String line in _decode(germanMorphologySurfaceChunks[bucket])) {
      if (line.isEmpty) continue;
      final List<String> fields = line.split('\t');
      if (fields.length != 7 || fields[0].isEmpty) {
        throw const FormatException('Invalid German surface reading');
      }
      final String key = fields[0];
      if (_bucket(key) != bucket) {
        throw const FormatException('Invalid German surface bucket');
      }
      if (fields[1] == '-1') {
        if (fields.skip(2).any((String field) => field.isNotEmpty)) {
          throw const FormatException('Invalid unresolved German reading');
        }
        unresolved.add(key);
        continue;
      }
      if (fields[2].isEmpty) {
        throw const FormatException('Missing German noun lemma');
      }
      final int id = int.parse(fields[1]);
      final int patternId = int.parse(fields[4]);
      final int standardMask = int.parse(fields[5]);
      final int swissMask = int.parse(fields[6]);
      if (id < 0 ||
          id >= germanMorphologyReadingCount ||
          patternId < 0 ||
          patternId >= _patterns.length ||
          standardMask < 0 ||
          swissMask < 0) {
        throw const FormatException('Invalid German surface metadata');
      }
      final _GermanNounPattern pattern = _patterns[patternId];
      final int maskLimit = 1 << pattern.allEndings.length;
      if (standardMask >= maskLimit || swissMask >= maskLimit) {
        throw const FormatException('Invalid German spelling mask');
      }
      GermanNounReading? reading = _readings[id] ?? readings[id];
      if (reading == null) {
        reading = GermanNounReading._(
          fields[2],
          fields[3],
          pattern,
          standardMask,
          swissMask,
        );
        readings[id] = reading;
        for (int bit = 0; bit < pattern.allEndings.length; bit++) {
          final String form = '${fields[3]}${pattern.allEndings[bit]}';
          if ((standardMask & (1 << bit)) != 0) standard.add(form);
          if ((swissMask & (1 << bit)) != 0) {
            swiss.add(form.replaceAll('ß', 'ss').replaceAll('ẞ', 'SS'));
          }
        }
      } else if (reading.lemma != fields[2] ||
          reading._stem != fields[3] ||
          !identical(reading._pattern, pattern) ||
          reading._standardMask != standardMask ||
          reading._swissMask != swissMask) {
        throw const FormatException('Conflicting German noun reading');
      }
      final List<GermanNounReading> analyses = forms.putIfAbsent(
        key,
        () => <GermanNounReading>[],
      );
      if (!analyses.contains(reading)) analyses.add(reading);
    }
    _readings.addAll(readings);
    _standardSpellings.addAll(standard);
    _swissSpellings.addAll(swiss);
    _unresolvedForms.addAll(unresolved);
    for (final MapEntry<String, List<GermanNounReading>> entry
        in forms.entries) {
      _forms[entry.key] = List<GermanNounReading>.unmodifiable(entry.value);
    }
    _bucketsLoaded[bucket] = true;
    _loadedBucketCount++;
  }

  List<GermanNounReading> lookup(String word) {
    if (!_loaded) throw StateError('Load German morphology before lookup');
    final String key = _key(word);
    if (key.isEmpty) return const <GermanNounReading>[];
    _loadBucket(_bucket(key));
    if (_unresolvedForms.contains(key)) return const <GermanNounReading>[];
    return _forms[key] ?? const <GermanNounReading>[];
  }

  /// Some surface forms also have determiner-dependent or otherwise incomplete
  /// noun analyses. Those readings must veto fixed-noun corrections, including
  /// corrections from the small first-party fallback dictionary.
  bool hasUnresolvedReading(String word) {
    if (!_loaded) throw StateError('Load German morphology before lookup');
    final String key = _key(word);
    if (key.isEmpty) return false;
    _loadBucket(_bucket(key));
    return _unresolvedForms.contains(key);
  }

  /// A finite intersection with the modern spelling vocabulary. Case remains
  /// significant. Swiss suggestions replace sharp-s with ss, matching the
  /// provider's later source-preserving presentation conversion. A missing
  /// target bucket may be loaded to qualify a first-party fallback suggestion.
  bool acceptsSpelling(String form, {bool swiss = false}) {
    if (!_loaded) throw StateError('Load German morphology before lookup');
    String normalized = normalizeGermanWord(form);
    if (swiss) {
      normalized = normalized.replaceAll('ß', 'ss').replaceAll('ẞ', 'SS');
    }
    final Set<String> spellings = swiss ? _swissSpellings : _standardSpellings;
    if (spellings.contains(normalized)) return true;
    if (normalized.isEmpty) return false;
    _loadBucket(_bucket(normalized.toLowerCase()));
    return spellings.contains(normalized);
  }
}
