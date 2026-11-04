import 'dart:convert';
import 'dart:typed_data';

import '../opc/content_types.dart';
import '../opc/opc_archive.dart';
import '../opc/relationships.dart';
import '../xml/namespaces.dart';
import 'drawingml_charts.dart';
import 'image_fit.dart';
import 'office_document_theme.dart';
import 'office_markup.dart';

/// Class PptxPalette.
class PptxPalette {
  /// PptxPalette API.
  const PptxPalette({
    this.primary = '2E75B6',
    this.accent = '548235',
    this.muted = '666666',
    this.gold = 'C9A227',
  });

  /// fromTheme API.
  factory PptxPalette.fromTheme(OfficeDocumentTheme theme) {
    return PptxPalette(
      primary: theme.palette.primary,
      accent: theme.palette.accent,
      muted: theme.palette.muted,
      gold: theme.palette.highlight,
    );
  }

  /// primary API.
  final String primary;

  /// accent API.
  final String accent;

  /// muted API.
  final String muted;

  /// gold API.
  final String gold;
}

/// A text box on a [PptxDeckBuilder.addPlacedSlide], in page points.
class PptxPlacedText {
  /// PptxPlacedText API.
  const PptxPlacedText({
    required this.xPt,
    required this.yPt,
    required this.wPt,
    required this.hPt,
    required this.text,
    this.sizePt = 12,
    this.bold = false,
    this.italic = false,
    this.color = '222222',
  });

  /// Left, top-left origin.
  final double xPt;

  /// Top, top-left origin.
  final double yPt;

  /// Width in points.
  final double wPt;

  /// Height in points.
  final double hPt;

  /// text API.
  final String text;

  /// Font size in points.
  final double sizePt;

  /// bold API.
  final bool bold;

  /// italic API.
  final bool italic;

  /// `RRGGBB`.
  final String color;
}

/// Kind of chart placed on a freeform slide.
enum PptxPlacedChartKind { column, bar, pie, line }

/// A native chart on a [PptxDeckBuilder.addPlacedSlide], in page points.
class PptxPlacedChart {
  /// PptxPlacedChart API.
  const PptxPlacedChart({
    required this.xPt,
    required this.yPt,
    required this.wPt,
    required this.hPt,
    required this.title,
    required this.kind,
    required this.points,
  });

  /// Left, top-left origin.
  final double xPt;

  /// Top, top-left origin.
  final double yPt;

  /// Width in points.
  final double wPt;

  /// Height in points.
  final double hPt;

  /// title API.
  final String title;

  /// kind API.
  final PptxPlacedChartKind kind;

  /// points API.
  final List<ChartPoint> points;
}

/// A PNG picture on a [PptxDeckBuilder.addPlacedSlide], in page points.
class PptxPlacedPicture {
  /// PptxPlacedPicture API.
  const PptxPlacedPicture({
    required this.xPt,
    required this.yPt,
    required this.wPt,
    required this.hPt,
    required this.pngBytes,
  });

  /// Left, top-left origin.
  final double xPt;

  /// Top, top-left origin.
  final double yPt;

  /// Width in points.
  final double wPt;

  /// Height in points.
  final double hPt;

  /// PNG bytes. JPEG and raw pixels are not accepted here.
  final Uint8List pngBytes;
}

/// Fluent PowerPoint builder: geometric layouts, charts, notes, contain-fit images.
class PptxDeckBuilder {
  /// PptxDeckBuilder API.
  PptxDeckBuilder({
    bool? rtl,
    PptxPalette? palette,
    OfficeDocumentTheme? theme,
    this.slideWidth = 12192000,
    this.slideHeight = 6858000,
    this.showSlideNumber = false,
    this.footerBar,
  }) : theme =
           theme ??
           OfficeDocumentTheme.light(
             rtl: rtl ?? false,
             page: OfficePageSize.widescreen,
           ),
       palette =
           palette ??
           (theme != null ? PptxPalette.fromTheme(theme) : const PptxPalette()),
       rtl = rtl ?? theme?.rtl ?? false;

  /// rtl API.
  final bool rtl;

  /// palette API.
  final PptxPalette palette;

  /// theme API.
  final OfficeDocumentTheme theme;

  /// slideWidth API.
  final int slideWidth;

  /// slideHeight API.
  final int slideHeight;

  /// showSlideNumber API.
  final bool showSlideNumber;

  /// footerBar API.
  final String? footerBar;
  final List<_SlideDraft> _slides = <_SlideDraft>[];
  final List<({String name, Uint8List bytes})> _images =
      <({String name, Uint8List bytes})>[];
  final List<({int id, String xml})> _charts = <({int id, String xml})>[];
  var _imageSeq = 0;
  var _chartSeq = 0;
  var _shapeId = 2;

  /// palette API.
  OfficePalette get _colors => theme.palette;

  /// addTitleSlide API.
  void addTitleSlide({
    required String title,
    String? subtitle,
    String? footer,
    String? notes,
  }) {
    addCoverSlide(
      title: title,
      subtitle: subtitle,
      footer: footer,
      notes: notes,
    );
  }

  /// addCoverSlide API.
  void addCoverSlide({
    required String title,
    String? kicker,
    String? subtitle,
    String? footer,
    bool accentRail = false,
    String? notes,
  }) {
    final List<String> shapes = <String>[
      _rect(0, 0, slideWidth, slideHeight, palette.primary),
      if (accentRail) _rect(0, 0, 180000, slideHeight, palette.accent),
      if (kicker != null && kicker.isNotEmpty)
        _textBox(
          600000,
          1800000,
          slideWidth - 1200000,
          500000,
          kicker,
          sizePt: 14,
          bold: true,
          color: palette.gold,
        ),
      _textBox(
        600000,
        kicker == null ? 2400000 : 2300000,
        slideWidth - 1200000,
        1400000,
        title,
        sizePt: 40,
        bold: true,
        color: _colors.onPrimary,
      ),
      if (subtitle != null && subtitle.isNotEmpty)
        _textBox(
          600000,
          3900000,
          slideWidth - 1200000,
          800000,
          subtitle,
          sizePt: 20,
          color: palette == const PptxPalette()
              ? 'D6E3F0'
              : _colors.primaryLight,
        ),
      if (footer != null && footer.isNotEmpty)
        _textBox(
          600000,
          6000000,
          slideWidth - 1200000,
          400000,
          footer,
          sizePt: 14,
          color: 'A8C4B8',
        ),
    ];
    _slides.add(_SlideDraft(shapes: shapes, notes: notes));
  }

  /// addSectionSlide API.
  void addSectionSlide({
    required String title,
    String? kicker,
    String? subtitle,
    String? notes,
  }) {
    _slides.add(
      _SlideDraft(
        shapes: <String>[
          _rect(0, 0, slideWidth, slideHeight, palette.primary),
          if (kicker != null && kicker.isNotEmpty)
            _textBox(
              600000,
              2000000,
              slideWidth - 1200000,
              500000,
              kicker,
              sizePt: 16,
              bold: true,
              color: palette.gold,
            ),
          _textBox(
            600000,
            2600000,
            slideWidth - 1200000,
            1400000,
            title,
            sizePt: 36,
            bold: true,
            color: _colors.onPrimary,
          ),
          if (subtitle != null && subtitle.isNotEmpty)
            _textBox(
              600000,
              4200000,
              slideWidth - 1200000,
              800000,
              subtitle,
              sizePt: 18,
              color: _colors.primaryLight,
            ),
        ],
        notes: notes,
      ),
    );
  }

  /// addClosingSlide API.
  void addClosingSlide({
    required String title,
    String? subtitle,
    String? footer,
    String? notes,
  }) {
    addCoverSlide(
      title: title,
      subtitle: subtitle,
      footer: footer,
      notes: notes,
    );
  }

  /// addQuoteSlide API.
  void addQuoteSlide({
    required String quote,
    String? attribution,
    String? title,
    String? notes,
  }) {
    _slides.add(
      _SlideDraft(
        shapes: <String>[
          if (title != null && title.isNotEmpty) _header(title),
          _textBox(
            800000,
            title == null ? 1800000 : 1600000,
            slideWidth - 1600000,
            2800000,
            quote,
            sizePt: 28,
            italic: true,
            color: '222222',
          ),
          if (attribution != null && attribution.isNotEmpty)
            _textBox(
              800000,
              5000000,
              slideWidth - 1600000,
              500000,
              attribution,
              sizePt: 16,
              color: palette.muted,
            ),
        ],
        notes: notes,
      ),
    );
  }

  /// addKpiSlide API.
  void addKpiSlide({
    required String title,
    required List<({String label, String value})> cards,
    String? notes,
  }) {
    final List<({String label, String value})> items = cards.take(8).toList();
    final int count = items.isEmpty ? 1 : items.length;
    final int cols = count <= 2
        ? count
        : (count <= 4 ? 2 : (count <= 6 ? 3 : 4));
    final int rows = (count + cols - 1) ~/ cols;
    const int left = 500000;
    const int top = 1300000;
    final int gap = 200000;
    final int areaW = slideWidth - 1000000;
    final int areaH = 4800000;
    final int cardW = (areaW - gap * (cols - 1)) ~/ cols;
    final int cardH = (areaH - gap * (rows - 1)) ~/ rows;
    final List<String> shapes = <String>[_header(title)];
    for (int i = 0; i < items.length; i++) {
      final int c = i % cols;
      final int r = i ~/ cols;
      final int x = rtl
          ? left + (cols - 1 - c) * (cardW + gap)
          : left + c * (cardW + gap);
      final int y = top + r * (cardH + gap);
      shapes
        ..add(_rect(x, y, cardW, cardH, _colors.surface))
        ..add(_rect(x, y, cardW, 80000, palette.accent))
        ..add(
          _textBox(
            x + 120000,
            y + 200000,
            cardW - 240000,
            400000,
            items[i].label,
            sizePt: 12,
            color: palette.muted,
          ),
        )
        ..add(
          _textBox(
            x + 120000,
            y + 600000,
            cardW - 240000,
            700000,
            items[i].value,
            sizePt: 28,
            bold: true,
            color: palette.primary,
          ),
        );
    }
    _slides.add(_SlideDraft(shapes: shapes, notes: notes));
  }

  /// addTitleBodySlide API.
  void addTitleBodySlide({
    required String title,
    required List<String> bullets,
    String? notes,
  }) {
    _slides.add(
      _SlideDraft(
        shapes: <String>[_header(title), ..._bullets(bullets)],
        notes: notes,
      ),
    );
  }

  /// addImageSlide API.
  void addImageSlide({
    required String title,
    required Uint8List pngBytes,
    String? caption,
    String? notes,
  }) {
    if (pngBytes.isEmpty) {
      return;
    }
    final int imgId = _addImage(pngBytes);
    const int boxX = 800000;
    const int boxY = 1400000;
    final int boxCx = slideWidth - 1600000;
    final int boxCy = caption == null ? 4200000 : 3800000;
    final ImageSize size = ImageFit.readSize(pngBytes) ?? const ImageSize(4, 3);
    final ({int cx, int cy}) fitted = ImageFit.containEmu(
      srcWidthPx: size.widthPx,
      srcHeightPx: size.heightPx,
      maxCx: boxCx,
      maxCy: boxCy,
    );
    final int x = boxX + (boxCx - fitted.cx) ~/ 2;
    final int y = boxY + (boxCy - fitted.cy) ~/ 2;
    _slides.add(
      _SlideDraft(
        shapes: <String>[
          _header(title),
          _picture(imgId, x, y, fitted.cx, fitted.cy),
          if (caption != null && caption.isNotEmpty)
            _textBox(
              800000,
              5800000,
              slideWidth - 1600000,
              400000,
              caption,
              sizePt: 12,
              color: palette.muted,
            ),
        ],
        imageIds: <int>[imgId],
        notes: notes,
      ),
    );
  }

  /// One slide of absolutely positioned text and PNG pictures.
  ///
  /// Coordinates are page points with a top-left origin, the same space as
  /// a PDF display list. The slide size is [slideWidth] and [slideHeight].
  void addPlacedSlide({
    required List<PptxPlacedText> texts,
    required List<PptxPlacedPicture> pictures,
    List<PptxPlacedChart> charts = const <PptxPlacedChart>[],
  }) {
    final List<String> shapes = <String>[];
    final List<int> imageIds = <int>[];
    final List<int> chartIds = <int>[];
    for (final PptxPlacedChart chart in charts) {
      if (chart.points.isEmpty) {
        continue;
      }
      final String xml = chart.kind == PptxPlacedChartKind.column
          ? DrawingmlCharts.bar(
              title: chart.title.isEmpty ? 'Chart' : chart.title,
              series: chart.points,
              rtl: rtl,
              horizontal: false,
              theme: theme,
            )
          : _chartXml(
              chart.title,
              switch (chart.kind) {
                PptxPlacedChartKind.bar => ChartKind.bar,
                PptxPlacedChartKind.pie => ChartKind.pie,
                PptxPlacedChartKind.line => ChartKind.line,
                PptxPlacedChartKind.column => ChartKind.bar,
              },
              chart.points,
              const <ChartSeries>[],
            );
      if (!xml.contains('<c:pt ')) {
        continue;
      }
      _chartSeq += 1;
      _charts.add((id: _chartSeq, xml: xml));
      chartIds.add(_chartSeq);
      shapes.add(
        _chartFrame(
          _chartSeq,
          x: _ptToEmu(chart.xPt),
          y: _ptToEmu(chart.yPt),
          cx: _ptToEmu(chart.wPt < 8 ? 8 : chart.wPt),
          cy: _ptToEmu(chart.hPt < 8 ? 8 : chart.hPt),
        ),
      );
    }
    for (final PptxPlacedPicture picture in pictures) {
      if (picture.pngBytes.isEmpty) {
        continue;
      }
      final int imgId = _addImage(picture.pngBytes);
      imageIds.add(imgId);
      shapes.add(
        _picture(
          imgId,
          _ptToEmu(picture.xPt),
          _ptToEmu(picture.yPt),
          _ptToEmu(picture.wPt),
          _ptToEmu(picture.hPt),
        ),
      );
    }
    for (final PptxPlacedText text in texts) {
      final String value = text.text.trim();
      if (value.isEmpty) {
        continue;
      }
      shapes.add(
        _textBox(
          _ptToEmu(text.xPt),
          _ptToEmu(text.yPt),
          _ptToEmu(text.wPt < 8 ? 8 : text.wPt),
          _ptToEmu(text.hPt < text.sizePt ? text.sizePt : text.hPt),
          value,
          sizePt: text.sizePt.round().clamp(6, 96),
          bold: text.bold,
          italic: text.italic,
          color: text.color,
        ),
      );
    }
    if (shapes.isEmpty) {
      shapes.add(_textBox(400000, 400000, slideWidth - 800000, 600000, ' '));
    }
    _slides.add(
      _SlideDraft(shapes: shapes, imageIds: imageIds, chartIds: chartIds),
    );
  }

  int _ptToEmu(double points) {
    final int emu = (points * 12700).round();
    return emu < 0 ? 0 : emu;
  }

  /// addSplitMediaSlide API.
  void addSplitMediaSlide({
    required String title,
    required List<String> bullets,
    required Uint8List imageBytes,
    String? notes,
  }) {
    if (imageBytes.isEmpty) {
      addTitleBodySlide(title: title, bullets: bullets, notes: notes);
      return;
    }
    final int imgId = _addImage(imageBytes);
    final int textX = rtl ? slideWidth ~/ 2 + 200000 : 500000;
    final int imgBoxX = rtl ? 500000 : slideWidth ~/ 2 + 200000;
    final int colW = slideWidth ~/ 2 - 700000;
    const int imgBoxY = 1300000;
    const int imgBoxCy = 4800000;
    final ImageSize size =
        ImageFit.readSize(imageBytes) ?? const ImageSize(4, 3);
    final ({int cx, int cy}) fitted = ImageFit.containEmu(
      srcWidthPx: size.widthPx,
      srcHeightPx: size.heightPx,
      maxCx: colW,
      maxCy: imgBoxCy,
    );
    final int imgX = imgBoxX + (colW - fitted.cx) ~/ 2;
    final int imgY = imgBoxY + (imgBoxCy - fitted.cy) ~/ 2;
    _slides.add(
      _SlideDraft(
        shapes: <String>[
          _header(title),
          ..._bullets(bullets, x: textX, cx: colW),
          _picture(imgId, imgX, imgY, fitted.cx, fitted.cy),
        ],
        imageIds: <int>[imgId],
        notes: notes,
      ),
    );
  }

  /// addSplitChartSlide API.
  void addSplitChartSlide({
    required String title,
    required List<String> bullets,
    ChartKind kind = ChartKind.pie,
    List<ChartPoint> points = const <ChartPoint>[],
    List<ChartSeries> series = const <ChartSeries>[],
    String? notes,
  }) {
    final String xml = _chartXml(title, kind, points, series);
    if (!xml.contains('<c:pt ')) {
      addTitleBodySlide(title: title, bullets: bullets, notes: notes);
      return;
    }
    _chartSeq += 1;
    _charts.add((id: _chartSeq, xml: xml));
    final int textX = rtl ? slideWidth ~/ 2 + 200000 : 500000;
    final int chartX = rtl ? 400000 : slideWidth ~/ 2 + 100000;
    final int colW = slideWidth ~/ 2 - 700000;
    _slides.add(
      _SlideDraft(
        shapes: <String>[
          _header(title),
          ..._bullets(bullets, x: textX, cx: colW),
          _chartFrame(_chartSeq, x: chartX, cx: colW + 200000, cy: 4600000),
        ],
        chartIds: <int>[_chartSeq],
        notes: notes,
      ),
    );
  }

  /// addTableSlide API.
  void addTableSlide({
    required String title,
    required List<List<String>> rows,
    bool hasHeader = true,
    String? notes,
  }) {
    _slides.add(
      _SlideDraft(
        shapes: <String>[
          _header(title),
          _table(rows, hasHeader: hasHeader),
        ],
        notes: notes,
      ),
    );
  }

  /// addTwoColumnSlide API.
  void addTwoColumnSlide({
    required String title,
    required List<String> left,
    required List<String> right,
    String? notes,
  }) {
    addTwoColumnTextSlide(title: title, left: left, right: right, notes: notes);
  }

  /// addTwoColumnTextSlide API.
  void addTwoColumnTextSlide({
    required String title,
    required List<String> left,
    required List<String> right,
    String? leftTitle,
    String? rightTitle,
    String? notes,
  }) {
    final int leftX = rtl ? slideWidth ~/ 2 + 200000 : 500000;
    final int rightX = rtl ? 500000 : slideWidth ~/ 2 + 200000;
    final int cx = slideWidth ~/ 2 - 700000;
    _slides.add(
      _SlideDraft(
        shapes: <String>[
          _header(title),
          if (leftTitle != null && leftTitle.isNotEmpty)
            _textBox(
              leftX,
              1100000,
              cx,
              400000,
              leftTitle,
              sizePt: 16,
              bold: true,
            ),
          if (rightTitle != null && rightTitle.isNotEmpty)
            _textBox(
              rightX,
              1100000,
              cx,
              400000,
              rightTitle,
              sizePt: 16,
              bold: true,
            ),
          ..._bullets(
            left,
            x: leftX,
            cx: cx,
            y: leftTitle == null ? 1200000 : 1550000,
          ),
          ..._bullets(
            right,
            x: rightX,
            cx: cx,
            y: rightTitle == null ? 1200000 : 1550000,
          ),
        ],
        notes: notes,
      ),
    );
  }

  /// addPieChartSlide API.
  void addPieChartSlide({
    required String title,
    required List<ChartPoint> series,
    String? notes,
  }) {
    _addChartSlide(
      title,
      DrawingmlCharts.pie(
        title: title,
        series: series,
        rtl: rtl,
        titleColor: palette.primary,
        theme: theme,
      ),
      notes: notes,
    );
  }

  /// addBarChartSlide API.
  void addBarChartSlide({
    required String title,
    required List<ChartPoint> series,
    bool horizontal = true,
    String? notes,
  }) {
    _addChartSlide(
      title,
      DrawingmlCharts.bar(
        title: title,
        series: series,
        rtl: rtl,
        horizontal: horizontal,
        titleColor: palette.primary,
        theme: theme,
      ),
      notes: notes,
    );
  }

  /// addLineChartSlide API.
  void addLineChartSlide({
    required String title,
    required List<ChartSeries> series,
    bool markers = true,
    String? notes,
  }) {
    _addChartSlide(
      title,
      DrawingmlCharts.line(
        title: title,
        series: series,
        rtl: rtl,
        markers: markers,
        titleColor: palette.primary,
        theme: theme,
      ),
      notes: notes,
    );
  }

  /// build API.
  Uint8List build({String? password}) {
    if (_slides.isEmpty) {
      addTitleSlide(title: 'Presentation');
    }
    final OpcPackage package = OpcPackage.empty();
    package.packageRelationships.add(
      type: RelationshipTypes.officeDocument,
      target: 'ppt/presentation.xml',
    );
    package.createPart(
      '/ppt/presentation.xml',
      OfficeContentTypes.slideMain,
      utf8.encode(_presentationXml()),
    );
    package.createPart(
      '/ppt/slideMasters/slideMaster1.xml',
      OfficeContentTypes.slideMaster,
      utf8.encode(_slideMasterXml()),
    );
    package.createPart(
      '/ppt/slideLayouts/slideLayout1.xml',
      OfficeContentTypes.slideLayout,
      utf8.encode(_slideLayoutXml()),
    );
    package.createPart(
      '/ppt/theme/theme1.xml',
      OfficeContentTypes.theme,
      utf8.encode(_themeXml()),
    );
    package.createPart(
      '/ppt/presProps.xml',
      OfficeContentTypes.slidePresProps,
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentationPr xmlns:p="${OfficeNamespaces.p}"/>',
      ),
    );
    package.createPart(
      '/ppt/viewProps.xml',
      OfficeContentTypes.slideViewProps,
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:viewPr xmlns:a="${OfficeNamespaces.a}" xmlns:p="${OfficeNamespaces.p}">'
        '<p:normalViewPr><p:restoredLeft sz="15620"/><p:restoredTop sz="94660"/>'
        '</p:normalViewPr></p:viewPr>',
      ),
    );
    package.createPart(
      '/ppt/tableStyles.xml',
      OfficeContentTypes.slideTableStyles,
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<a:tblStyleLst xmlns:a="${OfficeNamespaces.a}" '
        'def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>',
      ),
    );

    final bool anyNotes = _slides.any(
      (_SlideDraft s) => s.notes != null && s.notes!.trim().isNotEmpty,
    );
    if (anyNotes) {
      package.createPart(
        '/ppt/notesMasters/notesMaster1.xml',
        OfficeContentTypes.notesMaster,
        utf8.encode(_notesMasterXml()),
      );
    }

    final RelationshipCollection presRels = package.relationshipsFor(
      '/ppt/presentation.xml',
    );
    presRels
      ..add(
        type: RelationshipTypes.slideMaster,
        target: 'slideMasters/slideMaster1.xml',
        id: 'rIdMaster',
      )
      ..add(
        type: RelationshipTypes.theme,
        target: 'theme/theme1.xml',
        id: 'rIdTheme',
      )
      ..add(
        type: RelationshipTypes.presProps,
        target: 'presProps.xml',
        id: 'rIdPresProps',
      )
      ..add(
        type: RelationshipTypes.viewProps,
        target: 'viewProps.xml',
        id: 'rIdViewProps',
      )
      ..add(
        type: RelationshipTypes.tableStyles,
        target: 'tableStyles.xml',
        id: 'rIdTableStyles',
      );
    if (anyNotes) {
      presRels.add(
        type: RelationshipTypes.notesMaster,
        target: 'notesMasters/notesMaster1.xml',
        id: 'rIdNotesMaster',
      );
      package
          .relationshipsFor('/ppt/notesMasters/notesMaster1.xml')
          .add(
            type: RelationshipTypes.theme,
            target: '../theme/theme1.xml',
            id: 'rId1',
          );
    }

    package.relationshipsFor('/ppt/slideMasters/slideMaster1.xml')
      ..add(
        type: RelationshipTypes.slideLayout,
        target: '../slideLayouts/slideLayout1.xml',
        id: 'rId1',
      )
      ..add(
        type: RelationshipTypes.theme,
        target: '../theme/theme1.xml',
        id: 'rId2',
      );
    package
        .relationshipsFor('/ppt/slideLayouts/slideLayout1.xml')
        .add(
          type: RelationshipTypes.slideMaster,
          target: '../slideMasters/slideMaster1.xml',
          id: 'rId1',
        );

    for (int i = 0; i < _slides.length; i++) {
      final int n = i + 1;
      final _SlideDraft slide = _slides[i];
      package.createPart(
        '/ppt/slides/slide$n.xml',
        OfficeContentTypes.slide,
        utf8.encode(_slideXml(slide, n)),
      );
      presRels.add(
        type: RelationshipTypes.slide,
        target: 'slides/slide$n.xml',
        id: 'rIdSlide$n',
      );
      final RelationshipCollection slideRels = package.relationshipsFor(
        '/ppt/slides/slide$n.xml',
      );
      slideRels.add(
        type: RelationshipTypes.slideLayout,
        target: '../slideLayouts/slideLayout1.xml',
        id: 'rId1',
      );
      for (final int imgId in slide.imageIds) {
        slideRels.add(
          type: RelationshipTypes.image,
          target: '../media/image$imgId.png',
          id: 'rIdImg$imgId',
        );
      }
      for (final int chartId in slide.chartIds) {
        slideRels.add(
          type: RelationshipTypes.chart,
          target: '../charts/chart$chartId.xml',
          id: 'rIdChart$chartId',
        );
      }
      final String? notes = slide.notes?.trim();
      if (notes != null && notes.isNotEmpty) {
        package.createPart(
          '/ppt/notesSlides/notesSlide$n.xml',
          OfficeContentTypes.notesSlide,
          utf8.encode(_notesSlideXml(notes)),
        );
        slideRels.add(
          type: RelationshipTypes.notesSlide,
          target: '../notesSlides/notesSlide$n.xml',
          id: 'rIdNotes',
        );
        package.relationshipsFor('/ppt/notesSlides/notesSlide$n.xml')
          ..add(
            type: RelationshipTypes.notesMaster,
            target: '../notesMasters/notesMaster1.xml',
            id: 'rId1',
          )
          ..add(
            type: RelationshipTypes.slide,
            target: '../slides/slide$n.xml',
            id: 'rId2',
          );
      }
    }
    for (final ({String name, Uint8List bytes}) img in _images) {
      package.createPart('/ppt/media/${img.name}', 'image/png', img.bytes);
    }
    for (final ({int id, String xml}) chart in _charts) {
      package.createPart(
        '/ppt/charts/chart${chart.id}.xml',
        OfficeContentTypes.drawingChart,
        utf8.encode(chart.xml),
      );
    }
    return package.save(password: password);
  }

  void _addChartSlide(String title, String xml, {String? notes}) {
    if (!xml.contains('<c:pt ')) {
      return;
    }
    _chartSeq += 1;
    _charts.add((id: _chartSeq, xml: xml));
    _slides.add(
      _SlideDraft(
        shapes: <String>[_header(title), _chartFrame(_chartSeq)],
        chartIds: <int>[_chartSeq],
        notes: notes,
      ),
    );
  }

  String _chartXml(
    String title,
    ChartKind kind,
    List<ChartPoint> points,
    List<ChartSeries> series,
  ) {
    return switch (kind) {
      ChartKind.pie => DrawingmlCharts.pie(
        title: title,
        series: points,
        rtl: rtl,
        theme: theme,
      ),
      ChartKind.donut => DrawingmlCharts.donut(
        title: title,
        series: points,
        rtl: rtl,
        theme: theme,
      ),
      ChartKind.bar => DrawingmlCharts.bar(
        title: title,
        series: points,
        rtl: rtl,
        theme: theme,
      ),
      ChartKind.line => DrawingmlCharts.line(
        title: title,
        series: series.isEmpty
            ? <ChartSeries>[ChartSeries(name: title, points: points)]
            : series,
        rtl: rtl,
        theme: theme,
      ),
      ChartKind.area => DrawingmlCharts.area(
        title: title,
        series: series.isEmpty
            ? <ChartSeries>[ChartSeries(name: title, points: points)]
            : series,
        rtl: rtl,
        theme: theme,
      ),
      ChartKind.stackedBar => DrawingmlCharts.stackedBar(
        title: title,
        series: series.isEmpty
            ? <ChartSeries>[ChartSeries(name: title, points: points)]
            : series,
        rtl: rtl,
        theme: theme,
      ),
      ChartKind.percentStackedBar ||
      ChartKind.stackedArea ||
      ChartKind.radar ||
      ChartKind.combo => DrawingmlCharts.multiSeries(
        title: title,
        series: series.isEmpty
            ? <ChartSeries>[ChartSeries(name: title, points: points)]
            : series,
        rtl: rtl,
        kind: kind,
        theme: theme,
      ),
      ChartKind.scatter || ChartKind.bubble => DrawingmlCharts.xy(
        title: title,
        series: series.isEmpty
            ? <ChartSeries>[ChartSeries(name: title, points: points)]
            : series,
        rtl: rtl,
        bubble: kind == ChartKind.bubble,
        theme: theme,
      ),
    };
  }

  int _addImage(Uint8List bytes) {
    _imageSeq += 1;
    _images.add((name: 'image$_imageSeq.png', bytes: bytes));
    return _imageSeq;
  }

  int _nextId() => _shapeId++;

  String _header(String title) {
    return '${_rect(0, 0, slideWidth, 900000, palette.primary)}'
        '${_textBox(500000, 220000, slideWidth - 1000000, 500000, title, sizePt: 24, bold: true, color: _colors.onPrimary)}';
  }

  List<String> _chrome(int slideNumber) {
    if (!showSlideNumber && (footerBar == null || footerBar!.isEmpty)) {
      return const <String>[];
    }
    final String label = <String>[
      if (footerBar != null && footerBar!.isNotEmpty) footerBar!,
      if (showSlideNumber) '$slideNumber',
    ].join('  ·  ');
    return <String>[
      _rect(0, slideHeight - 420000, slideWidth, 420000, _colors.surface),
      _textBox(
        500000,
        slideHeight - 380000,
        slideWidth - 1000000,
        320000,
        label,
        sizePt: 11,
        color: palette.muted,
      ),
    ];
  }

  List<String> _bullets(
    List<String> items, {
    int x = 500000,
    int y = 1200000,
    int cx = 0,
  }) {
    final int width = cx == 0 ? slideWidth - 1000000 : cx;
    final StringBuffer paras = StringBuffer();
    for (final String item
        in items.where((String s) => s.trim().isNotEmpty).take(12)) {
      paras.write(_para('• ${item.trim()}', 18, false, '222222'));
    }
    return <String>[_textBoxRaw(x, y, width, 5000000, paras.toString())];
  }

  String _rect(int x, int y, int cx, int cy, String fill) {
    final int id = _nextId();
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Shape $id"/>'
        '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>'
        '<a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
        '<a:solidFill><a:srgbClr val="${OfficeMarkup.srgb(fill)}"/></a:solidFill>'
        '<a:ln><a:noFill/></a:ln></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>';
  }

  String _textBox(
    int x,
    int y,
    int cx,
    int cy,
    String text, {
    int sizePt = 18,
    bool bold = false,
    bool italic = false,
    String color = '222222',
  }) {
    return _textBoxRaw(
      x,
      y,
      cx,
      cy,
      _para(text, sizePt, bold, color, italic: italic),
    );
  }

  String _textBoxRaw(int x, int y, int cx, int cy, String paragraphs) {
    final int id = _nextId();
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Text $id"/>'
        '<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr>'
        '<a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/>'
        '</p:spPr><p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>'
        '$paragraphs</p:txBody></p:sp>';
  }

  String _para(
    String text,
    int sizePt,
    bool bold,
    String color, {
    bool italic = false,
  }) {
    final String face = theme.fontFamily;
    return '<a:p><a:pPr algn="${rtl ? 'r' : 'l'}"${rtl ? ' rtl="1"' : ''}/>'
        '<a:r><a:rPr lang="${rtl ? 'ar-SA' : 'en-US'}" sz="${sizePt * 100}"'
        '${bold ? ' b="1"' : ''}${italic ? ' i="1"' : ''}>'
        '<a:solidFill><a:srgbClr val="${OfficeMarkup.srgb(color)}"/></a:solidFill>'
        '<a:latin typeface="$face"/><a:cs typeface="$face"/></a:rPr>'
        '<a:t>${OfficeMarkup.escape(text)}</a:t></a:r></a:p>';
  }

  String _picture(int imgId, int x, int y, int cx, int cy) {
    final int id = _nextId();
    return '<p:pic><p:nvPicPr><p:cNvPr id="$id" name="Picture $id"/>'
        '<p:cNvPicPr/><p:nvPr/></p:nvPicPr>'
        '<p:blipFill><a:blip r:embed="rIdImg$imgId"/><a:stretch><a:fillRect/></a:stretch>'
        '</p:blipFill><p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/>'
        '</a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>';
  }

  String _chartFrame(
    int chartId, {
    int x = 800000,
    int y = 1300000,
    int? cx,
    int cy = 4800000,
  }) {
    final int width = cx ?? slideWidth - 1600000;
    final int id = _nextId();
    return '<p:graphicFrame><p:nvGraphicFramePr>'
        '<p:cNvPr id="$id" name="Chart $id"/><p:cNvGraphicFramePr/>'
        '<p:nvPr/></p:nvGraphicFramePr>'
        '<p:xfrm><a:off x="$x" y="$y"/>'
        '<a:ext cx="$width" cy="$cy"/></p:xfrm>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
        '<c:chart xmlns:c="${OfficeNamespaces.c}" xmlns:r="${OfficeNamespaces.r}" '
        'r:id="rIdChart$chartId"/></a:graphicData></a:graphic></p:graphicFrame>';
  }

  String _table(List<List<String>> rows, {required bool hasHeader}) {
    if (rows.isEmpty) {
      return '';
    }
    final int cols = rows.fold<int>(
      0,
      (int a, List<String> r) => a > r.length ? a : r.length,
    );
    final int tableW = slideWidth - 1000000;
    final int colW = cols == 0 ? tableW : tableW ~/ cols;
    final StringBuffer grid = StringBuffer('<a:tblGrid>');
    for (int i = 0; i < cols; i++) {
      grid.write('<a:gridCol w="$colW"/>');
    }
    grid.write('</a:tblGrid>');
    final StringBuffer body = StringBuffer();
    for (int r = 0; r < rows.length; r++) {
      body.write('<a:tr h="400000">');
      for (int c = 0; c < cols; c++) {
        final String text = c < rows[r].length ? rows[r][c] : '';
        final bool header = hasHeader && r == 0;
        final String fill = header
            ? _colors.tableHeader
            : (r.isOdd ? _colors.tableBand : _colors.surface);
        final String color = header ? _colors.onPrimary : '222222';
        body.write(
          '<a:tc><a:tcPr><a:solidFill><a:srgbClr val="${OfficeMarkup.srgb(fill)}"/>'
          '</a:solidFill></a:tcPr><a:txBody><a:bodyPr/><a:lstStyle/>'
          '${_para(text, header ? 12 : 11, header, color)}</a:txBody></a:tc>',
        );
      }
      body.write('</a:tr>');
    }
    final int id = _nextId();
    return '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="$id" name="Table $id"/>'
        '<p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
        '<p:xfrm><a:off x="500000" y="1200000"/><a:ext cx="$tableW" cy="4800000"/></p:xfrm>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">'
        '<a:tbl><a:tblPr/>$grid$body</a:tbl></a:graphicData></a:graphic></p:graphicFrame>';
  }

  String _slideXml(_SlideDraft slide, int number) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="${OfficeNamespaces.a}" xmlns:r="${OfficeNamespaces.r}" '
        'xmlns:p="${OfficeNamespaces.p}" xmlns:c="${OfficeNamespaces.c}">'
        '<p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '${slide.shapes.join()}${_chrome(number).join()}</p:spTree></p:cSld>'
        '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
  }

  String _presentationXml() {
    final StringBuffer ids = StringBuffer('<p:sldIdLst>');
    for (int i = 1; i <= _slides.length; i++) {
      ids.write('<p:sldId id="${255 + i}" r:id="rIdSlide$i"/>');
    }
    ids.write('</p:sldIdLst>');
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:r="${OfficeNamespaces.r}" xmlns:p="${OfficeNamespaces.p}">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rIdMaster"/></p:sldMasterIdLst>'
        '$ids<p:sldSz cx="$slideWidth" cy="$slideHeight"/>'
        '<p:notesSz cx="6858000" cy="9144000"/></p:presentation>';
  }

  String _slideMasterXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldMaster xmlns:a="${OfficeNamespaces.a}" xmlns:r="${OfficeNamespaces.r}" '
        'xmlns:p="${OfficeNamespaces.p}">'
        '<p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="${OfficeMarkup.srgb(_colors.surface)}"/></a:solidFill>'
        '<a:effectLst/></p:bgPr></p:bg><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '</p:spTree></p:cSld>'
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
        'accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" '
        'accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
        '</p:sldMaster>';
  }

  String _slideLayoutXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldLayout xmlns:a="${OfficeNamespaces.a}" xmlns:p="${OfficeNamespaces.p}" '
        'type="blank" preserve="1"><p:cSld name="Blank"><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>';
  }

  String _themeXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<a:theme xmlns:a="${OfficeNamespaces.a}" name="Office">'
        '<a:themeElements><a:clrScheme name="Office">'
        '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
        '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
        '<a:dk2><a:srgbClr val="1F4E79"/></a:dk2>'
        '<a:lt2><a:srgbClr val="EEECE1"/></a:lt2>'
        '<a:accent1><a:srgbClr val="${OfficeMarkup.srgb(palette.primary)}"/></a:accent1>'
        '<a:accent2><a:srgbClr val="${OfficeMarkup.srgb(palette.accent)}"/></a:accent2>'
        '<a:accent3><a:srgbClr val="${OfficeMarkup.srgb(palette.gold)}"/></a:accent3>'
        '<a:accent4><a:srgbClr val="C45C12"/></a:accent4>'
        '<a:accent5><a:srgbClr val="5B2C6F"/></a:accent5>'
        '<a:accent6><a:srgbClr val="548235"/></a:accent6>'
        '<a:hlink><a:srgbClr val="0563C1"/></a:hlink>'
        '<a:folHlink><a:srgbClr val="954F72"/></a:folHlink>'
        '</a:clrScheme>'
        '<a:fontScheme name="Office">'
        '<a:majorFont><a:latin typeface="${theme.fontFamily}"/><a:ea typeface="${theme.fontFamily}"/>'
        '<a:cs typeface="${theme.fontFamily}"/></a:majorFont>'
        '<a:minorFont><a:latin typeface="${theme.fontFamily}"/><a:ea typeface="${theme.fontFamily}"/>'
        '<a:cs typeface="${theme.fontFamily}"/></a:minorFont></a:fontScheme>'
        '<a:fmtScheme name="Office"><a:fillStyleLst>'
        '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
        '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
        '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>'
        '<a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/>'
        '</a:solidFill></a:ln><a:ln w="25400"><a:solidFill><a:schemeClr val="phClr"/>'
        '</a:solidFill></a:ln><a:ln w="38100"><a:solidFill><a:schemeClr val="phClr"/>'
        '</a:solidFill></a:ln></a:lnStyleLst>'
        '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle>'
        '<a:effectStyle><a:effectLst/></a:effectStyle>'
        '<a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
        '<a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
        '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
        '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>'
        '</a:fmtScheme></a:themeElements><a:objectDefaults/></a:theme>';
  }

  String _notesMasterXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:notesMaster xmlns:a="${OfficeNamespaces.a}" xmlns:r="${OfficeNamespaces.r}" '
        'xmlns:p="${OfficeNamespaces.p}">'
        '<p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '</p:spTree></p:cSld>'
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
        'accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" '
        'accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '</p:notesMaster>';
  }

  String _notesSlideXml(String notes) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:notes xmlns:a="${OfficeNamespaces.a}" xmlns:r="${OfficeNamespaces.r}" '
        'xmlns:p="${OfficeNamespaces.p}">'
        '<p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Notes"/><p:cNvSpPr txBox="1"/>'
        '<p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
        '<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>'
        '${_para(notes, 12, false, '222222')}</p:txBody></p:sp>'
        '</p:spTree></p:cSld>'
        '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>';
  }
}

class _SlideDraft {
  _SlideDraft({
    required this.shapes,
    List<int>? imageIds,
    List<int>? chartIds,
    this.notes,
  }) : imageIds = imageIds ?? const <int>[],
       chartIds = chartIds ?? const <int>[];

  /// shapes API.
  final List<String> shapes;

  /// imageIds API.
  final List<int> imageIds;

  /// chartIds API.
  final List<int> chartIds;

  /// notes API.
  final String? notes;
}
