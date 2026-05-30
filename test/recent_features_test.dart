// test/recent_features_test.dart
//
// Tests for features added in recent commits: bookmarks, version history,
// share link dialog, duplicate finder logic, key management (BIP39),
// tab persistence, and selective sync filters.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/providers/bookmarks_provider.dart';
import 'package:crisp_cloud/services/encryption_service.dart';
import 'package:crisp_cloud/services/sync_engine.dart';

void main() {
  // =========================================================================
  // Bookmarks
  // =========================================================================
  group('Bookmark', () {
    test('toJson and fromJson round-trip', () {
      const b = Bookmark(name: 'Docs', path: '/home/docs', side: PanelSide.local);
      final json = b.toJson();
      final restored = Bookmark.fromJson(json);
      expect(restored.name, 'Docs');
      expect(restored.path, '/home/docs');
      expect(restored.side, PanelSide.local);
    });

    test('fromJson defaults to PanelSide.local for unknown side', () {
      final b = Bookmark.fromJson({'name': 'x', 'path': '/x', 'side': 'unknown'});
      expect(b.side, PanelSide.local);
    });

    test('fromJson handles remote side', () {
      final b = Bookmark.fromJson({'name': 'r', 'path': '/r', 'side': 'remote'});
      expect(b.side, PanelSide.remote);
    });
  });

  group('BookmarksNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('starts empty', () {
      final notifier = BookmarksNotifier();
      expect(notifier.bookmarks, isEmpty);
    });

    test('add and remove bookmarks', () {
      final notifier = BookmarksNotifier();
      notifier.add('Docs', '/docs', PanelSide.local);
      expect(notifier.bookmarks.length, 1);
      expect(notifier.isBookmarked('/docs', PanelSide.local), isTrue);

      notifier.remove('/docs', PanelSide.local);
      expect(notifier.bookmarks, isEmpty);
      expect(notifier.isBookmarked('/docs', PanelSide.local), isFalse);
    });

    test('does not add duplicate bookmark', () {
      final notifier = BookmarksNotifier();
      notifier.add('Docs', '/docs', PanelSide.local);
      notifier.add('Docs Again', '/docs', PanelSide.local);
      expect(notifier.bookmarks.length, 1);
    });

    test('same path different sides are separate bookmarks', () {
      final notifier = BookmarksNotifier();
      notifier.add('Local', '/path', PanelSide.local);
      notifier.add('Remote', '/path', PanelSide.remote);
      expect(notifier.bookmarks.length, 2);
      expect(notifier.isBookmarked('/path', PanelSide.local), isTrue);
      expect(notifier.isBookmarked('/path', PanelSide.remote), isTrue);
    });

    test('remove only affects matching side', () {
      final notifier = BookmarksNotifier();
      notifier.add('Local', '/path', PanelSide.local);
      notifier.add('Remote', '/path', PanelSide.remote);
      notifier.remove('/path', PanelSide.local);
      expect(notifier.bookmarks.length, 1);
      expect(notifier.bookmarks.first.side, PanelSide.remote);
    });

    test('loads from SharedPreferences', () async {
      final saved = json.encode([
        {'name': 'Pre-saved', 'path': '/saved', 'side': 'remote'}
      ]);
      SharedPreferences.setMockInitialValues({'bookmarks': saved});

      final notifier = BookmarksNotifier();
      // Wait for async _load()
      await Future.delayed(const Duration(milliseconds: 50));
      expect(notifier.bookmarks.length, 1);
      expect(notifier.bookmarks.first.name, 'Pre-saved');
      expect(notifier.bookmarks.first.side, PanelSide.remote);
    });
  });

  // =========================================================================
  // Key Management (BIP39)
  // =========================================================================
  group('EncryptionService — Key Management', () {
    late Uint8List testKey;
    late Uint8List testSalt;

    setUp(() {
      testSalt = EncryptionService.generateSalt();
      testKey = EncryptionService.deriveKey('test-passphrase', testSalt,
          iterations: 1000);
    });

    test('exportKeyAsHex produces 64 hex chars', () {
      final hex = EncryptionService.exportKeyAsHex(testKey);
      expect(hex.length, 64);
      expect(hex, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('importKeyFromHex round-trips with exportKeyAsHex', () {
      final hex = EncryptionService.exportKeyAsHex(testKey);
      final restored = EncryptionService.importKeyFromHex(hex);
      expect(restored, equals(testKey));
    });

    test('importKeyFromHex rejects wrong length', () {
      expect(
        () => EncryptionService.importKeyFromHex('abcd'),
        throwsA(isA<FormatException>()),
      );
    });

    test('importKeyFromHex rejects invalid chars', () {
      expect(
        () => EncryptionService.importKeyFromHex('g' * 64),
        throwsA(isA<FormatException>()),
      );
    });

    test('importKeyFromHex tolerates whitespace', () {
      final hex = EncryptionService.exportKeyAsHex(testKey);
      final spaced = '${hex.substring(0, 32)} ${hex.substring(32)}';
      final restored = EncryptionService.importKeyFromHex(spaced);
      expect(restored, equals(testKey));
    });

    test('generateMnemonic produces 24-word phrase', () {
      final result = EncryptionService.generateMnemonic(testKey, testSalt);
      final words = result['mnemonic']!.split(' ');
      expect(words.length, 24);
      expect(result['salt'], isNotEmpty);
    });

    test('recoverKeyFromMnemonic round-trips', () {
      final result = EncryptionService.generateMnemonic(testKey, testSalt);
      final recovered =
          EncryptionService.recoverKeyFromMnemonic(result['mnemonic']!);
      expect(recovered, equals(testKey));
    });

    test('recoverKeyFromMnemonic rejects invalid mnemonic', () {
      expect(
        () => EncryptionService.recoverKeyFromMnemonic('invalid words here'),
        throwsA(isA<FormatException>()),
      );
    });

    test('exportBackupBundle and importBackupBundle round-trip', () {
      final bundle = EncryptionService.exportBackupBundle(testKey, testSalt);
      final result = EncryptionService.importBackupBundle(bundle);
      expect(result['key'], equals(testKey));
      expect(result['salt'], equals(testSalt));
    });

    test('importBackupBundle rejects tampered verification', () {
      final bundle = EncryptionService.exportBackupBundle(testKey, testSalt);
      final data = json.decode(bundle) as Map<String, dynamic>;
      data['verify'] = 'AAAA'; // tampered
      expect(
        () => EncryptionService.importBackupBundle(json.encode(data)),
        throwsA(isA<FormatException>()),
      );
    });

    test('backup bundle JSON has expected fields', () {
      final bundle = EncryptionService.exportBackupBundle(testKey, testSalt);
      final data = json.decode(bundle) as Map<String, dynamic>;
      expect(data.containsKey('version'), isTrue);
      expect(data.containsKey('mnemonic'), isTrue);
      expect(data.containsKey('salt'), isTrue);
      expect(data.containsKey('verify'), isTrue);
      expect(data['version'], 1);
    });
  });

  // =========================================================================
  // PanelTab model
  // =========================================================================
  group('PanelTab', () {
    test('label derived from path', () {
      final tab = PanelTab(id: '1', path: '/home/user/docs');
      expect(tab.label, 'docs');
    });

    test('label for root path', () {
      final tab = PanelTab(id: '1', path: '/');
      expect(tab.label, '/');
    });

    test('label for Windows path', () {
      final tab = PanelTab(id: '1', path: 'C:\\Users\\john\\Documents');
      expect(tab.label, 'Documents');
    });

    test('isPinned defaults to false', () {
      final tab = PanelTab(id: '1', path: '/');
      expect(tab.isPinned, isFalse);
    });

    test('copyWith preserves pin state', () {
      final tab = PanelTab(id: '1', path: '/', isPinned: true);
      final copy = tab.copyWith(path: '/new');
      expect(copy.isPinned, isTrue);
      expect(copy.path, '/new');
    });

    test('updateLabel recalculates from path', () {
      final tab = PanelTab(id: '1', path: '/');
      tab.path = '/home/user/music';
      tab.updateLabel();
      expect(tab.label, 'music');
    });
  });

  // =========================================================================
  // Selective Sync Filters
  // =========================================================================
  group('SyncEngine.passesFilter', () {
    test('empty patterns pass everything', () {
      expect(SyncEngine.passesFilter('file.txt', '', ''), isTrue);
      expect(SyncEngine.passesFilter('dir/file.dart', '', ''), isTrue);
    });

    test('include pattern filters to matching files', () {
      expect(SyncEngine.passesFilter('file.dart', '*.dart', ''), isTrue);
      expect(SyncEngine.passesFilter('file.txt', '*.dart', ''), isFalse);
    });

    test('multiple include patterns (comma-separated)', () {
      expect(SyncEngine.passesFilter('file.dart', '*.dart, *.yaml', ''), isTrue);
      expect(SyncEngine.passesFilter('file.yaml', '*.dart, *.yaml', ''), isTrue);
      expect(SyncEngine.passesFilter('file.txt', '*.dart, *.yaml', ''), isFalse);
    });

    test('exclude pattern blocks matching files', () {
      expect(SyncEngine.passesFilter('file.tmp', '', '*.tmp'), isFalse);
      expect(SyncEngine.passesFilter('file.dart', '', '*.tmp'), isTrue);
    });

    test('exclude takes precedence over include', () {
      expect(SyncEngine.passesFilter('file.dart', '*.dart', '*.dart'), isFalse);
    });

    test('glob ** patterns work for directories', () {
      expect(SyncEngine.passesFilter('.git/config', '', '.git/**'), isFalse);
      expect(SyncEngine.passesFilter('src/main.dart', '', '.git/**'), isTrue);
    });

    test('whitespace in patterns is trimmed', () {
      expect(SyncEngine.passesFilter('file.dart', '  *.dart  ', ''), isTrue);
      expect(SyncEngine.passesFilter('file.tmp', '', '  *.tmp  '), isFalse);
    });
  });

  // =========================================================================
  // Duplicate Finder logic (file grouping)
  // =========================================================================
  group('Duplicate finder logic', () {
    test('files with same size are grouped', () {
      final files = [
        FileItem(name: 'a.txt', isFolder: false, size: 100),
        FileItem(name: 'b.txt', isFolder: false, size: 100),
        FileItem(name: 'c.txt', isFolder: false, size: 200),
      ];

      final sizeGroups = <int, List<FileItem>>{};
      for (final file in files) {
        if (file.size != null && file.size! > 0) {
          sizeGroups.putIfAbsent(file.size!, () => []).add(file);
        }
      }
      final dupes = sizeGroups.values.where((g) => g.length > 1).toList();
      expect(dupes.length, 1);
      expect(dupes.first.length, 2);
      expect(dupes.first.first.name, 'a.txt');
    });

    test('folders are ignored', () {
      final files = [
        FileItem(name: 'dir1', isFolder: true, size: 100),
        FileItem(name: 'dir2', isFolder: true, size: 100),
      ];

      final nonFolders = files.where((f) => !f.isFolder).toList();
      expect(nonFolders, isEmpty);
    });

    test('zero-size files are skipped', () {
      final files = [
        FileItem(name: 'a.txt', isFolder: false, size: 0),
        FileItem(name: 'b.txt', isFolder: false, size: 0),
      ];

      final sizeGroups = <int, List<FileItem>>{};
      for (final file in files) {
        final size = file.size ?? -1;
        if (size <= 0) continue;
        sizeGroups.putIfAbsent(size, () => []).add(file);
      }
      expect(sizeGroups, isEmpty);
    });
  });

  // =========================================================================
  // FileItem model edge cases
  // =========================================================================
  group('FileItem', () {
    test('equality by uuid when present', () {
      final a = FileItem(name: 'a', isFolder: false, uuid: 'abc');
      final b = FileItem(name: 'b', isFolder: false, uuid: 'abc');
      expect(a, equals(b));
    });

    test('equality by path when no uuid', () {
      final a = FileItem(name: 'a', isFolder: false, path: '/x');
      final b = FileItem(name: 'b', isFolder: false, path: '/x');
      expect(a, equals(b));
    });

    test('sizeFormatted covers all ranges', () {
      expect(FileItem(name: 'a', isFolder: false, size: 500).sizeFormatted, '500 B');
      expect(FileItem(name: 'a', isFolder: false, size: 2048).sizeFormatted, '2.0 KB');
      expect(FileItem(name: 'a', isFolder: false, size: 5 * 1024 * 1024).sizeFormatted, '5.0 MB');
      expect(FileItem(name: 'a', isFolder: false, size: 2 * 1024 * 1024 * 1024).sizeFormatted, '2.0 GB');
    });
  });

  // =========================================================================
  // SyncResult
  // =========================================================================
  group('SyncResult', () {
    test('addition combines all fields', () {
      const a = SyncResult(uploaded: 2, downloaded: 1, conflicts: 1);
      const b = SyncResult(uploaded: 1, errors: 3, errorMessages: ['err']);
      final c = a + b;
      expect(c.uploaded, 3);
      expect(c.downloaded, 1);
      expect(c.conflicts, 1);
      expect(c.errors, 3);
      expect(c.errorMessages, ['err']);
    });

    test('hasChanges is false for empty result', () {
      expect(const SyncResult().hasChanges, isFalse);
    });

    test('hasChanges is true with any non-zero count', () {
      expect(const SyncResult(uploaded: 1).hasChanges, isTrue);
      expect(const SyncResult(conflicts: 1).hasChanges, isTrue);
    });
  });
}
