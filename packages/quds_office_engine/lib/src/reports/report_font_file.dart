/// TrueType files embedded in `.qrep` packages: inspection and face slots.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'report_fonts.dart';

/// Regular and bold TrueType files of one embedded family. At least one is
/// set; a missing face falls back to the other.
class ReportFontFiles {
  /// ReportFontFiles API.
  ReportFontFiles({this.regular, this.bold, this.italic, this.boldItalic})
    : assert(
        regular != null || bold != null || italic != null || boldItalic != null,
        'Need at least one face',
      );

  /// Upright regular face (weight closest to 400).
  final Uint8List? regular;

  /// Upright bold face (weight 600 or more).
  final Uint8List? bold;

  /// Italic face (`italic.ttf`).
  final Uint8List? italic;

  /// Bold-italic face (`boldItalic.ttf`).
  final Uint8List? boldItalic;

  /// Total size of the files in bytes.
  int get byteLength =>
      (regular?.length ?? 0) +
      (bold?.length ?? 0) +
      (italic?.length ?? 0) +
      (boldItalic?.length ?? 0);

  /// Copy with one face replaced.
  ReportFontFiles withFace(
    Uint8List bytes, {
    required bool bold,
    bool italic = false,
  }) => ReportFontFiles(
    regular: !bold && !italic ? bytes : regular,
    bold: bold && !italic ? bytes : this.bold,
    italic: !bold && italic ? bytes : this.italic,
    boldItalic: bold && italic ? bytes : boldItalic,
  );

  /// Registers this family in [registry] under [family].
  void registerIn(ReportFontRegistry registry, String family) {
    final Uint8List base = regular ?? bold ?? italic ?? boldItalic!;
    registry.registerBytes(
      family,
      base,
      bold: regular == null ? null : bold,
      italic: italic,
      boldItalic: boldItalic,
    );
  }
}

/// Writing systems a font preview can be shown in, each with sample text
/// and the code points that show a font covers it.
enum ReportScript {
  /// Latin letters.
  latin('The quick brown fox', <int>[0x41, 0x61, 0x7A]),

  /// Arabic.
  arabic('أبجد هوز حطي كلمن', <int>[0x627, 0x628, 0x644, 0x645]),

  /// Hebrew.
  hebrew('אבגד הוז חטי', <int>[0x5D0, 0x5D1, 0x5E9]),

  /// Devanagari (Hindi, Marathi, Nepali).
  devanagari('नमस्ते दुनिया', <int>[0x915, 0x92E, 0x938]),

  /// Bengali.
  bengali('নমস্কার বিশ্ব', <int>[0x995, 0x9AE, 0x9B8]),

  /// Tamil.
  tamil('வணக்கம் உலகம்', <int>[0xB95, 0xBAE, 0xBB5]),

  /// Thai.
  thai('สวัสดีชาวโลก', <int>[0xE01, 0xE19, 0xE2A]),

  /// Ethiopic (Amharic, Tigrinya).
  ethiopic('ሰላም ዓለም', <int>[0x1200, 0x1208, 0x1230]),

  /// Armenian.
  armenian('Բարեւ աշխարհ', <int>[0x531, 0x561, 0x562]),

  /// Georgian.
  georgian('გამარჯობა', <int>[0x10D0, 0x10D1, 0x10E1]),

  /// Korean Hangul.
  hangul('안녕하세요', <int>[0xAC00, 0xD55C, 0xAE00]),

  /// Japanese kana.
  kana('こんにちは', <int>[0x3042, 0x3093, 0x30A2]),

  /// Chinese characters (Han).
  han('永和九年 中文', <int>[0x4E2D, 0x6587, 0x6C38]),

  /// Greek.
  greek('Γειά σου κόσμε', <int>[0x391, 0x3A9, 0x3B1]),

  /// Cyrillic.
  cyrillic('Привет, мир', <int>[0x416, 0x431, 0x44F]);

  const ReportScript(this.sample, this.probes);

  /// Short sample text written in this script.
  final String sample;

  /// Code points a font must map to cover this script.
  final List<int> probes;

  /// Text that previews a font covering [scripts] in its own writing: Latin
  /// fonts show a Latin sample (plus Arabic when they cover it too), other
  /// fonts the sample of their first script.
  static String previewText(Set<ReportScript> scripts) {
    if (scripts.isEmpty) {
      return latin.sample;
    }
    if (scripts.contains(latin)) {
      return scripts.contains(arabic) ? 'Abc  أبجد هوز' : latin.sample;
    }
    for (final ReportScript s in values) {
      if (scripts.contains(s)) {
        return s.sample;
      }
    }
    return latin.sample;
  }

  /// Primary script for [scripts]: Latin when covered, else the first one.
  static ReportScript primary(Set<ReportScript> scripts) {
    if (scripts.isEmpty || scripts.contains(latin)) {
      return latin;
    }
    return values.firstWhere(scripts.contains);
  }
}

/// What a TrueType file declares in its `name`, `OS/2`, `head` and `cmap`
/// tables.
class ReportFontFileInfo {
  /// ReportFontFileInfo API.
  const ReportFontFileInfo({
    required this.family,
    required this.weight,
    required this.italic,
    this.scripts = const <ReportScript>{},
  });

  /// Writing systems the font's character map covers.
  final Set<ReportScript> scripts;

  /// Typographic family (name ID 16, else 1), English when available.
  final String family;

  /// `usWeightClass` (400 regular, 700 bold).
  final int weight;

  /// Italic or oblique face.
  final bool italic;

  /// Whether the face fills the bold slot (weight 600 or more).
  bool get bold => weight >= 600;

  /// Human-readable face name, e.g. `Bold` or `SemiBold Italic`.
  String get style {
    final String w = switch (weight) {
      < 150 => 'Thin',
      < 250 => 'ExtraLight',
      < 350 => 'Light',
      < 450 => 'Regular',
      < 550 => 'Medium',
      < 650 => 'SemiBold',
      < 750 => 'Bold',
      < 850 => 'ExtraBold',
      _ => 'Black',
    };
    if (!italic) {
      return w;
    }
    return w == 'Regular' ? 'Italic' : '$w Italic';
  }
}

/// Reads TrueType headers without parsing glyphs, so a host can scan
/// installed fonts quickly and reports only embed files they can draw.
abstract final class ReportFontFile {
  /// Inspects in-memory font bytes; see [inspectWith].
  static ReportFontFileInfo inspect(Uint8List bytes) =>
      inspectWith((int offset, int length) {
        if (offset < 0 || offset + length > bytes.length) {
          throw const ReportFontException('Font file is truncated');
        }
        return Uint8List.sublistView(bytes, offset, offset + length);
      });

  /// Inspects a font through [read] (`offset`, `length` → bytes), which lets
  /// a host read only the table directory, `name`, `OS/2` and `head` of a
  /// file on disk.
  ///
  /// Throws [ReportFontException] for collections (`.ttc`), CFF outlines
  /// (`.otf`), files without a family name, and fonts whose license
  /// (`OS/2 fsType`) forbids embedding.
  static ReportFontFileInfo inspectWith(
    Uint8List Function(int offset, int length) read,
  ) {
    final ByteData header = ByteData.sublistView(read(0, 12));
    final int version = header.getUint32(0);
    if (version == 0x74746366) {
      throw const ReportFontException(
        'Font collections (.ttc) are not supported; use a single .ttf',
      );
    }
    if (version == 0x4F54544F) {
      throw const ReportFontException(
        'CFF/OpenType outlines (.otf) cannot be embedded; use a TrueType .ttf',
      );
    }
    if (version != 0x00010000 && version != 0x74727565) {
      throw const ReportFontException('Not a TrueType font');
    }
    final int count = header.getUint16(4);
    if (count == 0 || count > 200) {
      throw const ReportFontException('Damaged font table directory');
    }
    final ByteData dir = ByteData.sublistView(read(12, count * 16));
    final Map<String, (int, int)> tables = <String, (int, int)>{};
    for (int i = 0; i < count; i++) {
      final int at = i * 16;
      final String tag = String.fromCharCodes(<int>[
        dir.getUint8(at),
        dir.getUint8(at + 1),
        dir.getUint8(at + 2),
        dir.getUint8(at + 3),
      ]);
      tables[tag] = (dir.getUint32(at + 8), dir.getUint32(at + 12));
    }
    for (final String tag in const <String>[
      'glyf',
      'loca',
      'cmap',
      'head',
      'hhea',
      'hmtx',
      'maxp',
    ]) {
      if (!tables.containsKey(tag)) {
        throw ReportFontException(
          tag == 'glyf'
              ? 'Font has no TrueType outlines (glyf); use a TrueType .ttf'
              : 'Font is missing its $tag table',
        );
      }
    }
    ByteData table(String tag) {
      final (int offset, int length) = tables[tag]!;
      return ByteData.sublistView(read(offset, length));
    }

    var weight = 400;
    var italic = false;
    if (tables.containsKey('OS/2')) {
      final ByteData os2 = table('OS/2');
      if (os2.lengthInBytes >= 64) {
        weight = os2.getUint16(4);
        final int fsType = os2.getUint16(8);
        if (fsType & 0x000F == 0x0002) {
          throw const ReportFontException(
            'The font license forbids embedding (restricted fsType)',
          );
        }
        final int fsSelection = os2.getUint16(62);
        italic = fsSelection & 0x0001 != 0 || fsSelection & 0x0200 != 0;
        if (fsSelection & 0x0020 != 0 && weight < 600) {
          weight = 700;
        }
      }
    } else {
      final ByteData head = table('head');
      final int macStyle = head.getUint16(44);
      weight = macStyle & 0x0001 != 0 ? 700 : 400;
      italic = macStyle & 0x0002 != 0;
    }
    if (weight < 1 || weight > 1000) {
      weight = 400;
    }
    if (!tables.containsKey('name')) {
      throw const ReportFontException('Font has no name table');
    }
    final String family = _family(table('name')).trim();
    if (family.isEmpty) {
      throw const ReportFontException('Font has no family name');
    }
    return ReportFontFileInfo(
      family: family,
      weight: weight,
      italic: italic,
      scripts: _scripts(table('cmap')),
    );
  }

  /// Scripts whose probe code points all map to glyphs in [cmap]; empty
  /// when no Unicode subtable can be read.
  static Set<ReportScript> _scripts(ByteData cmap) {
    final bool Function(int)? has = _cmapLookup(cmap);
    if (has == null) {
      return const <ReportScript>{};
    }
    return <ReportScript>{
      for (final ReportScript s in ReportScript.values)
        if (s.probes.every(has)) s,
    };
  }

  /// Lookup over the best Unicode subtable (format 12, else format 4).
  static bool Function(int)? _cmapLookup(ByteData cmap) {
    if (cmap.lengthInBytes < 4) {
      return null;
    }
    final int count = cmap.getUint16(2);
    int? format4;
    int? format12;
    for (int i = 0; i < count; i++) {
      final int at = 4 + i * 8;
      if (at + 8 > cmap.lengthInBytes) {
        break;
      }
      final int platform = cmap.getUint16(at);
      final int encoding = cmap.getUint16(at + 2);
      final int offset = cmap.getUint32(at + 4);
      if (offset + 4 > cmap.lengthInBytes) {
        continue;
      }
      final bool unicode =
          platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
      if (!unicode) {
        continue;
      }
      switch (cmap.getUint16(offset)) {
        case 4:
          format4 ??= offset;
        case 12:
          format12 ??= offset;
      }
    }
    if (format12 != null) {
      return _format12(cmap, format12);
    }
    if (format4 != null) {
      return _format4(cmap, format4);
    }
    return null;
  }

  static bool Function(int)? _format12(ByteData d, int at) {
    if (at + 16 > d.lengthInBytes) {
      return null;
    }
    final int groups = d.getUint32(at + 12);
    final int first = at + 16;
    final int n = math.min(groups, (d.lengthInBytes - first) ~/ 12);
    return (int c) {
      var lo = 0;
      var hi = n - 1;
      while (lo <= hi) {
        final int mid = (lo + hi) >> 1;
        final int g = first + mid * 12;
        final int start = d.getUint32(g);
        final int end = d.getUint32(g + 4);
        if (c < start) {
          hi = mid - 1;
        } else if (c > end) {
          lo = mid + 1;
        } else {
          return d.getUint32(g + 8) + (c - start) != 0;
        }
      }
      return false;
    };
  }

  static bool Function(int)? _format4(ByteData d, int at) {
    if (at + 14 > d.lengthInBytes) {
      return null;
    }
    final int segs = d.getUint16(at + 6) ~/ 2;
    final int ends = at + 14;
    final int starts = ends + segs * 2 + 2;
    final int deltas = starts + segs * 2;
    final int ranges = deltas + segs * 2;
    if (ranges + segs * 2 > d.lengthInBytes) {
      return null;
    }
    return (int c) {
      if (c > 0xFFFF) {
        return false;
      }
      for (int i = 0; i < segs; i++) {
        if (d.getUint16(ends + i * 2) < c) {
          continue;
        }
        final int start = d.getUint16(starts + i * 2);
        if (start > c) {
          return false;
        }
        final int delta = d.getUint16(deltas + i * 2);
        final int rangeAt = ranges + i * 2;
        final int range = d.getUint16(rangeAt);
        if (range == 0) {
          return (c + delta) & 0xFFFF != 0;
        }
        final int glyphAt = rangeAt + range + (c - start) * 2;
        if (glyphAt + 2 > d.lengthInBytes) {
          return false;
        }
        return d.getUint16(glyphAt) != 0;
      }
      return false;
    };
  }

  static String _family(ByteData name) {
    if (name.lengthInBytes < 6) {
      return '';
    }
    final int count = name.getUint16(2);
    final int strings = name.getUint16(4);
    var best = '';
    var bestScore = -1;
    for (int i = 0; i < count; i++) {
      final int at = 6 + i * 12;
      if (at + 12 > name.lengthInBytes) {
        break;
      }
      final int platform = name.getUint16(at);
      final int encoding = name.getUint16(at + 2);
      final int language = name.getUint16(at + 4);
      final int id = name.getUint16(at + 6);
      final int length = name.getUint16(at + 8);
      final int offset = strings + name.getUint16(at + 10);
      if ((id != 1 && id != 16) || offset + length > name.lengthInBytes) {
        continue;
      }
      final bool windows = platform == 3 && (encoding == 1 || encoding == 10);
      final bool mac = platform == 1 && encoding == 0;
      if (!windows && !mac) {
        continue;
      }
      final int score =
          (id == 16 ? 4 : 0) +
          (windows ? 2 : 0) +
          (language == 0x409 || (mac && language == 0) ? 1 : 0);
      if (score <= bestScore) {
        continue;
      }
      final StringBuffer s = StringBuffer();
      if (windows) {
        for (int j = 0; j + 1 < length; j += 2) {
          s.writeCharCode(name.getUint16(offset + j));
        }
      } else {
        for (int j = 0; j < length; j++) {
          s.writeCharCode(name.getUint8(offset + j));
        }
      }
      best = s.toString();
      bestScore = score;
    }
    return best;
  }
}
