/// `.qrep` XML parsing, validation, and serialization.
library;

import '../xml/xml_node.dart';
import '../xml/xml_reader.dart';
import 'report_data.dart';
import 'report_diagnostic_target.dart';
import 'report_expression.dart';
import 'report_format.dart';
import 'report_template.dart';
import 'report_units.dart';

/// Severity of a [ReportDiagnostic].
enum ReportDiagnosticSeverity { error, warning }

/// One validation finding with a template path (`Bands/Detail/Table[0]`).
class ReportDiagnostic {
  /// ReportDiagnostic API.
  const ReportDiagnostic(this.severity, this.path, this.message);

  /// severity API.
  final ReportDiagnosticSeverity severity;

  /// path API.
  final String path;

  /// message API.
  final String message;

  /// isError API.
  bool get isError => severity == ReportDiagnosticSeverity.error;

  /// Where in the template [path] points.
  ReportDiagnosticTarget get target => ReportDiagnosticTarget.parse(path);

  /// The nature of the finding.
  ReportDiagnosticKind get kind => ReportDiagnosticTarget.kindOf(path, message);

  /// [message] without the exception class name parser messages start with.
  String get summary {
    const String prefix = 'ReportExpressionException: ';
    return message.startsWith(prefix)
        ? message.substring(prefix.length)
        : message;
  }

  @override
  String toString() => '${isError ? 'error' : 'warning'}: $path: $message';
}

/// Thrown when a template has validation errors.
class ReportTemplateException implements Exception {
  /// ReportTemplateException API.
  const ReportTemplateException(this.diagnostics);

  /// All findings (errors and warnings).
  final List<ReportDiagnostic> diagnostics;

  /// Errors only.
  Iterable<ReportDiagnostic> get errors =>
      diagnostics.where((ReportDiagnostic d) => d.isError);

  @override
  String toString() =>
      'ReportTemplateException:\n${errors.map((ReportDiagnostic d) => '  $d').join('\n')}';
}

/// Parse output: the template (best effort) plus diagnostics.
class ReportParseResult {
  /// ReportParseResult API.
  const ReportParseResult(
    this.template,
    this.diagnostics, {
    this.readable = true,
  });

  /// template API.
  final ReportTemplate template;

  /// diagnostics API.
  final List<ReportDiagnostic> diagnostics;

  /// False when the XML could not be read at all (malformed, empty, or not
  /// `<QudsReport>`), so [template] is empty. When true, [template] holds
  /// everything that parsed, even if [diagnostics] has errors, and a
  /// designer can open it and show those errors.
  final bool readable;

  /// hasErrors API.
  bool get hasErrors => diagnostics.any((ReportDiagnostic d) => d.isError);

  /// Template, or throws [ReportTemplateException] when there are errors.
  ReportTemplate get templateOrThrow {
    if (hasErrors) {
      throw ReportTemplateException(diagnostics);
    }
    return template;
  }
}

/// Reads `<QudsReport>` XML into a [ReportTemplate].
///
/// Attribute names accept common aliases (`align`/`alignment`,
/// `dataset`/`dataSet`, `backColor`/`background`) so hand-written templates
/// are forgiving, while values (lengths, colors, enums, expressions) are
/// validated strictly.
class QudsReportXmlParser {
  /// QudsReportXmlParser API.
  QudsReportXmlParser();

  final List<ReportDiagnostic> _diag = <ReportDiagnostic>[];
  ReportUnit _unit = ReportUnit.mm;
  late ReportTemplate _template;

  /// Parses [xml]. Never throws for template problems — see diagnostics.
  ReportParseResult parse(String xml) {
    _diag.clear();
    _template = ReportTemplate();
    final XmlElement? root;
    try {
      root = XmlDocument.parse(xml).root;
    } on XmlParseException catch (e) {
      _error('', 'Malformed XML: ${e.message} (${_lineCol(xml, e.position)})');
      return _unreadable();
    } on FormatException catch (e) {
      _error('', 'Malformed XML: ${e.message}');
      return _unreadable();
    }
    if (root == null) {
      _error('', 'Empty document');
      return _unreadable();
    }
    if (root.localName != 'QudsReport') {
      _error(root.localName, 'Root element must be <QudsReport>');
      return _unreadable();
    }
    _readRoot(root);
    _validate();
    return ReportParseResult(_template, List<ReportDiagnostic>.of(_diag));
  }

  ReportParseResult _unreadable() => ReportParseResult(
    _template,
    List<ReportDiagnostic>.of(_diag),
    readable: false,
  );

  static String _lineCol(String text, int offset) {
    var line = 1;
    var col = 1;
    final int end = offset.clamp(0, text.length);
    for (int i = 0; i < end; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        line++;
        col = 1;
      } else {
        col++;
      }
    }
    return 'line $line, column $col';
  }

  void _error(String path, String message) => _diag.add(
    ReportDiagnostic(ReportDiagnosticSeverity.error, path, message),
  );

  void _warn(String path, String message) => _diag.add(
    ReportDiagnostic(ReportDiagnosticSeverity.warning, path, message),
  );

  static String? _attr(XmlElement e, List<String> names) {
    for (final String n in names) {
      final String? v = e.getAttribute(n);
      if (v != null) {
        return v;
      }
    }
    final Set<String> lower = <String>{
      for (final String n in names) n.toLowerCase(),
    };
    for (final XmlAttribute a in e.attributes) {
      if (lower.contains(a.localName.toLowerCase())) {
        return a.value;
      }
    }
    return null;
  }

  void _readTextStyle(
    ReportTextStyle style,
    XmlElement e,
    List<String> family,
    List<String> size,
    List<String> bold,
    List<String> italic,
    List<String> color,
    String path,
  ) {
    style.fontFamily = _attr(e, family);
    style.fontSize = _num(e, size, path);
    style.bold = _bool(e, bold, path);
    style.italic = _bool(e, italic, path);
    style.color = _color(e, color, path);
  }

  bool? _bool(XmlElement e, List<String> names, String path) {
    final String? raw = _attr(e, names);
    if (raw == null) {
      return null;
    }
    switch (raw.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'on':
        return true;
      case 'false':
      case '0':
      case 'no':
      case 'off':
        return false;
    }
    _error(path, 'Invalid boolean ${names.first}="$raw"');
    return null;
  }

  double? _len(
    XmlElement e,
    List<String> names,
    String path, {
    ReportUnit? unit,
  }) {
    final String? raw = _attr(e, names);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final double? v = ReportUnits.tryParse(raw, defaultUnit: unit ?? _unit);
    if (v == null) {
      _error(path, 'Invalid length ${names.first}="$raw"');
    }
    return v;
  }

  double? _num(XmlElement e, List<String> names, String path) {
    final String? raw = _attr(e, names);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final double? v = ReportUnits.tryParse(raw, defaultUnit: ReportUnit.pt);
    if (v == null) {
      _error(path, 'Invalid number ${names.first}="$raw"');
    }
    return v;
  }

  T? _enum<T extends Enum>(
    XmlElement e,
    List<String> names,
    List<T> values,
    String path, {
    Map<String, T> aliases = const <Never, Never>{},
  }) {
    final String? raw = _attr(e, names);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final T? alias = aliases[raw.trim().toLowerCase()];
    if (alias != null) {
      return alias;
    }
    final T? v = reportEnumByName(values, raw);
    if (v == null) {
      _error(
        path,
        'Invalid ${names.first}="$raw" (expected ${values.map((T x) => x.name).join(', ')})',
      );
    }
    return v;
  }

  String? _color(XmlElement e, List<String> names, String path) {
    final String? raw = _attr(e, names);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return raw.trim();
  }

  static const Map<String, ReportTextAlign> _alignAliases =
      <String, ReportTextAlign>{
        'centre': ReportTextAlign.center,
        'middle': ReportTextAlign.center,
        'leading': ReportTextAlign.start,
        'trailing': ReportTextAlign.end,
        'justified': ReportTextAlign.justify,
      };

  static const Map<String, ReportVerticalAlign> _vAlignAliases =
      <String, ReportVerticalAlign>{
        'center': ReportVerticalAlign.middle,
        'centre': ReportVerticalAlign.middle,
      };

  static String normalizeContent(String raw) {
    final List<String> lines = raw.replaceAll('\r\n', '\n').split('\n');
    final List<String> trimmed = <String>[
      for (final String l in lines) l.trim(),
    ];
    var start = 0;
    var end = trimmed.length;
    while (start < end && trimmed[start].isEmpty) {
      start++;
    }
    while (end > start && trimmed[end - 1].isEmpty) {
      end--;
    }
    return trimmed.sublist(start, end).join('\n');
  }

  static String _content(XmlElement e) {
    final StringBuffer b = StringBuffer();
    for (final XmlNode n in e.children) {
      if (n is XmlText) {
        b.write(n.text);
      } else if (n is XmlCdata) {
        b.write(n.text);
      }
    }
    return normalizeContent(b.toString());
  }

  void _readRoot(XmlElement root) {
    final ReportTemplate t = _template;
    final ReportUnit? unit = _enum(
      root,
      const <String>['unit', 'units'],
      ReportUnit.values,
      'QudsReport',
      aliases: const <String, ReportUnit>{
        'millimeter': ReportUnit.mm,
        'millimetre': ReportUnit.mm,
        'point': ReportUnit.pt,
        'points': ReportUnit.pt,
        'in': ReportUnit.inch,
        'pixel': ReportUnit.px,
      },
    );
    if (unit != null) {
      _unit = unit;
      t.unit = unit;
    }
    t.name = _attr(root, const <String>['name', 'title']) ?? 'Report';
    final String? dir = _attr(root, const <String>['direction', 'dir']);
    t.isRtl =
        _bool(root, const <String>[
          'isRtl',
          'rtl',
          'rightToLeft',
        ], 'QudsReport') ??
        (dir != null && dir.trim().toLowerCase() == 'rtl');
    _readPage(root, 'QudsReport');
    t.defaultFont =
        _attr(root, const <String>['defaultFont', 'font', 'fontFamily']) ?? '';
    t.defaultFontSize =
        _num(root, const <String>[
          'defaultFontSize',
          'fontSize',
        ], 'QudsReport') ??
        10;
    t.coordinateOrigin =
        _enum(
          root,
          const <String>['coordinateOrigin', 'origin'],
          ReportCoordinateOrigin.values,
          'QudsReport',
        ) ??
        ReportCoordinateOrigin.page;
    t.mirrorRtl =
        _bool(root, const <String>[
          'mirrorRtl',
          'mirrorLayout',
        ], 'QudsReport') ??
        true;
    const Set<String> known = <String>{
      'mirrorrtl',
      'mirrorlayout',
      'name',
      'title',
      'isrtl',
      'rtl',
      'righttoleft',
      'direction',
      'dir',
      'pagesize',
      'size',
      'orientation',
      'pagewidth',
      'pageheight',
      'defaultfont',
      'font',
      'fontfamily',
      'defaultfontsize',
      'fontsize',
      'unit',
      'units',
      'coordinateorigin',
      'origin',
    };
    for (final XmlAttribute a in root.attributes) {
      if (!known.contains(a.localName.toLowerCase()) && a.prefix.isEmpty) {
        t.extraAttributes[a.localName] = a.value;
      }
    }

    var sawBands = false;
    for (final XmlElement child in root.childElements) {
      switch (child.localName) {
        case 'Settings':
          _readSettings(child);
        case 'Variables':
          _readVariables(child);
        case 'DataSchema' || 'Data':
          _readDataSchema(child);
        case 'Bands':
          sawBands = true;
          _readBands(child);
        default:
          final ReportBandKind? kind = ReportBandKind.fromXml(child.localName);
          if (kind != null) {
            _warn(child.localName, 'Band outside <Bands>; accepted');
            _readBand(child, kind, section: 0);
          } else {
            _warn(child.localName, 'Unknown element ignored');
          }
      }
    }
    if (!sawBands && t.bands.isEmpty) {
      _warn('QudsReport', 'No <Bands> section');
    }
    t.sortBands();
  }

  void _readPage(XmlElement e, String path) {
    final ReportTemplate t = _template;
    final bool isRoot = e.localName == 'QudsReport';
    final String? size = _attr(e, const <String>['pageSize', 'size']);
    final double? w = _len(
      e,
      isRoot
          ? const <String>['pageWidth']
          : const <String>['pageWidth', 'width'],
      path,
    );
    final double? h = _len(
      e,
      isRoot
          ? const <String>['pageHeight']
          : const <String>['pageHeight', 'height'],
      path,
    );
    final bool custom = size == null || size.trim().toLowerCase() == 'custom';
    if (!custom) {
      final ReportPageSize? named = ReportPageSize.byName(size);
      if (named == null) {
        _error(path, 'Unknown pageSize="$size"');
      } else {
        t.pageSize = named;
      }
    } else if (w != null && h != null) {
      t.pageSize = ReportPageSize('Custom', w, h);
    } else if (size != null) {
      _error(path, 'pageSize="Custom" needs pageWidth and pageHeight');
    }
    final ReportOrientation? o = _enum(
      e,
      const <String>['orientation'],
      ReportOrientation.values,
      path,
    );
    if (o != null) {
      t.orientation = o;
    }
  }

  void _readSettings(XmlElement settings) {
    final ReportTemplate t = _template;
    for (final XmlElement s in settings.childElements) {
      final String path = 'Settings/${s.localName}';
      switch (s.localName) {
        case 'Margins':
          final double? all = _len(s, const <String>['all'], path);
          if (all != null) {
            t.margins
              ..top = all
              ..bottom = all
              ..left = all
              ..right = all;
          }
          t.margins.top = _len(s, const <String>['top'], path) ?? t.margins.top;
          t.margins.bottom =
              _len(s, const <String>['bottom'], path) ?? t.margins.bottom;
          t.margins.left =
              _len(s, const <String>['left'], path) ?? t.margins.left;
          t.margins.right =
              _len(s, const <String>['right'], path) ?? t.margins.right;
        case 'Colors':
          for (final XmlAttribute a in s.attributes) {
            if (ReportColor.tryParse(a.value) == null) {
              _error(path, 'Invalid color ${a.localName}="${a.value}"');
            }
            t.colors[a.localName] = a.value.trim();
          }
          for (final XmlElement c in s.childElements) {
            final String? name = _attr(c, const <String>['name']);
            final String? value = _attr(c, const <String>['value', 'color']);
            if (name == null || value == null) {
              _error('$path/${c.localName}', 'Color needs name and value');
              continue;
            }
            if (ReportColor.tryParse(value) == null) {
              _error(path, 'Invalid color $name="$value"');
            }
            t.colors[name] = value.trim();
          }
        case 'Formats':
          ReportFormatDefaults f = t.formats;
          f = f.copyWith(
            datePattern: _attr(s, const <String>['date', 'datePattern']),
            timePattern: _attr(s, const <String>['time', 'timePattern']),
            dateTimePattern: _attr(s, const <String>[
              'dateTime',
              'dateTimePattern',
            ]),
            decimalSeparator: _attr(s, const <String>[
              'decimalSeparator',
              'decimal',
            ]),
            groupSeparator: _attr(s, const <String>[
              'groupSeparator',
              'thousands',
            ]),
            arabicDigits: _bool(s, const <String>['arabicDigits'], path),
          );
          t.formats = f;
        case 'Page':
          _readPage(s, path);
        default:
          _warn(path, 'Unknown setting ignored');
      }
    }
  }

  void _readVariables(XmlElement vars) {
    for (final XmlElement v in vars.childElements) {
      final String path = 'Variables/${v.localName}';
      if (v.localName != 'Var' && v.localName != 'Variable') {
        _warn(path, 'Unknown element ignored');
        continue;
      }
      final String? name = _attr(v, const <String>['name']);
      if (name == null || name.trim().isEmpty) {
        _error(path, 'Variable needs a name');
        continue;
      }
      final String? rawType = _attr(v, const <String>['type', 'dataType']);
      ReportVariableType type = rawType == null
          ? ReportVariableType.text
          : ReportVariableType.fromName(rawType) ?? ReportVariableType.text;
      if (rawType != null && ReportVariableType.fromName(rawType) == null) {
        _warn('$path[$name]', 'Unknown variable type "$rawType" (using text)');
      }
      final String? expr = _attr(v, const <String>['expression']);
      if (expr != null && rawType == null) {
        type = ReportVariableType.expression;
      }
      final String value =
          _attr(v, const <String>['value']) ?? expr ?? _content(v);
      final ReportVariable variable = ReportVariable(
        name: name.trim(),
        value: value,
        type: type,
        description: _attr(v, const <String>['description', 'label']) ?? '',
        format: _attr(v, const <String>['format']),
        prompt: _bool(v, const <String>['prompt', 'ask'], path) ?? false,
        required: _bool(v, const <String>['required'], path) ?? false,
      );
      switch (type) {
        case ReportVariableType.text:
          _checkTemplate(value, '$path[$name]');
        case ReportVariableType.expression:
          _checkExpression(value, '$path[$name]');
        case ReportVariableType.number:
        case ReportVariableType.boolean:
        case ReportVariableType.date:
        case ReportVariableType.list:
          final String? err = variable.error;
          if (err != null) {
            _error('$path[$name]', err);
          }
      }
      final String lower = name.trim().toLowerCase();
      if (!ReportVariable.isValidName(name.trim())) {
        _warn(
          '$path[$name]',
          'Variable names are letters, digits and _, optionally grouped '
              'with dots (stats.sum)',
        );
      }
      for (final ReportVariable o in _template.variables) {
        final String other = o.name.toLowerCase();
        if (other == lower) {
          _warn('$path[$name]', 'Duplicate variable name');
        } else if (other.startsWith('$lower.') || lower.startsWith('$other.')) {
          _warn(
            '$path[$name]',
            '"${o.name}" and "${name.trim()}" clash: a name cannot be both '
                'a variable and a folder',
          );
        }
      }
      _template.variables.add(variable);
    }
  }

  ReportDataType _dataType(XmlElement e, String path) {
    final String? raw = _attr(e, const <String>['type', 'dataType']);
    if (raw == null) {
      return ReportDataType.text;
    }
    final ReportDataType? type = ReportDataType.fromName(raw);
    if (type == null) {
      _warn(path, 'Unknown data type "$raw" (using text)');
    }
    return type ?? ReportDataType.text;
  }

  void _readDataSchema(XmlElement schema) {
    final ReportDataSchema s = _template.dataSchema;
    for (final XmlElement child in schema.childElements) {
      final String path = 'DataSchema/${child.localName}';
      final String? name = _attr(child, const <String>['name', 'path'])?.trim();
      switch (child.localName) {
        case 'Table' || 'DataSet':
          if (name == null || name.isEmpty) {
            _error(path, 'Table needs a name');
            continue;
          }
          if (s.table(name) != null) {
            _warn('$path[$name]', 'Duplicate table');
            continue;
          }
          final ReportDataTable table = ReportDataTable(
            name: name,
            description: _attr(child, const <String>['description']) ?? '',
          );
          for (final XmlElement c in child.childElements) {
            final String cp = '$path[$name]/${c.localName}';
            if (c.localName != 'Column' && c.localName != 'Field') {
              _warn(cp, 'Unknown element ignored');
              continue;
            }
            final String? col = _attr(c, const <String>['name'])?.trim();
            if (col == null || col.isEmpty) {
              _error(cp, 'Column needs a name');
              continue;
            }
            if (table.column(col) != null) {
              _warn('$cp[$col]', 'Duplicate column');
              continue;
            }
            final String? expr = _attr(c, const <String>[
              'expression',
              'formula',
            ]);
            if (expr != null && expr.trim().isNotEmpty) {
              _checkExpression(expr, '$cp[$col]');
            }
            table.columns.add(
              ReportDataColumn(
                name: col,
                type: _dataType(c, '$cp[$col]'),
                expression: expr == null || expr.trim().isEmpty ? null : expr,
                format: _attr(c, const <String>['format']),
                description: _attr(c, const <String>['description']) ?? '',
              ),
            );
          }
          s.tables.add(table);
        case 'Field':
          if (name == null || name.isEmpty) {
            _error(path, 'Field needs a name');
            continue;
          }
          if (s.field(name) != null) {
            _warn('$path[$name]', 'Duplicate field');
            continue;
          }
          s.fields.add(
            ReportDataField(
              name: name,
              type: _dataType(child, '$path[$name]'),
              description: _attr(child, const <String>['description']) ?? '',
            ),
          );
        default:
          _warn(path, 'Unknown element ignored');
      }
    }
  }

  void _readBands(XmlElement bands) {
    var nextSection = 0;
    for (final XmlElement b in bands.childElements) {
      if (b.localName == 'Section') {
        while (_template.bandIn(ReportBandKind.detail, nextSection) != null ||
            _template.bandIn(ReportBandKind.groupHeader, nextSection) !=
                null ||
            _template.bandIn(ReportBandKind.groupFooter, nextSection) !=
                null) {
          nextSection++;
        }
        _readSection(b, nextSection);
        nextSection++;
        continue;
      }
      final ReportBandKind? kind = ReportBandKind.fromXml(b.localName);
      if (kind == null) {
        _error('Bands/${b.localName}', 'Unknown band');
        continue;
      }
      _readBand(b, kind, section: 0);
    }
  }

  void _readSection(XmlElement section, int index) {
    final String path = 'Bands/Section[$index]';
    final String? dataSet = _attr(section, const <String>[
      'dataSet',
      'dataSource',
      'source',
    ]);
    var sawDetail = false;
    for (final XmlElement b in section.childElements) {
      final ReportBandKind? kind = ReportBandKind.fromXml(b.localName);
      if (kind == null ||
          (kind != ReportBandKind.groupHeader &&
              kind != ReportBandKind.detail &&
              kind != ReportBandKind.groupFooter)) {
        _warn('$path/${b.localName}', 'Ignored outside a data section');
        continue;
      }
      final ReportBand? band = _readBand(b, kind, section: index);
      if (band != null &&
          band.kind == ReportBandKind.detail &&
          band.dataSet == null &&
          dataSet != null) {
        band.dataSet = dataSet;
      }
      if (kind == ReportBandKind.detail) {
        sawDetail = true;
      }
    }
    if (!sawDetail) {
      _warn(path, 'Section has no Detail band');
    }
  }

  ReportBand? _readBand(XmlElement b, ReportBandKind kind, {required int section}) {
    final String path = 'Bands/${kind.xmlName}';
    final bool data =
        kind == ReportBandKind.groupHeader ||
        kind == ReportBandKind.detail ||
        kind == ReportBandKind.groupFooter;
    if (_template.bandIn(kind, data ? section : 0) != null) {
      _error(path, 'Duplicate ${kind.xmlName} band');
      return null;
    }
    final ReportBand band = ReportBand(kind: kind, section: data ? section : 0);
    band.height = _len(b, const <String>['height'], path) ?? 0;
    band.dataSet = _attr(b, const <String>['dataSet', 'dataSource', 'source']);
    band.rowHeight = _len(b, const <String>['rowHeight'], path);
    band.groupBy = _expr(
      _attr(b, const <String>['groupBy', 'group']),
      '$path@groupBy',
    );
    band.sortBy = _sortSpec(
      _attr(b, const <String>['sortBy', 'orderBy']),
      '$path@sortBy',
    );
    final String? order = _attr(b, const <String>['sortOrder', 'order']);
    band.sortDescending =
        _bool(b, const <String>['sortDescending', 'descending'], path) ??
        (order != null && order.trim().toLowerCase().startsWith('desc'));
    band.filter = _expr(
      _attr(b, const <String>['filter', 'where']),
      '$path@filter',
    );
    band.printOnFirstPage =
        _bool(b, const <String>['printOnFirstPage', 'onFirstPage'], path) ??
        true;
    band.printOnLastPage =
        _bool(b, const <String>['printOnLastPage', 'onLastPage'], path) ?? true;
    band.newPageBefore =
        _bool(b, const <String>[
          'newPageBefore',
          'pageBreakBefore',
          'newPage',
        ], path) ??
        false;
    band.newPageAfter =
        _bool(b, const <String>['newPageAfter', 'pageBreakAfter'], path) ??
        false;
    band.keepTogether = _bool(b, const <String>['keepTogether'], path) ?? false;
    band.repeatOnEveryPage =
        _bool(b, const <String>['repeatOnEveryPage', 'repeat'], path) ?? false;
    band.background = _color(b, const <String>[
      'background',
      'backColor',
    ], path);
    band.visibleWhen = _expr(
      _attr(b, const <String>['visibleWhen', 'visible', 'printWhen']),
      '$path@visibleWhen',
    );
    var index = 0;
    for (final XmlElement child in b.childElements) {
      final ReportElement? el = _readElement(
        child,
        '$path/${child.localName}[$index]',
      );
      index++;
      if (el != null) {
        band.elements.add(el);
      }
    }
    if (band.height <= 0) {
      band.height = band.designHeight;
      if (band.height <= 0 && band.rowHeight != null) {
        band.height = band.rowHeight!;
      }
    }
    _template.bands.add(band);
    return band;
  }

  String? _expr(String? raw, String path) {
    if (raw == null) {
      return null;
    }
    String s = raw.trim();
    if (s.startsWith('{{') && s.endsWith('}}')) {
      s = s.substring(2, s.length - 2).trim();
    }
    if (s.isEmpty) {
      return null;
    }
    try {
      ReportExpression.parse(s);
    } on ReportExpressionException catch (e) {
      _error(path, e.toString());
    }
    return s;
  }

  String? _sortSpec(String? raw, String path) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    for (final ({String source, bool? descending}) key
        in ReportExpression.sortKeys(raw)) {
      try {
        ReportExpression.parse(key.source);
      } on ReportExpressionException catch (e) {
        _error(path, e.toString());
      }
    }
    return raw.trim();
  }

  void _checkExpression(String source, String path) {
    if (source.trim().isEmpty) {
      _error(path, 'Expression is empty');
      return;
    }
    try {
      ReportExpression.parse(source.trim());
    } on ReportExpressionException catch (e) {
      _error(path, e.toString());
    }
  }

  void _checkTemplate(String text, String path) {
    try {
      ReportTemplateText.parse(text);
    } on ReportExpressionException catch (e) {
      _error(path, e.toString());
    }
  }

  ReportElement? _readElement(XmlElement e, String path) {
    final String tag = e.localName;
    String? type;
    String? shapeKind;
    switch (tag) {
      case 'Element':
        type = _attr(e, const <String>['type']);
        if (type == null) {
          _error(path, 'Element needs a type');
          return null;
        }
      case 'Text':
      case 'Label':
      case 'Field':
        type = 'Text';
      case 'Image':
      case 'Picture':
        type = 'Image';
      case 'Table':
        type = 'Table';
      case 'Barcode':
      case 'QrCode':
        type = 'Barcode';
      case 'Shape':
        type = 'Shape';
      case 'Chart':
        type = 'Chart';
      case 'Crosstab':
        type = 'Crosstab';
      case 'Subreport':
        type = 'Subreport';
      case 'Line':
      case 'Rectangle':
      case 'Ellipse':
        type = 'Shape';
        shapeKind = tag;
      default:
        _error(path, 'Unknown element <$tag>');
        return null;
    }
    final String p = '$path ($type)';
    final ReportElement? el = switch (type.toLowerCase()) {
      'text' || 'label' || 'field' => _readText(e, p),
      'image' || 'picture' => _readImage(e, p),
      'table' => _readTable(e, p),
      'barcode' || 'qrcode' || 'qr' => _readBarcode(
        e,
        p,
        forceQr: tag == 'QrCode' || type.toLowerCase() != 'barcode',
      ),
      'shape' || 'line' || 'rectangle' || 'ellipse' => _readShape(
        e,
        p,
        shapeKind ?? (type.toLowerCase() == 'shape' ? null : type),
      ),
      'chart' => _readChart(e, p),
      'crosstab' => _readCrosstab(e, p),
      'subreport' => _readSubreport(e, p),
      _ => null,
    };
    if (el == null) {
      _error(path, 'Unknown element type "$type"');
      return null;
    }
    el.name = _attr(e, const <String>['name', 'id']);
    el.visibleWhen = _expr(
      _attr(e, const <String>['visibleWhen', 'visible', 'printWhen']),
      '$p@visibleWhen',
    );
    const Set<String> common = <String>{
      'type',
      'name',
      'id',
      'x',
      'y',
      'width',
      'height',
      'visiblewhen',
      'visible',
      'printwhen',
      'x1',
      'y1',
      'x2',
      'y2',
    };
    final Set<String> known = <String>{...common, ..._knownFor(el)};
    for (final XmlAttribute a in e.attributes) {
      if (!known.contains(a.localName.toLowerCase())) {
        el.extraAttributes[a.localName] = a.value;
        _warn(p, 'Unknown attribute "${a.localName}" kept as-is');
      }
    }
    return el;
  }

  static Set<String> _knownFor(ReportElement el) => switch (el) {
    ReportTextElement() => const <String>{
      'text',
      'value',
      'expression',
      'fontfamily',
      'font',
      'fontsize',
      'bold',
      'italic',
      'underline',
      'color',
      'forecolor',
      'background',
      'backcolor',
      'alignment',
      'align',
      'textalign',
      'verticalalignment',
      'valign',
      'verticalalign',
      'direction',
      'dir',
      'cangrow',
      'canshrink',
      'wordwrap',
      'wrap',
      'format',
      'padding',
      'bordercolor',
      'borderwidth',
      'border',
      'linespacing',
      'lineheight',
    },
    ReportImageElement() => const <String>{
      'src',
      'source',
      'value',
      'fit',
      'sizing',
      'bordercolor',
      'borderwidth',
      'border',
      'background',
      'backcolor',
    },
    ReportBarcodeElement() => const <String>{
      'value',
      'data',
      'text',
      'symbology',
      'barcodetype',
      'kind',
      'showtext',
      'color',
      'forecolor',
      'background',
      'backcolor',
      'fontsize',
    },
    ReportShapeElement() => const <String>{
      'kind',
      'shape',
      'color',
      'stroke',
      'strokecolor',
      'strokewidth',
      'linewidth',
      'fill',
      'background',
      'backcolor',
      'cornerradius',
      'radius',
      'linestyle',
      'dash',
    },
    ReportTableElement() => const <String>{
      'showgrid',
      'bordercolor',
      'borderwidth',
      'headerbackground',
      'headerbackcolor',
      'headercolor',
      'headerforecolor',
      'headerbold',
      'fontsize',
      'headerfontsize',
      'fontfamily',
      'font',
      'color',
      'rowheight',
      'headerheight',
      'stripecolor',
      'alternaterowcolor',
      'repeatheader',
      'showheader',
      'padding',
      'dataset',
      'datasource',
    },
    ReportChartElement() => const <String>{
      'charttype',
      'kind',
      'title',
      'dataset',
      'datasource',
      'category',
      'categoryfield',
      'value',
      'aggregate',
      'sortby',
      'sortorder',
      'limit',
      'top',
      'showlegend',
      'legend',
      'showvalues',
      'labels',
      'showgrid',
      'showaxes',
      'valueformat',
      'format',
      'fontsize',
      'fontfamily',
      'font',
      'color',
      'forecolor',
      'background',
      'backcolor',
      'bordercolor',
      'borderwidth',
      'border',
      'palette',
      'colors',
      'depth',
      'skew',
      'hole',
      'startangle',
      'smooth',
      'showmarkers',
      'markersize',
      'linewidth',
      'axismin',
      'axismax',
      'axismin2',
      'axismax2',
      'target',
      'showpercent',
      'lastistotal',
      'bands',
      'increasecolor',
      'decreasecolor',
      'totalcolor',
      'shape',
      'atlas',
      'shapekey',
      'keyfield',
      'lowcolor',
      'highcolor',
      'emptycolor',
      'showlabels',
      'regioncolor',
      'colorfield',
      'labelfield',
    },
    ReportCrosstabElement() => const <String>{
      'dataset',
      'datasource',
      'source',
      'rowfield',
      'row',
      'columnfield',
      'column',
      'valuefield',
      'value',
      'aggregate',
      'maxcolumns',
      'fontsize',
      'headerbold',
    },
    ReportSubreportElement() => const <String>{
      'template',
      'report',
      'name',
      'dataset',
      'datasource',
      'source',
    },
  };

  void _readBox(ReportElement el, XmlElement e, String path) {
    el.x = _len(e, const <String>['x'], path) ?? 0;
    el.y = _len(e, const <String>['y'], path) ?? 0;
    final double? w = _len(e, const <String>['width'], path);
    final double? h = _len(e, const <String>['height'], path);
    if (w != null) {
      if (w < 0) {
        _error(path, 'width must not be negative');
      }
      el.width = w;
    }
    if (h != null) {
      if (h < 0) {
        _error(path, 'height must not be negative');
      }
      el.height = h;
    }
  }

  ReportTextElement _readText(XmlElement e, String path) {
    final ReportTextElement t = ReportTextElement();
    _readBox(t, e, path);
    for (final XmlElement child in e.childElements) {
      if (child.localName != 'Run') {
        continue;
      }
      t.runs.add(
        ReportTextRun(
          text: _content(child),
          bold: _bool(child, const <String>['bold'], path),
          italic: _bool(child, const <String>['italic'], path),
          fontSize: _num(child, const <String>['fontSize', 'size'], path),
          color: _color(child, const <String>['color'], path),
          underline: _bool(child, const <String>['underline'], path),
          link: _attr(child, const <String>['link', 'href']),
        ),
      );
    }
    t.text = t.runs.isEmpty
        ? (_attr(e, const <String>['text', 'value', 'expression']) ??
              _content(e))
        : t.plainText;
    _checkTemplate(t.text, path);
    t.style
      ..fontFamily = _attr(e, const <String>['fontFamily', 'font'])
      ..fontSize = _num(e, const <String>['fontSize'], path)
      ..bold = _bool(e, const <String>['bold'], path)
      ..italic = _bool(e, const <String>['italic'], path)
      ..underline = _bool(e, const <String>['underline'], path)
      ..color = _color(e, const <String>['color', 'foreColor'], path);
    t.background = _color(e, const <String>['background', 'backColor'], path);
    t.align =
        _enum(
          e,
          const <String>['alignment', 'align', 'textAlign'],
          ReportTextAlign.values,
          path,
          aliases: _alignAliases,
        ) ??
        ReportTextAlign.start;
    t.verticalAlign =
        _enum(
          e,
          const <String>['verticalAlignment', 'vAlign', 'verticalAlign'],
          ReportVerticalAlign.values,
          path,
          aliases: _vAlignAliases,
        ) ??
        ReportVerticalAlign.top;
    t.direction =
        _enum(
          e,
          const <String>['direction', 'dir'],
          ReportTextDirection.values,
          path,
        ) ??
        ReportTextDirection.auto;
    t.canGrow = _bool(e, const <String>['canGrow'], path) ?? true;
    t.canShrink = _bool(e, const <String>['canShrink'], path) ?? false;
    t.wordWrap = _bool(e, const <String>['wordWrap', 'wrap'], path) ?? true;
    t.format = _attr(e, const <String>['format']);
    t.padding =
        _len(e, const <String>['padding'], path, unit: ReportUnit.pt) ?? 0;
    t.borderColor = _color(e, const <String>['borderColor'], path);
    t.borderWidth =
        _len(
          e,
          const <String>['borderWidth', 'border'],
          path,
          unit: ReportUnit.pt,
        ) ??
        (t.borderColor != null ? 0.5 : 0);
    t.lineSpacing =
        _num(e, const <String>['lineSpacing', 'lineHeight'], path) ?? 1.0;
    final double size = t.style.fontSize ?? _template.defaultFontSize;
    if (t.height <= 0) {
      t.height = size * 1.45 + t.padding * 2;
    }
    if (t.width <= 0) {
      t.width = _template.remainingWidth(t.x).clamp(10, _template.pageWidth);
      _warn(path, 'No width; using the remaining line width');
    }
    return t;
  }

  ReportImageElement _readImage(XmlElement e, String path) {
    final ReportImageElement img = ReportImageElement();
    _readBox(img, e, path);
    img.source =
        _attr(e, const <String>['src', 'source', 'value']) ?? _content(e);
    if (img.source.isEmpty) {
      _warn(path, 'Image has no source');
    }
    _checkTemplate(img.source, path);
    img.fit =
        _enum(
          e,
          const <String>['fit', 'sizing'],
          ReportImageFit.values,
          path,
        ) ??
        ReportImageFit.contain;
    img.borderColor = _color(e, const <String>['borderColor'], path);
    img.borderWidth =
        _len(
          e,
          const <String>['borderWidth', 'border'],
          path,
          unit: ReportUnit.pt,
        ) ??
        (img.borderColor != null ? 0.5 : 0);
    img.background = _color(e, const <String>['background', 'backColor'], path);
    if (img.width <= 0 || img.height <= 0) {
      _error(path, 'Image needs width and height');
    }
    return img;
  }

  ReportBarcodeElement _readBarcode(
    XmlElement e,
    String path, {
    required bool forceQr,
  }) {
    final ReportBarcodeElement bc = ReportBarcodeElement();
    _readBox(bc, e, path);
    bc.data = _attr(e, const <String>['value', 'data', 'text']) ?? _content(e);
    _checkTemplate(bc.data, path);
    bc.symbology =
        _enum(
          e,
          const <String>['symbology', 'barcodeType', 'kind'],
          ReportBarcodeType.values,
          path,
          aliases: const <String, ReportBarcodeType>{
            'code-128': ReportBarcodeType.code128,
            'qrcode': ReportBarcodeType.qr,
            'qr-code': ReportBarcodeType.qr,
            'ean-13': ReportBarcodeType.ean13,
            'ean13': ReportBarcodeType.ean13,
          },
        ) ??
        (forceQr && e.localName == 'QrCode'
            ? ReportBarcodeType.qr
            : ReportBarcodeType.code128);
    bc.showText =
        _bool(e, const <String>['showText'], path) ??
        bc.symbology != ReportBarcodeType.qr;
    bc.color = _color(e, const <String>['color', 'foreColor'], path);
    bc.background = _color(e, const <String>['background', 'backColor'], path);
    bc.fontSize = _num(e, const <String>['fontSize'], path) ?? 8;
    if (bc.width <= 0 || bc.height <= 0) {
      _error(path, 'Barcode needs width and height');
    }
    return bc;
  }

  ReportShapeElement _readShape(XmlElement e, String path, String? tagKind) {
    final ReportShapeKind kind =
        _enum(
          e,
          const <String>['kind', 'shape'],
          ReportShapeKind.values,
          path,
          aliases: const <String, ReportShapeKind>{
            'rect': ReportShapeKind.rectangle,
            'box': ReportShapeKind.rectangle,
            'roundrect': ReportShapeKind.roundedRectangle,
            'rounded': ReportShapeKind.roundedRectangle,
            'circle': ReportShapeKind.ellipse,
            'oval': ReportShapeKind.ellipse,
            'hline': ReportShapeKind.line,
            'vline': ReportShapeKind.line,
          },
        ) ??
        reportEnumByName(ReportShapeKind.values, tagKind) ??
        ReportShapeKind.rectangle;
    final String? stroke = _color(e, const <String>[
      'color',
      'stroke',
      'strokeColor',
    ], path);
    final double strokeWidth =
        _len(
          e,
          const <String>['strokeWidth', 'lineWidth'],
          path,
          unit: ReportUnit.pt,
        ) ??
        0.75;
    final ReportLineStyle style =
        _enum(
          e,
          const <String>['lineStyle', 'dash'],
          ReportLineStyle.values,
          path,
        ) ??
        ReportLineStyle.solid;
    final ReportShapeElement s;
    final double? x1 = _len(e, const <String>['x1'], path);
    if (kind == ReportShapeKind.line && x1 != null) {
      final double y1 = _len(e, const <String>['y1'], path) ?? 0;
      final double x2 = _len(e, const <String>['x2'], path) ?? x1;
      final double y2 = _len(e, const <String>['y2'], path) ?? y1;
      s = ReportShapeElement.line(
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        strokeColor: stroke,
        strokeWidth: strokeWidth,
        lineStyle: style,
      );
    } else {
      s = ReportShapeElement(
        kind: kind,
        strokeColor: stroke,
        strokeWidth: strokeWidth,
        lineStyle: style,
      );
      _readBox(s, e, path);
      if (kind != ReportShapeKind.line && (s.width <= 0 || s.height <= 0)) {
        _error(path, 'Shape needs width and height');
      }
    }
    s.fill = _color(e, const <String>['fill', 'background', 'backColor'], path);
    s.cornerRadius =
        _len(
          e,
          const <String>['cornerRadius', 'radius'],
          path,
          unit: ReportUnit.pt,
        ) ??
        (kind == ReportShapeKind.roundedRectangle ? 6 : 0);
    return s;
  }

  ReportCrosstabElement _readCrosstab(XmlElement e, String path) {
    final ReportCrosstabElement c = ReportCrosstabElement();
    _readBox(c, e, path);
    c.dataSet = _attr(e, const <String>['dataSet', 'dataSource', 'source']);
    c.rowField =
        _expr(_attr(e, const <String>['rowField', 'row']), '$path@rowField') ??
        '';
    c.columnField =
        _expr(
          _attr(e, const <String>['columnField', 'column']),
          '$path@columnField',
        ) ??
        '';
    c.valueField =
        _expr(
          _attr(e, const <String>['valueField', 'value']),
          '$path@valueField',
        ) ??
        '';
    c.aggregate =
        _enum(
          e,
          const <String>['aggregate'],
          ReportChartAggregate.values,
          path,
        ) ??
        ReportChartAggregate.sum;
    c.maxColumns =
        _num(e, const <String>['maxColumns'], path)?.round() ?? 12;
    c.fontSize = _num(e, const <String>['fontSize'], path) ?? 9;
    c.headerBold = _bool(e, const <String>['headerBold'], path) ?? true;
    return c;
  }

  ReportSubreportElement _readSubreport(XmlElement e, String path) {
    final ReportSubreportElement s = ReportSubreportElement();
    _readBox(s, e, path);
    s.templateName =
        _attr(e, const <String>['template', 'report', 'name']) ?? '';
    s.dataSet = _expr(
      _attr(e, const <String>['dataSet', 'dataSource', 'source']),
      '$path@dataSet',
    );
    if (s.templateName.trim().isEmpty) {
      _error(path, 'Subreport needs a template name');
    }
    return s;
  }

  ReportChartElement _readChart(XmlElement e, String path) {
    final ReportChartElement c = ReportChartElement();
    _readBox(c, e, path);
    c.chartType =
        _enum(
          e,
          const <String>['chartType', 'kind'],
          ReportChartType.values,
          path,
          aliases: const <String, ReportChartType>{
            'column': ReportChartType.bar,
            'columns': ReportChartType.bar,
            'hbar': ReportChartType.horizontalBar,
            'stacked': ReportChartType.stackedBar,
            'doughnut': ReportChartType.donut,
            'ring': ReportChartType.donut,
            'stacked100': ReportChartType.percentStackedBar,
            'percent': ReportChartType.percentStackedBar,
            '100': ReportChartType.percentStackedBar,
            'point': ReportChartType.scatter,
            'points': ReportChartType.scatter,
            'dot': ReportChartType.scatter,
            'dots': ReportChartType.scatter,
            'xy': ReportChartType.scatter,
            'spider': ReportChartType.radar,
            'heat': ReportChartType.heatmap,
            'meter': ReportChartType.gauge,
            'spark': ReportChartType.sparkline,
            'bar3d': ReportChartType.extrudedBar,
            'column3d': ReportChartType.extrudedBar,
            'pie3d': ReportChartType.extrudedPie,
            'donut3d': ReportChartType.extrudedDonut,
            'doughnut3d': ReportChartType.extrudedDonut,
            'map': ReportChartType.shapeMap,
            'choropleth': ReportChartType.shapeMap,
            'shapemap': ReportChartType.shapeMap,
          },
        ) ??
        ReportChartType.bar;
    c.title = _attr(e, const <String>['title']) ?? '';
    _checkTemplate(c.title, path);
    c.dataSet = _attr(e, const <String>['dataSet', 'dataSource']);
    c.category = _expr(
      _attr(e, const <String>['category', 'categoryField']),
      '$path@category',
    );
    final String? single = _expr(
      _attr(e, const <String>['value']),
      '$path@value',
    );
    c.aggregate =
        _enum(
          e,
          const <String>['aggregate'],
          ReportChartAggregate.values,
          path,
          aliases: const <String, ReportChartAggregate>{
            'average': ReportChartAggregate.avg,
            'total': ReportChartAggregate.sum,
          },
        ) ??
        ReportChartAggregate.sum;
    c.sortBy =
        _enum(e, const <String>['sortBy'], ReportChartSort.values, path) ??
        ReportChartSort.none;
    final String? order = _attr(e, const <String>['sortOrder'])?.toLowerCase();
    c.descending = order == 'desc' || order == 'descending';
    c.limit = (_num(e, const <String>['limit', 'top'], path) ?? 0).round();
    if (c.limit < 0) {
      _error(path, 'limit must not be negative');
      c.limit = 0;
    }
    c.showLegend =
        _bool(e, const <String>['showLegend', 'legend'], path) ?? true;
    c.showValues =
        _bool(e, const <String>['showValues', 'labels'], path) ?? false;
    c.showGrid = _bool(e, const <String>['showGrid'], path) ?? true;
    c.showAxes = _bool(e, const <String>['showAxes'], path) ?? true;
    c.valueFormat = _attr(e, const <String>['valueFormat', 'format']);
    c.fontSize = _num(e, const <String>['fontSize'], path) ?? 7.5;
    c.fontFamily = _attr(e, const <String>['fontFamily', 'font']);
    c.bold = _bool(e, const <String>['bold'], path) ?? false;
    c.italic = _bool(e, const <String>['italic'], path) ?? false;
    c.textColor = _color(e, const <String>['color', 'foreColor'], path);
    c.background = _color(e, const <String>['background', 'backColor'], path);
    c.borderColor = _color(e, const <String>['borderColor'], path);
    c.borderWidth =
        _len(
          e,
          const <String>['borderWidth', 'border'],
          path,
          unit: ReportUnit.pt,
        ) ??
        (c.borderColor != null ? 0.5 : 0);
    final String? palette = _attr(e, const <String>['palette', 'colors']);
    if (palette != null) {
      for (final String raw in palette.split(RegExp(r'[,;\s]+'))) {
        if (raw.isNotEmpty) {
          c.palette.add(raw);
        }
      }
    }
    c.depth = _num(e, const <String>['depth'], path) ?? 14;
    c.skew = _num(e, const <String>['skew'], path) ?? 32;
    c.hole = _num(e, const <String>['hole'], path) ?? 0.58;
    c.startAngle = _num(e, const <String>['startAngle'], path) ?? -90;
    c.smooth = _bool(e, const <String>['smooth'], path) ?? false;
    c.showMarkers = _bool(e, const <String>['showMarkers'], path);
    c.markerSize = _num(e, const <String>['markerSize'], path) ?? 2.6;
    c.lineWidth = _num(e, const <String>['lineWidth'], path) ?? 1.6;
    c.axisMin = _num(e, const <String>['axisMin'], path);
    c.axisMax = _num(e, const <String>['axisMax'], path);
    c.axisMin2 = _num(e, const <String>['axisMin2'], path);
    c.axisMax2 = _num(e, const <String>['axisMax2'], path);
    c.target = _expr(_attr(e, const <String>['target']), '$path@target');
    c.showPercent = _bool(e, const <String>['showPercent'], path) ?? false;
    c.lastIsTotal = _bool(e, const <String>['lastIsTotal'], path) ?? false;
    c.bands = (_num(e, const <String>['bands'], path) ?? 3).round().clamp(0, 8);
    c.increaseColor = _color(e, const <String>['increaseColor'], path);
    c.decreaseColor = _color(e, const <String>['decreaseColor'], path);
    c.totalColor = _color(e, const <String>['totalColor'], path);
    c.shape = _attr(e, const <String>['shape', 'atlas']) ?? 'world';
    c.shapeKey = _attr(e, const <String>['shapeKey', 'keyField']);
    c.lowColor = _color(e, const <String>['lowColor'], path);
    c.highColor = _color(e, const <String>['highColor'], path);
    c.emptyColor = _color(e, const <String>['emptyColor'], path);
    c.showLabels = _bool(e, const <String>['showLabels'], path) ?? true;
    c.labelField = _attr(e, const <String>['labelField']);
    _readTextStyle(
      c.titleStyle,
      e,
      const <String>['titleFont', 'titleFamily'],
      const <String>['titleSize', 'titleFontSize'],
      const <String>['titleBold'],
      const <String>['titleItalic'],
      const <String>['titleColor'],
      path,
    );
    _readTextStyle(
      c.labelStyle,
      e,
      const <String>['labelFont', 'labelFamily'],
      const <String>['labelSize', 'labelFontSize'],
      const <String>['labelBold'],
      const <String>['labelItalic'],
      const <String>['labelColor'],
      path,
    );
    _readTextStyle(
      c.legendStyle,
      e,
      const <String>['legendFont', 'legendFamily'],
      const <String>['legendSize', 'legendFontSize'],
      const <String>['legendBold'],
      const <String>['legendItalic'],
      const <String>['legendColor'],
      path,
    );
    c.regionColor = _expr(
      _attr(e, const <String>['regionColor', 'colorField']),
      '$path@regionColor',
    );
    for (final XmlElement child in e.childElements) {
      switch (child.localName) {
        case 'Series':
          final String sp = '$path/Series[${c.series.length}]';
          final ReportChartSeries s = ReportChartSeries(
            name: _attr(child, const <String>['name', 'title']) ?? '',
            value:
                _expr(
                  _attr(child, const <String>['value', 'field', 'expression']),
                  '$sp@value',
                ) ??
                '',
            color: _color(child, const <String>['color'], sp),
            x: _expr(_attr(child, const <String>['x']), '$sp@x'),
            size: _expr(_attr(child, const <String>['size']), '$sp@size'),
            style:
                _enum(
                  child,
                  const <String>['style'],
                  ReportSeriesStyle.values,
                  sp,
                  aliases: const <String, ReportSeriesStyle>{
                    'bar': ReportSeriesStyle.column,
                    'column': ReportSeriesStyle.column,
                  },
                ) ??
                ReportSeriesStyle.column,
            secondary: _bool(child, const <String>['secondary'], sp) ?? false,
          );
          _checkTemplate(s.name, sp);
          if (s.value.isEmpty) {
            _error(sp, 'Series needs a value expression');
          }
          c.series.add(s);
        case 'Point':
          final String pp = '$path/Point[${c.points.length}]';
          final ReportChartPoint pt = ReportChartPoint(
            label:
                _attr(child, const <String>['label', 'category', 'name']) ??
                _content(child),
            value:
                _expr(
                  _attr(child, const <String>['value', 'expression']),
                  '$pp@value',
                ) ??
                '',
            color: _color(child, const <String>['color'], pp),
            x: _expr(_attr(child, const <String>['x']), '$pp@x'),
            size: _expr(_attr(child, const <String>['size']), '$pp@size'),
            total: _bool(child, const <String>['total'], pp) ?? false,
          );
          _checkTemplate(pt.label, pp);
          if (pt.value.isEmpty) {
            _error(pp, 'Point needs a value');
          }
          c.points.add(pt);
        default:
          _warn('$path/${child.localName}', 'Unknown element ignored');
      }
    }
    if (single != null) {
      c.series.insert(0, ReportChartSeries(value: single));
    }
    if (c.series.isNotEmpty && c.category == null && !c.chartType.plotsPoints) {
      _error(path, 'Data-bound chart needs a category expression');
    }
    if (c.series.isEmpty && c.points.isEmpty) {
      _warn(path, 'Chart has no <Series> or <Point>; it prints empty');
    }
    if (c.width <= 0 || c.height <= 0) {
      _error(path, 'Chart needs width and height');
    }
    return c;
  }

  ReportTableElement _readTable(XmlElement e, String path) {
    final ReportTableElement t = ReportTableElement();
    _readBox(t, e, path);
    t.showGrid = _bool(e, const <String>['showGrid'], path) ?? true;
    t.borderColor = _color(e, const <String>['borderColor'], path);
    t.borderWidth =
        _len(e, const <String>['borderWidth'], path, unit: ReportUnit.pt) ??
        0.5;
    t.headerBackground = _color(e, const <String>[
      'headerBackground',
      'headerBackColor',
    ], path);
    t.headerColor = _color(e, const <String>[
      'headerColor',
      'headerForeColor',
    ], path);
    t.headerBold = _bool(e, const <String>['headerBold'], path) ?? true;
    t.fontSize = _num(e, const <String>['fontSize'], path);
    t.headerFontSize = _num(e, const <String>['headerFontSize'], path);
    t.fontFamily = _attr(e, const <String>['fontFamily', 'font']);
    t.color = _color(e, const <String>['color'], path);
    t.rowHeight = _len(e, const <String>['rowHeight'], path);
    t.headerHeight = _len(e, const <String>['headerHeight'], path);
    t.stripeColor = _color(e, const <String>[
      'stripeColor',
      'alternateRowColor',
    ], path);
    t.repeatHeader = _bool(e, const <String>['repeatHeader'], path) ?? true;
    t.showHeader = _bool(e, const <String>['showHeader'], path) ?? true;
    t.padding =
        _len(e, const <String>['padding'], path, unit: ReportUnit.pt) ?? 3;
    t.dataSet = _attr(e, const <String>['dataSet', 'dataSource']);
    for (final XmlElement child in e.childElements) {
      switch (child.localName) {
        case 'Columns':
          for (final XmlElement c in child.childElements) {
            if (c.localName != 'Column') {
              _warn('$path/Columns/${c.localName}', 'Unknown element ignored');
              continue;
            }
            final String cp = '$path/Columns/Column[${t.columns.length}]';
            final ReportTableColumn col = ReportTableColumn(
              width: _len(c, const <String>['width'], cp),
              header:
                  _attr(c, const <String>['header', 'title', 'text']) ??
                  _content(c),
              align:
                  _enum(
                    c,
                    const <String>['align', 'alignment'],
                    ReportTextAlign.values,
                    cp,
                    aliases: _alignAliases,
                  ) ??
                  ReportTextAlign.start,
              headerAlign: _enum(
                c,
                const <String>['headerAlign', 'headerAlignment'],
                ReportTextAlign.values,
                cp,
                aliases: _alignAliases,
              ),
            );
            _checkTemplate(col.header, cp);
            t.columns.add(col);
          }
        case 'RowTemplate':
        case 'Row':
        case 'Rows':
          t.cells.addAll(_readCells(child, '$path/${child.localName}'));
        case 'FooterRow':
        case 'Footer':
        case 'Totals':
          t.footerCells.addAll(_readCells(child, '$path/${child.localName}'));
        default:
          _warn('$path/${child.localName}', 'Unknown element ignored');
      }
    }
    if (t.columns.isEmpty) {
      _error(path, 'Table needs at least one <Column>');
    }
    if (t.cells.length != t.columns.length && t.columns.isNotEmpty) {
      _warn(
        path,
        'RowTemplate has ${t.cells.length} cells for ${t.columns.length} columns',
      );
    }
    if (t.width <= 0) {
      var sum = 0.0;
      for (final ReportTableColumn c in t.columns) {
        sum += c.width ?? 0;
      }
      t.width = sum > 0 ? sum : _template.remainingWidth(t.x);
    }
    if (t.height <= 0) {
      final double row = t.rowHeight ?? 22;
      t.height = (t.showHeader ? (t.headerHeight ?? row) : 0) + row;
    }
    return t;
  }

  List<ReportTableCell> _readCells(XmlElement row, String path) {
    final List<ReportTableCell> out = <ReportTableCell>[];
    for (final XmlElement c in row.childElements) {
      final String cp = '$path/${c.localName}[${out.length}]';
      if (c.localName != 'Cell') {
        _warn(cp, 'Unknown element ignored');
        continue;
      }
      final String? field = _expr(
        _attr(c, const <String>['field', 'expression', 'value']),
        cp,
      );
      final String content = _attr(c, const <String>['text']) ?? _content(c);
      if (field == null) {
        _checkTemplate(content, cp);
      }
      out.add(
        ReportTableCell(
          field: field,
          text: field == null ? content : null,
          format: _attr(c, const <String>['format']),
          bold: _bool(c, const <String>['bold'], cp),
          italic: _bool(c, const <String>['italic'], cp),
          color: _color(c, const <String>['color', 'foreColor'], cp),
          background: _color(c, const <String>['background', 'backColor'], cp),
          align: _enum(
            c,
            const <String>['align', 'alignment'],
            ReportTextAlign.values,
            cp,
            aliases: _alignAliases,
          ),
        ),
      );
    }
    return out;
  }

  void _validate() {
    final ReportTemplate t = _template;
    void color(String? raw, String path) {
      if (raw == null) {
        return;
      }
      final bool palette = t.colors.keys.any(
        (String k) => k.toLowerCase() == raw.toLowerCase(),
      );
      if (!palette && ReportColor.tryParse(raw) == null) {
        _error(path, 'Unknown color "$raw" (not a palette name or #hex)');
      }
    }

    if (t.margins.top + t.margins.bottom >= t.pageHeight ||
        t.margins.left + t.margins.right >= t.pageWidth) {
      _error('Settings/Margins', 'Margins leave no printable area');
    }
    final ReportBand? detail = t.detail;
    final bool chartsReadData = t.bands
        .expand((ReportBand b) => b.elements)
        .any(
          (ReportElement e) =>
              e is ReportChartElement &&
              e.dataSet != null &&
              e.dataSet!.trim().isNotEmpty,
        );
    if (detail == null && t.dataSchema.tables.isNotEmpty && !chartsReadData) {
      _warn('Bands', 'No Detail band; data rows will not print');
    }
    if (t.band(ReportBandKind.groupFooter) != null ||
        t.band(ReportBandKind.groupHeader) != null) {
      if (detail == null) {
        _error('Bands', 'Group bands need a Detail band');
      }
    }
    double fixedBands = 0;
    for (final ReportBandKind k in <ReportBandKind>[
      ReportBandKind.pageHeader,
      ReportBandKind.pageFooter,
    ]) {
      fixedBands += t.band(k)?.designHeight ?? 0;
    }
    final double body = t.pageHeight - t.margins.top - t.margins.bottom;
    if (fixedBands >= body) {
      _error('Bands', 'Page header + footer leave no room for content');
    }
    for (final ReportBand b in t.bands) {
      final String bp = 'Bands/${b.kind.xmlName}';
      color(b.background, bp);
      if (b.dataSet != null && b.kind != ReportBandKind.detail) {
        _warn(bp, 'dataSet is only used on the Detail band');
      }
      if (b.designHeight > body &&
          b.kind != ReportBandKind.reportHeader &&
          b.kind != ReportBandKind.reportSummary) {
        _warn(bp, 'Band is taller than the printable page height');
      }
      var i = 0;
      for (final ReportElement e in b.elements) {
        final String ep = '$bp/${e.displayName}[$i]';
        i++;
        if (e.y + e.height > b.height + 0.01 && b.height > 0) {
          _warn(ep, 'Extends below the band height');
        }
        final double left = t.elementLeft(e.x, e.width);
        if (left + e.width > t.pageWidth + 0.5 || left < -0.5) {
          _warn(ep, 'Extends past the page edge');
        }
        switch (e) {
          case ReportTextElement():
            color(e.style.color, ep);
            color(e.background, ep);
            color(e.borderColor, ep);
          case ReportImageElement():
            color(e.borderColor, ep);
            color(e.background, ep);
          case ReportBarcodeElement():
            color(e.color, ep);
            color(e.background, ep);
          case ReportShapeElement():
            color(e.strokeColor, ep);
            color(e.fill, ep);
          case ReportTableElement():
            color(e.borderColor, ep);
            color(e.headerBackground, ep);
            color(e.headerColor, ep);
            color(e.color, ep);
            color(e.stripeColor, ep);
            for (final ReportTableCell c in <ReportTableCell>[
              ...e.cells,
              ...e.footerCells,
            ]) {
              color(c.color, ep);
              color(c.background, ep);
            }
            if (b.kind == ReportBandKind.detail &&
                (e.dataSet ?? b.dataSet) == null) {
              _warn(
                ep,
                'Table in Detail without a dataSet prints one empty row',
              );
            }
            if (b.kind != ReportBandKind.detail && e.dataSet == null) {
              _warn(ep, 'Table outside Detail needs dataSet to repeat rows');
            }
          case ReportChartElement():
            color(e.textColor, ep);
            color(e.background, ep);
            color(e.borderColor, ep);
            for (final String c in e.palette) {
              color(c, ep);
            }
            for (final ReportChartSeries s in e.series) {
              color(s.color, ep);
            }
            for (final ReportChartPoint p in e.points) {
              color(p.color, ep);
            }
            if (b.kind == ReportBandKind.detail && e.dataSet == null) {
              _warn(ep, 'Chart in Detail without a dataSet plots one row');
            }
          case ReportCrosstabElement():
          case ReportSubreportElement():
            break;
        }
      }
      if (b.kind == ReportBandKind.detail) {
        final int tables = b.elements.whereType<ReportTableElement>().length;
        if (tables > 1) {
          _error(bp, 'Detail supports one repeating Table');
        }
      }
    }
  }
}

/// Serializes a [ReportTemplate] back to `.qrep` XML.
class QudsReportXmlWriter {
  /// QudsReportXmlWriter API.
  const QudsReportXmlWriter({this.indent = '    '});

  /// indent API.
  final String indent;

  /// XML text with declaration.
  String write(ReportTemplate t) {
    final StringBuffer b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8"?>\n',
    );
    final ReportUnit u = t.unit;
    String len(double v) => ReportUnits.format(v, unit: u);
    String pt(double v) => ReportUnits.trimNumber(v);

    final Map<String, String> root = <String, String>{
      'name': t.name,
      'isRtl': '${t.isRtl}',
      if (ReportPageSize.byName(t.pageSize.name) != null)
        'pageSize': t.pageSize.name,
      if (ReportPageSize.byName(t.pageSize.name) == null) ...<String, String>{
        'pageSize': 'Custom',
        'pageWidth': len(t.pageSize.width),
        'pageHeight': len(t.pageSize.height),
      },
      'orientation': t.orientation == ReportOrientation.landscape
          ? 'Landscape'
          : 'Portrait',
      if (t.defaultFont.isNotEmpty) 'defaultFont': t.defaultFont,
      if (t.defaultFontSize != 10) 'defaultFontSize': pt(t.defaultFontSize),
      if (u != ReportUnit.mm) 'unit': u.suffix,
      if (t.coordinateOrigin != ReportCoordinateOrigin.page)
        'coordinateOrigin': t.coordinateOrigin.name,
      if (!t.mirrorRtl) 'mirrorRtl': 'false',
      ...t.extraAttributes,
    };
    b.write('<QudsReport${_attrs(root)}>\n');

    b.write('$indent<Settings>\n');
    b.write(
      '$indent$indent<Margins${_attrs(<String, String>{'top': len(t.margins.top), 'bottom': len(t.margins.bottom), 'left': len(t.margins.left), 'right': len(t.margins.right)})}/>\n',
    );
    if (t.colors.isNotEmpty) {
      b.write('$indent$indent<Colors${_attrs(t.colors)}/>\n');
    }
    const ReportFormatDefaults d = ReportFormatDefaults();
    final ReportFormatDefaults f = t.formats;
    final Map<String, String> fmt = <String, String>{
      if (f.datePattern != d.datePattern) 'date': f.datePattern,
      if (f.timePattern != d.timePattern) 'time': f.timePattern,
      if (f.dateTimePattern != d.dateTimePattern) 'dateTime': f.dateTimePattern,
      if (f.decimalSeparator != d.decimalSeparator)
        'decimalSeparator': f.decimalSeparator,
      if (f.groupSeparator != d.groupSeparator)
        'groupSeparator': f.groupSeparator,
      if (f.arabicDigits) 'arabicDigits': 'true',
    };
    if (fmt.isNotEmpty) {
      b.write('$indent$indent<Formats${_attrs(fmt)}/>\n');
    }
    b.write('$indent</Settings>\n');

    if (t.variables.isNotEmpty) {
      b.write('$indent<Variables>\n');
      for (final ReportVariable v in t.variables) {
        b.write(
          '$indent$indent<Var${_attrs(<String, String>{'name': v.name, if (v.type != ReportVariableType.text) 'type': v.type.name, 'value': v.value, if (v.format != null && v.format!.trim().isNotEmpty) 'format': v.format!.trim(), if (v.description.isNotEmpty) 'description': v.description, if (v.prompt) 'prompt': 'true', if (v.required) 'required': 'true'})}/>\n',
        );
      }
      b.write('$indent</Variables>\n');
    }

    final ReportDataSchema schema = t.dataSchema;
    if (!schema.isEmpty) {
      b.write('$indent<DataSchema>\n');
      final String p2 = '$indent$indent';
      for (final ReportDataField f in schema.fields) {
        b.write(
          '$p2<Field${_attrs(<String, String>{'name': f.name, if (f.type != ReportDataType.text) 'type': f.type.name, if (f.description.isNotEmpty) 'description': f.description})}/>\n',
        );
      }
      for (final ReportDataTable table in schema.tables) {
        final String ta = _attrs(<String, String>{
          'name': table.name,
          if (table.description.isNotEmpty) 'description': table.description,
        });
        if (table.columns.isEmpty) {
          b.write('$p2<Table$ta/>\n');
          continue;
        }
        b.write('$p2<Table$ta>\n');
        for (final ReportDataColumn c in table.columns) {
          b.write(
            '$p2$indent<Column${_attrs(<String, String>{'name': c.name, if (c.type != ReportDataType.text) 'type': c.type.name, if (c.isCalculated) 'expression': c.expression!, if (c.format != null && c.format!.trim().isNotEmpty) 'format': c.format!.trim(), if (c.description.isNotEmpty) 'description': c.description})}/>\n',
          );
        }
        b.write('$p2</Table>\n');
      }
      b.write('$indent</DataSchema>\n');
    }

    b.write('$indent<Bands>\n');
    final bool wrapped = t.bands.any((ReportBand band) => band.section > 0);
    int? openSection;
    for (final ReportBand band in t.bands) {
      final bool data =
          band.kind == ReportBandKind.groupHeader ||
          band.kind == ReportBandKind.detail ||
          band.kind == ReportBandKind.groupFooter;
      if (wrapped && data && openSection != band.section) {
        if (openSection != null) {
          b.write('$indent$indent</Section>\n');
        }
        openSection = band.section;
        final ReportBand? detail = t.bandIn(ReportBandKind.detail, band.section);
        b.write(
          '$indent$indent<Section${_attrs(<String, String>{if (detail?.dataSet != null) 'dataSet': detail!.dataSet!})}>\n',
        );
      }
      if (wrapped && !data && openSection != null) {
        b.write('$indent$indent</Section>\n');
        openSection = null;
      }
      final String bandPad = wrapped && data
          ? '$indent$indent$indent'
          : '$indent$indent';
      final Map<String, String> ba = <String, String>{
        if (band.kind == ReportBandKind.detail && band.dataSet != null)
          'dataSet': band.dataSet!,
        'height': len(band.height),
        if (band.rowHeight != null) 'rowHeight': len(band.rowHeight!),
        if (band.groupBy != null) 'groupBy': band.groupBy!,
        if (band.sortBy != null) 'sortBy': band.sortBy!,
        if (band.sortDescending) 'sortOrder': 'desc',
        if (band.filter != null) 'filter': band.filter!,
        if (!band.printOnFirstPage) 'printOnFirstPage': 'false',
        if (!band.printOnLastPage) 'printOnLastPage': 'false',
        if (band.newPageBefore) 'newPageBefore': 'true',
        if (band.newPageAfter) 'newPageAfter': 'true',
        if (band.keepTogether) 'keepTogether': 'true',
        if (band.repeatOnEveryPage) 'repeatOnEveryPage': 'true',
        if (band.background != null) 'background': band.background!,
        if (band.visibleWhen != null) 'visibleWhen': band.visibleWhen!,
        ...band.extraAttributes,
      };
      if (band.elements.isEmpty) {
        b.write('$bandPad<${band.kind.xmlName}${_attrs(ba)}/>\n');
        continue;
      }
      b.write('$bandPad<${band.kind.xmlName}${_attrs(ba)}>\n');
      for (final ReportElement e in band.elements) {
        _writeElement(b, e, '$bandPad$indent', len, pt);
      }
      b.write('$bandPad</${band.kind.xmlName}>\n');
    }
    if (openSection != null) {
      b.write('$indent$indent</Section>\n');
    }
    b.write('$indent</Bands>\n');
    b.write('</QudsReport>\n');
    return b.toString();
  }

  void _writeElement(
    StringBuffer b,
    ReportElement e,
    String pad,
    String Function(double) len,
    String Function(double) pt,
  ) {
    final Map<String, String> common = <String, String>{
      if (e.name != null && e.name!.isNotEmpty) 'name': e.name!,
    };
    Map<String, String> box() => <String, String>{
      'x': len(e.x),
      'y': len(e.y),
      'width': len(e.width),
      'height': len(e.height),
    };
    final Map<String, String> tail = <String, String>{
      if (e.visibleWhen != null) 'visibleWhen': e.visibleWhen!,
      ...e.extraAttributes,
    };
    String align(ReportTextAlign a) => a.name;
    Map<String, String> styleAttrs(String prefix, ReportTextStyle style) =>
        <String, String>{
          if (style.fontFamily != null && style.fontFamily!.trim().isNotEmpty)
            '${prefix}Font': style.fontFamily!.trim(),
          if (style.fontSize != null) '${prefix}Size': pt(style.fontSize!),
          if (style.bold == true) '${prefix}Bold': 'true',
          if (style.italic == true) '${prefix}Italic': 'true',
          if (style.color != null && style.color!.trim().isNotEmpty)
            '${prefix}Color': style.color!.trim(),
        };
    switch (e) {
      case ReportTextElement():
        final ReportTextStyle s = e.style;
        final Map<String, String> a = <String, String>{
          'type': 'Text',
          ...common,
          ...box(),
          if (s.fontFamily != null) 'fontFamily': s.fontFamily!,
          if (s.fontSize != null) 'fontSize': pt(s.fontSize!),
          if (s.bold != null) 'bold': '${s.bold}',
          if (s.italic != null) 'italic': '${s.italic}',
          if (s.underline != null) 'underline': '${s.underline}',
          if (s.color != null) 'color': s.color!,
          if (e.background != null) 'background': e.background!,
          if (e.align != ReportTextAlign.start) 'alignment': align(e.align),
          if (e.verticalAlign != ReportVerticalAlign.top)
            'verticalAlignment': e.verticalAlign.name,
          if (e.direction != ReportTextDirection.auto)
            'direction': e.direction.name,
          if (!e.canGrow) 'canGrow': 'false',
          if (e.canShrink) 'canShrink': 'true',
          if (!e.wordWrap) 'wordWrap': 'false',
          if (e.format != null) 'format': e.format!,
          if (e.padding != 0) 'padding': '${pt(e.padding)}pt',
          if (e.borderColor != null) 'borderColor': e.borderColor!,
          if (e.borderWidth != 0) 'borderWidth': '${pt(e.borderWidth)}pt',
          if (e.lineSpacing != 1.0) 'lineSpacing': pt(e.lineSpacing),
          ...tail,
        };
        if (e.runs.isNotEmpty) {
          b.write('$pad<Element${_attrs(a)}>\n');
          for (final ReportTextRun run in e.runs) {
            b.write(
              '$pad$indent<Run${_attrs(<String, String>{if (run.bold == true) 'bold': 'true', if (run.italic == true) 'italic': 'true', if (run.fontSize != null) 'fontSize': pt(run.fontSize!), if (run.color != null) 'color': run.color!, if (run.underline == true) 'underline': 'true', if (run.link != null && run.link!.isNotEmpty) 'link': run.link!})}>${encodeXmlText(run.text)}</Run>\n',
            );
          }
          b.write('$pad</Element>\n');
        } else if (e.text.isEmpty) {
          b.write('$pad<Element${_attrs(a)}/>\n');
        } else {
          final String body = e.text.contains('\n')
              ? '\n${e.text.split('\n').map((String l) => '$pad$indent${encodeXmlText(l)}').join('\n')}\n$pad'
              : '\n$pad$indent${encodeXmlText(e.text)}\n$pad';
          b.write('$pad<Element${_attrs(a)}>$body</Element>\n');
        }
      case ReportImageElement():
        b.write(
          '$pad<Element${_attrs(<String, String>{'type': 'Image', ...common, ...box(), 'src': e.source, if (e.fit != ReportImageFit.contain) 'fit': e.fit.name, if (e.borderColor != null) 'borderColor': e.borderColor!, if (e.borderWidth != 0) 'borderWidth': '${pt(e.borderWidth)}pt', if (e.background != null) 'background': e.background!, ...tail})}/>\n',
        );
      case ReportBarcodeElement():
        b.write(
          '$pad<Element${_attrs(<String, String>{'type': 'Barcode', ...common, ...box(), 'symbology': e.symbology.name, 'value': e.data, if (e.showText != (e.symbology != ReportBarcodeType.qr)) 'showText': '${e.showText}', if (e.color != null) 'color': e.color!, if (e.background != null) 'background': e.background!, if (e.fontSize != 8) 'fontSize': pt(e.fontSize), ...tail})}/>\n',
        );
      case ReportShapeElement():
        final Map<String, String> geometry = e.kind == ReportShapeKind.line
            ? <String, String>{
                'x1': len(e.start.x),
                'y1': len(e.start.y),
                'x2': len(e.end.x),
                'y2': len(e.end.y),
              }
            : box();
        b.write(
          '$pad<Element${_attrs(<String, String>{'type': 'Shape', 'kind': switch (e.kind) {
            ReportShapeKind.line => 'Line',
            ReportShapeKind.rectangle => 'Rectangle',
            ReportShapeKind.roundedRectangle => 'RoundedRectangle',
            ReportShapeKind.ellipse => 'Ellipse',
          }, ...common, ...geometry, 'strokeWidth': pt(e.strokeWidth), if (e.strokeColor != null) 'color': e.strokeColor!, if (e.fill != null) 'fill': e.fill!, if (e.cornerRadius != 0 && e.kind == ReportShapeKind.roundedRectangle) 'cornerRadius': '${pt(e.cornerRadius)}pt', if (e.lineStyle != ReportLineStyle.solid) 'lineStyle': e.lineStyle.name, ...tail})}/>\n',
        );
      case ReportTableElement():
        final Map<String, String> a = <String, String>{
          ...common,
          'x': len(e.x),
          'y': len(e.y),
          'width': len(e.width),
          'showGrid': '${e.showGrid}',
          if (e.borderColor != null) 'borderColor': e.borderColor!,
          if (e.borderWidth != 0.5) 'borderWidth': '${pt(e.borderWidth)}pt',
          if (e.headerBackground != null)
            'headerBackground': e.headerBackground!,
          if (e.headerColor != null) 'headerColor': e.headerColor!,
          if (!e.headerBold) 'headerBold': 'false',
          if (e.fontSize != null) 'fontSize': pt(e.fontSize!),
          if (e.headerFontSize != null) 'headerFontSize': pt(e.headerFontSize!),
          if (e.fontFamily != null) 'fontFamily': e.fontFamily!,
          if (e.color != null) 'color': e.color!,
          if (e.rowHeight != null) 'rowHeight': len(e.rowHeight!),
          if (e.headerHeight != null) 'headerHeight': len(e.headerHeight!),
          if (e.stripeColor != null) 'stripeColor': e.stripeColor!,
          if (!e.repeatHeader) 'repeatHeader': 'false',
          if (!e.showHeader) 'showHeader': 'false',
          if (e.padding != 3) 'padding': '${pt(e.padding)}pt',
          if (e.dataSet != null) 'dataSet': e.dataSet!,
          ...tail,
        };
        final String p2 = '$pad$indent';
        final String p3 = '$p2$indent';
        b.write('$pad<Table${_attrs(a)}>\n');
        b.write('$p2<Columns>\n');
        for (final ReportTableColumn c in e.columns) {
          b.write(
            '$p3<Column${_attrs(<String, String>{if (c.width != null) 'width': len(c.width!), 'header': c.header, 'align': align(c.align), if (c.headerAlign != null) 'headerAlign': align(c.headerAlign!)})}/>\n',
          );
        }
        b.write('$p2</Columns>\n');
        void cells(String tag, List<ReportTableCell> list) {
          if (list.isEmpty) {
            return;
          }
          b.write('$p2<$tag>\n');
          for (final ReportTableCell c in list) {
            b.write(
              '$p3<Cell${_attrs(<String, String>{if (c.field != null) 'field': c.field!, if (c.field == null) 'text': c.text ?? '', if (c.format != null) 'format': c.format!, if (c.bold != null) 'bold': '${c.bold}', if (c.italic != null) 'italic': '${c.italic}', if (c.color != null) 'color': c.color!, if (c.background != null) 'background': c.background!, if (c.align != null) 'align': align(c.align!)})}/>\n',
            );
          }
          b.write('$p2</$tag>\n');
        }

        cells('RowTemplate', e.cells);
        cells('FooterRow', e.footerCells);
        b.write('$pad</Table>\n');
      case ReportChartElement():
        final Map<String, String> a = <String, String>{
          ...common,
          ...box(),
          'chartType': e.chartType.name,
          if (e.title.isNotEmpty) 'title': e.title,
          if (e.dataSet != null) 'dataSet': e.dataSet!,
          if (e.category != null) 'category': e.category!,
          if (e.aggregate != ReportChartAggregate.sum)
            'aggregate': e.aggregate.name,
          if (e.sortBy != ReportChartSort.none) 'sortBy': e.sortBy.name,
          if (e.descending) 'sortOrder': 'desc',
          if (e.limit > 0) 'limit': '${e.limit}',
          if (!e.showLegend) 'showLegend': 'false',
          if (e.showValues) 'showValues': 'true',
          if (!e.showGrid) 'showGrid': 'false',
          if (!e.showAxes) 'showAxes': 'false',
          if (e.valueFormat != null) 'valueFormat': e.valueFormat!,
          if (e.fontSize != 7.5) 'fontSize': pt(e.fontSize),
          if (e.fontFamily != null) 'fontFamily': e.fontFamily!,
          if (e.bold) 'bold': 'true',
          if (e.italic) 'italic': 'true',
          if (e.textColor != null) 'color': e.textColor!,
          if (e.background != null) 'background': e.background!,
          if (e.borderColor != null) 'borderColor': e.borderColor!,
          if (e.borderWidth != 0) 'borderWidth': '${pt(e.borderWidth)}pt',
          if (e.palette.isNotEmpty) 'palette': e.palette.join(','),
          if (e.depth != 14) 'depth': pt(e.depth),
          if (e.skew != 32) 'skew': '${e.skew}',
          if (e.hole != 0.58) 'hole': '${e.hole}',
          if (e.startAngle != -90) 'startAngle': '${e.startAngle}',
          if (e.smooth) 'smooth': 'true',
          if (e.showMarkers != null) 'showMarkers': '${e.showMarkers}',
          if (e.markerSize != 2.6) 'markerSize': pt(e.markerSize),
          if (e.lineWidth != 1.6) 'lineWidth': pt(e.lineWidth),
          if (e.axisMin != null) 'axisMin': '${e.axisMin}',
          if (e.axisMax != null) 'axisMax': '${e.axisMax}',
          if (e.axisMin2 != null) 'axisMin2': '${e.axisMin2}',
          if (e.axisMax2 != null) 'axisMax2': '${e.axisMax2}',
          if (e.target != null) 'target': e.target!,
          if (e.showPercent) 'showPercent': 'true',
          if (e.lastIsTotal) 'lastIsTotal': 'true',
          if (e.bands != 3) 'bands': '${e.bands}',
          if (e.increaseColor != null) 'increaseColor': e.increaseColor!,
          if (e.decreaseColor != null) 'decreaseColor': e.decreaseColor!,
          if (e.totalColor != null) 'totalColor': e.totalColor!,
          if (e.shape != 'world') 'shape': e.shape,
          if (e.shapeKey != null && e.shapeKey!.isNotEmpty)
            'shapeKey': e.shapeKey!,
          if (e.lowColor != null) 'lowColor': e.lowColor!,
          if (e.highColor != null) 'highColor': e.highColor!,
          if (e.emptyColor != null) 'emptyColor': e.emptyColor!,
          if (!e.showLabels) 'showLabels': 'false',
          if (e.labelField != null && e.labelField!.isNotEmpty)
            'labelField': e.labelField!,
          ...styleAttrs('title', e.titleStyle),
          ...styleAttrs('label', e.labelStyle),
          ...styleAttrs('legend', e.legendStyle),
          if (e.regionColor != null && e.regionColor!.isNotEmpty)
            'regionColor': e.regionColor!,
          ...tail,
        };
        if (e.series.isEmpty && e.points.isEmpty) {
          b.write('$pad<Chart${_attrs(a)}/>\n');
          return;
        }
        final String p2 = '$pad$indent';
        b.write('$pad<Chart${_attrs(a)}>\n');
        for (final ReportChartSeries s in e.series) {
          b.write(
            '$p2<Series${_attrs(<String, String>{if (s.name.isNotEmpty) 'name': s.name, 'value': s.value, if (s.color != null) 'color': s.color!, if (s.x != null) 'x': s.x!, if (s.size != null) 'size': s.size!, if (s.style != ReportSeriesStyle.column) 'style': s.style.name, if (s.secondary) 'secondary': 'true'})}/>\n',
          );
        }
        for (final ReportChartPoint p in e.points) {
          b.write(
            '$p2<Point${_attrs(<String, String>{'label': p.label, 'value': p.value, if (p.color != null) 'color': p.color!, if (p.x != null) 'x': p.x!, if (p.size != null) 'size': p.size!, if (p.total) 'total': 'true'})}/>\n',
          );
        }
        b.write('$pad</Chart>\n');
      case ReportCrosstabElement():
        b.write(
          '$pad<Crosstab${_attrs(<String, String>{...common, ...box(), if (e.dataSet != null) 'dataSet': e.dataSet!, 'rowField': e.rowField, 'columnField': e.columnField, 'valueField': e.valueField, if (e.aggregate != ReportChartAggregate.sum) 'aggregate': e.aggregate.name, if (e.maxColumns != 12) 'maxColumns': '${e.maxColumns}', if (e.fontSize != 9) 'fontSize': pt(e.fontSize), if (!e.headerBold) 'headerBold': 'false', ...tail})}/>\n',
        );
      case ReportSubreportElement():
        b.write(
          '$pad<Subreport${_attrs(<String, String>{...common, ...box(), 'template': e.templateName, if (e.dataSet != null) 'dataSet': e.dataSet!, ...tail})}/>\n',
        );
    }
  }

  static String _attrs(Map<String, String> attrs) {
    final StringBuffer b = StringBuffer();
    for (final MapEntry<String, String> e in attrs.entries) {
      b.write(' ${e.key}="${encodeXmlAttribute(e.value)}"');
    }
    return b.toString();
  }
}
