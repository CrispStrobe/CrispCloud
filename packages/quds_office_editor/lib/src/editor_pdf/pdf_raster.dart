import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:quds_office_engine/pdf_file.dart';

/// Decodes PDF image XObjects for [Canvas] (JPEG, PNG, or raw RGB).
abstract final class PdfRaster {
  /// Invokes [onReady] once the raster is a [ui.Image].
  static void decode(PdfDrawImage op, void Function(ui.Image image) onReady) {
    if (op.placeholder || op.bytes.isEmpty) {
      return;
    }
    final Uint8List? softMask = op.softMaskJpeg;
    if (op.jpeg && softMask != null && softMask.isNotEmpty) {
      ui.decodeImageFromList(op.bytes, (ui.Image color) {
        ui.decodeImageFromList(softMask, (ui.Image mask) {
          _composeJpegSoftMask(color, mask, onReady);
        });
      });
      return;
    }
    if (op.jpeg || _isPng(op.bytes)) {
      ui.decodeImageFromList(op.bytes, onReady);
      return;
    }
    final int pw = op.pixelWidth;
    final int ph = op.pixelHeight;
    if (pw < 1 || ph < 1) {
      return;
    }
    if (op.hasAlpha && op.bytes.length >= pw * ph * 4) {
      ui.decodeImageFromPixels(
        Uint8List.fromList(op.bytes.sublist(0, pw * ph * 4)),
        pw,
        ph,
        ui.PixelFormat.rgba8888,
        onReady,
      );
      return;
    }
    if (op.bytes.length < pw * ph * 3) {
      return;
    }
    final Uint8List rgba = Uint8List(pw * ph * 4);
    var o = 0;
    for (int i = 0; i < pw * ph; i++) {
      rgba[o++] = op.bytes[i * 3];
      rgba[o++] = op.bytes[i * 3 + 1];
      rgba[o++] = op.bytes[i * 3 + 2];
      rgba[o++] = 255;
    }
    ui.decodeImageFromPixels(rgba, pw, ph, ui.PixelFormat.rgba8888, onReady);
  }

  /// JPEG color + DeviceGray `/SMask` JPEG → RGBA (ISO soft mask).
  static void _composeJpegSoftMask(
    ui.Image color,
    ui.Image mask,
    void Function(ui.Image image) onReady,
  ) {
    color.toByteData(format: ui.ImageByteFormat.rawRgba).then((
      ByteData? colorData,
    ) {
      mask.toByteData(format: ui.ImageByteFormat.rawRgba).then((
        ByteData? maskData,
      ) {
        if (colorData == null || maskData == null) {
          mask.dispose();
          onReady(color);
          return;
        }
        final int w = color.width;
        final int h = color.height;
        final int mw = mask.width;
        final int mh = mask.height;
        final Uint8List rgb = colorData.buffer.asUint8List();
        final Uint8List gray = maskData.buffer.asUint8List();
        final Uint8List out = Uint8List(w * h * 4);
        for (int y = 0; y < h; y++) {
          final int my = mh == h ? y : (y * mh ~/ h);
          for (int x = 0; x < w; x++) {
            final int mx = mw == w ? x : (x * mw ~/ w);
            final int i = (y * w + x) * 4;
            final int mi = (my * mw + mx) * 4;
            out[i] = rgb[i];
            out[i + 1] = rgb[i + 1];
            out[i + 2] = rgb[i + 2];
            // DeviceGray SMask: luminance → alpha (R channel after decode).
            out[i + 3] = gray[mi];
          }
        }
        color.dispose();
        mask.dispose();
        ui.decodeImageFromPixels(out, w, h, ui.PixelFormat.rgba8888, onReady);
      });
    });
  }

  static bool _isPng(Uint8List bytes) {
    return bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
  }
}
