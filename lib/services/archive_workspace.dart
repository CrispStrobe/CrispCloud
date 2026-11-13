import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/archive_endpoint.dart';
import 'archive_container_publisher.dart';
import 'archive_checkpoint_source.dart';
import 'archive_writer_worker.dart';
import 'archive_dmg_writer.dart' show verifyDmgRewritePreservation;
import 'archive_endpoint_policy.dart';
import 'archive_hfs_writer.dart' show normalizeHfsArchivePath;
import 'archive_iso_writer.dart'
    show kArchiveIsoSingleExtentLimit, verifyIsoRewritePreservation;
import 'archive_rar_stored_reader.dart' show openStoredRarArchive;
import 'archive_rar_stored_writer.dart' show verifyStoredRarPreservation;
import 'archive_write_model.dart';
import 'archive_writer_service.dart';
import 'archive_output_spool.dart';
import 'archive_streamed_reader.dart';
import 'archive_streaming_writer.dart';
import 'archive_zip_package_policy.dart';
import 'archive_publication_journal.dart';
import 'archive_browser_session.dart';
import 'archive_member_index.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';
import 'file_operation_service.dart';
import 'file_operation_backend.dart' show LocalOperationBackend;
import 'storage_transfer_contract.dart';

/// Legacy workspace callers catch StateError for a cancelled callback, while
/// transfer coordinators need FileOperationCancelled to distinguish a user
/// stop from an authority or source failure. Preserve both classifications.
class _ArchiveWorkspaceCancelled extends StateError
    implements FileOperationCancelled {
  _ArchiveWorkspaceCancelled(super.message);
}

class ArchiveWorkspace {
  ArchiveWorkspace._(
    this.source,
    this._file,
    this._archive,
    this._fingerprint,
    this.password,
    this._policy,
    this.journal, {
    bool streaming = false,
    ArchiveOutputSpool? snapshot,
    // ignore: prefer_initializing_formals
  }) : _streaming = streaming,
       _snapshotSpool = snapshot {
    if (snapshot != null) _ownedSpools.add(snapshot);
    _loadEntries();
  }
  final FileOperationBackend source;
  FileItem _file;
  FileItem get file => _file;
  ViewerArchive _archive;
  String _fingerprint;
  final String? password;
  ArchiveEndpointPolicy _policy;
  final ArchivePublicationJournal journal;
  final bool _streaming;
  ArchiveOutputSpool? _snapshotSpool;
  final _ownedSpools = <ArchiveOutputSpool>{};
  ArchiveWorkspaceReview? _latestReview;
  bool get supportsLargeFiles => _streaming;
  int get maxMemberBytes => !_streaming
      ? kArchiveReadLimit
      : _policy.format == ArchiveEndpointFormat.iso
      ? kArchiveIsoSingleExtentLimit
      : kArchiveStreamingLimit;
  int get maxContainerBytes =>
      _streaming ? kArchiveStreamingLimit : ArchiveService.maxArchiveBytes;
  int get maxExpandedBytes =>
      _streaming ? kArchiveStreamingLimit : ArchiveService.maxExtractedBytes;
  int get expandedBytes => _entries.values.fold<int>(
    0,
    (sum, entry) => sum + (entry.isFolder ? 0 : entry.size),
  );
  final _entries = <String, _ArchiveEntry>{};
  bool _closed = false;
  bool _requiresReopen = false;
  bool _dirty = false;
  bool _saving = false;
  int _revision = 0;
  ArchiveWorkspaceReview? _pendingReview;
  ArchivePublicationRecord? _pendingPublication;
  ArchivePublicationReceipt? _lastReceipt;
  Object? _lastPublicationWarning;
  Object? _sourceRemovalAuthority;
  Object? _directorySyncAuthority;
  ArchivePublicationDirectoryDependency? _directorySyncDependency;
  ArchiveWorkspace? _parentWorkspace;
  bool get dirty => _dirty || (_parentWorkspace?.dirty ?? false);
  bool get isCurrent => !_closed && source.isCurrent;
  String get format => _archive.formatName;
  bool get encrypted => _policy.encrypted;
  bool get encryptNames => _policy.encryptNames;
  int get revision => _revision;
  String get fingerprint => _fingerprint;
  ArchiveWorkspace get outermost => _parentWorkspace?.outermost ?? this;
  List<String> get nestedMemberPaths {
    final result = <String>[];
    ArchiveWorkspace? level = this;
    while (level?._parentWorkspace != null) {
      result.add(level!.file.path!.replaceFirst(RegExp(r'^/+'), ''));
      level = level._parentWorkspace;
    }
    return List.unmodifiable(result.reversed);
  }

  ArchivePublicationReceipt? get lastReceipt => outermost._lastReceipt;
  Object? get lastPublicationWarning => outermost._lastPublicationWarning;
  ArchivePublicationRecord? get pendingPublication =>
      outermost._pendingPublication;
  ArchiveEndpointCapabilities get endpointCapabilities =>
      ArchiveEndpointCapabilities(
        format: _policy.format,
        canPublish: canUpdate,
        encrypted: encrypted,
        encryptNames: encryptNames,
        reason: canUpdate ? null : updateSupport,
      );
  bool get canUpdate {
    if (_parentWorkspace?._policy.packageKind == 'deb') return false;
    if (_parentWorkspace?.canUpdate == false) return false;
    return _policy.reason == null &&
        _policy.format != ArchiveEndpointFormat.readOnly &&
        ArchiveContainerPublisher.unsupportedReason(outermost.source) == null;
  }

  /// Whether this workspace permits moving members between its directories.
  /// Flat AR archives and replacement-only payload/package profiles have no
  /// supported destination for this operation.
  bool get canMoveMembers =>
      canRemoveMembers && _policy.format != ArchiveEndpointFormat.ar;

  /// Whether a verified member-removal candidate can be prepared. A successful
  /// review must still retain each format's required content and protection.
  bool get canRemoveMembers =>
      canUpdate && !_policy.singlePayload && _policy.packageKind != 'deb';

  bool get canSynchronizeDirectory =>
      canRemoveMembers && _policy.format != ArchiveEndpointFormat.ar;

  String get updateSupport => _parentWorkspace?._policy.packageKind == 'deb'
      ? 'Debian payloads require an external package build workflow. Replace the prepared control and data archives together in the outer package.'
      : _parentWorkspace?.canUpdate == false
      ? 'The enclosing archive cannot be repacked. Browsing and extraction are available.'
      : _policy.reason ??
            ArchiveContainerPublisher.unsupportedReason(outermost.source) ??
            (canUpdate
                ? _policy.packageKind == 'deb'
                      ? 'Replace prepared control and data archives together. Save verifies the wrapper and present checksums; package metadata must be rebuilt externally.'
                      : _policy.singlePayload
                      ? 'Replace the one decompressed payload; its name comes from the compressed filename.'
                      : 'Edit, add, rename and delete members; save repacks the archive.'
                : 'This format supports browsing and extraction. Repacking is unavailable.');

  static Future<Uint8List> _read(
    FileOperationBackend source,
    FileItem file,
    int limit, {
    bool Function()? isCancelled,
    FileOperationControl? control,
  }) async {
    if (!source.isCurrent) throw StateError('The archive source changed.');
    if ((file.size ?? 0) > limit) {
      throw const ArchiveViewException('Archive input exceeds its size limit.');
    }
    await control?.checkpoint();
    final builder = BytesBuilder(copy: false);
    final input = source.readFile(file);
    await for (final chunk in control?.bind(input) ?? input) {
      await control?.checkpoint();
      if (!source.isCurrent) throw StateError('The archive source changed.');
      if ((control?.isCancelled ?? false) || (isCancelled?.call() ?? false)) {
        throw _ArchiveWorkspaceCancelled('Archive operation cancelled.');
      }
      if (builder.length + chunk.length > limit) {
        throw const ArchiveViewException(
          'Archive input exceeds its size limit.',
        );
      }
      builder.add(chunk);
    }
    if (!source.isCurrent) throw StateError('The archive source changed.');
    if ((control?.isCancelled ?? false) || (isCancelled?.call() ?? false)) {
      throw _ArchiveWorkspaceCancelled('Archive operation cancelled.');
    }
    return builder.takeBytes();
  }

  static bool _streamableName(String name) {
    final lower = name.toLowerCase();
    return const [
      '.zip',
      '.cbz',
      '.7z',
      '.cb7',
      '.tar',
      '.cbt',
      '.tgz',
      '.tar.gz',
      '.iso',
      '.rar',
      '.cbr',
      '.dmg',
    ].any(lower.endsWith);
  }

  /// The generic RAR reader exposes only whole-second modification times.
  /// Buffered and nested rewrites must use the same exact Store metadata as
  /// native workspaces, or a rename would be mistaken for a timestamp edit.
  static Future<ViewerArchive> _openBufferedArchive(
    Uint8List bytes, {
    required String name,
    String? password,
  }) async {
    final lower = name.toLowerCase();
    if (lower.endsWith('.rar') || lower.endsWith('.cbr')) {
      try {
        return await openStoredRarArchive(
          koni.MemoryByteSource(bytes, name: name),
          maxBytes: ArchiveService.maxArchiveBytes,
        );
      } on ArchiveStreamingUnsupported {
        // A failed Store open closes only this memory-source handle. The
        // bounded fallback gets a fresh handle and remains read-only unless
        // the independent preservation inspector understands its full profile.
      }
    }
    return openViewerArchive(bytes, name: name, password: password);
  }

  /// Captures a repeatable private snapshot without retaining file contents in
  /// the Dart heap. Both the metadata witness and the exact byte count must
  /// still match after the read; publication later checks the full digest again.
  static Future<({ArchiveOutputSpool spool, String digest})> _captureSpool(
    FileOperationBackend source,
    FileItem file, {
    required int maxBytes,
    bool Function()? isCancelled,
  }) async {
    if (file.size == null || file.size! < 0 || file.size! > maxBytes) {
      throw const ArchiveViewException(
        'Archive input exceeds its streamed limit.',
      );
    }
    if (file.size! > kArchiveReadLimit &&
        !source.capabilities.boundedDownload &&
        !(source is ArchiveOperationBackend &&
            source.workspace.supportsLargeFiles)) {
      throw const ArchiveViewException(
        'This source does not provide bounded large-file reads.',
      );
    }
    void check() {
      if (!source.isCurrent) throw StateError('The archive source changed.');
      if (isCancelled?.call() ?? false) throw const FileOperationCancelled();
    }

    check();
    final spool = await ArchiveOutputSpool.create(maxBytes: maxBytes);
    try {
      var length = 0;
      Stream<List<int>> capture() async* {
        await for (final chunk in source.readFile(file)) {
          check();
          if (chunk.length > file.size! - length) {
            throw const ArchiveViewException(
              'The captured archive input grew.',
            );
          }
          if (chunk is! Uint8List &&
              chunk.any((byte) => byte < 0 || byte > 255)) {
            throw const ArchiveViewException(
              'The captured input contains invalid bytes.',
            );
          }
          for (var at = 0; at < chunk.length; at += 256 * 1024) {
            final end = at + 256 * 1024 < chunk.length
                ? at + 256 * 1024
                : chunk.length;
            final owned = Uint8List.fromList(chunk.sublist(at, end));
            await spool.write(owned);
            length += owned.length;
            check();
            yield owned;
          }
        }
      }

      final digest = await sha256.bind(capture()).single;
      check();
      if (length != file.size ||
          !sameArchiveFile(file, await source.stat(file.path!))) {
        throw StateError('The captured archive input changed while reading.');
      }
      await spool.finish();
      return (spool: spool, digest: digest.toString());
    } catch (_) {
      await spool.dispose();
      rethrow;
    }
  }

  /// Opens a nested route through owned workspaces. Each inner save replaces
  /// its member in the parent working copy; only the outermost save reaches
  /// physical storage, through the existing conflict and verification gates.
  static Future<ArchiveWorkspace> openNested(
    FileOperationBackend source,
    FileItem file,
    List<String> nestedMembers, {
    String? password,
    List<String?>? passwords,
    String? expectedOuterFingerprint,
    ArchivePublicationJournal? journal,
  }) async {
    if (nestedMembers.length >= kArchiveNestingLimit) {
      throw const ArchiveViewException(
        'Archive nesting is limited to 8 levels.',
      );
    }
    ArchiveWorkspace workspace;
    try {
      workspace = await open(
        source,
        file,
        password: passwords == null || passwords.isEmpty
            ? password
            : passwords.first,
        expectedFingerprint: expectedOuterFingerprint,
        journal: journal,
      );
    } on ArchivePasswordRequiredException catch (error) {
      throw ArchiveNestedPasswordRequiredException(
        0,
        file.name,
        error.wrongPassword,
      );
    }
    try {
      for (var index = 0; index < nestedMembers.length; index++) {
        final memberPath = nestedMembers[index];
        final relative = workspace._safeMemberPath(memberPath);
        final backend = _NestedArchiveBackend(workspace, '/$relative');
        final member = await backend.stat('/$relative');
        if (member == null || member.isFolder) {
          throw ArchiveViewException(
            'Nested archive no longer exists: $memberPath',
          );
        }
        ArchiveWorkspace child;
        try {
          child = await open(
            backend,
            member,
            password: passwords == null
                ? password
                : index + 1 < passwords.length
                ? passwords[index + 1]
                : null,
            journal: workspace.journal,
          );
        } on ArchivePasswordRequiredException catch (error) {
          throw ArchiveNestedPasswordRequiredException(
            index + 1,
            member.name,
            error.wrongPassword,
          );
        }
        child._parentWorkspace = workspace;
        workspace = child;
      }
      return workspace;
    } catch (_) {
      await workspace.close();
      rethrow;
    }
  }

  static Future<ArchiveWorkspace> open(
    FileOperationBackend source,
    FileItem file, {
    String? password,
    String? expectedFingerprint,
    ArchivePublicationJournal? journal,
  }) async {
    if (file.path == null ||
        !source.paths.isAbsolute(file.path!) ||
        file.isFolder ||
        file.isSymlink == true) {
      throw StateError('An archive requires a captured regular file.');
    }
    final current = await source.stat(file.path!);
    if (current == null || !sameArchiveFile(file, current)) {
      throw StateError('The captured archive changed before opening.');
    }
    if (!kIsWeb &&
        source is LocalOperationBackend &&
        _streamableName(file.name)) {
      final captured = await _captureSpool(
        source,
        current,
        maxBytes: kArchiveStreamingLimit,
      );
      ViewerArchive? opened;
      try {
        if (expectedFingerprint != null &&
            captured.digest != expectedFingerprint) {
          throw StateError(
            'The archive changed since it was opened. Refresh it before editing.',
          );
        }
        final result = await openStreamedArchiveSource(
          await captured.spool.openByteSource(),
          name: file.name,
          password: password,
          maxBytes: kArchiveStreamingLimit,
        );
        opened = result.archive;
        if (!result.policy.encrypted &&
            supportsStreamingArchiveWriting(result.policy.format)) {
          return ArchiveWorkspace._(
            source,
            current,
            result.archive,
            captured.digest,
            password,
            result.policy,
            journal ?? ArchivePublicationJournal(),
            streaming: true,
            snapshot: captured.spool,
          );
        }
        // Protected small containers keep the existing password and metadata
        // preservation path. No large encrypted source is buffered as fallback.
        if (current.size! > ArchiveService.maxArchiveBytes) {
          throw const ArchiveViewException(
            'Large encrypted archive editing is not supported by this codec.',
          );
        }
        await opened.close();
        opened = null;
      } on ArchiveStreamingUnsupported {
        await opened?.close();
        if (current.size! > ArchiveService.maxArchiveBytes) {
          await captured.spool.dispose();
          rethrow;
        }
      } catch (_) {
        await opened?.close();
        await captured.spool.dispose();
        rethrow;
      }
      await captured.spool.dispose();
    }
    final bytes = await _read(source, current, ArchiveService.maxArchiveBytes);
    if (!sameArchiveFile(current, await source.stat(current.path!)) ||
        current.size != bytes.length) {
      throw StateError('The archive changed while opening.');
    }
    if (expectedFingerprint != null &&
        sha256.convert(bytes).toString() != expectedFingerprint) {
      throw StateError(
        'The archive changed since it was opened. Refresh it before editing or extracting members.',
      );
    }
    final archive = await _openBufferedArchive(
      bytes,
      name: file.name,
      password: password,
    );
    try {
      final policy = await ArchiveEndpointPolicy.inspect(
        bytes,
        file.name,
        archive,
        password,
      );
      final encrypted = archive.members.where((member) => member.isEncrypted);
      if (encrypted.isNotEmpty) {
        if (password == null) {
          throw const ArchivePasswordRequiredException(
            'Enter the archive password before editing or extracting members.',
          );
        }
        // Every original protected file must authenticate, including one that
        // the user later replaces/removes. ZIP members can use different
        // passwords; validating only the first member is insufficient.
        final files = encrypted.where((member) => member.isFile).toList();
        if (policy.reason == null) {
          if (archive.members.fold<int>(
                0,
                (sum, member) => sum + (member.isFile ? member.size : 0),
              ) >
              ArchiveService.maxExtractedBytes) {
            throw const ArchiveViewException(
              'Archive contents exceed 256 MiB.',
            );
          }
          for (final member in files) {
            if (!source.isCurrent) {
              throw StateError('The archive source changed.');
            }
            await archive.readMember(member);
          }
        } else if (files.isNotEmpty) {
          await archive.readMember(files.first);
        }
      }
      return ArchiveWorkspace._(
        source,
        current,
        archive,
        sha256.convert(bytes).toString(),
        password,
        policy,
        journal ?? ArchivePublicationJournal(),
      );
    } catch (_) {
      await archive.close();
      rethrow;
    }
  }

  void _loadEntries() {
    _entries.clear();
    for (final entry in ArchiveMemberIndex(_archive).members.entries) {
      _entries[entry.key] = _ArchiveEntry(
        entry.key,
        !entry.value.isFile,
        member: entry.value,
      );
    }
    _validateEntries(_entries, maxBytes: maxExpandedBytes);
    _revision++;
  }

  static void _validateEntries(
    Map<String, _ArchiveEntry> entries, {
    int maxBytes = ArchiveService.maxExtractedBytes,
  }) {
    if (entries.length > 200000) {
      throw const ArchiveViewException(
        'Archive exceeds the 200,000 member limit.',
      );
    }
    var total = 0;
    var pathBytes = 0;
    for (final entry in entries.values) {
      final bytes = utf8.encode(entry.name).length;
      pathBytes += bytes;
      if (bytes > 4096 ||
          entry.name.split('/').length > 200 ||
          pathBytes > 8 * 1024 * 1024) {
        throw const ArchiveViewException(
          'Archive member paths exceed their bounded limits.',
        );
      }
      if (!entry.isFolder) total += entry.size;
      if (total > maxBytes) {
        throw ArchiveViewException(
          'Archive contents exceed ${maxBytes ~/ (1024 * 1024)} MiB.',
        );
      }
      var parent = p.posix.dirname(entry.name);
      while (parent != '.' && parent != '/') {
        if (entries[parent]?.isFolder == false) {
          throw ArchiveViewException(
            'Archive file is also a directory: $parent',
          );
        }
        parent = p.posix.dirname(parent);
      }
    }
  }

  void _publish(Map<String, _ArchiveEntry> entries) {
    if (_saving || pendingPublication != null) {
      throw StateError(
        'Finish or recover the current archive publication before changing its draft.',
      );
    }
    _validateEntries(entries, maxBytes: maxExpandedBytes);
    for (final entry in entries.values) {
      final privilege = (entry.mode ?? 0) & 0xc00;
      if (privilege != 0 &&
          (entry.member == null ||
              _policy.inspection == null ||
              ((entry.member!.posixMode ?? 0) & 0xc00) != privilege)) {
        throw const ArchiveViewException(
          'Adding setuid or setgid permissions requires an ownership-preserving workflow. Existing inspected ownership and privilege bits can be retained.',
        );
      }
    }
    if (_policy.singlePayload &&
        (entries.length != 1 ||
            entries.values.single.isFolder ||
            entries.keys.single != _policy.singleMemberName ||
            entries.values.single.mode != null)) {
      throw const ArchiveViewException(
        'A compressed file supports replacing its one payload. Its member name, count and filesystem permissions cannot be changed.',
      );
    }
    if (_policy.format == ArchiveEndpointFormat.ar &&
        entries.values.any(
          (entry) => entry.isFolder || entry.name.contains('/'),
        )) {
      throw const ArchiveViewException(
        'AR archives contain flat regular files only.',
      );
    }
    if (_policy.packageKind == 'deb') {
      final required = _policy.inspection!.container['requiredMembers'] as List;
      if (entries.length != required.length ||
          !required.every(entries.containsKey)) {
        throw const ArchiveViewException(
          'Debian packages require their original ordered control and data members. Only validated payload replacements are supported.',
        );
      }
    }
    _entries
      ..clear()
      ..addAll(entries);
    _dirty = true;
    _revision++;
  }

  void _check({bool writing = false}) {
    if (_requiresReopen) {
      throw StateError(
        'The archive was saved, but its working view could not be refreshed. Reopen the saved archive.',
      );
    }
    if (!isCurrent) throw StateError('The original archive source changed.');
    if (writing && !canUpdate) throw UnsupportedError(updateSupport);
  }

  /// The editable DMG namespace uses the writer's HFS Unicode 3.2 rules.
  /// Validate before normalization, so filesystem equivalence never relaxes
  /// traversal/absolute-path checks or changes other archive formats' names.
  String _safeMemberPath(String path) {
    final safe = ArchiveService.safeMemberPath(path);
    return _policy.format == ArchiveEndpointFormat.dmg
        ? normalizeHfsArchivePath(safe)
        : safe;
  }

  String _lookupMemberPath(String path) {
    final relative = path.replaceFirst(RegExp(r'^/+'), '');
    return _policy.format == ArchiveEndpointFormat.dmg && relative.isNotEmpty
        ? _safeMemberPath(relative)
        : relative;
  }

  List<FileItem> list([String path = '/']) {
    _check();
    final prefix = path == '/'
        ? ''
        : '${_lookupMemberPath(path).replaceAll(RegExp(r'/+$'), '')}/';
    final items = <String, FileItem>{};
    for (final entry in _entries.values) {
      if (!entry.name.startsWith(prefix)) continue;
      final rest = entry.name.substring(prefix.length);
      if (rest.isEmpty) continue;
      final slash = rest.indexOf('/');
      final name = slash < 0 ? rest : rest.substring(0, slash);
      final folder = slash >= 0 || entry.isFolder;
      items[name] = FileItem(
        name: name,
        path: '/$prefix$name',
        isFolder: folder,
        size: folder ? null : entry.size,
        updatedAt: folder ? _entries['$prefix$name']?.modified : entry.modified,
        metadata: {
          'version': entry.contentSha256 != null
              ? '${entry.contentSha256}:${entry.name}'
              : entry.bytes == null
              ? '$_fingerprint:${entry.member?.index}:${entry.name}'
              : '${sha256.convert(entry.bytes!)}:${entry.name}',
        },
      );
    }
    return items.values.toList()..sort(
      (a, b) => a.isFolder != b.isFolder
          ? (a.isFolder ? -1 : 1)
          : a.name.compareTo(b.name),
    );
  }

  Future<Uint8List> read(String path) async {
    _check();
    final name = _lookupMemberPath(path);
    final entry = _entries[name];
    if (entry == null || entry.isFolder) {
      throw StateError('Not an archive file: $path');
    }
    if (entry.spool != null) {
      if (entry.size > kArchiveReadLimit) {
        throw const ArchiveViewException(
          'This member is too large for a buffered editor. Copy it out using the streamed transfer.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in openRead(path)) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }
    return entry.bytes ?? _archive.readMember(entry.member!);
  }

  Stream<List<int>> openRead(String path) async* {
    _check();
    final name = _lookupMemberPath(path);
    final entry = _entries[name];
    if (entry == null || entry.isFolder) {
      throw StateError('Not an archive file: $path');
    }
    final generation = _revision;
    final stream = entry.spool != null
        ? entry.spool!.openRead()
        : entry.bytes != null
        ? Stream<List<int>>.value(entry.bytes!)
        : _archive.openMember(entry.member!, maxBytes: maxMemberBytes);
    var received = 0;
    await for (final chunk in stream) {
      _check();
      if (_revision != generation || chunk.length > entry.size - received) {
        throw StateError('The archive member changed during its transfer.');
      }
      received += chunk.length;
      yield chunk;
    }
    _check();
    if (_revision != generation || received != entry.size) {
      throw StateError('The archive member ended at an unexpected size.');
    }
  }

  void replace(String path, Uint8List bytes, {DateTime? modified, int? mode}) {
    _check(writing: true);
    final name = _safeMemberPath(path.replaceFirst(RegExp(r'^/+'), ''));
    if (bytes.length > kArchiveReadLimit) {
      throw const ArchiveViewException('Member exceeds the 64 MiB limit.');
    }
    final previous = _entries[name];
    if (previous?.isFolder == true) {
      throw StateError('A directory already uses this name.');
    }
    final updated = Map.of(_entries);
    updated[name] = _ArchiveEntry(
      name,
      false,
      member: previous?.member,
      bytes: Uint8List.fromList(bytes),
      modified: modified == null
          ? previous?.modified
          : _policy.normalizeImportedTime(modified),
      mode: mode ?? previous?.mode,
    );
    _publish(updated);
  }

  void createDirectory(String path, {DateTime? modified, int? mode}) {
    _check(writing: true);
    final name = _safeMemberPath(path.replaceFirst(RegExp(r'^/+'), ''));
    if (_entries[name]?.isFolder == false) {
      throw StateError('A file already uses this archive member name.');
    }
    if (_entries[name]?.isFolder == true) return;
    _publish({
      ..._entries,
      name: _ArchiveEntry(
        name,
        true,
        modified: _policy.normalizeImportedTime(modified),
        mode: mode,
      ),
    });
  }

  /// Atomically adopts one fully verified private import. A failed or cancelled
  /// import never leaves a partially changed workspace or a published result.
  void applyImport(
    List<ArchiveWorkspaceImport> items, {
    required int expectedRevision,
  }) {
    _check(writing: true);
    if (_revision != expectedRevision) {
      throw StateError(
        'The archive draft changed while files were being staged.',
      );
    }
    final updated = Map.of(_entries);
    final imported = <String>{};
    for (final item in items) {
      final name = _safeMemberPath(item.path.replaceFirst(RegExp(r'^/+'), ''));
      if (_policy.format == ArchiveEndpointFormat.dmg && !imported.add(name)) {
        throw StateError('Imported HFS names identify the same member: $name');
      }
      final previous = updated[name];
      if (previous != null && previous.isFolder != item.isFolder) {
        throw StateError('Archive member type changed: $name');
      }
      if (item.isFolder &&
              (item.bytes != null ||
                  item.spool != null ||
                  item.contentSha256 != null) ||
          !item.isFolder &&
              (item.bytes == null && item.spool == null ||
                  item.bytes != null && item.spool != null ||
                  item.bytes != null &&
                      item.bytes!.length > kArchiveReadLimit ||
                  item.spool != null &&
                      (!_streaming ||
                          !item.spool!.isSealed ||
                          item.spool!.length > maxMemberBytes ||
                          item.contentSha256 == null ||
                          !RegExp(r'^[a-f0-9]{64}$')
                              .hasMatch(item.contentSha256!)))) {
        throw const ArchiveViewException(
          'An imported member exceeds its size limit.',
        );
      }
      updated[name] = _ArchiveEntry(
        name,
        item.isFolder,
        member: previous?.member,
        bytes: item.bytes == null ? null : Uint8List.fromList(item.bytes!),
        spool: item.spool,
        contentSha256: item.contentSha256,
        modified: item.isFolder && previous != null
            ? previous.modified
            : _policy.normalizeImportedTime(item.modified) ??
                  previous?.modified,
        mode: item.isFolder && previous != null
            ? previous.mode
            : item.mode ?? previous?.mode,
      );
    }
    if (items.isNotEmpty) {
      _publish(updated);
      _ownedSpools.addAll(
        items.map((item) => item.spool).whereType<ArchiveOutputSpool>(),
      );
    }
  }

  /// Adopts selected directory-sync imports and exact removals together. A
  /// selected directory never recursively removes unchecked descendants.
  /// The owner token and complete source-tree dependency remain bound for this
  /// workspace's lifetime, preventing ordinary Save from bypassing sync guards.
  List<String> applyDirectorySync({
    required List<ArchiveWorkspaceImport> imports,
    required Set<String> removals,
    required String directory,
    required int expectedRevision,
    required Object publicationAuthority,
    required ArchivePublicationDirectoryDependency dependency,
  }) {
    _check(writing: true);
    if (!canSynchronizeDirectory ||
        _revision != expectedRevision ||
        _saving ||
        pendingPublication != null ||
        _directorySyncAuthority != null ||
        _sourceRemovalAuthority != null) {
      throw StateError('The archive cannot adopt this synchronization draft.');
    }
    final scope = directory == '/'
        ? ''
        : _safeMemberPath(directory.replaceFirst(RegExp(r'^/'), ''));
    if (scope.isNotEmpty &&
        _entries[scope]?.isFolder != true &&
        !_entries.keys.any((name) => name.startsWith('$scope/'))) {
      throw StateError('The synchronization destination directory changed.');
    }
    String name(String path) {
      final safe = ArchiveService.safeMemberPath(
        path.replaceFirst(RegExp(r'^/'), ''),
      );
      final canonical = _safeMemberPath(safe);
      if (path != '/$safe' ||
          scope.isNotEmpty && !canonical.startsWith('$scope/')) {
        throw StateError(
          'A synchronization action escapes its archive directory.',
        );
      }
      return canonical;
    }

    final removed = removals.map(name).toSet();
    final originalNames = SplayTreeMap<String, bool>()
      ..addEntries(_entries.keys.map((path) => MapEntry(path, true)));
    final retainedNames = SplayTreeMap<String, bool>()
      ..addEntries(
        _entries.keys
            .where((path) => !removed.contains(path))
            .map((path) => MapEntry(path, true)),
      );
    bool descendants(String path) =>
        originalNames.firstKeyAfter('$path/')?.startsWith('$path/') ?? false;
    for (final path in removed) {
      if (!_entries.containsKey(path) && !descendants(path)) {
        throw StateError('A selected archive-only entry changed: $path');
      }
      if ((_entries[path]?.isFolder ?? descendants(path)) &&
          (retainedNames.firstKeyAfter('$path/')?.startsWith('$path/') ??
              false)) {
        throw StateError(
          'Select every descendant before removing archive directory: $path',
        );
      }
    }
    final updated = Map.of(_entries);
    for (final path in removed) {
      updated.remove(path);
    }
    final imported = <String>{};
    for (final item in imports) {
      final path = name(item.path);
      if (!imported.add(path) || removed.contains(path)) {
        throw StateError(
          'A synchronization path has conflicting actions: $path',
        );
      }
      final previous = updated[path];
      if (previous != null && previous.isFolder != item.isFolder ||
          !item.isFolder &&
              (retainedNames.firstKeyAfter('$path/')?.startsWith('$path/') ??
                  false)) {
        throw StateError('A synchronization entry has a type conflict: $path');
      }
      if (!item.isFolder &&
              (item.bytes == null || item.bytes!.length > kArchiveReadLimit) ||
          item.isFolder && item.bytes != null ||
          (item.mode ?? 0) & 0xc00 != 0) {
        throw StateError(
          'A synchronization import has unsupported content or permissions.',
        );
      }
      updated[path] = _ArchiveEntry(
        path,
        item.isFolder,
        member: previous?.member,
        bytes: item.bytes == null ? null : Uint8List.fromList(item.bytes!),
        modified: item.isFolder && previous != null
            ? previous.modified
            : _policy.normalizeImportedTime(item.modified) ??
                  previous?.modified,
        mode: item.isFolder && previous != null
            ? previous.mode
            : item.mode ?? previous?.mode,
      );
      retainedNames[path] = true;
    }
    if (imports.isEmpty && removals.isEmpty) {
      throw StateError('Select at least one synchronization action.');
    }
    _publish(updated);
    _directorySyncAuthority = publicationAuthority;
    _directorySyncDependency = dependency;
    return List.unmodifiable(
      (removed.map((path) => '/$path').toList()..sort()),
    );
  }

  void remove(Iterable<String> paths) {
    _check(writing: true);
    final updated = Map.of(_entries);
    for (final path in paths) {
      final name = _safeMemberPath(path.replaceFirst(RegExp(r'^/+'), ''));
      updated.removeWhere((key, _) => key == name || key.startsWith('$name/'));
    }
    _publish(updated);
  }

  /// Removes only the exact copied members whose bytes were verified in a
  /// destination candidate. This operates on a separate source-removal draft;
  /// the source's physical container remains unchanged until reviewed save.
  /// A folder is removed only when no uncopied or skipped descendant remains.
  /// The private coordinator retains [publicationAuthority]; this workspace
  /// subsequently requires that exact owner and a destination dependency to
  /// publish, including after further edits or discarding its draft.
  Future<List<String>> stageVerifiedMemberRemoval(
    List<ArchiveWorkspaceRemoval> members, {
    required int expectedRevision,
    required Object publicationAuthority,
    bool Function()? isCancelled,
  }) async {
    void check() {
      _check(writing: true);
      if (!canRemoveMembers) {
        throw UnsupportedError(
          'This archive profile does not support removing transferred members.',
        );
      }
      if (_revision != expectedRevision ||
          _saving ||
          pendingPublication != null ||
          _sourceRemovalAuthority != null) {
        throw StateError('The source-removal draft changed after capture.');
      }
      if (isCancelled?.call() ?? false) throw const FileOperationCancelled();
    }

    check();
    if (members.isEmpty || members.length > 200000) {
      throw const ArchiveViewException(
        'No bounded copied-member set is available.',
      );
    }
    final names = <String>{};
    final files = <String>[];
    final directories = <String>[];
    final remainingNames = SplayTreeMap<String, bool>()
      ..addEntries(_entries.keys.map((name) => MapEntry(name, true)));
    bool hasChildren(String name) {
      final prefix = '$name/';
      return remainingNames.firstKeyAfter(prefix)?.startsWith(prefix) ?? false;
    }

    for (final member in members) {
      check();
      final name = _safeMemberPath(
        member.path.replaceFirst(RegExp(r'^/+'), ''),
      );
      if (!names.add(name)) {
        throw StateError('A copied source member is repeated: $name');
      }
      final entry = _entries[name];
      if (member.isDirectory) {
        if (member.sha256 != null ||
            member.size != 0 ||
            entry?.isFolder == false ||
            entry == null && !hasChildren(name)) {
          throw StateError('The copied source directory changed: $name');
        }
        directories.add(name);
      } else {
        if (entry == null ||
            entry.isFolder ||
            entry.size != member.size ||
            member.size < 0 ||
            member.size > maxMemberBytes ||
            member.sha256 == null ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(member.sha256!)) {
          throw StateError('The copied source member changed: $name');
        }
        final digest = await sha256
            .bind(
              openRead('/$name').map((chunk) {
                check();
                return chunk;
              }),
            )
            .single;
        check();
        if (digest.toString() != member.sha256) {
          throw StateError('Copied source bytes do not match: $name');
        }
        files.add(name);
      }
    }
    final updated = Map.of(_entries);
    final removed = <String>[];
    for (final file in files) {
      updated.remove(file);
      remainingNames.remove(file);
      removed.add('/$file');
    }
    directories.sort((a, b) => b.length.compareTo(a.length));
    for (final directory in directories) {
      if (!hasChildren(directory)) {
        updated.remove(directory);
        remainingNames.remove(directory);
        removed.add('/$directory');
      }
    }
    check();
    if (removed.isNotEmpty) {
      _publish(updated);
      _sourceRemovalAuthority = publicationAuthority;
    }
    return List.unmodifiable(removed);
  }

  /// Stages removal only for members whose foreground copy completed and whose
  /// destination still contains the same bytes. The archive itself is unchanged
  /// until [save]; skipped, failed and filtered members remain in the workspace.
  Future<int> stageCopiedMemberRemoval(
    FileOperationPlan plan, {
    bool Function()? isCancelled,
  }) async {
    _check(writing: true);
    if (!identical(plan.source.identity, this)) {
      throw StateError('The completed copy belongs to a different archive.');
    }
    final updated = Map.of(_entries);
    var removed = 0;
    for (final entry in plan.entries) {
      if (entry.source.isFolder ||
          entry.outcome != FileOperationOutcome.copied) {
        continue;
      }
      _check(writing: true);
      if (isCancelled?.call() ?? false) {
        throw _ArchiveWorkspaceCancelled('Archive move cancelled.');
      }
      final original = await sha256.bind(openRead(entry.source.path!)).single;
      final target = await plan.destination.stat(entry.destination);
      if (target == null || target.isFolder || target.isSymlink == true) {
        throw StateError(
          'The copied destination is missing: ${entry.destination}',
        );
      }
      if (target.size == null ||
          target.size! > maxMemberBytes ||
          target.size != entry.source.size ||
          target.size! > kArchiveReadLimit &&
              !plan.destination.capabilities.boundedDownload) {
        throw StateError(
          'The copied destination cannot be verified with bounded reads.',
        );
      }
      var count = 0;
      final copied = await sha256
          .bind(
            plan.destination.readFile(target).map((chunk) {
              _check(writing: true);
              if (!plan.destination.isCurrent ||
                  (isCancelled?.call() ?? false)) {
                throw const FileOperationCancelled();
              }
              if (chunk.length > target.size! - count) {
                throw StateError('The copied destination grew.');
              }
              count += chunk.length;
              return chunk;
            }),
          )
          .single;
      final after = await plan.destination.stat(entry.destination);
      if (!plan.destination.isCurrent ||
          after == null ||
          after.uuid != target.uuid ||
          after.size != target.size ||
          after.updatedAt != target.updatedAt ||
          count != target.size ||
          original != copied) {
        throw StateError(
          'The copied destination changed: ${entry.destination}',
        );
      }
      final name = _lookupMemberPath(entry.source.path!);
      if (updated.remove(name) != null) removed++;
    }
    // A directory can disappear only when every remaining child is gone.
    // Filtering or skipped conflicts therefore never delete uncopied members.
    final folders =
        plan.entries
            .where((entry) => entry.source.isFolder && entry.completed)
            .map((entry) => _lookupMemberPath(entry.source.path!))
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final folder in folders) {
      if (!updated.keys.any((path) => path.startsWith('$folder/'))) {
        if (updated.remove(folder) != null) removed++;
      }
    }
    _check(writing: true);
    if (isCancelled?.call() ?? false) {
      throw _ArchiveWorkspaceCancelled('Archive move cancelled.');
    }
    if (removed > 0) _publish(updated);
    return removed;
  }

  void rename(String path, String newPath) {
    _check(writing: true);
    final from = _safeMemberPath(path.replaceFirst(RegExp(r'^/+'), ''));
    final target = _safeMemberPath(newPath);
    if (target == from) return;
    if (target.startsWith('$from/')) {
      throw StateError('A directory cannot be moved into itself.');
    }
    final affected = _entries.entries
        .where((entry) => entry.key == from || entry.key.startsWith('$from/'))
        .toList();
    if (affected.isEmpty) throw StateError('Member no longer exists.');
    for (final entry in affected) {
      final renamed = '$target${entry.key.substring(from.length)}';
      if (_entries.containsKey(renamed)) {
        throw StateError('Archive member exists: $renamed');
      }
    }
    final updated = Map.of(_entries);
    for (final entry in affected) {
      updated.remove(entry.key);
    }
    for (final entry in affected) {
      final name = '$target${entry.key.substring(from.length)}';
      updated[name] = _ArchiveEntry(
        name,
        entry.value.isFolder,
        member: entry.value.member,
        bytes: entry.value.bytes,
        spool: entry.value.spool,
        contentSha256: entry.value.contentSha256,
        modified: entry.value.modified,
        mode: entry.value.mode,
      );
    }
    _publish(updated);
  }

  /// Stages one atomic move of selected roots within this workspace. The
  /// complete batch is checked before changing the draft. Existing folders
  /// never merge or replace each other, and a skipped root keeps its full tree.
  /// Original member identities retain inspected metadata and source ordering;
  /// physical storage changes only after the normal review and save workflow.
  ///
  /// Roots are processed in canonical path order, making Keep both names
  /// deterministic even when selections contain identical basenames.
  ArchiveMemberMoveResult moveMembers(
    List<String> paths,
    String destinationDirectory, {
    ArchiveMemberMoveConflict conflict = ArchiveMemberMoveConflict.fail,
  }) {
    _check(writing: true);
    if (!canMoveMembers) {
      throw UnsupportedError(
        'This archive profile does not support moving members between folders.',
      );
    }
    ArchiveWorkspace? level = this;
    while (level != null) {
      if (level._saving || level._pendingPublication != null) {
        throw StateError(
          'Finish or recover the current archive publication before changing its draft.',
        );
      }
      level = level._parentWorkspace;
    }
    if (paths.isEmpty || paths.length > 200000) {
      throw const ArchiveViewException(
        'Select between 1 and 200,000 archive members to move.',
      );
    }
    String canonical(String path) =>
        _safeMemberPath(path.replaceFirst(RegExp(r'^/+'), ''));
    final directory = destinationDirectory == '/'
        ? ''
        : canonical(destinationDirectory);
    final names = _entries.keys.toList()..sort();
    bool hasDescendants(String name) {
      final prefix = '$name/';
      var low = 0;
      var high = names.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (names[middle].compareTo(prefix) < 0) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return low < names.length && names[low].startsWith(prefix);
    }

    bool occupied(String name) =>
        _entries.containsKey(name) || hasDescendants(name);
    if (directory.isNotEmpty &&
        (_entries[directory]?.isFolder == false || !occupied(directory))) {
      throw StateError('Choose an existing archive directory.');
    }
    final selected = <String>{};
    for (final path in paths) {
      final name = canonical(path);
      if (!occupied(name)) {
        throw StateError('Archive member no longer exists: $name');
      }
      selected.add(name);
    }
    final roots = selected.where((name) {
      var parent = p.posix.dirname(name);
      while (parent != '.') {
        if (selected.contains(parent)) return false;
        parent = p.posix.dirname(parent);
      }
      return true;
    }).toList()..sort();
    for (final root in roots) {
      if (directory == root || directory.startsWith('$root/')) {
        throw StateError('A directory cannot be moved into itself.');
      }
    }

    final moves = <String, String>{};
    final skipped = <String>[];
    final unchanged = <String>[];
    final reserved = <String>{};
    final nextSuffix = <String, int>{};
    for (final root in roots) {
      final basename = p.posix.basename(root);
      final target = directory.isEmpty ? basename : '$directory/$basename';
      if (target == root) {
        unchanged.add('/$root');
        continue;
      }
      var destination = target;
      if (occupied(destination) || reserved.contains(destination)) {
        switch (conflict) {
          case ArchiveMemberMoveConflict.fail:
            throw StateError('Archive member exists: $destination');
          case ArchiveMemberMoveConflict.skip:
            skipped.add('/$root');
            continue;
          case ArchiveMemberMoveConflict.keepBoth:
            final isFolder = _entries[root]?.isFolder ?? true;
            final extension = isFolder ? '' : p.posix.extension(basename);
            final stem = basename.substring(
              0,
              basename.length - extension.length,
            );
            var suffix = nextSuffix[target] ?? 2;
            do {
              final name = '$stem ($suffix)$extension';
              destination = directory.isEmpty ? name : '$directory/$name';
              suffix++;
            } while (occupied(destination) || reserved.contains(destination));
            nextSuffix[target] = suffix;
        }
      }
      reserved.add(destination);
      moves[root] = destination;
    }

    if (moves.isNotEmpty) {
      final updated = <String, _ArchiveEntry>{};
      for (final entry in _entries.entries) {
        var root = entry.key;
        String? target;
        while (root != '.') {
          target = moves[root];
          if (target != null) break;
          root = p.posix.dirname(root);
        }
        final name = target == null
            ? entry.key
            : '$target${entry.key.substring(root.length)}';
        if (updated.containsKey(name)) {
          throw StateError(
            'Several archive members target the same path: $name',
          );
        }
        updated[name] = target == null
            ? entry.value
            : _ArchiveEntry(
                name,
                entry.value.isFolder,
                member: entry.value.member,
                bytes: entry.value.bytes,
                spool: entry.value.spool,
                contentSha256: entry.value.contentSha256,
                modified: entry.value.modified,
                mode: entry.value.mode,
              );
      }
      _publish(updated);
    }
    return ArchiveMemberMoveResult._(
      {for (final move in moves.entries) '/${move.key}': '/${move.value}'},
      skipped,
      unchanged,
    );
  }

  Future<void> addFiles(
    FileOperationBackend input,
    List<FileItem> files, {
    String directory = '/',
    bool replaceExisting = false,
    bool Function()? isCancelled,
  }) async {
    _check(writing: true);
    final staged = <String, _ArchiveEntry>{};
    final capturedSpools = <ArchiveOutputSpool>[];
    final generation = _revision;
    final visited = <String>{};
    var total = _entries.values.fold<int>(0, (sum, entry) => sum + entry.size);
    Future<void> add(FileItem file, String name, int depth) async {
      _check(writing: true);
      if (_revision != generation) {
        throw StateError('The archive draft changed during import.');
      }
      if (!input.isCurrent) throw StateError('The added-file source changed.');
      if (isCancelled?.call() ?? false) {
        throw _ArchiveWorkspaceCancelled('Archive update cancelled.');
      }
      if (file.isSymlink == true) {
        throw UnsupportedError('Symbolic links are not packed.');
      }
      if (depth > 200 || staged.length + _entries.length > 200000) {
        throw const ArchiveViewException('Archive traversal limit exceeded.');
      }
      if (file.path == null || !input.paths.isAbsolute(file.path!)) {
        throw StateError('Added file has no verified absolute path.');
      }
      if (!visited.add(input.pathKey(file.path!))) {
        throw StateError('Repeated source path while packing: ${file.path}');
      }
      name = _safeMemberPath(name);
      if (staged.containsKey(name)) {
        if (_policy.format == ArchiveEndpointFormat.dmg) {
          throw StateError(
            'Imported HFS names identify the same member: $name',
          );
        }
        return;
      }
      if (_entries.containsKey(name) && !replaceExisting) {
        throw StateError('Archive member exists: $name');
      }
      if (file.isFolder) {
        staged[name] = _ArchiveEntry(
          name,
          true,
          member: _entries[name]?.member,
          modified:
              _entries[name]?.modified ??
              _policy.normalizeImportedTime(file.updatedAt),
          mode: _entries[name]?.mode,
        );
        for (final child in await input.list(file.path!)) {
          if (child.path == null ||
              !input.isWithin(file.path!, child.path!) ||
              input.paths.dirname(child.path!) !=
                  input.paths.normalize(file.path!)) {
            throw StateError('Source returned an invalid child: ${child.path}');
          }
          await add(child, '$name/${child.name}', depth + 1);
        }
      } else {
        if (_streaming) {
          final captured = await _captureSpool(
            input,
            file,
            maxBytes: maxMemberBytes,
            isCancelled: isCancelled,
          );
          capturedSpools.add(captured.spool);
          total += captured.spool.length - (_entries[name]?.size ?? 0);
          if (total > maxExpandedBytes) {
            throw const ArchiveViewException(
              'Archive contents exceed the native streaming limit.',
            );
          }
          staged[name] = _ArchiveEntry(
            name,
            false,
            member: _entries[name]?.member,
            spool: captured.spool,
            contentSha256: captured.digest,
            modified: _policy.normalizeImportedTime(file.updatedAt),
            mode: _entries[name]?.mode,
          );
          return;
        }
        final bytes = await _read(
          input,
          file,
          kArchiveReadLimit,
          isCancelled: isCancelled,
        );
        total += bytes.length - (_entries[name]?.size ?? 0);
        if (total > ArchiveService.maxExtractedBytes) {
          throw const ArchiveViewException('Archive contents exceed 256 MiB.');
        }
        staged[name] = _ArchiveEntry(
          name,
          false,
          member: _entries[name]?.member,
          bytes: bytes,
          modified: _policy.normalizeImportedTime(file.updatedAt),
          mode: _entries[name]?.mode,
        );
      }
    }

    final prefix = directory == '/'
        ? ''
        : '${directory.replaceFirst(RegExp(r'^/+'), '')}/';
    try {
      for (final file in files) {
        await add(file, '$prefix${file.name}', 0);
      }
      if (_revision != generation) {
        throw StateError('The archive draft changed during import.');
      }
      _publish({..._entries, ...staged});
      _ownedSpools.addAll(capturedSpools);
    } catch (_) {
      for (final spool in capturedSpools) {
        await spool.dispose();
      }
      rethrow;
    }
  }

  Future<Uint8List> repack({
    bool Function()? isCancelled,
    FileOperationControl? control,
    bool background = false,
  }) async {
    return collectArchiveWrite(
      (sink) => _writePacked(
        sink,
        maxOutputBytes: ArchiveService.maxArchiveBytes,
        isCancelled: isCancelled,
        control: control,
        background: background,
      ),
      maxBytes: ArchiveService.maxArchiveBytes,
    );
  }

  List<ArchiveWriteEntry> _entriesForWriting(
    void Function() checkPacking, {
    Future<void> Function()? checkpoint,
    FileOperationControl? control,
  }) {
    // Retained members keep their original order, including after a rename.
    // This matters for comic page ordering and package metadata precedence.
    final originalOrder = _entries.values.toList();
    final ranks = {
      for (var index = 0; index < originalOrder.length; index++)
        originalOrder[index]: index,
    };
    final ordered = List<_ArchiveEntry>.of(originalOrder)
      ..sort(
        (a, b) => (a.member?.index ?? (200000 + ranks[a]!)).compareTo(
          b.member?.index ?? (200000 + ranks[b]!),
        ),
      );
    return [
      for (final entry in ordered)
        ArchiveWriteEntry(
          path: entry.name,
          isDirectory: entry.isFolder,
          size: entry.isFolder ? 0 : entry.size,
          modified: entry.modified,
          mode: entry.mode,
          attributes: entry.member == null
              ? const {}
              : _policy.inspection?.attributes[entry.member!.name] ??
                    _policy
                        .inspection
                        ?.attributes[ArchiveService.safeMemberPath(
                      entry.member!.name,
                    )] ??
                    const {},
          readChunks: entry.isFolder
              ? null
              : () async* {
                  checkPacking();
                  await checkpoint?.call();
                  final stream = openRead('/${entry.name}');
                  await for (final chunk in control?.bind(stream) ?? stream) {
                    await checkpoint?.call();
                    checkPacking();
                    yield chunk;
                  }
                  checkPacking();
                },
        ),
    ];
  }

  Future<void> _writePacked(
    Future<void> Function(List<int>) sink, {
    required int maxOutputBytes,
    bool Function()? isCancelled,
    FileOperationControl? control,
    bool background = false,
  }) async {
    _check(writing: true);
    void checkPacking() {
      _check(writing: true);
      if ((control?.isCancelled ?? false) || (isCancelled?.call() ?? false)) {
        throw _ArchiveWorkspaceCancelled('Archive update cancelled.');
      }
    }

    Future<void> checkpoint() async {
      checkPacking();
      await control?.checkpoint();
      checkPacking();
    }

    Future<void> emit(List<int> bytes) async {
      await checkpoint();
      await sink(bytes);
      checkPacking();
    }

    await checkpoint();
    if (_policy.packageKind == 'deb') {
      final payloads = _entries.values
          .where(
            (entry) =>
                entry.name.startsWith('control.tar') ||
                entry.name.startsWith('data.tar'),
          )
          .toList();
      if (payloads.any((entry) => entry.bytes != null) &&
          payloads.any((entry) => entry.bytes == null)) {
        throw const ArchiveViewException(
          'Replace the externally prepared control and data archives together so package metadata can be rebuilt consistently.',
        );
      }
    }
    if (encrypted &&
        !encryptNames &&
        !_entries.values.any(
          (entry) =>
              !entry.isFolder &&
              (_policy.format == ArchiveEndpointFormat.zip || entry.size > 0),
        )) {
      throw StateError(
        'Removing all protected file data would erase the archive encryption policy. Keep a protected member or use an explicit new archive.',
      );
    }
    final entries = _entriesForWriting(
      checkPacking,
      checkpoint: checkpoint,
      control: control,
    );
    final packageIssue = await archiveZipPackageIssue(file.name, entries);
    if (packageIssue != null) throw ArchiveViewException(packageIssue);
    if (background) {
      await writeArchiveEntriesInWorker(
        _policy.format,
        entries,
        sink: emit,
        source: _policy.inspection,
        streamed: _streaming,
        compression: _policy.compression,
        singlePayload: _policy.singlePayload,
        gzipHeader: _policy.gzipHeader,
        xzCheck: _policy.xzCheck,
        password: encrypted ? password : null,
        encryptNames: encryptNames,
        maxOutputBytes: maxOutputBytes,
        isCancelled: () {
          checkPacking();
          return false;
        },
        checkpoint: checkpoint,
        cancellationFuture: control?.cancellationFuture,
      );
      return;
    }
    if (_streaming) {
      await writeStreamingArchiveEntries(
        _policy.format,
        entries,
        sink: emit,
        source: _policy.inspection,
        gzipHeader: _policy.gzipHeader,
        maxOutputBytes: maxOutputBytes,
        isCancelled: () {
          checkPacking();
          return false;
        },
      );
      return;
    }
    await writeArchiveEntries(
      _policy.format,
      entries,
      sink: emit,
      source: _policy.inspection,
      compression: _policy.compression,
      singlePayload: _policy.singlePayload,
      gzipHeader: _policy.gzipHeader,
      xzCheck: _policy.xzCheck,
      password: encrypted ? password : null,
      encryptNames: encryptNames,
      maxOutputBytes: maxOutputBytes,
      isCancelled: () {
        checkPacking();
        return false;
      },
    );
  }

  /// Current metadata-only diff. This does not pack or read member payloads.
  List<ArchiveWorkspaceChange> get draftChanges {
    _check();
    final changes = <ArchiveWorkspaceChange>[];
    final retained = <String>{};
    for (final entry in _entries.values) {
      final original = entry.member == null
          ? null
          : ArchiveService.safeMemberPath(entry.member!.name);
      if (original != null) retained.add(original);
      if (original != null && original != entry.name) {
        changes.add(
          ArchiveWorkspaceChange(
            ArchiveWorkspaceChangeKind.rename,
            entry.name,
            from: original,
            size: entry.size,
          ),
        );
      }
      if (entry.bytes != null || entry.spool != null || original == null) {
        changes.add(
          ArchiveWorkspaceChange(
            entry.isFolder
                ? ArchiveWorkspaceChangeKind.createDirectory
                : original == null
                ? ArchiveWorkspaceChangeKind.add
                : ArchiveWorkspaceChangeKind.replace,
            entry.name,
            size: entry.size,
          ),
        );
      }
    }
    for (final entry in ArchiveMemberIndex(_archive).members.entries) {
      if (!retained.contains(entry.key)) {
        changes.add(
          ArchiveWorkspaceChange(
            ArchiveWorkspaceChangeKind.remove,
            entry.key,
            size: entry.value.size,
          ),
        );
      }
    }
    changes.sort((a, b) => a.path.compareTo(b.path));
    return List.unmodifiable(changes);
  }

  /// Packs and verifies a concrete review snapshot. Later edits invalidate it.
  Future<ArchiveWorkspaceReview> review({
    bool Function()? isCancelled,
    FileOperationControl? control,
    bool background = false,
  }) async {
    void check() {
      _check(writing: true);
      if (control?.isCancelled ?? false) throw const FileOperationCancelled();
      if (isCancelled?.call() ?? false) {
        throw _ArchiveWorkspaceCancelled('Archive update cancelled.');
      }
    }

    Future<void> checkpoint() async {
      check();
      await control?.checkpoint();
      check();
    }

    check();
    if (_saving) {
      throw StateError('The archive is already preparing a publication.');
    }
    // Reserve the draft before the first await, including a paused checkpoint.
    // Synchronous edits and nested moves must not overtake an admitted review.
    _saving = true;
    ArchiveOutputSpool? spool;
    try {
      await checkpoint();
      if (_pendingPublication != null && _pendingReview != null) {
        return _pendingReview!;
      }
      if (_latestReview?.isCurrent == true) return _latestReview!;
      final generations = <ArchiveWorkspace, int>{};
      ArchiveWorkspace? level = this;
      while (level != null) {
        generations[level] = level._revision;
        level = level._parentWorkspace;
      }
      Uint8List? bytes;
      if (_streaming) {
        spool = await ArchiveOutputSpool.create(maxBytes: maxContainerBytes);
        await _writePacked(
          spool.write,
          maxOutputBytes: maxContainerBytes,
          isCancelled: isCancelled,
          control: control,
          background: background,
        );
        await spool.finish();
      } else {
        bytes = await repack(
          isCancelled: isCancelled,
          control: control,
          background: background,
        );
      }
      final checked = await _verifyPacked(
        bytes,
        spool: spool,
        isCancelled: isCancelled,
        control: control,
      );
      await checked.archive.close();
      final digest = spool == null
          ? sha256.convert(bytes!).toString()
          : (await sha256
                    .bind(
                      (() async* {
                        final stream = spool!.openRead();
                        await for (final chunk
                            in control?.bind(stream) ?? stream) {
                          await checkpoint();
                          yield chunk;
                        }
                      })(),
                    )
                    .single)
                .toString();
      final changes = draftChanges;
      final result = ArchiveWorkspaceReview._(
        this,
        generations,
        bytes?.asUnmodifiableView(),
        List.unmodifiable(changes),
        spool: spool,
        sha256: digest,
      );
      _validateReview(result);
      final stale = _latestReview?.spool;
      if (stale != null && stale != _snapshotSpool && stale != spool) {
        await stale.dispose();
        _ownedSpools.remove(stale);
      }
      if (spool != null) _ownedSpools.add(spool);
      spool = null;
      _latestReview = result;
      return result;
    } finally {
      await spool?.dispose();
      _saving = false;
    }
  }

  void _validateReview(ArchiveWorkspaceReview review) {
    _check(writing: true);
    if (!identical(review.workspace, this) ||
        review._generations.entries.any(
          (entry) => !entry.key.isCurrent || entry.key._revision != entry.value,
        )) {
      throw StateError(
        'The archive draft changed after review. Review the updated changes again.',
      );
    }
  }

  Future<({ViewerArchive archive, ArchiveEndpointPolicy policy})> _verifyPacked(
    Uint8List? bytes, {
    ArchiveOutputSpool? spool,
    bool Function()? isCancelled,
    FileOperationControl? control,
  }) async {
    bool cancelled() =>
        (control?.isCancelled ?? false) || (isCancelled?.call() ?? false);
    void check() {
      _check(writing: true);
      if (cancelled()) throw const FileOperationCancelled();
    }

    Future<void> checkpoint() async {
      check();
      await control?.checkpoint();
      check();
    }

    await checkpoint();
    StreamedArchiveOpen? streamed;
    if (spool != null) {
      try {
        streamed = await openStreamedArchiveSource(
          ArchiveCheckpointSource(
            await spool.openByteSource(),
            checkpoint,
            check,
          ),
          name: file.name,
          password: password,
          maxBytes: maxContainerBytes,
          isCancelled: cancelled,
        );
      } on ArchiveViewException {
        // Preserve the file-operation cancellation contract at this boundary.
        // Reader validation can yield while opening the private candidate.
        if (cancelled()) throw const FileOperationCancelled();
        rethrow;
      }
    }
    final replacement =
        streamed?.archive ??
        await _openBufferedArchive(bytes!, name: file.name, password: password);
    try {
      final actual = ArchiveMemberIndex(replacement).members;
      if (_entries.length != actual.length ||
          !_entries.keys.toSet().containsAll(actual.keys)) {
        throw const ArchiveViewException(
          'Repacked archive members could not be verified.',
        );
      }
      for (final item in actual.entries) {
        await checkpoint();
        if (cancelled()) throw const FileOperationCancelled();
        final expected = _entries[item.key]!;
        final member = item.value;
        if (member.isFile == expected.isFolder ||
            member.isFile && member.size != expected.size ||
            expected.modified != null &&
                (member.modified == null ||
                    !member.modified!.isAtSameMomentAs(expected.modified!)) ||
            expected.mode != null &&
                (member.posixMode == null ||
                    (member.posixMode! & 0xfff) != (expected.mode! & 0xfff))) {
          throw ArchiveViewException(
            'Repacked member metadata could not be preserved: ${item.key}',
          );
        }
        if (member.isFile) {
          Stream<List<int>> checked(Stream<List<int>> stream) async* {
            await for (final chunk in control?.bind(stream) ?? stream) {
              await checkpoint();
              if (cancelled()) {
                throw const FileOperationCancelled();
              }
              yield chunk;
            }
          }

          final decoded = await sha256
              .bind(
                checked(
                  replacement.openMember(member, maxBytes: maxMemberBytes),
                ),
              )
              .single;
          final original = await sha256
              .bind(checked(openRead('/${item.key}')))
              .single;
          if (decoded != original ||
              encrypted &&
                  (_policy.format == ArchiveEndpointFormat.zip ||
                      member.size > 0) &&
                  !member.isEncrypted ||
              !encrypted && member.isEncrypted) {
            throw ArchiveViewException(
              'Repacked member verification failed: ${item.key}',
            );
          }
        }
        await Future<void>.delayed(Duration.zero);
      }
      final policy =
          streamed?.policy ??
          await ArchiveEndpointPolicy.inspect(
            bytes!,
            file.name,
            replacement,
            password,
          );
      if (policy.reason != null ||
          policy.format != _policy.format ||
          policy.encrypted != encrypted ||
          policy.encryptNames != encryptNames) {
        throw const ArchiveViewException(
          'Repacked archive protection policy could not be preserved.',
        );
      }
      if (const {
        ArchiveEndpointFormat.iso,
        ArchiveEndpointFormat.rar,
        ArchiveEndpointFormat.dmg,
      }.contains(policy.format)) {
        final inspection = policy.inspection;
        if (inspection == null) {
          throw const ArchiveViewException(
            'Repacked container preservation metadata is missing.',
          );
        }
        final entries = _entriesForWriting(() {
          _check(writing: true);
          if (cancelled()) {
            throw const FileOperationCancelled();
          }
        });
        switch (policy.format) {
          case ArchiveEndpointFormat.iso:
            verifyIsoRewritePreservation(
              entries,
              inspection,
              source: _policy.inspection,
            );
          case ArchiveEndpointFormat.rar:
            verifyStoredRarPreservation(
              entries,
              inspection,
              source: _policy.inspection,
            );
          case ArchiveEndpointFormat.dmg:
            verifyDmgRewritePreservation(
              entries,
              inspection,
              source: _policy.inspection,
            );
          default:
            break;
        }
      }
      return (archive: replacement, policy: policy);
    } catch (_) {
      await replacement.close();
      rethrow;
    }
  }

  /// Returns only after the outermost physical container has a verified,
  /// durable publication receipt. Nested member writes alone are never success.
  Future<ArchivePublicationReceipt?> save({
    bool Function()? isCancelled,
    FileOperationControl? control,
    bool background = false,
    ArchiveWorkspaceReview? reviewed,
    void Function(ArchivePublicationPhase)? onPhase,
    TransferCheckpoint? beforePublication,
    ArchivePublicationDependency? dependency,
    Object? sourceRemovalAuthority,
    ArchivePublicationDirectoryDependency? directoryDependency,
    Object? directorySyncAuthority,
  }) async {
    _check(writing: true);
    if (control?.isCancelled ?? false) throw const FileOperationCancelled();
    if (isCancelled?.call() ?? false) {
      throw _ArchiveWorkspaceCancelled('Archive update cancelled.');
    }
    if (_sourceRemovalAuthority != null &&
        (!identical(sourceRemovalAuthority, _sourceRemovalAuthority) ||
            dependency == null && _pendingPublication?.dependency == null)) {
      throw StateError(
        'Source removal requires its paired move coordinator and verified destination dependency.',
      );
    }
    if (_directorySyncAuthority != null &&
        (!identical(directorySyncAuthority, _directorySyncAuthority) ||
            jsonEncode(
                  (directoryDependency ??
                          _pendingPublication?.directoryDependency)
                      ?.toJson(),
                ) !=
                jsonEncode(_directorySyncDependency!.toJson()))) {
      throw StateError(
        'Directory synchronization requires its owner and original source-tree dependency.',
      );
    }
    if (_saving) throw StateError('An archive publication is already running.');
    if (!_dirty) {
      await control?.checkpoint();
      _check(writing: true);
      final receipt = await _parentWorkspace?.save(
        isCancelled: isCancelled,
        control: control,
        background: background,
        onPhase: onPhase,
        beforePublication: beforePublication,
        dependency: dependency,
        sourceRemovalAuthority: sourceRemovalAuthority,
        directoryDependency: directoryDependency,
        directorySyncAuthority: directorySyncAuthority,
      );
      if (source is _NestedArchiveBackend) {
        (source as _NestedArchiveBackend)._refreshParentRevision();
      }
      return receipt;
    }
    final selected =
        reviewed ??
        _pendingReview ??
        await review(
          isCancelled: isCancelled,
          control: control,
          background: background,
        );
    _validateReview(selected);
    _saving = true;
    ViewerArchive? replacement;
    ArchivePublicationReceipt? authoritativeReceipt;
    try {
      // A supplied review needs the same synchronous reservation as a newly
      // packed review; pausing Save must not reopen its draft to mutation.
      await control?.checkpoint();
      _check(writing: true);
      if (isCancelled?.call() ?? false) {
        throw _ArchiveWorkspaceCancelled('Archive update cancelled.');
      }
      final checked = await _verifyPacked(
        selected._bytes,
        spool: selected.spool,
        isCancelled: isCancelled,
        control: control,
      );
      replacement = checked.archive;
      final replacementPolicy = checked.policy;
      _validateReview(selected);
      if ((control?.isCancelled ?? false) || (isCancelled?.call() ?? false)) {
        throw const FileOperationCancelled();
      }
      ArchivePublicationReceipt? receipt;
      if (source is _NestedArchiveBackend) {
        final nested = source as _NestedArchiveBackend;
        final current = await _read(
          source,
          file,
          ArchiveService.maxArchiveBytes,
          isCancelled: isCancelled,
          control: control,
        );
        if (sha256.convert(current).toString() != _fingerprint) {
          throw StateError('The nested container changed after review.');
        }
        _validateReview(selected);
        await nested.writeFile(
          file.path!,
          Stream.value(selected.bytes),
          selected.bytes.length,
          replace: true,
        );
        _file = (await nested.stat(file.path!))!;
      } else {
        final publisher = ArchiveContainerPublisher(source, journal);
        try {
          receipt = await publisher.publishStream(
            original: file,
            originalSha256: _fingerprint,
            length: selected.packedBytes,
            candidateSha256: selected.sha256,
            openRead: selected.openRead,
            retry: _pendingPublication,
            isCancelled: () => _closed || (isCancelled?.call() ?? false),
            control: control,
            onPhase: onPhase,
            beforePublication: beforePublication,
            dependency: dependency,
            directoryDependency: directoryDependency,
          );
        } catch (_) {
          _pendingPublication = publisher.activeRecord;
          if (_pendingPublication != null) _pendingReview = selected;
          rethrow;
        }
        authoritativeReceipt = receipt;
        _file = receipt.file;
        _lastReceipt = receipt;
        _lastPublicationWarning = publisher.observerWarning;
      }
      final previous = _archive;
      _archive = replacement;
      _policy = replacementPolicy;
      replacement = null;
      _fingerprint = selected.sha256;
      _loadEntries();
      _dirty = false;
      _pendingPublication = null;
      _pendingReview = null;
      _latestReview = null;
      await previous.close();
      _snapshotSpool = selected.spool;
      for (final stale in _ownedSpools.toList()) {
        if (stale == _snapshotSpool) continue;
        try {
          await stale.dispose();
          _ownedSpools.remove(stale);
        } catch (error) {
          // A verified physical publication stays successful. Retain ownership
          // so close() can retry removing this private stale snapshot.
          _lastPublicationWarning ??= error;
        }
      }
      if (_closed) await _archive.close();
      // A failed enclosing publication retains its already verified child and
      // parent draft. The next explicit save retries the recorded candidate.
      if (_parentWorkspace != null) {
        receipt = await _parentWorkspace!.save(
          isCancelled: isCancelled,
          control: control,
          background: background,
          onPhase: onPhase,
          beforePublication: beforePublication,
          dependency: dependency,
          sourceRemovalAuthority: sourceRemovalAuthority,
          directoryDependency: directoryDependency,
          directorySyncAuthority: directorySyncAuthority,
        );
        authoritativeReceipt = receipt;
        (source as _NestedArchiveBackend)._refreshParentRevision();
      }
      return receipt;
    } catch (error) {
      final committed = authoritativeReceipt;
      if (committed == null) rethrow;
      // The physical container has a verified durable receipt. A view refresh
      // or private cleanup error cannot turn it into a failed publication or
      // invite a retry against the already replaced original.
      outermost._lastPublicationWarning ??= error;
      outermost._lastReceipt = committed;
      _requiresReopen = true;
      return committed;
    } finally {
      await replacement?.close();
      _saving = false;
    }
  }

  /// Discard draft mutations before physical publication starts. An ambiguous
  /// publication must first be reconciled through its durable recovery record.
  void discardDraft() {
    _check();
    if (_saving || pendingPublication != null) {
      throw StateError(
        'Recover the archive publication before discarding this draft.',
      );
    }
    _loadEntries();
    _dirty = false;
  }

  ArchiveOperationBackend get backend => ArchiveOperationBackend(this);

  /// Captures a read-only, revision-bound source. A draft (including a changed
  /// enclosing archive) is never silently treated as the physical original.
  ArchiveWorkspaceSourceSnapshot captureCopySource() {
    _check();
    final generations = <ArchiveWorkspace, int>{};
    ArchiveWorkspace? level = this;
    while (level != null) {
      if (level._dirty || level.pendingPublication != null || level._saving) {
        throw StateError(
          'Save or discard the source archive draft before copying members.',
        );
      }
      generations[level] = level._revision;
      level = level._parentWorkspace;
    }
    return ArchiveWorkspaceSourceSnapshot._(this, generations);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _archive.close();
    } finally {
      try {
        for (final spool in _ownedSpools) {
          await spool.dispose();
        }
        _ownedSpools.clear();
      } finally {
        await _parentWorkspace?.close();
      }
    }
  }
}

/// A capability to replace exactly one nested container in a parent working
/// copy. Other writes stay unavailable and no virtual path reaches a provider.
class _NestedArchiveBackend extends ArchiveOperationBackend {
  _NestedArchiveBackend(super.workspace, this.memberPath)
    : _parentRevision = workspace.revision;
  final String memberPath;
  int _parentRevision;
  @override
  bool get isCurrent =>
      super.isCurrent && workspace.revision == _parentRevision;
  void _refreshParentRevision() => _parentRevision = workspace.revision;

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async {
    if (!replace || path != memberPath) {
      throw StateError('Only the captured nested archive can be replaced.');
    }
    if (!isCurrent) throw StateError('The enclosing archive draft changed.');
    workspace._check(writing: true);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in data) {
      if (!isCurrent) throw StateError('The enclosing archive draft changed.');
      workspace._check(writing: true);
      if (builder.length + chunk.length > kArchiveReadLimit) {
        throw const ArchiveViewException(
          'Nested archive exceeds the 64 MiB member limit.',
        );
      }
      builder.add(chunk);
    }
    workspace._check(writing: true);
    if (!isCurrent) throw StateError('The enclosing archive draft changed.');
    if (length != null && builder.length != length) {
      throw const ArchiveViewException(
        'Nested archive write ended at an unexpected size.',
      );
    }
    workspace.replace(path, builder.takeBytes());
    _refreshParentRevision();
  }
}

class _ArchiveEntry {
  const _ArchiveEntry(
    this.name,
    this.isFolder, {
    this.member,
    this.bytes,
    this.spool,
    this.contentSha256,
    DateTime? modified,
    int? mode,
  }) : _modified = modified, // ignore: prefer_initializing_formals
       _mode = mode; // ignore: prefer_initializing_formals
  final String name;
  final bool isFolder;
  final ViewerArchiveMember? member;
  final Uint8List? bytes;
  final ArchiveOutputSpool? spool;
  final String? contentSha256;
  final DateTime? _modified;
  final int? _mode;
  DateTime? get modified => _modified ?? member?.modified;
  int? get mode => _mode ?? member?.posixMode;
  int get size => spool?.length ?? bytes?.length ?? member?.size ?? 0;
}

enum ArchiveWorkspaceChangeKind {
  add,
  replace,
  rename,
  remove,
  createDirectory,
}

enum ArchiveMemberMoveConflict { fail, keepBoth, skip }

/// Canonical archive-absolute roots affected by one grouped move. Descendants
/// of selected roots are included by that root and are not repeated here.
class ArchiveMemberMoveResult {
  ArchiveMemberMoveResult._(
    Map<String, String> moved,
    List<String> skipped,
    List<String> unchanged,
  ) : moved = Map.unmodifiable(moved),
      skipped = List.unmodifiable(skipped),
      unchanged = List.unmodifiable(unchanged);

  final Map<String, String> moved;
  final List<String> skipped;
  final List<String> unchanged;
}

class ArchiveWorkspaceChange {
  const ArchiveWorkspaceChange(
    this.kind,
    this.path, {
    this.from,
    required this.size,
  });
  final ArchiveWorkspaceChangeKind kind;
  final String path;
  final String? from;
  final int size;
}

class ArchiveWorkspaceImport {
  const ArchiveWorkspaceImport(
    this.path, {
    required this.isFolder,
    this.bytes,
    this.spool,
    this.contentSha256,
    this.modified,
    this.mode,
  });
  final String path;
  final bool isFolder;
  final Uint8List? bytes;

  /// A sealed, verified native snapshot. Ownership transfers only when
  /// [ArchiveWorkspace.applyImport] succeeds.
  final ArchiveOutputSpool? spool;
  final String? contentSha256;
  final DateTime? modified;
  final int? mode;
}

/// Password-free in-memory evidence for one successfully copied source member.
/// This member manifest is not persisted in publication recovery records.
class ArchiveWorkspaceRemoval {
  const ArchiveWorkspaceRemoval({
    required this.path,
    required this.isDirectory,
    required this.size,
    this.sha256,
  });
  final String path;
  final bool isDirectory;
  final int size;
  final String? sha256;
}

class ArchiveWorkspaceReview {
  const ArchiveWorkspaceReview._(
    this.workspace,
    this._generations,
    this._bytes,
    this.changes, {
    this.spool,
    required this.sha256,
  });
  final ArchiveWorkspace workspace;
  final Map<ArchiveWorkspace, int> _generations;
  final Uint8List? _bytes;
  final ArchiveOutputSpool? spool;
  final String sha256;
  Uint8List get bytes =>
      _bytes ??
      (throw StateError(
        'This review is streamed; use openRead instead of allocating its bytes.',
      ));
  Stream<List<int>> openRead() =>
      spool?.openRead() ?? Stream<List<int>>.value(bytes);
  final List<ArchiveWorkspaceChange> changes;
  int get packedBytes => spool?.length ?? bytes.length;
  bool get isCurrent => _generations.entries.every(
    (entry) => entry.key.isCurrent && entry.key._revision == entry.value,
  );
}

class ArchiveNestedPasswordRequiredException
    extends ArchivePasswordRequiredException {
  const ArchiveNestedPasswordRequiredException(
    this.level,
    this.containerName,
    bool wrong,
  ) : super(
        'Enter the original password for this archive level.',
        wrongPassword: wrong,
      );
  final int level;
  final String containerName;
}

/// Read-only transfer source for archive members; extraction reuses the same
/// staged conflict/verification engine as ordinary file copying.
class ArchiveOperationBackend extends FileOperationBackend {
  ArchiveOperationBackend(this.workspace);
  final ArchiveWorkspace workspace;
  @override
  Object get identity => workspace;
  @override
  String get label => workspace.file.name;
  @override
  p.Context get paths => p.posix;
  @override
  String pathKey(String path) {
    if (workspace._policy.format != ArchiveEndpointFormat.dmg || path == '/') {
      return super.pathKey(path);
    }
    final name = workspace._lookupMemberPath(path);
    return paths.isAbsolute(path) ? '/$name' : name;
  }

  @override
  bool get isCurrent => workspace.isCurrent;
  @override
  Future<List<FileItem>> list(String path) async => workspace.list(path);
  @override
  Future<FileItem?> stat(String path) async {
    if (!isCurrent) throw StateError('The archive workspace is closed.');
    if (path == '/') return FileItem(name: '/', path: '/', isFolder: true);
    if (workspace._policy.format == ArchiveEndpointFormat.dmg) {
      path = '/${workspace._lookupMemberPath(path)}';
    }
    for (final item in workspace.list(p.posix.dirname(path))) {
      if (item.path == path) return item;
    }
    return null;
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    yield* workspace.openRead(file.path!);
  }

  /// Archive metadata is optional per member; implicit directories and some
  /// formats have no stored mode. Ordinary extraction retains its conservative
  /// capabilities, while the archive copy transaction imports present values.
  @override
  Future<TransferMetadata> readMetadata(String path) async {
    workspace._check();
    final entry = workspace._entries[workspace._lookupMemberPath(path)];
    return TransferMetadata(mode: entry?.mode, modified: entry?.modified);
  }

  @override
  Future<void> createDirectory(String path) async =>
      throw UnsupportedError('Archive transfer source is read-only.');
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => throw UnsupportedError('Use the archive update workflow.');
  @override
  Future<void> deleteFile(FileItem file) async =>
      throw UnsupportedError('Use the archive update workflow.');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('Use the archive update workflow.');
}

/// Immutable identity for copying the original contents of an open workspace.
/// Byte verification remains the transaction owner's responsibility; this
/// snapshot prevents an in-memory draft, enclosing generation or authority
/// change from being read under the identity of the captured physical source.
class ArchiveWorkspaceSourceSnapshot {
  ArchiveWorkspaceSourceSnapshot._(
    this.workspace,
    Map<ArchiveWorkspace, int> generations,
  ) : _generations = Map.unmodifiable(generations),
      containerBackend = workspace.outermost.source,
      containerFile = _captureSourceFile(workspace.outermost.file),
      fingerprint = workspace.outermost.fingerprint,
      _identity = workspace.outermost.source.identity,
      _storage = workspace.outermost.source.storageReference;

  final ArchiveWorkspace workspace;
  final Map<ArchiveWorkspace, int> _generations;
  final FileOperationBackend containerBackend;
  final FileItem containerFile;
  final String fingerprint;
  final Object _identity;
  final Object? _storage;
  late final ArchiveOperationBackend backend = _ArchiveCopyBackend(this);

  bool get isCurrent =>
      containerBackend.isCurrent &&
      containerBackend.identity == _identity &&
      containerBackend.storageReference == _storage &&
      _generations.entries.every(
        (entry) =>
            entry.key.isCurrent &&
            entry.key._revision == entry.value &&
            !entry.key._dirty &&
            !entry.key._saving &&
            entry.key.pendingPublication == null,
      ) &&
      workspace.outermost.fingerprint == fingerprint &&
      sameArchiveFile(containerFile, workspace.outermost.file);

  void checkCurrent() {
    if (!isCurrent) {
      throw StateError(
        'The captured source archive or its draft changed. Reopen the copy preview.',
      );
    }
  }

  bool sharesContainerWith(ArchiveWorkspace destination) {
    final outer = destination.outermost;
    if (identical(workspace.outermost, outer)) return true;
    final sameStorage =
        _identity == outer.source.identity ||
        _storage != null && _storage == outer.source.storageReference;
    return sameStorage &&
        (containerBackend.samePath(containerFile.path!, outer.file.path!) ||
            outer.source.samePath(containerFile.path!, outer.file.path!));
  }

  static FileItem _captureSourceFile(FileItem file) => file.metadata == null
      ? file
      : file.copyWith(
          metadata: Map.unmodifiable(Map<String, dynamic>.of(file.metadata!)),
        );
}

class _ArchiveCopyBackend extends ArchiveOperationBackend {
  _ArchiveCopyBackend(this.snapshot) : super(snapshot.workspace);
  final ArchiveWorkspaceSourceSnapshot snapshot;
  @override
  bool get isCurrent => snapshot.isCurrent;
  @override
  Future<List<FileItem>> list(String path) async {
    snapshot.checkCurrent();
    final result = await super.list(path);
    snapshot.checkCurrent();
    return result;
  }

  @override
  Future<FileItem?> stat(String path) async {
    snapshot.checkCurrent();
    final result = await super.stat(path);
    snapshot.checkCurrent();
    return result;
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    snapshot.checkCurrent();
    await for (final chunk in super.readFile(file)) {
      snapshot.checkCurrent();
      yield chunk;
    }
    snapshot.checkCurrent();
  }

  @override
  Future<TransferMetadata> readMetadata(String path) async {
    snapshot.checkCurrent();
    final result = await super.readMetadata(path);
    snapshot.checkCurrent();
    return result;
  }
}
