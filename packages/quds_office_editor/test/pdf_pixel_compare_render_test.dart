import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/editor_pdf/paint_pdf_display_list.dart';
import 'package:quds_office_editor/src/editor_pdf/pdf_font_faces.dart';
import 'package:quds_office_editor/src/editor_pdf/pdf_raster.dart';
import 'package:quds_office_editor/src/embed/office_host_fonts.dart';
import 'package:quds_office_engine/pdf_file.dart';

/// Renders [al_tahreer_profile.pdf] page-by-page for Poppler comparison.
///
/// Output: `/tmp/quds_pdf_compare/ours/page-NN.png` at 1 PDF-pt ≈ 1 CSS px
/// (matches `pdftoppm -r 72`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final File pdf = File('/home/mohammed/Desktop/al_tahreer_profile.pdf');

  test(
    'render al_tahreer pages for pixel compare',
    () async {
      await OfficeHostFonts.ensureRegistered();

      final Directory out = Directory('/tmp/quds_pdf_compare/ours')
        ..createSync(recursive: true);
      final PdfFile file = PdfFile.open(pdf.readAsBytesSync());
      // ignore: avoid_print
      print('pages=${file.pageCount}');

      for (int i = 0; i < file.pageCount; i++) {
        final PdfDisplayList list = file.displayList(i);
        await _warmFonts(list);
        final Map<int, ui.Image> images = await _decodeImages(list);
        // Match Poppler `pdftoppm` pixel size: ceil(pts * dpi/72) at 72dpi.
        final int w = list.page.width.ceil().clamp(1, 4000);
        final int h = list.page.height.ceil().clamp(1, 4000);
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas canvas = Canvas(recorder);
        canvas.drawColor(const Color(0xFFFFFFFF), BlendMode.src);
        PaintPdfDisplayList.paint(
          canvas,
          list,
          decodeImage: (Uint8List bytes, bool _) =>
              images[identityHashCode(bytes)],
        );
        final ui.Image image = await recorder.endRecording().toImage(w, h);
        final ByteData? png = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        image.dispose();
        for (final ui.Image img in images.values) {
          img.dispose();
        }
        expect(png, isNotNull);
        final String name = 'page-${(i + 1).toString().padLeft(2, '0')}.png';
        File('${out.path}/$name').writeAsBytesSync(png!.buffer.asUint8List());
        // ignore: avoid_print
        print('wrote $name ${w}x$h ops=${list.ops.length}');
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: pdf.existsSync() ? false : 'needs ${pdf.path} (local compare tool)',
  );
}

Future<void> _warmFonts(PdfDisplayList list) async {
  final List<Completer<void>> waits = <Completer<void>>[];
  final Set<int> seen = <int>{};
  for (final PdfPaintOp op in list.ops) {
    if (op is! PdfDrawText || op.fontBytes == null) {
      continue;
    }
    final int key = identityHashCode(op.fontBytes);
    if (!seen.add(key)) {
      continue;
    }
    if (PdfFontFaces.isEmbedded(
      PdfFontFaces.familyFor(op.fontBytes, op.fontFamily),
    )) {
      continue;
    }
    final Completer<void> c = Completer<void>();
    waits.add(c);
    PdfFontFaces.ensure(op.fontBytes!, () {
      if (!c.isCompleted) {
        c.complete();
      }
    });
  }
  if (waits.isEmpty) {
    return;
  }
  await Future.wait(
    waits.map((Completer<void> c) => c.future),
  ).timeout(const Duration(seconds: 20), onTimeout: () => <void>[]);
}

Future<Map<int, ui.Image>> _decodeImages(PdfDisplayList list) async {
  final Map<int, ui.Image> out = <int, ui.Image>{};
  final List<Future<void>> waits = <Future<void>>[];
  final Set<int> seen = <int>{};
  for (final PdfPaintOp op in list.ops) {
    if (op is! PdfDrawImage || op.placeholder || op.bytes.isEmpty) {
      continue;
    }
    final int key = identityHashCode(op.bytes);
    if (!seen.add(key)) {
      continue;
    }
    final Completer<void> c = Completer<void>();
    waits.add(c.future);
    PdfRaster.decode(op, (ui.Image image) {
      out[key] = image;
      if (!c.isCompleted) {
        c.complete();
      }
    });
  }
  if (waits.isNotEmpty) {
    await Future.wait(waits).timeout(const Duration(seconds: 60));
  }
  return out;
}
