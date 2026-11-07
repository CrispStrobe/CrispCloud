import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/storage_reference.dart';
import 'file_operation_options.dart';
import 'destination_name_mask.dart';
import 'duplicate_name_template.dart';
import 'file_selection_pattern.dart';
import 'storage_transfer_contract.dart';
import 'stream_rate_limiter.dart';
import 'storage_scan_source.dart';

export 'file_operation_options.dart';

/// Storage adapter whose identity and authentication are captured before work.
/// [stat] and [list] must propagate access/network errors, never report them as
/// missing files. writeFile must not delete an existing destination on failure.
abstract class FileOperationBackend implements StorageScanSource {
  @override
  Object get identity;
  String? get persistentStorageId => null;
  StorageReference? get storageReference => null;
  bool get canRecover => false;

  /// The verifier runs against a complete temporary file before replacement.
  bool get supportsStagedVerification => false;
  StorageTransferCapabilities get capabilities =>
      const StorageTransferCapabilities();
  String get label;
  @override
  p.Context get paths;
  @override
  String pathKey(String path) => paths.normalize(path);

  /// Collision comparison may be more conservative than source identity.
  /// Never use this key to discard case-distinct selected source items.
  String destinationPathKey(String path) => pathKey(path);
  @override
  bool samePath(String first, String second) =>
      pathKey(first) == pathKey(second);
  @override
  bool isWithin(String parent, String child) =>
      paths.isWithin(pathKey(parent), pathKey(child));
  @override
  bool get isCurrent;
  bool get supportsModifiedTime => false;
  @override
  bool get supportsSymbolicLinks => false;

  /// Listing-backed metadata can share fresh directory snapshots during
  /// preview. Execution always calls [stat] again without that cache.
  bool get statRequiresDirectoryListing => false;
  bool isRootPath(String path) => paths.dirname(path) == path;
  @override
  Future<FileItem?> stat(String path);
  @override
  Future<List<FileItem>> list(String path);
  Future<void> createDirectory(String path);
  Stream<List<int>> readFile(FileItem file);
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  });
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    await checkpoint?.call({'phase': 'writing', 'destination': path});
    await writeFile(path, data, length, replace: replace);
    final result = await stat(path);
    if (verifyStaged != null && result != null) await verifyStaged(result);
    await checkpoint?.call({'phase': 'committed', 'destination': path});
  }

  Future<bool> moveNoReplace(FileItem file, String destination) async => false;
  Future<bool> hasPendingUpload(String path, {int? length}) async => false;
  Future<bool> copyNative(
    FileItem file,
    String destination, {
    required bool replace,
    TransferCheckpoint? checkpoint,
  }) async => false;

  Future<void> writeConfiguredFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    bool preallocate = false,
    String? resumeUploadPath,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    if (preallocate) {
      throw UnsupportedError('This storage cannot reserve disk space.');
    }
    if (resumeUploadPath != null) {
      throw UnsupportedError('This storage cannot resume a saved upload.');
    }
    await writePreparedFile(
      path,
      data,
      length,
      replace: replace,
      verifyStaged: verifyStaged,
      checkpoint: checkpoint,
    );
  }

  Future<bool> clonePreparedFile(
    FileItem source,
    String destination, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async => false;
  Future<void> renameExisting(FileItem file, String destination) async {
    if (!await moveNoReplace(file, destination)) {
      throw UnsupportedError(
        'This storage cannot safely rename an occupied target.',
      );
    }
  }

  Future<TransferMetadata> readMetadata(String path) async =>
      const TransferMetadata();

  /// Read only the fields requested by a transfer. Native adapters override
  /// this to avoid probing unrelated filesystem features (for example ACLs
  /// when the user only requested permissions).
  Future<TransferMetadata> readMetadataFields(
    String path, {
    bool permissions = true,
    bool modified = true,
    bool accessed = true,
    bool created = true,
    bool ownership = true,
    bool extendedAttributes = true,
    bool acl = true,
    bool windowsAttributes = true,
  }) async {
    final metadata = await readMetadata(path);
    return TransferMetadata(
      mode: permissions ? metadata.mode : null,
      modified: modified ? metadata.modified : null,
      accessed: accessed ? metadata.accessed : null,
      created: created ? metadata.created : null,
      owner: ownership ? metadata.owner : null,
      group: ownership ? metadata.group : null,
      extendedAttributes: extendedAttributes
          ? metadata.extendedAttributes
          : const {},
      acl: acl ? metadata.acl : null,
      windowsAttributes: windowsAttributes ? metadata.windowsAttributes : null,
      windowsAttributesMask: metadata.windowsAttributesMask,
    );
  }

  Future<void> writeMetadata(String path, TransferMetadata metadata) async =>
      throw UnsupportedError(
        'This storage cannot preserve the requested metadata.',
      );
  Stream<List<int>> readRange(FileItem file, int offset) async* {
    var remaining = offset;
    await for (final chunk in readFile(file)) {
      if (remaining >= chunk.length) {
        remaining -= chunk.length;
      } else {
        yield remaining == 0 ? chunk : chunk.sublist(remaining);
        remaining = 0;
      }
    }
    if (remaining != 0) {
      throw StateError('Source is shorter than the resume offset.');
    }
  }

  Future<void> deleteFile(FileItem file);
  Future<void> deleteEmptyDirectory(String path);
  Future<void> setModified(String path, DateTime modified) async =>
      throw UnsupportedError(
        'This storage cannot preserve modification times.',
      );
  Future<void> copySymbolicLink(
    FileItem source,
    String destination, {
    required bool replace,
  }) async =>
      throw UnsupportedError('This storage cannot create symbolic links.');
}

class FileOperationEntry {
  FileOperationEntry(this.source, this.destination, {this.existing});
  final FileItem source;
  String destination;
  FileItem? existing;
  FileOperationOutcome outcome = FileOperationOutcome.pending;
  String? message;
  Map<String, dynamic>? recovery;
  bool get failed =>
      outcome == FileOperationOutcome.failed ||
      outcome == FileOperationOutcome.metadataFailed;
  bool get completed =>
      outcome == FileOperationOutcome.copied ||
      outcome == FileOperationOutcome.moved ||
      outcome == FileOperationOutcome.directoryCreated;
}

class FileOperationPlan {
  FileOperationPlan({
    required this.source,
    required this.destination,
    required this.targetDirectory,
    required this.options,
    required this.entries,
    required this.errors,
    this.protectedDestinationPaths = const [],
  });
  final FileOperationBackend source;
  final FileOperationBackend destination;
  final String targetDirectory;
  final FileOperationOptions options;
  final List<FileOperationEntry> entries;
  final List<String> errors;

  /// Selected sources belonging to this destination account, including sources
  /// captured by other groups in a mixed-account collection operation.
  final List<String> protectedDestinationPaths;

  bool overlapsProtectedDestination(String path) {
    final key = destination.destinationPathKey(path);
    return protectedDestinationPaths.any((root) {
      final protected = destination.destinationPathKey(root);
      return key == protected ||
          destination.paths.isWithin(protected, key) ||
          destination.paths.isWithin(key, protected);
    });
  }

  void assertDestinationUnprotected(String path) {
    if (overlapsProtectedDestination(path)) {
      throw StateError(
        'Destination overlaps another selected source: $path. '
        'Choose another name or directory.',
      );
    }
  }

  bool get canExecute =>
      errors.isEmpty &&
      entries.any((entry) => entry.outcome == FileOperationOutcome.pending);
  int get fileCount => entries
      .where(
        (entry) =>
            !entry.source.isFolder &&
            entry.outcome == FileOperationOutcome.pending,
      )
      .length;
  int get totalBytes => entries
      .where(
        (entry) =>
            !entry.source.isFolder &&
            entry.outcome == FileOperationOutcome.pending,
      )
      .fold(0, (sum, entry) => sum + (entry.source.size ?? 0));
}

class FileOperationControl implements StreamRateControl {
  bool _cancelled = false;
  final Completer<void> _cancellation = Completer<void>();
  final StreamController<void> _changeEvents = StreamController<void>.broadcast(
    sync: true,
  );
  Future<void> get cancellationFuture => _cancellation.future;
  @override
  Stream<void> get changes => _changeEvents.stream;
  Completer<void>? _paused;
  @override
  bool get isCancelled => _cancelled;
  @override
  bool get isPaused => _paused != null;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_cancellation.isCompleted) _cancellation.complete();
    final pause = _paused;
    _paused = null;
    pause?.complete();
    _changeEvents.add(null);
  }

  void pause() {
    if (_cancelled || _paused != null) return;
    _paused = Completer<void>();
    _changeEvents.add(null);
  }

  void resume() {
    final pause = _paused;
    if (pause == null) return;
    _paused = null;
    pause.complete();
    _changeEvents.add(null);
  }

  @override
  Future<void> checkpoint() async {
    if (_cancelled) throw const FileOperationCancelled();
    await _paused?.future;
    if (_cancelled) throw const FileOperationCancelled();
  }

  /// Cancel a pending source read as well as a stream that is yielding chunks.
  /// A provider's asynchronous cleanup cannot hold the queue cancellation open.
  Stream<T> bind<T>(Stream<T> input) {
    late StreamController<T> output;
    StreamSubscription<T>? source;
    StreamSubscription<void>? cancelled;
    void stopSource() {
      final pending = source?.cancel();
      if (pending != null) unawaited(pending.catchError((Object _) {}));
      unawaited(cancelled?.cancel());
    }

    output = StreamController<T>(
      onListen: () {
        if (_cancelled) {
          output.addError(const FileOperationCancelled());
          unawaited(output.close());
          return;
        }
        cancelled = _changeEvents.stream.listen((_) {
          if (!_cancelled) return;
          if (!output.isClosed) {
            output.addError(const FileOperationCancelled());
            unawaited(output.close());
          }
          stopSource();
        });
        source = input.listen(
          (value) {
            if (!output.isClosed) output.add(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!output.isClosed) output.addError(error, stack);
          },
          onDone: () {
            unawaited(cancelled?.cancel());
            if (!output.isClosed) unawaited(output.close());
          },
        );
        if (output.isPaused) source!.pause();
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: stopSource,
    );
    return output.stream;
  }
}

class FileOperationCancelled implements Exception {
  const FileOperationCancelled();
  @override
  String toString() => 'Cancelled';
}

class FileOperationMetadataFailure implements Exception {
  const FileOperationMetadataFailure(this.error);
  final Object error;
  @override
  String toString() =>
      'Contents copied; metadata could not be preserved: $error';
}

/// Decisions returned by the conflict UI. Cancel stops the entire job.
enum FileConflictDecision {
  skip,
  replace,
  keepBoth,
  merge,
  cancel,
  renameSource,
  renameDestination,
  resumeVerified,
  append,
}

class FileConflictResolution {
  const FileConflictResolution(
    this.decision, {
    this.name,
    this.applyToAll = false,
  });
  final FileConflictDecision decision;
  final String? name;
  final bool applyToAll;
}

typedef DetailedFileConflictResolver = Future<FileConflictResolution> Function(
  FileOperationEntry entry,
  FileItem existing,
);

class FileOperationNeedsDecision implements Exception {
  const FileOperationNeedsDecision();
  @override
  String toString() => 'Waiting for a conflict decision.';
}

typedef FileConflictResolver = Future<FileConflictDecision> Function(
  FileOperationEntry entry,
  FileItem existing,
);

/// Previews all paths, then executes in order. Directory moves are file-by-file:
/// only empty source directories are removed, so filters/skips never lose data.
class FileOperationService {
  const FileOperationService({
    this.rateLimiterFactory = createStreamRateLimiter,
  });

  final StreamRateLimiter Function(int bytesPerSecond) rateLimiterFactory;

  void _checkSources(FileOperationBackend source, FileOperationBackend target) {
    if (!source.isCurrent || !target.isCurrent) {
      throw StateError('The storage account changed. Reopen the operation.');
    }
  }

  Future<FileOperationPlan> prepare({
    required List<FileItem> files,
    required FileOperationBackend source,
    required FileOperationBackend destination,
    required String targetDirectory,
    FileOperationOptions options = const FileOperationOptions(),
    FileOperationControl? control,
    List<String> protectedDestinationPaths = const [],
    int maxEntries = 200000,
    int maxDepth = 256,
    void Function(int scanned, String path)? onPlanningProgress,
  }) async {
    final entries = <FileOperationEntry>[];
    final errors = <String>[];
    final target = destination.paths.normalize(targetDirectory);
    final plan = FileOperationPlan(
      source: source,
      destination: destination,
      targetDirectory: target,
      options: options,
      entries: entries,
      errors: errors,
      protectedDestinationPaths: List.unmodifiable(protectedDestinationPaths),
    );
    _checkSources(source, destination);
    if (maxEntries <= 0 || maxDepth < 0) {
      errors.add(
        'Planning limits must allow at least one item and a non-negative depth.',
      );
      return plan;
    }
    final sourceMetadata = _PlanningMetadata(source, maxEntries);
    final targetMetadata = _PlanningMetadata(destination, maxEntries);
    options.validateSearchCriteria();
    options.validateTransferSettings();
    final duplicateNames = DuplicateNameTemplate(options.duplicateNameTemplate);
    final criteria = options.searchCriteria;
    final criteriaMatcher = criteria?.nameMatcher;
    final criteriaExcluded =
        criteria == null || criteria.excludeDirectories.isEmpty
        ? null
        : FileSelectionPattern(
            criteria.excludeDirectories,
            caseSensitive: criteria.caseSensitive,
            matchFullPath: criteria.excludeDirectories.contains('/'),
          );
    if (targetDirectory.trim().isEmpty ||
        !destination.paths.isAbsolute(target)) {
      errors.add('Choose an absolute destination directory.');
      return plan;
    }
    if (protectedDestinationPaths.any(
      (path) => !destination.paths.isAbsolute(path) || path.contains('\u0000'),
    )) {
      errors.add('Protected source paths must be absolute paths.');
      return plan;
    }
    if (options.preserveModified && !destination.supportsModifiedTime) {
      errors.add('The destination cannot preserve modification times.');
    }
    if (options.preallocate && !destination.capabilities.preallocate) {
      errors.add('The destination cannot reserve physical disk space.');
    }
    if (options.copyMethod == FileCopyMethod.copyOnWrite) {
      if (source.identity != destination.identity ||
          !destination.capabilities.copyOnWrite) {
        errors.add(
          'Copy-on-write requires the same native filesystem backend.',
        );
      }
      if (options.preallocate) {
        errors.add(
          'Full allocation cannot be combined with a required copy-on-write clone.',
        );
      }
      if (options.fileConflict == FileConflictPolicy.append ||
          options.fileConflict == FileConflictPolicy.resumeVerified) {
        errors.add(
          'Append and partial-file resume cannot require copy-on-write.',
        );
      }
    }
    if (options.copySymbolicLinks &&
        (!source.supportsSymbolicLinks || !destination.supportsSymbolicLinks)) {
      errors.add('Copying symbolic links requires two local filesystems.');
    }
    if ((options.minimumSize != null && options.minimumSize! < 0) ||
        (options.maximumSize != null && options.maximumSize! < 0) ||
        (options.minimumSize != null &&
            options.maximumSize != null &&
            options.minimumSize! > options.maximumSize!) ||
        (options.modifiedAfter != null &&
            options.modifiedBefore != null &&
            options.modifiedAfter!.isAfter(options.modifiedBefore!))) {
      errors.add('The size or date filter range is invalid.');
    }
    final nameMask = DestinationNameMask(options.destinationMask);
    if (options.destinationName != null) {
      DestinationNameMask.validateName(options.destinationName!);
      if (files.where((file) => file.name != '..').length != 1) {
        errors.add('An exact destination name requires one selected item.');
      }
    }
    for (final requirement in [
      (
        options.preservePermissions,
        source.capabilities.permissions && destination.capabilities.permissions,
        'permissions',
      ),
      (
        options.preserveOwnership,
        source.capabilities.ownership && destination.capabilities.ownership,
        'ownership',
      ),
      (
        options.preserveExtendedAttributes,
        source.capabilities.extendedAttributes &&
            destination.capabilities.extendedAttributes,
        'extended attributes',
      ),
      (
        options.preserveAcl,
        source.capabilities.accessControlLists &&
            destination.capabilities.accessControlLists,
        'access control lists',
      ),
      (
        options.preserveWindowsAttributes,
        source.capabilities.windowsAttributes &&
            destination.capabilities.windowsAttributes,
        'Windows attributes',
      ),
    ]) {
      if (requirement.$1 && !requirement.$2) {
        errors.add('Both storages must support preserving ${requirement.$3}.');
      }
    }
    final base = options.relativeBase;
    if (options.preserveRelativePaths &&
        (base == null || !source.paths.isAbsolute(base))) {
      errors.add('Choose an absolute source base for relative paths.');
      return plan;
    }
    final roots = <String, FileItem>{};
    for (final file in files) {
      if (file.name == '..') continue;
      final path = file.path;
      if (path == null || !source.paths.isAbsolute(path)) {
        errors.add('No absolute source path for ${file.name}.');
        continue;
      }
      roots.putIfAbsent(source.paths.normalize(path), () => file);
      if (roots.length > maxEntries) {
        errors.add('Selection exceeds the preview limit of $maxEntries items.');
        return plan;
      }
    }
    // Selecting a folder and a child must process the child only once.
    final selectedDirectories = {
      if (options.recursive)
        for (final entry in roots.entries)
          if (entry.value.isFolder && entry.value.isSymlink != true)
            source.pathKey(entry.key),
    };
    final unique = roots.entries.where((candidate) {
      var parent = source.paths.dirname(candidate.key);
      while (parent != candidate.key) {
        if (selectedDirectories.contains(source.pathKey(parent))) return false;
        final next = source.paths.dirname(parent);
        if (next == parent) break;
        parent = next;
      }
      return true;
    }).toList();
    final destinations = <String, FileOperationEntry>{};
    final reservedDestinations = <String>{};
    final nextCopySuffix = <String, int>{};
    final visited = <String>{};
    var fileIndex = 0;

    Future<void> walk(
      FileItem listed,
      String output,
      int depth, {
      bool freshlyListed = false,
    }) async {
      await control?.checkpoint();
      _checkSources(source, destination);
      final path = source.paths.normalize(listed.path!);
      if (visited.contains(source.pathKey(path))) return;
      if (visited.length >= maxEntries) {
        throw _PlanningLimitReached(
          'Preview exceeds $maxEntries items. Select a smaller scope or raise the item limit.',
        );
      }
      if (depth > maxDepth) {
        throw _PlanningLimitReached(
          'Preview exceeds $maxDepth folder levels at $path.',
        );
      }
      visited.add(source.pathKey(path));
      onPlanningProgress?.call(visited.length, path);
      if (visited.length % 256 == 0) {
        // Yield to UI input even when in-memory/cached metadata futures finish
        // synchronously. Pause and cancellation remain responsive in big trees.
        await Future<void>.delayed(Duration.zero);
        await control?.checkpoint();
      }
      final current = freshlyListed ? listed : await sourceMetadata.stat(path);
      _checkSources(source, destination);
      if (current == null) {
        errors.add('Source no longer exists: $path');
        return;
      }
      final file = current.copyWith(path: path);
      String? duplicateNameBase;
      if (!file.isFolder &&
          !(options.destinationName != null && roots.containsKey(path))) {
        output = destination.paths.join(
          destination.paths.dirname(output),
          nameMask.apply(file.name, index: ++fileIndex),
        );
      }
      if (source.identity == destination.identity &&
          source.samePath(path, output) &&
          !file.isFolder &&
          options.kind == FileOperationKind.copy &&
          options.fileConflict == FileConflictPolicy.keepBoth) {
        duplicateNameBase = output;
        output = await _availableName(
          output,
          destination,
          template: duplicateNames,
          reserved: reservedDestinations,
          stat: targetMetadata.stat,
          nextSuffix: nextCopySuffix,
        );
      }
      if (source.identity == destination.identity &&
          (source.samePath(path, output) ||
              (file.isFolder && source.isWithin(path, output)))) {
        errors.add('Cannot copy or move an item into itself: $path');
        return;
      }
      final entry = FileOperationEntry(file, output);
      if (duplicateNameBase != null) {
        entry.recovery = {'duplicateNameBase': duplicateNameBase};
      }
      entries.add(entry);
      if (file.isSymlink == true && !options.copySymbolicLinks) {
        entry.outcome = FileOperationOutcome.skipped;
        entry.message = 'Symbolic link skipped (links are never followed).';
        return;
      }
      if (file.isFolder && !options.recursive) {
        entry.outcome = FileOperationOutcome.skipped;
        entry.message = 'Folder skipped: recursion is off.';
        return;
      }
      if (file.isFolder &&
          ((options.excludedDirectories?.matches(file) ?? false) ||
              (criteriaExcluded?.matches(file) ?? false) ||
              ((!options.includeHidden || criteria?.includeHidden == false) &&
                  file.name.startsWith('.')))) {
        entry.outcome = FileOperationOutcome.filtered;
        entry.message = 'Excluded directory; descendants were not scanned.';
        return;
      }
      if (!file.isFolder &&
          !options.matchesFile(file, criteriaMatcher: criteriaMatcher)) {
        entry.outcome = FileOperationOutcome.filtered;
        entry.message = 'Excluded by the file filter.';
        return;
      }
      if (!file.isFolder &&
          file.isSymlink != true &&
          options.preallocate &&
          file.size == null) {
        errors.add('Space reservation requires a known source size: $path');
      }
      if (file.isFolder &&
          !options.matchesSharedCriteria(file, matcher: criteriaMatcher)) {
        entry.outcome = FileOperationOutcome.filtered;
        entry.message = 'Folder excluded by shared criteria; matching descendants remain eligible.';
      }
      final previous = destinations[destination.destinationPathKey(output)];
      if (previous != null && !(previous.source.isFolder && file.isFolder)) {
        if (options.fileConflict == FileConflictPolicy.keepBoth &&
            !file.isFolder) {
          entry.recovery = {
            ...?entry.recovery,
            'duplicateNameBase': duplicateNameBase ?? output,
          };
          output = await _availableName(
            duplicateNameBase ?? output,
            destination,
            template: duplicateNames,
            reserved: reservedDestinations,
            stat: targetMetadata.stat,
            nextSuffix: nextCopySuffix,
          );
          entry.destination = output;
        } else {
          errors.add(
            'Several source items target $output. Use Keep both or preserve relative paths.',
          );
        }
      }
      entry.existing = await targetMetadata.stat(output);
      _checkSources(source, destination);
      final actualDestination = entry.existing?.path;
      if (actualDestination != null) {
        // Providers may resolve a differently-cased request to the source
        // itself. Use the actual listed path before authorizing any move.
        final isSource =
            source.identity == destination.identity &&
            source.samePath(path, actualDestination);
        final canDuplicateSource =
            !file.isFolder &&
            options.kind == FileOperationKind.copy &&
            options.fileConflict == FileConflictPolicy.keepBoth;
        if (isSource && !canDuplicateSource) {
          errors.add('Cannot copy or move an item into itself: $path');
          return;
        }
        output = destination.paths.normalize(actualDestination);
        entry.destination = output;
      }
      if (entry.existing != null &&
          (entry.existing!.isFolder != file.isFolder ||
              entry.existing!.isSymlink == true)) {
        errors.add(
          'Destination has an incompatible type or is a symbolic link: $output',
        );
      } else if (entry.existing != null &&
          !file.isFolder &&
          options.fileConflict == FileConflictPolicy.keepBoth) {
        // Show the actual planned copy name, including names already reserved
        // by earlier entries. execute still rechecks for changes after preview.
        duplicateNameBase ??= entry.recovery?['duplicateNameBase'] as String?;
        duplicateNameBase ??= output;
        entry.recovery = {
          ...?entry.recovery,
          'duplicateNameBase': duplicateNameBase,
        };
        output = await _availableName(
          duplicateNameBase,
          destination,
          template: duplicateNames,
          reserved: reservedDestinations,
          stat: targetMetadata.stat,
          nextSuffix: nextCopySuffix,
        );
        entry.destination = output;
        entry.existing = null;
      }
      if (plan.overlapsProtectedDestination(output)) {
        errors.add(
          'Destination overlaps another selected source: $output. '
          'Choose another name or directory.',
        );
        return;
      }
      destinations[destination.destinationPathKey(output)] = entry;
      reservedDestinations.add(destination.destinationPathKey(output));
      if (file.isFolder && file.isSymlink != true) {
        final children = await source.list(path);
        if (children.length > maxEntries - visited.length) {
          throw _PlanningLimitReached(
            'Directory $path exceeds the remaining preview budget of ${maxEntries - visited.length} items.',
          );
        }
        children.sort((a, b) => a.name.compareTo(b.name));
        for (final child in children) {
          if (child.path == null ||
              child.name == '.' ||
              child.name == '..' ||
              source.paths.dirname(source.paths.normalize(child.path!)) !=
                  path ||
              source.paths.basename(child.path!) != child.name ||
              child.name.contains('/') ||
              child.name.contains('\\')) {
            errors.add(
              'Invalid child path returned by ${source.label}: ${child.path}',
            );
            continue;
          }
          await walk(
            child,
            destination.paths.join(output, child.name),
            depth + 1,
            freshlyListed: true,
          );
        }
      }
    }

    try {
      for (final root in unique) {
        String relative =
            options.destinationName ?? source.paths.basename(root.key);
        if (options.preserveRelativePaths) {
          if (!source.isWithin(base!, root.key)) {
            errors.add('Source is outside the relative base: ${root.key}');
            continue;
          }
          relative = source.paths.relative(root.key, from: base);
        }
        final components = source.paths.split(relative);
        if (options.destinationName != null) {
          // Keep the source's relative parent folders while honoring its exact
          // new root name. The two destination options compose independently.
          components[components.length - 1] = options.destinationName!;
        }
        final output = destination.paths.joinAll([target, ...components]);
        if (!destination.isWithin(target, output)) {
          errors.add(
            'Destination would escape the selected directory: $output',
          );
          continue;
        }
        await walk(root.value.copyWith(path: root.key), output, 0);
      }
      if (options.excludeEmptyDirectories) {
        final includedAncestors = <String>{};
        for (final entry in entries) {
          if (entry.source.isFolder ||
              entry.outcome != FileOperationOutcome.pending) {
            continue;
          }
          var parent = source.paths.dirname(entry.source.path!);
          while (includedAncestors.add(source.pathKey(parent))) {
            final next = source.paths.dirname(parent);
            if (next == parent) break;
            parent = next;
          }
        }
        for (final directory in entries.reversed.where(
          (entry) =>
              entry.source.isFolder &&
              entry.outcome == FileOperationOutcome.pending,
        )) {
          final containsIncludedFile = includedAncestors.contains(
            source.pathKey(directory.source.path!),
          );
          if (!containsIncludedFile) {
            directory.outcome = FileOperationOutcome.filtered;
            directory.message = 'Empty after filtering; excluded.';
          }
        }
      }
      if (source.identity == destination.identity) {
        final selectedPaths = entries
            .map((entry) => source.pathKey(entry.source.path!))
            .toSet();
        for (final entry in entries.where(
          (entry) => entry.outcome == FileOperationOutcome.pending,
        )) {
          // A transformed name must not overwrite a later selected source,
          // including a source excluded by the file filter. Copying in sequence
          // cannot safely implement cycles or overlapping source/target chains.
          if (selectedPaths.contains(source.pathKey(entry.destination))) {
            errors.add(
              'Destination overlaps a selected source: ${entry.destination}. '
              'Choose another name or directory.',
            );
          }
        }
      }
      // Check destination ancestors, including links, before any writes.
      final checked = <String>{};
      for (final entry in entries.where(
        (entry) => entry.outcome == FileOperationOutcome.pending,
      )) {
        var parent = destination.paths.dirname(entry.destination);
        while (checked.add(parent)) {
          await control?.checkpoint();
          final existing = await targetMetadata.stat(parent);
          if (existing != null &&
              (!existing.isFolder || existing.isSymlink == true)) {
            errors.add(
              'Destination parent is not a regular directory: $parent',
            );
            break;
          }
          final next = destination.paths.dirname(parent);
          if (next == parent) break;
          parent = next;
        }
      }
    } on _PlanningLimitReached catch (error) {
      errors.add(error.message);
    }
    _checkSources(source, destination);
    return plan;
  }

  Future<void> execute(
    FileOperationPlan plan, {
    required FileOperationControl control,
    FileConflictResolver? resolveConflict,
    DetailedFileConflictResolver? resolveDetailedConflict,
    Future<void> Function(FileOperationEntry entry, String phase)? checkpoint,
    void Function(FileOperationEntry entry, int transferred, int? total)?
    onProgress,
    void Function(FileOperationEntry entry)? onEntryComplete,
  }) async {
    if (!plan.canExecute) throw StateError(plan.errors.join('\n'));
    plan.options.validateSearchCriteria();
    plan.options.validateTransferSettings();
    final source = plan.source;
    final target = plan.destination;
    final options = plan.options;
    final rateLimiter = options.clientBytesPerSecond == null
        ? null
        : rateLimiterFactory(options.clientBytesPerSecond!);
    final duplicateNames = DuplicateNameTemplate(options.duplicateNameTemplate);
    final skippedDirectories = <String>[];
    final reserved = plan.entries
        .map((entry) => target.destinationPathKey(entry.destination))
        .toSet();
    var stopped = false;
    FileConflictResolution? allFiles;
    FileConflictResolution? allFolders;
    for (final entry in plan.entries) {
      if (entry.outcome != FileOperationOutcome.pending) continue;
      if (stopped || control.isCancelled) {
        entry.outcome = FileOperationOutcome.cancelled;
        entry.message = stopped
            ? 'Not started after an earlier error.'
            : 'Cancelled before starting.';
        onEntryComplete?.call(entry);
        continue;
      }
      if (skippedDirectories.any(
        (path) => source.isWithin(path, entry.source.path!),
      )) {
        entry.outcome = FileOperationOutcome.skipped;
        entry.message = 'Parent directory was skipped.';
        onEntryComplete?.call(entry);
        continue;
      }
      try {
        await control.checkpoint();
        _checkSources(source, target);
        final currentSource = await source.stat(entry.source.path!);
        if (currentSource == null ||
            !_sameVersion(entry.source, currentSource)) {
          throw StateError(
            'Source changed after preview: ${entry.source.path}',
          );
        }
        plan.assertDestinationUnprotected(entry.destination);
        if (entry.recovery?['resumeAfterCommit'] == true) {
          await _finishCommittedEntry(plan, entry, control, checkpoint);
          onEntryComplete?.call(entry);
          continue;
        }
        var existing = await target.stat(entry.destination);
        _checkSources(source, target);
        if (source.identity == target.identity &&
            existing?.path != null &&
            source.samePath(entry.source.path!, existing!.path!)) {
          throw StateError('Destination resolves to the source itself.');
        }
        if (existing?.path != null) {
          plan.assertDestinationUnprotected(existing!.path!);
        }
        var replace = false;
        var resumeOffset = 0;
        var append = false;
        FileItem? originalDestination;
        if (existing != null) {
          if (existing.isFolder != entry.source.isFolder ||
              existing.isSymlink == true) {
            throw StateError(
              'Destination has an incompatible type or is a symbolic link.',
            );
          }
          final resolution =
              (entry.source.isFolder ? allFolders : allFiles) ??
              await _decision(
                entry,
                existing,
                options,
                resolveConflict,
                resolveDetailedConflict,
              );
          final decision = resolution.decision;
          if ((entry.source.isFolder &&
                  decision != FileConflictDecision.merge &&
                  decision != FileConflictDecision.skip &&
                  decision != FileConflictDecision.cancel) ||
              (!entry.source.isFolder &&
                  decision == FileConflictDecision.merge)) {
            throw StateError(
              'The conflict decision is not valid for this item.',
            );
          }
          if (resolution.applyToAll && resolution.name == null) {
            if (entry.source.isFolder) {
              allFolders = resolution;
            } else {
              allFiles = resolution;
            }
          }
          await control.checkpoint();
          _checkSources(source, target);
          if (decision == FileConflictDecision.cancel) {
            control.cancel();
            throw const FileOperationCancelled();
          }
          if (decision == FileConflictDecision.skip) {
            entry.outcome = FileOperationOutcome.skipped;
            entry.message = 'Destination exists; skipped.';
            if (entry.source.isFolder) {
              skippedDirectories.add(entry.source.path!);
            }
            onEntryComplete?.call(entry);
            continue;
          }
          // Conflict inspection can take time (or compare complete contents).
          // Revalidate both snapshots before a decision can rename or replace
          // an item that changed while the conflict dialog was open.
          final checkedSource = await source.stat(entry.source.path!);
          final checkedDestination = await target.stat(entry.destination);
          _checkSources(source, target);
          if (checkedSource == null ||
              !_sameVersion(entry.source, checkedSource)) {
            throw StateError('Source changed while resolving the conflict.');
          }
          if (checkedDestination == null ||
              !_sameVersion(existing, checkedDestination)) {
            throw StateError(
              'Destination changed while resolving the conflict.',
            );
          }
          if (decision == FileConflictDecision.keepBoth) {
            final base =
                entry.recovery?['duplicateNameBase'] as String? ??
                entry.destination;
            if (!target.paths.isAbsolute(base) ||
                !target.samePath(
                  target.paths.dirname(base),
                  target.paths.dirname(entry.destination),
                )) {
              throw StateError('The saved duplicate-name base is invalid.');
            }
            entry.recovery = {...?entry.recovery, 'duplicateNameBase': base};
            entry.destination = await _availableName(
              base,
              target,
              template: duplicateNames,
              reserved: reserved,
            );
            reserved.add(target.destinationPathKey(entry.destination));
            existing = null;
          } else if (decision == FileConflictDecision.renameSource ||
              decision == FileConflictDecision.renameDestination) {
            final name = resolution.name;
            if (name == null) throw StateError('Enter a new filename.');
            DestinationNameMask.validateName(name);
            final renamed = target.paths.join(
              target.paths.dirname(entry.destination),
              name,
            );
            plan.assertDestinationUnprotected(renamed);
            if (reserved.contains(target.destinationPathKey(renamed)) ||
                await target.stat(renamed) != null) {
              throw StateError(
                'The chosen filename is already occupied: $name',
              );
            }
            if (decision == FileConflictDecision.renameSource) {
              entry.destination = renamed;
            } else {
              entry.recovery = {
                ...?entry.recovery,
                'renamedExistingPath': renamed,
              };
              plan.assertDestinationUnprotected(
                existing.path ?? entry.destination,
              );
              await checkpoint?.call(entry, 'renamingExisting');
              await target.renameExisting(existing, renamed);
              entry.message = 'Previous destination preserved as $renamed';
            }
            reserved.add(target.destinationPathKey(renamed));
            existing = null;
          } else if (!entry.source.isFolder) {
            replace = true;
            if (decision == FileConflictDecision.resumeVerified ||
                decision == FileConflictDecision.append) {
              originalDestination = existing;
              if (existing.size == null || entry.source.size == null) {
                throw StateError('Resume and append require known file sizes.');
              }
              if (decision == FileConflictDecision.resumeVerified) {
                resumeOffset = existing.size!;
                if (resumeOffset > entry.source.size!) {
                  throw StateError(
                    'The destination is larger than the source.',
                  );
                }
                await _verifyPrefix(
                  source,
                  entry.source,
                  target,
                  existing,
                  resumeOffset,
                  control,
                );
              } else {
                append = true;
              }
            }
          }
        }
        await control.checkpoint();
        _checkSources(source, target);
        plan.assertDestinationUnprotected(entry.destination);
        final recoveredStagePath =
            entry.recovery?['resumeStagePath'] as String?;
        final recoveredUploadPath =
            entry.recovery?['resumeUploadPath'] as String?;
        if (recoveredUploadPath != null) {
          plan.assertDestinationUnprotected(recoveredUploadPath);
          if (append || resumeOffset > 0 || recoveredStagePath != null) {
            throw StateError(
              'A saved multipart upload requires the complete original source. Restart this item to append or use a different partial copy.',
            );
          }
        }
        if (options.copyMethod == FileCopyMethod.copyOnWrite &&
            (append ||
                resumeOffset > 0 ||
                recoveredStagePath != null ||
                recoveredUploadPath != null)) {
          throw UnsupportedError(
            'A required copy-on-write clone cannot append or resume partial bytes.',
          );
        }
        if (recoveredStagePath != null && !append && resumeOffset == 0) {
          plan.assertDestinationUnprotected(recoveredStagePath);
          final staged = await target.stat(recoveredStagePath);
          if (staged == null ||
              staged.isFolder ||
              staged.isSymlink == true ||
              staged.size == null ||
              entry.source.size == null ||
              staged.size! > entry.source.size!) {
            throw StateError('The saved partial copy is no longer usable.');
          }
          await _verifyPrefix(
            source,
            entry.source,
            target,
            staged,
            staged.size!,
            control,
          );
          originalDestination = staged;
          resumeOffset = staged.size!;
        }
        await checkpoint?.call(entry, 'creatingParent');
        await _ensureDirectory(target, target.paths.dirname(entry.destination));
        if (entry.source.isFolder && entry.source.isSymlink != true) {
          await _ensureDirectory(target, entry.destination);
          entry.outcome = FileOperationOutcome.directoryCreated;
          if (options.requestsMetadataPreservation) {
            final directory = await target.stat(entry.destination);
            _checkSources(source, target);
            if (directory == null ||
                !directory.isFolder ||
                directory.isSymlink == true) {
              throw StateError('The destination directory changed.');
            }
            entry.recovery = {
              ...?entry.recovery,
              'directoryMetadataApplied': false,
              'directoryTargetObjectId': directory.uuid,
            };
          }
          entry.message = existing == null
              ? 'Directory created.'
              : 'Merged into existing directory.';
        } else {
          entry.recovery = {...?entry.recovery, 'append': append};
          await checkpoint?.call(entry, 'writing');
          Future<void> recordWriteState(
            Map<String, dynamic> state, {
            String? contentSha256,
          }) async {
            for (final key in [
              'stagingPath',
              'stagedPath',
              'backupPath',
              'destination',
            ]) {
              final path = state[key];
              if (path is String) plan.assertDestinationUnprotected(path);
            }
            entry.recovery = {
              ...?entry.recovery,
              ...state,
              if (contentSha256 != null) 'contentSha256': contentSha256,
            };
            final phase = state['phase'] as String;
            // Record completed mutations and recovery paths even after the
            // original source disconnects or the user cancels. Restoring an
            // old destination uses the backend's own captured account checks.
            await checkpoint?.call(entry, phase);
            if (phase == 'committed' ||
                phase == 'restoringBackup' ||
                phase == 'restoreCopied') {
              return;
            }
            // A provider may consume the entire source into a private spool
            // long before its upload ends. Input-stream checks no longer run
            // then, so each subsequent forward phase needs a fresh gate.
            await control.checkpoint();
            _checkSources(source, target);
          }

          var nativeMoved = false;
          var nativeCopied = false;
          if (options.preferNative &&
              options.copyMethod == FileCopyMethod.automatic &&
              !options.preallocate &&
              !replace &&
              recoveredStagePath == null &&
              recoveredUploadPath == null &&
              !options.verifyContents &&
              // A native move consumes the source before a later metadata
              // write can fail. Keep it until every explicitly requested
              // preservation step has succeeded.
              !options.requestsMetadataPreservation &&
              source.identity == target.identity &&
              options.kind == FileOperationKind.move) {
            nativeMoved = await source.moveNoReplace(
              entry.source,
              entry.destination,
            );
          }
          if (!nativeMoved &&
              (options.preferNative ||
                  options.copyMethod == FileCopyMethod.copyOnWrite) &&
              options.copyMethod != FileCopyMethod.stream &&
              !options.preallocate &&
              !append &&
              recoveredStagePath == null &&
              recoveredUploadPath == null &&
              resumeOffset == 0 &&
              entry.source.isSymlink != true &&
              source.identity == target.identity) {
            if (target.capabilities.copyOnWrite) {
              nativeCopied = await target.clonePreparedFile(
                entry.source,
                entry.destination,
                replace: replace,
                checkpoint: recordWriteState,
                verifyStaged: (staged) async {
                  await control.checkpoint();
                  _checkSources(source, target);
                  final current = await source.stat(entry.source.path!);
                  if (current == null || !_sameVersion(entry.source, current)) {
                    throw StateError('The source changed during cloning.');
                  }
                  final expected =
                      entry.recovery?['sourceSha256'] as String? ??
                      (options.verifyContents
                          ? await _digest(source, entry.source, control, target)
                          : null);
                  if (expected != null) {
                    if (await _digest(target, staged, control, source) !=
                        expected) {
                      throw StateError(
                        'Clone contents changed before commit; original destination retained.',
                      );
                    }
                    entry.recovery = {
                      ...?entry.recovery,
                      'contentSha256': expected,
                    };
                  }
                },
              );
            }
            if (!nativeCopied) {
              if (options.copyMethod == FileCopyMethod.copyOnWrite) {
                throw UnsupportedError(
                  'This volume cannot create a copy-on-write clone. Choose automatic or streaming copy.',
                );
              }
              nativeCopied = await source.copyNative(
                entry.source,
                entry.destination,
                replace: replace,
                checkpoint: control.checkpoint,
              );
            }
          }
          if (nativeMoved) {
            entry.outcome = FileOperationOutcome.moved;
            await checkpoint?.call(entry, 'complete');
            onEntryComplete?.call(entry);
            continue;
          }
          if (entry.source.isSymlink == true) {
            await target.copySymbolicLink(
              entry.source,
              entry.destination,
              replace: replace,
            );
          } else {
            var sent = 0;
            final expectedLength = append
                ? entry.source.size! + originalDestination!.size!
                : entry.source.size;
            Stream<List<int>> contents() async* {
              if (originalDestination != null) {
                yield* target.readFile(originalDestination);
              }
              yield* resumeOffset > 0
                  ? source.readRange(entry.source, resumeOffset)
                  : source.readFile(entry.source);
            }

            final inputDigest = _DigestCollector();
            final hashSink = sha256.startChunkedConversion(inputDigest);
            if (!nativeCopied) {
              Stream<List<int>> tracked() async* {
                try {
                  final input = control.bind(contents());
                  final limited =
                      rateLimiter?.bind(input, control: control) ?? input;
                  await for (final chunk in limited) {
                    await control.checkpoint();
                    _checkSources(source, target);
                    sent += chunk.length;
                    hashSink.add(chunk);
                    onProgress?.call(entry, sent, expectedLength);
                    yield chunk;
                  }
                } finally {
                  hashSink.close();
                }
              }

              await target.writeConfiguredFile(
                entry.destination,
                tracked(),
                expectedLength,
                replace: replace,
                preallocate: options.preallocate,
                resumeUploadPath: recoveredUploadPath,
                checkpoint: (state) => recordWriteState(
                  state,
                  contentSha256: inputDigest.value?.toString(),
                ),
                verifyStaged:
                    options.verifyContents || append || resumeOffset > 0
                    ? (staged) async {
                        await control.checkpoint();
                        _checkSources(source, target);
                        final actual = await _digest(
                          target,
                          staged,
                          control,
                          source,
                        );
                        if (actual != inputDigest.value?.toString()) {
                          throw StateError(
                            'SHA-256 verification failed before commit; existing destination retained.',
                          );
                        }
                      }
                    : null,
              );
              if (expectedLength != null && sent != expectedLength) {
                throw StateError(
                  'Source length changed while copying; source retained.',
                );
              }
            } else {
              sent = expectedLength ?? 0;
              hashSink.close();
              onProgress?.call(entry, sent, expectedLength);
            }
            await control.checkpoint();
            _checkSources(source, target);
            final written = await target.stat(entry.destination);
            if (written == null ||
                written.isFolder ||
                (written.size != null &&
                    expectedLength != null &&
                    written.size != expectedLength)) {
              throw StateError(
                'Destination could not be verified; source retained.',
              );
            }
            if (options.verifyContents || append || resumeOffset > 0) {
              final before = nativeCopied
                  ? await _digest(source, entry.source, control, target)
                  : inputDigest.value!.toString();
              final after = await _digest(target, written, control, source);
              if (before != after) {
                throw StateError(
                  'SHA-256 verification failed; source retained.',
                );
              }
            }
            entry.recovery = {...?entry.recovery, 'dataVerified': true};
            await checkpoint?.call(entry, 'verified');
          }
          await checkpoint?.call(entry, 'metadata');
          await _preserveMetadata(source, target, entry, options);
          if (options.kind == FileOperationKind.move) {
            await control.checkpoint();
            _checkSources(source, target);
            final latest = await source.stat(entry.source.path!);
            if (latest == null || !_sameVersion(entry.source, latest)) {
              throw StateError('Source changed during copy; source retained.');
            }
            await checkpoint?.call(entry, 'deletingSource');
            await source.deleteFile(entry.source);
            entry.outcome = FileOperationOutcome.moved;
          } else {
            entry.outcome = FileOperationOutcome.copied;
          }
        }
        await checkpoint?.call(entry, 'complete');
      } on FileOperationNeedsDecision {
        entry.outcome = FileOperationOutcome.needsDecision;
        entry.message = 'Waiting for a conflict decision.';
        await checkpoint?.call(entry, 'needsDecision');
        onEntryComplete?.call(entry);
        break;
      } on FileOperationCancelled {
        entry.outcome = FileOperationOutcome.cancelled;
        entry.message = 'Cancelled; source retained.';
        await checkpoint?.call(entry, 'cancelled');
      } on FileOperationMetadataFailure catch (error) {
        entry.outcome = FileOperationOutcome.metadataFailed;
        entry.message = '$error. Source retained.';
        stopped = options.stopOnError;
        await checkpoint?.call(entry, 'metadataFailed');
      } catch (error) {
        entry.outcome = FileOperationOutcome.failed;
        entry.message = error.toString();
        stopped = options.stopOnError;
        await checkpoint?.call(entry, 'failed');
      }
      onEntryComplete?.call(entry);
    }
    if (options.requestsMetadataPreservation && !control.isCancelled) {
      // Restrictive modes/ACLs are applied after children. Do not lock a
      // directory while an unfinished child still needs a write or retry.
      final incompleteDirectories = <String>{};
      void retainAncestors(String path) {
        var parent = source.paths.dirname(path);
        while (incompleteDirectories.add(source.pathKey(parent))) {
          final next = source.paths.dirname(parent);
          if (next == parent) break;
          parent = next;
        }
      }

      for (final entry in plan.entries) {
        if (entry.failed ||
            entry.outcome == FileOperationOutcome.pending ||
            entry.outcome == FileOperationOutcome.needsDecision ||
            entry.outcome == FileOperationOutcome.cancelled) {
          retainAncestors(entry.source.path!);
        }
      }
      for (final entry in plan.entries.reversed.where(
        (entry) =>
            entry.source.isFolder &&
            entry.source.isSymlink != true &&
            entry.outcome == FileOperationOutcome.directoryCreated &&
            entry.recovery?['directoryMetadataApplied'] != true,
      )) {
        if (incompleteDirectories.contains(
          source.pathKey(entry.source.path!),
        )) {
          continue;
        }
        try {
          await control.checkpoint();
          _checkSources(source, target);
          plan.assertDestinationUnprotected(entry.destination);
          final currentSource = await source.stat(entry.source.path!);
          final currentTarget = await target.stat(entry.destination);
          _checkSources(source, target);
          final expectedTargetId = entry.recovery?['directoryTargetObjectId'];
          if (currentSource == null ||
              !currentSource.isFolder ||
              currentSource.isSymlink == true ||
              // Child moves can legitimately change a directory revision.
              // Its stable object identity must still match the reviewed one.
              (entry.source.uuid != null &&
                  currentSource.uuid != entry.source.uuid) ||
              currentTarget == null ||
              !currentTarget.isFolder ||
              currentTarget.isSymlink == true ||
              (expectedTargetId != null &&
                  currentTarget.uuid != expectedTargetId)) {
            throw StateError(
              'A directory changed before its metadata could be preserved.',
            );
          }
          await checkpoint?.call(entry, 'directoryMetadata');
          await _preserveMetadata(source, target, entry, options);
          entry.recovery = {
            ...?entry.recovery,
            'directoryMetadataApplied': true,
          };
          await checkpoint?.call(entry, 'complete');
          onEntryComplete?.call(entry);
        } on FileOperationCancelled {
          // The job remains cancelled with its unfinished metadata checkpoint;
          // cancellation is not a metadata error and must not remove sources.
          break;
        } catch (error) {
          entry.outcome = FileOperationOutcome.metadataFailed;
          entry.message =
              'Directory contents copied; metadata could not be preserved: '
              '$error. Source directory retained.';
          retainAncestors(entry.source.path!);
          await checkpoint?.call(entry, 'metadataFailed');
          onEntryComplete?.call(entry);
        }
      }
    }
    if (options.kind == FileOperationKind.move && !control.isCancelled) {
      for (final entry in plan.entries.reversed.where(
        (entry) =>
            entry.source.isFolder &&
            entry.outcome == FileOperationOutcome.directoryCreated &&
            (!options.requestsMetadataPreservation ||
                entry.recovery?['directoryMetadataApplied'] == true),
      )) {
        try {
          await control.checkpoint();
          _checkSources(source, target);
          // No recursive deletion: excluded/skipped/new files keep their parent.
          if ((await source.list(entry.source.path!)).isEmpty) {
            await checkpoint?.call(entry, 'deletingSourceDirectory');
            await source.deleteEmptyDirectory(entry.source.path!);
            entry.outcome = FileOperationOutcome.moved;
            entry.message = 'Empty source directory removed.';
          } else {
            entry.message =
                'Source directory retained because it still contains items.';
          }
        } catch (error) {
          entry.message = 'Source directory retained: $error';
        }
        await checkpoint?.call(entry, 'complete');
        onEntryComplete?.call(entry);
      }
    }
  }

  Future<void> _preserveMetadata(
    FileOperationBackend source,
    FileOperationBackend target,
    FileOperationEntry entry,
    FileOperationOptions options,
  ) async {
    try {
      if (entry.source.isSymlink == true &&
          options.requestsMetadataPreservation) {
        throw UnsupportedError(
          'Link metadata cannot be changed without following the target.',
        );
      }
      if (options.preserveModified && entry.source.updatedAt == null) {
        throw StateError(
          'The reviewed source has no modification timestamp to preserve: '
          '${entry.source.path}.',
        );
      }
      TransferMetadata? metadata;
      if (options.preservePermissions ||
          options.preserveOwnership ||
          options.preserveExtendedAttributes ||
          options.preserveAcl ||
          options.preserveWindowsAttributes) {
        metadata = await source.readMetadataFields(
          entry.source.path!,
          permissions: options.preservePermissions,
          modified: false,
          accessed: false,
          created: false,
          ownership: options.preserveOwnership,
          extendedAttributes: options.preserveExtendedAttributes,
          acl: options.preserveAcl,
          windowsAttributes: options.preserveWindowsAttributes,
        );
        _checkSources(source, target);
        final missing = [
          if (options.preservePermissions && metadata.mode == null)
            'permissions',
          if (options.preserveOwnership &&
              (metadata.owner == null || metadata.group == null))
            'ownership',
          if (options.preserveAcl && metadata.acl == null)
            'access control list',
          if (options.preserveWindowsAttributes &&
              metadata.windowsAttributes == null)
            'Windows attributes',
        ];
        if (missing.isNotEmpty) {
          throw StateError(
            'The source did not return requested ${missing.join(', ')} '
            'metadata for ${entry.source.path}.',
          );
        }
      }
      if (options.preserveModified && entry.source.updatedAt != null) {
        await target.setModified(entry.destination, entry.source.updatedAt!);
      }
      if (metadata != null) {
        await target.writeMetadata(
          entry.destination,
          TransferMetadata(
            mode: options.preservePermissions ? metadata.mode : null,
            owner: options.preserveOwnership ? metadata.owner : null,
            group: options.preserveOwnership ? metadata.group : null,
            extendedAttributes: options.preserveExtendedAttributes
                ? metadata.extendedAttributes
                : const {},
            acl: options.preserveAcl ? metadata.acl : null,
            windowsAttributes: options.preserveWindowsAttributes
                ? metadata.windowsAttributes
                : null,
            windowsAttributesMask: 0x27,
          ),
        );
      }
    } catch (error) {
      throw FileOperationMetadataFailure(error);
    }
  }

  Future<void> _finishCommittedEntry(
    FileOperationPlan plan,
    FileOperationEntry entry,
    FileOperationControl control,
    Future<void> Function(FileOperationEntry, String)? checkpoint,
  ) async {
    await checkpoint?.call(entry, 'finishingCopy');
    final written = await plan.destination.stat(entry.destination);
    final expected =
        entry.recovery?['contentSha256'] ?? entry.recovery?['sourceSha256'];
    if (written == null ||
        expected is! String ||
        await _digest(plan.destination, written, control, plan.source) !=
            expected) {
      throw StateError(
        'The previously copied destination changed. Review it before retrying.',
      );
    }
    await _preserveMetadata(plan.source, plan.destination, entry, plan.options);
    if (plan.options.kind == FileOperationKind.move) {
      await control.checkpoint();
      _checkSources(plan.source, plan.destination);
      final current = await plan.source.stat(entry.source.path!);
      if (current == null || !_sameVersion(entry.source, current)) {
        throw StateError('The source changed before cleanup; it was retained.');
      }
      await checkpoint?.call(entry, 'deletingSource');
      await plan.source.deleteFile(entry.source);
      entry.outcome = FileOperationOutcome.moved;
    } else {
      entry.outcome = FileOperationOutcome.copied;
    }
    entry.message = 'Verified earlier copy; finished remaining steps.';
    await checkpoint?.call(entry, 'complete');
  }

  bool _sameVersion(FileItem before, FileItem after) =>
      before.isFolder == after.isFolder &&
      (before.isSymlink == true) == (after.isSymlink == true) &&
      before.symlinkTarget == after.symlinkTarget &&
      _version(before) == _version(after) &&
      (before.uuid == null || before.uuid == after.uuid) &&
      (before.isFolder ||
          ((before.size == null || before.size == after.size) &&
              (before.updatedAt == null ||
                  (after.updatedAt != null &&
                      before.updatedAt!.isAtSameMomentAs(after.updatedAt!)))));

  Future<String> _digest(
    FileOperationBackend backend,
    FileItem file,
    FileOperationControl control,
    FileOperationBackend other,
  ) async {
    if (file.isSymlink == true) {
      return sha256
          .convert(utf8.encode('link:${file.symlinkTarget}'))
          .toString();
    }
    final hash = await sha256
        .bind(
          control.bind(backend.readFile(file)).asyncMap((chunk) async {
            await control.checkpoint();
            _checkSources(backend, other);
            return chunk;
          }),
        )
        .first;
    return hash.toString();
  }

  Future<FileConflictResolution> _decision(
    FileOperationEntry entry,
    FileItem existing,
    FileOperationOptions options,
    FileConflictResolver? resolver,
    DetailedFileConflictResolver? detailedResolver,
  ) async {
    FileConflictDecision? decision;
    if (entry.source.isFolder) {
      decision = switch (options.directoryConflict) {
        DirectoryConflictPolicy.merge => FileConflictDecision.merge,
        DirectoryConflictPolicy.skip => FileConflictDecision.skip,
        DirectoryConflictPolicy.ask => null,
      };
    } else {
      decision = switch (options.fileConflict) {
        FileConflictPolicy.skip => FileConflictDecision.skip,
        FileConflictPolicy.replace => FileConflictDecision.replace,
        FileConflictPolicy.keepBoth => FileConflictDecision.keepBoth,
        FileConflictPolicy.replaceIfNewer =>
          entry.source.updatedAt != null &&
                  existing.updatedAt != null &&
                  entry.source.updatedAt!.isAfter(existing.updatedAt!)
              ? FileConflictDecision.replace
              : FileConflictDecision.skip,
        FileConflictPolicy.replaceIfLarger =>
          entry.source.size != null &&
                  existing.size != null &&
                  entry.source.size! > existing.size!
              ? FileConflictDecision.replace
              : FileConflictDecision.skip,
        FileConflictPolicy.replaceIfSmaller =>
          entry.source.size != null &&
                  existing.size != null &&
                  entry.source.size! < existing.size!
              ? FileConflictDecision.replace
              : FileConflictDecision.skip,
        FileConflictPolicy.resumeVerified =>
          FileConflictDecision.resumeVerified,
        FileConflictPolicy.append => FileConflictDecision.append,
        FileConflictPolicy.ask => null,
      };
    }
    if (decision != null) return FileConflictResolution(decision);
    if (detailedResolver != null) return detailedResolver(entry, existing);
    if (resolver != null) {
      return FileConflictResolution(await resolver(entry, existing));
    }
    throw const FileOperationNeedsDecision();
  }

  String? _version(FileItem file) {
    final metadata = file.metadata;
    for (final key in ['version', 'versionId', 'eTag', 'etag', 'rev', 'cTag']) {
      if (metadata?[key] != null) return metadata![key].toString();
    }
    return null;
  }

  Future<void> _verifyPrefix(
    FileOperationBackend source,
    FileItem original,
    FileOperationBackend target,
    FileItem partial,
    int length,
    FileOperationControl control,
  ) async {
    Stream<List<int>> prefix() async* {
      var remaining = length;
      if (remaining == 0) return;
      await for (final chunk in control.bind(source.readFile(original))) {
        await control.checkpoint();
        _checkSources(source, target);
        final part = chunk.length <= remaining
            ? chunk
            : chunk.sublist(0, remaining);
        yield part;
        remaining -= part.length;
        if (remaining == 0) break;
      }
      if (remaining != 0) {
        throw StateError('Source is shorter than its resume prefix.');
      }
    }

    final sourceHash = await sha256.bind(prefix()).first;
    final targetHash = await _digest(target, partial, control, source);
    if (sourceHash.toString() != targetHash) {
      throw StateError(
        'Resume rejected: destination is not an exact source prefix.',
      );
    }
    final current = await target.stat(partial.path!);
    if (current == null || !_sameVersion(partial, current)) {
      throw StateError('Resume destination changed during validation.');
    }
  }

  Future<String> _availableName(
    String original,
    FileOperationBackend backend, {
    required DuplicateNameTemplate template,
    Set<String> reserved = const {},
    Future<FileItem?> Function(String path)? stat,
    Map<String, int>? nextSuffix,
  }) async {
    final name = backend.paths.basename(original);
    final key = backend.destinationPathKey(original);
    for (var index = nextSuffix?[key] ?? 1; index < 1000000; index++) {
      final candidate = backend.paths.join(
        backend.paths.dirname(original),
        template.apply(name, index: index),
      );
      if (!reserved.contains(backend.destinationPathKey(candidate)) &&
          await (stat ?? backend.stat)(candidate) == null) {
        nextSuffix?[key] = index + 1;
        return candidate;
      }
    }
    throw StateError('Cannot find a free filename for $original');
  }

  Future<void> _ensureDirectory(
    FileOperationBackend backend,
    String path,
  ) async {
    if (!backend.isCurrent) throw StateError('The storage account changed.');
    final existing = await backend.stat(path);
    if (existing != null) {
      if (!existing.isFolder || existing.isSymlink == true) {
        throw StateError(
          'Destination parent is not a regular directory: $path',
        );
      }
      return;
    }
    final parent = backend.paths.dirname(path);
    if (parent == path) {
      throw StateError('Destination root is unavailable: $path');
    }
    await _ensureDirectory(backend, parent);
    if (!backend.isCurrent) throw StateError('The storage account changed.');
    await backend.createDirectory(path);
  }
}

class _PlanningLimitReached implements Exception {
  const _PlanningLimitReached(this.message);
  final String message;
}

/// A bounded, read-only metadata snapshot for preview. No cached information
/// can authorize a write; execute revalidates the reviewed entries separately.
class _PlanningMetadata {
  _PlanningMetadata(this.backend, this.maxEntries);
  final FileOperationBackend backend;
  final int maxEntries;
  final Map<String, FileItem?> _items = {};
  final Map<String, Map<String, FileItem>> _directories = {};
  int _listedEntries = 0;

  Future<FileItem?> stat(String path) async {
    path = backend.paths.normalize(path);
    final key = backend.destinationPathKey(path);
    if (_items.containsKey(key)) return _items[key];
    if (!backend.isCurrent) throw StateError('The storage account changed.');
    if (!backend.statRequiresDirectoryListing || backend.isRootPath(path)) {
      return _items[key] = await backend.stat(path);
    }
    final parent = await stat(backend.paths.dirname(path));
    if (parent == null) return _items[key] = null;
    if (!parent.isFolder || parent.isSymlink == true) {
      throw StateError(
        'Destination parent is not a regular directory: ${parent.path}',
      );
    }
    final parentPath = parent.path!;
    final parentKey = backend.destinationPathKey(parentPath);
    var directory = _directories[parentKey];
    if (directory == null) {
      final listed = await backend.list(parentPath);
      if (_listedEntries + listed.length > maxEntries) {
        throw _PlanningLimitReached(
          'Directory metadata exceeds the preview limit of $maxEntries items. Select a smaller scope or raise the item limit.',
        );
      }
      _listedEntries += listed.length;
      directory = <String, FileItem>{};
      for (final item in listed) {
        if (item.path == null ||
            !backend.samePath(backend.paths.dirname(item.path!), parentPath)) {
          throw StateError('Invalid child path returned by ${backend.label}.');
        }
        final nameKey = backend.destinationPathKey(item.name);
        if (directory.containsKey(nameKey)) {
          throw StateError(
            'Several items have case-ambiguous paths: ${item.path}',
          );
        }
        directory[nameKey] = item;
      }
      _directories[parentKey] = directory;
    }
    if (!backend.isCurrent) throw StateError('The storage account changed.');
    return _items[key] =
        directory[backend.destinationPathKey(backend.paths.basename(path))];
  }
}

class _DigestCollector implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
