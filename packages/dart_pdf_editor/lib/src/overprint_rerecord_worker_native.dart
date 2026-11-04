// Extracted from retained_scene.dart in dart_pdf_editor 14.0.0.
// See UPSTREAM.md for provenance and patch details.
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const overprintRerecordSupported = true;

Future<Uint8List?> rerecordOverprintCommands(
  Uint8List bytes, {
  required int pageIndex,
  required int maxDimension,
  required bool annotations,
  required Set<String> hiddenAnnotationSubtypes,
  List<int>? populatedRanges,
  double? maxImagePixelRatio,
}) {
  // Keep the original bounded transfer and background interpretation. Only
  // serializable inputs are captured; the retained scene stays on the UI
  // isolate, and this library does not import dart:ui or any Flutter widgets.
  final source = TransferableTypedData.fromList([bytes]);
  return Isolate.run(() {
    final document = PdfDocument.open(source.materialize().asUint8List(),
        populatedRanges: populatedRanges);
    if (pageIndex >= document.pageCount) return null;
    final retryPage = document.page(pageIndex);
    final recorder = RecordingPdfDevice();
    final interpreter = PdfInterpreter(
      cos: document.cos,
      device: recorder,
      overprintMaxDimension: maxDimension,
    )..drawPageContent(retryPage, retryPage.contentBytes());
    if (annotations) {
      interpreter.drawAnnotations(retryPage,
          skipSubtypes: hiddenAnnotationSubtypes);
    }
    return serializeCommands(
      recorder.commands,
      cos: document.cos,
      decodeImages: true,
      maxImagePixelRatio: maxImagePixelRatio,
      pageRasterPixels: pdfPageRasterPixels(
        retryPage.cropBox,
        maxImagePixelRatio,
      ),
    );
  });
}
