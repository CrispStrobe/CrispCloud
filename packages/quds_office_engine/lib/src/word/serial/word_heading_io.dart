import '../../opc/content_types.dart';
import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../model/wml_document.dart';
import '../model/word_link.dart';
import '../model/word_toc.dart';
import '../properties/wml_properties.dart';
import 'word_deserializer.dart';
import 'word_property_io.dart';
import 'word_serializer.dart';

/// Applies a built-in heading the way Word does.
///
/// * The document's own "heading N" style is used (found by its built-in
///   name, so localized style IDs work). If the package does not define it,
///   Word's built-in definition is added — the one Word itself inserts for
///   the document's theme: Office 2023 themes get the Word 365 look (Aptos
///   Display 20/16/14 pt, 18/4 · 8/4 pt spacing), older themes the Word
///   2013–2022 look (16/13/12 pt, 12/2/2 pt before, nothing after), both in
///   the theme's major font and a shade of its accent 1 colour.
/// * Direct paragraph formatting is removed and direct character formatting
///   that covers more than half of the paragraph is removed from its runs.
/// * Effective values are then resolved by the import-time style cascade, so
///   line spacing, theme fonts and colours match an imported heading exactly.
///
/// Documents without a package fall back to [WordToc.applyHeading].
abstract final class WordHeadingIo {
  static const _resetRunProperties = <String>{
    'rFonts', 'b', 'bCs', 'i', 'iCs', 'caps', 'smallCaps', 'strike',
    'dstrike', 'color', 'spacing', 'w', 'kern', 'position', 'sz', 'szCs',
    'highlight', 'u', 'shd', 'vertAlign',
  };

  static void apply(WmlDocument document, WmlParagraph paragraph, int level) {
    final OpcPackage? package = document.package;
    final int clamped = level.clamp(0, 9);
    if (package == null) {
      WordToc.applyHeading(paragraph, clamped);
      return;
    }
    final String mainUri = _mainUri(package);
    final XmlElement styles = _stylesRoot(package, mainUri);
    final String id = clamped == 0
        ? (_styleId(styles, 'normal') ?? _defaultParagraphId(styles) ?? 'Normal')
        : (_styleId(styles, 'heading $clamped') ??
              _addBuiltinHeading(styles, package, mainUri, clamped));
    _writeStyles(package, mainUri, styles);

    // Direct paragraph formatting: only the style reference remains.
    paragraph.properties
      ..styleId = id
      ..sourcePropertiesXml =
          '<w:pPr xmlns:w="${OfficeNamespaces.w}"><w:pStyle w:val="$id"/></w:pPr>'
      ..importedValues = null;
    _resetMajorityRunFormatting(paragraph);
    WordDeserializer().refreshStyles(document);
    if (clamped > 0) {
      paragraph.properties.bookmarkName ??= WordLink.headingBookmark(
        paragraph.text,
        clamped,
      );
    }
  }

  /// Apply a native catalog style by ID, including custom headings.
  static bool applyImportedStyles(
    WmlDocument document,
    Iterable<WmlParagraph> paragraphs,
    String styleId,
  ) {
    if (!document.importedStyles.containsKey(styleId)) return false;
    final properties = XmlDocument.parse(
      '<w:pPr xmlns:w="${OfficeNamespaces.w}"><w:pStyle/></w:pPr>',
    );
    properties.root!.firstChild('pStyle')!.setAttribute(
      'val',
      styleId,
      prefix: 'w',
      namespaceUri: OfficeNamespaces.w,
    );
    final source = properties.toXmlString(declaration: false);
    for (final paragraph in paragraphs) {
      paragraph.properties
        ..styleId = styleId
        ..listLabel = null
        ..listLabelUsesSpace = false
        ..listRestart = null
        ..sourcePropertiesXml = source
        ..importedValues = null;
      _resetMajorityRunFormatting(paragraph);
    }
    WordDeserializer()
      ..refreshStyles(document)
      ..refreshNumbering(document);
    return true;
  }

  /// Prepare an undoable update to the native style part. A removed effective
  /// tab becomes a clear record, which also suppresses a stop inherited from
  /// a parent style. Unchanged properties retain their native ownership.
  static ({PackagePart part, String before, String after})?
  prepareStyleGeometry(
    WmlDocument document,
    String id, {
    required WmlIndent indent,
    required List<WmlTabStop> tabs,
  }) {
    final package = document.package;
    if (package == null) return null;
    final part = package.getPart(_stylesUri(package, _mainUri(package)));
    if (part == null) return null;
    final current = WordDeserializer().paragraphStyleProperties(document, id);
    if (current == null) return null;
    final before = part.readText();
    final xml = XmlDocument.parse(before);
    final style = xml.root!
        .childrenNamed('style', namespaceUri: OfficeNamespaces.w)
        .where(
          (node) =>
              node.getAttribute('styleId', namespaceUri: OfficeNamespaces.w) ==
              id,
        )
        .first;
    final existing = style.firstChild('pPr', namespaceUri: OfficeNamespaces.w);
    final next = current.copy()..indent = indent;
    final generated = WordPropertyIo.parse(
      WordSerializer().paragraphPropertiesXml(
        WmlParagraphProps(
          indent: indent,
          explicitIndent: true,
          rightToLeft: next.rightToLeft,
        ),
      ),
      'pPr',
    );
    final properties = WordPropertyIo.preserve(
      generated,
      '',
      WordPropertyIo.paragraphValues(current),
      WordPropertyIo.paragraphValues(next),
      sourceElement: existing,
    );

    final oldStops = {
      for (final stop in current.tabs) pointsToTwips(stop.position): stop,
    };
    final newStops = {
      for (final stop in tabs) pointsToTwips(stop.position): stop,
    };
    for (final position in oldStops.keys) {
      if (!newStops.containsKey(position)) {
        WordPropertyIo.writeTabStop(properties, position, 'clear');
      }
    }
    for (final entry in newStops.entries) {
      final stop = entry.value;
      final old = oldStops[entry.key];
      if (old?.alignment == stop.alignment && old?.leader == stop.leader) {
        continue;
      }
      WordPropertyIo.writeTabStop(
        properties,
        entry.key,
        stop.alignment.name,
        leader: stop.leader.name,
      );
    }
    if (existing == null) {
      properties.setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
    }
    if (existing != null) {
      style.children[style.children.indexOf(existing)] = properties;
      properties.parent = style;
    } else {
      final run = style.firstChild('rPr', namespaceUri: OfficeNamespaces.w);
      final index = run == null
          ? style.children.length
          : style.children.indexOf(run);
      style.children.insert(index, properties);
      properties.parent = style;
    }
    return (part: part, before: before, after: xml.toXmlString());
  }

  static void _resetMajorityRunFormatting(WmlParagraph paragraph) {
    final runs = paragraph.inlines.whereType<WmlRun>().toList();
    final serializer = WordSerializer();
    final direct = <WmlRun, XmlElement>{
      for (final run in runs)
        run: XmlDocument.parse(
          run.properties.importedValues != null
              ? serializer.runPropertiesXml(run.properties)
              : ((run.properties.sourcePropertiesXml ?? '').isEmpty
                    ? '<w:rPr xmlns:w="${OfficeNamespaces.w}"/>'
                    : run.properties.sourcePropertiesXml!),
        ).root!,
    };
    final total = runs.fold<int>(0, (sum, run) => sum + run.text.length);
    for (final name in _resetRunProperties) {
      var covered = 0;
      for (final run in runs) {
        if (direct[run]!.childElements.any((e) => e.localName == name)) {
          covered += run.text.length;
        }
      }
      if (total == 0 || covered * 2 <= total) continue;
      for (final run in runs) {
        direct[run]!.children.removeWhere(
          (node) => node is XmlElement && node.localName == name,
        );
      }
    }
    for (final run in runs) {
      run.properties
        ..sourcePropertiesXml = XmlDocument(
          root: direct[run]!,
        ).toXmlString(declaration: false)
        ..importedValues = null;
    }
  }

  static String _mainUri(OpcPackage package) {
    final office = package.packageRelationships.firstByType(
      RelationshipTypes.officeDocument,
    );
    return office == null
        ? '/word/document.xml'
        : package.packageRelationships.resolve(office);
  }

  static String _stylesUri(OpcPackage package, String mainUri) {
    final rels = package.relationshipsFor(mainUri);
    final rel = rels.firstByType(RelationshipTypes.styles);
    return rel == null ? '/word/styles.xml' : rels.resolve(rel);
  }

  static XmlElement _stylesRoot(OpcPackage package, String mainUri) {
    final part = package.getPart(_stylesUri(package, mainUri));
    if (part != null) return XmlDocument.parse(part.readText()).root!;
    return XmlDocument.parse(
      '<w:styles xmlns:w="${OfficeNamespaces.w}"/>',
    ).root!;
  }

  static void _writeStyles(OpcPackage package, String mainUri, XmlElement root) {
    final rels = package.relationshipsFor(mainUri);
    final uri = _stylesUri(package, mainUri);
    final xml =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '${XmlDocument(root: root).toXmlString(declaration: false)}';
    final part = package.getPart(uri);
    if (part != null) {
      part.writeText(xml);
      return;
    }
    package.createPart(uri, OfficeContentTypes.wordStyles).writeText(xml);
    if (rels.firstByType(RelationshipTypes.styles) == null) {
      rels.add(type: RelationshipTypes.styles, target: 'styles.xml');
    }
  }

  static String? _styleId(XmlElement styles, String builtinName) {
    for (final style in styles.childrenNamed('style')) {
      if (style.getAttribute('type') != 'paragraph') continue;
      final name = style.firstChild('name')?.getAttribute('val');
      if (name != null && name.toLowerCase() == builtinName) {
        return style.getAttribute('styleId');
      }
    }
    return null;
  }

  static String? _defaultParagraphId(XmlElement styles) {
    for (final style in styles.childrenNamed('style')) {
      if (style.getAttribute('type') == 'paragraph' &&
          (style.getAttribute('default') == '1' ||
              style.getAttribute('default') == 'true')) {
        return style.getAttribute('styleId');
      }
    }
    return null;
  }

  /// Word's built-in heading definition for the document's theme era.
  static String _addBuiltinHeading(
    XmlElement styles,
    OpcPackage package,
    String mainUri,
    int level,
  ) {
    final ids = {
      for (final s in styles.childrenNamed('style')) s.getAttribute('styleId'),
    };
    var id = 'Heading$level';
    while (ids.contains(id)) {
      id = '${id}_';
    }
    final modern = _modernTheme(package, mainUri);
    final normal = _styleId(styles, 'normal') ?? _defaultParagraphId(styles);
    // (before, after, half-points, italic, accent shade or text1 tint)
    final (int, int, int?, bool, String) spec = modern
        ? switch (level) {
            1 => (360, 80, 40, false, 'BF'),
            2 => (160, 80, 32, false, 'BF'),
            3 => (160, 80, 28, false, 'BF'),
            4 => (80, 40, null, true, 'BF'),
            5 => (80, 40, null, false, 'BF'),
            6 => (40, 0, null, true, 'A6'),
            7 => (40, 0, null, false, 'A6'),
            8 => (0, 0, null, true, 'D8'),
            _ => (0, 0, null, false, 'D8'),
          }
        : switch (level) {
            1 => (240, 0, 32, false, 'BF'),
            2 => (40, 0, 26, false, 'BF'),
            3 => (40, 0, 24, false, '7F'),
            4 => (40, 0, null, true, 'BF'),
            5 => (40, 0, null, false, 'BF'),
            6 => (40, 0, null, false, '7F'),
            7 => (40, 0, null, true, '7F'),
            8 => (40, 0, 21, false, 'D8'),
            _ => (40, 0, 21, true, 'D8'),
          };
    final (before, after, size, italic, adjust) = spec;
    final bool text1 = (modern && level >= 6) || (!modern && level >= 8);
    // Word writes the theme colour computed for this document into w:val
    // as well; readers that ignore theme colours rely on it.
    final theme = _themeColors(package, mainUri);
    final int amount = int.parse(adjust, radix: 16);
    final String value = text1
        ? _hex(adjustThemeLuminance(theme.text1, tint: amount))
        : _hex(adjustThemeLuminance(theme.accent1, shade: amount));
    final String color = text1
        ? '<w:color w:val="$value" w:themeColor="text1" w:themeTint="$adjust"/>'
        : '<w:color w:val="$value" w:themeColor="accent1" w:themeShade="$adjust"/>';
    final String font = level <= 3 || !modern ? 'major' : 'minor';
    final xml =
        '<w:style xmlns:w="${OfficeNamespaces.w}" w:type="paragraph" '
        'w:styleId="$id"><w:name w:val="heading $level"/>'
        '${normal == null ? '' : '<w:basedOn w:val="$normal"/><w:next w:val="$normal"/>'}'
        '<w:uiPriority w:val="9"/><w:qFormat/>'
        '<w:pPr><w:keepNext/><w:keepLines/>'
        '<w:spacing w:before="$before" w:after="$after"/>'
        '<w:outlineLvl w:val="${level - 1}"/></w:pPr>'
        '<w:rPr><w:rFonts w:asciiTheme="${font}HAnsi" '
        'w:eastAsiaTheme="${font}EastAsia" w:hAnsiTheme="${font}HAnsi" '
        'w:cstheme="${font}Bidi"/>'
        '${italic ? '<w:i/><w:iCs/>' : ''}$color'
        '${size == null ? '' : '<w:sz w:val="$size"/><w:szCs w:val="$size"/>'}'
        '</w:rPr></w:style>';
    styles.children.add(XmlDocument.parse(xml).root!);
    return id;
  }

  static String _hex(int rgb) =>
      rgb.toRadixString(16).padLeft(6, '0').toUpperCase();

  /// accent 1 and text 1 (dk1) of the document theme; Office 2023 values
  /// when the package has no theme.
  static ({int accent1, int text1}) _themeColors(
    OpcPackage package,
    String mainUri,
  ) {
    final rels = package.relationshipsFor(mainUri);
    final rel = rels.firstByType(RelationshipTypes.theme);
    final part = package.getPart(
      rel == null ? '/word/theme/theme1.xml' : rels.resolve(rel),
    );
    var accent1 = 0x156082, text1 = 0x000000;
    if (part != null) {
      final scheme = XmlDocument.parse(part.readText()).root
          ?.firstChild('themeElements')
          ?.firstChild('clrScheme');
      int? colorOf(String name) {
        final value = scheme?.firstChild(name)?.childElements.firstOrNull;
        final hex = value?.getAttribute('lastClr') ?? value?.getAttribute('val');
        if (value?.getAttribute('val') == 'windowText') return 0;
        return hex == null ? null : int.tryParse(hex, radix: 16);
      }
      accent1 = colorOf('accent1') ?? accent1;
      text1 = colorOf('dk1') ?? text1;
    }
    return (accent1: accent1, text1: text1);
  }

  /// Office 2023 and later themes (accent 1 #156082 / Aptos) get the
  /// Word 365 heading look; older themes the Word 2013–2022 look.
  static bool _modernTheme(OpcPackage package, String mainUri) {
    final rels = package.relationshipsFor(mainUri);
    final rel = rels.firstByType(RelationshipTypes.theme);
    final part = package.getPart(
      rel == null ? '/word/theme/theme1.xml' : rels.resolve(rel),
    );
    if (part == null) return true;
    final text = part.readText();
    return text.contains('156082') || text.contains('typeface="Aptos');
  }
}
