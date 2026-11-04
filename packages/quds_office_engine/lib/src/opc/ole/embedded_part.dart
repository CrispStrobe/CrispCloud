import 'dart:convert';
import 'dart:typed_data';

import '../opc_archive.dart';
import 'cfbf_reader.dart';
import 'cfbf_writer.dart';

/// Well-known OLE CLSIDs for Office embeddings.
abstract final class OleClsids {
  /// word API.
  static final Uint8List word = _clsid(0x00020906, 0x0000, 0x0000, <int>[
    0xC0,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x46,
  ]);

  /// excel API.
  static final Uint8List excel = _clsid(0x00020820, 0x0000, 0x0000, <int>[
    0xC0,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x46,
  ]);

  /// powerPoint API.
  static final Uint8List powerPoint = _clsid(0x64818D10, 0x4F9B, 0x11CF, <int>[
    0x86,
    0xEA,
    0x00,
    0xAA,
    0x00,
    0xB9,
    0x29,
    0xE8,
  ]);

  static Uint8List _clsid(int d1, int d2, int d3, List<int> d4) {
    final Uint8List out = Uint8List(16);
    out[0] = d1 & 0xFF;
    out[1] = (d1 >> 8) & 0xFF;
    out[2] = (d1 >> 16) & 0xFF;
    out[3] = (d1 >> 24) & 0xFF;
    out[4] = d2 & 0xFF;
    out[5] = (d2 >> 8) & 0xFF;
    out[6] = d3 & 0xFF;
    out[7] = (d3 >> 8) & 0xFF;
    for (int i = 0; i < 8; i++) {
      out[8 + i] = d4[i];
    }
    return out;
  }
}

/// Isolated child package extracted from (or destined for) an OLE embedding.
///
/// The child [package] is a fully independent [OpcPackage]: mutate parts,
/// relationships, and content types, then call [pack] to rebuild the binary
/// that a parent document stores under `word/embeddings/` or `xl/embeddings/`.
class IsolatedEmbeddedPackage {
  /// IsolatedEmbeddedPackage API.
  IsolatedEmbeddedPackage({
    required this.package,
    required this.kind,
    this.displayName,
    this.thumbnail,
    this.progId,
  });

  /// package API.
  final OpcPackage package;

  /// kind API.
  final OpcPackageKind kind;

  /// displayName API.
  final String? displayName;

  /// thumbnail API.
  final Uint8List? thumbnail;

  /// progId API.
  final String? progId;

  /// resolvedDisplayName API.
  String get resolvedDisplayName =>
      displayName ??
      switch (kind) {
        OpcPackageKind.word => 'Microsoft Word Document',
        OpcPackageKind.sheet => 'Microsoft Excel Worksheet',
        OpcPackageKind.slide => 'Microsoft PowerPoint Presentation',
        OpcPackageKind.unknown => 'Package',
      };

  /// resolvedProgId API.
  String get resolvedProgId =>
      progId ??
      switch (kind) {
        OpcPackageKind.word => 'Word.Document.12',
        OpcPackageKind.sheet => 'Excel.Sheet.12',
        OpcPackageKind.slide => 'PowerPoint.Show.12',
        OpcPackageKind.unknown => 'Package',
      };

  /// clsid API.
  Uint8List get clsid => switch (kind) {
    OpcPackageKind.word => OleClsids.word,
    OpcPackageKind.sheet => OleClsids.excel,
    OpcPackageKind.slide => OleClsids.powerPoint,
    OpcPackageKind.unknown => Uint8List(16),
  };

  /// Rebuilds an `oleObject.bin` CFBF containing this package's ZIP bytes.
  Uint8List pack() {
    return EmbeddedPart.pack(this);
  }
}

/// Extracts and packages nested OOXML documents stored as OLE objects.
abstract final class EmbeddedPart {
  /// Opens an `oleObject.bin` (CFBF) or a raw OOXML ZIP and instantiates a
  /// standalone child [OpcPackage].
  static IsolatedEmbeddedPackage unpack(Uint8List bytes) {
    final Uint8List? ooxml = extractPackageBytes(bytes);
    if (ooxml == null) {
      throw const CfbfException(
        'No nested OOXML package found in OLE embedding',
      );
    }
    final OpcPackage package = OpcPackage.openBytes(ooxml);
    String? displayName;
    String? progId;
    Uint8List? thumbnail;
    if (CfbfFile.isCfbf(bytes)) {
      final CfbfFile cfbf = CfbfFile.fromBytes(bytes);
      final Uint8List? compObj =
          cfbf.readStream('\u0001CompObj') ?? cfbf.readStream('CompObj');
      if (compObj != null) {
        final _CompObj parsed = _CompObj.parse(compObj);
        displayName = parsed.userType;
        progId = parsed.progId;
      }
      thumbnail = _firstPresentation(cfbf);
    }
    return IsolatedEmbeddedPackage(
      package: package,
      kind: package.kind,
      displayName: displayName,
      progId: progId,
      thumbnail: thumbnail,
    );
  }

  /// Locates nested OOXML bytes inside a CFBF or returns [bytes] if they
  /// already are a ZIP archive.
  static Uint8List? extractPackageBytes(Uint8List bytes) {
    if (_isZip(bytes)) {
      return bytes;
    }
    if (!CfbfFile.isCfbf(bytes)) {
      return _findZip(bytes);
    }
    final CfbfFile cfbf = CfbfFile.fromBytes(bytes);
    const List<String> preferred = <String>[
      'Package',
      'CONTENTS',
      'Contents',
      'EmbeddedOdf',
      '\u0001Ole10Native',
      'Ole10Native',
    ];
    for (final String name in preferred) {
      final Uint8List? stream = cfbf.readStream(name);
      if (stream == null) {
        continue;
      }
      if (_isZip(stream)) {
        return stream;
      }
      final Uint8List? nested = _findZip(stream);
      if (nested != null) {
        return nested;
      }
    }
    for (final CfbfDirectoryEntry entry in cfbf.entries) {
      if (!entry.isStream) {
        continue;
      }
      final Uint8List data = cfbf.readEntry(entry);
      if (_isZip(data)) {
        return data;
      }
      final Uint8List? nested = _findZip(data);
      if (nested != null) {
        return nested;
      }
    }
    return null;
  }

  /// Wraps [child] in a CFBF with `Package`, `\x01CompObj`, `\x01Ole`,
  /// and `\x03ObjInfo` streams.
  static Uint8List pack(IsolatedEmbeddedPackage child) {
    final Uint8List zip = child.package.save();
    final CfbfWriter writer = CfbfWriter(clsid: child.clsid);
    writer.addStream('Package', zip);
    writer.addStream('\u0001Ole', _oleStream());
    writer.addStream(
      '\u0001CompObj',
      _CompObj(
        userType: child.resolvedDisplayName,
        progId: child.resolvedProgId,
      ).toBytes(),
    );
    writer.addStream(
      '\u0003ObjInfo',
      Uint8List.fromList(<int>[0x00, 0x00, 0x03, 0x00]),
    );
    if (child.thumbnail != null && child.thumbnail!.isNotEmpty) {
      writer.addStream('\u0002OlePres000', child.thumbnail!);
    }
    return writer.build();
  }

  /// Instantiates a new embedded child of [kind] with a valid empty package.
  static IsolatedEmbeddedPackage create(OpcPackageKind kind) {
    return IsolatedEmbeddedPackage(
      package: OpcPackage.create(kind),
      kind: kind,
    );
  }

  static bool _isZip(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  static Uint8List? _findZip(Uint8List bytes) {
    for (int i = 0; i + 4 <= bytes.length; i++) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4b &&
          bytes[i + 2] == 0x03 &&
          bytes[i + 3] == 0x04) {
        return Uint8List.sublistView(bytes, i);
      }
    }
    return null;
  }

  static Uint8List? _firstPresentation(CfbfFile cfbf) {
    for (final CfbfDirectoryEntry entry in cfbf.entries) {
      if (!entry.isStream) {
        continue;
      }
      final String upper = entry.name.toUpperCase();
      if (upper.contains('OLEPRES') || upper.contains('THUMBNAIL')) {
        return cfbf.readEntry(entry);
      }
    }
    return null;
  }

  static Uint8List _oleStream() {
    final Uint8List out = Uint8List(20);
    // Version 0x02000001, little-endian.
    out[0] = 0x01;
    out[1] = 0x00;
    out[2] = 0x00;
    out[3] = 0x02;
    return out;
  }
}

class _CompObj {
  _CompObj({this.userType, this.progId});

  /// userType API.
  final String? userType;

  /// progId API.
  final String? progId;

  /// parse API.
  factory _CompObj.parse(Uint8List bytes) {
    String? userType;
    String? progId;
    int offset = 28;
    if (bytes.length < 32) {
      return _CompObj();
    }
    if (offset + 4 <= bytes.length) {
      final int len = _u32(bytes, offset);
      offset += 4;
      if (len > 0 && len < 1024 && offset + len <= bytes.length) {
        userType = _ansi(bytes, offset, len);
        offset += len;
      }
    }
    if (offset + 4 <= bytes.length) {
      final int marker = _u32(bytes, offset);
      offset += 4;
      if (marker == 0xFFFFFFFF && offset + 4 <= bytes.length) {
        offset += 4; // clipboard format
      } else if (marker > 0 &&
          marker < 1024 &&
          offset + marker <= bytes.length) {
        offset += marker;
      }
    }
    if (offset + 4 <= bytes.length) {
      final int len = _u32(bytes, offset);
      offset += 4;
      if (len > 0 && len < 1024 && offset + len <= bytes.length) {
        progId = _ansi(bytes, offset, len);
      }
    }
    return _CompObj(userType: userType, progId: progId);
  }

  /// toBytes API.
  Uint8List toBytes() {
    final Uint8List user = _cString(userType ?? 'Package');
    final Uint8List prog = _cString(progId ?? 'Package');
    final BytesBuilder builder = BytesBuilder(copy: false);
    builder.add(Uint8List(4)); // reserved
    builder.add(_u32bytes(0x00000300)); // ANSI CompObj version
    builder.add(Uint8List(20));
    builder.add(_u32bytes(user.length));
    builder.add(user);
    builder.add(_u32bytes(0)); // no clipboard format
    builder.add(_u32bytes(prog.length));
    builder.add(prog);
    builder.add(_u32bytes(0));
    return builder.takeBytes();
  }

  static int _u32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  static Uint8List _u32bytes(int value) {
    return Uint8List.fromList(<int>[
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  static String _ansi(Uint8List bytes, int offset, int length) {
    final List<int> codes = <int>[];
    for (int i = 0; i < length; i++) {
      final int b = bytes[offset + i];
      if (b == 0) {
        break;
      }
      codes.add(b);
    }
    return latin1.decode(codes);
  }

  static Uint8List _cString(String value) {
    return Uint8List.fromList(<int>[...latin1.encode(value), 0]);
  }
}
