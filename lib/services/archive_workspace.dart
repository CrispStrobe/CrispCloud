import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'archive_browser_session.dart';
import 'archive_member_index.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';
import 'file_operation_service.dart';

class ArchiveWorkspace {
  ArchiveWorkspace._(
    this.source,
    this.file,
    this._archive,
    this._fingerprint,
    this.password,
  ) {
    _loadEntries();
  }
  final FileOperationBackend source;
  final FileItem file;
  ViewerArchive _archive;
  String _fingerprint;
  final String? password;
  final _entries = <String, _ArchiveEntry>{};
  bool _closed = false;
  bool _dirty = false;
  ArchiveWorkspace? _parentWorkspace;
  bool get dirty => _dirty || (_parentWorkspace?.dirty ?? false);
  bool get isCurrent => !_closed && source.isCurrent;
  String get format => _archive.formatName;
  bool get encrypted => _archive.members.any((member) => member.isEncrypted);
  bool get canUpdate {
    if (_parentWorkspace?.canUpdate == false) return false;
    final name = file.name.toLowerCase();
    return name.endsWith('.zip') ||
        name.endsWith('.7z') ||
        name.endsWith('.tar') ||
        name.endsWith('.tar.gz') ||
        name.endsWith('.tgz');
  }

  String get updateSupport => _parentWorkspace?.canUpdate == false
      ? 'The enclosing archive cannot be repacked. Browsing and extraction are available.'
      : canUpdate
      ? 'Edit, add, rename and delete members; save repacks the archive.'
      : 'This format supports browsing and extraction. Repacking is unavailable.';

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
    String? expectedOuterFingerprint,
  }) async {
    if (nestedMembers.length >= kArchiveNestingLimit) {
      throw const ArchiveViewException(
        'Archive nesting is limited to 8 levels.',
      );
    }
    var workspace = await open(
      source,
      file,
      password: password,
      expectedFingerprint: expectedOuterFingerprint,
    );
    try {
      for (final memberPath in nestedMembers) {
        final relative = ArchiveService.safeMemberPath(memberPath);
        final backend = _NestedArchiveBackend(workspace, '/$relative');
        final member = await backend.stat('/$relative');
        if (member == null || member.isFolder) {
          throw ArchiveViewException(
            'Nested archive no longer exists: $memberPath',
          );
        }
        final child = await open(backend, member, password: password);
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
  }) async {
    final bytes = await _read(source, file, ArchiveService.maxArchiveBytes);
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
      final encrypted = archive.members.where((member) => member.isEncrypted);
      if (encrypted.isNotEmpty) {
        if (password == null) {
          throw const ArchivePasswordRequiredException(
            'Enter the archive password before editing or extracting members.',
          );
        }
        // Validate a supplied password before allowing replacement of every
        // encrypted entry, which otherwise could silently change the password.
        await archive.readMember(encrypted.first);
      }
      return ArchiveWorkspace._(
        source,
        file,
        archive,
        sha256.convert(bytes).toString(),
        password,
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
  }

  static void _validateEntries(Map<String, _ArchiveEntry> entries) {
    if (entries.length > 200000) {
      throw const ArchiveViewException(
        'Archive exceeds the 200,000 member limit.',
      );
    }
    var total = 0;
    for (final entry in entries.values) {
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
    _validateEntries(entries);
    _entries
      ..clear()
      ..addAll(entries);
    _dirty = true;
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
        updatedAt: entry.member?.modified,
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

  void replace(String path, Uint8List bytes) {
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
    );
    _publish(updated);
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
        staged[name] = _ArchiveEntry(name, true);
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
        staged[name] = _ArchiveEntry(name, false, bytes: bytes);
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
    final lower = file.name.toLowerCase();
    final koni.ArchiveWriteFormat writerFormat = lower.endsWith('.zip')
        ? const koni.ZipWriteFormat()
        : lower.endsWith('.7z')
        ? const koni.SevenZWriteFormat()
        : const koni.TarWriteFormat();
    final sink = _BoundedArchiveSink();
    final writer = koni.Archive.create(
      sink,
      format: writerFormat,
      options: koni.ArchiveWriteOptions(
        password: encrypted ? password : null,
        encryptHeader: encrypted && lower.endsWith('.7z'),
      ),
    );
    try {
      var total = 0;
      final entries = _entries.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (final entry in entries) {
        _check(writing: true);
        if (isCancelled?.call() ?? false) {
          throw StateError('Archive update cancelled.');
        }
        final spec = koni.ArchiveEntrySpec(
          path: entry.name,
          type: entry.isFolder
              ? koni.ArchiveEntryType.directory
              : koni.ArchiveEntryType.file,
          modified: entry.member?.modified?.toUtc(),
          posixMode: entry.member?.posixMode,
        );
        if (entry.isFolder) {
          await writer.addEntry(spec);
        } else {
          final bytes = await read('/${entry.name}');
          total += bytes.length;
          if (total > ArchiveService.maxExtractedBytes) {
            throw const ArchiveViewException(
              'Archive contents exceed 256 MiB.',
            );
          }
          await writer.addBytes(spec, bytes);
        }
      }
      await writer.close();
      await sink.close();
      final bytes = sink.takeBytes();
      final result = lower.endsWith('.tar.gz') || lower.endsWith('.tgz')
          ? Uint8List.fromList(const codecs.GZipEncoder().encode(bytes))
          : bytes;
      if (result.length > ArchiveService.maxArchiveBytes) {
        throw const ArchiveViewException('Packed archive exceeds 256 MiB.');
      }
      return result;
    } catch (_) {
      await sink.close();
      rethrow;
    }
  }

  Future<void> save({bool Function()? isCancelled}) async {
    _check(writing: true);
    if (!_dirty) {
      await _parentWorkspace?.save(isCancelled: isCancelled);
      return;
    }
    final bytes = await repack(isCancelled: isCancelled);
    final current = await _read(
      source,
      file,
      ArchiveService.maxArchiveBytes,
      isCancelled: isCancelled,
    );
    if (sha256.convert(current).toString() != _fingerprint) {
      throw StateError(
        'The original archive changed. Save was refused; reopen it before editing.',
      );
    }
    if (isCancelled?.call() ?? false) {
      throw StateError('Archive update cancelled.');
    }
    // Verify the generated archive before committing it to the source.
    final replacement = await openViewerArchive(
      bytes,
      name: file.name,
      password: password,
    );
    try {
      final expected = _entries.keys.toSet();
      final actual = replacement.members
          .where((member) => member.name != '/')
          .map((member) => ArchiveService.safeMemberPath(member.name))
          .toSet();
      if (expected.length != actual.length || !expected.containsAll(actual)) {
        throw const ArchiveViewException(
          'Repacked archive members could not be verified.',
        );
      }
      for (final member in replacement.members.where(
        (member) => member.isFile,
      )) {
        if (isCancelled?.call() ?? false) {
          throw StateError('Archive update cancelled.');
        }
        final decoded = await replacement.readMember(member);
        final original = await read('/${member.name}');
        if (sha256.convert(decoded) != sha256.convert(original) ||
            (encrypted && !member.isEncrypted)) {
          throw ArchiveViewException(
            'Repacked member verification failed: ${member.name}',
          );
        }
      }
      _check(writing: true);
      if (source.supportsStagedVerification) {
        await source.writePreparedFile(
          file.path!,
          Stream.value(bytes),
          bytes.length,
          replace: true,
          verifyStaged: (staged) async {
            _check(writing: true);
            final prepared = await _read(
              source,
              staged,
              ArchiveService.maxArchiveBytes,
              isCancelled: isCancelled,
            );
            if (sha256.convert(prepared) != sha256.convert(bytes)) {
              throw const ArchiveViewException(
                'Uploaded archive verification failed before replacement.',
              );
            }
            final latest = await _read(
              source,
              file,
              ArchiveService.maxArchiveBytes,
              isCancelled: isCancelled,
            );
            if (sha256.convert(latest).toString() != _fingerprint) {
              throw StateError(
                'The original archive changed while saving. It was not replaced.',
              );
            }
          },
        );
      } else {
        await source.writeFile(
          file.path!,
          Stream.value(bytes),
          bytes.length,
          replace: true,
        );
      }
      final verified = await _read(
        source,
        file.copyWith(size: bytes.length),
        ArchiveService.maxArchiveBytes,
      );
      if (sha256.convert(verified).toString() !=
          sha256.convert(bytes).toString()) {
        throw StateError('Saved archive verification failed.');
      }
      await _archive.close();
      _archive = replacement;
      _fingerprint = sha256.convert(bytes).toString();
      _loadEntries();
      _dirty = false;
    } catch (_) {
      await replacement.close();
      rethrow;
    }
    // Keep a staged parent dirty if its save fails. A retry can commit the
    // already-verified child without closing or repacking the child again.
    await _parentWorkspace?.save(isCancelled: isCancelled);
  }

  ArchiveOperationBackend get backend => ArchiveOperationBackend(this);

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
  _NestedArchiveBackend(super.workspace, this.memberPath);
  final String memberPath;

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
    workspace._check(writing: true);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in data) {
      workspace._check(writing: true);
      if (builder.length + chunk.length > kArchiveReadLimit) {
        throw const ArchiveViewException(
          'Nested archive exceeds the 64 MiB member limit.',
        );
      }
      builder.add(chunk);
    }
    workspace._check(writing: true);
    if (length != null && builder.length != length) {
      throw const ArchiveViewException(
        'Nested archive write ended at an unexpected size.',
      );
    }
    workspace.replace(path, builder.takeBytes());
  }
}

class _ArchiveEntry {
  const _ArchiveEntry(this.name, this.isFolder, {this.member, this.bytes});
  final String name;
  final bool isFolder;
  final ViewerArchiveMember? member;
  final Uint8List? bytes;
  int get size => bytes?.length ?? member?.size ?? 0;
}

class _BoundedArchiveSink implements koni.ByteSink {
  final _sink = koni.BytesBuilderSink();
  @override
  int get length => _sink.length;
  @override
  Future<void> add(Uint8List bytes) {
    if (length + bytes.length > ArchiveService.maxArchiveBytes) {
      throw const ArchiveViewException('Packed archive exceeds 256 MiB.');
    }
    return _sink.add(bytes);
  }

  @override
  Future<void> close() => _sink.close();
  Uint8List takeBytes() => _sink.takeBytes();
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
