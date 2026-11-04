/// Public entry point: `.qrep` template → PDF / XLSX / DOCX.
library;

import 'dart:typed_data';

import '../pdf/pdf_save_options.dart';
import 'report_data.dart';
import 'report_docx_writer.dart';
import 'report_expression.dart';
import 'report_expression_engine.dart';
import 'report_font_file.dart';
import 'report_fonts.dart';
import 'report_format.dart';
import 'report_generator.dart';
import 'report_layout.dart';
import 'report_package.dart';
import 'report_pdf_writer.dart';
import 'report_template.dart';
import 'report_value.dart';
import 'report_xlsx_writer.dart';
import 'report_xml.dart';

/// Output format of [QudsReportEngine.export].
enum ReportExportFormat {
  /// PDF document.
  pdf,

  /// Excel workbook.
  xlsx,

  /// Word document.
  docx,
}

/// Thrown by the named-element API ([QudsReportEngine.element] and the
/// setters) when no element has the name or it is of another type.
class ReportElementException implements Exception {
  /// ReportElementException API.
  const ReportElementException(this.message);

  /// message API.
  final String message;

  @override
  String toString() => 'ReportElementException: $message';
}

/// Band report engine.
///
/// ```dart
/// final engine = QudsReportEngine.fromXml(templateXml, fonts: fonts);
/// final Uint8List pdf = await engine.exportToPdf(<String, Object?>{
///   'invoiceNo': 'INV-2026-001',
///   'items': <Map<String, Object?>>[
///     <String, Object?>{'code': 'P01', 'qty': 1, 'price': 500, 'total': 500},
///   ],
/// });
/// ```
///
/// Data is converted once into typed [ReportValue]s (maps → records,
/// iterables → lists). The template is read at export time, so a designer
/// can keep editing [template] and re-export.
///
/// Hosts can also feed the report piece by piece: put values in [data],
/// address elements by their unique name, then export.
///
/// ```dart
/// final engine = QudsReportEngine.fromPackage(qrepBytes, fonts: fonts);
/// engine.data
///   ..set('customer.name', 'Northwind Traders')
///   ..setTable('items', rows);
/// engine.setText('title', 'Quarterly invoice');
/// engine.elementAs<ReportTextElement>('title').style.color = '#C00000';
/// engine.setImage('logo', logoPng);
/// engine.setVisible('discountNote', false);
/// final Uint8List pdf = await engine.export(ReportExportFormat.pdf);
/// ```
class QudsReportEngine {
  /// QudsReportEngine API.
  QudsReportEngine(
    this.template, {
    ReportFontRegistry? fonts,
    Map<String, Uint8List>? images,
    Map<String, Uint8List>? shapes,
    this.userName = '',
    this.clock,
    Map<String, ReportFunction>? functions,
    Map<String, Object?>? variables,
    this.strict = false,
    this.diagnostics = const <ReportDiagnostic>[],
    Map<String, ReportFontFiles>? embeddedFonts,
    ReportData? data,
    this.sampleData,
  }) : data = data ?? ReportData(),
       embeddedFonts = embeddedFonts ?? <String, ReportFontFiles>{},
       fonts = fonts ?? ReportFontRegistry(),
       images = images ?? <String, Uint8List>{},
       shapes = shapes ?? <String, Uint8List>{},
       functions = functions ?? <String, ReportFunction>{},
       variables = variables ?? <String, Object?>{};

  /// Parses [xml]; throws [ReportTemplateException] when it has errors.
  factory QudsReportEngine.fromXml(
    String xml, {
    ReportFontRegistry? fonts,
    Map<String, Uint8List>? images,
    Map<String, Uint8List>? shapes,
    String userName = '',
    DateTime Function()? clock,
    Map<String, ReportFunction>? functions,
    Map<String, Object?>? variables,
    bool strict = false,
  }) {
    final ReportParseResult parsed = QudsReportXmlParser().parse(xml);
    return QudsReportEngine(
      parsed.templateOrThrow,
      fonts: fonts,
      images: images,
      shapes: shapes,
      userName: userName,
      clock: clock,
      functions: functions,
      variables: variables,
      strict: strict,
      diagnostics: parsed.diagnostics,
    );
  }

  /// Opens `.qrep` bytes (package ZIP or legacy plain XML).
  ///
  /// The package's embedded images and fonts are used; [images] and [fonts]
  /// add to them and win on name clashes ([fonts] is not modified). Throws
  /// [ReportPackageException] for a damaged package and
  /// [ReportTemplateException] when the layout has errors.
  factory QudsReportEngine.fromPackage(
    Uint8List bytes, {
    ReportFontRegistry? fonts,
    Map<String, Uint8List>? images,
    String userName = '',
    DateTime Function()? clock,
    Map<String, ReportFunction>? functions,
    Map<String, Object?>? variables,
    bool strict = false,
  }) {
    final ReportPackage package = ReportPackage.decode(bytes);
    final ReportParseResult parsed = QudsReportXmlParser().parse(package.xml);
    final ReportTemplate template = parsed.templateOrThrow
      ..subreports.addAll(package.subreports);
    return QudsReportEngine(
      template,
      fonts: package.fontRegistry(base: fonts),
      images: <String, Uint8List>{...package.images, ...?images},
      shapes: package.shapes,
      userName: userName,
      clock: clock,
      functions: functions,
      variables: variables,
      strict: strict,
      diagnostics: parsed.diagnostics,
      embeddedFonts: package.fonts,
      sampleData: package.sampleData,
    );
  }

  /// Template being generated (mutable; edits apply to the next export).
  final ReportTemplate template;

  /// Fonts used for shaping and PDF embedding.
  final ReportFontRegistry fonts;

  /// Named images (`<Image source="logo"/>`).
  final Map<String, Uint8List> images;

  /// Embedded shape layers (`shape="districts"` on a shape map).
  final Map<String, Uint8List> shapes;

  /// TrueType files written into [toPackage] (the fonts of a package opened
  /// with [QudsReportEngine.fromPackage]). They must already be in [fonts]
  /// to affect exports.
  final Map<String, ReportFontFiles> embeddedFonts;

  /// `System.UserName`.
  final String userName;

  /// Clock for `System.CurrentDate` (tests pin it).
  final DateTime Function()? clock;

  /// Host functions callable from expressions.
  final Map<String, ReportFunction> functions;

  /// Host values overriding template `<Variables>`.
  final Map<String, Object?> variables;

  /// Throw on expression errors instead of printing `#ERR`.
  final bool strict;

  /// Parser warnings from [QudsReportEngine.fromXml].
  final List<ReportDiagnostic> diagnostics;

  /// Data fed by the host, merged under the map passed to an export (the
  /// passed map wins on conflicts).
  final ReportData data;

  /// Design-time data saved in the package (`data/sample.json`); exports do
  /// not use it unless the host passes it.
  Map<String, Object?>? sampleData;

  /// Expression engine with the template's display formats.
  QudsExpressionEngine get expressions => QudsExpressionEngine(
    formatter: ReportFormatter(defaults: template.formats),
    functions: functions,
  );

  /// Serializes [template] back to `.qrep` XML.
  String toXml() => const QudsReportXmlWriter().write(template);

  /// `.qrep` package bytes: [template], every entry of [images], and
  /// [embeddedFonts].
  Uint8List toPackage() => ReportPackage(
    xml: toXml(),
    images: images,
    fonts: embeddedFonts,
    shapes: shapes,
    sampleData: sampleData,
  ).encode();

  /// Static checks: every placeholder parses and calls known functions.
  List<ReportDiagnostic> validate() {
    final QudsExpressionEngine engine = expressions;
    final List<ReportDiagnostic> out = <ReportDiagnostic>[];
    void check(String path, String? source, {bool expression = false}) {
      if (source == null || source.trim().isEmpty) {
        return;
      }
      final List<ReportExpression> exprs = <ReportExpression>[];
      try {
        if (expression && !source.contains('{{')) {
          exprs.add(ReportExpression.parse(source));
        } else {
          exprs.addAll(ReportTemplateText.parse(source).expressions);
        }
      } on ReportExpressionException catch (e) {
        out.add(
          ReportDiagnostic(ReportDiagnosticSeverity.error, path, e.message),
        );
        return;
      }
      for (final ReportExpression x in exprs) {
        for (final String fn in ReportExpression.functions(x.root)) {
          if (!engine.knowsFunction(fn)) {
            out.add(
              ReportDiagnostic(
                ReportDiagnosticSeverity.error,
                path,
                'Unknown function $fn() in "${x.source}"',
              ),
            );
          }
        }
      }
    }

    for (final String n in template.duplicateElementNames) {
      out.add(
        ReportDiagnostic(
          ReportDiagnosticSeverity.warning,
          'Bands',
          'Element name "$n" is used more than once',
        ),
      );
    }
    for (final ReportDataTable table in template.dataSchema.tables) {
      for (final ReportDataColumn c in table.columns) {
        if (c.isCalculated) {
          check(
            'DataSchema/${table.name}/${c.name}',
            c.expression,
            expression: true,
          );
        }
      }
    }
    for (final ReportVariable v in template.variables) {
      final String path = 'Variables/${v.name}';
      switch (v.type) {
        case ReportVariableType.text:
          check(path, v.value);
        case ReportVariableType.expression:
          check(path, v.value, expression: true);
        case ReportVariableType.number:
        case ReportVariableType.boolean:
        case ReportVariableType.date:
        case ReportVariableType.list:
          final String? err = v.error;
          if (err != null) {
            out.add(
              ReportDiagnostic(ReportDiagnosticSeverity.error, path, err),
            );
          }
      }
    }
    for (final ReportBand b in template.bands) {
      final String bp = 'Bands/${b.kind.xmlName}';
      check('$bp@dataSet', b.dataSet, expression: true);
      check('$bp@groupBy', b.groupBy, expression: true);
      check('$bp@filter', b.filter, expression: true);
      check('$bp@visibleWhen', b.visibleWhen, expression: true);
      final String? sortBy = b.sortBy;
      if (sortBy != null) {
        for (final ({String source, bool? descending}) key
            in ReportExpression.sortKeys(sortBy)) {
          check('$bp@sortBy', key.source, expression: true);
        }
      }
      for (int i = 0; i < b.elements.length; i++) {
        final ReportElement e = b.elements[i];
        final String ep = '$bp/${e.displayName}[$i]';
        check('$ep@visibleWhen', e.visibleWhen, expression: true);
        switch (e) {
          case ReportTextElement(:final String text):
            check(ep, text);
          case ReportImageElement(:final String source):
            check(ep, source);
          case ReportBarcodeElement(:final String data):
            check(ep, data);
          case ReportTableElement():
            check('$ep@dataSet', e.dataSet, expression: true);
            for (int c = 0; c < e.columns.length; c++) {
              check('$ep/Column[$c]', e.columns[c].header);
            }
            for (int c = 0; c < e.cells.length; c++) {
              check('$ep/Cell[$c]', e.cells[c].template);
            }
            for (int c = 0; c < e.footerCells.length; c++) {
              check('$ep/FooterCell[$c]', e.footerCells[c].template);
            }
          case ReportShapeElement():
            break;
          case ReportChartElement():
            check('$ep@dataSet', e.dataSet, expression: true);
            check('$ep@title', e.title);
            check('$ep@category', e.category, expression: true);
            for (int s = 0; s < e.series.length; s++) {
              check('$ep/Series[$s]', e.series[s].name);
              check(
                '$ep/Series[$s]@value',
                e.series[s].value,
                expression: true,
              );
            }
            for (int p = 0; p < e.points.length; p++) {
              check('$ep/Point[$p]', e.points[p].label);
              check('$ep/Point[$p]@value', e.points[p].value, expression: true);
            }
          case ReportCrosstabElement():
            check('$ep@dataSet', e.dataSet, expression: true);
            check('$ep@rowField', e.rowField, expression: true);
            check('$ep@columnField', e.columnField, expression: true);
            check('$ep@valueField', e.valueField, expression: true);
          case ReportSubreportElement():
            check('$ep@dataSet', e.dataSet, expression: true);
        }
      }
    }
    return out;
  }

  ReportGenerator _generator(QudsExpressionEngine engine, DateTime now) {
    return ReportGenerator(
      template: template,
      engine: engine,
      shaper: ReportTextShaper(fonts),
      images: images,
      shapes: shapes,
      now: now,
      userName: userName,
      variableOverrides: <String, ReportValue>{
        for (final MapEntry<String, Object?> e in variables.entries)
          e.key: ReportValue.from(e.value),
      },
      strict: strict,
    );
  }

  static ReportRecord _record(Map<String, Object?> data) {
    final ReportValue v = ReportValue.from(data);
    return v is ReportRecord ? v : ReportRecord.empty;
  }

  /// [data] merged over the host [QudsReportEngine.data], converted to
  /// typed values, with [ReportTemplate.dataSchema] applied: field and
  /// column types coerced (`'12.5'` → 12.5) and calculated columns added to
  /// every row. This is what exports and the designer's data explorer see.
  ReportRecord prepare([Map<String, Object?>? data]) {
    final QudsExpressionEngine engine = expressions;
    return _prepare(
      data,
      engine,
      _generator(engine, clock?.call() ?? DateTime.now()),
    );
  }

  ReportRecord _prepare(
    Map<String, Object?>? data,
    QudsExpressionEngine engine,
    ReportGenerator generator,
  ) {
    final Map<String, Object?> merged;
    if (this.data.values.isEmpty) {
      merged = data ?? const <String, Object?>{};
    } else if (data == null || data.isEmpty) {
      merged = this.data.values;
    } else {
      merged = (ReportData(this.data.toMap())..merge(data)).values;
    }
    final ReportRecord record = _record(merged);
    final ReportDataSchema schema = template.dataSchema;
    if (schema.isEmpty) {
      return record;
    }
    return _applySchema(record, schema, engine, generator);
  }

  ReportRecord _applySchema(
    ReportRecord root,
    ReportDataSchema schema,
    QudsExpressionEngine engine,
    ReportGenerator generator,
  ) {
    var out = root;
    for (final ReportDataField f in schema.fields) {
      out = _updateAt(out, _path(f.name), f.type.coerceValue);
    }
    for (final ReportDataTable table in schema.tables) {
      final List<(ReportDataColumn, ReportExpression?)> calculated =
          <(ReportDataColumn, ReportExpression?)>[];
      for (final ReportDataColumn c in table.columns) {
        if (!c.isCalculated) {
          continue;
        }
        try {
          calculated.add((c, ReportExpression.parse(c.expression!)));
        } on ReportExpressionException {
          if (strict) {
            rethrow;
          }
          calculated.add((c, null));
        }
      }
      final ReportScope base = generator.baseScope(out);
      out = _updateAt(out, _path(table.name), (ReportValue value) {
        if (value is! ReportList) {
          return value;
        }
        return ReportList(<ReportValue>[
          for (int i = 0; i < value.items.length; i++)
            _row(value.items[i], i, table, calculated, engine, base),
        ]);
      });
    }
    return out;
  }

  ReportValue _row(
    ReportValue row,
    int index,
    ReportDataTable table,
    List<(ReportDataColumn, ReportExpression?)> calculated,
    QudsExpressionEngine engine,
    ReportScope base,
  ) {
    if (row is! ReportRecord) {
      return row;
    }
    final Map<String, ReportValue> fields = Map<String, ReportValue>.of(
      row.fields,
    );
    for (final ReportDataColumn c in table.columns) {
      if (c.isCalculated || c.type == ReportDataType.text) {
        continue;
      }
      final String? key = _key(fields, c.name);
      if (key != null) {
        fields[key] = c.type.coerceValue(fields[key]!);
      }
    }
    for (final (ReportDataColumn c, ReportExpression? x) in calculated) {
      ReportValue v = ReportNull.instance;
      if (x != null) {
        try {
          v = engine.evaluate(
            x,
            base.copyWith(
              row: ReportRecord(fields),
              rowIndex: index,
              datasetPath: table.name,
            ),
          );
        } on ReportExpressionException {
          if (strict) {
            rethrow;
          }
        }
      }
      fields[_key(fields, c.name) ?? c.name] = c.type == ReportDataType.text
          ? v
          : c.type.coerceValue(v);
    }
    return ReportRecord(fields);
  }

  static List<String> _path(String path) => <String>[
    for (final String s in ReportData.normalizePath(path).split('.'))
      if (s.isNotEmpty) s,
  ];

  static String? _key(Map<String, ReportValue> fields, String name) {
    if (fields.containsKey(name)) {
      return name;
    }
    final String lower = name.toLowerCase();
    for (final String k in fields.keys) {
      if (k.toLowerCase() == lower) {
        return k;
      }
    }
    return null;
  }

  /// [root] with the value at [path] replaced by [update] (unchanged when
  /// the path does not exist).
  static ReportRecord _updateAt(
    ReportRecord root,
    List<String> path,
    ReportValue Function(ReportValue) update,
  ) {
    if (path.isEmpty) {
      return root;
    }
    final String? key = _key(root.fields, path.first);
    if (key == null) {
      return root;
    }
    final ReportValue current = root.fields[key]!;
    final ReportValue next;
    if (path.length == 1) {
      next = update(current);
    } else if (current is ReportRecord) {
      next = _updateAt(current, path.sublist(1), update);
    } else {
      return root;
    }
    if (identical(next, current)) {
      return root;
    }
    return ReportRecord(<String, ReportValue>{...root.fields, key: next});
  }

  /// Paginated layout (what the PDF writer and the designer preview paint).
  ReportDocumentLayout layout(Map<String, Object?> data) {
    final QudsExpressionEngine engine = expressions;
    final ReportGenerator generator = _generator(
      engine,
      clock?.call() ?? DateTime.now(),
    );
    final ReportDocumentLayout result = generator.generate(
      _prepare(data, engine, generator),
    );
    if (!fonts.isEmpty) {
      return result;
    }
    return ReportDocumentLayout(
      template: result.template,
      pageWidth: result.pageWidth,
      pageHeight: result.pageHeight,
      pages: result.pages,
      fonts: result.fonts,
      flow: result.flow,
      warnings: <String>[
        'No font registered: only WinAnsi Latin text is drawn (Helvetica)',
        ...result.warnings,
      ],
    );
  }

  /// PDF bytes for [data].
  Uint8List exportToPdfSync(
    Map<String, Object?> data, {
    PdfSaveOptions options = const PdfSaveOptions(),
  }) => ReportPdfWriter(author: userName, options: options).write(layout(data));

  /// PDF bytes for [data].
  Future<Uint8List> exportToPdf(
    Map<String, Object?> data, {
    PdfSaveOptions options = const PdfSaveOptions(),
  }) async => exportToPdfSync(data, options: options);

  /// XLSX bytes for [data].
  Uint8List exportToExcelSync(Map<String, Object?> data) =>
      const ReportXlsxWriter().write(layout(data));

  /// XLSX bytes for [data].
  Future<Uint8List> exportToExcel(Map<String, Object?> data) async =>
      exportToExcelSync(data);

  /// DOCX bytes for [data].
  Uint8List exportToWordSync(Map<String, Object?> data) {
    final QudsExpressionEngine engine = expressions;
    final DateTime now = clock?.call() ?? DateTime.now();
    final ReportGenerator generator = _generator(engine, now);
    final ReportRecord record = _prepare(data, engine, generator);
    final ReportDocumentLayout laid = generator.generate(record);
    return ReportDocxWriter(
      engine: engine,
      scope: generator.baseScope(record, totalPages: laid.pages.length),
    ).write(laid);
  }

  /// DOCX bytes for [data].
  Future<Uint8List> exportToWord(Map<String, Object?> data) async =>
      exportToWordSync(data);

  /// [format] bytes for [data] (merged over the host [QudsReportEngine.data]).
  Uint8List exportSync(
    ReportExportFormat format, {
    Map<String, Object?>? data,
    PdfSaveOptions options = const PdfSaveOptions(),
  }) {
    final Map<String, Object?> d = data ?? const <String, Object?>{};
    return switch (format) {
      ReportExportFormat.pdf => exportToPdfSync(d, options: options),
      ReportExportFormat.xlsx => exportToExcelSync(d),
      ReportExportFormat.docx => exportToWordSync(d),
    };
  }

  /// [format] bytes for [data] (merged over the host [QudsReportEngine.data]).
  Future<Uint8List> export(
    ReportExportFormat format, {
    Map<String, Object?>? data,
    PdfSaveOptions options = const PdfSaveOptions(),
  }) async => exportSync(format, data: data, options: options);

  /// Names of every named element, in band order.
  List<String> get elementNames => <String>[
    for (final (ReportBand _, ReportElement e) in template.allElements)
      if (e.name != null && e.name!.isNotEmpty) e.name!,
  ];

  /// Element named [name] (case-insensitive), or null.
  ReportElement? element(String name) => template.elementNamed(name)?.$2;

  /// Element named [name] as a [T].
  ///
  /// Throws [ReportElementException] when no element has the name or it is
  /// not a [T].
  T elementAs<T extends ReportElement>(String name) => _named<T>(name).$2;

  (ReportBand, T) _named<T extends ReportElement>(String name) {
    final (ReportBand, ReportElement)? pair = template.elementNamed(name);
    if (pair == null) {
      throw ReportElementException('No element named "$name"');
    }
    final (ReportBand band, ReportElement e) = pair;
    if (e is! T) {
      throw ReportElementException(
        'Element "$name" is ${e.displayName}, not $T',
      );
    }
    return (band, e);
  }

  /// Sets the text of text element [name]. `{{ }}` placeholders are still
  /// evaluated; pass [literal] to print [text] exactly as given.
  void setText(String name, String text, {bool literal = false}) {
    elementAs<ReportTextElement>(name).text = literal
        ? text.replaceAll('{{', "{{'{{'}}")
        : text;
  }

  /// Draws [bytes] (PNG / JPEG) in image element [name]: they are stored in
  /// [images] under the element's name.
  void setImage(String name, Uint8List bytes) {
    final ReportImageElement e = elementAs<ReportImageElement>(name);
    final String key = e.name!;
    images[key] = bytes;
    e.source = key;
  }

  /// Sets the encoded value of barcode element [name].
  void setBarcode(String name, String value) {
    elementAs<ReportBarcodeElement>(name).data = value;
  }

  /// Feeds the rows of table element [name]. They go into [data] at the
  /// table's data set path (its band's when it has none; the element name
  /// when neither has one, which then becomes the table's data set).
  void setTableRows(String name, Iterable<Map<String, Object?>> rows) {
    final (ReportBand band, ReportTableElement table) =
        _named<ReportTableElement>(name);
    data.setTable(
      _rowsPath(table, table.dataSet, band, (String p) => table.dataSet = p),
      rows,
    );
  }

  /// Feeds the rows of chart element [name] (same path rules as
  /// [setTableRows]); its series and category read them.
  void setChartRows(String name, Iterable<Map<String, Object?>> rows) {
    final (ReportBand band, ReportChartElement chart) =
        _named<ReportChartElement>(name);
    data.setTable(
      _rowsPath(chart, chart.dataSet, band, (String p) => chart.dataSet = p),
      rows,
    );
  }

  static String _rowsPath(
    ReportElement e,
    String? own,
    ReportBand band,
    void Function(String) assign,
  ) {
    if (own != null && own.trim().isNotEmpty) {
      return own.trim();
    }
    final String? bandSet = band.kind == ReportBandKind.detail
        ? band.dataSet
        : null;
    if (bandSet != null && bandSet.trim().isNotEmpty) {
      return bandSet.trim();
    }
    final String path = e.name!;
    assign(path);
    return path;
  }

  /// Replaces chart [name]'s data with fixed [points] (label → value, in
  /// order); its data set and series are cleared.
  void setChartPoints(String name, Map<String, num> points) {
    final ReportChartElement chart = elementAs<ReportChartElement>(name);
    chart
      ..dataSet = null
      ..series.clear()
      ..points.replaceRange(0, chart.points.length, <ReportChartPoint>[
        for (final MapEntry<String, num> p in points.entries)
          ReportChartPoint(label: p.key, value: '${p.value}'),
      ]);
  }

  /// Shows or hides element [name] in every export.
  void setVisible(String name, bool visible) {
    _named<ReportElement>(name).$2.visibleWhen = visible ? null : 'false';
  }
}
