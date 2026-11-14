// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import '../models/file_item.dart';
import '../models/transfer_job.dart';
import 'archive_container_publisher.dart' show sameArchiveFile;
import 'archive_creation_service.dart';
import 'archive_types.dart';
import 'archive_zip_recovery_service.dart';
import 'file_operation_service.dart';

/// The reviewed report and its captured source identity. This object has no
/// authority to change the source. The queue may retain it after its view closes.
class CapturedArchiveZipRecovery {
  CapturedArchiveZipRecovery._(this.source, this.file, this.report)
    : _identity = source.identity,
      _storageId = source.persistentStorageId;

  final FileOperationBackend source;
  final FileItem file;
  final ArchiveZipRecoveryReport report;
  final Object _identity;
  final String? _storageId;

  bool get isCurrent =>
      source.isCurrent &&
      source.identity == _identity &&
      source.persistentStorageId == _storageId;
}

/// Copies a bounded regular file for a review. Scanning never creates output.
/// Every subsequent recovery is bound to this snapshot's SHA-256 and identity.
Future<CapturedArchiveZipRecovery> captureArchiveZipRecovery({
  required FileOperationBackend source,
  required FileItem file,
  FileOperationControl? control,
  bool Function()? isCancelled,
  void Function(ArchiveZipRecoveryProgress)? onProgress,
}) async {
  final captured = transferFileFromJson(transferFileJson(file));
  final identity = source.identity;
  final storageId = source.persistentStorageId;
  final path = captured.path;
  if (path == null ||
      !source.paths.isAbsolute(path) ||
      source.paths.normalize(path) != path ||
      captured.isFolder ||
      captured.isSymlink == true ||
      captured.size == null ||
      captured.size! < 0 ||
      captured.size! > kArchiveReadLimit) {
    throw const ArchiveViewException(
      'ZIP recovery requires a regular source file of at most 64 MiB.',
    );
  }
  Future<void> check() async {
    if (!source.isCurrent ||
        source.identity != identity ||
        source.persistentStorageId != storageId) {
      throw StateError('The captured ZIP source is no longer available.');
    }
    if (isCancelled?.call() ?? false) throw const FileOperationCancelled();
    await control?.checkpoint();
    if (!source.isCurrent ||
        source.identity != identity ||
        source.persistentStorageId != storageId) {
      throw StateError('The captured ZIP source is no longer available.');
    }
    if (isCancelled?.call() ?? false) throw const FileOperationCancelled();
  }

  Future<void> validate() async {
    await check();
    if (!sameArchiveFile(captured, await source.stat(path))) {
      throw StateError('The ZIP source changed. Scan it again.');
    }
    await check();
  }

  await validate();
  final bytes = BytesBuilder(copy: false);
  final input = source.readFile(captured).timeout(const Duration(seconds: 30));
  await for (final chunk in control?.bind(input) ?? input) {
    await check();
    if (chunk.length > captured.size! - bytes.length) {
      throw StateError('The ZIP source size changed while reading.');
    }
    if (chunk is! Uint8List && chunk.any((value) => value < 0 || value > 255)) {
      throw StateError('The ZIP source returned invalid bytes.');
    }
    bytes.add(Uint8List.fromList(chunk));
  }
  if (bytes.length != captured.size) {
    throw StateError('The ZIP source is truncated. Scan it again.');
  }
  await validate();
  final memory = koni.MemoryByteSource(bytes.takeBytes(), name: captured.name);
  try {
    final report = await scanArchiveZipRecovery(
      memory,
      validateUnchanged: validate,
      checkpoint: check,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
    return CapturedArchiveZipRecovery._(source, captured, report);
  } finally {
    await memory.close();
  }
}

/// Rebuilds and independently verifies a private ZIP, then uses the existing
/// staged, exclusive new-file publisher. Neither source nor existing output is
/// replaced. The input is hashed again before publication, including after a
/// pause; an observed install remains successful if a later observer fails.
Future<ArchiveCreationResult> publishArchiveZipRecovery({
  required CapturedArchiveZipRecovery captured,
  required FileOperationBackend destination,
  required String destinationDirectory,
  required String outputName,
  required Set<int> selectedOffsets,
  FileOperationControl? control,
  void Function(ArchiveZipRecoveryProgress)? onProgress,
  Future<void> Function(Map<String, dynamic>)? onPublicationCheckpoint,
}) async {
  final selection = Set<int>.unmodifiable(selectedOffsets);
  ArchiveCreationOptions(name: outputName).validate();
  if (!destination.supportsStagedVerification ||
      !destination.paths.isAbsolute(destinationDirectory) ||
      destination.paths.normalize(destinationDirectory) !=
          destinationDirectory) {
    throw StateError('ZIP recovery needs a destination with verified staging.');
  }
  final identity = destination.identity;
  final storageId = destination.persistentStorageId;
  final output = destination.paths.join(destinationDirectory, outputName);
  if (captured.source.identity == identity &&
      destination.samePath(captured.file.path!, output)) {
    throw StateError('Choose a new filename for the recovered ZIP.');
  }
  var committed = false;
  Object? warning;
  var pauseEpoch = 0;
  final subscription = control?.changes.listen((_) {
    if (control.isPaused) pauseEpoch++;
  });
  late final ArchiveZipRecoveryResult recovered;
  FileItem? verifiedStage;

  void available() {
    if (!captured.isCurrent ||
        !destination.isCurrent ||
        destination.identity != identity ||
        destination.persistentStorageId != storageId) {
      throw StateError('The captured recovery source or destination changed.');
    }
  }

  Future<void> check() async {
    available();
    await control?.checkpoint();
    available();
  }

  Future<void> checkDestination() async {
    await check();
    var parent = destinationDirectory;
    while (true) {
      final item = await destination.stat(parent);
      await check();
      if (item == null || !item.isFolder || item.isSymlink == true) {
        throw StateError('The recovery destination directory changed.');
      }
      final next = destination.paths.dirname(parent);
      if (next == parent) break;
      parent = next;
    }
    if (await destination.stat(output) != null) {
      throw StateError('The recovery destination already exists.');
    }
    await check();
  }

  Future<String> hashFile(FileOperationBackend backend, FileItem file) async {
    await check();
    if (file.isFolder ||
        file.isSymlink == true ||
        file.size == null ||
        file.size! < 0 ||
        file.size! > kArchiveReadLimit) {
      throw StateError('The recovery verification file is unavailable.');
    }
    var received = 0;
    Stream<List<int>> bytes() async* {
      final input = backend.readFile(file).timeout(const Duration(seconds: 30));
      await for (final chunk in control?.bind(input) ?? input) {
        await check();
        if (chunk.length > file.size! - received) {
          throw StateError('Recovery verification length changed.');
        }
        if (chunk is! Uint8List &&
            chunk.any((value) => value < 0 || value > 255)) {
          throw StateError('Recovery verification returned invalid bytes.');
        }
        received += chunk.length;
        yield chunk;
      }
      await check();
      if (received != file.size ||
          !sameArchiveFile(file, await backend.stat(file.path!))) {
        throw StateError('A recovery verification file changed while reading.');
      }
      await check();
    }

    return (await sha256.bind(bytes()).single).toString();
  }

  Future<void> validateInput() async {
    await check();
    if (!sameArchiveFile(
      captured.file,
      await captured.source.stat(captured.file.path!),
    )) {
      throw StateError('The ZIP source changed since review. Scan it again.');
    }
    if (await hashFile(captured.source, captured.file) !=
        captured.report.sourceSha256) {
      throw StateError('The ZIP source changed since review. Scan it again.');
    }
  }

  Future<void> validateForCommit() async {
    // A pause permits earlier bytes to change without a metadata change. Repeat
    // the complete source/stage proofs until one pass observes no pause.
    while (true) {
      final epoch = pauseEpoch;
      await validateInput();
      final stage = verifiedStage;
      if (stage != null) {
        if (!sameArchiveFile(stage, await destination.stat(stage.path!)) ||
            stage.size != recovered.bytes.length ||
            await hashFile(destination, stage) != recovered.sha256) {
          throw StateError('The staged recovered ZIP did not verify.');
        }
      }
      await checkDestination();
      if (epoch == pauseEpoch) return;
    }
  }

  Future<void> publicationCheckpoint(Map<String, dynamic> state) async {
    final done = state['phase'] == 'committed';
    if (done) committed = true;
    if (!done) await check();
    try {
      await onPublicationCheckpoint?.call({
        ...state,
        'destination': output,
        'packedBytes': recovered.bytes.length,
        'packedSha256': recovered.sha256,
        'sourceSha256': captured.report.sourceSha256,
        'entryCount': recovered.entries.length,
      });
    } catch (error) {
      if (!done) rethrow;
      warning ??= error;
    }
    if (!done) await check();
    if (state['phase'] == 'committing') await validateForCommit();
  }

  ArchiveCreationResult result() => ArchiveCreationResult(
    output,
    recovered.entries.length,
    recovered.bytes.length,
    publicationWarning: warning,
  );
  try {
    await checkDestination();
    await validateInput();
    recovered = await recoverArchiveZip(
      captured.report,
      selectedOffsets: selection,
      checkpoint: check,
      isCancelled: () => control?.isCancelled ?? false,
      onProgress: onProgress,
    );
    await validateInput();
    await checkDestination();
    onProgress?.call(
      ArchiveZipRecoveryProgress(
        ArchiveZipRecoveryPhase.publishing,
        0,
        recovered.bytes.length,
        path: output,
      ),
    );
    await publicationCheckpoint({'phase': 'prepared'});
    Stream<List<int>> outputBytes() async* {
      final bytes = recovered.bytes;
      for (var at = 0; at < bytes.length; at += 65536) {
        await check();
        final end = at + 65536 < bytes.length ? at + 65536 : bytes.length;
        yield Uint8List.sublistView(bytes, at, end);
      }
    }

    await destination.writePreparedFile(
      output,
      outputBytes(),
      recovered.bytes.length,
      replace: false,
      checkpoint: publicationCheckpoint,
      verifyStaged: (staged) async {
        verifiedStage = staged;
        await validateForCommit();
      },
    );
    if (!committed) await publicationCheckpoint({'phase': 'committed'});
    return result();
  } catch (error) {
    if (committed) {
      warning ??= error;
      return result();
    }
    rethrow;
  } finally {
    await subscription?.cancel();
  }
}
