import '../visual/drawingml_visual_io.dart';
import '../visual/office_visual.dart';
import 'office_document_theme.dart';
import 'office_markup.dart';

/// Enum ChartKind.
enum ChartKind {
  pie,
  donut,
  bar,
  line,
  area,
  stackedBar,
  percentStackedBar,
  stackedArea,
  scatter,
  bubble,
  radar,
  combo,
}

/// DrawingML chart parts shared by Word and PowerPoint.
abstract final class DrawingmlCharts {
  /// pie API.
  static String pie({
    required String title,
    required List<ChartPoint> series,
    required bool rtl,
    String titleColor = '2E75B6',
    OfficeDocumentTheme? theme,
    ChartDisplay? display,
  }) {
    return singleSeries(
      title: title,
      points: series,
      rtl: rtl,
      titleColor: titleColor,
      kind: ChartKind.pie,
      theme: theme,
      display: display,
    );
  }

  /// donut API.
  static String donut({
    required String title,
    required List<ChartPoint> series,
    required bool rtl,
    String titleColor = '2E75B6',
    int holeSize = 50,
    OfficeDocumentTheme? theme,
    ChartDisplay? display,
  }) {
    return singleSeries(
      title: title,
      points: series,
      rtl: rtl,
      titleColor: titleColor,
      kind: ChartKind.donut,
      holeSize: holeSize,
      theme: theme,
      display: display,
    );
  }

  /// bar API.
  static String bar({
    required String title,
    required List<ChartPoint> series,
    required bool rtl,
    bool horizontal = true,
    String titleColor = '2E75B6',
    OfficeDocumentTheme? theme,
    ChartDisplay? display,
  }) {
    return singleSeries(
      title: title,
      points: series,
      rtl: rtl,
      titleColor: titleColor,
      kind: ChartKind.bar,
      horizontal: horizontal,
      theme: theme,
      display: display,
    );
  }

  /// line API.
  static String line({
    required String title,
    required List<ChartSeries> series,
    required bool rtl,
    bool markers = true,
    String titleColor = '2E75B6',
    OfficeDocumentTheme? theme,
    ChartDisplay? display,
  }) {
    return multiSeries(
      title: title,
      series: series,
      rtl: rtl,
      titleColor: titleColor,
      kind: ChartKind.line,
      markers: markers,
      theme: theme,
      display: display,
    );
  }

  /// area API.
  static String area({
    required String title,
    required List<ChartSeries> series,
    required bool rtl,
    String titleColor = '2E75B6',
    OfficeDocumentTheme? theme,
    ChartDisplay? display,
  }) {
    return multiSeries(
      title: title,
      series: series,
      rtl: rtl,
      titleColor: titleColor,
      kind: ChartKind.area,
      theme: theme,
      display: display,
    );
  }

  /// stackedBar API.
  static String stackedBar({
    required String title,
    required List<ChartSeries> series,
    required bool rtl,
    bool horizontal = false,
    String titleColor = '2E75B6',
    OfficeDocumentTheme? theme,
    ChartDisplay? display,
  }) {
    return multiSeries(
      title: title,
      series: series,
      rtl: rtl,
      titleColor: titleColor,
      kind: ChartKind.stackedBar,
      horizontal: horizontal,
      theme: theme,
      display: display,
    );
  }

  /// singleSeries API.
  static String singleSeries({
    required String title,
    required List<ChartPoint> points,
    required bool rtl,
    required ChartKind kind,
    String titleColor = '2E75B6',
    bool horizontal = false,
    int holeSize = 50,
    OfficeDocumentTheme? theme,
    ChartDisplay? display,
  }) {
    final List<ChartPoint> filtered = _filterPoints(points, theme);
    if (filtered.isEmpty) {
      return _emptyChart();
    }
    return _emit(
      title: title,
      rtl: rtl,
      titleColor: theme?.palette.primary ?? titleColor,
      kind: kind,
      horizontal: horizontal,
      holeSize: holeSize,
      categories: <String>[for (final ChartPoint p in filtered) p.label],
      series: <({String name, String color, List<double> values})>[
        (
          name: title,
          color: filtered.first.color,
          values: <double>[for (final ChartPoint p in filtered) p.value],
        ),
      ],
      pointColors: <String>[for (final ChartPoint p in filtered) p.color],
      markers: false,
      display: display,
    );
  }

  /// multiSeries API.
  static String multiSeries({
    required String title,
    required List<ChartSeries> series,
    required bool rtl,
    required ChartKind kind,
    String titleColor = '2E75B6',
    bool horizontal = false,
    bool markers = false,
    List<bool> lines = const <bool>[],
    List<bool> secondary = const <bool>[],
    OfficeDocumentTheme? theme,
    ChartDisplay? display,
  }) {
    final List<String> categories = <String>[];
    for (final ChartSeries s in series) {
      for (final ChartPoint p in s.points) {
        if (p.value.isFinite && p.label.trim().isNotEmpty) {
          if (!categories.contains(p.label.trim())) {
            categories.add(p.label.trim());
          }
        }
      }
    }
    final List<({String name, String color, List<double> values})> rows =
        <({String name, String color, List<double> values})>[];
    for (int i = 0; i < series.length; i++) {
      final ChartSeries s = series[i];
      final List<ChartPoint> pts = _filterPoints(s.points, theme);
      if (pts.isEmpty) {
        continue;
      }
      final Map<String, double> byLabel = <String, double>{
        for (final ChartPoint p in pts) p.label: p.value,
      };
      rows.add((
        name: s.name.trim().isEmpty ? 'Series ${i + 1}' : s.name.trim(),
        color: OfficeMarkup.srgb(
          s.color ?? theme?.colorAt(i) ?? pts.first.color,
        ),
        values: <double>[
          for (final String cat in categories) byLabel[cat] ?? 0,
        ],
      ));
    }
    if (rows.isEmpty || categories.isEmpty) {
      return _emptyChart();
    }
    return _emit(
      title: title,
      rtl: rtl,
      titleColor: theme?.palette.primary ?? titleColor,
      kind: kind,
      horizontal: horizontal,
      holeSize: 50,
      categories: categories,
      series: rows,
      pointColors: const <String>[],
      markers: markers,
      lines: lines,
      secondary: secondary,
      display: display,
    );
  }

  /// Scatter or bubble chart. Each point's [ChartPoint.x] is the X value
  /// (the category index when it is null) and [ChartPoint.value] is Y.
  static String xy({
    required String title,
    required List<ChartSeries> series,
    required bool rtl,
    required bool bubble,
    String titleColor = '404040',
    OfficeDocumentTheme? theme,
    ChartDisplay? display,
  }) {
    final ChartDisplay view = display ?? ChartDisplay();
    final StringBuffer serXml = StringBuffer();
    var s = 0;
    for (final ChartSeries seriesItem in series) {
      final List<ChartPoint> pts = <ChartPoint>[
        for (final ChartPoint p in seriesItem.points)
          if (p.value.isFinite) p,
      ];
      if (pts.isEmpty) {
        continue;
      }
      final String color = OfficeMarkup.srgb(
        seriesItem.color ?? theme?.colorAt(s) ?? pts.first.color,
      );
      final StringBuffer xLit = StringBuffer(
        '<c:numLit><c:formatCode>General</c:formatCode>'
        '<c:ptCount val="${pts.length}"/>',
      );
      final StringBuffer yLit = StringBuffer(
        '<c:numLit><c:formatCode>General</c:formatCode>'
        '<c:ptCount val="${pts.length}"/>',
      );
      final StringBuffer zLit = StringBuffer(
        '<c:numLit><c:formatCode>General</c:formatCode>'
        '<c:ptCount val="${pts.length}"/>',
      );
      for (int i = 0; i < pts.length; i++) {
        final double x = pts[i].x ?? (i + 1).toDouble();
        xLit.write('<c:pt idx="$i"><c:v>$x</c:v></c:pt>');
        yLit.write('<c:pt idx="$i"><c:v>${pts[i].value}</c:v></c:pt>');
        zLit.write('<c:pt idx="$i"><c:v>${pts[i].size ?? 1}</c:v></c:pt>');
      }
      xLit.write('</c:numLit>');
      yLit.write('</c:numLit>');
      zLit.write('</c:numLit>');
      final String name = seriesItem.name.trim().isEmpty
          ? 'Series ${s + 1}'
          : seriesItem.name.trim();
      serXml.write(
        '<c:ser><c:idx val="$s"/><c:order val="$s"/>'
        '<c:tx><c:v>${OfficeMarkup.escape(name)}</c:v></c:tx>'
        '<c:spPr><a:solidFill><a:srgbClr val="$color"/></a:solidFill></c:spPr>'
        '<c:xVal>$xLit</c:xVal><c:yVal>$yLit</c:yVal>'
        '${bubble ? '<c:bubbleSize>$zLit</c:bubbleSize>' : ''}'
        '<c:marker><c:symbol val="circle"/><c:size val="7"/>'
        '<c:spPr><a:solidFill><a:srgbClr val="$color"/></a:solidFill>'
        '</c:spPr></c:marker></c:ser>',
      );
      s++;
    }
    if (s == 0) {
      return _emptyChart();
    }
    final String tag = bubble ? 'bubbleChart' : 'scatterChart';
    final String style = bubble
        ? '<c:bubbleScale val="100"/>'
        : '<c:scatterStyle val="marker"/>';
    final String plot =
        '<c:$tag><c:varyColors val="0"/>$style$serXml'
        '<c:axId val="100"/><c:axId val="200"/></c:$tag>'
        '${_axes(horizontal: false, showAxes: view.showAxes, showGridlines: view.showGridlines, categoryTitle: view.categoryTitle, valueTitle: view.valueTitle)}';
    return _wrap(
      title: title,
      rtl: rtl,
      titleColor: titleColor,
      plot: plot,
      display: view,
    );
  }

  static List<ChartPoint> _filterPoints(
    List<ChartPoint> series,
    OfficeDocumentTheme? theme,
  ) {
    final List<ChartPoint> points = <ChartPoint>[];
    for (int i = 0; i < series.length; i++) {
      final ChartPoint s = series[i];
      if (!s.value.isFinite) {
        continue;
      }
      final bool custom = s.color.toUpperCase() != '4472C4';
      points.add(
        ChartPoint(
          label: s.label.trim().isEmpty ? '—' : s.label.trim(),
          value: s.value,
          color: OfficeMarkup.srgb(
            custom ? s.color : (theme?.colorAt(i) ?? s.color),
          ),
          x: s.x,
          size: s.size,
        ),
      );
    }
    return points;
  }

  static String _emptyChart() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"/>';

  static String _emit({
    required String title,
    required bool rtl,
    required String titleColor,
    required ChartKind kind,
    required bool horizontal,
    required int holeSize,
    required List<String> categories,
    required List<({String name, String color, List<double> values})> series,
    required List<String> pointColors,
    required bool markers,
    List<bool> lines = const <bool>[],
    List<bool> secondary = const <bool>[],
    ChartDisplay? display,
  }) {
    final ChartDisplay view = display ?? ChartDisplay();
    final int n = categories.length;
    final StringBuffer cats = StringBuffer('<c:strLit><c:ptCount val="$n"/>');
    for (int i = 0; i < n; i++) {
      cats.write(
        '<c:pt idx="$i"><c:v>${OfficeMarkup.escape(categories[i])}</c:v></c:pt>',
      );
    }
    cats.write('</c:strLit>');

    final StringBuffer serXml = StringBuffer();
    final StringBuffer barSer = StringBuffer();
    final StringBuffer lineSer = StringBuffer();
    for (int s = 0; s < series.length; s++) {
      final ({String name, String color, List<double> values}) row = series[s];
      final StringBuffer vals = StringBuffer(
        '<c:numLit><c:formatCode>General</c:formatCode><c:ptCount val="$n"/>',
      );
      final StringBuffer pts = StringBuffer();
      for (int i = 0; i < n; i++) {
        final double v = i < row.values.length ? row.values[i] : 0;
        vals.write('<c:pt idx="$i"><c:v>$v</c:v></c:pt>');
        final String color = i < pointColors.length
            ? pointColors[i]
            : row.color;
        if (kind == ChartKind.pie || kind == ChartKind.donut) {
          pts.write(
            '<c:dPt><c:idx val="$i"/><c:bubble3D val="0"/>'
            '<c:spPr><a:solidFill><a:srgbClr val="$color"/></a:solidFill>'
            '<a:ln><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill></a:ln>'
            '</c:spPr></c:dPt>',
          );
        } else if (kind == ChartKind.bar ||
            kind == ChartKind.stackedBar ||
            kind == ChartKind.percentStackedBar) {
          pts.write(
            '<c:dPt><c:idx val="$i"/><c:invertIfNegative val="0"/>'
            '<c:spPr><a:solidFill><a:srgbClr val="$color"/></a:solidFill>'
            '</c:spPr></c:dPt>',
          );
        }
      }
      vals.write('</c:numLit>');
      final String marker = markers
          ? '<c:marker><c:symbol val="circle"/><c:size val="7"/>'
                '<c:spPr><a:solidFill><a:srgbClr val="${row.color}"/></a:solidFill>'
                '</c:spPr></c:marker>'
          : '<c:marker><c:symbol val="none"/></c:marker>';
      final String lineFill =
          '<c:spPr><a:ln w="19050"><a:solidFill><a:srgbClr val="${row.color}"/>'
          '</a:solidFill></a:ln>'
          '${kind == ChartKind.area ? '<a:solidFill><a:srgbClr val="${row.color}">'
                    '<a:alpha val="40000"/></a:srgbClr></a:solidFill>' : ''}'
          '</c:spPr>';
      final bool asLine =
          kind == ChartKind.combo && s < lines.length && lines[s];
      final bool sec = s < secondary.length && secondary[s];
      final String ax = sec
          ? '<c:axId val="100"/><c:axId val="400"/>'
          : '';
      final String one =
          '<c:ser><c:idx val="$s"/><c:order val="$s"/>'
          '<c:tx><c:v>${OfficeMarkup.escape(row.name)}</c:v></c:tx>'
          '${kind == ChartKind.line || kind == ChartKind.area || kind == ChartKind.stackedArea || kind == ChartKind.radar || asLine ? '$marker$lineFill' : ''}'
          '$pts<c:cat>$cats</c:cat><c:val>$vals</c:val>$ax</c:ser>';
      serXml.write(one);
      if (asLine) {
        lineSer.write(one);
      } else {
        barSer.write(one);
      }
    }

    final String lang = rtl ? 'ar-SA' : 'en-US';
    final String algn = rtl ? 'r' : 'l';
    final bool showTitle = view.showTitle && title.trim().isNotEmpty;
    final String titleXml = showTitle
        ? '<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/>'
              '<a:p><a:pPr algn="$algn"${rtl ? ' rtl="1"' : ''}/><a:r>'
              '<a:rPr lang="$lang" sz="1400" b="1">'
              '<a:solidFill><a:srgbClr val="${OfficeMarkup.srgb(titleColor)}"/></a:solidFill>'
              '<a:cs typeface="Arial"/></a:rPr>'
              '<a:t>${OfficeMarkup.escape(title)}</a:t></a:r></a:p>'
              '</c:rich></c:tx><c:overlay val="0"/></c:title>'
        : '';

    final int showVal = view.showDataLabels && !view.showPercent ? 1 : 0;
    final int showPct =
        view.showPercent ||
            (view.showDataLabels &&
                (kind == ChartKind.pie || kind == ChartKind.donut))
        ? 1
        : 0;
    final String dLbls =
        '<c:dLbls><c:showLegendKey val="0"/><c:showVal val="$showVal"/>'
        '<c:showCatName val="0"/><c:showSerName val="0"/>'
        '<c:showPercent val="$showPct"/><c:showBubbleSize val="0"/>'
        '<c:showLeaderLines val="1"/></c:dLbls>';
    final int hole = view.holeSize.clamp(10, 90);
    final int slice = view.firstSliceAng.clamp(0, 359);
    final int gap = view.gapWidth.clamp(0, 500);
    final String axes = _axes(
      horizontal: horizontal,
      showAxes: view.showAxes,
      showGridlines: view.showGridlines,
      categoryTitle: view.categoryTitle,
      valueTitle: view.valueTitle,
    );

    final String barTag = view.view3d ? 'bar3DChart' : 'barChart';
    final String pieTag = view.view3d ? 'pie3DChart' : 'pieChart';
    final String grouping = switch (kind) {
      ChartKind.stackedBar => 'stacked',
      ChartKind.percentStackedBar => 'percentStacked',
      _ => 'clustered',
    };
    final String areaGrouping = kind == ChartKind.stackedArea
        ? 'stacked'
        : 'standard';
    final String secondAxis = secondary.contains(true)
        ? '<c:valAx><c:axId val="400"/>'
              '<c:scaling><c:orientation val="minMax"/></c:scaling>'
              '<c:delete val="0"/><c:axPos val="r"/>'
              '<c:majorTickMark val="out"/><c:minorTickMark val="none"/>'
              '<c:crossAx val="100"/><c:crosses val="max"/>'
              '<c:crossBetween val="between"/></c:valAx>'
        : '';
    final String plot = switch (kind) {
      ChartKind.pie =>
        '<c:$pieTag><c:varyColors val="0"/>$serXml$dLbls'
            '<c:firstSliceAng val="$slice"/></c:$pieTag>',
      ChartKind.donut =>
        '<c:doughnutChart><c:varyColors val="0"/>$serXml$dLbls'
            '<c:firstSliceAng val="$slice"/><c:holeSize val="$hole"/>'
            '</c:doughnutChart>',
      ChartKind.bar ||
      ChartKind.stackedBar ||
      ChartKind.percentStackedBar =>
        '<c:$barTag><c:barDir val="${horizontal ? 'bar' : 'col'}"/>'
            '<c:grouping val="$grouping"/>'
            '<c:varyColors val="0"/>$serXml$dLbls'
            '<c:gapWidth val="$gap"/><c:axId val="100"/><c:axId val="200"/>'
            '</c:$barTag>$axes$secondAxis',
      ChartKind.line =>
        '<c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>'
            '$serXml<c:marker val="${markers ? 1 : 0}"/>'
            '<c:axId val="100"/><c:axId val="200"/></c:lineChart>$axes',
      ChartKind.area || ChartKind.stackedArea =>
        '<c:areaChart><c:grouping val="$areaGrouping"/><c:varyColors val="0"/>'
            '$serXml<c:axId val="100"/><c:axId val="200"/></c:areaChart>$axes',
      ChartKind.radar =>
        '<c:radarChart><c:radarStyle val="${markers ? 'marker' : 'standard'}"/>'
            '<c:varyColors val="0"/>$serXml'
            '<c:axId val="100"/><c:axId val="200"/></c:radarChart>$axes',
      ChartKind.scatter || ChartKind.bubble =>
        '<c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>'
            '$serXml<c:axId val="100"/><c:axId val="200"/></c:lineChart>$axes',
      ChartKind.combo =>
        '<c:$barTag><c:barDir val="col"/><c:grouping val="clustered"/>'
            '<c:varyColors val="0"/>$barSer$dLbls'
            '<c:gapWidth val="$gap"/><c:axId val="100"/><c:axId val="200"/>'
            '</c:$barTag>'
            '<c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>'
            '$lineSer<c:marker val="1"/>'
            '<c:axId val="100"/><c:axId val="200"/></c:lineChart>'
            '$axes$secondAxis',
    };

    final bool showLegend = view.showLegend;
    final String pos = rtl && view.legendPos == ChartLegendPos.bottom
        ? 'l'
        : DrawingmlVisualIo.legendPosXml(view.legendPos);
    final String legend = showLegend
        ? '<c:legend><c:legendPos val="$pos"/><c:overlay val="0"/></c:legend>'
        : '';

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<c:date1904 val="0"/><c:lang val="$lang"/><c:roundedCorners val="0"/>'
        '<c:chart>$titleXml<c:autoTitleDeleted val="${showTitle ? 0 : 1}"/>'
        '<c:plotArea><c:layout/>${view.view3d ? '<c:view3D><c:rotX val="18"/>'
                  '<c:rotY val="20"/><c:rAngAx val="0"/>'
                  '<c:perspective val="20"/></c:view3D>' : ''}$plot</c:plotArea>'
        '$legend<c:plotVisOnly val="1"/></c:chart></c:chartSpace>';
  }

  static String _wrap({
    required String title,
    required bool rtl,
    required String titleColor,
    required String plot,
    required ChartDisplay display,
  }) {
    final String lang = rtl ? 'ar-SA' : 'en-US';
    final String algn = rtl ? 'r' : 'l';
    final bool showTitle = display.showTitle && title.trim().isNotEmpty;
    final String titleXml = showTitle
        ? '<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/>'
              '<a:p><a:pPr algn="$algn"${rtl ? ' rtl="1"' : ''}/><a:r>'
              '<a:rPr lang="$lang" sz="1400" b="1">'
              '<a:solidFill><a:srgbClr val="${OfficeMarkup.srgb(titleColor)}"/></a:solidFill>'
              '<a:cs typeface="Arial"/></a:rPr>'
              '<a:t>${OfficeMarkup.escape(title)}</a:t></a:r></a:p>'
              '</c:rich></c:tx><c:overlay val="0"/></c:title>'
        : '';
    final String pos = rtl && display.legendPos == ChartLegendPos.bottom
        ? 'l'
        : DrawingmlVisualIo.legendPosXml(display.legendPos);
    final String legend = display.showLegend
        ? '<c:legend><c:legendPos val="$pos"/><c:overlay val="0"/></c:legend>'
        : '';
    final String view3d = display.view3d
        ? '<c:view3D><c:rotX val="18"/><c:rotY val="20"/>'
              '<c:rAngAx val="0"/><c:perspective val="20"/></c:view3D>'
        : '';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<c:date1904 val="0"/><c:lang val="$lang"/><c:roundedCorners val="0"/>'
        '<c:chart>$titleXml<c:autoTitleDeleted val="${showTitle ? 0 : 1}"/>'
        '<c:plotArea><c:layout/>$view3d$plot</c:plotArea>'
        '$legend<c:plotVisOnly val="1"/></c:chart></c:chartSpace>';
  }

  static String _axisTitle(String text) {
    if (text.trim().isEmpty) {
      return '';
    }
    return '<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:rPr sz="1000"/><a:t>${OfficeMarkup.escape(text)}</a:t>'
        '</a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title>';
  }

  static String _axes({
    required bool horizontal,
    required bool showAxes,
    required bool showGridlines,
    required String categoryTitle,
    required String valueTitle,
  }) {
    final String hide = showAxes ? '0' : '1';
    final String grid = showGridlines ? '<c:majorGridlines/>' : '';
    return '<c:catAx><c:axId val="100"/>'
        '<c:scaling><c:orientation val="minMax"/></c:scaling>'
        '<c:delete val="$hide"/><c:axPos val="${horizontal ? 'l' : 'b'}"/>'
        '${_axisTitle(categoryTitle)}'
        '<c:majorTickMark val="out"/><c:minorTickMark val="none"/>'
        '<c:tickLblPos val="nextTo"/><c:crossAx val="200"/>'
        '<c:crosses val="autoZero"/><c:auto val="1"/>'
        '<c:lblAlgn val="ctr"/><c:lblOffset val="100"/>'
        '<c:noMultiLvlLbl val="0"/></c:catAx>'
        '<c:valAx><c:axId val="200"/>'
        '<c:scaling><c:orientation val="minMax"/></c:scaling>'
        '<c:delete val="$hide"/><c:axPos val="${horizontal ? 'b' : 'l'}"/>'
        '${_axisTitle(valueTitle)}$grid'
        '<c:majorTickMark val="out"/>'
        '<c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>'
        '<c:crossAx val="100"/><c:crosses val="autoZero"/>'
        '<c:crossBetween val="between"/></c:valAx>';
  }
}
