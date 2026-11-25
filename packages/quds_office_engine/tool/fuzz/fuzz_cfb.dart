import 'dart:io';
import 'dart:typed_data';

import 'package:covfuzz/covfuzz.dart';

import 'package:quds_office_engine/quds_office_engine.dart';

Uint8List _seed() {
  final writer = CfbfWriter()
    ..addStream('__properties_version1.0', Uint8List(32))
    ..addStream(
      'Data',
      Uint8List.fromList(List<int>.generate(5000, (i) => i % 251)),
    );
  return writer.build();
}

void _parse(Uint8List bytes) {
  try {
    final reader = BoundedCfbReader(bytes);
    for (final path in const <String>[
      'Data',
      '__properties_version1.0',
      'Missing/child',
    ]) {
      try {
        reader.readPath(path);
      } on FormatException {
        // Per-stream rejection is clean; the reader must remain usable.
      }
    }
  } on FormatException {
    // Typed construction/namespace rejection.
  } on CfbfException {
    // Typed sector rejection.
  }
}

void main(List<String> args) {
  final seed = _seed();
  _parse(seed);
  final report = fuzz<Uint8List>(
    seeds: <Uint8List>[seed],
    entry: _parse,
    mutate: mutateBytes,
    // The entry converts documented CFBF rejections to a return. Any escape
    // (RangeError, StateError, unterminated regex, etc.) is a finding.
    isClean: (_) => false,
    iterations: 100000,
    budgetMs: int.tryParse(args.firstOrNull ?? '') ?? 30000,
    stressors: <Uint8List>[
      Uint8List(0),
      Uint8List.fromList(<int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]),
    ],
  );
  exit(report.report());
}
