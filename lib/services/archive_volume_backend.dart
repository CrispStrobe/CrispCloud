import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/file_item.dart';
import 'archive_output_spool.dart';
import 'archive_output_spool_memory.dart' as memory;
import 'archive_source_cleanup_stub.dart'
    if (dart.library.io) 'archive_source_cleanup_io.dart'
    as native;
import 'archive_streamed_reader.dart';
import 'archive_viewer_service.dart';
import 'archive_viewer_streaming.dart';
import 'archive_volume_source.dart';
import 'file_operation_service.dart';

const int kArchiveVolumeMemoryLimit = 256 * 1024 * 1024;

/// A complete, immutable snapshot of a numbered 7z archive.
/// [archive] owns every temporary part and must be closed by the consumer.
class ArchiveVolumeOpen {
  ArchiveVolumeOpen({
    required this.archive,
    required this.file,
    required List<FileItem> parts,
    required this.fingerprint,
  }) : parts = List<FileItem>.unmodifiable(parts);

  final ViewerArchive archive;
  final FileItem file;
  final List<FileItem> parts;

  /// SHA-256 of all captured part bytes in their logical concatenation order.
  final String fingerprint;
}

/// Captures all numbered siblings from one backend/account/parent directory.
///
/// Only the first fixed-width 7z part may be selected. Numeric padding and case
/// aliases, gaps, links, unknown sizes and inconsistent snapshots are refused.
/// Every member of the manifest is re-statted, its native identity (where
/// available) checked around capture, and the complete sibling list checked
/// again before opening. No inferred archive path is sent to a backend.
///
/// Native inputs are copied to private disk spools under the aggregate 8 GiB
/// bound. Web and [spoolToDisk] false use memory spools under an aggregate
/// 256 MiB bound. Native supported 7z profiles retain streamed member access
/// when [streaming] is enabled; encrypted/filtered profiles use the ordinary
/// reader with [maxMemberBytes] capped at 64 MiB. The returned
/// format is always read-only `volumes/7z`, even if its inner format is writable.
///
/// [createSpool] optionally supplies private bounded snapshot storage. It must
/// provide the same sealing, positional-read and disposal contract as
/// [ArchiveOutputSpool]; the returned archive owns every supplied spool.
Future<ArchiveVolumeOpen> openSevenZipVolumeArchive(
  FileOperationBackend source,
  FileItem selected, {
  String? password,
  int maxInputBytes = kArchiveStreamingLimit,
  bool spoolToDisk = !kIsWeb,
  bool streaming = true,
  int maxMemberBytes = kArchiveReadLimit,
  bool Function()? isCancelled,
  Future<ArchiveOutputSpool> Function(int maxBytes)? createSpool,
}) async {
  if (maxInputBytes <= 0) {
    throw ArgumentError.value(maxInputBytes, 'maxInputBytes');
  }
  if (maxMemberBytes <= 0) {
    throw ArgumentError.value(maxMemberBytes, 'maxMemberBytes');
  }
  final boundedMemberBytes = maxMemberBytes < kArchiveReadLimit
      ? maxMemberBytes
      : kArchiveReadLimit;
  final capturedIdentity = source.identity;
  void check() {
    if (!source.isCurrent || source.identity != capturedIdentity) {
      throw const ArchiveViewException('The split-archive source changed.');
    }
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('Split-archive opening was cancelled.');
    }
  }

  check();
  if (selected.path == null ||
      selected.isFolder ||
      selected.isSymlink == true) {
    throw const ArchiveViewException('Choose a regular first 7z volume.');
  }
  final base = sevenZipVolumeBaseName(selected.name);
  if (base == null || source.paths.basename(selected.path!) != selected.name) {
    throw const ArchiveViewException('Choose the first numbered 7z volume.');
  }
  final parent = source.paths.dirname(selected.path!);
  final nativeStorage = spoolToDisk && !kIsWeb;
  final hardLimit = nativeStorage
      ? kArchiveStreamingLimit
      : kArchiveVolumeMemoryLimit;
  final limit = maxInputBytes < hardLimit ? maxInputBytes : hardLimit;
  final spools = <ArchiveOutputSpool>[];
  var disposed = false;
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    Object? firstError;
    StackTrace? firstStack;
    for (final spool in spools) {
      try {
        await spool.dispose();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }

  ViewerArchive? inner;
  try {
    final manifest = await _listManifest(source, parent, base, check);
    final first = manifest.first;
    if (manifest.any((part) => part.storageId != first.storageId)) {
      throw const ArchiveViewException(
        'All 7z volumes must belong to the same captured storage account.',
      );
    }
    if (first.path != selected.path ||
        first.name != selected.name ||
        selected.uuid != null && first.uuid != selected.uuid ||
        selected.storageId != null && first.storageId != selected.storageId) {
      throw const ArchiveViewException(
        'Open the first numbered 7z volume from its original folder.',
      );
    }
    final parts = <ArchiveVolumePart>[
      for (var index = 0; index < manifest.length; index++)
        ArchiveVolumePart(
          name: manifest[index].name,
          length: manifest[index].size!,
          open: () => spools[index].openByteSource(),
        ),
    ];
    final framing = validateSevenZipVolumeManifest(parts, maxTotalBytes: limit);
    final witnesses = <Object?>[];
    for (final file in manifest) {
      check();
      final current = await source.stat(file.path!);
      check();
      if (!_sameSnapshot(file, current)) {
        throw _changed();
      }
      witnesses.add(
        await native.captureNativeArchiveImportSource(source, file),
      );
      check();
    }
    final digest = _DigestSink();
    final hashing = sha256.startChunkedConversion(digest);
    try {
      for (var index = 0; index < manifest.length; index++) {
        check();
        final file = manifest[index];
        final current = await source.stat(file.path!);
        check();
        if (!_sameSnapshot(file, current)) throw _changed();
        await native.verifyNativeArchiveImportSource(
          source,
          file,
          witnesses[index],
        );
        check();
        final spool = await (createSpool != null
            ? createSpool(file.size!)
            : nativeStorage
            ? ArchiveOutputSpool.create(maxBytes: file.size!)
            : memory.createArchiveOutputSpool(maxBytes: file.size!));
        spools.add(spool);
        check();
        var received = 0;
        await for (final chunk in source.readFile(file)) {
          check();
          if (chunk.length > file.size! - received) throw _changed();
          if (chunk is! Uint8List &&
              chunk.any((byte) => byte < 0 || byte > 255)) {
            throw const ArchiveViewException(
              'A 7z volume contains an invalid byte stream.',
            );
          }
          for (var at = 0; at < chunk.length; at += 256 * 1024) {
            check();
            final remaining = chunk.length - at;
            final take = remaining < 256 * 1024 ? remaining : 256 * 1024;
            final copy = Uint8List.fromList(chunk.sublist(at, at + take));
            hashing.add(copy);
            await spool.write(copy);
            received += copy.length;
          }
        }
        check();
        if (received != file.size) throw _changed();
        await spool.finish();
        check();
        if (spool.length != file.size || !spool.isSealed) throw _changed();
        await native.verifyNativeArchiveImportSource(
          source,
          file,
          witnesses[index],
        );
        check();
        if (!_sameSnapshot(file, await source.stat(file.path!))) {
          throw _changed();
        }
        check();
      }
    } finally {
      hashing.close();
    }
    final after = await _listManifest(source, parent, base, check);
    if (after.length != manifest.length) throw _changed();
    for (var index = 0; index < manifest.length; index++) {
      check();
      final file = manifest[index];
      if (!_sameSnapshot(file, after[index]) ||
          !_sameSnapshot(file, await source.stat(file.path!))) {
        throw _changed();
      }
      check();
      await native.verifyNativeArchiveImportSource(
        source,
        file,
        witnesses[index],
      );
      check();
    }

    Future<ArchiveVolumeSource> joined() => openSevenZipVolumes(
      parts,
      maxTotalBytes: limit,
      isCurrent: () =>
          !disposed &&
          source.isCurrent &&
          source.identity == capturedIdentity &&
          !(isCancelled?.call() ?? false),
    );

    if (nativeStorage && streaming) {
      try {
        final streamed = await openStreamedArchiveSource(
          await joined(),
          name: framing.name,
          password: password,
          maxBytes: limit,
          isCancelled: isCancelled,
        );
        inner = streamed.archive;
      } catch (error) {
        if (!useBoundedArchiveViewerFallback(error)) rethrow;
      }
    }
    inner ??= await openViewerArchiveSource(
      await joined(),
      name: framing.name,
      password: password,
      maxMemberBytes: boundedMemberBytes,
    );
    check();
    if (inner.formatName != '7z') {
      throw const ArchiveViewException('The volume set is not a 7z archive.');
    }
    final opened = inner;
    final archive = ViewerArchive.reader(
      formatName: 'volumes/7z',
      members: opened.members,
      maxStreamingMemberBytes: opened.maxStreamingMemberBytes,
      notices: [...ArchiveVolumeSource.notices, ...opened.notices],
      read: (member, maxBytes) async {
        check();
        final bytes = await opened.readMember(member, maxBytes: maxBytes);
        check();
        return bytes;
      },
      streamReader: (member, chunkSize) async* {
        check();
        await for (final chunk in opened.openMember(
          member,
          maxBytes: opened.maxStreamingMemberBytes,
          chunkSize: chunkSize,
        )) {
          check();
          yield chunk;
        }
        check();
      },
      close: () async {
        try {
          await opened.close();
        } finally {
          await dispose();
        }
      },
    );
    inner = null;
    return ArchiveVolumeOpen(
      archive: archive,
      file: first,
      parts: manifest,
      fingerprint: digest.value!.toString(),
    );
  } catch (error, stack) {
    try {
      await inner?.close();
    } catch (_) {
      // Preserve the capture/open failure.
    }
    try {
      await dispose();
    } catch (_) {
      // Preserve the capture/open failure.
    }
    Error.throwWithStackTrace(error, stack);
  }
}

Future<List<FileItem>> _listManifest(
  FileOperationBackend source,
  String parent,
  String base,
  void Function() check,
) async {
  check();
  final listed = await source.list(parent);
  check();
  final manifest = <FileItem>[];
  final paths = <String>{};
  final identifiers = <String>{};
  for (final file in listed) {
    final candidate = sevenZipVolumeBaseName(file.name);
    if (candidate?.toLowerCase() != base.toLowerCase()) continue;
    if (manifest.length >= kArchiveVolumeCountLimit) {
      throw const ArchiveViewException('The split archive has too many parts.');
    }
    if (candidate != base ||
        file.name.length > 1024 ||
        file.name.length - file.name.lastIndexOf('.') - 1 > 6 ||
        file.path == null ||
        file.name.contains(RegExp(r'[/\\\x00]')) ||
        file.isFolder ||
        file.isSymlink == true ||
        file.size == null ||
        file.size! <= 0 ||
        source.paths.basename(file.path!) != file.name ||
        !source.samePath(source.paths.dirname(file.path!), parent) ||
        !paths.add(source.destinationPathKey(file.path!)) ||
        file.uuid != null && !identifiers.add(file.uuid!)) {
      throw const ArchiveViewException(
        'The 7z volume list contains an alias, link, or ambiguous source.',
      );
    }
    manifest.add(
      file.copyWith(
        metadata: Map<String, dynamic>.unmodifiable(file.metadata ?? const {}),
      ),
    );
  }
  if (manifest.isEmpty) {
    throw const ArchiveViewException('The selected 7z volume is missing.');
  }
  // Sorting is lexical only after the canonical-width check below; integer
  // ordering here also keeps malformed aliases visible to strict validation.
  manifest.sort((a, b) {
    final aNumber = BigInt.parse(a.name.substring(a.name.lastIndexOf('.') + 1));
    final bNumber = BigInt.parse(b.name.substring(b.name.lastIndexOf('.') + 1));
    final order = aNumber.compareTo(bNumber);
    return order != 0 ? order : a.name.compareTo(b.name);
  });
  return List<FileItem>.unmodifiable(manifest);
}

bool _sameSnapshot(FileItem before, FileItem? after) =>
    after != null &&
    !after.isFolder &&
    after.isSymlink != true &&
    before.name == after.name &&
    before.path == after.path &&
    before.uuid == after.uuid &&
    before.storageId == after.storageId &&
    before.size == after.size &&
    before.updatedAt == after.updatedAt &&
    const [
      'etag',
      'eTag',
      'version',
      'versionId',
      'revision',
      'rev',
      'cTag',
      'rangeReadSnapshot',
    ].every((key) => before.metadata?[key] == after.metadata?[key]);

ArchiveViewException _changed() => const ArchiveViewException(
  'The 7z volume set changed while being captured. Reload all parts.',
);

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest value) => this.value = value;
  @override
  void close() {}
}
