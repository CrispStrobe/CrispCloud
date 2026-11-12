import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'file_conversion_codec.dart';
import 'file_integrity_service.dart';
import 'file_operation_service.dart';
import 'storage_transfer_contract.dart';

export 'file_conversion_codec.dart';

enum FileConversionProblem {
  invalidName,
  invalidDestination,
  unsupportedStorage,
  sourceUnavailable,
  sourceChanged,
  destinationExists,
  verificationFailed,
  cancelled,
}

class FileConversionException implements Exception {
  const FileConversionException(this.problem);
  final FileConversionProblem problem;
  @override
  String toString() => 'File conversion: ${problem.name}';
}

enum FileConversionPhase {
  preparing,
  writing,
  verifyingOutput,
  verifyingSource,
}

class FileConversionProgress {
  const FileConversionProgress(this.phase, this.bytes, this.total);
  final FileConversionPhase phase;
  final int bytes;
  final int? total;
}

class FileConversionOptions {
  const FileConversionOptions({
    required this.direction,
    required this.format,
    required this.outputName,
  });
  final FileConversionDirection direction;
  final FileConversionFormat format;
  final String outputName;

  void validate() {
    // A single portable filename: headers cannot redirect or overwrite output.
    final name = outputName;
    final stem = name.split('.').first.toUpperCase();
    if (name.isEmpty ||
        name.trim() != name ||
        name == '.' ||
        name == '..' ||
        name.endsWith('.') ||
        utf8.encode(name).length > 240 ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]').hasMatch(name) ||
        const {'CON', 'PRN', 'AUX', 'NUL'}.contains(stem) ||
        RegExp(r'^(COM|LPT)[1-9]$').hasMatch(stem)) {
      throw const FileConversionException(FileConversionProblem.invalidName);
    }
  }
}

class FileConversionResult {
  const FileConversionResult({
    required this.path,
    required this.inputBytes,
    required this.outputBytes,
    required this.outputSha256,
  });
  final String path;
  final int inputBytes;
  final int outputBytes;
  final String outputSha256;
}

/// Two streaming conversion passes and read-back verification. A complete
/// syntax check precedes even a temporary write; publication is exclusive and
/// occurs only after the source and staged output still match their hashes.
class FileConversionService {
  const FileConversionService();

  static bool supportsDestination(FileOperationBackend backend) {
    final c = backend.capabilities;
    return backend.supportsStagedVerification &&
        c.boundedUpload &&
        c.boundedDownload &&
        ((c.nativeMove && c.atomicMove && c.noReplaceMove) ||
            (c.nativeCopy &&
                c.noReplaceCopy &&
                c.conditionalCopy &&
                c.conditionalDelete));
  }

  Future<FileConversionResult> convert({
    required FileOperationBackend source,
    required FileItem file,
    required FileOperationBackend destination,
    required String destinationDirectory,
    required FileConversionOptions options,
    FileOperationControl? control,
    void Function(FileConversionProgress)? onProgress,
  }) async {
    options.validate();
    final capturedFile = _snapshot(file);
    final gate = _ConversionGate(
      source,
      destination,
      control ?? FileOperationControl(),
    );
    gate.check();
    if (!source.capabilities.boundedDownload ||
        !supportsDestination(destination)) {
      throw const FileConversionException(
        FileConversionProblem.unsupportedStorage,
      );
    }
    if (file.path == null ||
        !source.paths.isAbsolute(file.path!) ||
        file.isFolder ||
        file.isSymlink == true) {
      throw const FileConversionException(FileConversionProblem.sourceChanged);
    }
    final directory = destination.paths.normalize(destinationDirectory);
    final output = destination.paths.normalize(
      destination.paths.join(directory, options.outputName),
    );
    if (!destination.paths.isAbsolute(directory) ||
        !destination.isWithin(directory, output) ||
        destination.paths.dirname(output) != directory ||
        (source.identity == destination.identity &&
            destination.destinationPathKey(output) ==
                destination.destinationPathKey(file.path!))) {
      throw const FileConversionException(
        FileConversionProblem.invalidDestination,
      );
    }
    const codec = FileConversionCodec();
    if (options.direction == FileConversionDirection.encode) {
      codec.validateFilename(capturedFile.name, options.format);
    }
    final input = _ControlledConversionBackend(source, gate);
    final target = _ControlledConversionBackend(destination, gate);
    final watch = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!gate.current) gate.control.cancel();
    });
    final clock = Stopwatch()..start();
    FileConversionPhase? lastPhase;
    var lastProgress = -100;
    void progress(FileConversionPhase phase, int bytes, int? total) {
      if (onProgress == null) return;
      if (phase == lastPhase &&
          clock.elapsedMilliseconds - lastProgress < 80 &&
          bytes != total) {
        return;
      }
      lastPhase = phase;
      lastProgress = clock.elapsedMilliseconds;
      onProgress(FileConversionProgress(phase, bytes, total));
    }

    try {
      var original = await requireIntegrityFile(input, capturedFile);
      if (!_sameKnownVersion(capturedFile, original, source) ||
          original.size != null && original.size! < 0) {
        throw const FileConversionException(
          FileConversionProblem.sourceChanged,
        );
      }
      original = _snapshot(original);
      final originalDirectory = await target.stat(directory);
      if (originalDirectory == null ||
          !originalDirectory.isFolder ||
          originalDirectory.isSymlink == true) {
        throw const FileConversionException(
          FileConversionProblem.invalidDestination,
        );
      }
      Future<void> checkDestination() async {
        final current = await target.stat(directory);
        if (current == null ||
            !current.isFolder ||
            current.isSymlink == true ||
            (originalDirectory.uuid != null &&
                originalDirectory.uuid != current.uuid)) {
          throw const FileConversionException(
            FileConversionProblem.invalidDestination,
          );
        }
        if (await target.stat(output) != null) {
          throw const FileConversionException(
            FileConversionProblem.destinationExists,
          );
        }
        gate.check();
      }

      Future<void> checkSource() async {
        final current = await input.stat(original.path!);
        if (current == null || !_sameVersion(original, current)) {
          throw const FileConversionException(
            FileConversionProblem.sourceChanged,
          );
        }
      }

      await checkDestination();
      Future<_ConversionPass> prepare() async {
        final pass = _ConversionPass();
        progress(FileConversionPhase.preparing, 0, original.size);
        await for (final chunk in _convert(
          input,
          original,
          options,
          pass,
          (bytes) =>
              progress(FileConversionPhase.preparing, bytes, original.size),
        )) {
          gate.check();
          // The first output is hashed and discarded. No temporary file exists.
          if (chunk.isEmpty) continue;
        }
        await checkSource();
        return pass;
      }

      final prepared = await prepare();
      await checkDestination();
      final written = _ConversionPass();
      progress(FileConversionPhase.writing, 0, original.size);
      var committed = false;
      final result = FileConversionResult(
        path: output,
        inputBytes: prepared.inputBytes,
        outputBytes: prepared.outputBytes,
        outputSha256: prepared.output.finish(),
      );
      try {
        await destination.writePreparedFile(
          output,
          _convert(
            input,
            original,
            options,
            written,
            (bytes) =>
                progress(FileConversionPhase.writing, bytes, original.size),
          ),
          prepared.outputBytes,
          replace: false,
          verifyStaged: (staged) async {
            gate.check();
            if (!written.complete ||
                written.inputBytes != prepared.inputBytes ||
                written.outputBytes != prepared.outputBytes ||
                written.input.finish() != prepared.input.finish() ||
                written.output.finish() != prepared.output.finish()) {
              throw const FileConversionException(
                FileConversionProblem.sourceChanged,
              );
            }
            await checkSource();
            progress(
              FileConversionPhase.verifyingOutput,
              0,
              prepared.outputBytes,
            );
            final actual = await hashIntegrityFile(
              target,
              staged,
              ChecksumAlgorithm.sha256,
              onProgress: (bytes, _) => progress(
                FileConversionPhase.verifyingOutput,
                bytes,
                prepared.outputBytes,
              ),
            );
            if (actual != prepared.output.finish() ||
                staged.size != null && staged.size != prepared.outputBytes) {
              throw const FileConversionException(
                FileConversionProblem.verificationFailed,
              );
            }
            progress(FileConversionPhase.verifyingSource, 0, original.size);
            final originalHash = await hashIntegrityFile(
              input,
              original,
              ChecksumAlgorithm.sha256,
              onProgress: (bytes, _) => progress(
                FileConversionPhase.verifyingSource,
                bytes,
                original.size,
              ),
            );
            if (originalHash != prepared.input.finish()) {
              throw const FileConversionException(
                FileConversionProblem.sourceChanged,
              );
            }
            await checkSource();
            await checkDestination();
            gate.check();
          },
          checkpoint: (state) async {
            // Once the backend confirms commit, cancellation must not report a
            // successfully published file as a failure or encourage a retry.
            if (state['phase'] == 'committed') {
              committed = true;
              return;
            }
            gate.check();
          },
        );
      } catch (_) {
        if (committed) return result;
        rethrow;
      }
      return result;
    } catch (error) {
      gate.check();
      if (error is FileOperationCancelled || error is FileIntegrityCancelled) {
        throw const FileConversionException(FileConversionProblem.cancelled);
      }
      if (error is FileIntegrityUnavailable) {
        throw const FileConversionException(
          FileConversionProblem.sourceChanged,
        );
      }
      rethrow;
    } finally {
      watch.cancel();
    }
  }

  Stream<List<int>> _convert(
    _ControlledConversionBackend source,
    FileItem file,
    FileConversionOptions options,
    _ConversionPass pass,
    void Function(int) progress,
  ) async* {
    Stream<List<int>> raw() async* {
      await for (final bytes in source.readFile(file)) {
        pass.inputBytes += bytes.length;
        if (file.size != null && pass.inputBytes > file.size!) {
          throw const FileConversionException(
            FileConversionProblem.sourceChanged,
          );
        }
        pass.input.add(bytes);
        progress(pass.inputBytes);
        yield bytes;
      }
      if (file.size != null && pass.inputBytes != file.size) {
        throw const FileConversionException(
          FileConversionProblem.sourceChanged,
        );
      }
    }

    const codec = FileConversionCodec();
    final transformed = options.direction == FileConversionDirection.encode
        ? codec.encode(raw(), format: options.format, filename: file.name)
        : codec.decode(raw(), format: options.format);
    await for (final chunk in transformed) {
      source.gate.check();
      pass.output.add(chunk);
      pass.outputBytes += chunk.length;
      yield chunk;
    }
    pass.complete = true;
  }
}

const _versionFields = [
  'etag',
  'eTag',
  'versionId',
  'revision',
  'rev',
  'cTag',
  'content_hash',
];

FileItem _snapshot(FileItem file) => file.copyWith(
  metadata: Map.unmodifiable({
    for (final key in _versionFields)
      if (file.metadata?.containsKey(key) ?? false) key: file.metadata![key],
  }),
);

bool _sameKnownVersion(
  FileItem before,
  FileItem after,
  FileOperationBackend source,
) =>
    before.path != null &&
    after.path != null &&
    source.samePath(before.path!, after.path!) &&
    before.isFolder == after.isFolder &&
    (before.isSymlink == true) == (after.isSymlink == true) &&
    (before.uuid == null || before.uuid == after.uuid) &&
    (before.size == null || before.size == after.size) &&
    (before.updatedAt == null || before.updatedAt == after.updatedAt) &&
    _versionFields.every(
      (key) =>
          before.metadata?[key] == null ||
          before.metadata?[key] == after.metadata?[key],
    );

bool _sameVersion(FileItem before, FileItem after) =>
    sameIntegrityVersion(before, after) &&
    _versionFields.every(
      (key) => before.metadata?[key] == after.metadata?[key],
    );

class _ConversionPass {
  final input = ChecksumAccumulator(ChecksumAlgorithm.sha256);
  final output = ChecksumAccumulator(ChecksumAlgorithm.sha256);
  int inputBytes = 0, outputBytes = 0;
  bool complete = false;
}

class _ConversionGate {
  _ConversionGate(this.source, this.destination, this.control)
    : sourceIdentity = source.identity,
      destinationIdentity = destination.identity;
  final FileOperationBackend source, destination;
  final Object sourceIdentity, destinationIdentity;
  final FileOperationControl control;
  bool get current =>
      source.isCurrent &&
      destination.isCurrent &&
      source.identity == sourceIdentity &&
      destination.identity == destinationIdentity;
  void check() {
    if (!current) {
      throw const FileConversionException(
        FileConversionProblem.sourceUnavailable,
      );
    }
    if (control.isCancelled) {
      throw const FileConversionException(FileConversionProblem.cancelled);
    }
  }
}

/// Applies source identity and cancellation to shared integrity helpers too,
/// including a pending stat or a provider stream that has stopped yielding.
class _ControlledConversionBackend extends FileOperationBackend {
  _ControlledConversionBackend(this.backend, this.gate);
  final FileOperationBackend backend;
  final _ConversionGate gate;
  @override
  Object get identity => backend.identity;
  @override
  String get label => backend.label;
  @override
  p.Context get paths => backend.paths;
  @override
  String pathKey(String path) => backend.pathKey(path);
  @override
  bool get isCurrent => gate.current;
  @override
  StorageTransferCapabilities get capabilities => backend.capabilities;
  @override
  Future<FileItem?> stat(String path) async {
    gate.check();
    final result = await gate.control
        .bind(Stream.fromFuture(backend.stat(path)))
        .first;
    gate.check();
    return result;
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    gate.check();
    await for (final bytes in gate.control.bind(backend.readFile(file))) {
      await gate.control.checkpoint();
      gate.check();
      yield bytes;
    }
    gate.check();
  }

  @override
  Future<List<FileItem>> list(String path) async =>
      throw UnsupportedError('Read-only conversion adapter.');
  @override
  Future<void> createDirectory(String path) async =>
      throw UnsupportedError('Read-only conversion adapter.');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('Read-only conversion adapter.');
  @override
  Future<void> deleteFile(FileItem file) async =>
      throw UnsupportedError('Read-only conversion adapter.');
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => throw UnsupportedError('Read-only conversion adapter.');
}
