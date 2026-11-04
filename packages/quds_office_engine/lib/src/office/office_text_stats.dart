import '../pdf/file/model/pdf_file.dart';
import '../pdf/file/text/pdf_extract.dart';
import '../sheet/model/sml_workbook.dart';
import '../slide/model/pml_presentation.dart';
import '../word/layout/word_layout.dart';
import '../word/model/wml_document.dart';

/// Counts that Word / Excel / PowerPoint hosts show in a status bar.
class OfficeTextStats {
  /// OfficeTextStats API.
  const OfficeTextStats({
    this.words = 0,
    this.characters = 0,
    this.charactersNoSpaces = 0,
    this.paragraphs = 0,
    this.pages = 0,
    this.cells = 0,
    this.slides = 0,
    this.notes = 0,
  });

  /// words API.
  final int words;

  /// characters API.
  final int characters;

  /// charactersNoSpaces API.
  final int charactersNoSpaces;

  /// paragraphs API.
  final int paragraphs;

  /// pages API.
  final int pages;

  /// cells API.
  final int cells;

  /// slides API.
  final int slides;

  /// notes API.
  final int notes;

  /// ofWord API.
  static OfficeTextStats ofWord(
    WmlDocument document, {
    LaidOutDocument? laidOut,
  }) {
    var words = 0;
    var chars = 0;
    var noSpace = 0;
    var paras = 0;
    for (final WmlParagraph paragraph in document.paragraphs) {
      paras++;
      final _Count count = _count(paragraph.text);
      words += count.words;
      chars += count.characters;
      noSpace += count.charactersNoSpaces;
    }
    return OfficeTextStats(
      words: words,
      characters: chars,
      charactersNoSpaces: noSpace,
      paragraphs: paras,
      pages: laidOut?.pages.length ?? 0,
    );
  }

  /// ofWorkbook API.
  static OfficeTextStats ofWorkbook(SmlWorkbook workbook) {
    var words = 0;
    var chars = 0;
    var noSpace = 0;
    var cells = 0;
    for (final SmlWorksheet sheet in workbook.sheets) {
      for (final SmlCell cell in sheet.allCells) {
        if (!cell.hasContent) {
          continue;
        }
        cells++;
        final _Count count = _count(cell.asString);
        words += count.words;
        chars += count.characters;
        noSpace += count.charactersNoSpaces;
      }
    }
    return OfficeTextStats(
      words: words,
      characters: chars,
      charactersNoSpaces: noSpace,
      cells: cells,
    );
  }

  /// ofPdf API.
  static OfficeTextStats ofPdf(PdfFile file) {
    final String text = PdfExtract.documentText(file);
    final _Count count = _count(text);
    return OfficeTextStats(
      words: count.words,
      characters: count.characters,
      charactersNoSpaces: count.charactersNoSpaces,
      paragraphs: PdfExtract.paragraphs(file).length,
      pages: file.pageCount,
    );
  }

  /// ofPresentation API.
  static OfficeTextStats ofPresentation(PmlPresentation presentation) {
    var words = 0;
    var chars = 0;
    var noSpace = 0;
    var notes = 0;
    for (final PmlSlide slide in presentation.slides) {
      final _Count note = _count(slide.notes);
      notes += note.words;
      words += note.words;
      chars += note.characters;
      noSpace += note.charactersNoSpaces;
      for (final PmlShape shape in slide.shapes) {
        final _Count body = _count(shape.text);
        words += body.words;
        chars += body.characters;
        noSpace += body.charactersNoSpaces;
        final PmlTable? table = shape.table;
        if (table == null) {
          continue;
        }
        for (final List<PmlTableCell> row in table.rows) {
          for (final PmlTableCell cell in row) {
            final _Count cellCount = _count(cell.text);
            words += cellCount.words;
            chars += cellCount.characters;
            noSpace += cellCount.charactersNoSpaces;
          }
        }
      }
    }
    return OfficeTextStats(
      words: words,
      characters: chars,
      charactersNoSpaces: noSpace,
      slides: presentation.slides.length,
      notes: notes,
    );
  }

  static _Count _count(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const _Count();
    }
    final int words = trimmed
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .length;
    var noSpace = 0;
    for (int i = 0; i < text.length; i++) {
      final int cu = text.codeUnitAt(i);
      if (cu != 0x20 && cu != 0x09 && cu != 0x0A && cu != 0x0D) {
        noSpace++;
      }
    }
    return _Count(
      words: words,
      characters: text.length,
      charactersNoSpaces: noSpace,
    );
  }
}

class _Count {
  const _Count({
    this.words = 0,
    this.characters = 0,
    this.charactersNoSpaces = 0,
  });

  final int words;
  final int characters;
  final int charactersNoSpaces;
}
