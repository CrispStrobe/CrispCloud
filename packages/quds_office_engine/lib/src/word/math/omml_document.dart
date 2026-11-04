/// Office Math (OMML) tree used by Word equations.
///
/// Nodes map to the `m:` namespace structures: `oMath`, `f`, `sSub`/`sSup`,
/// `rad`, `nary`, `d`, `m`, `acc`, `func`, and `limLow`.
enum OmmlDisplay { inline, display }

/// Enum OmmlView.
enum OmmlView { professional, linear }

/// Enum OmmlFracType.
enum OmmlFracType { bar, noBar, skewed, linear }

/// Enum OmmlScriptKind.
enum OmmlScriptKind { sub, sup, subSup, preSubSup }

/// Class OmmlNode.
sealed class OmmlNode {
  /// OmmlNode API.
  OmmlNode();

  /// copy API.
  OmmlNode copy();
}

/// Class OmmlSeq.
class OmmlSeq extends OmmlNode {
  /// OmmlSeq API.
  OmmlSeq({List<OmmlNode>? children}) : children = children ?? <OmmlNode>[];

  /// children API.
  List<OmmlNode> children;

  /// isEmpty API.
  bool get isEmpty => children.isEmpty;

  @override
  /// copy API.
  OmmlSeq copy() => OmmlSeq(
    children: <OmmlNode>[for (final OmmlNode n in children) n.copy()],
  );
}

/// Class OmmlText.
class OmmlText extends OmmlNode {
  /// OmmlText API.
  OmmlText({
    this.text = '',
    this.italic = true,
    this.bold = false,
    this.normal = false,
  });

  /// text API.
  String text;

  /// italic API.
  bool italic;

  /// bold API.
  bool bold;

  /// normal API.
  bool normal;

  @override
  /// copy API.
  OmmlText copy() =>
      OmmlText(text: text, italic: italic, bold: bold, normal: normal);
}

/// Class OmmlFrac.
class OmmlFrac extends OmmlNode {
  /// OmmlFrac API.
  OmmlFrac({OmmlSeq? num, OmmlSeq? den, this.type = OmmlFracType.bar})
    : num = num ?? OmmlSeq(),
      den = den ?? OmmlSeq();

  /// num API.
  OmmlSeq num;

  /// den API.
  OmmlSeq den;

  /// type API.
  OmmlFracType type;

  @override
  /// copy API.
  OmmlFrac copy() => OmmlFrac(num: num.copy(), den: den.copy(), type: type);
}

/// Class OmmlScript.
class OmmlScript extends OmmlNode {
  /// OmmlScript API.
  OmmlScript({
    OmmlSeq? base,
    this.sub,
    this.sup,
    this.kind = OmmlScriptKind.sup,
  }) : base = base ?? OmmlSeq();

  OmmlSeq base;

  /// sub API.
  OmmlSeq? sub;

  /// sup API.
  OmmlSeq? sup;

  /// kind API.
  OmmlScriptKind kind;

  @override
  /// copy API.
  OmmlScript copy() => OmmlScript(
    base: base.copy(),
    sub: sub?.copy(),
    sup: sup?.copy(),
    kind: kind,
  );
}

/// Class OmmlRad.
class OmmlRad extends OmmlNode {
  /// OmmlRad API.
  OmmlRad({this.deg, OmmlSeq? e}) : e = e ?? OmmlSeq();

  /// deg API.
  OmmlSeq? deg;

  /// e API.
  OmmlSeq e;

  @override
  /// copy API.
  OmmlRad copy() => OmmlRad(deg: deg?.copy(), e: e.copy());
}

/// Class OmmlNary.
class OmmlNary extends OmmlNode {
  /// OmmlNary API.
  OmmlNary({
    this.chr = '∫',
    this.sub,
    this.sup,
    OmmlSeq? e,
    this.hideSub = false,
    this.hideSup = false,
  }) : e = e ?? OmmlSeq();

  /// chr API.
  String chr;

  /// sub API.
  OmmlSeq? sub;

  /// sup API.
  OmmlSeq? sup;

  /// e API.
  OmmlSeq e;

  /// hideSub API.
  bool hideSub;

  /// hideSup API.
  bool hideSup;

  @override
  /// copy API.
  OmmlNary copy() => OmmlNary(
    chr: chr,
    sub: sub?.copy(),
    sup: sup?.copy(),
    e: e.copy(),
    hideSub: hideSub,
    hideSup: hideSup,
  );
}

/// Class OmmlDelim.
class OmmlDelim extends OmmlNode {
  /// OmmlDelim API.
  OmmlDelim({
    this.begChr = '(',
    this.endChr = ')',
    this.sepChr = '',
    OmmlSeq? e,
  }) : e = e ?? OmmlSeq();

  /// begChr API.
  String begChr;

  /// endChr API.
  String endChr;

  /// sepChr API.
  String sepChr;

  /// e API.
  OmmlSeq e;

  @override
  /// copy API.
  OmmlDelim copy() =>
      OmmlDelim(begChr: begChr, endChr: endChr, sepChr: sepChr, e: e.copy());
}

/// Class OmmlMatrix.
class OmmlMatrix extends OmmlNode {
  /// OmmlMatrix API.
  OmmlMatrix({List<List<OmmlSeq>>? rows})
    : rows =
          rows ??
          <List<OmmlSeq>>[
            <OmmlSeq>[OmmlSeq(), OmmlSeq()],
            <OmmlSeq>[OmmlSeq(), OmmlSeq()],
          ];

  /// rows API.
  List<List<OmmlSeq>> rows;

  @override
  /// copy API.
  OmmlMatrix copy() => OmmlMatrix(
    rows: <List<OmmlSeq>>[
      for (final List<OmmlSeq> row in rows)
        <OmmlSeq>[for (final OmmlSeq cell in row) cell.copy()],
    ],
  );
}

/// Class OmmlAcc.
class OmmlAcc extends OmmlNode {
  /// OmmlAcc API.
  OmmlAcc({this.chr = 'ˆ', OmmlSeq? e}) : e = e ?? OmmlSeq();

  /// chr API.
  String chr;

  /// e API.
  OmmlSeq e;

  @override
  /// copy API.
  OmmlAcc copy() => OmmlAcc(chr: chr, e: e.copy());
}

/// Class OmmlFunc.
class OmmlFunc extends OmmlNode {
  /// OmmlFunc API.
  OmmlFunc({this.name = 'sin', OmmlSeq? e}) : e = e ?? OmmlSeq();

  /// name API.
  String name;

  /// e API.
  OmmlSeq e;

  @override
  /// copy API.
  OmmlFunc copy() => OmmlFunc(name: name, e: e.copy());
}

/// Class OmmlLimLow.
class OmmlLimLow extends OmmlNode {
  /// OmmlLimLow API.
  OmmlLimLow({OmmlSeq? e, OmmlSeq? lim})
    : e =
          e ??
          OmmlSeq(
            children: <OmmlNode>[
              OmmlText(text: 'lim', italic: false, normal: true),
            ],
          ),
      lim = lim ?? OmmlSeq();

  /// e API.
  OmmlSeq e;

  /// lim API.
  OmmlSeq lim;

  @override
  /// copy API.
  OmmlLimLow copy() => OmmlLimLow(e: e.copy(), lim: lim.copy());
}

/// Class OmmlBar.
class OmmlBar extends OmmlNode {
  /// OmmlBar API.
  OmmlBar({OmmlSeq? e, this.posTop = true}) : e = e ?? OmmlSeq();

  /// e API.
  OmmlSeq e;

  /// posTop API.
  bool posTop;

  @override
  /// copy API.
  OmmlBar copy() => OmmlBar(e: e.copy(), posTop: posTop);
}

/// Class OmmlEquation.
class OmmlEquation {
  /// OmmlEquation API.
  OmmlEquation({
    OmmlSeq? root,
    this.display = OmmlDisplay.display,
    this.view = OmmlView.professional,
    this.linearText = '',
  }) : root = root ?? OmmlSeq();

  /// root API.
  OmmlSeq root;

  /// display API.
  OmmlDisplay display;

  /// view API.
  OmmlView view;

  /// linearText API.
  String linearText;

  /// empty API.
  factory OmmlEquation.empty() => OmmlEquation();

  /// copy API.
  OmmlEquation copy() => OmmlEquation(
    root: root.copy(),
    display: display,
    view: view,
    linearText: linearText,
  );
}
