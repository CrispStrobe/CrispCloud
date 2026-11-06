import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'file_integrity_service.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';

export 'file_integrity_service.dart'
    show ChecksumAlgorithm, ChecksumAccumulator, FileIntegrityCancelled;

class ChecksumVerifyResult {
  const ChecksumVerifyResult({
    required this.filename,
    required this.expected,
    required this.actual,
    this.error,
  });
  final String filename;
  final String expected;
  final String actual;
  final String? error;
  bool get ok =>
      error == null && expected.toLowerCase() == actual.toLowerCase();
}

class ChecksumManifestEntry {
  const ChecksumManifestEntry(this.filename, this.digest);
  final String filename;
  final String digest;
}

class ChecksumService {
  static String md5Hash(Uint8List data) => crypto.md5.convert(data).toString();
  static String sha256Hash(Uint8List data) =>
      crypto.sha256.convert(data).toString();
  static FileOperationBackend _local() =>
      LocalOperationBackend(LocalFileService(), isCurrent: () => true);
  static FileItem _file(String path) =>
      FileItem(name: p.basename(path), path: path, isFolder: false);
  static Future<String> md5File(String path) =>
      hashIntegrityFile(_local(), _file(path), ChecksumAlgorithm.md5);
  static Future<String> sha256File(String path) =>
      hashIntegrityFile(_local(), _file(path), ChecksumAlgorithm.sha256);

  static Future<String> hashFile(
    FileOperationBackend source,
    FileItem file,
    ChecksumAlgorithm algorithm, {
    bool Function()? isCancelled,
    void Function(int bytes, int? total)? onProgress,
  }) => hashIntegrityFile(
    source,
    file,
    algorithm,
    isCancelled: isCancelled,
    onProgress: onProgress,
  );

  static String _escape(String filename) => filename
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  static String _unescape(String filename) {
    final result = StringBuffer();
    for (var i = 0; i < filename.length; i++) {
      if (filename[i] != '\\') {
        result.write(filename[i]);
        continue;
      }
      if (++i == filename.length) {
        throw const FormatException('Incomplete escaped filename.');
      }
      result.write(switch (filename[i]) {
        'n' => '\n',
        'r' => '\r',
        '\\' => '\\',
        _ => throw const FormatException('Unknown filename escape.'),
      });
    }
    return result.toString();
  }

  static String formatManifest(
    Iterable<ChecksumManifestEntry> entries,
    ChecksumAlgorithm algorithm,
  ) {
    final output = StringBuffer();
    for (final entry in entries) {
      var name = entry.filename;
      if (name.isEmpty ||
          name.contains('\x00') ||
          !RegExp('^[0-9a-fA-F]{${algorithm.hexLength}}\$')
              .hasMatch(entry.digest)) {
        throw const FormatException('Invalid checksum entry.');
      }
      if (algorithm == ChecksumAlgorithm.crc32) {
        if (name.contains('\n') || name.contains('\r')) {
          throw const FormatException(
            'SFV cannot represent filenames with line breaks. Choose SHA-256.',
          );
        }
        if (name.startsWith(';') || name.startsWith('#')) name = './$name';
        output.writeln('$name ${entry.digest.toUpperCase()}');
      } else {
        final escaped =
            name.contains('\\') || name.contains('\n') || name.contains('\r');
        output.writeln(
          '${escaped ? '\\' : ''}${entry.digest}  ${escaped ? _escape(name) : name}',
        );
      }
    }
    final text = output.toString();
    if (utf8.encode(text).length > 2 * 1024 * 1024) {
      throw const FormatException('Manifest exceeds 2 MiB.');
    }
    return text;
  }

  static List<ChecksumManifestEntry> parseManifest(
    String text,
    ChecksumAlgorithm algorithm,
  ) {
    if (utf8.encode(text).length > 2 * 1024 * 1024) {
      throw const FormatException('Manifest exceeds 2 MiB.');
    }
    final entries = <ChecksumManifestEntry>[];
    final lines = const LineSplitter().convert(text);
    for (var lineNumber = 0; lineNumber < lines.length; lineNumber++) {
      var line = lines[lineNumber];
      if (line.trim().isEmpty || line.startsWith(';') || line.startsWith('#')) {
        continue;
      }
      try {
        late String filename;
        late String digest;
        if (algorithm == ChecksumAlgorithm.crc32) {
          final match = RegExp(r'^(.*) ([0-9a-fA-F]{8})$').firstMatch(line);
          if (match == null) {
            throw const FormatException('Expected SFV filename and CRC32.');
          }
          filename = match[1]!;
          digest = match[2]!;
        } else {
          final escaped = line.startsWith('\\');
          if (escaped) line = line.substring(1);
          final length = algorithm.hexLength;
          if (line.length <= length + 1 ||
              !RegExp('^[0-9a-fA-F]{$length}\$')
                  .hasMatch(line.substring(0, length)) ||
              (line[length] != ' ' && line[length] != '\t')) {
            throw const FormatException('Expected a checksum and filename.');
          }
          digest = line.substring(0, length);
          var start = length + 1;
          if (line[length] == ' ' &&
              (line[start] == ' ' || line[start] == '*')) {
            start++;
          }
          filename = line.substring(start);
          if (escaped) filename = _unescape(filename);
        }
        if (filename.isEmpty || filename.contains('\x00')) {
          throw const FormatException('Invalid filename.');
        }
        entries.add(ChecksumManifestEntry(filename, digest.toLowerCase()));
        if (entries.length > 100000) {
          throw const FormatException('Manifest exceeds 100,000 entries.');
        }
      } on FormatException catch (error) {
        throw FormatException(
          'Checksum line ${lineNumber + 1}: ${error.message}',
        );
      }
    }
    if (entries.isEmpty) {
      throw const FormatException('The checksum file has no entries.');
    }
    return entries;
  }

  static Future<String> createManifest(
    FileOperationBackend source,
    List<FileItem> files, {
    required String baseDirectory,
    required String outputName,
    ChecksumAlgorithm algorithm = ChecksumAlgorithm.sha256,
    bool Function()? isCancelled,
    void Function(FileItem file, int bytes, int? total)? onProgress,
  }) async {
    if (files.isEmpty || files.length > 100000) {
      throw ArgumentError('Select between 1 and 100,000 files.');
    }
    if (ChecksumAlgorithm.forName(outputName) != algorithm) {
      throw ArgumentError(
        'Use a .${algorithm.extension} filename for ${algorithm.label}.',
      );
    }
    final base = source.paths.normalize(baseDirectory);
    final output = resolveIntegrityPath(source, base, outputName);
    if (!source.samePath(source.paths.dirname(output), base)) {
      throw ArgumentError(
        'The checksum file must be stored in its base directory.',
      );
    }
    if (await source.stat(output) != null) {
      throw StateError('The output already exists: $output');
    }
    final names = <String>{};
    final resolved = <({FileItem file, String name})>[];
    for (final file in files) {
      if (file.isFolder || file.path == null) {
        throw ArgumentError('Select regular files to checksum.');
      }
      final relative = source.paths.relative(file.path!, from: base);
      final name = source.paths.split(relative).join('/');
      final path = resolveIntegrityPath(source, base, name);
      if (!source.samePath(path, file.path!) ||
          source.samePath(path, output) ||
          !names.add(source.pathKey(path))) {
        throw FormatException('Duplicate or invalid manifest filename: $name');
      }
      await rejectIntegritySymlinkParents(
        source,
        base,
        path,
        isCancelled: isCancelled,
      );
      resolved.add((file: file, name: name));
    }
    final entries = <ChecksumManifestEntry>[];
    for (final entry in resolved) {
      final digest = await hashFile(
        source,
        entry.file,
        algorithm,
        isCancelled: isCancelled,
        onProgress: (bytes, total) =>
            onProgress?.call(entry.file, bytes, total),
      );
      entries.add(ChecksumManifestEntry(entry.name, digest));
    }
    await writeIntegrityBytes(
      source,
      output,
      utf8.encode(formatManifest(entries, algorithm)),
      replace: false,
      isCancelled: isCancelled,
    );
    return output;
  }

  static Future<List<ChecksumVerifyResult>> verifyManifest(
    FileOperationBackend source,
    FileItem manifest, {
    ChecksumAlgorithm? algorithm,
    bool Function()? isCancelled,
    void Function(String filename, int bytes, int? total)? onProgress,
  }) async {
    final selectedAlgorithm =
        algorithm ?? ChecksumAlgorithm.forName(manifest.name);
    final text = utf8.decode(
      await readIntegrityBytes(source, manifest, isCancelled: isCancelled),
    );
    final entries = parseManifest(text, selectedAlgorithm);
    final base = source.paths.dirname(manifest.path!);
    final paths = <String>[];
    final unique = <String>{};
    for (final entry in entries) {
      final path = resolveIntegrityPath(source, base, entry.filename);
      if (!unique.add(source.pathKey(path))) {
        throw FormatException('Duplicate manifest filename: ${entry.filename}');
      }
      paths.add(path);
    }
    final results = <ChecksumVerifyResult>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      try {
        await rejectIntegritySymlinkParents(
          source,
          base,
          paths[i],
          isCancelled: isCancelled,
        );
        final actual = await hashFile(
          source,
          FileItem(name: entry.filename, path: paths[i], isFolder: false),
          selectedAlgorithm,
          isCancelled: isCancelled,
          onProgress: (bytes, total) =>
              onProgress?.call(entry.filename, bytes, total),
        );
        results.add(
          ChecksumVerifyResult(
            filename: entry.filename,
            expected: entry.digest,
            actual: actual,
          ),
        );
      } catch (error) {
        checkIntegrityCurrent(source, isCancelled);
        results.add(
          ChecksumVerifyResult(
            filename: entry.filename,
            expected: entry.digest,
            actual: '(unavailable)',
            error: '$error',
          ),
        );
      }
    }
    return results;
  }

  static Future<String> generateMd5File(
    List<String> filePaths,
    String dirPath, {
    String? outputName,
  }) => createManifest(
    _local(),
    filePaths.map(_file).toList(),
    baseDirectory: dirPath,
    outputName: outputName ?? 'checksums.md5',
    algorithm: ChecksumAlgorithm.md5,
  );
  static Future<String> generateSha256File(
    List<String> filePaths,
    String dirPath, {
    String? outputName,
  }) => createManifest(
    _local(),
    filePaths.map(_file).toList(),
    baseDirectory: dirPath,
    outputName: outputName ?? 'checksums.sha256',
  );
  static Future<List<ChecksumVerifyResult>> verifyChecksumFile(
    String checksumFilePath,
  ) => verifyManifest(_local(), _file(checksumFilePath));
}
