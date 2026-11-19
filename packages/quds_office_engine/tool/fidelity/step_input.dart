import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/src/automation/operations/step_input.dart';
import 'package:quds_office_engine/src/automation/operations/step_input.dart'
    as operations;

export 'package:quds_office_engine/src/automation/operations/step_input.dart'
    show OfficeMacroAssetResolver, StepInput;

List<Map<String, Object?>> readSteps(String path) {
  final Object? input = jsonDecode(File(path).readAsStringSync());
  if (input is! List<Object?>) {
    throw const FormatException('Steps must be a JSON array');
  }
  return <Map<String, Object?>>[
    for (final value in input)
      if (value is Map<String, Object?>)
        value
      else
        throw const FormatException('Every step must be a JSON object'),
  ];
}

/// Trusted CLI assets are relative to the scenario file, or absolute paths.
OfficeMacroAssetResolver fidelityAssetResolver(String? assetDirectory) =>
    (String path) {
      final file = File(path).isAbsolute || assetDirectory == null
          ? File(path)
          : File('$assetDirectory/$path');
      return file.readAsBytesSync();
    };

/// Compatibility wrapper for callers of the fidelity tooling.
Uint8List readPicture(StepInput step, String? assetDirectory) =>
    operations.readPicture(step, fidelityAssetResolver(assetDirectory));

/// Write only after all edits and serialization succeed, then atomically rename.
void writeOutput(String path, Uint8List bytes) {
  final target = File(path);
  target.parent.createSync(recursive: true);
  final temporary = File(
    '$path.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    temporary.writeAsBytesSync(bytes, flush: true);
    temporary.renameSync(path);
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}
