// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/byte_source.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';

import '../test/support/compound_header_fixture.dart';
import '../test/support/compound_property_fixture.dart';
import '../test/support/compound_root_fixture.dart';
import '../test/support/compound_tree_fixture.dart';

int _hash(List<int> bytes, [int value = 0]) {
  for (final byte in bytes) {
    value = (value * 31 + byte) % 0x100000000;
  }
  return value;
}

void _equal(List<int>? actual, List<int> expected, String label) {
  if (actual == null || actual.length != expected.length) {
    throw StateError('$label length mismatch');
  }
  for (var i = 0; i < expected.length; i++) {
    if (actual[i] != expected[i]) throw StateError('$label byte $i differs');
  }
}

/// Verify exact generated stream bytes through both APIs, repeat reads to
/// exercise caches, and account for actual source accesses independently.
Map<String, int> verifyCompoundGeneratedCase(
  int seed, {
  required bool version4,
}) {
  final fixture = version4
      ? compoundGeneratedV4(seed)
      : compoundGeneratedV3(seed);
  final before = _hash(fixture.bytes);
  final source = _CountedCompoundSource(fixture.bytes);
  final raw = CfbfFile.open(source);
  final bounded = BoundedCfbReader(fixture.bytes);
  var digest = 0, reads = 0, publicChecks = 0;
  for (final entry in fixture.streams.entries) {
    for (var repetition = 0; repetition < 3; repetition++) {
      final actual = raw.readPath(entry.key);
      _equal(actual, entry.value, 'raw/$seed/${entry.key}/$repetition');
      _equal(
        bounded.readPath(entry.key),
        entry.value,
        'bounded/$seed/${entry.key}/$repetition',
      );
      digest = _hash(actual!, digest);
      reads += 2;
    }
    final actualEntry = raw.entryByName(entry.key.split('/').last)!;
    final copied = compoundEntryCopy(actualEntry);
    _equal(raw.readEntry(copied), entry.value, 'raw copied entry');
    _equal(bounded.readEntry(copied), entry.value, 'bounded copied entry');
    reads += 2;
    for (final invalid in [
      compoundEntryCopy(actualEntry, index: -1),
      compoundEntryCopy(actualEntry, index: raw.entries.length),
      compoundEntryCopy(actualEntry, index: raw.root.index),
      compoundEntryCopy(actualEntry, type: CfbfObjectType.storage),
      compoundEntryCopy(actualEntry, streamSize: -1),
      compoundEntryCopy(actualEntry, streamSize: actualEntry.streamSize + 1),
      compoundEntryCopy(
        actualEntry,
        startSector: actualEntry.startSector == 0 ? 1 : 0,
      ),
    ]) {
      _rejects(
        () => raw.readEntry(invalid),
        'raw copied allocation must match',
      );
      _rejects(
        () => bounded.readEntry(invalid),
        'bounded copied allocation must match',
      );
      publicChecks += 2;
    }
  }
  if (source.outsideAttempts != 0 ||
      source.zeroViews != 0 ||
      before != _hash(fixture.bytes)) {
    throw StateError('Generated compound source-access invariant failed');
  }
  final sectorSize = version4 ? 4096 : 512;
  final physical = fixture.bytes.length ~/ sectorSize - 1;
  if (source.views > physical * 4 + 10) {
    throw StateError('Generated compound source reads exceeded linear bound');
  }
  return {
    'streams': fixture.streams.length,
    'reads': reads,
    'publicEntryRejections': publicChecks,
    'digest': digest,
    'views': source.views,
  };
}

Map<String, Object?> verifyCompoundPropertyAcceptance({bool enforce = true}) {
  var sinkReuseCases = 0;
  for (final alignment in [4, 8]) {
    final sink = ByteSink()..add([1, 2, 3]);
    _equal(sink.takeBytes(), [1, 2, 3], 'first sink drain');
    if (sink.length != 0) throw StateError('Drained sink has stale length');
    sink.padTo(alignment, 0xaa);
    _equal(sink.takeBytes(), [], 'empty sink padding');
    sink.u8(0x42);
    sink.padTo(alignment, 0xcc);
    _equal(sink.takeBytes(), [
      0x42,
      ...List.filled(alignment - 1, 0xcc),
    ], 'reused sink alignment');
    if (sink.length != 0) throw StateError('Reused sink has stale length');
    sinkReuseCases++;
  }
  var generated = 0, streams = 0, reads = 0, digest = 0, publicChecks = 0;
  for (final version4 in [false, true]) {
    for (var seed = 0; seed < 128; seed++) {
      final result = verifyCompoundGeneratedCase(seed, version4: version4);
      generated++;
      streams += result['streams']!;
      reads += result['reads']!;
      publicChecks += result['publicEntryRejections']!;
      digest = (digest * 31 + result['digest']!) % 0x100000000;
    }
  }
  var directoryChecks = 0;
  for (final version4 in [false, true]) {
    for (final mutation in compoundInvalidRoots) {
      final bytes = compoundRootFixture(mutation, version4: version4);
      _rejects(() => CfbfFile.fromBytes(bytes), 'raw root $mutation');
      _rejects(() => BoundedCfbReader(bytes), 'bounded root $mutation');
      directoryChecks += 2;
    }
  }
  for (final mutation in compoundInvalidTrees) {
    final bytes = compoundTreeFixture(mutation);
    _rejects(() => CfbfFile.fromBytes(bytes), 'raw tree $mutation');
    _rejects(() => BoundedCfbReader(bytes), 'bounded tree $mutation');
    directoryChecks += 2;
  }
  final treeBytes = compoundTreeFixture('valid');
  final tree = CfbfFile.fromBytes(treeBytes);
  final boundedTree = BoundedCfbReader(treeBytes);
  for (final parent in [tree.root, tree.entryByName('First')!]) {
    for (final (label, invalid) in compoundInvalidParents(
      parent,
      tree.entries.length,
    )) {
      _rejects(() => tree.childrenOf(invalid), 'raw parent $label');
      _rejects(() => tree.child(invalid, 'Alpha'), 'raw child $label');
      _rejects(() => boundedTree.childrenOf(invalid), 'bounded parent $label');
      _rejects(
        () => boundedTree.child(invalid, 'Alpha'),
        'bounded child $label',
      );
      directoryChecks += 4;
    }
  }
  var geometryChecks = 0;
  for (final variant in compoundInvalidGeometry) {
    final bytes = compoundGeometryFixture(variant);
    _rejects(() => CfbfHeader.parse(MemoryByteSource(bytes)), variant.$1);
    _rejects(() => CfbfFile.fromBytes(bytes), variant.$1);
    _rejects(() => BoundedCfbReader(bytes), variant.$1);
    geometryChecks += 3;
  }
  for (final version4 in [false, true]) {
    for (final miniFat in [false, true]) {
      final source = _CountedCompoundSource(
        compoundPhantomMetadataFixture(version4: version4, miniFat: miniFat),
      );
      _rejects(() => CfbfFile.open(source), 'phantom metadata');
      if (source.outsideAttempts != 0) {
        throw StateError('Phantom metadata touched source outside bounds');
      }
      geometryChecks++;
    }
  }
  var cases = 0, rawAccepted = 0, boundedAccepted = 0, bothAccepted = 0;
  var policyDifferences = 0, unexpected = 0, outsideAttempts = 0;
  final failures = <String>[];
  for (final version4 in [false, true]) {
    for (final mutation in compoundSeededMutations(
      seed: 0x5cfb2026,
      version4: version4,
    )) {
      cases++;
      final before = _hash(mutation.bytes);
      final source = _CountedCompoundSource(mutation.bytes);
      Map<String, List<int>?>? rawOutput, boundedOutput;
      void failure(String label, Object error) {
        unexpected++;
        if (failures.length < 24) {
          failures.add('${mutation.name}/$label: $error');
        }
      }

      try {
        final raw = CfbfFile.open(source);
        rawOutput = {
          for (final path in mutation.paths) path: raw.readPath(path),
        };
        rawAccepted++;
      } on CfbfException {
        // A structurally rejected mutation is an expected bounded outcome.
      } on FormatException {
        // Keep the rejection contract shared with the bounded wrapper.
      } catch (error) {
        failure('raw', error);
      }
      try {
        final bounded = BoundedCfbReader(mutation.bytes);
        boundedOutput = {
          for (final path in mutation.paths) path: bounded.readPath(path),
        };
        boundedAccepted++;
      } on CfbfException {
        // Requested stream validation can come from the underlying reader.
      } on FormatException {
        // Expected rejection.
      } catch (error) {
        failure('bounded', error);
      }
      if (rawOutput != null && boundedOutput != null) {
        bothAccepted++;
        for (final path in mutation.paths) {
          final a = rawOutput[path], b = boundedOutput[path];
          if (a == null || b == null) {
            if (a != b) failure('differential', 'different path existence');
          } else {
            try {
              _equal(a, b, path);
            } catch (error) {
              failure('differential', error);
            }
            digest = _hash(a, digest);
          }
        }
      } else if ((rawOutput != null) != (boundedOutput != null)) {
        // The raw reader intentionally has fewer eager stream-size checks.
        // Accepted/rejected differences are counted, not misreported as bugs.
        policyDifferences++;
      }
      outsideAttempts += source.outsideAttempts;
      if (source.outsideAttempts != 0) {
        failure('source', 'outside read attempted');
      }
      if (_hash(mutation.bytes) != before) failure('source', 'input changed');
      if (source.views > mutation.bytes.length ~/ 128 + 32) {
        failure('work', 'source views exceeded conservative linear bound');
      }
      digest =
          (digest * 31 +
              (rawOutput == null ? 0 : 1) +
              (boundedOutput == null ? 0 : 2)) %
          0x100000000;
    }
  }
  final report = <String, Object?>{
    'seed': 0x5cfb2026,
    'generatedFiles': generated,
    'byteSinkReuseCases': sinkReuseCases,
    'generatedStreams': streams,
    'exactPayloadReads': reads,
    'publicEntryRejections': publicChecks,
    'geometryRejectionChecks': geometryChecks,
    'directoryRejectionChecks': directoryChecks,
    'mutationCases': cases,
    'mutationGroups': {
      'headerGeometry': 512,
      'headerAllocation': 512,
      'directoryReferencesAndSizes': 512,
      'directoryTypesAndNameLengths': 512,
      'fatLinks': 512,
      'miniFatLinks': 512,
      'truncation': 512,
      'directoryNameUnits': 512,
    },
    'rawAccepted': rawAccepted,
    'boundedAccepted': boundedAccepted,
    'bothAccepted': bothAccepted,
    'policyDifferences': policyDifferences,
    'unexpectedFailures': unexpected,
    'outsideReadAttempts': outsideAttempts,
    'deterministicDigest': digest,
    'failures': failures,
  };
  if (enforce && unexpected != 0) {
    throw StateError('Compound mutation matrix failed: ${jsonEncode(report)}');
  }
  return report;
}

void _rejects(void Function() call, String label) {
  try {
    call();
  } on CfbfException {
    return;
  } on FormatException {
    return;
  }
  throw StateError('Malformed compound input accepted: $label');
}

class _CountedCompoundSource extends MemoryByteSource {
  _CountedCompoundSource(super.bytes);
  var views = 0, outsideAttempts = 0, zeroViews = 0;
  @override
  Uint8List view(int offset, int count) {
    views++;
    if (count == 0) zeroViews++;
    if (offset < 0 || count < 0 || offset > length - count) outsideAttempts++;
    return super.view(offset, count);
  }
}

void main(List<String> args) {
  print(
    jsonEncode(
      verifyCompoundPropertyAcceptance(
        enforce: !args.contains('--report-failures'),
      ),
    ),
  );
}
