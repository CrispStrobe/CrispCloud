import 'dart:io';
import 'dart:typed_data';

import 'package:covfuzz/covfuzz.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

void main(List<String> args) {
  final seeds = <Uint8List>[
    RawDeflate.deflate(
      Uint8List.fromList('Quds Office DEFLATE seed'.codeUnits),
    ),
    RawDeflate.deflate(Uint8List(4096), level: 9),
    RawDeflate.deflate(<int>[], level: 0),
  ];
  final report = fuzz<Uint8List>(
    seeds: seeds,
    entry: (bytes) {
      RawDeflate.inflate(bytes, maxOutputBytes: 1024 * 1024);
    },
    mutate: mutateBytes,
    isClean: (error) => error is ZipDeflateException,
    iterations: 200000,
    budgetMs: int.tryParse(args.firstOrNull ?? '') ?? 30000,
    stressors: <Uint8List>[
      Uint8List(0),
      Uint8List.fromList(<int>[0x03, 0x00]),
      Uint8List.fromList(<int>[0x05, 0x00, 0x00, 0xFF, 0xFF]),
      Uint8List.fromList(List<int>.filled(64, 0xFF)),
    ],
  );
  exit(report.report());
}
