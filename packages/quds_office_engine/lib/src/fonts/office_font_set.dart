import 'sfnt_parser.dart';

/// One real face supplied by a host. Aliases affect rendering only; document
/// font properties are never rewritten by font selection.
class OfficeFontFace {
  const OfficeFontFace({
    required this.font,
    required this.family,
    this.weight = 400,
    this.italic = false,
    this.aliases = const <String>[],
  }) : assert(family != ''),
       assert(weight >= 1 && weight <= 1000);

  final SfntFont font;
  final String family;
  final int weight;
  final bool italic;
  final List<String> aliases;

  bool matches(String name) {
    final normalized = name.trim().toLowerCase();
    return family.trim().toLowerCase() == normalized ||
        aliases.any((alias) => alias.trim().toLowerCase() == normalized);
  }
}

/// A bounded record of an actual requested-family substitution.
class OfficeFontSubstitution {
  const OfficeFontSubstitution(this.requestedFamily, this.resolvedFamily);
  final String requestedFamily;
  final String resolvedFamily;

  @override
  bool operator ==(Object other) =>
      other is OfficeFontSubstitution &&
      requestedFamily == other.requestedFamily &&
      resolvedFamily == other.resolvedFamily;
  @override
  int get hashCode => Object.hash(requestedFamily, resolvedFamily);
}

/// Optional export diagnostics. Counts are bounded even for hostile input.
class OfficeFontDiagnostics {
  static const int maxMissingCodePoints = 256;
  static const int maxSubstitutions = 128;
  final Set<int> _missing = <int>{};
  final Set<OfficeFontSubstitution> _substitutions = <OfficeFontSubstitution>{};
  bool truncated = false;

  Set<int> get missingCodePoints => Set<int>.unmodifiable(_missing);
  List<OfficeFontSubstitution> get substitutions =>
      List<OfficeFontSubstitution>.unmodifiable(_substitutions);

  /// Call only for text that could not be painted, not speculative font probes.
  void reportMissing(int codePoint) {
    if (codePoint < 32 ||
        codePoint > 0x10ffff ||
        _missing.contains(codePoint)) {
      return;
    }
    if (_missing.length >= maxMissingCodePoints) {
      truncated = true;
    } else {
      _missing.add(codePoint);
    }
  }

  /// Records a family used to paint a glyph. Resolvers do not call this while
  /// probing fonts for measurement or unused document content.
  void reportSubstitution(String? requested, String actual) {
    if (requested == null) return;
    // Bound work as well as retained bytes: a source font name is untrusted
    // and may be referenced by every glyph in a large document.
    String bounded(String value) =>
        value.length > 256 ? value.substring(0, 256) : value;
    final wanted = bounded(requested);
    final resolved = bounded(actual);
    if (wanted.trim().isEmpty ||
        wanted.trim().toLowerCase() == resolved.trim().toLowerCase()) {
      return;
    }
    final value = OfficeFontSubstitution(wanted, resolved);
    if (_substitutions.contains(value)) return;
    if (_substitutions.length >= maxSubstitutions) {
      truncated = true;
    } else {
      _substitutions.add(value);
    }
  }
}

/// TrueType faces used for Office layout and PDF text embedding.
///
/// [faces] resolves requested family and style before glyph fallback. Existing
/// [primary]/[fallbacks] callers retain their original coverage-only ordering.
/// CFF faces are intentionally excluded by the current PDF embedder.
class OfficeFontSet {
  const OfficeFontSet({
    this.primary,
    this.fallbacks = const <SfntFont>[],
    this.faces = const <OfficeFontFace>[],
    this.defaultFamily,
    this.diagnostics,
  });

  final SfntFont? primary;
  final List<SfntFont> fallbacks;
  final List<OfficeFontFace> faces;
  final String? defaultFamily;
  final OfficeFontDiagnostics? diagnostics;

  factory OfficeFontSet.single(SfntFont? font) => OfficeFontSet(primary: font);
  bool get isEmpty => primary == null && fallbacks.isEmpty && faces.isEmpty;

  /// Available embeddable bytes, without duplicate source objects.
  List<SfntFont> get embeddable {
    final result = <SfntFont>[];
    void add(SfntFont? font) {
      if (font != null && font.hasTable('glyf') && !result.contains(font)) {
        result.add(font);
      }
    }

    add(primary);
    for (final font in fallbacks) {
      add(font);
    }
    for (final face in faces) {
      add(face.font);
    }
    return result;
  }

  /// Resolves a real face covering [codePoint], preserving requested style.
  ///
  /// The requested family wins, then [defaultFamily], legacy coverage faces,
  /// and remaining named families in declaration order. A missing glyph returns
  /// null; callers can expose it via [OfficeFontDiagnostics.reportMissing].
  OfficeFontFace? resolve(
    int codePoint, {
    String? family,
    int weight = 400,
    bool italic = false,
  }) {
    OfficeFontFace? choose(Iterable<OfficeFontFace> candidates) {
      OfficeFontFace? best;
      var bestScore = 1 << 30;
      for (final candidate in candidates) {
        if (!candidate.font.hasTable('glyf') ||
            candidate.font.glyphIdFor(codePoint) == 0) {
          continue;
        }
        final score =
            (candidate.italic == italic ? 0 : 10000) +
            (candidate.weight - weight).abs();
        if (score < bestScore) {
          best = candidate;
          bestScore = score;
        }
      }
      return best;
    }

    OfficeFontFace? selected;
    if (family != null && family.length <= 256) {
      selected = choose(faces.where((face) => face.matches(family)));
    }
    if (selected == null && defaultFamily != null) {
      selected = choose(faces.where((face) => face.matches(defaultFamily!)));
    }
    if (selected == null) {
      for (final font in <SfntFont>[
        if (primary != null) primary!,
        ...fallbacks,
      ]) {
        if (font.hasTable('glyf') && font.glyphIdFor(codePoint) != 0) {
          selected = OfficeFontFace(font: font, family: 'Supplied font');
          break;
        }
      }
    }
    if (selected == null) {
      final seen = <String>{};
      for (final face in faces) {
        if (!seen.add(face.family.trim().toLowerCase())) continue;
        selected = choose(
          faces.where(
            (other) =>
                other.family.trim().toLowerCase() ==
                face.family.trim().toLowerCase(),
          ),
        );
        if (selected != null) break;
      }
    }
    return selected;
  }

  SfntFont? faceFor(
    int codePoint, {
    String? family,
    int weight = 400,
    bool italic = false,
  }) =>
      resolve(codePoint, family: family, weight: weight, italic: italic)?.font;
}

/// Picks covering faces from a candidate list for a body of text.
abstract final class OfficeFontResolver {
  /// Builds a set whose primary covers the most code points in [texts].
  ///
  /// Remaining uncovered points are assigned to later fallbacks that can
  /// render them. Candidates without `glyf` are ignored.
  static OfficeFontSet covering(
    Iterable<String> texts,
    Iterable<SfntFont> candidates,
  ) {
    final Set<int> cps = <int>{
      for (final String text in texts)
        for (final int cp in text.runes)
          if (cp >= 32) cp,
    };
    final List<SfntFont> glyf = <SfntFont>[
      for (final SfntFont font in candidates)
        if (font.hasTable('glyf')) font,
    ];
    if (glyf.isEmpty) {
      return const OfficeFontSet();
    }
    if (cps.isEmpty) {
      return OfficeFontSet(primary: glyf.first);
    }

    int score(SfntFont font) {
      var n = 0;
      for (final int cp in cps) {
        if (font.glyphIdFor(cp) != 0) {
          n++;
        }
      }
      return n;
    }

    final List<SfntFont> ranked = List<SfntFont>.from(glyf)
      ..sort((SfntFont a, SfntFont b) => score(b).compareTo(score(a)));
    final SfntFont primary = ranked.first;
    final Set<int> covered = <int>{
      for (final int cp in cps)
        if (primary.glyphIdFor(cp) != 0) cp,
    };
    final List<SfntFont> fallbacks = <SfntFont>[];
    for (final SfntFont font in ranked.skip(1)) {
      var helps = false;
      for (final int cp in cps) {
        if (covered.contains(cp)) {
          continue;
        }
        if (font.glyphIdFor(cp) != 0) {
          covered.add(cp);
          helps = true;
        }
      }
      if (helps) {
        fallbacks.add(font);
      }
    }
    return OfficeFontSet(primary: primary, fallbacks: fallbacks);
  }
}
