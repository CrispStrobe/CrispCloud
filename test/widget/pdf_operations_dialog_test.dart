import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/pdf_device_export.dart';
import 'package:crisp_cloud/services/pdf_file_store.dart';
import 'package:crisp_cloud/services/pdf_operations_host.dart';
import 'package:crisp_cloud/widgets/pdf_operations_dialog.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show PdfTextExtractor;
import 'package:pdf_operations/pdf_operations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pdf_operations_fixture.dart';

const _defaultFontPath =
    'packages/dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf';
late _TestFontBundle _fontBundle;

class _TestFontBundle extends CachingAssetBundle {
  _TestFontBundle(this.font);

  final ByteData font;

  @override
  Future<ByteData> load(String key) async =>
      key == _defaultFontPath ? font : await rootBundle.load(key);
}

class _Store implements PdfFileStore {
  _Store(this.displayName, {Uint8List? input})
    : input = input ?? buildPdfOperationsFixture();
  final Uint8List input;
  final copies = <(String, Uint8List)>[];
  int overwrites = 0;
  Future<PdfSaveOutcome> Function(Uint8List, String)? writer;
  @override
  final String displayName;
  @override
  String get documentId => 'test:$displayName';
  @override
  String get path => '/source/$displayName';
  @override
  bool get isRemote => false;
  @override
  Future<Uint8List> load() async => input;
  @override
  Future<PdfSaveOutcome> save(Uint8List bytes) async {
    overwrites++;
    return PdfSaveOutcome.savedOriginal;
  }

  @override
  Future<PdfSaveOutcome> saveCopy(Uint8List bytes, String name) async {
    copies.add((name, Uint8List.fromList(bytes)));
    return writer == null
        ? PdfSaveOutcome.savedCopy
        : await writer!(bytes, name);
  }
}

Future<void> _open(
  WidgetTester tester,
  PdfOperationAction action,
  List<_Store> stores, {
  PdfDeviceExporter? exporter,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  final host = PdfOperationsHost(
    stores: stores,
    deviceExporter: exporter,
    useWorker: false,
  );
  await tester.pumpWidget(
    DefaultAssetBundle(
      bundle: _fontBundle,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => Dialog.fullscreen(
                  child: PdfOperationsDialog(
                    host: host,
                    action: action,
                    autoRenderWorker: false,
                  ),
                ),
              ),
              child: const Text('Open operation'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open operation'));
  await tester.pumpAndSettle();
}

Future<void> _preview(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('pdf-operation-preview')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Fetch actual font bytes outside widget fake time. Browser asset requests
    // must finish before pumpAndSettle starts advancing the progress animation.
    _fontBundle = _TestFontBundle(await rootBundle.load(_defaultFontPath));
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('menu and palette selection rules reject mixed files and folders', () {
    final pdf = FileItem(
      name: 'REPORT.PDF',
      path: '/report.pdf',
      isFolder: false,
    );
    final other = FileItem(name: 'two.pdf', path: '/two.pdf', isFolder: false);
    final text = FileItem(name: 'notes.txt', isFolder: false);
    final folder = FileItem(name: 'folder.pdf', isFolder: true);
    expect(pdfOperationsForSelection([]), isEmpty);
    expect(pdfOperationsForSelection([pdf, text]), isEmpty);
    expect(pdfOperationsForSelection([folder]), isEmpty);
    expect(pdfOperationsForSelection([pdf, other]), [PdfOperationAction.merge]);
    expect(
      pdfOperationsForSelection([pdf]),
      containsAll([
        PdfOperationAction.extract,
        PdfOperationAction.rotate,
        PdfOperationAction.reorder,
        PdfOperationAction.deletePages,
        PdfOperationAction.watermark,
        PdfOperationAction.fillForm,
        PdfOperationAction.insertImage,
        PdfOperationAction.importOcr,
      ]),
    );
  });

  testWidgets(
    'rotation previews before saving, rotates only requested page, and never overwrites',
    (tester) async {
      final store = _Store('report.pdf');
      await _open(tester, PdfOperationAction.rotate, [store]);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-operation-pages')),
        '2',
      );
      await _preview(tester);
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(store.copies, isEmpty);
      expect(store.overwrites, 0);
      await tester.tap(find.byKey(const ValueKey('pdf-operation-save')));
      await tester.pumpAndSettle();
      expect(store.copies.single.$1, 'report-rotated.pdf');
      final document = PdfDocument.open(store.copies.single.$2);
      expect(document.pages[0].rotation, 0);
      expect(document.pages[1].rotation, 90);
      expect(store.overwrites, 0);
      expect(find.text('PDF copy saved.'), findsOneWidget);
    },
  );

  testWidgets(
    'ordered merge uses per-file ranges and saves beside original first selection',
    (tester) async {
      final first = _Store('one.pdf');
      final second = _Store(
        'two.pdf',
        input: buildPdfOperationsFixture(pageWidth: 600),
      );
      await _open(tester, PdfOperationAction.merge, [first, second]);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-merge-pages-0')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pdf-merge-pages-1')),
        '2',
      );
      await tester.tap(find.byKey(const ValueKey('pdf-merge-up-1')));
      await tester.pump();
      await _preview(tester);
      await tester.tap(find.byKey(const ValueKey('pdf-operation-save')));
      await tester.pumpAndSettle();
      expect(first.copies, hasLength(1));
      expect(second.copies, isEmpty);
      final inspection = PdfOperationsService().inspect(
        PdfInput(first.copies.single.$2),
      );
      expect(inspection.pageCount, 2);
      expect(inspection.pages.map((page) => page.width), [600, 300]);
      expect(first.overwrites + second.overwrites, 0);
    },
  );

  testWidgets('invalid page range leaves options and source untouched', (
    tester,
  ) async {
    final store = _Store('report.pdf');
    await _open(tester, PdfOperationAction.extract, [store]);
    await tester.enterText(
      find.byKey(const ValueKey('pdf-operation-pages')),
      '3',
    );
    await _preview(tester);
    expect(find.byKey(const ValueKey('pdf-operation-error')), findsOneWidget);
    expect(find.byType(PdfViewer), findsNothing);
    expect(find.byKey(const ValueKey('pdf-operation-pages')), findsOneWidget);
    expect(store.copies, isEmpty);
    expect(store.overwrites, 0);
  });

  testWidgets(
    'known-field JSON fills typed values and rejects unknown fields before writing',
    (tester) async {
      final store = _Store('form.pdf');
      await _open(tester, PdfOperationAction.fillForm, [store]);
      await tester.tap(find.text('JSON'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('pdf-form-json')),
        '{"missing":"value"}',
      );
      await _preview(tester);
      expect(find.byKey(const ValueKey('pdf-operation-error')), findsOneWidget);
      expect(store.copies, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-form-json')),
        '{"customer.name":"Zoë","consent":true,"country":"FR"}',
      );
      await _preview(tester);
      expect(find.byType(PdfViewer), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-operation-save')));
      await tester.pumpAndSettle();
      final form = PdfAcroForm.of(PdfDocument.open(store.copies.single.$2))!;
      expect(form.fieldNamed('customer.name')!.value, 'Zoë');
      expect(form.fieldNamed('country')!.value, 'FR');
      final inspection = PdfOperationsService().inspect(
        PdfInput(store.copies.single.$2),
      );
      expect(
        inspection.fields
            .singleWhere((field) => field.name == 'consent')
            .values,
        contains('Yes'),
      );
      expect(store.overwrites, 0);
    },
  );

  testWidgets(
    'failed sibling save retains preview and supports an independent export',
    (tester) async {
      final store = _Store('report.pdf')
        ..writer = (_, _) async => throw StateError('destination disconnected');
      final exported = <Uint8List>[];
      await _open(
        tester,
        PdfOperationAction.rotate,
        [store],
        exporter: (bytes, name) async {
          exported.add(bytes);
          return PdfSaveOutcome.savedCopy;
        },
      );
      await _preview(tester);
      await tester.tap(find.byKey(const ValueKey('pdf-operation-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('destination disconnected'), findsOneWidget);
      expect(find.byType(PdfViewer), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-operation-export')));
      await tester.pumpAndSettle();
      expect(exported.single, orderedEquals(store.copies.single.$2));
      expect(store.overwrites, 0);
    },
  );

  testWidgets(
    'switching JSON and typed fields preserves imported values and later edits',
    (tester) async {
      final store = _Store('form.pdf');
      await _open(tester, PdfOperationAction.fillForm, [store]);
      await tester.tap(find.text('JSON'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('pdf-form-json')),
        '{"customer.name":"Zoë","consent":true}',
      );
      await tester.tap(find.text('Fields'));
      await tester.pump();
      final name = find.byKey(const ValueKey('pdf-form-customer.name-1'));
      expect(tester.widget<TextFormField>(name).initialValue, 'Zoë');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('pdf-form-consent-1')),
            )
            .value,
        isTrue,
      );
      await tester.enterText(name, 'Zoë Updated');
      await tester.tap(find.text('JSON'));
      await tester.pump();
      final json = tester
          .widget<TextField>(find.byKey(const ValueKey('pdf-form-json')))
          .controller!
          .text;
      expect(jsonDecode(json), {
        'customer.name': 'Zoë Updated',
        'consent': true,
      });
      await _preview(tester);
      await tester.tap(find.byKey(const ValueKey('pdf-operation-save')));
      await tester.pumpAndSettle();
      final form = PdfAcroForm.of(PdfDocument.open(store.copies.single.$2))!;
      expect(form.fieldNamed('customer.name')!.value, 'Zoë Updated');
      expect(form.fieldNamed('consent')!.isChecked, isTrue);
    },
  );

  testWidgets(
    'invalid typed JSON remains visible when switching to form controls',
    (tester) async {
      final store = _Store('form.pdf');
      await _open(tester, PdfOperationAction.fillForm, [store]);
      await tester.tap(find.text('JSON'));
      await tester.pump();
      const input = '{"consent":"yes","unknown":"value"}';
      await tester.enterText(
        find.byKey(const ValueKey('pdf-form-json')),
        input,
      );
      await tester.tap(find.text('Fields'));
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-operation-error')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('pdf-form-json')))
            .controller!
            .text,
        input,
      );
      expect(store.copies, isEmpty);
      expect(store.overwrites, 0);
    },
  );

  testWidgets(
    'multiline form fields accept and save line breaks through typed controls',
    (tester) async {
      final store = _Store(
        'form.pdf',
        input: buildPdfOperationsFixture(multiline: true),
      );
      await _open(tester, PdfOperationAction.fillForm, [store]);
      final name = find.byKey(const ValueKey('pdf-form-customer.name-0'));
      final input = tester.widget<TextField>(
        find.descendant(of: name, matching: find.byType(TextField)),
      );
      expect(input.maxLines, 4);
      expect(input.keyboardType, TextInputType.multiline);
      await tester.enterText(name, 'Line one\nLine two');
      await _preview(tester);
      await tester.tap(find.byKey(const ValueKey('pdf-operation-save')));
      await tester.pumpAndSettle();
      final form = PdfAcroForm.of(PdfDocument.open(store.copies.single.$2))!;
      expect(form.fieldNamed('customer.name')!.value, 'Line one\nLine two');
      expect(store.overwrites, 0);
    },
  );

  testWidgets(
    'OCR span import previews searchable text and saves a separate PDF',
    (tester) async {
      final store = _Store('scan.pdf');
      await _open(tester, PdfOperationAction.importOcr, [store]);
      expect(find.textContaining('does not recognize images'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('pdf-ocr-skip-existing')),
            )
            .value,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('pdf-ocr-json')),
        '[{"page":2,"spans":[{"text":"Recognized sample","bounds":[20,300,200,320],"confidence":0.98}]}]',
      );
      await _preview(tester);
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(store.copies, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-operation-search')),
        'Recognized sample',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      final viewer = tester
          .widget<PdfViewer>(find.byType(PdfViewer))
          .controller!;
      expect(viewer.matchCount, 1);
      expect(viewer.searchResults.single.pageIndex, 1);
      await tester.tap(find.byKey(const ValueKey('pdf-operation-save')));
      await tester.pumpAndSettle();
      expect(store.copies.single.$1, 'scan-searchable.pdf');
      final document = PdfDocument.open(store.copies.single.$2);
      expect(
        PdfTextExtractor.extract(document, 0).text,
        isNot(contains('Recognized sample')),
      );
      expect(
        PdfTextExtractor.extract(document, 1).text,
        contains('Recognized sample'),
      );
      expect(store.overwrites, 0);
    },
  );

  testWidgets('invalid OCR page data creates no output and remains editable', (
    tester,
  ) async {
    final store = _Store('scan.pdf');
    await _open(tester, PdfOperationAction.importOcr, [store]);
    await tester.enterText(
      find.byKey(const ValueKey('pdf-ocr-json')),
      '[{"page":3,"spans":[{"text":"Outside PDF","bounds":[20,300,200,320]}]}]',
    );
    await _preview(tester);
    expect(find.byKey(const ValueKey('pdf-operation-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-ocr-json')), findsOneWidget);
    expect(find.byType(PdfViewer), findsNothing);
    expect(store.copies, isEmpty);
    expect(store.overwrites, 0);
  });

  testWidgets(
    'watermark preview applies chosen text only to requested pages and keeps fields',
    (tester) async {
      final store = _Store('marked.pdf');
      await _open(tester, PdfOperationAction.watermark, [store]);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-operation-pages')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pdf-watermark-text')),
        'CONFIDENTIAL',
      );
      await _preview(tester);
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(store.copies, isEmpty);
      await tester.tap(find.byKey(const ValueKey('pdf-operation-save')));
      await tester.pumpAndSettle();
      final document = PdfDocument.open(store.copies.single.$2);
      expect(
        PdfTextExtractor.extract(document, 0).text,
        isNot(contains('CONFIDENTIAL')),
      );
      expect(
        PdfTextExtractor.extract(document, 1).text,
        contains('CONFIDENTIAL'),
      );
      expect(
        PdfAcroForm.of(document)!.fieldNamed('customer.name')!.value,
        'Alice',
      );
      expect(store.overwrites, 0);
    },
  );

  testWidgets(
    'image insertion requires image data before any output can be saved',
    (tester) async {
      final store = _Store('image.pdf');
      await _open(tester, PdfOperationAction.insertImage, [store]);
      await _preview(tester);
      expect(find.byKey(const ValueKey('pdf-operation-error')), findsOneWidget);
      expect(find.byType(PdfViewer), findsNothing);
      expect(store.copies, isEmpty);
      expect(store.overwrites, 0);
    },
  );

  testWidgets(
    'save waits for completion and an unsaved preview needs a close decision',
    (tester) async {
      final pending = Completer<PdfSaveOutcome>();
      final store = _Store('report.pdf')..writer = (_, _) => pending.future;
      await _open(tester, PdfOperationAction.rotate, [store]);
      await _preview(tester);
      await tester.tap(find.byKey(const ValueKey('pdf-operation-close')));
      await tester.pumpAndSettle();
      expect(find.text('Close without saving?'), findsOneWidget);
      await tester.tap(find.text('Return to preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-operation-save')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(store.copies, hasLength(1));
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('pdf-operation-close')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(PdfOperationsDialog), findsOneWidget);
      pending.complete(PdfSaveOutcome.savedCopy);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-operation-close')));
      await tester.pumpAndSettle();
      expect(find.byType(PdfOperationsDialog), findsNothing);
    },
  );

  testWidgets(
    'password fields never show pre-existing contents or become editable controls',
    (tester) async {
      await _open(tester, PdfOperationAction.fillForm, [_Store('form.pdf')]);
      expect(find.text('pre-existing'), findsNothing);
      final secret = find.byKey(const ValueKey('pdf-form-secret-0'));
      expect(secret, findsOneWidget);
      expect(
        find.descendant(of: secret, matching: find.byType(TextFormField)),
        findsNothing,
      );
    },
  );
}
