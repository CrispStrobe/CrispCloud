import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/opc/office_open_decode.dart';
import 'package:test/test.dart';

Uint8List _odt({bool broken = false, bool unsupported = false}) {
  final name = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION '
    '{"citationID":"open-citation","citationItems":[{"id":7,'
    '"locator":"12","label":"page","prefix":"see ",'
    '"suppress-author":true}],"properties":{"plainCitation":"(Source)"}}'
    ' RND0123456789',
  );
  final body = unsupported
      ? '<text:alphabetical-index><text:p>Protected research</text:p>'
            '</text:alphabetical-index>'
      : '<text:p>Before <text:reference-mark-start text:name="$name"/>'
            '(Source)'
            '${broken ? '' : '<text:reference-mark-end text:name="$name"/>'}'
            ' after العربية 😀</text:p>';
  return (ZipWriter()
        ..addFile(
          'mimetype',
          utf8.encode('application/vnd.oasis.opendocument.text'),
          store: true,
        )
        ..addFile(
          'content.xml',
          utf8.encode(
            '<office:document-content '
            'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
            'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">'
            '<office:body><office:text>$body</office:text></office:body>'
            '</office:document-content>',
          ),
        ))
      .close();
}

void _expectOpened(WordOpenPayload result) {
  expect(
    result.document.paragraphs.single.text,
    'Before (Source) after العربية 😀',
  );
  expect(result.laidOut.pages, isNotEmpty);
  final field = WordZotero.fields(result.document).single;
  expect(field.citation!.citationId, 'open-citation');
  expect(field.citation!.items.single.locator, '12');
  expect(field.citation!.items.single.suppressAuthor, isTrue);
  final reopened = WordDeserializer().read(
    OpcPackage.openBytes(WordSerializer().writeBytes(result.document)),
  );
  expect(
    WordZotero.fields(reopened).single.citation!.citationId,
    'open-citation',
  );
  expect(
    reopened.paragraphs.single.text,
    result.document.paragraphs.single.text,
  );
}

void main() {
  test(
    'worker open recognizes native ODT bytes and retains active fields',
    () async {
      final bytes = _odt();
      final before = Uint8List.fromList(bytes);
      final progress = <OfficeOpenProgress>[];
      final opened = await OfficeIsolateOpen.word(
        bytes,
        onProgress: progress.add,
      );
      _expectOpened(opened);
      expect(bytes, orderedEquals(before));
      expect(
        progress.map((p) => p.stage),
        containsAllInOrder(['archive', 'document', 'layout', 'apply']),
      );
      expect(progress.every((p) => p.value >= 0 && p.value <= 1), isTrue);
    },
  );

  test('current-isolate decode awaits native import before layout', () async {
    final progress = <OfficeOpenProgress>[];
    final result = await decodeOfficeOpen(_odt(), null, 'word', progress.add);
    _expectOpened(result as WordOpenPayload);
    expect(
      progress.map((p) => p.stage),
      orderedEquals(['archive', 'document', 'layout', 'apply']),
    );
  });

  for (final unsupported in [false, true]) {
    test(
      'invalid native ODT does not publish a layout ($unsupported)',
      () async {
        final progress = <OfficeOpenProgress>[];
        await expectLater(
          decodeOfficeOpen(
            _odt(broken: !unsupported, unsupported: unsupported),
            null,
            'word',
            progress.add,
          ),
          throwsA(
            unsupported ? isA<UnsupportedError>() : isA<FormatException>(),
          ),
        );
        expect(progress.map((p) => p.stage), isNot(contains('layout')));
        expect(progress.map((p) => p.stage), isNot(contains('apply')));
      },
    );
  }

  test('native ODT import failures are delivered from the worker', () async {
    await expectLater(
      OfficeIsolateOpen.word(_odt(broken: true)),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'async decoder retains the existing DOCX, workbook and slide routes',
    () async {
      final word =
          await decodeOfficeOpen(
                WordSerializer().writeBytes(
                  WmlDocument.empty(text: 'DOCX kept'),
                ),
                null,
                'word',
                (_) {},
              )
              as WordOpenPayload;
      expect(word.document.paragraphs.single.text, 'DOCX kept');

      final workbook = SmlWorkbook();
      workbook.firstSheet.cellA1('A1').value = 8;
      workbook.firstSheet.cellA1('B1')
        ..type = SmlCellType.formula
        ..formula = '=A1+2';
      final sheet =
          await decodeOfficeOpen(
                SheetSerializer().writeBytes(workbook),
                null,
                'sheet',
                (_) {},
              )
              as SmlWorkbook;
      expect(sheet.firstSheet.cellA1('B1').value, 10);

      final presentation = PmlPresentation(
        slides: [
          PmlSlide(
            id: 256,
            shapes: [PmlShape(id: 2, name: 'Title', text: 'Slide kept')],
          ),
        ],
      );
      final slide =
          await decodeOfficeOpen(
                SlideSerializer().writeBytes(presentation),
                null,
                'slide',
                (_) {},
              )
              as PmlPresentation;
      expect(slide.slides.single.shapes.single.text, 'Slide kept');
    },
  );

  test('async decoder retains the PDF route', () async {
    final pdf = PdfDocument(title: 'Open PDF')
      ..addPage(PdfPage(width: 100, height: 100, content: Uint8List(0)));
    final opened = await decodeOfficeOpen(pdf.save(), null, 'pdf', (_) {});
    expect(opened, isA<PdfOpenPayload>());
    expect((opened as PdfOpenPayload).lists, hasLength(1));
  });
}
