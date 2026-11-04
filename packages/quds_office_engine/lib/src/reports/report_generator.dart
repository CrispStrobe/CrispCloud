/// Band flow and pagination: template + data → [ReportDocumentLayout].
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../builders/image_fit.dart';
import '../pdf/widgets/pw_barcode.dart';
import '../pdf/widgets/pw_qr.dart';
import 'report_chart.dart';
import 'report_expression.dart';
import 'report_expression_engine.dart';
import 'report_fonts.dart';
import 'report_layout.dart';
import 'report_png.dart';
import 'report_shape.dart';
import 'report_template.dart';
import 'report_units.dart';
import 'report_value.dart';
import 'report_xml.dart';

/// Lays out a [ReportTemplate] against data.
///
/// Flow per page set: report header (page 1), page header, then for every
/// group: group header, detail rows (or the detail table), group footer;
/// finally the report summary. A free-form detail row (no table in the
/// band) honors [ReportBand.newPageBefore] and [ReportBand.newPageAfter],
/// so one record can occupy its own page. Page footers are reserved at the
/// bottom of each page and painted once the page content is known, so they can show
/// page totals. When any text references `System.TotalPages`, layout runs
/// again until the page count is stable.
class ReportGenerator {
  /// ReportGenerator API.
  ReportGenerator({
    required this.template,
    required this.engine,
    required this.shaper,
    Map<String, Uint8List>? images,
    Map<String, Uint8List>? shapes,
    DateTime? now,
    this.userName = '',
    Map<String, ReportValue>? variableOverrides,
    this.strict = false,
  }) : images = images ?? <String, Uint8List>{},
       shapes = shapes ?? <String, Uint8List>{},
       now = now ?? DateTime.now(),
       variableOverrides = variableOverrides ?? <String, ReportValue>{};

  /// template API.
  final ReportTemplate template;

  /// engine API.
  final QudsExpressionEngine engine;

  /// shaper API.
  final ReportTextShaper shaper;

  /// Named image resources (`source="logo"`).
  final Map<String, Uint8List> images;

  /// Embedded shape layers (`shape="districts"`), encoded shape bytes.
  final Map<String, Uint8List> shapes;

  /// `System.CurrentDate` / `CurrentTime`.
  final DateTime now;

  /// `System.UserName`.
  final String userName;

  /// Host values that replace template `<Variables>`.
  final Map<String, ReportValue> variableOverrides;

  /// Throw on expression errors instead of printing `#ERR`.
  final bool strict;

  static const double _eps = 0.01;

  /// Generates the paginated layout for [data].
  ReportDocumentLayout generate(ReportRecord data) {
    final bool paging = _templateUsesPaging();
    var guess = 1;
    _Flow flow = _Flow(this, data, guess)..run();
    if (paging) {
      for (int attempt = 0; attempt < 3; attempt++) {
        final int count = flow.pages.length;
        if (count == guess) {
          break;
        }
        guess = count;
        flow = _Flow(this, data, guess)..run();
      }
    }
    return ReportDocumentLayout(
      template: template,
      pageWidth: template.pageWidth,
      pageHeight: template.pageHeight,
      pages: flow.pages,
      warnings: List<String>.unmodifiable(flow.warnings),
      fonts: shaper.fonts,
      flow: List<ReportFlowEntry>.unmodifiable(flow.entries),
    );
  }

  /// Root scope: data, evaluated `<Variables>` (host overrides win), and
  /// `System.*` for page 1 of [totalPages].
  ReportScope baseScope(
    ReportRecord data, {
    int totalPages = 1,
    List<String>? warnings,
  }) {
    final ReportSystemInfo system = ReportSystemInfo(
      now: now,
      totalPages: totalPages,
      userName: userName,
      reportName: template.name,
    );
    final Map<String, ReportValue> vars = <String, ReportValue>{};
    final List<ReportValue>? detailRows = template.variables.isEmpty
        ? null
        : _variableRows(
            ReportScope(
              data: data,
              variables: ReportRecord.empty,
              system: system,
            ),
          );
    for (final ReportVariable v in template.variables) {
      final ReportValue? host = variableOverrides[v.name];
      if (host != null) {
        vars[v.name] = host;
        continue;
      }
      final ReportValue? literal = v.literal(now: now);
      if (literal != null) {
        vars[v.name] = literal;
        continue;
      }
      final String? invalid =
          v.type == ReportVariableType.text ||
              v.type == ReportVariableType.expression
          ? null
          : v.error;
      if (invalid != null) {
        if (strict) {
          throw ReportExpressionException('Variable ${v.name}: $invalid');
        }
        warnings?.add('Variable ${v.name}: $invalid');
        vars[v.name] = ReportNull.instance;
        continue;
      }
      final ReportScope partial = ReportScope(
        data: data,
        variables: nestVariables(vars),
        system: system,
        aggregateRows: detailRows,
      );
      try {
        vars[v.name] = v.type == ReportVariableType.expression
            ? engine.evaluateSource(v.value.trim(), partial)
            : engine.valueOf(ReportTemplateText.parse(v.value), partial);
      } on ReportExpressionException catch (e) {
        if (strict) {
          rethrow;
        }
        warnings?.add('Variable ${v.name}: $e');
        vars[v.name] = const ReportText('#ERR');
      }
    }
    for (final MapEntry<String, ReportValue> e in variableOverrides.entries) {
      vars.putIfAbsent(e.key, () => e.value);
    }
    return ReportScope(
      data: data,
      variables: nestVariables(vars),
      system: system,
    );
  }

  /// `Variables.*` record for [flat] values keyed by variable name: dotted
  /// names (`stats.sum`) become nested records, so expressions read them as
  /// `Variables.stats.sum`. When a name is both a value and a folder, the
  /// first one wins.
  static ReportRecord nestVariables(Map<String, ReportValue> flat) {
    final Map<String, ReportValue> root = <String, ReportValue>{};
    final Map<ReportRecord, Map<String, ReportValue>> folders =
        Map<ReportRecord, Map<String, ReportValue>>.identity();
    for (final MapEntry<String, ReportValue> e in flat.entries) {
      final List<String> parts = e.key.split('.');
      Map<String, ReportValue>? at = root;
      for (int i = 0; i < parts.length - 1 && at != null; i++) {
        final ReportValue? next = at[parts[i]];
        if (next == null) {
          final Map<String, ReportValue> fields = <String, ReportValue>{};
          final ReportRecord folder = ReportRecord(fields);
          folders[folder] = fields;
          at[parts[i]] = folder;
          at = fields;
        } else {
          at = next is ReportRecord ? folders[next] : null;
        }
      }
      if (at != null) {
        at.putIfAbsent(parts.last, () => e.value);
      }
    }
    return ReportRecord(root);
  }

  /// Rows a variable's `SUM(item.x)` aggregates over: the detail band's data
  /// set before its filter and sort, which may themselves read variables.
  List<ReportValue>? _variableRows(ReportScope scope) {
    final String? path = template.detail?.dataSet?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }
    final ReportValue v;
    try {
      v = engine.evaluateSource(path, scope);
    } on ReportExpressionException {
      return null;
    }
    return switch (v) {
      ReportList(:final List<ReportValue> items) => items,
      ReportNull() => null,
      _ => <ReportValue>[v],
    };
  }

  bool _templateUsesPaging() {
    bool uses(String? s) {
      if (s == null || !s.contains('{{')) {
        return false;
      }
      try {
        return ReportTemplateText.parse(s).usesPaging;
      } on ReportExpressionException {
        return false;
      }
    }

    for (final ReportBand b in template.bands) {
      for (final ReportElement e in b.elements) {
        final bool hit = switch (e) {
          ReportTextElement(:final String text) => uses(text),
          ReportBarcodeElement(:final String data) => uses(data),
          ReportImageElement(:final String source) => uses(source),
          ReportTableElement(
            :final List<ReportTableColumn> columns,
            :final List<ReportTableCell> cells,
            :final List<ReportTableCell> footerCells,
          ) =>
            columns.any((ReportTableColumn c) => uses(c.header)) ||
                cells.any((ReportTableCell c) => uses(c.template)) ||
                footerCells.any((ReportTableCell c) => uses(c.template)),
          ReportShapeElement() => false,
          ReportChartElement(
            :final String title,
            :final List<ReportChartSeries> series,
            :final List<ReportChartPoint> points,
          ) =>
            uses(title) ||
                series.any((ReportChartSeries s) => uses(s.name)) ||
                points.any((ReportChartPoint p) => uses(p.label)),
          ReportCrosstabElement() => false,
          ReportSubreportElement() => false,
        };
        if (hit) {
          return true;
        }
      }
    }
    return false;
  }
}

/// Positioned primitives relative to a band top, plus the band height.
class _Box {
  _Box(
    this.primitives,
    this.height, {
    this.flow = const <ReportFlowItem>[],
    this.entry,
  });

  final List<ReportPrimitive> primitives;
  final double height;

  /// Logical items (relative to the box top).
  final List<ReportFlowItem> flow;

  /// Flow entry recorded when the box is placed.
  final ReportFlowEntry? entry;

  bool get isEmpty => primitives.isEmpty;
}

/// Sort key: expression plus direction.
class _SortKey {
  const _SortKey(this.expression, {required this.descending});

  final ReportExpression expression;
  final bool descending;
}

/// Group of detail rows.
class _Group {
  _Group(this.key, this.rows);

  final ReportValue key;
  final List<ReportValue> rows;
}

/// One layout pass with a fixed `System.TotalPages` guess.
class _Flow {
  _Flow(this.g, this.data, this.totalPages);

  final ReportGenerator g;
  final ReportRecord data;
  final int totalPages;

  final List<ReportPageLayout> pages = <ReportPageLayout>[];
  final List<List<ReportValue>> pageRows = <List<ReportValue>>[];
  final List<String> warnings = <String>[];
  final List<ReportFlowEntry> entries = <ReportFlowEntry>[];

  /// Elements whose primitives move to the next page as one unit.
  final Set<String> _atomic = <String>{};

  late ReportScope base;
  double _cursor = 0;
  double _limit = 0;
  double _freshCursor = 0;

  ReportBand? _repeatGroupBand;
  ReportScope? _repeatGroupScope;
  ReportTableElement? _activeTable;
  ReportScope? _activeTableScope;
  ReportBand? _activeDetail;

  ReportTemplate get t => g.template;

  bool get _fresh => (_cursor - _freshCursor).abs() < ReportGenerator._eps;

  double get _remaining => _limit - _cursor;

  // ---------------------------------------------------------------- flow

  void run() {
    base = _baseScope();
    final ReportBand? detail = t.detail;
    final String? dataset = detail?.dataSet;
    final List<ReportValue> allRows = detail == null
        ? const <ReportValue>[]
        : _prepareRows(detail, base);
    final ReportScope reportScope = base.copyWith(
      aggregateRows: allRows,
      datasetPath: dataset,
      overrideDataset: dataset != null,
    );

    _newPage(firstPage: true);
    final ReportBand? reportHeader = t.band(ReportBandKind.reportHeader);
    if (reportHeader != null &&
        _visible(reportHeader.visibleWhen, reportScope)) {
      _place(_renderBand(reportHeader, _pageScope(reportScope)));
      if (reportHeader.newPageAfter) {
        _newPage();
      }
    }
    _placePageHeader(reportScope, afterReportHeader: true);

    final List<ReportSection> sections = t.sections;
    if (sections.isEmpty && detail != null) {
      _runGroups(detail, allRows);
    } else {
      for (final ReportSection section in sections) {
        final ReportBand? band = section.detail;
        if (band == null) {
          continue;
        }
        _activeDetail = band;
        _runGroups(
          band,
          _prepareRows(band, base),
          header: section.groupHeader,
          footer: section.groupFooter,
        );
        _activeDetail = null;
        _repeatGroupBand = null;
        _repeatGroupScope = null;
      }
    }

    final ReportBand? summary = t.band(ReportBandKind.reportSummary);
    if (summary != null && _visible(summary.visibleWhen, reportScope)) {
      if (summary.newPageBefore && !_fresh) {
        _newPage();
      }
      _place(
        _renderBand(summary, _pageScope(reportScope)),
        keepTogether: summary.keepTogether,
      );
    }
    _finishFooters(dataset);
  }

  ReportScope _baseScope() =>
      g.baseScope(data, totalPages: totalPages, warnings: warnings);

  ReportScope _pageScope(ReportScope scope) => scope.copyWith(
    system: scope.system.copyWith(
      pageNumber: pages.length,
      totalPages: totalPages,
    ),
  );

  void _runGroups(
    ReportBand detail,
    List<ReportValue> rows, {
    ReportBand? header,
    ReportBand? footer,
  }) {
    final ReportBand? groupHeader =
        header ??
        (detail.section == 0 ? t.band(ReportBandKind.groupHeader) : null);
    final ReportBand? groupFooter =
        footer ??
        (detail.section == 0 ? t.band(ReportBandKind.groupFooter) : null);
    final String? groupBy =
        _nonEmpty(detail.groupBy) ?? _nonEmpty(groupHeader?.groupBy);
    final List<_Group> groups = groupBy == null
        ? <_Group>[_Group(ReportNull.instance, rows)]
        : _group(rows, groupBy);
    final String? dataset = detail.dataSet;
    for (int gi = 0; gi < groups.length; gi++) {
      final _Group group = groups[gi];
      final ReportScope gScope = base.copyWith(
        group: ReportGroupInfo(key: group.key, rows: group.rows, index: gi),
        aggregateRows: group.rows,
        datasetPath: dataset,
        overrideDataset: dataset != null,
      );
      if (groupHeader != null && _visible(groupHeader.visibleWhen, gScope)) {
        if (groupHeader.newPageBefore && !_fresh) {
          _newPage();
        }
        final _Box box = _renderBand(groupHeader, _pageScope(gScope));
        final double firstRow = detail.rowHeight ?? detail.height;
        if (box.height + firstRow > _remaining + ReportGenerator._eps &&
            !_fresh) {
          _newPage();
          _place(_renderBand(groupHeader, _pageScope(gScope)));
        } else {
          _place(box);
        }
        if (groupHeader.repeatOnEveryPage) {
          _repeatGroupBand = groupHeader;
          _repeatGroupScope = gScope;
        }
      }
      if (_visible(detail.visibleWhen, gScope)) {
        _runDetail(detail, group.rows, gScope);
      }
      _repeatGroupBand = null;
      _repeatGroupScope = null;
      if (groupFooter != null && _visible(groupFooter.visibleWhen, gScope)) {
        _place(
          _renderBand(groupFooter, _pageScope(gScope)),
          keepTogether: groupFooter.keepTogether,
        );
        if (groupFooter.newPageAfter && gi < groups.length - 1) {
          _newPage();
        }
      }
    }
  }

  void _runDetail(
    ReportBand detail,
    List<ReportValue> rows,
    ReportScope gScope,
  ) {
    ReportTableElement? table;
    for (final ReportElement e in detail.elements) {
      if (e is ReportTableElement && _visible(e.visibleWhen, gScope)) {
        table = e;
        break;
      }
    }
    if (table != null) {
      _runDetailTable(detail, table, rows, gScope);
      return;
    }
    if (detail.dataSet == null) {
      _place(
        _renderBand(detail, _pageScope(gScope)),
        keepTogether: detail.keepTogether,
      );
      return;
    }
    final double rowHeight = detail.rowHeight ?? detail.height;
    for (int i = 0; i < rows.length; i++) {
      if (detail.newPageBefore && !_fresh) {
        _newPage();
      }
      final ReportScope rowScope = gScope.copyWith(row: rows[i], rowIndex: i);
      final _Box box = _renderBand(
        detail,
        _pageScope(rowScope),
        baseHeight: rowHeight,
      );
      _place(box, keepTogether: true);
      pageRows.last.add(rows[i]);
      if (detail.newPageAfter && i < rows.length - 1) {
        _newPage();
      }
    }
  }

  void _runDetailTable(
    ReportBand detail,
    ReportTableElement table,
    List<ReportValue> groupRows,
    ReportScope gScope,
  ) {
    final List<ReportElement> lead = <ReportElement>[];
    final List<ReportElement> trail = <ReportElement>[];
    for (final ReportElement e in detail.elements) {
      if (identical(e, table)) {
        continue;
      }
      (e.y < table.y ? lead : trail).add(e);
    }
    if (lead.isNotEmpty || table.y > 0) {
      final _Box leadBox = _withEntry(
        _renderElements(
          lead,
          _pageScope(gScope),
          detail.kind,
          baseHeight: table.y,
        ),
        detail.kind,
      );
      if (leadBox.height > 0) {
        _place(leadBox);
      }
    }

    final String? tableSet = _nonEmpty(table.dataSet);
    final List<ReportValue> rows =
        tableSet != null && tableSet != detail.dataSet
        ? _datasetRows(tableSet, gScope)
        : groupRows;
    final double minRow = _minBodyRow(table, detail);

    if (table.showHeader) {
      final _Box header = _tableHeader(table, _pageScope(gScope), detail);
      final double need = header.height + (rows.isEmpty ? 0 : minRow);
      if (need > _remaining + ReportGenerator._eps && !_fresh) {
        _newPage();
      }
      _place(header, keepTogether: true);
    }
    _activeTable = table.showHeader && table.repeatHeader ? table : null;
    _activeTableScope = gScope;
    for (int i = 0; i < rows.length; i++) {
      final ReportScope rowScope = gScope.copyWith(row: rows[i], rowIndex: i);
      final _Box box = _tableBodyRow(
        table,
        table.cells,
        _pageScope(rowScope),
        detail,
        stripe: i.isOdd,
        minHeight: minRow,
      );
      if (box.height > _remaining + ReportGenerator._eps && !_fresh) {
        _newPage();
      }
      _place(box);
      pageRows.last.add(rows[i]);
    }
    _activeTable = null;
    _activeTableScope = null;
    if (table.footerCells.isNotEmpty) {
      _place(
        _tableBodyRow(
          table,
          table.footerCells,
          _pageScope(gScope),
          detail,
          stripe: false,
          minHeight: minRow,
          footer: true,
        ),
        keepTogether: true,
      );
    }

    final double tableBottom = table.y + table.height;
    final double rest = detail.height - tableBottom;
    if (trail.isNotEmpty || rest > 0) {
      final _Box trailBox = _withEntry(
        _renderElements(
          trail,
          _pageScope(gScope),
          detail.kind,
          baseHeight: rest > 0 ? rest : 0,
          dy: -tableBottom,
        ),
        detail.kind,
      );
      if (trailBox.height > 0) {
        _place(trailBox);
      }
    }
  }

  // ---------------------------------------------------------------- pages

  void _newPage({bool firstPage = false}) {
    pages.add(ReportPageLayout(pageNumber: pages.length + 1));
    pageRows.add(<ReportValue>[]);
    final int n = pages.length;
    _cursor = t.margins.top;
    _limit = t.pageHeight - t.margins.bottom - _footerReserve(n);
    _freshCursor = _cursor;
    if (firstPage) {
      return;
    }
    _placePageHeader(base, afterReportHeader: false);
  }

  void _placePageHeader(ReportScope scope, {required bool afterReportHeader}) {
    final int n = pages.length;
    final ReportBand? header = t.band(ReportBandKind.pageHeader);
    if (header != null &&
        (n > 1 || header.printOnFirstPage) &&
        _visible(header.visibleWhen, _pageScope(scope))) {
      _emit(_renderBand(header, _pageScope(scope)));
    }
    if (!afterReportHeader) {
      final ReportBand? groupBand = _repeatGroupBand;
      final ReportScope? groupScope = _repeatGroupScope;
      if (groupBand != null && groupScope != null) {
        _emit(_renderBand(groupBand, _pageScope(groupScope)));
      }
      final ReportTableElement? table = _activeTable;
      final ReportScope? tableScope = _activeTableScope;
      final ReportBand? detail = _activeDetail ?? t.detail;
      if (table != null && tableScope != null && detail != null) {
        _emit(_tableHeader(table, _pageScope(tableScope), detail));
      }
    }
    _freshCursor = _cursor;
  }

  double _footerReserve(int pageNumber) {
    final ReportBand? footer = t.band(ReportBandKind.pageFooter);
    if (footer == null || (pageNumber == 1 && !footer.printOnFirstPage)) {
      return 0;
    }
    return footer.designHeight;
  }

  void _finishFooters(String? dataset) {
    final ReportBand? footer = t.band(ReportBandKind.pageFooter);
    if (footer == null) {
      return;
    }
    for (int i = 0; i < pages.length; i++) {
      final int n = i + 1;
      if (n == 1 && !footer.printOnFirstPage) {
        continue;
      }
      if (n == pages.length && !footer.printOnLastPage && pages.length > 1) {
        continue;
      }
      final ReportScope scope = base.copyWith(
        system: base.system.copyWith(pageNumber: n, totalPages: totalPages),
        aggregateRows: pageRows[i],
        datasetPath: dataset,
        overrideDataset: dataset != null,
      );
      if (!_visible(footer.visibleWhen, scope)) {
        continue;
      }
      final _Box box = _renderBand(footer, scope);
      final double top = t.pageHeight - t.margins.bottom - footer.designHeight;
      for (final ReportPrimitive p in box.primitives) {
        pages[i].primitives.add(_move(p, 0, top));
      }
    }
  }

  /// Places [box] at the cursor, breaking pages (and splitting the box when
  /// it is taller than an empty page) as needed.
  void _place(_Box box, {bool keepTogether = false}) {
    final ReportFlowEntry? entry = box.entry;
    if (entry != null) {
      entries.add(entry);
    }
    var current = box;
    if (current.height > _remaining + ReportGenerator._eps && !_fresh) {
      _newPage();
    }
    var guard = 0;
    while (current.height > _remaining + ReportGenerator._eps && guard < 500) {
      guard++;
      final double cut = _remaining;
      if (cut <= 1) {
        break;
      }
      final (_Box first, _Box rest) = _split(current, cut);
      if (first.isEmpty && rest.height >= current.height - 0.5) {
        break;
      }
      _emit(first);
      _newPage();
      current = rest;
    }
    if (keepTogether &&
        current.height > _remaining + ReportGenerator._eps &&
        !_fresh) {
      _newPage();
    }
    _emit(current);
  }

  void _emit(_Box box) {
    final ReportPageLayout page = pages.last;
    for (final ReportPrimitive p in box.primitives) {
      page.primitives.add(_move(p, 0, _cursor));
    }
    _cursor += box.height;
  }

  // ---------------------------------------------------------------- data

  List<ReportValue> _prepareRows(ReportBand detail, ReportScope scope) {
    final String? path = _nonEmpty(detail.dataSet);
    if (path == null) {
      return const <ReportValue>[];
    }
    List<ReportValue> rows = _datasetRows(path, scope);
    final String? filter = _nonEmpty(detail.filter);
    if (filter != null) {
      rows = <ReportValue>[
        for (int i = 0; i < rows.length; i++)
          if (_visible(filter, scope.copyWith(row: rows[i], rowIndex: i)))
            rows[i],
      ];
    }
    final String? sortBy = _nonEmpty(detail.sortBy);
    if (sortBy != null) {
      rows = _sort(rows, sortBy, scope, descending: detail.sortDescending);
    }
    return rows;
  }

  List<ReportValue> _datasetRows(String path, ReportScope scope) {
    final ReportValue v = _evaluate(path, scope);
    return switch (v) {
      ReportList(:final List<ReportValue> items) => items,
      ReportNull() => const <ReportValue>[],
      _ => <ReportValue>[v],
    };
  }

  List<ReportValue> _sort(
    List<ReportValue> rows,
    String spec,
    ReportScope scope, {
    required bool descending,
  }) {
    final List<_SortKey> keys = <_SortKey>[
      for (final ({String source, bool? descending}) k
          in ReportExpression.sortKeys(spec))
        _SortKey(
          ReportExpression.parse(k.source),
          descending: k.descending ?? descending,
        ),
    ];
    final List<List<ReportValue>> values = <List<ReportValue>>[
      for (int i = 0; i < rows.length; i++)
        <ReportValue>[
          for (final _SortKey k in keys)
            _evalParsed(
              k.expression,
              scope.copyWith(row: rows[i], rowIndex: i),
            ),
        ],
    ];
    final List<int> order = List<int>.generate(rows.length, (int i) => i);
    order.sort((int a, int b) {
      for (int k = 0; k < keys.length; k++) {
        final int c = compareReportValues(values[a][k], values[b][k]);
        if (c != 0) {
          return keys[k].descending ? -c : c;
        }
      }
      return a - b;
    });
    return <ReportValue>[for (final int i in order) rows[i]];
  }

  List<_Group> _group(List<ReportValue> rows, String groupBy) {
    final ReportExpression expr = ReportExpression.parse(groupBy);
    final Map<String, _Group> byKey = <String, _Group>{};
    final List<_Group> ordered = <_Group>[];
    for (int i = 0; i < rows.length; i++) {
      final ReportValue key = _evalParsed(
        expr,
        base.copyWith(row: rows[i], rowIndex: i),
      );
      final String k = '${key.runtimeType}:${key.displayText}';
      final _Group group = byKey.putIfAbsent(k, () {
        final _Group created = _Group(key, <ReportValue>[]);
        ordered.add(created);
        return created;
      });
      group.rows.add(rows[i]);
    }
    return ordered;
  }

  // ---------------------------------------------------------------- eval

  ReportValue _evaluate(String source, ReportScope scope) {
    try {
      return source.contains('{{')
          ? g.engine.valueOf(ReportTemplateText.parse(source), scope)
          : g.engine.evaluateSource(source, scope);
    } on ReportExpressionException catch (e) {
      if (g.strict) {
        rethrow;
      }
      warnings.add(e.toString());
      return ReportNull.instance;
    }
  }

  ReportValue _evalParsed(ReportExpression expr, ReportScope scope) {
    try {
      return g.engine.evaluate(expr, scope);
    } on ReportExpressionException catch (e) {
      if (g.strict) {
        rethrow;
      }
      warnings.add(e.toString());
      return ReportNull.instance;
    }
  }

  bool _visible(String? expr, ReportScope scope) {
    final String? s = _nonEmpty(expr);
    return s == null || _evaluate(s, scope).truthy;
  }

  /// Typed value of a template (single placeholder) or its text.
  ReportValue _value(String template, ReportScope scope, String? format) {
    try {
      final ReportTemplateText parsed = ReportTemplateText.parse(template);
      if (format != null && format.isNotEmpty) {
        return ReportText(
          g.engine.formatter.format(g.engine.valueOf(parsed, scope), format),
        );
      }
      return g.engine.valueOf(parsed, scope);
    } on ReportExpressionException catch (e) {
      if (g.strict) {
        rethrow;
      }
      warnings.add(e.toString());
      return const ReportText('#ERR');
    }
  }

  /// Display text plus the typed value it was formatted from.
  ({String text, ReportValue value}) _textValue(
    String template,
    ReportScope scope,
    String? format,
  ) {
    final String? spec = format == null || format.trim().isEmpty
        ? null
        : format;
    if (!template.contains('{{')) {
      final ReportText v = ReportText(template);
      return (
        text: spec == null ? template : g.engine.formatter.format(v, spec),
        value: v,
      );
    }
    final ReportValue v = _value(template, scope, null);
    return (text: g.engine.formatter.format(v, spec), value: v);
  }

  String _text(String template, ReportScope scope, String? format) =>
      _textValue(template, scope, format).text;

  _Box _withEntry(_Box box, ReportBandKind kind) => _Box(
    box.primitives,
    box.height,
    flow: box.flow,
    entry: ReportFlowBand(kind, height: box.height, items: box.flow),
  );

  static String? _nonEmpty(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  // ---------------------------------------------------------------- bands

  _Box _renderBand(ReportBand band, ReportScope scope, {double? baseHeight}) {
    final _Box box = _renderElements(
      band.elements,
      scope,
      band.kind,
      baseHeight: baseHeight ?? band.height,
    );
    final String? bg = band.background;
    if (bg == null || box.height <= 0) {
      return _withEntry(box, band.kind);
    }
    return _withEntry(
      _Box(
        <ReportPrimitive>[
          ReportRectPrimitive(
            bounds: ReportRect(t.margins.left, 0, t.contentWidth, box.height),
            band: band.kind,
            fill: t.resolveColor(bg, ReportColor.transparent),
          ),
          ...box.primitives,
        ],
        box.height,
        flow: box.flow,
      ),
      band.kind,
    );
  }

  /// Lays out [elements] with can-grow push-down.
  ///
  /// An element moves down by the largest (shift + growth) of the elements
  /// that end above its top edge, so grown text never overlaps what follows.
  _Box _renderElements(
    List<ReportElement> elements,
    ReportScope scope,
    ReportBandKind kind, {
    required double baseHeight,
    double dy = 0,
  }) {
    final List<ReportElement> visible = <ReportElement>[
      for (final ReportElement e in elements)
        if (_visible(e.visibleWhen, scope)) e,
    ];
    final int n = visible.length;
    final List<int> order = List<int>.generate(n, (int i) => i)
      ..sort((int a, int b) {
        final int c = visible[a].y.compareTo(visible[b].y);
        return c != 0 ? c : a - b;
      });
    final Float64List tops = Float64List(n);
    final Float64List bottoms = Float64List(n);
    final Float64List growth = Float64List(n);
    final Float64List shift = Float64List(n);
    final List<_Box?> boxes = List<_Box?>.filled(n, null);
    var designBottom = 0.0;
    var finalBottom = 0.0;
    for (int k = 0; k < n; k++) {
      final int i = order[k];
      final ReportElement e = visible[i];
      final double top = e.y + dy;
      final _Box box = _renderElement(e, scope, kind);
      var s = 0.0;
      for (int m = 0; m < k; m++) {
        final int j = order[m];
        if (bottoms[j] <= top + ReportGenerator._eps) {
          final double cand = shift[j] + growth[j];
          if (cand > s) {
            s = cand;
          }
        }
      }
      tops[i] = top;
      bottoms[i] = top + e.height;
      growth[i] = box.height - e.height;
      shift[i] = s;
      boxes[i] = box;
      if (top + e.height > designBottom) {
        designBottom = top + e.height;
      }
      final double fb = top + s + box.height;
      if (fb > finalBottom) {
        finalBottom = fb;
      }
    }
    final double pad = baseHeight - designBottom;
    var height = baseHeight;
    final double needed = finalBottom + (pad > 0 ? pad : 0);
    if (needed > height) {
      height = needed;
    }
    // Paint in document order (z-order); flow items follow reading order.
    final List<ReportPrimitive> out = <ReportPrimitive>[
      for (int i = 0; i < n; i++)
        for (final ReportPrimitive p in boxes[i]!.primitives)
          _move(p, 0, tops[i] + shift[i]),
    ];
    final List<ReportFlowItem> flow = <ReportFlowItem>[
      for (final int i in order)
        for (final ReportFlowItem item in boxes[i]!.flow)
          _moveItem(item, tops[i] + shift[i]),
    ];
    return _Box(
      out,
      height < 0 ? 0 : height,
      flow: _inheritBackdrops(out, flow),
    );
  }

  /// Flow exporters drop free-standing shapes, so transparent text sitting
  /// on a filled shape takes the smallest such fill as its own background
  /// (white heading text on a colored banner stays readable).
  static List<ReportFlowItem> _inheritBackdrops(
    List<ReportPrimitive> primitives,
    List<ReportFlowItem> flow,
  ) {
    final List<ReportRectPrimitive> fills = <ReportRectPrimitive>[
      for (final ReportPrimitive p in primitives)
        if (p is ReportRectPrimitive && (p.fill?.alpha ?? 0) > 0) p,
    ];
    if (fills.isEmpty) {
      return flow;
    }
    return <ReportFlowItem>[
      for (final ReportFlowItem item in flow)
        if (item is ReportFlowText && item.background == null)
          _withBackdrop(item, fills)
        else
          item,
    ];
  }

  static ReportFlowText _withBackdrop(
    ReportFlowText item,
    List<ReportRectPrimitive> fills,
  ) {
    final double cx = item.rect.left + item.rect.width / 2;
    final double cy = item.rect.top + item.rect.height / 2;
    ReportRectPrimitive? best;
    for (final ReportRectPrimitive f in fills) {
      if (f.elementId == item.elementId || !f.bounds.contains(cx, cy)) {
        continue;
      }
      if (best == null ||
          f.bounds.width * f.bounds.height <
              best.bounds.width * best.bounds.height) {
        best = f;
      }
    }
    if (best == null) {
      return item;
    }
    return ReportFlowText(
      elementId: item.elementId,
      rect: item.rect,
      text: item.text,
      value: item.value,
      format: item.format,
      font: item.font,
      color: item.color,
      align: item.align,
      rtl: item.rtl,
      underline: item.underline,
      background: best.fill,
      spans: item.spans,
    );
  }

  static ReportFlowItem _moveItem(ReportFlowItem item, double dy) {
    final ReportRect r = item.rect.translate(0, dy);
    return switch (item) {
      ReportFlowText() => ReportFlowText(
        elementId: item.elementId,
        rect: r,
        text: item.text,
        value: item.value,
        format: item.format,
        font: item.font,
        color: item.color,
        align: item.align,
        rtl: item.rtl,
        underline: item.underline,
        background: item.background,
        spans: item.spans,
      ),
      ReportFlowImage() => ReportFlowImage(
        elementId: item.elementId,
        rect: r,
        bytes: item.bytes,
      ),
      ReportFlowRule() => ReportFlowRule(
        elementId: item.elementId,
        rect: r,
        color: item.color,
        width: item.width,
      ),
      ReportFlowTableBlock() => ReportFlowTableBlock(
        elementId: item.elementId,
        rect: r,
        rows: item.rows,
      ),
      ReportFlowChart() => ReportFlowChart(
        elementId: item.elementId,
        rect: r,
        data: item.data,
      ),
    };
  }

  /// Primitives of one element relative to its own top (y = 0).
  _Box _renderElement(ReportElement e, ReportScope scope, ReportBandKind kind) {
    final double x = t.elementLeft(e.x, e.width);
    return switch (e) {
      ReportTextElement() => _textElement(e, x, scope, kind),
      ReportImageElement() => _imageElement(e, x, scope, kind),
      ReportBarcodeElement() => _barcodeElement(e, x, scope, kind),
      ReportShapeElement() => _shapeElement(e, x, kind),
      ReportTableElement() => _inlineTable(e, scope, kind),
      ReportChartElement() => _chartElement(e, x, scope, kind),
      ReportCrosstabElement() => _crosstabElement(e, scope, kind),
      ReportSubreportElement() => _subreportElement(e, x, scope),
    };
  }

  _Box _crosstabElement(
    ReportCrosstabElement e,
    ReportScope scope,
    ReportBandKind kind,
  ) {
    final String? set = _nonEmpty(e.dataSet);
    final List<ReportValue> rows = set == null
        ? (scope.aggregateRows ?? const <ReportValue>[])
        : _datasetRows(set, scope);
    final List<String> rowKeys = <String>[];
    final List<String> colKeys = <String>[];
    final Map<String, Map<String, List<double>>> grid =
        <String, Map<String, List<double>>>{};
    for (int i = 0; i < rows.length; i++) {
      final ReportScope rs = scope.copyWith(row: rows[i], rowIndex: i);
      final String rowKey = e.rowField.trim().isEmpty
          ? ''
          : g.engine.formatter.display(_evaluate(e.rowField, rs));
      final String colKey = e.columnField.trim().isEmpty
          ? ''
          : g.engine.formatter.display(_evaluate(e.columnField, rs));
      final double value = e.valueField.trim().isEmpty
          ? 0
          : _evaluate(e.valueField, rs).asNumber?.toDouble() ?? 0;
      if (!grid.containsKey(rowKey)) {
        rowKeys.add(rowKey);
        grid[rowKey] = <String, List<double>>{};
      }
      final Map<String, List<double>> cols = grid[rowKey]!;
      if (!cols.containsKey(colKey) && !colKeys.contains(colKey)) {
        colKeys.add(colKey);
      }
      (cols[colKey] ??= <double>[]).add(value);
    }
    final int cap = e.maxColumns < 1 ? 1 : e.maxColumns;
    if (colKeys.length > cap) {
      warnings.add(
        'Crosstab kept $cap of ${colKeys.length} columns',
      );
      colKeys.removeRange(cap, colKeys.length);
    }
    final int n = colKeys.length + 1;
    final double width = e.width > 0 ? e.width : 72.0 * n;
    final ReportTableElement table = ReportTableElement(
      x: e.x,
      y: e.y,
      width: width,
      height: e.height,
      fontSize: e.fontSize,
      headerBold: e.headerBold,
      columns: <ReportTableColumn>[
        for (int i = 0; i < n; i++)
          ReportTableColumn(header: i == 0 ? '' : colKeys[i - 1]),
      ],
    );
    final List<ReportPrimitive> out = <ReportPrimitive>[];
    var y = 0.0;
    void add(_Box b) {
      for (final ReportPrimitive p in b.primitives) {
        out.add(_move(p, 0, y));
      }
      y += b.height;
    }

    add(_tableHeader(table, scope, ReportBand(kind: kind)));
    for (final String rowKey in rowKeys) {
      final Map<String, List<double>> cols =
          grid[rowKey] ?? <String, List<double>>{};
      add(
        _tableBodyRow(
          table,
          <ReportTableCell>[
            ReportTableCell(text: rowKey),
            for (final String col in colKeys)
              ReportTableCell(
                text: g.engine.formatter.display(
                  ReportNumber(_combine(e.aggregate, cols[col] ?? <double>[])),
                ),
              ),
          ],
          scope,
          ReportBand(kind: kind),
          stripe: false,
          minHeight: e.fontSize + 6,
        ),
      );
    }
    return _Box(out, y == 0 ? e.height : y);
  }

  double _combine(ReportChartAggregate aggregate, List<double> values) {
    if (values.isEmpty) {
      return 0;
    }
    switch (aggregate) {
      case ReportChartAggregate.sum:
        return values.fold<double>(0, (double a, double b) => a + b);
      case ReportChartAggregate.avg:
        return values.fold<double>(0, (double a, double b) => a + b) /
            values.length;
      case ReportChartAggregate.count:
        return values.length.toDouble();
      case ReportChartAggregate.min:
        return values.reduce((double a, double b) => a < b ? a : b);
      case ReportChartAggregate.max:
        return values.reduce((double a, double b) => a > b ? a : b);
      case ReportChartAggregate.first:
        return values.first;
      case ReportChartAggregate.last:
        return values.last;
    }
  }

  final Set<String> _subreportStack = <String>{};

  _Box _subreportElement(
    ReportSubreportElement e,
    double x,
    ReportScope scope,
  ) {
    final String name = e.templateName.trim();
    final String? xml = t.subreports[name];
    if (xml == null || xml.isEmpty) {
      warnings.add('Missing subreport "$name"');
      return _Box(const <ReportPrimitive>[], 0);
    }
    if (!_subreportStack.add(name)) {
      warnings.add('Subreport "$name" refers to itself');
      return _Box(const <ReportPrimitive>[], 0);
    }
    try {
      final ReportParseResult parsed = QudsReportXmlParser().parse(xml);
      if (!parsed.readable) {
        warnings.add('Subreport "$name" has errors');
        return _Box(const <ReportPrimitive>[], 0);
      }
      final ReportTemplate child = parsed.template;
      child.subreports.addAll(t.subreports);
      final ReportRecord data = _subreportData(e, scope);
      final ReportDocumentLayout layout = ReportGenerator(
        template: child,
        engine: g.engine,
        shaper: g.shaper,
        images: g.images,
        shapes: g.shapes,
        now: g.now,
        userName: g.userName,
        variableOverrides: g.variableOverrides,
        strict: g.strict,
      ).generate(data);
      final List<ReportPrimitive> out = <ReportPrimitive>[];
      var cursor = 0.0;
      final double content =
          child.pageHeight - child.margins.top - child.margins.bottom;
      for (final ReportPageLayout page in layout.pages) {
        for (final ReportPrimitive p in page.primitives) {
          out.add(_move(p, x - child.margins.left, cursor - child.margins.top));
        }
        cursor += content;
      }
      warnings.addAll(layout.warnings);
      final double height = cursor == 0 ? e.height : cursor;
      if (height > t.pageHeight - t.margins.top - t.margins.bottom) {
        warnings.add('Subreport "$name" is taller than one page');
      }
      return _Box(out, height);
    } on Object catch (err) {
      warnings.add('Subreport "$name" failed: $err');
      return _Box(const <ReportPrimitive>[], 0);
    } finally {
      _subreportStack.remove(name);
    }
  }

  ReportRecord _subreportData(ReportSubreportElement e, ReportScope scope) {
    final String? set = _nonEmpty(e.dataSet);
    if (set == null) {
      final ReportValue? row = scope.row;
      if (row is ReportRecord) {
        return row;
      }
      return scope.data;
    }
    final ReportValue value = _evaluate(set, scope);
    if (value is ReportRecord) {
      return value;
    }
    if (value is ReportList) {
      return ReportRecord(<String, ReportValue>{'items': value});
    }
    return ReportRecord(<String, ReportValue>{
      'items': ReportList(<ReportValue>[value]),
    });
  }

  ReportFontSpec _font(ReportTextStyle style) => ReportFontSpec(
    family: style.fontFamily ?? t.defaultFont,
    size: style.fontSize ?? t.defaultFontSize,
    bold: style.bold ?? false,
    italic: style.italic ?? false,
  );

  bool _rtl(ReportTextDirection d) => switch (d) {
    ReportTextDirection.rtl => true,
    ReportTextDirection.ltr => false,
    ReportTextDirection.auto => t.isRtl,
  };

  static ReportTextAlign _physical(
    ReportTextAlign a, {
    required bool rtl,
  }) => switch (a) {
    ReportTextAlign.start => rtl ? ReportTextAlign.right : ReportTextAlign.left,
    ReportTextAlign.end => rtl ? ReportTextAlign.left : ReportTextAlign.right,
    _ => a,
  };

  _Box _richText(
    ReportTextElement e,
    double x,
    ReportScope scope,
    ReportBandKind kind,
  ) {
    final bool rtl = _rtl(e.direction);
    final double inner = e.width - 2 * e.padding;
    final double maxWidth = inner < 1 ? 1 : inner;
    final List<ReportPrimitive> out = <ReportPrimitive>[];
    final List<ReportFlowSpan> spans = <ReportFlowSpan>[];
    var cursorX = 0.0;
    var cursorY = 0.0;
    var lineHeight = 0.0;
    void wrap() {
      cursorY += lineHeight;
      cursorX = 0;
      lineHeight = 0;
    }

    for (final ReportTextRun run in e.runs) {
      final ({String text, ReportValue value}) tv = _textValue(
        run.text,
        scope,
        null,
      );
      if (tv.text.isEmpty) {
        continue;
      }
      final ReportFontSpec font = ReportFontSpec(
        family: e.style.fontFamily ?? t.defaultFont,
        size: run.fontSize ?? e.style.fontSize ?? t.defaultFontSize,
        bold: run.bold ?? e.style.bold ?? false,
        italic: run.italic ?? e.style.italic ?? false,
      );
      final ReportColor color = t.resolveColor(
        run.color ?? e.style.color,
        t.textColor,
      );
      final bool underline = run.underline ?? e.style.underline ?? false;
      spans.add(
        ReportFlowSpan(
          text: tv.text,
          font: font,
          color: color,
          underline: underline,
          link: run.link,
        ),
      );
      final ReportShapedText single = g.shaper.shape(
        tv.text,
        font,
        maxWidth: 100000,
        rtl: rtl,
        wrap: false,
      );
      if (cursorX > 0 && cursorX + single.maxLineWidth > maxWidth) {
        wrap();
      }
      final ReportShapedText shaped =
          single.maxLineWidth <= maxWidth - cursorX + ReportGenerator._eps
          ? single
          : g.shaper.shape(
              tv.text,
              font,
              maxWidth: maxWidth,
              rtl: rtl,
              wrap: e.wordWrap,
              lineSpacing: e.lineSpacing,
            );
      final double w = shaped.maxLineWidth > maxWidth
          ? maxWidth
          : shaped.maxLineWidth;
      final double left = rtl
          ? x + e.padding + maxWidth - cursorX - w
          : x + e.padding + cursorX;
      out.add(
        ReportTextPrimitive(
          bounds: ReportRect(left, cursorY, w, shaped.height),
          elementId: e.id,
          band: kind,
          text: tv.text,
          shaped: shaped,
          contentRect: ReportRect(left, cursorY, w, shaped.height),
          font: font,
          color: color,
          align: ReportTextAlign.left,
          verticalAlign: ReportVerticalAlign.top,
          rtl: rtl,
          underline: underline,
          link: run.link,
        ),
      );
      if (shaped.lines.length > 1) {
        cursorY += shaped.height;
        cursorX = 0;
        lineHeight = 0;
      } else {
        cursorX += shaped.maxLineWidth;
        if (shaped.height > lineHeight) {
          lineHeight = shaped.height;
        }
      }
    }
    final double content = cursorY + lineHeight;
    final double need = content + 2 * e.padding;
    var h = e.height;
    if ((e.canGrow && need > h) || (e.canShrink && need < h && need > 0)) {
      h = need;
    }
    return _Box(
      out,
      h,
      flow: <ReportFlowItem>[
        ReportFlowText(
          elementId: e.id,
          rect: ReportRect(x, 0, e.width, h),
          text: spans.map((ReportFlowSpan s) => s.text).join(),
          value: ReportText(spans.map((ReportFlowSpan s) => s.text).join()),
          format: null,
          font: _font(e.style),
          color: t.resolveColor(e.style.color, t.textColor),
          align: _physical(e.align, rtl: rtl),
          rtl: rtl,
          underline: e.style.underline ?? false,
          spans: spans,
        ),
      ],
    );
  }

  _Box _textElement(
    ReportTextElement e,
    double x,
    ReportScope scope,
    ReportBandKind kind,
  ) {
    if (e.runs.isNotEmpty) {
      return _richText(e, x, scope, kind);
    }
    final ({String text, ReportValue value}) tv = _textValue(
      e.text,
      scope,
      e.format,
    );
    final String text = tv.text;
    final ReportFontSpec font = _font(e.style);
    final bool rtl = _rtl(e.direction);
    final ReportTextAlign align = _physical(e.align, rtl: rtl);
    final double innerWidth = e.width - 2 * e.padding;
    final ReportShapedText shaped = g.shaper.shape(
      text,
      font,
      maxWidth: innerWidth,
      rtl: rtl,
      wrap: e.wordWrap,
      justify: align == ReportTextAlign.justify,
      lineSpacing: e.lineSpacing,
    );
    final double need = shaped.height + 2 * e.padding;
    var h = e.height;
    if ((e.canGrow && need > h) || (e.canShrink && need < h)) {
      h = need;
    }
    final List<ReportPrimitive> out = <ReportPrimitive>[];
    final ReportRect bounds = ReportRect(x, 0, e.width, h);
    final ReportColor? fill = e.background == null
        ? null
        : t.resolveColor(e.background, ReportColor.transparent);
    final ReportColor? stroke = e.borderWidth > 0
        ? t.resolveColor(e.borderColor, t.textColor)
        : null;
    if (fill != null || stroke != null) {
      out.add(
        ReportRectPrimitive(
          bounds: bounds,
          elementId: e.id,
          band: kind,
          fill: fill,
          stroke: stroke,
          strokeWidth: e.borderWidth,
        ),
      );
    }
    if (text.isNotEmpty) {
      out.add(
        ReportTextPrimitive(
          bounds: bounds,
          elementId: e.id,
          band: kind,
          text: text,
          shaped: shaped,
          contentRect: ReportRect(
            x + e.padding,
            e.padding,
            innerWidth < 0 ? 0 : innerWidth,
            h - 2 * e.padding < 0 ? 0 : h - 2 * e.padding,
          ),
          font: font,
          color: t.resolveColor(e.style.color, t.textColor),
          align: align,
          verticalAlign: e.verticalAlign,
          rtl: rtl,
          underline: e.style.underline ?? false,
        ),
      );
    }
    return _Box(
      out,
      h,
      flow: <ReportFlowItem>[
        ReportFlowText(
          elementId: e.id,
          rect: bounds,
          text: text,
          value: tv.value,
          format: e.format,
          font: font,
          color: t.resolveColor(e.style.color, t.textColor),
          align: align,
          rtl: rtl,
          underline: e.style.underline ?? false,
          background: fill,
        ),
      ],
    );
  }

  _Box _imageElement(
    ReportImageElement e,
    double x,
    ReportScope scope,
    ReportBandKind kind,
  ) {
    final ReportRect bounds = ReportRect(x, 0, e.width, e.height);
    final List<ReportPrimitive> out = <ReportPrimitive>[];
    if (e.background != null) {
      out.add(
        ReportRectPrimitive(
          bounds: bounds,
          elementId: e.id,
          band: kind,
          fill: t.resolveColor(e.background, ReportColor.transparent),
        ),
      );
    }
    final Uint8List? bytes = _imageBytes(e.source, scope);
    final List<ReportFlowItem> flow = <ReportFlowItem>[];
    if (bytes != null) {
      final ImageSize? size = ImageFit.readSize(bytes);
      if (size == null || size.widthPx <= 0 || size.heightPx <= 0) {
        warnings.add(
          'Image ${e.displayName}: unsupported format (PNG/JPEG only)',
        );
      } else {
        flow.add(ReportFlowImage(elementId: e.id, rect: bounds, bytes: bytes));
        out.add(
          ReportImagePrimitive(
            bounds: bounds,
            elementId: e.id,
            band: kind,
            bytes: bytes,
            imageRect: _fit(bounds, size, e.fit),
          ),
        );
      }
    } else if (e.source.trim().isNotEmpty) {
      warnings.add('Image ${e.displayName}: source "${e.source}" not found');
    }
    if (e.borderWidth > 0) {
      out.add(
        ReportRectPrimitive(
          bounds: bounds,
          elementId: e.id,
          band: kind,
          stroke: t.resolveColor(e.borderColor, t.textColor),
          strokeWidth: e.borderWidth,
        ),
      );
    }
    return _Box(out, e.height, flow: flow);
  }

  static ReportRect _fit(ReportRect box, ImageSize size, ReportImageFit fit) {
    final double iw = size.widthPx.toDouble();
    final double ih = size.heightPx.toDouble();
    switch (fit) {
      case ReportImageFit.fill:
        return box;
      case ReportImageFit.none:
        final double w = iw * 0.75;
        final double h = ih * 0.75;
        return ReportRect(
          box.left + (box.width - w) / 2,
          box.top + (box.height - h) / 2,
          w,
          h,
        );
      case ReportImageFit.contain:
      case ReportImageFit.cover:
        final double sx = box.width / iw;
        final double sy = box.height / ih;
        final double s = fit == ReportImageFit.contain
            ? (sx < sy ? sx : sy)
            : (sx > sy ? sx : sy);
        final double w = iw * s;
        final double h = ih * s;
        return ReportRect(
          box.left + (box.width - w) / 2,
          box.top + (box.height - h) / 2,
          w,
          h,
        );
    }
  }

  Uint8List? _imageBytes(String source, ReportScope scope) {
    final String raw = source.trim();
    if (raw.isEmpty) {
      return null;
    }
    final ReportValue v = raw.contains('{{')
        ? _value(raw, scope, null)
        : ReportText(raw);
    if (v is ReportBinary) {
      return v.bytes;
    }
    final String s = v.displayText.trim();
    if (s.isEmpty) {
      return null;
    }
    final Uint8List? named = g.images[s];
    if (named != null) {
      return named;
    }
    if (s.startsWith('data:')) {
      final int comma = s.indexOf(',');
      if (comma < 0 || !s.substring(0, comma).contains(';base64')) {
        return null;
      }
      return _decodeBase64(s.substring(comma + 1));
    }
    final Uint8List? decoded = _decodeBase64(s);
    if (decoded != null && ImageFit.readSize(decoded) != null) {
      return decoded;
    }
    return null;
  }

  static Uint8List? _decodeBase64(String s) {
    try {
      return base64.decode(s.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      return null;
    }
  }

  _Box _barcodeElement(
    ReportBarcodeElement e,
    double x,
    ReportScope scope,
    ReportBandKind kind,
  ) {
    final String text = _text(e.data, scope, null);
    final ReportRect bounds = ReportRect(x, 0, e.width, e.height);
    final ReportColor color = t.resolveColor(e.color, ReportColor.black);
    final List<ReportPrimitive> out = <ReportPrimitive>[];
    if (e.background != null) {
      out.add(
        ReportRectPrimitive(
          bounds: bounds,
          elementId: e.id,
          band: kind,
          fill: t.resolveColor(e.background, ReportColor.white),
        ),
      );
    }
    if (text.isEmpty) {
      return _Box(out, e.height);
    }
    final List<ReportFlowItem> flow = <ReportFlowItem>[];
    try {
      if (e.symbology == ReportBarcodeType.qr) {
        final List<List<bool>> matrix = const QrEncoder().encode(
          String.fromCharCodes(utf8.encode(text)),
        );
        out.add(
          ReportBarcodePrimitive(
            bounds: bounds,
            elementId: e.id,
            band: kind,
            symbology: e.symbology,
            color: color,
            matrix: matrix,
          ),
        );
        flow.add(
          ReportFlowImage(
            elementId: e.id,
            rect: bounds,
            bytes: encodeMatrixPng(matrix),
          ),
        );
        return _Box(out, e.height, flow: flow);
      }
      final List<bool> modules = e.symbology == ReportBarcodeType.ean13
          ? const Ean13Encoder().encode(text)
          : const Code128Encoder().encodeWithQuietZone(text);
      final ReportFontSpec font = ReportFontSpec(
        family: t.defaultFont,
        size: e.fontSize,
      );
      final ReportShapedText? label = e.showText
          ? g.shaper.shape(
              text,
              font,
              maxWidth: e.width,
              rtl: false,
              wrap: false,
            )
          : null;
      final double labelH = label == null ? 0 : label.lineHeight;
      final double barH = e.height - labelH > 4 ? e.height - labelH : e.height;
      out.add(
        ReportBarcodePrimitive(
          bounds: ReportRect(x, 0, e.width, barH),
          elementId: e.id,
          band: kind,
          symbology: e.symbology,
          color: color,
          modules: modules,
        ),
      );
      flow.add(
        ReportFlowImage(
          elementId: e.id,
          rect: ReportRect(x, 0, e.width, barH),
          bytes: encodeBarcodePng(modules),
        ),
      );
      if (label != null && barH < e.height) {
        out.add(
          ReportTextPrimitive(
            bounds: ReportRect(x, barH, e.width, labelH),
            elementId: e.id,
            band: kind,
            text: text,
            shaped: label,
            contentRect: ReportRect(x, barH, e.width, labelH),
            font: font,
            color: color,
            align: ReportTextAlign.center,
            verticalAlign: ReportVerticalAlign.top,
            rtl: false,
          ),
        );
      }
    } on ArgumentError catch (err) {
      warnings.add('Barcode ${e.displayName}: ${err.message}');
    }
    return _Box(out, e.height, flow: flow);
  }

  _Box _shapeElement(ReportShapeElement e, double x, ReportBandKind kind) {
    final ReportColor stroke = t.resolveColor(e.strokeColor, t.textColor);
    if (e.kind == ReportShapeKind.line) {
      final bool rising = t.mirrored ? !e.rising : e.rising;
      final double y1 = rising ? e.height : 0;
      final double y2 = rising ? 0 : e.height;
      return _Box(
        <ReportPrimitive>[
          ReportLinePrimitive(
            bounds: ReportRect(x, 0, e.width, e.height),
            elementId: e.id,
            band: kind,
            x1: x,
            y1: y1,
            x2: x + e.width,
            y2: y2,
            color: stroke,
            width: e.strokeWidth,
            lineStyle: e.lineStyle,
          ),
        ],
        e.height,
        flow: e.height <= e.width * 0.05
            ? <ReportFlowItem>[
                ReportFlowRule(
                  elementId: e.id,
                  rect: ReportRect(x, 0, e.width, e.height),
                  color: stroke,
                  width: e.strokeWidth,
                ),
              ]
            : const <ReportFlowItem>[],
      );
    }
    return _Box(<ReportPrimitive>[
      ReportRectPrimitive(
        bounds: ReportRect(x, 0, e.width, e.height),
        elementId: e.id,
        band: kind,
        fill: e.fill == null
            ? null
            : t.resolveColor(e.fill, ReportColor.transparent),
        stroke: e.strokeWidth > 0 ? stroke : null,
        strokeWidth: e.strokeWidth,
        radius: e.kind == ReportShapeKind.roundedRectangle
            ? (e.cornerRadius > 0 ? e.cornerRadius : 4)
            : 0,
        ellipse: e.kind == ReportShapeKind.ellipse,
        lineStyle: e.lineStyle,
      ),
    ], e.height, flow: <ReportFlowItem>[
      ReportFlowImage(
        elementId: e.id,
        rect: ReportRect(x, 0, e.width, e.height),
        bytes: encodeShapePng(
          width: e.width.round().clamp(1, 512),
          height: e.height.round().clamp(1, 512),
          rgb: (e.fill == null
                  ? stroke
                  : t.resolveColor(e.fill, ReportColor.transparent))
              .argb,
          ellipse: e.kind == ReportShapeKind.ellipse,
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- charts

  _Box _chartElement(
    ReportChartElement e,
    double x,
    ReportScope scope,
    ReportBandKind kind,
  ) {
    _atomic.add(e.id);
    final ReportChartData data = _chartData(e, scope);
    final double room =
        t.pageHeight - t.margins.top - t.margins.bottom - _footerReserve(1);
    final double height = e.height > room && room > 8 ? room : e.height;
    if (height < e.height - 0.5) {
      warnings.add(
        'Chart ${e.displayName} was scaled to the page (${height.toStringAsFixed(0)} pt)',
      );
    }
    final ReportRect bounds = ReportRect(x, 0, e.width, height);
    final List<ReportPrimitive> out = <ReportPrimitive>[];
    final bool border = e.borderWidth > 0 && e.borderColor != null;
    if (e.background != null || border) {
      out.add(
        ReportRectPrimitive(
          bounds: bounds,
          elementId: e.id,
          band: kind,
          fill: e.background == null
              ? null
              : t.resolveColor(e.background, ReportColor.transparent),
          stroke: border ? t.resolveColor(e.borderColor, t.textColor) : null,
          strokeWidth: border ? e.borderWidth : 0,
        ),
      );
    }
    out.addAll(
      ReportChartRenderer(
        shaper: g.shaper,
        formatter: g.engine.formatter,
      ).render(
        data,
        bounds,
        font: ReportFontSpec(
          family: e.fontFamily ?? t.defaultFont,
          size: e.fontSize > 0 ? e.fontSize : 7.5,
          bold: e.bold,
          italic: e.italic,
        ),
        textColor: t.resolveColor(e.textColor, t.textColor),
        labelColor: (e.labelStyle.color ?? e.textColor) == null
            ? null
            : t.resolveColor(e.labelStyle.color ?? e.textColor, t.textColor),
        elementId: e.id,
        band: kind,
      ),
    );
    return _Box(
      out,
      height,
      flow: <ReportFlowItem>[
        ReportFlowChart(elementId: e.id, rect: bounds, data: data),
      ],
    );
  }

  ReportExpression? _parseExpression(String source) {
    try {
      return ReportExpression.parse(source);
    } on ReportExpressionException catch (err) {
      if (g.strict) {
        rethrow;
      }
      warnings.add(err.toString());
      return null;
    }
  }

  List<ReportValue> _chartRows(ReportChartElement e, ReportScope scope) {
    final String? path = _nonEmpty(e.dataSet);
    if (path != null) {
      return _datasetRows(path, scope);
    }
    final List<ReportValue>? rows = scope.aggregateRows;
    if (rows != null) {
      return rows;
    }
    final String? dataset = _nonEmpty(scope.datasetPath);
    if (dataset != null) {
      return _datasetRows(dataset, scope);
    }
    final ReportValue? row = scope.row;
    return row == null ? const <ReportValue>[] : <ReportValue>[row];
  }

  /// Categories and aggregated series values of [e] in [scope].
  ReportChartData _chartData(ReportChartElement e, ReportScope scope) {
    ReportColor palette(int i) =>
        t.resolveColor(e.paletteColor(i), t.primaryColor);
    final List<String> categories = <String>[];
    final List<ReportValue> keys = <ReportValue>[];
    final List<ReportChartSeriesData> series = <ReportChartSeriesData>[];
    final List<ReportColor> pointColors = <ReportColor>[];
    List<ReportColor?>? regionColors;
    List<String>? regionLabels;
    var varyColors = e.isRadial;
    if (e.series.isEmpty) {
      final List<double> values = <double>[];
      final List<double> xs = <double>[];
      final List<double> sizes = <double>[];
      final List<bool> totals = <bool>[];
      for (int i = 0; i < e.points.length; i++) {
        final ReportChartPoint p = e.points[i];
        final String label = _text(p.label, scope, null);
        categories.add(label);
        keys.add(ReportText(label));
        values.add(_evaluate(p.value, scope).asNumber?.toDouble() ?? 0);
        xs.add(
          p.x == null || p.x!.trim().isEmpty
              ? (i + 1).toDouble()
              : _evaluate(p.x!, scope).asNumber?.toDouble() ??
                    (i + 1).toDouble(),
        );
        sizes.add(
          p.size == null || p.size!.trim().isEmpty
              ? 1
              : _evaluate(p.size!, scope).asNumber?.toDouble() ?? 1,
        );
        totals.add(p.total);
        pointColors.add(
          p.color == null ? palette(i) : t.resolveColor(p.color, palette(i)),
        );
        varyColors = varyColors || p.color != null;
      }
      if (e.lastIsTotal && totals.isNotEmpty) {
        totals[totals.length - 1] = true;
      }
      series.add(
        ReportChartSeriesData(
          name: '',
          color: palette(0),
          values: values,
          xs: xs,
          sizes: sizes,
          totals: totals,
        ),
      );
    } else if (e.chartType.plotsPoints) {
      final List<ReportValue> rows = _chartRows(e, scope);
      final ReportExpression? category = _nonEmpty(e.category) == null
          ? null
          : _parseExpression(e.category!.trim());
      for (int s = 0; s < e.series.length; s++) {
        final ReportChartSeries def = e.series[s];
        final ReportExpression? yExpr = _nonEmpty(def.value) == null
            ? null
            : _parseExpression(def.value.trim());
        final ReportExpression? xExpr = _nonEmpty(def.x) == null
            ? null
            : _parseExpression(def.x!.trim());
        final ReportExpression? zExpr = _nonEmpty(def.size) == null
            ? null
            : _parseExpression(def.size!.trim());
        final List<double> values = <double>[];
        final List<double> xs = <double>[];
        final List<double> sizes = <double>[];
        for (int r = 0; r < rows.length; r++) {
          final ReportScope rs = scope.copyWith(row: rows[r], rowIndex: r);
          if (s == 0) {
            final String label = category == null
                ? '${r + 1}'
                : g.engine.formatter.display(_evalParsed(category, rs));
            categories.add(label);
            keys.add(ReportText(label));
            pointColors.add(palette(r));
          }
          values.add(
            yExpr == null
                ? 0
                : _evalParsed(yExpr, rs).asNumber?.toDouble() ?? 0,
          );
          xs.add(
            xExpr == null
                ? (r + 1).toDouble()
                : _evalParsed(xExpr, rs).asNumber?.toDouble() ??
                      (r + 1).toDouble(),
          );
          sizes.add(
            zExpr == null
                ? 1
                : _evalParsed(zExpr, rs).asNumber?.toDouble() ?? 1,
          );
        }
        final String name = _text(def.name, scope, null);
        series.add(
          ReportChartSeriesData(
            name: name.isEmpty && e.series.length > 1
                ? 'Series ${s + 1}'
                : name,
            color: def.color == null
                ? palette(s)
                : t.resolveColor(def.color, palette(s)),
            values: values,
            xs: xs,
            sizes: sizes,
            style: def.style,
            secondary: def.secondary,
          ),
        );
      }
    } else {
      final List<ReportValue> rows = _chartRows(e, scope);
      final ReportExpression? category = _nonEmpty(e.category) == null
          ? null
          : _parseExpression(e.category!.trim());
      final List<ReportExpression?> measures = <ReportExpression?>[
        for (final ReportChartSeries s in e.series)
          _nonEmpty(s.value) == null ? null : _parseExpression(s.value.trim()),
      ];
      final Map<String, int> index = <String, int>{};
      final List<List<List<double>>> samples = <List<List<double>>>[
        for (int s = 0; s < e.series.length; s++) <List<double>>[],
      ];
      final ReportExpression? colorExpr =
          e.chartType.isShapeMap && _nonEmpty(e.regionColor) != null
          ? _parseExpression(e.regionColor!.trim())
          : null;
      final List<ReportColor?> paints = <ReportColor?>[];
      for (int r = 0; r < rows.length; r++) {
        final ReportScope rs = scope.copyWith(row: rows[r], rowIndex: r);
        final ReportValue key = category == null
            ? ReportText('${r + 1}')
            : _evalParsed(category, rs);
        final String label = g.engine.formatter.display(key);
        final int ci = index.putIfAbsent(label, () {
          categories.add(label);
          keys.add(key);
          paints.add(null);
          for (final List<List<double>> s in samples) {
            s.add(<double>[]);
          }
          return categories.length - 1;
        });
        if (colorExpr != null && paints[ci] == null) {
          paints[ci] = _paintColor(
            t,
            g.engine.formatter.display(_evalParsed(colorExpr, rs)),
          );
        }
        for (int s = 0; s < measures.length; s++) {
          final ReportExpression? m = measures[s];
          final num? v = m == null ? null : _evalParsed(m, rs).asNumber;
          if (v != null) {
            samples[s][ci].add(v.toDouble());
          }
        }
      }
      for (int s = 0; s < e.series.length; s++) {
        final ReportChartSeries def = e.series[s];
        final String name = _text(def.name, scope, null);
        series.add(
          ReportChartSeriesData(
            name: name.isEmpty && e.series.length > 1
                ? 'Series ${s + 1}'
                : name,
            color: def.color == null
                ? palette(s)
                : t.resolveColor(def.color, palette(s)),
            values: <double>[
              for (final List<double> v in samples[s])
                _aggregate(e.aggregate, v),
            ],
            style: def.style,
            secondary: def.secondary,
            totals: e.chartType == ReportChartType.waterfall
                ? <bool>[
                    for (int i = 0; i < samples[s].length; i++)
                      e.lastIsTotal && i == samples[s].length - 1,
                  ]
                : null,
          ),
        );
      }
      for (int i = 0; i < categories.length; i++) {
        pointColors.add(palette(i));
      }
      if (colorExpr != null) {
        regionColors = paints;
      }
      final String labelSource = (e.labelField ?? '').trim();
      if (e.chartType.isShapeMap &&
          QudsExpressionEngine.isLabelFormula(labelSource)) {
        final Map<String, String> captions = g.engine.regionCaptions(
          labelSource,
          e.category,
          rows,
          scope,
          shapes: _shapeLayer(e),
        );
        regionLabels = <String>[
          for (final String key in categories) captions[key] ?? '',
        ];
      }
    }
    final List<int> order = List<int>.generate(categories.length, (int i) => i);
    if (e.sortBy != ReportChartSort.none) {
      order.sort((int a, int b) {
        final int c = e.sortBy == ReportChartSort.category
            ? compareReportValues(keys[a], keys[b])
            : series.first.values[a].compareTo(series.first.values[b]);
        return c == 0 ? a - b : (e.descending ? -c : c);
      });
    }
    final int keep = e.limit > 0 && e.limit < order.length
        ? e.limit
        : order.length;
    final List<int> picked = order.sublist(0, keep);
    const ReportColor increase = ReportColor(0xFF2E7D32);
    const ReportColor decrease = ReportColor(0xFFC62828);
    const ReportColor total = ReportColor(0xFF37474F);
    final double? target = _nonEmpty(e.target) == null
        ? null
        : _evaluate(e.target!, scope).asNumber?.toDouble();
    Map<String, String>? featureLabels;
    if (e.chartType.isShapeMap && e.showLabels) {
      final ReportShapeLayer? layer = _shapeLayer(e);
      final String field = (e.labelField ?? '').trim();
      if (layer != null && field.isNotEmpty) {
        featureLabels = g.engine.shapeFieldLabels(
          field: field,
          layer: layer,
          schema: t.dataSchema,
          data: scope.data,
          keyField: e.shapeKey,
        );
      }
    }
    final ReportFontSpec chartFont = ReportFontSpec(
      family: e.fontFamily ?? t.defaultFont,
      size: e.fontSize > 0 ? e.fontSize : 7.5,
      bold: e.bold,
      italic: e.italic,
    );
    final bool map = e.chartType.isShapeMap;
    return ReportChartData(
      type: e.chartType,
      title: _text(e.title, scope, null),
      categories: <String>[for (final int i in picked) categories[i]],
      series: <ReportChartSeriesData>[
        for (final ReportChartSeriesData s in series) s.pick(picked),
      ],
      pointColors: <ReportColor>[
        for (final int i in picked)
          if (i < pointColors.length) pointColors[i],
      ],
      rtl: t.mirrored,
      varyColors: varyColors,
      showLegend: e.showLegend,
      showValues: e.showValues,
      showGrid: e.showGrid,
      showAxes: e.showAxes,
      valueFormat: _nonEmpty(e.valueFormat),
      depth: e.depth,
      skew: e.skew,
      hole: e.hole,
      startAngle: e.startAngle,
      smooth: e.smooth,
      showMarkers: e.showMarkers,
      markerSize: e.markerSize,
      lineWidth: e.lineWidth,
      axisMin: e.axisMin,
      axisMax: e.axisMax,
      axisMin2: e.axisMin2,
      axisMax2: e.axisMax2,
      target: target,
      showPercent: e.showPercent,
      lastIsTotal: e.lastIsTotal,
      bands: e.bands,
      increase: e.increaseColor == null
          ? increase
          : t.resolveColor(e.increaseColor, increase),
      decrease: e.decreaseColor == null
          ? decrease
          : t.resolveColor(e.decreaseColor, decrease),
      total: e.totalColor == null ? total : t.resolveColor(e.totalColor, total),
      shapes: e.chartType.isShapeMap ? _shapeLayer(e) : null,
      showLabels: e.showLabels,
      labelField: e.labelField,
      regionLabels: regionLabels == null
          ? null
          : <String>[for (final int i in picked) regionLabels[i]],
      featureLabels: featureLabels,
      titleFont: map ? reportStyleFont(e.titleStyle, chartFont) : null,
      titleInk: map
          ? t.resolveColor(e.titleStyle.color ?? e.textColor, t.textColor)
          : null,
      labelFont: map ? reportStyleFont(e.labelStyle, chartFont) : null,
      legendFont: map ? reportStyleFont(e.legendStyle, chartFont) : null,
      legendInk: map
          ? t.resolveColor(e.legendStyle.color ?? e.textColor, t.textColor)
          : null,
      low: t.resolveColor(e.lowColor, const ReportColor(0xFFDEEBF7)),
      high: t.resolveColor(e.highColor, const ReportColor(0xFF08306B)),
      empty: t.resolveColor(e.emptyColor, const ReportColor(0xFFE4E4E4)),
      regionColors: regionColors == null
          ? null
          : <ReportColor?>[for (final int i in picked) regionColors[i]],
    );
  }

  /// A region color from `#hex`, a CSS name, or a palette entry.
  ReportColor? _paintColor(ReportTemplate template, String raw) {
    final String key = raw.trim();
    if (key.isEmpty) {
      return null;
    }
    final String lower = key.toLowerCase();
    String? mapped;
    for (final MapEntry<String, String> entry in template.colors.entries) {
      if (entry.key.toLowerCase() == lower) {
        mapped = entry.value;
        break;
      }
    }
    return ReportColor.tryParse(mapped ?? key);
  }

  ReportShapeLayer? _shapeLayer(ReportChartElement e) =>
      ReportShapes.resolve(e.shape, g.shapes);

  static double _aggregate(ReportChartAggregate a, List<double> v) {
    if (a == ReportChartAggregate.count) {
      return v.length.toDouble();
    }
    if (v.isEmpty) {
      return 0;
    }
    switch (a) {
      case ReportChartAggregate.sum:
      case ReportChartAggregate.avg:
        var sum = 0.0;
        for (final double x in v) {
          sum += x;
        }
        return a == ReportChartAggregate.avg ? sum / v.length : sum;
      case ReportChartAggregate.min:
        return v.reduce(math.min);
      case ReportChartAggregate.max:
        return v.reduce(math.max);
      case ReportChartAggregate.first:
        return v.first;
      case ReportChartAggregate.last:
        return v.last;
      case ReportChartAggregate.count:
        return v.length.toDouble();
    }
  }

  // ---------------------------------------------------------------- tables

  double _minBodyRow(ReportTableElement table, ReportBand band) {
    final double? explicit = table.rowHeight ?? band.rowHeight;
    if (explicit != null && explicit > 0) {
      return explicit;
    }
    final ReportFontSpec font = ReportFontSpec(
      family: table.fontFamily ?? t.defaultFont,
      size: table.fontSize ?? t.defaultFontSize,
    );
    return g.shaper.lineHeight(font) + 2 * table.padding;
  }

  /// Table rendered as one block (non-detail bands).
  _Box _inlineTable(
    ReportTableElement table,
    ReportScope scope,
    ReportBandKind kind,
  ) {
    final ReportBand band = t.band(kind) ?? ReportBand(kind: kind);
    final String? set = _nonEmpty(table.dataSet) ?? _nonEmpty(band.dataSet);
    final List<ReportValue> rows = set == null
        ? (scope.aggregateRows ?? const <ReportValue>[])
        : _datasetRows(set, scope);
    final ReportScope tableScope = scope.copyWith(
      aggregateRows: rows,
      datasetPath: set,
      overrideDataset: set != null,
    );
    final List<ReportPrimitive> out = <ReportPrimitive>[];
    final List<ReportFlowTableRow> flowRows = <ReportFlowTableRow>[];
    var y = 0.0;
    void add(_Box b) {
      for (final ReportPrimitive p in b.primitives) {
        out.add(_move(p, 0, y));
      }
      final ReportFlowEntry? entry = b.entry;
      if (entry is ReportFlowTableRow) {
        flowRows.add(entry);
      }
      y += b.height;
    }

    final double minRow = _minBodyRow(table, band);
    if (table.showHeader) {
      add(_tableHeader(table, tableScope, band));
    }
    for (int i = 0; i < rows.length; i++) {
      add(
        _tableBodyRow(
          table,
          table.cells,
          tableScope.copyWith(row: rows[i], rowIndex: i),
          band,
          stripe: i.isOdd,
          minHeight: minRow,
        ),
      );
    }
    if (table.footerCells.isNotEmpty) {
      add(
        _tableBodyRow(
          table,
          table.footerCells,
          tableScope,
          band,
          stripe: false,
          minHeight: minRow,
          footer: true,
        ),
      );
    }
    var width = 0.0;
    for (final double w in table.resolvedColumnWidths()) {
      width += w;
    }
    return _Box(
      out,
      y,
      flow: <ReportFlowItem>[
        ReportFlowTableBlock(
          elementId: table.id,
          rect: ReportRect(t.elementLeft(table.x, width), 0, width, y),
          rows: flowRows,
        ),
      ],
    );
  }

  List<double> _columnLefts(ReportTableElement table, List<double> widths) {
    var total = 0.0;
    for (final double w in widths) {
      total += w;
    }
    final double x0 = t.elementLeft(table.x, total);
    final List<double> lefts = <double>[];
    var acc = 0.0;
    for (final double w in widths) {
      lefts.add(t.isRtl ? x0 + total - acc - w : x0 + acc);
      acc += w;
    }
    return lefts;
  }

  _Box _tableHeader(
    ReportTableElement table,
    ReportScope scope,
    ReportBand band,
  ) {
    final List<String> texts = <String>[
      for (final ReportTableColumn c in table.columns)
        _text(c.header, scope, null),
    ];
    final List<ReportTextAlign> aligns = <ReportTextAlign>[
      for (final ReportTableColumn c in table.columns) c.headerAlign ?? c.align,
    ];
    final ReportFontSpec font = ReportFontSpec(
      family: table.fontFamily ?? t.defaultFont,
      size: table.headerFontSize ?? table.fontSize ?? t.defaultFontSize,
      bold: table.headerBold,
    );
    final double minH = table.headerHeight ?? _minBodyRow(table, band);
    return _tableRow(
      table,
      texts: texts,
      values: <ReportValue>[for (final String s in texts) ReportText(s)],
      formats: List<String?>.filled(texts.length, null),
      header: true,
      footer: false,
      aligns: aligns,
      fonts: List<ReportFontSpec>.filled(texts.length, font),
      colors: List<ReportColor>.filled(
        texts.length,
        t.resolveColor(table.headerColor, ReportColor.white),
      ),
      cellFills: List<ReportColor?>.filled(texts.length, null),
      rowFill: t.resolveColor(table.headerBackground, t.primaryColor),
      minHeight: minH,
      kind: band.kind,
    );
  }

  _Box _tableBodyRow(
    ReportTableElement table,
    List<ReportTableCell> cells,
    ReportScope scope,
    ReportBand band, {
    required bool stripe,
    required double minHeight,
    bool footer = false,
  }) {
    final int n = table.columns.length;
    final List<String> texts = <String>[];
    final List<ReportValue> values = <ReportValue>[];
    final List<String?> formats = <String?>[];
    final List<ReportTextAlign> aligns = <ReportTextAlign>[];
    final List<ReportFontSpec> fonts = <ReportFontSpec>[];
    final List<ReportColor> colors = <ReportColor>[];
    final List<ReportColor?> fills = <ReportColor?>[];
    final ReportColor bodyColor = t.resolveColor(table.color, t.textColor);
    for (int i = 0; i < n; i++) {
      final ReportTableCell? cell = i < cells.length ? cells[i] : null;
      if (cell == null) {
        texts.add('');
        values.add(ReportNull.instance);
        formats.add(null);
      } else {
        final ({String text, ReportValue value}) tv = _textValue(
          cell.template,
          scope,
          cell.format,
        );
        texts.add(tv.text);
        values.add(tv.value);
        formats.add(cell.format);
      }
      aligns.add(cell?.align ?? table.columns[i].align);
      fonts.add(
        ReportFontSpec(
          family: table.fontFamily ?? t.defaultFont,
          size: table.fontSize ?? t.defaultFontSize,
          bold: cell?.bold ?? footer,
          italic: cell?.italic ?? false,
        ),
      );
      colors.add(t.resolveColor(cell?.color, bodyColor));
      final String? bg = cell?.background;
      fills.add(
        bg == null ? null : t.resolveColor(bg, ReportColor.transparent),
      );
    }
    final String? stripeColor = table.stripeColor;
    return _tableRow(
      table,
      texts: texts,
      values: values,
      formats: formats,
      header: false,
      footer: footer,
      aligns: aligns,
      fonts: fonts,
      colors: colors,
      cellFills: fills,
      rowFill: stripe && stripeColor != null
          ? t.resolveColor(stripeColor, ReportColor.transparent)
          : null,
      minHeight: minHeight,
      kind: band.kind,
    );
  }

  _Box _tableRow(
    ReportTableElement table, {
    required List<String> texts,
    required List<ReportValue> values,
    required List<String?> formats,
    required bool header,
    required bool footer,
    required List<ReportTextAlign> aligns,
    required List<ReportFontSpec> fonts,
    required List<ReportColor> colors,
    required List<ReportColor?> cellFills,
    required ReportColor? rowFill,
    required double minHeight,
    required ReportBandKind kind,
  }) {
    final List<double> widths = table.resolvedColumnWidths();
    final List<double> lefts = _columnLefts(table, widths);
    final double pad = table.padding;
    final bool rtl = t.isRtl;
    final List<ReportShapedText> shaped = <ReportShapedText>[];
    var h = minHeight;
    for (int i = 0; i < widths.length; i++) {
      final ReportShapedText s = g.shaper.shape(
        texts[i],
        fonts[i],
        maxWidth: widths[i] - 2 * pad,
        rtl: rtl,
      );
      shaped.add(s);
      final double need = s.height + 2 * pad;
      if (need > h) {
        h = need;
      }
    }
    var tableWidth = 0.0;
    for (final double w in widths) {
      tableWidth += w;
    }
    final double x0 = t.elementLeft(table.x, tableWidth);
    final List<ReportPrimitive> out = <ReportPrimitive>[];
    if (rowFill != null) {
      out.add(
        ReportRectPrimitive(
          bounds: ReportRect(x0, 0, tableWidth, h),
          elementId: table.id,
          band: kind,
          fill: rowFill,
        ),
      );
    }
    final ReportColor grid = t.resolveColor(
      table.borderColor,
      const ReportColor(0xFFBFBFBF),
    );
    for (int i = 0; i < widths.length; i++) {
      final ReportRect cellRect = ReportRect(lefts[i], 0, widths[i], h);
      final ReportColor? fill = cellFills[i];
      if (fill != null) {
        out.add(
          ReportRectPrimitive(
            bounds: cellRect,
            elementId: table.id,
            band: kind,
            fill: fill,
          ),
        );
      }
      if (texts[i].isNotEmpty) {
        out.add(
          ReportTextPrimitive(
            bounds: cellRect,
            elementId: table.id,
            band: kind,
            text: texts[i],
            shaped: shaped[i],
            contentRect: ReportRect(
              lefts[i] + pad,
              pad,
              widths[i] - 2 * pad < 0 ? 0 : widths[i] - 2 * pad,
              h - 2 * pad < 0 ? 0 : h - 2 * pad,
            ),
            font: fonts[i],
            color: colors[i],
            align: _physical(aligns[i], rtl: rtl),
            verticalAlign: ReportVerticalAlign.middle,
            rtl: rtl,
          ),
        );
      }
      if (table.showGrid && table.borderWidth > 0) {
        out.add(
          ReportRectPrimitive(
            bounds: cellRect,
            elementId: table.id,
            band: kind,
            stroke: grid,
            strokeWidth: table.borderWidth,
          ),
        );
      }
    }
    return _Box(
      out,
      h,
      entry: ReportFlowTableRow(
        kind,
        table: table,
        header: header,
        footer: footer,
        columnWidths: widths,
        height: h,
        fill: rowFill,
        cells: <ReportFlowCell>[
          for (int i = 0; i < widths.length; i++)
            ReportFlowCell(
              text: texts[i],
              value: values[i],
              format: formats[i],
              bold: fonts[i].bold,
              italic: fonts[i].italic,
              align: _physical(aligns[i], rtl: rtl),
              color: colors[i],
              fontSize: fonts[i].size,
              background: cellFills[i],
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- geometry

  (_Box, _Box) _split(_Box box, double cut) {
    final List<ReportPrimitive> first = <ReportPrimitive>[];
    final List<ReportPrimitive> rest = <ReportPrimitive>[];
    var restBottom = box.height - cut;
    void toRest(ReportPrimitive p, double dy) {
      final ReportPrimitive moved = _move(p, 0, dy);
      rest.add(moved);
      if (moved.bounds.bottom > restBottom) {
        restBottom = moved.bounds.bottom;
      }
    }

    final Map<String, ({double top, double bottom})> units =
        <String, ({double top, double bottom})>{};
    for (final ReportPrimitive p in box.primitives) {
      final String? id = p.elementId;
      if (id == null || !_atomic.contains(id)) {
        continue;
      }
      final ({double top, double bottom})? u = units[id];
      units[id] = u == null
          ? (top: p.bounds.top, bottom: p.bounds.bottom)
          : (
              top: math.min(u.top, p.bounds.top),
              bottom: math.max(u.bottom, p.bounds.bottom),
            );
    }
    // An atomic chart that straddles the cut moves as a whole. Retreat the
    // cut to its top, and repeat, so the charts below it keep their spacing
    // instead of being drawn on top of the one that moved.
    var splitAt = cut;
    var retreated = true;
    while (retreated) {
      retreated = false;
      for (final ({double top, double bottom}) unit in units.values) {
        if (unit.top > ReportGenerator._eps &&
            unit.top < splitAt - ReportGenerator._eps &&
            unit.bottom > splitAt + ReportGenerator._eps) {
          splitAt = unit.top;
          retreated = true;
        }
      }
    }
    cut = splitAt;
    restBottom = box.height - cut;
    for (final ReportPrimitive p in box.primitives) {
      final ReportRect b = p.bounds;
      final ({double top, double bottom})? unit = units[p.elementId];
      if (unit != null &&
          unit.top < cut - ReportGenerator._eps &&
          unit.bottom > cut + ReportGenerator._eps) {
        toRest(p, -unit.top);
        continue;
      }
      if (b.bottom <= cut + ReportGenerator._eps) {
        first.add(p);
      } else if (b.top >= cut - ReportGenerator._eps) {
        toRest(p, -cut);
      } else if (p is ReportTextPrimitive) {
        final double lh = p.shaped.lineHeight;
        final int n = p.shaped.lines.length;
        final double top = p.firstLineTop;
        var keep = lh <= 0 ? n : ((cut - top) / lh).floor();
        keep = keep.clamp(0, n);
        if (keep > 0) {
          first.add(_textSlice(p, 0, keep, top, cut - b.top));
        }
        if (keep < n) {
          final ReportTextPrimitive tail = _textSlice(
            p,
            keep,
            n,
            top + keep * lh,
            null,
          );
          toRest(tail, -tail.bounds.top);
        }
      } else if (p is ReportImagePrimitive && b.height > 1) {
        final double keep = cut - b.top;
        final double span = b.height;
        final double frac = (keep / span).clamp(0.0, 1.0);
        if (frac > 0.02) {
          first.add(
            ReportImagePrimitive(
              bounds: ReportRect(b.left, b.top, b.width, keep),
              elementId: p.elementId,
              band: p.band,
              bytes: p.bytes,
              imageRect: ReportRect(b.left, b.top, b.width, keep),
              cropTop: p.cropTop,
              cropHeight: p.cropHeight * frac,
            ),
          );
        }
        final double tail = span - keep;
        if (tail > 1 && frac < 0.98) {
          toRest(
            ReportImagePrimitive(
              bounds: ReportRect(b.left, cut, b.width, tail),
              elementId: p.elementId,
              band: p.band,
              bytes: p.bytes,
              imageRect: ReportRect(b.left, cut, b.width, tail),
              cropTop: p.cropTop + p.cropHeight * frac,
              cropHeight: p.cropHeight * (1 - frac),
            ),
            -cut,
          );
        }
      } else if (p is ReportRectPrimitive && !p.ellipse) {
        first.add(
          _rectWith(p, ReportRect(b.left, b.top, b.width, cut - b.top)),
        );
        toRest(
          _rectWith(p, ReportRect(b.left, cut, b.width, b.bottom - cut)),
          -cut,
        );
      } else {
        toRest(p, -b.top);
      }
    }
    return (_Box(first, cut), _Box(rest, restBottom < 0 ? 0 : restBottom));
  }

  static ReportTextPrimitive _textSlice(
    ReportTextPrimitive p,
    int from,
    int to,
    double top,
    double? maxHeight,
  ) {
    final ReportShapedText shaped = ReportShapedText(
      lines: p.shaped.lines.sublist(from, to),
      lineHeight: p.shaped.lineHeight,
      ascent: p.shaped.ascent,
    );
    final double h = maxHeight ?? shaped.height;
    final ReportRect content = ReportRect(
      p.contentRect.left,
      top,
      p.contentRect.width,
      shaped.height,
    );
    return ReportTextPrimitive(
      bounds: ReportRect(
        p.bounds.left,
        top,
        p.bounds.width,
        h < shaped.height ? shaped.height : h,
      ),
      elementId: p.elementId,
      band: p.band,
      text: p.text,
      shaped: shaped,
      contentRect: content,
      font: p.font,
      color: p.color,
      align: p.align,
      verticalAlign: ReportVerticalAlign.top,
      rtl: p.rtl,
      underline: p.underline,
    );
  }

  static ReportRectPrimitive _rectWith(ReportRectPrimitive p, ReportRect r) =>
      ReportRectPrimitive(
        bounds: r,
        elementId: p.elementId,
        band: p.band,
        fill: p.fill,
        stroke: p.stroke,
        strokeWidth: p.strokeWidth,
        radius: p.radius,
        ellipse: p.ellipse,
        lineStyle: p.lineStyle,
      );
}

/// Copy of [p] shifted by ([dx], [dy]).
ReportPrimitive _move(ReportPrimitive p, double dx, double dy) {
  if (dx == 0 && dy == 0) {
    return p;
  }
  return switch (p) {
    ReportTextPrimitive() => ReportTextPrimitive(
      bounds: p.bounds.translate(dx, dy),
      elementId: p.elementId,
      band: p.band,
      text: p.text,
      shaped: p.shaped,
      contentRect: p.contentRect.translate(dx, dy),
      font: p.font,
      color: p.color,
      align: p.align,
      verticalAlign: p.verticalAlign,
      rtl: p.rtl,
      underline: p.underline,
      link: p.link,
    ),
    ReportRectPrimitive() => ReportRectPrimitive(
      bounds: p.bounds.translate(dx, dy),
      elementId: p.elementId,
      band: p.band,
      fill: p.fill,
      stroke: p.stroke,
      strokeWidth: p.strokeWidth,
      radius: p.radius,
      ellipse: p.ellipse,
      lineStyle: p.lineStyle,
    ),
    ReportLinePrimitive() => ReportLinePrimitive(
      bounds: p.bounds.translate(dx, dy),
      elementId: p.elementId,
      band: p.band,
      x1: p.x1 + dx,
      y1: p.y1 + dy,
      x2: p.x2 + dx,
      y2: p.y2 + dy,
      color: p.color,
      width: p.width,
      lineStyle: p.lineStyle,
    ),
    ReportImagePrimitive() => ReportImagePrimitive(
      bounds: p.bounds.translate(dx, dy),
      elementId: p.elementId,
      band: p.band,
      bytes: p.bytes,
      imageRect: p.imageRect.translate(dx, dy),
      cropTop: p.cropTop,
      cropHeight: p.cropHeight,
    ),
    ReportBarcodePrimitive() => ReportBarcodePrimitive(
      bounds: p.bounds.translate(dx, dy),
      elementId: p.elementId,
      band: p.band,
      symbology: p.symbology,
      color: p.color,
      modules: p.modules,
      matrix: p.matrix,
    ),
    ReportPathPrimitive() => ReportPathPrimitive(
      bounds: p.bounds.translate(dx, dy),
      elementId: p.elementId,
      band: p.band,
      points: Float64List.fromList(<double>[
        for (int i = 0; i < p.points.length; i++)
          p.points[i] + (i.isEven ? dx : dy),
      ]),
      closed: p.closed,
      fill: p.fill,
      stroke: p.stroke,
      strokeWidth: p.strokeWidth,
      lineStyle: p.lineStyle,
    ),
  };
}
