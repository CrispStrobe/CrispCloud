import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../models/file_item.dart';
import 'gallery_image_decoder.dart';
import 'thumbnail_service.dart';

export 'gallery_image_decoder.dart'
    show kGalleryInputLimitBytes, kGalleryMaxPixels;

class GalleryMediaException implements Exception {
  const GalleryMediaException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef GalleryBytesReader = Future<Uint8List> Function(int maxBytes);

/// Captured source for one image. Storage routing and account validity are
/// established once, before asynchronous work starts. A pane's left/right
/// label never determines where image bytes come from.
class GalleryMediaRequest {
  GalleryMediaRequest({
    required this.file,
    required this.namespaceId,
    required this.path,
    required this.readBytes,
    this.readProviderThumbnail,
    bool Function()? isCurrent,
    this.isRemote = false,
    this.isArchive = false,
    String revisionSalt = '',
  }) : _isCurrent = isCurrent ?? _alwaysCurrent,
       assetId = _digest([namespaceId, file.uuid ?? path]),
       revisionKey = _digest([
         namespaceId,
         path,
         file.uuid,
         file.name,
         file.size,
         file.updatedAt?.microsecondsSinceEpoch,
         revisionSalt,
         for (final key in _revisionFields) [key, '${file.metadata?[key] ?? ''}'],
       ]);

  final FileItem file;
  /// Stable account/source scope when storage exposes an account identity.
  final String namespaceId;
  /// Stable catalog identity; deliberately excludes mutable image revisions.
  final String assetId;
  /// Includes account, path, size, modification time and provider revisions.
  final String revisionKey;
  final String path;
  final bool isRemote;
  final bool isArchive;
  final GalleryBytesReader readBytes;
  final Future<Uint8List?> Function()? readProviderThumbnail;
  final bool Function() _isCurrent;

  bool get isCurrent {
    try { return _isCurrent(); } catch (_) { return false; }
  }

  void assertCurrent() {
    if (!isCurrent) {
      throw const GalleryMediaException(
        'The image source changed. Refresh the folder and open the image again.',
      );
    }
  }

  static bool _alwaysCurrent() => true;
  static bool hasRevisionMetadata(FileItem file) => file.updatedAt != null ||
      _revisionFields.any((key) {
        final value = file.metadata?[key];
        return value != null && '$value'.isNotEmpty;
      });
  static const _revisionFields = [
    'etag', 'eTag', 'version', 'versionId', 'revision', 'rev',
    'contentHash', 'content_hash', 'md5Checksum', 'sha1Hash',
    'updatedAt', 'modificationTime', 'lastModified', 'lastModifiedDateTime',
  ];
  static String _digest(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
}

class GalleryImageData {
  const GalleryImageData({
    required this.bytes,
    required this.width,
    required this.height,
    this.frameCount = 1,
    this.metadata = const {},
    this.isSvg = false,
    this.isConverted = false,
  });

  /// Displayable bytes. Common raster formats retain their original animation;
  /// SVG stays SVG; fallback formats are converted to a first-frame PNG.
  /// Use loadOriginal when exporting the source file unchanged.
  final Uint8List bytes;
  final int width;
  final int height;
  final int frameCount;
  final Map<String, String> metadata;
  final bool isSvg;
  final bool isConverted;
}

/// Shared bounded loader for thumbnails, preview, compare and export. Original
/// images are not retained in a global cache: opening a large folder must not
/// keep every full-resolution file in memory. Concurrent reads coalesce and
/// only three loads/decodes can run at once; full-size user requests go first.
class GalleryMediaService {
  GalleryMediaService({required this.thumbnails, this.maxConcurrentLoads = 3})
      : assert(maxConcurrentLoads > 0);

  final ThumbnailService thumbnails;
  final int maxConcurrentLoads;
  int _activeLoads = 0;
  final Queue<Completer<void>> _waiting = Queue();
  final Map<String, Future<Uint8List>> _originalReads = {};
  final Map<String, Future<GalleryImageData>> _imageReads = {};
  final Map<String, Future<Uint8List?>> _thumbnailReads = {};
  final Set<String> _unpreviewable = {};

  static const _rawExtensions = {
    'raw', 'dng', 'cr2', 'cr3', 'crw', 'nef', 'nrw', 'arw', 'srf', 'sr2',
    'raf', 'orf', 'rw2', 'pef', 'x3f', '3fr', 'fff', 'iiq', 'kdc', 'mos',
    'mrw', 'rwl', 'srw', 'erf',
  };

  /// Gallery candidates include camera RAW files even when only a provider
  /// thumbnail is available. Unsupported originals remain visible as files.
  static bool isImageFile(FileItem file) => !file.isFolder &&
      (ThumbnailService.isSupported(file.name) || file.extension == 'svg' ||
          _rawExtensions.contains(file.extension));

  static bool isSupported(FileItem file) => !file.isFolder &&
      (ThumbnailService.isSupported(file.name) || file.extension == 'svg');

  /// Provider thumbnails for SVG files can be raster PNGs; extension-based
  /// dispatch alone is insufficient. Our raster thumbnails are always PNG.
  static bool bytesAreSvg(Uint8List bytes) {
    final prefix = utf8.decode(bytes.sublist(0,
        bytes.length < 256 ? bytes.length : 256), allowMalformed: true)
        .replaceFirst('\ufeff', '').trimLeft();
    return prefix.startsWith('<');
  }

  Future<Uint8List> loadOriginal(GalleryMediaRequest request,
      {int? maxBytes}) async {
    final limit = maxBytes ?? kGalleryInputLimitBytes;
    if (limit < 1 || limit > kGalleryInputLimitBytes) {
      throw RangeError.range(limit, 1, kGalleryInputLimitBytes, 'maxBytes');
    }
    request.assertCurrent();
    _checkFile(request.file, limit);
    final key = '${request.revisionKey}:original:$limit';
    var future = _originalReads[key];
    if (future == null) {
      future = _withSlot(() => _readOriginal(request, limit), priority: true);
      _originalReads[key] = future;
    }
    try {
      final bytes = await future;
      request.assertCurrent();
      return bytes;
    } finally {
      if (identical(_originalReads[key], future)) _originalReads.remove(key);
    }
  }

  Future<GalleryImageData> loadImage(GalleryMediaRequest request) async {
    request.assertCurrent();
    _checkFile(request.file, kGalleryInputLimitBytes);
    final key = request.revisionKey;
    var future = _imageReads[key];
    if (future == null) {
      future = _withSlot(() async {
        final limit = request.file.extension == 'svg'
            ? 4 * 1024 * 1024 : kGalleryInputLimitBytes;
        final bytes = await _readOriginal(request, limit);
        final image = request.file.extension == 'svg'
            ? await _inspectSvg(bytes)
            : await _decodeImage(bytes, request.file.name);
        request.assertCurrent();
        return image;
      }, priority: true);
      _imageReads[key] = future;
    }
    try {
      final image = await future;
      request.assertCurrent();
      return image;
    } finally {
      if (identical(_imageReads[key], future)) _imageReads.remove(key);
    }
  }

  /// Returns PNG thumbnails, except SVGs which keep their bounded vector
  /// bytes for SvgPicture. A null result means this format cannot be decoded.
  Future<Uint8List?> loadThumbnail(GalleryMediaRequest request,
      {int size = 256, bool retry = false}) async {
    request.assertCurrent();
    if (!isImageFile(request.file)) return null;
    if (size < 1 || size > 2048) throw RangeError.range(size, 1, 2048, 'size');
    final key = '${request.revisionKey}:thumb:$size';
    if (retry) {
      _unpreviewable.remove(key);
      await thumbnails.invalidate(request.revisionKey, size: size);
    }
    if (_unpreviewable.contains(key)) return null;
    final cached = await thumbnails.readCached(request.revisionKey, size: size);
    request.assertCurrent();
    if (cached != null) return cached;
    var future = _thumbnailReads[key];
    if (future == null) {
      future = _withSlot(() async {
        request.assertCurrent();
        // Provider-generated previews avoid downloading huge cloud originals
        // and can display otherwise unsupported formats such as camera RAW.
        final provider = request.readProviderThumbnail;
        if (provider != null) {
          Uint8List? providerBytes;
          try { providerBytes = await provider(); } catch (_) { /* Fall back. */ }
          request.assertCurrent();
          if (providerBytes != null && providerBytes.length <= 4 * 1024 * 1024) {
            final thumbnail = await thumbnails.generate(
              request.revisionKey, providerBytes, size: size,
            );
            request.assertCurrent();
            if (thumbnail != null) return thumbnail;
          }
        }
        if (!isSupported(request.file)) return null;
        final isSvg = request.file.extension == 'svg';
        final bytes = await _readOriginal(request,
            isSvg ? 4 * 1024 * 1024 : kGalleryInputLimitBytes);
        if (isSvg) {
          await _inspectSvg(bytes);
          request.assertCurrent();
          await thumbnails.cacheProviderThumbnail(request.revisionKey, bytes,
              size: size);
          return bytes;
        }
        final thumbnail = await thumbnails.generate(
          request.revisionKey, bytes, size: size, fileName: request.file.name,
        );
        request.assertCurrent();
        return thumbnail;
      });
      _thumbnailReads[key] = future;
    }
    try {
      final result = await future;
      request.assertCurrent();
      if (result == null) {
        while (_unpreviewable.length >= 512) {
          _unpreviewable.remove(_unpreviewable.first);
        }
        _unpreviewable.add(key);
      }
      return result;
    } finally {
      if (identical(_thumbnailReads[key], future)) _thumbnailReads.remove(key);
    }
  }

  Future<Uint8List> _readOriginal(GalleryMediaRequest request, int limit) async {
    request.assertCurrent();
    _checkFile(request.file, limit);
    try {
      final bytes = await request.readBytes(limit);
      request.assertCurrent();
      if (bytes.length > limit) throw _tooLarge(limit);
      if (bytes.isEmpty) throw const GalleryMediaException('This image is empty.');
      return bytes.asUnmodifiableView();
    } on GalleryMediaException {
      rethrow;
    } catch (_) {
      throw const GalleryMediaException(
        'Could not read this image. Check the connection or file permissions and retry.',
      );
    }
  }

  Future<T> _withSlot<T>(Future<T> Function() operation,
      {bool priority = false}) async {
    if (_activeLoads >= maxConcurrentLoads) {
      final waiter = Completer<void>();
      priority ? _waiting.addFirst(waiter) : _waiting.addLast(waiter);
      await waiter.future;
    } else {
      _activeLoads++;
    }
    try {
      return await operation();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _activeLoads--;
      }
    }
  }

  static void _checkFile(FileItem file, int limit) {
    if (file.isFolder) throw const GalleryMediaException('Choose an image file.');
    if ((file.size ?? 0) > limit) throw _tooLarge(limit);
  }

  static GalleryMediaException _tooLarge(int limit) => GalleryMediaException(
    'This image exceeds the ${(limit / (1024 * 1024)).ceil()} MiB preview limit.',
  );

  static Future<GalleryImageData> _decodeImage(Uint8List bytes, String name) async {
    final metadata = readGalleryExif(bytes);
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? firstFrame;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width < 1 || descriptor.height < 1 ||
          descriptor.width * descriptor.height > kGalleryMaxPixels) {
        throw const GalleryMediaException('This image exceeds the 40 megapixel preview limit.');
      }
      codec = await descriptor.instantiateCodec();
      firstFrame = (await codec.getNextFrame()).image;
      return GalleryImageData(
        bytes: bytes,
        width: firstFrame.width,
        height: firstFrame.height,
        frameCount: codec.frameCount,
        metadata: Map.unmodifiable(metadata),
      );
    } on GalleryMediaException {
      rethrow;
    } catch (_) {
      // The pure Dart fallback below widens supported image formats.
    } finally {
      firstFrame?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
    final decoded = await compute(decodeGalleryRaster,
        GalleryDecodeRequest(bytes, fileName: name));
    if (decoded == null) {
      throw const GalleryMediaException(
        'This image format is unsupported on this device, damaged, or too large to decode.',
      );
    }
    return GalleryImageData(
      bytes: decoded.bytes,
      width: decoded.width,
      height: decoded.height,
      frameCount: decoded.frameCount,
      isConverted: true,
      metadata: Map.unmodifiable({
        ...metadata,
        'Preview': decoded.frameCount > 1 ? 'First frame / page' : 'Converted PNG preview',
      }),
    );
  }

  static Future<GalleryImageData> _inspectSvg(Uint8List bytes) async {
    try {
      final document = XmlDocument.parse(utf8.decode(bytes));
      final root = document.rootElement;
      if (root.name.local != 'svg') throw const FormatException('Not SVG');
      final viewBox = root.getAttribute('viewBox')?.trim()
          .split(RegExp(r'[\s,]+')).map(double.tryParse).toList();
      double? dimension(String name) {
        final value = root.getAttribute(name)?.trim();
        if (value == null || value.endsWith('%')) return null;
        return double.tryParse(value.replaceFirst(RegExp(r'px$'), ''));
      }
      final width = dimension('width') ??
          (viewBox?.length == 4 ? viewBox![2] : null) ?? 300;
      final height = dimension('height') ??
          (viewBox?.length == 4 ? viewBox![3] : null) ?? 150;
      if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0 ||
          width * height > kGalleryMaxPixels) {
        throw const GalleryMediaException('This SVG has invalid or excessive dimensions.');
      }
      // A tiny outer viewBox can embed a compressed, enormous raster image.
      // Check those headers before handing SVG bytes to vector_graphics,
      // whose image decoder otherwise bypasses the gallery pixel budget.
      var pixels = width * height;
      var elements = 0;
      var embeddedImages = 0;
      for (final node in root.descendants.whereType<XmlElement>()) {
        if (++elements > 10000) {
          throw const GalleryMediaException('This SVG has too many elements to preview.');
        }
        if (node.name.local != 'image' && node.name.local != 'feImage') continue;
        if (++embeddedImages > 64) {
          throw const GalleryMediaException('This SVG has too many embedded images to preview.');
        }
        final href = node.getAttribute('href') ??
            node.getAttribute('href', namespace: 'http://www.w3.org/1999/xlink');
        if (href == null || href.isEmpty) continue;
        final data = Uri.tryParse(href)?.data;
        if (data == null || !data.mimeType.toLowerCase().startsWith('image/') ||
            data.mimeType.toLowerCase().contains('svg')) {
          throw const GalleryMediaException(
            'This SVG contains linked or nested SVG images. Use a self-contained raster export to preview it.',
          );
        }
        final embedded = Uint8List.fromList(data.contentAsBytes());
        if (embedded.length > 4 * 1024 * 1024) {
          throw const GalleryMediaException('An embedded SVG image exceeds the preview limit.');
        }
        ui.ImmutableBuffer? buffer;
        ui.ImageDescriptor? descriptor;
        try {
          buffer = await ui.ImmutableBuffer.fromUint8List(embedded);
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          if (descriptor.width < 1 || descriptor.height < 1) {
            throw const GalleryMediaException('An embedded SVG image has invalid dimensions.');
          }
          pixels += descriptor.width * descriptor.height;
          if (pixels > kGalleryMaxPixels) {
            throw const GalleryMediaException('The embedded SVG images exceed the 40 megapixel preview limit.');
          }
        } finally {
          descriptor?.dispose();
          buffer?.dispose();
        }
      }
      return GalleryImageData(bytes: bytes,
          width: width.round().clamp(1, kGalleryMaxPixels),
          height: height.round().clamp(1, kGalleryMaxPixels), isSvg: true);
    } on GalleryMediaException {
      rethrow;
    } catch (_) {
      throw const GalleryMediaException('This SVG image could not be read.');
    }
  }
}
