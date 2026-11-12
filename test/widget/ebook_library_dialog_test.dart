import 'package:crisp_cloud/services/ebook_library.dart';
import 'package:crisp_cloud/widgets/ebook_library_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<EbookLibraryEntry> _book(
  EbookLibrary library,
  String title, {
  bool attachment = false,
}) => library.recordOpened(
  source: attachment
      ? null
      : FileReference(
          storage: const StorageReference(
            kind: 'remote',
            provider: 'cloud',
            accountKey: 'original-account',
          ),
          path: '/books/$title.epub',
        ),
  contentSha256: 'a' * 64,
  contentByteLength: 32,
  title: title,
  authors: const ['Reader Author'],
  format: 'epub',
  renderer: EbookReaderRenderer.foliate,
);

Future<void> _show(
  WidgetTester tester,
  EbookLibrary library, {
  void Function(EbookLibraryEntry)? onOpen,
  void Function(EbookLibraryEntry)? onLocate,
  String? currentEntryId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            child: const Text('Show library'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EbookLibraryDialog(
                library: library,
                currentEntryId: currentEntryId,
                onOpen: onOpen ?? (_) {},
                onLocate: onLocate ?? (_) {},
                errorMessage: (_) => 'Save failed; your draft is still here.',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Show library'));
  await tester.pumpAndSettle();
}

Future<void> _visible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('ebook-library-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'library filters combine search, favorites, exact tags and reading status',
    (tester) async {
      final library = await EbookLibrary.open();
      final alpha = await _book(library, 'Alpha astronomy');
      await _book(library, 'Beta botany');
      await library.update(
        alpha.id,
        favorite: true,
        tags: ['Science'],
        shelves: ['Study'],
        status: EbookReadingStatus.completed,
      );
      await _show(tester, library);
      expect(find.text('Books: 2'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('ebook-library-search')),
        'Alpha',
      );
      await tester.pumpAndSettle();
      expect(find.text('Books: 1'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('ebook-library-search')),
        '',
      );
      await tester.tap(
        find.byKey(const ValueKey('ebook-library-filter-favorites')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Books: 1'), findsOneWidget);
      final tag = find.byKey(const ValueKey('ebook-library-tag-filter'));
      await _visible(tester, tag);
      await tester.enterText(tag, 'No matching tag');
      await tester.pumpAndSettle();
      expect(find.text('Books: 0'), findsOneWidget);
      await tester.enterText(tag, 'science');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Books: 1'), findsOneWidget);
      final status = find.byKey(const ValueKey('ebook-library-status-filter'));
      await _visible(tester, status);
      await tester.tap(status);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unread').last);
      await tester.pumpAndSettle();
      expect(find.text('Books: 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source-free rows require locate and cannot invoke the open callback',
    (tester) async {
      final library = await EbookLibrary.open();
      final attachment = await _book(library, 'Attachment', attachment: true);
      final opened = <String>[];
      final located = <String>[];
      await _show(
        tester,
        library,
        onOpen: (row) => opened.add(row.id),
        onLocate: (row) => located.add(row.id),
      );
      final open = find.byKey(ValueKey('ebook-library-open-${attachment.id}'));
      await _visible(tester, open);
      expect(tester.widget<OutlinedButton>(open).onPressed, isNull);
      expect(
        find.text('Locate this file manually to read it again.'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(ValueKey('ebook-library-locate-${attachment.id}')),
      );
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(located, [attachment.id]);
    },
  );

  testWidgets('open callback receives the original saved account reference', (
    tester,
  ) async {
    final library = await EbookLibrary.open();
    final book = await _book(library, 'Saved source');
    EbookLibraryEntry? opened;
    await _show(
      tester,
      library,
      currentEntryId: book.id,
      onOpen: (row) => opened = row,
    );
    final open = find.byKey(ValueKey('ebook-library-open-${book.id}'));
    await _visible(tester, open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(opened!.source!.storage.accountKey, 'original-account');
    expect(opened!.source!.path, '/books/Saved source.epub');
    expect(find.text('Current book'), findsOneWidget);
  });

  testWidgets('failed library edit retains typed shelves and tags for retry', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    var fail = false;
    final library = await EbookLibrary.open(
      preferences: preferences,
      writePreference: (key, value) async {
        if (fail) return false;
        return preferences.setString(key, value);
      },
    );
    final book = await _book(library, 'Editable catalog row');
    await _show(tester, library);
    final edit = find.byKey(ValueKey('ebook-library-edit-${book.id}'));
    await _visible(tester, edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ebook-library-edit-shelves')),
      'Research\nTo read',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ebook-library-edit-tags')),
      'Physics\n日本語',
    );
    await tester.pump();
    final save = find.byKey(const ValueKey('ebook-library-edit-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    fail = true;
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ebook-library-edit-error')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('ebook-library-edit-shelves')),
          )
          .controller!
          .text,
      'Research\nTo read',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('ebook-library-edit-tags')),
          )
          .controller!
          .text,
      'Physics\n日本語',
    );
    expect(library.get(book.id)!.shelves, isEmpty);
    expect(library.get(book.id)!.tags, isEmpty);
    fail = false;
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(save, findsNothing);
    expect(library.get(book.id)!.shelves, ['Research', 'To read']);
    expect(library.get(book.id)!.tags, ['Physics', '日本語']);
  });

  testWidgets('favorite and confirmed removal update only the catalog', (
    tester,
  ) async {
    final library = await EbookLibrary.open();
    final book = await _book(library, 'Catalog actions');
    var accesses = 0;
    await _show(
      tester,
      library,
      onOpen: (_) => accesses++,
      onLocate: (_) => accesses++,
    );
    final favorite = find.byKey(ValueKey('ebook-library-favorite-${book.id}'));
    await _visible(tester, favorite);
    await tester.tap(favorite);
    await tester.pumpAndSettle();
    expect(library.get(book.id)!.favorite, isTrue);
    await tester.tap(find.byKey(ValueKey('ebook-library-remove-${book.id}')));
    await tester.pumpAndSettle();
    expect(library.get(book.id), isNotNull);
    await tester.tap(
      find.byKey(const ValueKey('ebook-library-confirm-remove')),
    );
    await tester.pumpAndSettle();
    expect(library.entries, isEmpty);
    expect(find.text('Books you open appear here.'), findsOneWidget);
    expect(accesses, 0);
  });

  testWidgets('narrow library and editor layouts remain scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = await EbookLibrary.open();
    final book = await _book(
      library,
      'A long title that should wrap into two readable lines',
    );
    await library.recordProgress(
      book.id,
      contentSha256: 'a' * 64,
      renderer: EbookReaderRenderer.foliate,
      fraction: .48,
    );
    await _show(tester, library);
    expect(tester.takeException(), isNull);
    final edit = find.byKey(ValueKey('ebook-library-edit-${book.id}'));
    await _visible(tester, edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final tags = find.byKey(const ValueKey('ebook-library-edit-tags'));
    await tester.ensureVisible(tags);
    await tester.enterText(tags, 'Narrow screen');
    await tester.pump();
    expect(tester.takeException(), isNull);
    final save = find.byKey(const ValueKey('ebook-library-edit-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(library.get(book.id)!.tags, ['Narrow screen']);
    expect(tester.takeException(), isNull);
  });
}
