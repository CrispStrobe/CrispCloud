import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/providers/gallery_media_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/gallery_image_decoder.dart';
import 'package:crisp_cloud/services/gallery_media_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/thumbnail_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _Cloud extends Fake implements CloudStorageClient {
  _Cloud({this.providerName = 'Google Drive', this.account = 'one', this.streaming = false});
  @override
  final String providerName;
  final String account;
  final bool streaming;
  @override
  String? get userId => account;
  @override
  String? get bucketId => 'bucket';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => true;
  @override
  bool get supportsStreaming => streaming;
  int reads = 0;
  int? reportedSize;
  int? streamProgressSize;
  void Function()? onStreamStart;
  int yieldedChunks = 0;
  bool streamCanceled = false;
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async =>
      reportedSize == null ? null : {'size': reportedSize};
  @override
  Future<Uint8List> downloadFileBytes(String path, {Function(int, int)? onProgress}) async {
    reads++;
    return Uint8List.fromList([1, 2]);
  }
  @override
  Stream<List<int>> downloadStream(String path, {Function(int, int)? onProgress}) async* {
    reads++;
    try {
      onStreamStart?.call();
      onProgress?.call(0, streamProgressSize ?? 0);
      yieldedChunks++;
      yield [1, 2];
      yieldedChunks++;
      yield List.filled(8, 3);
      fail('An oversized stream must be canceled before requesting another chunk.');
    } finally {
      streamCanceled = true;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Uint8List png() => img.encodePng(img.Image(width: 12, height: 6, numChannels: 4));
  GalleryMediaRequest request({String namespace = 'account-a', String name = 'photo.png',
      int? size, DateTime? modified, GalleryBytesReader? read,
      Future<Uint8List?> Function()? provider, bool Function()? current}) =>
      GalleryMediaRequest(
        file: FileItem(name: name, path: '/$name', isFolder: false,
            size: size, updatedAt: modified),
        namespaceId: namespace, path: '/$name', readBytes: read ?? (_) async => png(),
        readProviderThumbnail: provider, isCurrent: current,
      );

  test('catalog identities are stable while revision and account caches are isolated', () {
    final before = request(size: 10);
    final changed = request(size: 11);
    final modified = request(size: 10, modified: DateTime.utc(2026));
    final otherAccount = request(size: 10, namespace: 'account-b');
    expect(before.assetId, changed.assetId);
    expect(before.revisionKey, isNot(changed.revisionKey));
    expect(before.revisionKey, isNot(modified.revisionKey));
    expect(before.assetId, isNot(otherAccount.assetId));
    expect(before.revisionKey, isNot(otherAccount.revisionKey));
  });

  test('namespaces persist identified accounts and isolate ambiguous endpoints', () {
    String scope(_Cloud client) => galleryNamespaceForSource(RemotePanelSource(
        providerName: client.providerName, client: client, path: '/photos'));
    expect(scope(_Cloud()), scope(_Cloud()));
    expect(scope(_Cloud()), isNot(scope(_Cloud(account: 'two'))));
    expect(scope(_Cloud(providerName: 'S3')), isNot(scope(_Cloud(providerName: 'S3'))));
    expect(scope(_Cloud(providerName: 'SFTP')), isNot(scope(_Cloud(providerName: 'SFTP'))));
    expect(scope(_Cloud(providerName: 'Filen (Encrypted)')),
        isNot(scope(_Cloud(providerName: 'Filen (Encrypted)'))));
  });

  test('oversized originals and invalid sources are refused before storage access', () async {
    var reads = 0;
    final service = GalleryMediaService(thumbnails: ThumbnailService());
    Future<Uint8List> read(int _) async { reads++; return png(); }
    await expectLater(service.loadOriginal(request(size: 100, read: read), maxBytes: 10),
        throwsA(isA<GalleryMediaException>()));
    await expectLater(service.loadOriginal(request(read: read, current: () => false)),
        throwsA(isA<GalleryMediaException>()));
    expect(reads, 0);
  });

  test('account changes during a read discard the completed bytes', () async {
    var alive = true;
    final pending = Completer<Uint8List>();
    final service = GalleryMediaService(thumbnails: ThumbnailService());
    final future = service.loadOriginal(request(current: () => alive,
        read: (_) => pending.future));
    final rejected = expectLater(future, throwsA(isA<GalleryMediaException>()));
    alive = false;
    pending.complete(png());
    await rejected;
  });

  test('concurrent original requests coalesce and originals are not retained', () async {
    var reads = 0;
    final pending = Completer<Uint8List>();
    final service = GalleryMediaService(thumbnails: ThumbnailService());
    final image = request(read: (_) { reads++; return pending.future; });
    final a = service.loadOriginal(image);
    final b = service.loadOriginal(image);
    pending.complete(png());
    expect(await a, await b);
    expect(reads, 1);
    await service.loadOriginal(image);
    expect(reads, 2);
  });

  test('cloud thumbnails preview oversized originals without downloading them', () async {
    var reads = 0;
    var providerReads = 0;
    final service = GalleryMediaService(thumbnails: ThumbnailService());
    final image = request(size: 1024 * 1024 * 1024,
        provider: () async { providerReads++; return png(); },
        read: (_) async { reads++; return png(); });
    expect(await service.loadThumbnail(image), isNotNull);
    expect(await service.loadThumbnail(image), isNotNull);
    expect(providerReads, 1);
    expect(reads, 0);
  });

  test('a broken provider preview falls back to the original image', () async {
    final service = GalleryMediaService(thumbnails: ThumbnailService());
    var reads = 0;
    final image = request(provider: () async => Uint8List.fromList([1, 2, 3]),
        read: (_) async { reads++; return png(); });
    expect(await service.loadThumbnail(image), isNotNull);
    expect(reads, 1);
  });

  test('original, SVG and fallback TIFF data preserve explicit format semantics', () async {
    final service = GalleryMediaService(thumbnails: ThumbnailService());
    final raster = await service.loadImage(request());
    expect((raster.width, raster.height, raster.isConverted), (12, 6, false));
    final svgBytes = Uint8List.fromList(utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 80 40"/>'));
    final svg = await service.loadImage(request(name: 'art.svg', read: (_) async => svgBytes));
    expect((svg.width, svg.height, svg.isSvg), (80, 40, true));
    expect(GalleryMediaService.bytesAreSvg(svg.bytes), isTrue);
    expect(GalleryMediaService.bytesAreSvg(png()), isFalse);
    final tiffBytes = img.encodeTiff(img.Image(width: 8, height: 4));
    final tiff = request(name: 'scan.tiff', read: (_) async => tiffBytes);
    final preview = await service.loadImage(tiff);
    expect((preview.width, preview.height), (8, 4));
    expect(img.decodeImage(preview.bytes), isNotNull);
    expect(await service.loadOriginal(tiff), tiffBytes);
  });

  test('EXIF camera/date fields are read without decoding image pixels', () {
    final image = img.Image(width: 8, height: 4);
    image.exif.imageIfd[0x010f] = img.IfdValueAscii('Test camera');
    image.exif.exifIfd[0x9003] = img.IfdValueAscii('2026:10:01 12:34:56');
    final metadata = readGalleryExif(img.encodeJpg(image));
    expect(metadata['Camera make'], 'Test camera');
    expect(metadata['Date taken'], '2026:10:01 12:34:56');
    expect(readGalleryExif(Uint8List.fromList([0, 1, 2])), isEmpty);
  });

  test('SVG dimensions are checked before a renderer allocates pixels', () async {
    final service = GalleryMediaService(thumbnails: ThumbnailService());
    final bytes = Uint8List.fromList(utf8.encode('<svg width="100000" height="100000"/>'));
    await expectLater(service.loadImage(request(name: 'large.svg', read: (_) async => bytes)),
        throwsA(isA<GalleryMediaException>()));
  });

  test('SVG embedded rasters are bounded and nested SVG payloads are rejected', () async {
    final service = GalleryMediaService(thumbnails: ThumbnailService());
    Uint8List svg(String href) => Uint8List.fromList(utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">'
        '<image href="$href" width="100" height="100"/></svg>'));
    final valid = svg('data:image/png;base64,${base64Encode(png())}');
    expect((await service.loadImage(request(name: 'embedded.svg',
        read: (_) async => valid))).isSvg, isTrue);
    final nested = svg('data:image/svg+xml;base64,${base64Encode(valid)}');
    await expectLater(service.loadImage(request(name: 'nested.svg',
        read: (_) async => nested)), throwsA(isA<GalleryMediaException>()));
    final linked = svg('https://example.invalid/external.png');
    await expectLater(service.loadImage(request(name: 'linked.svg',
        read: (_) async => linked)), throwsA(isA<GalleryMediaException>()));
    // Alter a tiny PNG's dimensions. Whether the platform rejects its CRC or
    // exposes the oversized dimensions, it must never reach SVG rendering.
    final giant = Uint8List.fromList(png());
    ByteData.sublistView(giant).setUint32(16, 100000, Endian.big);
    ByteData.sublistView(giant).setUint32(20, 100000, Endian.big);
    final oversized = svg('data:image/png;base64,${base64Encode(giant)}');
    await expectLater(service.loadImage(request(name: 'oversized.svg',
        read: (_) async => oversized)), throwsA(isA<GalleryMediaException>()));
  });

  test('remote streaming stops when the byte budget is exceeded', () async {
    final client = _Cloud(streaming: true);
    final file = FileItem(name: 'photo.png', isFolder: false, size: 2);
    await expectLater(readGalleryRemoteBytes(client, '/photo.png', file, 4,
        isCurrent: () => true), throwsA(isA<GalleryMediaException>()));
    expect(client.streamCanceled, isTrue);
  });

  test('advertised streaming never bypasses the unknown-size preflight', () async {
    // These real adapter types may buffer the whole object before yielding.
    for (final provider in ['S3', 'Backblaze B2', 'Filen (Encrypted)']) {
      for (final size in [null, -1]) {
        final client = _Cloud(providerName: provider, streaming: true);
        final file = FileItem(name: 'photo.png', isFolder: false, size: size);
        await expectLater(readGalleryRemoteBytes(client, '/photo.png', file, 4,
            isCurrent: () => true), throwsA(isA<GalleryMediaException>()));
        expect(client.reads, 0, reason: '$provider must resolve an unknown size');
      }
    }
  });

  test('remote stream progress checks size and source before accepting chunks', () async {
    final file = FileItem(name: 'photo.png', isFolder: false, size: 2);
    final oversized = _Cloud(streaming: true)..streamProgressSize = 8;
    await expectLater(readGalleryRemoteBytes(oversized, '/photo.png', file, 4,
        isCurrent: () => true), throwsA(isA<GalleryMediaException>()));
    expect(oversized.yieldedChunks, 0);
    expect(oversized.streamCanceled, isTrue);

    var current = true;
    final changed = _Cloud(streaming: true)
      ..onStreamStart = () => current = false;
    await expectLater(readGalleryRemoteBytes(changed, '/photo.png', file, 4,
        isCurrent: () => current), throwsA(isA<GalleryMediaException>()));
    expect(changed.yieldedChunks, 0);
    expect(changed.streamCanceled, isTrue);
  });

  test('non-streaming providers must report a safe size before download', () async {
    final client = _Cloud();
    final file = FileItem(name: 'photo.png', isFolder: false);
    await expectLater(readGalleryRemoteBytes(client, '/photo.png', file, 4,
        isCurrent: () => true), throwsA(isA<GalleryMediaException>()));
    expect(client.reads, 0);
    client.reportedSize = 2;
    expect(await readGalleryRemoteBytes(client, '/photo.png', file, 4,
        isCurrent: () => true), [1, 2]);
    expect(client.reads, 1);
  });
}
