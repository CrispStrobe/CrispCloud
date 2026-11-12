import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import '../models/file_item.dart';
import '../models/archive_endpoint.dart';
import 'archive_compression_writer.dart';
import 'archive_disk_verification.dart';
import 'archive_dmg_writer.dart';
import 'archive_hfs_writer.dart';
import 'archive_iso_writer.dart';
import 'archive_output_spool.dart';
import 'archive_write_model.dart';
import 'archive_writer_service.dart';
import 'archive_zip_package_policy.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';
import 'file_operation_service.dart';

enum ArchiveCreationFormat {
  zip,
  sevenZip,
  tar,
  tarGzip,
  tarBzip2,
  tarXz,
  tarZstd,
  gzip,
  bzip2,
  xz,
  zstd,
  ar,
  cpio,
  xar,
  iso,
  hfsx,
  dmg,
  cbz,
  cb7,
  cbt,
  kmz,
  jar,
  war,
  ear,
}

extension ArchiveCreationFormatDetails on ArchiveCreationFormat {
  String get extension => switch (this) {
    ArchiveCreationFormat.sevenZip => '.7z',
    ArchiveCreationFormat.tarGzip => '.tar.gz',
    ArchiveCreationFormat.tarBzip2 => '.tar.bz2',
    ArchiveCreationFormat.tarXz => '.tar.xz',
    ArchiveCreationFormat.tarZstd => '.tar.zst',
    ArchiveCreationFormat.gzip => '.gz',
    ArchiveCreationFormat.bzip2 => '.bz2',
    ArchiveCreationFormat.zstd => '.zst',
    _ => '.$name',
  };

  String get label => switch (this) {
    ArchiveCreationFormat.sevenZip => '7z',
    ArchiveCreationFormat.tarGzip => 'TAR.GZ',
    ArchiveCreationFormat.tarBzip2 => 'TAR.BZ2',
    ArchiveCreationFormat.tarXz => 'TAR.XZ',
    ArchiveCreationFormat.tarZstd => 'TAR.ZST',
    ArchiveCreationFormat.gzip => 'gzip — one file',
    ArchiveCreationFormat.bzip2 => 'bzip2 — one file',
    ArchiveCreationFormat.xz => 'XZ — one file',
    ArchiveCreationFormat.zstd => 'Zstandard — one file',
    ArchiveCreationFormat.hfsx => 'HFSX data image',
    ArchiveCreationFormat.dmg => 'DMG (HFSX data volume)',
    ArchiveCreationFormat.iso => 'ISO data image',
    ArchiveCreationFormat.ar => 'AR — flat files',
    ArchiveCreationFormat.jar ||
    ArchiveCreationFormat.war ||
    ArchiveCreationFormat.ear => '${name.toUpperCase()} (unsigned)',
    _ => name.toUpperCase(),
  };

  ArchiveEndpointFormat get endpointFormat => switch (this) {
    ArchiveCreationFormat.zip ||
    ArchiveCreationFormat.cbz ||
    ArchiveCreationFormat.kmz ||
    ArchiveCreationFormat.jar ||
    ArchiveCreationFormat.war ||
    ArchiveCreationFormat.ear => ArchiveEndpointFormat.zip,
    ArchiveCreationFormat.sevenZip ||
    ArchiveCreationFormat.cb7 => ArchiveEndpointFormat.sevenZip,
    ArchiveCreationFormat.tar ||
    ArchiveCreationFormat.cbt => ArchiveEndpointFormat.tar,
    ArchiveCreationFormat.tarGzip => ArchiveEndpointFormat.tarGzip,
    ArchiveCreationFormat.tarBzip2 => ArchiveEndpointFormat.tarBzip2,
    ArchiveCreationFormat.tarXz => ArchiveEndpointFormat.tarXz,
    ArchiveCreationFormat.tarZstd => ArchiveEndpointFormat.tarZstd,
    ArchiveCreationFormat.gzip => ArchiveEndpointFormat.gzip,
    ArchiveCreationFormat.bzip2 => ArchiveEndpointFormat.bzip2,
    ArchiveCreationFormat.xz => ArchiveEndpointFormat.xz,
    ArchiveCreationFormat.zstd => ArchiveEndpointFormat.zstd,
    ArchiveCreationFormat.ar => ArchiveEndpointFormat.ar,
    ArchiveCreationFormat.cpio => ArchiveEndpointFormat.cpio,
    ArchiveCreationFormat.xar => ArchiveEndpointFormat.xar,
    ArchiveCreationFormat.iso => ArchiveEndpointFormat.iso,
    _ => ArchiveEndpointFormat.readOnly,
  };

  ArchiveCompressionKind? get wrapper => switch (this) {
    ArchiveCreationFormat.tarGzip ||
    ArchiveCreationFormat.gzip => ArchiveCompressionKind.gzip,
    ArchiveCreationFormat.tarBzip2 ||
    ArchiveCreationFormat.bzip2 => ArchiveCompressionKind.bzip2,
    ArchiveCreationFormat.tarXz ||
    ArchiveCreationFormat.xz => ArchiveCompressionKind.xz,
    ArchiveCreationFormat.tarZstd ||
    ArchiveCreationFormat.zstd => ArchiveCompressionKind.zstd,
    _ => null,
  };

  bool get singlePayload => const {
    ArchiveCreationFormat.gzip,
    ArchiveCreationFormat.bzip2,
    ArchiveCreationFormat.xz,
    ArchiveCreationFormat.zstd,
  }.contains(this);
  bool get diskImage => const {
    ArchiveCreationFormat.iso,
    ArchiveCreationFormat.hfsx,
    ArchiveCreationFormat.dmg,
  }.contains(this);
  bool get supportsDirectories =>
      !singlePayload && this != ArchiveCreationFormat.ar;
  bool get supportsPassword => const {
    ArchiveCreationFormat.zip,
    ArchiveCreationFormat.cbz,
    ArchiveCreationFormat.sevenZip,
    ArchiveCreationFormat.cb7,
  }.contains(this);
  bool get supportsHiddenNames =>
      endpointFormat == ArchiveEndpointFormat.sevenZip;

  List<ArchiveCreationCompression> get compressions => switch (this) {
    ArchiveCreationFormat.zip ||
    ArchiveCreationFormat.cbz ||
    ArchiveCreationFormat.kmz ||
    ArchiveCreationFormat.jar ||
    ArchiveCreationFormat.war ||
    ArchiveCreationFormat.ear ||
    ArchiveCreationFormat.tarGzip ||
    ArchiveCreationFormat.gzip => const [
      ArchiveCreationCompression.none,
      ArchiveCreationCompression.fast,
      ArchiveCreationCompression.normal,
      ArchiveCreationCompression.maximum,
    ],
    ArchiveCreationFormat.tarBzip2 ||
    ArchiveCreationFormat.tarXz ||
    ArchiveCreationFormat.tarZstd ||
    ArchiveCreationFormat.bzip2 ||
    ArchiveCreationFormat.xz ||
    ArchiveCreationFormat.zstd => const [
      ArchiveCreationCompression.fast,
      ArchiveCreationCompression.normal,
      ArchiveCreationCompression.maximum,
    ],
    ArchiveCreationFormat.sevenZip || ArchiveCreationFormat.cb7 => const [
      ArchiveCreationCompression.none,
      ArchiveCreationCompression.deflate,
      ArchiveCreationCompression.lzma2,
    ],
    ArchiveCreationFormat.dmg => const [
      ArchiveCreationCompression.none,
      ArchiveCreationCompression.normal,
    ],
    ArchiveCreationFormat.xar => const [ArchiveCreationCompression.normal],
    _ => const [ArchiveCreationCompression.none],
  };

  ArchiveCreationCompression get defaultCompression => supportsHiddenNames
      ? ArchiveCreationCompression.lzma2
      : compressions.contains(ArchiveCreationCompression.normal)
      ? ArchiveCreationCompression.normal
      : ArchiveCreationCompression.none;
}

enum ArchiveCreationCompression { none, fast, normal, maximum, deflate, lzma2 }

extension ArchiveCreationCompressionDetails on ArchiveCreationCompression {
  int get deflateLevel => switch (this) {
    ArchiveCreationCompression.none => 0,
    ArchiveCreationCompression.fast => 1,
    ArchiveCreationCompression.normal => 6,
    ArchiveCreationCompression.maximum => 9,
    _ => throw ArgumentError('This compression method has no numeric level.'),
  };
}

/// Passwords belong only to this invocation. Never serialize or log options.
class ArchiveCreationOptions {
  const ArchiveCreationOptions({
    required this.name,
    this.format = ArchiveCreationFormat.zip,
    this.compression = ArchiveCreationCompression.normal,
    this.password,
    this.encryptNames = false,
  });

  final String name;
  final ArchiveCreationFormat format;
  final ArchiveCreationCompression compression;
  final String? password;
  final bool encryptNames;

  void validate() {
    if (name.isEmpty ||
        name != name.trim() ||
        name == '.' ||
        name == '..' ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) ||
        name.endsWith('.') ||
        utf8.encode(name).length > 240 ||
        !name.toLowerCase().endsWith(format.extension)) {
      throw const ArchiveCreationException(ArchiveCreationError.invalidName);
    }
    final stem = name.split('.').first.toUpperCase();
    if (const {'CON', 'PRN', 'AUX', 'NUL'}.contains(stem) ||
        RegExp(r'^(COM|LPT)[1-9]$').hasMatch(stem)) {
      throw const ArchiveCreationException(ArchiveCreationError.invalidName);
    }
    if (!format.compressions.contains(compression)) {
      throw const ArchiveCreationException(
        ArchiveCreationError.unsupportedOptions,
      );
    }
    if (password != null && (!format.supportsPassword || password!.isEmpty) ||
        encryptNames && (!format.supportsHiddenNames || password == null)) {
      throw const ArchiveCreationException(
        ArchiveCreationError.unsupportedOptions,
      );
    }
  }
}

enum ArchiveCreationError {
  invalidName,
  unsupportedOptions,
  sourceChanged,
  sourceUnavailable,
  emptySelection,
  unsupportedEntry,
  duplicateName,
  tooLarge,
  destinationExists,
  invalidDestination,
  verificationFailed,
  cancelled,
}

class ArchiveCreationException implements Exception {
  const ArchiveCreationException(this.code, [this.path]);
  final ArchiveCreationError code;
  final String? path;
  @override
  String toString() =>
      'Archive creation: ${code.name}${path == null ? '' : ' ($path)'}';
}

enum ArchiveCreationPhase { scanning, packing, verifying, saving }

class ArchiveCreationProgress {
  const ArchiveCreationProgress(
    this.phase,
    this.completed,
    this.total,
    this.path,
  );
  final ArchiveCreationPhase phase;
  final int completed;
  final int total;
  final String path;
}

class ArchiveCreationResult {
  const ArchiveCreationResult(this.path, this.entryCount, this.bytes);
  final String path;
  final int entryCount;
  final int bytes;
}

class _CreationEntry {
  _CreationEntry(this.file, this.name, {this.mode});
  final FileItem file;
  final String name;
  final int? mode;
  String? digest;
}

/// Bounded archive creation through captured operation backends. The UI exposes
/// this workflow for native local files. No output is published until the
/// archive, its source snapshots and the staged destination have been verified.
class ArchiveCreationService {
  const ArchiveCreationService();

  static const maxEntries = 200000;
  static const maxNameBytes = 8 * 1024 * 1024;

  Future<ArchiveCreationResult> create({
    required FileOperationBackend source,
    required FileOperationBackend destination,
    required List<FileItem> files,
    required String destinationDirectory,
    required ArchiveCreationOptions options,
    bool Function()? isCancelled,
    void Function(ArchiveCreationProgress)? onProgress,
  }) async {
    options.validate();
    void check() {
      if (isCancelled?.call() ?? false) {
        throw const ArchiveCreationException(ArchiveCreationError.cancelled);
      }
      if (!source.isCurrent || !destination.isCurrent) {
        throw const ArchiveCreationException(
          ArchiveCreationError.sourceUnavailable,
        );
      }
    }

    void progress(
      ArchiveCreationPhase phase,
      int done,
      int total,
      String path,
    ) {
      check();
      onProgress?.call(ArchiveCreationProgress(phase, done, total, path));
      check();
    }

    check();
    if (files.isEmpty) {
      throw const ArchiveCreationException(ArchiveCreationError.emptySelection);
    }
    if (!destination.supportsStagedVerification ||
        !destination.paths.isAbsolute(destinationDirectory)) {
      throw const ArchiveCreationException(
        ArchiveCreationError.invalidDestination,
      );
    }
    final directory = await destination.stat(destinationDirectory);
    check();
    if (directory == null ||
        !directory.isFolder ||
        directory.isSymlink == true) {
      throw const ArchiveCreationException(
        ArchiveCreationError.invalidDestination,
      );
    }
    final output = destination.paths.join(destinationDirectory, options.name);
    Future<void> checkDestination() async {
      check();
      final current = await destination.stat(destinationDirectory);
      if (current == null ||
          !current.isFolder ||
          current.isSymlink == true ||
          current.uuid != directory.uuid) {
        throw const ArchiveCreationException(
          ArchiveCreationError.invalidDestination,
        );
      }
      if (await destination.stat(output) != null) {
        throw ArchiveCreationException(
          ArchiveCreationError.destinationExists,
          output,
        );
      }
      check();
    }

    await checkDestination();
    if (options.format.singlePayload &&
        (files.length != 1 || files.single.isFolder)) {
      throw const ArchiveCreationException(
        ArchiveCreationError.unsupportedEntry,
      );
    }
    final memberLimit = options.format.diskImage
        ? 2 * 1024 * 1024 * 1024
        : kArchiveReadLimit;
    final totalLimit = options.format.diskImage
        ? 2 * 1024 * 1024 * 1024
        : options.format.wrapper != null
        ? kArchiveReadLimit
        : ArchiveService.maxExtractedBytes;
    final entries = <_CreationEntry>[];
    final seen = <String>{};
    final names = <String>{};
    final folderChildren = <String, List<FileItem>>{};
    var totalBytes = 0, nameBytes = 0;
    final capturePermissions =
        !options.format.singlePayload && source.capabilities.permissions;
    Future<int?> sourceMode(String path) async {
      if (!capturePermissions) return null;
      final metadata = await source.readMetadataFields(
        path,
        permissions: true,
        modified: false,
        accessed: false,
        created: false,
        ownership: false,
        extendedAttributes: false,
        acl: false,
        windowsAttributes: false,
      );
      check();
      final mode = metadata.mode;
      if (mode == null || mode < 0 || mode > 0xffff) {
        throw ArchiveCreationException(
          ArchiveCreationError.unsupportedEntry,
          path,
        );
      }
      return mode & 0xfff;
    }

    Future<void> walk(FileItem selected, String name, int depth) async {
      check();
      final path = selected.path;
      if (path == null || !source.paths.isAbsolute(path)) {
        throw ArchiveCreationException(
          ArchiveCreationError.unsupportedEntry,
          path,
        );
      }
      if (!seen.add(source.pathKey(path))) return;
      if (depth > 200 || entries.length >= maxEntries) {
        throw const ArchiveCreationException(ArchiveCreationError.tooLarge);
      }
      final current = await source.stat(path);
      check();
      if (current == null) {
        throw ArchiveCreationException(
          ArchiveCreationError.sourceChanged,
          path,
        );
      }
      if (current.isSymlink == true ||
          !current.isFolder && (current.size == null || current.size! < 0)) {
        throw ArchiveCreationException(
          ArchiveCreationError.unsupportedEntry,
          path,
        );
      }
      if (!_sameVersion(selected, current, requireKnown: false)) {
        throw ArchiveCreationException(
          ArchiveCreationError.sourceChanged,
          path,
        );
      }
      if (!options.format.supportsDirectories && current.isFolder) {
        throw ArchiveCreationException(
          ArchiveCreationError.unsupportedEntry,
          path,
        );
      }
      name = options.format.singlePayload
          ? stripCompressionSuffix(options.name)
          : name;
      name = ArchiveService.safeMemberPath(name);
      if (options.format == ArchiveCreationFormat.hfsx ||
          options.format == ArchiveCreationFormat.dmg) {
        name = normalizeHfsArchivePath(name);
      }
      if (!names.add(name)) {
        throw ArchiveCreationException(
          ArchiveCreationError.duplicateName,
          name,
        );
      }
      nameBytes += utf8.encode(name).length;
      if (utf8.encode(name).length > 65535 || nameBytes > maxNameBytes) {
        throw const ArchiveCreationException(ArchiveCreationError.tooLarge);
      }
      if (source.identity == destination.identity &&
          (source.pathKey(path) == source.pathKey(output) ||
              current.isFolder && source.isWithin(path, output))) {
        throw const ArchiveCreationException(
          ArchiveCreationError.invalidDestination,
        );
      }
      entries.add(_CreationEntry(current, name, mode: await sourceMode(path)));
      progress(ArchiveCreationPhase.scanning, entries.length, 0, name);
      if (current.isFolder) {
        final children = await source.list(path);
        check();
        folderChildren[path] = List.unmodifiable(children);
        children.sort((a, b) => (a.path ?? '').compareTo(b.path ?? ''));
        for (final child in children) {
          if (child.path == null ||
              source.paths.dirname(child.path!) !=
                  source.paths.normalize(path) ||
              !source.isWithin(path, child.path!)) {
            throw ArchiveCreationException(
              ArchiveCreationError.unsupportedEntry,
              path,
            );
          }
          await walk(child, '$name/${child.name}', depth + 1);
        }
      } else {
        totalBytes += current.size!;
        if (current.size! > memberLimit || totalBytes > totalLimit) {
          throw const ArchiveCreationException(ArchiveCreationError.tooLarge);
        }
      }
      await Future<void>.delayed(Duration.zero);
    }

    // A selected ancestor owns its descendants even if a child was selected
    // first, avoiding duplicate members from overlapping selections.
    final ordered = List<FileItem>.of(files)
      ..sort((a, b) => (a.path ?? '').length.compareTo((b.path ?? '').length));
    for (final file in ordered) {
      await walk(file, file.name, 0);
    }

    Future<void> validateEntry(_CreationEntry entry) async {
      check();
      if (!_sameVersion(entry.file, await source.stat(entry.file.path!))) {
        throw ArchiveCreationException(
          ArchiveCreationError.sourceChanged,
          entry.file.path,
        );
      }
      if (entry.mode != await sourceMode(entry.file.path!)) {
        throw ArchiveCreationException(
          ArchiveCreationError.sourceChanged,
          entry.file.path,
        );
      }
      check();
    }

    Stream<List<int>> readEntryChunks(_CreationEntry entry) async* {
      await validateEntry(entry);
      final digest = _CreationDigestSink();
      final hash = sha256.startChunkedConversion(digest);
      var length = 0;
      await for (final chunk in source.readFile(entry.file)) {
        check();
        if (chunk.length > memberLimit - length ||
            chunk.length > entry.file.size! - length ||
            chunk is! Uint8List &&
                chunk.any((value) => value < 0 || value > 255)) {
          throw ArchiveCreationException(
            ArchiveCreationError.sourceChanged,
            entry.file.path,
          );
        }
        for (var at = 0; at < chunk.length; at += 256 * 1024) {
          final end = at + 256 * 1024 < chunk.length
              ? at + 256 * 1024
              : chunk.length;
          final copy = Uint8List.fromList(chunk.sublist(at, end));
          length += copy.length;
          hash.add(copy);
          yield copy;
          check();
        }
      }
      await validateEntry(entry);
      hash.close();
      if (length != entry.file.size ||
          entry.digest != null && entry.digest != digest.value) {
        throw ArchiveCreationException(
          ArchiveCreationError.sourceChanged,
          entry.file.path,
        );
      }
      entry.digest = digest.value;
    }

    Future<Uint8List> readEntry(_CreationEntry entry) async {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in readEntryChunks(entry)) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }

    final captured = [
      for (final entry in entries)
        ArchiveWriteEntry(
          path: entry.name,
          isDirectory: entry.file.isFolder,
          size: entry.file.isFolder ? 0 : entry.file.size!,
          mode: entry.mode,
          modified: entry.file.updatedAt == null || options.format.singlePayload
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  entry.file.updatedAt!.millisecondsSinceEpoch -
                      entry.file.updatedAt!.millisecondsSinceEpoch % 1000,
                  isUtc: true,
                ),
          readChunks: entry.file.isFolder ? null : () => readEntryChunks(entry),
        ),
    ];
    validateArchiveWriteEntries(
      captured,
      allowDirectories: options.format.supportsDirectories,
    );
    final packageIssue = await archiveZipPackageIssue(options.name, captured);
    if (packageIssue != null) throw ArchiveViewException(packageIssue);
    final spool = await ArchiveOutputSpool.create(
      maxBytes: options.format.diskImage
          ? 2 * 1024 * 1024 * 1024
          : ArchiveService.maxArchiveBytes,
    );
    try {
      var done = 0;
      Future<void> emit(List<int> bytes) async {
        check();
        await spool.write(bytes);
        check();
      }

      if (options.format.diskImage) {
        progress(ArchiveCreationPhase.packing, 0, totalBytes, options.name);
        switch (options.format) {
          case ArchiveCreationFormat.iso:
            await writeIsoArchive(
              captured,
              sink: emit,
              maxOutputBytes: spool.maxBytes,
              isCancelled: isCancelled,
            );
          case ArchiveCreationFormat.hfsx:
            await writeHfsArchive(
              captured,
              sink: emit,
              maxOutputBytes: spool.maxBytes,
              isCancelled: isCancelled,
            );
          case ArchiveCreationFormat.dmg:
            await writeDmgArchive(
              captured,
              sink: emit,
              maxOutputBytes: spool.maxBytes,
              isCancelled: isCancelled,
              compress: options.compression != ArchiveCreationCompression.none,
            );
          default:
            throw const ArchiveCreationException(
              ArchiveCreationError.unsupportedOptions,
            );
        }
      } else if (const {
            ArchiveEndpointFormat.ar,
            ArchiveEndpointFormat.cpio,
            ArchiveEndpointFormat.xar,
          }.contains(options.format.endpointFormat) ||
          options.format.singlePayload) {
        await writeArchiveEntries(
          options.format.endpointFormat,
          captured,
          sink: emit,
          compression: options.format.wrapper,
          singlePayload: options.format.singlePayload,
          level: options.compression.deflateLevel,
          maxOutputBytes: spool.maxBytes,
          isCancelled: isCancelled,
        );
      } else {
        final memory = _BoundedArchiveMemory(
          check,
          // GZIP-backed browsing buffers the decoded container. Produce archives
          // that the normal viewer can open, including TAR header overhead.
          limit: options.format.wrapper != null
              ? kArchiveReadLimit
              : ArchiveService.maxArchiveBytes,
        );
        final sink = _CreationSink(memory);
        final zip = options.format.endpointFormat == ArchiveEndpointFormat.zip
            ? codecs.ZipEncoder(password: options.password, streamed: true)
            : null;
        final writer = zip != null
            ? null
            : koni.Archive.create(
                sink,
                format:
                    options.format.endpointFormat ==
                        ArchiveEndpointFormat.sevenZip
                    ? const koni.SevenZWriteFormat()
                    : const koni.TarWriteFormat(),
                options: koni.ArchiveWriteOptions(
                  compression:
                      options.format.endpointFormat ==
                          ArchiveEndpointFormat.sevenZip
                      ? switch (options.compression) {
                          ArchiveCreationCompression.none =>
                            koni.ArchiveCompression.stored,
                          ArchiveCreationCompression.deflate =>
                            koni.ArchiveCompression.deflate,
                          _ => koni.ArchiveCompression.lzma2,
                        }
                      : koni.ArchiveCompression.stored,
                  password: options.password,
                  encryptHeader: options.encryptNames,
                ),
              );
        zip?.startEncode(memory, level: options.compression.deflateLevel);
        done = 0;
        for (final entry in entries) {
          progress(
            ArchiveCreationPhase.packing,
            done,
            entries.length,
            entry.name,
          );
          await validateEntry(entry);
          final bytes = entry.file.isFolder ? null : await readEntry(entry);
          if (zip != null) {
            final file = bytes == null
                ? codecs.ArchiveFile.directory('${entry.name}/')
                : codecs.ArchiveFile.bytes(entry.name, bytes);
            if (entry.file.updatedAt != null) {
              file.lastModTime =
                  entry.file.updatedAt!.millisecondsSinceEpoch ~/ 1000;
            }
            if (entry.mode != null) file.mode = entry.mode!;
            file.compression =
                options.compression == ArchiveCreationCompression.none
                ? codecs.CompressionType.none
                : codecs.CompressionType.deflate;
            final body = zip.addHeader(file);
            if (body != null) {
              try {
                while (body.step()) {
                  await Future<void>.delayed(Duration.zero);
                  check();
                }
                body.finish();
              } catch (_) {
                body.cancel();
                rethrow;
              }
            }
          } else {
            final spec = koni.ArchiveEntrySpec(
              path: entry.name,
              type: bytes == null
                  ? koni.ArchiveEntryType.directory
                  : koni.ArchiveEntryType.file,
              modified: entry.file.updatedAt?.toUtc(),
              posixMode: entry.mode,
            );
            if (bytes == null) {
              await writer!.addEntry(spec);
            } else {
              await writer!.addBytes(spec, bytes);
            }
          }
          done++;
          await Future<void>.delayed(Duration.zero);
        }
        check();
        if (zip != null) {
          zip.endEncode();
        } else {
          await writer!.close();
        }
        await sink.close();
        var packed = memory.getBytes();
        if (options.format.wrapper != null) {
          packed = encodeArchiveCompression(
            packed,
            options.format.wrapper!,
            level: options.compression.deflateLevel,
            maxOutputBytes: spool.maxBytes,
          );
        }
        await emit(packed);
      }
      await spool.finish();
      check();

      if (options.format.diskImage) {
        progress(
          ArchiveCreationPhase.verifying,
          0,
          entries.length,
          options.name,
        );
        await verifyCreatedDiskArchive(
          spool,
          captured,
          format: options.format.name,
          isCancelled: isCancelled,
        );
        progress(
          ArchiveCreationPhase.verifying,
          entries.length,
          entries.length,
          options.name,
        );
      } else if (options.format.singlePayload) {
        final source = await spool.openByteSource();
        try {
          final unpacked = decompressSingleFile(
            await source.read(0, source.length),
            options.name,
          ).data;
          if (unpacked.length != entries.single.file.size ||
              sha256.convert(unpacked).toString() != entries.single.digest) {
            throw const ArchiveCreationException(
              ArchiveCreationError.verificationFailed,
            );
          }
          progress(ArchiveCreationPhase.verifying, 1, 1, entries.single.name);
        } finally {
          await source.close();
        }
      } else {
        // Decode with the regular reader, which is independent of the ZIP encoder.
        final archive = await openViewerArchiveSource(
          await spool.openByteSource(),
          name: options.name,
          password: options.password,
        );
        try {
          final expected = {for (final entry in entries) entry.name: entry};
          if (archive.members.length != entries.length) {
            throw const ArchiveCreationException(
              ArchiveCreationError.verificationFailed,
            );
          }
          done = 0;
          for (final member in archive.members) {
            check();
            final name = member.name.replaceFirst(RegExp(r'/+$'), '');
            final entry = expected.remove(name);
            if (entry == null ||
                member.pathEscapedRoot ||
                member.isSpecial ||
                member.isFile == entry.file.isFolder ||
                entry.mode != null &&
                    (member.posixMode == null ||
                        (member.posixMode! & 0xfff) != entry.mode)) {
              throw const ArchiveCreationException(
                ArchiveCreationError.verificationFailed,
              );
            }
            if (member.isFile) {
              final decoded = await archive.readMember(member);
              if (sha256.convert(decoded).toString() != entry.digest ||
                  options.password != null &&
                      member.size > 0 &&
                      !member.isEncrypted) {
                throw const ArchiveCreationException(
                  ArchiveCreationError.verificationFailed,
                );
              }
            }
            progress(
              ArchiveCreationPhase.verifying,
              ++done,
              entries.length,
              name,
            );
            await Future<void>.delayed(Duration.zero);
          }
        } finally {
          await archive.close();
        }
      }

      Future<void> validateSources() async {
        for (final entry in entries) {
          await validateEntry(entry);
          if (!entry.file.isFolder) {
            await readEntryChunks(entry).drain<void>();
          }
        }
        for (final folder in folderChildren.entries) {
          final children = await source.list(folder.key);
          check();
          final old = {
            for (final child in folder.value)
              source.pathKey(child.path!): child,
          };
          if (children.length != old.length ||
              children.any(
                (child) =>
                    child.path == null ||
                    !_sameVersion(old[source.pathKey(child.path!)], child),
              )) {
            throw ArchiveCreationException(
              ArchiveCreationError.sourceChanged,
              folder.key,
            );
          }
        }
      }

      await validateSources();
      await checkDestination();
      progress(ArchiveCreationPhase.saving, 0, spool.length, output);
      final packedHash =
          (await sha256
                  .bind(
                    spool.openRead().map((chunk) {
                      check();
                      return chunk;
                    }),
                  )
                  .first)
              .toString();
      await destination.writePreparedFile(
        output,
        spool.openRead().map((chunk) {
          check();
          return chunk;
        }),
        spool.length,
        replace: false,
        checkpoint: (state) async {
          if (state['phase'] != 'committed') check();
        },
        verifyStaged: (staged) async {
          check();
          final hash = await sha256
              .bind(
                destination.readFile(staged).map((chunk) {
                  check();
                  return chunk;
                }),
              )
              .first;
          if (staged.size != spool.length || hash.toString() != packedHash) {
            throw const ArchiveCreationException(
              ArchiveCreationError.verificationFailed,
            );
          }
          await validateSources();
          await checkDestination();
        },
      );
      // A completed exclusive commit remains a success if cancellation arrives
      // after it; do not suggest that a published archive was rolled back.
      return ArchiveCreationResult(output, entries.length, spool.length);
    } catch (_) {
      if (isCancelled?.call() ?? false) {
        throw const ArchiveCreationException(ArchiveCreationError.cancelled);
      }
      rethrow;
    } finally {
      try {
        await spool.dispose();
      } catch (_) {
        // Failure to remove our private temporary output must not turn a
        // committed archive into a reported failed save, nor mask the original
        // creation error. The spool never owns the destination or source files.
      }
    }
  }

  static bool _sameVersion(
    FileItem? a,
    FileItem? b, {
    bool requireKnown = true,
  }) =>
      a != null &&
      b != null &&
      a.isFolder == b.isFolder &&
      (a.isSymlink != true && b.isSymlink != true) &&
      (a.uuid == null && !requireKnown || a.uuid == b.uuid) &&
      (a.size == null && !requireKnown || a.size == b.size) &&
      (a.updatedAt == null && !requireKnown || a.updatedAt == b.updatedAt);
}

class _BoundedArchiveMemory extends codecs.OutputMemoryStream {
  _BoundedArchiveMemory(
    this.check, {
    this.limit = ArchiveService.maxArchiveBytes,
  });
  final void Function() check;
  final int limit;
  void _allow(int count) {
    check();
    if (count < 0 || length + count > limit) {
      throw const ArchiveCreationException(ArchiveCreationError.tooLarge);
    }
  }

  @override
  void writeByte(int value) {
    _allow(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _allow(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(codecs.InputStream stream) {
    _allow(stream.length);
    super.writeStream(stream);
  }

  @override
  void reserve(int total) {
    check();
    if (total > limit) {
      throw const ArchiveCreationException(ArchiveCreationError.tooLarge);
    }
    super.reserve(total);
  }
}

class _CreationSink implements koni.ByteSink {
  _CreationSink(this.memory);
  final _BoundedArchiveMemory memory;
  @override
  int get length => memory.length;
  @override
  Future<void> add(Uint8List bytes) async => memory.writeBytes(bytes);
  @override
  Future<void> close() async {}
}

class _CreationDigestSink implements Sink<Digest> {
  String? value;
  @override
  void add(Digest digest) {
    value = digest.toString();
  }

  @override
  void close() {}
}
