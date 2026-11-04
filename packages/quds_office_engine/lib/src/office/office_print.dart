import 'dart:typed_data';

import '../fonts/office_font_set.dart';
import '../fonts/sfnt_parser.dart';
import '../pdf/file/io/pdf_incremental_save.dart';
import '../pdf/file/model/pdf_file.dart';
import '../pdf/office_pdf_export.dart';
import '../sheet/model/sml_workbook.dart';
import '../slide/model/pml_presentation.dart';
import '../word/layout/word_layout.dart';
import '../word/model/wml_document.dart';

/// Shared print / PDF range used by every host.
class OfficePrintSettings {
  /// OfficePrintSettings API.
  const OfficePrintSettings({
    this.pageFrom = 1,
    this.pageTo,
    this.copies = 1,
    this.landscape,
    this.title = '',
  });

  /// 1-based inclusive start page (or sheet / slide).
  final int pageFrom;

  /// Inclusive end. `null` means the last page.
  final int? pageTo;

  /// copies API.
  final int copies;

  /// landscape API.
  final bool? landscape;

  /// title API.
  final String title;
}

/// Compiles a printable PDF from the live models.
abstract final class OfficePrint {
  /// word API.
  static Uint8List word(
    WmlDocument document, {
    OfficePrintSettings settings = const OfficePrintSettings(),
    SfntFont? font,
    OfficeFontSet? fonts,
  }) {
    return OfficePdfExport.word(
      document,
      font: font,
      fonts: fonts,
      title: settings.title.isEmpty ? 'Document' : settings.title,
      pageFrom: settings.pageFrom,
      pageTo: settings.pageTo,
    );
  }

  /// workbook API.
  static Uint8List workbook(
    SmlWorkbook workbook, {
    OfficePrintSettings settings = const OfficePrintSettings(),
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSheetPrintOptions? options,
  }) {
    PdfSheetPrintOptions sheetOptions = options ?? const PdfSheetPrintOptions();
    if (settings.landscape == true) {
      sheetOptions = PdfSheetPrintOptions(
        pageWidth: sheetOptions.pageHeight,
        pageHeight: sheetOptions.pageWidth,
        margin: sheetOptions.margin,
        showGridlines: sheetOptions.showGridlines,
        showHeadings: sheetOptions.showHeadings,
        fitToPage: sheetOptions.fitToPage,
      );
    }
    return OfficePdfExport.workbook(
      workbook,
      font: font,
      fonts: fonts,
      title: settings.title.isEmpty ? 'Workbook' : settings.title,
      options: sheetOptions,
      sheetFrom: settings.pageFrom,
      sheetTo: settings.pageTo,
    );
  }

  /// presentation API.
  static Uint8List presentation(
    PmlPresentation presentation, {
    OfficePrintSettings settings = const OfficePrintSettings(),
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSlideExportMode mode = PdfSlideExportMode.slides,
  }) {
    return OfficePdfExport.presentation(
      presentation,
      font: font,
      fonts: fonts,
      title: settings.title.isEmpty ? 'Presentation' : settings.title,
      mode: mode,
      slideFrom: settings.pageFrom,
      slideTo: settings.pageTo,
    );
  }

  /// pdfFile API.
  static Uint8List pdfFile(
    PdfFile file, {
    OfficePrintSettings settings = const OfficePrintSettings(),
  }) {
    if (file.dirtyPages.isEmpty &&
        settings.pageFrom <= 1 &&
        (settings.pageTo == null || settings.pageTo! >= file.pageCount)) {
      return file.originalBytes;
    }
    return PdfIncrementalSave.write(
      originalBytes: file.originalBytes,
      file: file,
    );
  }

  /// Laid-out Word pages for a WYSIWYG print preview, already clamped.
  static List<LaidOutPage> wordPreview(
    WmlDocument document, {
    OfficePrintSettings settings = const OfficePrintSettings(),
    SfntFont? font,
  }) {
    final LaidOutDocument laid = WordLayoutEngine(font: font).layout(document);
    final (int from, int to) = clampRange(
      settings: settings,
      length: laid.pages.length,
    );
    return laid.pages.sublist(from - 1, to);
  }

  /// Clamps a 1-based range to [length].
  static (int from, int to) clampRange({
    required OfficePrintSettings settings,
    required int length,
  }) {
    if (length <= 0) {
      return (1, 1);
    }
    final int from = settings.pageFrom.clamp(1, length);
    final int to = (settings.pageTo ?? length).clamp(from, length);
    return (from, to);
  }
}
