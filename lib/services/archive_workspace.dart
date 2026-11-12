import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/archive_endpoint.dart';
import 'archive_container_publisher.dart';
import 'archive_endpoint_policy.dart';
import 'archive_write_model.dart';
import 'archive_writer_service.dart';
import 'archive_zip_package_policy.dart';
import 'archive_publication_journal.dart';
import 'archive_browser_session.dart';
import 'archive_member_index.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';
import 'file_operation_service.dart';
import 'storage_transfer_contract.dart';

class ArchiveWorkspace {
  ArchiveWorkspace._(
    this.source,
    this._file,
    this._archive,
    this._fingerprint,
    this.password,
    this._policy,
    this.journal,
  ) {
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
  final _entries = <String, _ArchiveEntry>{};
  bool _closed = false;
  bool _dirty = false;
  bool _saving = false;
  int _revision = 0;
  ArchiveWorkspaceReview? _pendingReview;
  ArchivePublicationRecord? _pendingPublication;
  ArchivePublicationReceipt? _lastReceipt;
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
  }) async {
    if (!source.isCurrent) throw StateError('The archive source changed.');
    if ((file.size ?? 0) > limit) {
      throw const ArchiveViewException('Archive input exceeds its size limit.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source.readFile(file)) {
      if (!source.isCurrent) throw StateError('The archive source changed.');
      if (isCancelled?.call() ?? false) {
        throw StateError('Archive operation cancelled.');
      }
      if (builder.length + chunk.length > limit) {
        throw const ArchiveViewException(
          'Archive input exceeds its size limit.',
        );
      }
      builder.add(chunk);
    }
    if (!source.isCurrent) throw StateError('The archive source changed.');
    if (isCancelled?.call() ?? false) {
      throw StateError('Archive operation cancelled.');
    }
    return builder.takeBytes();
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
        final relative = ArchiveService.safeMemberPath(memberPath);
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
    final archive = await openViewerArchive(
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
    _validateEntries(_entries);
    _revision++;
  }

  static void _validateEntries(Map<String, _ArchiveEntry> entries) {
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
      if (total > ArchiveService.maxExtractedBytes) {
        throw const ArchiveViewException('Archive contents exceed 256 MiB.');
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
    _validateEntries(entries);
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
    if (!isCurrent) throw StateError('The original archive source changed.');
    if (writing && !canUpdate) throw UnsupportedError(updateSupport);
  }

  List<FileItem> list([String path = '/']) {
    _check();
    final prefix = path == '/'
        ? ''
        : '${path.replaceFirst(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '')}/';
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
          'version': entry.bytes == null
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
    final name = path.replaceFirst(RegExp(r'^/+'), '');
    final entry = _entries[name];
    if (entry == null || entry.isFolder) {
      throw StateError('Not an archive file: $path');
    }
    return entry.bytes ?? _archive.readMember(entry.member!);
  }

  void replace(String path, Uint8List bytes, {DateTime? modified, int? mode}) {
    _check(writing: true);
    final name = ArchiveService.safeMemberPath(
      path.replaceFirst(RegExp(r'^/+'), ''),
    );
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
    final name = ArchiveService.safeMemberPath(
      path.replaceFirst(RegExp(r'^/+'), ''),
    );
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
    for (final item in items) {
      final name = ArchiveService.safeMemberPath(
        item.path.replaceFirst(RegExp(r'^/+'), ''),
      );
      final previous = updated[name];
      if (previous != null && previous.isFolder != item.isFolder) {
        throw StateError('Archive member type changed: $name');
      }
      if (!item.isFolder &&
          (item.bytes == null || item.bytes!.length > kArchiveReadLimit)) {
        throw const ArchiveViewException(
          'An imported member exceeds its size limit.',
        );
      }
      updated[name] = _ArchiveEntry(
        name,
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
    }
    if (items.isNotEmpty) _publish(updated);
  }

  void remove(Iterable<String> paths) {
    _check(writing: true);
    final updated = Map.of(_entries);
    for (final path in paths) {
      final name = ArchiveService.safeMemberPath(
        path.replaceFirst(RegExp(r'^/+'), ''),
      );
      updated.removeWhere((key, _) => key == name || key.startsWith('$name/'));
    }
    _publish(updated);
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
        throw StateError('Archive move cancelled.');
      }
      final original = await read(entry.source.path!);
      final target = await plan.destination.stat(entry.destination);
      if (target == null || target.isFolder || target.isSymlink == true) {
        throw StateError(
          'The copied destination is missing: ${entry.destination}',
        );
      }
      final copied = await _read(
        plan.destination,
        target,
        kArchiveReadLimit,
        isCancelled: isCancelled,
      );
      final after = await plan.destination.stat(entry.destination);
      if (!plan.destination.isCurrent ||
          after == null ||
          after.uuid != target.uuid ||
          after.size != target.size ||
          after.updatedAt != target.updatedAt ||
          sha256.convert(original).toString() !=
              sha256.convert(copied).toString()) {
        throw StateError(
          'The copied destination changed: ${entry.destination}',
        );
      }
      final name = entry.source.path!.replaceFirst(RegExp(r'^/+'), '');
      if (updated.remove(name) != null) removed++;
    }
    // A directory can disappear only when every remaining child is gone.
    // Filtering or skipped conflicts therefore never delete uncopied members.
    final folders =
        plan.entries
            .where((entry) => entry.source.isFolder && entry.completed)
            .map((entry) => entry.source.path!.replaceFirst(RegExp(r'^/+'), ''))
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final folder in folders) {
      if (!updated.keys.any((path) => path.startsWith('$folder/'))) {
        if (updated.remove(folder) != null) removed++;
      }
    }
    _check(writing: true);
    if (isCancelled?.call() ?? false) {
      throw StateError('Archive move cancelled.');
    }
    if (removed > 0) _publish(updated);
    return removed;
  }

  void rename(String path, String newPath) {
    _check(writing: true);
    final from = ArchiveService.safeMemberPath(
      path.replaceFirst(RegExp(r'^/+'), ''),
    );
    final target = ArchiveService.safeMemberPath(newPath);
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
        modified: entry.value.modified,
        mode: entry.value.mode,
      );
    }
    _publish(updated);
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
    final visited = <String>{};
    var total = _entries.values.fold<int>(0, (sum, entry) => sum + entry.size);
    Future<void> add(FileItem file, String name, int depth) async {
      _check(writing: true);
      if (!input.isCurrent) throw StateError('The added-file source changed.');
      if (isCancelled?.call() ?? false) {
        throw StateError('Archive update cancelled.');
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
      name = ArchiveService.safeMemberPath(name);
      if (staged.containsKey(name)) return;
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
    for (final file in files) {
      await add(file, '$prefix${file.name}', 0);
    }
    _publish({..._entries, ...staged});
  }

  Future<Uint8List> repack({bool Function()? isCancelled}) async {
    _check(writing: true);
    void checkPacking() {
      _check(writing: true);
      if (isCancelled?.call() ?? false) {
        throw StateError('Archive update cancelled.');
      }
    }

    checkPacking();
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
    final entries = [
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
                  yield await read('/${entry.name}');
                },
        ),
    ];
    final packageIssue = await archiveZipPackageIssue(file.name, entries);
    if (packageIssue != null) throw ArchiveViewException(packageIssue);
    return collectArchiveWrite(
      (sink) => writeArchiveEntries(
        _policy.format,
        entries,
        sink: sink,
        source: _policy.inspection,
        compression: _policy.compression,
        singlePayload: _policy.singlePayload,
        gzipHeader: _policy.gzipHeader,
        xzCheck: _policy.xzCheck,
        password: encrypted ? password : null,
        encryptNames: encryptNames,
        maxOutputBytes: ArchiveService.maxArchiveBytes,
        isCancelled: () {
          checkPacking();
          return false;
        },
      ),
      maxBytes: ArchiveService.maxArchiveBytes,
    );
  }

  /// Packs and verifies a concrete review snapshot. Later edits invalidate it.
  Future<ArchiveWorkspaceReview> review({bool Function()? isCancelled}) async {
    _check(writing: true);
    if (_saving) {
      throw StateError('The archive is already preparing a publication.');
    }
    if (_pendingPublication != null && _pendingReview != null) {
      return _pendingReview!;
    }
    final generations = <ArchiveWorkspace, int>{};
    ArchiveWorkspace? level = this;
    while (level != null) {
      generations[level] = level._revision;
      level = level._parentWorkspace;
    }
    _saving = true;
    try {
      final bytes = await repack(isCancelled: isCancelled);
      final checked = await _verifyPacked(bytes, isCancelled: isCancelled);
      await checked.close();
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
        if (entry.bytes != null || original == null) {
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
      final result = ArchiveWorkspaceReview._(
        this,
        generations,
        bytes.asUnmodifiableView(),
        List.unmodifiable(changes),
      );
      _validateReview(result);
      return result;
    } finally {
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

  Future<ViewerArchive> _verifyPacked(
    Uint8List bytes, {
    bool Function()? isCancelled,
  }) async {
    final replacement = await openViewerArchive(
      bytes,
      name: file.name,
      password: password,
    );
    try {
      final actual = ArchiveMemberIndex(replacement).members;
      if (_entries.length != actual.length ||
          !_entries.keys.toSet().containsAll(actual.keys)) {
        throw const ArchiveViewException(
          'Repacked archive members could not be verified.',
        );
      }
      for (final item in actual.entries) {
        _check(writing: true);
        if (isCancelled?.call() ?? false) throw const FileOperationCancelled();
        final expected = _entries[item.key]!;
        final member = item.value;
        if (member.isFile == expected.isFolder ||
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
          final decoded = await replacement.readMember(member);
          final original = await read('/${item.key}');
          if (sha256.convert(decoded) != sha256.convert(original) ||
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
      final policy = await ArchiveEndpointPolicy.inspect(
        bytes,
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
      return replacement;
    } catch (_) {
      await replacement.close();
      rethrow;
    }
  }

  /// Returns only after the outermost physical container has a verified,
  /// durable publication receipt. Nested member writes alone are never success.
  Future<ArchivePublicationReceipt?> save({
    bool Function()? isCancelled,
    ArchiveWorkspaceReview? reviewed,
    void Function(ArchivePublicationPhase)? onPhase,
    TransferCheckpoint? beforePublication,
  }) async {
    _check(writing: true);
    if (_saving) throw StateError('An archive publication is already running.');
    if (!_dirty) {
      final receipt = await _parentWorkspace?.save(
        isCancelled: isCancelled,
        onPhase: onPhase,
        beforePublication: beforePublication,
      );
      if (source is _NestedArchiveBackend) {
        (source as _NestedArchiveBackend)._refreshParentRevision();
      }
      return receipt;
    }
    final selected =
        reviewed ?? _pendingReview ?? await review(isCancelled: isCancelled);
    _validateReview(selected);
    _saving = true;
    ViewerArchive? replacement;
    try {
      replacement = await _verifyPacked(
        selected.bytes,
        isCancelled: isCancelled,
      );
      final replacementPolicy = await ArchiveEndpointPolicy.inspect(
        selected.bytes,
        file.name,
        replacement,
        password,
      );
      _validateReview(selected);
      if (isCancelled?.call() ?? false) throw const FileOperationCancelled();
      ArchivePublicationReceipt? receipt;
      if (source is _NestedArchiveBackend) {
        final nested = source as _NestedArchiveBackend;
        final current = await _read(
          source,
          file,
          ArchiveService.maxArchiveBytes,
          isCancelled: isCancelled,
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
          receipt = await publisher.publish(
            original: file,
            originalSha256: _fingerprint,
            bytes: selected.bytes,
            retry: _pendingPublication,
            isCancelled: () => _closed || (isCancelled?.call() ?? false),
            onPhase: onPhase,
            beforePublication: beforePublication,
          );
        } catch (_) {
          _pendingPublication = publisher.activeRecord;
          if (_pendingPublication != null) _pendingReview = selected;
          rethrow;
        }
        _file = receipt.file;
        _lastReceipt = receipt;
      }
      final previous = _archive;
      _archive = replacement;
      _policy = replacementPolicy;
      replacement = null;
      _fingerprint = sha256.convert(selected.bytes).toString();
      _loadEntries();
      _dirty = false;
      _pendingPublication = null;
      _pendingReview = null;
      await previous.close();
      if (_closed) await _archive.close();
      // A failed enclosing publication retains its already verified child and
      // parent draft. The next explicit save retries the recorded candidate.
      if (_parentWorkspace != null) {
        receipt = await _parentWorkspace!.save(
          isCancelled: isCancelled,
          onPhase: onPhase,
          beforePublication: beforePublication,
        );
        (source as _NestedArchiveBackend)._refreshParentRevision();
      }
      return receipt;
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
      await _parentWorkspace?.close();
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
    DateTime? modified,
    int? mode,
  }) : _modified = modified, // ignore: prefer_initializing_formals
       _mode = mode; // ignore: prefer_initializing_formals
  final String name;
  final bool isFolder;
  final ViewerArchiveMember? member;
  final Uint8List? bytes;
  final DateTime? _modified;
  final int? _mode;
  DateTime? get modified => _modified ?? member?.modified;
  int? get mode => _mode ?? member?.posixMode;
  int get size => bytes?.length ?? member?.size ?? 0;
}

enum ArchiveWorkspaceChangeKind {
  add,
  replace,
  rename,
  remove,
  createDirectory,
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
    this.modified,
    this.mode,
  });
  final String path;
  final bool isFolder;
  final Uint8List? bytes;
  final DateTime? modified;
  final int? mode;
}

class ArchiveWorkspaceReview {
  const ArchiveWorkspaceReview._(
    this.workspace,
    this._generations,
    this.bytes,
    this.changes,
  );
  final ArchiveWorkspace workspace;
  final Map<ArchiveWorkspace, int> _generations;
  final Uint8List bytes;
  final List<ArchiveWorkspaceChange> changes;
  int get packedBytes => bytes.length;
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
  bool get isCurrent => workspace.isCurrent;
  @override
  Future<List<FileItem>> list(String path) async => workspace.list(path);
  @override
  Future<FileItem?> stat(String path) async {
    if (!isCurrent) throw StateError('The archive workspace is closed.');
    if (path == '/') return FileItem(name: '/', path: '/', isFolder: true);
    for (final item in workspace.list(p.posix.dirname(path))) {
      if (item.path == path) return item;
    }
    return null;
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    yield await workspace.read(file.path!);
  }

  /// Archive metadata is optional per member; implicit directories and some
  /// formats have no stored mode. Ordinary extraction retains its conservative
  /// capabilities, while the archive copy transaction imports present values.
  @override
  Future<TransferMetadata> readMetadata(String path) async {
    workspace._check();
    final entry = workspace._entries[path.replaceFirst(RegExp(r'^/+'), '')];
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
