import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';

/// Horizontal cell alignment (`alignment/@horizontal`).
enum SmlHAlign { general, left, center, right }

/// The font used by the built-in Normal cell style for column dimensions.
///
/// Sizes are typographic points, while column metrics are measured at 96 dpi.
class SmlNormalFont {
  const SmlNormalFont({
    required this.family,
    required this.sizePoints,
    this.bold = false,
    this.italic = false,
  });

  final String family;
  final double sizePoints;
  final bool bold;
  final bool italic;
}

/// A measured Normal-font digit width, including the actual face provenance.
///
/// [resolvedFontFamily] names the font that was measured. It can differ from
/// the requested family when an application deliberately registers an alias.
class SmlColumnMetrics {
  const SmlColumnMetrics({
    required this.maximumDigitWidthPx,
    required this.resolvedFontFamily,
  });

  final int maximumDigitWidthPx;
  final String resolvedFontFamily;

  bool substitutes(SmlNormalFont font) =>
      resolvedFontFamily.toLowerCase() != font.family.toLowerCase();
}

/// Return null when the requested font cannot be resolved reliably.
typedef SmlColumnMetricsResolver = SmlColumnMetrics? Function(
  SmlNormalFont normalFont,
);

/// Parsed `styles.xml` subset: numFmts, fills, fonts, and cellXfs.
class SmlStyleSheet {
  XmlDocument? _source;
  List<XmlElement>? _sourceFonts;
  List<XmlElement>? _sourceFills;
  final Map<int, int> _fontBases = {};
  final Set<int> _explicitFontColors = {};
  final Map<int, int> _xfBases = {};

  /// SmlStyleSheet API.
  SmlStyleSheet({
    Map<int, String>? numFmts,
    List<int>? cellXfsNumFmt,
    List<SmlHAlign>? cellXfsAlign,
    List<String>? fillRgbs,
    List<String>? fontRgbs,
    List<bool>? fontBolds,
    List<double>? fontSizes,
    List<int>? cellXfsFillId,
    List<int>? cellXfsFontId,
    List<String>? themeColors,
    Map<String, String>? themeFontFamilies,
  }) : numFmts = numFmts ?? Map<int, String>.from(_builtIn),
       cellXfsNumFmt = cellXfsNumFmt ?? <int>[0],
       cellXfsAlign = cellXfsAlign ?? <SmlHAlign>[SmlHAlign.general],
       fillRgbs = fillRgbs ?? <String>['', ''],
       fontRgbs = fontRgbs ?? <String>[''],
       fontBolds = fontBolds ?? <bool>[false],
       fontSizes = fontSizes ?? <double>[11],
       cellXfsFillId = cellXfsFillId ?? <int>[0],
       cellXfsFontId = cellXfsFontId ?? <int>[0],
       themeColors = themeColors ?? List<String>.from(_officeTheme),
       themeFontFamilies = Map<String, String>.unmodifiable(
         themeFontFamilies ?? const <String, String>{},
       );

  /// numFmts API.
  final Map<int, String> numFmts;

  /// cellXfsNumFmt API.
  final List<int> cellXfsNumFmt;

  /// cellXfsAlign API.
  final List<SmlHAlign> cellXfsAlign;

  /// Solid fill RGB (`RRGGBB`) per fills.xml entry; empty means no fill.
  final List<String> fillRgbs;

  /// Font RGB (`RRGGBB`) per fonts.xml entry; empty means default text.
  final List<String> fontRgbs;

  /// Bold flag per fonts.xml entry.
  final List<bool> fontBolds;

  /// Point size per fonts.xml entry.
  final List<double> fontSizes;

  /// cellXfsFillId API.
  final List<int> cellXfsFillId;

  /// cellXfsFontId API.
  final List<int> cellXfsFontId;

  /// Theme scheme colors (dk1 … folHlink).
  final List<String> themeColors;

  /// Theme Latin faces keyed by `major` or `minor`.
  final Map<String, String> themeFontFamilies;

  /// Native Normal-font selection follows builtinId, not a localized name or
  /// cellXfs[0]. Ambiguous or malformed native style links remain unresolved.
  SmlNormalFont? get normalFont {
    final root = _source?.root;
    if (root == null) return null;
    final styles = root
        .firstChild('cellStyles', namespaceUri: root.namespaceUri)
        ?.childrenNamed('cellStyle', namespaceUri: root.namespaceUri);
    final normal = styles
        ?.where(
          (style) =>
              int.tryParse(
                style.getAttribute('builtinId', namespaceUri: '') ?? '',
              ) ==
              0,
        )
        .toList();
    if (normal == null || normal.length != 1) return null;
    final xfId = int.tryParse(
      normal.single.getAttribute('xfId', namespaceUri: '') ?? '',
    );
    final xfs = root
        .firstChild('cellStyleXfs', namespaceUri: root.namespaceUri)
        ?.childrenNamed('xf', namespaceUri: root.namespaceUri)
        .toList();
    if (xfId == null || xfs == null || xfId < 0 || xfId >= xfs.length) {
      return null;
    }
    final fontId = int.tryParse(
      xfs[xfId].getAttribute('fontId', namespaceUri: '') ?? '',
    );
    final fonts = root
        .firstChild('fonts', namespaceUri: root.namespaceUri)
        ?.childrenNamed('font', namespaceUri: root.namespaceUri)
        .toList();
    if (fontId == null ||
        fonts == null ||
        fontId < 0 ||
        fontId >= fonts.length) {
      return null;
    }
    final font = fonts[fontId];
    final scheme = font
        .firstChild('scheme', namespaceUri: root.namespaceUri)
        ?.getAttribute('val', namespaceUri: '');
    final family =
        themeFontFamilies[scheme] ??
        font
            .firstChild('name', namespaceUri: root.namespaceUri)
            ?.getAttribute('val', namespaceUri: '');
    final size = double.tryParse(
      font
              .firstChild('sz', namespaceUri: root.namespaceUri)
              ?.getAttribute('val', namespaceUri: '') ??
          '',
    );
    if (family == null ||
        family.trim().isEmpty ||
        size == null ||
        !size.isFinite ||
        size <= 0) {
      return null;
    }
    bool enabled(String name) {
      final element = font.firstChild(name, namespaceUri: root.namespaceUri);
      if (element == null) return false;
      final value = element.getAttribute('val', namespaceUri: '');
      return value == null || value == '1' || value.toLowerCase() == 'true';
    }

    return SmlNormalFont(
      family: family,
      sizePoints: size,
      bold: enabled('b'),
      italic: enabled('i'),
    );
  }

  /// Reads the Latin major/minor theme faces used for the ten ASCII digits.
  static Map<String, String> parseThemeFontFamilies(String xml) {
    final scheme = XmlDocument.parse(xml).root
        ?.firstChild('themeElements')
        ?.firstChild('fontScheme');
    return <String, String>{
      for (final kind in ['major', 'minor'])
        if (scheme
                ?.firstChild('${kind}Font')
                ?.firstChild('latin')
                ?.getAttribute('typeface')
            case final String family)
          if (family.trim().isNotEmpty) kind: family,
    };
  }

  /// parse API.
  factory SmlStyleSheet.parse(
    String xml, {
    List<String>? themeColors,
    Map<String, String>? themeFontFamilies,
  }) {
    final SmlStyleSheet sheet = SmlStyleSheet(
      cellXfsNumFmt: <int>[],
      cellXfsAlign: <SmlHAlign>[],
      fillRgbs: <String>[],
      fontRgbs: <String>[],
      fontBolds: <bool>[],
      fontSizes: <double>[],
      cellXfsFillId: <int>[],
      cellXfsFontId: <int>[],
      themeColors: themeColors,
      themeFontFamilies: themeFontFamilies,
    );
    // The source tree is retained for lossless merging, so read the modeled
    // subset from that same tree. Only direct SpreadsheetML children are
    // indices; extension elements with familiar local names are not styles.
    final source = XmlDocument.parse(xml);
    sheet._source = source;
    final root = source.root;
    if (root == null) return sheet;
    final namespace = root.namespaceUri;
    Iterable<XmlElement> entries(String container, String name) =>
        root
            .firstChild(container, namespaceUri: namespace)
            ?.childrenNamed(name, namespaceUri: namespace) ??
        const <XmlElement>[];

    String color(XmlElement? element) => resolveColor(
      rgb: element == null ? null : _attribute(element, 'rgb'),
      theme: element == null ? null : _attribute(element, 'theme'),
      indexed: element == null ? null : _attribute(element, 'indexed'),
      tint: element == null ? null : _attribute(element, 'tint'),
      themeColors: sheet.themeColors,
    );

    for (final format in entries('numFmts', 'numFmt')) {
      final id = int.tryParse(_attribute(format, 'numFmtId') ?? '');
      if (id != null) {
        sheet.numFmts[id] = _attribute(format, 'formatCode') ?? 'General';
      }
    }
    for (final fill in entries('fills', 'fill')) {
      final pattern = fill.firstChild('patternFill', namespaceUri: namespace);
      final foreground = color(
        pattern?.firstChild('fgColor', namespaceUri: namespace),
      );
      sheet.fillRgbs.add(
        foreground.isNotEmpty
            ? foreground
            : color(pattern?.firstChild('bgColor', namespaceUri: namespace)),
      );
    }
    for (final font in entries('fonts', 'font')) {
      final bold = font.firstChild('b', namespaceUri: namespace);
      final enabled = bold == null ? null : _attribute(bold, 'val');
      final size = font.firstChild('sz', namespaceUri: namespace);
      sheet.fontRgbs.add(
        color(font.firstChild('color', namespaceUri: namespace)),
      );
      sheet.fontBolds.add(
        bold != null &&
            (enabled == null ||
                enabled == '1' ||
                enabled.toLowerCase() == 'true'),
      );
      sheet.fontSizes.add(
        double.tryParse(size == null ? '' : _attribute(size, 'val') ?? '') ??
            11,
      );
    }
    for (final format in entries('cellXfs', 'xf')) {
      sheet.cellXfsNumFmt.add(
        int.tryParse(_attribute(format, 'numFmtId') ?? '') ?? 0,
      );
      final alignment = format.firstChild('alignment', namespaceUri: namespace);
      sheet.cellXfsAlign.add(
        parseHAlign(
          alignment == null ? null : _attribute(alignment, 'horizontal'),
        ),
      );
      sheet.cellXfsFillId.add(
        int.tryParse(_attribute(format, 'fillId') ?? '') ?? 0,
      );
      sheet.cellXfsFontId.add(
        int.tryParse(_attribute(format, 'fontId') ?? '') ?? 0,
      );
    }
    return sheet;
  }

  /// parseTheme API.
  static List<String> parseTheme(String xml) {
    final List<String> colors = List<String>.from(_officeTheme);
    final XmlPullReader reader = XmlPullReader(xml);
    var inScheme = false;
    var index = 0;
    while (reader.next()) {
      if (reader.eventType == XmlEventType.endElement &&
          reader.localName == 'clrScheme') {
        break;
      }
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'clrScheme') {
        inScheme = true;
        continue;
      }
      if (!inScheme) {
        continue;
      }
      if (reader.localName == 'srgbClr') {
        final String val = normalizeRgb(reader.getAttribute('val') ?? '');
        if (val.isNotEmpty && index < colors.length) {
          colors[index] = val;
        }
        index++;
      } else if (reader.localName == 'sysClr') {
        final String val = normalizeRgb(reader.getAttribute('lastClr') ?? '');
        if (val.isNotEmpty && index < colors.length) {
          colors[index] = val;
        }
        index++;
      }
    }
    return colors;
  }

  /// format API.
  String format(Object? value, int styleIndex) {
    final int numFmtId = styleIndex >= 0 && styleIndex < cellXfsNumFmt.length
        ? cellXfsNumFmt[styleIndex]
        : 0;
    final String code = numFmts[numFmtId] ?? 'General';
    return applyNumberFormat(value, code);
  }

  /// alignAt API.
  SmlHAlign alignAt(int styleIndex) {
    if (styleIndex >= 0 && styleIndex < cellXfsAlign.length) {
      return cellXfsAlign[styleIndex];
    }
    return SmlHAlign.general;
  }

  /// fillAt API.
  String fillAt(int styleIndex) {
    if (styleIndex < 0 || styleIndex >= cellXfsFillId.length) {
      return '';
    }
    final int id = cellXfsFillId[styleIndex];
    if (id < 0 || id >= fillRgbs.length) {
      return '';
    }
    return fillRgbs[id];
  }

  /// fontAt API.
  String fontAt(int styleIndex) {
    if (styleIndex < 0 || styleIndex >= cellXfsFontId.length) {
      return '';
    }
    final int id = cellXfsFontId[styleIndex];
    if (id < 0 || id >= fontRgbs.length) {
      return '';
    }
    return fontRgbs[id];
  }

  /// boldAt API.
  bool boldAt(int styleIndex) {
    if (styleIndex < 0 || styleIndex >= cellXfsFontId.length) {
      return false;
    }
    final int id = cellXfsFontId[styleIndex];
    if (id < 0 || id >= fontBolds.length) {
      return false;
    }
    return fontBolds[id];
  }

  /// sizeAt API.
  double sizeAt(int styleIndex) {
    if (styleIndex < 0 || styleIndex >= cellXfsFontId.length) {
      return 11;
    }
    final int id = cellXfsFontId[styleIndex];
    if (id < 0 || id >= fontSizes.length) {
      return 11;
    }
    return fontSizes[id];
  }

  /// xfForAlign API.
  int xfForAlign(SmlHAlign align) => xfFor(align: align);

  /// Family retained in the native cell font, with major/minor theme faces
  /// resolved. Null means the model has no declared family; it is not a claim
  /// that the host's platform default has the source font's metrics.
  String? familyAt(int styleIndex) {
    final font = _nativeFontAt(styleIndex);
    if (font == null) return null;
    final scheme = font
        .firstChild('scheme', namespaceUri: font.namespaceUri)
        ?.getAttribute('val', namespaceUri: '');
    return themeFontFamilies[scheme] ??
        font
            .firstChild('name', namespaceUri: font.namespaceUri)
            ?.getAttribute('val', namespaceUri: '');
  }

  /// Italic from the retained native font. Scalar cell edits keep these source
  /// attributes, so a derived style follows its font base without rewriting it.
  bool italicAt(int styleIndex) {
    final font = _nativeFontAt(styleIndex);
    final value = font?.firstChild('i', namespaceUri: font.namespaceUri);
    if (value == null) return false;
    final enabled = value.getAttribute('val', namespaceUri: '');
    return enabled == null || enabled == '1' || enabled.toLowerCase() == 'true';
  }

  XmlElement? _nativeFontAt(int styleIndex) {
    if (styleIndex < 0 || styleIndex >= cellXfsFontId.length) return null;
    var id = cellXfsFontId[styleIndex];
    final visited = <int>{};
    while (_fontBases.containsKey(id)) {
      if (!visited.add(id)) return null;
      id = _fontBases[id]!;
    }
    final root = _source?.root;
    final fonts = _sourceFonts ??=
        root
            ?.firstChild('fonts', namespaceUri: root.namespaceUri)
            ?.childrenNamed('font', namespaceUri: root.namespaceUri)
            .toList() ??
        [];
    return id >= 0 && id < fonts.length ? fonts[id] : null;
  }

  /// xfFor API.
  int xfFor({
    SmlHAlign align = SmlHAlign.general,
    String fillRgb = '',
    bool fillColorExplicit = false,
    String fontRgb = '',
    bool fontColorExplicit = false,
    bool bold = false,
    double size = 11,
    int? baseStyleIndex,
  }) {
    if (cellXfsAlign.isEmpty) {
      cellXfsNumFmt.add(0);
      cellXfsAlign.add(SmlHAlign.general);
      cellXfsFillId.add(0);
      cellXfsFontId.add(0);
    }
    if (fillRgbs.isEmpty) {
      fillRgbs.addAll(<String>['', '']);
    }
    if (fontRgbs.isEmpty) {
      fontRgbs.add('');
      fontBolds.add(false);
      fontSizes.add(11);
    }
    final int? base =
        baseStyleIndex != null &&
            baseStyleIndex >= 0 &&
            baseStyleIndex < cellXfsAlign.length
        ? baseStyleIndex
        : null;
    final String fill = normalizeRgb(fillRgb);
    final String font = normalizeRgb(fontRgb);
    final explicitFill =
        base != null &&
        fillColorExplicit &&
        !_hasDirectFill(cellXfsFillId[base], fill);
    final explicitColor =
        base != null && fontColorExplicit && !_hasDirectFontColor(base, font);
    if (base != null &&
        !explicitFill &&
        !explicitColor &&
        alignAt(base) == align &&
        fillAt(base) == fill &&
        fontAt(base) == font &&
        boldAt(base) == bold &&
        sizeAt(base) == size) {
      return base;
    }
    // The modeled RGB is not a fill's identity: gradients may have no scalar
    // color, and patterns/theme colors may share an RGB with a different fill.
    // Unrelated font/alignment edits must retain the original native fill.
    final int fillId = base != null && !explicitFill && fillAt(base) == fill
        ? cellXfsFillId[base]
        : _fillId(fill);
    final int? baseFont = base == null ? null : cellXfsFontId[base];
    final int fontId;
    if (baseFont != null &&
        (explicitColor ||
            fontRgbs[baseFont] != font ||
            fontBolds[baseFont] != bold ||
            fontSizes[baseFont] != size)) {
      fontId = fontRgbs.length;
      fontRgbs.add(font);
      fontBolds.add(bold);
      fontSizes.add(size);
      _fontBases[fontId] = baseFont;
      if (explicitColor) _explicitFontColors.add(fontId);
    } else {
      fontId = baseFont ?? _fontId(rgb: font, bold: bold, size: size);
    }

    for (int i = 0; i < cellXfsAlign.length; i++) {
      final int xfFill = i < cellXfsFillId.length ? cellXfsFillId[i] : 0;
      final int xfFont = i < cellXfsFontId.length ? cellXfsFontId[i] : 0;
      if (base == null &&
          cellXfsAlign[i] == align &&
          xfFill == fillId &&
          xfFont == fontId) {
        return i;
      }
    }
    if (base != null) _xfBases[cellXfsAlign.length] = base;
    cellXfsNumFmt.add(base == null ? 0 : cellXfsNumFmt[base]);
    cellXfsAlign.add(align);
    cellXfsFillId.add(fillId);
    cellXfsFontId.add(fontId);
    return cellXfsAlign.length - 1;
  }

  bool _hasDirectFontColor(int styleIndex, String rgb) {
    var id = cellXfsFontId[styleIndex];
    while (_fontBases.containsKey(id)) {
      final base = _fontBases[id]!;
      if (_explicitFontColors.contains(id) || fontRgbs[id] != fontRgbs[base]) {
        return fontRgbs[id] == rgb;
      }
      id = base;
    }
    final root = _source?.root;
    final fonts = root
        ?.firstChild('fonts', namespaceUri: root.namespaceUri)
        ?.childrenNamed('font', namespaceUri: root.namespaceUri);
    // Newly authored fonts are already written using direct colors.
    if (fonts == null || id < 0 || id >= fonts.length) return true;
    final color = fonts[id].firstChild(
      'color',
      namespaceUri: root!.namespaceUri,
    );
    if (color == null) return rgb.isEmpty;
    if (_attribute(color, 'theme') != null ||
        _attribute(color, 'indexed') != null ||
        _attribute(color, 'tint') != null ||
        _attribute(color, 'auto') != null) {
      return false;
    }
    return normalizeRgb(_attribute(color, 'rgb') ?? '') == rgb;
  }

  int _fontId({required String rgb, required bool bold, required double size}) {
    final int n = fontRgbs.length;
    while (fontBolds.length < n) {
      fontBolds.add(false);
    }
    while (fontSizes.length < n) {
      fontSizes.add(11);
    }
    for (int i = 0; i < n; i++) {
      if (fontRgbs[i] == rgb && fontBolds[i] == bold && fontSizes[i] == size) {
        return i;
      }
    }
    fontRgbs.add(rgb);
    fontBolds.add(bold);
    fontSizes.add(size);
    return fontRgbs.length - 1;
  }

  int _fillId(String rgb) {
    for (int i = 0; i < fillRgbs.length; i++) {
      // A solid-color command must not accidentally select a native pattern,
      // gradient or theme/indexed color that merely resolves to the same RGB.
      if (fillRgbs[i] == rgb && _hasDirectFill(i, rgb)) {
        return i;
      }
    }
    // The generated second empty fill is the required gray125 placeholder,
    // never the target of an explicit no-fill command.
    if (rgb.isEmpty && fillRgbs.length == 1) fillRgbs.add('');
    fillRgbs.add(rgb);
    return fillRgbs.length - 1;
  }

  bool _hasDirectFill(int id, String rgb) {
    if (id < 0 || id >= fillRgbs.length) return false;
    final root = _source?.root;
    final fills = _sourceFills ??=
        root
            ?.firstChild('fills', namespaceUri: root.namespaceUri)
            ?.childrenNamed('fill', namespaceUri: root.namespaceUri)
            .toList() ??
        [];
    if (id >= fills.length) {
      // Newly generated fills are direct solid colors, no fill, or gray125.
      return fillRgbs[id] == rgb && !(id == 1 && rgb.isEmpty);
    }
    final fill = fills[id];
    if (fill.firstChild('gradientFill', namespaceUri: fill.namespaceUri) !=
        null) {
      return false;
    }
    final pattern = fill.firstChild(
      'patternFill',
      namespaceUri: fill.namespaceUri,
    );
    final type = pattern == null ? 'none' : _attribute(pattern, 'patternType');
    if (rgb.isEmpty) return type == null || type == 'none';
    if (type != 'solid') return false;
    final color = pattern!.firstChild(
      'fgColor',
      namespaceUri: fill.namespaceUri,
    );
    if (color == null) return false;
    if (const [
      'theme',
      'indexed',
      'tint',
      'auto',
    ].any((name) => _attribute(color, name) != null)) {
      return false;
    }
    return normalizeRgb(_attribute(color, 'rgb') ?? '') == rgb;
  }

  /// parseHAlign API.
  static SmlHAlign parseHAlign(String? raw) {
    return switch (raw) {
      'center' => SmlHAlign.center,
      'left' => SmlHAlign.left,
      'right' => SmlHAlign.right,
      _ => SmlHAlign.general,
    };
  }

  /// hAlignName API.
  static String hAlignName(SmlHAlign align) {
    return switch (align) {
      SmlHAlign.center => 'center',
      SmlHAlign.left => 'left',
      SmlHAlign.right => 'right',
      SmlHAlign.general => 'general',
    };
  }

  /// Minimal `styles.xml` that preserves number formats, fill, and alignment.
  String toXml() {
    if (fillRgbs.isEmpty) {
      fillRgbs.addAll(<String>['', '']);
    }
    if (fontRgbs.isEmpty) {
      fontRgbs.add('');
      fontBolds.add(false);
      fontSizes.add(11);
    }
    while (fontBolds.length < fontRgbs.length) {
      fontBolds.add(false);
    }
    while (fontSizes.length < fontRgbs.length) {
      fontSizes.add(11);
    }
    final StringBuffer buf = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    );
    buf.write('<fonts count="${fontRgbs.length}">');
    for (int i = 0; i < fontRgbs.length; i++) {
      final String font = fontRgbs[i];
      final bool bold = fontBolds[i];
      final String size = fontSizes[i].toString();
      buf.write('<font>');
      if (bold) {
        buf.write('<b/>');
      }
      buf.write('<sz val="$size"/>');
      if (font.isNotEmpty) {
        buf.write('<color rgb="FF$font"/>');
      }
      buf.write('<name val="Calibri"/>');
      buf.write('</font>');
    }
    buf.write('</fonts><fills count="${fillRgbs.length}">');
    for (int i = 0; i < fillRgbs.length; i++) {
      final String rgb = fillRgbs[i];
      if (i == 1 && rgb.isEmpty) {
        buf.write('<fill><patternFill patternType="gray125"/></fill>');
      } else if (rgb.isEmpty) {
        buf.write('<fill><patternFill patternType="none"/></fill>');
      } else {
        buf.write(
          '<fill><patternFill patternType="solid">'
          '<fgColor rgb="FF$rgb"/></patternFill></fill>',
        );
      }
    }
    buf.write(
      '</fills><borders count="1">'
      '<border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
      '</cellStyleXfs>'
      '<cellXfs count="${cellXfsAlign.length}">',
    );
    for (int i = 0; i < cellXfsAlign.length; i++) {
      final int numFmtId = i < cellXfsNumFmt.length ? cellXfsNumFmt[i] : 0;
      final int fillId = i < cellXfsFillId.length ? cellXfsFillId[i] : 0;
      final int fontId = i < cellXfsFontId.length ? cellXfsFontId[i] : 0;
      final SmlHAlign align = cellXfsAlign[i];
      buf.write(
        '<xf numFmtId="$numFmtId" fontId="$fontId" fillId="$fillId" '
        'borderId="0" xfId="0"',
      );
      if (fillId > 0) {
        buf.write(' applyFill="1"');
      }
      if (fontId > 0) {
        buf.write(' applyFont="1"');
      }
      if (align != SmlHAlign.general) {
        buf.write(
          ' applyAlignment="1">'
          '<alignment horizontal="${hAlignName(align)}"/>'
          '</xf>',
        );
      } else {
        buf.write('/>');
      }
    }
    buf.write('</cellXfs></styleSheet>');
    final generated = XmlDocument.parse(buf.toString());
    if (_source == null) {
      _orderFonts(generated);
      return generated.toXmlString();
    }
    final result = XmlDocument.parse(_source!.toXmlString());
    final root = result.root!;
    final namespace = root.namespaceUri;
    for (final (name, entryName) in [
      ('fonts', 'font'),
      ('fills', 'fill'),
      ('cellXfs', 'xf'),
    ]) {
      final old = root.firstChild(name, namespaceUri: namespace);
      final fresh = generated.root!.firstChild(
        name,
        namespaceUri: generated.root!.namespaceUri,
      )!;
      if (old == null) {
        _insertStyleCollection(root, _generatedCopy(fresh, namespace));
        continue;
      }
      final oldEntries = old
          .childrenNamed(entryName, namespaceUri: namespace)
          .toList();
      final generatedEntries = fresh.childrenNamed(
        entryName,
        namespaceUri: fresh.namespaceUri,
      );
      for (int i = oldEntries.length; i < generatedEntries.length; i++) {
        XmlElement entry = _generatedCopy(generatedEntries[i], namespace);
        final base = name == 'fonts'
            ? _fontBases[i]
            : name == 'cellXfs'
            ? _xfBases[i]
            : null;
        if (base != null && base >= 0 && base < oldEntries.length) {
          final template = oldEntries[base].copy();
          if (name == 'fonts') {
            // A bold edit must not materialize a theme color as fixed RGB or
            // replace an imported size/property which the user did not edit.
            final changed = <String>[
              if (fontBolds[i] != fontBolds[base]) 'b',
              if (fontSizes[i] != fontSizes[base]) 'sz',
              if (_explicitFontColors.contains(i) ||
                  fontRgbs[i] != fontRgbs[base])
                'color',
            ];
            for (final key in changed) {
              final previous = template.firstChild(
                key,
                namespaceUri: namespace,
              );
              final replacement = entry.firstChild(
                key,
                namespaceUri: namespace,
              );
              if (previous != null && (replacement != null || key == 'b')) {
                // Preserve extension attributes and children attached to the
                // property which is changing, as well as unrelated properties.
                final attributes = key == 'color'
                    ? const ['rgb', 'theme', 'indexed', 'tint', 'auto']
                    : const ['val'];
                previous.attributes.removeWhere(
                  (attribute) =>
                      attribute.prefix.isEmpty &&
                      attribute.namespaceUri.isEmpty &&
                      attributes.contains(attribute.localName),
                );
                if (replacement == null) {
                  _setAttribute(previous, 'val', '0');
                } else {
                  for (final attribute in replacement.attributes) {
                    if (attribute.prefix.isEmpty &&
                        attribute.namespaceUri.isEmpty &&
                        attributes.contains(attribute.localName)) {
                      _setAttribute(
                        previous,
                        attribute.localName,
                        attribute.value,
                      );
                    }
                  }
                }
              } else if (replacement != null) {
                template.addChild(_generatedCopy(replacement, namespace));
              } else {
                template.children.remove(previous);
              }
            }
            _orderFontChildren(template);
          } else {
            if (cellXfsFontId[i] != cellXfsFontId[base]) {
              _setAttribute(template, 'fontId', '${cellXfsFontId[i]}');
              _setAttribute(template, 'applyFont', '1');
            }
            if (cellXfsFillId[i] != cellXfsFillId[base]) {
              _setAttribute(template, 'fillId', '${cellXfsFillId[i]}');
              _setAttribute(template, 'applyFill', '1');
            }
            if (cellXfsAlign[i] != cellXfsAlign[base]) {
              _setAttribute(template, 'applyAlignment', '1');
              final alignment = template.firstChild(
                'alignment',
                namespaceUri: namespace,
              );
              if (alignment != null) {
                _setAttribute(
                  alignment,
                  'horizontal',
                  hAlignName(cellXfsAlign[i]),
                );
              } else {
                final alignment = _generatedCopy(
                  XmlElement(localName: 'alignment', namespaceUri: namespace),
                  namespace,
                );
                _setAttribute(
                  alignment,
                  'horizontal',
                  hAlignName(cellXfsAlign[i]),
                );
                // CT_Xf places alignment before protection and extLst.
                final after = template.children.indexWhere(
                  (node) =>
                      node is XmlElement &&
                      node.namespaceUri == namespace &&
                      (node.localName == 'protection' ||
                          node.localName == 'extLst'),
                );
                alignment.parent = template;
                template.children.insert(
                  after < 0 ? template.children.length : after,
                  alignment,
                );
              }
            }
          }
          entry = template;
        }
        old.addChild(entry);
        oldEntries.add(entry);
      }
      _setAttribute(old, 'count', '${oldEntries.length}');
    }
    _orderFonts(result);
    return result.toXmlString();
  }

  // XmlElement's convenience accessor also matches foreign attributes unless
  // a namespace is supplied. Require an unprefixed name for native attributes;
  // namespace declarations themselves are not SpreadsheetML attributes.
  static String? _attribute(XmlElement element, String name) {
    for (final attribute in element.attributes) {
      if (attribute.localName == name &&
          attribute.prefix.isEmpty &&
          attribute.namespaceUri.isEmpty) {
        return attribute.value;
      }
    }
    return null;
  }

  static void _setAttribute(XmlElement element, String name, String value) {
    for (final attribute in element.attributes) {
      if (attribute.localName == name &&
          attribute.prefix.isEmpty &&
          attribute.namespaceUri.isEmpty) {
        attribute.value = value;
        return;
      }
    }
    element.attributes.add(XmlAttribute(localName: name, value: value));
  }

  // The XML writer emits lexical names, not namespaceUri. A generated subtree
  // needs its own default binding when inserted into a prefixed source or a
  // source whose default namespace was rebound by an extension. Binding at
  // the inserted root leaves the original prefix scopes untouched.
  static XmlElement _generatedCopy(XmlElement source, String namespace) {
    final copy = source.copy();
    void bind(XmlElement element) {
      element
        ..prefix = ''
        ..namespaceUri = namespace;
      for (final child in element.childElements) {
        bind(child);
      }
    }

    bind(copy);
    _setAttribute(copy, 'xmlns', namespace);
    return copy;
  }

  static void _insertStyleCollection(XmlElement root, XmlElement collection) {
    const order = [
      'numFmts',
      'fonts',
      'fills',
      'borders',
      'cellStyleXfs',
      'cellXfs',
      'cellStyles',
      'dxfs',
      'tableStyles',
      'colors',
      'extLst',
    ];
    final rank = order.indexOf(collection.localName);
    final after = root.children.indexWhere(
      (node) =>
          node is XmlElement &&
          node.namespaceUri == root.namespaceUri &&
          order.indexOf(node.localName) > rank,
    );
    collection.parent = root;
    root.children.insert(after < 0 ? root.children.length : after, collection);
  }

  // Some import producers emit the same properties in a non-schema order.
  // Normalize native properties without rewriting foreign extension nodes.
  static void _orderFonts(XmlDocument document) {
    final root = document.root!;
    for (final font
        in root
                .firstChild('fonts', namespaceUri: root.namespaceUri)
                ?.childrenNamed('font', namespaceUri: root.namespaceUri) ??
            <XmlElement>[]) {
      _orderFontChildren(font);
    }
  }

  static void _orderFontChildren(XmlElement font) {
    const order = <String>[
      'b',
      'i',
      'strike',
      'condense',
      'extend',
      'outline',
      'shadow',
      'u',
      'vertAlign',
      'sz',
      'color',
      'name',
      'family',
      'charset',
      'scheme',
    ];
    int rank(XmlElement node) {
      final index = order.indexOf(node.localName);
      return index < 0 ? order.length : index;
    }

    final slots = <int>[
      for (var i = 0; i < font.children.length; i++)
        if (font.children[i] case final XmlElement child)
          if (child.namespaceUri == font.namespaceUri) i,
    ];
    final children =
        <(int, XmlElement)>[
          for (final i in slots) (i, font.children[i] as XmlElement),
        ]..sort((a, b) {
          final compared = rank(a.$2).compareTo(rank(b.$2));
          return compared == 0 ? a.$1.compareTo(b.$1) : compared;
        });
    for (var i = 0; i < slots.length; i++) {
      font.children[slots[i]] = children[i].$2;
    }
  }

  /// resolveColor API.
  static String resolveColor({
    String? rgb,
    String? theme,
    String? indexed,
    String? tint,
    List<String> themeColors = const <String>[],
  }) {
    var hex = normalizeRgb(rgb ?? '');
    if (hex.isEmpty && theme != null) {
      final int raw = int.tryParse(theme) ?? -1;
      final int i = themeSchemeIndex(raw);
      if (i >= 0 && i < themeColors.length) {
        hex = themeColors[i];
      } else if (i >= 0 && i < _officeTheme.length) {
        hex = _officeTheme[i];
      }
    }
    if (hex.isEmpty && indexed != null) {
      final int i = int.tryParse(indexed) ?? -1;
      if (i >= 0 && i < _indexed.length) {
        hex = _indexed[i];
      }
    }
    if (hex.isEmpty) {
      return '';
    }
    final double? t = double.tryParse(tint ?? '');
    if (t == null || t == 0) {
      return hex;
    }
    return applyTint(hex, t);
  }

  /// SpreadsheetML `theme=` indices swap lt/dk pairs in `clrScheme`.
  static int themeSchemeIndex(int theme) {
    return switch (theme) {
      0 => 1,
      1 => 0,
      2 => 3,
      3 => 2,
      _ => theme,
    };
  }

  /// normalizeRgb API.
  static String normalizeRgb(String raw) {
    var hex = raw.trim().toUpperCase();
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }
    if (hex.length == 8) {
      hex = hex.substring(2);
    }
    if (hex.length != 6 || int.tryParse(hex, radix: 16) == null) {
      return '';
    }
    return hex;
  }

  /// applyTint API.
  static String applyTint(String rgb, double tint) {
    int channel(int value) {
      final double n = value / 255;
      final double out = tint < 0 ? n * (1 + tint) : n * (1 - tint) + tint;
      return (out.clamp(0, 1) * 255).round();
    }

    final int v = int.parse(rgb, radix: 16);
    final String r = channel((v >> 16) & 0xFF)
        .toRadixString(16)
        .padLeft(2, '0');
    final String g = channel((v >> 8) & 0xFF).toRadixString(16).padLeft(2, '0');
    final String b = channel(v & 0xFF).toRadixString(16).padLeft(2, '0');
    return '$r$g$b'.toUpperCase();
  }
}

/// ECMA-376 §18.8.30 number formats (common subset).
String applyNumberFormat(Object? value, String code) {
  if (value == null) {
    return '';
  }
  if (code == 'General' || code == '@') {
    if (value is num && value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toString();
  }

  /// n API.
  final double? n = value is num
      ? value.toDouble()
      : double.tryParse(value.toString());
  if (n == null) {
    return value.toString();
  }

  final List<String> sections = code.split(';');
  // Sections: positive; negative; zero. A negative section prints its own
  // sign (e.g. parentheses), so the value is formatted without one.
  var section = sections.first;
  var shown = n;
  if (n < 0 && sections.length > 1 && sections[1].isNotEmpty) {
    section = sections[1];
    shown = -n;
  } else if (n == 0 && sections.length > 2 && sections[2].isNotEmpty) {
    section = sections[2];
  }
  final bool negativeRed = section.contains('[Red]');
  final String clean = section.replaceAll('[Red]', '');

  String out;
  if (_isDateFormat(clean) && !RegExp(r'[0#?]').hasMatch(_literalFree(clean))) {
    out = formatExcelDate(excelSerialToDate(shown), clean);
  } else {
    out = _formatNumberSection(shown, clean);
  }
  if (negativeRed && n < 0) {
    return 'RED:$out';
  }
  return out;
}

/// [code] without quoted literals, escapes, and `[…]` blocks.
String _literalFree(String code) => code
    .replaceAll(RegExp(r'"[^"]*"'), '')
    .replaceAll(RegExp(r'\\.'), '')
    .replaceAll(RegExp(r'\[[^\]]*\]'), '');

/// Formats one numeric section: `0` / `#` / `?` digits, `,` grouping and
/// thousands scaling, `.` decimals, `%`, and literal prefix / suffix text.
String _formatNumberSection(double n, String code) {
  final StringBuffer literal = StringBuffer();
  final StringBuffer pattern = StringBuffer();
  var prefix = '';
  var inPattern = false;
  var patternDone = false;
  var percent = false;
  var i = 0;
  void emit(String text) {
    if (patternDone || inPattern) {
      literal.write(text);
      patternDone = true;
      inPattern = false;
    } else {
      prefix += text;
    }
  }

  while (i < code.length) {
    final String ch = code[i];
    if (ch == '"') {
      final int end = code.indexOf('"', i + 1);
      emit(code.substring(i + 1, end < 0 ? code.length : end));
      i = end < 0 ? code.length : end + 1;
    } else if (ch == r'\' && i + 1 < code.length) {
      emit(code[i + 1]);
      i += 2;
    } else if (ch == '[') {
      final int end = code.indexOf(']', i + 1);
      final String inner = code.substring(i + 1, end < 0 ? code.length : end);
      if (inner.startsWith(r'$')) {
        final int dash = inner.indexOf('-');
        emit(inner.substring(1, dash < 0 ? inner.length : dash));
      }
      i = end < 0 ? code.length : end + 1;
    } else if (ch == '_' && i + 1 < code.length) {
      emit(' ');
      i += 2;
    } else if (ch == '*' && i + 1 < code.length) {
      i += 2;
    } else if (!patternDone && '0#?,.'.contains(ch)) {
      inPattern = true;
      pattern.write(ch);
      i++;
    } else {
      if (ch == '%') {
        percent = true;
      }
      emit(ch);
      i++;
    }
  }
  final String suffix = literal.toString();
  final String digits = pattern.toString();
  if (digits.isEmpty) {
    final String text = '$prefix$suffix';
    return text.trim().isEmpty ? _plainNumber(n) : text;
  }
  final int dot = digits.indexOf('.');
  var integerPart = dot < 0 ? digits : digits.substring(0, dot);
  final String fraction = dot < 0 ? '' : digits.substring(dot + 1);
  var scale = 1.0;
  while (integerPart.endsWith(',')) {
    scale *= 1000;
    integerPart = integerPart.substring(0, integerPart.length - 1);
  }
  final bool group = integerPart.contains(',');
  final int minInteger = '0'.allMatches(integerPart).length;
  final int fixed = '0'.allMatches(fraction).length;
  final int optional = fraction.length - fixed;
  var value = (percent ? n * 100 : n) / scale;
  final bool negative = value < 0;
  value = value.abs();
  var text = value.toStringAsFixed(fixed + optional);
  if (optional > 0 && text.contains('.')) {
    var end = text.length;
    final int minEnd = text.indexOf('.') + 1 + fixed;
    while (end > minEnd && text[end - 1] == '0') {
      end--;
    }
    text = text.substring(0, end);
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
  }
  final int point = text.indexOf('.');
  var whole = point < 0 ? text : text.substring(0, point);
  final String decimals = point < 0 ? '' : text.substring(point);
  if (whole == '0' && minInteger == 0) {
    whole = '';
  }
  whole = whole.padLeft(minInteger, '0');
  if (group && whole.length > 3) {
    final StringBuffer grouped = StringBuffer();
    final int head = whole.length % 3;
    grouped.write(whole.substring(0, head));
    for (var g = head; g < whole.length; g += 3) {
      if (grouped.isNotEmpty) {
        grouped.write(',');
      }
      grouped.write(whole.substring(g, g + 3));
    }
    whole = grouped.toString();
  }
  final bool isZero = RegExp(r'^[0.,]*$').hasMatch('$whole$decimals');
  final String sign = negative && !isZero ? '-' : '';
  return '$sign$prefix$whole$decimals$suffix';
}

String _plainNumber(double n) =>
    n == n.roundToDouble() ? '${n.round()}' : n.toString();

bool _isDateFormat(String code) {
  final String c = code.toLowerCase();
  return c.contains('yy') ||
      c.contains('mmm') ||
      c.contains('dd') ||
      c.contains('d-m') ||
      c.contains('mm-');
}

/// Excel 1900-date-system serial → UTC date (leap-year bug included).
DateTime excelSerialToDate(double serial) {
  final int days = serial.floor();
  final int ms = ((serial - days) * 86400000).round();
  return DateTime.utc(1899, 12, 30).add(Duration(days: days, milliseconds: ms));
}

/// formatExcelDate API.
String formatExcelDate(DateTime dt, String code) {
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String pad(int value, int width) => value.toString().padLeft(width, '0');
  final String month = months[dt.month - 1];
  var out = code;
  out = out.replaceAll('yyyy', '${dt.year}');
  out = out.replaceAll('yy', pad(dt.year % 100, 2));
  out = out.replaceAll('mmm', month);
  out = out.replaceAll('mm', pad(dt.month, 2));
  out = out.replaceAll('dd', pad(dt.day, 2));
  out = out.replaceAll('d', '${dt.day}');
  return out;
}

const Map<int, String> _builtIn = <int, String>{
  0: 'General',
  1: '0',
  2: '0.00',
  3: '#,##0',
  4: '#,##0.00',
  9: '0%',
  10: '0.00%',
  14: 'mm-dd-yy',
  15: 'd-mmm-yy',
  16: 'd-mmm',
  17: 'mmm-yy',
  164: '"\$"#,##0.00',
};

const List<String> _officeTheme = <String>[
  '000000',
  'FFFFFF',
  '1F497D',
  'EEECE1',
  '4F81BD',
  'C0504D',
  '9BBB59',
  '8064A2',
  '4BACC6',
  'F79646',
  '0000FF',
  '800080',
];

const List<String> _indexed = <String>[
  '000000',
  'FFFFFF',
  'FF0000',
  '00FF00',
  '0000FF',
  'FFFF00',
  'FF00FF',
  '00FFFF',
  '000000',
  'FFFFFF',
  'FF0000',
  '00FF00',
  '0000FF',
  'FFFF00',
  'FF00FF',
  '00FFFF',
  '800000',
  '008000',
  '000080',
  '808000',
  '800080',
  '008080',
  'C0C0C0',
  '808080',
  '9999FF',
  '993366',
  'FFFFCC',
  'CCFFFF',
  '660066',
  'FF8080',
  '0066CC',
  'CCCCFF',
  '000080',
  'FF00FF',
  'FFFF00',
  '00FFFF',
  '800080',
  '800000',
  '008080',
  '0000FF',
  '00CCFF',
  'CCFFFF',
  'CCFFCC',
  'FFFF99',
  '99CCFF',
  'FF99CC',
  'CC99FF',
  'FFCC99',
  '3366FF',
  '33CCCC',
  '99CC00',
  'FFCC00',
  'FF9900',
  'FF6600',
  '666699',
  '969696',
  '003366',
  '339966',
  '003300',
  '333300',
  '993300',
  '993366',
  '333399',
  '333333',
];
