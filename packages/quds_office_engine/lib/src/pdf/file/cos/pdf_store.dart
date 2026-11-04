import 'dart:typed_data';

import '../crypto/pdf_security.dart';
import '../decode/pdf_filters.dart';
import 'pdf_cos.dart';
import 'pdf_cos_reader.dart';
import 'pdf_open_error.dart';
import 'pdf_xref.dart';

/// Resolved COS graph for one [PdfFile].
class PdfCosStore {
  /// PdfCosStore API.
  PdfCosStore({
    required this.bytes,
    required this.xref,
    required this.reader,
    this.security,
  });

  /// bytes API.
  final Uint8List bytes;

  /// xref API.
  final PdfXrefTable xref;

  /// reader API.
  final PdfCosReader reader;

  /// security API.
  final PdfSecurity? security;

  final Map<PdfCosRef, PdfCos> _cache = <PdfCosRef, PdfCos>{};
  final Map<int, List<PdfCos>> _objStm = <int, List<PdfCos>>{};

  /// deref API.
  PdfCos? deref(PdfCos? value) {
    var current = value;
    var hops = 0;
    while (current is PdfCosRef && hops < 32) {
      current = get(current);
      hops++;
    }
    return current;
  }

  /// get API.
  PdfCos? get(PdfCosRef ref) {
    final PdfCos? hit = _cache[ref];
    if (hit != null) {
      return hit;
    }
    final PdfXrefEntry? entry = xref.entries[ref.id];
    if (entry == null || !entry.inUse) {
      return null;
    }
    if (entry.objectStreamId != null) {
      final List<PdfCos> packed = _objectStream(entry.objectStreamId!);
      final int index = entry.objectStreamIndex ?? 0;
      if (index < 0 || index >= packed.length) {
        return null;
      }
      final PdfCos obj = packed[index];
      _cache[ref] = obj;
      return obj;
    }
    if (entry.offset <= 0 || entry.offset >= bytes.length) {
      return null;
    }
    final PdfCos raw = reader.parseObjectAt(entry.offset);
    final PdfCos unlocked = _unlock(raw, ref);
    _cache[ref] = unlocked;
    return unlocked;
  }

  PdfCos _unlock(PdfCos raw, PdfCosRef ref) {
    final PdfSecurity? sec = security;
    if (sec == null) {
      return raw;
    }
    if (raw is PdfCosStream) {
      final Uint8List clear = sec.decrypt(raw.raw, ref.id, ref.gen);
      return PdfCosStream(raw.dict, clear);
    }
    if (raw is PdfCosString) {
      return PdfCosString(sec.decrypt(raw.bytes, ref.id, ref.gen), hex: raw.hex);
    }
    if (raw is PdfCosDict) {
      return _unlockDict(raw, ref);
    }
    if (raw is PdfCosArray) {
      return PdfCosArray(<PdfCos>[
        for (final PdfCos item in raw.items) _unlock(item, ref),
      ]);
    }
    return raw;
  }

  PdfCosDict _unlockDict(PdfCosDict dict, PdfCosRef ref) {
    final PdfCosDict out = PdfCosDict();
    dict.values.forEach((String key, PdfCos value) {
      out[key] = value is PdfCosString || value is PdfCosArray
          ? _unlock(value, ref)
          : value;
    });
    return out;
  }

  /// Stream bytes with filters applied (and encryption already cleared).
  Uint8List? streamBytes(PdfCos? value) {
    final PdfCos? obj = deref(value);
    if (obj is! PdfCosStream) {
      return null;
    }
    if (obj.raw.length > 64 * 1024 * 1024) {
      throw const PdfOpenException(PdfOpenError.limit, 'Stream too large');
    }
    final PdfFilterResult decoded = PdfFilters.decodeResult(obj.raw, obj.dict);
    return decoded.bytes;
  }

  /// streamResult API.
  PdfFilterResult streamResult(PdfCos? value) {
    final PdfCos? obj = deref(value);
    if (obj is! PdfCosStream) {
      return const PdfFilterResult.unsupported('NotAStream');
    }
    return PdfFilters.decodeResult(obj.raw, obj.dict);
  }

  /// asDict API.
  PdfCosDict? asDict(PdfCos? value) {
    final PdfCos? obj = deref(value);
    return obj is PdfCosDict
        ? obj
        : obj is PdfCosStream
        ? obj.dict
        : null;
  }

  /// asArray API.
  PdfCosArray? asArray(PdfCos? value) {
    final PdfCos? obj = deref(value);
    return obj is PdfCosArray ? obj : null;
  }

  List<PdfCos> _objectStream(int id) {
    final List<PdfCos>? cached = _objStm[id];
    if (cached != null) {
      return cached;
    }
    final PdfCos? raw = get(PdfCosRef(id));
    if (raw is! PdfCosStream) {
      return const <PdfCos>[];
    }
    final int n = pdfCosInt(raw.dict['N']) ?? 0;
    final int first = pdfCosInt(raw.dict['First']) ?? 0;
    final Uint8List data = PdfFilters.decode(raw.raw, raw.dict);
    final PdfCosReader inner = PdfCosReader(data);
    final List<int> offsets = <int>[];
    for (int i = 0; i < n; i++) {
      inner.skipWsAndComments();
      _skipInt(inner);
      inner.skipWsAndComments();
      offsets.add(_readInt(inner) + first);
    }
    final List<PdfCos> objects = <PdfCos>[];
    for (final int off in offsets) {
      inner.offset = off;
      objects.add(inner.parseValue());
    }
    _objStm[id] = objects;
    return objects;
  }

  static void _skipInt(PdfCosReader reader) {
    reader.skipWsAndComments();
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
  }

  static int _readInt(PdfCosReader reader) {
    final int start = reader.offset;
    _skipInt(reader);
    return int.tryParse(
          String.fromCharCodes(reader.bytes.sublist(start, reader.offset)),
        ) ??
        0;
  }
}
