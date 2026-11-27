import 'dart:async';
import 'dart:io' show File, FileSystemEntity, FileSystemEntityType;
import 'dart:math' as math;
import 'dart:typed_data' show BytesBuilder;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// Read, validate, and normalize untrusted clipboard or drop image data.
abstract final class WordImageImport {
  static const formats = [Formats.png, Formats.jpeg, Formats.webp, Formats.gif];
  static const maxInputBytes = 12 * 1024 * 1024;
  static const maxBatchBytes = 24 * 1024 * 1024;
  static const maxDropItems = 4;
  static const _transferTimeout = Duration(seconds: 8);

  static Future<Uint8List?> readBytes(
    DataReader reader, {
    bool localFiles = false,
  }) async {
    try {
      if (localFiles && !kIsWeb && reader.canProvide(Formats.fileUri)) {
        final file = await _request<Uri>(
          (complete) => reader.getValue(
            Formats.fileUri,
            complete,
            onError: (_) => complete(null),
          ),
        );
        if (file == null ||
            file.scheme != 'file' ||
            file.host.isNotEmpty ||
            file.pathSegments.isEmpty ||
            !RegExp(
              r'\.(png|jpe?g|webp|gif)$',
              caseSensitive: false,
            ).hasMatch(file.pathSegments.last)) {
          return null;
        }
        final source = File.fromUri(file);
        if (await FileSystemEntity.type(source.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await source.length() > maxInputBytes) {
          return null;
        }
        return await _boundedBytes(source.openRead());
      }
      for (final format in formats) {
        if (!reader.canProvide(format)) continue;
        return await _request<Uint8List>(
          (complete) => reader.getFile(
            format,
            (file) async {
              try {
                if ((file.fileSize ?? 0) > maxInputBytes) {
                  complete(null);
                  return;
                }
                complete(await _boundedBytes(file.getStream()));
              } on Object {
                complete(null);
              }
            },
            onError: (_) => complete(null),
            synthesizeFilesFromURIs: false,
          ),
        );
      }
    } on Object {
      return null;
    }
    return null;
  }

  static Future<T?> _request<T>(
    ReadProgress? Function(void Function(T?) complete) start,
  ) async {
    final result = Completer<T?>();
    void complete(T? value) {
      if (!result.isCompleted) result.complete(value);
    }

    final progress = start(complete);
    if (progress == null) return null;
    return result.future.timeout(
      _transferTimeout,
      onTimeout: () {
        complete(null);
        progress.cancel();
        return null;
      },
    );
  }

  static Future<Uint8List?> _boundedBytes(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    await for (final part in stream.timeout(_transferTimeout)) {
      if (part.length > maxInputBytes - bytes.length) return null;
      bytes.add(part);
    }
    return bytes.takeBytes();
  }

  /// Creates a static PNG containing only decoded pixels. Oversized and
  /// malformed input is rejected before it can enter the document.
  static Future<OfficeVisual?> normalize(Uint8List bytes) async {
    if (bytes.length > maxInputBytes || !_hasBitmapSignature(bytes)) {
      return null;
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width < 1 ||
          height < 1 ||
          width > 8192 ||
          height > 8192 ||
          width * height > 24 * 1024 * 1024) {
        return null;
      }
      final scale = math.min(1.0, 2560 / math.max(width, height));
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || data.lengthInBytes > maxInputBytes) return null;
      final layout = math.min(
        .75,
        math.min(432 / image.width, 432 / image.height),
      );
      return OfficeVisual(
        kind: OfficeVisualKind.picture,
        imageBytes: data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
        width: image.width * layout,
        height: image.height * layout,
      );
    } on Object {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static bool _hasBitmapSignature(Uint8List bytes) {
    if (bytes.length < 12) return false;
    bool matches(int offset, List<int> magic) {
      for (var i = 0; i < magic.length; i++) {
        if (bytes[offset + i] != magic[i]) return false;
      }
      return true;
    }

    return matches(0, const [137, 80, 78, 71, 13, 10, 26, 10]) ||
        matches(0, const [255, 216, 255]) ||
        matches(0, const [71, 73, 70, 56, 55, 97]) ||
        matches(0, const [71, 73, 70, 56, 57, 97]) ||
        (matches(0, const [82, 73, 70, 70]) &&
            matches(8, const [87, 69, 66, 80]));
  }
}
