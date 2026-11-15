// SPDX-License-Identifier: MIT
// Actual Dart VM / compiled-JavaScript acceptance over independently authored
// Python/Pillow PNG images and deliberately malformed surrounding data.
import 'dart:convert';

import 'package:archive/archive.dart' as codecs;
import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'package:crisp_cloud/services/archive_png_carving_service.dart';
import 'package:crisp_cloud/services/archive_types.dart';

import 'png_carving_reference_data.dart';

var _checks = 0;
void check(bool condition, String message) {
  _checks++;
  if (!condition) throw StateError(message);
}

Future<void> main(List<String> arguments) async {
  final manifest =
      jsonDecode(pngCarvingReferenceManifestJson) as Map<String, dynamic>;
  final cases = manifest['cases'] as Map<String, dynamic>;
  final results = <String, Object>{};
  final candidates = <String, String>{};
  for (final name in pngCarvingReferenceData.keys) {
    final input = pngCarvingReferenceBytes(name);
    final row = cases[name] as Map<String, dynamic>;
    final expected = (row['candidates'] as List).cast<Map<String, dynamic>>();
    check(
      input.length == row['bytes'],
      'Independent source size differs: $name',
    );
    check(
      sha256.convert(input).toString() == row['sha256'],
      'Independent source hash differs: $name',
    );
    final source = koni.MemoryByteSource(input, name: 'reference-$name.img');
    final report = await scanArchivePngCarving(source);
    await source.close();
    check(
      report.sourceSha256 == row['sha256'],
      'Captured source hash differs: $name',
    );
    check(
      report.stopReason == ArchivePngCarvingStopReason.endOfInput,
      'Incomplete fixture scan: $name',
    );
    check(report.scannedBytes == input.length, 'Coverage differs: $name');
    check(
      report.candidates.length == expected.length,
      'Unexpected candidate count: $name',
    );
    for (var index = 0; index < expected.length; index++) {
      final candidate = report.candidates[index];
      final exp = expected[index];
      check(candidate.offset == exp['offset'], 'Offset differs: $name/$index');
      check(
        candidate.status.name == exp['status'],
        'Status differs: $name/$index: ${candidate.status.name}',
      );
      check(
        candidate.reason?.name == exp['reason'],
        'Reason differs: $name/$index: ${candidate.reason?.name}',
      );
      if (candidate.isRecoverable) {
        check(
          candidate.endOffset == exp['endExclusive'],
          'Boundary differs: $name/$index',
        );
        check(
          candidate.sha256 == exp['sha256'],
          'PNG hash differs: $name/$index',
        );
        check(
          candidate.width == exp['width'] && candidate.height == exp['height'],
          'Dimensions differ: $name/$index',
        );
      } else {
        var refused = false;
        try {
          await recoverArchivePngCarving(
            report,
            selectedOffsets: {candidate.offset},
          );
        } on ArchiveViewException {
          refused = true;
        }
        check(refused, 'Unvalidated candidate could be selected: $name/$index');
      }
    }
    final selected = report.recoverableCandidates.map((c) => c.offset).toSet();
    final result = await recoverArchivePngCarving(
      report,
      selectedOffsets: selected,
    );
    check(
      result.sourceSha256 == report.sourceSha256,
      'Source binding differs: $name',
    );
    check(
      sha256.convert(result.bytes).toString() == result.sha256,
      'ZIP hash differs: $name',
    );
    final zip = codecs.ZipDecoder().decodeBytes(result.bytes, verify: true);
    check(zip.length == selected.length + 1, 'ZIP member count differs: $name');
    check(
      zip.last.name == 'recovery-report.json',
      'Machine-readable report missing: $name',
    );
    for (final expectedFile in expected.where(
      (c) => c['status'] == 'recoverable',
    )) {
      final entry = zip.find(expectedFile['outputName'] as String);
      check(entry != null, 'Selected image missing: $name');
      check(
        sha256.convert(entry!.readBytes()!).toString() ==
            expectedFile['sha256'],
        'Recovered PNG bytes differ: $name',
      );
    }
    final exported = jsonDecode(utf8.decode(zip.last.readBytes()!)) as Map;
    check(
      exported['sourceSha256'] == report.sourceSha256,
      'Report source hash differs: $name',
    );
    check(
      (exported['unreadableRanges'] as List).isEmpty,
      'Invented unreadable coverage: $name',
    );
    check(
      (exported['unscannedRanges'] as List).isEmpty,
      'Invented unscanned coverage: $name',
    );
    check(
      sha256.convert(input).toString() == row['sha256'],
      'Carving changed caller bytes: $name',
    );
    results[name] = {
      'candidates': report.candidates.length,
      'recovered': selected.length,
      'sourceSha256': report.sourceSha256,
      'outputSha256': result.sha256,
    };
    candidates[name] = base64Encode(result.bytes);
  }
  // ignore: avoid_print
  print(
    jsonEncode({
      'profile': 'png-8bit-noninterlaced-v1',
      'groups': results.length,
      'checks': _checks,
      'referenceCases': results,
      if (arguments.contains('--emit-candidates')) 'candidates': candidates,
    }),
  );
}
