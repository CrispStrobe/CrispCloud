import 'dart:async';
import 'dart:typed_data';

import '../image/image.dart';
import 'bmp_encoder.dart';
import 'cur_encoder.dart';
import 'ico_encoder.dart';
import 'jpeg/jpeg_chroma.dart';
import 'jpeg_encoder.dart';
import 'png/png_filter.dart';
import 'png_encoder.dart';
import 'pvr_encoder.dart';
import 'tga_encoder.dart';
import 'tiff_encoder.dart';

/// Encode an [image] to the JPEG format.
Future<Uint8List> encodeJpg(
  Image image, {
  int quality = 100,
  required int backgroundColor,
  JpegChroma chroma = JpegChroma.yuv444,
  Completer<void>? destroy$,
}) => JpegHealthyEncoder(quality: quality).encode(
  image,
  chroma: chroma,
  destroy$: destroy$,
  backgroundColor: backgroundColor,
);

/// Encode an image to the PNG format.
Uint8List encodePng(
  Image image, {
  bool singleFrame = false,
  int level = 6,
  PngFilter filter = PngFilter.paeth,
}) => PngEncoder(
  filter: filter,
  level: level,
).encode(image, singleFrame: singleFrame);

/// Encode an image to the TGA format.
Uint8List encodeTga(Image image) => TgaEncoder().encode(image);

/// Encode an image to the Tiff format.
Uint8List encodeTiff(Image image, {bool singleFrame = false}) =>
    TiffEncoder().encode(image, singleFrame: singleFrame);

/// Encode an [Image] to the BMP format.
Uint8List encodeBmp(Image image) => BmpEncoder().encode(image);

/// Encode an [Image] to the CUR format.
Uint8List encodeCur(Image image, {bool singleFrame = false}) =>
    CurEncoder().encode(image, singleFrame: singleFrame);

/// Encode an image to the ICO format.
Uint8List encodeIco(Image image, {bool singleFrame = false}) =>
    IcoEncoder().encode(image, singleFrame: singleFrame);

/// Encode an image to the PVR format.
Uint8List encodePvr(Image image, {bool singleFrame = false}) =>
    PvrEncoder().encode(image, singleFrame: singleFrame);
