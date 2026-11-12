import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import '../models/file_item.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';
import 'file_operation_service.dart';

enum ArchiveCreationFormat { zip, sevenZip, tar, tarGzip }

extension ArchiveCreationFormatDetails on ArchiveCreationFormat {
  String get extension => switch (this) {
    ArchiveCreationFormat.zip => '.zip',
    ArchiveCreationFormat.sevenZip => '.7z',
    ArchiveCreationFormat.tar => '.tar',
    ArchiveCreationFormat.tarGzip => '.tar.gz',
  };

  String get label => switch (this) {
    ArchiveCreationFormat.zip => 'ZIP',
    ArchiveCreationFormat.sevenZip => '7z',
    ArchiveCreationFormat.tar => 'TAR',
    ArchiveCreationFormat.tarGzip => 'TAR.GZ',
  };

  bool get supportsPassword =>
      this == ArchiveCreationFormat.zip ||
      this == ArchiveCreationFormat.sevenZip;

  List<ArchiveCreationCompression> get compressions => switch (this) {
    ArchiveCreationFormat.zip || ArchiveCreationFormat.tarGzip => const [
      ArchiveCreationCompression.none,
      ArchiveCreationCompression.fast,
      ArchiveCreationCompression.normal,
      ArchiveCreationCompression.maximum,
    ],
    ArchiveCreationFormat.sevenZip => const [
      ArchiveCreationCompression.none,
      ArchiveCreationCompression.deflate,
      ArchiveCreationCompression.lzma2,
    ],
    ArchiveCreationFormat.tar => const [ArchiveCreationCompression.none],
  };

  ArchiveCreationCompression get defaultCompression => switch (this) {
    ArchiveCreationFormat.sevenZip => ArchiveCreationCompression.lzma2,
    ArchiveCreationFormat.tar => ArchiveCreationCompression.none,
    _ => ArchiveCreationCompression.normal,
  };
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
        encryptNames &&
            (format != ArchiveCreationFormat.sevenZip || password == null)) {
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
  _CreationEntry(this.file, this.name);
  final FileItem file;
  final String name;
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
    final entries = <_CreationEntry>[];
    final seen = <String>{};
    final names = <String>{};
    final folderChildren = <String, List<FileItem>>{};
    var totalBytes = 0, nameBytes = 0;

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
      name = ArchiveService.safeMemberPath(name);
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
      entries.add(_CreationEntry(current, name));
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
        if (current.size! > kArchiveReadLimit ||
            totalBytes > ArchiveService.maxExtractedBytes) {
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
      check();
    }

    Future<Uint8List> readEntry(_CreationEntry entry) async {
      await validateEntry(entry);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in source.readFile(entry.file)) {
        check();
        if (bytes.length + chunk.length > kArchiveReadLimit ||
            bytes.length + chunk.length > entry.file.size!) {
          throw ArchiveCreationException(
            ArchiveCreationError.sourceChanged,
            entry.file.path,
          );
        }
        bytes.add(chunk);
      }
      await validateEntry(entry);
      if (bytes.length != entry.file.size) {
        throw ArchiveCreationException(
          ArchiveCreationError.sourceChanged,
          entry.file.path,
        );
      }
      return bytes.takeBytes();
    }

    final memory = _BoundedArchiveMemory(check);
    final sink = _CreationSink(memory);
    final zip = options.format == ArchiveCreationFormat.zip
        ? codecs.ZipEncoder(password: options.password, streamed: true)
        : null;
    final writer = zip != null
        ? null
        : koni.Archive.create(
            sink,
            format: options.format == ArchiveCreationFormat.sevenZip
                ? const koni.SevenZWriteFormat()
                : const koni.TarWriteFormat(),
            options: koni.ArchiveWriteOptions(
              compression: options.format == ArchiveCreationFormat.sevenZip
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
    var done = 0;
    for (final entry in entries) {
      progress(ArchiveCreationPhase.packing, done, entries.length, entry.name);
      await validateEntry(entry);
      final bytes = entry.file.isFolder ? null : await readEntry(entry);
      if (bytes != null) entry.digest = sha256.convert(bytes).toString();
      if (zip != null) {
        final file = bytes == null
            ? codecs.ArchiveFile.directory('${entry.name}/')
            : codecs.ArchiveFile.bytes(entry.name, bytes);
        if (entry.file.updatedAt != null) {
          file.lastModTime =
              entry.file.updatedAt!.millisecondsSinceEpoch ~/ 1000;
        }
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
    if (options.format == ArchiveCreationFormat.tarGzip) {
      final compressed = _BoundedArchiveMemory(check);
      const codecs.GZipEncoder().encodeStream(
        codecs.InputMemoryStream(packed),
        compressed,
        level: options.compression.deflateLevel,
      );
      packed = compressed.getBytes();
    }
    check();

    // Decode with the regular reader, which is independent of the ZIP encoder.
    final archive = await openViewerArchive(
      packed,
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
            member.isFile == entry.file.isFolder) {
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
        progress(ArchiveCreationPhase.verifying, ++done, entries.length, name);
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      await archive.close();
    }

    Future<void> validateSources() async {
      for (final entry in entries) {
        await validateEntry(entry);
        if (!entry.file.isFolder) {
          final bytes = await readEntry(entry);
          if (sha256.convert(bytes).toString() != entry.digest) {
            throw ArchiveCreationException(
              ArchiveCreationError.sourceChanged,
              entry.file.path,
            );
          }
        }
      }
      for (final folder in folderChildren.entries) {
        final children = await source.list(folder.key);
        check();
        final old = {
          for (final child in folder.value) source.pathKey(child.path!): child,
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
    progress(ArchiveCreationPhase.saving, 0, packed.length, output);
    final packedHash = sha256.convert(packed).toString();
    await destination.writePreparedFile(
      output,
      Stream.value(packed),
      packed.length,
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
        if (staged.size != packed.length || hash.toString() != packedHash) {
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
    return ArchiveCreationResult(output, entries.length, packed.length);
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
  _BoundedArchiveMemory(this.check);
  final void Function() check;
  void _allow(int count) {
    check();
    if (count < 0 || length + count > ArchiveService.maxArchiveBytes) {
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
    if (total > ArchiveService.maxArchiveBytes) {
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
