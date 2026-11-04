import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/pdf_file_store.dart';
import 'package:crisp_cloud/services/pdf_device_export.dart';
import 'package:crisp_cloud/widgets/file_editor_dialog.dart';
import 'package:crisp_cloud/widgets/pdf_editor_dialog.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pdf_editor_fixture.dart';

class _MemoryPdfStore implements PdfFileStore {
  _MemoryPdfStore({Uint8List? input})
    : input = input ?? buildPdfEditorFixture();

  final Uint8List input;
  final List<Uint8List> writes = [];
  final List<String> copyNames = [];
  Future<PdfSaveOutcome> Function(Uint8List)? writer;

  @override
  String get documentId => 'test:sample.pdf';
  @override
  String get displayName => 'sample.pdf';
  @override
  String get path => '/sample.pdf';
  @override
  bool get isRemote => false;

  @override
  Future<Uint8List> load() async => input;

  @override
  Future<PdfSaveOutcome> save(Uint8List bytes) async {
    writes.add(Uint8List.fromList(bytes));
    return writer == null ? PdfSaveOutcome.savedOriginal : await writer!(bytes);
  }

  @override
  Future<PdfSaveOutcome> saveCopy(Uint8List bytes, String name) async {
    copyNames.add(name);
    return PdfSaveOutcome.savedCopy;
  }
}

Future<void> _open(
  WidgetTester tester,
  _MemoryPdfStore store, {
  PdfDeviceExporter? exporter,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final preferences = PdfEditingPreferences(store: PdfMemoryPreferencesStore());
  addTearDown(preferences.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => Dialog.fullscreen(
                  child: PdfEditorDialog(
                    file: FileItem(name: 'sample.pdf', isFolder: false),
                    side: PanelSide.local,
                    storeOverride: store,
                    preferencesOverride: preferences,
                    deviceExporterOverride: exporter,
                    autoRenderWorker: false,
                  ),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

PdfEditingController _controller(WidgetTester tester) =>
    tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;

Future<void> _rotate(WidgetTester tester) async {
  _controller(tester).rotatePages([0], 90);
  await tester.pumpAndSettle();
}

Finder get _save => find.byKey(const ValueKey('pdf-save'));
Finder get _close => find.byKey(const ValueKey('pdf-close'));
Finder get _unsaved => find.byKey(const ValueKey('pdf-unsaved-dialog'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only PDF file names use the PDF route', () {
    expect(isPdfFileName('report.PDF'), isTrue);
    expect(isPdfFileName('report.pdf.txt'), isFalse);
    expect(isPdfFileName('README'), isFalse);
    expect(isPdfFileName('report.pdf.'), isFalse);
  });

  testWidgets('F4 routes a PDF to the PDF dialog before loading bytes', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showFileEditorDialog(
                  context,
                  ref,
                  FileItem(
                    name: 'large.PDF',
                    isFolder: false,
                    size: 65 * 1024 * 1024,
                  ),
                  PanelSide.local,
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(PdfEditorDialog), findsOneWidget);
    expect(
      find.text('PDF editing is limited to files up to 64 MiB.'),
      findsOneWidget,
    );
  });

  testWidgets('undo back to the opened bytes clears host dirty state', (
    tester,
  ) async {
    await _open(tester, _MemoryPdfStore());
    expect(find.byType(PdfEditorView), findsOneWidget);
    expect(tester.widget<IconButton>(_save).onPressed, isNull);
    await _rotate(tester);
    expect(find.text('sample.pdf *'), findsOneWidget);
    expect(tester.widget<IconButton>(_save).onPressed, isNotNull);
    _controller(tester).undo();
    await tester.pumpAndSettle();
    expect(find.text('sample.pdf'), findsOneWidget);
    expect(tester.widget<IconButton>(_save).onPressed, isNull);
  });

  testWidgets('failed save keeps edits open and a later close can retry', (
    tester,
  ) async {
    final store = _MemoryPdfStore();
    var fail = true;
    store.writer = (_) async {
      if (fail) throw StateError('upload failed');
      return PdfSaveOutcome.savedOriginal;
    };
    await _open(tester, store);
    await _rotate(tester);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.text('sample.pdf *'), findsOneWidget);
    expect(find.textContaining('Could not save PDF'), findsOneWidget);
    fail = false;
    await tester.tap(_close);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: _unsaved, matching: find.text('Save')),
    );
    await tester.pumpAndSettle();
    expect(store.writes, hasLength(2));
    expect(find.byType(PdfEditorDialog), findsNothing);
  });

  testWidgets('save before close waits for upload and preserves newer edits', (
    tester,
  ) async {
    final upload = Completer<PdfSaveOutcome>();
    final store = _MemoryPdfStore()..writer = (_) => upload.future;
    await _open(tester, store);
    await _rotate(tester);
    final snapshot = Uint8List.fromList(_controller(tester).bytes);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: _unsaved, matching: find.text('Save')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.writes, hasLength(1));
    expect(store.writes.single, orderedEquals(snapshot));
    expect(find.byType(PdfEditorDialog), findsOneWidget);
    expect(tester.widget<IconButton>(_close).onPressed, isNull);
    _controller(tester).rotatePages([1], 90);
    await tester.pump();
    upload.complete(PdfSaveOutcome.savedOriginal);
    await tester.pumpAndSettle();
    expect(find.byType(PdfEditorDialog), findsOneWidget);
    expect(find.text('sample.pdf *'), findsOneWidget);
    expect(
      find.textContaining('New changes were made while saving.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a browser download stays dirty and close needs acknowledgement',
    (tester) async {
      final store = _MemoryPdfStore()
        ..writer = (_) async => PdfSaveOutcome.downloadedCopy;
      await _open(tester, store);
      await _rotate(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(find.text('sample.pdf *'), findsOneWidget);
      expect(
        find.text('Copy downloaded. The original has not been updated.'),
        findsOneWidget,
      );
      await tester.tap(_close);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: _unsaved, matching: find.text('Save')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Close after saving a copy?'), findsOneWidget);
      expect(find.byType(PdfEditorDialog), findsOneWidget);
      await tester.tap(find.text('Close editor'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfEditorDialog), findsNothing);
    },
  );

  testWidgets('Ctrl+S starts one host save', (tester) async {
    final store = _MemoryPdfStore();
    await _open(tester, store);
    await _rotate(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(store.writes, hasLength(1));
    expect(find.text('sample.pdf'), findsOneWidget);
  });

  testWidgets(
    'failed source save can recover a copy through the close prompt',
    (tester) async {
      final store = _MemoryPdfStore()
        ..writer = (_) async => throw StateError('account disconnected');
      final recovered = <Uint8List>[];
      await _open(
        tester,
        store,
        exporter: (bytes, name) async {
          recovered.add(Uint8List.fromList(bytes));
          return PdfSaveOutcome.savedCopy;
        },
      );
      await _rotate(tester);
      final snapshot = Uint8List.fromList(_controller(tester).bytes);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      await tester.tap(_close);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: _unsaved,
          matching: find.text(kIsWeb ? 'Download a copy' : 'Export a copy'),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.writes, hasLength(1));
      expect(store.copyNames, isEmpty);
      expect(recovered.single, orderedEquals(snapshot));
      expect(find.text('Close after saving a copy?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('sample.pdf *'), findsOneWidget);
    },
  );

  testWidgets('canceling device export leaves the edited document open', (
    tester,
  ) async {
    final store = _MemoryPdfStore();
    await _open(tester, store, exporter: (_, name) async => null);
    await _rotate(tester);
    await tester.tap(find.byKey(const ValueKey('pdf-export-copy')));
    await tester.pumpAndSettle();
    expect(find.text('sample.pdf *'), findsOneWidget);
    expect(store.writes, isEmpty);
    expect(store.copyNames, isEmpty);
    expect(find.text('Close after saving a copy?'), findsNothing);
  });

  testWidgets('the redaction shortcut cannot arm a disabled redaction tool', (
    tester,
  ) async {
    await _open(tester, _MemoryPdfStore());
    expect(
      tester.widget<PdfEditorView>(find.byType(PdfEditorView)).features.tools,
      isNot(contains(PdfEditTool.redact)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(_controller(tester).tool, isNot(PdfEditTool.redact));
  });

  testWidgets('XFA forms get an explanation without an editable surface', (
    tester,
  ) async {
    await _open(
      tester,
      _MemoryPdfStore(input: buildPdfEditorFixture(xfa: true)),
    );
    expect(find.byType(PdfEditorView), findsNothing);
    expect(
      find.textContaining('XFA forms cannot be edited here.'),
      findsOneWidget,
    );
    expect(_save, findsNothing);
  });

  testWidgets('the Save action requires a separate copy for a signed PDF', (
    tester,
  ) async {
    final store = _MemoryPdfStore(input: buildPdfEditorFixture(signed: true));
    await _open(tester, store);
    expect(
      find.textContaining('Save a copy to preserve the signed original.'),
      findsOneWidget,
    );
    await _rotate(tester);
    await tester.tap(_save);
    // The host stays busy while choosing a name. Wait for the dialog's
    // entrance animation without waiting for its progress indicator to stop.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('pdf-copy-name')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save a copy'), findsOneWidget);
    expect(tester.widget<IconButton>(_close).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('pdf-copy-name')),
      'copy.pdf',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save a copy'));
    await tester.pumpAndSettle();
    expect(store.writes, isEmpty);
    expect(store.copyNames, ['copy.pdf']);
    expect(find.text('sample.pdf *'), findsOneWidget);
  });
}
