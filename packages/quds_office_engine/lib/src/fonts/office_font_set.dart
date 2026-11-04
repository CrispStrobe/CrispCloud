import 'sfnt_parser.dart';

/// One or more glyf-backed faces used when embedding PDF text.
///
/// CFF/`FontFile3` faces are intentionally skipped — prefer TrueType/`glyf`
/// candidates (or fall back to Helvetica for WinAnsi Latin).
class OfficeFontSet {
  /// OfficeFontSet API.
  const OfficeFontSet({this.primary, this.fallbacks = const <SfntFont>[]});

  /// Primary face (used first when it covers a code point).
  final SfntFont? primary;

  /// Additional faces tried in order after [primary].
  final List<SfntFont> fallbacks;

  /// Single-face sugar.
  factory OfficeFontSet.single(SfntFont? font) => OfficeFontSet(primary: font);

  /// True when no faces were supplied.
  bool get isEmpty =>
      primary == null && fallbacks.isEmpty;

  /// Embeddable candidates (`glyf` table present), primary first.
  List<SfntFont> get embeddable {
    final List<SfntFont> out = <SfntFont>[];
    void add(SfntFont? font) {
      if (font == null || !font.hasTable('glyf')) {
        return;
      }
      out.add(font);
    }

    add(primary);
    for (final SfntFont font in fallbacks) {
      add(font);
    }
    return out;
  }

  /// First embeddable face with a non-zero glyph for [codePoint].
  SfntFont? faceFor(int codePoint) {
    for (final SfntFont font in embeddable) {
      if (font.glyphIdFor(codePoint) != 0) {
        return font;
      }
    }
    return null;
  }
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
