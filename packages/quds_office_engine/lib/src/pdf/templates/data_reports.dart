/// Data templates: KPI sheet and record listing.
library;

import 'dart:typed_data';

import '../../builders/office_markup.dart';
import '../../fonts/sfnt_parser.dart';
import '../widgets/pw_types.dart';
import 'kit.dart';
import 'sheets.dart';

/// One KPI. [delta] is an already formatted change, or empty.
class KpiMetric {
  /// KpiMetric API.
  const KpiMetric({
    required this.label,
    required this.value,
    this.delta = '',
  });

  /// label API.
  final String label;

  /// value API.
  final String value;

  /// delta API.
  final String delta;
}

/// KPI sheet labels.
class KpiLabels {
  /// KpiLabels API.
  const KpiLabels({
    this.document = 'KPI sheet',
    this.period = 'Period',
    this.notes = 'Notes',
  });

  /// document API.
  final String document;

  /// period API.
  final String period;

  /// notes API.
  final String notes;
}

/// Metric cards plus an optional chart.
class KpiSheetTemplate {
  /// KpiSheetTemplate API.
  KpiSheetTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.data,
    this.font,
    this.fontBold,
    required this.owner,
    this.metrics = const <KpiMetric>[],
    this.chart,
    this.chartTitle = '',
    this.labels = const KpiLabels(),
    this.period = '',
    this.notes,
    this.footer = '',
  });

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// owner API.
  final TemplateParty owner;

  /// metrics API.
  final List<KpiMetric> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// labels API.
  final KpiLabels labels;

  /// period API.
  final String period;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    final List<ChartPoint>? points = chart;
    return SheetTemplate(
      kind: SheetKind.score,
      skin: SheetSkin.tiles,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: owner,
      labels: SheetLabels(
        document: labels.document,
        date: labels.period,
        notes: labels.notes,
      ),
      date: period,
      metrics: <(String, String)>[
        for (final KpiMetric metric in metrics)
          (
            metric.label,
            metric.delta.isEmpty ? metric.value : '${metric.value}  ${metric.delta}',
          ),
      ],
      chart: points,
      chartTitle: chartTitle,
      notes: notes,
      footer: footer.isEmpty ? owner.name : footer,
    ).save();
  }
}

/// Record listing labels.
class ListingLabels {
  /// ListingLabels API.
  const ListingLabels({
    this.document = 'Listing',
    this.filter = 'Filter',
    this.count = 'Rows',
  });

  /// document API.
  final String document;

  /// filter API.
  final String filter;

  /// count API.
  final String count;
}

/// A filtered table. [columns] is the logical order; RTL flips it.
class ListingTemplate {
  /// ListingTemplate API.
  ListingTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.data,
    this.font,
    this.fontBold,
    required this.owner,
    required this.columns,
    this.rows = const <List<String>>[],
    this.labels = const ListingLabels(),
    this.filter = '',
    this.footer = '',
  });

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// owner API.
  final TemplateParty owner;

  /// columns API.
  final List<String> columns;

  /// rows API.
  final List<List<String>> rows;

  /// labels API.
  final ListingLabels labels;

  /// filter API.
  final String filter;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    return SheetTemplate(
      kind: SheetKind.listing,
      skin: SheetSkin.catalog,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: owner,
      labels: SheetLabels(
        document: labels.document,
        number: labels.filter,
        extra: labels.count,
        columns: columns,
      ),
      number: filter.isEmpty ? '${rows.length}' : '$filter  ·  ${rows.length}',
      rows: <SheetRow>[for (final List<String> row in rows) SheetRow(row)],
      footer: footer.isEmpty ? owner.name : footer,
    ).save();
  }
}
