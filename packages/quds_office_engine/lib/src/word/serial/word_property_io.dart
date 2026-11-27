import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../properties/wml_properties.dart';

/// Sparse source properties and effective values must remain separate: writing
/// inherited values as direct formatting would prevent subsequent style edits.
abstract final class WordPropertyIo {
  /// Keep captured native Word XML self-contained after the caller has verified
  /// that the fragment only uses the Word prefix and has no local declarations.
  static void compactScalarWordFragment(XmlElement element) {
    element.attributes.removeWhere(
      (attribute) =>
          attribute.prefix == 'xmlns' && attribute.localName != 'w',
    );
  }

  /// Private, ignorable provenance for runs whose ODF script formatting was
  /// flattened into the editor's scalar controls. Ordinary DOCX properties
  /// retain their independent native slots and never acquire this ownership.
  static const odtScriptProjectionNamespace =
      'urn:quds:office:odt-script-projection:1';

  static Map<String, String> runValues(WmlRunProps r) => {
    'rStyle': '${r.styleId}',
    'rFonts': '${r.asciiFont}|${r.csFont}',
    // Independent font slots must not turn inherited or themed fonts into
    // direct formatting when only the other script's font changes.
    'rFonts:ascii': r.asciiFont,
    'rFonts:cs': r.csFont,
    'rFonts:granular': '1',
    'b': '${r.bold}',
    'i': '${r.italic}',
    'strike': '${r.strike}',
    'caps': '${r.allCaps}',
    'smallCaps': '${r.smallCaps}',
    'color': r.color,
    'sz': '${r.fontSizeHalfPoints}',
    'kern': '${r.kerningHalfPoints}',
    'position': '${r.positionHalfPoints}',
    'highlight': '${r.highlight}',
    // The editor exposes one effective text background. Non-palette colors
    // are stored in native run shading instead of an invalid w:highlight.
    // Unprojected patterned/themed shading remains opaque source metadata.
    'shd': usesRunShading(r) ? '${WmlHighlight.toRgb(r.highlight)}' : 'null',
    'u': '${r.underline}',
    'vertAlign': '${r.vertAlign}',
    'lang': '${r.proofingLanguage}',
    'lang:bidi': '${r.complexScriptLanguage}',
    'noProof': '${r.noProof}',
  };

  static bool usesRunShading(WmlRunProps r) =>
      r.explicitProperties.contains('shd:highlight') ||
      (WmlHighlight.toRgb(r.highlight) != null &&
          WmlHighlight.toName(r.highlight) == null);
  static Map<String, String> paragraphValues(WmlParagraphProps p) => {
    'pStyle': '${p.styleId}',
    'jc': '${p.justification}',
    'jc:logical': paragraphJustificationValue(p),
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
    // The editor owns physical margins, while native start/end are logical.
    // Track the encoded sides independently so changing direction preserves
    // physical placement without flattening unrelated inherited indentation.
    'ind:start': '${p.rightToLeft == true ? p.indent.right : p.indent.left}',
    'ind:end': '${p.rightToLeft == true ? p.indent.left : p.indent.right}',
    'ind:firstLine': '${p.indent.firstLine}|${p.indent.hanging}',
    'ind:granular': '1',
    'keepLines': '${p.keepTogether}',
    'keepNext': '${p.keepWithNext}',
    'widowControl': '${p.widowControl}',
    'contextualSpacing': '${p.contextualSpacing}',
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

  static String paragraphJustificationValue(WmlParagraphProps p) =>
      switch (p.justification) {
        WmlJustification.center => 'center',
        WmlJustification.right => p.rightToLeft == true ? 'left' : 'right',
        WmlJustification.justify => 'both',
        WmlJustification.distributed => 'distribute',
        WmlJustification.left => p.rightToLeft == true ? 'right' : 'left',
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
    Map<String, String> current, {
    XmlElement? sourceElement,
  }) {
    final XmlElement result =
        sourceElement?.copy() ?? parse(source, generated.localName);
    for (final String key in current.keys) {
      if (generated.localName == 'rPr') {
        if (key.startsWith('rFonts:')) continue;
        if (key == 'rFonts') {
          _preserveRunFonts(result, generated, imported, current);
          continue;
        }
      }
      if (generated.localName == 'pPr') {
        if (key.startsWith('spacing:') ||
            key.startsWith('ind:') ||
            key.startsWith('jc:')) {
          continue;
        }
        if (key == 'spacing') {
          _preserveSpacing(result, generated, imported, current);
          continue;
        }
        if (key == 'ind') {
          _preserveIndent(result, generated, imported, current);
          continue;
        }
        if (key == 'jc') {
          _preserveJustification(result, generated, imported, current);
          continue;
        }
      }
      if (current[key] == imported[key]) continue;
      if (generated.localName == 'rPr' && key == 'color') {
        // An explicit foreground choice owns its native value and theme
        // selectors, while extension metadata and namespace aliases survive.
        // This also retains an automatic value equal to the resolved import.
        final value = generated.childElements
            .where(
              (child) =>
                  child.localName == 'color' &&
                  _wordName(child.namespaceUri, child.prefix),
            )
            .firstOrNull
            ?.attributes
            .where(
              (attribute) =>
                  attribute.localName == 'val' &&
                  _wordName(attribute.namespaceUri, attribute.prefix),
            )
            .firstOrNull
            ?.value;
        if (value != null) {
          _mergeWordAttributes(
            result,
            'color',
            const {'val', 'themeColor', 'themeShade', 'themeTint'},
            {'val': value},
          );
          continue;
        }
      }
      if (generated.localName == 'rPr' && key == 'shd') {
        final shading = generated.firstChild('shd');
        _mergeWordAttributes(
          result,
          'shd',
          const {
            'val',
            'color',
            'fill',
            'themeColor',
            'themeTint',
            'themeShade',
            'themeFill',
            'themeFillTint',
            'themeFillShade',
          },
          {
            'val': 'clear',
            'color': 'auto',
            'fill': shading?.getAttribute('fill') ?? 'auto',
          },
        );
        continue;
      }
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
      if ((generated.localName == 'rPr' &&
              (key == 'kern' ||
                  key == 'position' ||
                  key == 'noProof' ||
                  key == 'caps' ||
                  key == 'smallCaps')) ||
          (generated.localName == 'pPr' && key == 'suppressAutoHyphens')) {
        final value =
            generated.firstChild(key)?.getAttribute('val') ??
            (key == 'position' ? '0' : null);
        if (value != null) {
          // Scalar controls own only the native value, not extension
          // metadata, foreign same-name properties, or their namespace aliases.
          _mergeWordAttributes(result, key, const {'val'}, {'val': value});
          continue;
        }
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
          _appendGenerated(result, n);
        }
      } else if (const {
        'strike',
        'keepLines',
        'keepNext',
        'contextualSpacing',
        'pageBreakBefore',
        'bidi',
      }.contains(key)) {
        _appendGenerated(
          result,
          XmlElement(localName: key, prefix: 'w')
            ..setAttribute('val', '0', prefix: 'w'),
        );
      } else if (const {'u', 'highlight', 'vertAlign'}.contains(key)) {
        _appendGenerated(
          result,
          XmlElement(localName: key, prefix: 'w')..setAttribute(
            'val',
            key == 'vertAlign' ? 'baseline' : 'none',
            prefix: 'w',
          ),
        );
      }
    }
    if (generated.localName == 'rPr') {
      _preserveOdtScriptProjection(result, generated, imported, current);
    }
    if (generated.localName == 'pPr') {
      result.children.removeWhere(
        (n) =>
            n is XmlElement &&
            n.localName == 'sectPr' &&
            _wordName(n.namespaceUri, n.prefix),
      );
      for (final n in generated.childrenNamed('sectPr')) {
        _appendGenerated(result, n);
      }
    }
    orderChildren(result);
    return result;
  }

  static void _preserveOdtScriptProjection(
    XmlElement result,
    XmlElement generated,
    Map<String, String> imported,
    Map<String, String> current,
  ) {
    final projection = result.getAttribute(
      'script',
      namespaceUri: odtScriptProjectionNamespace,
    );
    if (projection == 'complex' || projection == 'shared') {
      for (final entry in const {
        'b': 'bCs',
        'i': 'iCs',
        'sz': 'szCs',
      }.entries) {
        if (current[entry.key] == imported[entry.key]) continue;
        final value = generated.firstChild(entry.key)?.getAttribute('val');
        if (value != null) {
          _mergeWordAttributes(
            result,
            entry.value,
            const {'val'},
            {'val': value},
          );
        }
      }
    } else if (projection == 'asian') {
      if (current['rFonts:ascii'] != imported['rFonts:ascii']) {
        final font = generated.firstChild('rFonts')?.getAttribute('ascii');
        _mergeWordAttributes(
          result,
          'rFonts',
          const {'eastAsia', 'eastAsiaTheme'},
          {'eastAsia': ?font},
        );
      }
      if (current['lang'] != imported['lang']) {
        final language = generated.firstChild('lang')?.getAttribute('val');
        _mergeWordAttributes(
          result,
          'lang',
          const {'eastAsia'},
          {'eastAsia': ?language},
        );
      }
    }
  }

  static void _preserveRunFonts(
    XmlElement result,
    XmlElement generated,
    Map<String, String> imported,
    Map<String, String> current,
  ) {
    const groups = <String, Set<String>>{
      'ascii': {'ascii', 'hAnsi', 'asciiTheme', 'hAnsiTheme'},
      'cs': {'cs', 'cstheme'},
    };
    final granular =
        imported['rFonts:granular'] == '1' ||
        groups.keys.any((group) => imported.containsKey('rFonts:$group'));
    // Removing the aggregate remains an explicit legacy all-font override.
    // Older snapshots without per-slot values retain aggregate comparison.
    final whole = !imported.containsKey('rFonts') || !granular;
    if (whole && current['rFonts'] == imported['rFonts']) return;
    final replacement = generated.firstChild('rFonts');
    for (final entry in groups.entries) {
      final key = 'rFonts:${entry.key}';
      if (!whole && current[key] == imported[key]) continue;
      _mergeWordAttributes(result, 'rFonts', entry.value, {
        for (final attribute in entry.value)
          attribute: ?replacement?.getAttribute(attribute),
      });
    }
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

  static void _preserveIndent(
    XmlElement result,
    XmlElement generated,
    Map<String, String> imported,
    Map<String, String> current,
  ) {
    const groups = <String, Set<String>>{
      'start': {'left', 'leftChars', 'start', 'startChars'},
      'end': {'right', 'rightChars', 'end', 'endChars'},
      'firstLine': {'firstLine', 'firstLineChars', 'hanging', 'hangingChars'},
    };
    final granular = imported['ind:granular'] == '1';
    // Legacy explicit all-indent writes remove the aggregate snapshot. Keep
    // that convention, and allow older saved histories without group values.
    final whole = !imported.containsKey('ind') || !granular;
    final directionChanged =
        (current['bidi'] == 'true') != (imported['bidi'] == 'true');
    if (whole && current['ind'] == imported['ind'] && !directionChanged) {
      return;
    }
    final replacement = generated.firstChild('ind');
    for (final entry in groups.entries) {
      final key = 'ind:${entry.key}';
      if (!whole && current[key] == imported[key]) continue;
      final values = <String, String>{
        for (final attribute in entry.value)
          attribute: ?replacement?.getAttribute(attribute),
      };
      if (entry.key == 'firstLine' && values.isEmpty && replacement != null) {
        // Omitting both exposes an inherited first-line/hanging indent.
        // One explicit zero resets their shared native inheritance group.
        values['firstLine'] = '0';
      }
      _mergeWordAttributes(result, 'ind', entry.value, values);
    }
  }

  static void _preserveJustification(
    XmlElement result,
    XmlElement generated,
    Map<String, String> imported,
    Map<String, String> current,
  ) {
    final unchanged = imported.containsKey('jc:logical')
        ? current['jc:logical'] == imported['jc:logical']
        : current['jc'] == imported['jc'] &&
              (current['bidi'] == 'true') == (imported['bidi'] == 'true');
    if (imported.containsKey('jc') && unchanged) return;
    final value = generated.firstChild('jc')?.getAttribute('val');
    if (value != null) {
      // Alignment owns its native value only. Foreign lookalikes, prefixes,
      // and extension attributes remain in the original sparse property.
      _mergeWordAttributes(result, 'jc', const {'val'}, {'val': value});
    }
  }

  static bool _wordName(String namespace, String prefix) =>
      namespace == OfficeNamespaces.w || (namespace.isEmpty && prefix == 'w');

  static void _appendGenerated(XmlElement target, XmlElement generated) {
    final inserted = generated.copy();
    if (inserted.prefix == 'w' &&
        _wordName(inserted.namespaceUri, inserted.prefix)) {
      inserted.namespaceUri = OfficeNamespaces.w;
      String? binding;
      for (XmlElement? node = target; node != null; node = node.parent) {
        binding = node.attributes
            .where((a) => a.qualifiedName == 'xmlns:w')
            .firstOrNull
            ?.value;
        if (binding != null) break;
        if (node.prefix == 'w' && node.namespaceUri.isNotEmpty) {
          binding = node.namespaceUri;
          break;
        }
      }
      // Generated fragments normally inherit the serializer's Word context.
      // Only a conflicting source binding needs a local declaration; never
      // rebind the sparse source itself or reinterpret retained extensions.
      if (binding != null && binding != OfficeNamespaces.w) {
        inserted.attributes.removeWhere((a) => a.qualifiedName == 'xmlns:w');
        inserted.attributes.add(
          XmlAttribute(
            localName: 'w',
            prefix: 'xmlns',
            namespaceUri: 'http://www.w3.org/2000/xmlns/',
            value: OfficeNamespaces.w,
          ),
        );
      }
    }
    target.addChild(inserted);
  }

  /// Change one native tab stop while retaining unowned attributes, children,
  /// other positions, and namespace lookalikes in the sparse direct pPr.
  /// Callers validate source tab positions and duplicate native containers.
  static void writeTabStop(
    XmlElement properties,
    int positionTwips,
    String alignment, {
    String? leader,
  }) {
    XmlElement? tabs;
    for (final child in properties.childElements) {
      if (child.localName == 'tabs' &&
          _wordName(child.namespaceUri, child.prefix)) {
        tabs = child;
        break;
      }
    }
    if (tabs == null) {
      tabs = XmlElement(
        localName: 'tabs',
        prefix: _wordAttributePrefix(properties),
        namespaceUri: OfficeNamespaces.w,
      );
      properties.addChild(tabs);
    }
    XmlElement? target;
    for (final child in tabs.childElements) {
      if (child.localName != 'tab' ||
          !_wordName(child.namespaceUri, child.prefix)) {
        continue;
      }
      final position = child.attributes
          .where(
            (a) => a.localName == 'pos' && _wordName(a.namespaceUri, a.prefix),
          )
          .firstOrNull
          ?.value;
      if (int.tryParse(position ?? '') == positionTwips) {
        target = child;
        break;
      }
    }
    if (target == null) {
      target = XmlElement(
        localName: 'tab',
        prefix: _wordAttributePrefix(tabs),
        namespaceUri: OfficeNamespaces.w,
      );
      tabs.addChild(target);
    }
    target.attributes.removeWhere(
      (a) =>
          const {'pos', 'val', 'leader'}.contains(a.localName) &&
          _wordName(a.namespaceUri, a.prefix),
    );
    final prefix = _wordAttributePrefix(target);
    for (final entry in {
      'pos': '$positionTwips',
      'val': alignment,
      'leader': ?leader,
    }.entries) {
      target.attributes.add(
        XmlAttribute(
          localName: entry.key,
          value: entry.value,
          prefix: prefix,
          namespaceUri: OfficeNamespaces.w,
        ),
      );
    }
    orderChildren(properties);
  }

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
    target.namespaceUri = OfficeNamespaces.w;
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

  /// A catalog style edit owns the native value, not extension attributes.
  static void mergeStyleValue(XmlElement style, String name, String? value) {
    _mergeWordAttributes(
      style,
      name,
      const {'val'},
      {if (value != null && value.isNotEmpty) 'val': value},
    );
    if (value == null || value.isEmpty) {
      style.children.removeWhere(
        (node) =>
            node is XmlElement &&
            node.localName == name &&
            _wordName(node.namespaceUri, node.prefix) &&
            node.children.isEmpty &&
            node.attributes.every((attribute) => attribute.prefix == 'xmlns'),
      );
    }
  }

  /// Change a solid paragraph background without replacing its opaque metadata.
  /// Callers must validate the native texture and theme attributes first.
  static void mergeParagraphShading(XmlElement properties, String color) {
    final existing = properties.childElements
        .where(
          (node) =>
              node.localName == 'shd' &&
              _wordName(node.namespaceUri, node.prefix),
        )
        .firstOrNull;
    _mergeWordAttributes(properties, 'shd', const {'fill'}, {'fill': color});
    if (existing == null ||
        !existing.attributes.any(
          (attribute) =>
              attribute.localName == 'val' &&
              _wordName(attribute.namespaceUri, attribute.prefix),
        )) {
      _mergeWordAttributes(properties, 'shd', const {'val'}, {'val': 'clear'});
    }
    orderChildren(properties);
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
    _mergeWordAttributes(
      runProperties,
      'lang',
      {attribute},
      {if (language != null && language.isNotEmpty) attribute: language},
    );
    if (language == null || language.isEmpty) {
      runProperties.children.removeWhere(
        (node) =>
            node is XmlElement &&
            node.localName == 'lang' &&
            _wordName(node.namespaceUri, node.prefix) &&
            node.children.isEmpty &&
            node.attributes.every((a) => a.prefix == 'xmlns'),
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
