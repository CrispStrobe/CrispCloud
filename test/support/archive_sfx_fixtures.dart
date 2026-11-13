import 'dart:convert';
import 'dart:typed_data';

/// Produced with Python's standard-library zipfile, independently of Koni and
/// the SFX inspector. Fixed timestamps, Unix modes, Deflate, and UTF-8 names.
/// Contents: readme.txt, docs/empty/, 日本語/名前.txt.
Uint8List sfxReferenceZip() => base64Decode(
  'UEsDBBQAAAAIAIMYIlhbyJUcDgAAAAwAAAAKAAAAcmVhZG1lLnR4dAt2i1AoSKzMyU9M4QIA'
  'UEsDBBQAAAAIAIMYIlgAAAAAAgAAAAAAAAALAAAAZG9jcy9lbXB0eS8DAFBLAwQUAAAICACD'
  'GCJYywQHxRsAAAAZAAAAFAAAAOaXpeacrOiqni/lkI3liY0udHh0y0jNyclXSCvKz1VIVI'
  'jyDFDIL0stykms5AIAUEsBAhQDFAAAAAgAgxgiWFvIlRwOAAAADAAAAAoAAAAAAAAAAAAAAKSB'
  'AAAAAHJlYWRtZS50eHRQSwECFAMUAAAACACDGCJYAAAAAAIAAAAAAAAACwAAAAAAAAAAAAAA'
  '7UE2AAAAZG9jcy9lbXB0eS9QSwECFAMUAAAICACDGCJYywQHxRsAAAAZAAAAFAAAAAAAAAAA'
  'AAAApIFhAAAA5pel5pys6KqeL+WQjeWJjS50eHRQSwUGAAAAAAMAAwCzAAAArgAAAAAA',
);

/// Unmodified RAR 7.23 output (`rar a -m3 tiny.rar hello.txt story.txt`) from
/// koni_rar 0.9.0/test/rar_reader_test.dart, MIT, copyright (c) 2026 the
/// koni_archive authors. The retained MIT notice for this fixture collection is
/// in ../fixtures/archives/README.md. No RAR executable is redistributed.
Uint8List sfxReferenceRar5() => base64Decode(
  'UmFyIRoHAQAzkrXlCgEFBgAFAQGAgABMAUfGHwICjAAGjACkgwKlXQ1ebvdJOIAAAQloZWxs'
  'by50eHRoZWxsbywgcmFyIQrCzGXTHwICwQAGywCkgwKlXQ1eKGEdrIADAQlzdG9yeS50eHTE'
  'oD5FRUIvdAQ+7BX4AaYnxQRHRmKJrn/gUcyG7q/TO/hY+g3boauSRjdJjmHnv4SK3CzdlWgU'
  'jM76I1YQwmnpkB13VlEDBQQA',
);

/// Unmodified RAR 7.23 `-hpsecret` fixture from koni_rar 0.9.0's generated
/// fixture set. Same MIT notice/provenance as sfxReferenceRar5 above.
Uint8List sfxReferenceEncryptedRar5() => base64Decode(
  'UmFyIRoHAQB3qGXVIQQAAAEPaxYUDUYl3vDquDKSspx0jLdvAGg/bcSYmK+EwRgjLW/v8+'
  '/no+XK3dxZtUPm1P4qWuDCGcIV6k2g6luva8SPm8wwSkuHMqq9fGYE7mKwk0MAd9VbOMP5'
  'TCUcV9x/zZlv8+PwJY2fjHl8ydulFex1NQmwlPxcl+HlbynSV5RsWB672/kpaH3sjBqX4tu8'
  'ayFsX+ezaolanG9kVTEEmW0AOX9FQh/zq5SUyNZRCWVzM9Y+eaIiWWmJM5FSJYvUMrpM0vz'
  '1saLI7FLXetRRQvy2Hvpwh0zQNXkjQYlcgQ==',
);

const int sfxPeOffset = 0x80;
const int sfxOptionalOffset = sfxPeOffset + 24;
const int sfxPayloadOffset = 1024;

/// Original deterministic PE fixture, built from Microsoft's PE/COFF layout.
/// No third-party executable is copied or run. The only .text instruction is
/// RET, and this synthetic image is used strictly as archive-container data.
/// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
Uint8List sfxPeStub({
  bool pe64 = false,
  bool arm64 = false,
  int rawSectionStart = 512,
  int rawSectionSize = 512,
  bool headersOnly = false,
}) {
  final size = headersOnly ? 512 : rawSectionStart + rawSectionSize;
  final bytes = Uint8List(size);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 0x5a4d, Endian.little);
  data.setUint16(2, 0x90, Endian.little);
  data.setUint16(4, 3, Endian.little);
  data.setUint16(8, 4, Endian.little);
  data.setUint16(12, 0xffff, Endian.little);
  data.setUint16(16, 0xb8, Endian.little);
  data.setUint16(24, 0x40, Endian.little);
  data.setUint32(60, sfxPeOffset, Endian.little);
  bytes.setRange(64, 64 + 23, ascii.encode('Archive fixture only\r\n\$'));
  data.setUint32(sfxPeOffset, 0x00004550, Endian.little);
  data.setUint16(
    sfxPeOffset + 4,
    arm64
        ? 0xaa64
        : pe64
        ? 0x8664
        : 0x14c,
    Endian.little,
  );
  data.setUint16(sfxPeOffset + 6, 1, Endian.little);
  final optionalSize = pe64 ? 240 : 224;
  data.setUint16(sfxPeOffset + 20, optionalSize, Endian.little);
  data.setUint16(sfxPeOffset + 22, pe64 ? 0x22 : 0x102, Endian.little);
  const optional = sfxOptionalOffset;
  data.setUint16(optional, pe64 ? 0x20b : 0x10b, Endian.little);
  bytes[optional + 2] = 14;
  data.setUint32(optional + 4, rawSectionSize, Endian.little);
  data.setUint32(optional + 16, 0x1000, Endian.little);
  data.setUint32(optional + 20, 0x1000, Endian.little);
  if (pe64) {
    data.setUint64(optional + 24, 0x140000000, Endian.little);
  } else {
    data.setUint32(optional + 28, 0x400000, Endian.little);
  }
  data.setUint32(optional + 32, 0x1000, Endian.little);
  data.setUint32(optional + 36, 0x200, Endian.little);
  data.setUint16(optional + 40, 6, Endian.little);
  data.setUint16(optional + 48, 6, Endian.little);
  data.setUint32(
    optional + 56,
    ((0x1000 + rawSectionSize + 4095) ~/ 4096) * 4096,
    Endian.little,
  );
  data.setUint32(optional + 60, 512, Endian.little);
  data.setUint16(optional + 68, 3, Endian.little);
  if (pe64) {
    data.setUint64(optional + 72, 1024 * 1024, Endian.little);
    data.setUint64(optional + 80, 4096, Endian.little);
    data.setUint64(optional + 88, 1024 * 1024, Endian.little);
    data.setUint64(optional + 96, 4096, Endian.little);
  } else {
    data.setUint32(optional + 72, 1024 * 1024, Endian.little);
    data.setUint32(optional + 76, 4096, Endian.little);
    data.setUint32(optional + 80, 1024 * 1024, Endian.little);
    data.setUint32(optional + 84, 4096, Endian.little);
  }
  data.setUint32(optional + (pe64 ? 108 : 92), 16, Endian.little);
  final section = optional + optionalSize;
  bytes.setRange(section, section + 5, ascii.encode('.text'));
  data.setUint32(section + 8, 16, Endian.little);
  data.setUint32(section + 12, 0x1000, Endian.little);
  data.setUint32(section + 16, rawSectionSize, Endian.little);
  data.setUint32(section + 20, rawSectionStart, Endian.little);
  data.setUint32(section + 36, 0x60000020, Endian.little);
  if (!headersOnly) bytes[rawSectionStart] = 0xc3;
  return bytes;
}

Uint8List sfxPeArchive(
  Uint8List payload, {
  bool pe64 = false,
  bool arm64 = false,
}) {
  final stub = sfxPeStub(pe64: pe64, arm64: arm64);
  return Uint8List.fromList([...stub, ...payload]);
}

/// The independent Python ZIP uses payload-relative offsets. This fixture
/// variant adjusts all central offsets to physical executable coordinates.
Uint8List sfxAbsoluteZipOffsets(Uint8List original, int prefixLength) {
  final bytes = Uint8List.fromList(original);
  final data = ByteData.sublistView(bytes);
  final end = bytes.length - 22;
  var at = data.getUint32(end + 16, Endian.little);
  final count = data.getUint16(end + 10, Endian.little);
  for (var i = 0; i < count; i++) {
    data.setUint32(
      at + 42,
      data.getUint32(at + 42, Endian.little) + prefixLength,
      Endian.little,
    );
    at +=
        46 +
        data.getUint16(at + 28, Endian.little) +
        data.getUint16(at + 30, Endian.little) +
        data.getUint16(at + 32, Endian.little);
  }
  data.setUint32(
    end + 16,
    data.getUint32(end + 16, Endian.little) + prefixLength,
    Endian.little,
  );
  return bytes;
}

/// Sparse, structurally valid ZIP64 containing a stored five-GiB member. The
/// test source synthesizes payload zeros and only supplies these small metadata
/// regions; opening must not allocate or read the declared file content.
({int length, Map<int, Uint8List> regions}) sfxSparseZip64({
  int memberSize = 5 * 1024 * 1024 * 1024,
  bool absoluteOffsets = false,
}) {
  final offset = absoluteOffsets ? sfxPayloadOffset : 0;
  final local = Uint8List(31 + 20);
  final l = ByteData.sublistView(local);
  l.setUint32(0, 0x04034b50, Endian.little);
  l.setUint16(4, 45, Endian.little);
  l.setUint32(18, 0xffffffff, Endian.little);
  l.setUint32(22, 0xffffffff, Endian.little);
  l.setUint16(26, 1, Endian.little);
  l.setUint16(28, 20, Endian.little);
  local[30] = 0x61;
  l.setUint16(31, 1, Endian.little);
  l.setUint16(33, 16, Endian.little);
  l.setUint64(35, memberSize, Endian.little);
  l.setUint64(43, memberSize, Endian.little);
  final centralPosition = sfxPayloadOffset + local.length + memberSize;
  final central = Uint8List(47 + 28);
  final c = ByteData.sublistView(central);
  c.setUint32(0, 0x02014b50, Endian.little);
  c.setUint16(4, 45, Endian.little);
  c.setUint16(6, 45, Endian.little);
  c.setUint32(20, 0xffffffff, Endian.little);
  c.setUint32(24, 0xffffffff, Endian.little);
  c.setUint16(28, 1, Endian.little);
  c.setUint16(30, 28, Endian.little);
  c.setUint32(42, 0xffffffff, Endian.little);
  central[46] = 0x61;
  c.setUint16(47, 1, Endian.little);
  c.setUint16(49, 24, Endian.little);
  c.setUint64(51, memberSize, Endian.little);
  c.setUint64(59, memberSize, Endian.little);
  c.setUint64(67, offset, Endian.little);
  final zip64Position = centralPosition + central.length;
  final end = Uint8List(56 + 20 + 22);
  final e = ByteData.sublistView(end);
  e.setUint32(0, 0x06064b50, Endian.little);
  e.setUint64(4, 44, Endian.little);
  e.setUint16(12, 45, Endian.little);
  e.setUint16(14, 45, Endian.little);
  e.setUint64(24, 1, Endian.little);
  e.setUint64(32, 1, Endian.little);
  e.setUint64(40, central.length, Endian.little);
  e.setUint64(48, centralPosition - sfxPayloadOffset + offset, Endian.little);
  e.setUint32(56, 0x07064b50, Endian.little);
  e.setUint64(64, zip64Position - sfxPayloadOffset + offset, Endian.little);
  e.setUint32(72, 1, Endian.little);
  e.setUint32(76, 0x06054b50, Endian.little);
  e.setUint16(84, 0xffff, Endian.little);
  e.setUint16(86, 0xffff, Endian.little);
  e.setUint32(88, 0xffffffff, Endian.little);
  e.setUint32(92, 0xffffffff, Endian.little);
  return (
    length: zip64Position + end.length,
    regions: {
      0: sfxPeStub(),
      sfxPayloadOffset: local,
      centralPosition: central,
      zip64Position: end,
    },
  );
}
