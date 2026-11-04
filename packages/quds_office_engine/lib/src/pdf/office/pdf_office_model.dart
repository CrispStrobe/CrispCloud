import 'dart:typed_data';

/// Why a piece of a PDF page was not copied into Office.
enum PdfOfficeNoticeKind {
  /// The page has no text runs. Scanned pixels are not read.
  noExtractableText,

  /// An image is not a JPEG or PNG the Office writers can store.
  imageSkipped,

  /// A rotated text line was written as a horizontal paragraph.
  rotationFlattened,
}

/// One limit hit while reading a PDF page for Office export.
class PdfOfficeNotice {
  /// PdfOfficeNotice API.
  const PdfOfficeNotice({
    required this.kind,
    required this.message,
    this.pageIndex,
  });

  /// kind API.
  final PdfOfficeNoticeKind kind;

  /// message API.
  final String message;

  /// Zero-based page, when the notice is about one page.
  final int? pageIndex;
}

/// One visual line rebuilt from glyphs or from a single text run.
class PdfOfficeLine {
  /// PdfOfficeLine API.
  const PdfOfficeLine({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.fontSize,
    required this.bold,
    required this.italic,
    required this.rtl,
    required this.color,
    this.headingLevel = 0,
    this.linkUrl,
    this.linkPage,
    this.listKind = PdfOfficeListKind.none,
  });

  /// Logical text. An RTL line built from glyphs is already reversed.
  final String text;

  /// 1–9 when this line is a heading. 0 is body text.
  final int headingLevel;

  /// Web address from a link annotation that covers this line.
  final String? linkUrl;

  /// 1-based page targeted by an internal link annotation.
  final int? linkPage;

  /// Bullet or numbered list marker found at the start of [text].
  final PdfOfficeListKind listKind;

  /// Left of the line, top-left page space.
  final double x;

  /// Baseline, top-left page space (y grows downward).
  final double y;

  /// width API.
  final double width;

  /// Font size in points.
  final double fontSize;

  /// bold API.
  final bool bold;

  /// italic API.
  final bool italic;

  /// True when Arabic or Hebrew letters outnumber Latin letters.
  final bool rtl;

  /// ARGB.
  final int color;
}

/// How a recovered line participates in a Word list.
enum PdfOfficeListKind { none, bullet, number }

/// A column, bar, pie, or line chart rebuilt from vector marks.
enum PdfOfficeChartKind { column, bar, pie, line }

/// One category on a [PdfOfficeChart].
class PdfOfficeChartPoint {
  /// PdfOfficeChartPoint API.
  const PdfOfficeChartPoint({
    required this.label,
    required this.value,
    required this.color,
  });

  /// Category label.
  final String label;

  /// Data value. Bar height is used when the page has no numeric axis.
  final double value;

  /// `RRGGBB`.
  final String color;
}

/// A chart whose geometry was a set of bars, wedges, or a polyline.
class PdfOfficeChart {
  /// PdfOfficeChart API.
  const PdfOfficeChart({
    required this.kind,
    required this.title,
    required this.points,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// kind API.
  final PdfOfficeChartKind kind;

  /// Title painted above the plot. Empty when none was found.
  final String title;

  /// points API.
  final List<PdfOfficeChartPoint> points;

  /// Left of the plot, including the title when one was found.
  final double x;

  /// Top of the plot.
  final double y;

  /// width API.
  final double width;

  /// height API.
  final double height;
}

/// One row of a table of contents, from the PDF outline or a dot-leader line.
class PdfOfficeTocEntry {
  /// PdfOfficeTocEntry API.
  const PdfOfficeTocEntry({
    required this.title,
    required this.level,
    required this.pageNumber,
  });

  /// title API.
  final String title;

  /// 1-based outline depth.
  final int level;

  /// 1-based page number.
  final int pageNumber;
}

/// A table whose cells are the rectangles of a ruled grid.
class PdfOfficeTable {
  /// PdfOfficeTable API.
  const PdfOfficeTable({
    required this.rows,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.headerFill,
  });

  /// Cell text, row-major. Empty cells are empty strings.
  final List<List<String>> rows;

  /// Left of the grid.
  final double x;

  /// Top of the grid.
  final double y;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// Fill of the first row, `RRGGBB`, when a rectangle covers that row.
  final String? headerFill;

  /// True when the first row is labels and a later row contains a number.
  bool get hasHeader {
    if (rows.length < 2) {
      return false;
    }
    final bool labels = rows.first.every(
      (String cell) => double.tryParse(cell.trim()) == null,
    );
    final bool numbers = rows
        .skip(1)
        .any(
          (List<String> row) =>
              row.any((String cell) => double.tryParse(cell.trim()) != null),
        );
    return labels && numbers;
  }
}

/// An image on the page. [bytes] is null when it cannot be stored.
class PdfOfficeImage {
  /// PdfOfficeImage API.
  const PdfOfficeImage({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.bytes,
    this.mime,
    this.skipReason,
  });

  /// Left.
  final double x;

  /// Top.
  final double y;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// JPEG or PNG bytes, or null when [skipReason] is set.
  final Uint8List? bytes;

  /// `image/jpeg` or `image/png`.
  final String? mime;

  /// Why [bytes] is null.
  final String? skipReason;

  /// True when [bytes] is a PNG.
  bool get isPng => mime == 'image/png';
}

/// One PDF page after line, table, and image recovery.
class PdfOfficePage {
  /// PdfOfficePage API.
  const PdfOfficePage({
    required this.index,
    required this.width,
    required this.height,
    required this.lines,
    required this.tables,
    required this.images,
    this.charts = const <PdfOfficeChart>[],
  });

  /// Zero-based page index.
  final int index;

  /// Page width in points.
  final double width;

  /// Page height in points.
  final double height;

  /// Lines that are not inside a recovered table, top to bottom.
  final List<PdfOfficeLine> lines;

  /// Ruled tables, top to bottom.
  final List<PdfOfficeTable> tables;

  /// Images in paint order.
  final List<PdfOfficeImage> images;

  /// Vector charts whose marks were not left as loose rectangles.
  final List<PdfOfficeChart> charts;

  /// True when most letters on the page are Arabic or Hebrew.
  bool get rtl {
    var rtl = 0;
    var ltr = 0;
    void count(String text) => _countScripts(text, (int r, int l) {
      rtl += r;
      ltr += l;
    });
    for (final PdfOfficeLine line in lines) {
      count(line.text);
    }
    for (final PdfOfficeTable table in tables) {
      for (final List<String> row in table.rows) {
        for (final String cell in row) {
          count(cell);
        }
      }
    }
    return rtl > ltr && rtl > 0;
  }
}

/// The pages and the limits hit while reading them.
class PdfOfficeRecovery {
  /// PdfOfficeRecovery API.
  const PdfOfficeRecovery({
    required this.pages,
    required this.notices,
    this.toc = const <PdfOfficeTocEntry>[],
  });

  /// pages API.
  final List<PdfOfficePage> pages;

  /// notices API.
  final List<PdfOfficeNotice> notices;

  /// PDF outline, when the file has one.
  final List<PdfOfficeTocEntry> toc;

  /// True when some page yielded a line or a non-empty table cell.
  bool get hasExtractableText {
    for (final PdfOfficePage page in pages) {
      if (page.lines.isNotEmpty || page.charts.isNotEmpty) {
        return true;
      }
      for (final PdfOfficeTable table in page.tables) {
        for (final List<String> row in table.rows) {
          for (final String cell in row) {
            if (cell.trim().isNotEmpty) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }
}

/// Sentence written into an Office file when a page has no text layer.
const String pdfOfficeNoTextMessage =
    'No extractable text on this page. Scanned pages are not read.';

/// True when Arabic or Hebrew letters outnumber Latin letters.
bool pdfOfficeIsRtl(String text) {
  var rtl = 0;
  var ltr = 0;
  _countScripts(text, (int r, int l) {
    rtl += r;
    ltr += l;
  });
  return rtl > ltr && rtl > 0;
}

void _countScripts(String text, void Function(int rtl, int ltr) emit) {
  var rtl = 0;
  var ltr = 0;
  for (final int rune in text.runes) {
    final bool arabic =
        (rune >= 0x0590 && rune <= 0x08FF) ||
        (rune >= 0xFB50 && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF);
    if (arabic) {
      rtl += 1;
    } else if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A)) {
      ltr += 1;
    }
  }
  emit(rtl, ltr);
}
