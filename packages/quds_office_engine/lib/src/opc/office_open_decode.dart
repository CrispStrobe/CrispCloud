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
import '../word/serial/word_deserializer.dart';
import 'office_open_types.dart';
import 'repair/office_repair.dart';

/// Decodes an Office package on the current isolate.
Object decodeOfficeOpen(
  Uint8List bytes,
  String? password,
  String kind,

  /// Function API.
  void Function(OfficeOpenProgress progress) emit,
) {
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
    emit(const OfficeOpenProgress(value: 0.92, stage: 'apply'));
    return payload;
  }

  /// package API.
  final package = OfficeRepair.open(bytes, password: password);

  /// emit API.
  emit(const OfficeOpenProgress(value: 0.42, stage: 'document'));
  switch (kind) {
    case 'word':
      final WmlDocument document = WordDeserializer().read(package);
      emit(const OfficeOpenProgress(value: 0.72, stage: 'layout'));
      final LaidOutDocument laidOut = WordLayoutEngine(
        font: null,
      ).layout(document);
      emit(const OfficeOpenProgress(value: 0.92, stage: 'apply'));
      return WordOpenPayload(document: document, laidOut: laidOut);
    case 'sheet':
      final SmlWorkbook workbook = SheetDeserializer().read(package);
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
