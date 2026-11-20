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

  bool _load({bool includeTheme = true}) {
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
    defaults = _wordChild(root, 'docDefaults');
    // Resolve native style identities by namespace, independently of prefix.
    // Foreign lookalikes stay in the stored styles XML without entering the
    // effective cascade. All three enabled ST_OnOff spellings are equivalent.
    // An omitted native type has the WordprocessingML default, paragraph.
    for (final style
        in root?.childElements.where((element) => _word(element, 'style')) ??
            <XmlElement>[]) {
      final id = style.getAttribute(
        'styleId',
        namespaceUri: OfficeNamespaces.w,
      );
      if (id == null) continue;
      styles[id] = style;
      final type =
          style.getAttribute('type', namespaceUri: OfficeNamespaces.w) ??
          'paragraph';
      if (type == 'paragraph' &&
          const {'1', 'true', 'on'}.contains(
            style.getAttribute('default', namespaceUri: OfficeNamespaces.w),
          )) {
        defaultParagraph = id;
      }
    }
    _missingStyles = styles.isEmpty && defaults == null;
    final themeRel = rels.firstByType(RelationshipTypes.theme);
    final theme = package.getPart(
      themeRel == null ? '/word/theme/theme1.xml' : rels.resolve(themeRel),
    );
    if (includeTheme && theme != null) {
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
    return true;
  }

  bool apply() {
    if (!_load()) return false;
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
    for (final comment in document.comments) {
      walk(comment.paragraphs);
    }
    return true;
  }

  static bool _word(XmlElement element, String name) =>
      element.localName == name &&
      (element.namespaceUri == OfficeNamespaces.w ||
          (element.namespaceUri.isEmpty && element.prefix == 'w'));

  static XmlElement? _wordChild(XmlElement? parent, String name) =>
      parent?.childElements.where((child) => _word(child, name)).firstOrNull;

  static String? _tabAttribute(XmlElement element, String name) => element
      .attributes
      .where(
        (a) =>
            a.localName == name &&
            (a.namespaceUri == OfficeNamespaces.w ||
                (a.namespaceUri.isEmpty && a.prefix == 'w')),
      )
      .firstOrNull
      ?.value;

  /// Native tab layers are cumulative by position, unlike most pPr children.
  /// Keep clear and bar records here: the projection consumes them, while a
  /// subsequent custom-tab edit must also know about non-positioning bars.
  static void _mergeTabs(XmlElement target, XmlElement incoming) {
    target.setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
    for (final child in incoming.childElements) {
      if (!_word(child, 'tab')) continue;
      final raw = _tabAttribute(child, 'pos');
      final position = WordDeserializer._measureTwips(raw ?? '0');
      target.children.removeWhere(
        (old) =>
            old is XmlElement &&
            _word(old, 'tab') &&
            WordDeserializer._measureTwips(_tabAttribute(old, 'pos') ?? '0') ==
                position,
      );
      // This node is only the effective projection, never sparse source.
      // Normalize native prefixes so an inherited declaration on the source
      // pPr cannot become an unbound alias when its child is copied here.
      final effective = XmlElement(
        localName: 'tab',
        prefix: 'w',
        namespaceUri: OfficeNamespaces.w,
      );
      for (final name in ['pos', 'val', 'leader']) {
        final value = _tabAttribute(child, name);
        if (value != null) {
          effective.setAttribute(
            name,
            value,
            prefix: 'w',
            namespaceUri: OfficeNamespaces.w,
          );
        }
      }
      target.addChild(effective);
    }
  }

  List<XmlElement> _tabContainers(XmlElement properties) => properties
      .childElements
      .where((child) => _word(child, 'tabs'))
      .toList(growable: false);

  void _checkTabSource(XmlElement properties) {
    if (!_word(properties, 'pPr')) {
      throw UnsupportedError(
        'Tab operations require an unambiguous native paragraph-properties namespace.',
      );
    }
    bool containsTabs(XmlElement node) =>
        _word(node, 'tabs') ||
        _word(node, 'tab') ||
        node.childElements.any(containsTabs);
    void checkAlternatives(XmlElement node) {
      if (node.localName == 'AlternateContent' &&
          node.namespaceUri ==
              'http://schemas.openxmlformats.org/markup-compatibility/2006' &&
          containsTabs(node)) {
        throw UnsupportedError(
          'Tab operations do not edit tabs inside markup-compatibility alternatives.',
        );
      }
      for (final child in node.childElements) {
        checkAlternatives(child);
      }
    }

    checkAlternatives(properties);
    final containers = _tabContainers(properties);
    if (containers.length > 1) {
      throw UnsupportedError(
        'Tab operations require at most one direct native tabs element per formatting layer.',
      );
    }
    final positions = <int>{};
    for (final container in containers) {
      for (final tab in container.childElements.where(
        (child) => _word(child, 'tab'),
      )) {
        final raw = _tabAttribute(tab, 'pos') ?? '';
        final position = RegExp(r'^[+-]?[0-9]+$').hasMatch(raw)
            ? int.tryParse(raw)
            : null;
        if (position == null ||
            position < -2147483648 ||
            position > 2147483647) {
          throw UnsupportedError(
            'Tab operations require signed 32-bit integer twip positions in native source tabs.',
          );
        }
        if (!positions.add(position)) {
          throw UnsupportedError(
            'Tab operations cannot edit duplicate native tab positions in one formatting layer.',
          );
        }
        if (!const {
          'left',
          'center',
          'right',
          'decimal',
          'bar',
          'clear',
          'num',
          'start',
          'end',
        }.contains(_tabAttribute(tab, 'val'))) {
          throw UnsupportedError(
            'Tab operations require a recognized native tab alignment.',
          );
        }
      }
    }
  }

  void _checkPackageTabAlternatives() {
    // The main-story reader selects MC branches before capturing sparse pPr.
    // Inspect original Word XML as well, including wrappers around a pPr or
    // an entire applicable style. Refuse conservatively at document scope:
    // native tab writes cannot keep all alternative branches synchronized.
    for (final part in document.package?.parts ?? <PackagePart>[]) {
      final type = part.contentType;
      if (!type.endsWith('+xml') ||
          (!type.contains('wordprocessingml') &&
              !type.contains('vnd.ms-word'))) {
        continue;
      }
      final source = part.readText();
      if (!source.contains('AlternateContent')) continue;
      final input = XmlPullReader(source);
      final alternatives = <int>[];
      final tabContainers = <int>[];
      while (input.next()) {
        if (input.eventType == XmlEventType.startElement) {
          if (input.namespaceUri == OfficeNamespaces.w &&
              input.localName == 'tabs') {
            tabContainers.add(input.depth);
          }
          if (input.namespaceUri == OfficeNamespaces.mc &&
              input.localName == 'AlternateContent') {
            alternatives.add(input.depth);
          } else if (alternatives.isNotEmpty &&
              input.namespaceUri == OfficeNamespaces.w &&
              (input.localName == 'tabs' ||
                  (input.localName == 'tab' && tabContainers.isNotEmpty))) {
            throw UnsupportedError(
              'Tab operations do not edit documents with tabs inside markup-compatibility alternatives.',
            );
          }
        } else if (input.eventType == XmlEventType.endElement) {
          if (alternatives.isNotEmpty && input.depth < alternatives.last) {
            alternatives.removeLast();
          }
          if (tabContainers.isNotEmpty && input.depth < tabContainers.last) {
            tabContainers.removeLast();
          }
        }
      }
    }
  }

  void editParagraphTabStops(
    WmlParagraph target,
    WmlTabStop? tab, {
    List<WmlTabStop>? replacement,
    WmlParagraphProps? properties,
  }) {
    if (tab != null && replacement != null) {
      throw ArgumentError('Use either one tab or a replacement collection.');
    }
    if (tab != null) {
      final twips = tab.position * 20;
      if (!tab.position.isFinite ||
          tab.position.abs() > 1584 ||
          twips.round() / 20 != tab.position) {
        throw ArgumentError(
          'Tab position must be within -1584..1584 points in exact 0.05-point increments.',
        );
      }
    }
    if (replacement != null &&
        replacement.any(
          (stop) => !stop.position.isFinite || stop.position < 0,
        )) {
      throw ArgumentError(
        'Replacement tab positions must be finite and nonnegative.',
      );
    }
    _checkPackageTabAlternatives();
    _load(includeTheme: false);
    List<XmlElement>? tableLayers;
    var occurrences = 0;
    void locate(
      Iterable<WmlBlock> blocks, [
      List<XmlElement> inherited = const [],
    ]) {
      for (final block in blocks) {
        if (identical(block, target)) {
          tableLayers = inherited;
          occurrences++;
        }
        if (block is WmlTable) {
          for (var row = 0; row < block.rows.length; row++) {
            final layers = _tableCellLayers(block, row);
            for (final cell in block.rows[row].cells) {
              locate(cell.blocks, layers);
            }
          }
        } else {
          for (final children in WordTree.childLists(block)) {
            locate(children, inherited);
          }
        }
      }
    }

    for (final section in document.sections) {
      locate(section.blocks);
      for (final story in [
        section.header,
        section.footer,
        section.firstHeader,
        section.firstFooter,
        section.evenHeader,
        section.evenFooter,
      ]) {
        locate(story);
      }
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      locate(note.blocks);
    }
    for (final comment in document.comments) {
      locate(comment.paragraphs);
    }
    if (occurrences != 1) {
      throw StateError('The paragraph must have one current document owner.');
    }
    final props = (properties ?? target.properties).copy();
    // Commit pending non-tab edits into the detached direct fragment before
    // changing tab ownership. No effective inherited values are copied here.
    final direct = WordPropertyIo.parse(
      WordSerializer().paragraphPropertiesXml(props),
      'pPr',
    );
    final layers = <XmlElement?>[
      _wordChild(_wordChild(defaults, 'pPrDefault'), 'pPr'),
      for (final t in tableLayers!) _wordChild(t, 'pPr'),
      for (final s in chain(props.styleId ?? defaultParagraph))
        _wordChild(s, 'pPr'),
      direct,
    ];
    for (final layer in layers.whereType<XmlElement>()) {
      _checkTabSource(layer);
    }
    if (tab == null) {
      final effective = merged('pPr', layers);
      for (final container in _tabContainers(effective)) {
        for (final stop in container.childElements.where(
          (child) => _word(child, 'tab'),
        )) {
          if (_tabAttribute(stop, 'val') == 'clear') continue;
          WordPropertyIo.writeTabStop(
            direct,
            int.parse(_tabAttribute(stop, 'pos')!),
            'clear',
          );
        }
      }
    }
    for (final stop in replacement ?? [?tab]) {
      WordPropertyIo.writeTabStop(
        direct,
        pointsToTwips(stop.position),
        stop.alignment.name,
        // Explicit none also overrides an inherited leader at this position.
        leader: stop.leader.name,
      );
    }
    final effective = merged('pPr', layers);
    props.tabs.clear();
    for (final container in _tabContainers(effective)) {
      reader._readTabs(
        XmlPullReader(
          XmlDocument(root: container).toXmlString(declaration: false),
        )..next(),
        props,
      );
    }
    props.sourcePropertiesXml = XmlDocument(
      root: direct,
    ).toXmlString(declaration: false);
    props.importedValues = WordPropertyIo.paragraphValues(props);
    target.properties = props;
  }

  bool clearRunProofingLanguage(
    WmlParagraph source,
    WmlParagraph preview,
    int start,
    int end, {
    bool includeComplexScript = false,
    bool activeLanguageOnly = false,
  }) {
    if (identical(source, preview) || source.text != preview.text) {
      throw ArgumentError('Use a detached preview with the source text.');
    }
    if (start < 0 || end < start || end > preview.text.length) {
      throw RangeError('The proofing range must be within the preview text.');
    }
    _load(includeTheme: false);
    List<XmlElement>? tableLayers;
    var occurrences = 0;
    void locate(
      Iterable<WmlBlock> blocks, [
      List<XmlElement> inherited = const [],
    ]) {
      for (final block in blocks) {
        if (identical(block, preview)) {
          throw ArgumentError('The preview must not belong to the document.');
        }
        if (identical(block, source)) {
          tableLayers = inherited;
          occurrences++;
        }
        if (block is WmlTable) {
          for (var row = 0; row < block.rows.length; row++) {
            final layers = _tableCellLayers(block, row);
            for (final cell in block.rows[row].cells) {
              locate(cell.blocks, layers);
            }
          }
        } else {
          for (final children in WordTree.childLists(block)) {
            locate(children, inherited);
          }
        }
      }
    }

    for (final section in document.sections) {
      locate(section.blocks);
      for (final story in [
        section.header,
        section.footer,
        section.firstHeader,
        section.firstFooter,
        section.evenHeader,
        section.evenFooter,
      ]) {
        locate(story);
      }
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      locate(note.blocks);
    }
    for (final comment in document.comments) {
      locate(comment.paragraphs);
    }
    if (occurrences != 1) {
      throw StateError('The source must have one current document owner.');
    }
    if (start == end) return false;
    final paragraphStyles = chain(
      source.properties.styleId ?? defaultParagraph,
    );
    // Also isolate callers that supplied a shallow preview. Publish the
    // prepared inline list only after every selected run has been resolved.
    final prepared = WmlClone.paragraph(preview);
    final range = WmlRunEdit.normalizeRange(prepared, start, end);
    final routingChanged = WmlRunEdit.splitProofingRange(
      prepared,
      range.start,
      range.end,
    );
    final latinProperties = {
      for (final run in prepared.inlines.whereType<WmlRun>())
        if (wordRunUsesLatinScriptLanguage(run)) run.properties,
    };
    final complexProperties = {
      for (final run in prepared.inlines.whereType<WmlRun>())
        if (wordRunUsesComplexScriptLanguage(run)) run.properties,
    };
    var changed = activeLanguageOnly && routingChanged;
    WmlRunEdit.applyRange(prepared, range.start, range.end, (props) {
      final attributes = activeLanguageOnly
          ? [
              if (latinProperties.contains(props)) 'val',
              if (complexProperties.contains(props)) 'bidi',
            ]
          : ['val', if (includeComplexScript) 'bidi'];
      final inheritedLanguage = merged('rPr', [
        for (final layer in tableLayers!) layer.firstChild('rPr'),
        for (final style in paragraphStyles) style.firstChild('rPr'),
        for (final style in chain(props.styleId)) style.firstChild('rPr'),
      ]).firstChild('lang');
      final imported = props.importedValues;
      final hasSparseSource =
          imported != null && props.sourcePropertiesXml != null;
      final direct = _proofingRunProperties(
        hasSparseSource
            ? props.sourcePropertiesXml!
            : WordSerializer().runPropertiesXml(props),
      );
      final updated = <String, String>{};
      for (final attribute in attributes) {
        final complex = attribute == 'bidi';
        final key = complex ? 'lang:bidi' : 'lang';
        final current = complex
            ? props.complexScriptLanguage
            : props.proofingLanguage;
        final inherited = inheritedLanguage?.getAttribute(attribute);
        final directLanguage = direct
            .firstChild('lang', namespaceUri: OfficeNamespaces.w)
            ?.getAttribute(attribute, namespaceUri: OfficeNamespaces.w);
        final pendingOverride = hasSparseSource && imported[key] != '$current';
        if (directLanguage == null &&
            !pendingOverride &&
            current == inherited) {
          continue;
        }
        WordPropertyIo.mergeLanguage(direct, null, attribute: attribute);
        if (complex) {
          props.complexScriptLanguage = inherited;
        } else {
          props.proofingLanguage = inherited;
        }
        updated[key] = '$inherited';
      }
      if (updated.isEmpty) return;
      props.sourcePropertiesXml = XmlDocument(
        root: direct,
      ).toXmlString(declaration: false);
      props.importedValues = hasSparseSource
          ? {...imported, ...updated}
          : WordPropertyIo.runValues(props);
      if (direct.firstChild('lang', namespaceUri: OfficeNamespaces.w) == null) {
        props.explicitProperties.remove('lang');
      }
      changed = true;
    });
    if (changed) preview.inlines = prepared.inlines;
    return changed;
  }

  XmlElement _proofingRunProperties(String xml) {
    // Newly authored runPropertiesXml is a fragment with an inherited `w`
    // prefix. Give that fragment its native context before matching @w:val.
    final wrapper = XmlDocument.parse(
      '<w:proofingContext xmlns:w="${OfficeNamespaces.w}">$xml</w:proofingContext>',
    ).root!;
    final properties = xml.isEmpty
        ? XmlElement(
            localName: 'rPr',
            prefix: 'w',
            namespaceUri: OfficeNamespaces.w,
          )
        : wrapper.firstChild('rPr', namespaceUri: OfficeNamespaces.w);
    if (properties == null) {
      throw const FormatException('Invalid direct run properties.');
    }
    return properties..setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
  }

  List<XmlElement> _tableCellLayers(WmlTable table, int row) {
    final layers = chain(table.properties.styleId);
    final source = WordPropertyIo.parse(
      table.properties.sourcePropertiesXml,
      'tblPr',
    );
    final lookElement = source.firstChild(
      'tblLook',
      namespaceUri: OfficeNamespaces.w,
    );
    final look = lookElement == null
        ? reader._tableLooks[table] ?? const _TableLook()
        : _TableLook.element(lookElement);
    final conditional = <String>{
      'wholeTable',
      if (look.bandedRows) row.isEven ? 'band1Horz' : 'band2Horz',
      if (row == 0 && look.firstRow) 'firstRow',
    };
    return <XmlElement>[
      if (layers.isEmpty) XmlElement(localName: 'tableDefaults'),
      ...layers,
      for (final style in layers)
        for (final region in style.childElements.where(
          (element) => _word(element, 'tblStylePr'),
        ))
          if (conditional.contains(
            region.getAttribute('type', namespaceUri: OfficeNamespaces.w),
          ))
            region,
    ];
  }

  List<XmlElement> chain(String? id, [Set<String>? seen]) {
    if (id == null || !styles.containsKey(id)) return [];
    seen ??= {};
    if (!seen.add(id)) return []; // Invalid cyclic input must terminate.
    final style = styles[id]!;
    return [
      ...chain(
        _wordChild(
          style,
          'basedOn',
        )?.getAttribute('val', namespaceUri: OfficeNamespaces.w),
        seen,
      ),
      style,
    ];
  }

  static XmlElement _numberingProjection(XmlElement source) {
    final projection = source.copy();
    final bindings = <String, String>{};
    for (XmlElement? node = source; node != null; node = node.parent) {
      for (final attribute in node.attributes) {
        if (attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns') {
          bindings.putIfAbsent(attribute.qualifiedName, () => attribute.value);
        }
      }
    }
    // Moving numPr under the effective pPr must retain the namespace context
    // of its IDs and levels. Their native prefix need not be the literal w.
    for (final entry in bindings.entries) {
      if (projection.attributes.any((a) => a.qualifiedName == entry.key)) {
        continue;
      }
      final prefixed = entry.key.startsWith('xmlns:');
      projection.attributes.add(
        XmlAttribute(
          localName: prefixed ? entry.key.substring(6) : 'xmlns',
          prefix: prefixed ? 'xmlns' : '',
          namespaceUri: 'http://www.w3.org/2000/xmlns/',
          value: entry.value,
        ),
      );
    }
    return projection;
  }

  static XmlElement _layoutAttributeProjection(XmlElement source) {
    // Only effective indentation/spacing attributes are projected here. Source
    // prefixes on copied attributes can become unbound, or a later layer rebinds
    // an earlier layer's prefix. Normalize native attributes in this detached
    // projection; the full direct/style XML retains all extension metadata.
    final result =
        XmlElement(
            localName: source.localName,
            prefix: 'w',
            namespaceUri: OfficeNamespaces.w,
          )
          ..attributes.add(
            XmlAttribute(
              localName: 'w',
              prefix: 'xmlns',
              namespaceUri: 'http://www.w3.org/2000/xmlns/',
              value: OfficeNamespaces.w,
            ),
          );
    for (final attribute in source.attributes) {
      if (attribute.namespaceUri == OfficeNamespaces.w ||
          (attribute.namespaceUri.isEmpty && attribute.prefix == 'w')) {
        result.attributes.add(
          XmlAttribute(
            localName: attribute.localName,
            prefix: 'w',
            namespaceUri: OfficeNamespaces.w,
            value: attribute.value,
          ),
        );
      }
    }
    return result;
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
      for (final incoming in layer.childElements) {
        final child = name == 'pPr' && _word(incoming, 'numPr')
            ? _numberingProjection(incoming)
            : name == 'pPr' &&
                  (_word(incoming, 'ind') || _word(incoming, 'spacing'))
            ? _layoutAttributeProjection(incoming)
            : incoming;
        if (name == 'pPr' &&
            (child.localName == 'spacing' ||
                child.localName == 'bidi' ||
                child.localName == 'ind' ||
                child.localName == 'tabs') &&
            child.namespaceUri != OfficeNamespaces.w &&
            !(child.namespaceUri.isEmpty && child.prefix == 'w')) {
          // Do not merge opaque same-name extensions into an effective Word
          // property. Their original XML remains in the source style/layer.
          continue;
        }
        if (child.localName == 'sectPr') continue;
        final old = result.firstChild(child.localName);
        if (name == 'pPr' && child.localName == 'tabs') {
          final effective = old ?? WordPropertyIo.parse('', 'tabs');
          _mergeTabs(effective, child);
          if (old == null) result.addChild(effective);
          continue;
        }
        if (name == 'rPr' &&
            const {'noProof', 'rtl', 'cs'}.contains(child.localName)) {
          // An omitted on/off value enables these properties. Do not retain
          // a lower layer's explicit false for a direct empty marker.
          final effective = old ?? child.copy();
          effective.setAttribute(
            'val',
            child.getAttribute('val') ?? '1',
            prefix: 'w',
          );
          if (old == null) result.addChild(effective);
          continue;
        }
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
      // Word applies themeShade/themeTint to the HSL luminance (accent
      // #4F81BD with shade BF gives Word's #365F91), not per RGB channel.
      if (shade != null || tint != null) {
        rgb = adjustThemeLuminance(rgb, shade: shade, tint: tint);
      }
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
    // A fresh import can already contain native numId=0. Its source XML owns
    // extension metadata that a full generated pPr cannot reproduce. Only
    // materialize a new suppression when there is no direct source to retain.
    final authoredSuppression =
        p.properties.numberingSuppressed &&
        (p.properties.sourcePropertiesXml?.isEmpty ?? true);
    if (previouslyImported || authoredSuppression) {
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
      _wordChild(_wordChild(defaults, 'pPrDefault'), 'pPr'),
      for (final t in tableLayers) _wordChild(t, 'pPr'),
      for (final s in paragraphChain) _wordChild(s, 'pPr'),
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
      fieldSeparate: old.fieldSeparate,
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
    final markerStyles = [for (final s in paragraphChain) s.firstChild('rPr')];
    final markerXml = merged('rPr', [
      defaults?.firstChild('rPrDefault')?.firstChild('rPr'),
      for (final t in tableLayers) t.firstChild('rPr'),
      ...markerStyles,
      pp.firstChild('rPr'),
    ], toggleLayers: markerStyles.whereType<XmlElement>().toSet());
    if (markerXml.childElements.isNotEmpty) {
      final marker = WmlRunProps(kerningHalfPoints: _missingStyles ? 1 : null);
      reader._parseRPr(
        XmlPullReader(
          XmlDocument(root: markerXml).toXmlString(declaration: false),
        )..next(),
        marker,
      );
      p.properties.importedParagraphMark = marker;
    }
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
      final resolved = WmlRunProps(
        kerningHalfPoints: _missingStyles ? 1 : null,
      );
      final inner = XmlPullReader(
        XmlDocument(root: rp).toXmlString(declaration: false),
      )..next();
      reader._parseRPr(inner, resolved);
      // The document default remains live: changing it must affect runs that
      // do not override it without stamping direct formatting onto every run.
      final inheritedLanguage = merged('rPr', [
        for (final t in tableLayers) t.firstChild('rPr'),
        ...styleRuns,
        direct,
      ]).firstChild('lang');
      resolved.proofingLanguage = inheritedLanguage?.getAttribute('val');
      resolved.complexScriptLanguage = inheritedLanguage?.getAttribute('bidi');
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
        for (int row = 0; row < block.rows.length; row++) {
          final cellLayers = _tableCellLayers(block, row);
          for (int col = 0; col < block.rows[row].cells.length; col++) {
            walk(block.rows[row].cells[col].blocks, cellLayers);
          }
        }
      }
    }
  }
}

/// Word's themeShade / themeTint: scales the HSL luminance (shade) or moves
/// it toward white (tint); 255 = unchanged.
int adjustThemeLuminance(int rgb, {int? shade, int? tint}) {
  final r = ((rgb >> 16) & 255) / 255;
  final g = ((rgb >> 8) & 255) / 255;
  final b = (rgb & 255) / 255;
  final max = [r, g, b].reduce((x, y) => x > y ? x : y);
  final min = [r, g, b].reduce((x, y) => x < y ? x : y);
  var l = (max + min) / 2;
  final d = max - min;
  final s = d == 0 ? 0.0 : d / (1 - (2 * l - 1).abs());
  double h;
  if (d == 0) {
    h = 0;
  } else if (max == r) {
    h = 60 * (((g - b) / d) % 6);
  } else if (max == g) {
    h = 60 * ((b - r) / d + 2);
  } else {
    h = 60 * ((r - g) / d + 4);
  }
  if (shade != null) l = l * shade / 255;
  if (tint != null) l = l * tint / 255 + (1 - tint / 255);
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = l - c / 2;
  final (double, double, double) rgb1 = h < 60
      ? (c, x, 0)
      : h < 120
      ? (x, c, 0)
      : h < 180
      ? (0, c, x)
      : h < 240
      ? (0, x, c)
      : h < 300
      ? (x, 0, c)
      : (c, 0, x);
  // Word truncates when converting back to 0-255 (4F81BD shade BF → 365F91).
  int ch(double v) => ((v + m) * 255 + 1e-6).floor().clamp(0, 255);
  return (ch(rgb1.$1) << 16) | (ch(rgb1.$2) << 8) | ch(rgb1.$3);
}
