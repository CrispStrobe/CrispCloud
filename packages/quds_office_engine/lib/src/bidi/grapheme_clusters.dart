/// UAX #29 grapheme-cluster segmentation used for caret hit-testing.
class GraphemeCluster {
  /// GraphemeCluster API.
  const GraphemeCluster({
    required this.start,
    required this.end,
    required this.text,
  });

  /// start API.
  final int start;

  /// end API.
  final int end;

  /// text API.
  final String text;

  /// length API.
  int get length => end - start;
}

/// Class GraphemeClusters.
abstract final class GraphemeClusters {
  /// segment API.
  static List<GraphemeCluster> segment(String text) {
    if (text.isEmpty) {
      return const <GraphemeCluster>[];
    }
    final List<int> units = text.codeUnits;
    final List<GraphemeCluster> out = <GraphemeCluster>[];
    int start = 0;
    int i = 0;
    while (i < units.length) {
      int next = i + _codePointLength(units, i);
      while (next < units.length && !_break(units, next)) {
        next += _codePointLength(units, next);
      }
      out.add(
        GraphemeCluster(
          start: start,
          end: next,
          text: text.substring(start, next),
        ),
      );
      start = next;
      i = next;
    }
    return out;
  }

  /// Returns the cluster index containing logical UTF-16 [offset].
  static int indexAt(List<GraphemeCluster> clusters, int offset) {
    for (int i = 0; i < clusters.length; i++) {
      if (offset < clusters[i].end) {
        return i;
      }
    }
    return clusters.length;
  }

  static bool _break(List<int> units, int index) {
    final int prev = _codePointBefore(units, index);
    final int curr = _codePointAt(units, index);
    final _Gc prevGc = _gc(prev);
    final _Gc currGc = _gc(curr);
    // GB3 CR × LF
    if (prevGc == _Gc.cr && currGc == _Gc.lf) {
      return false;
    }
    // GB4 / GB5
    if (prevGc == _Gc.cr || prevGc == _Gc.lf || prevGc == _Gc.control) {
      return true;
    }
    if (currGc == _Gc.cr || currGc == _Gc.lf || currGc == _Gc.control) {
      return true;
    }
    // GB6-GB8 Hangul
    if (prevGc == _Gc.l &&
        (currGc == _Gc.l ||
            currGc == _Gc.v ||
            currGc == _Gc.lv ||
            currGc == _Gc.lvt)) {
      return false;
    }
    if ((prevGc == _Gc.lv || prevGc == _Gc.v) &&
        (currGc == _Gc.v || currGc == _Gc.t)) {
      return false;
    }
    if ((prevGc == _Gc.lvt || prevGc == _Gc.t) && currGc == _Gc.t) {
      return false;
    }
    // GB9 × Extend / ZWJ
    if (currGc == _Gc.extend || currGc == _Gc.zwj) {
      return false;
    }
    // GB9a × SpacingMark
    if (currGc == _Gc.spacingMark) {
      return false;
    }
    // GB11 ZWJ × Extended_Pictographic (emoji ZWJ sequences)
    if (prevGc == _Gc.zwj && currGc == _Gc.extPict) {
      return false;
    }
    // GB12/13 RI × RI (pairs only)
    if (prevGc == _Gc.ri && currGc == _Gc.ri) {
      int count = 0;
      int p = index;
      while (true) {
        final int before = _codePointBefore(units, p);
        if (_gc(before) != _Gc.ri) {
          break;
        }
        count++;
        p -= _codePointLengthBefore(units, p);
        if (p <= 0) {
          break;
        }
      }
      return count.isOdd;
    }
    return true;
  }

  static int _codePointAt(List<int> units, int i) {
    final int lead = units[i];
    if (lead >= 0xD800 && lead <= 0xDBFF && i + 1 < units.length) {
      final int trail = units[i + 1];
      if (trail >= 0xDC00 && trail <= 0xDFFF) {
        return 0x10000 + ((lead - 0xD800) << 10) + (trail - 0xDC00);
      }
    }
    return lead;
  }

  static int _codePointBefore(List<int> units, int i) {
    if (i <= 0) {
      return 0;
    }
    final int trail = units[i - 1];
    if (trail >= 0xDC00 && trail <= 0xDFFF && i >= 2) {
      final int lead = units[i - 2];
      if (lead >= 0xD800 && lead <= 0xDBFF) {
        return 0x10000 + ((lead - 0xD800) << 10) + (trail - 0xDC00);
      }
    }
    return trail;
  }

  static int _codePointLength(List<int> units, int i) {
    final int lead = units[i];
    if (lead >= 0xD800 && lead <= 0xDBFF && i + 1 < units.length) {
      final int trail = units[i + 1];
      if (trail >= 0xDC00 && trail <= 0xDFFF) {
        return 2;
      }
    }
    return 1;
  }

  static int _codePointLengthBefore(List<int> units, int i) {
    if (i >= 2) {
      final int trail = units[i - 1];
      final int lead = units[i - 2];
      if (lead >= 0xD800 &&
          lead <= 0xDBFF &&
          trail >= 0xDC00 &&
          trail <= 0xDFFF) {
        return 2;
      }
    }
    return 1;
  }

  static _Gc _gc(int cp) {
    if (cp == 0x000D) {
      return _Gc.cr;
    }
    if (cp == 0x000A) {
      return _Gc.lf;
    }
    if (cp == 0x200D) {
      return _Gc.zwj;
    }
    if ((cp >= 0x1F1E6 && cp <= 0x1F1FF)) {
      return _Gc.ri;
    }
    if (_isExtend(cp)) {
      return _Gc.extend;
    }
    if (_isSpacingMark(cp)) {
      return _Gc.spacingMark;
    }
    if (_isHangulL(cp)) {
      return _Gc.l;
    }
    if (_isHangulV(cp)) {
      return _Gc.v;
    }
    if (_isHangulT(cp)) {
      return _Gc.t;
    }
    if (_isHangulLV(cp)) {
      return _Gc.lv;
    }
    if (_isHangulLVT(cp)) {
      return _Gc.lvt;
    }
    if (_isControl(cp)) {
      return _Gc.control;
    }
    if (_isExtPict(cp)) {
      return _Gc.extPict;
    }
    return _Gc.other;
  }

  static bool _isExtend(int cp) {
    return (cp >= 0x0300 && cp <= 0x036F) ||
        (cp >= 0x0483 && cp <= 0x0489) ||
        (cp >= 0x0591 && cp <= 0x05BD) ||
        (cp >= 0x0610 && cp <= 0x061A) ||
        (cp >= 0x064B && cp <= 0x065F) ||
        cp == 0x0670 ||
        (cp >= 0x06D6 && cp <= 0x06DC) ||
        (cp >= 0x06DF && cp <= 0x06E4) ||
        (cp >= 0x06E7 && cp <= 0x06E8) ||
        (cp >= 0x06EA && cp <= 0x06ED) ||
        (cp >= 0x08D3 && cp <= 0x08E1) ||
        (cp >= 0x08E3 && cp <= 0x0902) ||
        (cp >= 0x1AB0 && cp <= 0x1AFF) ||
        (cp >= 0x1DC0 && cp <= 0x1DFF) ||
        (cp >= 0x20D0 && cp <= 0x20FF) ||
        (cp >= 0xFE00 && cp <= 0xFE0F) ||
        (cp >= 0xFE20 && cp <= 0xFE2F) ||
        (cp >= 0xE0100 && cp <= 0xE01EF);
  }

  static bool _isSpacingMark(int cp) {
    return cp == 0x0903 ||
        (cp >= 0x093E && cp <= 0x0940) ||
        (cp >= 0x0949 && cp <= 0x094C) ||
        (cp >= 0x094E && cp <= 0x094F);
  }

  static bool _isControl(int cp) {
    return (cp >= 0x0000 && cp <= 0x0009) ||
        (cp >= 0x000B && cp <= 0x001F) ||
        (cp >= 0x007F && cp <= 0x009F) ||
        cp == 0x00AD ||
        cp == 0x061C ||
        (cp >= 0x200B && cp <= 0x200C) ||
        (cp >= 0x200E && cp <= 0x200F) ||
        (cp >= 0x202A && cp <= 0x202E) ||
        (cp >= 0x2060 && cp <= 0x206F);
  }

  static bool _isHangulL(int cp) => cp >= 0x1100 && cp <= 0x115F;
  static bool _isHangulV(int cp) => cp >= 0x1160 && cp <= 0x11A7;
  static bool _isHangulT(int cp) => cp >= 0x11A8 && cp <= 0x11FF;

  static bool _isHangulLV(int cp) {
    if (cp < 0xAC00 || cp > 0xD7A3) {
      return false;
    }
    return ((cp - 0xAC00) % 28) == 0;
  }

  static bool _isHangulLVT(int cp) {
    if (cp < 0xAC00 || cp > 0xD7A3) {
      return false;
    }
    return ((cp - 0xAC00) % 28) != 0;
  }

  static bool _isExtPict(int cp) {
    return (cp >= 0x1F300 && cp <= 0x1F5FF) ||
        (cp >= 0x1F600 && cp <= 0x1F64F) ||
        (cp >= 0x1F680 && cp <= 0x1F6FF) ||
        (cp >= 0x1F900 && cp <= 0x1F9FF) ||
        (cp >= 0x2600 && cp <= 0x26FF);
  }
}

enum _Gc {
  cr,
  lf,
  control,
  extend,
  zwj,
  ri,
  spacingMark,
  l,
  v,
  t,
  lv,
  lvt,
  extPict,
  other,
}
