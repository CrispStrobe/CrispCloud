// SPDX-License-Identifier: MPL-2.0

import 'dart:collection';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'legacy_word_media_model.dart';

part 'legacy_word_metafile_render.dart';

/// Limits apply before inflation or allocation from a stored record count.
const legacyWordMetafileByteLimit = 16 * 1024 * 1024;
const legacyWordMetafileRecordLimit = 50000;
const legacyWordMetafileObjectLimit = 4096;

/// Extracted OfficeArt file data, separate from the original BLIP evidence.
class DecodedOfficeArtMetafile {
  const DecodedOfficeArtMetafile({
    required this.bytes,
    required this.info,
    required this.dataOffset,
    required this.encodedLength,
  });
  final Uint8List bytes;
  final LegacyWordMetafileInfo info;
  final int dataOffset, encodedLength;
}

/// MS-ODRAW 2.2.24/25/31. [data] excludes the OfficeArt record header.
/// The returned source extent is the encoded payload, not a fictitious extent
/// of decompressed bytes in the original compound stream.
DecodedOfficeArtMetafile decodeOfficeArtMetafile(
  Uint8List data, {
  required LegacyWordImageFormat format,
  required bool twoUids,
  int maxDecodedBytes = legacyWordMetafileByteLimit,
}) {
  final input = _MetaBytes(data);
  final start = twoUids ? 32 : 16;
  input.require(start, 34);
  final decodedLength = input.u32(start);
  final bounds = LegacyWordVectorBounds(
    input.i32(start + 4),
    input.i32(start + 8),
    input.i32(start + 12),
    input.i32(start + 16),
  );
  final width = input.i32(start + 20), height = input.i32(start + 24);
  final savedLength = input.u32(start + 28);
  final compression = input.u8(start + 32), filter = input.u8(start + 33);
  final offset = start + 34;
  if (decodedLength == 0 ||
      decodedLength > legacyWordMetafileByteLimit ||
      decodedLength > maxDecodedBytes ||
      savedLength != data.length - offset ||
      filter != 0xfe ||
      (compression != 0 && compression != 0xfe)) {
    throw const FormatException('Invalid or oversized OfficeArt metafile.');
  }
  final encoded = Uint8List.sublistView(data, offset);
  final Uint8List decoded;
  if (compression == 0xfe) {
    if (savedLength != decodedLength) {
      throw const FormatException('Inconsistent OfficeArt metafile length.');
    }
    decoded = encoded;
  } else {
    decoded = _inflateMetafile(encoded, decodedLength);
  }
  final info = parseLegacyWordMetafile(
    decoded,
    format: format,
    bounds: bounds,
    widthEmu: width,
    heightEmu: height,
    maxPreviewCharacters: (maxDecodedBytes - decodedLength).clamp(
      0,
      8 * 1024 * 1024,
    ),
  );
  return DecodedOfficeArtMetafile(
    bytes: decoded,
    info: info,
    dataOffset: offset,
    encodedLength: savedLength,
  );
}

Uint8List _inflateMetafile(Uint8List encoded, int expected) {
  if (encoded.length < 6 ||
      (encoded[0] & 15) != 8 ||
      encoded[0] >> 4 > 7 ||
      ((encoded[0] << 8) + encoded[1]) % 31 != 0 ||
      (encoded[1] & 0x20) != 0) {
    throw const FormatException('Invalid OfficeArt zlib header.');
  }
  // The high-level zlib decoder allocates its own complete inflated buffer.
  // Passing an OutputMemoryStream subclass directly to Inflate keeps every
  // write/back-reference inside the declared capacity on both VM and web.
  final input = InputMemoryStream(
    Uint8List.sublistView(encoded, 2, encoded.length - 4),
  );
  final output = _ExactMetafileOutput(expected);
  try {
    final inflater = Inflate.stream(input, output: output, throwOnError: true);
    if (!inflater.isFinished || !input.isEOS || output.length != expected) {
      throw const FormatException('Truncated or trailing OfficeArt deflate.');
    }
    final bytes = output.getBytes();
    final checksum = ByteData.sublistView(
      encoded,
    ).getUint32(encoded.length - 4, Endian.big);
    if (getAdler32(bytes) != checksum) {
      throw const FormatException('Invalid OfficeArt metafile checksum.');
    }
    return bytes;
  } on ArchiveException {
    throw const FormatException('Invalid OfficeArt metafile compression.');
  } on RangeError {
    throw const FormatException('Truncated OfficeArt metafile compression.');
  }
}

class _ExactMetafileOutput extends OutputMemoryStream {
  _ExactMetafileOutput(this.limit) : super(size: limit);
  final int limit;
  void _check(int count) {
    if (count < 0 || count > limit - length) {
      throw const FormatException(
        'OfficeArt metafile exceeds its output limit.',
      );
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    if (distance <= 0 || distance > length) {
      throw const FormatException('Invalid metafile deflate back-reference.');
    }
    super.writeBackReference(distance, count);
  }

  @override
  void reserve(int total) {
    if (total > limit) {
      throw const FormatException(
        'OfficeArt metafile exceeds its output limit.',
      );
    }
    super.reserve(total);
  }
}

/// Validates a raw EMF/WMF record stream without calling GDI or native code.
/// Unsupported GDI operations are retained. Escape records disable native
/// embedding as well, so original escape payloads remain inert evidence.
LegacyWordMetafileInfo parseLegacyWordMetafile(
  Uint8List bytes, {
  required LegacyWordImageFormat format,
  LegacyWordVectorBounds? bounds,
  int? widthEmu,
  int? heightEmu,
  int maxPreviewCharacters = 8 * 1024 * 1024,
}) {
  if (bytes.length > legacyWordMetafileByteLimit) {
    throw const FormatException('Metafile exceeds its byte limit.');
  }
  final input = _MetaBytes(bytes);
  final scan = switch (format) {
    LegacyWordImageFormat.emf => _scanEmf(input),
    LegacyWordImageFormat.wmf => _scanWmf(input, bounds),
    _ => throw ArgumentError.value(format, 'format', 'Expected EMF or WMF'),
  };
  if (maxPreviewCharacters < 0 || maxPreviewCharacters > 8 * 1024 * 1024) {
    throw ArgumentError.value(maxPreviewCharacters, 'maxPreviewCharacters');
  }
  final selectedBounds = bounds ?? scan.bounds;
  final preview =
      scan.boundsKnown && selectedBounds.width > 0 && selectedBounds.height > 0
      ? _MetafileRenderer(
          input,
          scan,
          format,
          selectedBounds,
          maxPreviewCharacters,
        ).render()
      : const _MetafilePreview(null, []);
  return LegacyWordMetafileInfo(
    bounds: selectedBounds,
    recordCount: scan.records.length,
    nativeEmbeddingAllowed: scan.nativeEmbeddingAllowed,
    widthEmu: widthEmu,
    heightEmu: heightEmu,
    previewSvg: preview.svg,
    unsupportedPreviewRecords: preview.unsupported,
  );
}

class _MetafileRecord {
  const _MetafileRecord(this.type, this.offset, this.size);
  final int type, offset, size;
}

class _MetafileScan {
  const _MetafileScan(
    this.records,
    this.bounds,
    this.nativeEmbeddingAllowed,
    this.objects, {
    this.boundsKnown = true,
  });
  final List<_MetafileRecord> records;
  final LegacyWordVectorBounds bounds;
  final bool nativeEmbeddingAllowed;
  final int objects;
  final bool boundsKnown;
}

_MetafileScan _scanEmf(_MetaBytes input) {
  input.require(0, 88);
  final headerSize = input.u32(4), totalRecords = input.u32(52);
  final handles = input.u16(56);
  if (input.u32(0) != 1 ||
      headerSize < 88 ||
      headerSize % 4 != 0 ||
      input.u32(40) != 0x464d4520 ||
      input.u32(44) != 0x00010000 ||
      input.u32(48) != input.length ||
      totalRecords < 2 ||
      totalRecords > legacyWordMetafileRecordLimit ||
      handles < 1 ||
      handles > legacyWordMetafileObjectLimit) {
    throw const FormatException('Invalid or oversized EMF header.');
  }
  input.require(0, headerSize);
  final descriptionCount = input.u32(60), descriptionOffset = input.u32(64);
  if (descriptionCount > 0 &&
      (descriptionOffset < 88 ||
          descriptionOffset > headerSize ||
          descriptionCount > (headerSize - descriptionOffset) ~/ 2)) {
    throw const FormatException('Invalid EMF description extent.');
  }
  final records = <_MetafileRecord>[_MetafileRecord(1, 0, headerSize)];
  var cursor = headerSize, native = true, eof = false;
  while (cursor < input.length) {
    input.require(cursor, 8);
    final type = input.u32(cursor), size = input.u32(cursor + 4);
    if (size < 8 || size % 4 != 0 || type == 0 || type == 1) {
      throw const FormatException('Invalid EMF record header.');
    }
    input.require(cursor, size);
    if (records.length >= legacyWordMetafileRecordLimit) {
      throw const FormatException('Metafile exceeds its record limit.');
    }
    records.add(_MetafileRecord(type, cursor, size));
    if (const {105, 106, 110}.contains(type)) native = false;
    if (type == 14) {
      if (size < 20 || cursor + size != input.length) {
        throw const FormatException('Invalid EMF end record.');
      }
      final count = input.u32(cursor + 8), offset = input.u32(cursor + 12);
      if (input.u32(cursor + size - 4) != size ||
          (count > 0 &&
              (offset < 16 ||
                  offset > size - 4 ||
                  count > (size - 4 - offset) ~/ 4))) {
        throw const FormatException('Invalid EMF palette extent.');
      }
      eof = true;
    }
    cursor += size;
  }
  if (!eof || records.length != totalRecords) {
    throw const FormatException('Inconsistent EMF record count or end.');
  }
  return _MetafileScan(
    records,
    LegacyWordVectorBounds(
      input.i32(8),
      input.i32(12),
      input.i32(16),
      input.i32(20),
    ),
    native,
    handles,
  );
}

_MetafileScan _scanWmf(
  _MetaBytes input,
  LegacyWordVectorBounds? suppliedBounds,
) {
  input.require(0, 18);
  var start = 0;
  LegacyWordVectorBounds? placeableBounds;
  if (input.u32(0) == 0x9ac6cdd7) {
    input.require(0, 40);
    var checksum = 0;
    for (var i = 0; i < 20; i += 2) {
      checksum ^= input.u16(i);
    }
    if (checksum != input.u16(20) || input.u16(14) == 0) {
      throw const FormatException('Invalid placeable WMF header.');
    }
    placeableBounds = LegacyWordVectorBounds(
      input.i16(6),
      input.i16(8),
      input.i16(10),
      input.i16(12),
    );
    start = 22;
  }
  final words = input.u32(start + 6), objects = input.u16(start + 10);
  final maxRecord = input.u32(start + 12);
  if (!const {1, 2}.contains(input.u16(start)) ||
      input.u16(start + 2) != 9 ||
      !const {0x100, 0x300}.contains(input.u16(start + 4)) ||
      words != (input.length - start) ~/ 2 ||
      (input.length - start) % 2 != 0 ||
      objects > legacyWordMetafileObjectLimit ||
      maxRecord < 3 ||
      maxRecord > words) {
    throw const FormatException('Invalid or oversized WMF header.');
  }
  final records = <_MetafileRecord>[];
  var cursor = start + 18, native = true, eof = false, observedMax = 0;
  while (cursor < input.length) {
    input.require(cursor, 6);
    final sizeWords = input.u32(cursor), type = input.u16(cursor + 4);
    if (sizeWords < 3 || sizeWords > (input.length - cursor) ~/ 2) {
      throw const FormatException('Invalid WMF record extent.');
    }
    if (records.length >= legacyWordMetafileRecordLimit) {
      throw const FormatException('Metafile exceeds its record limit.');
    }
    final size = sizeWords * 2;
    records.add(_MetafileRecord(type, cursor, size));
    if (sizeWords > observedMax) observedMax = sizeWords;
    if (type == 0x0626) native = false;
    if (type == 0) {
      if (size != 6 || cursor + size != input.length) {
        throw const FormatException('Invalid WMF end record.');
      }
      eof = true;
    }
    cursor += size;
  }
  if (!eof || observedMax > maxRecord) {
    throw const FormatException('Inconsistent WMF maximum record or end.');
  }
  return _MetafileScan(
    records,
    suppliedBounds ??
        placeableBounds ??
        const LegacyWordVectorBounds(0, 0, 1, 1),
    native,
    objects,
    boundsKnown: suppliedBounds != null || placeableBounds != null,
  );
}

class _MetaBytes {
  _MetaBytes(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  int get length => bytes.length;
  void require(int offset, int size) {
    if (offset < 0 || size < 0 || offset > length || size > length - offset) {
      throw const FormatException('Truncated metafile structure.');
    }
  }

  int u8(int offset) {
    require(offset, 1);
    return bytes[offset];
  }

  int u16(int offset) {
    require(offset, 2);
    return data.getUint16(offset, Endian.little);
  }

  int i16(int offset) {
    require(offset, 2);
    return data.getInt16(offset, Endian.little);
  }

  int u32(int offset) {
    require(offset, 4);
    return data.getUint32(offset, Endian.little);
  }

  int i32(int offset) {
    require(offset, 4);
    return data.getInt32(offset, Endian.little);
  }

  double f32(int offset) {
    require(offset, 4);
    return data.getFloat32(offset, Endian.little);
  }
}
