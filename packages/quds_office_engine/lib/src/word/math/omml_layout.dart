import 'dart:math' as math;

import 'omml_document.dart';
import 'omml_edit.dart';
import 'omml_linear.dart';

/// Class LaidOutOmmlItem.
sealed class LaidOutOmmlItem {
  /// LaidOutOmmlItem API.
  LaidOutOmmlItem({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// x API.
  double x;

  /// y API.
  double y;

  /// width API.
  double width;

  /// height API.
  double height;
}

/// Class LaidOutOmmlText.
class LaidOutOmmlText extends LaidOutOmmlItem {
  /// LaidOutOmmlText API.
  LaidOutOmmlText({
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.text,
    required this.fontSize,
    this.italic = false,
    this.bold = false,
  });

  /// text API.
  final String text;

  /// fontSize API.
  final double fontSize;

  /// italic API.
  final bool italic;

  /// bold API.
  final bool bold;
}

/// Class LaidOutOmmlRule.
class LaidOutOmmlRule extends LaidOutOmmlItem {
  /// LaidOutOmmlRule API.
  LaidOutOmmlRule({
    required super.x,
    required super.y,
    required super.width,
    required super.height,
  });
}

/// Class LaidOutOmmlStroke.
class LaidOutOmmlStroke extends LaidOutOmmlItem {
  /// LaidOutOmmlStroke API.
  LaidOutOmmlStroke({
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.kind,
  });

  /// kind API.
  final OmmlStrokeKind kind;
}

/// Enum OmmlStrokeKind.
enum OmmlStrokeKind { radical, parenLeft, parenRight, braceLeft, braceRight }

/// Class LaidOutOmmlSlot.
class LaidOutOmmlSlot extends LaidOutOmmlItem {
  /// LaidOutOmmlSlot API.
  LaidOutOmmlSlot({
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.slotIndex,
    required this.empty,
  });

  /// slotIndex API.
  final int slotIndex;

  /// empty API.
  final bool empty;
}

/// Class LaidOutOmml.
class LaidOutOmml {
  /// LaidOutOmml API.
  LaidOutOmml({
    required this.width,
    required this.height,
    required this.baseline,
    required this.items,
    required this.slots,
  });

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// baseline API.
  final double baseline;

  /// items API.
  final List<LaidOutOmmlItem> items;

  /// slots API.
  final List<LaidOutOmmlSlot> slots;
}

/// Professional / linear box layout for an [OmmlEquation].
abstract final class OmmlLayout {
  /// layout API.
  static LaidOutOmml layout(OmmlEquation equation, {double fontSize = 16}) {
    if (equation.view == OmmlView.linear) {
      final String text = equation.linearText.isNotEmpty
          ? equation.linearText
          : OmmlLinear.write(equation.root);
      return _linear(text, fontSize);
    }
    final _Env env = _Env(fontSize: fontSize);
    final _Box box = env.seq(equation.root);
    env.flush(box, 0, 0);
    final ({double width, double height, double left, double top}) bounds = env
        .bounds();
    return LaidOutOmml(
      width: math.max(36, math.max(box.width + 16, bounds.width + 14)),
      height: math.max(
        fontSize * 1.6,
        math.max(box.height + 12, bounds.height + 12),
      ),
      baseline: box.ascent + 6,
      items: env.items,
      slots: env.slotItems,
    );
  }

  static LaidOutOmml _linear(String text, double fontSize) {
    final String shown = text.isEmpty ? ' ' : text;
    final double width = ommlMeasure(shown, fontSize) + 16;
    final double height = fontSize * 1.6;
    return LaidOutOmml(
      width: width,
      height: height,
      baseline: fontSize * 0.9,
      items: <LaidOutOmmlItem>[
        LaidOutOmmlText(
          x: 8,
          y: (height - fontSize) / 2,
          width: ommlMeasure(shown, fontSize),
          height: fontSize,
          text: shown,
          fontSize: fontSize,
          italic: false,
        ),
        LaidOutOmmlSlot(
          x: 4,
          y: 2,
          width: width - 8,
          height: height - 4,
          slotIndex: 0,
          empty: text.isEmpty,
        ),
      ],
      slots: <LaidOutOmmlSlot>[
        LaidOutOmmlSlot(
          x: 4,
          y: 2,
          width: width - 8,
          height: height - 4,
          slotIndex: 0,
          empty: text.isEmpty,
        ),
      ],
    );
  }
}

class _Box {
  _Box({
    required this.width,
    required this.ascent,
    required this.descent,
    required this.paint,
  });

  /// width API.
  final double width;

  /// ascent API.
  final double ascent;

  /// descent API.
  final double descent;

  /// Function API.
  final void Function(double x, double y) paint;

  /// height API.
  double get height => ascent + descent;
}

class _Env {
  _Env({required this.fontSize});

  /// fontSize API.
  final double fontSize;

  /// items API.
  final List<LaidOutOmmlItem> items = <LaidOutOmmlItem>[];

  /// slotItems API.
  final List<LaidOutOmmlSlot> slotItems = <LaidOutOmmlSlot>[];
  final List<OmmlSeq> _allSlots = <OmmlSeq>[];
  var _indexed = false;

  void _ensureSlots(OmmlSeq root) {
    if (_indexed) {
      return;
    }
    _allSlots
      ..clear()
      ..addAll(OmmlEdit.slots(root));
    _indexed = true;
  }

  int _slotIndex(OmmlSeq seq) {
    final int i = _allSlots.indexOf(seq);
    return i < 0 ? 0 : i;
  }

  /// seq API.
  _Box seq(OmmlSeq node) {
    _ensureSlots(node);
    if (node.children.isEmpty) {
      final double w = fontSize * 0.85;
      final double a = fontSize * 0.8;
      final double d = fontSize * 0.3;
      return _Box(
        width: w,
        ascent: a,
        descent: d,
        paint: (double x, double y) {
          final LaidOutOmmlSlot slot = LaidOutOmmlSlot(
            x: x,
            y: y,
            width: w,
            height: a + d,
            slotIndex: _slotIndex(node),
            empty: true,
          );
          items.add(slot);
          slotItems.add(slot);
        },
      );
    }
    final List<_Box> parts = <_Box>[
      for (final OmmlNode child in node.children) nodeBox(child),
    ];
    final List<double> gaps = <double>[0];
    var width = 0.0;
    var ascent = fontSize * 0.8;
    var descent = fontSize * 0.3;
    for (int i = 0; i < parts.length; i++) {
      final double gap = i == 0 ? 0 : _gapBefore(node.children, i);
      gaps.add(gap);
      width += gap + parts[i].width;
      ascent = math.max(ascent, parts[i].ascent);
      descent = math.max(descent, parts[i].descent);
    }
    return _Box(
      width: width,
      ascent: ascent,
      descent: descent,
      paint: (double x, double y) {
        var cx = x;
        for (int i = 0; i < parts.length; i++) {
          cx += gaps[i + 1];
          parts[i].paint(cx, y + (ascent - parts[i].ascent));
          cx += parts[i].width;
        }
        slotItems.add(
          LaidOutOmmlSlot(
            x: x,
            y: y,
            width: width,
            height: ascent + descent,
            slotIndex: _slotIndex(node),
            empty: false,
          ),
        );
      },
    );
  }

  double _gapBefore(List<OmmlNode> children, int index) {
    final OmmlNode prev = children[index - 1];
    final OmmlNode next = children[index];
    if (_isOperator(prev) || _isOperator(next)) {
      return fontSize * 0.28;
    }
    if (prev is OmmlFrac ||
        next is OmmlFrac ||
        prev is OmmlRad ||
        next is OmmlRad) {
      return fontSize * 0.22;
    }
    if (prev is OmmlDelim || next is OmmlDelim) {
      return fontSize * 0.1;
    }
    return fontSize * 0.06;
  }

  static bool _isOperator(OmmlNode node) {
    if (node is! OmmlText || node.text.isEmpty) {
      return false;
    }
    const String ops = '=+-±×·÷≠≤≥≈→←';
    return ops.contains(node.text);
  }

  /// nodeBox API.
  _Box nodeBox(OmmlNode node) {
    switch (node) {
      case OmmlSeq():
        return seq(node);
      case OmmlText():
        return textBox(node);
      case OmmlFrac():
        return fracBox(node);
      case OmmlScript():
        return scriptBox(node);
      case OmmlRad():
        return radBox(node);
      case OmmlNary():
        return naryBox(node);
      case OmmlDelim():
        return delimBox(node);
      case OmmlMatrix():
        return matrixBox(node);
      case OmmlAcc():
        return accBox(node);
      case OmmlFunc():
        return funcBox(node);
      case OmmlLimLow():
        return limBox(node);
      case OmmlBar():
        return barBox(node);
    }
  }

  /// textBox API.
  _Box textBox(OmmlText node) {
    final String text = node.text.isEmpty ? ' ' : node.text;
    final double size = fontSize;
    final bool italic = node.italic && !node.normal;
    final double width = ommlMeasure(text, size) * (italic ? 1.18 : 1.08);
    return _Box(
      width: width,
      ascent: size * 0.82,
      descent: size * 0.28,
      paint: (double x, double y) {
        items.add(
          LaidOutOmmlText(
            x: x,
            y: y,
            width: width,
            height: size,
            text: text,
            fontSize: size,
            italic: italic,
            bold: node.bold,
          ),
        );
      },
    );
  }

  /// fracBox API.
  _Box fracBox(OmmlFrac node) {
    final _Env child = _Env(fontSize: fontSize * 0.85)
      .._allSlots.addAll(_allSlots)
      .._indexed = true;
    final _Box num = child.seq(node.num);
    final _Box den = child.seq(node.den);
    if (node.type == OmmlFracType.linear || node.type == OmmlFracType.skewed) {
      final String sep = node.type == OmmlFracType.linear ? '/' : '⁄';
      final double sepW = fontSize * 0.4;
      return _Box(
        width: num.width + sepW + den.width,
        ascent: math.max(num.ascent, den.ascent),
        descent: math.max(num.descent, den.descent),
        paint: (double x, double y) {
          num.paint(x, y);
          items.add(
            LaidOutOmmlText(
              x: x + num.width,
              y: y,
              width: sepW,
              height: fontSize,
              text: sep,
              fontSize: fontSize,
            ),
          );
          den.paint(x + num.width + sepW, y);
          items.addAll(child.items);
          slotItems.addAll(child.slotItems);
        },
      );
    }
    final double pad = fontSize * 0.35;
    final double width = math.max(num.width, den.width) + pad * 2;
    final double gap = node.type == OmmlFracType.noBar
        ? fontSize * 0.18
        : fontSize * 0.22;
    final double axis = fontSize * 0.28;
    final double ascent = num.height + gap + axis;
    final double descent = den.height + gap - axis;
    return _Box(
      width: width,
      ascent: ascent,
      descent: math.max(fontSize * 0.3, descent),
      paint: (double x, double y) {
        num.paint(x + (width - num.width) / 2, y);
        if (node.type == OmmlFracType.bar) {
          items.add(
            LaidOutOmmlRule(
              x: x + 2,
              y: y + num.height + gap,
              width: width - 4,
              height: 1.2,
            ),
          );
        }
        den.paint(x + (width - den.width) / 2, y + num.height + gap * 2 + 1);
        items.addAll(child.items);
        slotItems.addAll(child.slotItems);
      },
    );
  }

  /// scriptBox API.
  _Box scriptBox(OmmlScript node) {
    final _Box base = seq(node.base);
    final _Env small = _Env(fontSize: fontSize * 0.62)
      .._allSlots.addAll(_allSlots)
      .._indexed = true;
    final _Box? sub = node.sub == null ? null : small.seq(node.sub!);
    final _Box? sup = node.sup == null ? null : small.seq(node.sup!);
    final double scriptW = math.max(sub?.width ?? 0, sup?.width ?? 0);
    final double extraA = (sup?.height ?? 0) * 0.55;
    final double extraD = (sub?.height ?? 0) * 0.45;
    return _Box(
      width: base.width + scriptW,
      ascent: base.ascent + extraA,
      descent: base.descent + extraD,
      paint: (double x, double y) {
        base.paint(x, y + extraA);
        if (sup != null) {
          sup.paint(x + base.width, y);
        }
        if (sub != null) {
          sub.paint(
            x + base.width,
            y + extraA + base.height - sub.height * 0.35,
          );
        }
        items.addAll(small.items);
        slotItems.addAll(small.slotItems);
      },
    );
  }

  /// radBox API.
  _Box radBox(OmmlRad node) {
    final _Env child = _Env(fontSize: fontSize)
      .._allSlots.addAll(_allSlots)
      .._indexed = true;
    final _Box e = child.seq(node.e);
    final _Env? degEnv = node.deg == null
        ? null
        : (_Env(fontSize: fontSize * 0.5)
            .._allSlots.addAll(_allSlots)
            .._indexed = true);
    final _Box? deg = degEnv?.seq(node.deg!);
    final double tick = fontSize * 0.85;
    final double pad = fontSize * 0.28;
    final double width = (deg?.width ?? 0) + tick + e.width + pad;
    return _Box(
      width: width,
      ascent: e.ascent + fontSize * 0.35,
      descent: e.descent,
      paint: (double x, double y) {
        var origin = x;
        if (deg != null) {
          deg.paint(x, y);
          origin += deg.width + 2;
        }
        items.add(
          LaidOutOmmlStroke(
            x: origin,
            y: y,
            width: tick + e.width + pad,
            height: e.height + fontSize * 0.28,
            kind: OmmlStrokeKind.radical,
          ),
        );
        e.paint(origin + tick, y + fontSize * 0.22);
        items.addAll(child.items);
        slotItems.addAll(child.slotItems);
        if (degEnv != null) {
          items.addAll(degEnv.items);
          slotItems.addAll(degEnv.slotItems);
        }
      },
    );
  }

  /// naryBox API.
  _Box naryBox(OmmlNary node) {
    final double opSize = fontSize * 1.55;
    final double opW = opSize * 0.7;
    final _Env small = _Env(fontSize: fontSize * 0.55)
      .._allSlots.addAll(_allSlots)
      .._indexed = true;
    final _Box? sub = node.sub == null || node.hideSub
        ? null
        : small.seq(node.sub!);
    final _Box? sup = node.sup == null || node.hideSup
        ? null
        : small.seq(node.sup!);
    final _Box e = seq(node.e);
    final double midW = math.max(
      opW,
      math.max(sub?.width ?? 0, sup?.width ?? 0),
    );
    final double extraA = (sup?.height ?? 0) + 2;
    final double extraD = (sub?.height ?? 0) + 2;
    return _Box(
      width: midW + 4 + e.width,
      ascent: math.max(opSize * 0.75, e.ascent) + extraA,
      descent: math.max(opSize * 0.25, e.descent) + extraD,
      paint: (double x, double y) {
        final double opY = y + extraA;
        if (sup != null) {
          sup.paint(x + (midW - sup.width) / 2, y);
        }
        items.add(
          LaidOutOmmlText(
            x: x + (midW - opW) / 2,
            y: opY,
            width: opW,
            height: opSize,
            text: node.chr,
            fontSize: opSize,
          ),
        );
        if (sub != null) {
          sub.paint(x + (midW - sub.width) / 2, opY + opSize * 0.95);
        }
        e.paint(x + midW + 4, opY + math.max(0, (opSize - e.height) / 2));
        items.addAll(small.items);
        slotItems.addAll(small.slotItems);
      },
    );
  }

  /// delimBox API.
  _Box delimBox(OmmlDelim node) {
    final _Box inner = seq(node.e);
    final double delimW = fontSize * 0.42;
    final double inset = fontSize * 0.08;
    return _Box(
      width: delimW + inset + inner.width + inset + delimW,
      ascent: inner.ascent + 3,
      descent: inner.descent + 3,
      paint: (double x, double y) {
        if (node.begChr.isNotEmpty) {
          items.add(
            LaidOutOmmlStroke(
              x: x,
              y: y,
              width: delimW,
              height: inner.height + 6,
              kind: node.begChr == '{'
                  ? OmmlStrokeKind.braceLeft
                  : OmmlStrokeKind.parenLeft,
            ),
          );
        }
        inner.paint(x + delimW + inset, y + 3);
        if (node.endChr.isNotEmpty) {
          items.add(
            LaidOutOmmlStroke(
              x: x + delimW + inset + inner.width + inset,
              y: y,
              width: delimW,
              height: inner.height + 6,
              kind: node.endChr == '}'
                  ? OmmlStrokeKind.braceRight
                  : OmmlStrokeKind.parenRight,
            ),
          );
        }
      },
    );
  }

  /// matrixBox API.
  _Box matrixBox(OmmlMatrix node) {
    final List<List<_Box>> cells = <List<_Box>>[];
    final _Env child = _Env(fontSize: fontSize * 0.9)
      .._allSlots.addAll(_allSlots)
      .._indexed = true;
    var cols = 0;
    for (final List<OmmlSeq> row in node.rows) {
      cols = math.max(cols, row.length);
      cells.add(<_Box>[for (final OmmlSeq cell in row) child.seq(cell)]);
    }
    final List<double> colW = List<double>.filled(cols, 0);
    final List<double> rowH = <double>[];
    for (int r = 0; r < cells.length; r++) {
      var h = fontSize;
      for (int c = 0; c < cells[r].length; c++) {
        colW[c] = math.max(colW[c], cells[r][c].width + 8);
        h = math.max(h, cells[r][c].height);
      }
      rowH.add(h);
    }
    final double width = colW.fold<double>(0, (double a, double b) => a + b);
    final double height =
        rowH.fold<double>(0, (double a, double b) => a + b) + 4;
    return _Box(
      width: width,
      ascent: height * 0.55,
      descent: height * 0.45,
      paint: (double x, double y) {
        var cy = y;
        for (int r = 0; r < cells.length; r++) {
          var cx = x;
          for (int c = 0; c < cells[r].length; c++) {
            cells[r][c].paint(cx + 4, cy + 2);
            cx += colW[c];
          }
          cy += rowH[r];
        }
        items.addAll(child.items);
        slotItems.addAll(child.slotItems);
      },
    );
  }

  /// accBox API.
  _Box accBox(OmmlAcc node) {
    final _Box e = seq(node.e);
    return _Box(
      width: math.max(e.width, fontSize * 0.5),
      ascent: e.ascent + fontSize * 0.35,
      descent: e.descent,
      paint: (double x, double y) {
        items.add(
          LaidOutOmmlText(
            x: x + e.width / 2 - fontSize * 0.15,
            y: y,
            width: fontSize * 0.4,
            height: fontSize * 0.4,
            text: node.chr,
            fontSize: fontSize * 0.7,
          ),
        );
        e.paint(x, y + fontSize * 0.3);
      },
    );
  }

  /// funcBox API.
  _Box funcBox(OmmlFunc node) {
    final _Box name = textBox(
      OmmlText(text: node.name, italic: false, normal: true),
    );
    final _Box arg = seq(node.e);
    return _Box(
      width: name.width + 3 + arg.width,
      ascent: math.max(name.ascent, arg.ascent),
      descent: math.max(name.descent, arg.descent),
      paint: (double x, double y) {
        name.paint(x, y);
        arg.paint(x + name.width + 3, y);
      },
    );
  }

  /// limBox API.
  _Box limBox(OmmlLimLow node) {
    final _Box e = seq(node.e);
    final _Env small = _Env(fontSize: fontSize * 0.55)
      .._allSlots.addAll(_allSlots)
      .._indexed = true;
    final _Box lim = small.seq(node.lim);
    final double width = math.max(e.width, lim.width);
    return _Box(
      width: width,
      ascent: e.ascent,
      descent: e.descent + lim.height + 2,
      paint: (double x, double y) {
        e.paint(x + (width - e.width) / 2, y);
        lim.paint(x + (width - lim.width) / 2, y + e.height + 1);
        items.addAll(small.items);
        slotItems.addAll(small.slotItems);
      },
    );
  }

  /// barBox API.
  _Box barBox(OmmlBar node) {
    final _Box e = seq(node.e);
    return _Box(
      width: e.width,
      ascent: e.ascent + (node.posTop ? 3 : 0),
      descent: e.descent + (node.posTop ? 0 : 3),
      paint: (double x, double y) {
        if (node.posTop) {
          items.add(LaidOutOmmlRule(x: x, y: y, width: e.width, height: 1.1));
          e.paint(x, y + 3);
        } else {
          e.paint(x, y);
          items.add(
            LaidOutOmmlRule(
              x: x,
              y: y + e.height + 1,
              width: e.width,
              height: 1.1,
            ),
          );
        }
      },
    );
  }

  /// flush API.
  void flush(_Box box, double x, double y) => box.paint(x + 8, y + 6);

  /// bounds API.
  ({double width, double height, double left, double top}) bounds() {
    if (items.isEmpty) {
      return (width: 0, height: 0, left: 0, top: 0);
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = 0.0;
    var maxY = 0.0;
    for (final LaidOutOmmlItem item in items) {
      minX = math.min(minX, item.x);
      minY = math.min(minY, item.y);
      maxX = math.max(maxX, item.x + item.width);
      maxY = math.max(maxY, item.y + item.height);
    }
    return (
      width: math.max(0, maxX - math.min(0, minX)),
      height: math.max(0, maxY - math.min(0, minY)),
      left: minX,
      top: minY,
    );
  }
}

/// ommlMeasure helper.
double ommlMeasure(String text, double fontSize) {
  /// w API.
  var w = 0.0;
  for (final int cp in text.runes) {
    w += _ommlAdvance(cp, fontSize);
  }
  return w <= 0 ? fontSize * 0.35 : w;
}

double _ommlAdvance(int cp, double fontSize) {
  if (cp == 0x20) {
    return fontSize * 0.32;
  }
  if (cp == 0x3D || cp == 0x2B || cp == 0xB1) {
    return fontSize * 0.72;
  }
  if (cp >= 0x30 && cp <= 0x39) {
    return fontSize * 0.6;
  }
  if ('il.,;:\'|!'.contains(String.fromCharCode(cp))) {
    return fontSize * 0.32;
  }
  if ('mwMW@'.contains(String.fromCharCode(cp))) {
    return fontSize * 0.92;
  }
  if (cp > 0x2100) {
    return fontSize * 0.7;
  }
  return fontSize * 0.62;
}
