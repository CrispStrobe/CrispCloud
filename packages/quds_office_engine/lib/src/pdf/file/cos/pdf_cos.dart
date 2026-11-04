import 'dart:convert';
import 'dart:typed_data';

/// Closed COS value union (ISO 32000-1 §7.3).
sealed class PdfCos {
  /// PdfCos API.
  const PdfCos();
}

/// Class PdfCosNull.
final class PdfCosNull extends PdfCos {
  /// PdfCosNull API.
  const PdfCosNull();
}

/// Class PdfCosBool.
final class PdfCosBool extends PdfCos {
  /// PdfCosBool API.
  const PdfCosBool(this.value);

  /// value API.
  final bool value;
}

/// Class PdfCosInt.
final class PdfCosInt extends PdfCos {
  /// PdfCosInt API.
  const PdfCosInt(this.value);

  /// value API.
  final int value;

  /// asDouble API.
  double get asDouble => value.toDouble();
}

/// Class PdfCosReal.
final class PdfCosReal extends PdfCos {
  /// PdfCosReal API.
  const PdfCosReal(this.value);

  /// value API.
  final double value;
}

/// Class PdfCosName.
final class PdfCosName extends PdfCos {
  /// PdfCosName API.
  const PdfCosName(this.value);

  /// Name without the leading `/`.
  final String value;
}

/// Literal or hexadecimal PDF string.
final class PdfCosString extends PdfCos {
  /// PdfCosString API.
  const PdfCosString(this.bytes, {this.hex = false});

  /// bytes API.
  final Uint8List bytes;

  /// hex API.
  final bool hex;

  /// Decodes PDFDocEncoding / UTF-16BE (`FE FF`) to Dart text.
  String get asText {
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return utf8.decode(
        utf8.encode(String.fromCharCodes(_utf16be(bytes.sublist(2)))),
        allowMalformed: true,
      );
    }
    return String.fromCharCodes(bytes);
  }

  static List<int> _utf16be(Uint8List data) {
    final List<int> out = <int>[];
    for (int i = 0; i + 1 < data.length; i += 2) {
      out.add((data[i] << 8) | data[i + 1]);
    }
    return out;
  }
}

/// Class PdfCosArray.
final class PdfCosArray extends PdfCos {
  /// PdfCosArray API.
  PdfCosArray([List<PdfCos>? items]) : items = items ?? <PdfCos>[];

  /// items API.
  final List<PdfCos> items;
}

/// Class PdfCosDict.
final class PdfCosDict extends PdfCos {
  /// PdfCosDict API.
  PdfCosDict([Map<String, PdfCos>? values])
    : values = values ?? <String, PdfCos>{};

  /// Keys are COS names without `/`.
  final Map<String, PdfCos> values;

  /// lookup API.
  PdfCos? operator [](String name) => values[name];

  /// write API.
  void operator []=(String name, PdfCos value) => values[name] = value;
}

/// Indirect reference `id gen R`.
final class PdfCosRef extends PdfCos {
  /// PdfCosRef API.
  const PdfCosRef(this.id, [this.gen = 0]);

  /// id API.
  final int id;

  /// gen API.
  final int gen;

  @override
  bool operator ==(Object other) =>
      other is PdfCosRef && other.id == id && other.gen == gen;

  @override
  int get hashCode => Object.hash(id, gen);
}

/// Stream object: dictionary plus undecoded bytes.
final class PdfCosStream extends PdfCos {
  /// PdfCosStream API.
  PdfCosStream(this.dict, this.raw);

  /// dict API.
  final PdfCosDict dict;

  /// Raw bytes after `stream` / before `endstream` (possibly still filtered).
  final Uint8List raw;
}

/// Numeric helper for mixed int/real COS.
double? pdfCosNumber(PdfCos? value) {
  return switch (value) {
    PdfCosInt(:final int value) => value.toDouble(),
    PdfCosReal(:final double value) => value,
    _ => null,
  };
}

/// Integer helper.
int? pdfCosInt(PdfCos? value) {
  return switch (value) {
    PdfCosInt(:final int value) => value,
    PdfCosReal(:final double value) => value.round(),
    _ => null,
  };
}

/// Name helper.
String? pdfCosName(PdfCos? value) {
  return value is PdfCosName ? value.value : null;
}

/// Literal text helper.
String? pdfCosText(PdfCos? value) {
  return value is PdfCosString ? value.asText : null;
}

/// Rectangle `[llx lly urx ury]`.
({double llx, double lly, double urx, double ury})? pdfCosRect(PdfCos? value) {
  if (value is! PdfCosArray || value.items.length < 4) {
    return null;
  }
  final double? a = pdfCosNumber(value.items[0]);
  final double? b = pdfCosNumber(value.items[1]);
  final double? c = pdfCosNumber(value.items[2]);
  final double? d = pdfCosNumber(value.items[3]);
  if (a == null || b == null || c == null || d == null) {
    return null;
  }
  return (llx: a, lly: b, urx: c, ury: d);
}
