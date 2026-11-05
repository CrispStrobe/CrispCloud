// ignore_for_file: public_member_api_docs

import '../color/color.dart';
import '../color/color_float16.dart';
import '../color/color_float32.dart';
import '../color/color_float64.dart';
import '../color/color_int16.dart';
import '../color/color_int32.dart';
import '../color/color_int8.dart';
import '../color/color_uint1.dart';
import '../color/color_uint16.dart';
import '../color/color_uint2.dart';
import '../color/color_uint32.dart';
import '../color/color_uint4.dart';
import '../color/color_uint8.dart';
import '../color/format.dart';

int rgbaToUint32(int r, int g, int b, int a) =>
    r.clamp(0, 255) |
    (g.clamp(0, 255) << 8) |
    (b.clamp(0, 255) << 16) |
    (a.clamp(0, 255) << 24);

Color _convertColor(Color c, Color c2, num a) {
  final numChannels = c2.length;
  final format = c2.format;
  final fromFormat = c.palette?.format ?? c.format;
  final cl = c.length;
  if (numChannels == 1) {
    final g = c.length > 2 ? c.luminance : c[0];
    final gi = (c[0] is int) ? g.floor() : g;
    c2[0] = convertFormatValue(gi, fromFormat, format);
  } else if (numChannels <= cl) {
    for (var ci = 0; ci < numChannels; ++ci) {
      c2[ci] = convertFormatValue(c[ci], fromFormat, format);
    }
  } else {
    if (cl == 2) {
      final l = convertFormatValue(c[0], fromFormat, format);
      if (numChannels == 3) {
        c2[0] = l;
        c2[1] = l;
        c2[2] = l;
      } else {
        final a = convertFormatValue(c[1], fromFormat, format);
        c2[0] = l;
        c2[1] = l;
        c2[2] = l;
        c2[3] = a;
      }
    } else {
      for (var ci = 0; ci < cl; ++ci) {
        c2[ci] = convertFormatValue(c[ci], fromFormat, format);
      }
      final v = cl == 1 ? c2[0] : 0;
      for (var ci = cl; ci < numChannels; ++ci) {
        c2[ci] = ci == 3 ? a : v;
      }
    }
  }
  return c2;
}

Color convertColor(
  Color c, {
  Color? to,
  Format? format,
  int? numChannels,
  num? alpha,
}) {
  final fromFormat = c.palette?.format ?? c.format;
  format = to?.format ?? format ?? c.format;
  numChannels = to?.length ?? numChannels ?? c.length;
  alpha ??= 0;

  if (format == fromFormat && numChannels == c.length) {
    if (to == null) {
      return c.clone();
    }
    to.set(c);
    return to;
  }

  switch (format) {
    case Format.uint8:
      final c2 = to ?? ColorUint8(numChannels);
      return _convertColor(c, c2, alpha);
    case Format.uint1:
      final c2 = to ?? ColorUint1(numChannels);
      return _convertColor(c, c2, alpha);
    case Format.uint2:
      final c2 = to ?? ColorUint2(numChannels);
      return _convertColor(c, c2, alpha);
    case Format.uint4:
      final c2 = to ?? ColorUint4(numChannels);
      return _convertColor(c, c2, alpha);
    case Format.uint16:
      final c2 = to ?? ColorUint16(numChannels);
      return _convertColor(c, c2, alpha);
    case Format.uint32:
      final c2 = to ?? ColorUint32(numChannels);
      return _convertColor(c, c2, alpha);
    case Format.int8:
      final c2 = to ?? ColorInt8(numChannels);
      return _convertColor(c, c2, alpha);
    case Format.int16:
      final c2 = to ?? ColorInt16(numChannels);
      return _convertColor(c, c2, alpha);
    case Format.int32:
      final c2 = to ?? ColorInt32(numChannels);
      return _convertColor(c, c2, alpha);
    case Format.float16:
      final c2 = to ?? ColorFloat16(numChannels);
      return _convertColor(c, c2, alpha);
    case Format.float32:
      final c2 = to ?? ColorFloat32(numChannels);
      return _convertColor(c, c2, alpha);
    case Format.float64:
      final c2 = to ?? ColorFloat64(numChannels);
      return _convertColor(c, c2, alpha);
  }
}

/// Returns the luminance (grayscale) value of the color.
num getLuminance(Color c) => 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;

/// Returns the normalized \[0, 1\] luminance (grayscale) value of the color.
num getLuminanceNormalized(Color c) =>
    0.299 * c.rNormalized + 0.587 * c.gNormalized + 0.114 * c.bNormalized;
