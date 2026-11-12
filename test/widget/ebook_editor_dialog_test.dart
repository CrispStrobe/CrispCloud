import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/ebook_device_export.dart';
import 'package:crisp_cloud/services/ebook_annotations.dart';
import 'package:crisp_cloud/services/ebook_editor_menu.dart';
import 'package:crisp_cloud/services/ebook_file_store.dart';
import 'package:crisp_cloud/services/pdf_file_store.dart';
import 'package:crisp_cloud/widgets/ebook_editor_dialog.dart';
import 'package:crisp_cloud/widgets/ebook_chapter_reader.dart';
import 'package:crisp_cloud/widgets/ebook_prose_editor.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

class _Store implements PdfFileStore {
  _Store()
    : input = EpubDocument.create(
        title: 'Original',
        authors: ['Author'],
      ).toBytes();
  Uint8List input;
  final writes = <Uint8List>[];
  Future<PdfSaveOutcome> Function(Uint8List)? writer;
  @override
  String get documentId => 'account-one:/books/original.epub';
  @override
  String get displayName => 'original.epub';
  @override
  String get path => '/books/original.epub';
  @override
  bool get isRemote => true;
  @override
  Future<Uint8List> load() async => Uint8List.fromList(input);
  @override
  Future<PdfSaveOutcome> save(Uint8List bytes) async {
    writes.add(Uint8List.fromList(bytes));
    final outcome =
        await (writer?.call(bytes) ??
            Future.value(PdfSaveOutcome.savedOriginal));
    if (outcome == PdfSaveOutcome.savedOriginal) {
      input = Uint8List.fromList(bytes);
    }
    return outcome;
  }

  @override
  Future<PdfSaveOutcome> saveCopy(Uint8List bytes, String name) async =>
      PdfSaveOutcome.savedCopy;
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Store store, {
  EbookDeviceExporter? exporter,
  EbookDocumentLoader? documentLoader,
  bool expectDocument = true,
  bool portableReader = false,
  bool startEditing = true,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => Dialog.fullscreen(
                  child: EbookEditorDialog(
                    file: FileItem(name: 'original.epub', isFolder: false),
                    side: PanelSide.local,
                    startEditing: startEditing,
                    storeOverride: EbookFileStore(store),
                    deviceExporterOverride: exporter,
                    documentLoaderOverride:
                        documentLoader ??
                        (bytes) async => EpubDocument.open(bytes),
                    readerBuilderOverride: portableReader
                        ? null
                        : (_, _, _, _) => const Text('Reader preview'),
                  ),
                ),
              ),
              child: const Text('Open book'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open book'));
  await tester.pumpAndSettle();
  expect(find.byType(EbookEditorDialog), findsOneWidget);
  if (expectDocument && startEditing)
    expect(find.text('Original'), findsOneWidget);
  return container;
}

Finder get _titleField => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == 'Title',
);
Finder get _save => find.byKey(const ValueKey('ebook-save'));
Finder get _close => find.descendant(
  of: find.byType(AppBar).first,
  matching: find.byTooltip('Close'),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'formatted prose integrates with undo, redo and original-file save',
    (tester) async {
      final store = _Store();
      final book = EpubDocument.open(store.input);
      final path = book.chapters.first.path;
      book.updateText(
        path,
        '<html xmlns="http://www.w3.org/1999/xhtml">'
        '<head><title>Text</title></head><body><p id="p">Before '
        '<em id="em">tyop</em> <a href="#p">link</a></p></body></html>',
      );
      store.input = book.toBytes();
      final container = await _open(tester, store);
      await tester.tap(find.text('Resources'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Text').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Before tyop link'));
      await tester.pumpAndSettle();
      expect(find.byType(EbookProseEditorDialog), findsOneWidget);
      final field = find.byKey(const ValueKey('ebook-prose-segment-1'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'typo');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(EbookProseEditorDialog),
          matching: find.widgetWithText(FilledButton, 'Apply'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Before typo link'), findsOneWidget);
      container
          .read(ebookEditorMenuProvider)!
          .perform(EbookEditorMenuAction.undo);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Before tyop link'), findsOneWidget);
      container
          .read(ebookEditorMenuProvider)!
          .perform(EbookEditorMenuAction.redo);
      await tester.pumpAndSettle();
      await tester.tap(_save);
      await tester.pumpAndSettle();
      final saved = EpubDocument.open(store.writes.single);
      final xml = XmlDocument.parse(saved.readText(path));
      final emphasis = xml.descendants.whereType<XmlElement>().singleWhere(
        (e) => e.name.local == 'em',
      );
      final link = xml.descendants.whereType<XmlElement>().singleWhere(
        (e) => e.name.local == 'a',
      );
      expect(emphasis.innerText, 'typo');
      expect(emphasis.getAttribute('id'), 'em');
      expect(link.getAttribute('href'), '#p');
    },
  );

  testWidgets('plain paragraph mode retains newline authoring through save', (
    tester,
  ) async {
    final store = _Store();
    final book = EpubDocument.open(store.input);
    final path = book.chapters.first.path;
    book.updateText(
      path,
      '<html xmlns="http://www.w3.org/1999/xhtml">'
      '<head><title>Text</title></head><body><p>First</p></body></html>',
    );
    store.input = book.toBytes();
    await _open(tester, store);
    await tester.tap(find.text('Resources'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'First'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ebook-prose-plain-text')),
      'First\nSecond',
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(EbookProseEditorDialog),
        matching: find.widgetWithText(FilledButton, 'Apply'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    final saved = EpubDocument.open(store.writes.single);
    expect(saved.readText(path), contains('First<br/>Second'));
  });

  testWidgets(
    'portable reader shares search, immediate bookmarks and persisted appearance',
    (tester) async {
      final store = _Store();
      final book = EpubDocument.open(store.input);
      book.addChapter(title: 'Second chapter', text: 'Only in second chapter');
      store.input = book.toBytes();
      await _open(tester, store, portableReader: true);
      await tester.tap(find.text('Read').first);
      await tester.pumpAndSettle();
      expect(find.byType(EbookChapterReader), findsOneWidget);
      final addBookmark = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Add bookmark',
      );
      expect(tester.widget<IconButton>(addBookmark).onPressed, isNotNull);
      await tester.tap(addBookmark);
      await tester.pump(const Duration(milliseconds: 600));
      final search = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Search',
      );
      await tester.enterText(search, 'Only in second');
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      final result = find.byWidgetPredicate(
        (w) =>
            w is ListTile &&
            w.title is Text &&
            ((w.title as Text).data?.contains('Only in second') ?? false),
      );
      expect(result, findsOneWidget);
      await tester.tap(result);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is DropdownButton<String> && w.value == 'light',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('dark').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      final annotations = await EbookAnnotations.open(
        'account-one:/books/original.epub:chapter-reader',
        store.input,
      );
      expect(annotations.bookmarks, hasLength(1));
      expect(annotations.bookmarks.single.cfi, startsWith('crisp-reader:v1:'));
      expect(annotations.location!.sectionIndex, 1);
      expect(annotations.appearance.theme, 'dark');
      expect(annotations.appearance.flow, 'scrolled');
      await tester.tap(_close);
      await tester.pumpAndSettle();
      await _open(tester, store, portableReader: true, startEditing: false);
      await tester.pumpAndSettle();
      final reader = tester.widget<EbookChapterReader>(
        find.byType(EbookChapterReader),
      );
      expect(reader.appearance.theme, 'dark');
      expect(reader.initialLocation, annotations.location!.cfi);
      await tester.tap(find.byTooltip('Bookmarks'));
      await tester.pumpAndSettle();
      final bookmark = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ListTile),
      );
      expect(bookmark, findsOneWidget);
      await tester.tap(bookmark);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  test('ebook routing uses only complete supported extensions', () {
    for (final name in [
      'book.EPUB',
      'book.mobi',
      'book.azw3',
      'book.fb2',
      'book.cbz',
    ]) {
      expect(isEbookFileName(name), isTrue, reason: name);
    }
    for (final name in [
      'README',
      'epub',
      'mobi',
      '.epub',
      'book.epub.zip',
      'book.mobi.',
      'book.kfx',
      'book.pdf',
    ]) {
      expect(isEbookFileName(name), isFalse, reason: name);
    }
  });

  testWidgets(
    'metadata save preserves chapter data and acknowledges original',
    (tester) async {
      final store = _Store();
      final before = EpubDocument.open(store.input);
      await _open(tester, store);
      await tester.enterText(_titleField, 'Edited title');
      await tester.pump();
      expect(find.text('* original.epub'), findsOneWidget);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(store.writes, hasLength(1));
      final saved = EpubDocument.open(store.writes.single);
      expect(saved.title, 'Edited title');
      for (final chapter in before.chapters) {
        expect(
          saved.readBytes(chapter.path),
          orderedEquals(before.readBytes(chapter.path)),
        );
      }
      expect(find.text('* original.epub'), findsNothing);
    },
  );

  testWidgets('failed upload keeps edits and close can retry', (tester) async {
    final store = _Store()
      ..writer = (_) async => throw StateError('upload failed');
    await _open(tester, store);
    await tester.enterText(_titleField, 'Keep this edit');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.text('upload failed'), findsOneWidget);
    expect(find.text('* original.epub'), findsOneWidget);
    store.writer = null;
    await tester.tap(_close);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ebook-unsaved-dialog')),
        matching: find.text('Save'),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.writes, hasLength(2));
    expect(EpubDocument.open(store.input).title, 'Keep this edit');
    expect(find.byType(EbookEditorDialog), findsNothing);
  });

  testWidgets('new drafts typed during upload remain unsaved', (tester) async {
    final upload = Completer<PdfSaveOutcome>();
    final store = _Store()..writer = (_) => upload.future;
    await _open(tester, store);
    await tester.enterText(_titleField, 'Submitted title');
    await tester.pump();
    await tester.tap(_save);
    await tester.pump();
    expect(store.writes, hasLength(1));
    await tester.enterText(_titleField, 'Newer title');
    upload.complete(PdfSaveOutcome.savedOriginal);
    await tester.pumpAndSettle();
    expect(EpubDocument.open(store.input).title, 'Submitted title');
    expect(find.text('* original.epub'), findsOneWidget);
    expect(tester.widget<IconButton>(_save).onPressed, isNotNull);
  });

  testWidgets('browser-style copy outcome stays dirty and close is explicit', (
    tester,
  ) async {
    final store = _Store()..writer = (_) async => PdfSaveOutcome.downloadedCopy;
    final original = Uint8List.fromList(store.input);
    await _open(tester, store);
    await tester.enterText(_titleField, 'Downloaded title');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(store.input, orderedEquals(original));
    expect(find.text('* original.epub'), findsOneWidget);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'A separate copy was exported. Close and leave the original unchanged?',
      ),
      findsOneWidget,
    );
  });

  testWidgets('closing removes only this editor’s native menu', (tester) async {
    final container = await _open(tester, _Store());
    expect(container.read(ebookEditorMenuProvider), isNotNull);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(container.read(ebookEditorMenuProvider), isNull);
  });

  testWidgets('legacy fallback previews drafts without writing or rerouting', (
    tester,
  ) async {
    final store = _Store();
    await _open(tester, store);
    await tester.enterText(_titleField, 'Unsaved fallback title');
    await tester.pump();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ebook-text-fallback-menu')));
    await tester.pumpAndSettle();
    final fallback = tester.widget<InternalViewerDialog>(
      find.byType(InternalViewerDialog),
    );
    expect(fallback.displayName, 'original.epub');
    expect(
      EpubDocument.open(fallback.bytesOverride!).title,
      'Unsaved fallback title',
    );
    expect(store.writes, isEmpty);
    Navigator.of(tester.element(find.byType(InternalViewerDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(InternalViewerDialog), findsNothing);
    expect(find.text('* original.epub'), findsOneWidget);
    expect(
      tester.widget<TextField>(_titleField).controller!.text,
      'Unsaved fallback title',
    );
  });

  testWidgets('strict package load failure keeps the text fallback available', (
    tester,
  ) async {
    final store = _Store();
    await _open(
      tester,
      store,
      documentLoader: (_) async => throw StateError('Strict package failure'),
      expectDocument: false,
    );
    expect(find.text('Strict package failure'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ebook-text-fallback')));
    await tester.pumpAndSettle();
    final fallback = tester.widget<InternalViewerDialog>(
      find.byType(InternalViewerDialog),
    );
    expect(fallback.bytesOverride, orderedEquals(store.input));
    expect(store.writes, isEmpty);
    expect(
      find.descendant(
        of: find.byType(InternalViewerDialog),
        matching: find.text('Strict package failure'),
      ),
      findsNothing,
    );
  });

  testWidgets('existing chapter defects do not block legacy text extraction', (
    tester,
  ) async {
    final store = _Store();
    final chapter = EpubDocument.open(store.input).chapters.first.path;
    final archive = Archive();
    for (final entry in ZipDecoder().decodeBytes(store.input).files) {
      archive.addFile(
        entry.name == chapter
            ? ArchiveFile.bytes(
                chapter,
                utf8.encode('<html><body><p>Recoverable legacy text'),
              )
            : entry,
      );
    }
    store.input = Uint8List.fromList(ZipEncoder().encode(archive));
    await _open(tester, store);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ebook-text-fallback-menu')));
    await tester.pumpAndSettle();
    final fallback = tester.widget<InternalViewerDialog>(
      find.byType(InternalViewerDialog),
    );
    expect(fallback.bytesOverride, orderedEquals(store.input));
    expect(store.writes, isEmpty);
  });

  testWidgets(
    'invalid source drafts survive fallback to the last readable copy',
    (tester) async {
      final store = _Store();
      await _open(tester, store);
      await tester.tap(find.text('Resources'));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<CodeEditor>(find.byType(CodeEditor))
          .controller!;
      const draft = '<html><body><p>Still writing this chapter';
      controller.text = draft;
      await tester.pump();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ebook-text-fallback-menu')));
      await tester.pumpAndSettle();
      final fallback = tester.widget<InternalViewerDialog>(
        find.byType(InternalViewerDialog),
      );
      expect(fallback.bytesOverride, orderedEquals(store.input));
      expect(
        find.text(
          'Showing the last readable version. Your edits are still kept in the editor.',
        ),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(InternalViewerDialog))).pop();
      await tester.pumpAndSettle();
      expect(controller.text, draft);
      expect(find.text('* original.epub'), findsOneWidget);
      expect(store.writes, isEmpty);
    },
  );

  testWidgets('native close cannot target a child route or bypass dirty Back', (
    tester,
  ) async {
    final store = _Store();
    final container = await _open(tester, store);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ebook-text-fallback-menu')));
    await tester.pumpAndSettle();
    container
        .read(ebookEditorMenuProvider)!
        .perform(EbookEditorMenuAction.close);
    await tester.pumpAndSettle();
    expect(find.byType(InternalViewerDialog), findsOneWidget);
    Navigator.of(tester.element(find.byType(InternalViewerDialog))).pop();
    await tester.pumpAndSettle();
    await tester.enterText(_titleField, 'Do not discard this edit');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ebook-unsaved-dialog')), findsOneWidget);
    expect(store.writes, isEmpty);
  });

  testWidgets('a corrupt cover does not replace the editor with an error', (
    tester,
  ) async {
    final store = _Store();
    final document = EpubDocument.open(store.input)
      ..replaceCover(Uint8List.fromList([1, 2, 3]), mediaType: 'image/png');
    final bytes = document.toBytes();
    final data = ByteData.sublistView(bytes);
    var corrupted = false;
    for (var offset = 0; offset + 46 < bytes.length; offset++) {
      if (data.getUint32(offset, Endian.little) != 0x02014b50) continue;
      final nameLength = data.getUint16(offset + 28, Endian.little);
      final name = utf8.decode(
        bytes.sublist(offset + 46, offset + 46 + nameLength),
      );
      if (name != document.coverPath) continue;
      final local = data.getUint32(offset + 42, Endian.little);
      final crc = data.getUint32(offset + 16, Endian.little) ^ 1;
      data.setUint32(offset + 16, crc, Endian.little);
      data.setUint32(local + 14, crc, Endian.little);
      corrupted = true;
      break;
    }
    expect(corrupted, isTrue);
    store.input = bytes;
    await _open(tester, store);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(_titleField, findsOneWidget);
    expect(_close, findsOneWidget);
  });
}
