import 'dart:math' as math;
import 'dart:typed_data';

import '../bidi/arabic_shaping.dart';
import '../bidi/line_breaker.dart';
import '../fonts/font_metrics.dart';
import '../fonts/font_subsetter.dart';
import '../fonts/gpos_mark_to_base.dart';
import '../fonts/office_font_set.dart';
import '../fonts/sfnt_parser.dart';
import '../opc/opc_archive.dart';
import '../opc/repair/office_repair.dart';
import '../sheet/formula/formula_eval.dart';
import '../sheet/model/sml_workbook.dart';
import '../sheet/serial/sheet_serial.dart';
import '../sheet/styles/sml_styles.dart';
import '../slide/model/pml_presentation.dart';
import '../slide/serial/slide_serial.dart';
import '../visual/office_visual.dart';
import '../word/layout/word_layout.dart';
import '../word/math/omml_layout.dart';
import '../word/model/wml_document.dart';
import '../word/model/word_link.dart';
import '../word/model/word_toc.dart';
import '../word/properties/wml_properties.dart';
import '../word/serial/word_deserializer.dart';
import 'file/text/pdf_std14.dart';
import 'office_pdf_visuals.dart';
import 'pdf_canvas.dart';
import 'pdf_document.dart';
import 'pdf_save_options.dart';

/// Print layout for worksheet PDF (Office Print defaults to A4 portrait).
class PdfSheetPrintOptions {
  /// PdfSheetPrintOptions API.
  const PdfSheetPrintOptions({
    this.pageWidth = 595.28,
    this.pageHeight = 841.89,
    this.margin = 36,
    this.showGridlines = true,
    this.showHeadings = true,
    this.fitToPage = false,
  });

  /// a4Portrait API.
  factory PdfSheetPrintOptions.a4Portrait() => const PdfSheetPrintOptions();

  /// a4Landscape API.
  factory PdfSheetPrintOptions.a4Landscape() =>
      const PdfSheetPrintOptions(pageWidth: 841.89, pageHeight: 595.28);

  /// letter API.
  factory PdfSheetPrintOptions.letter() =>
      const PdfSheetPrintOptions(pageWidth: 612, pageHeight: 792);

  /// pageWidth API.
  final double pageWidth;

  /// pageHeight API.
  final double pageHeight;

  /// margin API.
  final double margin;

  /// showGridlines API.
  final bool showGridlines;

  /// showHeadings API.
  final bool showHeadings;

  /// fitToPage API.
  final bool fitToPage;
}

/// How a deck is paginated — matching PowerPoint's print what.
enum PdfSlideExportMode { slides, notesPages }

/// Office-faithful PDF 1.7 export for Word, Excel, and PowerPoint models.
///
/// Word uses the layout engine (pages, tables, headers/footers, visuals).
/// Excel prints each sheet as a paginated grid with evaluated values.
/// PowerPoint emits one landscape page per slide with fills, rotation, and media.
abstract final class OfficePdfExport {
  /// fromBytes API.
  static Uint8List fromBytes(
    Uint8List bytes, {
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSaveOptions saveOptions = const PdfSaveOptions(),
    String title = 'Quds Office',
    String? password,
  }) {
    final OpcPackage package = OfficeRepair.open(bytes, password: password);
    switch (package.kind) {
      case OpcPackageKind.word:
        return word(
          WordDeserializer().read(package),
          font: font,
          fonts: fonts,
          saveOptions: saveOptions,
          title: title,
        );
      case OpcPackageKind.sheet:
        return workbook(
          SheetDeserializer().read(package),
          font: font,
          fonts: fonts,
          saveOptions: saveOptions,
          title: title,
        );
      case OpcPackageKind.slide:
        return presentation(
          SlideDeserializer().read(package),
          font: font,
          fonts: fonts,
          saveOptions: saveOptions,
          title: title,
        );
      case OpcPackageKind.unknown:
        throw FormatException('Unsupported Office package for PDF export');
    }
  }

  /// word API.
  static Uint8List word(
    WmlDocument document, {
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSaveOptions saveOptions = const PdfSaveOptions(),
    String title = 'Quds Office',
    LaidOutDocument? laidOut,
    int pageFrom = 1,
    int? pageTo,
  }) {
    final OfficeFontSet set = fonts ?? OfficeFontSet.single(font);
    final LaidOutDocument laid = _layoutWord(document, set, laidOut);
    final Set<int> cps = <int>{};
    _collectWordCodepoints(laid, cps);
    final _FontPack pack = _FontPack.build(set, cps);
    final PdfDocument pdf = PdfDocument(title: title);
    final _PdfImageBank images = _PdfImageBank();
    final int from = pageFrom.clamp(1, math.max(1, laid.pages.length));
    final int to = (pageTo ?? laid.pages.length).clamp(from, laid.pages.length);
    final Map<int, int> layoutToPdf = <int, int>{};
    var pdfPageIndex = 0;
    for (final LaidOutPage page
        in laid.pages.skip(from - 1).take(to - from + 1)) {
      layoutToPdf[page.index] = pdfPageIndex++;
      final _PageSink sink = _PageSink(page.width, page.height, pack, images);
      sink.canvas.fillRect(0, 0, page.width, page.height, 'FFFFFF');
      for (final LaidOutBox frame in page.frames) {
        _paintFrame(sink, frame);
      }
      for (final LaidOutLine line in page.lines) {
        _paintWordLine(sink, line);
      }
      for (final LaidOutLine line in page.header) {
        _paintWordLine(sink, line);
      }
      for (final LaidOutLine line in page.footer) {
        _paintWordLine(sink, line);
      }
      for (final LaidOutLine line in page.notes) {
        _paintWordLine(sink, line);
      }
      _collectWordLinks(sink, page, laid, document, layoutToPdf);
      sink.finish(pdf);
    }
    _addWordOutlines(pdf, document, laid, layoutToPdf);
    if (pdf.pages.isEmpty) {
      pdf.addPage(
        PdfPage(
          width: 595.28,
          height: 841.89,
          content: PdfCanvas(595.28, 841.89).toStream(),
        ),
      );
    }
    return pdf.save(faces: pack.faces, options: saveOptions);
  }

  /// workbook API.
  static Uint8List workbook(
    SmlWorkbook book, {
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSaveOptions saveOptions = const PdfSaveOptions(),
    String title = 'Quds Office',
    PdfSheetPrintOptions options = const PdfSheetPrintOptions(),
    int sheetFrom = 1,
    int? sheetTo,
  }) {
    final OfficeFontSet set = fonts ?? OfficeFontSet.single(font);
    final Set<int> cps = <int>{};
    for (final SmlWorksheet sheet in book.sheets) {
      _collectShaped(sheet.name, cps);
      for (final SmlCell cell in sheet.allCells) {
        _collectShaped(_sheetDisplay(book, sheet, cell).text, cps);
      }
      for (final SmlDrawing drawing in sheet.drawings) {
        _collectShaped(drawing.visual.title, cps);
        for (final point in drawing.visual.points) {
          _collectShaped(point.label, cps);
        }
      }
    }
    for (int i = 0; i < 26; i++) {
      cps.add(65 + i);
    }
    for (int i = 0x30; i <= 0x39; i++) {
      cps.add(i);
    }
    for (final SmlWorksheet sheet in book.sheets) {
      var maxCol = 0;
      for (final SmlCell cell in sheet.allCells) {
        if (cell.ref.col > maxCol) {
          maxCol = cell.ref.col;
        }
      }
      for (int c = 0; c <= maxCol; c++) {
        cps.addAll(SmlCellRef(c, 0).a1.replaceAll(RegExp(r'\d+'), '').runes);
      }
    }
    final _FontPack pack = _FontPack.build(set, cps);
    final PdfDocument pdf = PdfDocument(title: title);
    final _PdfImageBank images = _PdfImageBank();
    var printed = 0;
    final int from = sheetFrom.clamp(1, math.max(1, book.sheets.length));
    final int to = (sheetTo ?? book.sheets.length).clamp(
      from,
      book.sheets.length,
    );
    for (int i = from - 1; i < to; i++) {
      final SmlWorksheet sheet = book.sheets[i];
      final int before = pdf.pages.length;
      printed += _printSheet(pdf, book, sheet, pack, options, images);
      if (pdf.pages.length > before) {
        pdf.addOutline(PdfOutlineItem(title: sheet.name, pageIndex: before));
      }
    }
    if (printed == 0) {
      pdf.addPage(
        PdfPage(
          width: options.pageWidth,
          height: options.pageHeight,
          content: PdfCanvas(options.pageWidth, options.pageHeight).toStream(),
        ),
      );
    }
    return pdf.save(faces: pack.faces, options: saveOptions);
  }

  /// One landscape page per slide, or two slides stacked on one A4 page.
  static Uint8List presentation(
    PmlPresentation deck, {
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSaveOptions saveOptions = const PdfSaveOptions(),
    String title = 'Quds Office',
    PdfSlideExportMode mode = PdfSlideExportMode.slides,
    int slidesPerPage = 1,
    int slideFrom = 1,
    int? slideTo,
  }) {
    final OfficeFontSet set = fonts ?? OfficeFontSet.single(font);
    final double slideW = deck.slideWidth / 12700;
    final double slideH = deck.slideHeight / 12700;
    final bool notes = mode == PdfSlideExportMode.notesPages;
    if (slidesPerPage != 1 && slidesPerPage != 2) {
      throw ArgumentError('slides per page is 1 or 2, not an N-up sheet');
    }
    final bool pair = slidesPerPage == 2;
    final double pageW = notes || pair ? 595.28 : slideW;
    final double pageH = notes || pair ? 841.89 : slideH;
    final Set<int> cps = <int>{};
    for (final PmlSlide slide in deck.slides) {
      _collectShaped(slide.notes, cps);
      for (final PmlShape shape in slide.shapes) {
        _collectShaped(deck.resolveText(shape, slide), cps);
        if (shape.visual != null) {
          _collectShaped(shape.visual!.title, cps);
          for (final point in shape.visual!.points) {
            _collectShaped(point.label, cps);
          }
        }
      }
    }
    for (final PmlShape shape in deck.master.shapes) {
      _collectShaped(shape.text, cps);
    }
    final _FontPack pack = _FontPack.build(set, cps);
    final PdfDocument pdf = PdfDocument(title: title);
    final _PdfImageBank images = _PdfImageBank();
    final int from = slideFrom.clamp(1, math.max(1, deck.slides.length));
    final int to = (slideTo ?? deck.slides.length).clamp(
      from,
      deck.slides.length,
    );
    if (pair) {
      return _twoSlidesPerPage(
        deck: deck,
        pdf: pdf,
        pack: pack,
        images: images,
        pageW: pageW,
        pageH: pageH,
        slideW: slideW,
        slideH: slideH,
        from: from,
        to: to,
        faces: pack.faces,
        saveOptions: saveOptions,
      );
    }
    for (int i = from - 1; i < to; i++) {
      final PmlSlide slide = deck.slides[i];
      final _PageSink sink = _PageSink(pageW, pageH, pack, images);
      sink.canvas.fillRect(0, 0, pageW, pageH, 'FFFFFF');
      final double ox = notes ? 36 : 0;
      final double oy = notes ? 36 : 0;
      final double scale = notes
          ? math.min((pageW - 72) / slideW, 420 / slideH)
          : 1;
      sink.canvas.save();
      if (notes) {
        sink.canvas.clipRect(ox, oy, slideW * scale, slideH * scale);
        sink.canvas.translateScale(ox, oy, scale);
      }
      sink.canvas.fillRect(
        0,
        0,
        slideW,
        slideH,
        deck.master.background.isEmpty ? 'FFFFFF' : deck.master.background,
      );
      for (final PmlShape shape in deck.master.shapes) {
        _paintShape(sink, deck, slide, shape);
      }
      for (final PmlShape shape in slide.shapes) {
        _paintShape(sink, deck, slide, shape);
      }
      sink.canvas.restore();
      void linkShapes(Iterable<PmlShape> shapes, {required bool scaled}) {
        for (final PmlShape shape in shapes) {
          if (shape.hyperlinkUrl.isEmpty) {
            continue;
          }
          final double x = shape.transform.xPoints;
          final double y = shape.transform.yPoints;
          final double w = shape.transform.widthPoints;
          final double h = shape.transform.heightPoints;
          if (scaled) {
            sink.links.add(
              PdfLinkAnnot(
                x: ox + x * scale,
                y: oy + y * scale,
                width: w * scale,
                height: h * scale,
                uri: shape.hyperlinkUrl,
              ),
            );
          } else {
            sink.links.add(
              PdfLinkAnnot(
                x: x,
                y: y,
                width: w,
                height: h,
                uri: shape.hyperlinkUrl,
              ),
            );
          }
        }
      }

      linkShapes(deck.master.shapes, scaled: notes);
      linkShapes(slide.shapes, scaled: notes);
      if (notes) {
        sink.drawText(
          '${i + 1} / ${deck.slides.length}',
          36,
          36 + slideH * scale + 18,
          9,
          '595959',
        );
        if (slide.notes.isNotEmpty) {
          _wrapShapeText(
            sink,
            slide.notes,
            36,
            36 + slideH * scale + 36,
            pageW - 72,
            11,
            '222222',
          );
        }
      }
      final String outlineTitle = _slideOutlineTitle(deck, slide, i);
      pdf.addOutline(
        PdfOutlineItem(title: outlineTitle, pageIndex: pdf.pages.length),
      );
      sink.finish(pdf);
    }
    if (pdf.pages.isEmpty) {
      pdf.addPage(
        PdfPage(
          width: pageW,
          height: pageH,
          content: PdfCanvas(pageW, pageH).toStream(),
        ),
      );
    }
    return pdf.save(faces: pack.faces, options: saveOptions);
  }

  /// Two slides stacked on one A4 page. Not a MediaBox swap and not booklet imposition.
  static Uint8List _twoSlidesPerPage({
    required PmlPresentation deck,
    required PdfDocument pdf,
    required _FontPack pack,
    required _PdfImageBank images,
    required double pageW,
    required double pageH,
    required double slideW,
    required double slideH,
    required int from,
    required int to,
    required List<PdfEmbeddedFace> faces,
    required PdfSaveOptions saveOptions,
  }) {
    const double margin = 28;
    const double gap = 22;
    const double caption = 14;
    final double bandH = (pageH - margin * 2 - gap - caption * 2) / 2;
    final double bandW = pageW - margin * 2;
    for (int i = from - 1; i < to; i += 2) {
      final _PageSink sink = _PageSink(pageW, pageH, pack, images);
      sink.canvas.fillRect(0, 0, pageW, pageH, 'FFFFFF');
      final int count = i + 1 < to ? 2 : 1;
      for (int slot = 0; slot < count; slot++) {
        final int index = i + slot;
        final PmlSlide slide = deck.slides[index];
        final double scale = math.min(bandW / slideW, bandH / slideH);
        final double drawnW = slideW * scale;
        final double drawnH = slideH * scale;
        final double ox = margin + (bandW - drawnW) / 2;
        final double oy = margin + slot * (bandH + caption + gap);
        sink.canvas.save();
        sink.canvas.clipRect(ox, oy, drawnW, drawnH);
        sink.canvas.translateScale(ox, oy, scale);
        sink.canvas.fillRect(
          0,
          0,
          slideW,
          slideH,
          deck.master.background.isEmpty ? 'FFFFFF' : deck.master.background,
        );
        for (final PmlShape shape in deck.master.shapes) {
          _paintShape(sink, deck, slide, shape);
        }
        for (final PmlShape shape in slide.shapes) {
          _paintShape(sink, deck, slide, shape);
        }
        sink.canvas.restore();
        void linkShapes(Iterable<PmlShape> shapes) {
          for (final PmlShape shape in shapes) {
            if (shape.hyperlinkUrl.isEmpty) {
              continue;
            }
            sink.links.add(
              PdfLinkAnnot(
                x: ox + shape.transform.xPoints * scale,
                y: oy + shape.transform.yPoints * scale,
                width: shape.transform.widthPoints * scale,
                height: shape.transform.heightPoints * scale,
                uri: shape.hyperlinkUrl,
              ),
            );
          }
        }

        linkShapes(deck.master.shapes);
        linkShapes(slide.shapes);
        sink.drawText(
          '${index + 1} / ${deck.slides.length}',
          ox,
          oy + drawnH + 3,
          8,
          '595959',
        );
        pdf.addOutline(
          PdfOutlineItem(
            title: _slideOutlineTitle(deck, slide, index),
            pageIndex: pdf.pages.length,
          ),
        );
      }
      if (count == 2) {
        final double ruleY = margin + bandH + caption + gap / 2;
        sink.canvas.strokeRect(margin, ruleY, bandW, 0.6, 'E2E8F0');
      }
      sink.finish(pdf);
    }
    if (pdf.pages.isEmpty) {
      pdf.addPage(
        PdfPage(
          width: pageW,
          height: pageH,
          content: PdfCanvas(pageW, pageH).toStream(),
        ),
      );
    }
    return pdf.save(faces: faces, options: saveOptions);
  }

  static LaidOutDocument _layoutWord(
    WmlDocument document,
    OfficeFontSet set,
    LaidOutDocument? laidOut,
  ) {
    WordLink.ensureHeadingBookmarks(document);
    WordToc.refreshEmpty(document);
    WordToc.rebindHeadings(document);
    final WordLayoutEngine engine = WordLayoutEngine(
      font:
          set.primary ?? (set.embeddable.isEmpty ? null : set.embeddable.first),
      fonts: set.isEmpty ? null : set,
    );
    LaidOutDocument laid = laidOut ?? engine.layout(document);
    if (WordToc.syncPageNumbers(document, laid)) {
      laid = engine.layout(document);
    }
    return laid;
  }

  static ({int page, double y})? _pageOfParagraph(
    LaidOutDocument laid,
    int paragraphIndex,
  ) {
    for (final LaidOutPage page in laid.pages) {
      for (final LaidOutLine line in page.lines) {
        if (line.paragraphIndex == paragraphIndex) {
          return (page: page.index, y: line.y);
        }
      }
    }
    return null;
  }

  static void _collectWordLinks(
    _PageSink sink,
    LaidOutPage page,
    LaidOutDocument laid,
    WmlDocument document,
    Map<int, int> layoutToPdf,
  ) {
    for (final LaidOutBox box in page.frames) {
      if (box.kind != LaidOutBoxKind.tocEntry || box.paragraphIndex == null) {
        continue;
      }
      final ({int page, double y})? dest = _pageOfParagraph(
        laid,
        box.paragraphIndex!,
      );
      if (dest == null) {
        continue;
      }
      final int? pdfPage = layoutToPdf[dest.page];
      if (pdfPage == null) {
        continue;
      }
      sink.links.add(
        PdfLinkAnnot(
          x: box.x,
          y: box.y,
          width: box.width,
          height: math.max(10, box.height),
          destPage: pdfPage,
          destY: dest.y,
        ),
      );
    }
    void walk(LaidOutLine line) {
      if (line.tocTargetParagraph != null) {
        return;
      }
      _addGlyphLinks(sink, line, laid, document, layoutToPdf);
    }

    for (final LaidOutLine line in page.lines) {
      walk(line);
    }
    for (final LaidOutLine line in page.header) {
      walk(line);
    }
    for (final LaidOutLine line in page.footer) {
      walk(line);
    }
    for (final LaidOutLine line in page.notes) {
      walk(line);
    }
  }

  static void _addWordOutlines(
    PdfDocument pdf,
    WmlDocument document,
    LaidOutDocument laid,
    Map<int, int> layoutToPdf,
  ) {
    final List<WmlParagraph> paras = document.paragraphs.toList();
    for (int i = 0; i < paras.length; i++) {
      final WmlParagraph para = paras[i];
      final int? level = para.properties.headingLevel;
      if (level == null || level < 1) {
        continue;
      }
      final String title = para.text.trim();
      if (title.isEmpty) {
        continue;
      }
      final ({int page, double y})? dest = _pageOfParagraph(laid, i);
      if (dest == null) {
        continue;
      }
      final int? pdfPage = layoutToPdf[dest.page];
      if (pdfPage == null) {
        continue;
      }
      pdf.addOutline(
        PdfOutlineItem(
          title: title.length > 120 ? '${title.substring(0, 120)}…' : title,
          pageIndex: pdfPage,
          destY: dest.y,
        ),
      );
    }
  }

  static String _slideOutlineTitle(
    PmlPresentation deck,
    PmlSlide slide,
    int index,
  ) {
    for (final PmlShape shape in slide.shapes) {
      final String text = deck.resolveText(shape, slide).trim();
      if (text.isNotEmpty) {
        return text.length > 80 ? '${text.substring(0, 80)}…' : text;
      }
    }
    return 'Slide ${index + 1}';
  }

  static void _addGlyphLinks(
    _PageSink sink,
    LaidOutLine line,
    LaidOutDocument laid,
    WmlDocument document,
    Map<int, int> layoutToPdf,
  ) {
    WmlHyperlink? current;
    var x0 = 0.0;
    var y0 = 0.0;
    var x1 = 0.0;
    var y1 = 0.0;
    void flush() {
      if (current == null) {
        return;
      }
      sink.addResolvedLink(
        x0,
        y0,
        math.max(8, x1 - x0),
        math.max(8, y1 - y0),
        current!,
        laid,
        document,
        layoutToPdf,
      );
      current = null;
    }

    for (final LaidOutGlyph glyph in line.glyphs) {
      final WmlHyperlink? link = glyph.hyperlink;
      if (link == null || link.displayTarget.isEmpty) {
        flush();
        continue;
      }
      final double top = glyph.y - glyph.fontSize;
      final double bottom = glyph.y + glyph.fontSize * 0.3;
      if (current != null && current!.displayTarget == link.displayTarget) {
        x1 = math.max(x1, glyph.x + glyph.advance);
        y0 = math.min(y0, top);
        y1 = math.max(y1, bottom);
        continue;
      }
      flush();
      current = link;
      x0 = glyph.x;
      x1 = glyph.x + glyph.advance;
      y0 = top;
      y1 = bottom;
    }
    flush();
  }

  static void _collectWordCodepoints(LaidOutDocument laid, Set<int> cps) {
    void line(LaidOutLine item) {
      if (item.overlayText != null) {
        _collectShaped(item.overlayText!, cps);
      }
      if (item.listLabel != null) {
        _collectShaped(item.listLabel!, cps);
      }
      for (final LaidOutGlyph g in item.glyphs) {
        cps.add(g.glyph.codePoint);
        final int? nominal = ArabicShaper.nominalOf(g.glyph.codePoint);
        if (nominal != null) {
          cps.add(nominal);
        }
      }
    }

    for (final LaidOutPage page in laid.pages) {
      for (final LaidOutLine item in page.lines) {
        line(item);
      }
      for (final LaidOutLine item in page.header) {
        line(item);
      }
      for (final LaidOutLine item in page.footer) {
        line(item);
      }
      for (final LaidOutLine item in page.notes) {
        line(item);
      }
      for (final LaidOutBox frame in page.frames) {
        final OfficeVisual? visual = frame.visual;
        if (visual != null) {
          _collectShaped(visual.title, cps);
          for (final point in visual.points) {
            _collectShaped(point.label, cps);
          }
        }
        final LaidOutOmml? omml = frame.omml;
        if (omml != null) {
          for (final LaidOutOmmlItem item in omml.items) {
            if (item is LaidOutOmmlText) {
              _collectShaped(item.text, cps);
            }
          }
        }
      }
    }
  }

  static void _paintFrame(_PageSink sink, LaidOutBox frame) {
    if (frame.kind == LaidOutBoxKind.tocEntry) {
      return;
    }
    if (frame.fillColor != null && frame.fillColor!.isNotEmpty) {
      sink.canvas.fillRect(
        frame.x,
        frame.y,
        frame.width,
        frame.height,
        frame.fillColor!,
      );
    }
    if (frame.strokeColor.isNotEmpty && frame.strokeColor != '00000000') {
      final bool edges =
          frame.kind == LaidOutBoxKind.tableCell &&
          !(frame.strokeTop &&
              frame.strokeRight &&
              frame.strokeBottom &&
              frame.strokeLeft);
      if (edges || frame.kind == LaidOutBoxKind.tableCell) {
        sink.canvas.setStrokeColor(frame.strokeColor);
        sink.canvas.setLineWidth(frame.strokeWidth.clamp(0.25, 2.0));
        if (frame.strokeTop) {
          sink.canvas.moveTo(frame.x, frame.y);
          sink.canvas.lineTo(frame.x + frame.width, frame.y);
          sink.canvas.stroke();
        }
        if (frame.strokeBottom) {
          sink.canvas.moveTo(frame.x, frame.y + frame.height);
          sink.canvas.lineTo(frame.x + frame.width, frame.y + frame.height);
          sink.canvas.stroke();
        }
        if (frame.strokeLeft) {
          sink.canvas.moveTo(frame.x, frame.y);
          sink.canvas.lineTo(frame.x, frame.y + frame.height);
          sink.canvas.stroke();
        }
        if (frame.strokeRight) {
          sink.canvas.moveTo(frame.x + frame.width, frame.y);
          sink.canvas.lineTo(frame.x + frame.width, frame.y + frame.height);
          sink.canvas.stroke();
        }
      } else {
        sink.canvas.strokeRect(
          frame.x,
          frame.y,
          frame.width,
          frame.height,
          frame.strokeColor,
        );
      }
    }
    final LaidOutOmml? omml = frame.omml;
    if (omml != null) {
      _paintOmml(sink, frame.x, frame.y, omml);
      return;
    }
    final OfficeVisual? visual = frame.visual;
    if (visual == null) {
      return;
    }
    OfficePdfVisuals.paint(
      sink.canvas,
      frame.x,
      frame.y,
      frame.width,
      frame.height,
      visual,
      sink.images,
      drawText: sink.drawText,
      nextImageName: sink.nextImageName,
    );
  }

  static void _paintOmml(
    _PageSink sink,
    double originX,
    double originY,
    LaidOutOmml omml,
  ) {
    for (final LaidOutOmmlItem item in omml.items) {
      final double x = originX + item.x;
      final double y = originY + item.y;
      switch (item) {
        case LaidOutOmmlText():
          sink.drawText(
            item.text,
            x,
            y + item.fontSize * 0.85,
            item.fontSize,
            '1F4E79',
          );
        case LaidOutOmmlRule():
          sink.canvas.setStrokeColor('1F4E79');
          sink.canvas.setLineWidth(item.height);
          sink.canvas.moveTo(x, y);
          sink.canvas.lineTo(x + item.width, y);
          sink.canvas.stroke();
        case LaidOutOmmlStroke():
          _paintOmmlStroke(sink.canvas, x, y, item);
        case LaidOutOmmlSlot():
          if (item.empty) {
            sink.canvas.setStrokeColor('B4C7E7');
            sink.canvas.setDash(<double>[2, 2]);
            sink.canvas.strokeRect(x, y, item.width, item.height, 'B4C7E7');
            sink.canvas.resetDash();
          }
      }
    }
  }

  static void _paintOmmlStroke(
    PdfCanvas canvas,
    double x,
    double y,
    LaidOutOmmlStroke item,
  ) {
    canvas.setStrokeColor('1F4E79');
    canvas.setLineWidth(1.1);
    switch (item.kind) {
      case OmmlStrokeKind.radical:
        canvas.moveTo(x, y + item.height * 0.55);
        canvas.lineTo(x + item.width * 0.12, y + item.height);
        canvas.lineTo(x + item.width * 0.22, y);
        canvas.lineTo(x + item.width, y);
        canvas.stroke();
      case OmmlStrokeKind.parenLeft:
      case OmmlStrokeKind.braceLeft:
        canvas.moveTo(x + item.width, y);
        canvas.curveTo(
          x,
          y + item.height * 0.2,
          x,
          y + item.height * 0.8,
          x + item.width,
          y + item.height,
        );
        canvas.stroke();
      case OmmlStrokeKind.parenRight:
      case OmmlStrokeKind.braceRight:
        canvas.moveTo(x, y);
        canvas.curveTo(
          x + item.width,
          y + item.height * 0.2,
          x + item.width,
          y + item.height * 0.8,
          x,
          y + item.height,
        );
        canvas.stroke();
    }
  }

  static void _paintWordLine(_PageSink sink, LaidOutLine line) {
    if (line.listLabel != null && line.isParagraphStart) {
      final double markerX = line.listMarkerX != 0
          ? line.listMarkerX
          : line.x - 14;
      final double baseline = line.glyphs.isNotEmpty
          ? line.glyphs.first.y
          : line.y + line.height * 0.78;
      final double size = line.glyphs.isNotEmpty
          ? line.glyphs.first.fontSize
          : 10;
      sink.drawText(line.listLabel!.trim(), markerX, baseline, size, '000000');
    }
    if (line.overlayText != null &&
        line.overlayText!.isNotEmpty &&
        line.glyphs.isEmpty) {
      sink.drawText(line.overlayText!, line.x, line.y + 11, 10, '333333');
      return;
    }
    for (final LaidOutGlyph g in line.glyphs) {
      if (g.highlight != null && g.highlight!.isNotEmpty) {
        sink.canvas.fillRect(
          g.x,
          g.y - g.fontSize * 0.85,
          g.advance,
          g.fontSize * 1.05,
          g.highlight!,
        );
      }
    }
    for (final LaidOutGlyph g in line.glyphs) {
      sink.drawGlyph(g);
      _paintGlyphChrome(sink, g);
    }
    if (line.overlayText != null &&
        line.overlayText!.isNotEmpty &&
        line.glyphs.isNotEmpty) {
      final double pageNumW = _estimateTextWidth(sink, line.overlayText!, 10);
      final double pageNumX = WordToc.pageNumberX(
        pageWidth: sink.width,
        marginRight: 72,
        numberWidth: pageNumW,
      );
      if (line.tocLeader) {
        final double titleEnd = line.glyphs.isEmpty
            ? line.x + line.width
            : line.glyphs.last.x + line.glyphs.last.advance;
        _paintTocLeader(
          sink,
          titleEnd + 4,
          WordToc.leaderEndX(
            pageWidth: sink.width,
            marginRight: 72,
            numberWidth: pageNumW,
          ),
          line.y + 11,
        );
      }
      final double x = line.tocLeader ? pageNumX : line.x + line.width + 8;
      sink.drawText(line.overlayText!, x, line.y + 11, 10, '333333');
    }
  }

  static double _estimateTextWidth(_PageSink sink, String text, double size) {
    final SfntFont? font = sink.pack.layoutFont;
    if (font != null) {
      return FontMetrics(font: font, fontSizePoints: size).measureText(text);
    }
    return text.length * size * 0.5;
  }

  static void _paintTocLeader(
    _PageSink sink,
    double fromX,
    double toX,
    double y,
  ) {
    if (toX - fromX < 8) {
      return;
    }
    sink.canvas.setStrokeColor('999999');
    sink.canvas.setLineWidth(0.6);
    sink.canvas.setDash(<double>[0.8, 2.2]);
    sink.canvas.moveTo(fromX, y);
    sink.canvas.lineTo(toX, y);
    sink.canvas.stroke();
    sink.canvas.resetDash();
  }

  static void _paintGlyphChrome(_PageSink sink, LaidOutGlyph g) {
    if (g.strike) {
      sink.canvas.setStrokeColor(g.color);
      sink.canvas.setLineWidth(0.7);
      final double mid = g.y - g.fontSize * 0.35;
      sink.canvas.moveTo(g.x, mid);
      sink.canvas.lineTo(g.x + g.advance, mid);
      sink.canvas.stroke();
    }
    if (g.underline == WmlUnderline.none) {
      return;
    }
    sink.canvas.setStrokeColor(g.color);
    sink.canvas.setLineWidth(g.underline == WmlUnderline.double ? 1.1 : 0.7);
    switch (g.underline) {
      case WmlUnderline.dotted:
        sink.canvas.setDash(<double>[1.1, 1.1]);
        sink.canvas.moveTo(g.x, g.y + 1.2);
        sink.canvas.lineTo(g.x + g.advance, g.y + 1.2);
        sink.canvas.stroke();
        sink.canvas.resetDash();
      case WmlUnderline.wavy:
        var wx = g.x;
        final double base = g.y + 1.4;
        sink.canvas.moveTo(wx, base);
        while (wx < g.x + g.advance) {
          final double nx = math.min(wx + 2.4, g.x + g.advance);
          sink.canvas.curveTo(
            wx + 0.8,
            base - 1.1,
            wx + 1.6,
            base + 1.1,
            nx,
            base,
          );
          wx = nx;
        }
        sink.canvas.stroke();
      case WmlUnderline.double:
        sink.canvas.setLineWidth(0.7);
        sink.canvas.moveTo(g.x, g.y + 1.1);
        sink.canvas.lineTo(g.x + g.advance, g.y + 1.1);
        sink.canvas.stroke();
        sink.canvas.moveTo(g.x, g.y + 3.4);
        sink.canvas.lineTo(g.x + g.advance, g.y + 3.4);
        sink.canvas.stroke();
      case WmlUnderline.single:
        sink.canvas.moveTo(g.x, g.y + 1.2);
        sink.canvas.lineTo(g.x + g.advance, g.y + 1.2);
        sink.canvas.stroke();
      case WmlUnderline.none:
        break;
    }
  }

  /// Sheet CSS-pixel sizes → PDF points (96 CSS dpi).
  static double _sheetPxToPt(double px) => px * 72 / 96;

  static int _printSheet(
    PdfDocument pdf,
    SmlWorkbook book,
    SmlWorksheet sheet,
    _FontPack pack,
    PdfSheetPrintOptions options,
    _PdfImageBank images,
  ) {
    final double pageW = options.pageWidth;
    final double pageH = options.pageHeight;
    final double margin = options.margin;
    final double gutter = options.showHeadings ? 28 : 0;
    final double band = 18;

    var minCol = 0;
    var maxCol = 0;
    var minRow = 0;
    var maxRow = 0;
    var any = false;
    final SmlRange? area = sheet.printArea;
    if (area != null) {
      minCol = area.minCol;
      maxCol = area.maxCol;
      minRow = area.minRow;
      maxRow = area.maxRow;
      any = true;
    } else {
      for (final SmlCell cell in sheet.allCells) {
        if ((cell.value == null || cell.asString.isEmpty) &&
            (cell.formula == null || cell.formula!.isEmpty)) {
          continue;
        }
        if (!any) {
          minCol = maxCol = cell.ref.col;
          minRow = maxRow = cell.ref.row;
          any = true;
        } else {
          minCol = math.min(minCol, cell.ref.col);
          maxCol = math.max(maxCol, cell.ref.col);
          minRow = math.min(minRow, cell.ref.row);
          maxRow = math.max(maxRow, cell.ref.row);
        }
      }
      for (final SmlDrawing drawing in sheet.drawings) {
        if (!any) {
          minCol = maxCol = drawing.col;
          minRow = maxRow = drawing.row;
          any = true;
        }
        maxCol = math.max(maxCol, drawing.col + 4);
        maxRow = math.max(maxRow, drawing.row + 8);
        minCol = math.min(minCol, drawing.col);
        minRow = math.min(minRow, drawing.row);
      }
      for (final SmlMerge merge in sheet.merges) {
        if (!any) {
          minCol = merge.c0;
          maxCol = merge.c1;
          minRow = merge.r0;
          maxRow = merge.r1;
          any = true;
        } else {
          minCol = math.min(minCol, merge.c0);
          maxCol = math.max(maxCol, merge.c1);
          minRow = math.min(minRow, merge.r0);
          maxRow = math.max(maxRow, merge.r1);
        }
      }
    }
    if (!any) {
      minCol = 0;
      maxCol = 4;
      minRow = 0;
      maxRow = 12;
    }

    final List<double> colPts = <double>[
      for (int c = minCol; c <= maxCol; c++)
        math.max(4, _sheetPxToPt(sheet.columnWidth(c))),
    ];
    final List<double> rowPts = <double>[
      for (int r = minRow; r <= maxRow; r++)
        math.max(4, _sheetPxToPt(sheet.rowHeightAt(r))),
    ];

    final double usableW = pageW - margin * 2 - gutter;
    final double usableH = pageH - margin * 2 - band - 16;
    var scale = 1.0;
    if (options.fitToPage) {
      final double needW = colPts.fold<double>(
        0,
        (double a, double b) => a + b,
      );
      final double needH = rowPts.fold<double>(
        0,
        (double a, double b) => a + b,
      );
      if (needW > 0 && needH > 0) {
        scale = math.min(1, math.min(usableW / needW, usableH / needH));
      }
    }
    for (int i = 0; i < colPts.length; i++) {
      colPts[i] *= scale;
    }
    for (int i = 0; i < rowPts.length; i++) {
      rowPts[i] *= scale;
    }

    final SmlRange? titleRows = sheet.printTitleRows;
    final int titleR0 = titleRows == null
        ? -1
        : titleRows.minRow.clamp(minRow, maxRow);
    final int titleR1 = titleRows == null
        ? -1
        : titleRows.maxRow.clamp(minRow, maxRow);
    final bool hasTitleRows = titleR0 >= 0 && titleR1 >= titleR0;
    var titleRowsHeight = 0.0;
    if (hasTitleRows) {
      for (int r = titleR0; r <= titleR1; r++) {
        titleRowsHeight += rowPts[r - minRow];
      }
    }
    final int dataMinRow = hasTitleRows
        ? math.max(minRow, titleR1 + 1)
        : minRow;
    final List<double> dataRowPts = <double>[
      for (int r = dataMinRow; r <= maxRow; r++) rowPts[r - minRow],
    ];

    final List<({int start, int end})> colBands = _packSheetAxis(
      colPts,
      usableW,
    );
    final double headingReserve = options.showHeadings
        ? math.max(12.0, rowPts.isEmpty ? 16.0 : rowPts.first)
        : 0;
    final List<({int start, int end})> rowBands = _packSheetAxis(
      dataRowPts.isEmpty ? rowPts : dataRowPts,
      usableH - headingReserve - titleRowsHeight,
    );

    var pages = 0;
    var pageNo = 1;
    final int totalGuess = math.max(1, colBands.length * rowBands.length);
    final bool rtl = sheet.rightToLeft;
    final SmlHeaderFooter? hf = sheet.headerFooter;

    for (final ({int start, int end}) rb in rowBands) {
      for (final ({int start, int end}) cb in colBands) {
        final _PageSink sink = _PageSink(pageW, pageH, pack, images);
        sink.canvas.fillRect(0, 0, pageW, pageH, 'FFFFFF');
        void paintHfBand(List<String> sections, double baseline, double size) {
          const List<_TextAlign> slots = <_TextAlign>[
            _TextAlign.left,
            _TextAlign.center,
            _TextAlign.right,
          ];
          for (int i = 0; i < 3; i++) {
            final String text = _expandSheetTokens(
              sections[i],
              sheet.name,
              pageNo,
              totalGuess,
            );
            sink.drawText(
              text,
              margin,
              baseline,
              size,
              '595959',
              maxWidth: pageW - margin * 2,
              align: slots[i],
            );
          }
        }

        if (hf == null ||
            (hf.headerLeft.isEmpty &&
                hf.headerCenter.isEmpty &&
                hf.headerRight.isEmpty)) {
          sink.drawText(
            '${sheet.name}  -  $pageNo / $totalGuess',
            margin,
            margin + 10,
            9,
            '595959',
          );
        } else {
          paintHfBand(
            <String>[hf.headerLeft, hf.headerCenter, hf.headerRight],
            margin + 10,
            9,
          );
        }
        if (hf != null) {
          paintHfBand(
            <String>[hf.footerLeft, hf.footerCenter, hf.footerRight],
            pageH - margin,
            8,
          );
        }
        final double rowGutterX = rtl ? pageW - margin - gutter : margin;
        final double gridLeft = rtl ? margin : margin + gutter;
        final double gridRight = rtl ? pageW - margin - gutter : pageW - margin;
        final double gridY = margin + band;
        final double headingH = options.showHeadings ? 14.0 : 0;

        double colOffset(int local) {
          var sum = 0.0;
          for (int i = cb.start; i < local; i++) {
            sum += colPts[i];
          }
          return sum;
        }

        double colX(int absCol) {
          final int local = absCol - minCol;
          final double w = colPts[local];
          if (!rtl) {
            return gridLeft + colOffset(local) - colOffset(cb.start);
          }
          final double fromBand = colOffset(local) - colOffset(cb.start);
          return gridRight - fromBand - w;
        }

        double colWAt(int absCol) => colPts[absCol - minCol];

        double rowHAt(int absRow) => rowPts[absRow - minRow];

        void paintCellFrame(
          double x,
          double y,
          double spanW,
          double spanH,
          SmlCell? stored,
        ) {
          if (stored != null && stored.fillRgb.isNotEmpty) {
            sink.canvas.fillRect(x, y, spanW, spanH, stored.fillRgb);
          }
          if (stored != null && stored.borderRgb.isNotEmpty) {
            sink.canvas.setLineWidth(
              stored.borderWidth <= 0 ? 0.75 : stored.borderWidth,
            );
            sink.canvas.strokeRect(x, y, spanW, spanH, stored.borderRgb);
          } else if (options.showGridlines) {
            sink.canvas.strokeRect(x, y, spanW, spanH, 'D0D0D0');
          }
        }

        void paintRowRange(int r0, int r1, double originY) {
          var yCursor = originY;
          for (int r = r0; r <= r1; r++) {
            final double h = rowHAt(r);
            if (h <= 0) {
              continue;
            }
            final double y = yCursor;
            yCursor += h;
            if (options.showHeadings) {
              sink.canvas.fillRect(rowGutterX, y, gutter, h, 'F2F2F2');
              if (options.showGridlines) {
                sink.canvas.strokeRect(rowGutterX, y, gutter, h, 'D0D0D0');
              }
              sink.drawText(
                '${r + 1}',
                rowGutterX + 4,
                y + h * 0.75,
                8,
                '595959',
              );
            }
            for (int c = minCol + cb.start; c <= minCol + cb.end; c++) {
              final SmlMerge? merge = sheet.mergeAt(c, r);
              if (merge != null && (merge.c0 != c || merge.r0 != r)) {
                continue;
              }
              var spanW = colWAt(c);
              var spanH = h;
              if (merge != null) {
                spanW = 0;
                for (int mc = merge.c0; mc <= merge.c1; mc++) {
                  if (mc < minCol || mc > maxCol) {
                    continue;
                  }
                  spanW += colPts[mc - minCol];
                }
                spanH = 0;
                for (int mr = merge.r0; mr <= merge.r1; mr++) {
                  if (mr < minRow || mr > maxRow) {
                    continue;
                  }
                  spanH += rowPts[mr - minRow];
                }
              }
              final double x = colX(c);
              final SmlCell? stored = sheet.rows[r]?.cells[c];
              paintCellFrame(x, y, spanW, spanH, stored);
              if (stored == null) {
                continue;
              }
              final ({String text, String color, bool numeric}) shown =
                  _sheetDisplay(book, sheet, stored);
              if (shown.text.isEmpty) {
                continue;
              }
              final double size = math.max(4, stored.fontSize * scale);
              final _TextAlign align = switch (stored.horizontalAlign) {
                SmlHAlign.left => _TextAlign.left,
                SmlHAlign.center => _TextAlign.center,
                SmlHAlign.right => _TextAlign.right,
                SmlHAlign.general =>
                  shown.numeric ? _TextAlign.right : _TextAlign.auto,
              };
              sink.canvas.save();
              sink.canvas.clipRect(x + 1, y + 1, spanW - 2, spanH - 2);
              sink.drawText(
                shown.text,
                x + 3,
                y + spanH - math.max(2, size * 0.28),
                size,
                shown.color,
                maxWidth: spanW - 6,
                align: align,
                bold: stored.fontBold,
              );
              sink.canvas.restore();
            }
          }
        }

        if (options.showHeadings) {
          if (gutter > 0) {
            sink.canvas.fillRect(rowGutterX, gridY, gutter, headingH, 'F2F2F2');
          }
          for (int c = minCol + cb.start; c <= minCol + cb.end; c++) {
            final double x = colX(c);
            final double w = colWAt(c);
            sink.canvas.fillRect(x, gridY, w, headingH, 'F2F2F2');
            if (options.showGridlines) {
              sink.canvas.strokeRect(x, gridY, w, headingH, 'D0D0D0');
            }
            sink.drawText(
              SmlCellRef(c, 0).a1.replaceAll(RegExp(r'\d+'), ''),
              x + 4,
              gridY + headingH * 0.75,
              8,
              '595959',
            );
          }
        }

        var bodyY = gridY + headingH;
        if (hasTitleRows) {
          paintRowRange(titleR0, titleR1, bodyY);
          bodyY += titleRowsHeight;
        }
        final int bandStartAbs = dataRowPts.isEmpty
            ? minRow + rb.start
            : dataMinRow + rb.start;
        final int bandEndAbs = dataRowPts.isEmpty
            ? minRow + rb.end
            : dataMinRow + rb.end;
        paintRowRange(bandStartAbs, bandEndAbs, bodyY);

        for (final SmlDrawing drawing in sheet.drawings) {
          if (drawing.col < minCol + cb.start ||
              drawing.col > minCol + cb.end ||
              drawing.row < bandStartAbs ||
              drawing.row > bandEndAbs) {
            continue;
          }
          var yOff = bodyY;
          for (int r = bandStartAbs; r < drawing.row; r++) {
            yOff += rowHAt(r);
          }
          final double x = colX(drawing.col);
          final double y = yOff;
          final double remainW = math.max(36, pageW - margin - x - 4);
          final double remainH = math.max(36, pageH - margin - y - 4);
          OfficePdfVisuals.paint(
            sink.canvas,
            x,
            y,
            drawing.visual.width.clamp(40, remainW),
            drawing.visual.height.clamp(40, remainH),
            drawing.visual,
            sink.images,
            drawText: sink.drawText,
            nextImageName: sink.nextImageName,
          );
        }
        sink.finish(pdf);
        pages++;
        pageNo++;
      }
    }
    return pages;
  }

  static String _expandSheetTokens(
    String template,
    String sheetName,
    int page,
    int pages,
  ) {
    final StringBuffer out = StringBuffer();
    var i = 0;
    while (i < template.length) {
      final String ch = template[i];
      if (ch != '&' || i + 1 >= template.length) {
        out.write(ch);
        i++;
        continue;
      }
      final String code = template[i + 1];
      i += 2;
      switch (code) {
        case '&':
          out.write('&');
        case 'A':
          out.write(sheetName);
        case 'P':
          out.write('$page');
        case 'N':
          out.write('$pages');
        case 'D':
          final DateTime now = DateTime.now();
          out.write('${now.year}-${_two(now.month)}-${_two(now.day)}');
        case 'T':
          final DateTime now = DateTime.now();
          out.write('${_two(now.hour)}:${_two(now.minute)}');
        case '"':
          final int close = template.indexOf('"', i);
          i = close < 0 ? template.length : close + 1;
        case 'K':
          i = math.min(template.length, i + 6);
        default:
          // Font size digits; B / I / U / S / E / X / Y toggles and the
          // picture, path, and file codes print nothing.
          if (_isDigit(code)) {
            while (i < template.length && _isDigit(template[i])) {
              i++;
            }
          }
      }
    }
    return out.toString().trim();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static bool _isDigit(String ch) {
    final int cu = ch.codeUnitAt(0);
    return cu >= 0x30 && cu <= 0x39;
  }

  /// Packs variable-size axis segments into bands that fit [budget].
  static List<({int start, int end})> _packSheetAxis(
    List<double> sizes,
    double budget,
  ) {
    if (sizes.isEmpty) {
      return <({int start, int end})>[(start: 0, end: 0)];
    }
    final double limit = math.max(sizes.first, budget);
    final List<({int start, int end})> bands = <({int start, int end})>[];
    var start = 0;
    var used = 0.0;
    for (int i = 0; i < sizes.length; i++) {
      final double next = sizes[i];
      if (i > start && used + next > limit) {
        bands.add((start: start, end: i - 1));
        start = i;
        used = 0;
      }
      used += next;
    }
    bands.add((start: start, end: sizes.length - 1));
    return bands;
  }

  static ({String text, String color, bool numeric}) _sheetDisplay(
    SmlWorkbook book,
    SmlWorksheet sheet,
    SmlCell cell,
  ) {
    final Object? value = cell.formula != null && cell.formula!.isNotEmpty
        ? FormulaEvaluator.evaluateCell(book, sheet, cell)
        : cell.value;
    if (value == null) {
      return (text: '', color: '222222', numeric: false);
    }
    final bool numeric = value is num;
    if (book.styles != null) {
      final String formatted = book.styles!.format(value, cell.styleIndex);
      final String ink = cell.fontRgb.isNotEmpty ? cell.fontRgb : '222222';
      if (formatted.startsWith('RED:')) {
        return (
          text: formatted.substring(4),
          color: 'C00000',
          numeric: numeric,
        );
      }
      return (text: formatted, color: ink, numeric: numeric);
    }
    if (value is num) {
      if (value == value.roundToDouble()) {
        return (text: '${value.round()}', color: '222222', numeric: true);
      }
      return (text: value.toStringAsFixed(2), color: '222222', numeric: true);
    }
    return (text: value.toString(), color: '222222', numeric: false);
  }

  static void _paintShape(
    _PageSink sink,
    PmlPresentation deck,
    PmlSlide slide,
    PmlShape shape,
  ) {
    final double x = shape.transform.xPoints;
    final double y = shape.transform.yPoints;
    final double w = shape.transform.widthPoints;
    final double h = shape.transform.heightPoints;
    sink.canvas.save();
    if (shape.transform.rotationDegrees.abs() > 0.05) {
      sink.canvas.rotateAround(
        x + w / 2,
        y + h / 2,
        shape.transform.rotationDegrees,
      );
    }
    if (shape.table != null) {
      _paintSlideTable(sink, shape.table!, x, y, w, h);
    } else if (shape.visual != null) {
      OfficePdfVisuals.paint(
        sink.canvas,
        x,
        y,
        w,
        h,
        shape.visual!,
        sink.images,
        drawText: sink.drawText,
        nextImageName: sink.nextImageName,
      );
    } else {
      _fillPreset(
        sink.canvas,
        shape.preset,
        x,
        y,
        w,
        h,
        shape.fillColor,
        shape.path,
      );
      if (shape.strokeColor.isNotEmpty &&
          shape.preset != PmlShapePreset.connector) {
        _strokePreset(
          sink.canvas,
          shape.preset,
          x,
          y,
          w,
          h,
          shape.strokeColor,
          shape.strokeWidth <= 0 ? 1 : shape.strokeWidth,
          shape.path,
        );
      }
      final String text = deck.resolveText(shape, slide);
      if (text.isNotEmpty) {
        final String ink = shape.textColor.isNotEmpty
            ? shape.textColor
            : (shape.fillColor.isEmpty ? '1A1A1A' : _contrast(shape.fillColor));
        final double rawSize = shape.fontSizePt > 0
            ? shape.fontSizePt.clamp(8, 48)
            : (h * 0.22).clamp(10, 28);
        final double size = math.min(rawSize, math.max(8, h * 0.55));
        final bool singleLine = !text.contains('\n');
        final double top = singleLine && h < size * 2.8
            ? y + math.max(2, (h - size) / 2)
            : y + math.max(4, size * 0.1);
        _wrapShapeText(sink, text, x + 10, top, w - 20, size, ink);
      }
    }
    sink.canvas.restore();
  }

  static void _strokePreset(
    PdfCanvas canvas,
    PmlShapePreset preset,
    double x,
    double y,
    double w,
    double h,
    String stroke,
    double width,
    List<PmlPathPoint> path,
  ) {
    canvas.setStrokeColor(stroke);
    canvas.setLineWidth(width.clamp(0.25, 8.0));
    switch (preset) {
      case PmlShapePreset.roundRect:
        canvas.roundedRect(x, y, w, h, 8);
        canvas.stroke();
      case PmlShapePreset.ellipse:
        canvas.ellipse(x, y, w, h);
        canvas.stroke();
      case PmlShapePreset.triangle:
        canvas.moveTo(x + w / 2, y);
        canvas.lineTo(x + w, y + h);
        canvas.lineTo(x, y + h);
        canvas.closePath();
        canvas.stroke();
      case PmlShapePreset.connector:
        canvas.moveTo(x, y + h / 2);
        canvas.lineTo(x + w, y + h / 2);
        canvas.stroke();
      case PmlShapePreset.freeform:
        if (path.length >= 2) {
          canvas.moveTo(x + path.first.x / 12700, y + path.first.y / 12700);
          for (int i = 1; i < path.length; i++) {
            canvas.lineTo(x + path[i].x / 12700, y + path[i].y / 12700);
          }
          canvas.closePath();
          canvas.stroke();
        } else {
          canvas.rect(x, y, w, h);
          canvas.stroke();
        }
      case PmlShapePreset.rect:
        canvas.rect(x, y, w, h);
        canvas.stroke();
    }
  }

  static void _paintSlideTable(
    _PageSink sink,
    PmlTable table,
    double x,
    double y,
    double w,
    double h,
  ) {
    sink.canvas.setStrokeColor('1F1F1F');
    sink.canvas.setLineWidth(0.8);
    sink.canvas.rect(x, y, w, h);
    sink.canvas.stroke();
    for (int row = 0; row < table.rowCount; row++) {
      for (int col = 0; col < table.colCount; col++) {
        final PmlTableCell cell = table.cellAt(row, col);
        final ({double x, double y, double width, double height}) box = table
            .cellBounds(x: x, y: y, width: w, height: h, row: row, col: col);
        if (cell.fillColor.isNotEmpty) {
          sink.canvas.setFillColor(cell.fillColor);
          sink.canvas.rect(box.x, box.y, box.width, box.height);
          sink.canvas.fill();
        }
        sink.canvas.setStrokeColor('6B6B6B');
        sink.canvas.setLineWidth(0.5);
        sink.canvas.rect(box.x, box.y, box.width, box.height);
        sink.canvas.stroke();
        if (cell.text.isNotEmpty) {
          final String ink = cell.textColor.isNotEmpty
              ? cell.textColor
              : '1A1A1A';
          final double size = (box.height * 0.28).clamp(8, 14);
          _wrapShapeText(
            sink,
            cell.text,
            box.x + 4,
            box.y + 3,
            box.width - 8,
            size,
            ink,
          );
        }
      }
    }
  }

  static void _fillPreset(
    PdfCanvas canvas,
    PmlShapePreset preset,
    double x,
    double y,
    double w,
    double h,
    String fill,
    List<PmlPathPoint> path,
  ) {
    if (fill.isEmpty) {
      return;
    }
    canvas.setFillColor(fill);
    switch (preset) {
      case PmlShapePreset.roundRect:
        canvas.roundedRect(x, y, w, h, 8);
        canvas.fill();
      case PmlShapePreset.ellipse:
        canvas.ellipse(x, y, w, h);
        canvas.fill();
      case PmlShapePreset.triangle:
        canvas.moveTo(x + w / 2, y);
        canvas.lineTo(x + w, y + h);
        canvas.lineTo(x, y + h);
        canvas.closePath();
        canvas.fill();
      case PmlShapePreset.connector:
        canvas.setStrokeColor(fill);
        canvas.setLineWidth(1.6);
        canvas.moveTo(x, y + h / 2);
        canvas.lineTo(x + w, y + h / 2);
        canvas.stroke();
      case PmlShapePreset.freeform:
        if (path.length >= 2) {
          canvas.moveTo(x + path.first.x / 12700, y + path.first.y / 12700);
          for (int i = 1; i < path.length; i++) {
            canvas.lineTo(x + path[i].x / 12700, y + path[i].y / 12700);
          }
          canvas.closePath();
          canvas.fill();
        } else {
          canvas.rect(x, y, w, h);
          canvas.fill();
        }
      case PmlShapePreset.rect:
        canvas.rect(x, y, w, h);
        canvas.fill();
    }
  }

  static void _wrapShapeText(
    _PageSink sink,
    String text,
    double x,
    double y,
    double maxWidth,
    double size,
    String color,
  ) {
    final SfntFont? layoutFont = sink.pack.layoutFont;
    if (layoutFont != null) {
      var cy = y;
      for (final String para in text.split('\n')) {
        if (para.isEmpty) {
          cy += size * 1.25;
          continue;
        }
        final List<BrokenLine> lines = LineBreaker.breakLines(
          text: para,
          maxWidth: maxWidth,
          widthOf: (int cp) => sink.pack.widthOf(cp, size),
          glyphIdOf: sink.pack.glyphIdOf,
          markAttachOf: GposMarkToBase.fnFor(
            layoutFont,
            size,
            faceFor: sink.pack.fontFor,
          ),
        );
        for (final BrokenLine line in lines) {
          if (line.glyphs.isEmpty) {
            cy += size * 1.25;
            continue;
          }
          final bool rtl = line.glyphs.any((ShapedGlyph g) => g.level.isOdd);
          var cx = rtl ? x + maxWidth - line.width : x;
          // Tm d=-1 grows glyphs up the flipped page; y is the baseline.
          final double baseline = cy + size;
          for (final ShapedGlyph g in line.glyphs) {
            if (g.codePoint < 32) {
              continue;
            }
            sink.drawGlyph(
              LaidOutGlyph(
                glyph: g,
                x: cx + g.paintDx,
                y: baseline - g.paintDy,
                color: color,
                fontSize: size,
                bold: false,
                underline: WmlUnderline.none,
              ),
            );
            cx += g.advance;
          }
          cy += size * 1.35;
        }
      }
      return;
    }
    final List<String> words = text.split(RegExp(r'\s+'));
    var line = '';
    var cy = y;
    for (final String word in words) {
      final String next = line.isEmpty ? word : '$line $word';
      if (sink.measure(next, size) > maxWidth && line.isNotEmpty) {
        sink.drawText(line, x, cy + size, size, color);
        line = word;
        cy += size * 1.25;
      } else {
        line = next;
      }
    }
    if (line.isNotEmpty) {
      sink.drawText(line, x, cy + size, size, color);
    }
  }

  static void _collectShaped(String text, Set<int> cps) {
    if (text.isEmpty) {
      return;
    }
    cps.addAll(text.runes);
    for (final ShapedChar shaped in ArabicShaper.shape(text)) {
      cps.add(shaped.codePoint);
    }
  }

  static String _contrast(String hex) {
    final int rgb =
        int.tryParse(hex.replaceAll('#', ''), radix: 16) ?? 0x4472C4;
    final int r = (rgb >> 16) & 0xFF;
    final int g = (rgb >> 8) & 0xFF;
    final int b = rgb & 0xFF;
    return (0.299 * r + 0.587 * g + 0.114 * b) < 140 ? 'FFFFFF' : '1A1A1A';
  }
}

/// Line placement inside `maxWidth`; [auto] puts RTL lines on the right.
enum _TextAlign { auto, left, center, right }

class _FontPack {
  _FontPack(this.set, this.faces, this.metrics);

  /// Resolved font set.
  final OfficeFontSet set;

  /// Embedded CID faces (`F1`, `F3`, …).
  final List<PdfEmbeddedFace> faces;

  /// Metrics for the primary (or first) face.
  final FontMetrics? metrics;

  /// Primary / first face used for line-breaking heuristics.
  SfntFont? get layoutFont =>
      faces.isNotEmpty ? faces.first.source : set.primary;

  /// Face that actually covers [codePoint], else the layout face.
  SfntFont? fontFor(int codePoint) => set.faceFor(codePoint) ?? layoutFont;

  /// Glyph id in the covering face, falling back from a missing presentation
  /// form to the nominal Arabic letter.
  int glyphIdOf(int codePoint) {
    final SfntFont? face = fontFor(codePoint);
    if (face == null) {
      return 0;
    }
    final int gid = face.glyphIdFor(codePoint);
    if (gid != 0) {
      return gid;
    }
    final int? nominal = ArabicShaper.nominalOf(codePoint);
    if (nominal == null) {
      return 0;
    }
    return face.glyphIdFor(nominal);
  }

  /// Advance in points. Never returns 0 for a letter the covering face has,
  /// so joining glyphs cannot stack on the previous letter.
  double widthOf(int codePoint, double size) {
    final SfntFont? face = fontFor(codePoint);
    if (face == null || size <= 0) {
      return size * 0.5;
    }
    var cp = codePoint;
    if (face.glyphIdFor(cp) == 0) {
      final int? nominal = ArabicShaper.nominalOf(cp);
      if (nominal != null && face.glyphIdFor(nominal) != 0) {
        cp = nominal;
      }
    }
    final int gid = face.glyphIdFor(cp);
    if (gid == 0) {
      return size * 0.5;
    }
    final double width = FontMetrics(
      font: face,
      fontSizePoints: size,
    ).advanceWidth(gid);
    return width > 0 ? width : size * 0.5;
  }

  /// build API.
  static _FontPack build(OfficeFontSet set, Set<int> cps) {
    final List<SfntFont> candidates = set.embeddable;
    final SfntFont? metricsFont = candidates.isNotEmpty
        ? candidates.first
        : set.primary;
    final FontMetrics? metrics = metricsFont == null
        ? null
        : FontMetrics(font: metricsFont, fontSizePoints: 11);
    if (candidates.isEmpty || cps.isEmpty) {
      return _FontPack(set, const <PdfEmbeddedFace>[], metrics);
    }

    final Map<SfntFont, Set<int>> byFace = <SfntFont, Set<int>>{};
    for (final int cp in cps) {
      final SfntFont? face = set.faceFor(cp);
      if (face == null) {
        continue;
      }
      byFace.putIfAbsent(face, () => <int>{}).add(cp);
    }

    final List<PdfEmbeddedFace> faces = <PdfEmbeddedFace>[];
    var faceOrdinal = 0;
    for (final SfntFont font in candidates) {
      final Set<int>? used = byFace[font];
      if (used == null || used.isEmpty) {
        continue;
      }
      faceOrdinal++;
      // F2 is reserved for Helvetica; first face is F1, then F3, F4, …
      final String name = faceOrdinal == 1 ? 'F1' : 'F${faceOrdinal + 1}';
      faces.add(
        PdfEmbeddedFace(
          subset: FontSubsetter(font).subset(used),
          source: font,
          resourceName: name,
        ),
      );
    }
    return _FontPack(set, faces, metrics);
  }

  PdfEmbeddedFace? faceForCodePoint(int codePoint) {
    for (final PdfEmbeddedFace face in faces) {
      if (face.subset.unicodeToNewGlyph.containsKey(codePoint)) {
        return face;
      }
    }
    final SfntFont? source = set.faceFor(codePoint);
    if (source == null) {
      return null;
    }
    for (final PdfEmbeddedFace face in faces) {
      if (identical(face.source, source)) {
        return face;
      }
    }
    return null;
  }
}

class _PdfImageBank {
  var _n = 0;

  /// next API.
  String next() => 'Im${++_n}';
}

class _PageSink {
  _PageSink(this.width, this.height, this.pack, this._images)
    : canvas = PdfCanvas(width, height);

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// pack API.
  final _FontPack pack;
  final _PdfImageBank _images;

  /// canvas API.
  final PdfCanvas canvas;

  /// images API.
  final List<PdfEmbeddedImage> images = <PdfEmbeddedImage>[];

  /// links API.
  final List<PdfLinkAnnot> links = <PdfLinkAnnot>[];

  /// nextImageName API.
  String nextImageName() => _images.next();

  /// addResolvedLink API.
  void addResolvedLink(
    double x,
    double y,
    double width,
    double height,
    WmlHyperlink link,
    LaidOutDocument laid,
    WmlDocument document,
    Map<int, int> layoutToPdf,
  ) {
    if (link.isWeb) {
      links.add(
        PdfLinkAnnot(x: x, y: y, width: width, height: height, uri: link.url),
      );
      return;
    }
    if (link.isFile) {
      links.add(
        PdfLinkAnnot(x: x, y: y, width: width, height: height, file: link.file),
      );
      return;
    }
    if (!link.isInternal) {
      return;
    }
    final int? para = WordLink.paragraphIndexForAnchor(document, link.anchor!);
    if (para == null) {
      return;
    }
    final ({int page, double y})? dest = OfficePdfExport._pageOfParagraph(
      laid,
      para,
    );
    if (dest == null) {
      return;
    }
    final int? pdfPage = layoutToPdf[dest.page];
    if (pdfPage == null) {
      return;
    }
    links.add(
      PdfLinkAnnot(
        x: x,
        y: y,
        width: width,
        height: height,
        destPage: pdfPage,
        destY: dest.y,
      ),
    );
  }

  /// drawGlyph API.
  void drawGlyph(LaidOutGlyph g) {
    _emit(
      oldGid: g.glyph.glyphId,
      codePoint: g.glyph.codePoint,
      x: g.x,
      y: g.y,
      size: g.fontSize,
      color: g.color,
      italic: g.italic,
      bold: g.bold,
    );
  }

  /// drawText API.
  void drawText(
    String text,
    double x,
    double y,
    double size,
    String color, {
    double? maxWidth,
    _TextAlign align = _TextAlign.auto,
    bool bold = false,
  }) {
    if (text.isEmpty) {
      return;
    }
    final SfntFont? layoutFont = pack.layoutFont;
    if (layoutFont != null && pack.faces.isNotEmpty) {
      final List<BrokenLine> lines = LineBreaker.breakLines(
        text: text,
        maxWidth: maxWidth ?? 1e9,
        widthOf: (int cp) => pack.widthOf(cp, size),
        glyphIdOf: pack.glyphIdOf,
        markAttachOf: GposMarkToBase.fnFor(
          layoutFont,
          size,
          faceFor: pack.fontFor,
        ),
      );
      var cy = y;
      for (int i = 0; i < lines.length; i++) {
        final BrokenLine line = lines[i];
        if (line.glyphs.isEmpty) {
          cy += size * 1.25;
          continue;
        }
        final bool rtl = line.glyphs.any((ShapedGlyph g) => g.level.isOdd);
        var cx = x;
        if (maxWidth != null) {
          final double slack = maxWidth - line.width;
          cx += switch (align) {
            _TextAlign.auto => rtl ? slack : 0,
            _TextAlign.left => 0,
            _TextAlign.center => slack / 2,
            _TextAlign.right => slack,
          };
        }
        for (final ShapedGlyph g in line.glyphs) {
          if (g.codePoint < 32) {
            continue;
          }
          _emit(
            oldGid: g.glyphId,
            codePoint: g.codePoint,
            x: cx + g.paintDx,
            y: cy - g.paintDy,
            size: size,
            color: color,
            bold: bold,
          );
          cx += g.advance;
        }
        cy += size * 1.25;
      }
      return;
    }
    if (_winAnsiOnly(text)) {
      canvas.showLatin(x: x, y: y, fontSize: size, text: text, color: color);
      return;
    }
    var cx = x;
    for (final int cp in text.runes) {
      if (_isWinAnsi(cp)) {
        canvas.showLatin(
          x: cx,
          y: y,
          fontSize: size,
          text: String.fromCharCode(cp),
          color: color,
        );
        cx += size * 0.5;
      }
    }
  }

  void _emit({
    required int oldGid,
    required int codePoint,
    required double x,
    required double y,
    required double size,
    required String color,
    bool italic = false,
    bool bold = false,
  }) {
    final int? nominal = ArabicShaper.nominalOf(codePoint);
    PdfEmbeddedFace? face = pack.faceForCodePoint(codePoint);
    var drawable = codePoint;
    if (face == null && nominal != null) {
      face = pack.faceForCodePoint(nominal);
      if (face != null) {
        drawable = nominal;
      }
    }
    if (face != null) {
      final int gid =
          face.subset.unicodeToNewGlyph[drawable] ??
          face.subset.unicodeToNewGlyph[codePoint] ??
          face.subset.oldToNewGlyph[oldGid] ??
          0;
      if (gid != 0) {
        canvas.showGlyph(
          x: x,
          y: y,
          fontSize: size,
          glyphId: gid,
          color: color,
          italic: italic,
          bold: bold,
          fontName: face.resourceName,
        );
        return;
      }
    }
    if (_isWinAnsi(codePoint)) {
      canvas.showLatin(
        x: x,
        y: y,
        fontSize: size,
        text: String.fromCharCode(codePoint),
        color: color,
      );
    }
  }

  static bool _isWinAnsi(int cp) => PdfStd14.winAnsiByte(cp) != null;

  static bool _winAnsiOnly(String text) {
    for (final int cp in text.runes) {
      if (cp == 0x0A || cp == 0x0D) {
        continue;
      }
      if (!_isWinAnsi(cp)) {
        return false;
      }
    }
    return true;
  }

  /// measure API.
  double measure(String text, double size) {
    final SfntFont? font = pack.layoutFont;
    if (font != null) {
      return FontMetrics(font: font, fontSizePoints: size).measureText(text);
    }
    return text.length * size * 0.5;
  }

  /// finish API.
  void finish(PdfDocument pdf) {
    canvas.endText();
    pdf.addPage(
      PdfPage(
        width: width,
        height: height,
        content: canvas.toStream(),
        images: List<PdfEmbeddedImage>.from(images),
        links: List<PdfLinkAnnot>.from(links),
      ),
    );
  }
}
