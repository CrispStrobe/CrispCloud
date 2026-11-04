import 'dart:typed_data';

import '../decode/pdf_filters.dart';
import 'pdf_cos.dart';
import 'pdf_cos_reader.dart';
import 'pdf_open_error.dart';

/// One xref slot (ISO 32000-1 §7.5.4).
class PdfXrefEntry {
  /// PdfXrefEntry API.
  const PdfXrefEntry({
    required this.id,
    required this.offset,
    required this.gen,
    required this.inUse,
    this.objectStreamId,
    this.objectStreamIndex,
  });

  /// id API.
  final int id;

  /// File offset, or 0 when the object lives in an object stream.
  final int offset;

  /// gen API.
  final int gen;

  /// inUse API.
  final bool inUse;

  /// objectStreamId API.
  final int? objectStreamId;

  /// objectStreamIndex API.
  final int? objectStreamIndex;
}

/// Parsed cross-reference plus trailer dictionary.
class PdfXrefTable {
  /// PdfXrefTable API.
  PdfXrefTable({required this.entries, required this.trailer, required this.prev});

  /// Newest definition wins (incremental updates).
  final Map<int, PdfXrefEntry> entries;

  /// trailer API.
  final PdfCosDict trailer;

  /// Previous xref offset, if any.
  final int? prev;
}

/// Loads xref tables and streams, including incremental `/Prev` chains.
abstract final class PdfXref {
  /// parse API.
  static PdfXrefTable parse(Uint8List bytes, PdfCosReader reader) {
    final int start = reader.findLastStartXref();
    if (start < 0) {
      return repair(bytes, reader);
    }
    try {
      return _parseFrom(bytes, reader, start, <int>{});
    } on PdfOpenException {
      return repair(bytes, reader);
    }
  }

  static PdfXrefTable _parseFrom(
    Uint8List bytes,
    PdfCosReader reader,
    int offset,
    Set<int> seen,
  ) {
    if (!seen.add(offset) || offset < 0 || offset >= bytes.length) {
      throw const PdfOpenException(PdfOpenError.badXref, 'Cyclic xref');
    }
    reader.offset = offset;
    reader.skipWsAndComments();
    if (reader.offset + 4 <= bytes.length &&
        bytes[reader.offset] == 0x78 &&
        bytes[reader.offset + 1] == 0x72 &&
        bytes[reader.offset + 2] == 0x65 &&
        bytes[reader.offset + 3] == 0x66) {
      return _parseTable(bytes, reader, seen);
    }
    return _parseXrefStream(bytes, reader, offset, seen);
  }

  static PdfXrefTable _parseTable(
    Uint8List bytes,
    PdfCosReader reader,
    Set<int> seen,
  ) {
    reader.offset += 4; // xref
    final Map<int, PdfXrefEntry> entries = <int, PdfXrefEntry>{};
    while (true) {
      reader.skipWsAndComments();
      if (reader.offset + 7 <= bytes.length &&
          bytes[reader.offset] == 0x74 /* t */) {
        break;
      }
      final int first = _readInt(reader);
      reader.skipWsAndComments();
      final int count = _readInt(reader);
      for (int i = 0; i < count; i++) {
        reader.skipWsAndComments();
        final int off = _readInt(reader);
        reader.skipWsAndComments();
        final int gen = _readInt(reader);
        reader.skipWsAndComments();
        final int flag = reader.offset < bytes.length ? bytes[reader.offset] : 0;
        if (flag == 0x6E || flag == 0x66) {
          reader.offset++;
        }
        final int id = first + i;
        entries[id] = PdfXrefEntry(
          id: id,
          offset: off,
          gen: gen,
          inUse: flag == 0x6E,
        );
      }
    }
    reader.skipWsAndComments();
    if (!_consume(reader, bytes, 'trailer')) {
      throw const PdfOpenException(PdfOpenError.badXref, 'Missing trailer');
    }
    final PdfCos trailerVal = reader.parseValue();
    if (trailerVal is! PdfCosDict) {
      throw const PdfOpenException(PdfOpenError.badXref, 'Trailer is not a dict');
    }
    final int? prev = pdfCosInt(trailerVal['Prev']);
    if (prev != null) {
      final PdfXrefTable older = _parseFrom(bytes, reader, prev, seen);
      older.entries.addAll(entries);
      return PdfXrefTable(
        entries: older.entries,
        trailer: trailerVal,
        prev: prev,
      );
    }
    return PdfXrefTable(entries: entries, trailer: trailerVal, prev: prev);
  }

  static PdfXrefTable _parseXrefStream(
    Uint8List bytes,
    PdfCosReader reader,
    int offset,
    Set<int> seen,
  ) {
    final PdfCos obj = reader.parseObjectAt(offset);
    if (obj is! PdfCosStream) {
      throw const PdfOpenException(PdfOpenError.badXref, 'Expected xref stream');
    }
    final PdfCosDict dict = obj.dict;
    final Uint8List decoded = PdfFilters.decode(obj.raw, dict);
    final List<int> w = _w(dict['W']);
    final int size = pdfCosInt(dict['Size']) ?? 0;
    final List<(int, int)> index = _index(dict['Index'], size);
    final Map<int, PdfXrefEntry> entries = <int, PdfXrefEntry>{};
    var cursor = 0;
    for (final (int first, int count) in index) {
      for (int i = 0; i < count; i++) {
        final int type = _field(decoded, cursor, w[0], 1);
        cursor += w[0];
        final int f2 = _field(decoded, cursor, w[1], 0);
        cursor += w[1];
        final int f3 = _field(decoded, cursor, w[2], 0);
        cursor += w[2];
        final int id = first + i;
        switch (type) {
          case 0:
            entries[id] = PdfXrefEntry(
              id: id,
              offset: 0,
              gen: f3,
              inUse: false,
            );
          case 1:
            entries[id] = PdfXrefEntry(
              id: id,
              offset: f2,
              gen: f3,
              inUse: true,
            );
          case 2:
            entries[id] = PdfXrefEntry(
              id: id,
              offset: 0,
              gen: 0,
              inUse: true,
              objectStreamId: f2,
              objectStreamIndex: f3,
            );
          default:
            entries[id] = PdfXrefEntry(
              id: id,
              offset: 0,
              gen: 0,
              inUse: false,
            );
        }
      }
    }
    final int? prev = pdfCosInt(dict['Prev']);
    if (prev != null) {
      final PdfXrefTable older = _parseFrom(bytes, reader, prev, seen);
      older.entries.addAll(entries);
      return PdfXrefTable(entries: older.entries, trailer: dict, prev: prev);
    }
    return PdfXrefTable(entries: entries, trailer: dict, prev: prev);
  }

  /// Rebuilds xref by scanning `id gen obj` markers.
  static PdfXrefTable repair(Uint8List bytes, PdfCosReader reader) {
    final Map<int, PdfXrefEntry> entries = <int, PdfXrefEntry>{};
    final Uint8List needle = Uint8List.fromList(' obj'.codeUnits);
    for (int i = 0; i + needle.length < bytes.length; i++) {
      if (bytes[i] < 0x30 || bytes[i] > 0x39) {
        continue;
      }
      var j = i;
      while (j < bytes.length && bytes[j] >= 0x30 && bytes[j] <= 0x39) {
        j++;
      }
      if (j == i) {
        continue;
      }
      var k = j;
      while (k < bytes.length &&
          (bytes[k] == 0x20 || bytes[k] == 0x09 || bytes[k] == 0x0A)) {
        k++;
      }
      final int genStart = k;
      while (k < bytes.length && bytes[k] >= 0x30 && bytes[k] <= 0x39) {
        k++;
      }
      if (k == genStart || k + needle.length > bytes.length) {
        continue;
      }
      var ok = true;
      for (int n = 0; n < needle.length; n++) {
        if (bytes[k + n] != needle[n]) {
          ok = false;
          break;
        }
      }
      if (!ok) {
        continue;
      }
      final int id =
          int.tryParse(String.fromCharCodes(bytes.sublist(i, j))) ?? -1;
      final int gen =
          int.tryParse(String.fromCharCodes(bytes.sublist(genStart, k))) ?? 0;
      if (id >= 0) {
        entries[id] = PdfXrefEntry(id: id, offset: i, gen: gen, inUse: true);
      }
    }
    if (entries.isEmpty) {
      throw const PdfOpenException(PdfOpenError.badXref, 'Repair found no objects');
    }
    return PdfXrefTable(entries: entries, trailer: PdfCosDict(), prev: null);
  }

  static int _readInt(PdfCosReader reader) {
    reader.skipWsAndComments();
    final int start = reader.offset;
    if (reader.offset < reader.bytes.length &&
        (reader.bytes[reader.offset] == 0x2B ||
            reader.bytes[reader.offset] == 0x2D)) {
      reader.offset++;
    }
    while (reader.offset < reader.bytes.length &&
        reader.bytes[reader.offset] >= 0x30 &&
        reader.bytes[reader.offset] <= 0x39) {
      reader.offset++;
    }
    return int.tryParse(
          String.fromCharCodes(reader.bytes.sublist(start, reader.offset)),
        ) ??
        0;
  }

  static bool _consume(PdfCosReader reader, Uint8List bytes, String text) {
    reader.skipWsAndComments();
    if (reader.offset + text.length > bytes.length) {
      return false;
    }
    for (int i = 0; i < text.length; i++) {
      if (bytes[reader.offset + i] != text.codeUnitAt(i)) {
        return false;
      }
    }
    reader.offset += text.length;
    return true;
  }

  static List<int> _w(PdfCos? value) {
    if (value is PdfCosArray && value.items.length >= 3) {
      return <int>[
        pdfCosInt(value.items[0]) ?? 1,
        pdfCosInt(value.items[1]) ?? 4,
        pdfCosInt(value.items[2]) ?? 2,
      ];
    }
    return const <int>[1, 4, 2];
  }

  static List<(int, int)> _index(PdfCos? value, int size) {
    if (value is PdfCosArray) {
      final List<(int, int)> out = <(int, int)>[];
      for (int i = 0; i + 1 < value.items.length; i += 2) {
        out.add((
          pdfCosInt(value.items[i]) ?? 0,
          pdfCosInt(value.items[i + 1]) ?? 0,
        ));
      }
      return out;
    }
    return <(int, int)>[(0, size)];
  }

  static int _field(Uint8List data, int offset, int width, int fallback) {
    if (width <= 0) {
      return fallback;
    }
    var v = 0;
    for (int i = 0; i < width && offset + i < data.length; i++) {
      v = (v << 8) | data[offset + i];
    }
    return v;
  }
}
