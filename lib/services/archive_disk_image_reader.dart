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

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_fat_reader.dart';
import 'archive_ext_reader.dart';
import 'archive_slice_source.dart';
import 'archive_types.dart';
import 'disk_partition_inspector.dart';

const int diskImageMaxPartitions = 32;
const int diskImageMaxEntries = 100000;
const int diskImageMaxMetadataBytes = 64 * 1024 * 1024;
const int diskImageMaxRetainedPathBytes = 16 * 1024 * 1024;
const int diskImageMaxClusters = 1048576;
const int diskImageMaxExtents = 100000;
const int _readBytes = 64 * 1024;
const int _maxExactOffset = 9007199254740991;
const int _maxNotices = 128;
const String _efiSystemGuid = 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B';
const String _basicDataGuid = 'EBD0A0A2-B9E5-4433-87C0-68B6B72699C7';
const String _linuxFilesystemGuid = '0FC63DAF-8483-4772-8E79-3D69D8477DE4';

class ArchiveDiskImageCancelledException extends ArchiveViewException {
  const ArchiveDiskImageCancelledException()
    : super('Disk-image reading was cancelled.');
}

/// Non-owning recognition at fixed MBR/GPT positions, not a filesystem scan.
/// A recognized FAT volume takes precedence over apparent partition bytes in
/// its boot code. Explicit GPT signatures precede the short ext marker: the
/// first GPT partition name can contain that marker at the same byte offset.
/// Ext volumes still precede apparent MBR entries in their unused boot area.
/// An MBR boot signature alone is insufficient recognition.
/// At most two 512-byte reads, one two-byte ext probe and four eight-byte GPT
/// probes are requested.
/// Recognition does not establish a valid or authoritative partition table.
Future<bool> hasDiskImagePartitionRecognition(koni.ByteSource source) async {
  if (source.length < 512 || source.length > _maxExactOffset) return false;
  final prefix = await source.read(0, 512);
  if (prefix.length != 512) {
    throw const ArchiveViewException(
      'The disk-image boot sector could not be read completely.',
      code: ArchiveMessageCode.corrupt,
    );
  }
  if (await hasFatVolumeRecognition(source)) return false;
  for (final sector in const [512, 4096]) {
    final last = (source.length ~/ sector - 1) * sector;
    for (final offset in {sector, last}) {
      if (offset < sector || offset > source.length - sector) continue;
      final bytes = await source.read(offset, 8);
      if (bytes.length != 8) {
        throw const ArchiveViewException(
          'A disk-image signature probe could not be read completely.',
          code: ArchiveMessageCode.corrupt,
        );
      }
      if (_gptSignature(bytes)) return true;
    }
  }
  if (await hasExtVolumeRecognition(source)) return false;
  if (prefix[510] != 0x55 || prefix[511] != 0xaa) return false;
  final data = ByteData.sublistView(prefix);
  var records = 0;
  for (var index = 0; index < 4; index++) {
    final at = 446 + 16 * index;
    final type = prefix[at + 4];
    final first = data.getUint32(at + 8, Endian.little);
    final count = data.getUint32(at + 12, Endian.little);
    if (type == 0 && count == 0) continue;
    if ((prefix[at] != 0 && prefix[at] != 0x80) ||
        type == 0 ||
        first == 0 ||
        count == 0) {
      return false;
    }
    records++;
  }
  return records > 0;
}

bool _gptSignature(Uint8List bytes) {
  const signature = [0x45, 0x46, 0x49, 0x20, 0x50, 0x41, 0x52, 0x54];
  if (bytes.length < signature.length) return false;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}

/// Browse validated primary MBR or mirrored GPT partitions as read-only entries.
/// Each admitted partition has `partition-NNN/raw.img`; eligible FAT/ext volumes
/// also have `partition-NNN/files/...`. Names and numbers come from the chosen
/// table's original indices, never from untrusted filesystem or volume labels.
///
/// The returned archive owns [source], including on failure. Child readers own
/// only non-owning bounded slices. Source/cancellation failures propagate;
/// rejected child filesystems retain their raw partition and an explicit notice.
/// All optional resource limits can only lower the fixed profile ceilings.
Future<ViewerArchive> openDiskImageArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
  int? logicalSectorBytes,
  int maxPartitions = diskImageMaxPartitions,
  int maxEntries = diskImageMaxEntries,
  int maxMetadataBytes = diskImageMaxMetadataBytes,
  int maxRetainedPathBytes = diskImageMaxRetainedPathBytes,
  int maxClusters = diskImageMaxClusters,
  int maxExtents = diskImageMaxExtents,
  bool Function()? isCancelled,
  FutureOr<void> Function()? validateUnchanged,
}) async {
  _DiskImageReader? reader;
  try {
    for (final limit in <(String, int, int)>[
      ('maxMemberBytes', maxMemberBytes, kArchiveStreamingLimit),
      ('maxPartitions', maxPartitions, diskImageMaxPartitions),
      ('maxEntries', maxEntries, diskImageMaxEntries),
      ('maxMetadataBytes', maxMetadataBytes, diskImageMaxMetadataBytes),
      (
        'maxRetainedPathBytes',
        maxRetainedPathBytes,
        diskImageMaxRetainedPathBytes,
      ),
      ('maxClusters', maxClusters, diskImageMaxClusters),
      ('maxExtents', maxExtents, diskImageMaxExtents),
    ]) {
      if (limit.$2 <= 0 || limit.$2 > limit.$3) {
        throw ArgumentError.value(
          limit.$2,
          limit.$1,
          'Outside supported bounds.',
        );
      }
    }
    if (logicalSectorBytes != null &&
        logicalSectorBytes != 512 &&
        logicalSectorBytes != 4096) {
      throw ArgumentError.value(logicalSectorBytes, 'logicalSectorBytes');
    }
    reader = _DiskImageReader(
      _DiskImageSource(
        source,
        maxMetadataBytes,
        isCancelled,
        validateUnchanged,
      ),
      maxMemberBytes,
      logicalSectorBytes,
      maxPartitions,
      maxEntries,
      maxRetainedPathBytes,
      ArchiveFatTraversalBudget(
        maxClusters: maxClusters,
        maxExtents: maxExtents,
      ),
      ArchiveExtTraversalBudget(maxBlocks: maxClusters, maxExtents: maxExtents),
    );
    return await reader.open();
  } catch (error, stack) {
    try {
      if (reader == null) {
        await source.close();
      } else {
        await reader.close();
      }
    } finally {
      Error.throwWithStackTrace(error, stack);
    }
  }
}

/// Whether a completed inspection meets this reader's table/geometry profile.
/// This performs no source reads and grants no publication or write authority.
/// The actual open revalidates the source and reinspects its partition metadata.
bool diskImageAnalysisSupportsBrowsing(DiskPartitionAnalysis analysis) {
  try {
    _admitDiskImageAnalysis(analysis);
    return true;
  } on ArchiveViewException {
    return false;
  }
}

List<DiskPartitionEntry> _admitDiskImageAnalysis(
  DiskPartitionAnalysis analysis, {
  int maxPartitions = diskImageMaxPartitions,
}) {
  Never bad(String detail) => throw ArchiveViewException(
    'Invalid disk image: $detail',
    code: ArchiveMessageCode.corrupt,
  );
  Never unsupported(String detail) => throw ArchiveViewException(
    'Unsupported disk image: $detail',
    code: ArchiveMessageCode.unsupported,
  );
  if (analysis.totalBytes < 512 ||
      analysis.totalBytes > _maxExactOffset ||
      (analysis.sectorBytes != 512 && analysis.sectorBytes != 4096)) {
    unsupported('No supported exact disk geometry was identified.');
  }
  List<DiskPartitionEntry> bounded(List<DiskPartitionEntry> entries) {
    if (entries.length > maxPartitions) {
      throw ArchiveViewException(
        'The disk has more than $maxPartitions supported partition records.',
        code: ArchiveMessageCode.archiveLimit,
      );
    }
    final sector = BigInt.from(analysis.sectorBytes!);
    for (final entry in entries) {
      final start = entry.firstLba * sector;
      final end = (entry.lastLba + BigInt.one) * sector;
      if (start < sector ||
          end <= start ||
          end > BigInt.from(analysis.totalBytes)) {
        bad('A partition range leaves the image.');
      }
    }
    return entries;
  }

  if (analysis.scheme == DiskPartitionScheme.none ||
      analysis.sectorBytes == null) {
    unsupported('No unambiguous supported partition table was identified.');
  }
  final allowed = analysis.scheme == DiskPartitionScheme.mbr
      ? const {
          DiskPartitionFindingCode.sectorSizeAssumed,
          DiskPartitionFindingCode.extendedPartitionsNotInspected,
        }
      : const <DiskPartitionFindingCode>{};
  final refused = analysis.findings.where(
    (finding) => !allowed.contains(finding.code),
  );
  if (refused.isNotEmpty) {
    bad('Partition-table validation failed: ${refused.first.message}');
  }
  if (analysis.scheme == DiskPartitionScheme.gpt) {
    if (analysis.headers.length != 2 ||
        !analysis.headers.every(
          (header) =>
              header.present &&
              header.headerCrcStatus == DiskPartitionCheckStatus.valid &&
              header.tableCrcStatus == DiskPartitionCheckStatus.valid,
        )) {
      bad('Both GPT headers and partition arrays must be present and valid.');
    }
    final primary = analysis.headers.where(
      (header) => header.role == DiskGptHeaderRole.primary,
    );
    final backup = analysis.headers.where(
      (header) => header.role == DiskGptHeaderRole.backup,
    );
    if (primary.length != 1 || backup.length != 1) {
      bad('The GPT mirror roles are ambiguous.');
    }
    return bounded(primary.single.partitions);
  }
  final partitions = analysis.partitions;
  if (partitions.isEmpty) {
    unsupported('The MBR has no nonempty partition records.');
  }
  return bounded(partitions);
}

class _DiskImageReader {
  _DiskImageReader(
    this.source,
    this.maxMemberBytes,
    this.logicalSectorBytes,
    this.maxPartitions,
    this.maxEntries,
    this.maxRetainedPathBytes,
    this.traversalBudget,
    this.extTraversalBudget,
  );

  final _DiskImageSource source;
  final int maxMemberBytes;
  final int? logicalSectorBytes;
  final int maxPartitions, maxEntries, maxRetainedPathBytes;
  final ArchiveFatTraversalBudget traversalBudget;
  final ArchiveExtTraversalBudget extTraversalBudget;
  final _members = <ViewerArchiveMember>[];
  final _targets = <_DiskImageTarget?>[];
  final _children = <ViewerArchive>[];
  final _notices = <String>[];
  var _pathBytes = 0;
  var _omittedNotices = 0;
  var _closed = false;

  Future<ViewerArchive> open() async {
    if (source.length < 512 || source.length > _maxExactOffset) {
      _bad('The image length is outside the supported exact range.');
    }
    await source.validate();
    if (await hasFatVolumeRecognition(source)) {
      _unsupported(
        'This source is a standalone FAT volume, not a partitioned disk.',
      );
    }
    final analysis = await inspectDiskPartitions(
      totalBytes: source.length,
      read: source.read,
      logicalSectorBytes: logicalSectorBytes,
      isCancelled: () => source.cancelled,
      validateUnchanged: source.validate,
    );
    source.check();
    if (analysis.scheme == DiskPartitionScheme.mbr &&
        await hasExtVolumeRecognition(source)) {
      _unsupported(
        'This source is a standalone ext volume, not a partitioned disk.',
      );
    }
    final partitions = _admitDiskImageAnalysis(
      analysis,
      maxPartitions: maxPartitions,
    );
    _notice(
      'Read-only ${analysis.scheme.name.toUpperCase()} disk image. Raw partition '
      'images and filesystem files describe overlapping content; extracting '
      'both copies that content twice.',
    );
    for (final finding in analysis.findings) {
      _notice(finding.message);
    }
    final sector = analysis.sectorBytes!;
    for (final partition in partitions) {
      await Future<void>.delayed(Duration.zero);
      await source.validate();
      final first = partition.firstLba * BigInt.from(sector);
      final end = (partition.lastLba + BigInt.one) * BigInt.from(sector);
      if (first < BigInt.from(sector) ||
          end <= first ||
          end > BigInt.from(source.length) ||
          end > BigInt.from(_maxExactOffset)) {
        _bad('A partition range is not representable within this image.');
      }
      final offset = first.toInt();
      final length = (end - first).toInt();
      final prefix = 'partition-${partition.index.toString().padLeft(3, '0')}';
      _add(prefix, 0, false);
      _add(
        '$prefix/raw.img',
        length,
        true,
        target: _DiskImageTarget.raw(offset),
      );
      final ext = _extType(partition, analysis.scheme);
      final filesystemName = ext ? 'ext' : 'FAT';
      if (!ext && !_fatType(partition, analysis.scheme)) {
        _notice(
          '$prefix: partition type ${partition.type} is exposed as raw bytes '
          'only. No filesystem, extended chain, dynamic disk or encryption '
          'interpretation was attempted.',
        );
        continue;
      }
      final slice = ArchiveSliceSource(
        source,
        offset: offset,
        length: length,
        name: '$prefix/raw.img',
        ownsParent: false,
      );
      ViewerArchive? child;
      try {
        final recognized = ext
            ? await hasExtVolumeRecognition(slice)
            : await hasFatVolumeRecognition(slice);
        if (!recognized) {
          _notice(
            '$prefix: no supported $filesystemName volume was recognized; raw bytes remain available.',
          );
          await slice.close();
          continue;
        }
        // Reserve the synthetic files directory before assigning the remaining
        // entry/path allowances to the child. Prefixed paths are charged again
        // below; the child-relative strings are retained by its own reader.
        final root = '$prefix/files';
        final remainingEntries = maxEntries - _members.length - 1;
        final remainingPaths =
            maxRetainedPathBytes - _pathBytes - root.length * 2;
        // Both filesystem kinds spend the same disk-wide allocation allowance.
        // Failed children retain their debits; mixing formats cannot multiply
        // the budget by giving each adapter a fresh full allocation allowance.
        final remainingBlocks =
            traversalBudget.maxClusters -
            traversalBudget.clustersVisited -
            extTraversalBudget.blocksVisited;
        final remainingExtents =
            traversalBudget.maxExtents -
            traversalBudget.extentsCreated -
            extTraversalBudget.extentsCreated;
        if (remainingEntries <= 0 ||
            remainingPaths <= 0 ||
            remainingBlocks <= 0 ||
            remainingExtents <= 0 ||
            source.metadataRemaining <= 0) {
          _limit('No listing budget remains for another filesystem.');
        }
        child = ext
            ? await openExtArchive(
                slice,
                maxMemberBytes: maxMemberBytes,
                maxEntries: remainingEntries,
                maxMetadataBytes: source.metadataRemaining,
                maxRetainedPathBytes: remainingPaths,
                maxBlocks: remainingBlocks,
                maxExtents: remainingExtents,
                traversalBudget: extTraversalBudget,
                isCancelled: () => source.cancelled,
              )
            : await openFatArchive(
                slice,
                maxMemberBytes: maxMemberBytes,
                maxEntries: remainingEntries,
                maxMetadataBytes: source.metadataRemaining,
                maxRetainedPathBytes: remainingPaths,
                maxClusters: remainingBlocks,
                maxExtents: remainingExtents,
                traversalBudget: traversalBudget,
                isCancelled: () => source.cancelled,
              );
        _children.add(child);
        await source.validate();
      } on ArchiveFatCancelledException {
        rethrow;
      } on ArchiveExtCancelledException {
        rethrow;
      } on ArchiveViewException catch (error) {
        source.throwReadFailure();
        source.check();
        if (!const {
          ArchiveMessageCode.corrupt,
          ArchiveMessageCode.unsupported,
          ArchiveMessageCode.archiveLimit,
          ArchiveMessageCode.entryLimit,
          ArchiveMessageCode.entryLimitDetail,
        }.contains(error.code)) {
          rethrow;
        }
        await slice.close();
        _notice(
          '$prefix: $filesystemName listing was refused: ${error.message} Raw bytes remain available.',
        );
        continue;
      }
      // Each child retains its original relative paths as well as the
      // composite listing's prefixed strings. Charge both sets to one budget.
      for (final member in child.members) {
        if (member.name.length * 2 > maxRetainedPathBytes - _pathBytes) {
          _limit(
            'The combined retained relative-path text limit was exceeded.',
          );
        }
        _pathBytes += member.name.length * 2;
      }
      _add('$prefix/files', 0, false);
      for (final member in child.members) {
        if (member.name.isEmpty ||
            member.name.contains('\\') ||
            member.name
                .split('/')
                .any((part) => part.isEmpty || part == '.' || part == '..')) {
          _bad('A child filesystem supplied an unsafe member path.');
        }
        _add(
          '$prefix/files/${member.name}',
          member.size,
          member.isFile,
          target: _DiskImageTarget.child(child, member),
          original: member,
        );
      }
      for (final notice in child.notices) {
        _notice('$prefix: $notice');
      }
    }
    await source.validate();
    source.listing = false;
    if (_omittedNotices != 0) {
      _notices.add(
        '$_omittedNotices additional filesystem notices were omitted.',
      );
    }
    return ViewerArchive.reader(
      formatName: 'disk-image',
      maxStreamingMemberBytes: maxMemberBytes,
      members: _members,
      notices: _notices,
      read: _read,
      streamReader: _stream,
      close: close,
    );
  }

  bool _fatType(DiskPartitionEntry partition, DiskPartitionScheme scheme) {
    if (scheme == DiskPartitionScheme.gpt) {
      return partition.type == _efiSystemGuid ||
          partition.type == _basicDataGuid;
    }
    return const {
      '0x01',
      '0x04',
      '0x06',
      '0x0B',
      '0x0C',
      '0x0E',
      '0xEF EFI system',
    }.contains(partition.type);
  }

  bool _extType(DiskPartitionEntry partition, DiskPartitionScheme scheme) =>
      scheme == DiskPartitionScheme.gpt
      ? partition.type == _linuxFilesystemGuid
      : partition.type == '0x83';

  void _add(
    String path,
    int size,
    bool file, {
    _DiskImageTarget? target,
    ViewerArchiveMember? original,
  }) {
    if (_members.length >= maxEntries) {
      _limit('The combined listing entry limit was exceeded.');
    }
    if (path.length > 4096 ||
        path.length * 2 > maxRetainedPathBytes - _pathBytes) {
      _limit('The combined retained full-path text limit was exceeded.');
    }
    _pathBytes += path.length * 2;
    _members.add(
      ViewerArchiveMember(
        name: path,
        size: size,
        isFile: file,
        isEncrypted: original?.isEncrypted ?? false,
        isSpecial: original?.isSpecial ?? false,
        modified: original?.modified,
        posixMode: original?.posixMode,
        pathEscapedRoot: original?.pathEscapedRoot ?? false,
        index: _members.length,
      ),
    );
    _targets.add(target);
  }

  void _notice(String message) {
    if (_notices.length >= _maxNotices - 1) {
      _omittedNotices++;
      return;
    }
    _notices.add(
      message.length <= 1024 ? message : '${message.substring(0, 1023)}…',
    );
  }

  Future<Uint8List> _read(ViewerArchiveMember member, int requested) async {
    source.check();
    final limit = requested < maxMemberBytes ? requested : maxMemberBytes;
    if (member.size > limit || member.size > kArchiveReadLimit) {
      _limit('The member exceeds its buffered read allowance.');
    }
    final target = _targets[member.index]!;
    if (target.archive case final archive?) {
      return archive.readMember(target.member!, maxBytes: limit);
    }
    final bytes = Uint8List(member.size);
    for (var at = 0; at < bytes.length;) {
      final left = bytes.length - at;
      final count = left < _readBytes ? left : _readBytes;
      bytes.setRange(
        at,
        at + count,
        await source.read(target.offset! + at, count),
      );
      at += count;
    }
    return bytes;
  }

  Stream<List<int>> _stream(
    ViewerArchiveMember member,
    int requestedChunk,
  ) async* {
    source.check();
    if (member.size > maxMemberBytes) {
      _limit('The member exceeds its streamed read allowance.');
    }
    final chunkSize = requestedChunk < _readBytes ? requestedChunk : _readBytes;
    final target = _targets[member.index]!;
    if (target.archive case final archive?) {
      yield* archive.openMember(
        target.member!,
        maxBytes: maxMemberBytes,
        chunkSize: chunkSize,
      );
      return;
    }
    for (var at = 0; at < member.size;) {
      final left = member.size - at;
      final count = left < chunkSize ? left : chunkSize;
      yield await source.read(target.offset! + at, count);
      at += count;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    Object? error;
    StackTrace? stack;
    for (final child in _children) {
      try {
        await child.close();
      } catch (caught, trace) {
        error ??= caught;
        stack ??= trace;
      }
    }
    _children.clear();
    _targets.clear();
    try {
      await source.close();
    } catch (caught, trace) {
      error ??= caught;
      stack ??= trace;
    }
    if (error != null) Error.throwWithStackTrace(error, stack!);
  }

  Never _bad(String detail) => throw ArchiveViewException(
    'Invalid disk image: $detail',
    code: ArchiveMessageCode.corrupt,
  );
  Never _unsupported(String detail) => throw ArchiveViewException(
    'Unsupported disk image: $detail',
    code: ArchiveMessageCode.unsupported,
  );
  Never _limit(String detail) => throw ArchiveViewException(
    'Disk-image limit: $detail',
    code: ArchiveMessageCode.archiveLimit,
  );
}

class _DiskImageTarget {
  const _DiskImageTarget.raw(this.offset) : archive = null, member = null;
  const _DiskImageTarget.child(this.archive, this.member) : offset = null;
  final int? offset;
  final ViewerArchive? archive;
  final ViewerArchiveMember? member;
}

class _DiskImageSource implements koni.ByteSource {
  _DiskImageSource(
    this.source,
    this.maxMetadataBytes,
    this.isCancelled,
    this.validateUnchanged,
  ) : length = source.length,
      name = source.name;

  final koni.ByteSource source;
  final int maxMetadataBytes;
  final bool Function()? isCancelled;
  final FutureOr<void> Function()? validateUnchanged;
  @override
  final int length;
  @override
  final String? name;
  var listing = true;
  var metadataBytes = 0;
  var _closed = false;
  (Object, StackTrace)? _readFailure;
  int get metadataRemaining => maxMetadataBytes - metadataBytes;
  bool get cancelled => isCancelled?.call() ?? false;

  void throwReadFailure() {
    if (_readFailure case final failure?) {
      Error.throwWithStackTrace(failure.$1, failure.$2);
    }
  }

  void check() {
    throwReadFailure();
    if (_closed) {
      throw const ArchiveViewException('The disk-image source is closed.');
    }
    if (cancelled) throw const ArchiveDiskImageCancelledException();
    if (source.length != length) {
      throw const ArchiveViewException('The disk-image source length changed.');
    }
  }

  Future<void> validate() async {
    try {
      check();
      await validateUnchanged?.call();
      check();
    } catch (error, stack) {
      _readFailure ??= (error, stack);
      rethrow;
    }
  }

  @override
  Future<Uint8List> read(int offset, int count) async {
    try {
      if (offset < 0 ||
          count < 0 ||
          count > _readBytes ||
          offset > length ||
          count > length - offset) {
        throw const ArchiveViewException(
          'A disk-image read leaves its bounded source.',
        );
      }
      if (listing && count > metadataRemaining) {
        throw const ArchiveViewException(
          'The disk-wide metadata read limit was exceeded.',
          code: ArchiveMessageCode.archiveLimit,
        );
      }
      // Reserve before the first await so concurrent child reads cannot each
      // observe the same remaining allowance. Failed attempts retain the debit.
      if (listing) metadataBytes += count;
      await Future<void>.delayed(Duration.zero);
      await validate();
      final bytes = await source.read(offset, count);
      await validate();
      if (bytes.length != count) {
        throw const ArchiveViewException(
          'The disk-image source returned an incomplete read.',
        );
      }
      return Uint8List.fromList(bytes);
    } catch (error, stack) {
      _readFailure ??= (error, stack);
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await source.close();
  }
}
