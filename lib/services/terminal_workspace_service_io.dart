import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/file_item.dart';
import '../models/storage_reference.dart';
import 'cloud_storage_interface.dart';
import 'file_operation_backend.dart';
import 'native_file_primitives.dart';
import 'storage_identity.dart';
import 'terminal_workspace_service.dart';

TerminalWorkspaceService createTerminalWorkspaceService({
  String? rootDirectory,
  required int maxEntries,
  required int maxDepth,
  required int maxTotalBytes,
}) => NativeTerminalWorkspaceService(
  rootDirectory: rootDirectory,
  maxEntries: maxEntries,
  maxDepth: maxDepth,
  maxTotalBytes: maxTotalBytes,
);

/// Manifests and sealed upload snapshots are siblings of `files`, never files
/// inside the directory exposed to a shell. The native shell should restrict
/// its filesystem root to [TerminalWorkspace.directoryPath].
class NativeTerminalWorkspaceService extends TerminalWorkspaceService {
  NativeTerminalWorkspaceService({
    String? rootDirectory,
    this.maxEntries = 10000,
    this.maxDepth = 64,
    this.maxTotalBytes = 16 * 1024 * 1024 * 1024,
  }) : _requestedRoot = rootDirectory,
       super.base() {
    if (maxEntries < 1 || maxDepth < 1 || maxTotalBytes < 1) {
      throw ArgumentError('Workspace limits must be positive.');
    }
  }

  final String? _requestedRoot;
  final int maxEntries;
  final int maxDepth;
  final int maxTotalBytes;
  Future<Directory>? _rootFuture;
  final List<String> _warnings = [];
  static final Map<String, Future<void>> _mutations = {};

  @override
  bool get isSupported => true;
  @override
  List<String> get warnings => List.unmodifiable(_warnings);

  Future<Directory> _root() => _rootFuture ??= _createRoot();

  Future<Directory> _createRoot() async {
    final requested = p.absolute(
      _requestedRoot ??
          p.join(
            (await getApplicationDocumentsDirectory()).path,
            'CrispCloudTerminalWorkspaces',
          ),
    );
    if (await FileSystemEntity.type(requested, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const TerminalWorkspaceException(
        'The workspace storage directory is a symbolic link.',
      );
    }
    final directory = await Directory(requested).create(recursive: true);
    return Directory(await directory.resolveSymbolicLinks());
  }

  Future<T> _exclusive<T>(String id, Future<T> Function() operation) async {
    final key = p.join((await _root()).path, id);
    final previous = _mutations[key] ?? Future<void>.value();
    final completed = Completer<void>();
    _mutations[key] = completed.future;
    await previous;
    try {
      return await operation();
    } finally {
      completed.complete();
      if (identical(_mutations[key], completed.future)) _mutations.remove(key);
    }
  }

  /// Validate each component without following symlinks. Canonical containment
  /// is checked as well; a name obtained from a manifest is never trusted.
  Future<String> _safePath(
    String id,
    String relative, {
    bool allowMissing = false,
  }) async {
    validateTerminalWorkspaceId(id);
    validateTerminalWorkspaceRelativePath(relative);
    final root = await _root();
    var current = root.path;
    final components = [id, ...relative.split('/')];
    for (var index = 0; index < components.length; index++) {
      current = p.join(current, components[index]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const TerminalWorkspaceException(
          'Symbolic links cannot be staged or uploaded.',
        );
      }
      if (type == FileSystemEntityType.notFound) {
        if (!allowMissing) {
          throw const TerminalWorkspaceException(
            'A workspace path is missing.',
          );
        }
        continue;
      }
      if (index < components.length - 1 &&
          type != FileSystemEntityType.directory) {
        throw const TerminalWorkspaceException(
          'A workspace parent is not a directory.',
        );
      }
      final real = await (type == FileSystemEntityType.directory
          ? Directory(current).resolveSymbolicLinks()
          : File(current).resolveSymbolicLinks());
      if (!p.isWithin(root.path, real)) {
        throw const TerminalWorkspaceException(
          'A workspace path escaped its storage directory.',
        );
      }
    }
    return current;
  }

  Future<void> _createDirectory(String id, String relative) async {
    final path = await _safePath(id, relative, allowMissing: true);
    await Directory(path).create(recursive: true);
    await _safePath(id, relative);
  }

  Future<TerminalWorkspace> _save(TerminalWorkspace workspace) async {
    final next = workspace.copyWith(
      revision: workspace.revision + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    final payload = jsonEncode(next.toJson());
    final encoded = jsonEncode({
      'payload': payload,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
    });
    final path = await _safePath(next.id, 'manifest.json', allowMissing: true);
    final pending = await _safePath(
      next.id,
      'manifest.pending',
      allowMissing: true,
    );
    await File(pending).writeAsString(encoded, flush: true);
    await _safePath(next.id, 'manifest.pending');
    await _safePath(next.id, 'manifest.json', allowMissing: true);
    await File(pending).rename(path);
    return next;
  }

  @override
  Future<TerminalWorkspace?> load(String id) async {
    validateTerminalWorkspaceId(id);
    TerminalWorkspace? result;
    Object? failure;
    // A fully flushed pending manifest can survive process termination before
    // rename. Prefer its newer revision, but never discard a valid old record.
    for (final name in const ['manifest.json', 'manifest.pending']) {
      try {
        final path = await _safePath(id, name, allowMissing: true);
        if (await FileSystemEntity.type(path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          continue;
        }
        final file = File(path);
        if (await file.length() > 32 * 1024 * 1024) {
          throw const FormatException('Workspace manifest is too large.');
        }
        final envelope = jsonDecode(await file.readAsString()) as Map;
        final payload = envelope['payload'] as String;
        if (envelope['sha256'] !=
            sha256.convert(utf8.encode(payload)).toString()) {
          throw const FormatException('Workspace manifest checksum failed.');
        }
        final directoryPath = await _safePath(id, 'files', allowMissing: true);
        final candidate = TerminalWorkspace.fromJson(
          Map<String, dynamic>.from(jsonDecode(payload) as Map),
          directoryPath: directoryPath,
        );
        if (candidate.id != id ||
            candidate.storage.isLocal ||
            !candidate.storage.persistent ||
            candidate.entries.length > maxEntries) {
          throw const FormatException(
            'Invalid workspace identity or entry count.',
          );
        }
        _validateRemoteScope(candidate.storage, candidate.remoteRoot);
        if (result == null || candidate.revision > result.revision) {
          result = candidate;
        }
      } catch (error) {
        failure = error;
      }
    }
    if (result == null && failure != null) {
      throw TerminalWorkspaceException(
        'Cannot read saved workspace: ${_describe(failure)}',
        workspaceId: id,
      );
    }
    if (result != null && failure != null) {
      _warnings.add(
        '$id: An unreadable journal was retained; the last valid revision was recovered.',
      );
    }
    return result;
  }

  @override
  Future<List<TerminalWorkspace>> list({StorageReference? storage}) async {
    _warnings.clear();
    final root = await _root();
    final workspaces = <TerminalWorkspace>[];
    await for (final entry in root.list(followLinks: false)) {
      final id = p.basename(entry.path);
      if (!RegExp(r'^ws-[0-9a-f-]{36}$').hasMatch(id)) continue;
      try {
        if (entry is! Directory) {
          throw const FormatException(
            'Workspace directory is not a regular directory.',
          );
        }
        final workspace = await load(id);
        if (workspace != null &&
            (storage == null || workspace.storage == storage)) {
          workspaces.add(workspace);
          _warnings.addAll(workspace.warnings);
        }
      } catch (error) {
        _warnings.add('$id: ${_describe(error)}');
      }
    }
    workspaces.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return workspaces;
  }

  void _validateRemoteScope(StorageReference storage, String root) {
    validateTerminalWorkspaceRemoteRoot(root);
    validateTerminalWorkspaceRemoteRoot(p.posix.normalize(storage.root));
    final boundary = p.posix.normalize(storage.root);
    if (root != boundary && !p.posix.isWithin(boundary, root)) {
      throw const TerminalWorkspaceException(
        'The cloud directory is outside the captured account root.',
      );
    }
  }

  void Function() _guard(
    CloudStorageClient client,
    StorageReference storage,
    bool Function() isCurrent,
    bool Function()? isCancelled,
  ) => () {
    if (isCancelled?.call() == true) {
      throw const TerminalWorkspaceException(
        'Workspace operation cancelled. Local work has been retained.',
      );
    }
    if (!isCurrent() ||
        !client.isAuthenticated ||
        storageReferenceForClient(client) != storage) {
      throw const TerminalWorkspaceException(
        'The original cloud account is no longer active. Local work has been retained.',
      );
    }
  };

  Future<TerminalWorkspace> _required(String id) async =>
      await load(id) ??
      (throw TerminalWorkspaceException(
        'The workspace no longer exists.',
        workspaceId: id,
      ));

  @override
  Future<TerminalWorkspace> stage({
    required CloudStorageClient client,
    required String remoteRoot,
    required List<FileItem> items,
    required bool Function() isCurrent,
    StorageReference? storage,
    String? title,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    final captured = storage ?? storageReferenceForClient(client);
    _validateRemoteScope(captured, remoteRoot);
    if (!captured.persistent || captured.isLocal) {
      throw const TerminalWorkspaceException(
        'This cloud account has no persistent identity. Reconnect it before staging files.',
      );
    }
    final check = _guard(client, captured, isCurrent, isCancelled);
    check();
    if (items.isEmpty) {
      throw const TerminalWorkspaceException(
        'Select at least one cloud file or folder.',
      );
    }
    final backend = _WorkspaceCloudBackend(
      client,
      check: check,
      maxEntries: maxEntries,
    );
    final root = await _directory(backend, remoteRoot, check);
    final entries = <TerminalWorkspaceEntry>[];
    final names = <String>{};
    final directoryIds = <String>{};
    var knownBytes = 0;
    Future<void> visit(FileItem item, String relativePath, int depth) async {
      check();
      validateTerminalWorkspaceRelativePath(relativePath);
      if (depth > maxDepth || entries.length >= maxEntries) {
        throw const TerminalWorkspaceException(
          'The workspace folder depth or entry limit was exceeded. Select a smaller folder.',
        );
      }
      if (item.isSymlink == true || !names.add(relativePath.toLowerCase())) {
        throw const TerminalWorkspaceException(
          'The selection contains symbolic links or case-ambiguous names.',
        );
      }
      final fingerprint = TerminalWorkspaceFingerprint.fromFile(item);
      entries.add(
        TerminalWorkspaceEntry(
          relativePath: relativePath,
          remotePath: p.posix.join(remoteRoot, relativePath),
          fingerprint: fingerprint,
        ),
      );
      if (item.isFolder) {
        if (fingerprint.objectId != null &&
            !directoryIds.add(fingerprint.objectId!)) {
          throw const TerminalWorkspaceException(
            'The provider returned a directory cycle or alias.',
          );
        }
        final children = await backend.list(item.path!);
        for (final child in children) {
          await visit(child, '$relativePath/${child.name}', depth + 1);
        }
        final after = await _directory(backend, item.path!, check);
        if (!fingerprint.sameDirectory(
          TerminalWorkspaceFingerprint.fromFile(after),
        )) {
          throw const TerminalWorkspaceException(
            'A selected cloud directory changed identity while staging.',
          );
        }
      } else {
        knownBytes += item.size ?? 0;
        if (knownBytes > maxTotalBytes) {
          throw const TerminalWorkspaceException(
            'The workspace size limit was exceeded. Select fewer files.',
          );
        }
      }
    }

    for (final selected in items) {
      validateTerminalWorkspaceRelativePath(selected.name);
      if (selected.name.contains('/') ||
          selected.isSymlink == true ||
          (selected.storageId != null && selected.storageId != captured.id) ||
          (selected.path != null &&
              selected.path != p.posix.join(remoteRoot, selected.name))) {
        throw const TerminalWorkspaceException(
          'A selected item is outside the captured cloud directory.',
        );
      }
      final current = await backend.stat(
        p.posix.join(remoteRoot, selected.name),
      );
      check();
      if (current == null ||
          current.isFolder != selected.isFolder ||
          (selected.uuid != null && selected.uuid != current.uuid) ||
          (selected.size != null &&
              !selected.isFolder &&
              current.size != selected.size &&
              current.metadata?['size'] != selected.size)) {
        throw const TerminalWorkspaceException(
          'The selected cloud item changed. Refresh the folder and select it again.',
        );
      }
      await visit(current, selected.name, 1);
    }
    check();
    final id = 'ws-${const Uuid().v4()}';
    return _exclusive(id, () async {
      await _createDirectory(id, 'files');
      await _createDirectory(id, 'scratch');
      final now = DateTime.now().toUtc();
      var workspace = await _save(
        TerminalWorkspace(
          id: id,
          title:
              title ??
              (items.length == 1
                  ? items.single.name
                  : '${items.length} cloud items'),
          storage: captured,
          remoteRoot: remoteRoot,
          remoteRootFingerprint: TerminalWorkspaceFingerprint.fromFile(root),
          directoryPath: await _safePath(id, 'files'),
          createdAt: now,
          updatedAt: now,
          revision: 0,
          status: TerminalWorkspaceStatus.staging,
          entries: entries,
        ),
      );
      try {
        workspace = await _stageEntries(workspace, backend, check, onProgress);
        return workspace;
      } catch (error) {
        workspace = await _required(id);
        await _save(
          workspace.copyWith(
            status: TerminalWorkspaceStatus.interrupted,
            error: _describe(error),
          ),
        );
        throw TerminalWorkspaceException(_describe(error), workspaceId: id);
      }
    });
  }

  @override
  Future<TerminalWorkspace> resumeStage({
    required String workspaceId,
    required CloudStorageClient client,
    required bool Function() isCurrent,
    bool Function()? isCancelled,
  }) => _exclusive(workspaceId, () async {
    var workspace = await _required(workspaceId);
    final check = _guard(client, workspace.storage, isCurrent, isCancelled);
    check();
    if (workspace.entries.every(
      (entry) => entry.status == TerminalWorkspaceEntryStatus.ready,
    )) {
      return workspace;
    }
    final backend = _WorkspaceCloudBackend(
      client,
      check: check,
      maxEntries: maxEntries,
    );
    try {
      workspace = await _save(
        workspace.copyWith(
          status: TerminalWorkspaceStatus.staging,
          clearError: true,
        ),
      );
      return await _stageEntries(workspace, backend, check, null);
    } catch (error) {
      workspace = await _required(workspaceId);
      await _save(
        workspace.copyWith(
          status: TerminalWorkspaceStatus.interrupted,
          error: _describe(error),
        ),
      );
      throw TerminalWorkspaceException(
        _describe(error),
        workspaceId: workspaceId,
      );
    }
  });

  Future<TerminalWorkspace> _stageEntries(
    TerminalWorkspace workspace,
    _WorkspaceCloudBackend backend,
    void Function() check,
    void Function(int, int)? onProgress,
  ) async {
    await _checkDirectoryAnchors(workspace, backend, check);
    var totalBytes = workspace.entries.fold<int>(
      0,
      (sum, entry) =>
          sum +
          (entry.status == TerminalWorkspaceEntryStatus.ready
              ? entry.originalSize ?? 0
              : 0),
    );
    for (var index = 0; index < workspace.entries.length; index++) {
      check();
      var entry = workspace.entries[index];
      if (entry.status == TerminalWorkspaceEntryStatus.ready) continue;
      final current = await backend.stat(entry.remotePath);
      if (current == null ||
          current.isSymlink == true ||
          !entry.fingerprint.matches(
            TerminalWorkspaceFingerprint.fromFile(current),
          )) {
        throw TerminalWorkspaceException(
          'Cloud item changed before staging: ${entry.relativePath}',
        );
      }
      if (entry.isDirectory) {
        await _createDirectory(workspace.id, 'files/${entry.relativePath}');
        entry = entry.copyWith(status: TerminalWorkspaceEntryStatus.ready);
      } else {
        final target = await _safePath(
          workspace.id,
          'files/${entry.relativePath}',
          allowMissing: true,
        );
        final existingType = await FileSystemEntity.type(
          target,
          followLinks: false,
        );
        if (existingType != FileSystemEntityType.notFound) {
          // Only a journaled staging receipt can explain an already-present
          // file. Otherwise it may be a user's edit or a filesystem name alias.
          if (existingType != FileSystemEntityType.file) {
            throw TerminalWorkspaceException(
              'An unfinished local file has an incompatible type: ${entry.relativePath}',
            );
          }
          final local = await _hashLocal(
            workspace.id,
            'files/${entry.relativePath}',
            check,
          );
          final remote = await _hashRemote(backend, current, check);
          if (entry.originalDigest == null ||
              entry.originalSize == null ||
              local.digest != entry.originalDigest ||
              local.length != entry.originalSize ||
              local.digest != remote.digest ||
              local.length != remote.length) {
            throw TerminalWorkspaceException(
              'An unfinished local file contains edits. They have been retained: ${entry.relativePath}',
            );
          }
          totalBytes += local.length;
          if (totalBytes > maxTotalBytes) {
            throw const TerminalWorkspaceException(
              'The workspace size limit was exceeded.',
            );
          }
          entry = entry.copyWith(
            status: TerminalWorkspaceEntryStatus.ready,
            originalDigest: local.digest,
            originalSize: local.length,
          );
        } else {
          final temporaryRelative = 'scratch/${const Uuid().v4()}.stage';
          final temporary = File(
            await _safePath(
              workspace.id,
              temporaryRelative,
              allowMissing: true,
            ),
          );
          try {
            final digest = await _writeStream(
              backend.readFile(current),
              temporary,
              check,
              limit: maxTotalBytes - totalBytes,
            );
            final after = await backend.stat(entry.remotePath);
            check();
            if (after == null ||
                after.isSymlink == true ||
                !entry.fingerprint.matches(
                  TerminalWorkspaceFingerprint.fromFile(after),
                ) ||
                (current.size != null && current.size != digest.length)) {
              throw TerminalWorkspaceException(
                'Cloud item changed while downloading: ${entry.relativePath}',
              );
            }
            // Flush the receipt before installing the file. A restart can
            // safely recognize the narrow rename-before-ready crash window.
            entry = entry.copyWith(
              originalDigest: digest.digest,
              originalSize: digest.length,
            );
            final stagedEntries = [...workspace.entries];
            stagedEntries[index] = entry;
            workspace = await _save(workspace.copyWith(entries: stagedEntries));
            await _safePath(
              workspace.id,
              'files/${entry.relativePath}',
              allowMissing: true,
            );
            if (await FileSystemEntity.type(target, followLinks: false) !=
                FileSystemEntityType.notFound) {
              throw TerminalWorkspaceException(
                'A local file appeared while staging: ${entry.relativePath}',
              );
            }
            if (!await moveNativeNoReplace(temporary.path, target)) {
              throw const TerminalWorkspaceException(
                'The local filesystem cannot safely install this staged file without replacing another file.',
              );
            }
            await _safePath(workspace.id, 'files/${entry.relativePath}');
            totalBytes += digest.length;
            entry = entry.copyWith(
              status: TerminalWorkspaceEntryStatus.ready,
              originalDigest: digest.digest,
              originalSize: digest.length,
            );
          } finally {
            await _deleteScratch(workspace.id, temporaryRelative);
          }
        }
      }
      final updated = [...workspace.entries];
      updated[index] = entry;
      workspace = await _save(workspace.copyWith(entries: updated));
      onProgress?.call(index + 1, workspace.entries.length);
    }
    check();
    return _save(
      workspace.copyWith(
        status: TerminalWorkspaceStatus.ready,
        clearError: true,
      ),
    );
  }

  Future<FileItem> _directory(
    _WorkspaceCloudBackend backend,
    String path,
    void Function() check,
  ) async {
    final directory = await backend.stat(path);
    check();
    if (directory == null ||
        !directory.isFolder ||
        directory.isSymlink == true) {
      throw const TerminalWorkspaceException(
        'The captured remote directory is no longer available.',
      );
    }
    return directory;
  }

  Future<void> _checkDirectoryAnchors(
    TerminalWorkspace workspace,
    _WorkspaceCloudBackend backend,
    void Function() check,
  ) async {
    final root = await _directory(backend, workspace.remoteRoot, check);
    if (!workspace.remoteRootFingerprint.sameDirectory(
      TerminalWorkspaceFingerprint.fromFile(root),
    )) {
      throw const TerminalWorkspaceException(
        'The original remote directory changed identity.',
      );
    }
    for (final entry in workspace.entries.where((entry) => entry.isDirectory)) {
      final current = await _directory(backend, entry.remotePath, check);
      if (!entry.fingerprint.sameDirectory(
        TerminalWorkspaceFingerprint.fromFile(current),
      )) {
        throw TerminalWorkspaceException(
          'The original remote directory changed identity: ${entry.relativePath}',
        );
      }
    }
  }

  @override
  Future<List<TerminalWorkspaceChange>> inspect(
    String workspaceId, {
    bool Function()? isCancelled,
  }) async {
    void check() {
      if (isCancelled?.call() == true) {
        throw const TerminalWorkspaceException(
          'Workspace inspection cancelled. Local work has been retained.',
        );
      }
    }

    check();
    final workspace = await _required(workspaceId);
    check();
    final originals = {
      for (final entry in workspace.entries) entry.relativePath: entry,
    };
    final seen = <String>{};
    final names = <String, String>{};
    final ambiguous = <String>{};
    final changes = <TerminalWorkspaceChange>[];
    var count = 0;
    var bytes = 0;
    TerminalWorkspaceChange change(
      String relative,
      TerminalWorkspaceChangeKind kind, {
      bool directory = false,
      _ContentDigest? content,
      String? reason,
    }) => TerminalWorkspaceChange(
      workspaceId: workspaceId,
      manifestRevision: workspace.revision,
      relativePath: relative,
      remotePath: p.posix.join(workspace.remoteRoot, relative),
      kind: kind,
      isDirectory: directory,
      digest: content?.digest,
      size: content?.length,
      reason: reason,
    );
    Future<void> walk(String relative, int depth) async {
      check();
      if (depth > maxDepth) {
        throw const TerminalWorkspaceException(
          'Workspace inspection depth limit exceeded.',
        );
      }
      final path = await _safePath(
        workspaceId,
        relative.isEmpty ? 'files' : 'files/$relative',
      );
      await for (final entity in Directory(path).list(followLinks: false)) {
        check();
        if (++count > maxEntries) {
          throw const TerminalWorkspaceException(
            'Workspace inspection entry limit exceeded.',
          );
        }
        final name = p.basename(entity.path);
        final child = relative.isEmpty ? name : '$relative/$name';
        seen.add(child);
        try {
          validateTerminalWorkspaceRelativePath(child);
          final previous = names[child.toLowerCase()];
          names[child.toLowerCase()] = child;
          if (previous != null) {
            ambiguous.add(child.toLowerCase());
            changes.removeWhere((value) => value.relativePath == previous);
            changes.add(
              change(
                previous,
                TerminalWorkspaceChangeKind.unsafe,
                reason: 'Case-ambiguous local paths cannot be uploaded.',
              ),
            );
            throw const TerminalWorkspaceException(
              'Case-ambiguous local paths cannot be uploaded.',
            );
          }
          final type = await FileSystemEntity.type(
            entity.path,
            followLinks: false,
          );
          final original = originals[child];
          if (type == FileSystemEntityType.link) {
            changes.add(
              change(
                child,
                TerminalWorkspaceChangeKind.unsafe,
                reason: 'Symbolic links are not followed or uploaded.',
              ),
            );
          } else if (type == FileSystemEntityType.directory) {
            if (original != null && !original.isDirectory) {
              changes.add(
                change(
                  child,
                  TerminalWorkspaceChangeKind.unsafe,
                  directory: true,
                  reason: 'A staged file was replaced by a directory.',
                ),
              );
            } else if (original == null) {
              changes.add(
                change(
                  child,
                  TerminalWorkspaceChangeKind.added,
                  directory: true,
                  reason: 'Folders are not created remotely; files inside require an existing remote folder.',
                ),
              );
            }
            await walk(child, depth + 1);
          } else if (type == FileSystemEntityType.file) {
            if (original?.isDirectory == true ||
                original?.status == TerminalWorkspaceEntryStatus.pending) {
              changes.add(
                change(
                  child,
                  TerminalWorkspaceChangeKind.unsafe,
                  reason: 'This path has no completed regular-file baseline. Resume staging first.',
                ),
              );
              continue;
            }
            final digest = await _hashLocal(
              workspaceId,
              'files/$child',
              check,
              limit: maxTotalBytes - bytes,
            );
            bytes += digest.length;
            if (bytes > maxTotalBytes) {
              throw const TerminalWorkspaceException(
                'Workspace inspection size limit exceeded.',
              );
            }
            if (original == null ||
                original.originalDigest != digest.digest ||
                original.originalSize != digest.length) {
              changes.add(
                change(
                  child,
                  original == null || original.originalDigest == null
                      ? TerminalWorkspaceChangeKind.added
                      : TerminalWorkspaceChangeKind.modified,
                  content: digest,
                  reason:
                      p.posix.dirname(child) != '.' &&
                          originals[p.posix.dirname(child)]?.isDirectory != true
                      ? 'The corresponding remote folder must already exist. New local folders are not created remotely.'
                      : null,
                ),
              );
            }
          } else {
            changes.add(
              change(
                child,
                TerminalWorkspaceChangeKind.unsafe,
                reason: 'Only regular files can be uploaded.',
              ),
            );
          }
        } catch (error) {
          // Cancellation is an operation outcome, not an unsafe-file row.
          // Do not continue walking or hashing the remainder of the workspace.
          check();
          changes.add(
            change(
              child,
              TerminalWorkspaceChangeKind.unsafe,
              reason: _describe(error),
            ),
          );
        }
      }
    }

    await walk('', 0);
    for (final original in workspace.entries) {
      check();
      if (!seen.contains(original.relativePath) &&
          original.status == TerminalWorkspaceEntryStatus.ready) {
        changes.add(
          change(
            original.relativePath,
            TerminalWorkspaceChangeKind.deleted,
            directory: original.isDirectory,
            reason: 'Local deletions are never applied to cloud storage.',
          ),
        );
      }
    }
    final reviewed = changes
        .map(
          (value) =>
              ambiguous.any(
                (prefix) =>
                    value.relativePath.toLowerCase() == prefix ||
                    value.relativePath.toLowerCase().startsWith('$prefix/'),
              )
              ? change(
                  value.relativePath,
                  TerminalWorkspaceChangeKind.unsafe,
                  directory: value.isDirectory,
                  reason: 'Case-ambiguous local paths cannot be uploaded.',
                )
              : value,
        )
        .toList();
    reviewed.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    check();
    return List.unmodifiable(reviewed);
  }

  @override
  Future<TerminalWorkspaceUploadResult> uploadReviewed({
    required String workspaceId,
    required CloudStorageClient client,
    required List<TerminalWorkspaceChange> changes,
    required bool Function() isCurrent,
    bool Function()? isCancelled,
  }) => _exclusive(workspaceId, () async {
    var workspace = await _required(workspaceId);
    final check = _guard(client, workspace.storage, isCurrent, isCancelled);
    check();
    final uploaded = <String>[];
    final skipped = <String>[];
    final failures = <String, String>{};
    final selected = <String>{};
    for (final change in changes) {
      validateTerminalWorkspaceRelativePath(change.relativePath);
      if (change.workspaceId != workspaceId ||
          change.manifestRevision != workspace.revision ||
          change.remotePath !=
              p.posix.join(workspace.remoteRoot, change.relativePath) ||
          !selected.add(change.relativePath.toLowerCase())) {
        throw const TerminalWorkspaceException(
          'The upload review is stale or does not belong to this workspace. Review changes again.',
        );
      }
    }
    if (changes.isEmpty) {
      return TerminalWorkspaceUploadResult(
        workspace: workspace,
        uploadedPaths: uploaded,
        skippedPaths: skipped,
        failures: failures,
      );
    }
    final backend = _WorkspaceCloudBackend(
      client,
      check: check,
      maxEntries: maxEntries,
    );
    await _checkDirectoryAnchors(workspace, backend, check);
    // Validate the whole review before any cloud mutation. Each payload is
    // still revalidated when taking its sealed per-file snapshot below.
    final actual = {
      for (final value in await inspect(workspaceId, isCancelled: isCancelled))
        value.relativePath: value,
    };
    for (final change in changes) {
      final current = actual[change.relativePath];
      if (current == null ||
          current.kind != change.kind ||
          current.digest != change.digest ||
          current.size != change.size ||
          current.isDirectory != change.isDirectory) {
        throw const TerminalWorkspaceException(
          'Local files changed after review. Review changes again before uploading.',
        );
      }
    }
    workspace = await _save(
      workspace.copyWith(
        status: TerminalWorkspaceStatus.uploading,
        clearError: true,
      ),
    );
    for (final change in changes) {
      if (!change.canUpload) {
        skipped.add(change.relativePath);
        continue;
      }
      String? snapshotRelative;
      try {
        check();
        await _checkDirectoryAnchors(workspace, backend, check);
        final originalIndex = workspace.entries.indexWhere(
          (entry) => entry.relativePath == change.relativePath,
        );
        TerminalWorkspaceEntry? original = originalIndex < 0
            ? null
            : workspace.entries[originalIndex];
        if ((change.kind == TerminalWorkspaceChangeKind.modified &&
                original == null) ||
            (change.kind == TerminalWorkspaceChangeKind.added &&
                original != null &&
                original.pendingUpload == null)) {
          throw const TerminalWorkspaceException(
            'The reviewed file no longer matches its staging record.',
          );
        }
        snapshotRelative = 'scratch/${const Uuid().v4()}.upload';
        final snapshot = File(
          await _safePath(workspaceId, snapshotRelative, allowMissing: true),
        );
        final digest = await _snapshot(
          workspaceId,
          change.relativePath,
          snapshot,
          check,
        );
        if (digest.digest != change.digest || digest.length != change.size) {
          throw const TerminalWorkspaceException(
            'Local file changed after review. Its edits have been retained; review again.',
          );
        }
        var current = await backend.stat(change.remotePath);
        check();
        // A lost acknowledgement can leave the exact reviewed payload already
        // committed. Reconcile by content, never blindly repeat that mutation.
        final pending = original?.pendingUpload;
        if (pending != null &&
            current != null &&
            !current.isFolder &&
            current.isSymlink != true &&
            pending['digest'] is String &&
            pending['length'] is int) {
          final existingDigest = await _hashRemote(backend, current, check);
          if (existingDigest.digest == pending['digest'] &&
              existingDigest.length == pending['length']) {
            final fresh = (await backend.stat(change.remotePath))!;
            workspace = await _recordUploaded(
              workspace,
              TerminalWorkspaceChange(
                workspaceId: change.workspaceId,
                manifestRevision: change.manifestRevision,
                relativePath: change.relativePath,
                remotePath: change.remotePath,
                kind: change.kind,
                digest: pending['digest'] as String,
                size: pending['length'] as int,
              ),
              fresh,
              backend,
            );
            if (existingDigest.digest == change.digest &&
                existingDigest.length == change.size) {
              uploaded.add(change.relativePath);
              continue;
            }
            // A previous review committed before a lost acknowledgement and
            // the local file has since changed again. Use the confirmed bytes
            // as its baseline while preserving this review's sealed payload.
            original = workspace.entries.firstWhere(
              (entry) => entry.relativePath == change.relativePath,
            );
            current = fresh;
          }
        }
        final restoredPath =
            pending?['restoreCopyPath'] ?? pending?['restoreMovePath'];
        final restoredVersion =
            pending?['restoreCopyVersion'] ?? pending?['restoreMoveVersion'];
        if (pending != null &&
            original?.originalDigest != null &&
            current != null &&
            !current.isFolder &&
            current.isSymlink != true &&
            restoredPath == change.remotePath &&
            restoredVersion is String &&
            TerminalWorkspaceFingerprint.fromFile(current).version ==
                restoredVersion) {
          final restored = await _hashRemote(backend, current, check);
          if (restored.digest == original!.originalDigest &&
              restored.length == original.originalSize) {
            original = original.copyWith(
              fingerprint: TerminalWorkspaceFingerprint.fromFile(current),
            );
            workspace = await _replaceEntry(workspace, original);
          }
        }
        var recoveringBackup = false;
        if (current == null &&
            original?.originalDigest != null &&
            pending != null) {
          final backupPath = _recoveryPath(
            pending['backupPath'],
            change.remotePath,
            backup: true,
          );
          final backupVersion =
              pending['backupVersion'] ?? pending['backupCopyVersion'];
          if (backupPath != null &&
              backupVersion is String &&
              const [
                'backupCopied',
                'backedUp',
                'committing',
                'commitCopied',
              ].contains(pending['phase'])) {
            final backup = await backend.stat(backupPath);
            if (backup != null &&
                !backup.isFolder &&
                backup.isSymlink != true &&
                TerminalWorkspaceFingerprint.fromFile(backup).version ==
                    backupVersion) {
              final backupDigest = await _hashRemote(backend, backup, check);
              if (backupDigest.digest == original!.originalDigest &&
                  backupDigest.length == original.originalSize) {
                recoveringBackup = true;
                final warning =
                    'The interrupted upload retained its original cloud copy at $backupPath. Remove it only after checking the completed upload.';
                workspace = await _save(
                  workspace.copyWith(
                    warnings: {...workspace.warnings, warning}.toList(),
                  ),
                );
                _warnings.add(warning);
              }
            }
          }
        }
        if (original != null && original.originalDigest != null) {
          if (!recoveringBackup &&
              (current == null ||
                  current.isFolder ||
                  current.isSymlink == true ||
                  !original.fingerprint.matches(
                    TerminalWorkspaceFingerprint.fromFile(current),
                  ))) {
            throw const TerminalWorkspaceException(
              'The remote file changed since staging. Local work has been retained; compare the versions before uploading.',
            );
          }
          final remoteDigest = recoveringBackup
              ? null
              : await _hashRemote(backend, current!, check);
          if (remoteDigest != null &&
              (remoteDigest.digest != original.originalDigest ||
                  remoteDigest.length != original.originalSize)) {
            throw const TerminalWorkspaceException(
              'The remote contents changed since staging. Local work has been retained; compare the versions before uploading.',
            );
          }
        } else if (current != null) {
          throw const TerminalWorkspaceException(
            'A remote file already uses this new name. Choose another name or stage that file first.',
          );
        }
        final parent = await backend.stat(p.posix.dirname(change.remotePath));
        check();
        if (parent == null) {
          throw const TerminalWorkspaceException(
            'The remote parent folder does not exist. Create it remotely before uploading files inside it. Local work has been retained.',
          );
        }
        if (!parent.isFolder || parent.isSymlink == true) {
          throw const TerminalWorkspaceException(
            'The remote parent is not a regular directory. Local work has been retained.',
          );
        }
        _requireSafeCommit(
          backend,
          replacing: current != null,
          current: current,
        );
        if (original?.pendingUpload != null) {
          workspace = await _rememberRecoveryCopies(
            workspace,
            original!,
            backend,
          );
        }
        final receipt = <String, dynamic>{
          'digest': change.digest,
          'length': change.size,
          'phase': 'prepared',
          'destination': change.remotePath,
        };
        original ??= TerminalWorkspaceEntry(
          relativePath: change.relativePath,
          remotePath: change.remotePath,
          fingerprint: TerminalWorkspaceFingerprint(isDirectory: false),
          status: TerminalWorkspaceEntryStatus.ready,
        );
        workspace = await _replaceEntry(
          workspace,
          original.copyWith(pendingUpload: receipt),
        );
        final baseline = current == null
            ? null
            : TerminalWorkspaceFingerprint.fromFile(current);
        final baselineDigest = original.originalDigest;
        await backend.writePreparedFile(
          change.remotePath,
          _snapshotStream(workspaceId, snapshotRelative, check),
          change.size,
          replace: current != null,
          verifyStaged: (staged) async {
            final verified = await _hashRemote(backend, staged, check);
            if (verified.digest != change.digest ||
                verified.length != change.size) {
              throw const TerminalWorkspaceException(
                'The uploaded temporary file failed its content check.',
              );
            }
          },
          checkpoint: (state) async {
            check();
            if (state['phase'] == 'backingUp' && baseline != null) {
              final beforeBackup = await backend.stat(change.remotePath);
              if (beforeBackup == null ||
                  beforeBackup.isSymlink == true ||
                  !baseline.matches(
                    TerminalWorkspaceFingerprint.fromFile(beforeBackup),
                  )) {
                throw const TerminalWorkspaceException(
                  'The remote file changed while uploading. Local work has been retained.',
                );
              }
              final freshDigest = await _hashRemote(
                backend,
                beforeBackup,
                check,
              );
              if (freshDigest.digest != baselineDigest) {
                throw const TerminalWorkspaceException(
                  'The remote contents changed while uploading. Local work has been retained.',
                );
              }
            }
            final recorded = workspace.entries.firstWhere(
              (entry) => entry.relativePath == change.relativePath,
            );
            workspace = await _replaceEntry(
              workspace,
              recorded.copyWith(
                pendingUpload: {
                  ...receipt,
                  ...recorded.pendingUpload!,
                  ...state,
                },
              ),
            );
          },
        );
        check();
        current = await backend.stat(change.remotePath);
        if (current == null || current.isFolder || current.isSymlink == true) {
          throw const TerminalWorkspaceException(
            'The uploaded destination could not be confirmed. Review this workspace again to recover.',
          );
        }
        final committed = await _hashRemote(backend, current, check);
        if (committed.digest != change.digest ||
            committed.length != change.size) {
          throw const TerminalWorkspaceException(
            'The remote destination changed during upload verification. Local work has been retained.',
          );
        }
        final after = (await backend.stat(change.remotePath))!;
        workspace = await _recordUploaded(workspace, change, after, backend);
        uploaded.add(change.relativePath);
      } catch (error) {
        failures[change.relativePath] = _describe(error);
        // Stop after account/cancellation changes. Do not even clean up a
        // remote temporary file against a replacement account.
        try {
          check();
        } catch (_) {
          for (final remaining in changes.where(
            (item) =>
                item.canUpload &&
                !uploaded.contains(item.relativePath) &&
                !failures.containsKey(item.relativePath),
          )) {
            failures[remaining.relativePath] = _describe(error);
          }
          break;
        }
      } finally {
        if (snapshotRelative != null) {
          await _deleteScratch(workspaceId, snapshotRelative);
        }
      }
    }
    workspace = await _save(
      workspace.copyWith(
        status: failures.isEmpty
            ? TerminalWorkspaceStatus.ready
            : TerminalWorkspaceStatus.interrupted,
        clearError: failures.isEmpty,
        error: failures.isEmpty
            ? null
            : failures.entries
                  .map((entry) => '${entry.key}: ${entry.value}')
                  .join('\n'),
      ),
    );
    return TerminalWorkspaceUploadResult(
      workspace: workspace,
      uploadedPaths: uploaded,
      skippedPaths: skipped,
      failures: failures,
    );
  });

  void _requireSafeCommit(
    _WorkspaceCloudBackend backend, {
    required bool replacing,
    FileItem? current,
  }) {
    final capabilities = backend.capabilities;
    final conditionalCopy =
        capabilities.nativeCopy &&
        capabilities.noReplaceCopy &&
        capabilities.conditionalCopy &&
        capabilities.conditionalDelete;
    final exactMove =
        capabilities.nativeMove &&
        capabilities.atomicMove &&
        capabilities.noReplaceMove;
    // The transfer backend prefers native move when both routes exist. Its
    // chosen route must protect the captured source and backup cleanup too.
    final safeReplacement = exactMove
        ? capabilities.conditionalMove && capabilities.conditionalDelete
        : conditionalCopy;
    if (backend.client is! CloudTransferOperations ||
        (!conditionalCopy && !exactMove) ||
        (replacing && !safeReplacement)) {
      throw TerminalWorkspaceException(
        replacing
            ? '${backend.label} cannot atomically protect an existing file from concurrent changes. '
                  'Your edited file is retained locally. Upload under a new unused name on a provider with exact no-replace uploads, or use a provider with conditional replacement support.'
            : '${backend.label} cannot guarantee an exact upload without replacing another file. '
                  'Your new file is retained locally. Use a provider with exact no-replace uploads.',
      );
    }
    if (replacing &&
        TerminalWorkspaceFingerprint.fromFile(current!).version == null) {
      throw const TerminalWorkspaceException(
        'This remote file has no revision token for a conditional replacement. Local work has been retained.',
      );
    }
  }

  Future<TerminalWorkspace> _replaceEntry(
    TerminalWorkspace workspace,
    TerminalWorkspaceEntry entry,
  ) {
    final entries = [...workspace.entries];
    final index = entries.indexWhere(
      (value) => value.relativePath == entry.relativePath,
    );
    if (index < 0) {
      if (entries.length >= maxEntries) {
        throw const TerminalWorkspaceException(
          'The workspace manifest entry limit was exceeded. Stage a smaller selection before adding more files.',
        );
      }
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    return _save(workspace.copyWith(entries: entries));
  }

  String? _recoveryPath(
    Object? value,
    String destination, {
    required bool backup,
  }) {
    if (value is! String ||
        p.posix.dirname(value) != p.posix.dirname(destination)) {
      return null;
    }
    final pattern = backup
        ? r'^\.crisp-replaced-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.bak$'
        : r'^\.crisp-transfer-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.tmp$';
    return RegExp(pattern).hasMatch(p.posix.basename(value)) ? value : null;
  }

  Future<TerminalWorkspace> _recordUploaded(
    TerminalWorkspace workspace,
    TerminalWorkspaceChange change,
    FileItem remote,
    _WorkspaceCloudBackend backend,
  ) async {
    final existing = workspace.entries
        .where((entry) => entry.relativePath == change.relativePath)
        .firstOrNull;
    if (existing != null) {
      workspace = await _rememberRecoveryCopies(workspace, existing, backend);
    }
    return _replaceEntry(
      workspace,
      TerminalWorkspaceEntry(
        relativePath: change.relativePath,
        remotePath: change.remotePath,
        fingerprint: TerminalWorkspaceFingerprint.fromFile(remote),
        status: TerminalWorkspaceEntryStatus.ready,
        originalDigest: change.digest,
        originalSize: change.size,
      ),
    );
  }

  Future<TerminalWorkspace> _rememberRecoveryCopies(
    TerminalWorkspace workspace,
    TerminalWorkspaceEntry entry,
    _WorkspaceCloudBackend backend,
  ) async {
    final receipt = entry.pendingUpload;
    final warnings = {...workspace.warnings};
    if (receipt != null) {
      for (final backup in [true, false]) {
        final path = _recoveryPath(
          receipt[backup ? 'backupPath' : 'stagedPath'],
          entry.remotePath,
          backup: backup,
        );
        if (path == null) continue;
        try {
          if (await backend.stat(path) == null) continue;
          warnings.add(
            'A recovery copy remains at $path. Remove it only after checking the completed upload.',
          );
        } catch (_) {
          warnings.add(
            'Check whether a recovery copy remains at $path before cleaning up this upload.',
          );
        }
      }
    }
    _warnings.addAll(
      warnings.where((warning) => !workspace.warnings.contains(warning)),
    );
    return warnings.length == workspace.warnings.length
        ? workspace
        : _save(workspace.copyWith(warnings: warnings.toList()));
  }

  Future<_ContentDigest> _snapshot(
    String id,
    String relative,
    File target,
    void Function() check,
  ) async {
    final source = await _safePath(id, 'files/$relative');
    if (await FileSystemEntity.type(source, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const TerminalWorkspaceException(
        'Only regular local files may be uploaded.',
      );
    }
    final before = await File(source).stat();
    final digest = await _writeStream(
      File(source).openRead(),
      target,
      check,
      limit: maxTotalBytes,
    );
    await _safePath(id, 'files/$relative');
    final after = await File(source).stat();
    if (before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed ||
        after.size != digest.length) {
      throw const TerminalWorkspaceException(
        'The local file changed while taking its upload snapshot. Review changes again.',
      );
    }
    return digest;
  }

  Stream<List<int>> _snapshotStream(
    String id,
    String relative,
    void Function() check,
  ) async* {
    final path = await _safePath(id, relative);
    await for (final chunk in File(path).openRead()) {
      check();
      yield chunk;
    }
    await _safePath(id, relative);
    check();
  }

  Future<_ContentDigest> _hashLocal(
    String id,
    String relative,
    void Function() check, {
    int? limit,
  }) async {
    final path = await _safePath(id, relative);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const TerminalWorkspaceException(
        'Only regular workspace files may be read.',
      );
    }
    final before = await File(path).stat();
    final result = await _hashStream(
      File(path).openRead(),
      check,
      limit: limit ?? maxTotalBytes,
    );
    await _safePath(id, relative);
    final after = await File(path).stat();
    if (before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed ||
        after.size != result.length) {
      throw const TerminalWorkspaceException(
        'A local file changed during inspection. Review it again.',
      );
    }
    return result;
  }

  Future<_ContentDigest> _hashRemote(
    _WorkspaceCloudBackend backend,
    FileItem file,
    void Function() check,
  ) async {
    if (file.isFolder || file.isSymlink == true) {
      throw const TerminalWorkspaceException(
        'The cloud item is not a regular file.',
      );
    }
    final before = TerminalWorkspaceFingerprint.fromFile(file);
    final result = await _hashStream(
      backend.readFile(file),
      check,
      limit: maxTotalBytes,
    );
    final after = await backend.stat(file.path!);
    check();
    if (after == null ||
        after.isSymlink == true ||
        !before.matches(TerminalWorkspaceFingerprint.fromFile(after)) ||
        (file.size != null && file.size != result.length)) {
      throw const TerminalWorkspaceException(
        'The remote file changed while checking its contents.',
      );
    }
    return result;
  }

  Future<_ContentDigest> _hashStream(
    Stream<List<int>> stream,
    void Function() check, {
    required int limit,
  }) async {
    var length = 0;
    final result = await sha256
        .bind(
          stream.map((chunk) {
            check();
            length += chunk.length;
            if (length > limit) {
              throw const TerminalWorkspaceException(
                'The workspace size limit was exceeded.',
              );
            }
            return chunk;
          }),
        )
        .first;
    check();
    return _ContentDigest(result.toString(), length);
  }

  Future<_ContentDigest> _writeStream(
    Stream<List<int>> stream,
    File target,
    void Function() check, {
    required int limit,
  }) async {
    final result = _DigestSink();
    final hash = sha256.startChunkedConversion(result);
    final sink = target.openWrite();
    var length = 0;
    try {
      await sink.addStream(
        stream.map((chunk) {
          check();
          length += chunk.length;
          if (length > limit) {
            throw const TerminalWorkspaceException(
              'The workspace size limit was exceeded.',
            );
          }
          hash.add(chunk);
          return chunk;
        }),
      );
      await sink.flush();
      check();
    } catch (error, stack) {
      try {
        await sink.close();
      } catch (_) {
        // A failed source stream can close the sink itself. Preserve the
        // original transfer failure, rather than replacing it with "closed".
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      hash.close();
    }
    await sink.close();
    return _ContentDigest(result.value!.toString(), length);
  }

  Future<void> _deleteScratch(String id, String relative) async {
    try {
      final path = await _safePath(id, relative, allowMissing: true);
      if (await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.file) {
        await File(path).delete();
      }
    } catch (_) {
      // Never follow a substituted path to clean up. Unfinished local scratch
      // files remain isolated from the shell workspace and its change review.
    }
  }

  String _describe(Object error) {
    var message = error is TerminalWorkspaceException
        ? error.message
        : error.toString();
    // Persist readable failure recovery without signed URLs or URL credentials.
    message = message.replaceAll(
      RegExp(r'https?://[^\s)]+'),
      '[remote endpoint]',
    );
    return message.length > 2000 ? '${message.substring(0, 2000)}…' : message;
  }
}

class _ContentDigest {
  const _ContentDigest(this.digest, this.length);
  final String digest;
  final int length;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Retains the existing cloud transfer transaction, while requiring complete,
/// validated, fresh directory listings for workspace conflict decisions.
class _WorkspaceCloudBackend extends CloudOperationBackend {
  _WorkspaceCloudBackend(
    super.client, {
    required this.check,
    required this.maxEntries,
  }) : super(
         isCurrent: () {
           try {
             check();
             return true;
           } catch (_) {
             return false;
           }
         },
       );
  final void Function() check;
  final int maxEntries;

  @override
  Future<List<FileItem>> list(String path) async {
    check();
    final result = await client.listPathForEdit(path);
    check();
    for (final key in const [
      'nextPageToken',
      'nextMarker',
      'continuationToken',
      'nextContinuationToken',
      'nextLink',
      '@odata.nextLink',
      'cursor',
    ]) {
      final value = result[key];
      if (value != null && value != '' && value != false) {
        throw const TerminalWorkspaceException(
          'The cloud directory listing is incomplete. No workspace changes were uploaded.',
        );
      }
    }
    if (result['hasMore'] == true ||
        result['has_more'] == true ||
        result['isTruncated'] == true ||
        result['truncated'] == true ||
        result['complete'] == false ||
        result['success'] == false ||
        result['error'] != null ||
        result['folders'] is! List ||
        result['files'] is! List) {
      throw const TerminalWorkspaceException(
        'The cloud directory could not be listed completely.',
      );
    }
    final entries = <FileItem>[];
    final names = <String>{};
    for (final group in const ['folders', 'files']) {
      for (final raw in result[group] as List) {
        if (entries.length >= maxEntries) {
          throw const TerminalWorkspaceException(
            'The cloud listing entry limit was exceeded.',
          );
        }
        final item = Map<String, dynamic>.from(raw as Map);
        var name = item['name']?.toString() ?? '';
        final fileType = item['fileType']?.toString() ?? '';
        if (group == 'files' &&
            fileType.isNotEmpty &&
            fileType.toLowerCase() != 'file' &&
            !name.toLowerCase().endsWith('.${fileType.toLowerCase()}')) {
          name = '$name.$fileType';
        }
        validateTerminalWorkspaceRelativePath(name);
        if (name.contains('/') || !names.add(name.toLowerCase())) {
          throw const TerminalWorkspaceException(
            'The cloud directory contains ambiguous filenames.',
          );
        }
        final nested = item['metadata'];
        final declared =
            item['downloadSize'] ??
            (nested is Map ? nested['downloadSize'] : null);
        final rawSize = declared ?? item['size'];
        if (rawSize != null &&
            (rawSize is! num ||
                !rawSize.isFinite ||
                rawSize < 0 ||
                rawSize != rawSize.toInt())) {
          throw const TerminalWorkspaceException(
            'The cloud directory returned an invalid file length.',
          );
        }
        final rawDate =
            item['modificationTime'] ??
            item['lastModified'] ??
            item['timestamp'] ??
            item['updatedAt'];
        final modified = rawDate is DateTime
            ? rawDate
            : rawDate is num
            ? DateTime.fromMillisecondsSinceEpoch(rawDate.toInt())
            : rawDate == null
            ? null
            : DateTime.tryParse(rawDate.toString());
        entries.add(
          FileItem(
            name: name,
            path: p.posix.join(path, name),
            isFolder: group == 'folders',
            uuid: item['uuid']?.toString(),
            size: rawSize == null ? null : (rawSize as num).toInt(),
            updatedAt: modified,
            isSymlink: item['isSymlink'] == true,
            metadata: item,
          ),
        );
      }
    }
    return entries;
  }
}
