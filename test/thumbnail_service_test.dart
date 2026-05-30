// test/thumbnail_service_test.dart
//
// Dedicated tests for ThumbnailService beyond what's in
// infrastructure_test.dart. Focuses on:
//   - isSupported for all extensions (including edge cases)
//   - Key generation consistency (remoteKey, localKey)
//   - Memory cache behavior (getCached, capacity eviction)
//   - cachedKeys and memoryCacheSize
//   - clear behavior

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/thumbnail_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // isSupported — comprehensive extension coverage
  // ---------------------------------------------------------------------------
  group('ThumbnailService.isSupported', () {
    test('supports jpg', () {
      expect(ThumbnailService.isSupported('photo.jpg'), true);
    });

    test('supports jpeg', () {
      expect(ThumbnailService.isSupported('photo.jpeg'), true);
    });

    test('supports png', () {
      expect(ThumbnailService.isSupported('image.png'), true);
    });

    test('supports gif', () {
      expect(ThumbnailService.isSupported('anim.gif'), true);
    });

    test('supports bmp', () {
      expect(ThumbnailService.isSupported('bitmap.bmp'), true);
    });

    test('supports webp', () {
      expect(ThumbnailService.isSupported('modern.webp'), true);
    });

    test('supports ico', () {
      expect(ThumbnailService.isSupported('favicon.ico'), true);
    });

    test('rejects pdf', () {
      expect(ThumbnailService.isSupported('doc.pdf'), false);
    });

    test('rejects mp4', () {
      expect(ThumbnailService.isSupported('video.mp4'), false);
    });

    test('rejects txt', () {
      expect(ThumbnailService.isSupported('readme.txt'), false);
    });

    test('rejects svg (not in supported set)', () {
      expect(ThumbnailService.isSupported('logo.svg'), false);
    });

    test('rejects tiff (not in supported set)', () {
      expect(ThumbnailService.isSupported('scan.tiff'), false);
    });

    test('is case-insensitive', () {
      expect(ThumbnailService.isSupported('PHOTO.JPG'), true);
      expect(ThumbnailService.isSupported('Image.PNG'), true);
      expect(ThumbnailService.isSupported('pic.GIF'), true);
      expect(ThumbnailService.isSupported('icon.ICO'), true);
    });

    test('handles file with multiple dots', () {
      expect(ThumbnailService.isSupported('archive.tar.jpg'), true);
      expect(ThumbnailService.isSupported('file.backup.png'), true);
      expect(ThumbnailService.isSupported('file.jpg.zip'), false);
    });

    test('no extension returns false', () {
      // 'Makefile'.split('.').last == 'Makefile' which is not in the set
      expect(ThumbnailService.isSupported('Makefile'), false);
    });
  });

  // ---------------------------------------------------------------------------
  // Key generation
  // ---------------------------------------------------------------------------
  group('Key generation', () {
    test('remoteKey format is provider:path', () {
      expect(ThumbnailService.remoteKey('s3', '/bucket/photo.jpg'), 's3:/bucket/photo.jpg');
    });

    test('localKey format is local:path', () {
      expect(ThumbnailService.localKey('/tmp/pic.png'), 'local:/tmp/pic.png');
    });

    test('remoteKey is consistent for same input', () {
      final k1 = ThumbnailService.remoteKey('gdrive', '/a/b.jpg');
      final k2 = ThumbnailService.remoteKey('gdrive', '/a/b.jpg');
      expect(k1, k2);
    });

    test('different providers produce different keys', () {
      final k1 = ThumbnailService.remoteKey('s3', '/photo.jpg');
      final k2 = ThumbnailService.remoteKey('gdrive', '/photo.jpg');
      expect(k1, isNot(k2));
    });

    test('different paths produce different keys', () {
      final k1 = ThumbnailService.remoteKey('s3', '/a.jpg');
      final k2 = ThumbnailService.remoteKey('s3', '/b.jpg');
      expect(k1, isNot(k2));
    });
  });

  // ---------------------------------------------------------------------------
  // Memory cache behavior
  // ---------------------------------------------------------------------------
  group('Memory cache', () {
    late ThumbnailService service;

    setUp(() {
      service = ThumbnailService();
    });

    test('getCached returns null for unknown key', () {
      expect(service.getCached('nonexistent'), isNull);
    });

    test('cacheProviderThumbnail stores in memory cache', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      await service.cacheProviderThumbnail('test-key', bytes);
      expect(service.getCached('test-key'), isNotNull);
      expect(service.getCached('test-key'), bytes);
    });

    test('cachedKeys lists all cached entries', () async {
      await service.cacheProviderThumbnail('k1', Uint8List.fromList([1]));
      await service.cacheProviderThumbnail('k2', Uint8List.fromList([2]));
      expect(service.cachedKeys, containsAll(['k1', 'k2']));
      expect(service.cachedKeys.length, 2);
    });

    test('memoryCacheSize sums all byte lengths', () async {
      await service.cacheProviderThumbnail('a', Uint8List.fromList([1, 2, 3]));
      await service.cacheProviderThumbnail('b', Uint8List.fromList([4, 5]));
      expect(service.memoryCacheSize, 5);
    });

    test('clear empties memory cache', () async {
      await service.cacheProviderThumbnail('key', Uint8List.fromList([1]));
      expect(service.cachedKeys, isNotEmpty);
      // clear requires _cacheDir to be set for disk; in test it's null so just clears memory
      await service.clear();
      expect(service.cachedKeys, isEmpty);
      expect(service.memoryCacheSize, 0);
    });

    test('memory cache size starts at zero', () {
      expect(service.memoryCacheSize, 0);
      expect(service.cachedKeys, isEmpty);
    });
  });
}
