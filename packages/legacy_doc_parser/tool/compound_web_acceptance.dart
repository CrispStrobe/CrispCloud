// SPDX-License-Identifier: MPL-2.0
// Executed by tool/verify_web.py in actual compiled JavaScript.

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/byte_source.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

import '../test/support/compound_allocation_fixture.dart';
import '../test/support/compound_size_fixture.dart';

Map<String, Object?> verifyCompoundAllocationWebCases() {
  var rejections = 0;
  void rejects(void Function() read, String label) {
    try {
      read();
    } on CfbfException {
      rejections++;
      return;
    } on FormatException {
      rejections++;
      return;
    }
    throw StateError('Accepted malformed compound allocation: $label');
  }

  for (final mutation in [
    'duplicate-fat',
    'fat-count-zero',
    'fat-count-extra',
    'difat-count-extra',
    'minifat-count-extra',
    'minifat-free-terminal',
    'directory-count',
    'directory-free-terminal',
  ]) {
    final bytes = compoundAllocationFixture(mutation);
    final before = Uint8List.fromList(bytes);
    rejects(() => CfbfFile.fromBytes(bytes), 'raw $mutation');
    rejects(() => BoundedCfbReader(bytes), 'bounded $mutation');
    _equal(bytes, before, 'source $mutation');
  }
  for (final (mutation, path) in [
    ('mini-cycle-tail', 'Small'),
    ('mini-free-tail', 'Small'),
    ('regular-cycle-tail', 'Large'),
    ('regular-free-tail', 'Large'),
    ('root-cycle-tail', 'Small'),
    ('mini-cycle-spare', 'Small'),
    ('regular-cycle-spare', 'Large'),
  ]) {
    final bytes = compoundAllocationFixture(mutation);
    final before = Uint8List.fromList(bytes);
    rejects(() => CfbfFile.fromBytes(bytes).readPath(path), 'raw $mutation');
    rejects(() => BoundedCfbReader(bytes).readPath(path), 'bounded $mutation');
    _equal(bytes, before, 'source $mutation');
  }

  var streamComparisons = 0;
  void valid(Uint8List bytes, Map<String, List<int>> streams) {
    final before = Uint8List.fromList(bytes);
    final raw = CfbfFile.fromBytes(bytes), bounded = BoundedCfbReader(bytes);
    for (final stream in streams.entries) {
      _equal(raw.readPath(stream.key)!, stream.value, 'raw ${stream.key}');
      _equal(
        bounded.readPath(stream.key)!,
        stream.value,
        'bounded ${stream.key}',
      );
      streamComparisons += 2;
    }
    _equal(bytes, before, 'valid source');
  }

  valid(compoundAllocationFixture('valid'), {
    'Small': List.generate(65, (index) => index),
    'Large': List.generate(4097, (index) => index % 251),
  });
  valid(compoundAllocationFixture('spare-capacity'), {
    'Small': [0],
    'Large': List.generate(4096, (index) => index % 251),
  });
  valid(compoundSizeFixture(version4: true), {
    'Large': List.generate(4096, (index) => index & 255),
  });
  final large = List.generate(8 * 1024 * 1024, (index) => index % 251);
  final writer = CfbfWriter()..addStream('Large', large);
  for (var index = 0; index < 130; index++) {
    writer.addStream('Small$index', [index & 255]);
  }
  valid(writer.build(), {
    'Large': large,
    'Small129': [129],
  });
  for (final size in [1, 65, 127]) {
    valid(compoundPartialMiniFixture(size), {
      'Small': List.generate(size, (index) => index & 255),
    });
  }
  final shared = compoundSharedChainFixture();
  final counted = _CountedSource(shared);
  final raw = CfbfFile.open(counted), bounded = BoundedCfbReader(shared);
  counted.views = counted.zeroLengthViews = 0;
  for (final entry in raw.entries.where((entry) => entry.isStream)) {
    rejects(() => raw.readEntry(entry), 'raw shared tail');
    rejects(() => bounded.readPath(entry.name), 'bounded shared tail');
  }
  if (counted.views != 0 || counted.zeroLengthViews != 0) {
    throw StateError('Shared tails read payload before rejecting overlap');
  }
  final overallocated = compoundOverallocatedFixture();
  final overallocatedSource = _CountedSource(overallocated);
  final regular = CfbfFile.open(overallocatedSource);
  final boundedRegular = BoundedCfbReader(overallocated);
  final expected = List.generate(4096, (index) => index % 251);
  overallocatedSource.views = overallocatedSource.zeroLengthViews = 0;
  for (var index = 0; index < 4; index++) {
    _equal(regular.readPath('Large')!, expected, 'raw overallocated stream');
    _equal(
      boundedRegular.readPath('Large')!,
      expected,
      'bounded overallocated',
    );
  }
  if (overallocatedSource.views != 32 ||
      overallocatedSource.zeroLengthViews != 0) {
    throw StateError('Valid overallocated stream reread spare payload');
  }
  return {
    'malformedCases': 16,
    'readerRejections': rejections,
    'validCases': 7,
    'streamComparisons': streamComparisons,
    'sharedTailStreams': 65,
    'sharedTailSectorReads': counted.views,
    'sharedTailZeroLengthReads': counted.zeroLengthViews,
    'overallocatedReads': 4,
    'overallocatedSectorReads': overallocatedSource.views,
    'portableIntegers': _verifyPortableIntegers(),
    'sourceUnchanged': true,
  };
}

Map<String, Object?> _verifyPortableIntegers() {
  for (final (value, bytes) in [
    (0, [0, 0, 0, 0, 0, 0, 0, 0]),
    (1, [1, 0, 0, 0, 0, 0, 0, 0]),
    (4294967295, [255, 255, 255, 255, 0, 0, 0, 0]),
    (4294967296, [0, 0, 0, 0, 1, 0, 0, 0]),
    (4294967297, [1, 0, 0, 0, 1, 0, 0, 0]),
    (9007199254740991, [255, 255, 255, 255, 255, 255, 31, 0]),
  ]) {
    final source = Uint8List.fromList(bytes);
    final cursor = ByteCursor(source);
    if (cursor.u64le() != value || cursor.offset != 8) {
      throw StateError('Portable u64 decode failed for $value');
    }
    final sink = ByteSink()..u64le(value);
    _equal(sink.takeBytes(), bytes, 'Portable u64 encode $value');
    _equal(source, bytes, 'Portable u64 source $value');
  }
  var rejectedWrites = 0;
  for (final value in [-1, 9007199254740992]) {
    final sink = ByteSink()..u8(42);
    try {
      sink.u64le(value);
    } on RangeError {
      rejectedWrites++;
    }
    _equal(sink.toBytes(), [42], 'Failed u64 write remains atomic');
    if (sink.length != 1) throw StateError('Failed u64 write advanced length');
  }
  var rejectedReads = 0;
  for (final high in [0x200000, 0x80000000, 0xffffffff]) {
    final bytes = Uint8List(8);
    ByteData.sublistView(bytes).setUint32(4, high, Endian.little);
    final before = Uint8List.fromList(bytes);
    try {
      ByteCursor(bytes).u64le();
    } on RangeError {
      rejectedReads++;
    }
    _equal(bytes, before, 'Failed u64 read preserves input');
  }
  if (rejectedReads != 3 || rejectedWrites != 2) {
    throw StateError('Portable u64 range guards did not reject every case');
  }
  final time = Uint8List.fromList(List.filled(8, 255));
  final file = CfbfFile.fromBytes(
    (CfbfWriter(modifiedFiletime: time)..addStream('Small', [3])).build(),
  );
  _equal(file.root.modifiedFiletime, time, 'Full-width raw FILETIME');
  _equal(file.readPath('Small')!, [3], 'Small stream with raw FILETIME');
  return {
    'validValues': 6,
    'readRangeRejections': rejectedReads,
    'writeRangeRejections': rejectedWrites,
    'rawFiletimePreserved': true,
  };
}

class _CountedSource extends MemoryByteSource {
  _CountedSource(super.bytes);

  var views = 0;
  var zeroLengthViews = 0;

  @override
  Uint8List view(int offset, int length) {
    views++;
    if (length == 0) zeroLengthViews++;
    return super.view(offset, length);
  }
}

void _equal(List<int> actual, List<int> expected, String label) {
  if (actual.length != expected.length) {
    throw StateError('$label length mismatch');
  }
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) {
      throw StateError('$label byte mismatch at $index');
    }
  }
}
