// SPDX-License-Identifier: MIT
// Original acceptance using independent Python zipfile reference streams.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_zip_recovery_service.dart';

import 'archive_zip_recovery_reference_data.dart';

var _checks = 0;
void check(bool condition, String message) {
  _checks++;
  if (!condition) {
    throw StateError(message);
  }
}

class ZipReferenceSource implements koni.ByteSource {
  ZipReferenceSource(this.bytes);
  final Uint8List bytes;
  var closed = false;
  var reads = 0;
  @override
  int get length => bytes.length;
  @override
  String get name => 'independent.zip';
  @override
  Future<Uint8List> read(int offset, int length) async {
    check(
      !closed && offset >= 0 && offset <= bytes.length - length,
      'Invalid recovery source read',
    );
    check(length <= 64 * 1024, 'Recovery capture request exceeds bound');
    reads++;
    return Uint8List.sublistView(bytes, offset, offset + length);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

Future<Map<String, String>> verify(ArchiveZipRecoveryResult result) async {
  check(
    sha256.convert(result.bytes).toString() == result.sha256,
    'Candidate SHA does not match',
  );
  final archive = await koni.Archive.open(koni.MemoryByteSource(result.bytes));
  try {
    final hashes = <String, String>{};
    for (final member in archive.entries.where((entry) => !entry.isDirectory)) {
      final bytes = await archive.readBytes(member, maxSize: 1024 * 1024);
      final hash = sha256.convert(bytes).toString();
      check(
        hash == zipRecoveryReferencePayloadHashes[member.path],
        'Recovered payload differs: ${member.path}',
      );
      hashes[member.path] = hash;
    }
    return hashes;
  } finally {
    await archive.close();
  }
}

Future<void> main(List<String> arguments) async {
  final results = <String, Object>{};
  final candidates = <String, String>{};
  for (final name in zipRecoveryReferenceData.keys) {
    final input = zipRecoveryReferenceBytes(name);
    final before = sha256.convert(input).toString();
    final source = ZipReferenceSource(input);
    final phases = <ArchiveZipRecoveryPhase>{};
    final report = await scanArchiveZipRecovery(
      source,
      onProgress: (progress) => phases.add(progress.phase),
    );
    check(!source.closed, 'Scanning closed a caller-owned source');
    check(report.sourceSha256 == before, 'Captured source SHA differs');
    check(sha256.convert(input).toString() == before, 'Scan changed original');
    final names = report.recoverableEntries.map((entry) => entry.name).toList()
      ..sort();
    final expected = [...zipRecoveryReferenceExpected[name]!]..sort();
    check(
      jsonEncode(names) == jsonEncode(expected),
      'Unexpected recoverable entries $name: $names expected $expected',
    );
    if (names.isEmpty) {
      var rejected = false;
      try {
        await recoverArchiveZip(report);
      } on ArchiveViewException {
        rejected = true;
      }
      check(rejected, 'Empty/unproven selection produced a ZIP');
      results[name] = {'recoverable': names, 'stop': report.stopReason.name};
    } else {
      final result = await recoverArchiveZip(
        report,
        onProgress: (progress) => phases.add(progress.phase),
      );
      check(result.sourceSha256 == before, 'Recovered source binding differs');
      check(
        phases.contains(ArchiveZipRecoveryPhase.scanning) &&
            phases.contains(ArchiveZipRecoveryPhase.recovering) &&
            phases.contains(ArchiveZipRecoveryPhase.verifying),
        'Missing recovery phase',
      );
      results[name] = {
        'recoverable': names,
        'stop': report.stopReason.name,
        'hashes': await verify(result),
      };
      candidates[name] = base64Encode(result.bytes);
      var immutable = false;
      try {
        result.bytes[0] ^= 1;
      } on UnsupportedError {
        immutable = true;
      }
      check(immutable, 'Candidate bytes were mutable');
    }
    await source.close();
  }

  final input = zipRecoveryReferenceBytes('missing-directory');
  final source = ZipReferenceSource(input);
  final report = await scanArchiveZipRecovery(source);
  input.fillRange(0, input.length, 0);
  final selected = <int>{report.recoverableEntries.first.offset};
  final result = await recoverArchiveZip(
    report,
    selectedOffsets: selected,
    checkpoint: () async {
      selected.clear();
    },
  );
  check(
    result.entries.length == 1 && result.entries.single.name == 'stored.txt',
    'Call-time selection changed during checkpoint',
  );
  check((await verify(result)).length == 1, 'Subset candidate differs');
  check(!source.closed, 'Recovery closed caller source');
  await source.close();

  var limited = false;
  try {
    await recoverArchiveZip(report, maxOutputBytes: 32);
  } on ArchiveViewException {
    limited = true;
  }
  check(limited, 'Candidate exceeded output limit');
  var cancelled = false;
  try {
    await recoverArchiveZip(report, isCancelled: () => true);
  } on ArchiveZipRecoveryCancelled {
    cancelled = true;
  }
  check(cancelled, 'Pre-cancelled recovery proceeded');
  // ignore: avoid_print
  print(
    jsonEncode({
      'groups': zipRecoveryReferenceData.length + 3,
      'checks': _checks,
      'referenceCases': results,
      'sourceSnapshotAndSelectionImmutable': true,
      'candidateLimitAndCancellation': true,
      if (arguments.contains('--emit-candidates')) 'candidates': candidates,
    }),
  );
}
