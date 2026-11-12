import '../xml/namespaces.dart';
import '../xml/xml_node.dart';
import '../xml/xml_reader.dart';

/// The geometry of a DrawingML outline, independent of any canvas toolkit.
///
/// Color and fill ownership stay with the shape. This is a read-only view of
/// preserved native XML; reading it never normalizes or rewrites that XML.
class DrawingLineStyle {
  const DrawingLineStyle({
    this.widthPoints = 1,
    this.cap = DrawingLineCap.square,
    this.join = DrawingLineJoin.miter,
    this.miterLimit = 4,
    this.inset = false,
    this.dashLengths = const [],
    this.capsIncludedInDash = true,
  });

  final double widthPoints;
  final DrawingLineCap cap;
  final DrawingLineJoin join;
  final double miterLimit;
  final bool inset;

  /// Alternating dash and space lengths, measured in multiples of line width.
  final List<double> dashLengths;

  /// Office includes round caps in both dash forms, and square caps in presets.
  /// Custom square-cap dashes instead extend past the specified dash length.
  final bool capsIncludedInDash;

  /// Reads explicit native width, preset/custom dashes, caps, joins and inset.
  ///
  /// The caller supplies its existing visual fallback for an omitted width.
  /// Theme inheritance, compound strokes and non-solid fills are not resolved
  /// here. Foreign namespaces and malformed properties cannot inject styles.
  static DrawingLineStyle fromXml(String? source, {double fallbackWidth = 1}) {
    final fallback = DrawingLineStyle(widthPoints: fallbackWidth);
    if (source == null || source.isEmpty) return fallback;
    final XmlElement? line;
    try {
      if (!_wellFormed(source)) return fallback;
      line = XmlDocument.parse(source).root;
    } on XmlParseException {
      return fallback;
    } on RangeError {
      return fallback;
    }
    if (line == null || line.localName != 'ln' || !_drawing(line)) {
      return fallback;
    }
    String? attr(String name) => line!.getAttribute(name, namespaceUri: '');
    final nativeWidth = int.tryParse(attr('w') ?? '');
    final width = nativeWidth != null && nativeWidth >= 0
        ? nativeWidth / 12700
        : fallbackWidth;
    final cap = switch (attr('cap')) {
      'flat' => DrawingLineCap.flat,
      'rnd' => DrawingLineCap.round,
      _ => DrawingLineCap.square,
    };
    final children = line.children.whereType<XmlElement>().where(_drawing);
    var join = DrawingLineJoin.miter;
    var miterLimit = 4.0;
    var dashes = const <double>[];
    var custom = false;
    for (final child in children) {
      switch (child.localName) {
        case 'round':
          join = DrawingLineJoin.round;
        case 'bevel':
          join = DrawingLineJoin.bevel;
        case 'miter':
          join = DrawingLineJoin.miter;
          miterLimit =
              _percentage(child.getAttribute('lim', namespaceUri: '')) ?? 4;
        case 'prstDash':
          dashes =
              _presetDashes[child.getAttribute('val', namespaceUri: '')] ??
              const [];
          custom = false;
        case 'custDash':
          final values = <double>[];
          var valid = true;
          for (final stop in child.children.whereType<XmlElement>()) {
            if (!_drawing(stop) || stop.localName != 'ds') continue;
            final dash = _percentage(stop.getAttribute('d', namespaceUri: ''));
            final space = _percentage(
              stop.getAttribute('sp', namespaceUri: ''),
            );
            if (dash == null || space == null || dash + space <= 0) {
              valid = false;
              break;
            }
            values.addAll([dash, space]);
          }
          dashes = valid ? List<double>.unmodifiable(values) : const [];
          custom = true;
      }
    }
    return DrawingLineStyle(
      widthPoints: width,
      cap: cap,
      join: join,
      miterLimit: miterLimit,
      inset: attr('algn') == 'in',
      dashLengths: dashes,
      capsIncludedInDash: !custom || cap == DrawingLineCap.round,
    );
  }

  static bool _drawing(XmlElement element) =>
      element.namespaceUri == OfficeNamespaces.a ||
      element.namespaceUri == 'http://purl.oclc.org/ooxml/drawingml/main';

  static bool _wellFormed(String source) {
    final reader = XmlPullReader(source);
    final stack = <String>[];
    var roots = 0;
    while (reader.next()) {
      switch (reader.eventType) {
        case XmlEventType.startElement:
          if (stack.isEmpty && ++roots > 1) return false;
          stack.add(reader.qualifiedName);
        case XmlEventType.endElement:
          if (stack.isEmpty || stack.removeLast() != reader.qualifiedName) {
            return false;
          }
        case XmlEventType.dtd:
          return false;
        case XmlEventType.characters:
        case XmlEventType.cdata:
          if (stack.isEmpty && !reader.isWhitespace) return false;
        default:
          break;
      }
    }
    return roots == 1 && stack.isEmpty;
  }

  static double? _percentage(String? value) {
    if (value == null) return null;
    final raw = value.endsWith('%')
        ? double.tryParse(value.substring(0, value.length - 1))
        : double.tryParse(value);
    if (raw == null || !raw.isFinite || raw < 0) return null;
    return raw / (value.endsWith('%') ? 100 : 100000);
  }

  // DrawingML preset proportions, also used by LibreOffice's native importer:
  // oox/source/drawingml/lineproperties.cxx (lclConvertPresetDash).
  static const _presetDashes = <String, List<double>>{
    'solid': [],
    'dot': [1, 3],
    'dash': [4, 3],
    'dashDot': [4, 3, 1, 3],
    'lgDash': [8, 3],
    'lgDashDot': [8, 3, 1, 3],
    'lgDashDotDot': [8, 3, 1, 3, 1, 3],
    'sysDot': [1, 1],
    'sysDash': [3, 1],
    'sysDashDot': [3, 1, 1, 1],
    'sysDashDotDot': [3, 1, 1, 1, 1, 1],
  };
}

enum DrawingLineCap { flat, round, square }

enum DrawingLineJoin { miter, round, bevel }
