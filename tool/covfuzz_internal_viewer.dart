// tool/covfuzz_internal_viewer.dart
//
// Coverage-guided fuzzing (covfuzz) for the viewer's magic-byte and text
// decoding paths — the branches blind mutation rarely reaches behind headers.
//
// Run (its own process, VM service required):
//   dart run --enable-vm-service=0 --no-pause-isolates-on-exit \
//     tool/covfuzz_internal_viewer.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:covfuzz/covfuzz.dart';

import 'package:crisp_cloud/services/internal_viewer_service.dart';

const _svc = InternalViewerService();

Uint8List _bytes(List<int> data) => Uint8List.fromList(data);

Future<void> main() async {
  final seeds = <Uint8List>[
    _bytes(utf8.encode('hello world\nsecond line\n')),
    _bytes(utf8.encode('Grüße, 日本語 🙂\n')),
    _bytes(<int>[0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]),
    _bytes(<int>[0xEF, 0xBB, 0xBF, 0x68, 0x69]),
    _bytes(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    _bytes(<int>[0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37]),
    _bytes(<int>[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]),
    _bytes(<int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]),
    _bytes(<int>[0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]),
    _bytes(<int>[0x28, 0xB5, 0x2F, 0xFD]),
  ];

  final report = await covFuzz<Uint8List>(
    seeds: seeds,
    entry: (bytes) {
      _svc.detectMode('fuzz.bin', header: bytes);
      InternalViewerService.decodeTextForView(bytes);
      InternalViewerService.renderSafeBytes(bytes);
      InternalViewerService.renderSafeBytes(bytes, binaryMode: true);
    },
    mutate: mutateBytes,
    targetLib: 'package:crisp_cloud/services/internal_viewer_service.dart',
    isClean: (_) => false,
    iterations: 2000,
    budgetMs: 30000,
    corpusDir: '.corpus/internal_viewer',
    log: true,
  );
  report.report();
  exit(report.clean ? 0 : 1);
}
