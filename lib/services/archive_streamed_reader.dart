import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:archive/archive.dart' show getCrc32;
import 'package:koni_codecs/koni_codecs.dart' as codecs;

import '../models/archive_endpoint.dart';
import 'archive_dmg_reader.dart';
import 'archive_endpoint_policy.dart';
import 'archive_format_registry.dart';
import 'archive_iso_reader.dart';
import 'archive_udf_reader.dart';
import 'archive_iso_writer.dart';
import 'archive_output_spool.dart';
import 'archive_rar_stored_reader.dart';
import 'archive_sevenz_streamed_reader.dart';
import 'archive_streaming_unsupported.dart';

export 'archive_streaming_unsupported.dart';
import 'archive_tar_writer.dart';
import 'archive_viewer_service.dart';
import 'archive_write_model.dart';
import 'archive_zip_package_policy.dart';

/// A native, bounded reader and its preservation policy. [archive] owns the
/// supplied source and any decoded scratch output; close it after use.
class StreamedArchiveOpen {
  const StreamedArchiveOpen({required this.archive, required this.policy});
  final ViewerArchive archive;
  final ArchiveEndpointPolicy policy;
}

/// Opens the common writable container formats without collecting their input
/// or members. The caller transfers source ownership, including on failure.
/// ZIP/7z metadata stays bounded; gzip is validated into a private TAR spool.
/// Read-only ISO viewers can omit the full preservation scan with
/// [inspectIsoForRewrite]. Such a handle has an explicitly read-only policy;
/// workspace opens and candidate verification retain the default full scan.
Future<StreamedArchiveOpen> openStreamedArchiveSource(
  koni.ByteSource source, {
  required String name,
  String? password,
  int maxBytes = kArchiveStreamingLimit,
  bool Function()? isCancelled,
  bool inspectIsoForRewrite = true,
  int? diskImageSectorBytes,
}) async {
  ArchiveOutputSpool? decoded;
  koni.ByteSource? decodedSource;
  ViewerArchive? inner;
  var opening = true;
  void check() {
    if (opening && (isCancelled?.call() ?? false)) {
      throw const ArchiveViewException('Archive opening was cancelled.');
    }
  }

  try {
    if (!const bool.fromEnvironment('dart.library.io') ||
        maxBytes <= 0 ||
        maxBytes > kArchiveStreamingLimit ||
        source.length > maxBytes) {
      throw const ArchiveViewException(
        'Streamed archive input exceeds its supported bounds.',
      );
    }
    check();
    final input = _BorrowedSource(source, check);
    final prefix = await input.read(
      0,
      source.length < 512 ? source.length : 512,
    );
    final descriptor = archiveFormatForName(name);
    if (descriptor?.id == 'fat' ||
        descriptor?.id == 'ext' ||
        descriptor?.id == 'disk-image' ||
        diskImageSectorBytes != null) {
      inner = await openViewerArchiveSource(
        input,
        name: name,
        password: password,
        maxMemberBytes: maxBytes < kArchiveReadLimit
            ? maxBytes
            : kArchiveReadLimit,
        maxDiskImageMemberBytes: maxBytes,
        diskImageSectorBytes: diskImageSectorBytes,
        isCancelled: isCancelled,
      );
      final policy = ArchiveEndpointPolicy(
        ArchiveEndpointFormat.readOnly,
        encrypted: inner.members.any((member) => member.isEncrypted),
        encryptNames: false,
        reason: 'Disk images support browsing and extraction only.',
      );
      check();
      final ownedArchive = _own(
        inner,
        source,
        null,
        null,
        inner.maxStreamingMemberBytes,
      );
      inner = null;
      opening = false;
      return StreamedArchiveOpen(archive: ownedArchive, policy: policy);
    }
    final format = switch (descriptor?.id) {
      'zip' => ArchiveEndpointFormat.zip,
      'zip-alias' ||
      'java-archive' when isEditableZipAlias(name) => ArchiveEndpointFormat.zip,
      '7z' || '7z-alias' => ArchiveEndpointFormat.sevenZip,
      'tar' || 'tar-alias' => ArchiveEndpointFormat.tar,
      'tar-gzip' => ArchiveEndpointFormat.tarGzip,
      'iso' => ArchiveEndpointFormat.iso,
      'rar' => ArchiveEndpointFormat.rar,
      'dmg' => ArchiveEndpointFormat.dmg,
      _ => ArchiveEndpointFormat.readOnly,
    };
    if ((format == ArchiveEndpointFormat.iso || descriptor?.id == 'udf') &&
        await hasUdfVolumeRecognition(input)) {
      inner = await openUdfArchive(input, maxMemberBytes: maxBytes);
      const policy = ArchiveEndpointPolicy(
        ArchiveEndpointFormat.readOnly,
        encrypted: false,
        encryptNames: false,
        reason: 'UDF and ISO/UDF bridge images support browsing and extraction only.',
      );
      check();
      final ownedArchive = _own(inner, source, null, null, maxBytes);
      inner = null;
      opening = false;
      return StreamedArchiveOpen(archive: ownedArchive, policy: policy);
    }
    if (descriptor?.id == 'udf') {
      throw const ArchiveViewException(
        'The archive does not match its filename.',
      );
    }
    if (format == ArchiveEndpointFormat.readOnly) {
      throw const ArchiveViewException(
        'This format has no streamed writable profile.',
      );
    }
    if (format == ArchiveEndpointFormat.dmg) {
      if (input.length < 512 ||
          !(await input.read(input.length - 512, 4)).asMap().entries.every(
            (entry) => entry.value == const [0x6b, 0x6f, 0x6c, 0x79][entry.key],
          )) {
        throw const ArchiveViewException(
          'The archive does not match its filename.',
        );
      }
      final opened = await openStreamedDmgSource(
        input,
        maxBytes: maxBytes,
        isCancelled: isCancelled,
      );
      inner = opened.archive;
      final policy = ArchiveEndpointPolicy(
        format,
        encrypted: false,
        encryptNames: false,
        reason: opened.inspection.reason,
        inspection: opened.inspection,
      );
      final ownedArchive = _own(inner, source, null, null, maxBytes);
      inner = null;
      opening = false;
      return StreamedArchiveOpen(archive: ownedArchive, policy: policy);
    }
    if (format == ArchiveEndpointFormat.tarGzip) {
      decoded = await ArchiveOutputSpool.create(maxBytes: maxBytes);
      final gzipHeader = await _decodeGzip(input, decoded, check);
      decodedSource = await decoded.openByteSource();
      inner = await openViewerArchiveSource(
        _BorrowedSource(decodedSource, check),
        name: 'contents.tar',
        maxMemberBytes: maxBytes,
      );
      if (inner.formatName != 'tar') {
        throw const ArchiveViewException(
          'The gzip payload is not a TAR archive.',
        );
      }
      final inspection = await inspectTarRewriteSource(
        decodedSource,
        inner,
        maxBytes: maxBytes,
        isCancelled: isCancelled,
      );
      final policy = ArchiveEndpointPolicy(
        format,
        encrypted: false,
        encryptNames: false,
        reason: inspection.reason,
        inspection: inspection,
        gzipHeader: gzipHeader,
      );
      final ownedArchive = _own(
        inner,
        source,
        decodedSource,
        decoded,
        maxBytes,
      );
      inner = null;
      decodedSource = null;
      decoded = null;
      opening = false;
      return StreamedArchiveOpen(archive: ownedArchive, policy: policy);
    }
    if (format == ArchiveEndpointFormat.sevenZip) {
      inner = await openStreamedSevenZipSource(input, maxBytes: maxBytes);
    } else if (format == ArchiveEndpointFormat.iso) {
      if (input.length < 16 * 2048 + 7 ||
          !(await input.read(16 * 2048 + 1, 5)).asMap().entries.every(
            (entry) =>
                entry.value == const [0x43, 0x44, 0x30, 0x30, 0x31][entry.key],
          )) {
        throw const ArchiveViewException(
          'The archive does not match its filename.',
        );
      }
      inner = await openIsoArchive(input, maxMemberBytes: maxBytes);
    } else if (format == ArchiveEndpointFormat.rar) {
      inner = await openStoredRarArchive(
        input,
        maxBytes: maxBytes,
        isCancelled: isCancelled,
      );
    } else {
      if (format == ArchiveEndpointFormat.zip &&
          (prefix.length < 4 || prefix[0] != 0x50 || prefix[1] != 0x4b)) {
        throw const ArchiveViewException(
          'The ZIP container does not match its filename.',
        );
      }
      inner = await openViewerArchiveSource(
        input,
        name: name,
        password: password,
        maxMemberBytes: maxBytes,
      );
    }
    final expected = switch (format) {
      ArchiveEndpointFormat.zip => 'zip',
      ArchiveEndpointFormat.sevenZip => '7z',
      ArchiveEndpointFormat.iso => 'iso',
      ArchiveEndpointFormat.rar => 'rar',
      _ => 'tar',
    };
    if (inner.formatName != expected) {
      throw const ArchiveViewException(
        'The archive does not match its filename.',
      );
    }
    ArchiveRewriteInspection? inspection;
    String? reason;
    final encrypted = inner.members.any((member) => member.isEncrypted);
    if (encrypted) {
      throw const ArchiveStreamingUnsupported(
        'Protected archives use the bounded password-preserving workspace.',
      );
    }
    if ((format == ArchiveEndpointFormat.zip ||
            format == ArchiveEndpointFormat.sevenZip) &&
        inner.members.any((member) => (member.posixMode ?? 0) & 0xc00 != 0)) {
      reason = 'This writer cannot preserve ownership associated with setuid or setgid members.';
    }
    if (format == ArchiveEndpointFormat.zip) {
      reason ??= await _inspectZipTimes(input);
      if (reason == null && isEditableZipAlias(name)) {
        final opened = inner;
        reason = await archiveZipPackageIssue(name, [
          for (final member in opened.members)
            ArchiveWriteEntry(
              path: member.name.replaceFirst(RegExp(r'/+$'), ''),
              isDirectory: !member.isFile,
              size: member.isFile ? member.size : 0,
              readChunks: member.isFile
                  ? () => opened.openMember(member)
                  : null,
            ),
        ]);
      }
    } else if (format == ArchiveEndpointFormat.tar) {
      inspection = await inspectTarRewriteSource(
        input,
        inner,
        maxBytes: maxBytes,
        isCancelled: isCancelled,
      );
      reason ??= inspection.reason;
    } else if (format == ArchiveEndpointFormat.iso) {
      if (inspectIsoForRewrite) {
        inspection = await inspectIsoRewriteSource(
          input,
          inner,
          maxBytes: maxBytes,
          isCancelled: isCancelled,
        );
        reason ??= inspection.reason;
      } else {
        reason = 'ISO rewriting requires a complete preservation inspection.';
      }
    } else if (format == ArchiveEndpointFormat.rar) {
      inspection = await inspectStoredRarRewriteSource(
        input,
        maxBytes: maxBytes,
        isCancelled: isCancelled,
      );
      reason ??= inspection.reason;
    }
    check();
    final policy = ArchiveEndpointPolicy(
      format,
      encrypted: encrypted,
      encryptNames: false,
      reason: reason,
      inspection: inspection,
    );
    final ownedArchive = _own(inner, source, null, null, maxBytes);
    inner = null;
    opening = false;
    return StreamedArchiveOpen(archive: ownedArchive, policy: policy);
  } catch (_) {
    try {
      await inner?.close();
    } finally {
      try {
        await decodedSource?.close();
      } finally {
        try {
          await decoded?.dispose();
        } finally {
          await source.close();
        }
      }
    }
    rethrow;
  }
}

ViewerArchive _own(
  ViewerArchive inner,
  koni.ByteSource original,
  koni.ByteSource? decodedSource,
  ArchiveOutputSpool? decoded,
  int maxBytes,
) => ViewerArchive.reader(
  maxStreamingMemberBytes: maxBytes,
  formatName: inner.formatName,
  members: inner.members,
  notices: inner.notices,
  read: (member, limit) => inner.readMember(member, maxBytes: limit),
  streamReader: (member, chunkSize) =>
      inner.openMember(member, maxBytes: maxBytes, chunkSize: chunkSize),
  close: () async {
    try {
      await inner.close();
    } finally {
      try {
        await decodedSource?.close();
      } finally {
        try {
          await decoded?.dispose();
        } finally {
          await original.close();
        }
      }
    }
  },
);

class _BorrowedSource implements koni.ByteSource {
  _BorrowedSource(this.source, this.check);
  final koni.ByteSource source;
  final void Function() check;
  @override
  int get length => source.length;
  @override
  String? get name => source.name;
  @override
  Future<Uint8List> read(int offset, int length) async {
    check();
    if (length > 64 * 1024 * 1024) {
      throw const ArchiveViewException('Archive metadata read exceeds 64 MiB.');
    }
    final result = await source.read(offset, length);
    check();
    return result;
  }

  @override
  Future<void> close() async {}
}

Future<Uint8List> _decodeGzip(
  koni.ByteSource source,
  ArchiveOutputSpool output,
  void Function() check,
) async {
  if (source.length < 18) {
    throw const ArchiveViewException('Truncated gzip container.');
  }
  final start = await source.read(
    0,
    source.length < 65536 ? source.length : 65536,
  );
  final parsed = codecs.tryParseGzipHeader(start, verifyHeaderCrc: true);
  if (parsed == null || parsed.$2 > source.length - 8) {
    throw const ArchiveViewException(
      'The gzip header exceeds its bounded profile.',
    );
  }
  final header = Uint8List.fromList(start.sublist(0, parsed.$2));
  final trailer = ByteData.sublistView(await source.read(source.length - 8, 8));
  final pending = <Uint8List>[];
  var crc = 0;
  var produced = 0;
  final decoder = codecs.RawInflater(
    onOutput: (chunk) {
      if (chunk.length > output.maxBytes - produced) {
        throw const ArchiveViewException(
          'The gzip payload exceeds the streaming limit.',
        );
      }
      produced += chunk.length;
      crc = getCrc32(chunk, crc);
      pending.add(chunk);
    },
  );
  for (var offset = header.length; offset < source.length - 8;) {
    check();
    final count = source.length - 8 - offset < 4096
        ? source.length - 8 - offset
        : 4096;
    final input = await source.read(offset, count);
    final consumed = decoder.addInput(input);
    offset += consumed;
    for (final chunk in pending) {
      await output.write(chunk);
    }
    pending.clear();
    if (consumed != input.length ||
        decoder.isFinished &&
            (offset != source.length - 8 ||
                decoder.takeLeftoverBytes().isNotEmpty)) {
      throw const ArchiveViewException(
        'Concatenated or trailing gzip data cannot be rewritten safely.',
      );
    }
    await Future<void>.delayed(Duration.zero);
  }
  decoder.finish();
  for (final chunk in pending) {
    await output.write(chunk);
  }
  if (crc != trailer.getUint32(0, Endian.little) ||
      produced & 0xffffffff != trailer.getUint32(4, Endian.little)) {
    throw const ArchiveViewException(
      'The gzip checksum or decoded size does not match.',
    );
  }
  check();
  await output.finish();
  return header;
}

Future<String?> _inspectZipTimes(koni.ByteSource source) async {
  const unsupported =
      'This ZIP timestamp metadata cannot be preserved by the streaming reader and writer.';
  try {
    if (source.length < 22) return unsupported;
    final tailLength = source.length < 65557 ? source.length : 65557;
    final tailStart = source.length - tailLength;
    final tail = await source.read(tailStart, tailLength);
    final td = ByteData.sublistView(tail);
    var end = -1;
    for (var at = tail.length - 22; at >= 0; at--) {
      if (td.getUint32(at, Endian.little) == 0x06054b50 &&
          at + 22 + td.getUint16(at + 20, Endian.little) == tail.length) {
        end = at;
        break;
      }
    }
    if (end < 0 ||
        td.getUint16(end + 4, Endian.little) != 0 ||
        td.getUint16(end + 6, Endian.little) != 0) {
      return unsupported;
    }
    var count = td.getUint16(end + 10, Endian.little);
    var size = td.getUint32(end + 12, Endian.little);
    var position = td.getUint32(end + 16, Endian.little);
    final absoluteEnd = tailStart + end;
    final locator = absoluteEnd >= 20
        ? await source.read(absoluteEnd - 20, 20)
        : null;
    if (locator != null &&
            ByteData.sublistView(locator).getUint32(0, Endian.little) ==
                0x07064b50 ||
        size == 0xffffffff ||
        position == 0xffffffff) {
      if (locator == null) return unsupported;
      final ld = ByteData.sublistView(locator);
      if (ld.getUint32(0, Endian.little) != 0x07064b50 ||
          ld.getUint32(4, Endian.little) != 0 ||
          ld.getUint32(16, Endian.little) != 1) {
        return unsupported;
      }
      final offset = ld.getUint64(8, Endian.little);
      if (offset > absoluteEnd - 76) return unsupported;
      final z = ByteData.sublistView(await source.read(offset, 56));
      if (z.getUint32(0, Endian.little) != 0x06064b50 ||
          z.getUint32(16, Endian.little) != 0 ||
          z.getUint32(20, Endian.little) != 0) {
        return unsupported;
      }
      count = z.getUint64(32, Endian.little);
      size = z.getUint64(40, Endian.little);
      position = z.getUint64(48, Endian.little);
    }
    if (count > 200000 ||
        size > 64 * 1024 * 1024 ||
        position > absoluteEnd ||
        size > absoluteEnd - position) {
      return unsupported;
    }
    final directory = await source.read(position, size);
    final data = ByteData.sublistView(directory);
    int u16(int at) => data.getUint16(at, Endian.little);
    int u32(int at) => data.getUint32(at, Endian.little);
    int u64(int at) => data.getUint64(at, Endian.little);
    final locals = <({int start, int end})>[];
    final seen = <int>{};
    var at = 0, metadata = 0;
    for (var i = 0; i < count; i++) {
      if (at + 46 > size || u32(at) != 0x02014b50) return unsupported;
      final nameLength = u16(at + 28),
          extraLength = u16(at + 30),
          commentLength = u16(at + 32);
      final next = at + 46 + nameLength + extraLength + commentLength;
      if (next > size) return unsupported;
      final extra = at + 46 + nameLength;
      final centralTime = _zipTime(directory, extra, extraLength);
      var local = u32(at + 42);
      if (local == 0xffffffff) {
        for (var field = extra; field < extra + extraLength;) {
          final length = u16(field + 2);
          if (u16(field) == 1) {
            final value =
                field +
                4 +
                (u32(at + 24) == 0xffffffff ? 8 : 0) +
                (u32(at + 20) == 0xffffffff ? 8 : 0);
            if (value + 8 > field + 4 + length) return unsupported;
            local = u64(value);
            break;
          }
          field += 4 + length;
        }
      }
      if (local > position - 30 || !seen.add(local)) return unsupported;
      final header = ByteData.sublistView(await source.read(local, 30));
      if (header.getUint32(0, Endian.little) != 0x04034b50) return unsupported;
      final localNameLength = header.getUint16(26, Endian.little);
      final localExtraLength = header.getUint16(28, Endian.little);
      final localEnd = local + 30 + localNameLength + localExtraLength;
      if (localEnd > position || localNameLength != nameLength) {
        return unsupported;
      }
      metadata += localEnd - local;
      if (metadata > 64 * 1024 * 1024) return unsupported;
      final localData = await source.read(
        local + 30,
        localNameLength + localExtraLength,
      );
      for (var j = 0; j < nameLength; j++) {
        if (localData[j] != directory[at + 46 + j]) return unsupported;
      }
      final localTime = _zipTime(localData, localNameLength, localExtraLength);
      if (localTime != null && localTime != centralTime) return unsupported;
      locals.add((start: local, end: localEnd));
      at = next;
    }
    locals.sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < locals.length; i++) {
      if (locals[i - 1].end > locals[i].start) return unsupported;
    }
    return at == size ? null : unsupported;
  } on RangeError {
    return unsupported;
  } on FormatException {
    return unsupported;
  }
}

int? _zipTime(Uint8List bytes, int begin, int length) {
  final data = ByteData.sublistView(bytes);
  final end = begin + length;
  int? result;
  for (var at = begin; at < end;) {
    if (at + 4 > end) throw const FormatException('Truncated ZIP extra field.');
    final id = data.getUint16(at, Endian.little),
        count = data.getUint16(at + 2, Endian.little);
    if (at + 4 + count > end) {
      throw const FormatException('Truncated ZIP extra field.');
    }
    if (id == 0x5455) {
      if (count < 1) {
        throw const FormatException('Missing ZIP timestamp flags.');
      }
      if (bytes[at + 4] & 1 != 0) {
        if (count < 5 || result != null) {
          throw const FormatException('Invalid ZIP timestamp.');
        }
        result = data.getUint32(at + 5, Endian.little);
        if (result > 0x7fffffff) {
          throw const FormatException('Unsupported signed ZIP time.');
        }
      }
    }
    at += 4 + count;
  }
  return result;
}
