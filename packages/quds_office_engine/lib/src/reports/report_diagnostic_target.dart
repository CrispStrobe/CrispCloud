import 'report_template.dart';
import 'report_xml.dart';

/// Part of a report a [ReportDiagnostic] points at.
enum ReportDiagnosticPlace {
  /// The file as a whole (malformed XML, wrong root).
  file,

  /// Page setup, margins, fonts, colors (`Settings/…`).
  settings,

  /// A template variable.
  variable,

  /// A data schema table or field list.
  dataTable,

  /// A column of a data schema table, or a field.
  dataColumn,

  /// The band list as a whole.
  bands,

  /// One band.
  band,

  /// One element of a band.
  element,
}

/// Broad nature of a [ReportDiagnostic], for grouping and explaining it.
enum ReportDiagnosticKind {
  /// The file cannot be read as a report.
  file,

  /// An expression or `{{…}}` placeholder does not parse.
  expression,

  /// An expression calls a function the engine does not know.
  unknownFunction,

  /// Size or position: overlaps, overflow, no room on the page.
  layout,

  /// Something required is missing (a name, a size, a value).
  missing,

  /// A name is used more than once.
  duplicate,

  /// A value has the wrong form (number, color, page size, type).
  invalidValue,

  /// Bands, data sets, and tables that do not fit together.
  structure,

  /// Markup the engine does not know; it was ignored or kept as-is.
  unsupported,
}

/// Where in a template a [ReportDiagnostic] points, parsed from its
/// [ReportDiagnostic.path] (`Bands/Detail/Text[2]@visibleWhen`,
/// `Variables/total`, `DataSchema/items/amount`, …).
///
/// Paths from [QudsReportXmlParser] and from `QudsReportEngine.validate`
/// parse to the same target.
class ReportDiagnosticTarget {
  /// ReportDiagnosticTarget API.
  const ReportDiagnosticTarget({
    required this.place,
    this.band,
    this.element,
    this.part,
    this.partIndex,
    this.attribute,
    this.name,
    this.column,
  });

  /// What kind of thing the diagnostic is about.
  final ReportDiagnosticPlace place;

  /// The band, for [ReportDiagnosticPlace.band] and
  /// [ReportDiagnosticPlace.element].
  final ReportBandKind? band;

  /// Index of the element in its band's `elements`.
  final int? element;

  /// Sub-part of the element: `Column`, `Cell`, `FooterCell`, `Series`, or
  /// `Point`.
  final String? part;

  /// Index of [part].
  final int? partIndex;

  /// Attribute of the element, band, or part (`visibleWhen`, `dataSet`,
  /// `value`, …).
  final String? attribute;

  /// Variable or data table name ('' for the field list), or the settings
  /// section (`Page`, `Margins`, …).
  final String? name;

  /// Data column or field name.
  final String? column;

  static final RegExp _indexed = RegExp(r'^(.*?)\[([^\]]*)\]$');
  static final RegExp _element = RegExp(r'^(.+?)\[(\d+)\](?: \(\w+\))?(.*)$');

  /// Parses a diagnostic path. Unknown shapes point at the file.
  static ReportDiagnosticTarget parse(String path) {
    final String p = path.trim();
    if (p.startsWith('Settings')) {
      final List<String> parts = p.split('/');
      return ReportDiagnosticTarget(
        place: ReportDiagnosticPlace.settings,
        name: parts.length > 1 ? parts[1] : null,
      );
    }
    if (p.startsWith('Variables/')) {
      final String rest = p.substring('Variables/'.length);
      final RegExpMatch? m = _indexed.firstMatch(rest);
      final String? name = m == null ? rest : m.group(2);
      return ReportDiagnosticTarget(
        place: ReportDiagnosticPlace.variable,
        name: name == null || name.isEmpty || name == 'Variable' ? null : name,
      );
    }
    if (p == 'Variables') {
      return const ReportDiagnosticTarget(
        place: ReportDiagnosticPlace.variable,
      );
    }
    if (p.startsWith('DataSchema')) {
      return _data(p.split('/').skip(1).toList());
    }
    if (p == 'Bands' || p == 'QudsReport') {
      return ReportDiagnosticTarget(
        place: p == 'Bands'
            ? ReportDiagnosticPlace.bands
            : ReportDiagnosticPlace.file,
      );
    }
    if (p.startsWith('Bands/')) {
      return _band(p.substring('Bands/'.length));
    }
    return const ReportDiagnosticTarget(place: ReportDiagnosticPlace.file);
  }

  static ReportDiagnosticTarget _data(List<String> parts) {
    if (parts.isEmpty) {
      return const ReportDiagnosticTarget(
        place: ReportDiagnosticPlace.dataTable,
      );
    }
    String? unwrap(String s, {required bool parser}) {
      final RegExpMatch? m = _indexed.firstMatch(s);
      if (m != null) {
        return m.group(2);
      }
      return parser ? null : s;
    }

    final bool parser =
        _indexed.hasMatch(parts.first) ||
        const <String>{'Table', 'DataSet', 'Field'}.contains(parts.first);
    final String head =
        _indexed.firstMatch(parts.first)?.group(1) ?? parts.first;
    if (parser && head == 'Field') {
      return ReportDiagnosticTarget(
        place: ReportDiagnosticPlace.dataColumn,
        name: '',
        column: unwrap(parts.first, parser: true),
      );
    }
    final String? table = unwrap(parts.first, parser: parser);
    if (parts.length < 2) {
      return ReportDiagnosticTarget(
        place: ReportDiagnosticPlace.dataTable,
        name: table,
      );
    }
    final String? column = unwrap(parts[1], parser: parser);
    return ReportDiagnosticTarget(
      place: column == null
          ? ReportDiagnosticPlace.dataTable
          : ReportDiagnosticPlace.dataColumn,
      name: table,
      column: column,
    );
  }

  static ReportDiagnosticTarget _band(String rest) {
    final int slash = rest.indexOf('/');
    final String head = slash < 0 ? rest : rest.substring(0, slash);
    final int at = head.indexOf('@');
    final String kindName = at < 0 ? head : head.substring(0, at);
    final ReportBandKind? kind = ReportBandKind.fromXml(kindName);
    if (kind == null) {
      return const ReportDiagnosticTarget(place: ReportDiagnosticPlace.bands);
    }
    if (slash < 0) {
      return ReportDiagnosticTarget(
        place: ReportDiagnosticPlace.band,
        band: kind,
        attribute: at < 0 ? null : head.substring(at + 1),
      );
    }
    final RegExpMatch? m = _element.firstMatch(rest.substring(slash + 1));
    if (m == null) {
      return ReportDiagnosticTarget(
        place: ReportDiagnosticPlace.band,
        band: kind,
      );
    }
    final int index = int.parse(m.group(2)!);
    String tail = m.group(3)!;
    String? attribute;
    final int tailAt = tail.lastIndexOf('@');
    if (tailAt >= 0) {
      attribute = tail.substring(tailAt + 1);
      tail = tail.substring(0, tailAt);
    }
    String? part;
    int? partIndex;
    final List<String> segments = tail
        .split('/')
        .where((String s) => s.isNotEmpty)
        .toList();
    if (segments.isNotEmpty) {
      final RegExpMatch? pm = _indexed.firstMatch(segments.last);
      final String name = pm?.group(1) ?? segments.last;
      partIndex = int.tryParse(pm?.group(2) ?? '');
      final bool footer = segments.any(
        (String s) => s.toLowerCase().contains('footer'),
      );
      part = switch (name) {
        'Cell' ||
        'FooterCell' when footer || name == 'FooterCell' => 'FooterCell',
        'Cell' => 'Cell',
        'Column' => 'Column',
        'Series' => 'Series',
        'Point' => 'Point',
        _ => null,
      };
      if (part == null) {
        partIndex = null;
      }
    }
    return ReportDiagnosticTarget(
      place: ReportDiagnosticPlace.element,
      band: kind,
      element: index,
      part: part,
      partIndex: partIndex,
      attribute: attribute,
    );
  }

  /// Identity of the target, for telling two findings about the same spot
  /// apart from two about different spots.
  String get key =>
      '${place.name}|${band?.name}|$element|$part|$partIndex|$attribute|'
      '$name|$column';

  /// The nature of a finding with [message] at [path].
  static ReportDiagnosticKind kindOf(String path, String message) {
    final String m = message.trim();
    bool has(String s) => m.contains(s);
    if (path.trim().isEmpty ||
        m.startsWith('Malformed XML') ||
        m.startsWith('Empty document') ||
        m.startsWith('Root element')) {
      return ReportDiagnosticKind.file;
    }
    if (has('Unknown function')) {
      return ReportDiagnosticKind.unknownFunction;
    }
    if (m.startsWith('ReportExpressionException')) {
      return ReportDiagnosticKind.expression;
    }
    if (has('Duplicate') || has('more than once')) {
      return ReportDiagnosticKind.duplicate;
    }
    if (has('Extends ') ||
        has('taller than') ||
        has('no room') ||
        has('no printable area') ||
        has('must not be negative') ||
        has('needs width and height') ||
        has('remaining line width')) {
      return ReportDiagnosticKind.layout;
    }
    if (has('ignored') ||
        has('kept as-is') ||
        m.startsWith('Unknown element') ||
        m.startsWith('Unknown band') ||
        m.startsWith('Unknown attribute')) {
      return ReportDiagnosticKind.unsupported;
    }
    if (m.startsWith('Invalid') ||
        m.startsWith('Unknown color') ||
        m.startsWith('Unknown pageSize') ||
        m.startsWith('Unknown variable type') ||
        m.startsWith('Unknown data type') ||
        has('is not a ') ||
        m.startsWith('Variable names are')) {
      return ReportDiagnosticKind.invalidValue;
    }
    if (has('()')) {
      return ReportDiagnosticKind.expression;
    }
    if (has('Detail') ||
        has('dataSet') ||
        has('<Bands>') ||
        has(' cells for ')) {
      return ReportDiagnosticKind.structure;
    }
    if (has('needs') ||
        has('has no') ||
        has('is empty') ||
        m.startsWith('No ')) {
      return ReportDiagnosticKind.missing;
    }
    return ReportDiagnosticKind.expression;
  }
}
