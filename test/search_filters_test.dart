// test/search_filters_test.dart
//
// Tests for SearchNotifier filter logic (type, size, date) and the
// virtual-folder show-as-folder plumbing.
//
// All tests are pure-Dart — no Flutter widgets or real providers needed.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/search_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

FileItem _file(String name, {int? size, DateTime? updatedAt}) =>
    FileItem(name: name, path: '/$name', isFolder: false, size: size, updatedAt: updatedAt);

FileItem _folder(String name) =>
    FileItem(name: name, path: '/$name', isFolder: true);

ProviderContainer _makeContainer() {
  SharedPreferences.setMockInitialValues({});
  final secureStorage = InMemorySecureStorage();
  final configService = FilenConfigService(
    configPath: '/tmp/search_filters_test_config',
    secureStorage: secureStorage,
  );
  return ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(secureStorage),
      configPathProvider.overrideWithValue('/tmp/search_filters_test_config'),
      authProvider.overrideWith((ref) => AuthNotifier(
            ref,
            initialProvider: CloudProvider.filen,
            config: configService,
            configPath: '/tmp/search_filters_test_config',
            secureStorage: secureStorage,
          )),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late ProviderContainer container;

  setUp(() {
    container = _makeContainer();
  });

  tearDown(() async {
    await Future.delayed(const Duration(milliseconds: 200));
    container.dispose();
  });

  // -------------------------------------------------------------------------
  // Type filter
  // -------------------------------------------------------------------------
  group('type filter', () {
    test('passes file whose extension is in the filter list', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByType: ['pdf', 'docx']);
      expect(search.matchesFilters(_file('report.pdf')), isTrue);
      expect(search.matchesFilters(_file('notes.docx')), isTrue);
    });

    test('rejects file whose extension is not in the filter list', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByType: ['pdf']);
      expect(search.matchesFilters(_file('photo.jpg')), isFalse);
    });

    test('passes any file when filter list is empty', () {
      final search = container.read(searchProvider);
      // default: no type filter
      expect(search.matchesFilters(_file('anything.xyz')), isTrue);
    });

    test('extension comparison is case-insensitive', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByType: ['png']);
      expect(search.matchesFilters(_file('image.PNG')), isTrue);
    });

    test('file with no extension fails when type filter is set', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByType: ['txt']);
      expect(search.matchesFilters(_file('Makefile')), isFalse);
    });

    test('folders always pass type filter', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByType: ['pdf']);
      expect(search.matchesFilters(_folder('docs')), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Size filter
  // -------------------------------------------------------------------------
  group('size filter', () {
    test('passes file within [minSize, maxSize]', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByMinSize: 1000, filterByMaxSize: 5000);
      expect(search.matchesFilters(_file('f.bin', size: 2500)), isTrue);
    });

    test('rejects file below minSize', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByMinSize: 2000);
      expect(search.matchesFilters(_file('tiny.bin', size: 500)), isFalse);
    });

    test('rejects file above maxSize', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByMaxSize: 1024);
      expect(search.matchesFilters(_file('big.bin', size: 2048)), isFalse);
    });

    test('passes file at exact minSize boundary (inclusive)', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByMinSize: 512);
      expect(search.matchesFilters(_file('exact.bin', size: 512)), isTrue);
    });

    test('passes file at exact maxSize boundary (inclusive)', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByMaxSize: 512);
      expect(search.matchesFilters(_file('exact.bin', size: 512)), isTrue);
    });

    test('file with null size is treated as 0 bytes for size filters', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByMinSize: 1);
      // size is null → treated as 0 → below min
      expect(search.matchesFilters(_file('nosize.bin')), isFalse);
    });

    test('folders skip size filter', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByMinSize: 1000000);
      expect(search.matchesFilters(_folder('big-folder')), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Date filter
  // -------------------------------------------------------------------------
  group('date filter', () {
    final jan = DateTime(2024, 1, 15);
    final mar = DateTime(2024, 3, 10);
    final jun = DateTime(2024, 6, 1);

    test('passes file within date range', () {
      final search = container.read(searchProvider);
      search.setFilters(
          filterByDateAfter: jan, filterByDateBefore: jun);
      expect(search.matchesFilters(_file('f.txt', updatedAt: mar)), isTrue);
    });

    test('rejects file before dateAfter', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByDateAfter: mar);
      expect(search.matchesFilters(_file('old.txt', updatedAt: jan)), isFalse);
    });

    test('rejects file after dateBefore', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByDateBefore: mar);
      expect(search.matchesFilters(_file('new.txt', updatedAt: jun)), isFalse);
    });

    test('rejects file with null date when date filter is active', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByDateAfter: jan);
      expect(search.matchesFilters(_file('nodateinfo.txt')), isFalse);
    });

    test('passes file on exact dateAfter boundary', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByDateAfter: mar);
      expect(search.matchesFilters(_file('f.txt', updatedAt: mar)), isTrue);
    });

    test('passes file on exact dateBefore boundary', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByDateBefore: mar);
      expect(search.matchesFilters(_file('f.txt', updatedAt: mar)), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Combined filters
  // -------------------------------------------------------------------------
  group('combined filters', () {
    test('all conditions must pass', () {
      final search = container.read(searchProvider);
      search.setFilters(
        filterByType: ['pdf'],
        filterByMinSize: 500,
        filterByMaxSize: 5000,
        filterByDateAfter: DateTime(2024, 1, 1),
      );

      // Passes all
      expect(
        search.matchesFilters(_file('doc.pdf',
            size: 1000, updatedAt: DateTime(2024, 6, 1))),
        isTrue,
      );

      // Wrong type
      expect(
        search.matchesFilters(_file('doc.txt',
            size: 1000, updatedAt: DateTime(2024, 6, 1))),
        isFalse,
      );

      // Too small
      expect(
        search.matchesFilters(_file('doc.pdf',
            size: 100, updatedAt: DateTime(2024, 6, 1))),
        isFalse,
      );

      // Too old
      expect(
        search.matchesFilters(_file('doc.pdf',
            size: 1000, updatedAt: DateTime(2023, 6, 1))),
        isFalse,
      );
    });
  });

  // -------------------------------------------------------------------------
  // clearFilters
  // -------------------------------------------------------------------------
  group('clearFilters', () {
    test('resets all filter fields', () {
      final search = container.read(searchProvider);
      search.setFilters(
        filterByType: ['pdf'],
        filterByMinSize: 100,
        filterByMaxSize: 999,
        filterByDateAfter: DateTime(2024),
        filterByDateBefore: DateTime(2025),
      );
      search.clearFilters();

      expect(search.filterByType, isEmpty);
      expect(search.filterByMinSize, isNull);
      expect(search.filterByMaxSize, isNull);
      expect(search.filterByDateAfter, isNull);
      expect(search.filterByDateBefore, isNull);
    });

    test('after clearFilters every file passes', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByType: ['pdf']);
      search.clearFilters();
      expect(search.matchesFilters(_file('image.jpg', size: 0)), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // applyFilters
  // -------------------------------------------------------------------------
  group('applyFilters', () {
    test('returns only matching items', () {
      final search = container.read(searchProvider);
      search.setFilters(filterByType: ['mp3', 'flac']);

      final items = [
        _file('song.mp3', size: 4000000),
        _file('photo.jpg', size: 2000000),
        _file('album.flac', size: 30000000),
        _folder('music'),
      ];
      final results = search.applyFilters(items);

      // mp3 and flac files pass; jpg does not; folder always passes
      expect(results.length, equals(3));
      expect(results.any((f) => f.name == 'song.mp3'), isTrue);
      expect(results.any((f) => f.name == 'album.flac'), isTrue);
      expect(results.any((f) => f.name == 'music'), isTrue);
      expect(results.any((f) => f.name == 'photo.jpg'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // extensionsForCategories helper
  // -------------------------------------------------------------------------
  group('extensionsForCategories', () {
    test('returns extensions for selected categories', () {
      final exts = extensionsForCategories({FileTypeCategory.images});
      expect(exts, containsAll(['jpg', 'jpeg', 'png', 'gif']));
    });

    test('returns empty list for empty set', () {
      final exts = extensionsForCategories({});
      expect(exts, isEmpty);
    });

    test('combines extensions from multiple categories', () {
      final exts = extensionsForCategories(
          {FileTypeCategory.audio, FileTypeCategory.archives});
      expect(exts, contains('mp3'));
      expect(exts, contains('zip'));
    });
  });

  // -------------------------------------------------------------------------
  // setSearchResults / showResultsAsFolder
  // -------------------------------------------------------------------------
  group('setSearchResults', () {
    test('stores results and sets showResultsAsFolder = false by default', () {
      final search = container.read(searchProvider);
      final items = [_file('a.txt'), _file('b.txt')];
      search.setSearchResults(items, asFolder: false);

      expect(search.searchResults.length, equals(2));
      expect(search.showResultsAsFolder, isFalse);
    });

    test('clearSearchResults resets results and flag', () {
      final search = container.read(searchProvider);
      search.setSearchResults([_file('a.txt')], asFolder: false);
      search.clearSearchResults();

      expect(search.searchResults, isEmpty);
      expect(search.showResultsAsFolder, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // PanelNotifier.showSearchResults integration
  // -------------------------------------------------------------------------
  group('PanelNotifier search results', () {
    test('showSearchResults sets showingSearchResults flag and updates files',
        () async {
      final panel = container.read(panelProvider(PanelSide.remote));
      await Future.delayed(Duration.zero); // let async init settle
      final items = [_file('result.txt', size: 100)];
      panel.showSearchResults(items);

      expect(panel.showingSearchResults, isTrue);
      expect(panel.files, isNotNull);
      expect(panel.files!.length, equals(1));
      expect(panel.files!.first.name, equals('result.txt'));
    });

    test('showingSearchResults is false initially', () {
      final panel = container.read(panelProvider(PanelSide.remote));
      expect(panel.showingSearchResults, isFalse);
    });
  });
}
