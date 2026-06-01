// test/storage_analytics_test.dart
//
// Tests for StorageAnalyticsService: categorization, breakdown calculation,
// duplicate detection, stale-file detection, largest-file ranking,
// cleanup suggestions, savings estimation, and model serialization.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/storage_analytics_service.dart';
import 'package:crisp_cloud/models/file_item.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

FileItem _file(
  String name, {
  int? size,
  DateTime? updatedAt,
  String? path,
}) =>
    FileItem(
      name: name,
      isFolder: false,
      size: size,
      updatedAt: updatedAt,
      path: path ?? '/$name',
    );

FileItem _folder(String name) =>
    FileItem(name: name, isFolder: true);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late StorageAnalyticsService svc;

  setUp(() {
    svc = StorageAnalyticsService();
  });

  // =========================================================================
  // File categorization
  // =========================================================================

  group('categorizeFile', () {
    test('documents — pdf', () {
      expect(svc.categorizeFile('report.pdf'), FileCategory.documents);
    });

    test('documents — docx', () {
      expect(svc.categorizeFile('letter.docx'), FileCategory.documents);
    });

    test('documents — xlsx', () {
      expect(svc.categorizeFile('budget.xlsx'), FileCategory.documents);
    });

    test('documents — markdown', () {
      expect(svc.categorizeFile('README.md'), FileCategory.documents);
    });

    test('documents — csv', () {
      expect(svc.categorizeFile('data.csv'), FileCategory.documents);
    });

    test('images — jpg', () {
      expect(svc.categorizeFile('photo.jpg'), FileCategory.images);
    });

    test('images — JPEG uppercase ext', () {
      expect(svc.categorizeFile('IMG_001.JPEG'), FileCategory.images);
    });

    test('images — png', () {
      expect(svc.categorizeFile('screenshot.png'), FileCategory.images);
    });

    test('images — svg', () {
      expect(svc.categorizeFile('icon.svg'), FileCategory.images);
    });

    test('images — heic', () {
      expect(svc.categorizeFile('photo.heic'), FileCategory.images);
    });

    test('images — psd', () {
      expect(svc.categorizeFile('design.psd'), FileCategory.images);
    });

    test('videos — mp4', () {
      expect(svc.categorizeFile('movie.mp4'), FileCategory.videos);
    });

    test('videos — mkv', () {
      expect(svc.categorizeFile('episode.mkv'), FileCategory.videos);
    });

    test('videos — avi', () {
      expect(svc.categorizeFile('clip.avi'), FileCategory.videos);
    });

    test('videos — mov', () {
      expect(svc.categorizeFile('screen.mov'), FileCategory.videos);
    });

    test('audio — mp3', () {
      expect(svc.categorizeFile('song.mp3'), FileCategory.audio);
    });

    test('audio — flac', () {
      expect(svc.categorizeFile('lossless.flac'), FileCategory.audio);
    });

    test('audio — wav', () {
      expect(svc.categorizeFile('sample.wav'), FileCategory.audio);
    });

    test('code — dart', () {
      expect(svc.categorizeFile('main.dart'), FileCategory.code);
    });

    test('code — py', () {
      expect(svc.categorizeFile('script.py'), FileCategory.code);
    });

    test('code — json', () {
      expect(svc.categorizeFile('config.json'), FileCategory.code);
    });

    test('code — yaml', () {
      expect(svc.categorizeFile('pubspec.yaml'), FileCategory.code);
    });

    test('code — sh', () {
      expect(svc.categorizeFile('deploy.sh'), FileCategory.code);
    });

    test('archives — zip', () {
      expect(svc.categorizeFile('backup.zip'), FileCategory.archives);
    });

    test('archives — tar.gz last ext is gz', () {
      expect(svc.categorizeFile('archive.tar.gz'), FileCategory.archives);
    });

    test('archives — 7z', () {
      expect(svc.categorizeFile('files.7z'), FileCategory.archives);
    });

    test('archives — rar', () {
      expect(svc.categorizeFile('files.rar'), FileCategory.archives);
    });

    test('archives — iso', () {
      expect(svc.categorizeFile('disk.iso'), FileCategory.archives);
    });

    test('databases — sqlite', () {
      expect(svc.categorizeFile('app.sqlite'), FileCategory.databases);
    });

    test('databases — sql', () {
      expect(svc.categorizeFile('dump.sql'), FileCategory.databases);
    });

    test('databases — db', () {
      expect(svc.categorizeFile('store.db'), FileCategory.databases);
    });

    test('fonts — ttf', () {
      expect(svc.categorizeFile('font.ttf'), FileCategory.fonts);
    });

    test('fonts — woff2', () {
      expect(svc.categorizeFile('icon.woff2'), FileCategory.fonts);
    });

    test('other — unknown extension', () {
      expect(svc.categorizeFile('file.xyz123'), FileCategory.other);
    });

    test('other — no extension', () {
      expect(svc.categorizeFile('Makefile'), FileCategory.other);
    });

    test('other — trailing dot', () {
      expect(svc.categorizeFile('file.'), FileCategory.other);
    });

    test('other — empty string', () {
      expect(svc.categorizeFile(''), FileCategory.other);
    });

    test('multiple dots — uses last extension', () {
      // "my.backup.2024.tar" → ext = "tar" → archives
      expect(svc.categorizeFile('my.backup.2024.tar'), FileCategory.archives);
    });

    test('case insensitive — PDF uppercase', () {
      expect(svc.categorizeFile('DOCUMENT.PDF'), FileCategory.documents);
    });
  });

  // =========================================================================
  // StorageBreakdown
  // =========================================================================

  group('analyzeProvider', () {
    test('empty provider returns zero totals', () {
      final bd = svc.analyzeProvider('p1', []);
      expect(bd.usedBytes, 0);
      expect(bd.categoryBreakdowns[FileCategory.documents]!.fileCount, 0);
    });

    test('single file — correct category count and bytes', () {
      final files = [_file('note.txt', size: 1024)];
      final bd = svc.analyzeProvider('p1', files);
      expect(bd.usedBytes, 1024);
      expect(
          bd.categoryBreakdowns[FileCategory.documents]!.fileCount, 1);
      expect(
          bd.categoryBreakdowns[FileCategory.documents]!.totalBytes, 1024);
    });

    test('folders are excluded from totals', () {
      final files = [
        _folder('docs'),
        _file('note.txt', size: 512),
      ];
      final bd = svc.analyzeProvider('p1', files);
      expect(bd.usedBytes, 512);
    });

    test('percentages sum to ~100 for non-empty provider', () {
      final files = [
        _file('a.pdf', size: 300),
        _file('b.jpg', size: 300),
        _file('c.mp4', size: 400),
      ];
      final bd = svc.analyzeProvider('p1', files);
      final total = bd.categoryBreakdowns.values
          .fold<double>(0, (s, v) => s + v.percentage);
      expect(total, closeTo(100.0, 0.01));
    });

    test('all-zero sizes produce 0% percentages', () {
      final files = [_file('a.pdf', size: 0)];
      final bd = svc.analyzeProvider('p1', files);
      for (final cat in FileCategory.values) {
        expect(bd.categoryBreakdowns[cat]!.percentage, 0.0);
      }
    });

    test('correct per-category split', () {
      final files = [
        _file('doc.pdf', size: 200),
        _file('img.png', size: 800),
      ];
      final bd = svc.analyzeProvider('p1', files);
      expect(bd.categoryBreakdowns[FileCategory.documents]!.percentage,
          closeTo(20.0, 0.01));
      expect(bd.categoryBreakdowns[FileCategory.images]!.percentage,
          closeTo(80.0, 0.01));
    });

    test('providerId is stored on breakdown', () {
      final bd = svc.analyzeProvider('my-s3', []);
      expect(bd.providerId, 'my-s3');
    });

    test('multiple files of same category accumulate correctly', () {
      final files = [
        _file('a.mp3', size: 1000),
        _file('b.wav', size: 2000),
        _file('c.flac', size: 3000),
      ];
      final bd = svc.analyzeProvider('p1', files);
      final audio = bd.categoryBreakdowns[FileCategory.audio]!;
      expect(audio.fileCount, 3);
      expect(audio.totalBytes, 6000);
    });
  });

  // =========================================================================
  // Stale files
  // =========================================================================

  group('findStaleFiles', () {
    test('files older than threshold are returned', () {
      final old = _file('old.pdf',
          size: 1000,
          updatedAt: DateTime.now().subtract(const Duration(days: 200)));
      final stale = svc.findStaleFiles([old], 180, providerId: 'p1');
      expect(stale.length, 1);
      expect(stale.first.path, '/old.pdf');
      expect(stale.first.provider, 'p1');
    });

    test('files newer than threshold are excluded', () {
      final recent = _file('new.pdf',
          size: 1000,
          updatedAt: DateTime.now().subtract(const Duration(days: 10)));
      final stale = svc.findStaleFiles([recent], 180);
      expect(stale, isEmpty);
    });

    test('boundary: exactly at threshold is stale', () {
      final boundary = _file('edge.pdf',
          size: 500,
          updatedAt: DateTime.now().subtract(const Duration(days: 180)));
      final stale = svc.findStaleFiles([boundary], 180);
      expect(stale.length, 1);
    });

    test('files without updatedAt are skipped', () {
      final noDate = _file('nodate.pdf', size: 500);
      final stale = svc.findStaleFiles([noDate], 30);
      expect(stale, isEmpty);
    });

    test('folders are excluded from stale list', () {
      final folder = _folder('old_folder');
      final stale = svc.findStaleFiles([folder], 0);
      expect(stale, isEmpty);
    });

    test('configurable staleDays threshold', () {
      final files = [
        _file('a.txt',
            size: 100,
            updatedAt: DateTime.now().subtract(const Duration(days: 30))),
        _file('b.txt',
            size: 200,
            updatedAt: DateTime.now().subtract(const Duration(days: 60))),
      ];
      expect(svc.findStaleFiles(files, 20).length, 2);
      expect(svc.findStaleFiles(files, 45).length, 1);
      expect(svc.findStaleFiles(files, 90).length, 0);
    });

    test('stale files sorted largest first', () {
      final files = [
        _file('small.txt',
            size: 100,
            updatedAt: DateTime.now().subtract(const Duration(days: 200))),
        _file('large.pdf',
            size: 9000,
            updatedAt: DateTime.now().subtract(const Duration(days: 200))),
      ];
      final stale = svc.findStaleFiles(files, 180);
      expect(stale.first.sizeBytes, 9000);
    });

    test('daysSinceAccess is computed correctly', () {
      final dt = DateTime.now().subtract(const Duration(days: 365));
      final f = _file('old.pdf', size: 100, updatedAt: dt);
      final stale = svc.findStaleFiles([f], 180);
      expect(stale.first.daysSinceAccess, greaterThanOrEqualTo(365));
    });
  });

  // =========================================================================
  // Largest files
  // =========================================================================

  group('findLargestFiles', () {
    test('returns top N files sorted descending', () {
      final files = [
        _file('a.mp4', size: 100),
        _file('b.mp4', size: 500),
        _file('c.mp4', size: 300),
        _file('d.mp4', size: 700),
        _file('e.mp4', size: 200),
      ];
      final top3 = svc.findLargestFiles(files, 3);
      expect(top3.length, 3);
      expect(top3.map((f) => f.size).toList(), [700, 500, 300]);
    });

    test('returns all files if fewer than topN', () {
      final files = [_file('x.zip', size: 1000)];
      expect(svc.findLargestFiles(files, 10).length, 1);
    });

    test('empty list returns empty', () {
      expect(svc.findLargestFiles([], 5), isEmpty);
    });

    test('folders excluded', () {
      final items = [
        _folder('big_folder'),
        _file('file.zip', size: 999),
      ];
      final top = svc.findLargestFiles(items, 5);
      expect(top.length, 1);
      expect(top.first.name, 'file.zip');
    });

    test('files with null size excluded', () {
      final items = [
        _file('no_size.bin'),
        _file('with_size.bin', size: 500),
      ];
      final top = svc.findLargestFiles(items, 5);
      expect(top.length, 1);
      expect(top.first.size, 500);
    });

    test('topN=1 returns single largest', () {
      final files = [
        _file('a.bin', size: 200),
        _file('b.bin', size: 800),
      ];
      final top = svc.findLargestFiles(files, 1);
      expect(top.length, 1);
      expect(top.first.size, 800);
    });
  });

  // =========================================================================
  // Cross-provider duplicate detection
  // =========================================================================

  group('findDuplicatesAcrossProviders', () {
    test('identical name and size across two providers detected', () {
      final allFiles = {
        'filen': [_file('video.mp4', size: 2 * 1024 * 1024 * 1024)],
        's3': [_file('video.mp4', size: 2 * 1024 * 1024 * 1024)],
      };
      final dups = svc.findDuplicatesAcrossProviders(allFiles);
      expect(dups.length, 1);
      expect(dups.first.entries.length, 2);
    });

    test('three-way duplicate detected', () {
      final size = 500 * 1024 * 1024;
      final allFiles = {
        'filen': [_file('backup.zip', size: size)],
        's3': [_file('backup.zip', size: size)],
        'local': [_file('backup.zip', size: size)],
      };
      final dups = svc.findDuplicatesAcrossProviders(allFiles);
      expect(dups.length, 1);
      expect(dups.first.entries.length, 3);
    });

    test('different size — not a duplicate', () {
      final allFiles = {
        'filen': [_file('report.pdf', size: 1000)],
        's3': [_file('report.pdf', size: 2000)],
      };
      final dups = svc.findDuplicatesAcrossProviders(allFiles);
      expect(dups, isEmpty);
    });

    test('same size but different name — not a duplicate', () {
      final allFiles = {
        'filen': [_file('a.pdf', size: 1000)],
        's3': [_file('b.pdf', size: 1000)],
      };
      final dups = svc.findDuplicatesAcrossProviders(allFiles);
      expect(dups, isEmpty);
    });

    test('name matching is case-insensitive', () {
      final allFiles = {
        'filen': [_file('Photo.JPG', size: 3000)],
        's3': [_file('photo.jpg', size: 3000)],
      };
      final dups = svc.findDuplicatesAcrossProviders(allFiles);
      expect(dups.length, 1);
    });

    test('zero-size files are excluded', () {
      final allFiles = {
        'filen': [_file('empty.txt', size: 0)],
        's3': [_file('empty.txt', size: 0)],
      };
      final dups = svc.findDuplicatesAcrossProviders(allFiles);
      expect(dups, isEmpty);
    });

    test('folders are excluded', () {
      final allFiles = {
        'filen': [_folder('docs')],
        's3': [_folder('docs')],
      };
      final dups = svc.findDuplicatesAcrossProviders(allFiles);
      expect(dups, isEmpty);
    });

    test('empty providers map returns empty', () {
      final dups = svc.findDuplicatesAcrossProviders({});
      expect(dups, isEmpty);
    });

    test('single provider — no cross-provider duplicates', () {
      final allFiles = {
        'filen': [
          _file('a.mp4', size: 100),
          _file('a.mp4', size: 100), // same provider, same name+size
        ],
      };
      // Two entries in same provider — still flagged as duplicate group
      // because duplicates can be within-provider too.
      final dups = svc.findDuplicatesAcrossProviders(allFiles);
      expect(dups.length, 1);
    });

    test('wastedBytes computed correctly for two copies', () {
      const size = 2 * 1024 * 1024 * 1024; // 2 GB
      final allFiles = {
        'filen': [_file('video.mp4', size: size)],
        's3': [_file('video.mp4', size: size)],
      };
      final dups = svc.findDuplicatesAcrossProviders(allFiles);
      // 2 copies → 1 wasted copy
      expect(dups.first.wastedBytes, size);
    });

    test('groups sorted by wastedBytes descending', () {
      final allFiles = {
        'p1': [
          _file('small.txt', size: 100),
          _file('large.bin', size: 100000),
        ],
        'p2': [
          _file('small.txt', size: 100),
          _file('large.bin', size: 100000),
        ],
      };
      final dups = svc.findDuplicatesAcrossProviders(allFiles);
      expect(dups.first.wastedBytes,
          greaterThan(dups.last.wastedBytes));
    });
  });

  // =========================================================================
  // Cleanup suggestions
  // =========================================================================

  group('generateCleanupSuggestions', () {
    test('returns duplicate suggestion for duplicate group', () {
      const size = 500 * 1024 * 1024;
      final dups = [
        DuplicateGroup(
          key: '$size:video.mp4',
          entries: [
            DuplicateEntry(
                path: '/video.mp4', provider: 'filen', sizeBytes: size),
            DuplicateEntry(
                path: '/video.mp4', provider: 's3', sizeBytes: size),
          ],
        ),
      ];
      final suggestions = svc.generateCleanupSuggestions([], dups, []);
      expect(suggestions.any((s) => s.type == CleanupType.duplicate), isTrue);
    });

    test('returns stale suggestion when stale files exist', () {
      final stales = [
        StaleFile(
          path: '/old.pdf',
          provider: 'p1',
          sizeBytes: 10000,
          daysSinceAccess: 365,
        ),
      ];
      final suggestions =
          svc.generateCleanupSuggestions([], [], stales);
      expect(suggestions.any((s) => s.type == CleanupType.stale), isTrue);
    });

    test('returns large-file suggestion for files ≥100 MB', () {
      final bigFile = _file('bigvideo.mp4', size: 200 * 1024 * 1024);
      final breakdown = StorageBreakdown(
        providerId: 'p1',
        totalBytes: 0,
        usedBytes: bigFile.size!,
        freeBytes: 0,
        categoryBreakdowns: {},
        staleFiles: [],
        largestFiles: [bigFile],
        analyzedAt: DateTime.now(),
      );
      final suggestions =
          svc.generateCleanupSuggestions([breakdown], [], []);
      expect(suggestions.any((s) => s.type == CleanupType.large), isTrue);
    });

    test('no suggestion for large files <100 MB', () {
      final smallFile = _file('small.pdf', size: 50 * 1024 * 1024);
      final breakdown = StorageBreakdown(
        providerId: 'p1',
        totalBytes: 0,
        usedBytes: smallFile.size!,
        freeBytes: 0,
        categoryBreakdowns: {},
        staleFiles: [],
        largestFiles: [smallFile],
        analyzedAt: DateTime.now(),
      );
      final suggestions =
          svc.generateCleanupSuggestions([breakdown], [], []);
      expect(suggestions.any((s) => s.type == CleanupType.large), isFalse);
    });

    test('empty inputs return empty list', () {
      final suggestions = svc.generateCleanupSuggestions([], [], []);
      expect(suggestions, isEmpty);
    });

    test('suggestions sorted by savingsBytes descending', () {
      const dupSize = 1024 * 1024 * 1024; // 1 GB
      final stales = [
        StaleFile(
            path: '/old.txt',
            provider: 'p1',
            sizeBytes: 1000,
            daysSinceAccess: 400),
      ];
      final dups = [
        DuplicateGroup(
          key: '$dupSize:heavy.bin',
          entries: [
            DuplicateEntry(
                path: '/heavy.bin', provider: 'p1', sizeBytes: dupSize),
            DuplicateEntry(
                path: '/heavy.bin', provider: 'p2', sizeBytes: dupSize),
          ],
        ),
      ];
      final suggestions =
          svc.generateCleanupSuggestions([], dups, stales);
      expect(suggestions.first.savingsBytes,
          greaterThanOrEqualTo(suggestions.last.savingsBytes));
    });
  });

  // =========================================================================
  // estimateSavings
  // =========================================================================

  group('estimateSavings', () {
    test('sums all suggestion savingsBytes', () {
      final suggestions = [
        CleanupSuggestion(
            type: CleanupType.duplicate,
            description: 'd',
            savingsBytes: 1000,
            files: []),
        CleanupSuggestion(
            type: CleanupType.stale,
            description: 's',
            savingsBytes: 2000,
            files: []),
        CleanupSuggestion(
            type: CleanupType.large,
            description: 'l',
            savingsBytes: 3000,
            files: []),
      ];
      expect(svc.estimateSavings(suggestions), 6000);
    });

    test('empty list returns 0', () {
      expect(svc.estimateSavings([]), 0);
    });

    test('single suggestion', () {
      final s = [
        CleanupSuggestion(
            type: CleanupType.stale,
            description: 's',
            savingsBytes: 500,
            files: []),
      ];
      expect(svc.estimateSavings(s), 500);
    });
  });

  // =========================================================================
  // Model serialization / deserialization
  // =========================================================================

  group('Model serialization', () {
    test('CategoryStats round-trips through JSON', () {
      const cs = CategoryStats(fileCount: 5, totalBytes: 1024, percentage: 25.5);
      final json = cs.toJson();
      final cs2 = CategoryStats.fromJson(json);
      expect(cs2.fileCount, cs.fileCount);
      expect(cs2.totalBytes, cs.totalBytes);
      expect(cs2.percentage, cs.percentage);
    });

    test('StaleFile round-trips through JSON', () {
      final dt = DateTime(2024, 6, 15, 10, 30);
      final sf = StaleFile(
        path: '/docs/old.pdf',
        provider: 'filen',
        sizeBytes: 204800,
        lastAccessed: dt,
        daysSinceAccess: 200,
      );
      final json = sf.toJson();
      final sf2 = StaleFile.fromJson(json);
      expect(sf2.path, sf.path);
      expect(sf2.provider, sf.provider);
      expect(sf2.sizeBytes, sf.sizeBytes);
      expect(sf2.daysSinceAccess, sf.daysSinceAccess);
      expect(sf2.lastAccessed, dt);
    });

    test('StaleFile null lastAccessed round-trips', () {
      const sf = StaleFile(
        path: '/x',
        provider: 'p',
        sizeBytes: 0,
        daysSinceAccess: 10,
      );
      final sf2 = StaleFile.fromJson(sf.toJson());
      expect(sf2.lastAccessed, isNull);
    });

    test('DuplicateEntry round-trips through JSON', () {
      final dt = DateTime(2025, 1, 1);
      final de = DuplicateEntry(
        path: '/video.mp4',
        provider: 's3',
        sizeBytes: 2 * 1024 * 1024 * 1024,
        modifiedAt: dt,
      );
      final de2 = DuplicateEntry.fromJson(de.toJson());
      expect(de2.path, de.path);
      expect(de2.provider, de.provider);
      expect(de2.sizeBytes, de.sizeBytes);
      expect(de2.modifiedAt, dt);
    });

    test('DuplicateGroup round-trips through JSON', () {
      final group = DuplicateGroup(
        key: '1000:file.mp4',
        entries: [
          const DuplicateEntry(
              path: '/a/file.mp4', provider: 'p1', sizeBytes: 1000),
          const DuplicateEntry(
              path: '/b/file.mp4', provider: 'p2', sizeBytes: 1000),
        ],
      );
      final group2 = DuplicateGroup.fromJson(group.toJson());
      expect(group2.key, group.key);
      expect(group2.entries.length, 2);
      expect(group2.wastedBytes, 1000);
    });

    test('CleanupSuggestion round-trips through JSON', () {
      const s = CleanupSuggestion(
        type: CleanupType.duplicate,
        description: 'Test suggestion',
        savingsBytes: 99999,
        files: ['/a', '/b'],
      );
      final s2 = CleanupSuggestion.fromJson(s.toJson());
      expect(s2.type, CleanupType.duplicate);
      expect(s2.description, s.description);
      expect(s2.savingsBytes, s.savingsBytes);
      expect(s2.files, s.files);
    });

    test('StorageBreakdown round-trips through JSON', () {
      final bd = StorageBreakdown(
        providerId: 'my-gdrive',
        totalBytes: 15 * 1024 * 1024 * 1024,
        usedBytes: 8 * 1024 * 1024 * 1024,
        freeBytes: 7 * 1024 * 1024 * 1024,
        categoryBreakdowns: {
          FileCategory.images: const CategoryStats(
              fileCount: 100, totalBytes: 500000000, percentage: 50.0),
          FileCategory.videos: const CategoryStats(
              fileCount: 10, totalBytes: 500000000, percentage: 50.0),
        },
        staleFiles: [
          const StaleFile(
            path: '/old.pdf',
            provider: 'my-gdrive',
            sizeBytes: 1024,
            daysSinceAccess: 200,
          ),
        ],
        largestFiles: [],
        analyzedAt: DateTime(2026, 1, 1),
      );

      final json = jsonDecode(jsonEncode(bd.toJson())) as Map<String, dynamic>;
      final bd2 = StorageBreakdown.fromJson(json);

      expect(bd2.providerId, bd.providerId);
      expect(bd2.totalBytes, bd.totalBytes);
      expect(bd2.usedBytes, bd.usedBytes);
      expect(bd2.freeBytes, bd.freeBytes);
      expect(bd2.staleFiles.length, 1);
      expect(
          bd2.categoryBreakdowns[FileCategory.images]!.fileCount, 100);
      expect(
          bd2.categoryBreakdowns[FileCategory.videos]!.totalBytes, 500000000);
    });
  });

  // =========================================================================
  // Category stats percentage sum
  // =========================================================================

  group('categoryBreakdowns percentages', () {
    test('percentages sum to 100 for multi-category provider', () {
      final files = [
        _file('a.pdf', size: 100),
        _file('b.jpg', size: 200),
        _file('c.mp4', size: 300),
        _file('d.mp3', size: 400),
      ];
      final bd = svc.analyzeProvider('p1', files);
      final sum = bd.categoryBreakdowns.values
          .fold<double>(0, (acc, s) => acc + s.percentage);
      expect(sum, closeTo(100.0, 0.01));
    });
  });

  // =========================================================================
  // Edge cases for analyzeProvider
  // =========================================================================

  group('analyzeProvider edge cases', () {
    test('all files in other category', () {
      final files = [
        _file('Makefile', size: 1000),
        _file('LICENSE', size: 500),
      ];
      final bd = svc.analyzeProvider('p1', files);
      expect(bd.categoryBreakdowns[FileCategory.other]!.fileCount, 2);
      expect(bd.categoryBreakdowns[FileCategory.other]!.totalBytes, 1500);
    });

    test('files with null size count as zero bytes', () {
      final files = [_file('unknown.xyz')]; // size == null
      final bd = svc.analyzeProvider('p1', files);
      expect(bd.usedBytes, 0);
      expect(bd.categoryBreakdowns[FileCategory.other]!.fileCount, 1);
    });

    test('all categories are present in breakdown map', () {
      final bd = svc.analyzeProvider('p1', []);
      for (final cat in FileCategory.values) {
        expect(bd.categoryBreakdowns.containsKey(cat), isTrue);
      }
    });
  });
}
