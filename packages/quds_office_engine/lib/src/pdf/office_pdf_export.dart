import 'dart:math' as math;
import 'dart:typed_data';

import '../bidi/arabic_shaping.dart';
import '../bidi/line_breaker.dart';
import '../bidi/uax9_bidi.dart';
import '../fonts/font_metrics.dart';
import '../fonts/font_subsetter.dart';
import '../fonts/gpos_mark_to_base.dart';
import '../fonts/office_font_set.dart';
import '../fonts/sfnt_parser.dart';
import '../opc/opc_archive.dart';
import '../opc/repair/office_repair.dart';
import '../sheet/formula/formula_eval.dart';
import '../sheet/model/sml_conditional_format.dart';
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
import 'pdf_font.dart';
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
    String title = 'CrispOffice',
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
        throw const FormatException(
          'Unsupported Office package for PDF export',
        );
    }
  }

  /// word API.
  static Uint8List word(
    WmlDocument document, {
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSaveOptions saveOptions = const PdfSaveOptions(),
    String title = 'CrispOffice',
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
    String title = 'CrispOffice',
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
    String title = 'CrispOffice',
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
      for (final PmlShape shape in <PmlShape>[
        ...slide.backgroundShapes,
        ...slide.shapes,
      ]) {
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
      sink.canvas.fillRect(0, 0, slideW, slideH, _slideBackground(deck, slide));
      for (final PmlShape shape in _slideBackgroundShapes(deck, slide)) {
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

      linkShapes(_slideBackgroundShapes(deck, slide), scaled: notes);
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
          _slideBackground(deck, slide),
        );
        for (final PmlShape shape in _slideBackgroundShapes(deck, slide)) {
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

        linkShapes(_slideBackgroundShapes(deck, slide));
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
    final logicalText = _wordLineActualText(line);
    if (logicalText != null) sink.canvas.beginActualText(logicalText);
    for (var i = 0; i < line.glyphs.length;) {
      final glyph = line.glyphs[i];
      final actualText = logicalText == null ? glyph.actualText : null;
      var end = i + 1;
      if (actualText != null) {
        while (end < line.glyphs.length &&
            line.glyphs[end].actualText == actualText &&
            line.glyphs[end].glyph.logicalIndex == glyph.glyph.logicalIndex &&
            line.glyphs[end].sourceEnd == glyph.sourceEnd) {
          end++;
        }
        sink.canvas.beginActualText(actualText);
      }
      for (var index = i; index < end; index++) {
        sink.drawGlyph(line.glyphs[index]);
        _paintGlyphChrome(sink, line.glyphs[index]);
      }
      if (actualText != null) sink.canvas.endActualText();
      i = end;
    }
    if (logicalText != null) sink.canvas.endActualText();
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
    final WmlUnderline u = g.underline;
    final double width = u.isHeavy ? 1.4 : 0.7;
    sink.canvas.setLineWidth(width);
    if (u.isWavy) {
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
      return;
    }
    if (u == WmlUnderline.double) {
      sink.canvas.moveTo(g.x, g.y + 1.1);
      sink.canvas.lineTo(g.x + g.advance, g.y + 1.1);
      sink.canvas.stroke();
      sink.canvas.moveTo(g.x, g.y + 3.4);
      sink.canvas.lineTo(g.x + g.advance, g.y + 3.4);
      sink.canvas.stroke();
      return;
    }
    // Word underlines spaces only for continuous styles, not for "words".
    if (u == WmlUnderline.words && g.glyph.codePoint == 0x20) return;
    final List<num> dash = u.dashPattern;
    if (dash.isNotEmpty) {
      sink.canvas.setDash(<double>[for (final num d in dash) d * width * 1.6]);
    }
    sink.canvas.moveTo(g.x, g.y + 1.2);
    sink.canvas.lineTo(g.x + g.advance, g.y + 1.2);
    sink.canvas.stroke();
    if (dash.isNotEmpty) sink.canvas.resetDash();
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
    final conditionalFormats = SmlConditionalResolver(
      sheet: sheet,
      workbook: book,
    );
    final double pageW = options.pageWidth;
    final double pageH = options.pageHeight;
    final double margin = options.margin;
    final double gutter = options.showHeadings ? 28 : 0;
    const double band = 18;

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
          SmlConditionalStyle conditional,
        ) {
          final fill = conditional.fillRgb ?? stored?.fillRgb ?? '';
          if (fill.isNotEmpty) {
            sink.canvas.fillRect(x, y, spanW, spanH, fill);
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
              final conditional = conditionalFormats.resolve(SmlCellRef(c, r));
              paintCellFrame(x, y, spanW, spanH, stored, conditional);
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
                conditional.fontRgb ?? shown.color,
                maxWidth: spanW - 6,
                align: align,
                bold: stored.fontBold,
                family: book.styles?.familyAt(stored.styleIndex),
                italic: book.styles?.italicAt(stored.styleIndex) ?? false,
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
    final String ink = cell.fontRgb.isNotEmpty ? cell.fontRgb : '222222';
    if (book.styles != null) {
      final String formatted = book.styles!.format(value, cell.styleIndex);
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
        return (text: '${value.round()}', color: ink, numeric: true);
      }
      return (text: value.toStringAsFixed(2), color: ink, numeric: true);
    }
    return (text: value.toString(), color: ink, numeric: false);
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
      // A connector is a single stroke. Its legacy fill color is a fallback
      // only when no authored stroke exists, never a second wider underlay.
      if (shape.preset != PmlShapePreset.connector ||
          shape.strokeColor.isEmpty) {
        _fillPreset(
          sink.canvas,
          shape.preset,
          x,
          y,
          w,
          h,
          shape.fillColor,
          shape.path,
          shape.transform.flipH,
          shape.transform.flipV,
          gradient: shape.gradient,
        );
      }
      if (shape.strokeColor.isNotEmpty) {
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
          shape.transform.flipH,
          shape.transform.flipV,
        );
      }
      final String text = deck.resolveText(shape, slide);
      if (text.isNotEmpty && shape.textScale > 0) {
        final List<PmlTextParagraph> paragraphs = shape.resolvedRichText;
        if (paragraphs.isNotEmpty && text == shape.text) {
          _paintRichText(sink, shape, paragraphs, x, y, w, h);
        } else {
          final String ink = shape.textColor.isNotEmpty
              ? shape.textColor
              : (shape.fillColor.isEmpty
                    ? '1A1A1A'
                    : _contrast(shape.fillColor));
          final double rawSize = shape.fontSizePt > 0
              ? shape.fontSizePt.clamp(8, 48)
              : (h * 0.22).clamp(10, 28);
          final double size =
              math.min(rawSize, math.max(8, h * 0.55)) * shape.textScale;
          final bool singleLine = !text.contains('\n');
          final double top = singleLine && h < size * 2.8
              ? y + math.max(2, (h - size) / 2)
              : y + math.max(4, size * 0.1);
          _wrapShapeText(
            sink,
            text,
            x + 10,
            top,
            w - 20,
            size,
            ink,
            lineAdvance: shape.textScale == 1 && shape.lineSpacingReduction == 0
                ? null
                : sink.lineHeight(size) * (1 - shape.lineSpacingReduction),
          );
        }
      }
    }
    sink.canvas.restore();
  }

  static void _paintGradient(
    PdfCanvas canvas,
    PmlShapePreset preset,
    double x,
    double y,
    double w,
    double h,
    PmlGradientFill gradient,
    List<PmlPathPoint> path,
  ) {
    canvas.save();
    switch (preset) {
      case PmlShapePreset.rect:
        canvas.rect(x, y, w, h);
      case PmlShapePreset.roundRect:
        canvas.roundedRect(x, y, w, h, math.min(8, math.min(w, h) / 4));
      case PmlShapePreset.ellipse:
        canvas.ellipse(x, y, w, h);
      case PmlShapePreset.triangle:
        canvas.moveTo(x + w / 2, y);
        canvas.lineTo(x + w, y + h);
        canvas.lineTo(x, y + h);
        canvas.closePath();
      case PmlShapePreset.diamond:
      case PmlShapePreset.hexagon:
      case PmlShapePreset.pentagon:
      case PmlShapePreset.homePlate:
      case PmlShapePreset.chevron:
      case PmlShapePreset.parallelogram:
      case PmlShapePreset.trapezoid:
        _shapePath(canvas, preset, x, y, w, h);
      case PmlShapePreset.downArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.down);
      case PmlShapePreset.upArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.up);
      case PmlShapePreset.leftArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.left);
      case PmlShapePreset.rightArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.right);
      case PmlShapePreset.connector:
        canvas.rect(x, y, w, h);
      case PmlShapePreset.freeform:
        if (path.length >= 2) {
          canvas.moveTo(x + path.first.x / 12700, y + path.first.y / 12700);
          for (final point in path.skip(1)) {
            canvas.lineTo(x + point.x / 12700, y + point.y / 12700);
          }
          canvas.closePath();
        } else {
          canvas.rect(x, y, w, h);
        }
    }
    canvas.clip();
    final double angle = gradient.angleDegrees;
    final double cx = x + w / 2;
    final double cy = y + h / 2;
    const int steps = 72;
    if (gradient.radial) {
      canvas.fillRect(x, y, w, h, gradient.stops.last.color);
      final double radius = math.min(w, h) / 2;
      for (var i = steps; i > 0; i--) {
        final double r = radius * i / steps;
        canvas.setFillColor(_gradientColor(gradient, (i - .5) / steps));
        canvas.ellipse(cx - r, cy - r, r * 2, r * 2);
        canvas.fill();
      }
    } else {
      final double radians = angle * math.pi / 180;
      final double cosine = math.cos(radians).abs();
      final double sine = math.sin(radians).abs();
      // Project the bounds onto the gradient direction, matching the editor.
      // A horizontal gradient spans w, and a vertical one spans h.
      final double span = w * cosine + h * sine;
      final double cross = w * sine + h * cosine;
      canvas.rotateAround(cx, cy, angle);
      for (int i = 0; i < steps; i++) {
        final double t0 = i / steps;
        final double t1 = (i + 1) / steps;
        canvas.setFillColor(_gradientColor(gradient, (t0 + t1) / 2));
        canvas.rect(
          cx - span / 2 + span * t0,
          cy - cross / 2,
          span * (t1 - t0) + 0.35,
          cross,
        );
        canvas.fill();
      }
    }
    canvas.restore();
  }

  static String _gradientColor(PmlGradientFill gradient, double t) {
    final List<PmlGradientStop> stops = gradient.stops;
    if (t <= stops.first.position) return stops.first.color;
    if (t >= stops.last.position) return stops.last.color;
    for (int i = 1; i < stops.length; i++) {
      if (t <= stops[i].position) {
        final PmlGradientStop a = stops[i - 1];
        final PmlGradientStop b = stops[i];
        final double span = (b.position - a.position).abs();
        final double f = span < 0.0001 ? 0 : (t - a.position) / span;
        final int ca = int.tryParse(a.color, radix: 16) ?? 0;
        final int cb = int.tryParse(b.color, radix: 16) ?? ca;
        int mix(int shift) {
          final int va = (ca >> shift) & 0xFF;
          final int vb = (cb >> shift) & 0xFF;
          return (va + (vb - va) * f).round().clamp(0, 255);
        }

        return ((mix(16) << 16) | (mix(8) << 8) | mix(0))
            .toRadixString(16)
            .padLeft(6, '0')
            .toUpperCase();
      }
    }
    return stops.last.color;
  }

  static void _shapePath(
    PdfCanvas canvas,
    PmlShapePreset preset,
    double x,
    double y,
    double w,
    double h,
  ) {
    switch (preset) {
      case PmlShapePreset.diamond:
        canvas.moveTo(x + w / 2, y);
        canvas.lineTo(x + w, y + h / 2);
        canvas.lineTo(x + w / 2, y + h);
        canvas.lineTo(x, y + h / 2);
      case PmlShapePreset.hexagon:
        canvas.moveTo(x + w * 0.25, y);
        canvas.lineTo(x + w * 0.75, y);
        canvas.lineTo(x + w, y + h / 2);
        canvas.lineTo(x + w * 0.75, y + h);
        canvas.lineTo(x + w * 0.25, y + h);
        canvas.lineTo(x, y + h / 2);
      case PmlShapePreset.pentagon:
        // A regular pentagon normalized to its bounding rectangle.
        final double inset = (3 - math.sqrt(5)) / 4;
        canvas.moveTo(x, y + h * inset * 2);
        canvas.lineTo(x + w / 2, y);
        canvas.lineTo(x + w, y + h * inset * 2);
        canvas.lineTo(x + w * (1 - inset), y + h);
        canvas.lineTo(x + w * inset, y + h);
      case PmlShapePreset.homePlate:
        final double head = math.min(w, h) / 2;
        canvas.moveTo(x, y);
        canvas.lineTo(x + w - head, y);
        canvas.lineTo(x + w, y + h / 2);
        canvas.lineTo(x + w - head, y + h);
        canvas.lineTo(x, y + h);
      case PmlShapePreset.chevron:
        canvas.moveTo(x, y);
        canvas.lineTo(x + w * 0.75, y);
        canvas.lineTo(x + w, y + h / 2);
        canvas.lineTo(x + w * 0.75, y + h);
        canvas.lineTo(x, y + h);
        canvas.lineTo(x + w * 0.25, y + h / 2);
      case PmlShapePreset.parallelogram:
        canvas.moveTo(x + w * 0.25, y);
        canvas.lineTo(x + w, y);
        canvas.lineTo(x + w * 0.75, y + h);
        canvas.lineTo(x, y + h);
      case PmlShapePreset.trapezoid:
        canvas.moveTo(x + w * 0.2, y);
        canvas.lineTo(x + w * 0.8, y);
        canvas.lineTo(x + w, y + h);
        canvas.lineTo(x, y + h);
      case PmlShapePreset.rect:
      case PmlShapePreset.roundRect:
      case PmlShapePreset.ellipse:
      case PmlShapePreset.triangle:
      case PmlShapePreset.connector:
      case PmlShapePreset.freeform:
      case PmlShapePreset.downArrow:
      case PmlShapePreset.upArrow:
      case PmlShapePreset.leftArrow:
      case PmlShapePreset.rightArrow:
        canvas.rect(x, y, w, h);
    }
    canvas.closePath();
  }

  static void _arrowPath(
    PdfCanvas canvas,
    double x,
    double y,
    double w,
    double h,
    _ArrowDirection direction,
  ) {
    final bool vertical =
        direction == _ArrowDirection.down || direction == _ArrowDirection.up;
    final double shaft = (vertical ? w : h) * 0.48;
    final double head = (vertical ? h : w) * 0.48;
    void point(double px, double py) => canvas.lineTo(px, py);
    void move(double px, double py) => canvas.moveTo(px, py);
    switch (direction) {
      case _ArrowDirection.down:
        final double left = x + (w - shaft) / 2;
        final double bottom = y + h - head;
        move(left, y);
        point(left + shaft, y);
        point(left + shaft, bottom);
        point(x + w, bottom);
        point(x + w / 2, y + h);
        point(x, bottom);
        point(left, bottom);
      case _ArrowDirection.up:
        final double left = x + (w - shaft) / 2;
        final double top = y + head;
        move(left, y + h);
        point(left + shaft, y + h);
        point(left + shaft, top);
        point(x + w, top);
        point(x + w / 2, y);
        point(x, top);
        point(left, top);
      case _ArrowDirection.left:
        final double top = y + (h - shaft) / 2;
        final double right = x + w - head;
        move(x + w, top);
        point(x + w, top + shaft);
        point(right, top + shaft);
        point(right, y + h);
        point(x, y + h / 2);
        point(right, y);
        point(right, top);
      case _ArrowDirection.right:
        final double top = y + (h - shaft) / 2;
        final double left = x + head;
        move(x, top);
        point(x, top + shaft);
        point(left, top + shaft);
        point(left, y + h);
        point(x + w, y + h / 2);
        point(left, y);
        point(left, top);
    }
    canvas.closePath();
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
    bool flipH,
    bool flipV,
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
        canvas.moveTo(flipH ? x + w : x, flipV ? y + h : y);
        canvas.lineTo(flipH ? x : x + w, flipV ? y : y + h);
        canvas.stroke();
      case PmlShapePreset.downArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.down);
        canvas.stroke();
      case PmlShapePreset.upArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.up);
        canvas.stroke();
      case PmlShapePreset.leftArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.left);
        canvas.stroke();
      case PmlShapePreset.rightArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.right);
        canvas.stroke();
      case PmlShapePreset.diamond:
      case PmlShapePreset.hexagon:
      case PmlShapePreset.pentagon:
      case PmlShapePreset.homePlate:
      case PmlShapePreset.chevron:
      case PmlShapePreset.parallelogram:
      case PmlShapePreset.trapezoid:
        _shapePath(canvas, preset, x, y, w, h);
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
    bool flipH,
    bool flipV, {
    PmlGradientFill? gradient,
  }) {
    if (gradient != null &&
        gradient.stops.length >= 2 &&
        preset != PmlShapePreset.connector) {
      _paintGradient(canvas, preset, x, y, w, h, gradient, path);
      return;
    }
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
        canvas.moveTo(flipH ? x + w : x, flipV ? y + h : y);
        canvas.lineTo(flipH ? x : x + w, flipV ? y : y + h);
        canvas.stroke();
      case PmlShapePreset.downArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.down);
        canvas.fill();
      case PmlShapePreset.upArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.up);
        canvas.fill();
      case PmlShapePreset.leftArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.left);
        canvas.fill();
      case PmlShapePreset.rightArrow:
        _arrowPath(canvas, x, y, w, h, _ArrowDirection.right);
        canvas.fill();
      case PmlShapePreset.diamond:
      case PmlShapePreset.hexagon:
      case PmlShapePreset.pentagon:
      case PmlShapePreset.homePlate:
      case PmlShapePreset.chevron:
      case PmlShapePreset.parallelogram:
      case PmlShapePreset.trapezoid:
        _shapePath(canvas, preset, x, y, w, h);
        canvas.fill();
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

  static List<PmlShape> _slideBackgroundShapes(
    PmlPresentation deck,
    PmlSlide slide,
  ) {
    // Resolved decorations already exclude hidden master shapes. Layout
    // decorations remain visible even when the slide hides its master.
    if (slide.backgroundShapesResolved || slide.backgroundShapes.isNotEmpty) {
      if (slide.inheritsMasterBackground && deck.master.hasAuthoredBackground) {
        // Direct master edits take effect before a native save, without
        // deleting imported snapshots or overriding local slide/layout fills.
        return [
          for (final shape in slide.backgroundShapes)
            if (!shape.isBackgroundFill) shape,
        ];
      }
      return slide.backgroundShapes;
    }
    return slide.showMasterShapes ? deck.master.shapes : const <PmlShape>[];
  }

  static String _slideBackground(PmlPresentation deck, PmlSlide slide) {
    return slide.resolveBackground(deck.master.background);
  }

  static double _slideLineAdvance(
    _PageSink sink,
    PmlTextParagraph paragraph,
    PmlShape shape,
    double size, {
    bool bold = false,
    bool italic = false,
    String? family,
  }) {
    final double? fixed = paragraph.lineSpacingPt;
    if (fixed != null && fixed.isFinite) return math.max(0, fixed);
    final double base = shape.textScale == 1 && shape.lineSpacingReduction == 0
        ? size * 1.25
        : sink.lineHeight(size, bold: bold, italic: italic, family: family);
    return base *
        math.max(0, paragraph.lineSpacing - shape.lineSpacingReduction);
  }

  static void _paintRichText(
    _PageSink sink,
    PmlShape shape,
    List<PmlTextParagraph> paragraphs,
    double x,
    double y,
    double w,
    double h,
  ) {
    const double leftInset = 7.2;
    const double topInset = 3.6;
    const double rightInset = 7.2;
    final double width = math.max(8, w - leftInset - rightInset);
    final String fallbackColor = shape.textColor.isEmpty
        ? '000000'
        : shape.textColor;
    final double fallbackSize = shape.fontSizePt > 0 ? shape.fontSizePt : 12;
    double fitScale = 1;
    final List<PmlTextParagraph> visible = <PmlTextParagraph>[
      for (final PmlTextParagraph paragraph in paragraphs)
        if (_paragraphText(paragraph).trim().isNotEmpty) paragraph,
    ];
    if (visible.length == 1 && h < fallbackSize * shape.textScale * 3) {
      final PmlTextParagraph paragraph = visible.single;
      final PmlTextRun? run = _firstRichRun(paragraph);
      final double size =
          ((run?.fontSizePt ?? 0) > 0
              ? run!.fontSizePt
              : (paragraph.defaultFontSizePt > 0
                    ? paragraph.defaultFontSizePt
                    : fallbackSize)) *
          shape.textScale;
      final String text = _paragraphText(paragraph);
      if (!text.contains('\t') && !text.contains('\n')) {
        final double natural = sink.measureStyled(
          text,
          size,
          bold:
              (run?.bold ?? false) &&
              !(run?.fontFamily.toLowerCase().contains(
                    'microsoft sans serif',
                  ) ??
                  false),
          italic: run?.italic ?? false,
          family: (run?.fontFamily ?? '').isEmpty ? null : run!.fontFamily,
          baseLevel: paragraph.rightToLeft ? 1 : 0,
        );
        final double available = math.max(8, width - paragraph.marginLeftPt);
        if (natural > available) {
          fitScale = (available / natural).clamp(0.75, 1.0);
        }
      }
    }
    final double sizeScale = fitScale * shape.textScale;
    double paragraphHeight(
      PmlTextParagraph paragraph,
      double top, {
      bool paint = false,
    }) => _paintRichParagraph(
      sink,
      shape,
      paragraph,
      x + leftInset,
      top,
      width,
      fallbackSize,
      fallbackColor,
      sizeScale,
      paint: paint,
    );
    final double total = paragraphs.fold<double>(
      0,
      (height, paragraph) => height + paragraphHeight(paragraph, 0),
    );
    double cy = switch (shape.textAnchor) {
      PmlTextAnchor.center => y + (h - total) / 2,
      PmlTextAnchor.bottom => y + h - total - topInset,
      PmlTextAnchor.top => y + topInset,
    };
    for (final PmlTextParagraph paragraph in paragraphs) {
      cy += paragraphHeight(paragraph, cy, paint: true);
    }
  }

  // The dry run and painting share this layout path so anchoring uses exactly
  // the advances that are emitted, including blank, mixed and numeric lines.
  static double _paintRichParagraph(
    _PageSink sink,
    PmlShape shape,
    PmlTextParagraph paragraph,
    double x,
    double y,
    double width,
    double fallbackSize,
    String fallbackColor,
    double sizeScale, {
    required bool paint,
  }) {
    final PmlTextRun? run = _firstRichRun(paragraph);
    final String text = _paragraphText(paragraph);
    final double unscaledSize = (run?.fontSizePt ?? 0) > 0
        ? run!.fontSizePt
        : (paragraph.defaultFontSizePt > 0
              ? paragraph.defaultFontSizePt
              : fallbackSize);
    final double size = unscaledSize * sizeScale;
    final bool bold =
        (run?.bold ?? false) &&
        !(run?.fontFamily.toLowerCase().contains('microsoft sans serif') ??
            false);
    final bool italic = run?.italic ?? false;
    final String? family = (run?.fontFamily ?? '').isEmpty
        ? null
        : run!.fontFamily;
    final String color = (run?.color ?? '').isNotEmpty
        ? run!.color
        : fallbackColor;
    final double spacingFactor = math.max(
      0,
      paragraph.lineSpacing - shape.lineSpacingReduction,
    );
    final double lineAdvance =
        paragraph.lineSpacingPt ??
        (shape.textScale == 1 && shape.lineSpacingReduction == 0
                ? size * 1.25
                : sink.lineHeight(
                    size,
                    bold: bold,
                    italic: italic,
                    family: family,
                  )) *
            spacingFactor;
    final double cy = y + paragraph.spaceBeforePt;
    final double px = x + paragraph.marginLeftPt;
    final double maxWidth = math.max(8, width - paragraph.marginLeftPt);
    final _TextAlign align = switch (paragraph.align) {
      PmlTextAlign.center => _TextAlign.center,
      PmlTextAlign.right => _TextAlign.right,
      PmlTextAlign.left || PmlTextAlign.justify => _TextAlign.left,
    };
    double height;
    if (text.trim().isEmpty) {
      height = lineAdvance;
    } else if (text.contains('\t')) {
      final List<String> parts = text.split('\t');
      var cx = px;
      var lines = 1;
      final double tab = paragraph.defaultTabPt <= 0
          ? 72
          : paragraph.defaultTabPt;
      for (final String part in parts) {
        if (part.isNotEmpty) {
          final double remaining = math.max(8, px + maxWidth - cx);
          lines = math.max(
            lines,
            sink.lineCount(
              part,
              size,
              maxWidth: remaining,
              bold: bold,
              italic: italic,
              family: family,
              baseLevel: paragraph.rightToLeft ? 1 : 0,
              forceLayout: true,
            ),
          );
          if (paint) {
            sink.drawText(
              part,
              cx,
              cy + size,
              size,
              color,
              maxWidth: remaining,
              align: _TextAlign.left,
              bold: bold,
              italic: italic,
              family: family,
              baseLevel: paragraph.rightToLeft ? 1 : 0,
              lineAdvance: lineAdvance,
            );
          }
          cx += sink.measureStyled(
            part,
            size,
            bold: bold,
            italic: italic,
            family: family,
            baseLevel: paragraph.rightToLeft ? 1 : 0,
          );
        }
        final double offset = math.max(0, cx - px);
        cx = math.min(px + maxWidth, px + ((offset / tab).floor() + 1) * tab);
      }
      height = lines * lineAdvance;
    } else if (_hasMixedRichStyles(paragraph)) {
      height = _paintStyledParagraph(
        sink,
        paragraph,
        px,
        cy,
        maxWidth,
        align,
        size,
        fallbackColor,
        sizeScale,
        spacingFactor: spacingFactor,
        naturalLeading: shape.textScale != 1 || shape.lineSpacingReduction != 0,
        fixedLeading: paragraph.lineSpacingPt,
        paint: paint,
      );
    } else {
      final List<String>? plainLtrLines =
          !paragraph.rightToLeft &&
              !text.contains('\r') &&
              !RegExp(r'\p{L}', unicode: true).hasMatch(text)
          ? text.split('\n')
          : null;
      final bool plainLtrFits =
          plainLtrLines?.every(
            (line) =>
                sink.plainWidth(
                  line,
                  size,
                  bold: bold,
                  italic: italic,
                  family: family,
                ) <=
                maxWidth,
          ) ??
          false;
      if (plainLtrLines != null && plainLtrFits) {
        var baseline = cy + size;
        for (final String line in plainLtrLines) {
          if (paint) {
            final double textWidth = sink.plainWidth(
              line,
              size,
              bold: bold,
              italic: italic,
              family: family,
            );
            final double dx = switch (align) {
              _TextAlign.center => (maxWidth - textWidth) / 2,
              _TextAlign.right => maxWidth - textWidth,
              _TextAlign.left || _TextAlign.auto => 0,
            };
            sink.drawPlainLtr(
              line,
              px + dx,
              baseline,
              size,
              color,
              bold: bold,
              italic: italic,
              family: family,
            );
          }
          baseline += lineAdvance;
        }
        height = plainLtrLines.length * lineAdvance;
      } else {
        final int lines = sink.lineCount(
          text,
          size,
          maxWidth: maxWidth,
          bold: bold,
          italic: italic,
          family: family,
          baseLevel: paragraph.rightToLeft ? 1 : 0,
          forceLayout: true,
        );
        if (paint) {
          sink.drawText(
            text,
            px,
            cy + size,
            size,
            color,
            maxWidth: maxWidth,
            align: align,
            bold: bold,
            italic: italic,
            family: family,
            baseLevel: paragraph.rightToLeft ? 1 : 0,
            lineAdvance: lineAdvance,
          );
        }
        height = lines * lineAdvance;
      }
    }
    return paragraph.spaceBeforePt + height + paragraph.spaceAfterPt;
  }

  static bool _hasMixedRichStyles(PmlTextParagraph paragraph) {
    String? first;
    for (final PmlTextRun run in paragraph.runs) {
      if (run.text.trim().isEmpty) continue;
      final String key =
          '${run.fontSizePt}|${run.bold}|${run.italic}|${run.color}|${run.fontFamily}';
      if (first == null) {
        first = key;
      } else if (first != key) {
        return true;
      }
    }
    return false;
  }

  static double _paintStyledParagraph(
    _PageSink sink,
    PmlTextParagraph paragraph,
    double x,
    double y,
    double maxWidth,
    _TextAlign align,
    double fallbackSize,
    String fallbackColor,
    double sizeScale, {
    double spacingFactor = 1,
    bool naturalLeading = true,
    double? fixedLeading,
    bool paint = true,
  }) {
    final List<_RichWord> words = <_RichWord>[];
    var segments = <_RichSegment>[];
    var spaceBefore = false;
    var pendingSpace = false;
    var pendingBreak = false;
    for (final PmlTextRun run in paragraph.runs) {
      // The paragraph fallback is already scaled by the caller.
      final double size = run.fontSizePt > 0
          ? run.fontSizePt * sizeScale
          : fallbackSize;

      final String color = run.color.isEmpty ? fallbackColor : run.color;
      final bool bold =
          run.bold &&
          !run.fontFamily.toLowerCase().contains('microsoft sans serif');
      for (final int cp in run.text.runes) {
        final String ch = String.fromCharCode(cp);
        if (ch == '\n') {
          if (segments.isNotEmpty) {
            words.add(_RichWord(segments, spaceBefore, pendingBreak));
            segments = <_RichSegment>[];
          }
          pendingBreak = true;
          pendingSpace = false;
          continue;
        }
        if (ch.trim().isEmpty) {
          if (segments.isNotEmpty) {
            words.add(_RichWord(segments, spaceBefore, pendingBreak));
            segments = <_RichSegment>[];
            pendingBreak = false;
          }
          pendingSpace = true;
          continue;
        }
        if (segments.isEmpty) {
          spaceBefore = pendingSpace;
          pendingSpace = false;
        }
        if (segments.isNotEmpty &&
            segments.last.matches(
              size,
              color,
              bold,
              run.italic,
              run.fontFamily,
            )) {
          segments.last.text += ch;
        } else {
          segments.add(
            _RichSegment(
              text: ch,
              size: size,
              color: color,
              bold: bold,
              italic: run.italic,
              family: run.fontFamily,
            ),
          );
        }
        if (ch == '-') {
          words.add(_RichWord(segments, spaceBefore, pendingBreak));
          segments = <_RichSegment>[];
          pendingBreak = false;
          spaceBefore = false;
        }
      }
    }
    if (segments.isNotEmpty) {
      words.add(_RichWord(segments, spaceBefore, pendingBreak));
    }
    if (words.isEmpty) return 0;

    final List<List<_RichWord>> lines = <List<_RichWord>>[];
    var line = <_RichWord>[];
    var lineWidth = 0.0;
    for (final _RichWord word in words) {
      if (word.breakBefore && line.isNotEmpty) {
        lines.add(line);
        line = <_RichWord>[];
        lineWidth = 0;
      }
      final _RichSegment? first = word.segments.isEmpty
          ? null
          : word.segments.first;
      final double gap = word.spaceBefore && first != null
          ? sink.spaceWidth(
              first.size,
              bold: first.bold,
              italic: first.italic,
              family: first.family,
            )
          : 0;
      final double wordWidth = gap + word.width(sink);
      if (line.isNotEmpty && lineWidth + wordWidth > maxWidth) {
        lines.add(line);
        line = <_RichWord>[];
        lineWidth = 0;
      }
      line.add(word);
      lineWidth += wordWidth;
    }
    if (line.isNotEmpty) lines.add(line);

    var cy = y;
    for (final List<_RichWord> current in lines) {
      var width = 0.0;
      var height = 0.0;
      for (final _RichWord word in current) {
        final _RichSegment? first = word.segments.isEmpty
            ? null
            : word.segments.first;
        if (word.spaceBefore && first != null) {
          width += sink.spaceWidth(
            first.size,
            bold: first.bold,
            italic: first.italic,
            family: first.family,
          );
        }
        width += word.width(sink);
        for (final _RichSegment segment in word.segments) {
          final double natural = !naturalLeading
              ? segment.size * 1.25
              : sink.lineHeight(
                  segment.size,
                  bold: segment.bold,
                  italic: segment.italic,
                  family: segment.family.isEmpty ? null : segment.family,
                );
          height = math.max(height, natural);
        }
      }
      var cx = x;
      if (align == _TextAlign.center) {
        cx += (maxWidth - width) / 2;
      } else if (align == _TextAlign.right) {
        cx += maxWidth - width;
      }
      for (final _RichWord word in current) {
        final _RichSegment? first = word.segments.isEmpty
            ? null
            : word.segments.first;
        if (word.spaceBefore && first != null) {
          cx += sink.spaceWidth(
            first.size,
            bold: first.bold,
            italic: first.italic,
            family: first.family,
          );
        }
        for (final _RichSegment segment in word.segments) {
          if (paint) {
            sink.drawText(
              segment.text,
              cx,
              cy + segment.size,
              segment.size,
              segment.color,
              bold: segment.bold,
              italic: segment.italic,
              family: segment.family.isEmpty ? null : segment.family,
              baseLevel: paragraph.rightToLeft ? 1 : 0,
            );
          }
          cx += sink.measureStyled(
            segment.text,
            segment.size,
            bold: segment.bold,
            italic: segment.italic,
            family: segment.family,
            baseLevel: paragraph.rightToLeft ? 1 : 0,
          );
        }
      }
      cy +=
          fixedLeading ??
          (height <= 0 ? sink.lineHeight(fallbackSize) : height) *
              spacingFactor;
    }
    return cy - y;
  }

  static PmlTextRun? _firstRichRun(PmlTextParagraph paragraph) {
    for (final PmlTextRun run in paragraph.runs) {
      if (run.text.isNotEmpty) return run;
    }
    return paragraph.runs.isEmpty ? null : paragraph.runs.first;
  }

  static String _paragraphText(PmlTextParagraph paragraph) =>
      paragraph.runs.map((PmlTextRun run) => run.text).join();

  static void _wrapShapeText(
    _PageSink sink,
    String text,
    double x,
    double y,
    double maxWidth,
    double size,
    String color, {
    double? lineAdvance,
  }) {
    final SfntFont? layoutFont = sink.pack.layoutFont;
    if (layoutFont != null) {
      var cy = y;
      for (final String para in text.split('\n')) {
        if (para.isEmpty) {
          cy += lineAdvance ?? size * 1.25;
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
        for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
          final line = lines[lineIndex];
          if (line.glyphs.isEmpty) {
            cy += lineAdvance ?? size * 1.25;
            continue;
          }
          final bool rtl = line.glyphs.any((ShapedGlyph g) => g.level.isOdd);
          var cx = rtl ? x + maxWidth - line.width : x;
          // Tm d=-1 grows glyphs up the flipped page; y is the baseline.
          final double baseline = cy + size;
          final logicalText = _brokenLineActualText(
            para,
            line,
            first: lineIndex == 0,
          );
          if (logicalText != null) sink.canvas.beginActualText(logicalText);
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
          if (logicalText != null) sink.canvas.endActualText();
          cy += lineAdvance ?? size * 1.35;
        }
      }
      return;
    }
    var cy = y;
    for (final String paragraph in text.split('\n')) {
      if (paragraph.isEmpty) {
        cy += lineAdvance ?? size * 1.25;
        continue;
      }
      final List<String> words = paragraph
          .split(RegExp(r'\s+'))
          .where((String word) => word.isNotEmpty)
          .toList(growable: false);
      var line = '';
      for (final String word in words) {
        final String next = line.isEmpty ? word : '$line $word';
        if (sink.measure(next, size) > maxWidth && line.isNotEmpty) {
          sink.drawText(line, x, cy + size, size, color);
          line = word;
          cy += lineAdvance ?? size * 1.25;
        } else {
          line = next;
        }
      }
      if (line.isNotEmpty) {
        sink.drawText(line, x, cy + size, size, color);
      }
      cy += lineAdvance ?? size * 1.35;
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

enum _ArrowDirection { down, up, left, right }

class _RichSegment {
  _RichSegment({
    required this.text,
    required this.size,
    required this.color,
    required this.bold,
    required this.italic,
    required this.family,
  });

  String text;
  final double size;
  final String color;
  final bool bold;
  final bool italic;
  final String family;

  bool matches(
    double size,
    String color,
    bool bold,
    bool italic,
    String family,
  ) =>
      this.size == size &&
      this.color == color &&
      this.bold == bold &&
      this.italic == italic &&
      this.family == family;
}

class _RichWord {
  _RichWord(this.segments, this.spaceBefore, this.breakBefore);

  final List<_RichSegment> segments;
  final bool spaceBefore;
  final bool breakBefore;

  double get size => segments.isEmpty ? 0 : segments.first.size;

  double get height {
    var result = 0.0;
    for (final _RichSegment segment in segments) {
      if (segment.size > result) result = segment.size;
    }
    return result;
  }

  double width(_PageSink sink) {
    var result = 0.0;
    for (final _RichSegment segment in segments) {
      result += sink.measureStyled(
        segment.text,
        segment.size,
        bold: segment.bold,
        italic: segment.italic,
        family: segment.family,
      );
    }
    return result;
  }
}

/// Line placement inside `maxWidth`; [auto] puts RTL lines on the right.
enum _TextAlign { auto, left, center, right }

// PDF character codes continue to select the existing shaped outlines. A
// marked replacement carries the separate logical source when joining,
// mirroring, bidi reordering or synthetic text changes those codes. Keeping
// this on the complete line preserves order across differently styled runs.
String? _wordLineActualText(LaidOutLine line) {
  if (line.glyphs.isEmpty) return null;
  final logical = List<LaidOutGlyph>.of(line.glyphs)
    ..sort((a, b) {
      final bySource = a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex);
      return bySource != 0
          ? bySource
          : a.displayOffset.compareTo(b.displayOffset);
    });
  final source = line.sourceText ?? line.sourceParagraph?.text;
  final out = StringBuffer();
  var sourceEnd = logical.first.glyph.logicalIndex;
  if (source != null &&
      line.isParagraphStart &&
      _invisibleSourceRange(source, 0, sourceEnd)) {
    out.write(source.substring(0, sourceEnd));
  }
  final displays = <(int, int, String)>{};
  for (final glyph in logical) {
    final start = glyph.glyph.logicalIndex;
    final end = glyph.logicalEnd;
    if (source != null &&
        sourceEnd < start &&
        _invisibleSourceRange(source, sourceEnd, start)) {
      // A sparse host layout must not borrow visible text from another run.
      // Only omitted source controls and unselected soft hyphens bridge gaps.
      out.write(source.substring(sourceEnd, start));
    }
    if (glyph.displayText case final String display) {
      if (displays.add((start, end, display))) {
        // Generated note labels retain their displayed number; synthetic
        // capitals and discretionary hyphens retain their authored source.
        out.write(glyph.actualText ?? display);
      }
    } else if (source != null &&
        start >= 0 &&
        end >= start &&
        end <= source.length) {
      out.write(source.substring(start, end));
    } else if (glyph.glyph.codePoint >= 32) {
      out.writeCharCode(glyph.glyph.codePoint);
    }
    sourceEnd = math.max(sourceEnd, end);
  }
  if (source != null && sourceEnd >= 0 && sourceEnd <= source.length) {
    final end = _afterOmittedLineEnd(source, sourceEnd);
    out.write(source.substring(sourceEnd, end));
  }
  final text = out.toString();
  final painted = String.fromCharCodes(
    line.glyphs
        .where((glyph) => glyph.glyph.codePoint >= 32)
        .map((glyph) => glyph.glyph.codePoint),
  );
  return text == painted ? null : text;
}

String? _brokenLineActualText(
  String source,
  BrokenLine line, {
  required bool first,
}) {
  var start = line.logicalStart;
  final end = line.logicalEnd;
  if (start < 0 || end < start || end > source.length) return null;
  if (first && _invisibleSourceRange(source, 0, start)) start = 0;
  final text = source.substring(start, _afterOmittedLineEnd(source, end));
  final painted = String.fromCharCodes(
    line.glyphs
        .where((glyph) => glyph.codePoint >= 32)
        .map((glyph) => glyph.codePoint),
  );
  return text == painted ? null : text;
}

bool _invisibleSourceRange(String source, int start, int end) =>
    start >= 0 &&
    end >= start &&
    end <= source.length &&
    source.substring(start, end).runes.every(_omittedSourceControl);

bool _omittedSourceControl(int codePoint) =>
    codePoint == 0x00ad || Uax9Bidi.isInvisibleFormat(codePoint);

int _afterOmittedLineEnd(String source, int start) {
  var end = start;
  while (end < source.length) {
    final cp = source.codeUnitAt(end);
    // These spaces are trimmed by LineBreaker; they still separate authored
    // words when copied across a visual wrap. Tabs retain their own glyph.
    if (!_omittedSourceControl(cp) &&
        cp != 0x20 &&
        cp != 0x2000 &&
        cp != 0x3000) {
      break;
    }
    end++;
  }
  return end;
}

class _FontPack {
  _FontPack(this.set, this.codePoints, this.layoutFont);

  final OfficeFontSet set;
  final Set<int> codePoints;
  final SfntFont? layoutFont;
  final List<PdfEmbeddedFace> faces = <PdfEmbeddedFace>[];
  final Map<(SfntFont, double), FontMetrics> _metrics = {};

  SfntFont? fontFor(
    int cp, {
    String? family,
    int weight = 400,
    bool italic = false,
  }) {
    final face = set.faceFor(
      cp,
      family: family,
      weight: weight,
      italic: italic,
    );
    if (face != null) return face;
    final nominal = ArabicShaper.nominalOf(cp);
    return nominal == null
        ? null
        : set.faceFor(nominal, family: family, weight: weight, italic: italic);
  }

  int glyphIdOf(
    int cp, {
    String? family,
    int weight = 400,
    bool italic = false,
  }) {
    final face = fontFor(cp, family: family, weight: weight, italic: italic);
    if (face == null) return 0;
    final gid = face.glyphIdFor(cp);
    return gid != 0 ? gid : face.glyphIdFor(ArabicShaper.nominalOf(cp) ?? cp);
  }

  double widthOf(
    int cp,
    double size, {
    String? family,
    int weight = 400,
    bool italic = false,
  }) {
    final face = fontFor(cp, family: family, weight: weight, italic: italic);
    if (face == null || size <= 0) {
      final byte = PdfStd14.winAnsiByte(cp);
      return byte == null
          ? size * 0.5
          : PdfStd14.width('Helvetica', byte) / 1000 * size;
    }
    final gid = glyphIdOf(cp, family: family, weight: weight, italic: italic);
    return _metrics
        .putIfAbsent((
          face,
          size,
        ), () => FontMetrics(font: face, fontSizePoints: size))
        .advanceWidth(gid);
  }

  static _FontPack build(OfficeFontSet set, Set<int> cps) =>
      _FontPack(set, <int>{
        ...cps,
        for (final cp in cps)
          if (ArabicShaper.nominalOf(cp) case final int nominal) nominal,
      }, set.faceFor(0x20) ?? set.embeddable.firstOrNull);

  /// Embed only faces actually painted, always choosing the same source face
  /// that supplied layout metrics. Looking up a character in any existing
  /// subset first would erase family and style differences for shared glyphs.
  ({PdfEmbeddedFace embedded, OfficeFontFace face})? faceForCodePoint(
    int cp, {
    String? family,
    int weight = 400,
    bool italic = false,
  }) {
    final choice = set.resolve(
      cp,
      family: family,
      weight: weight,
      italic: italic,
    );
    if (choice == null) return null;
    for (final embedded in faces) {
      if (identical(embedded.source, choice.font) &&
          embedded.subset.unicodeToNewGlyph.containsKey(cp)) {
        return (embedded: embedded, face: choice);
      }
    }
    final alreadyEncoded = <int>{
      for (final embedded in faces)
        if (identical(embedded.source, choice.font))
          ...embedded.subset.unicodeToNewGlyph.keys,
    };
    final used = <int>{cp};
    for (final point in codePoints) {
      if (used.length == PdfCidEncoding.maxCharacters) break;
      if (!alreadyEncoded.contains(point) &&
          choice.font.glyphIdFor(point) != 0) {
        used.add(point);
      }
    }
    // A late generated label gets a new immutable subset if its character was
    // not collected initially. A resource also contains at most 65535 Unicode
    // mappings; larger repertoires use another resource with distinct CIDs.
    // Never renumber character codes already emitted to PDF.
    final subset = FontSubsetter(choice.font).subset(used);
    final embedded = PdfEmbeddedFace(
      subset: subset,
      source: choice.font,
      encoding: PdfCidEncoding.fromSubset(subset),
      // F2 is reserved for the Standard 14 Helvetica fallback.
      resourceName: faces.isEmpty ? 'F1' : 'F${faces.length + 2}',
    );
    faces.add(embedded);
    return (embedded: embedded, face: choice);
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
      family: g.fontFamily,
      advance: g.advance,
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
    bool italic = false,
    String? family,
    int? baseLevel,
    double? lineAdvance,
  }) {
    if (text.isEmpty || size <= 0) {
      return;
    }
    if (pack.layoutFont != null ||
        _needsAuthoredLtr(text, baseLevel) ||
        lineAdvance != null) {
      final List<BrokenLine> lines = _layoutLines(
        text,
        size,
        maxWidth: maxWidth ?? 1e9,
        bold: bold,
        italic: italic,
        family: family,
        baseLevel: baseLevel,
      );
      var cy = y;
      for (int i = 0; i < lines.length; i++) {
        final BrokenLine line = lines[i];
        if (line.glyphs.isEmpty) {
          cy += lineAdvance ?? size * 1.25;
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
        final logicalText = _brokenLineActualText(text, line, first: i == 0);
        if (logicalText != null) canvas.beginActualText(logicalText);
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
            italic: italic,
            family: family,
            advance: g.advance,
          );
          cx += g.advance;
        }
        if (logicalText != null) canvas.endActualText();
        cy += lineAdvance ?? size * 1.25;
      }
      return;
    }
    if (_winAnsiOnly(text)) {
      canvas.showLatin(x: x, y: y, fontSize: size, text: text, color: color);
      return;
    }
    var cx = x;
    for (final int cp in text.runes) {
      if (cp < 32) continue;
      final advance = pack.widthOf(
        cp,
        size,
        family: family,
        weight: bold ? 700 : 400,
        italic: italic,
      );
      _emit(
        oldGid: 0,
        codePoint: cp,
        x: cx,
        y: y,
        size: size,
        color: color,
        family: family,
        bold: bold,
        italic: italic,
        advance: advance,
      );
      cx += advance;
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
    String? family,
    double? advance,
  }) {
    // Controls and lam-alef's zero-width shaping placeholder are not missing
    // printable characters.
    if (codePoint < 32) return;
    final int? nominal = ArabicShaper.nominalOf(codePoint);
    var selected = pack.faceForCodePoint(
      codePoint,
      family: family,
      weight: bold ? 700 : 400,
      italic: italic,
    );
    var drawable = codePoint;
    if (selected == null && nominal != null) {
      selected = pack.faceForCodePoint(
        nominal,
        family: family,
        weight: bold ? 700 : 400,
        italic: italic,
      );
      if (selected != null) drawable = nominal;
    }
    if (selected != null) {
      final face = selected.embedded;
      final cid =
          face.encoding?.unicodeToCid[drawable] ??
          face.subset.unicodeToNewGlyph[drawable] ??
          0;
      if (cid != 0) {
        if (pack.set.faces.isNotEmpty) {
          pack.set.diagnostics?.reportSubstitution(
            family,
            selected.face.family,
          );
        }
        canvas.showGlyph(
          x: x,
          y: y,
          fontSize: size,
          glyphId: cid,
          color: color,
          // Real bold/italic cuts already carry their own outlines. Simulate
          // only an unavailable style, retaining legacy single-face behavior.
          italic: italic && !selected.face.italic,
          bold: bold && selected.face.weight < 600,
          fontName: face.resourceName,
        );
        return;
      }
    }
    if (_isWinAnsi(codePoint)) {
      pack.set.diagnostics?.reportSubstitution(family, 'Helvetica');
      canvas.showLatin(
        x: x,
        y: y,
        fontSize: size,
        text: String.fromCharCode(codePoint),
        color: color,
      );
      return;
    }
    pack.set.diagnostics?.reportMissing(nominal ?? codePoint);
    // Keep the layout advance and make missing coverage visible even when no
    // fallback font can draw U+FFFD. The host can localize a coverage warning
    // from the bounded diagnostics without parsing a PDF.
    final boxWidth = math.max(size * 0.25, (advance ?? size * 0.5) * 0.8);
    canvas.save();
    canvas.setLineWidth(math.max(0.35, size * 0.04));
    canvas.strokeRect(x, y - size * 0.75, boxWidth, size * 0.75, color);
    canvas.restore();
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

  static final RegExp _letters = RegExp(r'\p{L}', unicode: true);

  static bool _needsAuthoredLtr(String text, int? baseLevel) =>
      baseLevel == 0 && !_letters.hasMatch(text);

  /// Use one line plan for numeric drawing, wrapping, alignment and height.
  /// A nonpainting LTR override keeps explicitly LTR number groups in authored
  /// order; the breaker otherwise resolves their separating spaces as RTL.
  /// The override character is removed from every source offset, so
  /// it cannot leak into PDF text extraction or the document's authored text.
  List<BrokenLine> _layoutLines(
    String text,
    double size, {
    required double maxWidth,
    bool bold = false,
    bool italic = false,
    String? family,
    int? baseLevel,
    bool justify = true,
  }) {
    final bool anchor = _needsAuthoredLtr(text, baseLevel);
    final SfntFont? layoutFont = pack.layoutFont;
    final List<BrokenLine> lines = LineBreaker.breakLines(
      text: anchor ? '\u202d$text' : text,
      baseLevel: baseLevel,
      maxWidth: maxWidth,
      widthOf: (int cp) => pack.widthOf(
        cp,
        size,
        family: family,
        weight: bold ? 700 : 400,
        italic: italic,
      ),
      glyphIdOf: (int cp) => pack.glyphIdOf(
        cp,
        family: family,
        weight: bold ? 700 : 400,
        italic: italic,
      ),
      // These slide paragraphs are left/center/right aligned, not justified.
      // Their measured width must match the advances that are actually drawn.
      justify: anchor ? false : justify,
      breakLongWords: anchor,
      markAttachOf: layoutFont == null
          ? null
          : GposMarkToBase.fnFor(
              layoutFont,
              size,
              faceFor: (int cp) => pack.fontFor(
                cp,
                family: family,
                weight: bold ? 700 : 400,
                italic: italic,
              ),
            ),
    );
    if (!anchor) return lines;
    return <BrokenLine>[
      for (final BrokenLine line in lines)
        BrokenLine(
          glyphs: <ShapedGlyph>[
            for (final ShapedGlyph glyph in line.glyphs)
              ShapedGlyph(
                codePoint: glyph.codePoint,
                glyphId: glyph.glyphId,
                advance: glyph.advance,
                logicalIndex: math.max(0, glyph.logicalIndex - 1),
                level: glyph.level,
                isSpace: glyph.isSpace,
                paintDx: glyph.paintDx,
                paintDy: glyph.paintDy,
                isDiscretionaryHyphen: glyph.isDiscretionaryHyphen,
                sourceLength: glyph.sourceLength,
              ),
          ],
          width: line.width,
          logicalStart: math.max(0, line.logicalStart - 1),
          logicalEnd: math.max(0, line.logicalEnd - 1),
          justificationRatio: line.justificationRatio,
        ),
    ];
  }

  double lineHeight(
    double size, {
    bool bold = false,
    bool italic = false,
    String? family,
  }) {
    final SfntFont? font = pack.fontFor(
      65,
      family: family,
      weight: bold ? 700 : 400,
      italic: italic,
    );
    if (font == null || font.unitsPerEm <= 0) return size * 1.25;
    final double ratio =
        (font.ascender - font.descender + font.lineGap) / font.unitsPerEm;
    return size * math.max(1.0, ratio);
  }

  /// Number of laid-out lines for [text] at [size].
  double plainWidth(
    String text,
    double size, {
    bool bold = false,
    bool italic = false,
    String? family,
  }) {
    var width = 0.0;
    for (final int cp in text.runes) {
      if (cp < 32) continue;
      width += pack.widthOf(
        cp,
        size,
        family: family,
        weight: bold ? 700 : 400,
        italic: italic,
      );
    }
    return width;
  }

  void drawPlainLtr(
    String text,
    double x,
    double baseline,
    double size,
    String color, {
    bool bold = false,
    bool italic = false,
    String? family,
  }) {
    var cx = x;
    for (final int cp in text.runes) {
      if (cp < 32) continue;
      final double advance = pack.widthOf(
        cp,
        size,
        family: family,
        weight: bold ? 700 : 400,
        italic: italic,
      );
      _emit(
        oldGid: 0,
        codePoint: cp,
        x: cx,
        y: baseline,
        size: size,
        color: color,
        bold: bold,
        italic: italic,
        family: family,
        advance: advance,
      );
      cx += advance;
    }
  }

  int lineCount(
    String text,
    double size, {
    double? maxWidth,
    bool bold = false,
    bool italic = false,
    String? family,
    int? baseLevel,
    bool forceLayout = false,
  }) {
    if (pack.layoutFont == null && !_needsAuthoredLtr(text, baseLevel)) {
      return math.max(1, text.split('\n').length);
    }
    return math.max(
      1,
      _layoutLines(
        text,
        size,
        maxWidth: maxWidth ?? 1e9,
        bold: bold,
        italic: italic,
        family: family,
        baseLevel: baseLevel,
      ).length,
    );
  }

  /// Advance width of a single space for line layout.
  double spaceWidth(
    double size, {
    bool bold = false,
    bool italic = false,
    String? family,
  }) => pack.widthOf(
    32,
    size,
    family: family,
    weight: bold ? 700 : 400,
    italic: italic,
  );

  /// Measure using the actual run face rather than the regular fallback.
  double measureStyled(
    String text,
    double size, {
    bool bold = false,
    bool italic = false,
    String? family,
    int? baseLevel,
  }) {
    final List<BrokenLine> lines = _layoutLines(
      text,
      size,
      baseLevel: baseLevel,
      maxWidth: 1e9,
      bold: bold,
      italic: italic,
      family: family,
      justify: false,
    );
    return lines.fold<double>(0, (width, line) => math.max(width, line.width));
  }

  /// measure API.
  double measure(String text, double size) {
    final lines = LineBreaker.breakLines(
      text: text,
      maxWidth: 1e9,
      widthOf: (cp) => pack.widthOf(cp, size),
      glyphIdOf: pack.glyphIdOf,
      justify: false,
    );
    return lines.fold<double>(0, (width, line) => math.max(width, line.width));
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
        extGStates: canvas.alphaStates,
      ),
    );
  }
}
