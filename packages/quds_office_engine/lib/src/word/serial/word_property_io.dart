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
    'smallCaps': '${r.smallCaps}',
    'color': r.color,
    'sz': '${r.fontSizeHalfPoints}',
    'kern': '${r.kerningHalfPoints}',
    'highlight': '${r.highlight}',
    'u': '${r.underline}',
    'vertAlign': '${r.vertAlign}',
    'lang': '${r.proofingLanguage}',
    'lang:bidi': '${r.complexScriptLanguage}',
    'noProof': '${r.noProof}',
  };
  static Map<String, String> paragraphValues(WmlParagraphProps p) => {
    'pStyle': '${p.styleId}',
    'jc': '${p.justification}',
    'spacing':
        '${p.spacingBefore}|${p.spacingAfter}|${p.lineSpacing}|${p.lineSpacingRule}',
    // Keep the aggregate for older snapshots, while separately tracking
    // attribute groups so a line-spacing write does not own before/after.
    'spacing:before': '${p.spacingBefore}',
    'spacing:after': '${p.spacingAfter}',
    'spacing:line': '${p.lineSpacing}|${p.lineSpacingRule}',
    'spacing:granular': '1',
    'ind':
        '${p.indent.left}|${p.indent.right}|${p.indent.firstLine}|${p.indent.hanging}',
    'keepLines': '${p.keepTogether}',
    'pageBreakBefore': '${p.pageBreakBefore}',
    'numPr': '${p.numId ?? (p.numberingSuppressed ? 0 : null)}|${p.ilvl}',
    'outlineLvl': '${p.headingLevel}',
    'bidi': '${p.rightToLeft}',
    'rPr': '${p.proofingLanguage}',
    'suppressAutoHyphens': '${p.suppressAutoHyphens}',
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
      if (generated.localName == 'pPr') {
        if (key.startsWith('spacing:')) continue;
        if (key == 'spacing') {
          _preserveSpacing(result, generated, imported, current);
          continue;
        }
      }
      if (current[key] == imported[key]) continue;
      if (generated.localName == 'pPr' && key == 'bidi') {
        // Reading order owns only the Word val attribute, including an
        // explicit false against inherited RTL. Retain extension metadata.
        final bidi = generated.firstChild('bidi');
        _mergeWordAttributes(
          result,
          'bidi',
          const {'val'},
          {'val': bidi == null ? '0' : bidi.getAttribute('val') ?? '1'},
        );
        continue;
      }
      if (key == 'lang' || key == 'lang:bidi' || key == 'rPr') {
        // Each language value owns only its own attribute. Preserve East
        // Asian language and unrelated formatting from the native source.
        if (key == 'lang' || key == 'lang:bidi') {
          final attribute = key == 'lang' ? 'val' : 'bidi';
          mergeLanguage(
            result,
            generated.firstChild('lang')?.getAttribute(attribute),
            attribute: attribute,
          );
        } else {
          var marker = result.firstChild(
            'rPr',
            namespaceUri: OfficeNamespaces.w,
          );
          final value = generated
              .firstChild('rPr')
              ?.firstChild('lang')
              ?.getAttribute('val');
          if (marker == null && value != null) {
            marker = XmlElement(
              localName: 'rPr',
              prefix: 'w',
              namespaceUri: OfficeNamespaces.w,
            );
            result.addChild(marker);
          }
          if (marker != null) mergeLanguage(marker, value);
        }
        continue;
      }
      result.children.removeWhere(
        // The regular-size field owns sz; a separate szCs is source data for
        // the complex-script size and must survive a regular-size edit.
        // Foreign properties can share local names. Only Word elements and
        // intentionally unbound internal w fragments belong to this edit.
        (n) =>
            n is XmlElement &&
            n.localName == key &&
            (n.namespaceUri == OfficeNamespaces.w ||
                (n.namespaceUri.isEmpty && n.prefix == 'w')),
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
    orderChildren(result);
    return result;
  }

  static void _preserveSpacing(
    XmlElement result,
    XmlElement generated,
    Map<String, String> imported,
    Map<String, String> current,
  ) {
    const groups = <String, Set<String>>{
      'before': {'before', 'beforeLines', 'beforeAutospacing'},
      'after': {'after', 'afterLines', 'afterAutospacing'},
      'line': {'line', 'lineRule'},
    };
    final granular =
        imported['spacing:granular'] == '1' ||
        groups.keys.any((group) => imported.containsKey('spacing:$group'));
    // A removed aggregate remains the legacy explicit all-spacing override.
    // Old maps without granular snapshots retain their previous behavior.
    final whole = !imported.containsKey('spacing') || !granular;
    if (whole && current['spacing'] == imported['spacing']) return;
    final replacement = generated.firstChild('spacing');
    for (final entry in groups.entries) {
      final key = 'spacing:${entry.key}';
      if (!whole && current[key] == imported[key]) continue;
      _mergeWordAttributes(result, 'spacing', entry.value, {
        for (final attribute in entry.value)
          attribute: ?replacement?.getAttribute(attribute),
      });
    }
  }

  static bool _wordName(String namespace, String prefix) =>
      namespace == OfficeNamespaces.w || (namespace.isEmpty && prefix == 'w');

  static void _mergeWordAttributes(
    XmlElement properties,
    String name,
    Set<String> owned,
    Map<String, String> values,
  ) {
    XmlElement? target;
    for (final child in properties.childElements) {
      if (child.localName == name &&
          _wordName(child.namespaceUri, child.prefix)) {
        target = child;
        break;
      }
    }
    if (target == null) {
      if (values.isEmpty) return;
      target = XmlElement(
        localName: name,
        prefix: _wordAttributePrefix(properties),
        namespaceUri: OfficeNamespaces.w,
      );
      properties.addChild(target);
    }
    target.attributes.removeWhere(
      (attribute) =>
          owned.contains(attribute.localName) &&
          _wordName(attribute.namespaceUri, attribute.prefix),
    );
    if (values.isEmpty) return;
    final prefix = _wordAttributePrefix(target);
    for (final entry in values.entries) {
      target.attributes.add(
        XmlAttribute(
          localName: entry.key,
          value: entry.value,
          prefix: prefix,
          namespaceUri: OfficeNamespaces.w,
        ),
      );
    }
  }

  static String _wordAttributePrefix(XmlElement element) {
    final bindings = <String, String>{};
    for (XmlElement? node = element; node != null; node = node.parent) {
      for (final attribute in node.attributes) {
        if (attribute.prefix == 'xmlns') {
          bindings.putIfAbsent(attribute.localName, () => attribute.value);
        } else if (attribute.prefix.isNotEmpty &&
            attribute.namespaceUri.isNotEmpty) {
          bindings.putIfAbsent(attribute.prefix, () => attribute.namespaceUri);
        }
      }
      if (node.prefix.isNotEmpty && node.namespaceUri.isNotEmpty) {
        bindings[node.prefix] ??= node.namespaceUri;
      }
    }
    var prefix = 'w';
    for (
      var suffix = 1;
      bindings[prefix] != null && bindings[prefix] != OfficeNamespaces.w;
      suffix++
    ) {
      prefix = 'w$suffix';
    }
    element.attributes.removeWhere(
      (attribute) => attribute.qualifiedName == 'xmlns:$prefix',
    );
    element.attributes.add(
      XmlAttribute(
        localName: prefix,
        value: OfficeNamespaces.w,
        prefix: 'xmlns',
        namespaceUri: 'http://www.w3.org/2000/xmlns/',
      ),
    );
    return prefix;
  }

  /// Change the owned language attribute while preserving native metadata.
  static void mergeLanguage(
    XmlElement runProperties,
    String? language, {
    String attribute = 'val',
  }) {
    if (attribute != 'val' && attribute != 'bidi') {
      throw ArgumentError.value(attribute, 'attribute');
    }
    var lang = runProperties.firstChild(
      'lang',
      namespaceUri: OfficeNamespaces.w,
    );
    if (lang == null && language != null && language.isNotEmpty) {
      lang = XmlElement(
        localName: 'lang',
        prefix: 'w',
        namespaceUri: OfficeNamespaces.w,
      )..setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
      runProperties.addChild(lang);
    }
    if (lang == null) return;
    if (language == null || language.isEmpty) {
      lang.attributes.removeWhere(
        (a) => a.localName == attribute && a.namespaceUri == OfficeNamespaces.w,
      );
      if (lang.attributes.every((a) => a.prefix == 'xmlns')) {
        runProperties.children.remove(lang);
      }
    } else {
      lang.setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
      lang.setAttribute(
        attribute,
        language,
        prefix: 'w',
        namespaceUri: OfficeNamespaces.w,
      );
    }
    orderChildren(runProperties);
  }

  /// Canonical OOXML property order for sparse style and direct property edits.
  static void orderChildren(XmlElement element) {
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
    final order = switch (element.localName) {
      'rPr' => runOrder,
      'pPr' => paragraphOrder,
      'tblPr' => [
        'tblStyle',
        'tblpPr',
        'tblOverlap',
        'bidiVisual',
        'tblStyleRowBandSize',
        'tblStyleColBandSize',
        'tblW',
        'jc',
        'tblCellSpacing',
        'tblInd',
        'tblBorders',
        'shd',
        'tblLayout',
        'tblCellMar',
        'tblLook',
        'tblCaption',
        'tblDescription',
        'tblPrChange',
      ],
      'tcPr' => [
        'cnfStyle',
        'tcW',
        'gridSpan',
        'hMerge',
        'vMerge',
        'tcBorders',
        'shd',
        'noWrap',
        'tcMar',
        'textDirection',
        'tcFitText',
        'vAlign',
        'hideMark',
        'headers',
        'cellIns',
        'cellDel',
        'cellMerge',
        'tcPrChange',
      ],
      'style' => [
        'name',
        'aliases',
        'basedOn',
        'next',
        'link',
        'autoRedefine',
        'hidden',
        'uiPriority',
        'semiHidden',
        'unhideWhenUsed',
        'qFormat',
        'locked',
        'personal',
        'personalCompose',
        'personalReply',
        'rsid',
        'pPr',
        'rPr',
        'tblPr',
        'trPr',
        'tcPr',
        'tblStylePr',
      ],
      _ => <String>[],
    };
    int rank(XmlNode n) {
      final i = n is XmlElement ? order.indexOf(n.localName) : -1;
      return i < 0 ? order.length : i;
    }

    element.children.sort((a, b) => rank(a).compareTo(rank(b)));
  }
}
