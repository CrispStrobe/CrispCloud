/// Content widgets: badges, callouts, steps, and data grids.
library;

import 'pw_box.dart';
import 'pw_core.dart';
import 'pw_layout.dart';
import 'pw_style.dart';
import 'pw_table.dart';
import 'pw_text.dart';
import 'pw_types.dart';

/// Visual tone for [Badge] / [Callout].
enum BadgeTone { info, success, warning, danger, neutral }

/// Compact status chip.
class Badge extends Widget {
  /// Badge API.
  const Badge(
    this.label, {
    this.tone = BadgeTone.info,
    this.backgroundColor,
    this.foregroundColor,
    this.fontSize = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  });

  /// label API.
  final String label;

  /// tone API.
  final BadgeTone tone;

  /// backgroundColor API. Overrides [tone] wash.
  final String? backgroundColor;

  /// foregroundColor API. Overrides [tone] ink.
  final String? foregroundColor;

  /// fontSize API.
  final double fontSize;

  /// padding API.
  final EdgeInsetsGeometry padding;

  static (String bg, String fg) _palette(BadgeTone tone) {
    switch (tone) {
      case BadgeTone.info:
        return ('E8EAF6', '283593');
      case BadgeTone.success:
        return ('E8F5E9', '2E7D32');
      case BadgeTone.warning:
        return ('FFF8E1', 'F57F17');
      case BadgeTone.danger:
        return ('FFEBEE', 'C62828');
      case BadgeTone.neutral:
        return ('ECEFF1', '455A64');
    }
  }

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final (String bg, String fg) = _palette(tone);
    // Intrinsic chip — avoid Container expand-to-maxWidth when parent is tight.
    final PwBox chip = Padding(
      padding: padding,
      child: DecoratedBox(
        decoration: BoxDecoration(color: backgroundColor ?? bg),
        child: Text(
          label,
          softWrap: false,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: foregroundColor ?? fg,
          ),
        ),
      ),
    ).layout(context, const BoxConstraints());
    return ProxyBox(constraints.constrain(chip.size), child: chip);
  }
}

/// Accent callout with a colored leading bar.
class Callout extends Widget {
  /// Callout API.
  const Callout({
    required this.body,
    this.title = '',
    this.tone = BadgeTone.info,
    this.accentColor,
    this.backgroundColor,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
  });

  /// title API.
  final String title;

  /// body API.
  final String body;

  /// tone API.
  final BadgeTone tone;

  /// accentColor API.
  final String? accentColor;

  /// backgroundColor API.
  final String? backgroundColor;

  /// padding API.
  final EdgeInsetsGeometry padding;

  static (String accent, String wash, String ink) _palette(BadgeTone tone) {
    switch (tone) {
      case BadgeTone.info:
        return ('3949AB', 'EEF2FF', '1A237E');
      case BadgeTone.success:
        return ('43A047', 'E8F5E9', '1B5E20');
      case BadgeTone.warning:
        return ('FB8C00', 'FFF8E1', 'E65100');
      case BadgeTone.danger:
        return ('E53935', 'FFEBEE', 'B71C1C');
      case BadgeTone.neutral:
        return ('78909C', 'ECEFF1', '37474F');
    }
  }

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final (String accent, String wash, String ink) = _palette(tone);
    final String bar = accentColor ?? accent;
    final String bg = backgroundColor ?? wash;
    return Container(
      decoration: BoxDecoration(color: bg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(width: 4, color: bar, child: const SizedBox(height: 1)),
          Expanded(
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (title.isNotEmpty)
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: ink,
                      ),
                    ),
                  if (title.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(fontSize: 9, color: ink, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).layout(context, constraints);
  }
}

/// One step in a [Steps] trail.
class StepItem {
  /// StepItem API.
  const StepItem({
    required this.title,
    this.subtitle = '',
    this.done = false,
    this.active = false,
  });

  /// title API.
  final String title;

  /// subtitle API.
  final String subtitle;

  /// done API.
  final bool done;

  /// active API.
  final bool active;
}

/// Numbered process trail (horizontal or vertical).
class Steps extends Widget {
  /// Steps API.
  const Steps({
    required this.items,
    this.direction = Axis.horizontal,
    this.activeColor = '3949AB',
    this.doneColor = '43A047',
    this.mutedColor = '90A4AE',
  });

  /// items API.
  final List<StepItem> items;

  /// direction API.
  final Axis direction;

  /// activeColor API.
  final String activeColor;

  /// doneColor API.
  final String doneColor;

  /// mutedColor API.
  final String mutedColor;

  String _dotColor(StepItem item) {
    if (item.done) {
      return doneColor;
    }
    if (item.active) {
      return activeColor;
    }
    return mutedColor;
  }

  Widget _step(int index, StepItem item, {required bool compact}) {
    final String color = _dotColor(item);
    final Widget mark = Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        '${index + 1}',
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: 'FFFFFF',
        ),
      ),
    );
    final Widget titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          item.title,
          style: TextStyle(
            fontSize: compact ? 8 : 9,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        if (item.subtitle.isNotEmpty)
          Text(
            item.subtitle,
            style: TextStyle(fontSize: 7, color: mutedColor),
          ),
      ],
    );
    if (direction == Axis.horizontal) {
      return Expanded(
        child: Column(
          children: <Widget>[
            mark,
            const SizedBox(height: 6),
            titles,
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        mark,
        const SizedBox(width: 10),
        Expanded(child: titles),
      ],
    );
  }

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    if (items.isEmpty) {
      return const SizedBox.shrink().layout(context, constraints);
    }
    if (direction == Axis.horizontal) {
      final List<Widget> row = <Widget>[];
      for (int i = 0; i < items.length; i++) {
        if (i > 0) {
          row.add(
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Divider(height: 2, thickness: 1, color: mutedColor),
              ),
            ),
          );
        }
        row.add(_step(i, items[i], compact: items.length > 4));
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: row,
      ).layout(context, constraints);
    }
    final List<Widget> col = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) {
        col.add(const SizedBox(height: 10));
      }
      col.add(_step(i, items[i], compact: false));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: col,
    ).layout(context, constraints);
  }
}

/// Column definition for [DataGrid].
class DataColumn {
  /// DataColumn API.
  const DataColumn(
    this.label, {
    this.flex = 1,
    this.numeric = false,
  });

  /// label API.
  final String label;

  /// flex API.
  final int flex;

  /// numeric API — right-aligns cells.
  final bool numeric;
}

/// One data row for [DataGrid].
class DataRow {
  /// DataRow API.
  const DataRow(this.cells);

  /// cells API — same length as columns.
  final List<String> cells;
}

/// Styled data table built on [Table.fromTextArray].
class DataGrid extends Widget {
  /// DataGrid API.
  const DataGrid({
    required this.columns,
    required this.rows,
    this.headerColor = '1A237E',
    this.oddRowColor = 'F5F7FA',
    this.borderColor = 'CFD8DC',
    this.cellPadding = const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  });

  /// columns API.
  final List<DataColumn> columns;

  /// rows API.
  final List<DataRow> rows;

  /// headerColor API.
  final String headerColor;

  /// oddRowColor API.
  final String oddRowColor;

  /// borderColor API.
  final String borderColor;

  /// cellPadding API.
  final EdgeInsets cellPadding;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final Map<int, TableColumnWidth> widths = <int, TableColumnWidth>{
      for (int i = 0; i < columns.length; i++)
        i: FlexColumnWidth(columns[i].flex.toDouble()),
    };
    final Map<int, AlignmentGeometry> aligns = <int, AlignmentGeometry>{
      for (int i = 0; i < columns.length; i++)
        i: columns[i].numeric
            ? Alignment.centerRight
            : AlignmentDirectional.centerStart,
    };
    return Table.fromTextArray(
      headers: <String>[for (final DataColumn c in columns) c.label],
      data: <List<String>>[
        for (final DataRow row in rows) List<String>.from(row.cells),
      ],
      columnWidthSpec: widths,
      headerDecoration: headerColor,
      oddRowDecoration: oddRowColor,
      cellPadding: cellPadding,
      headerPadding: cellPadding,
      cellAlignments: aligns,
      headerAlignments: aligns,
      headerStyle: const TextStyle(
        color: 'FFFFFF',
        fontWeight: FontWeight.bold,
        fontSize: 9,
      ),
      cellStyle: const TextStyle(fontSize: 9, color: '263238'),
      border: true,
      tableBorder: TableBorder.all(color: borderColor, width: 0.5),
    ).layout(context, constraints);
  }
}
