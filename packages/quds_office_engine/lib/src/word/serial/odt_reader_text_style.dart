import '../../odf/odf_zotero_models.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../properties/wml_properties.dart';
import 'word_property_io.dart';

/// Transient ODF script-specific values. These never enter the Word model:
/// supported source text is materialized into ordinary native runs instead.
final class OdtReaderScriptStyle {
  String? font;
  int? size;
  bool? bold;
  bool? italic;
  String? language;
  bool languageSpecified = false;
  bool? noProof;

  OdtReaderScriptStyle copy() => OdtReaderScriptStyle()
    ..font = font
    ..size = size
    ..bold = bold
    ..italic = italic
    ..language = language
    ..languageSpecified = languageSpecified
    ..noProof = noProof;
}

enum OdtTextScript { latin, complex, asian }

/// Actual preceding Unicode script, independent of how runs were projected.
/// One context spans adjacent text/style/link nodes in a paragraph; a genuine
/// inline object or a new paragraph starts a new context.
final class OdtReaderScriptContext {
  OdtTextScript? previous;
}

/// Resolved text style before the input's Unicode script runs are known.
///
/// ODF 1.4 section 20.358 defines three independent script slots. Word's
/// editor model exposes a single size/weight/style, so active distinctions are
/// flattened at emission, without changing text or UTF-16 field coordinates.
final class OdtReaderTextStyle extends WmlRunProps {
  OdtReaderTextStyle.from(WmlRunProps source)
    : super(
        styleId: source.styleId,
        bold: source.bold,
        italic: source.italic,
        underline: source.underline,
        strike: source.strike,
        allCaps: source.allCaps,
        smallCaps: source.smallCaps,
        color: source.color,
        highlight: source.highlight,
        fontSizeHalfPoints: source.fontSizeHalfPoints,
        kerningHalfPoints: source.kerningHalfPoints,
        asciiFont: source.asciiFont,
        csFont: source.csFont,
        vertAlign: source.vertAlign,
        positionHalfPoints: source.positionHalfPoints,
        proofingLanguage: source.proofingLanguage,
        noProof: source.noProof,
        complexScriptLanguage: source.complexScriptLanguage,
        complexScript: source.complexScript,
      ) {
    explicitProperties.addAll(source.explicitProperties);
    if (source is OdtReaderTextStyle) {
      complex = source.complex.copy();
      asian = source.asian.copy();
      opacity = source.opacity;
      automaticColor = source.automaticColor;
      hyphenate = source.hyphenate;
    }
  }

  OdtReaderScriptStyle complex = OdtReaderScriptStyle();
  OdtReaderScriptStyle asian = OdtReaderScriptStyle();
  double opacity = 100;
  bool automaticColor = false;
  bool hyphenate = false;

  @override
  OdtReaderTextStyle copy() => OdtReaderTextStyle.from(this);

  void validateEffective() {
    // ODF 1.4 section 20.227 leaves a simultaneous non-default font variant
    // and text transform undefined. Check after inheritance so an explicit
    // child normal/none can resolve the conflict before text is materialized.
    if (allCaps && smallCaps) {
      throw UnsupportedError(
        'Combined ODT uppercase and small capitals are not supported.',
      );
    }
    if (opacity != 100) {
      throw UnsupportedError('Effective ODT text opacity is not supported.');
    }
    if (automaticColor) {
      throw UnsupportedError(
        'Effective automatic ODT text color is not supported.',
      );
    }
    if (hyphenate) {
      throw UnsupportedError(
        'Automatic ODT text hyphenation is not supported.',
      );
    }
  }

  /// Whether link states have the same supported formatting and inheritance.
  ///
  /// Equal current projections alone are insufficient: an explicit complex
  /// script value and a Western fallback may diverge inside a child span.
  /// Require the same nullable slots and explicit-property state first, then
  /// compare every native script projection and its retained source properties.
  bool hasSameResolvedFormattingAs(OdtReaderTextStyle other) {
    Object scriptValues(OdtReaderScriptStyle value) => (
      value.font,
      value.size,
      value.bold,
      value.italic,
      value.language,
      value.languageSpecified,
      value.noProof,
    );
    if (scriptValues(complex) != scriptValues(other.complex) ||
        scriptValues(asian) != scriptValues(other.asian) ||
        opacity != other.opacity ||
        automaticColor != other.automaticColor ||
        hyphenate != other.hyphenate ||
        explicitProperties.length != other.explicitProperties.length ||
        !explicitProperties.every(other.explicitProperties.contains)) {
      return false;
    }
    for (final script in OdtTextScript.values) {
      final current = nativeProperties(script: script, projectedText: true);
      final candidate = other.nativeProperties(
        script: script,
        projectedText: true,
      );
      final currentValues = WordPropertyIo.runValues(current);
      final candidateValues = WordPropertyIo.runValues(candidate);
      if (current.styleId != candidate.styleId ||
          current.proofingLanguage != candidate.proofingLanguage ||
          current.complexScriptLanguage != candidate.complexScriptLanguage ||
          current.highlight != candidate.highlight ||
          current.complexScript != candidate.complexScript ||
          current.sourcePropertiesXml != candidate.sourcePropertiesXml ||
          currentValues.length != candidateValues.length ||
          currentValues.entries.any(
            (entry) => candidateValues[entry.key] != entry.value,
          )) {
        return false;
      }
    }
    return true;
  }

  bool get _distinctComplexFormatting =>
      csFont != asciiFont ||
      (complexScriptLanguage ?? proofingLanguage) != proofingLanguage ||
      (complex.size ?? fontSizeHalfPoints) != fontSizeHalfPoints ||
      (complex.bold ?? bold) != bold ||
      (complex.italic ?? italic) != italic ||
      (complex.noProof ?? noProof ?? false) != (noProof ?? false);

  /// Group actual source text by script, including when all initial values
  /// agree. Script ownership must still select the right font/language slots
  /// after editing. Marks and joiners stay with their preceding base.
  Iterable<({String text, WmlRunProps properties})> materialize(
    String text, {
    OdtReaderScriptContext? context,
  }) sync* {
    validateEffective();
    if (text.isEmpty) return;
    var start = 0;
    var offset = 0;
    OdtTextScript? previous = context?.previous;
    OdtTextScript? group;
    for (final rune in text.runes) {
      final script = _script(rune, previous);
      previous = script;
      if (group != null && script != group) {
        yield (
          text: text.substring(start, offset),
          properties: nativeProperties(script: group, projectedText: true),
        );
        start = offset;
      }
      group = script;
      offset += rune > 0xffff ? 2 : 1;
    }
    context?.previous = previous;
    yield (
      text: text.substring(start),
      properties: nativeProperties(script: group!, projectedText: true),
    );
  }

  /// Materialize a paragraph mark or a source-text segment. The source XML
  /// carries script slots unavailable as independent public model properties.
  /// Only explicitly projected segments own subsequent synchronized edits.
  WmlRunProps nativeProperties({
    OdtTextScript script = OdtTextScript.latin,
    bool projectedText = false,
  }) {
    validateEffective();
    final result = super.copy();
    final slot = script == OdtTextScript.complex ? complex : asian;
    final projection = script != OdtTextScript.latin
        ? script.name
        : projectedText && !_distinctComplexFormatting
        ? 'shared'
        : null;
    if (script != OdtTextScript.latin) {
      result
        ..fontSizeHalfPoints = slot.size ?? fontSizeHalfPoints
        ..bold = slot.bold ?? bold
        ..italic = slot.italic ?? italic
        ..noProof = slot.noProof ?? noProof;
      if (script == OdtTextScript.complex) {
        // Keep the independent font/language slots intact. The explicit
        // native marker selects the complex slot for Indic/Thai as well as
        // RTL scripts, including after a later complex-font edit.
        result.complexScript = true;
      } else {
        result
          ..asciiFont = asian.font ?? asciiFont
          ..proofingLanguage = asian.languageSpecified
              ? asian.language
              : proofingLanguage;
      }
    }

    final source = XmlElement(
      localName: 'rPr',
      prefix: 'w',
      namespaceUri: OfficeNamespaces.w,
    )..setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
    if (projection != null) {
      source
        ..setAttribute(
          'qodt',
          WordPropertyIo.odtScriptProjectionNamespace,
          prefix: 'xmlns',
        )
        ..setAttribute(
          'mc',
          'http://schemas.openxmlformats.org/markup-compatibility/2006',
          prefix: 'xmlns',
        )
        ..setAttribute(
          'Ignorable',
          'qodt',
          prefix: 'mc',
          namespaceUri:
              'http://schemas.openxmlformats.org/markup-compatibility/2006',
        )
        ..setAttribute(
          'script',
          projection,
          prefix: 'qodt',
          namespaceUri: WordPropertyIo.odtScriptProjectionNamespace,
        );
    }
    void word(String name, String value) => source.addChild(
      XmlElement(localName: name, prefix: 'w', namespaceUri: OfficeNamespaces.w)
        ..setAttribute(
          'val',
          value,
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        ),
    );
    word(
      'bCs',
      (script == OdtTextScript.complex ? result.bold : complex.bold ?? bold)
          ? '1'
          : '0',
    );
    word(
      'iCs',
      (script == OdtTextScript.complex
              ? result.italic
              : complex.italic ?? italic)
          ? '1'
          : '0',
    );
    word(
      'szCs',
      '${script == OdtTextScript.complex ? result.fontSizeHalfPoints : complex.size ?? fontSizeHalfPoints}',
    );
    if (script == OdtTextScript.complex) word('cs', '1');
    if (asian.font != null || script == OdtTextScript.asian) {
      source.addChild(
        XmlElement(
          localName: 'rFonts',
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        )..setAttribute(
          'eastAsia',
          script == OdtTextScript.asian ? result.asciiFont : asian.font!,
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        ),
      );
    }
    final language = script == OdtTextScript.asian
        ? result.proofingLanguage
        : asian.language;
    if (language != null) {
      source.addChild(
        XmlElement(
          localName: 'lang',
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        )..setAttribute(
          'eastAsia',
          language,
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        ),
      );
    }
    WordPropertyIo.orderChildren(source);
    result
      ..sourcePropertiesXml = XmlDocument(
        root: source,
      ).toXmlString(declaration: false)
      // Empty snapshots deliberately emit all flattened native values on first
      // save; later DOCX reads establish ordinary sparse source snapshots.
      ..importedValues = <String, String>{};
    return result;
  }

  static final _mark = RegExp(r'\p{M}', unicode: true);
  // LibreOffice i18nutil/source/utility/unicode.cxx classifies these scripts
  // as Asian. Script properties include supplementary Kana, Tangut, Khitan,
  // and Hangul extensions outside ODF's older block table.
  static final _asianScript = RegExp(
    r'[\p{Script=Han}\p{Script=Hangul}\p{Script=Hiragana}'
    r'\p{Script=Katakana}\p{Script=Bopomofo}\p{Script=Yi}'
    r'\p{Script=Tangut}\p{Script=Khitan_Small_Script}]',
    unicode: true,
  );

  static OdtTextScript _script(int rune, OdtTextScript? previous) {
    if (previous != null &&
        (_mark.hasMatch(String.fromCharCode(rune)) ||
            rune == 0x200c ||
            rune == 0x200d)) {
      return previous;
    }
    // ODF 1.4, 20.358 table 23. Newer Arabic/CJK blocks extend the
    // implementation-defined remainder without classifying emoji as CJK.
    if (_in(rune, 0x0590, 0x074f) ||
        _in(rune, 0x0750, 0x08ff) ||
        _in(rune, 0x0900, 0x109f) ||
        _in(rune, 0x1200, 0x137f) ||
        _in(rune, 0x1780, 0x18af) ||
        _in(rune, 0xfb1d, 0xfdff) ||
        _in(rune, 0xfe70, 0xfeff) ||
        _in(rune, 0x1ee00, 0x1eeff)) {
      return OdtTextScript.complex;
    }
    if (_asianScript.hasMatch(String.fromCharCode(rune)) ||
        _in(rune, 0x1100, 0x11ff) ||
        _in(rune, 0x2e80, 0x31ef) ||
        _in(rune, 0x3200, 0x4dbf) ||
        _in(rune, 0x4e00, 0xa4cf) ||
        _in(rune, 0xac00, 0xd7af) ||
        _in(rune, 0xf900, 0xfaff) ||
        _in(rune, 0xfe30, 0xfe4f) ||
        _in(rune, 0xff00, 0xffef) ||
        _in(rune, 0x20000, 0x323af)) {
      return OdtTextScript.asian;
    }
    return OdtTextScript.latin;
  }

  static bool _in(int value, int lower, int upper) =>
      value >= lower && value <= upper;
}

/// A shared document budget bounds alternating-script run allocations too.
final class OdtReaderRunBudget {
  static const maximum = 100000;
  int _count = 0;

  void consume() {
    if (++_count > maximum) {
      throw const OdfZoteroLimitException('materialized text runs');
    }
  }
}
