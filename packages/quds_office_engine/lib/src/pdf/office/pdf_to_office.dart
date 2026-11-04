import 'dart:typed_data';

import '../../builders/office_markup.dart';
import '../../builders/pptx_builder.dart';
import '../../builders/xlsx_io.dart';
import '../../visual/office_visual.dart';
import '../../word/model/wml_document.dart';
import '../../word/properties/wml_properties.dart';
import '../../word/serial/word_serializer.dart';
import '../file/model/pdf_file.dart';
import 'pdf_office_layout.dart';
import 'pdf_office_model.dart';

/// Reads a PDF file into DOCX, XLSX, or a freeform PPTX.
///
/// DOCX keeps each line and each JPEG or PNG where it sat on the page,
/// and rebuilds a ruled table, a vector chart, and a table of contents
/// when the page actually contains them. XLSX keeps those tables and the
/// chart's numbers. A page with no text layer is reported; pixels are not
/// recognized as letters.
abstract final class PdfToOffice {
  /// Pages, lines, tables, images, and the limits that were hit.
  static PdfOfficeRecovery recover(
    PdfFile file, {
    void Function(int index, int count)? onPage,
  }) => PdfOfficeLayout.recover(file, onPage: onPage);

  /// One section per page. Each line and each picture keeps its page position.
  static Uint8List toDocx(Uint8List bytes, {String? password}) {
    return docxFrom(_open(bytes, password));
  }

  /// [toDocx] for a file that is already open.
  static Uint8List docxFrom(PdfOfficeRecovery recovery) {
    final bool printed = recovery.pages.any(
      (PdfOfficePage page) => _printedToc(page.lines).length >= 3,
    );
    final List<WmlSection> sections = <WmlSection>[
      if (!printed && recovery.toc.length >= 2) _tocSection(recovery),
      for (final PdfOfficePage page in recovery.pages) _docxSection(page),
    ];
    if (sections.isEmpty) {
      sections.add(_docxSection(_emptyPage()));
    }
    return WordSerializer().writeBytes(WmlDocument(sections: sections));
  }

  /// One sheet per ruled table. Prose that is not in a table is one column.
  static Uint8List toXlsx(Uint8List bytes, {String? password}) {
    return xlsxFrom(_open(bytes, password));
  }

  /// [toXlsx] for a file that is already open.
  static Uint8List xlsxFrom(PdfOfficeRecovery recovery) {
    final XlsxWorkbookBuilder book = XlsxWorkbookBuilder();
    var tables = 0;
    final List<String> prose = <String>[];
    var proseRtl = false;
    for (final PdfOfficePage page in recovery.pages) {
      for (final PdfOfficeTable table in page.tables) {
        tables += 1;
        final XlsxSheetBuilder sheet = book.addSheet('Table $tables');
        sheet.rightToLeft = page.rtl;
        for (var r = 0; r < table.rows.length; r++) {
          for (var c = 0; c < table.rows[r].length; c++) {
            sheet.setCell(r, c, _cellValue(table.rows[r][c]));
          }
        }
      }
      for (final PdfOfficeLine line in page.lines) {
        final String text = line.text.trim();
        if (text.isEmpty) {
          continue;
        }
        prose.add(text);
        proseRtl = proseRtl || line.rtl;
      }
    }
    if (prose.isNotEmpty) {
      final XlsxSheetBuilder sheet = book.addSheet('Text');
      sheet.rightToLeft = proseRtl;
      for (var i = 0; i < prose.length; i++) {
        sheet.setCell(i, 0, prose[i]);
      }
    }
    var chartNumber = 0;
    for (final PdfOfficePage page in recovery.pages) {
      for (final PdfOfficeChart chart in page.charts) {
        chartNumber += 1;
        final XlsxSheetBuilder sheet = book.addSheet('Chart $chartNumber');
        sheet.setCell(0, 0, 'Label');
        sheet.setCell(0, 1, 'Value');
        for (var i = 0; i < chart.points.length; i++) {
          sheet.setCell(i + 1, 0, chart.points[i].label);
          sheet.setCell(i + 1, 1, chart.points[i].value);
        }
      }
    }
    if (book.sheets.isEmpty) {
      book.addSheet('Text').setCell(0, 0, pdfOfficeNoTextMessage);
    }
    return book.build();
  }

  /// One slide per page: positioned text boxes and PNG pictures.
  static Uint8List toPptx(Uint8List bytes, {String? password}) {
    return pptxFrom(_open(bytes, password));
  }

  /// [toPptx] for a file that is already open.
  static Uint8List pptxFrom(PdfOfficeRecovery recovery) {
    var width = 200.0;
    var height = 200.0;
    for (final PdfOfficePage page in recovery.pages) {
      if (page.width > width) {
        width = page.width;
      }
      if (page.height > height) {
        height = page.height;
      }
    }
    final PptxDeckBuilder deck = PptxDeckBuilder(
      rtl: _rtl(recovery),
      slideWidth: (width * 12700).round(),
      slideHeight: (height * 12700).round(),
    );
    if (recovery.pages.isEmpty) {
      deck.addPlacedSlide(
        texts: <PptxPlacedText>[
          const PptxPlacedText(
            xPt: 36,
            yPt: 36,
            wPt: 400,
            hPt: 40,
            text: pdfOfficeNoTextMessage,
          ),
        ],
        pictures: const <PptxPlacedPicture>[],
      );
    }
    for (final PdfOfficePage page in recovery.pages) {
      final List<PptxPlacedText> texts = <PptxPlacedText>[
        for (final PdfOfficeLine line in page.lines)
          PptxPlacedText(
            xPt: line.x,
            yPt: line.y - line.fontSize,
            wPt: line.width < line.fontSize ? line.fontSize * 8 : line.width,
            hPt: line.fontSize * 1.6,
            text: line.text,
            sizePt: line.fontSize,
            bold: line.bold,
            italic: line.italic,
            color: _rgb(line.color),
          ),
        for (final PdfOfficeTable table in page.tables)
          for (var r = 0; r < table.rows.length; r++)
            for (var c = 0; c < table.rows[r].length; c++)
              if (table.rows[r][c].trim().isNotEmpty)
                PptxPlacedText(
                  xPt: table.x + _colLeft(table, c),
                  yPt: table.y + _rowTop(table, r),
                  wPt: _colWidth(table),
                  hPt: _rowHeight(table),
                  text: table.rows[r][c],
                  sizePt: 12,
                ),
      ];
      if (texts.isEmpty && page.lines.isEmpty && !_pageTableText(page)) {
        texts.add(
          const PptxPlacedText(
            xPt: 36,
            yPt: 36,
            wPt: 460,
            hPt: 48,
            text: pdfOfficeNoTextMessage,
          ),
        );
      }
      final List<PptxPlacedPicture> pictures = <PptxPlacedPicture>[];
      for (final PdfOfficeImage image in page.images) {
        final Uint8List? bytes = image.bytes;
        if (bytes == null) {
          continue;
        }
        if (!image.isPng) {
          continue;
        }
        pictures.add(
          PptxPlacedPicture(
            xPt: image.x,
            yPt: image.y,
            wPt: image.width,
            hPt: image.height,
            pngBytes: bytes,
          ),
        );
      }
      deck.addPlacedSlide(
        texts: texts,
        pictures: pictures,
        charts: <PptxPlacedChart>[
          for (final PdfOfficeChart chart in page.charts)
            PptxPlacedChart(
              xPt: chart.x,
              yPt: chart.y,
              wPt: chart.width,
              hPt: chart.height,
              title: chart.title,
              kind: switch (chart.kind) {
                PdfOfficeChartKind.column => PptxPlacedChartKind.column,
                PdfOfficeChartKind.bar => PptxPlacedChartKind.bar,
                PdfOfficeChartKind.pie => PptxPlacedChartKind.pie,
                PdfOfficeChartKind.line => PptxPlacedChartKind.line,
              },
              points: <ChartPoint>[
                for (final PdfOfficeChartPoint point in chart.points)
                  ChartPoint(
                    label: point.label,
                    value: point.value,
                    color: point.color,
                  ),
              ],
            ),
        ],
      );
    }
    return deck.build();
  }

  static PdfOfficeRecovery _open(Uint8List bytes, String? password) {
    return recover(PdfFile.open(bytes, password: password));
  }

  static bool _rtl(PdfOfficeRecovery recovery) {
    var rtlPages = 0;
    var other = 0;
    for (final PdfOfficePage page in recovery.pages) {
      if (page.rtl) {
        rtlPages += 1;
      } else if (page.lines.isNotEmpty || _pageTableText(page)) {
        other += 1;
      }
    }
    return rtlPages > other;
  }

  static const WmlPageMargins _pageMargins = WmlPageMargins(
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    header: 0,
    footer: 0,
  );

  static PdfOfficePage _emptyPage() {
    return const PdfOfficePage(
      index: 0,
      width: 595.28,
      height: 841.89,
      lines: <PdfOfficeLine>[],
      tables: <PdfOfficeTable>[],
      images: <PdfOfficeImage>[],
    );
  }

  static WmlSection _tocSection(PdfOfficeRecovery recovery) {
    final PdfOfficePage? first = recovery.pages.isEmpty
        ? null
        : recovery.pages.first;
    return WmlSection(
      pageSize: WmlPageSize(
        width: first == null || first.width < 36 ? 595.28 : first.width,
        height: first == null || first.height < 36 ? 841.89 : first.height,
      ),
      margins: const WmlPageMargins(),
      blocks: <WmlBlock>[_tocBlock(recovery.toc)],
    );
  }

  static WmlToc _tocBlock(List<PdfOfficeTocEntry> entries) {
    final bool arabic = entries.any(
      (PdfOfficeTocEntry entry) => pdfOfficeIsRtl(entry.title),
    );
    var maxLevel = 1;
    for (final PdfOfficeTocEntry entry in entries) {
      if (entry.level > maxLevel) {
        maxLevel = entry.level;
      }
    }
    return WmlToc(
      title: arabic ? 'المحتويات' : 'Contents',
      minLevel: 1,
      maxLevel: maxLevel.clamp(1, 9),
      entries: <WmlTocEntry>[
        for (final PdfOfficeTocEntry entry in entries)
          WmlTocEntry(
            text: entry.title,
            level: entry.level.clamp(1, 9),
            headingParagraphIndex: 0,
            pageNumber: entry.pageNumber < 1 ? 1 : entry.pageNumber,
          ),
      ],
    );
  }

  static WmlSection _docxSection(PdfOfficePage page) {
    final List<PdfOfficeLine> tocLines = _printedToc(page.lines);
    final List<WmlBlock> blocks = <WmlBlock>[
      for (final PdfOfficeImage image in page.images)
        if (image.bytes != null) _picture(image),
      for (final PdfOfficeChart chart in page.charts) _chart(chart),
      for (final PdfOfficeTable table in page.tables) _tableFrame(table),
      if (tocLines.length >= 3) _printedTocFrame(tocLines),
      for (final List<PdfOfficeLine> group in _clusters(page.lines, tocLines))
        _clusterFrame(group),
    ];
    _bookmarkFirst(blocks, page.index + 1);
    if (blocks.isEmpty) {
      blocks.add(
        _textFrame(
          x: 36,
          y: 36,
          width: page.width > 80 ? page.width - 72 : page.width,
          height: 48,
          text: pdfOfficeNoTextMessage,
          fontSize: 12,
        ),
      );
    }
    return WmlSection(
      pageSize: WmlPageSize(
        width: page.width < 36 ? 36 : page.width,
        height: page.height < 36 ? 36 : page.height,
      ),
      margins: _pageMargins,
      breakKind: WmlSectionBreakKind.nextPage,
      blocks: blocks,
    );
  }

  static WmlVisual _picture(PdfOfficeImage image) {
    return WmlVisual(
      visual: OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: image.isPng ? 'image.png' : 'image.jpg',
        imageBytes: image.bytes,
        width: image.width < 1 ? 1 : image.width,
        height: image.height < 1 ? 1 : image.height,
        offsetX: image.x,
        offsetY: image.y,
        picture: PictureAdjust(
          wrap: PictureWrap.inFront,
          lockAspect: false,
          wrapDistT: 0,
          wrapDistB: 0,
          wrapDistL: 0,
          wrapDistR: 0,
        ),
      ),
    );
  }

  static final RegExp _tocPattern = RegExp(
    r'^(.+?)(?:\s*[.\u00B7\u2026]{2,}\s*|\s{3,})(\d{1,4})\s*$',
  );

  static List<PdfOfficeLine> _printedToc(List<PdfOfficeLine> lines) {
    return <PdfOfficeLine>[
      for (final PdfOfficeLine line in lines)
        if (_tocPattern.hasMatch(line.text.trim())) line,
    ];
  }

  static WmlFrame _printedTocFrame(List<PdfOfficeLine> lines) {
    var left = lines.first.x;
    var top = lines.first.y - lines.first.fontSize;
    var right = lines.first.x + lines.first.width;
    var bottom = lines.first.y;
    final List<PdfOfficeTocEntry> entries = <PdfOfficeTocEntry>[];
    for (final PdfOfficeLine line in lines) {
      if (line.x < left) {
        left = line.x;
      }
      final double lineTop = line.y - line.fontSize;
      if (lineTop < top) {
        top = lineTop;
      }
      if (line.x + line.width > right) {
        right = line.x + line.width;
      }
      if (line.y > bottom) {
        bottom = line.y;
      }
      final RegExpMatch? match = _tocPattern.firstMatch(line.text.trim());
      entries.add(
        PdfOfficeTocEntry(
          title: match?.group(1)?.trim() ?? line.text.trim(),
          level: 1,
          pageNumber: int.tryParse(match?.group(2) ?? '') ?? 1,
        ),
      );
    }
    return WmlFrame(
      x: left < 0 ? 0 : left,
      y: top < 0 ? 0 : top,
      width: right - left < 80 ? 80 : right - left,
      height: bottom - top + lines.last.fontSize,
      anchor: WmlFrameAnchor.page,
      blocks: <WmlBlock>[_tocBlock(entries)],
    );
  }

  static List<List<PdfOfficeLine>> _clusters(
    List<PdfOfficeLine> lines,
    List<PdfOfficeLine> skipped,
  ) {
    final List<List<PdfOfficeLine>> groups = <List<PdfOfficeLine>>[];
    for (final PdfOfficeLine line in lines) {
      if (skipped.contains(line) || line.text.trim().isEmpty) {
        continue;
      }
      if (groups.isEmpty || !_joins(groups.last.last, line)) {
        groups.add(<PdfOfficeLine>[line]);
      } else {
        groups.last.add(line);
      }
    }
    return groups;
  }

  static bool _joins(PdfOfficeLine previous, PdfOfficeLine line) {
    if (previous.headingLevel > 0 || line.headingLevel > 0) {
      return false;
    }
    if (previous.listKind != line.listKind) {
      return false;
    }
    if ((previous.fontSize - line.fontSize).abs() > 1.5 ||
        previous.bold != line.bold ||
        previous.italic != line.italic) {
      return false;
    }
    if ((previous.x - line.x).abs() > 14) {
      return false;
    }
    final double gap = line.y - previous.y;
    return gap >= previous.fontSize * 0.6 && gap <= previous.fontSize * 2.2;
  }

  static WmlFrame _clusterFrame(List<PdfOfficeLine> lines) {
    final PdfOfficeLine first = lines.first;
    final double size = first.fontSize < 4 ? 4 : first.fontSize;
    var left = first.x;
    var right = first.x + first.width;
    var top = first.y - size * 0.92;
    var bottom = first.y + size * 0.4;
    for (final PdfOfficeLine line in lines) {
      final double lineSize = line.fontSize < 4 ? 4 : line.fontSize;
      final double pad = lineSize * 0.55;
      final double x = line.rtl ? line.x - pad * 0.35 : line.x;
      if (x < left) {
        left = x;
      }
      if (line.x + line.width + pad > right) {
        right = line.x + line.width + pad;
      }
      final double lineTop = line.y - lineSize * 0.92;
      if (lineTop < top) {
        top = lineTop;
      }
      if (line.y + lineSize * 0.45 > bottom) {
        bottom = line.y + lineSize * 0.45;
      }
    }
    return WmlFrame(
      x: left < 0 ? 0 : left,
      y: top < 0 ? 0 : top,
      width: right - left < size * 2 ? size * 2 : right - left,
      height: bottom - top < size ? size : bottom - top,
      anchor: WmlFrameAnchor.page,
      blocks: <WmlBlock>[
        for (final PdfOfficeLine line in lines) _lineParagraph(line),
      ],
    );
  }

  static WmlParagraph _lineParagraph(PdfOfficeLine line) {
    final int level = line.headingLevel.clamp(0, 9);
    return _paragraph(
      text: _withoutMarker(line),
      fontSize: line.fontSize < 4 ? 4 : line.fontSize,
      bold: line.bold || level > 0,
      italic: line.italic,
      rtl: line.rtl,
      color: _rgb(line.color),
      headingLevel: level == 0 ? null : level,
      listKind: line.listKind,
      link: _hyperlink(line),
    );
  }

  static WmlHyperlink? _hyperlink(PdfOfficeLine line) {
    final String? url = line.linkUrl;
    if (url != null && url.isNotEmpty) {
      return WmlHyperlink(url: url);
    }
    final int? page = line.linkPage;
    if (page != null && page > 0) {
      return WmlHyperlink(anchor: '_PdfP$page');
    }
    return null;
  }

  static String _withoutMarker(PdfOfficeLine line) {
    final String text = line.text.trim();
    if (line.listKind == PdfOfficeListKind.bullet) {
      return text.replaceFirst(RegExp(r'^[•·●◦▪‣\-–—*]\s+'), '');
    }
    if (line.listKind == PdfOfficeListKind.number) {
      return text.replaceFirst(RegExp(r'^(?:\d+|[٠-٩]+)[.)]\s+'), '');
    }
    return line.text;
  }

  static void _bookmarkFirst(List<WmlBlock> blocks, int pageNumber) {
    final WmlParagraph? paragraph = _firstParagraph(blocks);
    if (paragraph != null) {
      paragraph.properties.bookmarkName = '_PdfP$pageNumber';
    }
  }

  static WmlParagraph? _firstParagraph(List<WmlBlock> blocks) {
    for (final WmlBlock block in blocks) {
      switch (block) {
        case WmlParagraph():
          return block;
        case WmlFrame():
          final WmlParagraph? nested = _firstParagraph(block.blocks);
          if (nested != null) {
            return nested;
          }
        case WmlTable():
          for (final WmlTableRow row in block.rows) {
            for (final WmlTableCell cell in row.cells) {
              final WmlParagraph? nested = _firstParagraph(cell.blocks);
              if (nested != null) {
                return nested;
              }
            }
          }
        case WmlToc():
          return block.titleParagraph;
        case WmlVisual():
        case WmlEquation():
          break;
      }
    }
    return null;
  }

  static WmlVisual _chart(PdfOfficeChart chart) {
    return WmlVisual(
      visual: OfficeVisual(
        kind: switch (chart.kind) {
          PdfOfficeChartKind.column => OfficeVisualKind.chartColumn,
          PdfOfficeChartKind.bar => OfficeVisualKind.chartBar,
          PdfOfficeChartKind.pie => OfficeVisualKind.chartPie,
          PdfOfficeChartKind.line => OfficeVisualKind.chartLine,
        },
        title: chart.title,
        width: chart.width < 8 ? 8 : chart.width,
        height: chart.height < 8 ? 8 : chart.height,
        offsetX: chart.x,
        offsetY: chart.y,
        points: <ChartPoint>[
          for (final PdfOfficeChartPoint point in chart.points)
            ChartPoint(
              label: point.label,
              value: point.value,
              color: point.color,
            ),
        ],
        picture: PictureAdjust(
          wrap: PictureWrap.inFront,
          lockAspect: false,
          wrapDistT: 0,
          wrapDistB: 0,
          wrapDistL: 0,
          wrapDistR: 0,
        ),
        chart: ChartDisplay(
          showLegend: chart.kind == PdfOfficeChartKind.pie,
          showTitle: chart.title.isNotEmpty,
        ),
      ),
    );
  }

  static WmlFrame _tableFrame(PdfOfficeTable table) {
    final int cols = table.rows.fold<int>(
      0,
      (int count, List<String> row) => row.length > count ? row.length : count,
    );
    final double colW = cols == 0 ? table.width : table.width / cols;
    final String? header =
        table.headerFill ?? (table.hasHeader ? '1F4E79' : null);
    final bool dark = header != null && _hexLuma(header) < 150;
    return WmlFrame(
      x: table.x,
      y: table.y,
      width: table.width < 8 ? 8 : table.width,
      height: table.height < 8 ? 8 : table.height,
      anchor: WmlFrameAnchor.page,
      blocks: <WmlBlock>[
        WmlTable(
          grid: <double>[for (var c = 0; c < cols; c++) colW],
          properties: WmlTableProps(
            borders: true,
            borderColor: 'BFBFBF',
            rightToLeft: table.rows.any(
              (List<String> row) => row.any(pdfOfficeIsRtl),
            ),
          ),
          rows: <WmlTableRow>[
            for (var r = 0; r < table.rows.length; r++)
              WmlTableRow(
                height: _rowHeight(table),
                cells: <WmlTableCell>[
                  for (var c = 0; c < table.rows[r].length; c++)
                    WmlTableCell(
                      width: colW,
                      fillColor: r == 0 ? header : null,
                      blocks: <WmlBlock>[
                        _paragraph(
                          text: table.rows[r][c],
                          fontSize: _rowHeight(table) < 16 ? 8 : 11,
                          bold: r == 0 && table.hasHeader,
                          rtl: pdfOfficeIsRtl(table.rows[r][c]),
                          color: r == 0 && dark ? 'FFFFFF' : '000000',
                        ),
                      ],
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static double _hexLuma(String hex) {
    final int value = int.tryParse(hex, radix: 16) ?? 0;
    final int r = (value >> 16) & 0xFF;
    final int g = (value >> 8) & 0xFF;
    final int b = value & 0xFF;
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  static WmlFrame _textFrame({
    required double x,
    required double y,
    required double width,
    required double height,
    required String text,
    required double fontSize,
    bool bold = false,
    bool italic = false,
    bool rtl = false,
    String color = '000000',
    String? stroke,
  }) {
    return WmlFrame(
      x: x,
      y: y,
      width: width < 8 ? 8 : width,
      height: height < 8 ? 8 : height,
      anchor: WmlFrameAnchor.page,
      wrap: WmlFrameWrap.none,
      strokeColor: stroke,
      blocks: <WmlBlock>[
        _paragraph(
          text: text,
          fontSize: fontSize,
          bold: bold,
          italic: italic,
          rtl: rtl,
          color: color,
        ),
      ],
    );
  }

  static WmlParagraph _paragraph({
    required String text,
    required double fontSize,
    bool bold = false,
    bool italic = false,
    bool rtl = false,
    String color = '000000',
    int? headingLevel,
    PdfOfficeListKind listKind = PdfOfficeListKind.none,
    WmlHyperlink? link,
  }) {
    return WmlParagraph(
      properties: WmlParagraphProps(
        justification: rtl ? WmlJustification.right : WmlJustification.left,
        rightToLeft: rtl,
        spacingBefore: 0,
        spacingAfter: 0,
        lineSpacing: 1,
        headingLevel: headingLevel,
        styleId: headingLevel == null
            ? null
            : 'Heading${headingLevel.clamp(1, 3)}',
        numId: switch (listKind) {
          PdfOfficeListKind.bullet => 1,
          PdfOfficeListKind.number => 2,
          PdfOfficeListKind.none => null,
        },
      ),
      inlines: <WmlInline>[
        WmlRun(
          text: text,
          hyperlink: link,
          properties: WmlRunProps(
            bold: bold,
            italic: italic,
            color: color,
            fontSizeHalfPoints: (fontSize * 2).round().clamp(8, 288),
            asciiFont: 'Arial',
            csFont: 'Arial',
          ),
        ),
      ],
    );
  }

  static Object _cellValue(String text) {
    final String trimmed = text.trim();
    final int? whole = int.tryParse(trimmed);
    if (whole != null) {
      return whole;
    }
    final double? number = double.tryParse(trimmed);
    if (number != null) {
      return number;
    }
    return text;
  }

  static String _rgb(int argb) {
    return (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  static bool _pageTableText(PdfOfficePage page) {
    for (final PdfOfficeTable table in page.tables) {
      for (final List<String> row in table.rows) {
        for (final String cell in row) {
          if (cell.trim().isNotEmpty) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static double _colLeft(PdfOfficeTable table, int col) {
    final int count = table.rows.isEmpty ? 1 : table.rows.first.length;
    if (count <= 0) {
      return 0;
    }
    return table.width * col / count;
  }

  static double _colWidth(PdfOfficeTable table) {
    final int count = table.rows.isEmpty ? 1 : table.rows.first.length;
    if (count <= 0) {
      return table.width;
    }
    return table.width / count;
  }

  static double _rowTop(PdfOfficeTable table, int row) {
    final int count = table.rows.isEmpty ? 1 : table.rows.length;
    return table.height * row / count;
  }

  static double _rowHeight(PdfOfficeTable table) {
    final int count = table.rows.isEmpty ? 1 : table.rows.length;
    if (count <= 0) {
      return table.height;
    }
    return table.height / count;
  }
}
