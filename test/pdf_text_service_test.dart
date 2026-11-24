import 'dart:io';

import 'package:crisp_cloud/services/pdf_text_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'support/pdf_editor_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('crispcloud/pdf_text');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'portable PDF text extraction works without a registered plugin',
    () async {
      final doc = PdfDocument();
      final canvas = PdfCanvas(300, 400)
        ..showLatin(
          x: 20,
          y: 40,
          fontSize: 12,
          color: '000000',
          text: 'Hello PDF',
        );
      doc.addPage(PdfPage(width: 300, height: 400, content: canvas.toStream()));
      expect(
        await PdfTextService().extractText(doc.save()),
        contains('Hello PDF'),
      );
      expect(
        await PdfTextService().extractText(buildPdfEditorFixture()),
        isEmpty,
      );
    },
    skip: Platform.isMacOS || Platform.isIOS,
  );

  test('Windows passes PDF bytes to the PDFium text adapter', () async {
    final bytes = buildPdfEditorFixture();
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'extractText');
      expect(call.arguments, bytes);
      return 'Grüße aus dem PDF';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    expect(await PdfTextService().extractText(bytes), 'Grüße aus dem PDF');
  }, skip: !Platform.isWindows);
}
