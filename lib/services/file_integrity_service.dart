import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'file_operation_service.dart';

enum ChecksumAlgorithm {
  md5('MD5', 'md5', 32),
  sha1('SHA-1', 'sha1', 40),
  sha256('SHA-256', 'sha256', 64),
  sha512('SHA-512', 'sha512', 128),
  crc32('CRC32 / SFV', 'sfv', 8);

  const ChecksumAlgorithm(this.label, this.extension, this.hexLength);
  final String label;
  final String extension;
  final int hexLength;

  static ChecksumAlgorithm forName(String name) {
    final extension = p.posix
        .extension(name)
        .toLowerCase()
        .replaceFirst('.', '');
    return values.firstWhere(
      (algorithm) => algorithm.extension == extension,
      orElse: () => throw FormatException('Unsupported checksum format: $name'),
    );
  }
}

class FileIntegrityCancelled implements Exception {
  const FileIntegrityCancelled();
  @override
  String toString() => 'Operation cancelled.';
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? digest;
  @override
  void add(crypto.Digest data) => digest = data;
  @override
  void close() {}
}

/// Constant-memory incremental hashing, shared by checksums and split manifests.
class ChecksumAccumulator {
  ChecksumAccumulator(this.algorithm) {
    final hash = switch (algorithm) {
      ChecksumAlgorithm.md5 => crypto.md5,
      ChecksumAlgorithm.sha1 => crypto.sha1,
      ChecksumAlgorithm.sha256 => crypto.sha256,
      ChecksumAlgorithm.sha512 => crypto.sha512,
      ChecksumAlgorithm.crc32 => null,
    };
    _input = hash?.startChunkedConversion(_output);
  }
  final ChecksumAlgorithm algorithm;
  final _output = _DigestSink();
  Sink<List<int>>? _input;
  var _crc = 0xffffffff;
  String? _finished;
  static final _crcTable = List<int>.generate(256, (value) {
    for (var bit = 0; bit < 8; bit++) {
      value = value & 1 == 1 ? (value >>> 1) ^ 0xedb88320 : value >>> 1;
    }
    return value;
  });
  void add(List<int> bytes) {
    if (_finished != null) throw StateError('Checksum is already finished.');
    if (_input != null) {
      _input!.add(bytes);
      return;
    }
    for (final byte in bytes) {
      _crc = _crcTable[(_crc ^ byte) & 0xff] ^ (_crc >>> 8);
    }
  }

  String finish() {
    if (_finished != null) return _finished!;
    _input?.close();
    return _finished = _input == null
        ? ((_crc ^ 0xffffffff) & 0xffffffff).toRadixString(16).padLeft(8, '0')
        : _output.digest!.toString();
  }
}

void checkIntegrityCurrent(
  FileOperationBackend source,
  bool Function()? isCancelled,
) {
  if (!source.isCurrent) {
    throw StateError('The original storage account is unavailable.');
  }
  if (isCancelled?.call() ?? false) throw const FileIntegrityCancelled();
}

bool sameIntegrityVersion(FileItem before, FileItem after) =>
    before.path == after.path &&
    before.uuid == after.uuid &&
    before.size == after.size &&
    before.updatedAt == after.updatedAt &&
    before.isFolder == after.isFolder &&
    before.isSymlink == after.isSymlink &&
    const [
      'etag',
      'versionId',
      'revision',
      'content_hash',
    ].every((key) => before.metadata?[key] == after.metadata?[key]);

Future<FileItem> requireIntegrityFile(
  FileOperationBackend source,
  FileItem file, {
  bool Function()? isCancelled,
}) async {
  checkIntegrityCurrent(source, isCancelled);
  final current = file.path == null ? null : await source.stat(file.path!);
  checkIntegrityCurrent(source, isCancelled);
  if (current == null || current.isFolder || current.isSymlink == true) {
    throw StateError(
      'Missing or unsupported regular file: ${file.path ?? file.name}',
    );
  }
  if (file.uuid != null && current.uuid != file.uuid) {
    throw StateError('A different file now occupies ${file.path}.');
  }
  if (!source.capabilities.boundedDownload &&
      (current.size == null || current.size! > 64 * 1024 * 1024)) {
    throw UnsupportedError(
      'This storage cannot stream a file of this size. Download it first.',
    );
  }
  return current;
}

Future<String> hashIntegrityFile(
  FileOperationBackend source,
  FileItem file,
  ChecksumAlgorithm algorithm, {
  bool Function()? isCancelled,
  void Function(int bytes, int? total)? onProgress,
}) async {
  final current = await requireIntegrityFile(
    source,
    file,
    isCancelled: isCancelled,
  );
  final digest = ChecksumAccumulator(algorithm);
  var bytes = 0;
  await for (final chunk in source.readFile(current)) {
    checkIntegrityCurrent(source, isCancelled);
    bytes += chunk.length;
    digest.add(chunk);
    onProgress?.call(bytes, current.size);
  }
  checkIntegrityCurrent(source, isCancelled);
  final after = await source.stat(current.path!);
  checkIntegrityCurrent(source, isCancelled);
  if (after == null ||
      !sameIntegrityVersion(current, after) ||
      (current.size != null && bytes != current.size)) {
    throw StateError(
      'The file changed while calculating its checksum: ${current.path}',
    );
  }
  return digest.finish();
}

/// Manifest references must stay beneath their base directory. Native POSIX
/// filenames may contain literal backslashes; Windows roots are always refused.
String resolveIntegrityPath(
  FileOperationBackend source,
  String base,
  String relative,
) {
  if (relative.isEmpty ||
      relative.contains('\x00') ||
      relative.startsWith('/') ||
      relative.startsWith('\\\\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(relative) ||
      source.paths.isAbsolute(relative)) {
    throw FormatException('Unsafe manifest filename: $relative');
  }
  final parts = source.paths.style == p.Style.windows
      ? relative.replaceAll('\\', '/').split('/')
      : relative.split('/');
  if (parts.any((part) => part == '..')) {
    throw FormatException('Manifest filename escapes its directory: $relative');
  }
  final result = source.paths.normalize(source.paths.joinAll([base, ...parts]));
  if (!source.isWithin(base, result)) {
    throw FormatException('Manifest filename escapes its directory: $relative');
  }
  return result;
}

Future<void> rejectIntegritySymlinkParents(
  FileOperationBackend source,
  String base,
  String path, {
  bool Function()? isCancelled,
}) async {
  var current = base;
  final relative = source.paths.relative(path, from: base);
  for (final component in source.paths.split(relative)) {
    checkIntegrityCurrent(source, isCancelled);
    final item = await source.stat(current);
    if (item == null || !item.isFolder || item.isSymlink == true) {
      throw StateError(
        'Manifest directory is missing or a symbolic link: $current',
      );
    }
    current = source.paths.join(current, component);
  }
}

Future<Uint8List> readIntegrityBytes(
  FileOperationBackend source,
  FileItem file, {
  int maxBytes = 2 * 1024 * 1024,
  bool Function()? isCancelled,
}) async {
  final current = await requireIntegrityFile(
    source,
    file,
    isCancelled: isCancelled,
  );
  if ((current.size ?? 0) > maxBytes) {
    throw const FormatException('Manifest exceeds its size limit.');
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in source.readFile(current)) {
    checkIntegrityCurrent(source, isCancelled);
    if (builder.length + chunk.length > maxBytes) {
      throw const FormatException('Manifest exceeds its size limit.');
    }
    builder.add(chunk);
  }
  final after = await source.stat(current.path!);
  checkIntegrityCurrent(source, isCancelled);
  if (after == null ||
      !sameIntegrityVersion(current, after) ||
      current.size != null && builder.length != current.size) {
    throw StateError('The manifest changed while reading it.');
  }
  return builder.takeBytes();
}

Future<void> writeIntegrityBytes(
  FileOperationBackend destination,
  String path,
  List<int> bytes, {
  required bool replace,
  bool Function()? isCancelled,
  Future<void> Function()? beforeCommit,
}) async {
  checkIntegrityCurrent(destination, isCancelled);
  if (!replace && await destination.stat(path) != null) {
    throw StateError('A file already exists: $path');
  }
  final expected = crypto.sha256.convert(bytes).toString();
  await destination.writePreparedFile(
    path,
    Stream.value(bytes),
    bytes.length,
    replace: replace,
    verifyStaged: (staged) async {
      checkIntegrityCurrent(destination, isCancelled);
      final actual = await hashIntegrityFile(
        destination,
        staged,
        ChecksumAlgorithm.sha256,
        isCancelled: isCancelled,
      );
      if (actual != expected) {
        throw StateError('The written manifest failed verification.');
      }
      await beforeCommit?.call();
      checkIntegrityCurrent(destination, isCancelled);
    },
  );
  checkIntegrityCurrent(destination, isCancelled);
}
