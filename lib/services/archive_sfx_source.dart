import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';

/// Maximum physical position of an accepted executable overlay. The prefix is
/// inspected positionally, never collected into one buffer.
const int kArchiveSfxStubLimit = 32 * 1024 * 1024;

/// Aggregate bytes inspected while establishing the PE and archive boundaries.
const int kArchiveSfxMetadataLimit = 16 * 1024 * 1024;

/// Opens a read-only archive appended at a validated unsigned PE overlay.
///
/// The supported profile is PE32 x86 or PE32+ x64/ARM64, ordinary aligned
/// sections, and a ZIP, 7z or RAR payload immediately after the last raw section.
/// Certificates, COFF tables, external debug data, installer configuration
/// overlays and arbitrary padding before the payload are refused. Nothing is
/// executed, mounted, installed, or authenticated.
///
/// This method owns [source] on success and failure. The returned adapter must
/// then be passed to the normal bounded archive reader, which validates its
/// complete index and verifies supported member checksums on extraction. An
/// archive reader's failure must close the adapter. Keep the container format
/// distinct (for example `sfx/zip`): rewriting it as an ordinary archive would
/// discard the executable prefix and potentially invalidate signatures.
///
/// PE layout follows Microsoft's PE/COFF specification:
/// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
Future<ArchiveSfxSource> openPeSfxSource(
  koni.ByteSource source, {
  int maxStubBytes = kArchiveSfxStubLimit,
  int maxMetadataBytes = kArchiveSfxMetadataLimit,
}) async {
  try {
    if (maxStubBytes < 512 || maxStubBytes > kArchiveSfxStubLimit) {
      throw ArgumentError.value(maxStubBytes, 'maxStubBytes');
    }
    if (maxMetadataBytes < 512 || maxMetadataBytes > kArchiveSfxMetadataLimit) {
      throw ArgumentError.value(maxMetadataBytes, 'maxMetadataBytes');
    }
    final inspection = _SfxInspection(
      source,
      maxStubBytes: maxStubBytes,
      maxMetadataBytes: maxMetadataBytes,
    );
    final payloadOffset = await inspection.readPe();
    final available = source.length - payloadOffset;
    if (available < 4) throw _corrupt('The executable has no archive overlay.');
    final header = await inspection.read(
      payloadOffset,
      math.min(available, 32),
    );
    final String kind;
    final bool keepZipCoordinates;
    if (_magic(header, const [0x50, 0x4b, 0x03, 0x04]) ||
        _magic(header, const [0x50, 0x4b, 0x05, 0x06]) ||
        _magic(header, const [0x50, 0x4b, 0x06, 0x06])) {
      await inspection.readZip(payloadOffset);
      kind = 'zip';
      // The pinned ZIP reader handles both absolute SFX offsets and offsets
      // relative to the appended ZIP. Keeping physical coordinates avoids
      // mutating central/local records. readZip has checked that every member
      // header and data extent lies after the executable, including ZIP64.
      keepZipCoordinates = true;
    } else if (_magic(header, const [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c])) {
      await inspection.readSevenZip(payloadOffset, header);
      kind = '7z';
      keepZipCoordinates = false;
    } else if (_magic(header, const [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07])) {
      await inspection.readRar(payloadOffset, header);
      kind = 'rar';
      keepZipCoordinates = false;
    } else {
      throw _unsupported(
        'The executable overlay is not a supported ZIP, 7z or RAR archive. '
        'Installer configuration blocks and arbitrary overlay prefixes are '
        'not supported.',
      );
    }
    return ArchiveSfxSource._(
      source,
      archiveKind: kind,
      payloadOffset: payloadOffset,
      sourceOffset: keepZipCoordinates ? 0 : payloadOffset,
    );
  } catch (error, stack) {
    try {
      await source.close();
    } catch (_) {
      // Preserve the inspection error if releasing a failed source also fails.
    }
    Error.throwWithStackTrace(error, stack);
  }
}

/// An owning positional view over an inspected executable archive.
///
/// ZIP retains physical file coordinates because both absolute and relative
/// central-directory offsets occur in real SFX files. 7z/RAR expose the strict
/// payload slice. Consumers should use [archiveKind] and the ordinary reader;
/// this adapter is not a command to export or rewrite the physical executable.
class ArchiveSfxSource implements koni.ByteSource {
  ArchiveSfxSource._(
    this._source, {
    required this.archiveKind,
    required this.payloadOffset,
    required int sourceOffset,
  }) : _sourceOffset = sourceOffset,
       _physicalLength = _source.length,
       length = _source.length - sourceOffset;

  final koni.ByteSource _source;
  final int _sourceOffset;
  final int _physicalLength;
  final String archiveKind;
  final int payloadOffset;

  @override
  final int length;

  @override
  String get name => 'executable-payload.$archiveKind';

  /// These details do not assert that any executable or publisher is trusted.
  static const notices = <String>[
    'Read-only archive inside a Windows executable. The executable is never '
        'run and publisher signatures are not authenticated.',
    'Only an archive immediately following validated unsigned PE sections is '
        'supported. Signed executables and installer-specific overlays are '
        'unavailable.',
  ];

  bool _closed = false;
  Future<void>? _closing;
  bool get isClosed => _closed;

  @override
  Future<Uint8List> read(int offset, int count) async {
    _checkOpen();
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    if (count < 0) throw ArgumentError.value(count, 'length');
    if (offset > length || count > length - offset) {
      throw koni.UnexpectedEofException(
        'Read leaves the inspected executable archive.',
        offset: offset,
      );
    }
    if (count > kArchiveReadLimit + 64 * 1024) {
      throw _limit('A single SFX read exceeds its bounded input window.');
    }
    final bytes = await _source.read(_sourceOffset + offset, count);
    _checkOpen();
    if (bytes.length != count) {
      throw _corrupt('The executable archive source was truncated.');
    }
    return bytes;
  }

  void _checkOpen() {
    if (_closed) {
      throw koni.ArchiveClosedException('The executable archive is closed.');
    }
    if (_source.length != _physicalLength) {
      throw _corrupt('The executable archive source changed its size.');
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= Future<void>.sync(_source.close);
  }
}

class _PeSection {
  const _PeSection(this.address, this.start, this.size, this.executable);
  final int address;
  final int start;
  final int size;
  final bool executable;
  int get end => start + size;

  bool containsAddress(int address, int count) =>
      address >= this.address &&
      address - this.address <= size &&
      count <= size - (address - this.address);
}

class _SfxInspection {
  _SfxInspection(
    this.source, {
    required this.maxStubBytes,
    required this.maxMetadataBytes,
  }) : _length = source.length;

  final koni.ByteSource source;
  final int maxStubBytes;
  final int maxMetadataBytes;
  final int _length;
  int _readBytes = 0;

  Future<Uint8List> read(int offset, int count) async {
    if (_length < 0 ||
        _length > 9007199254740991 ||
        source.length != _length ||
        offset < 0 ||
        count < 0 ||
        offset > _length ||
        count > _length - offset) {
      throw _corrupt('Executable archive metadata leaves its captured source.');
    }
    if (count > maxMetadataBytes - _readBytes) {
      throw _limit('Executable archive metadata exceeds its inspection limit.');
    }
    _readBytes += count;
    final bytes = await source.read(offset, count);
    if (bytes.length != count || source.length != _length) {
      throw _corrupt('Executable archive metadata is truncated or changed.');
    }
    return bytes;
  }

  Future<int> readPe() async {
    final dos = await read(0, 64);
    if (!_magic(dos, const [0x4d, 0x5a])) {
      throw _unsupported('Only Windows PE executable archives are supported.');
    }
    final peOffset = _u32(dos, 60);
    if (peOffset < 64 || peOffset > maxStubBytes - 24) {
      throw _corrupt('Invalid or oversized PE header offset.');
    }
    final coff = await read(peOffset, 24);
    if (!_magic(coff, const [0x50, 0x45, 0, 0])) {
      throw _corrupt('The executable has no valid PE signature.');
    }
    final machine = _u16(coff, 4);
    final sectionCount = _u16(coff, 6);
    final optionalSize = _u16(coff, 20);
    final characteristics = _u16(coff, 22);
    if (sectionCount == 0 || sectionCount > 96) {
      throw _corrupt('Unsupported or invalid PE section count.');
    }
    if (characteristics & 2 == 0 || characteristics & 0x2000 != 0) {
      throw _unsupported(
        'PE object files and DLLs are not executable archives.',
      );
    }
    if (_u32(coff, 12) != 0 || _u32(coff, 16) != 0) {
      throw _unsupported('PE COFF symbol/string tables are not supported.');
    }
    final optionalOffset = peOffset + 24;
    if (optionalSize < 96 ||
        optionalSize > 4096 ||
        optionalOffset > maxStubBytes - optionalSize) {
      throw _corrupt('Invalid PE optional-header size.');
    }
    final optional = await read(optionalOffset, optionalSize);
    final magic = _u16(optional, 0);
    final int directoryStart;
    if (magic == 0x10b && machine == 0x14c) {
      directoryStart = 96;
    } else if (magic == 0x20b && (machine == 0x8664 || machine == 0xaa64)) {
      directoryStart = 112;
    } else {
      throw _unsupported(
        'This PE machine/optional-header profile is unsupported.',
      );
    }
    if (optionalSize < directoryStart) {
      throw _corrupt('The PE optional header is truncated.');
    }
    final sectionAlignment = _u32(optional, 32);
    final fileAlignment = _u32(optional, 36);
    final imageSize = _u32(optional, 56);
    final headersSize = _u32(optional, 60);
    if (!_powerOfTwo(fileAlignment) ||
        fileAlignment < 512 ||
        fileAlignment > 65536 ||
        !_powerOfTwo(sectionAlignment) ||
        sectionAlignment < 4096 ||
        sectionAlignment < fileAlignment) {
      throw _unsupported(
        'The PE section/file alignment profile is unsupported.',
      );
    }
    final sectionTable = optionalOffset + optionalSize;
    final sectionBytes = sectionCount * 40;
    if (headersSize < sectionTable + sectionBytes ||
        headersSize > maxStubBytes ||
        headersSize > _length ||
        headersSize % fileAlignment != 0 ||
        imageSize < headersSize ||
        imageSize % sectionAlignment != 0) {
      throw _corrupt('Invalid PE header or image extent.');
    }
    final directoryCount = _u32(optional, directoryStart - 4);
    if (directoryCount > 16 ||
        directoryCount > (optionalSize - directoryStart) ~/ 8) {
      throw _unsupported('Unknown or truncated PE data directories.');
    }
    final sectionData = await read(sectionTable, sectionBytes);
    final sections = <_PeSection>[];
    var overlay = headersSize;
    var previousVirtualEnd = 0;
    for (var index = 0; index < sectionCount; index++) {
      final at = index * 40;
      final virtualSize = _u32(sectionData, at + 8);
      final address = _u32(sectionData, at + 12);
      final size = _u32(sectionData, at + 16);
      final start = _u32(sectionData, at + 20);
      final virtualExtent = math.max(virtualSize, size);
      if (address == 0 ||
          address % sectionAlignment != 0 ||
          address < previousVirtualEnd ||
          address > imageSize ||
          virtualExtent > imageSize - address) {
        throw _corrupt('PE virtual sections overlap or leave the image.');
      }
      previousVirtualEnd = address + virtualExtent;
      if (_u32(sectionData, at + 24) != 0 ||
          _u32(sectionData, at + 28) != 0 ||
          _u16(sectionData, at + 32) != 0 ||
          _u16(sectionData, at + 34) != 0) {
        throw _unsupported(
          'PE section relocation/line tables are unsupported.',
        );
      }
      if (size == 0) {
        if (start != 0) {
          throw _corrupt('An empty PE section has a raw pointer.');
        }
      } else if (start < headersSize ||
          start % fileAlignment != 0 ||
          size % fileAlignment != 0 ||
          start > _length ||
          size > _length - start) {
        throw _corrupt('PE raw sections overlap headers or leave the source.');
      }
      if (size > 0) {
        if (start > maxStubBytes || size > maxStubBytes - start) {
          throw _limit('The executable prefix exceeds its inspection profile.');
        }
        overlay = math.max(overlay, start + size);
      }
      sections.add(
        _PeSection(
          address,
          start,
          size,
          _u32(sectionData, at + 36) & 0x20000000 != 0,
        ),
      );
    }
    final physical = sections.where((section) => section.size > 0).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    for (var index = 1; index < physical.length; index++) {
      if (physical[index].start < physical[index - 1].end) {
        throw _corrupt('PE raw sections overlap.');
      }
    }
    if (physical.isEmpty || overlay >= _length) {
      throw _corrupt('The executable has no appended archive payload.');
    }

    int fileOffset(int rva, int count) {
      if (rva < headersSize && count <= headersSize - rva) return rva;
      for (final section in sections) {
        if (section.containsAddress(rva, count)) {
          return section.start + rva - section.address;
        }
      }
      throw _corrupt('A PE data directory leaves the mapped executable.');
    }

    final entryPoint = _u32(optional, 16);
    if (entryPoint == 0 ||
        !sections.any(
          (section) =>
              section.executable && section.containsAddress(entryPoint, 1),
        )) {
      throw _unsupported('The PE image has no mapped executable entry point.');
    }
    for (var index = 0; index < directoryCount; index++) {
      final at = directoryStart + index * 8;
      final address = _u32(optional, at);
      final size = _u32(optional, at + 4);
      if (index == 4 && (address != 0 || size != 0)) {
        throw _unsupported(
          'Signed PE executable overlays are unsupported; publisher '
          'signatures are not authenticated.',
        );
      }
      if (address == 0 && size == 0) continue;
      if (index == 7 || index == 15) {
        throw _unsupported('Reserved PE data directories are not supported.');
      }
      // The global-pointer directory is an RVA with a specified zero size.
      if (index == 8 && address != 0 && size == 0) {
        fileOffset(address, 1);
        continue;
      }
      if (address == 0 || size == 0) {
        throw _corrupt('A PE data directory has inconsistent address/size.');
      }
      final atFile = fileOffset(address, size);
      if (index == 6) {
        if (size % 28 != 0 || size > 28 * 1024) {
          throw _corrupt('Invalid or oversized PE debug directory.');
        }
        final debug = await read(atFile, size);
        for (var record = 0; record < size; record += 28) {
          final dataSize = _u32(debug, record + 16);
          final dataAddress = _u32(debug, record + 20);
          final dataPointer = _u32(debug, record + 24);
          if (dataSize == 0 && dataAddress == 0 && dataPointer == 0) continue;
          if (dataSize == 0 ||
              dataAddress == 0 ||
              dataPointer < headersSize ||
              dataPointer >= overlay ||
              dataSize > overlay - dataPointer ||
              fileOffset(dataAddress, dataSize) != dataPointer) {
            throw _unsupported(
              'PE debug data outside mapped sections is unsupported.',
            );
          }
        }
      }
    }
    return overlay;
  }

  Future<void> readSevenZip(int offset, Uint8List header) async {
    if (header.length < 32 || header[6] != 0) {
      throw _corrupt('Invalid or unsupported 7z SFX signature header.');
    }
    if (getCrc32(Uint8List.sublistView(header, 12, 32)) != _u32(header, 8)) {
      throw _corrupt('The 7z SFX start-header checksum is invalid.');
    }
    final nextOffset = _u64(header, 12);
    final nextSize = _u64(header, 20);
    final remaining = _length - offset - 32;
    if (nextOffset > remaining || nextSize != remaining - nextOffset) {
      throw _corrupt(
        'The 7z SFX header extent is truncated or has trailing data.',
      );
    }
    final next = await read(offset + 32 + nextOffset, nextSize);
    if (getCrc32(next) != _u32(header, 28)) {
      throw _corrupt('The 7z SFX next-header checksum is invalid.');
    }
  }

  Future<void> readRar(int offset, Uint8List signature) async {
    if (signature.length < 8) throw _corrupt('Truncated RAR SFX signature.');
    if (signature[6] == 0) {
      final fixed = await read(offset + 7, 7);
      final headerSize = _u16(fixed, 5);
      if (fixed[2] != 0x73 || headerSize < 13) {
        throw _corrupt('The RAR4 SFX main header is invalid.');
      }
      final header = await read(offset + 7, headerSize);
      if ((getCrc32(Uint8List.sublistView(header, 2)) & 0xffff) !=
          _u16(header, 0)) {
        throw _corrupt('The RAR4 SFX header checksum is invalid.');
      }
      if (_u16(header, 3) & 1 != 0) {
        throw _unsupported(
          'Split-volume RAR executable archives are unsupported.',
        );
      }
      // Header-encrypted RAR4 keeps its first main header public. The normal
      // reader handles the password and all remaining headers/member checks.
      return;
    }
    if (signature[6] != 1 || signature[7] != 0) {
      throw _unsupported('Unknown RAR executable archive version.');
    }
    final prefix = await read(offset + 8, 7);
    final size = _vint(prefix, 4, maximumBytes: 3);
    if (size.value < 2) throw _corrupt('Invalid RAR5 SFX header size.');
    final fullSize = 4 + size.bytes + size.value;
    final header = await read(offset + 8, fullSize);
    if (getCrc32(Uint8List.sublistView(header, 4)) != _u32(header, 0)) {
      throw _corrupt('The RAR5 SFX header checksum is invalid.');
    }
    var cursor = 4 + size.bytes;
    final type = _vint(header, cursor);
    cursor += type.bytes;
    if (type.value != 1 && type.value != 4) {
      throw _corrupt('RAR5 SFX must start with its main or encryption header.');
    }
    final flags = _vint(header, cursor);
    cursor += flags.bytes;
    if (flags.value & 2 != 0) {
      throw _corrupt(
        'RAR5 SFX main/encryption headers cannot contain file data.',
      );
    }
    if (flags.value & 1 != 0) {
      final extra = _vint(header, cursor);
      cursor += extra.bytes;
      if (extra.value > header.length - cursor) {
        throw _corrupt('RAR5 SFX extra metadata leaves its header.');
      }
    }
    if (type.value == 1) {
      final archiveFlags = _vint(header, cursor);
      if (archiveFlags.value & 3 != 0) {
        throw _unsupported(
          'Split-volume RAR executable archives are unsupported.',
        );
      }
    }
  }

  Future<void> readZip(int payloadOffset) async {
    final tailCount = math.min(_length - payloadOffset, 65557);
    final tailStart = _length - tailCount;
    final tail = await read(tailStart, tailCount);
    var eocdAt = -1;
    for (var at = tail.length - 22; at >= 0; at--) {
      if (_u32(tail, at) == 0x06054b50 &&
          at + 22 + _u16(tail, at + 20) == tail.length) {
        if (eocdAt >= 0) throw _corrupt('Ambiguous ZIP SFX end records.');
        eocdAt = at;
      }
    }
    if (eocdAt < 0) throw _corrupt('The ZIP SFX end record is missing.');
    final eocdOffset = tailStart + eocdAt;
    final disk = _u16(tail, eocdAt + 4);
    final cdDisk = _u16(tail, eocdAt + 6);
    var entriesOnDisk = _u16(tail, eocdAt + 8);
    var entries = _u16(tail, eocdAt + 10);
    var cdSize = _u32(tail, eocdAt + 12);
    var cdOffset = _u32(tail, eocdAt + 16);
    var cdEnd = eocdOffset;
    int? locatorRecord;
    int? actualRecord;
    final hasMarkers =
        entries == 0xffff ||
        entriesOnDisk == 0xffff ||
        cdSize == 0xffffffff ||
        cdOffset == 0xffffffff;
    if (disk != 0 || cdDisk != 0) {
      throw _unsupported(
        'Split-volume ZIP executable archives are unsupported.',
      );
    }
    final locatorOffset = eocdOffset - 20;
    final locator = locatorOffset >= payloadOffset
        ? await read(locatorOffset, 20)
        : null;
    final hasLocator = locator != null && _u32(locator, 0) == 0x07064b50;
    if (hasMarkers && !hasLocator) {
      throw _corrupt('ZIP64 SFX metadata has no ZIP64 locator.');
    }
    if (hasLocator) {
      if (_u32(locator, 4) != 0 || _u32(locator, 16) != 1) {
        throw _unsupported(
          'Split-volume ZIP64 executable archives are unsupported.',
        );
      }
      locatorRecord = _u64(locator, 8);
      final candidates = <int>{locatorRecord, payloadOffset + locatorRecord};
      Uint8List? zip64;
      for (final at in candidates) {
        if (at < payloadOffset || at > locatorOffset - 56) continue;
        final fixed = await read(at, 56);
        if (_u32(fixed, 0) != 0x06064b50) continue;
        final recordSize = _u64(fixed, 4);
        if (recordSize < 44 || recordSize != locatorOffset - at - 12) continue;
        if (actualRecord != null) {
          throw _corrupt('Ambiguous ZIP64 SFX record offsets.');
        }
        // Read and bound any extensible-data sector as metadata as well.
        if (recordSize > 44) await read(at + 56, recordSize - 44);
        actualRecord = at;
        zip64 = fixed;
      }
      if (zip64 == null || actualRecord == null) {
        throw _corrupt('The ZIP64 SFX end record is invalid.');
      }
      if (_u32(zip64, 16) != 0 || _u32(zip64, 20) != 0) {
        throw _unsupported(
          'Split-volume ZIP64 executable archives are unsupported.',
        );
      }
      entriesOnDisk = _u64(zip64, 24);
      entries = _u64(zip64, 32);
      cdSize = _u64(zip64, 40);
      cdOffset = _u64(zip64, 48);
      cdEnd = actualRecord;
    }
    if (entries != entriesOnDisk) {
      throw _unsupported(
        'Split-volume ZIP executable archives are unsupported.',
      );
    }
    if (entries > 200000 || cdSize > maxMetadataBytes) {
      throw _limit('The ZIP SFX directory exceeds its inspection limit.');
    }
    if (cdSize > cdEnd - payloadOffset) {
      throw _corrupt('The ZIP SFX directory overlaps the executable.');
    }
    final cdStart = cdEnd - cdSize;
    final base = cdStart - cdOffset;
    if (base != 0 && base != payloadOffset) {
      throw _corrupt('The ZIP SFX directory uses ambiguous archive offsets.');
    }
    if (actualRecord != null && locatorRecord! + base != actualRecord) {
      throw _corrupt('The ZIP64 SFX locator uses inconsistent offsets.');
    }
    final directory = await read(cdStart, cdSize);
    var cursor = 0;
    final extents = <({int start, int end})>[];
    for (var index = 0; index < entries; index++) {
      if (directory.length - cursor < 46 ||
          _u32(directory, cursor) != 0x02014b50) {
        throw _corrupt('Invalid ZIP SFX central-directory entry.');
      }
      final flags = _u16(directory, cursor + 8);
      final method = _u16(directory, cursor + 10);
      final crc = _u32(directory, cursor + 16);
      var compressed = _u32(directory, cursor + 20);
      var expanded = _u32(directory, cursor + 24);
      final nameLength = _u16(directory, cursor + 28);
      final extraLength = _u16(directory, cursor + 30);
      final commentLength = _u16(directory, cursor + 32);
      var startDisk = _u16(directory, cursor + 34);
      var local = _u32(directory, cursor + 42);
      final end = cursor + 46 + nameLength + extraLength + commentLength;
      if (nameLength == 0 || end > directory.length) {
        throw _corrupt('Invalid ZIP SFX name/extra/comment extent.');
      }
      final name = Uint8List.sublistView(
        directory,
        cursor + 46,
        cursor + 46 + nameLength,
      );
      final extra = Uint8List.sublistView(
        directory,
        cursor + 46 + nameLength,
        cursor + 46 + nameLength + extraLength,
      );
      final needsExpanded = expanded == 0xffffffff;
      final needsCompressed = compressed == 0xffffffff;
      final needsLocal = local == 0xffffffff;
      final needsDisk = startDisk == 0xffff;
      final zip64 = _zip64Extra(extra);
      var zipAt = 0;
      int next64() {
        if (zip64 == null || zip64.length - zipAt < 8) {
          throw _corrupt('Truncated ZIP64 SFX central extra field.');
        }
        final result = _u64(zip64, zipAt);
        zipAt += 8;
        return result;
      }

      if (needsExpanded) expanded = next64();
      if (needsCompressed) compressed = next64();
      if (needsLocal) local = next64();
      if (needsDisk) {
        if (zip64 == null || zip64.length - zipAt < 4) {
          throw _corrupt('Truncated ZIP64 SFX disk field.');
        }
        startDisk = _u32(zip64, zipAt);
      }
      if (startDisk != 0) {
        throw _unsupported(
          'Split-volume ZIP executable archives are unsupported.',
        );
      }
      local += base;
      if (local < payloadOffset || local > cdStart - 30) {
        throw _corrupt(
          'A ZIP SFX member points into the executable or directory.',
        );
      }
      final localHeader = await read(local, 30);
      if (_u32(localHeader, 0) != 0x04034b50 ||
          _u16(localHeader, 6) != flags ||
          _u16(localHeader, 8) != method ||
          _u16(localHeader, 26) != nameLength) {
        throw _corrupt('ZIP SFX local and central headers disagree.');
      }
      final localExtraLength = _u16(localHeader, 28);
      final dataStart = local + 30 + nameLength + localExtraLength;
      if (dataStart > cdStart || compressed > cdStart - dataStart) {
        throw _corrupt('ZIP SFX member data leaves its archive region.');
      }
      final localVariable = await read(
        local + 30,
        nameLength + localExtraLength,
      );
      for (var at = 0; at < nameLength; at++) {
        if (name[at] != localVariable[at]) {
          throw _corrupt('ZIP SFX local and central member names disagree.');
        }
      }
      final localExtra = _zip64Extra(
        Uint8List.sublistView(localVariable, nameLength),
      );
      final localCompressed = _u32(localHeader, 18);
      final localExpanded = _u32(localHeader, 22);
      var dataEnd = dataStart + compressed;
      if (flags & 8 == 0) {
        var exactExpanded = localExpanded;
        var exactCompressed = localCompressed;
        var extraAt = 0;
        if (exactExpanded == 0xffffffff) {
          if (localExtra == null || localExtra.length < 8) {
            throw _corrupt('Missing ZIP64 SFX local expanded size.');
          }
          exactExpanded = _u64(localExtra, 0);
          extraAt = 8;
        }
        if (exactCompressed == 0xffffffff) {
          if (localExtra == null || localExtra.length - extraAt < 8) {
            throw _corrupt('Missing ZIP64 SFX local compressed size.');
          }
          exactCompressed = _u64(localExtra, extraAt);
        }
        if (_u32(localHeader, 14) != crc ||
            exactExpanded != expanded ||
            exactCompressed != compressed) {
          throw _corrupt('ZIP SFX local and central sizes/checksums disagree.');
        }
      } else {
        final wide =
            needsExpanded ||
            needsCompressed ||
            localExpanded == 0xffffffff ||
            localCompressed == 0xffffffff;
        final needed = wide ? 20 : 12;
        if (needed > cdStart - dataEnd) {
          throw _corrupt('The ZIP SFX data descriptor is truncated.');
        }
        final descriptor = await read(
          dataEnd,
          math.min(needed + 4, cdStart - dataEnd),
        );
        final hasSignature = _u32(descriptor, 0) == 0x08074b50;
        final at = hasSignature ? 4 : 0;
        if (descriptor.length < needed + at ||
            _u32(descriptor, at) != crc ||
            (wide ? _u64(descriptor, at + 4) : _u32(descriptor, at + 4)) !=
                compressed ||
            (wide ? _u64(descriptor, at + 12) : _u32(descriptor, at + 8)) !=
                expanded) {
          throw _corrupt('ZIP SFX data descriptor and directory disagree.');
        }
        dataEnd += needed + at;
      }
      extents.add((start: local, end: dataEnd));
      cursor = end;
    }
    if (cursor != directory.length) {
      throw _corrupt('Unrecognized trailing ZIP SFX directory metadata.');
    }
    extents.sort((a, b) => a.start.compareTo(b.start));
    if (extents.isEmpty) {
      if (cdSize != 0 || cdEnd != payloadOffset) {
        throw _corrupt('An empty ZIP SFX has unexplained overlay data.');
      }
    } else {
      if (extents.first.start != payloadOffset) {
        throw _corrupt('The ZIP SFX starts inside an unexplained overlay.');
      }
      for (var index = 1; index < extents.length; index++) {
        if (extents[index].start < extents[index - 1].end) {
          throw _corrupt('ZIP SFX member extents overlap.');
        }
      }
    }
  }
}

Uint8List? _zip64Extra(Uint8List extra) {
  Uint8List? result;
  var at = 0;
  while (at < extra.length) {
    if (extra.length - at < 4) {
      throw _corrupt('Truncated ZIP SFX extra record.');
    }
    final id = _u16(extra, at);
    final size = _u16(extra, at + 2);
    at += 4;
    if (size > extra.length - at) {
      throw _corrupt('ZIP SFX extra record is truncated.');
    }
    if (id == 1) {
      if (result != null) throw _corrupt('Duplicate ZIP64 SFX extra record.');
      result = Uint8List.sublistView(extra, at, at + size);
    }
    at += size;
  }
  return result;
}

({int value, int bytes}) _vint(Uint8List data, int at, {int maximumBytes = 8}) {
  var value = 0;
  var multiplier = 1;
  for (var count = 0; count < maximumBytes; count++) {
    if (at + count >= data.length) throw _corrupt('Truncated RAR SFX integer.');
    final byte = data[at + count];
    final part = byte & 0x7f;
    if (part > (9007199254740991 - value) ~/ multiplier) {
      throw _corrupt('RAR SFX integer cannot be represented safely.');
    }
    value += part * multiplier;
    if (byte & 0x80 == 0) return (value: value, bytes: count + 1);
    multiplier *= 128;
  }
  throw _corrupt('Oversized RAR SFX integer.');
}

int _u16(Uint8List bytes, int at) {
  if (at < 0 || bytes.length - at < 2) throw _corrupt('Truncated SFX integer.');
  return ByteData.sublistView(bytes).getUint16(at, Endian.little);
}

int _u32(Uint8List bytes, int at) {
  if (at < 0 || bytes.length - at < 4) throw _corrupt('Truncated SFX integer.');
  return ByteData.sublistView(bytes).getUint32(at, Endian.little);
}

int _u64(Uint8List bytes, int at) {
  final low = _u32(bytes, at);
  final high = _u32(bytes, at + 4);
  if (high > 0x1fffff) {
    throw _corrupt('SFX offset cannot be represented safely.');
  }
  return high * 4294967296 + low;
}

bool _powerOfTwo(int value) => value > 0 && value & (value - 1) == 0;

bool _magic(Uint8List bytes, List<int> magic) {
  if (bytes.length < magic.length) return false;
  for (var index = 0; index < magic.length; index++) {
    if (bytes[index] != magic[index]) return false;
  }
  return true;
}

ArchiveViewException _corrupt(String detail) => ArchiveViewException(
  detail,
  code: ArchiveMessageCode.corrupt,
  arguments: {'detail': detail},
);

ArchiveViewException _unsupported(String detail) =>
    ArchiveViewException(detail);

ArchiveViewException _limit(String detail) => ArchiveViewException(
  detail,
  code: ArchiveMessageCode.archiveLimit,
  arguments: {'limit': 'SFX metadata/prefix limit', 'detail': detail},
);
