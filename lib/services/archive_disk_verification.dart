import 'package:crypto/crypto.dart';

import 'archive_dmg_reader.dart';
import 'archive_checkpoint_source.dart';
import 'file_operation_service.dart';
import 'archive_hfs_reader.dart';
import 'archive_hfs_writer.dart';
import 'archive_iso_reader.dart';
import 'archive_output_spool.dart';
import 'archive_types.dart';
import 'archive_write_model.dart';

const _diskLimit = kArchiveStreamingLimit;

/// Reopens a newly created data image before publication and compares its exact
/// file/directory namespace, file lengths, streamed SHA-256, supplied modes and
/// second-resolution modification times with the captured input. The caller's
/// entries must reopen the same captured content on every read.
///
/// DMG's generated raw-partition view is not an independent source member. Its
/// sole HFSX partition is drained separately to verify the UDIF partition CRC.
/// This validates our fresh data-image profile, not a publisher signature or an
/// arbitrary existing filesystem rewrite. The spool remains caller-owned.
/// [onVerificationPlan] runs once before payload verification and supplies the
/// extra raw-partition bytes needed for the DMG CRC pass (zero for ISO/HFSX).
/// [onDecodedBytes] reports only decoded member and raw-partition bytes; source
/// reads through [entries] remain the caller's responsibility to count.
Future<void> verifyCreatedDiskArchive(
  ArchiveOutputSpool spool,
  List<ArchiveWriteEntry> entries, {
  required String format,
  bool Function()? isCancelled,
  FileOperationControl? control,
  void Function(int rawPartitionBytes)? onVerificationPlan,
  Future<void> Function(int count, String path)? onDecodedBytes,
}) async {
  void check() {
    if ((control?.isCancelled ?? false) || (isCancelled?.call() ?? false)) {
      throw const ArchiveViewException('Disk image verification cancelled.');
    }
  }

  Future<void> checkpoint() async {
    check();
    await control?.checkpoint();
    check();
  }

  Stream<T> controlled<T>(Stream<T> input) => control?.bind(input) ?? input;

  final kind = format.toLowerCase();
  if (!const ['iso', 'hfs', 'hfsx', 'dmg'].contains(kind)) {
    throw ArgumentError.value(format, 'format');
  }
  validateArchiveWriteEntries(entries, maxEntries: 100000);
  check();
  final expected = <String, ArchiveWriteEntry?>{};
  final explicit = <String>{};
  for (final entry in entries) {
    final name = kind == 'iso'
        ? entry.path
        : normalizeHfsArchivePath(entry.path);
    if (!explicit.add(name) ||
        expected.containsKey(name) &&
            expected[name] == null &&
            !entry.isDirectory) {
      throw ArchiveViewException('Expected disk paths conflict: $name');
    }
    expected[name] = entry;
    final parts = name.split('/');
    for (var end = 1; end < parts.length; end++) {
      final parent = parts.take(end).join('/');
      if (expected[parent]?.isDirectory == false) {
        throw ArchiveViewException('Expected disk paths conflict: $parent');
      }
      expected.putIfAbsent(parent, () => null);
    }
  }
  final source = ArchiveCheckpointSource(
    await spool.openByteSource(),
    checkpoint,
    check,
  );
  ViewerArchive? archive;
  try {
    await checkpoint();
    archive = switch (kind) {
      'iso' => await openIsoArchive(source, maxMemberBytes: _diskLimit),
      'dmg' => await openDmgArchive(source, maxMemberBytes: _diskLimit),
      _ => await openHfsArchive(source, maxMemberBytes: _diskLimit),
    };
    if (kind != 'iso' && kind != 'dmg' && archive.formatName != 'hfsx') {
      throw const ArchiveViewException(
        'Created HFS image is not the HFSX profile.',
      );
    }
    final actual = <String, ViewerArchiveMember>{};
    ViewerArchiveMember? rawPartition;
    var members = archive.members;
    if (kind == 'dmg') {
      // An empty valid filesystem has no translated members. Reject the
      // reader's explicit fallback notice so a broken catalog cannot pass as
      // an empty creation merely because its raw partition CRC is valid.
      if (archive.notices.any(
        (notice) => notice.contains('filesystem browsing unavailable:'),
      )) {
        throw const ArchiveViewException(
          'Created DMG filesystem could not be verified.',
        );
      }
      final partitions = members
          .where((m) => m.name.startsWith('partitions/'))
          .toList();
      if (partitions.length != 1 || !partitions.single.name.endsWith('.hfs')) {
        throw const ArchiveViewException(
          'Created DMG must contain one HFSX data volume.',
        );
      }
      final partition = partitions.single;
      rawPartition = partition;
      final stem = partition.name.substring(
        'partitions/'.length,
        partition.name.length - '.hfs'.length,
      );
      final prefix = 'files/$stem/';
      members = members.where((m) => !identical(m, partition)).toList();
      for (final member in members) {
        if (!member.name.startsWith(prefix)) {
          throw const ArchiveViewException(
            'Unexpected created DMG member view.',
          );
        }
        final name = member.name.substring(prefix.length);
        if (actual.containsKey(name)) {
          throw ArchiveViewException(
            'Created disk contains duplicate paths: $name',
          );
        }
        actual[name] = member;
      }
    } else {
      for (final member in members) {
        if (actual.containsKey(member.name)) {
          throw ArchiveViewException(
            'Created disk contains duplicate paths: ${member.name}',
          );
        }
        actual[member.name] = member;
      }
    }
    if (actual.length != expected.length ||
        !expected.keys.every(actual.containsKey)) {
      throw const ArchiveViewException(
        'Created disk contents do not match the captured selection.',
      );
    }
    check();
    onVerificationPlan?.call(rawPartition?.size ?? 0);
    check();
    if (rawPartition != null) {
      // Draining is necessary: the raw-partition CRC is checked at stream end.
      await for (final chunk in controlled(
        archive.openMember(rawPartition, maxBytes: _diskLimit),
      )) {
        await checkpoint();
        await onDecodedBytes?.call(chunk.length, rawPartition.name);
        check();
      }
    }
    for (final item in expected.entries) {
      await checkpoint();
      final entry = item.value;
      final member = actual[item.key]!;
      final directory = entry?.isDirectory ?? true;
      if (member.isFile == directory ||
          member.isSpecial ||
          member.pathEscapedRoot ||
          member.isEncrypted ||
          member.size != (entry?.size ?? 0)) {
        throw ArchiveViewException(
          'Created disk member metadata differs: ${item.key}',
        );
      }
      if (entry?.modified != null) {
        final date = entry!.modified!.toUtc();
        final seconds = DateTime.utc(
          date.year,
          date.month,
          date.day,
          date.hour,
          date.minute,
          date.second,
        );
        if (member.modified?.toUtc() != seconds) {
          throw ArchiveViewException(
            'Created disk member timestamp differs: ${item.key}',
          );
        }
      }
      if (entry?.mode != null) {
        final mode = (entry!.mode! & 0xfff) | (directory ? 0x4000 : 0x8000);
        if (member.posixMode != mode) {
          throw ArchiveViewException(
            'Created disk member mode differs: ${item.key}',
          );
        }
      }
      if (directory) continue;
      Stream<List<int>> checked(
        Stream<List<int>> input, {
        bool decoded = false,
      }) async* {
        await for (final chunk in controlled(input)) {
          await checkpoint();
          yield chunk;
          if (decoded) {
            await onDecodedBytes?.call(chunk.length, item.key);
            check();
          }
        }
        check();
      }

      final before = await sha256.bind(checked(entry!.openRead())).single;
      final after = await sha256
          .bind(
            checked(
              archive.openMember(member, maxBytes: _diskLimit),
              decoded: true,
            ),
          )
          .single;
      if (before != after) {
        throw ArchiveViewException(
          'Created disk member content differs: ${item.key}',
        );
      }
    }
    check();
  } finally {
    if (archive != null) {
      await archive.close();
    } else {
      await source.close();
    }
  }
}
