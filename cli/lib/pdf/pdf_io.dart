import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../adapters/bounded_download.dart';
import '../adapters/cli_adapter_factory.dart';
import '../adapters/cli_storage_client.dart';
import '../config/cli_config.dart';

typedef PdfCliAdapterFactory =
    CliStorageClient Function(String name, Map<String, dynamic> configuration);

class PdfCliException implements Exception {
  const PdfCliException(this.code, this.message, {this.exitCode = 1});

  final String code;
  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

/// Local paths are never implicitly interpreted using the default provider.
/// Remote locations opt in explicitly: cloud://configured-profile/path.pdf.
class PdfCliLocation {
  PdfCliLocation._(this.original, this.path, this.profile);

  factory PdfCliLocation.parse(String value) {
    if (value.isEmpty || value == '-' || value.contains('\u0000')) {
      throw const PdfCliException('invalidPath', 'A file path is required.', exitCode: 2);
    }
    if (!value.startsWith('cloud://')) {
      return PdfCliLocation._(value, p.normalize(p.absolute(value)), null);
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const PdfCliException(
        'invalidPath',
        'Use cloud://profile/path with no credentials, port, query or fragment.',
        exitCode: 2,
      );
    }
    final segments = uri.pathSegments;
    if (segments.isEmpty ||
        segments.any(
          (segment) =>
              segment.isEmpty ||
              segment == '.' ||
              segment == '..' ||
              segment.contains('/') ||
              segment.contains('\\') ||
              segment.contains('\u0000'),
        )) {
      throw const PdfCliException(
        'invalidPath',
        'A cloud location must identify one file using an absolute path.',
        exitCode: 2,
      );
    }
    // Retain case in profile names instead of using Uri.host's normalization.
    final slash = value.indexOf('/', 'cloud://'.length);
    final profile = value.substring('cloud://'.length, slash);
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(profile)) {
      throw const PdfCliException('invalidPath', 'Invalid cloud profile name.', exitCode: 2);
    }
    return PdfCliLocation._(value, '/${segments.join('/')}', profile);
  }

  final String original;
  final String path;
  final String? profile;
  bool get isRemote => profile != null;
  String get name => isRemote ? p.posix.basename(path) : p.basename(path);
}

class PdfCliOutput {
  const PdfCliOutput._(this.location, this.digest, this.mode);

  final PdfCliLocation location;
  final String? digest;
  final int? mode;
  bool get existed => digest != null;
}

/// Host I/O shared by the PDF CLI subcommands. It captures adapter instances,
/// uses fresh reads, bounds downloads, and rejects source/destination aliases.
/// Remote writes are preflight-checked, not an atomic conditional operation.
class PdfCliFileStore {
  PdfCliFileStore(
    this.config, {
    PdfCliAdapterFactory? adapterFactory,
    Stream<List<int>>? input,
    bool? inputHasTerminal,
  }) : _adapterFactory = adapterFactory ?? createAdapter,
       _input = input ?? stdin,
       _inputHasTerminal = inputHasTerminal ?? stdin.hasTerminal;

  final CliConfig config;
  final PdfCliAdapterFactory _adapterFactory;
  final Stream<List<int>> _input;
  final bool _inputHasTerminal;
  final _adapters = <String, CliStorageClient>{};
  final _remoteRoots = <String, Uri>{};
  final _readLocations = <PdfCliLocation>[];
  final _localReadPaths = <String>{};
  bool _inputConsumed = false;

  static const maxOutputBytes = 128 * 1024 * 1024;

  Future<Uint8List> readBytes(
    String path, {
    int maxBytes = 64 * 1024 * 1024,
  }) async {
    final location = PdfCliLocation.parse(path);
    final Uint8List bytes;
    if (location.isRemote) {
      bytes = await _readRemote(location, maxBytes: maxBytes);
    } else {
      final file = File(location.path);
      _localReadPaths.add(await file.resolveSymbolicLinks());
      bytes = await _readLocal(file, maxBytes);
    }
    _readLocations.add(location);
    return bytes;
  }

  /// Passwords and mappings can be piped through stdin. A command may consume
  /// it once; interactive terminal input is deliberately not echoed as a secret.
  Future<String> readUtf8(
    String path, {
    int maxBytes = 1024 * 1024,
    bool secret = false,
  }) async {
    final Uint8List bytes;
    if (path == '-') {
      if (_inputConsumed) {
        throw const PdfCliException(
          'stdinUsed',
          'Only one option may read stdin in a command.',
          exitCode: 2,
        );
      }
      if (_inputHasTerminal) {
        throw const PdfCliException(
          'stdinTerminal',
          'Pipe the data into stdin or supply a file.',
          exitCode: 2,
        );
      }
      _inputConsumed = true;
      bytes = await _readStream(_input, maxBytes);
    } else {
      if (secret) {
        final location = PdfCliLocation.parse(path);
        if (location.isRemote) {
          throw const PdfCliException(
            'passwordLocation',
            'Password files must be local, or use - for stdin.',
          exitCode: 2,
          );
        }
        final stat = await File(location.path).stat();
        if (!Platform.isWindows && (stat.mode & 0x3f) != 0) {
          throw const PdfCliException(
            'passwordPermissions',
            'Password files must not grant group or other access (chmod 600).',
          );
        }
      }
      bytes = await readBytes(path, maxBytes: maxBytes);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const PdfCliException('invalidEncoding', 'Expected UTF-8 input.', exitCode: 2);
    }
  }

  Future<PdfCliOutput> prepareOutput(
    String path, {
    required bool overwrite,
  }) async {
    final location = PdfCliLocation.parse(path);
    await _rejectSource(location);
    final Uint8List? previous;
    int? mode;
    if (location.isRemote) {
      final entry = await _remoteEntry(location, output: true);
      if (entry != null && !overwrite) _exists();
      previous = entry == null
          ? null
          : await _readRemote(location, maxBytes: maxOutputBytes);
    } else {
      final file = File(location.path);
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      _checkOutputType(type);
      if (type == FileSystemEntityType.file && !overwrite) _exists();
      // Requiring an existing parent avoids a typo creating a directory tree.
      if (!await file.parent.exists()) {
        throw const PdfCliException(
          'missingParent',
          'The output directory does not exist.',
        );
      }
      previous = type == FileSystemEntityType.file
          ? await _readLocal(file, maxOutputBytes)
          : null;
      if (previous != null) mode = (await file.stat()).mode & 0x1ff;
    }
    return PdfCliOutput._(
      location,
      previous == null ? null : sha256.convert(previous).toString(),
      mode,
    );
  }

  /// Commit only after the transformation and all validation have succeeded.
  /// Returns storage-specific warnings for the result JSON and stderr.
  Future<List<String>> writeOutput(PdfCliOutput output, Uint8List bytes) async {
    if (bytes.length > maxOutputBytes) {
      throw const PdfCliException('outputLimit', 'Output exceeds 128 MiB.');
    }
    final location = output.location;
    await _rejectSource(location);
    await _revalidate(output);
    if (location.isRemote) {
      final adapter = _adapter(location);
      try {
        await adapter.upload(
          bytes,
          location.name,
          p.posix.dirname(location.path),
        );
      } catch (_) {
        throw const PdfCliException(
          'writeFailed',
          'Cloud upload failed. The output may be incomplete; inputs were not overwritten.',
        );
      }
      final verified = await _readRemote(location, maxBytes: maxOutputBytes);
      if (sha256.convert(verified).toString() !=
          sha256.convert(bytes).toString()) {
        throw const PdfCliException(
          'verificationFailed',
          'Cloud output verification failed. Keep the source files and retry to a new name.',
        );
      }
      return const [
        'Cloud output uses fresh preflight checks and read-back verification; '
            'the provider interface cannot make the check and write atomic.',
      ];
    }

    final target = File(location.path);
    if (!output.existed) {
      // Reserve a fresh name exclusively. Unlike rename-over-a-target, this
      // rejects a file created after the final preflight check.
      await target.create(exclusive: true);
      await _setMode(target.path, 0x180); // 0600, before writing private data.
      await target.writeAsBytes(bytes, flush: true);
      return const [];
    }
    final staging = await target.parent.createTemp('.crisp-pdf-');
    var committed = false;
    final warnings = <String>[
      'Replacing an existing local output preserves mode bits, but not necessarily '
          'ownership, ACLs or extended attributes.',
    ];
    try {
      final staged = File(p.join(staging.path, 'output.pdf'));
      await staged.create(exclusive: true);
      await _setMode(staged.path, 0x180);
      await staged.writeAsBytes(bytes, flush: true);
      await _setMode(staged.path, output.mode ?? 0x180);
      await _rejectSource(location);
      await _revalidate(output);
      await staged.rename(target.path);
      committed = true;
    } finally {
      try {
        await staging.delete(recursive: true);
      } catch (_) {
        // A temporary-directory cleanup error must neither hide the original
        // write failure nor reclassify an already committed PDF as failed.
        if (committed) {
          warnings.add(
            'The PDF was saved, but its empty temporary directory '
            'could not be removed.',
          );
        }
      }
    }
    return warnings;
  }

  Future<void> _revalidate(PdfCliOutput output) async {
    final location = output.location;
    final Uint8List? now;
    if (location.isRemote) {
      final entry = await _remoteEntry(location, output: true);
      now = entry == null
          ? null
          : await _readRemote(location, maxBytes: maxOutputBytes);
    } else {
      final type = await FileSystemEntity.type(
        location.path,
        followLinks: false,
      );
      _checkOutputType(type);
      now = type == FileSystemEntityType.file
          ? await _readLocal(File(location.path), maxOutputBytes)
          : null;
    }
    final digest = now == null ? null : sha256.convert(now).toString();
    if (digest != output.digest) {
      throw const PdfCliException(
        'outputChanged',
        'The output changed while processing. Choose a new output name.',
      );
    }
  }

  Future<void> _rejectSource(PdfCliLocation output) async {
    if (output.isRemote) {
      _adapter(output);
      final identity = _remoteIdentity(output);
      for (final source in _readLocations.where((source) => source.isRemote)) {
        if (_remoteIdentity(source) == identity) {
          _sourceOutput();
        }
      }
      return;
    }
    final canonicalParent = await Directory(
      p.dirname(output.path),
    ).resolveSymbolicLinks();
    final canonical = p.join(canonicalParent, p.basename(output.path));
    for (final source in _localReadPaths) {
      if (p.equals(source, canonical) ||
          (Platform.isWindows &&
              source.toLowerCase() == canonical.toLowerCase())) {
        _sourceOutput();
      }
      if (await File(output.path).exists() &&
          await FileSystemEntity.identical(source, output.path)) {
        _sourceOutput();
      }
    }
  }

  CliStorageClient _adapter(PdfCliLocation location) {
    final profile = location.profile!;
    return _adapters.putIfAbsent(profile, () {
      final settings = config.providerConfig(profile, strict: true);
      if (settings == null) {
        throw PdfCliException(
          'unknownProfile',
          'Unknown cloud profile: $profile',
        );
      }
      final root = _remoteRoot(settings);
      final adapter = _adapterFactory(profile, settings);
      // Capture only the addressing fields actually used by the adapter.
      // Credentials and irrelevant configuration keys cannot create aliases.
      _remoteRoots[profile] = root;
      return adapter;
    });
  }

  String _remoteIdentity(PdfCliLocation location) {
    final root = _remoteRoots[location.profile]!;
    return root
        .replace(
          pathSegments: [
            ...root.pathSegments,
            ...location.path.substring(1).split('/'),
          ],
        )
        .toString()
        .toLowerCase();
  }

  static Uri _remoteRoot(Map<String, dynamic> settings) {
    final type = (settings['type'] as String? ?? '').toLowerCase();
    if (type == 'sftp') {
      return Uri(
        scheme: 'sftp',
        host: (settings['host'] as String? ?? '').toLowerCase(),
        port: int.tryParse('${settings['port'] ?? 22}') ?? 22,
      );
    }
    final raw = settings[type == 's3' ? 'endpoint' : 'host'] as String? ?? '';
    final base = Uri.tryParse(raw);
    if (base == null || !base.hasAuthority) {
      throw const PdfCliException(
        'invalidEndpoint',
        'The cloud profile has an invalid endpoint.',
      );
    }
    final prefix = base.pathSegments.toList();
    while (prefix.isNotEmpty && prefix.last.isEmpty) {
      prefix.removeLast();
    }
    final bucket = settings['bucket'] as String? ?? '';
    // Match S3CliAdapter's virtual-hosted endpoint rule. WebDAV profiles with
    // different base directories are compared by their complete resource URL.
    final virtualHosted = type == 's3' && raw.contains('amazonaws.com');
    return Uri(
      scheme: base.scheme,
      host: virtualHosted ? '$bucket.${base.host}' : base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: virtualHosted
          ? const []
          : [...prefix, if (type == 's3') bucket],
    );
  }

  Future<CliFileItem?> _remoteEntry(
    PdfCliLocation location, {
    bool output = false,
  }) async {
    final adapter = _adapter(location);
    final List<CliFileItem> listing;
    try {
      // stat() in existing adapters conflates absence and access failure.
      // A successful fresh parent listing is required to authorize a write.
      listing = await adapter.list(p.posix.dirname(location.path));
    } catch (_) {
      throw const PdfCliException(
        'listingFailed',
        'Could not verify the cloud directory. Check its access and retry.',
      );
    }
    final matches = listing
        .where(
          (entry) => entry.name.toLowerCase() == location.name.toLowerCase(),
        )
        .toList();
    if (matches.length > 1 ||
        (matches.isNotEmpty && matches.single.name != location.name)) {
      throw const PdfCliException(
        'ambiguousPath',
        'Cloud filename differs only by case. Use a distinct name or its exact spelling.',
      );
    }
    if (matches.isEmpty) {
      if (output) return null;
      throw const PdfCliException('notFound', 'Cloud input was not found.');
    }
    if (matches.single.isDirectory) {
      throw const PdfCliException(
        'notAFile',
        'The cloud path identifies a directory.',
      );
    }
    return matches.single;
  }

  Future<Uint8List> _readRemote(
    PdfCliLocation location, {
    required int maxBytes,
  }) async {
    final entry = await _remoteEntry(location);
    if ((entry?.size ?? 0) > maxBytes) {
      throw CliDownloadLimitException(maxBytes);
    }
    final adapter = _adapter(location);
    if (adapter is! CliBoundedDownload) {
      throw const PdfCliException(
        'unboundedAdapter',
        'This provider does not support bounded PDF downloads.',
      );
    }
    try {
      return await (adapter as CliBoundedDownload).downloadBytesBounded(
        location.path,
        maxBytes: maxBytes,
      );
    } on CliDownloadLimitException {
      rethrow;
    } catch (_) {
      throw const PdfCliException(
        'readFailed',
        'Could not read the cloud file.',
      );
    }
  }

  Future<Uint8List> _readLocal(File file, int maxBytes) async {
    if (await FileSystemEntity.type(file.path) != FileSystemEntityType.file) {
      throw const PdfCliException('notAFile', 'Input must be a regular file.');
    }
    if (await file.length() > maxBytes) {
      throw CliDownloadLimitException(maxBytes);
    }
    return _readStream(file.openRead(), maxBytes);
  }

  static Future<Uint8List> _readStream(
    Stream<List<int>> stream,
    int maxBytes,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (builder.length + chunk.length > maxBytes) {
        throw CliDownloadLimitException(maxBytes);
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static Future<void> _setMode(String path, int mode) async {
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', [mode.toRadixString(8), path]);
    if (result.exitCode != 0) {
      throw const PdfCliException(
        'permissions',
        'Could not set output file permissions.',
      );
    }
  }

  static void _checkOutputType(FileSystemEntityType type) {
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const PdfCliException(
        'invalidOutput',
        'Output must be a regular file; symbolic links and directories are refused.',
      );
    }
  }

  static Never _sourceOutput() => throw const PdfCliException(
    'sourceOutput',
    'PDF operations require a separate output file. The output aliases an input.',
  );

  static Never _exists() => throw const PdfCliException(
    'outputExists',
    'Output already exists. Choose a new path or explicitly use --overwrite.',
  );

  Future<void> dispose() async {
    for (final adapter in _adapters.values) {
      try {
        await adapter.dispose();
      } catch (_) {
        // A close error must not report a successfully committed PDF as failed.
      }
    }
    _adapters.clear();
  }
}
