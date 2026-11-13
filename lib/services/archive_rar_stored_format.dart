// Independently implemented from https://www.rarlab.com/technote.htm.
// This file handles documented RAR5 container fields only. It contains no
// RAR compression algorithm or code derived from UnRAR / 7-Zip's RAR engine.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

import 'archive_types.dart';

const rarStoredSignature = <int>[0x52, 0x61, 0x72, 0x21, 0x1a, 7, 1, 0];
const rarStoredMaxHeaderBytes = 0x1fffff;
const rarStoredMaxMetadataBytes = 16 * 1024 * 1024;
const rarStoredMaxEntries = 200000;
const rarStoredChunkBytes = 256 * 1024;
const rarStoredMaxExact = 0x1fffffffffffff;
final _fileTimeEpoch = BigInt.from(116444736000000000);
final _maxUint64 = (BigInt.one << 64) - BigInt.one;

Never rarStoredError(String message) => throw ArchiveViewException(message);

/// Bounds-checked reader for an already bounded RAR5 header. Large member
/// bodies are positional streams and never pass through this class.
class RarStoredCursor {
  RarStoredCursor(this.bytes, {this.offset = 0, int? end})
    : end = end ?? bytes.length;

  final Uint8List bytes;
  int offset;
  final int end;

  int get remaining => end - offset;

  void require(int count) {
    if (count < 0 || offset < 0 || count > end - offset) {
      rarStoredError('Truncated RAR5 header.');
    }
  }

  int byte() {
    require(1);
    return bytes[offset++];
  }

  int uint32() {
    require(4);
    final value = ByteData.sublistView(bytes).getUint32(offset, Endian.little);
    offset += 4;
    return value;
  }

  BigInt uint64() {
    final low = uint32();
    final high = uint32();
    return BigInt.from(low) | (BigInt.from(high) << 32);
  }

  int vint({int maxBytes = 10, int maxValue = rarStoredMaxExact}) {
    var value = BigInt.zero;
    for (var index = 0; index < maxBytes; index++) {
      final next = byte();
      value |= BigInt.from(next & 0x7f) << (index * 7);
      if (value > BigInt.from(maxValue)) {
        rarStoredError('RAR5 integer exceeds its supported bound.');
      }
      if (next & 0x80 == 0) return value.toInt();
    }
    rarStoredError('RAR5 variable-length integer is too long.');
  }

  Uint8List take(int count) {
    require(count);
    final result = Uint8List.sublistView(bytes, offset, offset + count);
    offset += count;
    return result;
  }

  void finish() {
    if (offset != end) {
      rarStoredError('Unrecognized trailing RAR5 header data.');
    }
  }
}

Uint8List rarStoredVint(int value) {
  if (value < 0 || value > rarStoredMaxExact) {
    rarStoredError('RAR5 integer exceeds its supported bound.');
  }
  final result = <int>[];
  do {
    final low = value % 128;
    value ~/= 128;
    result.add(low | (value == 0 ? 0 : 0x80));
  } while (value != 0);
  return Uint8List.fromList(result);
}

Uint8List rarStoredUint32(int value) {
  if (value < 0 || value > 0xffffffff) {
    rarStoredError('RAR5 uint32 exceeds its supported bound.');
  }
  return Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
}

Uint8List rarStoredUint64(BigInt value) {
  if (value < BigInt.zero || value > _maxUint64) {
    rarStoredError('RAR5 FILETIME exceeds its supported bound.');
  }
  final result = Uint8List(8);
  for (var index = 0; index < 8; index++) {
    result[index] = (value & BigInt.from(255)).toInt();
    value >>= 8;
  }
  return result;
}

/// Builds a checksum-protected header. [dataSize] is absent for main/end
/// records, and is present even for an empty file when set to zero.
Uint8List rarStoredHeader(
  int type,
  Uint8List fields, {
  Uint8List? extra,
  int? dataSize,
}) {
  final body = BytesBuilder(copy: false)
    ..add(rarStoredVint(type))
    ..add(rarStoredVint((extra == null ? 0 : 1) | (dataSize == null ? 0 : 2)));
  if (extra != null) body.add(rarStoredVint(extra.length));
  if (dataSize != null) body.add(rarStoredVint(dataSize));
  body.add(fields);
  if (extra != null) body.add(extra);
  if (body.length > rarStoredMaxHeaderBytes) {
    rarStoredError('RAR5 header exceeds its 2 MiB bound.');
  }
  final checked = BytesBuilder(copy: false)
    ..add(rarStoredVint(body.length))
    ..add(body.takeBytes());
  final bytes = checked.takeBytes();
  return (BytesBuilder(copy: false)
        ..add(rarStoredUint32(getCrc32(bytes)))
        ..add(bytes))
      .takeBytes();
}

Uint8List rarStoredExtra(int type, Uint8List data) {
  final body =
      (BytesBuilder(copy: false)
            ..add(rarStoredVint(type))
            ..add(data))
          .takeBytes();
  return (BytesBuilder(copy: false)
        ..add(rarStoredVint(body.length))
        ..add(body))
      .takeBytes();
}

/// Reject paths that the application's folder model cannot represent exactly.
/// A single trailing slash on a directory is retained separately by the reader.
void validateRarStoredPath(String path) {
  final parts = path.split('/');
  if (path.isEmpty ||
      path.contains('\\') ||
      path.contains(':') ||
      path.contains('\ufffe') ||
      path.contains('\uffff') ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
      parts.length > 200 ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
      utf8.encode(path).length > 4096) {
    rarStoredError('RAR5 member path is not supported: $path');
  }
}

/// Exact representation of the documented high-precision time extra. Raw
/// FILETIME ticks and Unix nanoseconds survive rewrites even when the viewer's
/// DateTime can expose only microseconds. No unknown extra field is accepted.
class RarStoredTimes {
  RarStoredTimes(this.flags, Map<String, BigInt> values, Map<String, int> nanos)
    : values = Map.unmodifiable(values),
      nanos = Map.unmodifiable(nanos) {
    _validate();
  }

  final int flags;
  final Map<String, BigInt> values;
  final Map<String, int> nanos;
  static const fields = <String, int>{'mtime': 2, 'ctime': 4, 'atime': 8};
  bool get unix => flags & 1 != 0;

  void _validate() {
    if (flags < 0 || flags & ~0x1f != 0 || !unix && flags & 0x10 != 0) {
      rarStoredError('Unsupported RAR5 time flags.');
    }
    for (final item in fields.entries) {
      final present = flags & item.value != 0;
      final value = values[item.key];
      final subsecond = nanos[item.key];
      if (present != (value != null) ||
          value != null &&
              (value < BigInt.zero ||
                  value > (unix ? BigInt.from(0xffffffff) : _maxUint64)) ||
          (present && unix && flags & 0x10 != 0) != (subsecond != null) ||
          subsecond != null && (subsecond < 0 || subsecond >= 1000000000)) {
        rarStoredError('Invalid RAR5 high-precision timestamp.');
      }
    }
    if (values.keys.any((key) => !fields.containsKey(key)) ||
        nanos.keys.any((key) => !fields.containsKey(key))) {
      rarStoredError('Unknown RAR5 timestamp field.');
    }
  }

  factory RarStoredTimes.decode(Uint8List bytes) {
    final input = RarStoredCursor(bytes);
    final flags = input.vint();
    if (flags & ~0x1f != 0) rarStoredError('Unknown RAR5 time flags.');
    final unix = flags & 1 != 0;
    final values = <String, BigInt>{};
    final nanos = <String, int>{};
    for (final item in fields.entries) {
      if (flags & item.value != 0) {
        values[item.key] = unix ? BigInt.from(input.uint32()) : input.uint64();
      }
    }
    if (unix && flags & 0x10 != 0) {
      for (final item in fields.entries) {
        if (flags & item.value != 0) nanos[item.key] = input.uint32();
      }
    }
    input.finish();
    return RarStoredTimes(flags, values, nanos);
  }

  factory RarStoredTimes.fromAttributes(Object value) {
    if (value is! Map ||
        value['flags'] is! int ||
        value.keys.any(
          (key) => !const {
            'flags',
            'mtime',
            'ctime',
            'atime',
            'mtimeNs',
            'ctimeNs',
            'atimeNs',
          }.contains(key),
        )) {
      rarStoredError('Invalid preserved RAR5 timestamp metadata.');
    }
    final values = <String, BigInt>{};
    final nanos = <String, int>{};
    for (final name in fields.keys) {
      final raw = value[name];
      if (raw != null) {
        if (raw is! String ||
            raw.length > 20 ||
            !RegExp(r'^\d+$').hasMatch(raw)) {
          rarStoredError('Invalid preserved RAR5 timestamp value.');
        }
        values[name] = BigInt.parse(raw);
      }
      final subsecond = value['${name}Ns'];
      if (subsecond != null) {
        if (subsecond is! int) rarStoredError('Invalid RAR5 nanoseconds.');
        nanos[name] = subsecond;
      }
    }
    return RarStoredTimes(value['flags'] as int, values, nanos);
  }

  Map<String, Object?> toAttributes() => Map.unmodifiable({
    'flags': flags,
    for (final item in values.entries) item.key: item.value.toString(),
    for (final item in nanos.entries) '${item.key}Ns': item.value,
  });

  Uint8List encode() {
    final result = BytesBuilder(copy: false)..add(rarStoredVint(flags));
    for (final name in fields.keys) {
      final value = values[name];
      if (value != null) {
        result.add(
          unix ? rarStoredUint32(value.toInt()) : rarStoredUint64(value),
        );
      }
    }
    for (final name in fields.keys) {
      final value = nanos[name];
      if (value != null) result.add(rarStoredUint32(value));
    }
    return result.takeBytes();
  }

  DateTime? get modified {
    final raw = values['mtime'];
    if (raw == null) return null;
    BigInt micros;
    if (unix) {
      micros =
          raw * BigInt.from(1000000) +
          BigInt.from((nanos['mtime'] ?? 0) ~/ 1000);
    } else {
      final ticks = raw - _fileTimeEpoch;
      micros = ticks ~/ BigInt.from(10);
      if (ticks.isNegative && ticks.remainder(BigInt.from(10)) != BigInt.zero) {
        micros -= BigInt.one;
      }
    }
    final limit = BigInt.parse('8640000000000000000');
    if (micros < -limit || micros > limit) {
      rarStoredError('RAR5 timestamp is outside the DateTime range.');
    }
    return DateTime.fromMicrosecondsSinceEpoch(micros.toInt(), isUtc: true);
  }

  RarStoredTimes withModified(DateTime next) {
    final micros = BigInt.from(next.microsecondsSinceEpoch);
    final seconds = micros ~/ BigInt.from(1000000);
    if (unix && micros >= BigInt.zero && seconds <= BigInt.from(0xffffffff)) {
      final remainder = (micros % BigInt.from(1000000)).toInt() * 1000;
      final nextFlags = flags | 2 | (remainder == 0 ? 0 : 0x10);
      final nextNanos = <String, int>{...nanos};
      if (nextFlags & 0x10 != 0) {
        for (final name in values.keys) {
          nextNanos.putIfAbsent(name, () => 0);
        }
        nextNanos['mtime'] = remainder;
      }
      return RarStoredTimes(nextFlags, {
        ...values,
        'mtime': seconds,
      }, nextNanos);
    }
    final nextValues = <String, BigInt>{};
    for (final item in values.entries) {
      if (item.key == 'mtime') continue;
      final subsecond = nanos[item.key] ?? 0;
      if (unix && subsecond % 100 != 0) {
        rarStoredError('Changing this time would lose preserved nanoseconds.');
      }
      nextValues[item.key] = unix
          ? item.value * BigInt.from(10000000) +
                BigInt.from(subsecond ~/ 100) +
                _fileTimeEpoch
          : item.value;
    }
    nextValues['mtime'] = micros * BigInt.from(10) + _fileTimeEpoch;
    return RarStoredTimes((flags & ~0x11) | 2, nextValues, const {});
  }
}
