import 'omml_document.dart';

/// Structural templates inserted from the Equation Tools ribbon.
enum OmmlStructure {
  fractionBar,
  fractionSkewed,
  fractionLinear,
  stack,
  superscript,
  subscript,
  subSuperscript,
  squareRoot,
  nRoot,
  integral,
  integralDefinite,
  sum,
  product,
  paren,
  squareBracket,
  brace,
  abs,
  matrix2x2,
  matrix3x3,
  cases,
  accentHat,
  accentBar,
  accentArrow,
  sin,
  cos,
  tan,
  log,
  ln,
  lim,
}

/// Class OmmlCharRef.
class OmmlCharRef {
  /// OmmlCharRef API.
  const OmmlCharRef({
    required this.cell,
    required this.run,
    required this.offset,
  });

  /// cell API.
  final OmmlSeq cell;

  /// run API.
  final OmmlText run;

  /// offset API.
  final int offset;
}

/// Slot navigation and structural edits on an [OmmlEquation].
abstract final class OmmlEdit {
  /// slots API.
  static List<OmmlSeq> slots(OmmlSeq root) {
    final List<OmmlSeq> out = <OmmlSeq>[];
    late void Function(OmmlNode node) walk;
    void walkSeq(OmmlSeq seq) {
      out.add(seq);
      for (final OmmlNode child in seq.children) {
        walk(child);
      }
    }

    walk = (OmmlNode node) {
      switch (node) {
        case OmmlSeq():
          walkSeq(node);
        case OmmlText():
          break;
        case OmmlFrac():
          walkSeq(node.num);
          walkSeq(node.den);
        case OmmlScript():
          walkSeq(node.base);
          if (node.sub != null) {
            walkSeq(node.sub!);
          }
          if (node.sup != null) {
            walkSeq(node.sup!);
          }
        case OmmlRad():
          if (node.deg != null) {
            walkSeq(node.deg!);
          }
          walkSeq(node.e);
        case OmmlNary():
          if (node.sub != null) {
            walkSeq(node.sub!);
          }
          if (node.sup != null) {
            walkSeq(node.sup!);
          }
          walkSeq(node.e);
        case OmmlDelim():
          walkSeq(node.e);
        case OmmlMatrix():
          for (final List<OmmlSeq> row in node.rows) {
            for (final OmmlSeq cell in row) {
              walkSeq(cell);
            }
          }
        case OmmlAcc():
          walkSeq(node.e);
        case OmmlFunc():
          walkSeq(node.e);
        case OmmlLimLow():
          walkSeq(node.e);
          walkSeq(node.lim);
        case OmmlBar():
          walkSeq(node.e);
      }
    };

    walkSeq(root);
    return out;
  }

  /// slotAt API.
  static OmmlSeq slotAt(OmmlSeq root, int index) {
    final List<OmmlSeq> all = slots(root);
    if (all.isEmpty) {
      return root;
    }
    return all[index.clamp(0, all.length - 1)];
  }

  /// Editable argument boxes: empty placeholders or sequences that hold
  /// text / mixed content. Wrapper-only sequences (a single structure) are
  /// skipped so arrows move between the cells the user sees.
  static List<OmmlSeq> cells(OmmlSeq root) {
    return <OmmlSeq>[
      for (final OmmlSeq seq in slots(root))
        if (_isCell(seq)) seq,
    ];
  }

  static bool _isCell(OmmlSeq seq) {
    if (seq.isEmpty) {
      return true;
    }
    var hasText = false;
    var structures = 0;
    for (final OmmlNode child in seq.children) {
      if (child is OmmlText) {
        hasText = true;
      } else if (child is! OmmlSeq) {
        structures++;
      }
    }
    if (!hasText && structures == 1 && seq.children.length == 1) {
      return false;
    }
    return hasText || structures > 0;
  }

  /// slotIndexOf API.
  static int slotIndexOf(OmmlSeq root, OmmlSeq seq) {
    final int i = slots(root).indexOf(seq);
    return i < 0 ? 0 : i;
  }

  /// cellIndexes API.
  static Set<int> cellIndexes(OmmlSeq root) {
    return <int>{
      for (final OmmlSeq cell in cells(root)) slotIndexOf(root, cell),
    };
  }

  /// snapToCell API.
  static int snapToCell(OmmlSeq root, int slotIndex) {
    final List<OmmlSeq> all = slots(root);
    final List<OmmlSeq> cellList = cells(root);
    if (all.isEmpty || cellList.isEmpty) {
      return 0;
    }
    final OmmlSeq target = all[slotIndex.clamp(0, all.length - 1)];
    if (cellList.contains(target)) {
      return all.indexOf(target);
    }
    for (final OmmlSeq cell in cellList) {
      if (_seqContains(target, cell)) {
        return all.indexOf(cell);
      }
    }
    for (final OmmlSeq cell in cellList) {
      if (_seqContains(cell, target)) {
        return all.indexOf(cell);
      }
    }
    return all.indexOf(cellList.first);
  }

  static bool _seqContains(OmmlSeq parent, OmmlSeq child) {
    if (identical(parent, child)) {
      return false;
    }
    for (final OmmlSeq seq in slots(parent)) {
      if (identical(seq, child)) {
        return true;
      }
    }
    return false;
  }

  /// chars API.
  static List<OmmlCharRef> chars(OmmlSeq root) {
    final List<OmmlSeq> cellList = cells(root);
    final List<OmmlCharRef> out = <OmmlCharRef>[];
    late void Function(OmmlNode node, OmmlSeq? cell) walk;
    void walkSeq(OmmlSeq seq, OmmlSeq? cell) {
      final OmmlSeq? here = cellList.contains(seq) ? seq : cell;
      for (final OmmlNode child in seq.children) {
        walk(child, here);
      }
    }

    walk = (OmmlNode node, OmmlSeq? cell) {
      switch (node) {
        case OmmlSeq():
          walkSeq(node, cell);
        case OmmlText():
          if (cell == null) {
            break;
          }
          for (int i = 0; i < node.text.length; i++) {
            out.add(OmmlCharRef(cell: cell, run: node, offset: i));
          }
        case OmmlFrac():
          walkSeq(node.num, cell);
          walkSeq(node.den, cell);
        case OmmlScript():
          walkSeq(node.base, cell);
          if (node.sub != null) {
            walkSeq(node.sub!, cell);
          }
          if (node.sup != null) {
            walkSeq(node.sup!, cell);
          }
        case OmmlRad():
          if (node.deg != null) {
            walkSeq(node.deg!, cell);
          }
          walkSeq(node.e, cell);
        case OmmlNary():
          if (node.sub != null) {
            walkSeq(node.sub!, cell);
          }
          if (node.sup != null) {
            walkSeq(node.sup!, cell);
          }
          walkSeq(node.e, cell);
        case OmmlDelim():
          walkSeq(node.e, cell);
        case OmmlMatrix():
          for (final List<OmmlSeq> row in node.rows) {
            for (final OmmlSeq item in row) {
              walkSeq(item, cell);
            }
          }
        case OmmlAcc():
          walkSeq(node.e, cell);
        case OmmlFunc():
          walkSeq(node.e, cell);
        case OmmlLimLow():
          walkSeq(node.e, cell);
          walkSeq(node.lim, cell);
        case OmmlBar():
          walkSeq(node.e, cell);
      }
    };

    walkSeq(root, cellList.contains(root) ? root : null);
    return out;
  }

  /// cellChars API.
  static List<OmmlCharRef> cellChars(OmmlSeq root, OmmlSeq cell) {
    return <OmmlCharRef>[
      for (final OmmlCharRef ch in chars(root))
        if (identical(ch.cell, cell)) ch,
    ];
  }

  /// cellPlain API.
  static String cellPlain(OmmlSeq root, OmmlSeq cell) {
    final StringBuffer buf = StringBuffer();
    for (final OmmlCharRef ch in cellChars(root, cell)) {
      buf.write(ch.run.text.substring(ch.offset, ch.offset + 1));
    }
    return buf.toString();
  }

  /// readingCells API.
  static List<OmmlSeq> readingCells(OmmlSeq root) {
    final List<OmmlSeq> list = cells(root);
    final List<OmmlCharRef> stream = chars(root);
    int firstIndex(OmmlSeq cell) {
      for (int i = 0; i < stream.length; i++) {
        if (identical(stream[i].cell, cell)) {
          return i;
        }
      }
      return -1;
    }

    final List<OmmlSeq> ranked = List<OmmlSeq>.of(list);
    ranked.sort((OmmlSeq a, OmmlSeq b) {
      final int ia = firstIndex(a);
      final int ib = firstIndex(b);
      if (ia >= 0 && ib >= 0 && ia != ib) {
        return ia.compareTo(ib);
      }
      if (ia >= 0 && ib < 0) {
        return -1;
      }
      if (ia < 0 && ib >= 0) {
        return 1;
      }
      return list.indexOf(a).compareTo(list.indexOf(b));
    });
    return ranked;
  }

  /// nextSlot API.
  static int nextSlot(OmmlSeq root, int index) {
    return _stepCell(root, index, 1, wrap: true);
  }

  /// prevSlot API.
  static int prevSlot(OmmlSeq root, int index) {
    return _stepCell(root, index, -1, wrap: true);
  }

  /// stepReading API.
  static int stepReading(OmmlSeq root, int index, int delta) {
    return _stepCell(root, index, delta, wrap: false);
  }

  /// True when any placeholder still holds typed characters.
  static bool hasUserText(OmmlSeq root) => chars(root).isNotEmpty;

  /// isFirstReadingCell API.
  static bool isFirstReadingCell(OmmlSeq root, int slotIndex) {
    final List<OmmlSeq> order = readingCells(root);
    if (order.isEmpty) {
      return true;
    }
    final List<OmmlSeq> all = slots(root);
    if (all.isEmpty) {
      return true;
    }
    final int current = snapToCell(root, slotIndex);
    final OmmlSeq here = all[current.clamp(0, all.length - 1)];
    return identical(order.first, here);
  }

  static int _stepCell(
    OmmlSeq root,
    int index,
    int delta, {
    required bool wrap,
  }) {
    final List<OmmlSeq> all = slots(root);
    final List<OmmlSeq> order = readingCells(root);
    if (all.isEmpty) {
      return 0;
    }
    if (order.isEmpty) {
      final int n = all.length;
      if (n <= 1) {
        return 0;
      }
      if (!wrap) {
        return (index + delta).clamp(0, n - 1);
      }
      return (index + delta) % n;
    }
    final int current = snapToCell(root, index);
    final OmmlSeq here = all[current.clamp(0, all.length - 1)];
    var i = order.indexOf(here);
    if (i < 0) {
      i = 0;
    }
    if (wrap) {
      final int next = (i + delta) % order.length;
      final int wrapped = next < 0 ? next + order.length : next;
      return all.indexOf(order[wrapped]);
    }
    final int next = (i + delta).clamp(0, order.length - 1);
    return all.indexOf(order[next]);
  }

  /// insertAt API.
  static void insertAt(OmmlSeq root, OmmlSeq cell, int offset, String text) {
    if (text.isEmpty) {
      return;
    }
    final List<OmmlCharRef> mine = cellChars(root, cell);
    if (mine.isEmpty) {
      insertText(cell, text);
      return;
    }
    if (offset <= 0) {
      final OmmlText run = mine.first.run;
      run.text = '$text${run.text}';
      return;
    }
    if (offset >= mine.length) {
      mine.last.run.text += text;
      return;
    }
    final OmmlCharRef at = mine[offset];
    at.run.text =
        at.run.text.substring(0, at.offset) +
        text +
        at.run.text.substring(at.offset);
  }

  /// deleteAt API.
  static bool deleteAt(
    OmmlSeq root,
    OmmlSeq cell,
    int offset, {
    required bool backward,
  }) {
    final List<OmmlCharRef> mine = cellChars(root, cell);
    final int index = backward ? offset - 1 : offset;
    if (index < 0 || index >= mine.length) {
      return false;
    }
    final OmmlCharRef ch = mine[index];
    ch.run.text =
        ch.run.text.substring(0, ch.offset) +
        ch.run.text.substring(ch.offset + 1);
    if (ch.run.text.isEmpty) {
      for (final OmmlSeq seq in slots(root)) {
        if (seq.children.remove(ch.run)) {
          break;
        }
      }
    }
    return true;
  }

  /// insertText API.
  static void insertText(OmmlSeq slot, String text, {bool normal = false}) {
    if (text.isEmpty) {
      return;
    }
    if (slot.children.isNotEmpty && slot.children.last is OmmlText) {
      final OmmlText last = slot.children.last as OmmlText;
      if (last.normal == normal) {
        last.text += text;
        return;
      }
    }
    slot.children.add(
      OmmlText(
        text: text,
        italic: !normal && _looksLikeMathIdent(text),
        normal: normal,
      ),
    );
  }

  /// deleteBack API.
  static bool deleteBack(OmmlSeq slot) {
    if (slot.children.isEmpty) {
      return false;
    }
    final OmmlNode last = slot.children.last;
    if (last is OmmlText) {
      if (last.text.isEmpty) {
        slot.children.removeLast();
        return true;
      }
      last.text = last.text.substring(0, last.text.length - 1);
      if (last.text.isEmpty) {
        slot.children.removeLast();
      }
      return true;
    }
    slot.children.removeLast();
    return true;
  }

  /// applyStructure API.
  static void applyStructure(OmmlSeq slot, OmmlStructure kind) {
    final OmmlSeq content = slot.isEmpty
        ? OmmlSeq()
        : OmmlSeq(children: List<OmmlNode>.from(slot.children));
    slot.children
      ..clear()
      ..add(_build(kind, content));
  }

  static OmmlNode _build(OmmlStructure kind, OmmlSeq content) {
    switch (kind) {
      case OmmlStructure.fractionBar:
        return OmmlFrac(num: content, den: OmmlSeq());
      case OmmlStructure.fractionSkewed:
        return OmmlFrac(
          num: content,
          den: OmmlSeq(),
          type: OmmlFracType.skewed,
        );
      case OmmlStructure.fractionLinear:
        return OmmlFrac(
          num: content,
          den: OmmlSeq(),
          type: OmmlFracType.linear,
        );
      case OmmlStructure.stack:
        return OmmlFrac(num: content, den: OmmlSeq(), type: OmmlFracType.noBar);
      case OmmlStructure.superscript:
        return OmmlScript(
          base: content,
          sup: OmmlSeq(),
          kind: OmmlScriptKind.sup,
        );
      case OmmlStructure.subscript:
        return OmmlScript(
          base: content,
          sub: OmmlSeq(),
          kind: OmmlScriptKind.sub,
        );
      case OmmlStructure.subSuperscript:
        return OmmlScript(
          base: content,
          sub: OmmlSeq(),
          sup: OmmlSeq(),
          kind: OmmlScriptKind.subSup,
        );
      case OmmlStructure.squareRoot:
        return OmmlRad(e: content);
      case OmmlStructure.nRoot:
        return OmmlRad(deg: OmmlSeq(), e: content);
      case OmmlStructure.integral:
        return OmmlNary(chr: '∫', e: content, hideSub: true, hideSup: true);
      case OmmlStructure.integralDefinite:
        return OmmlNary(chr: '∫', sub: OmmlSeq(), sup: OmmlSeq(), e: content);
      case OmmlStructure.sum:
        return OmmlNary(chr: '∑', sub: OmmlSeq(), sup: OmmlSeq(), e: content);
      case OmmlStructure.product:
        return OmmlNary(chr: '∏', sub: OmmlSeq(), sup: OmmlSeq(), e: content);
      case OmmlStructure.paren:
        return OmmlDelim(begChr: '(', endChr: ')', e: content);
      case OmmlStructure.squareBracket:
        return OmmlDelim(begChr: '[', endChr: ']', e: content);
      case OmmlStructure.brace:
        return OmmlDelim(begChr: '{', endChr: '}', e: content);
      case OmmlStructure.abs:
        return OmmlDelim(begChr: '|', endChr: '|', e: content);
      case OmmlStructure.matrix2x2:
        return OmmlDelim(
          begChr: '(',
          endChr: ')',
          e: OmmlSeq(
            children: <OmmlNode>[
              OmmlMatrix(
                rows: <List<OmmlSeq>>[
                  <OmmlSeq>[content, OmmlSeq()],
                  <OmmlSeq>[OmmlSeq(), OmmlSeq()],
                ],
              ),
            ],
          ),
        );
      case OmmlStructure.matrix3x3:
        return OmmlDelim(
          begChr: '[',
          endChr: ']',
          e: OmmlSeq(
            children: <OmmlNode>[
              OmmlMatrix(
                rows: <List<OmmlSeq>>[
                  <OmmlSeq>[content, OmmlSeq(), OmmlSeq()],
                  <OmmlSeq>[OmmlSeq(), OmmlSeq(), OmmlSeq()],
                  <OmmlSeq>[OmmlSeq(), OmmlSeq(), OmmlSeq()],
                ],
              ),
            ],
          ),
        );
      case OmmlStructure.cases:
        return OmmlDelim(
          begChr: '{',
          endChr: '',
          e: OmmlSeq(
            children: <OmmlNode>[
              OmmlMatrix(
                rows: <List<OmmlSeq>>[
                  <OmmlSeq>[content, OmmlSeq()],
                  <OmmlSeq>[OmmlSeq(), OmmlSeq()],
                ],
              ),
            ],
          ),
        );
      case OmmlStructure.accentHat:
        return OmmlAcc(chr: 'ˆ', e: content);
      case OmmlStructure.accentBar:
        return OmmlBar(e: content);
      case OmmlStructure.accentArrow:
        return OmmlAcc(chr: '→', e: content);
      case OmmlStructure.sin:
        return OmmlFunc(name: 'sin', e: content);
      case OmmlStructure.cos:
        return OmmlFunc(name: 'cos', e: content);
      case OmmlStructure.tan:
        return OmmlFunc(name: 'tan', e: content);
      case OmmlStructure.log:
        return OmmlFunc(name: 'log', e: content);
      case OmmlStructure.ln:
        return OmmlFunc(name: 'ln', e: content);
      case OmmlStructure.lim:
        return OmmlLimLow(lim: content.isEmpty ? OmmlSeq() : content);
    }
  }

  static bool _looksLikeMathIdent(String text) {
    if (text.isEmpty) {
      return false;
    }
    final int cp = text.runes.first;
    return (cp >= 0x41 && cp <= 0x5A) ||
        (cp >= 0x61 && cp <= 0x7A) ||
        (cp >= 0x03B1 && cp <= 0x03C9) ||
        (cp >= 0x0391 && cp <= 0x03A9);
  }
}
