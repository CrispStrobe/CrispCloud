import 'dart:convert';
import 'dart:typed_data';

/// Adds explicit UTC member modification seconds to the bounded ZIP emitted by
/// the pinned writer. Compressed/encrypted payloads and authentication bytes
/// are copied unchanged. Every local offset and central/ZIP64 footer is rebuilt.
/// This is a metadata finalizer for our writer output, never an input decoder.
Uint8List preserveArchiveZipTimes(
  Uint8List bytes,
  Map<String, DateTime?> times, {
  int limit = 256 * 1024 * 1024,
}) {
  Never invalid() =>
      throw StateError('The packed ZIP metadata layout cannot be verified.');
  if (bytes.length < 22 || bytes.length > limit || times.length > 200000) {
    invalid();
  }
  final input = ByteData.sublistView(bytes);
  int u16(int offset) => input.getUint16(offset, Endian.little);
  int u32(int offset) => input.getUint32(offset, Endian.little);
  int u64(int offset) => input.getUint64(offset, Endian.little);
  final end = bytes.length - 22;
  if (u32(end) != 0x06054b50 ||
      u16(end + 20) != 0 ||
      u16(end + 4) != 0 ||
      u16(end + 6) != 0) {
    invalid();
  }
  var count = u16(end + 10),
      cdBytes = u32(end + 12),
      cdStart = u32(end + 16),
      footerStart = end;
  final zip64 =
      (end >= 76 && u32(end - 20) == 0x07064b50) ||
      cdBytes == 0xffffffff ||
      cdStart == 0xffffffff;
  if (zip64) {
    if (end < 76 ||
        u32(end - 20) != 0x07064b50 ||
        u32(end - 16) != 0 ||
        u32(end - 4) != 1) {
      invalid();
    }
    final offset = u64(end - 12);
    if (offset != end - 76 ||
        u32(offset) != 0x06064b50 ||
        u64(offset + 4) != 44 ||
        u32(offset + 16) != 0 ||
        u32(offset + 20) != 0) {
      invalid();
    }
    if (u64(offset + 24) != u64(offset + 32)) invalid();
    count = u64(offset + 32);
    cdBytes = u64(offset + 40);
    cdStart = u64(offset + 48);
    footerStart = offset;
  } else if (u16(end + 8) != count) {
    invalid();
  }
  if (count != times.length ||
      count > 200000 ||
      cdStart < 0 ||
      cdBytes < 0 ||
      cdStart + cdBytes != footerStart) {
    invalid();
  }
  final records = <_ZipTimeRecord>[];
  final names = <String>{};
  var position = cdStart;
  for (var index = 0; index < count; index++) {
    if (position + 46 > footerStart || u32(position) != 0x02014b50) invalid();
    final nameLength = u16(position + 28),
        extraLength = u16(position + 30),
        commentLength = u16(position + 32);
    final next = position + 46 + nameLength + extraLength + commentLength;
    final local = u32(position + 42);
    if (next > footerStart ||
        u16(position + 34) != 0 ||
        local >= cdStart ||
        u32(position + 20) == 0xffffffff ||
        u32(position + 24) == 0xffffffff) {
      invalid();
    }
    final nameBytes = Uint8List.sublistView(
      bytes,
      position + 46,
      position + 46 + nameLength,
    );
    final decoded = utf8.decode(nameBytes);
    final name = decoded.endsWith('/')
        ? decoded.substring(0, decoded.length - 1)
        : decoded;
    if (!names.add(name) || !times.containsKey(name)) invalid();
    final modified = times[name]?.toUtc();
    var timestamp = Uint8List(0);
    if (modified != null) {
      final micros = modified.microsecondsSinceEpoch;
      final seconds = micros ~/ 1000000;
      if (micros % 1000000 == 0 && seconds >= 0 && seconds <= 0x7fffffff) {
        timestamp = Uint8List(9);
        ByteData.sublistView(timestamp)
          ..setUint16(0, 0x5455, Endian.little)
          ..setUint16(2, 5, Endian.little)
          ..setUint8(4, 1)
          ..setUint32(5, seconds, Endian.little);
      } else if (micros % 1000000 != 0 ||
          modified.year < 1980 ||
          modified.year > 2107 ||
          modified.second.isOdd ||
          u16(position + 12) !=
              ((modified.hour << 11) |
                  (modified.minute << 5) |
                  (modified.second ~/ 2)) ||
          u16(position + 14) !=
              (((modified.year - 1980) << 9) |
                  (modified.month << 5) |
                  modified.day)) {
        throw StateError(
          'The ZIP writer cannot preserve this member timestamp: $name',
        );
      }
    }
    records.add(
      _ZipTimeRecord(
        position,
        next,
        local,
        nameLength,
        extraLength,
        nameBytes,
        timestamp,
      ),
    );
    position = next;
  }
  if (position != footerStart) invalid();
  final output = BytesBuilder(copy: false);
  void add(List<int> data) {
    if (output.length + data.length > limit) {
      throw StateError('Packed ZIP metadata exceeds the container limit.');
    }
    output.add(data);
  }

  void extra(int begin, int length) {
    final finish = begin + length;
    for (var at = begin; at < finish;) {
      if (at + 4 > finish ||
          at + 4 + u16(at + 2) > finish ||
          u16(at) == 0x5455) {
        invalid();
      }
      at += 4 + u16(at + 2);
    }
  }

  final ordered = records.toList()..sort((a, b) => a.local.compareTo(b.local));
  if (ordered.isNotEmpty && ordered.first.local != 0) invalid();
  for (var index = 0; index < ordered.length; index++) {
    final record = ordered[index];
    final next = index + 1 < ordered.length
        ? ordered[index + 1].local
        : cdStart;
    final local = record.local;
    if (local + 30 > next || u32(local) != 0x04034b50) invalid();
    if (u16(local + 10) != u16(record.start + 12) ||
        u16(local + 12) != u16(record.start + 14)) {
      invalid();
    }
    final nameLength = u16(local + 26), extraLength = u16(local + 28);
    final payload = local + 30 + nameLength + extraLength;
    if (payload > next ||
        nameLength != record.nameLength ||
        extraLength + record.timestamp.length > 0xffff ||
        utf8.decode(
              Uint8List.sublistView(bytes, local + 30, local + 30 + nameLength),
            ) !=
            utf8.decode(record.name)) {
      invalid();
    }
    extra(local + 30 + nameLength, extraLength);
    record.newLocal = output.length;
    final header = Uint8List.fromList(bytes.sublist(local, local + 30));
    ByteData.sublistView(header)
        .setUint16(28, extraLength + record.timestamp.length, Endian.little);
    add(header);
    add(Uint8List.sublistView(bytes, local + 30, payload));
    add(record.timestamp);
    add(Uint8List.sublistView(bytes, payload, next));
  }
  final newStart = output.length;
  for (final record in records) {
    if (record.extraLength + record.timestamp.length > 0xffff) invalid();
    extra(record.start + 46 + record.nameLength, record.extraLength);
    final header = Uint8List.fromList(
      bytes.sublist(record.start, record.start + 46),
    );
    ByteData.sublistView(header)
      ..setUint16(
        30,
        record.extraLength + record.timestamp.length,
        Endian.little,
      )
      ..setUint32(42, record.newLocal, Endian.little);
    final afterExtra =
        record.start + 46 + record.nameLength + record.extraLength;
    add(header);
    add(Uint8List.sublistView(bytes, record.start + 46, afterExtra));
    add(record.timestamp);
    add(Uint8List.sublistView(bytes, afterExtra, record.end));
  }
  final newSize = output.length - newStart;
  if (zip64 || count == 0xffff) {
    final newFooter = output.length;
    final footer = Uint8List(56);
    ByteData.sublistView(footer)
      ..setUint32(0, 0x06064b50, Endian.little)
      ..setUint64(4, 44, Endian.little)
      ..setUint16(12, 45, Endian.little)
      ..setUint16(14, 45, Endian.little)
      ..setUint64(24, count, Endian.little)
      ..setUint64(32, count, Endian.little)
      ..setUint64(40, newSize, Endian.little)
      ..setUint64(48, newStart, Endian.little);
    add(footer);
    final locator = Uint8List(20);
    ByteData.sublistView(locator)
      ..setUint32(0, 0x07064b50, Endian.little)
      ..setUint64(8, newFooter, Endian.little)
      ..setUint32(16, 1, Endian.little);
    add(locator);
  }
  final endRecord = Uint8List.fromList(bytes.sublist(end));
  ByteData.sublistView(endRecord)
    ..setUint32(12, newSize, Endian.little)
    ..setUint32(16, newStart, Endian.little);
  add(endRecord);
  return output.takeBytes();
}

class _ZipTimeRecord {
  _ZipTimeRecord(
    this.start,
    this.end,
    this.local,
    this.nameLength,
    this.extraLength,
    this.name,
    this.timestamp,
  );
  final int start, end, local, nameLength, extraLength;
  final Uint8List name, timestamp;
  int newLocal = 0;
}

/// The pinned reader treats UT seconds as unsigned. A negative signed Unix
/// time would otherwise be mistaken for a future date and rewritten incorrectly.
/// Inspect bounded local/central extras before granting write capability.
String? archiveZipTimestampPolicyIssue(Uint8List bytes) {
  const unsupported =
      'This ZIP timestamp metadata cannot be preserved by the current reader and writer.';
  if (bytes.length > 256 * 1024 * 1024) return unsupported;
  try {
    final input = ByteData.sublistView(bytes);
    int u16(int at) => input.getUint16(at, Endian.little);
    int u32(int at) => input.getUint32(at, Endian.little);
    int u64(int at) => input.getUint64(at, Endian.little);
    var end = -1;
    for (
      var at = bytes.length - 22;
      at >= (bytes.length - 65557).clamp(0, bytes.length);
      at--
    ) {
      if (u32(at) == 0x06054b50 && at + 22 + u16(at + 20) == bytes.length) {
        end = at;
        break;
      }
    }
    if (end < 0 || u16(end + 4) != 0 || u16(end + 6) != 0) return unsupported;
    var count = u16(end + 10), size = u32(end + 12), position = u32(end + 16);
    if ((end >= 76 && u32(end - 20) == 0x07064b50) ||
        size == 0xffffffff ||
        position == 0xffffffff) {
      if (end < 76 ||
          u32(end - 20) != 0x07064b50 ||
          u32(end - 16) != 0 ||
          u32(end - 4) != 1) {
        return unsupported;
      }
      final offset = u64(end - 12);
      if (offset < 0 ||
          offset + 56 > end - 20 ||
          u32(offset) != 0x06064b50 ||
          u32(offset + 16) != 0 ||
          u32(offset + 20) != 0) {
        return unsupported;
      }
      count = u64(offset + 32);
      size = u64(offset + 40);
      position = u64(offset + 48);
    }
    if (count < 0 ||
        count > 200000 ||
        position < 0 ||
        size < 0 ||
        position + size > end) {
      return unsupported;
    }
    final directoryStart = position;
    final limit = position + size;
    final localOffsets = <int>{};
    final localMetadata = <({int start, int end})>[];
    var localMetadataBytes = 0;
    int? timestamp(int begin, int length) {
      final finish = begin + length;
      int? result;
      for (var at = begin; at < finish;) {
        if (at + 4 > finish || at + 4 + u16(at + 2) > finish) {
          throw const FormatException('Invalid ZIP extra field.');
        }
        final id = u16(at), length = u16(at + 2);
        if (id == 0x5455) {
          if (length < 1) {
            throw const FormatException('Invalid ZIP timestamp flags.');
          }
          if ((bytes[at + 4] & 1) != 0) {
            if (length < 5 || result != null) {
              throw const FormatException('Invalid ZIP timestamp.');
            }
            result = u32(at + 5);
            if (result > 0x7fffffff) {
              throw const FormatException(
                'Signed ZIP time is unsupported by the reader.',
              );
            }
          }
        }
        at += 4 + length;
      }
      return result;
    }

    for (var index = 0; index < count; index++) {
      if (position + 46 > limit || u32(position) != 0x02014b50) {
        return unsupported;
      }
      final nameLength = u16(position + 28),
          extraLength = u16(position + 30),
          commentLength = u16(position + 32);
      final next = position + 46 + nameLength + extraLength + commentLength;
      if (next > limit) return unsupported;
      final extra = position + 46 + nameLength;
      final centralTime = timestamp(extra, extraLength);
      var local = u32(position + 42);
      if (local == 0xffffffff) {
        for (var at = extra; at < extra + extraLength;) {
          final length = u16(at + 2);
          if (u16(at) == 1) {
            final field =
                at +
                4 +
                (u32(position + 24) == 0xffffffff ? 8 : 0) +
                (u32(position + 20) == 0xffffffff ? 8 : 0);
            if (field + 8 > at + 4 + length) return unsupported;
            local = u64(field);
            break;
          }
          at += 4 + length;
        }
      }
      if (local < 0 ||
          local + 30 > directoryStart ||
          !localOffsets.add(local) ||
          u32(local) != 0x04034b50) {
        return unsupported;
      }
      final localNameLength = u16(local + 26), localLength = u16(local + 28);
      final localExtra = local + 30 + localNameLength;
      final localEnd = localExtra + localLength;
      if (localEnd > directoryStart || localNameLength != nameLength) {
        return unsupported;
      }
      // Central records must not amplify a tiny input into repeated scans of
      // shared/overlapping local metadata. Charge the entire region before
      // comparing names or parsing extras, then reject overlaps below.
      localMetadataBytes += localEnd - local;
      if (localMetadataBytes > bytes.length) return unsupported;
      for (var index = 0; index < nameLength; index++) {
        if (bytes[local + 30 + index] != bytes[position + 46 + index]) {
          return unsupported;
        }
      }
      final localTime = timestamp(localExtra, localLength);
      if (localTime != null && localTime != centralTime) return unsupported;
      localMetadata.add((start: local, end: localEnd));
      position = next;
    }
    localMetadata.sort((a, b) => a.start.compareTo(b.start));
    for (var index = 1; index < localMetadata.length; index++) {
      if (localMetadata[index - 1].end > localMetadata[index].start) {
        return unsupported;
      }
    }
    return position == limit ? null : unsupported;
  } on RangeError {
    return unsupported;
  } on FormatException {
    return unsupported;
  }
}
