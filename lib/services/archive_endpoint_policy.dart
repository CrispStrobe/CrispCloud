import 'dart:typed_data';

import '../models/archive_endpoint.dart';
import 'archive_viewer_service.dart';
import 'archive_zip_metadata.dart';

/// Writer policy is deliberately narrower than reader recognition. The reader
/// exposes only selected metadata; opaque format extensions are not promised.
class ArchiveEndpointPolicy {
  const ArchiveEndpointPolicy(
    this.format, {
    required this.encrypted,
    required this.encryptNames,
    this.reason,
  });
  final ArchiveEndpointFormat format;
  final bool encrypted;
  final bool encryptNames;
  final String? reason;

  static Future<ArchiveEndpointPolicy> inspect(
    Uint8List bytes,
    String name,
    ViewerArchive archive,
    String? password,
  ) async {
    final lower = name.toLowerCase();
    final format = lower.endsWith('.zip')
        ? ArchiveEndpointFormat.zip
        : lower.endsWith('.7z')
        ? ArchiveEndpointFormat.sevenZip
        : lower.endsWith('.tar.gz') || lower.endsWith('.tgz')
        ? ArchiveEndpointFormat.tarGzip
        : lower.endsWith('.tar')
        ? ArchiveEndpointFormat.tar
        : ArchiveEndpointFormat.readOnly;
    final files = archive.members.where((member) => member.isFile).toList();
    var encrypted = archive.members.any((member) => member.isEncrypted);
    var encryptNames = false;
    String? reason;
    final expectedFormat = switch (format) {
      ArchiveEndpointFormat.zip => 'zip',
      ArchiveEndpointFormat.sevenZip => '7z',
      ArchiveEndpointFormat.tar || ArchiveEndpointFormat.tarGzip => 'tar',
      ArchiveEndpointFormat.readOnly => null,
    };
    final gzip = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
    if (expectedFormat != null &&
        (archive.formatName.toLowerCase() != expectedFormat ||
            (format == ArchiveEndpointFormat.tarGzip) != gzip)) {
      reason = 'The detected archive format does not match its filename. Repacking would change its format.';
    }
    if (format == ArchiveEndpointFormat.readOnly) reason = 'This format supports browsing and extraction, but its writer is unavailable.';
    if (format == ArchiveEndpointFormat.zip) {
      reason ??= archiveZipTimestampPolicyIssue(bytes);
    }
    // Header protection is independent of file-data encryption. In particular,
    // an empty 7z can still require its original password to open the header.
    if (format == ArchiveEndpointFormat.sevenZip && password != null) {
      try {
        final public = await openViewerArchive(bytes, name: name);
        await public.close();
      } on ArchivePasswordRequiredException {
        encryptNames = true;
        encrypted = true;
      }
    }
    if (password != null && files.isEmpty && !encryptNames && !encrypted) {
      reason = 'The protection policy of this empty archive cannot be established. Repacking is refused.';
    }
    if (encrypted && password == null) {
      reason = 'The original archive password is required.';
    }
    if (encrypted &&
        files.any(
          (member) =>
              !member.isEncrypted &&
              (format == ArchiveEndpointFormat.zip || member.size > 0),
        )) {
      reason = 'Mixed encrypted and unencrypted members cannot be repacked without changing their protection policy.';
    }
    if (format == ArchiveEndpointFormat.zip &&
        archive.members.any((member) => !member.isFile && member.isEncrypted)) {
      reason =
          'Encrypted ZIP directory entries cannot be preserved by this writer.';
    }
    if (format == ArchiveEndpointFormat.zip &&
        encrypted &&
        !_zipAes256(bytes)) {
      reason = 'This ZIP encryption policy cannot be preserved by the available writer. Browsing and extraction remain available.';
    }
    if ((format == ArchiveEndpointFormat.tar ||
            format == ArchiveEndpointFormat.tarGzip) &&
        encrypted) {
      reason = 'The TAR writer cannot preserve this encryption policy.';
    }
    return ArchiveEndpointPolicy(
      format,
      encrypted: encrypted,
      encryptNames: encryptNames,
      reason: reason,
    );
  }

  /// Read the already-decoded ZIP's bounded central-directory descriptors only
  /// to distinguish the supported AES-256 policy from legacy/strong variants.
  /// Payload validation remains the independent archive reader's responsibility.
  static bool _zipAes256(Uint8List bytes) {
    try {
      final data = ByteData.sublistView(bytes);
      int u16(int at) => data.getUint16(at, Endian.little);
      int u32(int at) => data.getUint32(at, Endian.little);
      int u64(int at) => data.getUint64(at, Endian.little);
      var end = -1;
      final minimum = (bytes.length - 65557).clamp(0, bytes.length);
      for (var offset = bytes.length - 22; offset >= minimum; offset--) {
        if (u32(offset) == 0x06054b50 &&
            offset + 22 + u16(offset + 20) == bytes.length) {
          end = offset;
          break;
        }
      }
      if (end < 0 || u16(end + 4) != 0 || u16(end + 6) != 0) return false;
      var count = u16(end + 10), size = u32(end + 12), offset = u32(end + 16);
      if ((end >= 76 && u32(end - 20) == 0x07064b50) ||
          size == 0xffffffff ||
          offset == 0xffffffff) {
        if (end < 20 ||
            u32(end - 20) != 0x07064b50 ||
            u32(end - 16) != 0 ||
            u32(end - 4) != 1) {
          return false;
        }
        final zip64 = u64(end - 12);
        if (zip64 < 0 ||
            zip64 + 56 > end ||
            u32(zip64) != 0x06064b50 ||
            u32(zip64 + 16) != 0 ||
            u32(zip64 + 20) != 0) {
          return false;
        }
        count = u64(zip64 + 32);
        size = u64(zip64 + 40);
        offset = u64(zip64 + 48);
      }
      if (count <= 0 ||
          count > 200000 ||
          offset < 0 ||
          size < 0 ||
          offset + size > end) {
        return false;
      }
      final limit = offset + size;
      var encrypted = 0;
      for (var index = 0; index < count; index++) {
        if (offset + 46 > limit || u32(offset) != 0x02014b50) return false;
        final flags = u16(offset + 8), method = u16(offset + 10);
        final nameBytes = u16(offset + 28),
            extraBytes = u16(offset + 30),
            commentBytes = u16(offset + 32);
        final next = offset + 46 + nameBytes + extraBytes + commentBytes;
        if (next > limit) return false;
        if ((flags & 1) != 0) {
          encrypted++;
          if ((flags & 0x40) != 0 || method != 99) return false;
          var extra = offset + 46 + nameBytes;
          final extraEnd = extra + extraBytes;
          var aes = false;
          while (extra < extraEnd) {
            if (extra + 4 > extraEnd) return false;
            final id = u16(extra), length = u16(extra + 2);
            extra += 4;
            if (extra + length > extraEnd) return false;
            if (id == 0x9901) {
              if (aes ||
                  length != 7 ||
                  ![1, 2].contains(u16(extra)) ||
                  bytes[extra + 2] != 0x41 ||
                  bytes[extra + 3] != 0x45 ||
                  bytes[extra + 4] != 3) {
                return false;
              }
              aes = true;
            }
            extra += length;
          }
          if (!aes) return false;
        }
        offset = next;
      }
      return encrypted > 0 && offset == limit;
    } on RangeError {
      return false;
    }
  }

  DateTime? normalizeImportedTime(DateTime? value) {
    if (value == null) return null;
    final utc = value.toUtc();
    return switch (format) {
      ArchiveEndpointFormat.zip => _zipImportedTime(utc),
      ArchiveEndpointFormat.tar ||
      ArchiveEndpointFormat.tarGzip => DateTime.fromMillisecondsSinceEpoch(
        utc.millisecondsSinceEpoch ~/ 1000 * 1000,
        isUtc: true,
      ),
      ArchiveEndpointFormat.sevenZip => DateTime.fromMillisecondsSinceEpoch(
        utc.millisecondsSinceEpoch,
        isUtc: true,
      ),
      ArchiveEndpointFormat.readOnly => utc,
    };
  }

  DateTime _zipImportedTime(DateTime utc) {
    final seconds = utc.millisecondsSinceEpoch ~/ 1000;
    if (seconds >= 0 && seconds <= 0x7fffffff) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    }
    if (utc.year >= 1980 && utc.year <= 2107) {
      return DateTime.utc(
        utc.year,
        utc.month,
        utc.day,
        utc.hour,
        utc.minute,
        utc.second ~/ 2 * 2,
      );
    }
    throw StateError(
      'The imported time cannot be represented by the supported ZIP timestamp fields.',
    );
  }
}
