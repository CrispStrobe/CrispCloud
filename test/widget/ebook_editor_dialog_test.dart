import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/ebook_device_export.dart';
import 'package:crisp_cloud/services/ebook_annotations.dart';
import 'package:crisp_cloud/services/ebook_edit_session.dart';
import 'package:crisp_cloud/services/ebook_reading_data_files.dart';
import 'package:crisp_cloud/services/ebook_library.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:crisp_cloud/services/ebook_editor_menu.dart';
import 'package:crisp_cloud/services/ebook_file_store.dart';
import 'package:crisp_cloud/services/pdf_file_store.dart';
import 'package:crisp_cloud/widgets/ebook_editor_dialog.dart';
import 'package:crisp_cloud/widgets/ebook_chapter_reader.dart';
import 'package:crisp_cloud/widgets/ebook_prose_editor.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:crisperbooks/crisperbooks.dart' show EbookSpeechDialog;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:xml/xml.dart';

class _FailingAnnotationStore extends InMemorySharedPreferencesStore {
  _FailingAnnotationStore() : super.empty();

  int annotationWrites = 0;
  bool failNextAnnotationWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (key.startsWith('flutter.ebook.annotations.')) {
      annotationWrites++;
      if (failNextAnnotationWrite) {
        failNextAnnotationWrite = false;
        return Future.value(false);
      }
    }
    return super.setValue(valueType, key, value);
  }
}

class _SpeechTransport {
  CrispEbookController? controller;
  final calls = <String>[];
  var _status = 'stopped';
  var _revision = 0;

  Widget build(
    BuildContext context,
    Uint8List bytes,
    String filename,
    CrispEbookController reader,
  ) {
    if (controller != reader) {
      controller = reader;
      reader.attach(_send);
      reader.updateBookInfo(
        const EbookBookInfo(
          title: 'Original',
          authors: [],
          toc: [],
          sectionCount: 1,
          sourceFormat: 'epub',
        ),
      );
    }
    return const Text('Reader preview');
  }

  Future<dynamic> _send(String method, EbookJson args) async {
    calls.add(method);
    switch (method) {
      case 'speechStart':
      case 'speechResume':
        _status = 'speaking';
      case 'speechPause':
        _status = 'paused';
      case 'speechStop':
        _status = 'stopped';
    }
    return {
      'status': _status,
      'voices': [
        {'uri': 'local-en', 'name': 'English', 'language': 'en-US'},
      ],
      'voiceUri': 'local-en',
      'revision': ++_revision,
    };
  }
}

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
  EbookReaderBuilder? readerBuilder,
  EbookReadingDataPicker? readingDataPicker,
  EbookReadingDataExporter? readingDataExporter,
  Future<EbookLinuxHostStatus> Function()? linuxHostProbe,
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
                    readingDataPickerOverride: readingDataPicker,
                    readingDataExporterOverride: readingDataExporter,
                    linuxHostProbeOverride: linuxHostProbe,
                    documentLoaderOverride:
                        documentLoader ??
                        (bytes) async => EpubDocument.open(bytes),
                    readerBuilderOverride: portableReader
                        ? null
                        : readerBuilder ??
                              (_, _, _, _) => const Text('Reader preview'),
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
  if (expectDocument && startEditing) {
    expect(find.text('Original'), findsOneWidget);
  }
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
    'enhanced reader opens shared speech controls and sends local commands',
    (tester) async {
      final store = _Store();
      final speech = _SpeechTransport();
      await _open(
        tester,
        store,
        startEditing: false,
        readerBuilder: speech.build,
      );
      await tester.tap(find.byTooltip('Read aloud'));
      await tester.pumpAndSettle();
      expect(find.byType(EbookSpeechDialog), findsOneWidget);
      expect(speech.calls, ['speechStatus']);

      await tester.tap(find.byKey(const ValueKey('ebook-speech-primary')));
      await tester.pumpAndSettle();
      expect(speech.calls.last, 'speechStart');
      expect(find.text('Reading aloud'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ebook-speech-primary')));
      await tester.pumpAndSettle();
      expect(speech.calls.last, 'speechPause');
      expect(find.text('Read-aloud paused'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ebook-speech-primary')));
      await tester.pumpAndSettle();
      expect(speech.calls.last, 'speechResume');

      await tester.tap(find.byKey(const ValueKey('ebook-speech-close')));
      await tester.pumpAndSettle();
      expect(find.byType(EbookSpeechDialog), findsNothing);
      expect(speech.controller!.speech.isActive, isTrue);
      expect(store.writes, isEmpty);
    },
  );

  testWidgets(
    'reading data exports exact publication state without source access',
    (tester) async {
      final store = _Store();
      final notes = await EbookAnnotations.open(store.documentId, store.input);
      notes.bookmarks.add(
        const EbookLocation(cfi: 'epubcfi(/6/2!/4/2:0)', fraction: .25),
      );
      await notes.save();
      String? exported;
      String? filename;
      await _open(
        tester,
        store,
        readingDataExporter: (json, name) async {
          exported = json;
          filename = name;
          return EbookSaveOutcome.savedCopy;
        },
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export reading data'));
      await tester.pumpAndSettle();
      expect(filename, 'original.reading.json');
      final data = EbookReadingData.decode(exported!);
      expect(data.bookmarks, hasLength(1));
      expect(data.contentSha256, notes.contentSha256);
      expect(exported, isNot(contains('account-one')));
      expect(store.writes, isEmpty);
    },
  );

  testWidgets('import applies only after preview and preserves the book file', (
    tester,
  ) async {
    final store = _Store();
    final imported = await EbookAnnotations.open('another-device', store.input);
    imported.bookmarks.add(
      const EbookLocation(cfi: 'epubcfi(/6/2!/4/2:0)', fraction: .5),
    );
    await _open(
      tester,
      store,
      readingDataPicker: () async => imported.exportReadingData(),
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import reading data'));
    await tester.pumpAndSettle();
    expect(
      (await EbookAnnotations.open(store.documentId, store.input)).bookmarks,
      isEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('ebook-apply-reading-data')));
    await tester.pumpAndSettle();
    final saved = await EbookAnnotations.open(store.documentId, store.input);
    expect(saved.bookmarks.single.fraction, .5);
    expect(store.writes, isEmpty);
  });

  testWidgets(
    'stale reading state stays open and can be exported before explicit discard',
    (tester) async {
      final store = _Store();
      final initial = await EbookAnnotations.open(
        store.documentId,
        store.input,
      );
      initial.bookmarks.add(
        const EbookLocation(cfi: 'epubcfi(/6/2!/4/2:0)', fraction: .1),
      );
      await initial.save();
      String? rescued;
      await _open(
        tester,
        store,
        readingDataExporter: (json, _) async {
          rescued = json;
          return EbookSaveOutcome.savedCopy;
        },
      );
      final otherReader = await EbookAnnotations.open(
        store.documentId,
        store.input,
      );
      otherReader.bookmarks.add(
        const EbookLocation(cfi: 'epubcfi(/6/4!/4/2:0)', fraction: .7),
      );
      await otherReader.save();
      await tester.tap(_close);
      await tester.pumpAndSettle();
      expect(find.text('Reading data could not be saved'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Export reading data'));
      await tester.pumpAndSettle();
      expect(EbookReadingData.decode(rescued!).bookmarks, hasLength(1));
      expect(find.byType(EbookEditorDialog), findsOneWidget);
      expect(
        (await EbookAnnotations.open(store.documentId, store.input)).bookmarks,
        hasLength(2),
      );
      await tester.tap(_close);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Close without saving reading data'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EbookEditorDialog), findsNothing);
      expect(
        (await EbookAnnotations.open(store.documentId, store.input)).bookmarks,
        hasLength(2),
      );
    },
  );

  testWidgets(
    'explicit reading-data discard does not retry a transient write failure',
    (tester) async {
      final preferencesStore = _FailingAnnotationStore();
      SharedPreferencesStorePlatform.instance = preferencesStore;
      final store = _Store();
      await _open(
        tester,
        store,
        portableReader: true,
        startEditing: false,
        linuxHostProbe: () async => const EbookLinuxHostStatus(
          available: false,
          reason: 'Portable test reader',
        ),
      );
      final reader = tester.widget<EbookChapterReader>(
        find.byType(EbookChapterReader),
      );
      Map<String, Object> annotationValues(Map<String, Object> values) =>
          Map.fromEntries(
            values.entries.where(
              (entry) => entry.key.startsWith('flutter.ebook.annotations.'),
            ),
          );
      final saved = annotationValues(await preferencesStore.getAll());
      final writesBeforeClose = preferencesStore.annotationWrites;
      preferencesStore.failNextAnnotationWrite = true;
      await tester.tap(_close);
      await tester.pumpAndSettle();
      expect(find.text('Reading data could not be saved'), findsOneWidget);
      expect(preferencesStore.annotationWrites, writesBeforeClose + 1);

      // A delayed layout/relocation callback can arrive while the failure
      // prompt is open. It must not restart autosave before the user decides.
      reader.onLocationChanged(
        const EbookLocation(cfi: 'crisp-section:0', fraction: .9),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(preferencesStore.annotationWrites, writesBeforeClose + 1);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Close without saving reading data'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EbookEditorDialog), findsNothing);
      expect(preferencesStore.annotationWrites, writesBeforeClose + 1);
      expect(annotationValues(await preferencesStore.getAll()), saved);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'replacement without a location clears the displayed library progress',
    (tester) async {
      final store = _Store();
      final initial = await EbookAnnotations.open(
        store.documentId,
        store.input,
      );
      initial.location = const EbookLocation(
        cfi: 'epubcfi(/6/2!/4/2:0)',
        fraction: .8,
      );
      await initial.save();
      final imported = await EbookAnnotations.open('other-device', store.input);
      await _open(
        tester,
        store,
        readingDataPicker: () async => imported.exportReadingData(),
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import reading data'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ebook-reading-data-merge-mode')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace local reading data').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ebook-apply-reading-data')));
      await tester.pumpAndSettle();
      final library = await EbookLibrary.open();
      addTearDown(library.dispose);
      expect(library.entries.single.progress, isNull);
      expect(
        (await EbookAnnotations.open(store.documentId, store.input)).location,
        isNull,
      );
    },
  );

  testWidgets(
    'opening a book records a source-free library entry without inventing access',
    (tester) async {
      final store = _Store();
      await _open(tester, store);
      final library = await EbookLibrary.open();
      addTearDown(library.dispose);
      expect(library.entries, hasLength(1));
      expect(library.entries.single.title, 'Original');
      expect(library.entries.single.source, isNull);
      expect(library.entries.single.canLocateSource, isFalse);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ebook library'));
      await tester.pumpAndSettle();
      expect(
        find.text('Locate this file manually to read it again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Linux selects the shared engine only after a successful host probe',
    (tester) async {
      await _open(
        tester,
        _Store(),
        portableReader: true,
        startEditing: false,
        linuxHostProbe: () async =>
            const EbookLinuxHostStatus(available: true, version: 'test'),
      );
      expect(find.byType(CrispEbookReader), findsOneWidget);
      expect(find.byType(EbookChapterReader), findsNothing);
      // The platform host is absent in this widget-test process. Its instance
      // error offers a deliberate fallback without reusing Foliate locators.
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use portable EPUB reader').last);
      await tester.pumpAndSettle();
      expect(find.byType(EbookChapterReader), findsOneWidget);
      expect(find.byType(CrispEbookReader), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

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
      expect(find.byTooltip('Read aloud'), findsNothing);
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
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.key == const ValueKey('ebook-appearance-Theme'),
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
