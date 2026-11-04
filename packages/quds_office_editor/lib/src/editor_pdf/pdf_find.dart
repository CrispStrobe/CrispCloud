import 'dart:ui' show Rect;

import 'package:quds_office_engine/quds_office_engine.dart';

import 'pdf_text_selection.dart';

/// One search hit: page-local highlight boxes for the matching span.
class PdfFindMark {
  /// PdfFindMark API.
  const PdfFindMark({
    required this.page,
    required this.rects,
    this.preview = '',
  });

  /// Zero-based page.
  final int page;

  /// Matching slices in unrotated crop top-left space.
  final List<Rect> rects;

  /// Short excerpt around the match.
  final String preview;
}

/// Display-list search. Matches the text the viewer can select, including a
/// span that crosses several runs, and folds Arabic presentation forms.
abstract final class PdfFind {
  /// Every match of [query] in [lists], in reading order.
  static List<PdfFindMark> search(List<PdfDisplayList> lists, String query) {
    final String needle = fold(query);
    if (needle.isEmpty) {
      return const <PdfFindMark>[];
    }
    final List<PdfFindMark> hits = <PdfFindMark>[];
    for (int page = 0; page < lists.length; page++) {
      final List<PdfTextRun> runs = lists[page].runs;
      if (runs.isEmpty) {
        continue;
      }
      final _Haystack hay = _Haystack.of(runs);
      var from = 0;
      while (from <= hay.folded.length - needle.length) {
        final int at = hay.folded.indexOf(needle, from);
        if (at < 0) {
          break;
        }
        final int end = at + needle.length;
        final List<Rect> rects = hay.rects(runs, at, end);
        if (rects.isNotEmpty) {
          hits.add(
            PdfFindMark(
              page: page,
              rects: rects,
              preview: hay.excerpt(at, end),
            ),
          );
        }
        from = at + needle.length;
      }
    }
    return hits;
  }

  /// Case-fold and map Arabic presentation forms to isolated letters.
  static String fold(String text) {
    final StringBuffer out = StringBuffer();
    for (final int cp in text.runes) {
      for (final int folded in _foldCodePoint(cp)) {
        out.writeCharCode(folded);
      }
    }
    return out.toString();
  }
}

class _Haystack {
  _Haystack(this.folded, this.map);

  final String folded;

  /// Folded index → (run, code-unit offset in that run).
  final List<({int run, int offset})> map;

  static _Haystack of(List<PdfTextRun> runs) {
    final StringBuffer folded = StringBuffer();
    final List<({int run, int offset})> map = <({int run, int offset})>[];
    for (int r = 0; r < runs.length; r++) {
      final PdfTextRun run = runs[r];
      if (folded.isNotEmpty && run.breakBefore) {
        folded.write('\n');
        map.add((run: r, offset: 0));
      }
      var unit = 0;
      for (final int cp in run.text.runes) {
        final int width = cp > 0xFFFF ? 2 : 1;
        final List<int> chars = _foldCodePoint(cp);
        for (int i = 0; i < chars.length; i++) {
          folded.writeCharCode(chars[i]);
          map.add((run: r, offset: unit));
        }
        unit += width;
      }
    }
    return _Haystack(folded.toString(), map);
  }

  List<Rect> rects(List<PdfTextRun> runs, int from, int to) {
    if (map.isEmpty || from >= to || runs.isEmpty) {
      return const <Rect>[];
    }
    final int start = from.clamp(0, map.length - 1);
    final int last = (to - 1).clamp(0, map.length - 1);
    final List<Rect> out = <Rect>[];
    var run = map[start].run;
    var a = map[start].offset;
    var b = a + 1;
    for (int i = start + 1; i <= last; i++) {
      final ({int run, int offset}) at = map[i];
      if (at.run == run) {
        if (at.offset + 1 > b) {
          b = at.offset + 1;
        }
        continue;
      }
      out.add(PdfTextSelection.sliceRect(runs[run], a, b));
      run = at.run;
      a = at.offset;
      b = at.offset + 1;
    }
    if (run >= 0 && run < runs.length) {
      out.add(PdfTextSelection.sliceRect(runs[run], a, b));
    }
    return out;
  }

  String excerpt(int from, int to) {
    if (folded.isEmpty) {
      return '';
    }
    final int a = from.clamp(0, folded.length);
    final int b = to.clamp(a, folded.length);
    final int left = (a - 18).clamp(0, folded.length);
    final int right = (b + 18).clamp(0, folded.length);
    return folded.substring(left, right).replaceAll('\n', ' ');
  }
}

List<int> _foldCodePoint(int cp) {
  if (_isMark(cp) || cp == 0x0640 || cp == 0x200C || cp == 0x200D) {
    return const <int>[];
  }
  final int alef = _lamAlef(cp);
  if (alef >= 0) {
    return <int>[0x0644, _foldLetter(alef)];
  }
  return <int>[_foldLetter(cp)];
}

int _foldLetter(int cp) {
  var base = ArabicShaper.nominal(cp);
  base = switch (base) {
    0x0622 || 0x0623 || 0x0625 || 0x0671 => 0x0627,
    0x0649 => 0x064A,
    _ => base,
  };
  if (base >= 0x41 && base <= 0x5A) {
    return base + 0x20;
  }
  return base;
}

bool _isMark(int cp) {
  return (cp >= 0x064B && cp <= 0x065F) ||
      cp == 0x0670 ||
      (cp >= 0x06D6 && cp <= 0x06ED) ||
      (cp >= 0x08D3 && cp <= 0x08FF);
}

/// Lam-Alef ligature → the alef it combines with, or -1.
int _lamAlef(int cp) {
  return switch (cp) {
    0xFEF5 || 0xFEF6 => 0x0622,
    0xFEF7 || 0xFEF8 => 0x0623,
    0xFEF9 || 0xFEFA => 0x0625,
    0xFEFB || 0xFEFC => 0x0627,
    _ => -1,
  };
}
