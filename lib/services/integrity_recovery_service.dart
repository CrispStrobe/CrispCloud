import 'dart:async';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../models/file_item.dart';
import '../models/integrity_recovery.dart';
import '../models/transfer_job.dart';
import 'file_integrity_service.dart';
import 'file_operation_service.dart';
import 'file_split_service.dart';
import 'transfer_journal.dart';

typedef IntegrityProgress = void Function(String phase, int bytes, int total);

/// Split/combine operations use the same durable journal, account references,
/// staged backend writes and operation admission as ordinary transfer recovery.
/// A recovered split reuses verified whole parts. A recovered combine restarts
/// unfinished staging, or reconciles a fully verified destination after a lost
/// response. Neither path appends to or overwrites an unverified output.
class IntegrityRecoveryService {
  const IntegrityRecoveryService(this.journal);
  final TransferJournal journal;

  static bool isIntegrityJob(TransferJobRecord job) =>
      isIntegrityTransferJob(job);
  bool isActive(String id) => journal.isOperationActive(id);

  Future<SplitResult> startSplit({
    required FileOperationBackend source,
    required FileItem file,
    required FileOperationBackend destination,
    required String targetDirectory,
    required int chunkSizeBytes,
    FileOperationControl? control,
    IntegrityProgress? onProgress,
    void Function(String id)? onJobCreated,
  }) async {
    final currentControl = control ?? FileOperationControl();
    final job = await prepareSplit(
      source: source,
      file: file,
      destination: destination,
      targetDirectory: targetDirectory,
      chunkSizeBytes: chunkSizeBytes,
      control: currentControl,
      onProgress: onProgress,
    );
    onJobCreated?.call(job.id);
    await journal.runExclusiveOperation(job.id, () async {
      final reviewed = await _review(
        job.id,
        source,
        destination,
        currentControl,
        onProgress,
        allowSession: true,
      );
      await _run(reviewed, source, destination, currentControl, onProgress);
    });
    final definition = IntegrityRecoveryDefinition.fromJob(
      journal.job(job.id)!,
    );
    return SplitResult(
      definition.outputPath,
      definition.completeManifest,
      definition.parts.map((part) => part.destination).toList(),
    );
  }

  Future<String> startCombine({
    required FileOperationBackend source,
    required FileOperationBackend destination,
    required String outputPath,
    FileItem? manifestFile,
    SplitManifest? reviewedManifest,
    List<FileItem> legacyParts = const [],
    bool allowUnverifiedLegacy = false,
    FileOperationControl? control,
    IntegrityProgress? onProgress,
    void Function(String id)? onJobCreated,
  }) async {
    final currentControl = control ?? FileOperationControl();
    final job = await prepareCombine(
      source: source,
      destination: destination,
      outputPath: outputPath,
      manifestFile: manifestFile,
      reviewedManifest: reviewedManifest,
      legacyParts: legacyParts,
      allowUnverifiedLegacy: allowUnverifiedLegacy,
      control: currentControl,
      onProgress: onProgress,
    );
    onJobCreated?.call(job.id);
    await journal.runExclusiveOperation(job.id, () async {
      final reviewed = await _review(
        job.id,
        source,
        destination,
        currentControl,
        onProgress,
        allowSession: true,
      );
      await _run(reviewed, source, destination, currentControl, onProgress);
    });
    return outputPath;
  }

  /// Establish all expected part hashes before saving an executable operation.
  /// No output is written while this definition is prepared.
  Future<TransferJobRecord> prepareSplit({
    required FileOperationBackend source,
    required FileItem file,
    required FileOperationBackend destination,
    required String targetDirectory,
    required int chunkSizeBytes,
    FileOperationControl? control,
    IntegrityProgress? onProgress,
  }) async {
    final currentControl = control ?? FileOperationControl();
    _check(source, destination, currentControl);
    if (chunkSizeBytes <= 0) {
      throw ArgumentError('Choose a positive part size.');
    }
    final original = await requireIntegrityFile(
      source,
      file,
      isCancelled: () => currentControl.isCancelled,
    );
    final total = original.size;
    if (total == null) throw StateError('The source must report its size.');
    final count = math.max(1, (total + chunkSizeBytes - 1) ~/ chunkSizeBytes);
    if (count > kSplitMaxParts) {
      throw StateError(
        'Choose a larger part size; at most $kSplitMaxParts parts are supported.',
      );
    }
    final directory = await _requireDirectory(destination, targetDirectory);
    _requireStaging(destination, math.min(total, chunkSizeBytes));
    final output = resolveIntegrityPath(
      destination,
      targetDirectory,
      '${original.name}.split.json',
    );
    final destinations = [
      for (var i = 1; i <= count; i++)
        resolveIntegrityPath(
          destination,
          targetDirectory,
          FileSplitService.partName(original.name, i),
        ),
    ];
    for (final path in [output, ...destinations]) {
      _check(source, destination, currentControl);
      if (await destination.stat(path) != null) {
        throw StateError(
          'An output already exists: $path. Review its saved recovery or choose a new destination.',
        );
      }
    }
    final evidence = await _scanSplitSource(
      source,
      original,
      total,
      chunkSizeBytes,
      currentControl,
      onProgress,
    );
    final complete = SplitManifest(
      originalName: original.name,
      totalBytes: total,
      chunkSize: chunkSizeBytes,
      status: SplitManifestStatus.complete,
      sha256: evidence.$2,
      parts: [
        for (var i = 0; i < evidence.$1.length; i++)
          SplitPart(
            index: i + 1,
            path: FileSplitService.partName(original.name, i + 1),
            size: math.min(chunkSizeBytes, total - i * chunkSizeBytes),
            sha256: evidence.$1[i],
          ),
      ],
    );
    complete.encode();
    final entries = <FileOperationEntry>[
      FileOperationEntry(original, output)
        ..recovery = {
          'integrityVersion': 1,
          'integrityKind': 'split',
          'originalName': original.name,
          'totalBytes': total,
          'chunkSize': chunkSizeBytes,
          'expectedSha256': evidence.$2,
          'sourceFile': integrityFileJson(original),
          'destinationDirectory': integrityFileJson(directory),
        },
      for (var i = 0; i < complete.parts.length; i++)
        FileOperationEntry(original, destinations[i])
          ..recovery = {
            'integrityPart': i + 1,
            'partSize': complete.parts[i].size,
            'partSha256': complete.parts[i].sha256,
            'relativePath': complete.parts[i].path,
            'sourceFile': integrityFileJson(original),
          },
    ];
    _check(source, destination, currentControl);
    return journal.create(
      'integrity_split_${const Uuid().v4()}',
      FileOperationPlan(
        source: source,
        destination: destination,
        targetDirectory: targetDirectory,
        options: const FileOperationOptions(),
        entries: entries,
        errors: const [],
      ),
    );
  }

  Future<TransferJobRecord> prepareCombine({
    required FileOperationBackend source,
    required FileOperationBackend destination,
    required String outputPath,
    FileItem? manifestFile,
    SplitManifest? reviewedManifest,
    List<FileItem> legacyParts = const [],
    bool allowUnverifiedLegacy = false,
    FileOperationControl? control,
    IntegrityProgress? onProgress,
  }) async {
    final currentControl = control ?? FileOperationControl();
    _check(source, destination, currentControl);
    final directory = await _requireDirectory(
      destination,
      destination.paths.dirname(outputPath),
    );
    if (!destination.paths.isAbsolute(outputPath) ||
        !destination.isWithin(directory.path!, outputPath) ||
        await destination.stat(outputPath) != null) {
      throw StateError(
        'Choose a vacant output in the reviewed destination directory.',
      );
    }
    SplitManifest? manifest;
    final files = <FileItem>[];
    final relative = <String>[];
    if (manifestFile != null) {
      manifest = await FileSplitService.readManifest(
        source,
        manifestFile,
        isCancelled: () => currentControl.isCancelled,
      );
      if (manifest.status != SplitManifestStatus.complete) {
        throw StateError(
          'The split is incomplete. Open Split/combine recovery to resume its original operation.',
        );
      }
      if (reviewedManifest != null &&
          reviewedManifest.definitionFingerprint !=
              manifest.definitionFingerprint) {
        throw const SplitManifestChangedException();
      }
      final base = source.paths.dirname(manifestFile.path!);
      for (final part in manifest.parts) {
        final path = resolveIntegrityPath(source, base, part.path);
        await rejectIntegritySymlinkParents(
          source,
          base,
          path,
          isCancelled: () => currentControl.isCancelled,
        );
        final file = await requireIntegrityFile(
          source,
          FileItem(
            name: source.paths.basename(path),
            path: path,
            isFolder: false,
          ),
          isCancelled: () => currentControl.isCancelled,
        );
        if (file.size != part.size) {
          throw StateError('A split part changed: $path');
        }
        files.add(file);
        relative.add(part.path);
      }
    } else {
      if (!allowUnverifiedLegacy) {
        throw StateError(
          'Confirm legacy combination without an original checksum.',
        );
      }
      for (final file in FileSplitService.orderedLegacyParts(
        source,
        legacyParts,
      )) {
        files.add(
          await requireIntegrityFile(
            source,
            file,
            isCancelled: () => currentControl.isCancelled,
          ),
        );
        relative.add(file.name);
      }
    }
    if (files.isEmpty || files.any((file) => file.size == null)) {
      throw StateError('Every input part must have a known size.');
    }
    if (source.identity == destination.identity &&
        files.any((file) => source.samePath(file.path!, outputPath))) {
      throw StateError('The output cannot replace an input part.');
    }
    final total = files.fold<int>(0, (sum, file) => sum + file.size!);
    _requireStaging(destination, total);
    final evidence = await _scanCombineSources(
      source,
      files,
      currentControl,
      onProgress,
      expectedParts: manifest?.parts.map((part) => part.sha256).toList(),
    );
    if (manifest != null && evidence.$2 != manifest.sha256) {
      throw StateError('The input parts do not match the whole-file checksum.');
    }
    if (manifestFile != null &&
        (await FileSplitService.readManifest(
              source,
              manifestFile,
              isCancelled: () => currentControl.isCancelled,
            )).definitionFingerprint !=
            manifest!.definitionFingerprint) {
      throw const SplitManifestChangedException();
    }
    final entries = <FileOperationEntry>[
      FileOperationEntry(files.first, outputPath)
        ..recovery = {
          'integrityVersion': 1,
          'integrityKind': 'combine',
          'originalName':
              manifest?.originalName ?? destination.paths.basename(outputPath),
          'totalBytes': total,
          'chunkSize': manifest?.chunkSize ?? math.max(1, files.first.size!),
          'expectedSha256': evidence.$2,
          'sourceFile': integrityFileJson(files.first),
          'destinationDirectory': integrityFileJson(directory),
          'legacy': manifest == null,
          if (manifestFile != null)
            'inputManifest': integrityFileJson(manifestFile),
          if (manifest != null)
            'inputManifestFingerprint': manifest.definitionFingerprint,
        },
      for (var i = 0; i < files.length; i++)
        FileOperationEntry(files[i], outputPath)
          ..recovery = {
            'integrityPart': i + 1,
            'partSize': files[i].size!,
            'partSha256': evidence.$1[i],
            'relativePath': relative[i],
            'sourceFile': integrityFileJson(files[i]),
          },
    ];
    _check(source, destination, currentControl);
    return journal.create(
      'integrity_combine_${const Uuid().v4()}',
      FileOperationPlan(
        source: source,
        destination: destination,
        targetDirectory: directory.path!,
        options: const FileOperationOptions(),
        entries: entries,
        errors: const [],
      ),
    );
  }

  Future<IntegrityRecoveryReview> review(
    String id, {
    required FileOperationBackend source,
    required FileOperationBackend destination,
    FileOperationControl? control,
    IntegrityProgress? onProgress,
  }) {
    if (isActive(id)) {
      return Future.error(StateError('This operation is already active.'));
    }
    return _review(
      id,
      source,
      destination,
      control ?? FileOperationControl(),
      onProgress,
    );
  }

  Future<IntegrityRecoveryReview> _review(
    String id,
    FileOperationBackend source,
    FileOperationBackend destination,
    FileOperationControl control,
    IntegrityProgress? progress, {
    bool allowSession = false,
  }) async {
    await journal.initialize();
    final job = journal.job(id);
    if (job == null) throw StateError('The saved operation is unavailable.');
    final definition = IntegrityRecoveryDefinition.fromJob(job);
    _checkBindings(
      job,
      source,
      destination,
      control,
      allowSession: allowSession,
    );
    final directory = await _requireDirectory(
      destination,
      job.targetDirectory,
      expected: definition.destinationDirectory,
    );
    _validatePaths(definition, source, destination, job.targetDirectory);
    _requireStaging(
      destination,
      definition.kind == IntegrityOperationKind.split
          ? math.min(definition.totalBytes, definition.chunkSize)
          : definition.totalBytes,
    );
    SplitManifest? outputManifest;
    FileItem? output;
    final verified = <FileItem?>[];
    if (definition.kind == IntegrityOperationKind.split) {
      final evidence = await _scanSplitSource(
        source,
        definition.sourceFile,
        definition.totalBytes,
        definition.chunkSize,
        control,
        progress,
      );
      if (evidence.$2 != definition.expectedSha256 ||
          !_sameHashes(
            evidence.$1,
            definition.parts.map((part) => part.sha256),
          )) {
        throw StateError(
          'The original source contents changed. Existing parts were preserved.',
        );
      }
      outputManifest = await _readSplitOutputManifest(
        definition,
        destination,
        control,
      );
      if (outputManifest != null && !_hasWriteIntent(job.entries.first)) {
        throw StateError(
          'An unreviewed file occupies ${definition.outputPath}. It was preserved.',
        );
      }
      for (final part in definition.parts) {
        final saved = job.entries[part.index];
        final current = await destination.stat(part.destination);
        _check(source, destination, control);
        final inManifest =
            outputManifest != null && outputManifest.parts.length >= part.index;
        if (current == null) {
          if (_confirmed(saved) != null || inManifest) {
            throw StateError(
              'A previously recorded part is missing: ${part.destination}',
            );
          }
          verified.add(null);
          continue;
        }
        if (!_hasWriteIntent(saved) && !inManifest) {
          throw StateError(
            'An unreviewed file occupies ${part.destination}. It was preserved.',
          );
        }
        await _verifyOutput(
          destination,
          current,
          part.size,
          part.sha256,
          control,
          recorded: _confirmed(saved),
        );
        verified.add(current);
      }
      if (outputManifest == null && _confirmed(job.entries.first) != null) {
        throw StateError(
          'The saved split manifest is missing. Existing parts were preserved.',
        );
      }
    } else {
      await _verifyInputManifest(definition, source, control);
      final evidence = await _scanCombineSources(
        source,
        definition.parts.map((part) => part.source).toList(),
        control,
        progress,
        expectedParts: definition.parts.map((part) => part.sha256).toList(),
      );
      if (evidence.$2 != definition.expectedSha256) {
        throw StateError(
          'The input parts changed. Existing output was preserved.',
        );
      }
      await _verifyInputManifest(definition, source, control);
      output = await destination.stat(definition.outputPath);
      if (output != null) {
        if (!_hasWriteIntent(job.entries.first)) {
          throw StateError(
            'An unreviewed file occupies ${definition.outputPath}. It was preserved.',
          );
        }
        await _verifyOutput(
          destination,
          output,
          definition.totalBytes,
          definition.expectedSha256,
          control,
          recorded: _confirmed(job.entries.first),
        );
      } else if (_confirmed(job.entries.first) != null) {
        throw StateError(
          'The previously confirmed combined output is missing.',
        );
      }
    }
    _checkBindings(
      job,
      source,
      destination,
      control,
      allowSession: allowSession,
    );
    final retained = <String>{};
    for (final entry in job.entries) {
      for (final path in [
        entry.recovery['stagedPath'],
        entry.recovery['backupPath'],
        ...List<Object?>.from(
          entry.recovery['retainedCopies'] as List? ?? const [],
        ),
      ]) {
        await control.checkpoint();
        _checkBindings(
          job,
          source,
          destination,
          control,
          allowSession: allowSession,
        );
        if (path is String && await destination.stat(path) != null) {
          retained.add(path);
        }
      }
    }
    return IntegrityRecoveryReview(
      jobId: id,
      definition: definition,
      verifiedOutputs: List.unmodifiable(verified),
      retainedPaths: List.unmodifiable(retained),
      manifest: outputManifest,
      output: output,
      fingerprint: IntegrityRecoveryReview.evidenceFingerprint({
        'definition': _definitionEvidence(job),
        'directory': integrityFileJson(directory),
        'parts': verified
            .map((file) => file == null ? null : integrityFileJson(file))
            .toList(),
        'manifest': outputManifest?.definitionFingerprint,
        'output': output == null ? null : integrityFileJson(output),
      }),
    );
  }

  /// The review is checked again under the admission gate before any mutation.
  Future<void> resume(
    IntegrityRecoveryReview reviewed, {
    required FileOperationBackend source,
    required FileOperationBackend destination,
    FileOperationControl? control,
    IntegrityProgress? onProgress,
  }) => journal.runExclusiveOperation(reviewed.jobId, () async {
    final currentControl = control ?? FileOperationControl();
    final current = await _review(
      reviewed.jobId,
      source,
      destination,
      currentControl,
      onProgress,
    );
    if (current.fingerprint != reviewed.fingerprint) {
      throw StateError(
        'The recovery evidence changed after review. Review again before continuing.',
      );
    }
    await _run(current, source, destination, currentControl, onProgress);
  });

  /// Explicitly forget instructions, retaining every source, output and stage.
  Future<void> forget(String id) => journal.runExclusiveOperation(id, () async {
    await journal.initialize();
    final job = journal.job(id);
    if (job == null || !isIntegrityJob(job)) {
      throw StateError('Unknown integrity operation.');
    }
    await journal.dismiss(id);
  });

  Future<void> _run(
    IntegrityRecoveryReview review,
    FileOperationBackend source,
    FileOperationBackend destination,
    FileOperationControl control,
    IntegrityProgress? progress,
  ) async {
    final id = review.jobId;
    await journal.setStatus(id, TransferJobStatus.running);
    try {
      if (review.definition.kind == IntegrityOperationKind.split) {
        await _resumeSplit(review, source, destination, control, progress);
      } else {
        await _resumeCombine(review, source, destination, control, progress);
      }
      await journal.setStatus(
        id,
        TransferJobStatus.completed,
        message: 'All integrity outputs verified. Sources were retained.',
      );
    } catch (error) {
      try {
        await journal.setStatus(
          id,
          error is FileIntegrityCancelled || error is FileOperationCancelled
              ? TransferJobStatus.cancelled
              : TransferJobStatus.failed,
          message: '$error',
        );
      } catch (_) {
        /* The previous durable intent remains recoverable. */
      }
      rethrow;
    }
  }

  Future<void> _resumeSplit(
    IntegrityRecoveryReview review,
    FileOperationBackend source,
    FileOperationBackend destination,
    FileOperationControl control,
    IntegrityProgress? progress,
  ) async {
    final definition = review.definition;
    final verified = review.verifiedOutputs.toList();
    var currentManifest = review.manifest;
    Future<void> saveManifest({bool complete = false}) async {
      _check(source, destination, control);
      final count = verified.takeWhile((file) => file != null).length;
      final manifest = SplitManifest(
        originalName: definition.originalName,
        totalBytes: definition.totalBytes,
        chunkSize: definition.chunkSize,
        status: complete
            ? SplitManifestStatus.complete
            : SplitManifestStatus.incomplete,
        parts: definition.completeManifest.parts.take(count).toList(),
        sha256: complete ? definition.expectedSha256 : null,
      );
      final bytes = manifest.encode();
      final hash = ChecksumAccumulator(ChecksumAlgorithm.sha256)..add(bytes);
      final expectedPrevious = currentManifest?.definitionFingerprint;
      Future<void> checkPrevious() async {
        _check(source, destination, control);
        final existing = await _readSplitOutputManifest(
          definition,
          destination,
          control,
        );
        if (existing?.definitionFingerprint != expectedPrevious) {
          throw StateError('The split manifest changed during recovery.');
        }
        _check(source, destination, control);
      }

      await checkPrevious();
      await _write(
        review.jobId,
        0,
        destination,
        Stream.value(bytes),
        bytes.length,
        hash.finish(),
        control,
        replace: currentManifest != null,
        beforeCommit: checkPrevious,
      );
      currentManifest = manifest;
    }

    for (var i = 0; i < verified.length; i++) {
      if (verified[i] != null) {
        await _confirm(review.jobId, i + 1, verified[i]!);
      }
    }
    if (currentManifest?.status == SplitManifestStatus.complete &&
        verified.every((file) => file != null)) {
      final manifestFile = await destination.stat(definition.outputPath);
      if (manifestFile == null) {
        throw StateError('The split manifest disappeared.');
      }
      await _confirm(review.jobId, 0, manifestFile);
      return;
    }
    // Save the verified prefix before continuing. A crash after a part commit
    // but before its manifest update can now be reconciled without recopying.
    await saveManifest();
    final original = await _requireOriginal(
      source,
      definition.sourceFile,
      control,
    );
    final reader = _IntegrityReader(control.bind(source.readFile(original)));
    final whole = ChecksumAccumulator(ChecksumAlgorithm.sha256);
    var transferred = 0;
    try {
      for (var i = 0; i < definition.parts.length; i++) {
        final part = definition.parts[i];
        final hash = ChecksumAccumulator(ChecksumAlgorithm.sha256);
        var consumed = 0;
        final stream = reader.take(part.size, (bytes) {
          _check(source, destination, control);
          consumed += bytes.length;
          transferred += bytes.length;
          hash.add(bytes);
          whole.add(bytes);
          progress?.call(
            'Verifying and splitting',
            transferred,
            definition.totalBytes,
          );
        });
        if (verified[i] != null) {
          await stream.drain<void>();
          if (hash.finish() != part.sha256) {
            throw StateError('The original source changed during recovery.');
          }
        } else {
          await _write(
            review.jobId,
            part.index,
            destination,
            stream,
            part.size,
            part.sha256,
            control,
            beforeCommit: () async {
              _check(source, destination, control);
              if (consumed != part.size || hash.finish() != part.sha256) {
                throw StateError('The source part changed before commit.');
              }
              await _requireOriginal(source, definition.sourceFile, control);
            },
          );
          verified[i] = await destination.stat(part.destination);
          await saveManifest();
        }
      }
      if (await reader.hasMore || whole.finish() != definition.expectedSha256) {
        throw StateError('The original source changed during recovery.');
      }
      await _requireOriginal(source, definition.sourceFile, control);
      // Revalidate every output before publishing a complete manifest.
      for (final part in definition.parts) {
        final file = await destination.stat(part.destination);
        if (file == null) {
          throw StateError('A split part disappeared before completion.');
        }
        await _verifyOutput(
          destination,
          file,
          part.size,
          part.sha256,
          control,
          recorded: _confirmed(journal.job(review.jobId)!.entries[part.index]),
        );
      }
      await saveManifest(complete: true);
    } finally {
      await reader.close();
    }
  }

  Future<void> _resumeCombine(
    IntegrityRecoveryReview review,
    FileOperationBackend source,
    FileOperationBackend destination,
    FileOperationControl control,
    IntegrityProgress? progress,
  ) async {
    final definition = review.definition;
    if (review.output != null) {
      await _confirm(review.jobId, 0, review.output!);
      return;
    }
    final whole = ChecksumAccumulator(ChecksumAlgorithm.sha256);
    var written = 0;
    Stream<List<int>> joined() async* {
      for (final part in definition.parts) {
        final file = await _requireOriginal(source, part.source, control);
        final digest = ChecksumAccumulator(ChecksumAlgorithm.sha256);
        var count = 0;
        await for (final bytes in control.bind(source.readFile(file))) {
          await control.checkpoint();
          _check(source, destination, control);
          count += bytes.length;
          written += bytes.length;
          if (count > part.size) {
            throw StateError('An input part grew during recovery.');
          }
          digest.add(bytes);
          whole.add(bytes);
          progress?.call(
            'Combining verified parts',
            written,
            definition.totalBytes,
          );
          yield bytes;
        }
        if (count != part.size || digest.finish() != part.sha256) {
          throw StateError('An input part changed during recovery.');
        }
        await _requireOriginal(source, part.source, control);
      }
    }

    await _write(
      review.jobId,
      0,
      destination,
      joined(),
      definition.totalBytes,
      definition.expectedSha256,
      control,
      beforeCommit: () async {
        _check(source, destination, control);
        if (written != definition.totalBytes ||
            whole.finish() != definition.expectedSha256) {
          throw StateError(
            'The combined data does not match the reviewed inputs.',
          );
        }
        await _verifyInputManifest(definition, source, control);
        for (final part in definition.parts) {
          await _requireOriginal(source, part.source, control);
        }
      },
    );
  }

  Future<void> _write(
    String id,
    int index,
    FileOperationBackend destination,
    Stream<List<int>> bytes,
    int length,
    String expected,
    FileOperationControl control, {
    bool replace = false,
    Future<void> Function()? beforeCommit,
  }) async {
    final path = journal.job(id)!.entries[index].destination;
    await destination.writePreparedFile(
      path,
      control.bind(bytes),
      length,
      replace: replace,
      checkpoint: (state) async {
        await control.checkpoint();
        if (!destination.isCurrent) {
          throw StateError('The destination account disconnected.');
        }
        await _checkpoint(id, index, state);
      },
      verifyStaged: (file) async {
        await control.checkpoint();
        await _verifyOutput(destination, file, length, expected, control);
        await beforeCommit?.call();
      },
    );
    final current = await destination.stat(path);
    if (current == null) {
      throw StateError('The output commit could not be confirmed: $path');
    }
    await _verifyOutput(destination, current, length, expected, control);
    await _confirm(id, index, current);
  }

  Future<void> _checkpoint(
    String id,
    int index,
    Map<String, dynamic> state,
  ) async {
    final saved = journal.job(id)!.entries[index];
    final retained = List<String>.from(
      saved.recovery['retainedCopies'] as List? ?? const [],
    );
    for (final key in const ['stagedPath', 'backupPath']) {
      final before = saved.recovery[key];
      final after = state[key];
      if (before is String &&
          state.containsKey(key) &&
          before != after &&
          !retained.contains(before)) {
        if (retained.length >= 100) {
          throw StateError(
            'Review retained staging files before another attempt.',
          );
        }
        retained.add(before);
      }
    }
    final entry = FileOperationEntry(saved.source, saved.destination)
      ..outcome = saved.outcome
      ..recovery = {
        ...saved.recovery,
        ...state,
        if (retained.isNotEmpty) 'retainedCopies': retained,
      };
    await journal.checkpoint(
      id,
      index,
      entry,
      state['phase'] as String? ?? 'writing',
    );
  }

  Future<void> _confirm(String id, int index, FileItem current) async {
    final saved = journal.job(id)!.entries[index];
    final entry = FileOperationEntry(saved.source, saved.destination)
      ..outcome = FileOperationOutcome.copied
      ..recovery = {
        ...saved.recovery,
        'confirmed': integrityFileJson(current),
        'phase': 'confirmed',
      };
    await journal.checkpoint(id, index, entry, 'confirmed');
  }

  static FileItem? _confirmed(TransferEntryRecord entry) =>
      entry.recovery['confirmed'] is Map
      ? transferFileFromJson(
          Map<String, dynamic>.from(entry.recovery['confirmed'] as Map),
        )
      : null;
  static bool _hasWriteIntent(TransferEntryRecord entry) =>
      _confirmed(entry) != null ||
      const [
        'staging',
        'allocating',
        'writing',
        'committing',
        'committed',
        'confirmed',
        'backingUp',
      ].contains(entry.phase);

  static void _check(
    FileOperationBackend source,
    FileOperationBackend destination,
    FileOperationControl control,
  ) {
    checkIntegrityCurrent(source, () => control.isCancelled);
    checkIntegrityCurrent(destination, () => control.isCancelled);
  }

  static void _checkBindings(
    TransferJobRecord job,
    FileOperationBackend source,
    FileOperationBackend destination,
    FileOperationControl control, {
    bool allowSession = false,
  }) {
    _check(source, destination, control);
    if ((!job.canRecover && !allowSession) ||
        job.source != source.storageReference ||
        job.destination != destination.storageReference) {
      throw StateError(
        'Reconnect the exact original source and destination accounts to recover this operation.',
      );
    }
  }

  static Future<FileItem> _requireDirectory(
    FileOperationBackend backend,
    String path, {
    FileItem? expected,
  }) async {
    if (!backend.paths.isAbsolute(path) || path.contains('\u0000')) {
      throw StateError('Choose an absolute destination directory.');
    }
    final file = await backend.stat(path);
    if (!backend.isCurrent ||
        file == null ||
        !file.isFolder ||
        file.isSymlink == true ||
        expected != null &&
            (expected.path != file.path ||
                expected.uuid != null && expected.uuid != file.uuid)) {
      throw StateError(
        'The captured destination directory is missing or changed.',
      );
    }
    return file;
  }

  static void _requireStaging(FileOperationBackend destination, int length) {
    if (!destination.supportsStagedVerification) {
      throw UnsupportedError(
        'This destination cannot verify staged integrity output.',
      );
    }
    if (!destination.capabilities.boundedUpload && length > 64 * 1024 * 1024) {
      throw UnsupportedError(
        'This destination cannot stream integrity output of this size.',
      );
    }
  }

  static Future<FileItem> _requireOriginal(
    FileOperationBackend source,
    FileItem saved,
    FileOperationControl control,
  ) async {
    await control.checkpoint();
    final current = await requireIntegrityFile(
      source,
      saved,
      isCancelled: () => control.isCancelled,
    );
    if (!_sameVersion(saved, current)) {
      throw StateError(
        'A reviewed source or input part changed: ${saved.path}',
      );
    }
    return current;
  }

  static Future<void> _verifyOutput(
    FileOperationBackend destination,
    FileItem file,
    int size,
    String expected,
    FileOperationControl control, {
    FileItem? recorded,
  }) async {
    if (file.isFolder ||
        file.isSymlink == true ||
        file.size != size ||
        recorded != null && !_sameVersion(recorded, file)) {
      throw StateError(
        'An output changed or is incomplete: ${file.path}. It was preserved.',
      );
    }
    final digest = await _scanCombineSources(
      destination,
      [file],
      control,
      null,
    );
    if (digest.$2 != expected) {
      throw StateError(
        'An output has unverified contents: ${file.path}. It was preserved.',
      );
    }
  }

  // Native stat returns local DateTimes; journal JSON stores UTC. Normalize
  // their representation while retaining all ordinary version checks.
  static bool _sameVersion(FileItem before, FileItem after) =>
      sameIntegrityVersion(
        before.copyWith(updatedAt: before.updatedAt?.toUtc()),
        after.copyWith(updatedAt: after.updatedAt?.toUtc()),
      );

  static Future<(List<String>, String)> _scanSplitSource(
    FileOperationBackend source,
    FileItem saved,
    int total,
    int chunkSize,
    FileOperationControl control,
    IntegrityProgress? progress,
  ) async {
    final file = await _requireOriginal(source, saved, control);
    final reader = _IntegrityReader(control.bind(source.readFile(file)));
    final whole = ChecksumAccumulator(ChecksumAlgorithm.sha256);
    final hashes = <String>[];
    var consumed = 0;
    final count = math.max(1, (total + chunkSize - 1) ~/ chunkSize);
    try {
      for (var i = 0; i < count; i++) {
        final hash = ChecksumAccumulator(ChecksumAlgorithm.sha256);
        await for (final bytes in reader.take(
          math.min(chunkSize, total - consumed),
          (_) {},
        )) {
          await control.checkpoint();
          checkIntegrityCurrent(source, () => control.isCancelled);
          consumed += bytes.length;
          hash.add(bytes);
          whole.add(bytes);
          progress?.call('Verifying the original source', consumed, total);
        }
        hashes.add(hash.finish());
      }
      if (await reader.hasMore || consumed != total) {
        throw StateError('The original source length changed.');
      }
      await _requireOriginal(source, saved, control);
      return (hashes, whole.finish());
    } finally {
      await reader.close();
    }
  }

  static Future<(List<String>, String)> _scanCombineSources(
    FileOperationBackend source,
    List<FileItem> saved,
    FileOperationControl control,
    IntegrityProgress? progress, {
    List<String>? expectedParts,
  }) async {
    final whole = ChecksumAccumulator(ChecksumAlgorithm.sha256);
    final hashes = <String>[];
    var bytesRead = 0;
    final total = saved.fold<int>(0, (sum, file) => sum + (file.size ?? 0));
    for (var i = 0; i < saved.length; i++) {
      final file = await _requireOriginal(source, saved[i], control);
      final digest = ChecksumAccumulator(ChecksumAlgorithm.sha256);
      var count = 0;
      await for (final bytes in control.bind(source.readFile(file))) {
        await control.checkpoint();
        checkIntegrityCurrent(source, () => control.isCancelled);
        count += bytes.length;
        bytesRead += bytes.length;
        if (file.size != null && count > file.size!) {
          throw StateError('An input length changed.');
        }
        digest.add(bytes);
        whole.add(bytes);
        progress?.call('Verifying inputs', bytesRead, total);
      }
      final hash = digest.finish();
      if (count != file.size ||
          expectedParts != null && expectedParts[i] != hash) {
        throw StateError('A reviewed input part changed: ${file.path}');
      }
      await _requireOriginal(source, saved[i], control);
      hashes.add(hash);
    }
    return (hashes, whole.finish());
  }

  static bool _sameHashes(List<String> first, Iterable<String> second) {
    final values = second.toList();
    return first.length == values.length &&
        Iterable<int>.generate(first.length)
            .every((index) => first[index] == values[index]);
  }

  static void _validatePaths(
    IntegrityRecoveryDefinition definition,
    FileOperationBackend source,
    FileOperationBackend destination,
    String directory,
  ) {
    if (definition.destinationDirectory.path != directory ||
        !destination.samePath(
          destination.paths.dirname(definition.outputPath),
          directory,
        )) {
      throw const FormatException(
        'The saved output is outside its captured directory.',
      );
    }
    if (definition.kind == IntegrityOperationKind.split) {
      if (!destination.samePath(
        definition.outputPath,
        resolveIntegrityPath(
          destination,
          directory,
          '${definition.originalName}.split.json',
        ),
      )) {
        throw const FormatException('The saved split manifest path changed.');
      }
      for (final part in definition.parts) {
        if (part.relativePath !=
                FileSplitService.partName(
                  definition.originalName,
                  part.index,
                ) ||
            !destination.samePath(
              part.destination,
              resolveIntegrityPath(destination, directory, part.relativePath),
            ) ||
            part.source.path != definition.sourceFile.path) {
          throw const FormatException('A saved split part path changed.');
        }
      }
    } else {
      final inputManifest = definition.inputManifest;
      if (inputManifest != null) {
        final base = source.paths.dirname(inputManifest.path!);
        for (final part in definition.parts) {
          if (!source.samePath(
            part.source.path!,
            resolveIntegrityPath(source, base, part.relativePath),
          )) {
            throw const FormatException('A saved input part path changed.');
          }
        }
      }
    }
  }

  static Future<SplitManifest?> _readSplitOutputManifest(
    IntegrityRecoveryDefinition definition,
    FileOperationBackend destination,
    FileOperationControl control,
  ) async {
    final file = await destination.stat(definition.outputPath);
    if (file == null) return null;
    final manifest = await FileSplitService.readManifest(
      destination,
      file,
      isCancelled: () => control.isCancelled,
    );
    final expected = definition.completeManifest;
    if (manifest.originalName != expected.originalName ||
        manifest.totalBytes != expected.totalBytes ||
        manifest.chunkSize != expected.chunkSize ||
        manifest.parts.length > expected.parts.length ||
        manifest.sha256 != null && manifest.sha256 != expected.sha256 ||
        manifest.status == SplitManifestStatus.complete &&
            manifest.sha256 != expected.sha256) {
      throw StateError(
        'The split manifest definition changed. It was preserved.',
      );
    }
    for (var i = 0; i < manifest.parts.length; i++) {
      final before = expected.parts[i];
      final after = manifest.parts[i];
      if (before.path != after.path ||
          before.size != after.size ||
          before.sha256 != after.sha256) {
        throw StateError(
          'The split manifest definition changed. It was preserved.',
        );
      }
    }
    return manifest;
  }

  static Future<void> _verifyInputManifest(
    IntegrityRecoveryDefinition definition,
    FileOperationBackend source,
    FileOperationControl control,
  ) async {
    final file = definition.inputManifest;
    if (file == null) return;
    final current = await FileSplitService.readManifest(
      source,
      file,
      isCancelled: () => control.isCancelled,
    );
    if (current.definitionFingerprint != definition.inputManifestFingerprint) {
      throw const SplitManifestChangedException();
    }
  }

  static Object _definitionEvidence(TransferJobRecord job) => {
    'source': job.source?.toJson(),
    'destination': job.destination?.toJson(),
    'directory': job.targetDirectory,
    'entries': [
      for (final entry in job.entries)
        {
          'destination': entry.destination,
          'definition': {
            for (final key in const [
              'integrityVersion',
              'integrityKind',
              'originalName',
              'totalBytes',
              'chunkSize',
              'expectedSha256',
              'sourceFile',
              'destinationDirectory',
              'legacy',
              'inputManifest',
              'inputManifestFingerprint',
              'integrityPart',
              'partSize',
              'partSha256',
              'relativePath',
            ])
              if (entry.recovery.containsKey(key)) key: entry.recovery[key],
          },
        },
    ],
  };
}

/// One source subscription; retained data is at most its current input chunk.
class _IntegrityReader {
  _IntegrityReader(Stream<List<int>> input) : _input = StreamIterator(input);
  final StreamIterator<List<int>> _input;
  List<int> _bytes = const [];
  int _offset = 0;
  bool _ended = false;
  Future<bool> _next() async {
    if (_ended) return false;
    while (_offset == _bytes.length) {
      if (!await _input.moveNext()) {
        _ended = true;
        return false;
      }
      _bytes = _input.current;
      _offset = 0;
    }
    return true;
  }

  Stream<List<int>> take(int length, void Function(List<int>) consume) async* {
    var remaining = length;
    while (remaining > 0) {
      if (!await _next()) {
        throw StateError('The source ended before its reviewed size.');
      }
      final count = math.min(
        remaining,
        math.min(_bytes.length - _offset, 256 * 1024),
      );
      final bytes = _bytes.sublist(_offset, _offset + count);
      _offset += count;
      remaining -= count;
      consume(bytes);
      yield bytes;
    }
  }

  Future<bool> get hasMore => _next();
  Future<void> close() async {
    if (!_ended) await _input.cancel();
    _ended = true;
    _bytes = const [];
  }
}
