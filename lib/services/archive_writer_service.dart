import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import '../models/archive_endpoint.dart';
import 'archive_compression_writer.dart';
import 'archive_iso_writer.dart';
import 'archive_package_writers.dart';
import 'archive_tar_writer.dart';
import 'archive_types.dart';
import 'archive_write_model.dart';
import 'archive_zip_metadata.dart';

/// Dispatches only explicit writer formats. A filename is never allowed to
/// select a fallback TAR writer for an unsupported package or compression.
Future<void> writeArchiveEntries(
  ArchiveEndpointFormat format,
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  ArchiveRewriteInspection? source,
  ArchiveCompressionKind? compression,
  bool singlePayload = false,
  Uint8List? gzipHeader,
  int xzCheck = 4,
  int level = 6,
  String? password,
  bool encryptNames = false,
  int maxOutputBytes = 256 * 1024 * 1024,
  bool Function()? isCancelled,
}) async {
  void check() {
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('Archive writing was cancelled.');
    }
  }

  check();
  validateArchiveWriteEntries(entries);
  if (maxOutputBytes <= 0 || maxOutputBytes > 2 * 1024 * 1024 * 1024) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  final compressedLimit = maxOutputBytes < kArchiveReadLimit
      ? maxOutputBytes
      : kArchiveReadLimit;
  final expectedCompression = switch (format) {
    ArchiveEndpointFormat.tarGzip ||
    ArchiveEndpointFormat.gzip => ArchiveCompressionKind.gzip,
    ArchiveEndpointFormat.tarBzip2 ||
    ArchiveEndpointFormat.bzip2 => ArchiveCompressionKind.bzip2,
    ArchiveEndpointFormat.tarXz ||
    ArchiveEndpointFormat.xz => ArchiveCompressionKind.xz,
    ArchiveEndpointFormat.tarZstd ||
    ArchiveEndpointFormat.zstd => ArchiveCompressionKind.zstd,
    ArchiveEndpointFormat.tarLz4 ||
    ArchiveEndpointFormat.lz4 => ArchiveCompressionKind.lz4,
    ArchiveEndpointFormat.tarLzma ||
    ArchiveEndpointFormat.lzma => ArchiveCompressionKind.lzma,
    _ => null,
  };
  final expectedSingle = const {
    ArchiveEndpointFormat.gzip,
    ArchiveEndpointFormat.bzip2,
    ArchiveEndpointFormat.xz,
    ArchiveEndpointFormat.zstd,
    ArchiveEndpointFormat.lz4,
    ArchiveEndpointFormat.lzma,
  }.contains(format);
  if (compression != expectedCompression || singlePayload != expectedSingle) {
    throw const ArchiveViewException(
      'The requested writer and compression wrapper do not match.',
    );
  }
  if (format == ArchiveEndpointFormat.readOnly || source?.supported == false) {
    throw ArchiveViewException(source?.reason ?? 'No writer is available.');
  }
  if (password != null &&
          format != ArchiveEndpointFormat.zip &&
          format != ArchiveEndpointFormat.sevenZip ||
      encryptNames &&
          (format != ArchiveEndpointFormat.sevenZip || password == null)) {
    throw const ArchiveViewException(
      'This writer cannot preserve the requested protection.',
    );
  }
  var written = 0;
  Future<void> emit(List<int> bytes) async {
    for (var offset = 0; offset < bytes.length; offset += 256 * 1024) {
      check();
      final end = offset + 256 * 1024 < bytes.length
          ? offset + 256 * 1024
          : bytes.length;
      if (end - offset > maxOutputBytes - written) {
        throw const ArchiveViewException(
          'The packed archive exceeds its output limit.',
        );
      }
      await sink(Uint8List.fromList(bytes.sublist(offset, end)));
      written += end - offset;
      check();
    }
  }

  if (format == ArchiveEndpointFormat.iso) {
    await writeIsoArchive(
      entries,
      sink: emit,
      source: source,
      maxOutputBytes: maxOutputBytes,
      isCancelled: isCancelled,
    );
    return;
  }
  if (const {
    ArchiveEndpointFormat.ar,
    ArchiveEndpointFormat.cpio,
    ArchiveEndpointFormat.xar,
  }.contains(format)) {
    await writePackageArchive(
      source?.container['package.kind'] as String? ?? format.name,
      entries,
      sink: emit,
      source: source,
      maxOutputBytes: maxOutputBytes,
      isCancelled: isCancelled,
    );
    return;
  }
  if (singlePayload) {
    if (compression == null ||
        entries.length != 1 ||
        entries.single.isDirectory) {
      throw const ArchiveViewException(
        'A compressed file requires exactly one regular payload.',
      );
    }
    final bytes = await entries.single.read();
    check();
    await emit(
      encodeArchiveCompression(
        bytes,
        compression,
        level: level,
        maxOutputBytes: compressedLimit,
        gzipHeader: gzipHeader,
        xzCheck: xzCheck,
      ),
    );
    return;
  }
  if (const {
    ArchiveEndpointFormat.tar,
    ArchiveEndpointFormat.tarGzip,
    ArchiveEndpointFormat.tarBzip2,
    ArchiveEndpointFormat.tarXz,
    ArchiveEndpointFormat.tarZstd,
    ArchiveEndpointFormat.tarLz4,
    ArchiveEndpointFormat.tarLzma,
  }.contains(format)) {
    if (compression == null) {
      await writeTarArchive(
        entries,
        sink: emit,
        source: source,
        maxOutputBytes: maxOutputBytes,
        isCancelled: isCancelled,
      );
    } else {
      final tar = await collectArchiveWrite(
        (sink) => writeTarArchive(
          entries,
          sink: sink,
          source: source,
          maxOutputBytes: kArchiveReadLimit,
          isCancelled: isCancelled,
        ),
        maxBytes: kArchiveReadLimit,
      );
      check();
      await emit(
        encodeArchiveCompression(
          tar,
          compression,
          level: level,
          maxOutputBytes: compressedLimit,
          gzipHeader: gzipHeader,
          xzCheck: xzCheck,
        ),
      );
    }
    return;
  }
  final writerFormat = switch (format) {
    ArchiveEndpointFormat.zip => const koni.ZipWriteFormat(),
    ArchiveEndpointFormat.sevenZip => const koni.SevenZWriteFormat(),
    _ => throw const ArchiveViewException(
      'Unsupported archive writer dispatch.',
    ),
  };
  final output = _WriterSink(maxOutputBytes, check);
  final writer = koni.Archive.create(
    output,
    format: writerFormat,
    options: koni.ArchiveWriteOptions(
      password: password,
      encryptHeader: encryptNames,
    ),
  );
  try {
    var total = 0;
    for (final entry in entries) {
      check();
      final spec = koni.ArchiveEntrySpec(
        path: entry.path,
        type: entry.isDirectory
            ? koni.ArchiveEntryType.directory
            : koni.ArchiveEntryType.file,
        modified: entry.modified?.toUtc(),
        posixMode: entry.mode,
      );
      if (entry.isDirectory) {
        await writer.addEntry(spec);
      } else {
        total += entry.size;
        if (total > 256 * 1024 * 1024) {
          throw const ArchiveViewException('Archive contents exceed 256 MiB.');
        }
        await writer.addBytes(spec, await entry.read());
      }
    }
    await writer.close();
    check();
    var bytes = output.takeBytes();
    if (format == ArchiveEndpointFormat.zip) {
      bytes = preserveArchiveZipTimes(bytes, {
        for (final entry in entries) entry.path: entry.modified,
      });
    }
    await emit(bytes);
  } finally {
    await output.close();
  }
}

class _WriterSink implements koni.ByteSink {
  _WriterSink(this.limit, this.check);
  final int limit;
  final void Function() check;
  final _bytes = BytesBuilder(copy: false);
  var _closed = false;

  @override
  int get length => _bytes.length;

  @override
  Future<void> add(Uint8List bytes) async {
    check();
    if (_closed) throw StateError('Archive output is closed.');
    if (bytes.length > limit - _bytes.length) {
      throw const ArchiveViewException(
        'Packed archive exceeds its size limit.',
      );
    }
    _bytes.add(Uint8List.fromList(bytes));
  }

  Uint8List takeBytes() => _bytes.takeBytes();

  @override
  Future<void> close() async {
    _closed = true;
  }
}
