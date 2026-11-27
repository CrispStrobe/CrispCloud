import 'dart:typed_data';

/// Bounded preview of an EMF whose visible content consists of a single DIB
/// copy, optionally on a solid background. Other GDI drawing is unsupported.
abstract final class OfficeEmfBitmap {
  static bool hasSignature(Uint8List bytes) {
    if (bytes.length < 88) return false;
    final header = ByteData.sublistView(bytes, 0, 88);
    return header.getUint32(0, Endian.little) == 1 &&
        header.getUint32(40, Endian.little) == 0x464d4520;
  }

  static ({int width, int height, Uint8List rgb, Uint8List? alpha})? decode(
    Uint8List bytes,
  ) {
    if (!hasSignature(bytes) || bytes.length > 16 * 1024 * 1024) return null;
    final data = ByteData.sublistView(bytes);
    int unsigned(int offset) => data.getUint32(offset, Endian.little);
    int signed(int offset) => data.getInt32(offset, Endian.little);
    int word(int offset) => data.getUint16(offset, Endian.little);

    final headerSize = unsigned(4);
    final records = unsigned(52);
    if (headerSize < 88 ||
        headerSize > bytes.length ||
        headerSize % 4 != 0 ||
        unsigned(48) != bytes.length ||
        records < 3 ||
        records > 4096) {
      return null;
    }
    final left = signed(8);
    final top = signed(12);
    final width = signed(16) - left + 1;
    final height = signed(20) - top + 1;
    if (width < 1 || width > 2048 || height < 1 || height > 2048) return null;

    var windowExtent = (1, 1);
    var viewportExtent = (1, 1);
    final saved = <((int, int), (int, int), int?)>[];
    final brushes = <int, int>{};
    int? brush;
    int? background;
    ({int x, int y, int width, int signedHeight, int offset, int stride})?
    bitmap;
    var offset = headerSize;
    for (var record = 1; record < records; record++) {
      if (offset + 8 > bytes.length) return null;
      final type = unsigned(offset);
      final size = unsigned(offset + 4);
      if (size < 8 || size % 4 != 0 || size > bytes.length - offset) {
        return null;
      }
      if ((record == records - 1) != (type == 14)) return null;
      int u(int index) => unsigned(offset + index * 4);
      int s(int index) => signed(offset + index * 4);
      switch (type) {
        case 9: // SETWINDOWEXTEX
        case 11: // SETVIEWPORTEXTEX
          if (size != 16 || s(2) <= 0 || s(3) <= 0) return null;
          final extent = (s(2), s(3));
          if (type == 9) {
            windowExtent = extent;
          } else {
            viewportExtent = extent;
          }
        case 10: // SETWINDOWORGEX
        case 12: // SETVIEWPORTORGEX
          if (size != 16 || s(2) != 0 || s(3) != 0) return null;
        case 17: // SETMAPMODE
          if (size != 12 || !const {1, 8}.contains(u(2))) return null;
        case 33: // SAVEDC
          if (size != 8) return null;
          saved.add((windowExtent, viewportExtent, brush));
        case 34: // RESTOREDC
          if (size != 12 || s(2) != -1 || saved.isEmpty) return null;
          (windowExtent, viewportExtent, brush) = saved.removeLast();
        case 37: // SELECTOBJECT
          if (size != 12) return null;
          brush = switch (u(2)) {
            0x80000000 => 0xffffff,
            0x80000004 => 0,
            final id => brushes[id],
          };
        case 39: // CREATEBRUSHINDIRECT
          if (size != 24 || u(3) != 0) return null;
          brushes[u(2)] = u(4) & 0xffffff;
        case 76: // BITBLT with PATCOPY and no source bitmap
          if (size != 100 ||
              u(10) != 0x00f00021 ||
              u(21) != 0 ||
              u(22) != 0 ||
              u(23) != 0 ||
              u(24) != 0 ||
              windowExtent != viewportExtent ||
              brush == null ||
              bitmap != null ||
              s(6) != left ||
              s(7) != top ||
              s(8) != width ||
              s(9) != height) {
            return null;
          }
          background = brush;
        case 81: // STRETCHDIBITS with an unscaled SRCCOPY
          if (size < 80 ||
              bitmap != null ||
              windowExtent != viewportExtent ||
              s(8) != 0 ||
              s(9) != 0 ||
              u(16) != 0 ||
              u(17) != 0x00cc0020 ||
              s(10) != s(18) ||
              s(11) != s(19)) {
            return null;
          }
          final x = s(6) - left;
          final y = s(7) - top;
          final w = s(10);
          final h = s(11);
          // Both offsets are relative to the start of this EMF record.
          final header = u(12);
          final bitmapStart = u(14);
          final bitmapLength = u(15);
          if (w < 1 ||
              h < 1 ||
              x < 0 ||
              y < 0 ||
              x + w > width ||
              y + h > height ||
              u(13) != 40 ||
              header < 80 ||
              header + 40 > bitmapStart ||
              bitmapStart + bitmapLength > size) {
            return null;
          }
          final dib = offset + header;
          final signedHeight = signed(dib + 8);
          final stride = (w * 3 + 3) & ~3;
          if (unsigned(dib) != 40 ||
              signed(dib + 4) != w ||
              signedHeight.abs() != h ||
              word(dib + 12) != 1 ||
              word(dib + 14) != 24 ||
              unsigned(dib + 16) != 0 ||
              bitmapLength != stride * h) {
            return null;
          }
          bitmap = (
            x: x,
            y: y,
            width: w,
            signedHeight: signedHeight,
            offset: offset + bitmapStart,
            stride: stride,
          );
        case 14: // EOF
          if (size < 20) return null;
        case 40: // DELOBJECT
          if (size != 12) return null;
          brushes.remove(u(2));
        case 18: // background mode
        case 22: // text alignment
        case 25: // background color
        case 48: // realize palette
        case 70: // comment, including the separate EMF+ stream on dual files
          break;
        case 75: // reset clipping region
          if (size != 16 || u(2) != 0 || u(3) != 5) return null;
        default:
          return null;
      }
      offset += size;
    }
    if (offset != bytes.length || bitmap == null) return null;

    final rgb = Uint8List(width * height * 3);
    final alpha = background == null ? Uint8List(width * height) : null;
    if (background != null) {
      for (var i = 0; i < rgb.length; i += 3) {
        rgb[i] = background & 255;
        rgb[i + 1] = (background >> 8) & 255;
        rgb[i + 2] = (background >> 16) & 255;
      }
    }
    final bitmapHeight = bitmap.signedHeight.abs();
    for (var row = 0; row < bitmapHeight; row++) {
      final sourceRow = bitmap.signedHeight > 0 ? bitmapHeight - 1 - row : row;
      var source = bitmap.offset + sourceRow * bitmap.stride;
      var pixel = (bitmap.y + row) * width + bitmap.x;
      for (var x = 0; x < bitmap.width; x++, pixel++, source += 3) {
        final i = pixel * 3;
        rgb[i] = bytes[source + 2];
        rgb[i + 1] = bytes[source + 1];
        rgb[i + 2] = bytes[source];
        alpha?[pixel] = 255;
      }
    }
    return (width: width, height: height, rgb: rgb, alpha: alpha);
  }
}
