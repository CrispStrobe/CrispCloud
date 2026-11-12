import 'dart:typed_data';

import '../models/archive_endpoint.dart';
import 'archive_viewer_service.dart';
import 'archive_zip_metadata.dart';
import 'archive_compression_writer.dart';
import 'archive_format_registry.dart';
import 'archive_iso_writer.dart';
import 'archive_package_writers.dart';
import 'archive_tar_writer.dart';
import 'archive_write_model.dart';
import 'archive_zip_package_policy.dart';

/// Writer policy is deliberately narrower than reader recognition. The reader
/// exposes only selected metadata; opaque format extensions are not promised.
class ArchiveEndpointPolicy {
  const ArchiveEndpointPolicy(
    this.format, {
    required this.encrypted,
    required this.encryptNames,
    this.reason,
    this.inspection,
    this.gzipHeader,
    this.xzCheck = 4,
    this.singleMemberName,
  });
  final ArchiveEndpointFormat format;
  final bool encrypted;
  final bool encryptNames;
  final String? reason;
  final ArchiveRewriteInspection? inspection;
  final Uint8List? gzipHeader;
  final int xzCheck;
  final String? singleMemberName;

  bool get singlePayload => const {
    ArchiveEndpointFormat.gzip,
    ArchiveEndpointFormat.bzip2,
    ArchiveEndpointFormat.xz,
    ArchiveEndpointFormat.zstd,
    ArchiveEndpointFormat.lz4,
    ArchiveEndpointFormat.lzma,
  }.contains(format);

  ArchiveCompressionKind? get compression => switch (format) {
    ArchiveEndpointFormat.tarGzip ||
    ArchiveEndpointFormat.gzip => ArchiveCompressionKind.gzip,
    ArchiveEndpointFormat.tarBzip2 ||
    ArchiveEndpointFormat.bzip2 => ArchiveCompressionKind.bzip2,
    ArchiveEndpointFormat.tarXz ||
    ArchiveEndpointFormat.xz => ArchiveCompressionKind.xz,
    ArchiveEndpointFormat.tarZstd ||
    ArchiveEndpointFormat.zstd => ArchiveCompressionKind.zstd,
    ArchiveEndpointFormat.tarLz4 ||
    ArchiveEndpointFormat.lz4 => ArchiveCompressionKind.lz4,
    ArchiveEndpointFormat.tarLzma ||
    ArchiveEndpointFormat.lzma => ArchiveCompressionKind.lzma,
    _ => null,
  };

  String? get packageKind => inspection?.container['package.kind'] as String?;

  static Future<ArchiveEndpointPolicy> inspect(
    Uint8List bytes,
    String name,
    ViewerArchive archive,
    String? password,
  ) async {
    final lower = name.toLowerCase();
    final descriptor = archiveFormatForName(name);
    final format = switch (descriptor?.id) {
      'zip' => ArchiveEndpointFormat.zip,
      'zip-alias' ||
      'java-archive' when isEditableZipAlias(name) => ArchiveEndpointFormat.zip,
      '7z' || '7z-alias' => ArchiveEndpointFormat.sevenZip,
      'tar' || 'tar-alias' => ArchiveEndpointFormat.tar,
      'tar-gzip' => ArchiveEndpointFormat.tarGzip,
      'tar-bzip2' => ArchiveEndpointFormat.tarBzip2,
      'tar-xz' => ArchiveEndpointFormat.tarXz,
      'tar-zstd' => ArchiveEndpointFormat.tarZstd,
      'tar-lz4' => ArchiveEndpointFormat.tarLz4,
      'tar-lzma' => ArchiveEndpointFormat.tarLzma,
      'gzip' => ArchiveEndpointFormat.gzip,
      'bzip2' => ArchiveEndpointFormat.bzip2,
      'xz' => ArchiveEndpointFormat.xz,
      'zstd' => ArchiveEndpointFormat.zstd,
      'lz4' => ArchiveEndpointFormat.lz4,
      'lzma' => ArchiveEndpointFormat.lzma,
      'ar' || 'deb' => ArchiveEndpointFormat.ar,
      'cpio' => ArchiveEndpointFormat.cpio,
      'xar' when lower.endsWith('.xar') => ArchiveEndpointFormat.xar,
      'iso' => ArchiveEndpointFormat.iso,
      _ => ArchiveEndpointFormat.readOnly,
    };
    final basic = ArchiveEndpointPolicy(
      format,
      encrypted: false,
      encryptNames: false,
    );
    final files = archive.members.where((member) => member.isFile).toList();
    var encrypted = archive.members.any((member) => member.isEncrypted);
    var encryptNames = false;
    String? reason;
    ArchiveRewriteInspection? inspection;
    Uint8List? gzipHeader;
    var xzCheck = 4;
    final expectedFormat = switch (format) {
      ArchiveEndpointFormat.zip => 'zip',
      ArchiveEndpointFormat.sevenZip => '7z',
      ArchiveEndpointFormat.tar ||
      ArchiveEndpointFormat.tarGzip ||
      ArchiveEndpointFormat.tarBzip2 ||
      ArchiveEndpointFormat.tarXz ||
      ArchiveEndpointFormat.tarZstd ||
      ArchiveEndpointFormat.tarLz4 ||
      ArchiveEndpointFormat.tarLzma => 'tar',
      ArchiveEndpointFormat.readOnly => null,
      _ => format.name,
    };
    if (expectedFormat != null &&
        (archive.formatName.toLowerCase() != expectedFormat ||
            basic.compression !=
                archiveCompressionForBytes(bytes, name: name))) {
      reason = 'The detected archive format does not match its filename or supported compression wrapper. Repacking would change its format.';
    }
    // The 7z writer has no separate preservation inspector. The displayed
    // inner format alone is insufficient: a read-only wrapper renamed .7z
    // must not be silently removed on save, including shared skippable frames.
    if (format == ArchiveEndpointFormat.sevenZip &&
        (bytes.length < 6 ||
            bytes[0] != 0x37 ||
            bytes[1] != 0x7a ||
            bytes[2] != 0xbc ||
            bytes[3] != 0xaf ||
            bytes[4] != 0x27 ||
            bytes[5] != 0x1c)) {
      reason = 'The 7z writer requires the original unwrapped 7z container; an outer compression wrapper cannot be discarded.';
    }
    if (format == ArchiveEndpointFormat.readOnly) {
      reason = switch (descriptor?.id) {
        'dmg' || 'hfs' => 'Existing disk images remain read-only. Create a new HFSX data image from regular files and folders; other filesystem metadata requires a filesystem-aware editor.',
        'zip-package' || 'crx' || 'xar-package' || 'rpm' || 'cab' || 'pbzx' => 'This package requires a dedicated metadata or signing workflow. Browsing and extraction are available.',
        'ar-library' => 'Static object libraries require their linker or archive tool to rebuild the library symbol index.',
        _ => 'This format supports browsing and extraction, but its writer is unavailable.',
      };
    }
    if (reason == null && basic.compression != null) {
      try {
        validateArchiveCompressionRewrite(bytes, basic.compression!);
        if (basic.compression == ArchiveCompressionKind.gzip) {
          gzipHeader = archiveGzipHeader(bytes);
        }
        if (basic.compression == ArchiveCompressionKind.xz) {
          xzCheck = bytes[7];
          if (!const [0, 1, 4, 10].contains(xzCheck)) {
            reason = 'The XZ integrity check cannot be preserved.';
          }
        }
        if (basic.singlePayload &&
            (!archive.isDirectCompressionPayload ||
                files.length != 1 ||
                archive.members.length != 1)) {
          reason = 'A single-file compression writer requires the immediate regular payload. A listing inside another container cannot be flattened during save.';
        }
      } catch (_) {
        reason = 'The compression header cannot be preserved safely.';
      }
    }
    if (format == ArchiveEndpointFormat.zip && reason == null) {
      reason = archiveZipTimestampPolicyIssue(bytes);
      if (reason == null && isEditableZipAlias(name)) {
        reason = await archiveZipPackageIssue(name, [
          for (final member in archive.members)
            ArchiveWriteEntry(
              path: member.name.replaceFirst(RegExp(r'/+$'), ''),
              isDirectory: !member.isFile,
              size: member.isFile ? member.size : 0,
              readChunks: member.isFile
                  ? () => archive.openMember(member)
                  : null,
            ),
        ]);
      }
    }
    if (reason == null &&
        (format == ArchiveEndpointFormat.zip ||
            format == ArchiveEndpointFormat.sevenZip) &&
        archive.members.any((member) => (member.posixMode ?? 0) & 0xc00 != 0)) {
      reason = 'This writer cannot preserve ownership associated with setuid or setgid archive members.';
    }
    if (reason == null && expectedFormat == 'tar') {
      inspection = await inspectTarRewrite(bytes, archive, name: name);
      reason = inspection.reason;
    }
    if (reason == null &&
        const {
          ArchiveEndpointFormat.ar,
          ArchiveEndpointFormat.cpio,
          ArchiveEndpointFormat.xar,
          ArchiveEndpointFormat.iso,
        }.contains(format)) {
      inspection = format == ArchiveEndpointFormat.iso
          ? await inspectIsoRewrite(bytes, archive)
          : await inspectPackageRewrite(
              bytes,
              format == ArchiveEndpointFormat.ar &&
                      (lower.endsWith('.deb') || lower.endsWith('.udeb'))
                  ? 'deb'
                  : format.name,
              archive,
            );
      reason = inspection.reason;
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
    if (format != ArchiveEndpointFormat.zip &&
        format != ArchiveEndpointFormat.sevenZip &&
        encrypted) {
      reason = 'The selected writer cannot preserve this encryption policy.';
    }
    return ArchiveEndpointPolicy(
      format,
      encrypted: encrypted,
      encryptNames: encryptNames,
      reason: reason,
      inspection: inspection,
      gzipHeader: gzipHeader,
      xzCheck: xzCheck,
      singleMemberName: basic.singlePayload && files.length == 1
          ? files.single.name
          : null,
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
        if ((flags & 1) != 0 || (flags & 0x40) != 0 || method == 99) {
          encrypted++;
          if ((flags & 1) == 0 || (flags & 0x40) != 0 || method != 99) {
            return false;
          }
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
    if (value == null || singlePayload) return null;
    final utc = value.toUtc();
    return switch (format) {
      ArchiveEndpointFormat.zip => _zipImportedTime(utc),
      ArchiveEndpointFormat.tar ||
      ArchiveEndpointFormat.tarGzip ||
      ArchiveEndpointFormat.tarBzip2 ||
      ArchiveEndpointFormat.tarXz ||
      ArchiveEndpointFormat.tarZstd ||
      ArchiveEndpointFormat.tarLz4 ||
      ArchiveEndpointFormat.tarLzma ||
      ArchiveEndpointFormat.ar ||
      ArchiveEndpointFormat.cpio ||
      ArchiveEndpointFormat.xar ||
      ArchiveEndpointFormat.iso => DateTime.fromMillisecondsSinceEpoch(
        utc.millisecondsSinceEpoch - utc.millisecondsSinceEpoch % 1000,
        isUtc: true,
      ),
      ArchiveEndpointFormat.sevenZip => DateTime.fromMillisecondsSinceEpoch(
        utc.millisecondsSinceEpoch,
        isUtc: true,
      ),
      _ => utc,
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
