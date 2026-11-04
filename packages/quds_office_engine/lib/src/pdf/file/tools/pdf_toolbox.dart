import 'dart:typed_data';

import '../../../bidi/arabic_shaping.dart';
import '../../../fonts/font_subsetter.dart';
import '../../../fonts/sfnt_parser.dart';
import '../model/pdf_file.dart';
import '../model/pdf_page_info.dart';
import 'pdf_page_graft.dart';
import 'pdf_page_view.dart';

/// How [PdfToolbox.extract] writes several ranges.
enum PdfExtractMode {
  /// Every range, from every source, in order, one file.
  oneFile,

  /// One file per range, including several ranges from the same file.
  perRange,
}

/// How [PdfToolbox.split] cuts one file.
enum PdfSplitKind {
  /// Groups of [PdfSplitSpec.chunk] pages.
  every,

  /// One file per page.
  burst,

  /// Odd pages (1-based) in one file.
  odd,

  /// Even pages (1-based) in one file.
  even,

  /// A file starting at each outline entry that has a page.
  bookmarks,
}

/// Split rule.
class PdfSplitSpec {
  /// PdfSplitSpec API.
  const PdfSplitSpec.every(this.chunk) : kind = PdfSplitKind.every;

  /// PdfSplitSpec API.
  const PdfSplitSpec.burst() : kind = PdfSplitKind.burst, chunk = 1;

  /// PdfSplitSpec API.
  const PdfSplitSpec.odd() : kind = PdfSplitKind.odd, chunk = 1;

  /// PdfSplitSpec API.
  const PdfSplitSpec.even() : kind = PdfSplitKind.even, chunk = 1;

  /// PdfSplitSpec API.
  const PdfSplitSpec.bookmarks() : kind = PdfSplitKind.bookmarks, chunk = 1;

  /// kind API.
  final PdfSplitKind kind;

  /// Pages per output when [kind] is [PdfSplitKind.every].
  final int chunk;
}

/// One input file and the ranges to take from it.
///
/// [ranges] is a list of range groups. A single file may contribute several
/// groups (`1-3`, `8-10`, `15`). Commas inside a group select pages of that
/// group. An empty list means the whole file, as one group.
class PdfPageSource {
  /// PdfPageSource API.
  const PdfPageSource(
    this.bytes, {
    this.ranges = const <String>[],
    this.rotate = 0,
    this.reverse = false,
  });

  /// File bytes.
  final Uint8List bytes;

  /// Range groups, 1-based. `8-` runs to the last page. Empty means all pages.
  final List<String> ranges;

  /// Extra clockwise `/Rotate`, in 90° steps. Does not swap the page box.
  final int rotate;

  /// reverse API.
  final bool reverse;
}

/// Page assembly: merge, split, extract, reorder, rotate.
///
/// Outputs are new files. Resources travel with each page.
abstract final class PdfToolbox {
  /// Concatenates [sources] in order into one PDF.
  static Uint8List merge(List<PdfPageSource> sources) {
    return _one(_slots(sources));
  }

  /// Extracts ranges. [PdfExtractMode.perRange] yields one file per group,
  /// so one source with three ranges yields three files.
  static List<Uint8List> extract(
    List<PdfPageSource> sources, {
    PdfExtractMode mode = PdfExtractMode.oneFile,
  }) {
    if (mode == PdfExtractMode.oneFile) {
      return <Uint8List>[_one(_slots(sources))];
    }
    final List<Uint8List> out = <Uint8List>[];
    for (final PdfPageSource source in sources) {
      final PdfFile file = PdfFile.open(source.bytes);
      for (final List<int> group in _groups(file, source)) {
        out.add(_one(_fromIndices(file, group, source.rotate)));
      }
    }
    if (out.isEmpty) {
      throw ArgumentError('extract produced no pages');
    }
    return out;
  }

  /// Cuts [bytes] according to [spec].
  static List<Uint8List> split(Uint8List bytes, PdfSplitSpec spec) {
    final PdfFile file = PdfFile.open(bytes);
    final List<List<int>> groups = _splitGroups(file, spec);
    return <Uint8List>[
      for (final List<int> group in groups)
        if (group.isNotEmpty) _one(_fromIndices(file, group, 0)),
    ];
  }

  /// Keeps [order] (0-based, duplicates allowed) and drops the rest.
  static Uint8List reorder(Uint8List bytes, List<int> order) {
    final PdfFile file = PdfFile.open(bytes);
    if (order.isEmpty) {
      throw ArgumentError('reorder requires at least one page');
    }
    return _one(_fromIndices(file, order, 0));
  }

  /// Drops pages selected by [ranges] (1-based groups).
  static Uint8List remove(Uint8List bytes, List<String> ranges) {
    final PdfFile file = PdfFile.open(bytes);
    final Set<int> drop = <int>{
      for (final List<int> group in _groups(
        file,
        PdfPageSource(bytes, ranges: ranges),
      ))
        ...group,
    };
    final List<int> keep = <int>[
      for (int i = 0; i < file.pageCount; i++)
        if (!drop.contains(i)) i,
    ];
    if (keep.isEmpty) {
      throw ArgumentError('remove would leave no pages');
    }
    return _one(_fromIndices(file, keep, 0));
  }

  /// Adds [degrees] (90, 180, 270, or negative) to `/Rotate`.
  ///
  /// [ranges] empty rotates every page. The media box is not rewritten.
  static Uint8List rotate(
    Uint8List bytes, {
    int degrees = 90,
    List<String> ranges = const <String>[],
  }) {
    PdfPageView.normalizeQuarter(degrees);
    final PdfFile file = PdfFile.open(bytes);
    final Set<int> chosen = ranges.isEmpty
        ? <int>{for (int i = 0; i < file.pageCount; i++) i}
        : <int>{
            for (final List<int> group in _groups(
              file,
              PdfPageSource(bytes, ranges: ranges),
            ))
              ...group,
          };
    return _one(<PdfGraftSlot>[
      for (int i = 0; i < file.pageCount; i++)
        PdfGraftSlot.page(
          file,
          i,
          extraRotate: chosen.contains(i) ? degrees : 0,
        ),
    ]);
  }

  /// Reverses page order.
  static Uint8List reverse(Uint8List bytes) {
    final PdfFile file = PdfFile.open(bytes);
    return _one(
      _fromIndices(file, <int>[
        for (int i = file.pageCount - 1; i >= 0; i--) i,
      ], 0),
    );
  }

  /// Inserts a blank page at [index] (0-based, clamped). Does not rotate.
  static Uint8List insertBlank(
    Uint8List bytes,
    int index, {
    double width = 595.28,
    double height = 841.89,
  }) {
    final PdfFile file = PdfFile.open(bytes);
    final int at = index.clamp(0, file.pageCount);
    final List<PdfGraftSlot> slots = <PdfGraftSlot>[
      for (int i = 0; i < file.pageCount; i++) PdfGraftSlot.page(file, i),
    ];
    slots.insert(at, PdfGraftSlot.blank(width: width, height: height));
    return _one(slots);
  }

  /// Paints [text] over selected pages. Without [fontBytes] the face is
  /// Helvetica and non-Latin letters are skipped. With [fontBytes] the face
  /// is embedded and Arabic is shaped before the glyphs are shown.
  static Uint8List stamp(
    Uint8List bytes, {
    required String text,
    double fontSize = 48,
    double opacity = 0.22,
    List<String> ranges = const <String>[],
    Uint8List? fontBytes,
  }) {
    final double size = fontSize < 6 ? 6 : fontSize;
    if (fontBytes == null) {
      final String literal = _pdfLiteral(text);
      if (literal.isEmpty) {
        throw ArgumentError('stamp text is empty');
      }
      return _decorate(
        bytes,
        ranges: ranges,
        overlay: (PdfPageInfo page, int index, int count) {
          final double width = size * 0.5 * literal.length;
          final double x = page.cropBox.llx + (page.cropBox.width - width) / 2;
          final double y = page.cropBox.lly + page.cropBox.height / 2;
          return _overlay(literal, size, x, y);
        },
        opacity: opacity,
      );
    }
    final _EmbeddedStamp face = _EmbeddedStamp(fontBytes, text);
    if (face.hex(text).isEmpty) {
      throw ArgumentError('stamp text is empty');
    }
    return _decorate(
      bytes,
      ranges: ranges,
      embeddedFont: face.bytes,
      overlay: (PdfPageInfo page, int index, int count) {
        final double width = face.width(text, size);
        final double x = page.cropBox.llx + (page.cropBox.width - width) / 2;
        final double y = page.cropBox.lly + page.cropBox.height / 2;
        return face.overlay(text, size, x, y);
      },
      opacity: opacity,
    );
  }

  /// Footer page numbers. [pattern] may contain `{n}` and `{N}`.
  ///
  /// Optional [bates] is a prefix in the top corner (`FILE-000001`).
  /// [fontBytes] embeds that face and shapes Arabic; otherwise Helvetica.
  static Uint8List numberPages(
    Uint8List bytes, {
    String pattern = '{n} / {N}',
    int start = 1,
    String bates = '',
    int batesDigits = 6,
    String header = '',
    List<String> ranges = const <String>[],
    Uint8List? fontBytes,
  }) {
    final _EmbeddedStamp? face = fontBytes == null
        ? null
        : _EmbeddedStamp(
            fontBytes,
            '$pattern $bates $header 0123456789/',
          );
    return _decorate(
      bytes,
      ranges: ranges,
      embeddedFont: face?.bytes,
      overlay: (PdfPageInfo page, int index, int count) {
        final int shown = start + index;
        final String rawLabel = pattern
            .replaceAll('{n}', '$shown')
            .replaceAll('{N}', '$count');
        final String label = face == null ? _pdfLiteral(rawLabel) : rawLabel;
        final double size = 10;
        final double width = face == null
            ? size * 0.5 * label.length
            : face.width(label, size);
        final double x = page.cropBox.llx + (page.cropBox.width - width) / 2;
        final double y = page.cropBox.lly + 28;
        final StringBuffer ops = StringBuffer(
          face == null
              ? _overlay(label, size, x, y)
              : face.overlay(label, size, x, y),
        );
        if (bates.trim().isNotEmpty) {
          final String rawMark =
              '${bates.trim()}-${shown.toString().padLeft(batesDigits < 1 ? 1 : batesDigits, '0')}';
          final String mark = face == null ? _pdfLiteral(rawMark) : rawMark;
          final double markWidth = face == null
              ? size * 0.52 * mark.length
              : face.width(mark, 9);
          final double bx = page.cropBox.urx - 36 - markWidth;
          final double by = page.cropBox.ury - 36;
          ops.write(
            face == null
                ? _overlay(mark, 9, bx, by)
                : face.overlay(mark, 9, bx, by),
          );
        }
        if (header.trim().isNotEmpty) {
          final String head = face == null ? _pdfLiteral(header) : header;
          if (head.isNotEmpty) {
            ops.write(
              face == null
                  ? _overlay(head, 10, page.cropBox.llx + 36, page.cropBox.ury - 36)
                  : face.overlay(
                      head,
                      10,
                      page.cropBox.llx + 36,
                      page.cropBox.ury - 36,
                    ),
            );
          }
        }
        return ops.toString();
      },
    );
  }

  /// Insets CropBox. Does not rewrite the content stream or MediaBox.
  static Uint8List crop(
    Uint8List bytes, {
    double left = 0,
    double bottom = 0,
    double right = 0,
    double top = 0,
    List<String> ranges = const <String>[],
  }) {
    if (left < 0 || bottom < 0 || right < 0 || top < 0) {
      throw ArgumentError('crop insets are not negative');
    }
    final PdfFile file = PdfFile.open(bytes);
    final Set<int> chosen = ranges.isEmpty
        ? <int>{for (int i = 0; i < file.pageCount; i++) i}
        : <int>{
            for (final List<int> group in _groups(
              file,
              PdfPageSource(bytes, ranges: ranges),
            ))
              ...group,
          };
    return _one(<PdfGraftSlot>[
      for (int i = 0; i < file.pageCount; i++)
        PdfGraftSlot.page(
          file,
          i,
          cropLeft: chosen.contains(i) ? left : 0,
          cropBottom: chosen.contains(i) ? bottom : 0,
          cropRight: chosen.contains(i) ? right : 0,
          cropTop: chosen.contains(i) ? top : 0,
        ),
    ]);
  }

  static Uint8List _decorate(
    Uint8List bytes, {
    required List<String> ranges,
    required String Function(PdfPageInfo page, int index, int count) overlay,
    double opacity = 1,
    Uint8List? embeddedFont,
  }) {
    final PdfFile file = PdfFile.open(bytes);
    final Set<int> chosen = ranges.isEmpty
        ? <int>{for (int i = 0; i < file.pageCount; i++) i}
        : <int>{
            for (final List<int> group in _groups(
              file,
              PdfPageSource(bytes, ranges: ranges),
            ))
              ...group,
          };
    return _one(<PdfGraftSlot>[
      for (int i = 0; i < file.pageCount; i++)
        PdfGraftSlot.page(
          file,
          i,
          overlay: chosen.contains(i)
              ? overlay(file.pageAt(i), i, file.pageCount)
              : null,
          overlayOpacity: opacity,
          embeddedFont: chosen.contains(i) ? embeddedFont : null,
        ),
    ]);
  }

  static String _overlay(String literal, double size, double x, double y) {
    return 'q /QzG gs 0.35 0.35 0.35 rg BT /QzF $size Tf 1 0 0 1 $x $y Tm ($literal) Tj ET Q\n';
  }

  static String _pdfLiteral(String text) {
    final String trimmed = text.trim();
    final StringBuffer out = StringBuffer();
    for (final int unit in trimmed.codeUnits) {
      if (unit < 32 || unit > 126) {
        continue;
      }
      if (unit == 0x28 || unit == 0x29 || unit == 0x5C) {
        out.write('\\');
      }
      out.writeCharCode(unit);
    }
    return out.toString();
  }

  /// Inserts pages from [source] at [index] (0-based).
  static Uint8List insertFrom(
    Uint8List bytes,
    int index,
    PdfPageSource source,
  ) {
    final PdfFile dest = PdfFile.open(bytes);
    final int at = index.clamp(0, dest.pageCount);
    final List<PdfGraftSlot> incoming = _slots(<PdfPageSource>[source]);
    final List<PdfGraftSlot> slots = <PdfGraftSlot>[
      for (int i = 0; i < dest.pageCount; i++) PdfGraftSlot.page(dest, i),
    ];
    slots.insertAll(at, incoming);
    return _one(slots);
  }

  /// Interleaves pages: A1, B1, A2, B2, then any remainder.
  static Uint8List mix(PdfPageSource a, PdfPageSource b) {
    final List<PdfGraftSlot> left = _slots(<PdfPageSource>[a]);
    final List<PdfGraftSlot> right = _slots(<PdfPageSource>[b]);
    final List<PdfGraftSlot> slots = <PdfGraftSlot>[];
    final int n = left.length > right.length ? left.length : right.length;
    for (int i = 0; i < n; i++) {
      if (i < left.length) {
        slots.add(left[i]);
      }
      if (i < right.length) {
        slots.add(right[i]);
      }
    }
    return _one(slots);
  }

  /// Resolves a 1-based range group against [pageCount].
  static List<int> resolveRange(String spec, int pageCount) {
    if (pageCount < 1) {
      throw ArgumentError('file has no pages');
    }
    final String raw = spec.trim();
    if (raw.isEmpty) {
      return <int>[for (int i = 0; i < pageCount; i++) i];
    }
    final List<int> out = <int>[];
    for (final String part in raw.split(',')) {
      final String token = part.trim();
      if (token.isEmpty) {
        continue;
      }
      final int dash = token.indexOf('-');
      if (dash < 0) {
        out.add(_oneBased(token, pageCount) - 1);
        continue;
      }
      final String startRaw = token.substring(0, dash).trim();
      final String endRaw = token.substring(dash + 1).trim();
      final int start = startRaw.isEmpty ? 1 : _oneBased(startRaw, pageCount);
      final int end = endRaw.isEmpty ? pageCount : _oneBased(endRaw, pageCount);
      if (end < start) {
        throw ArgumentError('range $token is reversed; use reverse()');
      }
      for (int page = start; page <= end; page++) {
        out.add(page - 1);
      }
    }
    if (out.isEmpty) {
      throw ArgumentError('range "$spec" selected no pages');
    }
    return out;
  }

  static List<PdfGraftSlot> _slots(List<PdfPageSource> sources) {
    final List<PdfGraftSlot> slots = <PdfGraftSlot>[];
    for (final PdfPageSource source in sources) {
      final PdfFile file = PdfFile.open(source.bytes);
      for (final List<int> group in _groups(file, source)) {
        slots.addAll(_fromIndices(file, group, source.rotate));
      }
    }
    if (slots.isEmpty) {
      throw ArgumentError('no pages selected');
    }
    return slots;
  }

  static List<List<int>> _groups(PdfFile file, PdfPageSource source) {
    final List<String> specs = source.ranges.isEmpty
        ? const <String>['']
        : source.ranges;
    return <List<int>>[
      for (final String spec in specs)
        _maybeReverse(resolveRange(spec, file.pageCount), source.reverse),
    ];
  }

  static List<int> _maybeReverse(List<int> pages, bool reverse) {
    if (!reverse) {
      return pages;
    }
    return pages.reversed.toList(growable: false);
  }

  static List<PdfGraftSlot> _fromIndices(
    PdfFile file,
    List<int> indices,
    int rotate,
  ) {
    return <PdfGraftSlot>[
      for (final int index in indices)
        PdfGraftSlot.page(file, index, extraRotate: rotate),
    ];
  }

  static List<List<int>> _splitGroups(PdfFile file, PdfSplitSpec spec) {
    final int n = file.pageCount;
    switch (spec.kind) {
      case PdfSplitKind.burst:
        return <List<int>>[
          for (int i = 0; i < n; i++) <int>[i],
        ];
      case PdfSplitKind.odd:
        return <List<int>>[
          <int>[for (int i = 0; i < n; i += 2) i],
        ];
      case PdfSplitKind.even:
        return <List<int>>[
          <int>[for (int i = 1; i < n; i += 2) i],
        ];
      case PdfSplitKind.every:
        final int chunk = spec.chunk < 1 ? 1 : spec.chunk;
        final List<List<int>> groups = <List<int>>[];
        for (int i = 0; i < n; i += chunk) {
          final int end = i + chunk > n ? n : i + chunk;
          groups.add(<int>[for (int p = i; p < end; p++) p]);
        }
        return groups;
      case PdfSplitKind.bookmarks:
        final List<int> marks = <int>[];
        void walk(PdfOutlineNode? node) {
          if (node == null) {
            return;
          }
          final int? page = node.pageIndex;
          if (page != null && page >= 0 && page < n && !marks.contains(page)) {
            marks.add(page);
          }
          for (final PdfOutlineNode child in node.children) {
            walk(child);
          }
        }
        walk(file.outline);
        marks.sort();
        if (marks.isEmpty || marks.first != 0) {
          marks.insert(0, 0);
        }
        final List<List<int>> groups = <List<int>>[];
        for (int i = 0; i < marks.length; i++) {
          final int start = marks[i];
          final int end = i + 1 < marks.length ? marks[i + 1] : n;
          if (end > start) {
            groups.add(<int>[for (int p = start; p < end; p++) p]);
          }
        }
        return groups.isEmpty
            ? <List<int>>[
                <int>[for (int i = 0; i < n; i++) i],
              ]
            : groups;
    }
  }

  static int _oneBased(String token, int pageCount) {
    final int? page = int.tryParse(token);
    if (page == null || page < 1 || page > pageCount) {
      throw ArgumentError('page $token is outside 1-$pageCount');
    }
    return page;
  }

  static Uint8List _one(List<PdfGraftSlot> slots) => PdfPageGraft.write(slots);
}

class _EmbeddedStamp {
  _EmbeddedStamp(Uint8List fontBytes, String sample)
    : font = SfntFont.parse(fontBytes),
      subset = FontSubsetter(SfntFont.parse(fontBytes)).subset(
        <int>{
          for (final ShapedChar char in ArabicShaper.shape(sample))
            char.codePoint,
        },
      );

  final SfntFont font;
  final FontSubset subset;

  Uint8List get bytes => subset.bytes;

  String hex(String text) {
    final StringBuffer out = StringBuffer();
    for (final ShapedChar char in ArabicShaper.shape(text)) {
      final int gid = subset.unicodeToNewGlyph[char.codePoint] ?? 0;
      if (gid == 0 || char.advanceFactor == 0) {
        continue;
      }
      out.write(gid.toRadixString(16).padLeft(4, '0'));
    }
    return out.toString();
  }

  double width(String text, double size) {
    var w = 0.0;
    for (final ShapedChar char in ArabicShaper.shape(text)) {
      if (char.advanceFactor == 0) {
        continue;
      }
      final int old = font.glyphIdFor(char.codePoint);
      w += font.advanceWidth(old) * size / font.unitsPerEm * char.advanceFactor;
    }
    return w;
  }

  String overlay(String text, double size, double x, double y) {
    final String glyphs = hex(text);
    if (glyphs.isEmpty) {
      return '';
    }
    return 'q /QzG gs 0.35 0.35 0.35 rg BT /QzF $size Tf 1 0 0 1 $x $y Tm <$glyphs> Tj ET Q\n';
  }
}
