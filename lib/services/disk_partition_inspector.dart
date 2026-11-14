// Copyright 2026 CrispCloud contributors
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
//
// Original read-only implementation from the UEFI 2.11 specification, chapter 5:
// https://uefi.org/specs/UEFI/2.11/05_GUID_Partition_Table_Format.html
// No partition-editor, recovery-tool, or filesystem implementation is included.

import 'dart:async';
import 'dart:typed_data';

import 'binary_structure_service.dart' show BinaryStructureField;

const int diskPartitionMaxEntries = 4096;
const int diskPartitionMaxTableBytes = 1024 * 1024;
const int diskPartitionReadChunkBytes = 64 * 1024;
const int diskPartitionReadLimit = 2 * diskPartitionMaxTableBytes + 16 * 1024;
const int diskPartitionMaxFindings = 256;
const int _maxExactOffset = 9007199254740991;

enum DiskPartitionScheme { none, mbr, gpt }

enum DiskGptHeaderRole { primary, backup }

enum DiskPartitionCheckStatus { unchecked, valid, invalid }

enum DiskPartitionFindingSeverity { information, warning, error }

enum DiskPartitionFindingCode {
  noPartitionTable,
  truncated,
  sectorSizeAssumed,
  sectorSizeAmbiguous,
  partialSector,
  protectiveMbrMissing,
  protectiveMbrMismatch,
  hybridMbr,
  extendedPartitionsNotInspected,
  missingGptHeader,
  unsupportedRevision,
  invalidHeader,
  headerCrcMismatch,
  tableCrcMismatch,
  tableNotInspected,
  metadataLimit,
  outOfRange,
  overlap,
  headerMismatch,
  arrayMismatch,
  duplicateGuid,
  invalidPartition,
  staleBackup,
  findingsTruncated,
}

class DiskPartitionInspectionCancelled implements Exception {
  const DiskPartitionInspectionCancelled();

  @override
  String toString() => 'Partition inspection cancelled.';
}

class DiskPartitionFinding {
  const DiskPartitionFinding({
    required this.code,
    required this.severity,
    required this.message,
    this.field,
  });

  final DiskPartitionFindingCode code;
  final DiskPartitionFindingSeverity severity;
  final String message;
  final BinaryStructureField? field;
}

class DiskPartitionEntry {
  const DiskPartitionEntry({
    required this.table,
    required this.index,
    required this.name,
    required this.type,
    required this.firstLba,
    required this.lastLba,
    required this.field,
  });

  final String table;
  final int index;
  final String name;
  final String type;
  final BigInt firstLba;
  final BigInt lastLba;
  final BinaryStructureField field;
}

class DiskGptHeaderInspection {
  const DiskGptHeaderInspection({
    required this.role,
    required this.offset,
    required this.present,
    required this.headerCrcStatus,
    required this.tableCrcStatus,
    this.diskGuid,
    this.partitions = const [],
  });

  final DiskGptHeaderRole role;
  final int offset;
  final bool present;
  final DiskPartitionCheckStatus headerCrcStatus;
  final DiskPartitionCheckStatus tableCrcStatus;
  final String? diskGuid;
  final List<DiskPartitionEntry> partitions;
}

class DiskPartitionAnalysis {
  const DiskPartitionAnalysis({
    required this.scheme,
    required this.totalBytes,
    required this.sectorBytes,
    required this.inspectedBytes,
    required this.fields,
    required this.findings,
    required this.headers,
    required this.partitions,
  });

  final DiskPartitionScheme scheme;
  final int totalBytes;

  /// Null when automatic GPT probing identifies both supported sector sizes.
  final int? sectorBytes;
  final int inspectedBytes;
  final List<BinaryStructureField> fields;
  final List<DiskPartitionFinding> findings;
  final List<DiskGptHeaderInspection> headers;

  /// Records from each inspected table, including both GPT mirrors. These are
  /// evidence records, not a deduplicated or authoritative list of volumes.
  final List<DiskPartitionEntry> partitions;
}

/// Inspect MBR/GPT metadata through an existing positional byte reader.
///
/// Automatic probing checks primary and physical-tail GPT headers at 512 and
/// 4096 logical bytes per sector. Conflicting signatures require an explicit
/// [logicalSectorBytes]. MBR alone does not encode sector size; automatic MBR
/// inspection assumes 512 and reports that assumption. Only the four primary
/// MBR records are inspected; extended chains are disclosed but not followed.
///
/// Reads are bounded to 64 KiB each, 1 MiB/4096 entries per GPT table, and
/// [diskPartitionReadLimit] in total. Fields refer to metadata actually read,
/// including backup metadata at large offsets. Apart from fixed eight-byte
/// GPT signature probes, no partition payload is read or scanned.
/// Unsigned 64-bit LBAs remain BigInt until their byte ranges have been checked
/// against the source. Source offsets must fit JavaScript's exact integer range.
///
/// Snapshot validation brackets the entire operation. The event loop is yielded
/// before each positional read and periodically during table parsing, so native
/// synchronous readers remain cancellable. The caller retains source ownership.
Future<DiskPartitionAnalysis> inspectDiskPartitions({
  required int totalBytes,
  required FutureOr<Uint8List> Function(int offset, int length) read,
  int? logicalSectorBytes,
  FutureOr<void> Function()? validateUnchanged,
  bool Function()? isCancelled,
}) async {
  if (totalBytes < 0 || totalBytes > _maxExactOffset) {
    throw ArgumentError.value(totalBytes, 'totalBytes');
  }
  if (logicalSectorBytes != null &&
      logicalSectorBytes != 512 &&
      logicalSectorBytes != 4096) {
    throw ArgumentError.value(logicalSectorBytes, 'logicalSectorBytes');
  }
  final inspector = _PartitionInspector(
    totalBytes,
    read,
    logicalSectorBytes,
    isCancelled,
  );
  inspector.checkCancelled();
  await validateUnchanged?.call();
  inspector.checkCancelled();
  final result = await inspector.inspect();
  inspector.checkCancelled();
  await validateUnchanged?.call();
  inspector.checkCancelled();
  return result;
}

class _PartitionInspector {
  _PartitionInspector(this.total, this.reader, this.override, this.isCancelled);

  final int total;
  final FutureOr<Uint8List> Function(int, int) reader;
  final int? override;
  final bool Function()? isCancelled;
  final fields = <BinaryStructureField>[];
  final findings = <DiskPartitionFinding>[];
  final partitions = <DiskPartitionEntry>[];
  final headers = <DiskGptHeaderInspection>[];
  final cache = <(int, int), Uint8List>{};
  var readBytes = 0;
  var suppressedFindings = 0;
  var scheme = DiskPartitionScheme.none;
  int? sector;

  void checkCancelled() {
    if (isCancelled?.call() ?? false) {
      throw const DiskPartitionInspectionCancelled();
    }
  }

  Future<void> yieldAndCheck() async {
    checkCancelled();
    await Future<void>.delayed(Duration.zero);
    checkCancelled();
  }

  Future<Uint8List> read(
    int offset,
    int length, {
    bool remember = false,
  }) async {
    if (offset < 0 ||
        length < 0 ||
        length > total - offset ||
        length > diskPartitionReadChunkBytes) {
      throw StateError('Invalid internal partition read range.');
    }
    final cached = cache[(offset, length)];
    if (cached != null) return cached;
    if (length > diskPartitionReadLimit - readBytes) {
      throw StateError('Partition metadata read budget exhausted.');
    }
    await yieldAndCheck();
    final result = await reader(offset, length);
    checkCancelled();
    if (result.length != length) {
      throw StateError('Partition metadata could not be read completely.');
    }
    readBytes += length;
    if (remember) {
      final copy = Uint8List.fromList(result);
      cache[(offset, length)] = copy;
      return copy;
    }
    return result;
  }

  void finding(
    DiskPartitionFindingCode code,
    String message, {
    DiskPartitionFindingSeverity severity = DiskPartitionFindingSeverity.error,
    BinaryStructureField? field,
  }) {
    if (findings.length >= diskPartitionMaxFindings - 1) {
      suppressedFindings++;
      return;
    }
    findings.add(
      DiskPartitionFinding(
        code: code,
        severity: severity,
        message: message,
        field: field,
      ),
    );
  }

  DiskPartitionAnalysis finish() {
    if (suppressedFindings != 0) {
      findings.add(
        DiskPartitionFinding(
          code: DiskPartitionFindingCode.findingsTruncated,
          severity: DiskPartitionFindingSeverity.warning,
          message: '$suppressedFindings additional findings were omitted.',
        ),
      );
    }
    return DiskPartitionAnalysis(
      scheme: scheme,
      totalBytes: total,
      sectorBytes: sector,
      inspectedBytes: readBytes,
      fields: List.unmodifiable(fields),
      findings: List.unmodifiable(findings),
      headers: List.unmodifiable(headers),
      partitions: List.unmodifiable(partitions),
    );
  }

  Future<DiskPartitionAnalysis> inspect() async {
    final prefix = await read(0, total < 512 ? total : 512, remember: true);
    if (prefix.length < 512) {
      finding(
        DiskPartitionFindingCode.truncated,
        'The source is shorter than a complete MBR sector.',
        severity: DiskPartitionFindingSeverity.warning,
      );
      return finish();
    }
    final mbrSignature = prefix[510] == 0x55 && prefix[511] == 0xaa;
    final probes = <int, (_HeaderProbe, _HeaderProbe)>{};
    for (final size in override == null ? const [512, 4096] : [override!]) {
      final primary = await probe(size, size);
      final lastOffset = (total ~/ size - 1) * size;
      final backup = await probe(lastOffset, size);
      probes[size] = (primary, backup);
    }
    final candidates = probes.entries
        .where((entry) => entry.value.$1.signature || entry.value.$2.signature)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (override == null && candidates.length > 1) {
      scheme = DiskPartitionScheme.gpt;
      finding(
        DiskPartitionFindingCode.sectorSizeAmbiguous,
        'GPT signatures exist for both 512-byte and 4096-byte sectors. '
        'Choose a logical sector size to inspect either interpretation.',
        severity: DiskPartitionFindingSeverity.warning,
      );
      for (final entry in probes.entries) {
        for (final probe in [entry.value.$1, entry.value.$2]) {
          if (probe.signature) {
            fields.add(
              _field(
                'GPT signature (${entry.key}-byte sectors)',
                'bytes',
                probe.offset,
                8,
                'EFI PART',
              ),
            );
          }
        }
      }
      return finish();
    }
    sector = override ?? (candidates.isEmpty ? 512 : candidates.single);
    if (total % sector! != 0) {
      finding(
        DiskPartitionFindingCode.partialSector,
        'The source length is not a multiple of $sector bytes; the final '
        'partial sector cannot contain a complete backup header.',
        severity: DiskPartitionFindingSeverity.warning,
      );
    }
    final mbr = mbrSignature ? inspectMbr(prefix) : <DiskPartitionEntry>[];
    final protective = mbr
        .where((entry) => entry.type.startsWith('0xEE'))
        .toList();
    if (protective.length > 1) {
      finding(
        DiskPartitionFindingCode.protectiveMbrMismatch,
        'A protective MBR must contain exactly one protective record.',
      );
    }
    final legacy = mbr
        .where((entry) => !entry.type.startsWith('0xEE'))
        .toList();
    if (protective.isNotEmpty) {
      await inspectProtectiveMbr(prefix, protective);
    }
    final selected = probes[sector]!;
    final hasGpt = selected.$1.signature || selected.$2.signature;
    if (hasGpt || protective.isNotEmpty) {
      scheme = DiskPartitionScheme.gpt;
      if (!mbrSignature || protective.isEmpty) {
        finding(
          DiskPartitionFindingCode.protectiveMbrMissing,
          'A GPT signature was found without a protective MBR.',
        );
      }
      if (legacy.isNotEmpty && protective.isNotEmpty) {
        finding(
          DiskPartitionFindingCode.hybridMbr,
          'The MBR contains protective and legacy partition records. '
          'Their overlapping interpretations require care.',
          severity: DiskPartitionFindingSeverity.warning,
        );
      }
      if (!selected.$1.signature &&
          selected.$2.signature &&
          legacy.isNotEmpty) {
        finding(
          DiskPartitionFindingCode.staleBackup,
          'A backup GPT coexists with legacy MBR partitions and no primary '
          'GPT. The backup may be stale; no table is selected as authoritative.',
          severity: DiskPartitionFindingSeverity.warning,
        );
      }
      // Check both fixed headers before following either array pointer. A
      // damaged mirror must not redirect metadata reads into the other
      // physically plausible header's declared partition area.
      await preloadHeader(selected.$1);
      await preloadHeader(selected.$2);
      final primary = await inspectGpt(
        selected.$1,
        DiskGptHeaderRole.primary,
        selected.$2,
      );
      final backup = await inspectGpt(
        selected.$2,
        DiskGptHeaderRole.backup,
        selected.$1,
      );
      headers.addAll([primary.summary, backup.summary]);
      compareHeaders(primary, backup);
    } else if (mbr.isNotEmpty) {
      scheme = DiskPartitionScheme.mbr;
      if (override == null) {
        finding(
          DiskPartitionFindingCode.sectorSizeAssumed,
          'MBR records do not specify logical sector size. Bounds use '
          '512-byte sectors; select 4096 if that is the source geometry.',
          severity: DiskPartitionFindingSeverity.information,
        );
      }
    } else {
      finding(
        DiskPartitionFindingCode.noPartitionTable,
        'No supported partition table was identified. A boot-sector '
        'signature alone does not establish an MBR partition table.',
        severity: DiskPartitionFindingSeverity.information,
      );
    }
    return finish();
  }

  Future<_HeaderProbe> probe(int offset, int size) async {
    if (offset < size || offset > total - size) {
      return _HeaderProbe(offset < 0 ? 0 : offset, null);
    }
    return _HeaderProbe(offset, await read(offset, 8, remember: true));
  }

  Future<void> preloadHeader(_HeaderProbe probe) async {
    if (!probe.signature) return;
    final bytes = await read(probe.offset, sector!, remember: true);
    if (!_HeaderProbe(probe.offset, bytes).signature) {
      throw StateError('Partition header changed after its signature probe.');
    }
  }

  (BigInt, BigInt)? peerUsableRange(_HeaderProbe probe) {
    if (!probe.signature) return null;
    final bytes = cache[(probe.offset, sector!)];
    if (bytes == null) return null;
    final size = _u32(bytes, 12);
    if (size < 92 ||
        size > sector! ||
        _u32(bytes, 8) != 0x00010000 ||
        _u64(bytes, 24) != BigInt.from(probe.offset ~/ sector!)) {
      return null;
    }
    final first = _u64(bytes, 40);
    final last = _u64(bytes, 48);
    final reserved = (16384 + sector! - 1) ~/ sector!;
    final lastDisk = BigInt.from(total ~/ sector! - 1);
    if (first < BigInt.from(2 + reserved) ||
        last > lastDisk - BigInt.from(1 + reserved) ||
        first > last) {
      return null;
    }
    return (first, last);
  }

  Future<void> inspectProtectiveMbr(
    Uint8List bytes,
    List<DiskPartitionEntry> protective,
  ) async {
    final protectedIndexes = protective.map((entry) => entry.index - 1).toSet();
    var reservedValid = bytes.sublist(440, 446).every((value) => value == 0);
    for (var index = 0; index < 4; index++) {
      final at = 446 + index * 16;
      if (protectedIndexes.contains(index)) {
        reservedValid =
            reservedValid &&
            bytes[at] == 0 &&
            bytes[at + 1] == 0 &&
            bytes[at + 2] == 2 &&
            bytes[at + 3] == 0;
      } else if (bytes.sublist(at, at + 16).any((value) => value != 0)) {
        reservedValid = false;
      }
    }
    if (!reservedValid) {
      finding(
        DiskPartitionFindingCode.protectiveMbrMismatch,
        'The protective MBR has nonzero reserved fields, an unexpected boot '
        'indicator or starting CHS, or additional nonzero partition records.',
        severity: DiskPartitionFindingSeverity.warning,
        field: fields.first,
      );
    }
    if (sector! > 512 && total >= sector!) {
      final tail = await read(512, sector! - 512, remember: true);
      final field = _field(
        'Protective MBR reserved sector bytes',
        'bytes',
        512,
        tail.length,
        '${tail.length} bytes',
      );
      fields.add(field);
      if (tail.any((value) => value != 0)) {
        finding(
          DiskPartitionFindingCode.protectiveMbrMismatch,
          'The protective MBR has nonzero bytes in its reserved sector tail.',
          severity: DiskPartitionFindingSeverity.warning,
          field: field,
        );
      }
    }
  }

  List<DiskPartitionEntry> inspectMbr(Uint8List bytes) {
    final children = <BinaryStructureField>[
      _field('Disk signature', 'u32le', 440, 4, _hex(_u32(bytes, 440))),
      _field('Boot-sector signature', 'u16le', 510, 2, '0xAA55'),
    ];
    final records = <DiskPartitionEntry>[];
    final lastDisk = BigInt.from(total ~/ sector! - 1);
    for (var index = 0; index < 4; index++) {
      final at = 446 + index * 16;
      final type = bytes[at + 4];
      final count = _u32(bytes, at + 12);
      if (type == 0 || count == 0) continue;
      final first = BigInt.from(_u32(bytes, at + 8));
      final last = first + BigInt.from(count) - BigInt.one;
      final description = switch (type) {
        0xee => '0xEE GPT protective',
        0xef => '0xEF EFI system',
        _ => '0x${type.toRadixString(16).toUpperCase().padLeft(2, '0')}',
      };
      final field = _group('MBR partition ${index + 1}', at, 16, [
        _field('Boot indicator', 'u8', at, 1, _hex(bytes[at])),
        _field('Starting CHS', 'bytes', at + 1, 3, _bytesHex(bytes, at + 1, 3)),
        _field('Partition type', 'u8', at + 4, 1, description),
        _field('Ending CHS', 'bytes', at + 5, 3, _bytesHex(bytes, at + 5, 3)),
        _field('Starting LBA', 'u32le', at + 8, 4, '$first'),
        _field('Sector count', 'u32le', at + 12, 4, '$count'),
      ]);
      final record = DiskPartitionEntry(
        table: 'MBR',
        index: index + 1,
        name: 'Partition ${index + 1}',
        type: description,
        firstLba: first,
        lastLba: last,
        field: field,
      );
      records.add(record);
      children.add(field);
      if (first < BigInt.one || last > lastDisk) {
        finding(
          DiskPartitionFindingCode.outOfRange,
          'MBR partition ${index + 1} lies outside the available disk sectors.',
          field: field,
        );
      }
      if (type == 0xee) {
        final diskSize = total ~/ sector! - 1;
        final expected = diskSize < 0xffffffff ? diskSize : 0xffffffff;
        if (first != BigInt.one || count != expected) {
          finding(
            DiskPartitionFindingCode.protectiveMbrMismatch,
            'The protective MBR does not cover the expected disk extent.',
            field: field,
          );
        }
      }
      if (type == 0x05 || type == 0x0f || type == 0x85) {
        finding(
          DiskPartitionFindingCode.extendedPartitionsNotInspected,
          'MBR partition ${index + 1} is an extended partition container. '
          'Its EBR chain and logical partitions were not inspected.',
          severity: DiskPartitionFindingSeverity.warning,
          field: field,
        );
      }
    }
    fields.add(_group('Master boot record', 0, 512, children));
    checkOverlaps(records.where((p) => !p.type.startsWith('0xEE')).toList());
    partitions.addAll(records);
    return records;
  }

  Future<_ParsedGpt> inspectGpt(
    _HeaderProbe probe,
    DiskGptHeaderRole role,
    _HeaderProbe peer,
  ) async {
    final label = role == DiskGptHeaderRole.primary
        ? 'Primary GPT'
        : 'Backup GPT';
    final result = _ParsedGpt(role, probe.offset);
    if (!probe.signature) {
      finding(
        DiskPartitionFindingCode.missingGptHeader,
        '$label header is missing at its expected physical location.',
      );
      return result;
    }
    final bytes = await read(probe.offset, sector!, remember: true);
    result.present = true;
    final size = _u32(bytes, 12);
    final revision = _u32(bytes, 8);
    final expectedCrc = _u32(bytes, 16);
    result.myLba = _u64(bytes, 24);
    result.alternateLba = _u64(bytes, 32);
    result.firstUsable = _u64(bytes, 40);
    result.lastUsable = _u64(bytes, 48);
    result.diskGuid = _guid(bytes, 56);
    result.tableLba = _u64(bytes, 72);
    result.entryCount = _u32(bytes, 80);
    result.entrySize = _u32(bytes, 84);
    final expectedTableCrc = _u32(bytes, 88);
    final headerFields = <BinaryStructureField>[
      _field('Signature', 'bytes', probe.offset, 8, 'EFI PART'),
      _field('Revision', 'u32le', probe.offset + 8, 4, _hex(revision)),
      _field('Header size', 'u32le', probe.offset + 12, 4, '$size'),
      _field('Header CRC32', 'u32le', probe.offset + 16, 4, _hex(expectedCrc)),
      _field('Reserved', 'u32le', probe.offset + 20, 4, _hex(_u32(bytes, 20))),
      _field('Current LBA', 'u64le', probe.offset + 24, 8, '${result.myLba}'),
      _field(
        'Alternate LBA',
        'u64le',
        probe.offset + 32,
        8,
        '${result.alternateLba}',
      ),
      _field(
        'First usable LBA',
        'u64le',
        probe.offset + 40,
        8,
        '${result.firstUsable}',
      ),
      _field(
        'Last usable LBA',
        'u64le',
        probe.offset + 48,
        8,
        '${result.lastUsable}',
      ),
      _field('Disk GUID', 'guid', probe.offset + 56, 16, result.diskGuid!),
      _field(
        'Partition array LBA',
        'u64le',
        probe.offset + 72,
        8,
        '${result.tableLba}',
      ),
      _field(
        'Partition entry count',
        'u32le',
        probe.offset + 80,
        4,
        '${result.entryCount}',
      ),
      _field(
        'Partition entry size',
        'u32le',
        probe.offset + 84,
        4,
        '${result.entrySize}',
      ),
      _field(
        'Partition array CRC32',
        'u32le',
        probe.offset + 88,
        4,
        _hex(expectedTableCrc),
      ),
      _field(
        'Reserved header bytes',
        'bytes',
        probe.offset + 92,
        bytes.length - 92,
        '${bytes.length - 92} bytes',
      ),
    ];
    final headerField = _group(
      '$label header',
      probe.offset,
      bytes.length,
      headerFields,
    );
    fields.add(headerField);
    if (size < 92 || size > sector!) {
      finding(
        DiskPartitionFindingCode.invalidHeader,
        '$label header size must be between 92 and $sector bytes.',
        field: headerFields[2],
      );
    } else {
      final copy = Uint8List.fromList(bytes.sublist(0, size));
      copy.fillRange(16, 20, 0);
      result.headerCrc = _crc32(copy) == expectedCrc
          ? DiskPartitionCheckStatus.valid
          : DiskPartitionCheckStatus.invalid;
      if (result.headerCrc == DiskPartitionCheckStatus.invalid) {
        finding(
          DiskPartitionFindingCode.headerCrcMismatch,
          '$label header CRC32 does not match.',
          field: headerFields[3],
        );
      }
    }
    if (revision != 0x00010000) {
      finding(
        DiskPartitionFindingCode.unsupportedRevision,
        '$label has unsupported revision ${_hex(revision)}. '
        'Its partition array was not interpreted.',
        field: headerFields[1],
      );
      return result;
    }
    if (bytes.sublist(92).any((value) => value != 0)) {
      finding(
        DiskPartitionFindingCode.invalidHeader,
        '$label has nonzero reserved header bytes.',
        field: headerFields.last,
      );
    }
    final lastDisk = BigInt.from(total ~/ sector! - 1);
    final thisLba = BigInt.from(probe.offset ~/ sector!);
    final alternate = role == DiskGptHeaderRole.primary ? lastDisk : BigInt.one;
    if (result.myLba != thisLba ||
        result.alternateLba != alternate ||
        _u32(bytes, 20) != 0 ||
        result.diskGuid == _zeroGuid) {
      finding(
        DiskPartitionFindingCode.invalidHeader,
        '$label has inconsistent location, reserved fields, or disk GUID.',
        field: headerField,
      );
    }
    final reservedSectors = (16384 + sector! - 1) ~/ sector!;
    final usableRangeValid =
        result.firstUsable! >= BigInt.from(2 + reservedSectors) &&
        result.lastUsable! <= lastDisk - BigInt.from(1 + reservedSectors) &&
        result.firstUsable! <= result.lastUsable!;
    if (!usableRangeValid) {
      finding(
        DiskPartitionFindingCode.outOfRange,
        '$label usable sector range leaves insufficient room for GPT metadata '
        'or lies outside the disk.',
        field: headerField,
      );
    }
    final count = result.entryCount!;
    final entrySize = result.entrySize!;
    if (count == 0 || entrySize < 128 || (entrySize & (entrySize - 1)) != 0) {
      finding(
        DiskPartitionFindingCode.invalidHeader,
        '$label partition count or entry size is invalid. Entry size must '
        'be 128 times a power of two.',
        field: headerFields[12],
      );
      return result;
    }
    if (count > diskPartitionMaxEntries ||
        entrySize > diskPartitionMaxTableBytes ||
        count > diskPartitionMaxTableBytes ~/ entrySize) {
      finding(
        DiskPartitionFindingCode.metadataLimit,
        '$label array exceeds the $diskPartitionMaxEntries-entry or '
        '$diskPartitionMaxTableBytes-byte inspection limit.',
        field: headerFields[11],
      );
      return result;
    }
    final tableBytes = count * entrySize;
    final offsetBig = result.tableLba! * BigInt.from(sector!);
    final endBig = offsetBig + BigInt.from(tableBytes);
    if (offsetBig < BigInt.zero || endBig > BigInt.from(total)) {
      finding(
        DiskPartitionFindingCode.outOfRange,
        '$label partition array lies outside the available source.',
        field: headerFields[10],
      );
      return result;
    }
    final tableEndLba =
        result.tableLba! + BigInt.from((tableBytes + sector! - 1) ~/ sector!);
    final peerRange = peerUsableRange(peer);
    if (peerRange != null &&
        result.tableLba! <= peerRange.$2 &&
        tableEndLba > peerRange.$1) {
      finding(
        DiskPartitionFindingCode.overlap,
        '$label array overlaps the other GPT header\'s declared usable sector range.',
        field: headerFields[10],
      );
      finding(
        DiskPartitionFindingCode.tableNotInspected,
        '$label array was not followed because the GPT mirrors disagree '
        'about metadata and partition boundaries.',
        field: headerFields[10],
      );
      return result;
    }
    final placementValid = role == DiskGptHeaderRole.primary
        ? result.tableLba! > thisLba && tableEndLba <= result.firstUsable!
        : result.tableLba! > result.lastUsable! && tableEndLba <= thisLba;
    if (!placementValid) {
      finding(
        DiskPartitionFindingCode.overlap,
        '$label array overlaps a header or the declared usable sector range.',
        field: headerFields[10],
      );
    }
    if (!placementValid || !usableRangeValid) {
      finding(
        DiskPartitionFindingCode.tableNotInspected,
        '$label array was not followed because its metadata placement is unsafe.',
        field: headerFields[10],
      );
      return result;
    }
    if (size < 92 || size > sector!) {
      finding(
        DiskPartitionFindingCode.tableNotInspected,
        '$label array was not followed because its header size is invalid.',
        field: headerField,
      );
      return result;
    }
    final tableOffset = offsetBig.toInt();
    final table = Uint8List(tableBytes);
    for (var copied = 0; copied < tableBytes;) {
      final remaining = tableBytes - copied;
      final length = remaining < diskPartitionReadChunkBytes
          ? remaining
          : diskPartitionReadChunkBytes;
      final chunk = await read(tableOffset + copied, length);
      table.setRange(copied, copied + length, chunk);
      copied += length;
    }
    result.tableBytes = table;
    result.tableCrc = _crc32(table) == expectedTableCrc
        ? DiskPartitionCheckStatus.valid
        : DiskPartitionCheckStatus.invalid;
    if (result.tableCrc == DiskPartitionCheckStatus.invalid) {
      finding(
        DiskPartitionFindingCode.tableCrcMismatch,
        '$label partition array CRC32 does not match.',
        field: headerFields[13],
      );
    }
    final entryFields = <BinaryStructureField>[];
    final guids = <String>{};
    for (var index = 0; index < count; index++) {
      if (index % 128 == 0) await yieldAndCheck();
      final at = index * entrySize;
      final type = _guid(table, at);
      if (type == _zeroGuid) continue;
      final guid = _guid(table, at + 16);
      final first = _u64(table, at + 32);
      final last = _u64(table, at + 40);
      final attributes = _u64(table, at + 48);
      final name = _name(table, at + 56);
      final position = tableOffset + at;
      final field = _group(
        '$label partition ${index + 1}',
        position,
        entrySize,
        [
          _field('Partition type GUID', 'guid', position, 16, type),
          _field('Unique partition GUID', 'guid', position + 16, 16, guid),
          _field('Starting LBA', 'u64le', position + 32, 8, '$first'),
          _field('Ending LBA', 'u64le', position + 40, 8, '$last'),
          _field(
            'Attributes',
            'u64le',
            position + 48,
            8,
            '0x${attributes.toRadixString(16).toUpperCase()}',
          ),
          _field('Partition name', 'utf16le', position + 56, 72, name),
          if (entrySize > 128)
            _field(
              'Reserved entry bytes',
              'bytes',
              position + 128,
              entrySize - 128,
              '${entrySize - 128} bytes',
            ),
        ],
      );
      final partition = DiskPartitionEntry(
        table: label,
        index: index + 1,
        name: name,
        type: type,
        firstLba: first,
        lastLba: last,
        field: field,
      );
      result.partitions.add(partition);
      entryFields.add(field);
      if (first > last ||
          first < result.firstUsable! ||
          last > result.lastUsable! ||
          first <= BigInt.one ||
          last >= lastDisk) {
        finding(
          DiskPartitionFindingCode.outOfRange,
          '$label partition ${index + 1} lies outside its usable disk range.',
          field: field,
        );
      }
      if (guid == _zeroGuid || !guids.add(guid)) {
        finding(
          DiskPartitionFindingCode.duplicateGuid,
          '$label partition ${index + 1} has a zero or duplicate unique GUID.',
          field: field,
        );
      }
      if ((attributes & ((BigInt.one << 48) - BigInt.from(8))) != BigInt.zero ||
          table.sublist(at + 128, at + entrySize).any((byte) => byte != 0)) {
        finding(
          DiskPartitionFindingCode.invalidPartition,
          '$label partition ${index + 1} has nonzero reserved attributes or bytes.',
          field: field,
        );
      }
    }
    fields.add(
      _group('$label partition array', tableOffset, tableBytes, entryFields),
    );
    checkOverlaps(result.partitions);
    partitions.addAll(result.partitions);
    return result;
  }

  void checkOverlaps(List<DiskPartitionEntry> entries) {
    final sorted = entries.where((p) => p.firstLba <= p.lastLba).toList()
      ..sort((a, b) => a.firstLba.compareTo(b.firstLba));
    DiskPartitionEntry? farthest;
    for (final entry in sorted) {
      if (farthest != null && entry.firstLba <= farthest.lastLba) {
        finding(
          DiskPartitionFindingCode.overlap,
          '${entry.table} partitions ${farthest.index} and ${entry.index} overlap.',
          field: entry.field,
        );
      }
      if (farthest == null || entry.lastLba > farthest.lastLba) {
        farthest = entry;
      }
    }
  }

  void compareHeaders(_ParsedGpt a, _ParsedGpt b) {
    if (!a.present || !b.present) return;
    if (a.myLba != b.alternateLba ||
        a.alternateLba != b.myLba ||
        a.diskGuid != b.diskGuid ||
        a.firstUsable != b.firstUsable ||
        a.lastUsable != b.lastUsable ||
        a.entryCount != b.entryCount ||
        a.entrySize != b.entrySize) {
      finding(
        DiskPartitionFindingCode.headerMismatch,
        'Primary and backup GPT headers disagree about the disk or partition array.',
      );
    }
    final first = a.tableBytes;
    final second = b.tableBytes;
    if (first == null || second == null) return;
    var equal = first.length == second.length;
    for (var i = 0; equal && i < first.length; i++) {
      equal = first[i] == second[i];
    }
    if (!equal) {
      finding(
        DiskPartitionFindingCode.arrayMismatch,
        'Primary and backup GPT partition arrays differ. No mirror is selected '
        'as authoritative, even when their individual CRC32 checks pass.',
      );
    }
  }
}

class _HeaderProbe {
  const _HeaderProbe(this.offset, this.bytes);
  final int offset;
  final Uint8List? bytes;
  bool get signature {
    final data = bytes;
    if (data == null) return false;
    const signature = [0x45, 0x46, 0x49, 0x20, 0x50, 0x41, 0x52, 0x54];
    for (var i = 0; i < signature.length; i++) {
      if (data[i] != signature[i]) return false;
    }
    return true;
  }
}

class _ParsedGpt {
  _ParsedGpt(this.role, this.offset);
  final DiskGptHeaderRole role;
  final int offset;
  bool present = false;
  DiskPartitionCheckStatus headerCrc = DiskPartitionCheckStatus.unchecked;
  DiskPartitionCheckStatus tableCrc = DiskPartitionCheckStatus.unchecked;
  BigInt? myLba, alternateLba, firstUsable, lastUsable, tableLba;
  String? diskGuid;
  int? entryCount, entrySize;
  Uint8List? tableBytes;
  final partitions = <DiskPartitionEntry>[];

  DiskGptHeaderInspection get summary => DiskGptHeaderInspection(
    role: role,
    offset: offset,
    present: present,
    headerCrcStatus: headerCrc,
    tableCrcStatus: tableCrc,
    diskGuid: diskGuid,
    partitions: List.unmodifiable(partitions),
  );
}

BinaryStructureField _field(
  String name,
  String type,
  int start,
  int length,
  String value,
) => BinaryStructureField(
  name: name,
  type: type,
  start: start,
  end: start + length,
  value: value,
);

BinaryStructureField _group(
  String name,
  int start,
  int length,
  List<BinaryStructureField> children,
) => BinaryStructureField(
  name: name,
  type: 'structure',
  start: start,
  end: start + length,
  children: List.unmodifiable(children),
);

int _u16(Uint8List bytes, int at) => bytes[at] + bytes[at + 1] * 256;
int _u32(Uint8List bytes, int at) =>
    _u16(bytes, at) + _u16(bytes, at + 2) * 65536;
BigInt _u64(Uint8List bytes, int at) =>
    BigInt.from(_u32(bytes, at)) + (BigInt.from(_u32(bytes, at + 4)) << 32);
String _hex(int value) =>
    '0x${value.toRadixString(16).toUpperCase().padLeft(8, '0')}';
String _bytesHex(Uint8List bytes, int at, int count) => List.generate(
  count,
  (i) => bytes[at + i].toRadixString(16).toUpperCase().padLeft(2, '0'),
).join(' ');
const _zeroGuid = '00000000-0000-0000-0000-000000000000';
String _guid(Uint8List bytes, int at) {
  String part(int value, int digits) =>
      value.toRadixString(16).toUpperCase().padLeft(digits, '0');
  return '${part(_u32(bytes, at), 8)}-${part(_u16(bytes, at + 4), 4)}-'
      '${part(_u16(bytes, at + 6), 4)}-${part(bytes[at + 8], 2)}${part(bytes[at + 9], 2)}-'
      '${List.generate(6, (i) => part(bytes[at + 10 + i], 2)).join()}';
}

String _name(Uint8List bytes, int at) {
  final units = <int>[];
  for (var i = 0; i < 36; i++) {
    final unit = _u16(bytes, at + i * 2);
    if (unit == 0) break;
    units.add(unit);
  }
  return String.fromCharCodes(units);
}

// IEEE CRC32, expressed with unsigned shifts for Dart VM/compiled-JS parity.
final _crcTable = Uint32List.fromList(
  List<int>.generate(256, (index) {
    var crc = index;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320);
    }
    return crc;
  }, growable: false),
);
int _crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff).toUnsigned(32);
}
