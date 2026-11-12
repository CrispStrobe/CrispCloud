part of 'word_deserializer.dart';

/// Resolve only declared properties, from defaults through table/paragraph/
/// character styles to direct formatting. Missing values never reset a parent.
class _StyleCascade {
  _StyleCascade(this.reader, this.document);
  final WordDeserializer reader;
  final WmlDocument document;
  final Map<String, XmlElement> styles = {};
  final Map<String, String> colors = {};
  final Map<String, String> fonts = {};
  XmlElement? defaults;
  String? defaultParagraph;
  bool _missingStyles = false;

  bool apply() {
    final package = document.package;
    if (package == null) return false;
    final office = package.packageRelationships.firstByType(
      RelationshipTypes.officeDocument,
    );
    final uri = office == null
        ? '/word/document.xml'
        : package.packageRelationships.resolve(office);
    final rels = package.relationshipsFor(uri);
    final rel = rels.firstByType(RelationshipTypes.styles);
    final part = package.getPart(
      rel == null ? '/word/styles.xml' : rels.resolve(rel),
    );
    _missingStyles = part == null;
    final root = part == null ? null : XmlDocument.parse(part.readText()).root;
    defaults = root?.firstChild('docDefaults');
    for (final style in root?.childrenNamed('style') ?? <XmlElement>[]) {
      final id = style.getAttribute('styleId');
      if (id == null) continue;
      styles[id] = style;
      if (style.getAttribute('type') == 'paragraph' &&
          style.getAttribute('default') == '1') {
        defaultParagraph = id;
      }
    }
    _missingStyles = styles.isEmpty && defaults == null;
    final themeRel = rels.firstByType(RelationshipTypes.theme);
    final theme = package.getPart(
      themeRel == null ? '/word/theme/theme1.xml' : rels.resolve(themeRel),
    );
    if (theme != null) {
      final t = XmlDocument.parse(theme.readText()).root!;
      final elements = t.firstChild('themeElements');
      for (final color
          in elements?.firstChild('clrScheme')?.childElements ??
              <XmlElement>[]) {
        final value = color.childElements.firstOrNull;
        if (value != null) {
          colors[color.localName] = value.getAttribute('val') == 'windowText'
              ? '000000'
              : value.getAttribute('lastClr') ??
                    value.getAttribute('val') ??
                    '000000';
        }
      }
      colors.addAll({
        'text1': colors['dk1'] ?? '000000',
        'text2': colors['dk2'] ?? '000000',
        'background1': colors['lt1'] ?? 'FFFFFF',
        'background2': colors['lt2'] ?? 'FFFFFF',
      });
      for (final group
          in elements?.firstChild('fontScheme')?.childElements ??
              <XmlElement>[]) {
        final prefix = group.localName == 'majorFont' ? 'major' : 'minor';
        for (final script in group.childElements) {
          final typeface = script.getAttribute('typeface');
          if (typeface == null || typeface.isEmpty) continue;
          if (script.localName == 'latin') {
            fonts['${prefix}Ascii'] = typeface;
            fonts['${prefix}HAnsi'] = typeface;
          }
          if (script.localName == 'cs') fonts['${prefix}Bidi'] = typeface;
          if (script.localName == 'ea') fonts['${prefix}EastAsia'] = typeface;
        }
      }
    }
    for (final section in document.sections) {
      walk(section.blocks);
      for (final story in [
        section.header,
        section.footer,
        section.firstHeader,
        section.firstFooter,
        section.evenHeader,
        section.evenFooter,
      ]) {
        walk(story);
      }
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      walk(note.blocks);
    }
    return true;
  }

  List<XmlElement> chain(String? id, [Set<String>? seen]) {
    if (id == null || !styles.containsKey(id)) return [];
    seen ??= {};
    if (!seen.add(id)) return []; // Invalid cyclic input must terminate.
    final style = styles[id]!;
    return [
      ...chain(style.firstChild('basedOn')?.getAttribute('val'), seen),
      style,
    ];
  }

  XmlElement merged(
    String name,
    Iterable<XmlElement?> layers, {
    Set<XmlElement> toggleLayers = const {},
  }) {
    final result = WordPropertyIo.parse('', name)
      ..setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
    for (final layer in layers) {
      if (layer == null) continue;
      for (final child in layer.childElements) {
        if (child.localName == 'sectPr') continue;
        final old = result.firstChild(child.localName);
        if (name == 'rPr' &&
            const {
              'b',
              'bCs',
              'i',
              'iCs',
              'strike',
              'caps',
              'smallCaps',
              'emboss',
              'imprint',
              'outline',
              'shadow',
              'vanish',
            }.contains(child.localName)) {
          bool enabled(XmlElement? element) =>
              element != null &&
              !const [
                '0',
                'false',
                'off',
              ].contains(element.getAttribute('val'));
          final on = enabled(child);
          if (toggleLayers.contains(layer) && !on) continue;
          final value = toggleLayers.contains(layer) ? !enabled(old) : on;
          final effective = old ?? child.copy();
          effective.setAttribute('val', value ? '1' : '0', prefix: 'w');
          if (old == null) result.addChild(effective);
          continue;
        }
        if (old == null) {
          result.addChild(child.copy());
          continue;
        }
        if (child.localName == 'color' &&
            child.getAttribute('val') != null &&
            child.getAttribute('themeColor') == null) {
          for (final key in ['themeColor', 'themeShade', 'themeTint']) {
            old.removeAttribute(key);
          }
        }
        if (child.localName == 'rFonts') {
          for (final pair in {
            'ascii': 'asciiTheme',
            'hAnsi': 'hAnsiTheme',
            'cs': 'cstheme',
            'eastAsia': 'eastAsiaTheme',
          }.entries) {
            if (child.getAttribute(pair.key) != null &&
                child.getAttribute(pair.value) == null) {
              old.removeAttribute(pair.value);
            }
          }
        }
        for (final a in child.attributes) {
          old.setAttribute(
            a.localName,
            a.value,
            prefix: a.prefix,
            namespaceUri: a.namespaceUri,
          );
        }
        if (child.children.isNotEmpty) {
          old.children
            ..clear()
            ..addAll(child.children.map((n) => n.copy()));
        }
      }
    }
    final color = result.firstChild('color');
    final themeColor = color?.getAttribute('themeColor');
    if (themeColor != null && colors.containsKey(themeColor)) {
      var rgb = int.tryParse(colors[themeColor]!, radix: 16) ?? 0;
      final shade = int.tryParse(
        color!.getAttribute('themeShade') ?? '',
        radix: 16,
      );
      final tint = int.tryParse(
        color.getAttribute('themeTint') ?? '',
        radix: 16,
      );
      int channel(int c) =>
          (shade != null
                  ? c * shade / 255
                  : tint != null
                  ? 255 - (255 - c) * tint / 255
                  : c)
              .round()
              .clamp(0, 255);
      rgb =
          (channel((rgb >> 16) & 255) << 16) |
          (channel((rgb >> 8) & 255) << 8) |
          channel(rgb & 255);
      color.setAttribute(
        'val',
        rgb.toRadixString(16).padLeft(6, '0').toUpperCase(),
        prefix: 'w',
      );
    }
    final rf = result.firstChild('rFonts');
    for (final entry in {
      'ascii': 'asciiTheme',
      'hAnsi': 'hAnsiTheme',
      'cs': 'cstheme',
      'eastAsia': 'eastAsiaTheme',
    }.entries) {
      final font = fonts[rf?.getAttribute(entry.value)];
      if (font != null) rf!.setAttribute(entry.key, font, prefix: 'w');
    }
    return result;
  }

  void paragraph(WmlParagraph p, List<XmlElement> tableLayers) {
    final bool previouslyImported = p.properties.importedValues != null;
    if (p.properties.importedValues != null ||
        p.properties.numberingSuppressed) {
      p.properties.sourcePropertiesXml = WordSerializer()
          .paragraphPropertiesXml(p.properties);
    }
    if (_missingStyles) {
      // Missing style parts are legal. Retain the absence of direct XML rather
      // than serializing the editor's new-document defaults onto this import.
      // Keep the established built-in fallback for an explicit style reference.
      if (!previouslyImported && p.properties.styleId == null) {
        if (!p.properties.explicitSpacingAfter) p.properties.spacingAfter = 0;
        if (!p.properties.explicitLineSpacing) p.properties.lineSpacing = 1;
      }
      for (final run in p.inlines.whereType<WmlRun>()) {
        if (run.properties.importedValues != null) {
          run.properties.sourcePropertiesXml = WordSerializer()
              .runPropertiesXml(run.properties);
        }
      }
      WordStyles.resolveOntoParagraph(
        p,
        document: document,
        notBold: reader._notBold,
        notItalic: reader._notItalic,
      );
      p.properties.sourcePropertiesXml ??= '';
      p.properties.importedValues = WordPropertyIo.paragraphValues(
        p.properties,
      );
      for (final run in p.inlines.whereType<WmlRun>()) {
        run.properties.sourcePropertiesXml ??= '';
        run.properties.importedValues = WordPropertyIo.runValues(
          run.properties,
        );
      }
      return;
    }
    final direct = WordPropertyIo.parse(
      p.properties.sourcePropertiesXml,
      'pPr',
    );
    final id = p.properties.styleId ?? defaultParagraph;
    final paragraphChain = chain(id);
    final pp = merged('pPr', [
      defaults?.firstChild('pPrDefault')?.firstChild('pPr'),
      for (final t in tableLayers) t.firstChild('pPr'),
      for (final s in paragraphChain) s.firstChild('pPr'),
      direct,
    ]);
    // Preserve non-formatting paragraph metadata (fields, notes, bookmarks).
    final source = p.properties.sourcePropertiesXml;
    final old = p.properties;
    p.properties = WmlParagraphProps(
      // Native defaults apply when no imported layer declares spacing. The
      // editor's new-paragraph defaults (8 pt / 1.15 lines) must not appear
      // merely because an unrelated heading caused a styles part to be added.
      spacingAfter: 0,
      lineSpacing: 1,
      styleId: old.styleId,
      fieldInstruction: old.fieldInstruction,
      fieldBegin: old.fieldBegin,
      fieldEnd: old.fieldEnd,
      pageNumberField: old.pageNumberField,
      bookmarkName: old.bookmarkName,
      sourceBookmarkName: old.sourceBookmarkName,
      noteId: old.noteId,
      endnoteRef: old.endnoteRef,
      listLabel: old.listLabel,
      listRestart: old.listRestart,
      columnBreakBefore: old.columnBreakBefore,
    );
    reader._parsePPr(
      XmlPullReader(XmlDocument(root: pp).toXmlString(declaration: false))
        ..next(),
      p.properties,
    );
    if (tableLayers.isNotEmpty) {
      if (pp.firstChild('spacing')?.getAttribute('after') == null) {
        p.properties.spacingAfter = old.spacingAfter;
      }
      if (pp.firstChild('spacing')?.getAttribute('line') == null) {
        p.properties.lineSpacing = old.lineSpacing;
      }
    }
    p.properties.sourcePropertiesXml = source ?? '';
    p.properties.importedValues = WordPropertyIo.paragraphValues(p.properties);
    for (final run in p.inlines.whereType<WmlRun>()) {
      final props = run.properties;
      if (props.importedValues != null) {
        props.sourcePropertiesXml = WordSerializer().runPropertiesXml(props);
      }
      final direct = WordPropertyIo.parse(props.sourcePropertiesXml, 'rPr');
      final styleRuns = [
        for (final s in paragraphChain) s.firstChild('rPr'),
        for (final s in chain(props.styleId)) s.firstChild('rPr'),
      ];
      final rp = merged('rPr', [
        defaults?.firstChild('rPrDefault')?.firstChild('rPr'),
        for (final t in tableLayers) t.firstChild('rPr'),
        ...styleRuns,
        direct,
      ], toggleLayers: styleRuns.whereType<XmlElement>().toSet());
      final resolved = WmlRunProps();
      final inner = XmlPullReader(
        XmlDocument(root: rp).toXmlString(declaration: false),
      )..next();
      reader._parseRPr(inner, resolved);
      if (run.hyperlink != null) {
        if (rp.firstChild('color') == null) resolved.color = WordLink.color;
        if (rp.firstChild('u') == null) {
          resolved.underline = WmlUnderline.single;
        }
      }
      if (run.noteRefId != null) resolved.vertAlign = WmlVertAlign.superscript;
      resolved.styleId = props.styleId;
      resolved.sourcePropertiesXml = props.sourcePropertiesXml ?? '';
      resolved.explicitProperties
        ..clear()
        ..addAll(props.explicitProperties);
      resolved.importedValues = WordPropertyIo.runValues(resolved);
      run.properties = resolved;
    }
  }

  void walk(
    Iterable<WmlBlock> blocks, [
    List<XmlElement> tableLayers = const [],
  ]) {
    for (final block in blocks) {
      if (block is WmlParagraph) {
        paragraph(block, tableLayers);
      } else if (block is WmlContentControlBlock) {
        walk(block.blocks, tableLayers);
      } else if (block is WmlFrame) {
        walk(block.blocks, tableLayers);
      } else if (block is WmlTable) {
        final layers = chain(block.properties.styleId);
        final look = reader._tableLooks[block] ?? const _TableLook();
        for (int row = 0; row < block.rows.length; row++) {
          for (int col = 0; col < block.rows[row].cells.length; col++) {
            final conditional = <String>{
              'wholeTable',
              if (look.bandedRows) row.isEven ? 'band1Horz' : 'band2Horz',
              if (row == 0 && look.firstRow) 'firstRow',
            };
            final cellLayers = <XmlElement>[
              if (layers.isEmpty) XmlElement(localName: 'tableDefaults'),
              ...layers,
            ];
            for (final style in layers) {
              for (final region in style.childrenNamed('tblStylePr')) {
                if (conditional.contains(region.getAttribute('type'))) {
                  cellLayers.add(region);
                }
              }
            }
            walk(block.rows[row].cells[col].blocks, cellLayers);
          }
        }
      }
    }
  }
}
