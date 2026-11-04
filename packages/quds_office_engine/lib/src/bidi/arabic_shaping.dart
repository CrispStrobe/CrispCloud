/// Arabic joining form after contextual analysis.
enum ArabicJoinForm { isolated, initial, medial, finalForm }

/// One shaped character. Diacritics keep [advanceFactor] = 0.
class ShapedChar {
  /// ShapedChar API.
  const ShapedChar({
    required this.codePoint,
    required this.form,
    required this.advanceFactor,
    required this.logicalIndex,
  });

  /// codePoint API.
  final int codePoint;

  /// form API.
  final ArabicJoinForm form;

  /// advanceFactor API.
  final double advanceFactor;

  /// logicalIndex API.
  final int logicalIndex;
}

/// Isolated / initial / medial / final shaping plus obligatory Lam-Alef ligatures.
abstract final class ArabicShaper {
  /// shape API.
  static List<ShapedChar> shape(String text) {
    final List<int> cps = text.runes.toList();
    if (cps.isEmpty) {
      return const <ShapedChar>[];
    }
    final List<_Join> joins = cps.map(_joinType).toList();
    final List<ArabicJoinForm> forms = List<ArabicJoinForm>.filled(
      cps.length,
      ArabicJoinForm.isolated,
    );
    for (int i = 0; i < cps.length; i++) {
      if (joins[i] == _Join.transparent || joins[i] == _Join.none) {
        forms[i] = ArabicJoinForm.isolated;
        continue;
      }
      final bool joinsPrev = _joinsLeft(joins, i);
      final bool joinsNext = _joinsRight(joins, i);
      if (joins[i] == _Join.right) {
        forms[i] = joinsPrev
            ? ArabicJoinForm.finalForm
            : ArabicJoinForm.isolated;
      } else {
        if (joinsPrev && joinsNext) {
          forms[i] = ArabicJoinForm.medial;
        } else if (joinsNext) {
          forms[i] = ArabicJoinForm.initial;
        } else if (joinsPrev) {
          forms[i] = ArabicJoinForm.finalForm;
        } else {
          forms[i] = ArabicJoinForm.isolated;
        }
      }
    }

    final List<ShapedChar> out = <ShapedChar>[];
    var logical = 0;
    for (int i = 0; i < cps.length; i++) {
      final int cp = cps[i];
      if (joins[i] == _Join.transparent ||
          joins[i] == _Join.causing ||
          cp == 0x200C) {
        out.add(
          ShapedChar(
            codePoint: cp,
            form: ArabicJoinForm.isolated,
            advanceFactor: 0,
            logicalIndex: logical,
          ),
        );
        logical += cp > 0xFFFF ? 2 : 1;
        continue;
      }
      if (cp == 0x0644 && i + 1 < cps.length) {
        int k = i + 1;
        while (k < cps.length && joins[k] == _Join.transparent) {
          k++;
        }
        if (k < cps.length && _alefLigature(cps[k]) != null) {
          final int lig = _alefLigature(cps[k])!;
          final bool finalForm =
              forms[i] == ArabicJoinForm.finalForm ||
              forms[i] == ArabicJoinForm.medial;
          out.add(
            ShapedChar(
              codePoint: finalForm ? lig + 1 : lig,
              form: finalForm
                  ? ArabicJoinForm.finalForm
                  : ArabicJoinForm.isolated,
              advanceFactor: 1,
              logicalIndex: logical,
            ),
          );
          logical += 1; // lam
          for (int t = i + 1; t < k; t++) {
            out.add(
              ShapedChar(
                codePoint: cps[t],
                form: ArabicJoinForm.isolated,
                advanceFactor: 0,
                logicalIndex: logical,
              ),
            );
            logical += cps[t] > 0xFFFF ? 2 : 1;
          }
          // The alef is inside the ligature. A zero-advance marker keeps the
          // line breaker from also painting a second alef beside لا.
          out.add(
            ShapedChar(
              codePoint: 0,
              form: ArabicJoinForm.isolated,
              advanceFactor: 0,
              logicalIndex: logical,
            ),
          );
          logical += cps[k] > 0xFFFF ? 2 : 1;
          i = k;
          continue;
        }
      }
      out.add(
        ShapedChar(
          codePoint: _presentation(cp, forms[i]),
          form: forms[i],
          advanceFactor: 1,
          logicalIndex: logical,
        ),
      );
      logical += cp > 0xFFFF ? 2 : 1;
    }
    return out;
  }

  /// Nominal letter for an Arabic presentation form, if [cp] is one.
  ///
  /// Lam-Alef ligatures (U+FEF5–U+FEFC) have no single nominal and return null.
  static int? nominalOf(int cp) => _nominal[cp];

  /// Fold presentation forms in [text] back to nominal Arabic.
  static String foldPresentation(String text) {
    final StringBuffer out = StringBuffer();
    for (final int cp in text.runes) {
      out.writeCharCode(nominalOf(cp) ?? cp);
    }
    return out.toString();
  }

  static bool _joinsLeft(List<_Join> joins, int i) {
    int j = i - 1;
    while (j >= 0 && joins[j] == _Join.transparent) {
      j--;
    }
    if (j < 0) {
      return false;
    }
    return joins[j] == _Join.dual || joins[j] == _Join.causing;
  }

  static bool _joinsRight(List<_Join> joins, int i) {
    int j = i + 1;
    while (j < joins.length && joins[j] == _Join.transparent) {
      j++;
    }
    if (j >= joins.length) {
      return false;
    }
    return joins[j] == _Join.dual ||
        joins[j] == _Join.right ||
        joins[j] == _Join.causing;
  }

  /// Isolated presentation-form start for Lam-Alef pairs (FEF5, FEF7, FEF9, FEFB).
  static int? _alefLigature(int alef) {
    switch (alef) {
      case 0x0622:
        return 0xFEF5;
      case 0x0623:
        return 0xFEF7;
      case 0x0625:
        return 0xFEF9;
      case 0x0627:
        return 0xFEFB;
      default:
        return null;
    }
  }

  static int _presentation(int cp, ArabicJoinForm form) {
    final List<int>? forms = _forms[cp];
    if (forms == null) {
      return cp;
    }
    return switch (form) {
      ArabicJoinForm.isolated => forms[0],
      ArabicJoinForm.finalForm => forms[1],
      ArabicJoinForm.initial => forms[2],
      ArabicJoinForm.medial => forms[3],
    };
  }

  static _Join _joinType(int cp) {
    if (cp == 0x200D) {
      return _Join.causing;
    }
    if (_transparent(cp)) {
      return _Join.transparent;
    }
    if (cp == 0x200C) {
      return _Join.none;
    }
    if (_rightJoining.contains(cp)) {
      return _Join.right;
    }
    if ((cp >= 0x0620 && cp <= 0x064A) ||
        (cp >= 0x066E && cp <= 0x06D3) ||
        (cp >= 0x0750 && cp <= 0x077F) ||
        (cp >= 0x08A0 && cp <= 0x08BD)) {
      return _rightJoining.contains(cp) ? _Join.right : _Join.dual;
    }
    return _Join.none;
  }

  static bool _transparent(int cp) {
    return (cp >= 0x064B && cp <= 0x065F) ||
        cp == 0x0670 ||
        (cp >= 0x06D6 && cp <= 0x06ED) ||
        (cp >= 0x08D3 && cp <= 0x08FF);
  }

  static const Set<int> _rightJoining = <int>{
    0x0622,
    0x0623,
    0x0624,
    0x0625,
    0x0627,
    0x0629,
    0x062F,
    0x0630,
    0x0631,
    0x0632,
    0x0648,
    0x0671,
    0x0672,
    0x0673,
    0x0675,
    0x0688,
    0x0689,
    0x0691,
    0x06A0,
    0x06C0,
    0x06C3,
    0x06C4,
    0x06C5,
    0x06C6,
    0x06C7,
    0x06C8,
    0x06C9,
    0x06CA,
    0x06CB,
    0x06CD,
    0x06CF,
    0x06D2,
    0x06D3,
  };

  /// Isolated, Final, Initial, Medial presentation forms (FE7x/FE8x).
  static const Map<int, List<int>> _forms = <int, List<int>>{
    0x0621: <int>[0xFE80, 0xFE80, 0xFE80, 0xFE80],
    0x0622: <int>[0xFE81, 0xFE82, 0xFE81, 0xFE82],
    0x0623: <int>[0xFE83, 0xFE84, 0xFE83, 0xFE84],
    0x0624: <int>[0xFE85, 0xFE86, 0xFE85, 0xFE86],
    0x0625: <int>[0xFE87, 0xFE88, 0xFE87, 0xFE88],
    0x0626: <int>[0xFE89, 0xFE8A, 0xFE8B, 0xFE8C],
    0x0627: <int>[0xFE8D, 0xFE8E, 0xFE8D, 0xFE8E],
    0x0628: <int>[0xFE8F, 0xFE90, 0xFE91, 0xFE92],
    0x0629: <int>[0xFE93, 0xFE94, 0xFE93, 0xFE94],
    0x062A: <int>[0xFE95, 0xFE96, 0xFE97, 0xFE98],
    0x062B: <int>[0xFE99, 0xFE9A, 0xFE9B, 0xFE9C],
    0x062C: <int>[0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0],
    0x062D: <int>[0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4],
    0x062E: <int>[0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8],
    0x062F: <int>[0xFEA9, 0xFEAA, 0xFEA9, 0xFEAA],
    0x0630: <int>[0xFEAB, 0xFEAC, 0xFEAB, 0xFEAC],
    0x0631: <int>[0xFEAD, 0xFEAE, 0xFEAD, 0xFEAE],
    0x0632: <int>[0xFEAF, 0xFEB0, 0xFEAF, 0xFEB0],
    0x0633: <int>[0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4],
    0x0634: <int>[0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8],
    0x0635: <int>[0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC],
    0x0636: <int>[0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0],
    0x0637: <int>[0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4],
    0x0638: <int>[0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8],
    0x0639: <int>[0xFEC9, 0xFECA, 0xFECB, 0xFECC],
    0x063A: <int>[0xFECD, 0xFECE, 0xFECF, 0xFED0],
    0x0641: <int>[0xFED1, 0xFED2, 0xFED3, 0xFED4],
    0x0642: <int>[0xFED5, 0xFED6, 0xFED7, 0xFED8],
    0x0643: <int>[0xFED9, 0xFEDA, 0xFEDB, 0xFEDC],
    0x0644: <int>[0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0],
    0x0645: <int>[0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4],
    0x0646: <int>[0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8],
    0x0647: <int>[0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC],
    0x0648: <int>[0xFEED, 0xFEEE, 0xFEED, 0xFEEE],
    0x0649: <int>[0xFEEF, 0xFEF0, 0xFEEF, 0xFEF0],
    0x064A: <int>[0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4],
  };

  static final Map<int, int> _nominal = <int, int>{
    for (final MapEntry<int, List<int>> entry in _forms.entries)
      for (final int form in entry.value) form: entry.key,
  };

  /// Presentation form → isolated Arabic letter, or [codePoint] if none.
  static int nominal(int codePoint) => _nominal[codePoint] ?? codePoint;
}

enum _Join { none, dual, right, transparent, causing }
