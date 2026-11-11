import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../properties/wml_properties.dart';

/// Sparse source properties and effective values must remain separate: writing
/// inherited values as direct formatting would prevent subsequent style edits.
abstract final class WordPropertyIo {
  static Map<String, String> runValues(WmlRunProps r) => {
    'rStyle': '${r.styleId}',
    'rFonts': '${r.asciiFont}|${r.csFont}',
    'b': '${r.bold}',
    'i': '${r.italic}',
    'strike': '${r.strike}',
    'color': r.color,
    'sz': '${r.fontSizeHalfPoints}',
    'highlight': '${r.highlight}',
    'u': '${r.underline}',
    'vertAlign': '${r.vertAlign}',
  };
  static Map<String, String> paragraphValues(WmlParagraphProps p) => {
    'pStyle': '${p.styleId}',
    'jc': '${p.justification}',
    'spacing':
        '${p.spacingBefore}|${p.spacingAfter}|${p.lineSpacing}|${p.lineSpacingRule}',
    'ind':
        '${p.indent.left}|${p.indent.right}|${p.indent.firstLine}|${p.indent.hanging}',
    'keepLines': '${p.keepTogether}',
    'pageBreakBefore': '${p.pageBreakBefore}',
    'numPr': '${p.numId}|${p.ilvl}',
    'outlineLvl': '${p.headingLevel}',
    'bidi': '${p.rightToLeft}',
    'framePr': '${p.dropCapLines}',
    'shd': '${p.shadingFill}',
    'pBdr': '${p.borderColor}',
    'tabs': p.tabs
        .map((t) => '${t.position}|${t.alignment}|${t.leader}')
        .join(','),
  };
  static XmlElement parse(String? xml, String name) =>
      xml == null || xml.isEmpty
      ? XmlElement(
          localName: name,
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        )
      : XmlDocument.parse(xml).root!;

  static XmlElement preserve(
    XmlElement generated,
    String source,
    Map<String, String> imported,
    Map<String, String> current,
  ) {
    final XmlElement result = parse(source, generated.localName);
    for (final String key in current.keys) {
      if (current[key] == imported[key]) continue;
      result.children.removeWhere(
        (n) =>
            n is XmlElement &&
            (n.localName == key || key == 'sz' && n.localName == 'szCs'),
      );
      final List<XmlElement> replacement = generated.childrenNamed(key);
      if (replacement.isNotEmpty) {
        for (final n in replacement) {
          result.addChild(n.copy());
        }
      } else if (const {
        'strike',
        'keepLines',
        'pageBreakBefore',
        'bidi',
      }.contains(key)) {
        result.addChild(
          XmlElement(localName: key, prefix: 'w')
            ..setAttribute('val', '0', prefix: 'w'),
        );
      } else if (const {'u', 'highlight', 'vertAlign'}.contains(key)) {
        result.addChild(
          XmlElement(localName: key, prefix: 'w')..setAttribute(
            'val',
            key == 'vertAlign' ? 'baseline' : 'none',
            prefix: 'w',
          ),
        );
      }
    }
    result.children.removeWhere(
      (n) => n is XmlElement && n.localName == 'sectPr',
    );
    for (final n in generated.childrenNamed('sectPr')) {
      result.addChild(n.copy());
    }
    order(result);
    return result;
  }

  /// Put properties in OOXML schema order after an explicit style edit.
  static void order(XmlElement properties) {
    const runOrder = [
      'rStyle',
      'rFonts',
      'b',
      'bCs',
      'i',
      'iCs',
      'caps',
      'smallCaps',
      'strike',
      'dstrike',
      'outline',
      'shadow',
      'emboss',
      'imprint',
      'noProof',
      'snapToGrid',
      'vanish',
      'webHidden',
      'color',
      'spacing',
      'w',
      'kern',
      'position',
      'sz',
      'szCs',
      'highlight',
      'u',
      'effect',
      'bdr',
      'shd',
      'fitText',
      'vertAlign',
      'rtl',
      'cs',
      'em',
      'lang',
      'eastAsianLayout',
      'specVanish',
      'oMath',
      'rPrChange',
    ];
    const paragraphOrder = [
      'pStyle',
      'keepNext',
      'keepLines',
      'pageBreakBefore',
      'framePr',
      'widowControl',
      'numPr',
      'suppressLineNumbers',
      'pBdr',
      'shd',
      'tabs',
      'suppressAutoHyphens',
      'kinsoku',
      'wordWrap',
      'overflowPunct',
      'topLinePunct',
      'autoSpaceDE',
      'autoSpaceDN',
      'bidi',
      'adjustRightInd',
      'snapToGrid',
      'spacing',
      'ind',
      'contextualSpacing',
      'mirrorIndents',
      'suppressOverlap',
      'jc',
      'textDirection',
      'textAlignment',
      'textboxTightWrap',
      'outlineLvl',
      'divId',
      'cnfStyle',
      'rPr',
      'sectPr',
      'pPrChange',
    ];
    final order = properties.localName == 'rPr' ? runOrder : paragraphOrder;
    int rank(XmlNode n) {
      final i = n is XmlElement ? order.indexOf(n.localName) : -1;
      return i < 0 ? order.length : i;
    }

    properties.children.sort((a, b) => rank(a).compareTo(rank(b)));
  }
}
