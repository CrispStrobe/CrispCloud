// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_structured_render.dart';

// These are preview limits, not preservation limits. A native asset exceeding
// them remains in the model and receives a small placeholder in HTML.
const _htmlImageByteLimit = 2 * 1024 * 1024;
const _htmlImagePixelLimit = 16 * 1024 * 1024;
const _htmlRasterDecodedPixelLimit = 32 * 1024 * 1024;
const _htmlImageCacheLimit = 8 * 1024 * 1024;
const _htmlImageEmissionLimit = 3 * 1024 * 1024;

class _HtmlMediaEvent {
  const _HtmlMediaEvent({
    required this.cp,
    required this.order,
    required this.imageId,
    required this.presentation,
    required this.floating,
    required this.cropped,
    this.widthTwips,
    this.heightTwips,
  });
  final int cp, order;
  final String? imageId;
  final LegacyWordMediaPresentation presentation;
  final bool floating, cropped;
  final int? widthTwips, heightTwips;
}

class _HtmlImageData {
  const _HtmlImageData(this.uri, this.width, this.height, this.rasterPixels);
  final String uri;
  final int width, height;
  final int rasterPixels;
}

class _HtmlMediaIndex {
  _HtmlMediaIndex(LegacyWordMediaCatalog media) {
    if (media.assets.length > 4096 ||
        media.pictures.length + media.drawings.length > 4096) {
      throw const FormatException('Word preview media exceeds its item limit.');
    }
    for (final asset in media.assets) {
      if (_assets.containsKey(asset.id)) {
        throw const FormatException('Duplicate Word preview image identifier.');
      }
      _assets[asset.id] = asset;
    }
    void add(_HtmlMediaEvent event) {
      if (event.cp < 0 || event.cp > 0x7fffffff) {
        throw const FormatException('Invalid Word preview image anchor.');
      }
      if (!event.presentation.hidden) _events.add(event);
    }

    for (final picture in media.pictures) {
      if (picture.shapeDeleted) continue;
      add(
        _HtmlMediaEvent(
          cp: picture.cp,
          order: _events.length,
          imageId: picture.imageId,
          presentation: picture.presentation,
          floating: false,
          cropped:
              picture.cropTopFixed16 != 0 ||
              picture.cropBottomFixed16 != 0 ||
              picture.cropLeftFixed16 != 0 ||
              picture.cropRightFixed16 != 0,
          widthTwips: picture.widthTwips,
          heightTwips: picture.heightTwips,
        ),
      );
    }
    for (final drawing in media.drawings) {
      if (drawing.shapeDeleted || drawing.imageId == null) continue;
      add(
        _HtmlMediaEvent(
          cp: drawing.anchorCp,
          order: _events.length,
          imageId: drawing.imageId,
          presentation: drawing.presentation,
          floating: true,
          cropped:
              drawing.cropTopFixed16 != 0 ||
              drawing.cropBottomFixed16 != 0 ||
              drawing.cropLeftFixed16 != 0 ||
              drawing.cropRightFixed16 != 0,
          widthTwips: drawing.rightTwips - drawing.leftTwips,
          heightTwips: drawing.bottomTwips - drawing.topTwips,
        ),
      );
    }
    _events.sort((a, b) {
      final byCp = a.cp.compareTo(b.cp);
      return byCp != 0 ? byCp : a.order.compareTo(b.order);
    });
  }

  final _assets = <String, LegacyWordImageAsset>{};
  final _events = <_HtmlMediaEvent>[];
  final _cache = <String, _HtmlImageData?>{};
  var _inspectedBytes = 0;
  var _cachedCharacters = 0;
  var _emittedRasterPixels = 0;
  var _emittedUriCharacters = 0;
  var remainingExpansionBytes = 0;

  bool canEmit(_HtmlImageData image) =>
      image.rasterPixels <=
          _htmlRasterDecodedPixelLimit - _emittedRasterPixels &&
      image.uri.length <= _htmlImageEmissionLimit - _emittedUriCharacters;

  bool reserveImage(_HtmlImageData image, int expansionBytes) {
    // Hosts can decode each occurrence independently even when its URI is
    // shared. Charge every emitted occurrence, across all related stories.
    if (!canEmit(image) || expansionBytes > remainingExpansionBytes) {
      return false;
    }
    _emittedRasterPixels += image.rasterPixels;
    _emittedUriCharacters += image.uri.length;
    remainingExpansionBytes -= expansionBytes;
    return true;
  }

  int _lowerBound(int cp) {
    var low = 0, high = _events.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_events[middle].cp < cp) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  List<_HtmlMediaEvent> within(int first, int end) {
    if (first < 0 || end < first || end > 0x7fffffff) {
      throw const FormatException('Invalid Word preview paragraph range.');
    }
    return _events.sublist(_lowerBound(first), _lowerBound(end));
  }

  _HtmlImageData? image(String? id) {
    if (id == null) return null;
    if (_cache.containsKey(id)) return _cache[id];
    final asset = _assets[id];
    _cache[id] = null;
    if (asset == null ||
        asset.bytes.length > 64 * 1024 * 1024 - _inspectedBytes ||
        _cachedCharacters >= _htmlImageCacheLimit) {
      return null;
    }
    _inspectedBytes += asset.bytes.length;
    Uint8List bytes;
    String type;
    int width, height;
    switch (asset.format) {
      case LegacyWordImageFormat.png:
      case LegacyWordImageFormat.jpeg:
        bytes = asset.bytes;
        if (bytes.length > _htmlImageByteLimit) return null;
        final size = asset.format == LegacyWordImageFormat.png
            ? _pngSize(bytes)
            : _jpegSize(bytes);
        if (size == null) return null;
        (width, height) = size;
        type = asset.format == LegacyWordImageFormat.png
            ? 'image/png'
            : 'image/jpeg';
      case LegacyWordImageFormat.emf:
      case LegacyWordImageFormat.wmf:
        // Public models can contain arbitrary previewSvg strings. Always
        // regenerate from bounded raw records, never trust that metadata.
        LegacyWordMetafileInfo info;
        try {
          info = parseLegacyWordMetafile(
            asset.bytes,
            format: asset.format,
            maxPreviewCharacters: _htmlImageByteLimit ~/ 4,
          );
        } on FormatException {
          return null;
        }
        final svg = info.previewSvg;
        if (svg == null || !info.nativeEmbeddingAllowed) return null;
        bytes = utf8.encode(svg);
        if (bytes.length > _htmlImageByteLimit) return null;
        width = info.bounds.width;
        height = info.bounds.height;
        type = 'image/svg+xml';
      default:
        // TIFF/DIB/PICT and opaque formats remain available to native output.
        return null;
    }
    final encodedLength = ((bytes.length + 2) ~/ 3) * 4;
    final prefix = 'data:$type;base64,';
    if (encodedLength + prefix.length >
        _htmlImageCacheLimit - _cachedCharacters) {
      return null;
    }
    final uri = '$prefix${base64.encode(bytes)}';
    _cachedCharacters += uri.length;
    return _cache[id] = _HtmlImageData(
      uri,
      width,
      height,
      type == 'image/svg+xml' ? 0 : width * height,
    );
  }

  static bool _sizeAllowed(int width, int height) =>
      width > 0 &&
      height > 0 &&
      width <= 16384 &&
      height <= 16384 &&
      width * height <= _htmlImagePixelLimit;

  static (int, int)? _pngSize(Uint8List bytes) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 45) return null;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return null;
    }
    final input = ByteData.sublistView(bytes);
    if (input.getUint32(8) != 13 || input.getUint32(12) != 0x49484452) {
      return null;
    }
    final width = input.getUint32(16), height = input.getUint32(20);
    if (!_sizeAllowed(width, height)) return null;
    var offset = 8, chunks = 0;
    var pixels = false;
    while (offset <= bytes.length - 12 && ++chunks <= 4096) {
      final length = input.getUint32(offset);
      if (length > bytes.length - offset - 12) return null;
      final type = input.getUint32(offset + 4);
      if (type == 0x6163544c) {
        return null; // APNG has an unbounded frame budget.
      }
      if (type == 0x49444154) pixels = true;
      offset += length + 12;
      if (type == 0x49454e44) {
        return length == 0 && pixels && offset == bytes.length
            ? (width, height)
            : null;
      }
    }
    return null;
  }

  static (int, int)? _jpegSize(Uint8List bytes) {
    if (bytes.length < 4 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[bytes.length - 2] != 0xff ||
        bytes.last != 0xd9) {
      return null;
    }
    final input = ByteData.sublistView(bytes);
    var offset = 2, records = 0;
    (int, int)? size;
    while (offset < bytes.length - 2 && ++records <= 4096) {
      if (bytes[offset++] != 0xff) return null;
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (offset >= bytes.length) return null;
      final marker = bytes[offset++];
      if (marker == 0 || marker == 0xd8 || marker == 0xd9) return null;
      if (marker == 1 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      if (offset > bytes.length - 2) return null;
      final length = input.getUint16(offset);
      if (length < 2 || length > bytes.length - offset) return null;
      if (marker == 0xc0 || marker == 0xc1 || marker == 0xc2) {
        if (length < 8 || size != null) return null;
        final height = input.getUint16(offset + 3);
        final width = input.getUint16(offset + 5);
        if (!_sizeAllowed(width, height)) return null;
        size = (width, height);
      }
      if (marker == 0xda) return size;
      offset += length;
    }
    return null;
  }
}

extension _HtmlMediaWriter on _HtmlWriter {
  void _image(_HtmlMediaEvent event) {
    _item();
    // Showing the complete uncropped asset could expose source content outside
    // its visible crop. Until crop playback is shared by HTML hosts, omit it.
    final placeholder =
        '<span data-word-image="unavailable" '
        'data-word-image-cp="${event.cp}"'
        '${event.cropped ? ' data-word-image-crop="not-reproduced"' : ''}'
        '>[Image preview unavailable]</span>';
    final data =
        measureOnly ||
            event.cropped ||
            imageExpansionBytes == 0 ||
            _media.remainingExpansionBytes == 0
        ? null
        : _media.image(event.imageId);
    String? imageMarkup;
    if (data != null && _media.canEmit(data)) {
      var width = event.widthTwips != null && event.widthTwips! > 0
          ? event.widthTwips! / 15
          : data.width.toDouble();
      var height = event.heightTwips != null && event.heightTwips! > 0
          ? event.heightTwips! / 15
          : data.height.toDouble();
      if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
        width = height = 96;
      }
      final largest = width > height ? width : height;
      if (largest > 2048) {
        width *= 2048 / largest;
        height *= 2048 / largest;
      }
      final layout = event.floating ? 'anchor-approximation' : 'inline';
      final markup =
          '<img data-word-image="$layout" data-word-image-cp="${event.cp}"'
          ' src="${data.uri}" width="${width.ceil().clamp(1, 2048)}"'
          ' height="${height.ceil().clamp(1, 2048)}"'
          ' alt="${event.floating ? 'Floating image shown at its text anchor' : 'Embedded image'}"'
          ' style="max-width:100%;height:auto;object-fit:contain;vertical-align:middle;">';
      final expansion = (markup.length - placeholder.length).clamp(
        0,
        markup.length,
      );
      if (expansion <= imageExpansionBytes &&
          _media.reserveImage(data, expansion)) {
        imageExpansionBytes -= expansion;
        imageMarkup = markup;
      }
    }
    final presentation = event.presentation;
    if (presentation.deleted) {
      _write(
        '<del data-word-image-revision="deleted" '
        'style="background-color:#ffe8e8;border:1px solid #b40000;">'
        '<span>Deleted image: </span>',
      );
    }
    if (presentation.inserted) {
      _write(
        '<ins data-word-image-revision="inserted" '
        'style="background-color:#e5f5e5;border:1px solid #267326;">',
      );
    }
    _write(imageMarkup ?? placeholder);
    if (presentation.inserted) _write('</ins>');
    if (presentation.deleted) _write('</del>');
  }
}
