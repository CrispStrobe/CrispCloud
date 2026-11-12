import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'archive_member_index.dart';
import 'archive_types.dart';

enum ArchiveIntegrityStatus { checked, failed, skipped, directory }

enum ArchiveIntegritySkipReason {
  unsafePath,
  specialEntry,
  memberLimit,
  totalLimit,
  passwordRequired,
}

enum ArchiveIntegrityStopReason { cancelled, unavailable }

class ArchiveIntegrityEntry {
  const ArchiveIntegrityEntry({
    required this.member,
    required this.status,
    this.sha256,
    this.skipReason,
    this.detail,
  });

  final ViewerArchiveMember member;
  final ArchiveIntegrityStatus status;
  final String? sha256;
  final ArchiveIntegritySkipReason? skipReason;
  final String? detail;
}

class ArchiveIntegrityProgress {
  const ArchiveIntegrityProgress({
    required this.completedEntries,
    required this.totalEntries,
    required this.bytesRead,
    this.memberName,
  });

  final int completedEntries;
  final int totalEntries;
  final int bytesRead;
  final String? memberName;
}

/// A report about one already-opened snapshot, never a publisher-authenticity
/// verdict. Readers check available stored checksums as they decode; some
/// formats have no payload checksums. Calculated hashes are useful evidence for
/// comparison, not an independent expected digest.
class ArchiveIntegrityReport {
  ArchiveIntegrityReport({
    required this.formatName,
    required this.totalEntries,
    required List<ArchiveIntegrityEntry> entries,
    required this.bytesRead,
    required this.maxMemberBytes,
    required this.maxTotalBytes,
    required List<String> notices,
    this.namespaceIssue,
    this.stopReason,
  }) : entries = List.unmodifiable(entries),
       notices = List.unmodifiable(notices);

  final String formatName;
  final int totalEntries;
  final List<ArchiveIntegrityEntry> entries;
  final int bytesRead;
  final int maxMemberBytes;
  final int maxTotalBytes;
  final List<String> notices;
  final String? namespaceIssue;
  final ArchiveIntegrityStopReason? stopReason;

  int _count(ArchiveIntegrityStatus status) =>
      entries.where((entry) => entry.status == status).length;
  int get checkedCount => _count(ArchiveIntegrityStatus.checked);
  int get failedCount => _count(ArchiveIntegrityStatus.failed);
  int get skippedCount => _count(ArchiveIntegrityStatus.skipped);
  int get directoryCount => _count(ArchiveIntegrityStatus.directory);
  int get unprocessedCount => totalEntries - entries.length;

  bool get allRegularMembersChecked =>
      stopReason == null &&
      unprocessedCount == 0 &&
      failedCount == 0 &&
      skippedCount == 0 &&
      namespaceIssue == null;
}

/// Tests regular members sequentially without retaining their decoded content.
/// Owns neither the archive nor its storage. Cancellation is cooperative between
/// chunks/reads; existing buffered codecs may finish a bounded decode first.
/// A member's declared size is charged before reading, even on failure, so an
/// unreadable member cannot release the work budget for repeated retries.
Future<ArchiveIntegrityReport> checkArchiveIntegrity(
  ViewerArchive archive, {
  int? maxMemberBytes,
  int? maxTotalBytes,
  int maxEntries = 200000,
  bool Function()? isCancelled,
  bool Function()? isCurrent,
  void Function(ArchiveIntegrityProgress progress)? onProgress,
}) async {
  maxMemberBytes ??= archive.maxStreamingMemberBytes;
  maxTotalBytes ??= archive.maxStreamingMemberBytes > kArchiveReadLimit
      ? archive.maxStreamingMemberBytes
      : 256 * 1024 * 1024;
  if (maxMemberBytes <= 0 || maxTotalBytes <= 0 || maxEntries <= 0) {
    throw ArgumentError('Archive check limits must be positive.');
  }
  if (archive.members.length > maxEntries) {
    throw const ArchiveViewException(
      'Archive exceeds the integrity check member limit.',
    );
  }
  final entries = <ArchiveIntegrityEntry>[];
  var bytesRead = 0, chargedBytes = 0;
  String? namespaceIssue;
  ArchiveIntegrityStopReason? stopReason;

  ArchiveIntegrityStopReason? stopped() {
    if (isCancelled?.call() ?? false) {
      return ArchiveIntegrityStopReason.cancelled;
    }
    if (archive.isClosed || !(isCurrent?.call() ?? true)) {
      return ArchiveIntegrityStopReason.unavailable;
    }
    return null;
  }

  void progress([String? memberName]) => onProgress?.call(
    ArchiveIntegrityProgress(
      completedEntries: entries.length,
      totalEntries: archive.members.length,
      bytesRead: bytesRead,
      memberName: memberName,
    ),
  );

  stopReason = stopped();
  if (stopReason == null) {
    var nameBytes = 0, inspected = 0;
    for (final member in archive.members) {
      if (inspected++ % 128 == 0) {
        await Future<void>.delayed(Duration.zero);
        stopReason = stopped();
        if (stopReason != null) break;
      }
      // Bound the ancestor expansion in ArchiveMemberIndex before it starts.
      // Readers can legitimately list names that are too deep/long to form a
      // useful extraction namespace. Content checks can still report them.
      if (member.name.length > 4096 ||
          member.name.split('/').length > 200 ||
          (nameBytes += utf8.encode(member.name).length) > 8 * 1024 * 1024 ||
          utf8.encode(member.name).length > 4096) {
        namespaceIssue = 'Archive paths exceed the check namespace limits (4096 UTF-8 bytes per path, 200 levels, 8 MiB total).';
        break;
      }
    }
    if (namespaceIssue == null && stopReason == null) {
      try {
        ArchiveMemberIndex(archive);
      } on ArchiveViewException catch (error) {
        // Testing content remains useful even when the namespace is unsuitable
        // for pane navigation or extraction. Never mark that report successful.
        namespaceIssue = error.toString();
      }
    }
  }
  progress();
  for (final member in archive.members) {
    // Yield to the event loop even for long runs of empty/skipped members.
    await Future<void>.delayed(Duration.zero);
    stopReason = stopped();
    if (stopReason != null) break;

    ArchiveIntegritySkipReason? skip;
    if (member.pathEscapedRoot) {
      skip = ArchiveIntegritySkipReason.unsafePath;
    } else if (member.isSpecial) {
      skip = ArchiveIntegritySkipReason.specialEntry;
    } else if (!member.isFile) {
      entries.add(
        ArchiveIntegrityEntry(
          member: member,
          status: ArchiveIntegrityStatus.directory,
        ),
      );
      progress();
      continue;
    } else if (member.size < 0 || member.size > maxMemberBytes) {
      skip = ArchiveIntegritySkipReason.memberLimit;
    } else if (member.size > maxTotalBytes - chargedBytes) {
      skip = ArchiveIntegritySkipReason.totalLimit;
    }
    if (skip != null) {
      entries.add(
        ArchiveIntegrityEntry(
          member: member,
          status: ArchiveIntegrityStatus.skipped,
          skipReason: skip,
        ),
      );
      progress();
      continue;
    }
    chargedBytes += member.size;
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    try {
      progress(member.name);
      await for (final chunk in archive.openMember(
        member,
        maxBytes: maxMemberBytes,
      )) {
        stopReason = stopped();
        if (stopReason != null) break;
        hash.add(chunk);
        bytesRead += chunk.length;
        progress(member.name);
        await Future<void>.delayed(Duration.zero);
      }
      stopReason = stopped();
      if (stopReason != null) break;
      hash.close();
      entries.add(
        ArchiveIntegrityEntry(
          member: member,
          status: ArchiveIntegrityStatus.checked,
          sha256: digest.value!.toString(),
        ),
      );
    } on ArchivePasswordRequiredException catch (error) {
      stopReason = stopped();
      if (stopReason != null) break;
      entries.add(
        ArchiveIntegrityEntry(
          member: member,
          status: error.wrongPassword
              ? ArchiveIntegrityStatus.failed
              : ArchiveIntegrityStatus.skipped,
          skipReason: error.wrongPassword
              ? null
              : ArchiveIntegritySkipReason.passwordRequired,
          detail: error.toString(),
        ),
      );
    } catch (error) {
      stopReason = stopped();
      if (stopReason != null) break;
      entries.add(
        ArchiveIntegrityEntry(
          member: member,
          status: ArchiveIntegrityStatus.failed,
          detail: error.toString(),
        ),
      );
    } finally {
      // Digest converters retain no decoded member buffers. Close partial
      // conversions too, but never expose their digest as a successful result.
      if (digest.value == null) hash.close();
    }
    progress();
  }
  progress();
  return ArchiveIntegrityReport(
    formatName: archive.formatName,
    totalEntries: archive.members.length,
    entries: entries,
    bytesRead: bytesRead,
    maxMemberBytes: maxMemberBytes,
    maxTotalBytes: maxTotalBytes,
    notices: archive.notices,
    namespaceIssue: namespaceIssue,
    stopReason: stopReason,
  );
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
