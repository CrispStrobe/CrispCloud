import 'dart:typed_data';

import '../pdf/file/model/pdf_file.dart';
import '../sheet/formula/formula_eval.dart';
import '../sheet/model/sml_workbook.dart';
import '../sheet/serial/sheet_serial.dart';
import '../slide/model/pml_presentation.dart';
import '../slide/serial/slide_serial.dart';
import '../visual/sheet_chart_data.dart';
import '../word/layout/word_layout.dart';
import '../word/model/wml_document.dart';
import '../word/model/word_tree.dart';
import '../word/serial/odt_document_reader.dart';
import '../word/serial/word_deserializer.dart';
import 'office_open_types.dart';
import 'repair/office_repair.dart';

/// Decodes an Office package on the current isolate.
Future<Object> decodeOfficeOpen(
  Uint8List bytes,
  String? password,
  String kind,

  /// Function API.
  void Function(OfficeOpenProgress progress) emit, {
  String? formulaLocale,
}) async {
  /// emit API.
  emit(const OfficeOpenProgress(value: 0.16, stage: 'archive'));
  if (kind == 'pdf') {
    emit(const OfficeOpenProgress(value: 0.42, stage: 'xref'));
    final PdfFile file = PdfFile.open(bytes, password: password);
    emit(const OfficeOpenProgress(value: 0.72, stage: 'display'));
    final PdfOpenPayload payload = PdfOpenPayload(
      file: file,
      lists: file.displayLists(),
    );
    emit(const OfficeOpenProgress(value: 0.97, stage: 'apply'));
    return payload;
  }

  final documentOnly = kind == 'word-document';
  if ((kind == 'word' || documentOnly) && OdtDocumentReader.isOdt(bytes)) {
    emit(const OfficeOpenProgress(value: 0.42, stage: 'document'));
    final WmlDocument document = await OdtDocumentReader.readBytes(bytes);
    if (documentOnly) {
      emit(const OfficeOpenProgress(value: 0.92, stage: 'apply'));
      return document;
    }
    emit(const OfficeOpenProgress(value: 0.25, stage: 'layout'));
    final LaidOutDocument laidOut = WordLayoutEngine(
      font: null,
    ).layout(document);
    emit(const OfficeOpenProgress(value: 0.97, stage: 'apply'));
    return WordOpenPayload(document: document, laidOut: laidOut);
  }

  /// package API.
  final package = OfficeRepair.open(bytes, password: password);

  /// emit API.
  emit(const OfficeOpenProgress(value: 0.42, stage: 'document'));
  switch (kind) {
    case 'word-document':
      final WmlDocument document = WordDeserializer().read(package);
      int blocks = 0;
      for (final WmlSection section in document.sections) {
        blocks += WordTree.visibleBlocks(section.blocks).length;
      }
      final int notes = document.footnotes.length + document.endnotes.length;
      emit(
        OfficeOpenProgress(
          value: 0.42,
          stage: 'document',
          detail:
              '${document.sections.length} sections · '
              '$blocks blocks · $notes notes',
        ),
      );
      emit(const OfficeOpenProgress(value: 0.92, stage: 'apply'));
      return document;
    case 'word':
      final WmlDocument document = WordDeserializer().read(package);
      emit(const OfficeOpenProgress(value: 0.25, stage: 'layout'));
      final LaidOutDocument laidOut = WordLayoutEngine(
        font: null,
        onProgress: (progress) {
          final fraction = progress.fraction.clamp(0.0, 1.0);
          emit(
            OfficeOpenProgress(
              value: 0.25 + 0.70 * fraction,
              stage: 'layout',
              detail:
                  'Layout: ${progress.pages} pages · '
                  '${progress.blocksDone}/${progress.blocksTotal} blocks · '
                  '${progress.notesDone}/${progress.notesTotal} notes',
            ),
          );
        },
      ).layout(document);
      emit(const OfficeOpenProgress(value: 0.92, stage: 'apply'));
      return WordOpenPayload(document: document, laidOut: laidOut);
    case 'sheet':
      final SmlWorkbook workbook = SheetDeserializer().read(package)
        ..formulaLocale = formulaLocale;
      emit(const OfficeOpenProgress(value: 0.72, stage: 'formulas'));
      FormulaEvaluator.recalculate(workbook);
      SheetChartData.refreshWorkbook(workbook);
      emit(const OfficeOpenProgress(value: 0.92, stage: 'apply'));
      return workbook;
    case 'slide':
      final PmlPresentation presentation = SlideDeserializer().read(package);
      emit(const OfficeOpenProgress(value: 0.92, stage: 'apply'));
      return presentation;
    default:
      throw StateError('Unknown open kind: $kind');
  }
}
