// tool/fuzz_internal_viewer.dart
//
// Blind robustness fuzzing (covfuzz) for the F3 viewer's parser surface:
//   * InternalViewerService: mode detection, text decoding, safe-byte
//     rendering, hex-pattern parsing, byte search.
//   * ArchiveViewerService.decompressSingleFile: bounded gz/bz2/xz/zst
//     decompression (must only ever throw ArchiveViewException).
//
// Run: dart run tool/fuzz_internal_viewer.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:covfuzz/covfuzz.dart';

import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';

const _svc = InternalViewerService();

Uint8List _bytes(List<int> data) => Uint8List.fromList(data);

Uint8List _file(String path) => File(path).readAsBytesSync();

List<Uint8List> _seeds() {
  final tar = Uint8List(1024);
  const ustar = 'ustar';
  for (var i = 0; i < ustar.length; i++) {
    tar[257 + i] = ustar.codeUnitAt(i);
  }
  return <Uint8List>[
    _bytes(utf8.encode('hello world\nsecond line\n')),
    _bytes(utf8.encode('Grüße, 日本語, emoji 🙂\n')),
    _bytes(<int>[0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]), // UTF-16LE BOM
    _bytes(<int>[0xEF, 0xBB, 0xBF, 0x68, 0x69]), // UTF-8 BOM
    _bytes(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    _bytes(<int>[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]), // 7z magic
    _bytes(<int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]), // RAR4 magic
    _bytes(<int>[0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]), // XZ magic
    _bytes(<int>[0x28, 0xB5, 0x2F, 0xFD]), // Zstd magic
    tar,
    _bytes(<int>[0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00]),
    _file('test/fixtures/archives/sample.7z'),
    _file('test/fixtures/archives/sample.rar'),
  ];
}

void main() {
  final seeds = _seeds();

  final parserReport = fuzz<Uint8List>(
    seeds: seeds,
    entry: (bytes) {
      _svc.detectMode('fuzz.bin', header: bytes);
      final decoded = InternalViewerService.decodeTextForView(bytes);
      decoded.text.length;
      InternalViewerService.renderSafeBytes(bytes);
      InternalViewerService.renderSafeBytes(bytes, binaryMode: true);
      InternalViewerService.findBytes(
        bytes,
        const <int>[0x50, 0x4B, 0x03, 0x04],
        maxMatches: 16,
      );
      InternalViewerService.parseHexPattern(
        utf8.decode(bytes, allowMalformed: true),
      );
    },
    mutate: mutateBytes,
    // The service contract: no throws for arbitrary bytes.
    isClean: (_) => false,
    iterations: 25000,
    budgetMs: 20000,
    stressors: <Uint8List>[
      Uint8List(0),
      Uint8List.fromList(List<int>.filled(1 << 20, 0x41)),
    ],
  );

  final decompressReport = fuzz<Uint8List>(
    seeds: seeds,
    entry: (bytes) {
      // Bounded single-file decompression: any failure must be our typed
      // ArchiveViewException (a crash/escape is a defect).
      for (final name in const ['f.gz', 'f.bz2', 'f.xz', 'f.zst']) {
        try {
          decompressSingleFile(bytes, name, maxBytes: 64 * 1024);
        } on ArchiveViewException {
          // clean rejection
        }
      }
    },
    mutate: mutateBytes,
    isClean: (error) => error is ArchiveViewException,
    iterations: 8000,
    budgetMs: 20000,
  );

  var exitCode = 0;
  if (!parserReport.clean || parserReport.slow) exitCode = 1;
  if (!decompressReport.clean || decompressReport.slow) exitCode = 1;
  parserReport.report();
  decompressReport.report();
  exit(exitCode);
}
