import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'archive_format_registry.dart';
import 'archive_member_index.dart';
import 'archive_service.dart';
import 'archive_source_cleanup_stub.dart'
    if (dart.library.io) 'archive_source_cleanup_io.dart'
    as native;
import 'archive_viewer_file.dart';
import 'archive_viewer_service.dart';
import 'archive_volume_backend.dart';
import 'archive_volume_source.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'file_selection_pattern.dart';
import 'local_file_service.dart';
import 'read_only_operation_backend.dart';
import 'viewer_spool.dart';

enum ArchiveExtractionFolderMode { perArchive, shared, smart }

enum ArchiveBatchExtractionStatus { completed, failed, cancelled, skipped }

enum ArchiveBatchExtractionStopReason { failed, cancelled, unavailable }

enum ArchiveBatchExtractionSkipReason {
  directory,
  symbolicLink,
  duplicate,
  passwordDeclined,
  noMatches,
}

typedef ArchiveExtractionPasswordRequest = Future<String?> Function(
  FileItem file, {
  required bool wrongPassword,
});

class ArchiveBatchExtractionOptions {
  const ArchiveBatchExtractionOptions({
    this.folderMode = ArchiveExtractionFolderMode.perArchive,
    this.mask = '*',
    this.matchFullPath = false,
    this.caseSensitive = false,
    this.flatten = false,
  });
  final ArchiveExtractionFolderMode folderMode;
  final String mask;
  final bool matchFullPath, caseSensitive;

  /// Places regular files by basename. Explicit and empty directories are
  /// omitted; every resulting basename is checked for collisions in preview.
  final bool flatten;
}

class ArchiveBatchExtractionEntry {
  const ArchiveBatchExtractionEntry({
    required this.archiveFile,
    required this.memberPath,
    required this.destination,
    required this.relativePath,
    required this.size,
    required this.isDirectory,
  });
  final FileItem archiveFile;
  final String memberPath, destination, relativePath;
  final int size;
  final bool isDirectory;
}

class ArchiveBatchExtractionSkip {
  const ArchiveBatchExtractionSkip(this.file, this.reason);
  final FileItem file;
  final ArchiveBatchExtractionSkipReason reason;
}

class ArchiveBatchExtractionProgress {
  const ArchiveBatchExtractionProgress({
    required this.preparing,
    required this.completedArchives,
    required this.totalArchives,
    this.currentFile,
    this.completedMembers = 0,
    this.totalMembers = 0,
    this.publishedFiles = 0,
  });
  final bool preparing;
  final int completedArchives, totalArchives, completedMembers, totalMembers;
  final int publishedFiles;
  final FileItem? currentFile;
}

class ArchiveBatchExtractionItem {
  ArchiveBatchExtractionItem({
    required this.file,
    required this.status,
    List<String> publishedFiles = const [],
    this.completedEntries = 0,
    this.snapshotSha256,
    this.skipReason,
    this.detail,
  }) : publishedFiles = List<String>.unmodifiable(publishedFiles);
  final FileItem file;
  final ArchiveBatchExtractionStatus status;
  final List<String> publishedFiles;
  final int completedEntries;
  final String? snapshotSha256, detail;
  final ArchiveBatchExtractionSkipReason? skipReason;
}

class ArchiveBatchExtractionReport {
  ArchiveBatchExtractionReport({
    required this.totalArchives,
    required List<ArchiveBatchExtractionItem> items,
    this.stopReason,
    this.detail,
  }) : items = List<ArchiveBatchExtractionItem>.unmodifiable(items);
  final int totalArchives;
  final List<ArchiveBatchExtractionItem> items;
  final ArchiveBatchExtractionStopReason? stopReason;
  final String? detail;
  int get completedCount => items
      .where((item) => item.status == ArchiveBatchExtractionStatus.completed)
      .length;
  int get skippedCount => items
      .where((item) => item.status == ArchiveBatchExtractionStatus.skipped)
      .length;
  int get publishedFileCount =>
      items.fold(0, (total, item) => total + item.publishedFiles.length);
  int get unprocessedCount => totalArchives - items.length;
}

/// A reviewable extraction plan retaining immutable archive snapshots.
///
/// Preparing never writes to the destination. All selected output paths are
/// checked together, including implicit directories, case aliases and existing
/// files. A failed preview releases every snapshot. A successful plan owns its
/// snapshots until extraction finishes or [close] is called. Passwords are used
/// only in live readers; none enter preview entries, fingerprints or reports.
///
/// Execution is sequential and stops on the first error, cancellation or loss
/// of the captured source account. Each file uses ArchiveService's verified
/// private staging and exclusive publication. Completed files remain in place;
/// an active failed stage is discarded. No source archive is changed/deleted.
class ArchiveBatchExtractionPlan {
  ArchiveBatchExtractionPlan._({
    required this.source,
    required this._identity,
    required this._storageId,
    required this.files,
    required this.targetDirectory,
    required this.options,
    required this.entries,
    required this.skipped,
    required this.inputBytes,
    required this.outputBytes,
    required this._archives,
    required this._local,
    required this.maxOutputBytes,
    required this._protectedPaths,
  });

  static const maxArchives = 128;
  static const maxEntries = 200000;
  static const maxPathBytes = 16 * 1024 * 1024;

  final FileOperationBackend source;
  final Object _identity;
  final String? _storageId;
  final List<FileItem> files;
  final String targetDirectory;
  final ArchiveBatchExtractionOptions options;
  final List<ArchiveBatchExtractionEntry> entries;
  final List<ArchiveBatchExtractionSkip> skipped;
  final int inputBytes, outputBytes, maxOutputBytes;
  final List<_PreparedArchive> _archives;
  final LocalFileService _local;
  final Set<String> _protectedPaths;
  bool _closed = false, _started = false;
  Future<void>? _closing;
  Completer<void>? _activeExtraction;

  bool get isClosed => _closed;
  bool get isCurrent =>
      !_closed &&
      source.isCurrent &&
      source.identity == _identity &&
      source.persistentStorageId == _storageId;

  static Future<ArchiveBatchExtractionPlan> prepare({
    required FileOperationBackend source,
    required List<FileItem> files,
    required String targetDirectory,
    ArchiveBatchExtractionOptions options =
        const ArchiveBatchExtractionOptions(),
    ArchiveExtractionPasswordRequest? requestPassword,
    bool Function()? isCancelled,
    void Function(ArchiveBatchExtractionProgress progress)? onProgress,
    LocalFileService? local,
    int maxInputBytes = kArchiveStreamingLimit,
    int maxOutputBytes = kArchiveStreamingLimit,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Batch extraction requires a local native destination.',
      );
    }
    if (files.isEmpty || files.length > maxArchives) {
      throw const ArchiveViewException(
        'Select between 1 and 128 archives for extraction.',
      );
    }
    if (maxInputBytes <= 0 ||
        maxInputBytes > kArchiveStreamingLimit ||
        maxOutputBytes <= 0 ||
        maxOutputBytes > kArchiveStreamingLimit) {
      throw ArgumentError('Invalid batch extraction limits.');
    }
    if (targetDirectory.trim().isEmpty) {
      throw const ArchiveViewException('Choose a local destination folder.');
    }
    final matcher = FileSelectionPattern(
      options.mask,
      caseSensitive: options.caseSensitive,
      matchFullPath: options.matchFullPath,
    );
    final captured = List<FileItem>.unmodifiable(files.map(_captureFile));
    final identity = source.identity;
    final storageId = source.persistentStorageId;
    void check() {
      if (isCancelled?.call() ?? false) throw const _Cancelled();
      if (!source.isCurrent ||
          source.identity != identity ||
          source.persistentStorageId != storageId) {
        throw const ArchiveViewException(
          'The captured archive source is no longer available.',
        );
      }
    }

    final root = p.normalize(p.absolute(targetDirectory));
    final service = local ?? LocalFileService();
    final destination = LocalOperationBackend(service, isCurrent: () => true);
    final archives = <_PreparedArchive>[];
    final skipped = <ArchiveBatchExtractionSkip>[];
    final seen = <String>{}, folderKeys = <String>{};
    final protected = <String>{};
    final namespace = <String, bool>{};
    final entries = <ArchiveBatchExtractionEntry>[];
    var inputBytes = 0, outputBytes = 0, pathBytes = 0;
    _OpenedArchive? pending;
    try {
      for (
        var archiveIndex = 0;
        archiveIndex < captured.length;
        archiveIndex++
      ) {
        check();
        final file = captured[archiveIndex];
        onProgress?.call(
          ArchiveBatchExtractionProgress(
            preparing: true,
            completedArchives: archiveIndex,
            totalArchives: captured.length,
            currentFile: file,
          ),
        );
        check();
        final skip = file.isFolder
            ? ArchiveBatchExtractionSkipReason.directory
            : file.isSymlink == true
            ? ArchiveBatchExtractionSkipReason.symbolicLink
            : file.path != null && !seen.add(source.pathKey(file.path!))
            ? ArchiveBatchExtractionSkipReason.duplicate
            : null;
        if (skip != null) {
          skipped.add(ArchiveBatchExtractionSkip(file, skip));
          continue;
        }
        if (file.path == null) {
          throw const ArchiveViewException(
            'An archive has no captured source path.',
          );
        }
        if (file.storageId != null && file.storageId != storageId) {
          throw const ArchiveViewException(
            'The selected archive belongs to another storage account.',
          );
        }
        if (inputBytes >= maxInputBytes) {
          throw const ArchiveViewException(
            'Batch archive snapshots exceed the input limit.',
          );
        }
        bool selected(ViewerArchiveMember member) {
          if (member.name == '/' && !member.isFile) return false;
          final path = ArchiveService.safeMemberPath(member.name);
          return (!options.flatten || member.isFile) &&
              matcher.matches(
                FileItem(
                  name: p.posix.basename(path),
                  path: path,
                  isFolder: !member.isFile,
                ),
              );
        }

        pending = await _openCaptured(
          source,
          file,
          maxInputBytes - inputBytes,
          check: check,
          isCancelled: isCancelled,
          requestPassword: requestPassword,
          selected: selected,
        );
        check();
        if (pending == null) {
          skipped.add(
            ArchiveBatchExtractionSkip(
              file,
              ArchiveBatchExtractionSkipReason.passwordDeclined,
            ),
          );
          continue;
        }
        final opened = pending;
        final index = ArchiveMemberIndex(opened.archive);
        final chosen = index.members.entries
            .where((entry) => selected(entry.value))
            .toList();
        if (chosen.isEmpty) {
          skipped.add(
            ArchiveBatchExtractionSkip(
              file,
              ArchiveBatchExtractionSkipReason.noMatches,
            ),
          );
          await opened.close();
          pending = null;
          continue;
        }
        var prefix = '';
        final roots = chosen.map((entry) => entry.key.split('/').first).toSet();
        final needsFolder =
            options.folderMode == ArchiveExtractionFolderMode.perArchive ||
            options.folderMode == ArchiveExtractionFolderMode.smart &&
                (options.flatten || roots.length != 1);
        if (needsFolder) {
          prefix = _folderName(file.name);
          if (!folderKeys.add(destination.pathKey(p.join(root, prefix)))) {
            throw ArchiveViewException(
              'Two archives would use the same output folder: $prefix',
            );
          }
        }
        final mapped = <_MappedMember>[];
        var archiveBytes = 0;
        for (final member in chosen) {
          check();
          final relative = [
            if (prefix.isNotEmpty) prefix,
            options.flatten ? p.posix.basename(member.key) : member.key,
          ].join('/');
          final target = p.joinAll([root, ...relative.split('/')]);
          final componentBytes = relative
              .split('/')
              .map((value) => utf8.encode(value).length);
          if (utf8.encode(target).length > 4096 ||
              componentBytes.any((length) => length > 255) ||
              componentBytes.length > 64) {
            throw ArchiveViewException(
              'An extraction path exceeds the supported local path bounds: $relative',
            );
          }
          final key = destination.pathKey(target);
          final isFile = member.value.isFile;
          if (namespace.containsKey(key)) {
            if (!isFile && namespace[key] == false) continue;
            throw ArchiveViewException('Batch destinations collide: $target');
          }
          var ancestor = p.dirname(target);
          while (p.isWithin(root, ancestor)) {
            final ancestorKey = destination.pathKey(ancestor);
            if (namespace[ancestorKey] == true) {
              throw ArchiveViewException(
                'A batch file occupies a destination directory: $ancestor',
              );
            }
            namespace.putIfAbsent(ancestorKey, () => false);
            ancestor = p.dirname(ancestor);
          }
          namespace[key] = isFile;
          if (member.value.size < 0 ||
              !isFile && member.value.size != 0 ||
              member.value.size > opened.archive.maxStreamingMemberBytes) {
            throw ArchiveViewException(
              'An archive member exceeds its extraction profile: ${member.key}',
            );
          }
          archiveBytes += isFile ? member.value.size : 0;
          outputBytes += isFile ? member.value.size : 0;
          if (outputBytes > maxOutputBytes ||
              opened.archive.maxStreamingMemberBytes <= kArchiveReadLimit &&
                  archiveBytes > ArchiveService.maxExtractedBytes) {
            throw const ArchiveViewException(
              'Selected archive contents exceed the extraction limit.',
            );
          }
          pathBytes +=
              utf8.encode(target).length + utf8.encode(member.key).length;
          if (entries.length >= maxEntries ||
              namespace.length > maxEntries ||
              pathBytes > maxPathBytes) {
            throw const ArchiveViewException(
              'Batch extraction preview exceeds its member/path limit.',
            );
          }
          final preview = ArchiveBatchExtractionEntry(
            archiveFile: file,
            memberPath: member.key,
            destination: target,
            relativePath: relative,
            size: member.value.size,
            isDirectory: !isFile,
          );
          entries.add(preview);
          mapped.add(_MappedMember(opened.archive, member.value, preview));
        }
        inputBytes += opened.inputBytes;
        if (source is LocalOperationBackend) {
          protected.addAll(
            opened.sourcePaths.map((path) => p.normalize(p.absolute(path))),
          );
        }
        archives.add(_PreparedArchive(file, opened, mapped));
        pending = null;
      }
      check();
      final plan = ArchiveBatchExtractionPlan._(
        source: source,
        identity: identity,
        storageId: storageId,
        files: captured,
        targetDirectory: root,
        options: options,
        entries: List.unmodifiable(entries),
        skipped: List.unmodifiable(skipped),
        inputBytes: inputBytes,
        outputBytes: outputBytes,
        archives: archives,
        local: service,
        maxOutputBytes: maxOutputBytes,
        protectedPaths: Set.unmodifiable(protected),
      );
      final all = plan._view(archives.expand((archive) => archive.members));
      try {
        await ArchiveService.extractOpenedSnapshot(
          all,
          root,
          local: service,
          maxTotalBytes: maxOutputBytes,
          validateOnly: true,
          protectedSourcePaths: protected,
          isCancelled: isCancelled,
          checkSource: () async => check(),
        );
        check();
      } finally {
        await all.close();
      }
      onProgress?.call(
        ArchiveBatchExtractionProgress(
          preparing: true,
          completedArchives: captured.length,
          totalArchives: captured.length,
        ),
      );
      check();
      return plan;
    } catch (error, stack) {
      try {
        await pending?.close();
      } catch (_) {}
      for (final archive in archives) {
        try {
          await archive.opened.close();
        } catch (_) {}
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  ViewerArchive _view(Iterable<_MappedMember> selected) {
    final mapped = selected.toList(growable: false);
    final owners = <ViewerArchiveMember, _MappedMember>{};
    final members = <ViewerArchiveMember>[];
    for (var index = 0; index < mapped.length; index++) {
      final original = mapped[index].member;
      final member = ViewerArchiveMember(
        name: mapped[index].preview.relativePath,
        size: original.size,
        isFile: original.isFile,
        isEncrypted: original.isEncrypted,
        pathEscapedRoot: false,
        index: index,
        modified: original.modified,
        posixMode: original.posixMode,
      );
      owners[member] = mapped[index];
      members.add(member);
    }
    void check() {
      if (!isCurrent) {
        throw const ArchiveViewException(
          'The captured extraction plan is no longer available.',
        );
      }
    }

    return ViewerArchive.reader(
      formatName: 'extraction-plan',
      members: members,
      maxStreamingMemberBytes: maxOutputBytes,
      read: (member, limit) async {
        check();
        final selected = owners[member]!;
        final bytes = await selected.archive.readMember(
          selected.member,
          maxBytes: limit,
        );
        check();
        return bytes;
      },
      streamReader: (member, chunkSize) async* {
        check();
        final selected = owners[member]!;
        final archive = selected.archive;
        await for (final chunk in archive.openMember(
          selected.member,
          maxBytes: archive.maxStreamingMemberBytes,
          chunkSize: chunkSize,
        )) {
          check();
          yield chunk;
        }
        check();
      },
      close: () async {},
    );
  }

  Future<ArchiveBatchExtractionReport> extract({
    bool Function()? isCancelled,
    void Function(ArchiveBatchExtractionProgress progress)? onProgress,
  }) async {
    if (_started || _closed) {
      throw StateError('This extraction plan already ran or was closed.');
    }
    _started = true;
    final active = Completer<void>();
    _activeExtraction = active;
    final items = <ArchiveBatchExtractionItem>[
      for (final skip in skipped)
        ArchiveBatchExtractionItem(
          file: skip.file,
          status: ArchiveBatchExtractionStatus.skipped,
          skipReason: skip.reason,
        ),
    ];
    ArchiveBatchExtractionStopReason? reason;
    String? batchFailure;
    ArchiveBatchExtractionStopReason? stopped() =>
        isCancelled?.call() == true || _closed
        ? ArchiveBatchExtractionStopReason.cancelled
        : !isCurrent
        ? ArchiveBatchExtractionStopReason.unavailable
        : null;
    var publishedCount = 0;
    try {
      reason = stopped();
      if (reason == null) {
        final all = _view(_archives.expand((archive) => archive.members));
        try {
          await ArchiveService.extractOpenedSnapshot(
            all,
            targetDirectory,
            local: _local,
            maxTotalBytes: maxOutputBytes,
            validateOnly: true,
            protectedSourcePaths: _protectedPaths,
            isCancelled: () => stopped() != null,
            checkSource: () async {
              if (stopped() != null) throw const _Cancelled();
            },
          );
        } finally {
          await all.close();
        }
      }
      for (final archive in _archives) {
        reason = stopped();
        if (reason != null) break;
        final published = <String>[];
        var completed = 0;
        String? failure;
        final view = _view(archive.members);
        try {
          await ArchiveService.extractOpenedSnapshot(
            view,
            targetDirectory,
            local: _local,
            maxTotalBytes: maxOutputBytes,
            protectedSourcePaths: _protectedPaths,
            isCancelled: () => stopped() != null,
            checkSource: () async {
              if (stopped() != null) throw const _Cancelled();
            },
            onFilePublished: (path) {
              published.add(path);
              publishedCount++;
            },
            onProgress: (done, total) {
              completed = done;
              onProgress?.call(
                ArchiveBatchExtractionProgress(
                  preparing: false,
                  completedArchives: items.length,
                  totalArchives: files.length,
                  currentFile: archive.file,
                  completedMembers: done,
                  totalMembers: total,
                  publishedFiles: publishedCount,
                ),
              );
            },
          );
        } catch (error) {
          failure = _detail(error);
        } finally {
          await view.close();
        }
        reason = stopped();
        final status = failure == null && completed == archive.members.length
            ? ArchiveBatchExtractionStatus.completed
            : reason != null
            ? ArchiveBatchExtractionStatus.cancelled
            : ArchiveBatchExtractionStatus.failed;
        items.add(
          ArchiveBatchExtractionItem(
            file: archive.file,
            status: status,
            publishedFiles: published,
            completedEntries: completed,
            snapshotSha256: archive.opened.fingerprint,
            detail: failure,
          ),
        );
        if (status == ArchiveBatchExtractionStatus.failed) {
          reason = ArchiveBatchExtractionStopReason.failed;
        }
        onProgress?.call(
          ArchiveBatchExtractionProgress(
            preparing: false,
            completedArchives: items.length,
            totalArchives: files.length,
            publishedFiles: publishedCount,
          ),
        );
        if (reason != null) break;
      }
      reason ??= stopped();
    } catch (error) {
      reason = stopped() ?? ArchiveBatchExtractionStopReason.failed;
      batchFailure = _detail(error);
    } finally {
      _closed = true;
      try {
        await _disposeSnapshots();
      } finally {
        _activeExtraction = null;
        active.complete();
      }
    }
    final order = Map<FileItem, int>.identity();
    for (var index = 0; index < files.length; index++) {
      order[files[index]] = index;
    }
    items.sort(
      (first, second) => order[first.file]!.compareTo(order[second.file]!),
    );
    return ArchiveBatchExtractionReport(
      totalArchives: files.length,
      items: items,
      stopReason: reason,
      detail: batchFailure,
    );
  }

  Future<void> close() {
    _closed = true;
    // An extraction still owns any pending native reads, staged writes and
    // publication checks. Closing requests cancellation immediately, then lets
    // that owner drain before its finally disposes the captured input files.
    return _activeExtraction?.future ?? _disposeSnapshots();
  }

  Future<void> _disposeSnapshots() => _closing ??= () async {
    for (final archive in _archives) {
      try {
        await archive.opened.close();
      } catch (_) {
        // Other snapshots still need release; publication results stay valid.
      }
    }
  }();
}

class _PreparedArchive {
  _PreparedArchive(this.file, this.opened, this.members);
  final FileItem file;
  final _OpenedArchive opened;
  final List<_MappedMember> members;
}

class _MappedMember {
  _MappedMember(this.archive, this.member, this.preview);
  final ViewerArchive archive;
  final ViewerArchiveMember member;
  final ArchiveBatchExtractionEntry preview;
}

class _OpenedArchive {
  _OpenedArchive(
    this.archive,
    this.fingerprint,
    this.inputBytes,
    this.sourcePaths,
    this._close,
  );
  final ViewerArchive archive;
  final String fingerprint;
  final int inputBytes;
  final List<String> sourcePaths;
  final Future<void> Function() _close;
  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _close();
  }
}

Future<_OpenedArchive?> _openCaptured(
  FileOperationBackend source,
  FileItem selectedFile,
  int remaining, {
  required void Function() check,
  required bool Function(ViewerArchiveMember member) selected,
  bool Function()? isCancelled,
  ArchiveExtractionPasswordRequest? requestPassword,
}) async {
  ViewerSpool? spool;
  ViewerArchive? archive;
  String? password, fingerprint;
  var attempts = 0;
  var declined = false;
  Future<bool> ask(bool wrong) async {
    if (requestPassword == null) {
      declined = true;
      return false;
    }
    if (attempts >= 3) return false;
    check();
    password = await requestPassword(selectedFile, wrongPassword: wrong);
    check();
    if (password == null) {
      declined = true;
      return false;
    }
    attempts++;
    return true;
  }

  try {
    check();
    final guard = _CaptureGuard(check);
    final observed = await guard.wait(() => source.stat(selectedFile.path!));
    check();
    if (!_sameSelection(selectedFile, observed)) throw _changed();
    final file = _captureFile(observed!);
    if (file.size == null || file.size! < 0 || file.size! > remaining) {
      throw const ArchiveViewException(
        'Archive input has an unknown size or exceeds the batch limit.',
      );
    }
    final split = sevenZipVolumeBaseName(file.name) != null;
    if (!split) {
      final witness = await native.captureNativeArchiveImportSource(
        source,
        file,
      );
      check();
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      try {
        spool = await createViewerSpool(
          _HashingBackend(source, hash, check),
          file,
          maxBytes: remaining,
          isCancelled: isCancelled,
        );
      } finally {
        hash.close();
      }
      check();
      await native.verifyNativeArchiveImportSource(source, file, witness);
      check();
      if (!_sameSnapshot(
        file,
        await guard.wait(() => source.stat(file.path!)),
      )) {
        throw _changed();
      }
      check();
      fingerprint = digest.value!.toString();
    }
    while (true) {
      check();
      ArchiveVolumeOpen? volumes;
      try {
        if (split) {
          volumes = await openSevenZipVolumeArchive(
            source,
            file,
            password: password,
            maxInputBytes: remaining,
            isCancelled: isCancelled,
            onSnapshotCaptured: (hash) {
              check();
              if (fingerprint != null && fingerprint != hash) throw _changed();
              fingerprint = hash;
            },
          );
          archive = volumes.archive;
        } else {
          archive = await openViewerArchiveFile(
            spool!.path,
            name: file.name,
            password: password,
            streaming: true,
            isCancelled: isCancelled,
          );
        }
        check();
        ArchiveMemberIndex(archive);
        final encrypted = archive.members
            .where(
              (member) =>
                  member.isFile && member.isEncrypted && selected(member),
            )
            .toList();
        if (encrypted.isNotEmpty && password == null) {
          await archive.close();
          archive = null;
          if (await ask(false)) continue;
          return null;
        }
        if (encrypted.isNotEmpty) {
          // Probe a selected encrypted member before review. Mixed per-entry
          // passwords may still fail later; publication verifies every member.
          await for (final _ in archive.openMember(
            encrypted.first,
            maxBytes: archive.maxStreamingMemberBytes,
          )) {
            check();
          }
          check();
        }
        final opened = archive;
        final retainedSpool = spool;
        archive = null;
        spool = null;
        return _OpenedArchive(
          opened,
          fingerprint!,
          volumes?.parts.fold<int>(0, (sum, part) => sum + part.size!) ??
              file.size!,
          volumes?.parts.map((part) => part.path!).toList() ?? [file.path!],
          () async {
            try {
              await opened.close();
            } finally {
              await retainedSpool?.close();
            }
          },
        );
      } on ArchivePasswordRequiredException catch (error) {
        await archive?.close();
        archive = null;
        if (await ask(error.wrongPassword || attempts > 0)) continue;
        if (declined) return null;
        throw const ArchiveViewException('The archive password was rejected.');
      } on ArchiveViewException catch (error) {
        await archive?.close();
        archive = null;
        if (password != null &&
            (error.code == ArchiveMessageCode.corrupt ||
                error.code == ArchiveMessageCode.readEntry)) {
          if (await ask(true)) continue;
          if (declined) return null;
        }
        rethrow;
      }
    }
  } finally {
    password = null;
    try {
      await archive?.close();
    } finally {
      await spool?.close();
    }
  }
}

class _HashingBackend extends ReadOnlyOperationBackend {
  _HashingBackend(super.source, this.hash, this.check)
    : super(
        isAvailable: () {
          try {
            check();
            return true;
          } catch (_) {
            return false;
          }
        },
      );
  final ByteConversionSink hash;
  final void Function() check;
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    await for (final chunk in super.readFile(file)) {
      check();
      if (chunk is! Uint8List &&
          chunk.any((value) => value < 0 || value > 255)) {
        throw const ArchiveViewException(
          'An archive source returned invalid bytes.',
        );
      }
      hash.add(chunk);
      yield chunk;
    }
  }
}

const _revisionKeys = [
  'etag',
  'eTag',
  'version',
  'versionId',
  'revision',
  'rev',
  'cTag',
  'rangeReadSnapshot',
];
FileItem _captureFile(FileItem file) => FileItem(
  name: file.name,
  path: file.path,
  uuid: file.uuid,
  storageId: file.storageId,
  isFolder: file.isFolder,
  size: file.size,
  updatedAt: file.updatedAt,
  isSymlink: file.isSymlink,
  symlinkTarget: file.symlinkTarget,
  metadata: Map<String, dynamic>.unmodifiable({
    for (final key in _revisionKeys)
      if (file.metadata?.containsKey(key) ?? false)
        key: _revision(file.metadata![key]),
  }),
);
Object? _revision(Object? value) {
  if (value == null ||
      value is String ||
      value is num ||
      value is bool ||
      value is DateTime) {
    return value;
  }
  throw const ArchiveViewException(
    'Archive version metadata cannot be captured.',
  );
}

bool _sameSelection(FileItem before, FileItem? after) =>
    after != null &&
    !after.isFolder &&
    after.isSymlink != true &&
    before.path == after.path &&
    before.name == after.name &&
    (before.uuid == null || before.uuid == after.uuid) &&
    (before.storageId == null ||
        after.storageId == null ||
        before.storageId == after.storageId) &&
    (before.size == null || before.size == after.size) &&
    (before.updatedAt == null || before.updatedAt == after.updatedAt) &&
    _revisionKeys.every(
      (key) =>
          !before.metadata!.containsKey(key) ||
          before.metadata?[key] == after.metadata?[key],
    );
bool _sameSnapshot(FileItem before, FileItem? after) =>
    _sameSelection(before, after) &&
    before.size == after!.size &&
    before.uuid == after.uuid &&
    before.storageId == after.storageId &&
    before.updatedAt == after.updatedAt &&
    _revisionKeys.every((key) => before.metadata?[key] == after.metadata?[key]);
String _folderName(String name) {
  var base = sevenZipVolumeBaseName(name) ?? name;
  final suffixes = archiveFormatForName(base)?.suffixes ?? const <String>[];
  final matching =
      suffixes.where((suffix) => base.toLowerCase().endsWith(suffix)).toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  if (matching.isNotEmpty) {
    base = base.substring(0, base.length - matching.first.length);
  }
  if (base.isEmpty || base == '.') base = 'archive';
  return ArchiveService.safeMemberPath(base);
}

String _detail(Object error) {
  final text = error.toString();
  return text.length > 4096 ? '${text.substring(0, 4096)}…' : text;
}

ArchiveViewException _changed() => const ArchiveViewException(
  'The selected archive changed while being captured.',
);

class _Cancelled implements Exception {
  const _Cancelled();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest value) => this.value = value;
  @override
  void close() {}
}

class _CaptureGuard {
  _CaptureGuard(this.check);
  final void Function() check;
  Future<T> wait<T>(Future<T> Function() action) async {
    check();
    final result = Completer<T>();
    final elapsed = Stopwatch()..start();
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (result.isCompleted) return;
      try {
        check();
        if (elapsed.elapsed >= const Duration(minutes: 2)) {
          throw const ArchiveViewException(
            'The archive source stopped responding.',
          );
        }
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    unawaited(
      Future<T>.sync(action).then<void>(
        (value) {
          if (!result.isCompleted) result.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        },
      ),
    );
    try {
      final value = await result.future;
      check();
      return value;
    } finally {
      timer.cancel();
    }
  }
}
