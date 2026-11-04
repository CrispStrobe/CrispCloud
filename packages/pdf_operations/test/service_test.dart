import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_operations/pdf_operations.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

Matcher code(String value) => isA<PdfOperationException>()
    .having((error) => error.code, 'code', value);

void main() {
  const service = PdfOperationsService();
  late Uint8List fontBytes;
  setUpAll(() {
    fontBytes = File('test/fonts/CrispPdfTestSans.ttf').readAsBytesSync();
  });

  group('inspection and snapshot ownership', () {
    test('schema includes form metadata and visual page sizes', () {
      final result = service.inspect(PdfInput(workflowPdf()));
      expect(result.pageCount, 3);
      expect(result.encrypted, isFalse);
      expect(result.fields.firstWhere((field) => field.name == 'interests').multiSelect, isTrue);
      final choice = result.fields.firstWhere((field) => field.name == 'delivery');
      expect(choice.options.map((option) => option.value), ['standard', 'express']);
      expect(choice.options.map((option) => option.label), ['Standard', 'Express']);
      expect(result.pages.first.pageIndex, 0);
      expect(result.pages.first.toJson()['page'], 1);
      final geometry = service.inspect(PdfInput(geometryPdf()));
      expect((geometry.pages[0].width, geometry.pages[0].height), (300.0, 400.0));
      expect((geometry.pages[1].width, geometry.pages[1].height), (400.0, 300.0));
      expect(geometry.pages.map((page) => page.rotation), [0, 90, 180, 270]);
    });

    test('inspection never exposes historical password-field values', () {
      final result = service.inspect(PdfInput(restrictedFormPdf(), password: 'not-serialized'));
      final field = result.fields.firstWhere((field) => field.name == 'password');
      expect(field.password, isTrue);
      expect(field.values, isEmpty);
      expect(jsonEncode(result.toJson()), isNot(contains('historical-test-password')));
      expect(jsonEncode(result.toJson()), isNot(contains('not-serialized')));
    });

    test('input/result bytes cannot mutate an earlier snapshot', () {
      final bytes = workflowPdf();
      final originalFirst = bytes.first;
      final input = PdfInput(bytes);
      bytes[0] = 0;
      expect(input.bytes.first, originalFirst);
      expect(() => input.bytes[0] = 0, throwsUnsupportedError);
      final result = service.rotate(input, pages: '1');
      expect(() => result.bytes[0] = 0, throwsUnsupportedError);
      expect(service.inspect(input).pages.first.rotation, 0);
      expect(service.inspect(PdfInput(result.bytes)).pages.first.rotation, 90);
    });
  });

  group('page workflows', () {
    test('ordered merge imports functional forms and renames colliding roots', () {
      final result = service.merge([
        PdfMergeInput(PdfInput(workflowPdf(label: 'A')), pages: '3,1,2'),
        PdfMergeInput(PdfInput(workflowPdf(label: 'B')), pages: '2,1'),
      ]);
      expect(result.pageCount, 5);
      final text = service.text(PdfInput(result.bytes));
      expect(text.map((page) => page.text.trim()), [
        'A page 3', 'A page 1', 'A page 2', 'B page 2', 'B page 1',
      ]);
      final document = PdfDocument.open(result.bytes);
      final form = PdfAcroForm.of(document)!;
      expect(form.fields.where((field) => field.type == PdfFieldType.text).length, 4);
      expect(form.fields.map((field) => field.name).toSet().length, form.fields.length);
      final secondImported = form.fields.where((field) => field.name.startsWith('second_')).single;
      final filled = service.fillForm(PdfInput(result.bytes), values: {secondImported.name: 'Still editable'});
      final reread = PdfAcroForm.of(PdfDocument.open(filled.bytes))!;
      expect(reread.fieldNamed(secondImported.name)!.value, 'Still editable');
    });

    test('first-source subset retains fields only for selected pages', () {
      final result = service.merge([
        PdfMergeInput(PdfInput(workflowPdf(label: 'A')), pages: '2'),
        PdfMergeInput(PdfInput(workflowPdf(label: 'B')), pages: '1'),
      ]);
      expect(result.pageCount, 2);
      final form = PdfAcroForm.of(PdfDocument.open(result.bytes))!;
      expect(form.fieldNamed('second')!.widgetPageIndex(0), 0);
      expect(form.fieldNamed('customer.name')!.widgetPageIndex(0), 1);
    });

    test('extract keeps selected form usable and remaps its page index', () {
      final result = service.extract(PdfInput(workflowPdf()), pages: '2');
      expect(result.pageCount, 1);
      final document = PdfDocument.open(result.bytes);
      expect(document.pageCount, 1);
      final form = PdfAcroForm.of(document)!;
      expect(form.fields.map((field) => field.name), ['second']);
      expect(form.fieldNamed('second')!.widgetPageIndex(0), 0);
      final filled = service.fillForm(PdfInput(result.bytes), values: {'second': 'Extracted and filled'});
      expect(PdfAcroForm.of(PdfDocument.open(filled.bytes))!.fieldNamed('second')!.value, 'Extracted and filled');
      expect(PdfOutline.of(document).items.any((item) => item.title.contains('chapter 2')), isTrue);
    });

    test('rotation only changes selected pages and supports negative turns', () {
      final result = service.rotate(PdfInput(workflowPdf()), pages: '3,1', degrees: -90);
      expect(service.inspect(PdfInput(result.bytes)).pages.map((page) => page.rotation), [270, 0, 270]);
      expect(result.pageCount, 3);
      expect(() => service.rotate(PdfInput(workflowPdf()), degrees: 45), throwsA(code('invalidRotation')));
    });

    test('reorder requires all pages; deletion preserves warning and correct count', () {
      final input = PdfInput(workflowPdf());
      final reordered = service.reorder(input, pages: '3-1');
      expect(service.text(PdfInput(reordered.bytes)).map((page) => page.text.trim()),
          ['Source page 3', 'Source page 2', 'Source page 1']);
      expect(() => service.reorder(input, pages: '1,3'), throwsA(code('invalidPages')));
      final deleted = service.deletePages(input, pages: '2');
      expect(deleted.pageCount, 2);
      expect(PdfDocument.open(deleted.bytes).pageCount, 2);
      expect(deleted.warnings.join(' '), contains('not secure erasure'));
      expect(() => service.deletePages(input, pages: 'all'), throwsA(code('invalidPages')));
    });

    test('text and search include page index and match geometry', () {
      final input = PdfInput(workflowPdf());
      expect(service.text(input, pages: '3,1').map((page) => page.pageIndex), [2, 0]);
      final hits = service.search(input, query: 'PAGE 2');
      expect(hits, hasLength(1));
      expect(hits.single.pageIndex, 1);
      expect(hits.single.text, 'page 2');
      expect(hits.single.bounds, isNotEmpty);
      expect(service.search(input, query: 'page [13]', regex: true), hasLength(2));
      expect(service.search(input, query: 'page 2', pages: '1'), isEmpty);
      expect(() => service.search(input, query: '[', regex: true), throwsA(code('invalidSearch')));
    });
  });

  group('strict form filling', () {
    test('sets typed values, regenerates appearances, and checkbox is idempotent', () {
      final values = <String, Object?>{
        'customer.name': 'Anna Müller', 'agree': true, 'color': 'Blue',
        'delivery': 'Express', 'interests': ['music', 'books'],
      };
      final result = service.fillForm(PdfInput(workflowPdf()), values: values);
      expect(result.filledFields, values.keys);
      final form = PdfAcroForm.of(PdfDocument.open(result.bytes))!;
      expect(form.fieldNamed('customer.name')!.value, 'Anna Müller');
      expect(form.fieldNamed('agree')!.isChecked, isTrue);
      expect(form.fieldNamed('color')!.value, 'Blue');
      expect(form.fieldNamed('delivery')!.value, 'express');
      expect(form.fieldNamed('interests')!.values, ['books', 'music']);
      final repeated = service.fillForm(PdfInput(result.bytes), values: values);
      expect(PdfAcroForm.of(PdfDocument.open(repeated.bytes))!.fieldNamed('agree')!.isChecked, isTrue);
      final clear = service.fillForm(PdfInput(repeated.bytes), values: {'agree': false, 'interests': <String>[]});
      final cleared = PdfAcroForm.of(PdfDocument.open(clear.bytes))!;
      expect(cleared.fieldNamed('agree')!.isChecked, isFalse);
      expect(cleared.fieldNamed('interests')!.values, isEmpty);
    });

    test('rejects unknown/type/choice/readonly/password/maxlength values together', () {
      final input = PdfInput(restrictedFormPdf());
      try {
        service.fillForm(input, values: {
          'missing': 'value', 'agree': 'true', 'delivery': 'invalid',
          'readOnly': 'new', 'password': 'new-secret', 'short': 'toolong',
          'required': '', 'customer.name': 'Otherwise valid',
        });
        fail('Expected whole-map validation failure');
      } on PdfOperationException catch (error) {
        expect(error.code, 'invalidForm');
        expect(error.fieldErrors.keys.toSet(),
            {'missing', 'agree', 'delivery', 'readOnly', 'password', 'short', 'required'});
        expect(jsonEncode(error.toJson()), isNot(contains('new-secret')));
      }
      expect(PdfAcroForm.of(PdfDocument.open(input.bytes))!.fieldNamed('customer.name')!.value, 'Original');
    });

    test('Unicode requires glyph coverage and creates actual Unicode appearance text', () {
      final input = PdfInput(workflowPdf());
      expect(() => service.fillForm(input, values: {'customer.name': 'Жук'}), throwsA(code('invalidForm')));
      final font = PdfEmbeddedFont.parse(fontBytes);
      final result = service.fillForm(input, values: {'customer.name': 'Жук Αθήνα'}, appearanceFont: font);
      final document = PdfDocument.open(result.bytes);
      expect(PdfAcroForm.of(document)!.fieldNamed('customer.name')!.value, 'Жук Αθήνα');
      final editor = PdfEditor(document)..flattenForm();
      final renderedText = PdfTextExtractor.extract(PdfDocument.open(editor.save()), 0).text;
      expect(renderedText, contains('Жук Αθήνα'));
      expect(() => service.fillForm(input, values: {'customer.name': '漢'}, appearanceFont: font), throwsA(code('invalidForm')));
    });

    test('already embedded form font is reused without another font argument', () {
      final first = service.fillForm(PdfInput(workflowPdf()),
          values: {'customer.name': 'Жук'}, appearanceFont: PdfEmbeddedFont.parse(fontBytes));
      final second = service.fillForm(PdfInput(first.bytes), values: {'customer.name': 'Москва'});
      final editor = PdfEditor(PdfDocument.open(second.bytes))..flattenForm();
      expect(PdfTextExtractor.extract(PdfDocument.open(editor.save()), 0).text, contains('Москва'));
    });

    test('custom simple-font encodings require an explicit covering appearance font', () {
      final input = PdfInput(remappedFormPdf());
      expect(() => service.fillForm(input, values: {'customer.name': 'B'}),
          throwsA(code('invalidForm')));
      final filled = service.fillForm(input, values: {'customer.name': 'B'},
          appearanceFont: PdfEmbeddedFont.parse(fontBytes));
      final document = PdfDocument.open(filled.bytes);
      expect(PdfAcroForm.of(document)!.fieldNamed('customer.name')!.value, 'B');
      final editor = PdfEditor(document)..flattenForm();
      final appearance = PdfTextExtractor.extract(PdfDocument.open(editor.save()), 0).text;
      expect(appearance, contains('B'));
      expect(appearance, isNot(contains('8')));
    });
  });

  group('watermark and image appearance', () {
    test('flattening a watermark leaves existing form fields and comments interactive', () {
      final input = PdfInput(workflowPdf());
      final result = service.watermark(input, pages: '1,3',
          watermark: const PdfWatermarkOptions(text: 'DRAFT', angleDegrees: 0));
      final document = PdfDocument.open(result.bytes);
      expect(PdfAcroForm.of(document)!.fieldNamed('customer.name'), isNotNull);
      expect(document.page(0).annotations.any((annotation) => annotation.name == 'existing-comment'), isTrue);
      expect(document.page(0).annotations.any((annotation) => annotation.subtype == 'Widget'), isTrue);
      expect(service.search(PdfInput(result.bytes), query: 'DRAFT').map((hit) => hit.pageIndex), [0, 2]);
      expect(document.page(0).annotations.any((annotation) => annotation.name?.startsWith('crisp-pdf-watermark') == true), isFalse);
    });

    test('editable rotated watermark stays in cropped pages at every rotation', () {
      final result = service.watermark(PdfInput(geometryPdf()),
          watermark: const PdfWatermarkOptions(text: 'Draft', angleDegrees: -35, flatten: false));
      final document = PdfDocument.open(result.bytes);
      for (final page in document.pages) {
        final annotation = page.annotations.single;
        expect(annotation.subtype, 'FreeText');
        expect(annotation.normalAppearance, isNotNull);
        expect(annotation.rect.left, greaterThanOrEqualTo(page.cropBox.left - 1e-6));
        expect(annotation.rect.bottom, greaterThanOrEqualTo(page.cropBox.bottom - 1e-6));
        expect(annotation.rect.right, lessThanOrEqualTo(page.cropBox.right + 1e-6));
        expect(annotation.rect.top, lessThanOrEqualTo(page.cropBox.top + 1e-6));
      }
    });

    test('rotate then flatten matches the geometry of a separately reopened mark', () {
      final input = PdfInput(geometryPdf());
      final editable = service.watermark(input,
          watermark: const PdfWatermarkOptions(text: 'DRAFT', angleDegrees: 35, flatten: false));
      final reopened = PdfDocument.open(editable.bytes);
      final referenceEditor = PdfEditor(reopened);
      for (var i = 0; i < reopened.pageCount; i++) {
        referenceEditor.flattenAnnotations(i, annotations: reopened.page(i).annotations);
      }
      final reference = PdfDocument.open(referenceEditor.save());
      final actual = PdfDocument.open(service.watermark(input,
          watermark: const PdfWatermarkOptions(text: 'DRAFT', angleDegrees: 35)).bytes);
      for (var i = 0; i < actual.pageCount; i++) {
        final actualRun = PdfTextExtractor.extract(actual, i).runs.single;
        final referenceRun = PdfTextExtractor.extract(reference, i).runs.single;
        expect(actualRun.text, referenceRun.text);
        for (final coordinate in [
          (actualRun.bounds.left, referenceRun.bounds.left),
          (actualRun.bounds.bottom, referenceRun.bounds.bottom),
          (actualRun.bounds.right, referenceRun.bounds.right),
          (actualRun.bounds.top, referenceRun.bounds.top),
        ]) {
          expect(coordinate.$1, closeTo(coordinate.$2, 1e-6));
        }
      }
    });

    test('Unicode watermark is embedded and searchable after flattening', () {
      final result = service.watermark(PdfInput(PdfBlankDocument.create()),
          watermark: PdfWatermarkOptions(text: 'Жук Αθήνα', angleDegrees: 0,
              font: PdfEmbeddedFont.parse(fontBytes)));
      expect(service.search(PdfInput(result.bytes), query: 'Жук Αθήνα'), hasLength(1));
      expect(() => service.watermark(PdfInput(workflowPdf()),
          watermark: const PdfWatermarkOptions(text: '漢')), throwsA(code('unsupportedText')));
    });

    test('image placement uses visual fractions on 0 and 90 degree crop boxes', () {
      final result = service.insertImage(PdfInput(geometryPdf()), imageBytes: redLogoPng(),
          pages: '1-2', placement: const PdfImagePlacement(x: .1, y: .2, width: .5, flatten: false));
      final document = PdfDocument.open(result.bytes);
      expect(document.page(0).annotations.single.rect, const PdfRect(60, 285, 210, 360));
      expect(document.page(1).annotations.single.rect, const PdfRect(90, 80, 190, 280));
      expect(document.page(2).annotations, isEmpty);
      expect(document.page(3).annotations, isEmpty);
    });

    test('logo watermark preserves image form and only selected pages', () {
      final result = service.watermark(PdfInput(geometryPdf()), pages: '2,4',
          watermark: PdfWatermarkOptions(imageBytes: redLogoPng(), opacity: .35,
              angleDegrees: 15, flatten: false));
      final document = PdfDocument.open(result.bytes);
      expect(document.pages.map((page) => page.annotations.length), [0, 1, 0, 1]);
      expect(document.page(1).annotations.single.subtype, 'Stamp');
    });

    test('invalid appearances and oversized image headers reject before decode', () {
      final input = PdfInput(geometryPdf());
      expect(() => service.watermark(input, watermark: const PdfWatermarkOptions(text: 'x', widthFraction: .00001)), throwsA(code('invalidWatermark')));
      expect(() => service.watermark(input, watermark: const PdfWatermarkOptions(text: 'x', opacity: double.nan)), throwsA(code('invalidAppearance')));
      expect(() => service.insertImage(input, imageBytes: redLogoPng(), placement: const PdfImagePlacement(x: .9, width: .2)), throwsA(code('invalidPlacement')));
      final excessive = Uint8List.fromList(redLogoPng());
      ByteData.sublistView(excessive).setUint32(16, 100000);
      ByteData.sublistView(excessive).setUint32(20, 100000);
      expect(() => service.insertImage(input, imageBytes: excessive, placement: const PdfImagePlacement()), throwsA(code('imageLimit')));
    });
  });

  group('encryption and unsupported inputs', () {
    test('missing and incorrect passwords have machine-readable errors', () {
      final bytes = buildEncryptedPdf(userPassword: 'test-password', revision: 6);
      expect(() => service.inspect(PdfInput(bytes)), throwsA(code('passwordRequired')));
      expect(() => service.inspect(PdfInput(bytes, password: 'wrong')), throwsA(code('invalidPassword')));
      expect(service.inspect(PdfInput(bytes, password: 'test-password')).encrypted, isTrue);
    });

    test('rotate and merge preserve first whole input encryption', () {
      final input = PdfInput(buildEncryptedPdf(userPassword: 'test-password', revision: 6), password: 'test-password');
      final rotated = service.rotate(input);
      expect(() => PdfDocument.open(rotated.bytes), throwsA(isA<CosPasswordException>()));
      expect(PdfDocument.open(rotated.bytes, password: 'test-password').page(0).rotation, 90);
      final merged = service.merge([PdfMergeInput(input), PdfMergeInput(PdfInput(workflowPdf()))]);
      expect(merged.pageCount, 4);
      expect(() => PdfDocument.open(merged.bytes), throwsA(isA<CosPasswordException>()));
      expect(PdfDocument.open(merged.bytes, password: 'test-password').pageCount, 4);
    });

    test('decryption requires explicit acknowledgment for extract and plain-base merge', () {
      final input = PdfInput(buildEncryptedPdf(userPassword: 'test-password', revision: 6), password: 'test-password');
      expect(() => service.extract(input, pages: '1'), throwsA(code('decryptionRequired')));
      final extracted = service.extract(input, pages: '1', allowDecryption: true);
      expect(PdfDocument.open(extracted.bytes).cos.isEncrypted, isFalse);
      expect(extracted.warnings.join(' '), contains('unencrypted'));
      final sources = [PdfMergeInput(PdfInput(workflowPdf())), PdfMergeInput(input)];
      expect(() => service.merge(sources), throwsA(code('decryptionRequired')));
      expect(PdfDocument.open(service.merge(sources, allowDecryption: true).bytes).cos.isEncrypted, isFalse);
    });

    test('XFA is inspectable but all mutations refuse it', () {
      final input = PdfInput(buildXfaFormPdf());
      expect(service.inspect(input).hasXfa, isTrue);
      expect(() => service.rotate(input), throwsA(code('unsupportedXfa')));
      expect(() => service.extract(input, pages: '1'), throwsA(code('unsupportedXfa')));
      expect(() => service.fillForm(input, values: {'name': 'new'}), throwsA(code('unsupportedXfa')));
    });

    test('signature marker produces explicit original-preservation warning', () {
      final input = PdfInput(signatureMarkerPdf());
      expect(service.inspect(input).hasSignatures, isTrue);
      expect(service.rotate(input).warnings.join(' '), contains('Keep the signed original'));
    });

    test('byte/page/output limits are enforced', () {
      final input = PdfInput(workflowPdf());
      expect(() => const PdfOperationsService(maxInputBytes: 1).inspect(input), throwsA(code('inputLimit')));
      expect(() => const PdfOperationsService(maxPageCount: 2).inspect(input), throwsA(code('pageLimit')));
      expect(() => const PdfOperationsService(maxOutputBytes: 1).rotate(input), throwsA(code('outputLimit')));
      expect(() => const PdfOperationsService(maxTotalInputBytes: 1).merge([PdfMergeInput(input)]), throwsA(code('totalInputLimit')));
    });
  });

  group('external OCR spans', () {
    test('JSON has validated one-based pages and PDF-space bounds', () {
      final page = PdfOcrPage.fromJson({
        'page': 2,
        'spans': [{'text': 'word', 'bounds': [50, 100, 120, 120], 'confidence': .9}],
      });
      expect(page.pageIndex, 1);
      expect(page.spans.single.bounds, const PdfRect(50, 100, 120, 120));
      expect(page.toJson()['page'], 2);
      expect(() => PdfOcrPage.fromJson({'page': 0, 'spans': []}), throwsA(code('invalidOcr')));
      expect(() => PdfOcrPage.fromJson({'page': 1, 'spans': [{'text': 'x', 'bounds': [0, 0, 0, 20]}]}), throwsA(code('invalidOcr')));
    });

    test('invisible Unicode layer remains selectable/searchable', () {
      final input = PdfInput(PdfBlankDocument.create());
      final result = service.applyOcr(input,
          pages: [PdfOcrPage(pageIndex: 0, spans: [const PdfOcrSpan(text: 'Жук Αθήνα', bounds: PdfRect(72, 680, 230, 705))])],
          font: PdfEmbeddedFont.parse(fontBytes));
      expect(service.search(PdfInput(result.bytes), query: 'Жук Αθήνα'), hasLength(1));
      expect(String.fromCharCodes(PdfDocument.open(result.bytes).page(0).contentBytes()), contains('3 Tr'));
    });

    test('default skip prevents duplicate OCR on an existing text page', () {
      final input = PdfInput(workflowPdf());
      final result = service.applyOcr(input,
          pages: [PdfOcrPage(pageIndex: 0, spans: [const PdfOcrSpan(text: 'duplicate', bounds: PdfRect(72, 680, 200, 700))])]);
      expect(service.search(PdfInput(result.bytes), query: 'duplicate'), isEmpty);
      expect(result.warnings.join(' '), contains('already has text'));
    });

    test('backend cannot return pages outside the requested set', () async {
      await expectLater(service.recognize(PdfInput(workflowPdf()),
          pages: '1', backend: _WrongPageBackend()), throwsA(code('invalidOcr')));
    });
  });
}

class _WrongPageBackend implements PdfRecognitionBackend {
  @override
  Future<List<PdfOcrPage>> recognize(PdfInput input, List<int> pageIndices) async =>
      [PdfOcrPage(pageIndex: 1, spans: [])];
}
