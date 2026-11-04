import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/overprint_rerecord_worker.dart' as worker;
import 'package:dart_pdf_editor/src/overprint_rerecord_worker_stub.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'support/test_pdf.dart';

void main() {
  test('the browser worker declines only the optional overprint retry',
      () async {
    expect(web.overprintRerecordSupported, isFalse);
    expect(
      await web.rerecordOverprintCommands(
        buildTestPdf(),
        pageIndex: 0,
        maxDimension: 768,
        annotations: true,
        hiddenAnnotationSubtypes: {},
      ),
      isNull,
    );
    expect(worker.overprintRerecordSupported, !kIsWeb);
  });

  testWidgets('native retry preserves scene commands and render options',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildTestPdf()).page(0);
      final source = await PdfRetainedScene.record(
        page,
        maxImagePixelRatio: 1.5,
        imageDecodeHeadroom: 1,
      );
      addTearDown(source.dispose);
      final future = source.rerecordWithOverprintMaxDimension(768);
      if (kIsWeb) {
        expect(future, isNull);
        return;
      }
      expect(future, isNotNull);
      final retry = await future!;
      addTearDown(retry.dispose);
      expect(retry.page, same(source.page));
      expect(retry.plan, same(source.plan));
      expect(serializeCommands(retry.commands),
          orderedEquals(serializeCommands(source.commands)!));
    });
  });
}
