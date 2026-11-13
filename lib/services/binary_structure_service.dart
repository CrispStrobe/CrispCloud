// Copyright 2026 Flyfish Viewer
// SPDX-License-Identifier: Apache-2.0
//
// Modified Dart port of File Viewer's binary parser and models. This port
// inspects only a bounded 64 KiB prefix, reports incomplete/ambiguous headers,
// and uses exact unsigned 64-bit values on native and web targets.
// Source revision, license and modification record:
// packages/file_viewer_binary/UPSTREAM.md

import 'dart:typed_data';

/// Maximum input retained/read by the header inspector. The rest of the file
/// remains with the caller's existing lazy byte source.
const int binaryStructurePrefixBytes = 64 * 1024;

enum BinaryStructureFormat {
  raw,
  png,
  wasm,
  elf,
  pe,
  machO,
  zip,
  javaClass,
  machOFat,
}

enum BinaryStructureIssue {
  /// A header requires bytes beyond the reported end of the file.
  truncated,

  /// Bytes outside the supplied prefix were not inspected.
  prefixLimit,

  /// A recognized header contains inconsistent or unsupported header values.
  invalidHeader,

  /// Shared magic bytes do not establish one of the possible formats.
  ambiguousMagic,
}

class BinaryStructureField {
  const BinaryStructureField({
    required this.name,
    required this.type,
    required this.start,
    required this.end,
    this.value,
    this.children = const [],
  });

  final String name;
  final String type;
  final int start;
  final int end;
  final String? value;
  final List<BinaryStructureField> children;
}

class BinaryStructureAnalysis {
  const BinaryStructureAnalysis({
    required this.format,
    required this.byteLength,
    required this.inspectedBytes,
    required this.fields,
    required this.issues,
  });

  final BinaryStructureFormat format;
  final int byteLength;
  final int inspectedBytes;
  final List<BinaryStructureField> fields;
  final List<BinaryStructureIssue> issues;
}

/// Inspect fixed-size headers; never execute input or decompress/read payloads.
///
/// [prefix] must start at file offset zero, but may itself be a typed-data view.
/// Fields reference only bytes actually present in this prefix. Header groups
/// can cover a partial, present range; missing children are omitted and issues
/// disclose the missing bytes. The result is not a file-validity assessment.
/// There is no iteration or allocation based on a file-provided entry count.
BinaryStructureAnalysis inspectBinaryStructure(
  Uint8List prefix, {
  required int totalBytes,
}) {
  if (prefix.length > binaryStructurePrefixBytes) {
    throw ArgumentError.value(
      prefix.length,
      'prefix.length',
      'Must not exceed $binaryStructurePrefixBytes bytes.',
    );
  }
  if (totalBytes < prefix.length) {
    throw ArgumentError.value(
      totalBytes,
      'totalBytes',
      'Must be at least the supplied prefix length.',
    );
  }
  return _HeaderInspector(prefix, totalBytes).inspect();
}

class _HeaderInspector {
  _HeaderInspector(this.bytes, this.totalBytes)
    : view = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final int totalBytes;
  final ByteData view;
  final fields = <BinaryStructureField>[];
  final issues = <BinaryStructureIssue>{};
  var format = BinaryStructureFormat.raw;

  BinaryStructureAnalysis inspect() {
    if (bytes.length < totalBytes) {
      issues.add(BinaryStructureIssue.prefixLimit);
    }
    if (_starts(const [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10])) {
      format = BinaryStructureFormat.png;
      _png();
    } else if (_starts(const [0, 0x61, 0x73, 0x6d])) {
      format = BinaryStructureFormat.wasm;
      _magic('WASM magic', 4);
      final version = _uint(fields, 'Version', 4, 4, Endian.little);
      if (version != null && version != 1) _invalid();
    } else if (_starts(const [0x7f, 0x45, 0x4c, 0x46])) {
      format = BinaryStructureFormat.elf;
      _elf();
    } else if (_starts(const [0x4d, 0x5a])) {
      format = BinaryStructureFormat.pe;
      _pe();
    } else if (_starts(const [0xfe, 0xed, 0xfa, 0xce]) ||
        _starts(const [0xce, 0xfa, 0xed, 0xfe]) ||
        _starts(const [0xfe, 0xed, 0xfa, 0xcf]) ||
        _starts(const [0xcf, 0xfa, 0xed, 0xfe])) {
      format = BinaryStructureFormat.machO;
      _machO();
    } else if (_starts(const [0x50, 0x4b, 3, 4]) ||
        _starts(const [0x50, 0x4b, 5, 6]) ||
        _starts(const [0x50, 0x4b, 7, 8])) {
      format = BinaryStructureFormat.zip;
      _zip();
    } else if (_starts(const [0xca, 0xfe, 0xba, 0xbe])) {
      _javaOrFatMachO();
    } else if (_starts(const [0xca, 0xfe, 0xba, 0xbf]) ||
        _starts(const [0xbe, 0xba, 0xfe, 0xca]) ||
        _starts(const [0xbf, 0xba, 0xfe, 0xca])) {
      format = BinaryStructureFormat.machOFat;
      final little = bytes[0] != 0xca;
      _fatMachO(
        little ? Endian.little : Endian.big,
        bytes[0] == 0xbf || bytes[3] == 0xbf,
      );
    } else {
      _incompleteMagic();
    }
    return BinaryStructureAnalysis(
      format: format,
      byteLength: totalBytes,
      inspectedBytes: bytes.length,
      fields: List.unmodifiable(fields),
      issues: List.unmodifiable(issues),
    );
  }

  bool _has(int offset, int width) =>
      offset >= 0 && width >= 0 && offset + width <= bytes.length;

  bool _need(int offset, int width) {
    if (_has(offset, width)) return true;
    issues.add(
      offset + width > totalBytes
          ? BinaryStructureIssue.truncated
          : BinaryStructureIssue.prefixLimit,
    );
    return false;
  }

  void _invalid() => issues.add(BinaryStructureIssue.invalidHeader);

  bool _starts(List<int> signature, [int offset = 0]) {
    if (!_has(offset, signature.length)) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[offset + index] != signature[index]) return false;
    }
    return true;
  }

  void _field(
    List<BinaryStructureField> target,
    String name,
    String type,
    int offset,
    int width,
    String value,
  ) {
    if (!_need(offset, width) || width == 0) return;
    target.add(
      BinaryStructureField(
        name: name,
        type: type,
        start: offset,
        end: offset + width,
        value: value,
      ),
    );
  }

  void _group(
    String name,
    int offset,
    int width,
    List<BinaryStructureField> children,
  ) {
    _need(offset, width);
    if (offset >= bytes.length || width == 0) return;
    final end = offset + width < bytes.length ? offset + width : bytes.length;
    fields.add(
      BinaryStructureField(
        name: name,
        type: 'structure',
        start: offset,
        end: end,
        children: List.unmodifiable(children),
      ),
    );
  }

  void _magic(String name, int width, [int offset = 0]) {
    if (!_need(offset, width)) return;
    final value = List.generate(
      width,
      (i) => bytes[offset + i].toRadixString(16).toUpperCase().padLeft(2, '0'),
    ).join(' ');
    _field(fields, name, 'bytes', offset, width, value);
  }

  int? _uint(
    List<BinaryStructureField> target,
    String name,
    int offset,
    int width,
    Endian endian, {
    bool hex = false,
  }) {
    if (!_need(offset, width)) return null;
    final value = switch (width) {
      1 => view.getUint8(offset),
      2 => view.getUint16(offset, endian),
      4 => view.getUint32(offset, endian),
      _ => throw StateError('Unsupported fixed field width.'),
    };
    final type = width == 1
        ? 'u8'
        : 'u${width * 8}${endian == Endian.little ? 'le' : 'be'}';
    _field(target, name, type, offset, width, hex ? _hex(value) : '$value');
    return value;
  }

  BigInt _read64(int offset, Endian endian) {
    // Combining two uint32 values via BigInt avoids native signed-64 overflow
    // and JavaScript's 53-bit integer precision limit.
    final high = view.getUint32(
      offset + (endian == Endian.little ? 4 : 0),
      endian,
    );
    final low = view.getUint32(
      offset + (endian == Endian.little ? 0 : 4),
      endian,
    );
    return (BigInt.from(high) << 32) | BigInt.from(low);
  }

  BigInt? _uint64(
    List<BinaryStructureField> target,
    String name,
    int offset,
    Endian endian,
  ) {
    if (!_need(offset, 8)) return null;
    final value = _read64(offset, endian);
    _field(
      target,
      name,
      endian == Endian.little ? 'u64le' : 'u64be',
      offset,
      8,
      '0x${value.toRadixString(16).toUpperCase()}',
    );
    return value;
  }

  String _hex(int value) => '0x${value.toRadixString(16).toUpperCase()}';

  void _png() {
    _magic('PNG signature', 8);
    final length = _uint(fields, 'Chunk length', 8, 4, Endian.big);
    if (!_need(12, 4)) return;
    final kind = String.fromCharCodes(bytes.sublist(12, 16));
    _field(
      fields,
      'Chunk type',
      'ascii',
      12,
      4,
      kind.replaceAll(RegExp(r'[^\x20-\x7e]'), '.'),
    );
    if (kind != 'IHDR' || length != 13) {
      _invalid();
      return;
    }
    _need(0, 33); // Includes the first chunk's CRC; CRC is not validated here.
    final children = <BinaryStructureField>[];
    final width = _uint(children, 'Width', 16, 4, Endian.big);
    final height = _uint(children, 'Height', 20, 4, Endian.big);
    if (width == 0 || height == 0) _invalid();
    _uint(children, 'Bit depth', 24, 1, Endian.big);
    _uint(children, 'Color type', 25, 1, Endian.big);
    _group('IHDR', 16, 13, children);
  }

  void _elf() {
    _magic('ELF magic', 4);
    final elfClass = _uint(fields, 'Class', 4, 1, Endian.big);
    final encoding = _uint(fields, 'Data encoding', 5, 1, Endian.big);
    if (elfClass == null || encoding == null) return;
    if ((elfClass != 1 && elfClass != 2) || (encoding != 1 && encoding != 2)) {
      _invalid();
      return; // An unknown byte order must never silently become little-endian.
    }
    final is64 = elfClass == 2;
    final endian = encoding == 1 ? Endian.little : Endian.big;
    final children = <BinaryStructureField>[];
    _uint(children, 'Type', 16, 2, endian, hex: true);
    _uint(children, 'Machine', 18, 2, endian, hex: true);
    if (is64) {
      _uint64(children, 'Entry point', 24, endian);
    } else {
      _uint(children, 'Entry point', 24, 4, endian, hex: true);
    }
    _group(
      is64 ? 'ELF64 header' : 'ELF32 header',
      16,
      is64 ? 48 : 36,
      children,
    );
  }

  void _pe() {
    _magic('DOS magic', 2);
    final offset = _uint(
      fields,
      'PE header offset',
      0x3c,
      4,
      Endian.little,
      hex: true,
    );
    if (offset == null) return;
    if (offset < 64) {
      _invalid();
      return;
    }
    if (!_need(offset, 4)) {
      if (offset + 4 > totalBytes) _invalid();
      return;
    }
    _magic('PE signature', 4, offset);
    if (!_starts(const [0x50, 0x45, 0, 0], offset)) {
      _invalid();
      return;
    }
    final children = <BinaryStructureField>[];
    _uint(children, 'Machine', offset + 4, 2, Endian.little, hex: true);
    _uint(children, 'Number of sections', offset + 6, 2, Endian.little);
    final optionalSize = _uint(
      children,
      'Optional header size',
      offset + 20,
      2,
      Endian.little,
    );
    _group('COFF header', offset + 4, 20, children);
    if (optionalSize == null || optionalSize == 0) return;
    final optionalStart = offset + 24;
    _need(optionalStart, optionalSize);
    if (optionalSize < 2) {
      _invalid();
      return;
    }
    final magic = _uint(
      fields,
      'Optional header magic',
      optionalStart,
      2,
      Endian.little,
      hex: true,
    );
    if (magic != null && magic != 0x10b && magic != 0x20b && magic != 0x107) {
      _invalid();
    }
  }

  void _machO() {
    final little = bytes[0] == 0xce || bytes[0] == 0xcf;
    final is64 = bytes[0] == 0xcf || bytes[3] == 0xcf;
    final endian = little ? Endian.little : Endian.big;
    _magic('Mach-O magic', 4);
    final children = <BinaryStructureField>[];
    _uint(children, 'CPU type', 4, 4, endian, hex: true);
    _uint(children, 'CPU subtype', 8, 4, endian, hex: true);
    _uint(children, 'File type', 12, 4, endian, hex: true);
    final commands = _uint(children, 'Load commands', 16, 4, endian);
    final commandBytes = _uint(children, 'Load command bytes', 20, 4, endian);
    _uint(children, 'Flags', 24, 4, endian, hex: true);
    if (commands != null &&
        commandBytes != null &&
        commands > commandBytes ~/ 8) {
      _invalid();
    }
    _group(
      is64 ? 'Mach-O 64 header' : 'Mach-O 32 header',
      4,
      is64 ? 28 : 24,
      children,
    );
  }

  void _zip() {
    _magic('ZIP signature', 4);
    if (bytes[2] != 3) {
      // The signature alone cannot establish ZIP64 descriptor field widths.
      _need(0, bytes[2] == 5 ? 22 : 16);
      return;
    }
    final children = <BinaryStructureField>[];
    _uint(children, 'Version needed', 4, 2, Endian.little);
    _uint(children, 'Flags', 6, 2, Endian.little, hex: true);
    _uint(children, 'Compression', 8, 2, Endian.little);
    _uint(children, 'Compressed size', 18, 4, Endian.little);
    _uint(children, 'Uncompressed size', 22, 4, Endian.little);
    final nameLength = _uint(children, 'Filename length', 26, 2, Endian.little);
    final extraLength = _uint(
      children,
      'Extra field length',
      28,
      2,
      Endian.little,
    );
    _group('Local file header', 4, 26, children);
    if (nameLength != null && extraLength != null) {
      _need(30, nameLength + extraLength);
    }
  }

  void _javaOrFatMachO() {
    // CAFEBABE is shared by Java class files and big-endian fat Mach-O. Use
    // independent, fixed-size evidence instead of claiming Java from magic.
    final java = _has(4, 6) && _plausibleJavaHeader();
    final fat = _plausibleFatHeader();
    final incompleteFat =
        _has(4, 4) &&
        view.getUint32(4, Endian.big) > 0 &&
        view.getUint32(4, Endian.big) <= (totalBytes - 8) ~/ 20 &&
        !_has(8, 20);
    if (java && !fat && !incompleteFat) {
      format = BinaryStructureFormat.javaClass;
      _magic('Class magic', 4);
      _uint(fields, 'Minor version', 4, 2, Endian.big);
      _uint(fields, 'Major version', 6, 2, Endian.big);
      _uint(fields, 'Constant pool count', 8, 2, Endian.big);
    } else if (fat && !java) {
      format = BinaryStructureFormat.machOFat;
      _fatMachO(Endian.big, false);
    } else {
      _magic('Shared Java / fat Mach-O magic', 4);
      issues.add(BinaryStructureIssue.ambiguousMagic);
      if (!_has(4, 6)) _need(4, 6);
      if (incompleteFat) _need(8, 20);
    }
  }

  bool _plausibleJavaHeader() {
    final minor = view.getUint16(4, Endian.big);
    final major = view.getUint16(6, Endian.big);
    return major >= 45 &&
        (minor == 0 || minor == 65535 || (major == 45 && minor <= 3)) &&
        view.getUint16(8, Endian.big) > 0;
  }

  bool _plausibleFatHeader() {
    if (!_has(4, 24)) return false;
    final count = view.getUint32(4, Endian.big);
    if (count == 0 || count > (totalBytes - 8) ~/ 20) return false;
    // CPU codes are extensible. An unfamiliar code must not eliminate the
    // fat interpretation and incorrectly turn shared magic into a Java claim.
    final offset = view.getUint32(16, Endian.big);
    final size = view.getUint32(20, Endian.big);
    final alignment = view.getUint32(24, Endian.big);
    return offset >= 8 + count * 20 &&
        size > 0 &&
        offset + size <= totalBytes &&
        alignment <= 31;
  }

  void _fatMachO(Endian endian, bool is64) {
    _magic(is64 ? 'Fat Mach-O 64 magic' : 'Fat Mach-O magic', 4);
    final count = _uint(fields, 'Architecture count', 4, 4, endian);
    if (count == null) return;
    if (count == 0) {
      _invalid();
      return;
    }
    final entryBytes = is64 ? 32 : 20;
    if (count > (totalBytes - 8) ~/ entryBytes) {
      issues.add(BinaryStructureIssue.truncated);
    }
    final children = <BinaryStructureField>[];
    _uint(children, 'CPU type', 8, 4, endian, hex: true);
    _uint(children, 'CPU subtype', 12, 4, endian, hex: true);
    if (is64) {
      _uint64(children, 'Slice offset', 16, endian);
      _uint64(children, 'Slice size', 24, endian);
    } else {
      _uint(children, 'Slice offset', 16, 4, endian, hex: true);
      _uint(children, 'Slice size', 20, 4, endian, hex: true);
    }
    _uint(children, 'Alignment exponent', is64 ? 32 : 24, 4, endian);
    // Only the first architecture is inspected, regardless of count.
    _group('First architecture', 8, entryBytes, children);
  }

  void _incompleteMagic() {
    if (bytes.isEmpty) return;
    const signatures = [
      [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10],
      [0, 0x61, 0x73, 0x6d],
      [0x7f, 0x45, 0x4c, 0x46],
      [0x4d, 0x5a],
      [0xfe, 0xed, 0xfa, 0xce],
      [0xce, 0xfa, 0xed, 0xfe],
      [0xfe, 0xed, 0xfa, 0xcf],
      [0xcf, 0xfa, 0xed, 0xfe],
      [0x50, 0x4b, 3, 4],
      [0x50, 0x4b, 5, 6],
      [0x50, 0x4b, 7, 8],
      [0xca, 0xfe, 0xba, 0xbe],
      [0xca, 0xfe, 0xba, 0xbf],
      [0xbe, 0xba, 0xfe, 0xca],
      [0xbf, 0xba, 0xfe, 0xca],
    ];
    for (final signature in signatures) {
      if (bytes.length >= signature.length) continue;
      var matches = true;
      for (var index = 0; index < bytes.length; index++) {
        if (bytes[index] != signature[index]) matches = false;
      }
      if (matches) {
        _need(0, signature.length);
        return;
      }
    }
  }
}
