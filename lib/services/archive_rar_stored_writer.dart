// Independently implemented from https://www.rarlab.com/technote.htm.
// Emits RAR5 method 0 (Store) only, with no proprietary compression algorithm,
// UnRAR source, external executable, or 7-Zip RAR implementation.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart';

import 'archive_rar_stored_format.dart';
import 'archive_types.dart';
import 'archive_write_model.dart';

const _attributeKeys = {
  'package.sourcePath',
  'package.order',
  'rar5.hostOs',
  'rar5.attributes',
  'rar5.compression',
  'rar5.hasCrc',
  'rar5.trailingSlash',
  'rar5.headerMtime',
  'rar5.times',
};

/// Confirms every supported metadata field after reopening the candidate.
/// This performs no payload reads. Ordinary member size/type/hash validation
/// remains the caller's responsibility. Renames intentionally change only the
/// lookup path, never the retained timestamps or platform attribute fields.
void verifyStoredRarPreservation(
  List<ArchiveWriteEntry> entries,
  ArchiveRewriteInspection actual, {
  ArchiveRewriteInspection? source,
}) {
  if (!actual.supported ||
      actual.container['package.kind'] != 'rar' ||
      actual.container['rar5.store'] != true ||
      actual.container['rar5.version'] != 5 ||
      actual.container.length != 3 ||
      actual.attributes.length != entries.length ||
      source != null &&
          (!source.supported ||
              source.container['package.kind'] != 'rar' ||
              source.container['rar5.store'] != true ||
              source.container['rar5.version'] != 5 ||
              source.container.length != 3)) {
    rarStoredError('The RAR5 Store preservation profile changed.');
  }
  validateArchiveWriteEntries(entries, maxEntries: rarStoredMaxEntries);
  for (final entry in entries) {
    validateRarStoredPath(entry.path);
    final retained = entry.attributes.isEmpty
        ? source?.attributes[entry.path] ?? const <String, Object?>{}
        : entry.attributes;
    final plan = _plan(entry, retained);
    final wanted = <String, Object?>{
      'rar5.hostOs': plan.host,
      'rar5.attributes': plan.attributes,
      'rar5.compression': plan.compression,
      'rar5.hasCrc': plan.hasCrc,
      'rar5.trailingSlash': plan.name.last == 0x2f,
      if (plan.headerMtime != null) 'rar5.headerMtime': plan.headerMtime,
      if (plan.times != null) 'rar5.times': plan.times!.toAttributes(),
    };
    final found = actual.attributes[entry.path];
    if (found == null ||
        !_sameMetadata(wanted, {
          for (final item in found.entries)
            if (item.key != 'package.order' && item.key != 'package.sourcePath')
              item.key: item.value,
        })) {
      rarStoredError(
        'Repacked RAR5 metadata could not be preserved: ${entry.path}',
      );
    }
  }
}

bool _sameMetadata(Object? first, Object? second) {
  if (first is Map && second is Map) {
    return first.length == second.length &&
        first.entries.every(
          (item) =>
              second.containsKey(item.key) &&
              _sameMetadata(item.value, second[item.key]),
        );
  }
  return first == second;
}

/// Writes an unpublished RAR5 Store archive with bounded memory/backpressure.
/// Entries must open repeatable captured streams: a first pass obtains CRC and
/// SHA-256; the second emits bytes and independently confirms both. A failure
/// can leave partial candidate output; verified publication owns replacement.
/// Retained entries carry their inspection attributes, including after rename.
Future<void> writeStoredRarArchive(
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  required int maxOutputBytes,
  ArchiveRewriteInspection? source,
  bool Function()? isCancelled,
}) async {
  if (maxOutputBytes <= 0 || maxOutputBytes > kArchiveStreamingLimit) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  void check() {
    if (isCancelled?.call() ?? false) {
      rarStoredError('RAR5 writing was cancelled.');
    }
  }

  check();
  if (source != null &&
      (!source.supported ||
          source.container['package.kind'] != 'rar' ||
          source.container['rar5.store'] != true ||
          source.container['rar5.version'] != 5 ||
          source.container.keys.any(
            (key) => !const {
              'package.kind',
              'rar5.store',
              'rar5.version',
            }.contains(key),
          ))) {
    rarStoredError(
      source.reason ?? 'The RAR5 Store inspection is incompatible.',
    );
  }
  validateArchiveWriteEntries(entries, maxEntries: rarStoredMaxEntries);
  final main = rarStoredHeader(1, rarStoredVint(0));
  final end = rarStoredHeader(5, rarStoredVint(0));
  var total = rarStoredSignature.length + main.length + end.length;
  var metadata = total, expanded = 0, nameBytes = 0;
  final plans = <_Plan>[];
  for (final entry in entries) {
    check();
    validateRarStoredPath(entry.path);
    final attributes = entry.attributes.isEmpty
        ? source?.attributes[entry.path] ?? const <String, Object?>{}
        : entry.attributes;
    final plan = _plan(entry, attributes);
    nameBytes += plan.name.length;
    final size = plan.header(0).length;
    metadata += size;
    total += size + entry.size;
    expanded += entry.size;
    if (metadata > rarStoredMaxMetadataBytes ||
        nameBytes > 8 * 1024 * 1024 ||
        total > maxOutputBytes ||
        expanded > kArchiveStreamingLimit) {
      rarStoredError(
        'RAR5 Store output exceeds its supported size or metadata limit.',
      );
    }
    plans.add(plan);
    if (plans.length % 512 == 0) await Future<void>.delayed(Duration.zero);
  }
  if (total > maxOutputBytes) {
    rarStoredError('RAR5 Store output exceeds its size limit.');
  }

  var written = 0, chunks = 0;
  Future<void> cooperate() async {
    if (++chunks % 16 == 0) await Future<void>.delayed(Duration.zero);
    check();
  }

  Future<void> emit(List<int> bytes) async {
    check();
    if (bytes.length > maxOutputBytes - written) {
      rarStoredError('RAR5 Store output exceeds its size limit.');
    }
    for (var at = 0; at < bytes.length; at += rarStoredChunkBytes) {
      check();
      final stop = at + rarStoredChunkBytes < bytes.length
          ? at + rarStoredChunkBytes
          : bytes.length;
      await sink(Uint8List.fromList(bytes.sublist(at, stop)));
      written += stop - at;
      await cooperate();
    }
  }

  await emit(rarStoredSignature);
  await emit(main);
  for (final plan in plans) {
    check();
    if (plan.entry.isDirectory) {
      await emit(plan.header(0));
      continue;
    }
    final before = _DigestSink();
    final firstHash = sha256.startChunkedConversion(before);
    var firstCrc = 0;
    try {
      await for (final chunk in plan.entry.openRead(
        chunkSize: rarStoredChunkBytes,
      )) {
        check();
        firstCrc = getCrc32(chunk, firstCrc);
        firstHash.add(chunk);
        await cooperate();
      }
    } finally {
      firstHash.close();
    }
    check();
    await emit(plan.header(firstCrc));
    final after = _DigestSink();
    final secondHash = sha256.startChunkedConversion(after);
    var secondCrc = 0;
    try {
      await for (final chunk in plan.entry.openRead(
        chunkSize: rarStoredChunkBytes,
      )) {
        check();
        secondCrc = getCrc32(chunk, secondCrc);
        secondHash.add(chunk);
        await emit(chunk);
      }
    } finally {
      secondHash.close();
    }
    if (firstCrc != secondCrc ||
        before.value == null ||
        before.value != after.value) {
      rarStoredError(
        'The captured RAR5 member changed between reads: ${plan.entry.path}',
      );
    }
  }
  await emit(end);
  check();
  if (written != total) {
    rarStoredError('RAR5 Store output length does not match its plan.');
  }
}

class _Plan {
  const _Plan(
    this.entry,
    this.name,
    this.host,
    this.attributes,
    this.compression,
    this.hasCrc,
    this.headerMtime,
    this.times,
  );
  final ArchiveWriteEntry entry;
  final Uint8List name;
  final int host, attributes, compression;
  final bool hasCrc;
  final int? headerMtime;
  final RarStoredTimes? times;

  Uint8List header(int crc) {
    final flags =
        (entry.isDirectory ? 1 : 0) |
        (headerMtime == null ? 0 : 2) |
        (hasCrc ? 4 : 0);
    final fields = BytesBuilder(copy: false)
      ..add(rarStoredVint(flags))
      ..add(rarStoredVint(entry.size))
      ..add(rarStoredVint(attributes));
    if (headerMtime != null) fields.add(rarStoredUint32(headerMtime!));
    if (hasCrc) fields.add(rarStoredUint32(crc));
    fields
      ..add(rarStoredVint(compression))
      ..add(rarStoredVint(host))
      ..add(rarStoredVint(name.length))
      ..add(name);
    return rarStoredHeader(
      2,
      fields.takeBytes(),
      extra: times == null ? null : rarStoredExtra(3, times!.encode()),
      dataSize: entry.size,
    );
  }
}

int _integer(Map<String, Object?> attrs, String key, int fallback, int max) {
  final value = attrs[key] ?? fallback;
  if (value is! int || value < 0 || value > max) {
    rarStoredError('Invalid preserved RAR5 field: $key');
  }
  return value;
}

_Plan _plan(ArchiveWriteEntry entry, Map<String, Object?> attrs) {
  if (attrs.keys.any((key) => !_attributeKeys.contains(key))) {
    rarStoredError('Unknown RAR5 member metadata cannot be rewritten.');
  }
  final originalPath = attrs['package.sourcePath'];
  if (originalPath != null) {
    if (originalPath is! String) {
      rarStoredError('Invalid preserved RAR5 source path.');
    }
    validateRarStoredPath(originalPath);
  }
  _integer(attrs, 'package.order', 0, rarStoredMaxEntries);
  final retained = attrs.keys.any((key) => key.startsWith('rar5.'));
  if (retained &&
      !const {
        'rar5.hostOs',
        'rar5.attributes',
        'rar5.compression',
        'rar5.hasCrc',
        'rar5.trailingSlash',
      }.every(attrs.containsKey)) {
    rarStoredError('Incomplete preserved RAR5 metadata.');
  }
  final host = _integer(attrs, 'rar5.hostOs', 1, 1);
  final type = entry.isDirectory ? 0x4000 : 0x8000;
  var attributes = _integer(
    attrs,
    'rar5.attributes',
    type | (entry.isDirectory ? 0x1ed : 0x1a4),
    0xffffffff,
  );
  final compression = _integer(attrs, 'rar5.compression', 0, 0x7fff);
  if (compression & 0x3ff != 0 || (compression & 0x7c00) ~/ 0x400 > 15) {
    rarStoredError('Only uncompressed RAR5 Store entries can be written.');
  }
  final hasCrc = attrs['rar5.hasCrc'] ?? !entry.isDirectory;
  final trailingSlash = attrs['rar5.trailingSlash'] ?? false;
  if (hasCrc is! bool ||
      !entry.isDirectory && !hasCrc ||
      trailingSlash is! bool ||
      trailingSlash && !entry.isDirectory) {
    rarStoredError('Invalid preserved RAR5 file flags.');
  }
  if (host == 1) {
    if (attributes & ~0xffff != 0 ||
        attributes & 0xf000 != 0 && attributes & 0xf000 != type ||
        attributes & 0xc00 != 0) {
      rarStoredError(
        'RAR5 Unix attributes require an ordinary file or directory.',
      );
    }
    final requested = entry.mode;
    if (requested != null) {
      if (requested < 0 ||
          requested > 0xffff ||
          requested & 0xc00 != 0 ||
          requested & 0xf000 != 0 && requested & 0xf000 != type) {
        rarStoredError('Unsupported RAR5 Unix mode.');
      }
      attributes = (attributes & ~0xfff) | (requested & 0xfff);
    }
  } else {
    if (attributes & 0x400 != 0 ||
        (attributes & 0x10 != 0) != entry.isDirectory ||
        entry.mode != null) {
      rarStoredError(
        'RAR5 Windows attributes cannot represent this entry or Unix mode edit.',
      );
    }
  }
  int? headerMtime;
  if (attrs.containsKey('rar5.headerMtime')) {
    headerMtime = _integer(attrs, 'rar5.headerMtime', 0, 0xffffffff);
  }
  var times = attrs['rar5.times'] == null
      ? null
      : RarStoredTimes.fromAttributes(attrs['rar5.times']!);
  final originalModified =
      times?.modified ??
      (headerMtime == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              headerMtime * 1000,
              isUtc: true,
            ));
  final modified = entry.modified;
  final sameTime = modified == null
      ? originalModified == null
      : originalModified != null && modified.isAtSameMomentAs(originalModified);
  if (!sameTime) {
    if (modified == null) {
      rarStoredError(
        'A retained RAR5 modification time cannot be silently removed.',
      );
    }
    final micros = modified.microsecondsSinceEpoch;
    final seconds = micros ~/ 1000000;
    headerMtime = micros >= 0 && seconds <= 0xffffffff ? seconds : null;
    if (times != null || headerMtime == null || micros % 1000000 != 0) {
      times = (times ?? RarStoredTimes(0, const {}, const {})).withModified(
        modified,
      );
    }
  }
  final name = Uint8List.fromList(
    utf8.encode('${entry.path}${trailingSlash ? '/' : ''}'),
  );
  return _Plan(
    entry,
    name,
    host,
    attributes,
    compression,
    hasCrc,
    headerMtime,
    times,
  );
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
