import 'dart:convert';
import 'dart:typed_data';

import 'pdf_cos.dart';

/// Serializes COS values to ISO 32000 syntax (ASCII-safe objects).
abstract final class PdfCosWrite {
  /// Encodes [value] as PDF tokens (no `obj` wrapper).
  static Uint8List encode(PdfCos value) {
    final BytesBuilder out = BytesBuilder();
    _write(out, value);
    return out.takeBytes();
  }

  /// Encodes a dictionary as `<<...>>`.
  static String encodeDict(PdfCosDict dict) => utf8.decode(encode(dict));

  static void _write(BytesBuilder out, PdfCos value) {
    switch (value) {
      case PdfCosNull():
        out.add(ascii('null'));
      case PdfCosBool(:final bool value):
        out.add(ascii(value ? 'true' : 'false'));
      case PdfCosInt(:final int value):
        out.add(ascii('$value'));
      case PdfCosReal(:final double value):
        out.add(ascii(_num(value)));
      case PdfCosName(:final String value):
        out.add(ascii('/$value'));
      case PdfCosString(:final Uint8List bytes):
        out.add(ascii('('));
        out.add(ascii(_escapeLiteral(String.fromCharCodes(bytes))));
        out.add(ascii(')'));
      case PdfCosArray(:final List<PdfCos> items):
        out.add(ascii('['));
        for (int i = 0; i < items.length; i++) {
          if (i > 0) {
            out.add(ascii(' '));
          }
          _write(out, items[i]);
        }
        out.add(ascii(']'));
      case PdfCosDict(:final Map<String, PdfCos> values):
        out.add(ascii('<<'));
        values.forEach((String key, PdfCos item) {
          out.add(ascii('/$key '));
          _write(out, item);
        });
        out.add(ascii('>>'));
      case PdfCosRef(:final int id, :final int gen):
        out.add(ascii('$id $gen R'));
      case PdfCosStream(:final PdfCosDict dict, :final Uint8List raw):
        final PdfCosDict copy = PdfCosDict(Map<String, PdfCos>.of(dict.values));
        copy['Length'] = PdfCosInt(raw.length);
        _write(out, copy);
        out.add(ascii('stream\n'));
        out.add(raw);
        out.add(ascii('\nendstream'));
    }
  }

  static String _escapeLiteral(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }

  static String _num(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static List<int> ascii(String text) => utf8.encode(text);
}
