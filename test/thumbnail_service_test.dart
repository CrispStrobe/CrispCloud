// test/thumbnail_service_test.dart
//
// Dedicated tests for ThumbnailService beyond what's in
// infrastructure_test.dart. Focuses on:
//   - isSupported for all extensions (including edge cases)
//   - Key generation consistency (remoteKey, localKey)
//   - Memory cache behavior (getCached, capacity eviction)
//   - cachedKeys and memoryCacheSize
//   - clear behavior

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:crisp_cloud/services/thumbnail_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

    test('supports formats available through the pure Dart fallback', () {
      for (final extension in ['tif', 'tiff', 'psd', 'tga', 'pnm', 'ppm']) {
        expect(ThumbnailService.isSupported('scan.$extension'), true);
      }
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
      expect(ThumbnailService.isSupported('jpg'), false);
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

    test('LRU hits protect the recently used item', () async {
      service = ThumbnailService(maxMemoryCacheEntries: 2);
      await service.cacheProviderThumbnail('a', Uint8List.fromList([1]));
      await service.cacheProviderThumbnail('b', Uint8List.fromList([2]));
      service.getCached('a');
      await service.cacheProviderThumbnail('c', Uint8List.fromList([3]));
      expect(service.getCached('a'), isNotNull);
      expect(service.getCached('b'), isNull);
    });

    test('byte budget and replacement accounting stay bounded', () async {
      service = ThumbnailService(maxMemoryCacheBytes: 5);
      await service.cacheProviderThumbnail('a', Uint8List(3));
      await service.cacheProviderThumbnail('b', Uint8List(3));
      expect(service.getCached('a'), isNull);
      expect(service.memoryCacheSize, 3);
      await service.cacheProviderThumbnail('b', Uint8List(2));
      expect(service.memoryCacheSize, 2);
      await service.cacheProviderThumbnail('oversized', Uint8List(8));
      expect(service.memoryCacheSize, 2);
      expect(service.getCached('oversized'), isNull);
    });

    test('cached snapshots cannot be modified by the caller', () async {
      final source = Uint8List.fromList([1, 2]);
      await service.cacheProviderThumbnail('image', source);
      source[0] = 9;
      expect(service.getCached('image'), [1, 2]);
      expect(() => service.getCached('image')![0] = 3, throwsUnsupportedError);
    });
  });

  group('Actual decoding and disk reuse', () {
    Uint8List png(int width, int height) => img.encodePng(
        img.Image(width: width, height: height, numChannels: 4));

    test('native thumbnails preserve ratio and alpha without upscaling', () async {
      final service = ThumbnailService();
      final wide = await service.generate('wide', png(300, 100));
      expect(wide, isNotNull);
      final decoded = img.decodePng(wide!)!;
      expect((decoded.width, decoded.height), (120, 40));
      expect(decoded.getPixel(0, 0).a, 0);
      final small = img.decodePng((await service.generate('small', png(16, 8)))!)!;
      expect((small.width, small.height), (16, 8));
    });

    test('thumbnail sizes and concurrent decodes cannot alias', () async {
      final service = ThumbnailService();
      final bytes = png(512, 256);
      final first = service.generate('same', bytes, size: 64);
      final duplicate = service.generate('same', bytes, size: 64);
      expect(identical(first, duplicate), true);
      final small = img.decodePng((await first)!)!;
      final large = img.decodePng((await service.generate('same', bytes, size: 256))!)!;
      expect((small.width, small.height), (64, 32));
      expect((large.width, large.height), (256, 128));
      expect(service.getCached('same', size: 64), isNot(service.getCached('same', size: 256)));
    });

    test('clear prevents an in-flight decode from repopulating the cache', () async {
      final service = ThumbnailService();
      final pending = service.generate('late', png(300, 100));
      await service.clear();
      await pending;
      expect(service.cachedKeys, isEmpty);
    });

    test('invalid image bytes return null', () async {
      expect(await ThumbnailService().generate('bad', Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('disk cache is read before original bytes and obeys its budgets', () async {
      final dir = await Directory.systemTemp.createTemp('gallery-thumbnail-test-');
      try {
        final first = ThumbnailService(maxDiskCacheEntries: 2);
        await first.init(cacheDirectory: dir.path);
        final expected = await first.generate('image', png(200, 100), size: 64);
        final second = ThumbnailService(maxDiskCacheEntries: 2);
        await second.init(cacheDirectory: dir.path);
        expect(await second.readCached('image', size: 64), expected);
        await second.cacheProviderThumbnail('a', Uint8List.fromList([1]));
        await second.cacheProviderThumbnail('b', Uint8List.fromList([2]));
        expect(await second.getDiskCacheCount(), 2);
        await second.clear();
        expect(await second.getDiskCacheCount(), 0);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
