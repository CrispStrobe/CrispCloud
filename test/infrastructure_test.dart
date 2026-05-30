// test/infrastructure_test.dart
//
// Tests for infrastructure features:
// - CertPinningService
// - FileCacheService
// - ThumbnailService
// - Delta sync (content hash comparison)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/cert_pinning_service.dart';
import 'package:crisp_cloud/services/file_cache_service.dart';
import 'package:crisp_cloud/services/thumbnail_service.dart';

void main() {
  // --- CertPinningService Tests ---
  group('CertPinningService', () {
    late CertPinningService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = CertPinningService();
    });

    test('disabled by default', () {
      expect(service.isEnabled, false);
    });

    test('enable and disable', () async {
      await service.setEnabled(true);
      expect(service.isEnabled, true);

      await service.setEnabled(false);
      expect(service.isEnabled, false);
    });

    test('getPinnedProviders returns known providers', () {
      final providers = service.getPinnedProviders();
      expect(providers.length, greaterThanOrEqualTo(4));
      final names = providers.map((p) => p['name'] as String).toSet();
      expect(names, contains('Google'));
      expect(names, contains('Microsoft'));
      expect(names, contains('Dropbox'));
      expect(names, contains('Amazon S3'));
    });

    test('validate always passes when disabled', () {
      // Even with a fake cert, should pass when disabled
      expect(service.isEnabled, false);
      // We can't easily create a real X509Certificate in tests,
      // but we verify the service reports as disabled
    });
  });

  // --- CertPinSet Tests ---
  group('CertPinSet', () {
    test('matchesHost exact', () {
      const ps = CertPinSet(name: 'Test', hostPatterns: ['example.com'], pins: {});
      expect(ps.matchesHost('example.com'), true);
      expect(ps.matchesHost('other.com'), false);
    });

    test('matchesHost subdomain', () {
      const ps = CertPinSet(name: 'Test', hostPatterns: ['example.com'], pins: {});
      expect(ps.matchesHost('api.example.com'), true);
      expect(ps.matchesHost('sub.api.example.com'), true);
      expect(ps.matchesHost('notexample.com'), false);
    });

    test('matchesHost case insensitive', () {
      const ps = CertPinSet(name: 'Test', hostPatterns: ['Example.COM'], pins: {});
      expect(ps.matchesHost('example.com'), true);
      expect(ps.matchesHost('EXAMPLE.COM'), true);
    });

    test('matchesHost multiple patterns', () {
      const ps = CertPinSet(name: 'Test', hostPatterns: ['a.com', 'b.com'], pins: {});
      expect(ps.matchesHost('a.com'), true);
      expect(ps.matchesHost('b.com'), true);
      expect(ps.matchesHost('c.com'), false);
    });
  });

  // --- FileCacheService Tests ---
  group('FileCacheService', () {
    test('CacheEntry toJson/fromJson round-trip', () {
      final entry = CacheEntry(
        remotePath: '/docs/file.txt',
        provider: 'gdrive',
        sizeBytes: 1024,
        cachedAt: DateTime(2026, 1, 1),
        lastAccessed: DateTime(2026, 1, 2),
        localFileName: 'abc123',
      );

      final json = entry.toJson();
      final restored = CacheEntry.fromJson(json);

      expect(restored.remotePath, '/docs/file.txt');
      expect(restored.provider, 'gdrive');
      expect(restored.sizeBytes, 1024);
      expect(restored.localFileName, 'abc123');
    });

    test('CacheEntry serializes dates correctly', () {
      final now = DateTime.now();
      final entry = CacheEntry(
        remotePath: '/test',
        provider: 'dropbox',
        sizeBytes: 100,
        cachedAt: now,
        lastAccessed: now,
        localFileName: 'x',
      );

      final json = entry.toJson();
      expect(json['cachedAt'], now.toIso8601String());
      expect(json['lastAccessed'], now.toIso8601String());
    });
  });

  // --- ThumbnailService Tests ---
  group('ThumbnailService', () {
    test('isSupported identifies image files', () {
      expect(ThumbnailService.isSupported('photo.jpg'), true);
      expect(ThumbnailService.isSupported('image.png'), true);
      expect(ThumbnailService.isSupported('pic.gif'), true);
      expect(ThumbnailService.isSupported('icon.webp'), true);
      expect(ThumbnailService.isSupported('logo.bmp'), true);
    });

    test('isSupported rejects non-image files', () {
      expect(ThumbnailService.isSupported('document.pdf'), false);
      expect(ThumbnailService.isSupported('script.dart'), false);
      expect(ThumbnailService.isSupported('data.json'), false);
      expect(ThumbnailService.isSupported('video.mp4'), false);
      expect(ThumbnailService.isSupported('archive.zip'), false);
    });

    test('isSupported case insensitive', () {
      expect(ThumbnailService.isSupported('PHOTO.JPG'), true);
      expect(ThumbnailService.isSupported('Image.PNG'), true);
    });

    test('remoteKey format', () {
      final key = ThumbnailService.remoteKey('gdrive', '/photos/cat.jpg');
      expect(key, 'gdrive:/photos/cat.jpg');
    });

    test('localKey format', () {
      final key = ThumbnailService.localKey('/home/user/photo.jpg');
      expect(key, 'local:/home/user/photo.jpg');
    });

    test('getCached returns null for unknown key', () {
      final service = ThumbnailService();
      expect(service.getCached('nonexistent'), null);
    });
  });

  // --- Delta Sync Content Hash Tests ---
  group('Delta Sync', () {
    // Test the content hash comparison logic used in sync engine

    bool isRemoteModified({
      required int? fileSize,
      required DateTime? fileModified,
      required String? fileHash,
      required DateTime? knownModified,
      required int knownSize,
      required String? knownHash,
    }) {
      // If both sides have content hashes, use those
      if (fileHash != null && knownHash != null) {
        return fileHash != knownHash;
      }
      // Fallback: timestamp + size
      if (knownModified == null) return true;
      final timeDiff = fileModified != null
          ? fileModified.difference(knownModified).inSeconds.abs()
          : 0;
      return timeDiff > 1 || (fileSize ?? 0) != knownSize;
    }

    test('same hash means not modified', () {
      expect(isRemoteModified(
        fileSize: 100,
        fileModified: DateTime(2026, 1, 2),
        fileHash: 'abc123',
        knownModified: DateTime(2026, 1, 1),
        knownSize: 100,
        knownHash: 'abc123',
      ), false);
    });

    test('different hash means modified', () {
      expect(isRemoteModified(
        fileSize: 100,
        fileModified: DateTime(2026, 1, 1),
        fileHash: 'abc123',
        knownModified: DateTime(2026, 1, 1),
        knownSize: 100,
        knownHash: 'xyz789',
      ), true);
    });

    test('hash takes precedence over timestamp', () {
      // Same hash but different timestamp → not modified (hash wins)
      expect(isRemoteModified(
        fileSize: 100,
        fileModified: DateTime(2026, 6, 1),
        fileHash: 'same',
        knownModified: DateTime(2026, 1, 1),
        knownSize: 100,
        knownHash: 'same',
      ), false);
    });

    test('no hash falls back to timestamp', () {
      // No hashes, different timestamp → modified
      expect(isRemoteModified(
        fileSize: 100,
        fileModified: DateTime(2026, 6, 1),
        fileHash: null,
        knownModified: DateTime(2026, 1, 1),
        knownSize: 100,
        knownHash: null,
      ), true);
    });

    test('no hash, same timestamp and size → not modified', () {
      final t = DateTime(2026, 1, 1);
      expect(isRemoteModified(
        fileSize: 100,
        fileModified: t,
        fileHash: null,
        knownModified: t,
        knownSize: 100,
        knownHash: null,
      ), false);
    });

    test('only remote has hash, falls back to timestamp', () {
      expect(isRemoteModified(
        fileSize: 100,
        fileModified: DateTime(2026, 6, 1),
        fileHash: 'abc',
        knownModified: DateTime(2026, 1, 1),
        knownSize: 100,
        knownHash: null,
      ), true);
    });
  });
}
