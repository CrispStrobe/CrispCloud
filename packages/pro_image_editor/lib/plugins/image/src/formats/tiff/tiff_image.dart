// ignore_for_file: public_member_api_docs

import '../../exif/exif_tag.dart';
import '../../exif/ifd_value.dart';
import '../../util/input_buffer.dart';
import 'tiff_entry.dart';

class TiffImage {
  TiffImage(InputBuffer p) {
    final p3 = InputBuffer.from(p);

    final numDirEntries = p.readUint16();
    for (var i = 0; i < numDirEntries; ++i) {
      final tag = p.readUint16();
      final ti = p.readUint16();
      final type = IfdValueType.values[ti];
      final typeSize = ifdValueTypeSize[ti];
      final count = p.readUint32();
      var valueOffset = 0;
      // The value for the tag is either stored in another location,
      // or within the tag itself (if the size fits in 4 bytes).
      // We're not reading the data here, just storing offsets.
      if (count * typeSize > 4) {
        valueOffset = p.readUint32();
      } else {
        valueOffset = p.offset;
        p.skip(4);
      }

      final entry = TiffEntry(tag, type, count, p3, valueOffset);

      tags[entry.tag] = entry;

      if (tag == exifTagNameToID['ImageWidth']) {
        width = entry.read()?.toInt() ?? 0;
      } else if (tag == exifTagNameToID['ImageLength']) {
        height = entry.read()?.toInt() ?? 0;
      } else if (tag == exifTagNameToID['PhotometricInterpretation']) {
        final v = entry.read();
        final pt = v?.toInt() ?? TiffPhotometricType.values.length;
        if (pt < TiffPhotometricType.values.length) {
          photometricType = TiffPhotometricType.values[pt];
        } else {
          photometricType = TiffPhotometricType.unknown;
        }
      } else if (tag == exifTagNameToID['Compression']) {
        compression = entry.read()?.toInt() ?? 0;
      } else if (tag == exifTagNameToID['BitsPerSample']) {
        bitsPerSample = entry.read()?.toInt() ?? 0;
      } else if (tag == exifTagNameToID['SamplesPerPixel']) {
        samplesPerPixel = entry.read()?.toInt() ?? 0;
      } else if (tag == exifTagNameToID['Predictor']) {
        predictor = entry.read()?.toInt() ?? 0;
      } else if (tag == exifTagNameToID['SampleFormat']) {
        final v = entry.read()?.toInt() ?? 0;
        sampleFormat = TiffFormat.values[v];
      } else if (tag == exifTagNameToID['ColorMap']) {
        final v = entry.read();
        if (v != null) {
          colorMap = v.toData().buffer.asUint16List();
          colorMapRed = 0;
          colorMapGreen = colorMap!.length ~/ 3;
          colorMapBlue = colorMapGreen * 2;
        }
      }
    }

    if (colorMap != null && photometricType == TiffPhotometricType.palette) {
      // Only support RGB palettes.
      colorMapSamples = 3;
      samplesPerPixel = 1;
    }

    if (width == 0 || height == 0) {
      return;
    }

    if (colorMap != null && bitsPerSample == 8) {
      final cm = colorMap!;
      final len = cm.length;
      for (var i = 0; i < len; ++i) {
        cm[i] >>= 8;
      }
    }

    if (photometricType == TiffPhotometricType.whiteIsZero) {
      isWhiteZero = true;
    }

    channelsPerPixel = samplesPerPixel;

    if (hasTag(exifTagNameToID['TileOffsets']!)) {
      tiled = true;
      // Image is in tiled format
      tileWidth = _readTag(exifTagNameToID['TileWidth']!);
      tileHeight = _readTag(exifTagNameToID['TileLength']!);
      tileOffsets = _readTagList(exifTagNameToID['TileOffsets']!);
      tileByteCounts = _readTagList(exifTagNameToID['TileByteCounts']!);
    } else {
      tiled = false;

      tileWidth = _readTag(exifTagNameToID['TileWidth']!, width);
      if (!hasTag(exifTagNameToID['RowsPerStrip']!)) {
        tileHeight = _readTag(exifTagNameToID['TileLength']!, height);
      } else {
        final l = _readTag(exifTagNameToID['RowsPerStrip']!);
        var infinity = 1;
        infinity = (infinity << 32) - 1;
        if (l == infinity) {
          // 2^32 - 1 (effectively infinity, entire image is 1 strip)
          tileHeight = height;
        } else {
          tileHeight = l;
        }
      }

      tileOffsets = _readTagList(exifTagNameToID['StripOffsets']!);
      tileByteCounts = _readTagList(exifTagNameToID['StripByteCounts']!);
    }

    // Calculate number of tiles and the tileSize in bytes
    tilesX = (width + tileWidth - 1) ~/ tileWidth;
    tilesY = (height + tileHeight - 1) ~/ tileHeight;
    tileSize = tileWidth * tileHeight * samplesPerPixel;

    fillOrder = _readTag(exifTagNameToID['FillOrder']!, 1);
    t4Options = _readTag(exifTagNameToID['T4Options']!);
    t6Options = _readTag(exifTagNameToID['T6Options']!);
    extraSamples = _readTag(exifTagNameToID['ExtraSamples']!);

    // Determine which kind of image we are dealing with.
    switch (photometricType) {
      case TiffPhotometricType.whiteIsZero:
      case TiffPhotometricType.blackIsZero:
        if (bitsPerSample == 1 && samplesPerPixel == 1) {
          imageType = TiffImageType.bilevel;
        } else if (bitsPerSample == 4 && samplesPerPixel == 1) {
          imageType = TiffImageType.gray4bit;
        } else if (bitsPerSample % 8 == 0) {
          if (samplesPerPixel == 1) {
            imageType = TiffImageType.gray;
          } else if (samplesPerPixel == 2) {
            imageType = TiffImageType.grayAlpha;
          } else {
            imageType = TiffImageType.generic;
          }
        }
        break;
      case TiffPhotometricType.rgb:
        if (bitsPerSample % 8 == 0) {
          if (samplesPerPixel == 3) {
            imageType = TiffImageType.rgb;
          } else if (samplesPerPixel == 4) {
            imageType = TiffImageType.rgba;
          } else {
            imageType = TiffImageType.generic;
          }
        }
        break;
      case TiffPhotometricType.palette:
        if (samplesPerPixel == 1 &&
            colorMap != null &&
            (bitsPerSample == 4 || bitsPerSample == 8 || bitsPerSample == 16)) {
          imageType = TiffImageType.palette;
        }
        break;
      case TiffPhotometricType.transparencyMask: // Transparency mask
        if (bitsPerSample == 1 && samplesPerPixel == 1) {
          imageType = TiffImageType.bilevel;
        }
        break;
      case TiffPhotometricType.yCbCr:
        if (compression == TiffCompression.jpeg &&
            bitsPerSample == 8 &&
            samplesPerPixel == 3) {
          imageType = TiffImageType.rgb;
        } else {
          if (hasTag(exifTagNameToID['YCbCrSubSampling']!)) {
            final v = tags[exifTagNameToID['YCbCrSubSampling']!]!.read()!;
            chromaSubH = v.toInt();
            chromaSubV = v.toInt(1);
          } else {
            chromaSubH = 2;
            chromaSubV = 2;
          }

          if (chromaSubH * chromaSubV == 1) {
            imageType = TiffImageType.generic;
          } else if (bitsPerSample == 8 && samplesPerPixel == 3) {
            imageType = TiffImageType.yCbCrSub;
          }
        }
        break;
      case TiffPhotometricType.cmyk:
        if (bitsPerSample % 8 == 0) {
          imageType = TiffImageType.generic;
        }
        if (samplesPerPixel == 4) {
          channelsPerPixel = 3;
        } else if (samplesPerPixel == 5) {
          channelsPerPixel = 4;
        }
        break;
      default: // Other including CMYK, CIE L*a*b*, unknown.
        if (bitsPerSample % 8 == 0) {
          imageType = TiffImageType.generic;
        }
        break;
    }
  }
  Map<int, TiffEntry> tags = {};
  int width = 0;
  int height = 0;
  TiffPhotometricType photometricType = TiffPhotometricType.unknown;
  int compression = 1;
  int bitsPerSample = 1;
  int samplesPerPixel = 1;
  int channelsPerPixel = 1;
  TiffFormat sampleFormat = TiffFormat.uint;
  TiffImageType imageType = TiffImageType.invalid;
  bool isWhiteZero = false;
  int predictor = 1;
  late int chromaSubH;
  late int chromaSubV;
  bool tiled = false;
  int tileWidth = 0;
  int tileHeight = 0;
  List<int>? tileOffsets;
  List<int>? tileByteCounts;
  late int tilesX;
  late int tilesY;
  int? tileSize;
  int? fillOrder = 1;
  int? t4Options = 0;
  int? t6Options = 0;
  int? extraSamples;
  int colorMapSamples = 0;
  List<int>? colorMap;
  // Starting index in the [colorMap] for the red channel.
  late int colorMapRed;
  // Starting index in the [colorMap] for the green channel.
  late int colorMapGreen;
  // Starting index in the [colorMap] for the blue channel.
  late int colorMapBlue;

  bool get isValid => width != 0 && height != 0;

  bool hasTag(int tag) => tags.containsKey(tag);

  int _readTag(int type, [int defaultValue = 0]) {
    if (!hasTag(type)) {
      return defaultValue;
    }
    return tags[type]!.read()?.toInt() ?? 0;
  }

  List<int>? _readTagList(int type) {
    if (!hasTag(type)) {
      return null;
    }
    final tag = tags[type]!;
    final value = tag.read()!;
    return List<int>.generate(tag.count, value.toInt);
  }
}

enum TiffFormat { invalid, uint, int, float }

enum TiffPhotometricType {
  whiteIsZero, // = 0
  blackIsZero, // = 1
  rgb, // = 2
  palette, // = 3
  transparencyMask, // = 4
  cmyk, // = 5
  yCbCr, // = 6
  reserved7, // = 7
  cieLab, // = 8
  iccLab, // = 9
  ituLab, // = 10
  logL, // = 32844
  logLuv, // = 32845
  colorFilterArray, // = 32803
  linearRaw, // = 34892
  depth, // = 51177
  unknown,
}

enum TiffImageType {
  bilevel,
  gray4bit,
  gray,
  grayAlpha,
  palette,
  rgb,
  rgba,
  yCbCrSub,
  generic,
  invalid,
}

class TiffCompression {
  const TiffCompression(this.value);
  static const none = 1;
  static const ccittRle = 2;
  static const ccittFax3 = 3;
  static const ccittFax4 = 4;
  static const lzw = 5;
  static const oldJpeg = 6;
  static const jpeg = 7;
  static const next = 32766;
  static const ccittRlew = 32771;
  static const packBits = 32773;
  static const thunderScan = 32809;
  static const it8ctpad = 32895;
  static const tt8lw = 32896;
  static const it8mp = 32897;
  static const it8bl = 32898;
  static const pixarFilm = 32908;
  static const pixarLog = 32909;
  static const deflate = 32946;
  static const zip = 8;
  static const dcs = 32947;
  static const jbig = 34661;
  static const sgiLog = 34676;
  static const sgiLog24 = 34677;
  static const jp2000 = 34712;
  final int value;
}
