import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../model/wml_document.dart';

/// Owns three live settings without replacing the rest of the native part.
abstract final class WordSettingsIo {
  static ({
    bool tracking,
    bool protection,
    bool oddEven,
    bool autoHyphenation,
    bool noSpaceRaiseLower,
    WmlRestrictMode restrictMode,
    bool protectionHasPassword,
    bool protectionFormattingRestricted,
  })
  read(String xml) {
    final root = XmlDocument.parse(xml).root!;
    final compatibility = root.firstChild(
      'compat',
      namespaceUri: OfficeNamespaces.w,
    );
    return (
      tracking: _enabled(root, 'trackRevisions'),
      protection: _enabled(root, 'documentProtection'),
      oddEven: _enabled(root, 'evenAndOddHeaders'),
      autoHyphenation: _enabled(root, 'autoHyphenation'),
      noSpaceRaiseLower:
          compatibility != null && _enabled(compatibility, 'noSpaceRaiseLower'),
      restrictMode: _restrictMode(root),
      protectionHasPassword: _hasPassword(root),
      protectionFormattingRestricted: const {'1', 'true', 'on'}.contains(
        root
            .firstChild('documentProtection', namespaceUri: OfficeNamespaces.w)
            ?.getAttribute('formatting', namespaceUri: OfficeNamespaces.w)
            ?.toLowerCase(),
      ),
    );
  }

  /// Null means an absent settings part still has no settings to write.
  static String? merge(
    String? source, {
    required bool tracking,
    required bool protection,
    required bool oddEven,
    bool? autoHyphenation,
    WmlRestrictMode? restrictMode,
    List<int>? footnoteSpecialIds,
    List<int>? endnoteSpecialIds,
  }) {
    if (source == null &&
        !tracking &&
        !protection &&
        !oddEven &&
        autoHyphenation != true &&
        footnoteSpecialIds == null &&
        endnoteSpecialIds == null) {
      return null;
    }
    final document = source == null
        ? XmlDocument.parse('<w:settings xmlns:w="${OfficeNamespaces.w}"/>')
        : XmlDocument.parse(source);
    final root = document.root!;
    final prefix = _unusedPrefix(root);
    var changed = false;
    final values = {
      'trackRevisions': tracking,
      'documentProtection': protection,
      'evenAndOddHeaders': oddEven,
      'autoHyphenation': ?autoHyphenation,
    };
    for (final entry in values.entries) {
      var element = root.firstChild(
        entry.key,
        namespaceUri: OfficeNamespaces.w,
      );
      final flagChanged = _enabled(root, entry.key) != entry.value;
      final modeChanged =
          entry.key == 'documentProtection' &&
          ((element == null && protection) ||
              (restrictMode != null && _restrictMode(root) != restrictMode));
      if (!flagChanged && !modeChanged) continue;
      if (element == null) {
        element = XmlElement(
          localName: entry.key,
          prefix: prefix,
          namespaceUri: OfficeNamespaces.w,
        );
        _insert(root, element);
      }
      // Bind only the changed owned element. Rebinding the root's `w` prefix
      // could reinterpret native extension attributes that already use it.
      element.setAttribute(
        prefix,
        OfficeNamespaces.w,
        prefix: 'xmlns',
        namespaceUri: 'http://www.w3.org/2000/xmlns/',
      );
      // Preserve all other attributes, including protection hashing metadata.
      if (flagChanged) {
        element.setAttribute(
          entry.key == 'documentProtection' ? 'enforcement' : 'val',
          entry.value ? '1' : '0',
          prefix: prefix,
          namespaceUri: OfficeNamespaces.w,
        );
      }
      if (modeChanged) {
        element.setAttribute(
          'edit',
          (restrictMode ?? WmlRestrictMode.readOnly).name,
          prefix: prefix,
          namespaceUri: OfficeNamespaces.w,
        );
      }
      changed = true;
    }
    for (final (kind, ids) in [
      ('footnote', footnoteSpecialIds),
      ('endnote', endnoteSpecialIds),
    ]) {
      if (ids == null) continue;
      var properties = root.firstChild(
        '${kind}Pr',
        namespaceUri: OfficeNamespaces.w,
      );
      final existing = properties
          ?.childrenNamed(kind, namespaceUri: OfficeNamespaces.w)
          .map(
            (node) => node.getAttribute('id', namespaceUri: OfficeNamespaces.w),
          )
          .toList();
      if (existing != null &&
          existing.length == ids.length &&
          List.generate(
            ids.length,
            (index) => index,
          ).every((index) => existing[index] == '${ids[index]}')) {
        continue;
      }
      if (properties == null) {
        properties = XmlElement(
          localName: '${kind}Pr',
          prefix: prefix,
          namespaceUri: OfficeNamespaces.w,
        );
        _insert(root, properties);
      }
      properties.setAttribute(
        prefix,
        OfficeNamespaces.w,
        prefix: 'xmlns',
        namespaceUri: 'http://www.w3.org/2000/xmlns/',
      );
      properties.children.removeWhere(
        (node) =>
            node is XmlElement &&
            node.namespaceUri == OfficeNamespaces.w &&
            node.localName == kind,
      );
      for (final id in ids) {
        properties.addChild(
          XmlElement(
            localName: kind,
            prefix: prefix,
            namespaceUri: OfficeNamespaces.w,
          )..setAttribute(
            'id',
            '$id',
            prefix: prefix,
            namespaceUri: OfficeNamespaces.w,
          ),
        );
      }
      changed = true;
    }
    return !changed && source != null ? source : document.toXmlString();
  }

  static WmlRestrictMode _restrictMode(XmlElement root) {
    final node = root.firstChild(
      'documentProtection',
      namespaceUri: OfficeNamespaces.w,
    );
    if (node == null) return WmlRestrictMode.readOnly;
    final value = node.getAttribute('edit', namespaceUri: OfficeNamespaces.w);
    return switch (value) {
      null || 'none' => WmlRestrictMode.none,
      'comments' => WmlRestrictMode.comments,
      'forms' => WmlRestrictMode.forms,
      'trackedChanges' => WmlRestrictMode.trackedChanges,
      _ => WmlRestrictMode.readOnly,
    };
  }

  static bool _hasPassword(XmlElement root) {
    final node = root.firstChild(
      'documentProtection',
      namespaceUri: OfficeNamespaces.w,
    );
    if (node == null) return false;
    // ECMA password metadata plus the later Word hash/salt attribute names.
    // Fail closed on partial metadata instead of silently removing protection.
    const names = <String>{
      'password',
      'hash',
      'salt',
      'hashValue',
      'saltValue',
      'algorithmName',
      'cryptProviderType',
      'cryptAlgorithmClass',
      'cryptAlgorithmType',
      'cryptAlgorithmSid',
      'cryptSpinCount',
      'spinCount',
      'cryptProvider',
      'algIdExt',
      'algIdExtSource',
      'cryptProviderTypeExt',
      'cryptProviderTypeExtSource',
    };
    return node.attributes.any(
      (attribute) =>
          (attribute.namespaceUri == OfficeNamespaces.w ||
              attribute.namespaceUri ==
                  'http://schemas.microsoft.com/office/word/2010/wordml') &&
          names.contains(attribute.localName) &&
          attribute.value.isNotEmpty,
    );
  }

  static String _unusedPrefix(XmlElement root) {
    final used = <String>{};
    void visit(XmlElement element) {
      used.add(element.prefix);
      for (final attribute in element.attributes) {
        used.add(attribute.prefix);
        if (attribute.prefix == 'xmlns') used.add(attribute.localName);
      }
      for (final child in element.childElements) {
        visit(child);
      }
    }

    visit(root);
    var candidate = 'wordSettings';
    var suffix = 0;
    while (used.contains(candidate)) {
      candidate = 'wordSettings${++suffix}';
    }
    return candidate;
  }

  static bool _enabled(XmlElement root, String name) {
    final node = root.firstChild(name, namespaceUri: OfficeNamespaces.w);
    if (node == null) return false;
    final protection = name == 'documentProtection';
    final value = node.getAttribute(
      protection ? 'enforcement' : 'val',
      namespaceUri: OfficeNamespaces.w,
    );
    if (value == null) return !protection;
    return const {'1', 'true', 'on'}.contains(value.toLowerCase());
  }

  // CT_Settings sequence through the last element this helper can create.
  // All remaining native settings follow these entries and stay in place.
  // https://python-docx.readthedocs.io/en/latest/dev/analysis/features/settings.html
  static const _prefixOrder = [
    'writeProtection',
    'view',
    'zoom',
    'removePersonalInformation',
    'removeDateAndTime',
    'doNotDisplayPageBoundaries',
    'displayBackgroundShape',
    'printPostScriptOverText',
    'printFractionalCharacterWidth',
    'printFormsData',
    'embedTrueTypeFonts',
    'embedSystemFonts',
    'saveSubsetFonts',
    'saveFormsData',
    'mirrorMargins',
    'alignBordersAndEdges',
    'bordersDoNotSurroundHeader',
    'bordersDoNotSurroundFooter',
    'gutterAtTop',
    'hideSpellingErrors',
    'hideGrammaticalErrors',
    'activeWritingStyle',
    'proofState',
    'formsDesign',
    'attachedTemplate',
    'linkStyles',
    'stylePaneFormatFilter',
    'stylePaneSortMethod',
    'documentType',
    'mailMerge',
    'revisionView',
    'trackRevisions',
    'doNotTrackMoves',
    'doNotTrackFormatting',
    'documentProtection',
    'autoFormatOverride',
    'styleLockTheme',
    'styleLockQFSet',
    'defaultTabStop',
    'autoHyphenation',
    'consecutiveHyphenLimit',
    'hyphenationZone',
    'doNotHyphenateCaps',
    'showEnvelope',
    'summaryLength',
    'clickAndTypeStyle',
    'defaultTableStyle',
    'evenAndOddHeaders',
    'bookFoldRevPrinting',
    'bookFoldPrinting',
    'bookFoldPrintingSheets',
    'drawingGridHorizontalSpacing',
    'drawingGridVerticalSpacing',
    'displayHorizontalDrawingGridEvery',
    'displayVerticalDrawingGridEvery',
    'doNotUseMarginsForDrawingGridOrigin',
    'drawingGridHorizontalOrigin',
    'drawingGridVerticalOrigin',
    'doNotShadeFormData',
    'noPunctuationKerning',
    'characterSpacingControl',
    'printTwoOnOne',
    'strictFirstAndLastChars',
    'noLineBreaksAfter',
    'noLineBreaksBefore',
    'savePreviewPicture',
    'doNotValidateAgainstSchema',
    'saveInvalidXml',
    'ignoreMixedContent',
    'alwaysShowPlaceholderText',
    'doNotDemarcateInvalidXml',
    'saveXmlDataOnly',
    'useXSLTWhenSaving',
    'saveThroughXslt',
    'showXMLTags',
    'alwaysMergeEmptyNamespace',
    'updateFields',
    'hdrShapeDefaults',
    'footnotePr',
    'endnotePr',
  ];

  static void _insert(XmlElement root, XmlElement element) {
    final rank = _prefixOrder.indexOf(element.localName);
    final index = root.children.indexWhere((child) {
      if (child is! XmlElement) return false;
      final other = child.namespaceUri == OfficeNamespaces.w
          ? _prefixOrder.indexOf(child.localName)
          : -1;
      return other == -1 || other > rank;
    });
    element.parent = root;
    root.children.insert(index < 0 ? root.children.length : index, element);
  }
}
