import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_pty2/flutter_pty2.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'archive_external_packer_types.dart';
import 'archive_external_packer_metadata_io.dart';
import 'archive_viewer_service.dart';
import 'archive_write_model.dart';
import 'command_entry_service.dart';
import 'local_file_service.dart';
import 'native_journal_lease.dart';
import 'native_system.dart';

ArchiveExternalPackerEngine createArchiveExternalPackerEngine() =>
    NativeArchiveExternalPackerEngine();

Never _fail(ArchiveExternalPackerFailure failure) =>
    throw ArchiveExternalPackerException(failure);

void _check(bool Function()? cancelled) {
  if (cancelled?.call() ?? false) _fail(ArchiveExternalPackerFailure.cancelled);
}

/// A fixed adapter invocation. The executable and arguments are never joined
/// into shell source. Only owned private paths enter the command line.
class ArchiveExternalPackerInvocation {
  ArchiveExternalPackerInvocation({
    required this.executable,
    required List<String> arguments,
    required this.directory,
    required Map<String, String> environment,
    required this.timeout,
    this.outputPath,
    this.maxOutputBytes = kArchiveExternalPackerTotalLimit,
    this.isCancelled,
  }) : arguments = List.unmodifiable(arguments),
       environment = Map.unmodifiable(environment);
  final String executable, directory;
  final List<String> arguments;
  final Map<String, String> environment;
  final Duration timeout;
  final String? outputPath;
  final int maxOutputBytes;
  final bool Function()? isCancelled;
}

class ArchiveExternalPackerProcessResult {
  const ArchiveExternalPackerProcessResult(this.exitCode, this.output);
  final int exitCode;
  final String output;
}

typedef ArchiveExternalPackerProcessRunner =
    Future<ArchiveExternalPackerProcessResult> Function(
      ArchiveExternalPackerInvocation invocation,
    );

/// Desktop-only, separately installed foreground CLI binaries. The default
/// host preserves the existing Mac App Store restriction on host processes.
class NativeArchiveExternalPackerEngine implements ArchiveExternalPackerEngine {
  NativeArchiveExternalPackerEngine({
    CommandEntryHost? executableHost,
    Future<bool> Function(String)? hasAccess,
    ArchiveExternalPackerProcessRunner? runner,
    this.stagingRoot,
  }) : _host = executableHost ?? const NativeCommandEntryHost(),
       _hasAccess = hasAccess ?? LocalFileService().hasAccessToPath,
       _runner = runner ?? runArchiveExternalPackerProcess;

  final CommandEntryHost _host;
  final Future<bool> Function(String) _hasAccess;
  final ArchiveExternalPackerProcessRunner _runner;
  final Future<String> Function()? stagingRoot;
  @override
  String? get platform => _host.platform;

  @override
  Future<List<ArchiveExternalPackerConfiguration>> discover() async {
    if (platform == null) return const [];
    final paths = platform == 'windows' ? p.windows : p.posix;
    final directories = <String>{
      for (final directory in _host.searchPath)
        if (directory.isNotEmpty && paths.isAbsolute(directory)) directory,
      if (platform == 'linux') ...['/usr/bin', '/usr/local/bin'],
      if (platform == 'macos') ...['/opt/homebrew/bin', '/usr/local/bin'],
      if (platform == 'windows')
        for (final key in ['ProgramFiles', 'ProgramFiles(x86)'])
          if (Platform.environment[key] case final String root)
            if (paths.isAbsolute(root)) ...[
              paths.join(root, '7-Zip'),
              paths.join(root, 'WinRAR'),
            ],
    };
    final found = <ArchiveExternalPackerConfiguration>[];
    final visited = <String>{};
    for (final kind in ArchiveExternalPackerKind.values) {
      final names = kind == ArchiveExternalPackerKind.sevenZip
          ? ['7zz', '7z']
          : ['rar'];
      for (final directory in directories.take(128)) {
        for (final name in names) {
          final candidate = paths.join(
            directory,
            platform == 'windows' ? '$name.exe' : name,
          );
          try {
            final configuration = ArchiveExternalPackerConfiguration(
              platform: platform!,
              kind: kind,
              executable: candidate,
            );
            final identity = await _identity(configuration);
            if (visited.add(identity.path)) {
              found.add(
                ArchiveExternalPackerConfiguration(
                  platform: platform!,
                  kind: kind,
                  executable: identity.path,
                ),
              );
            }
          } catch (_) {
            // Discovery reads existing files only; unusable candidates are
            // absent. The selected candidate is explicitly probed separately.
          }
        }
      }
    }
    return List.unmodifiable(found);
  }

  Future<ArchiveExternalPackerIdentity> _identity(
    ArchiveExternalPackerConfiguration configuration,
  ) async {
    configuration.validate();
    if (platform == null) {
      _fail(ArchiveExternalPackerFailure.unsupportedPlatform);
    }
    if (configuration.platform != platform ||
        !await _hasAccess(configuration.executable)) {
      _fail(ArchiveExternalPackerFailure.unavailable);
    }
    final before = await _host.inspect(configuration.executable);
    if (before == null ||
        before.isDirectory ||
        before.size < 4 ||
        before.size > 128 * 1024 * 1024 ||
        platform != 'windows' && before.mode & 0x49 == 0 ||
        !await _hasAccess(before.resolvedPath)) {
      _fail(ArchiveExternalPackerFailure.unavailable);
    }
    final file = File(before.resolvedPath);
    final header = await file.open();
    late final List<int> magic;
    try {
      magic = await header.read(4);
    } finally {
      await header.close();
    }
    if (magic.length != 4) _fail(ArchiveExternalPackerFailure.changed);
    // Reject scripts/interpreters and launcher wrappers. Official CLI binaries
    // run in the owned process session; no shell is needed for any operation.
    final signature = magic.fold<int>(0, (value, byte) => value * 256 + byte);
    final native = platform == 'windows'
        ? magic[0] == 0x4d && magic[1] == 0x5a
        : platform == 'linux'
        ? signature == 0x7f454c46
        : const {
            0xfeedface,
            0xfeedfacf,
            0xcefaedfe,
            0xcffaedfe,
            0xcafebabe,
            0xbebafeca,
            0xcafebabf,
            0xbfbafeca,
          }.contains(signature);
    if (!native) _fail(ArchiveExternalPackerFailure.unavailable);
    var count = 0;
    final digest = await sha256
        .bind(
          file.openRead(0, before.size + 1).map((bytes) {
            count += bytes.length;
            return bytes;
          }),
        )
        .single;
    if (count != before.size ||
        await _host.inspect(configuration.executable) != before) {
      _fail(ArchiveExternalPackerFailure.changed);
    }
    return ArchiveExternalPackerIdentity(
      path: before.resolvedPath,
      length: before.size,
      modified: before.modified,
      changed: before.changed,
      mode: before.mode,
      sha256: digest.toString(),
    );
  }

  Future<void> _revalidate(
    ArchiveExternalPackerInstallation installation,
  ) async {
    if (await _identity(installation.configuration) != installation.identity) {
      _fail(ArchiveExternalPackerFailure.changed);
    }
  }

  @override
  Future<ArchiveExternalPackerInstallation> probe(
    ArchiveExternalPackerConfiguration configuration, {
    bool Function()? isCancelled,
  }) async {
    _check(isCancelled);
    final identity = await _identity(configuration);
    final stage = await _PackerStage.create(stagingRoot);
    var cleanup = true;
    late String version;
    try {
      _check(isCancelled);
      final result = await _runner(
        ArchiveExternalPackerInvocation(
          executable: identity.path,
          arguments: configuration.kind == ArchiveExternalPackerKind.sevenZip
              ? ['i', '-sccUTF-8', '-bsp0']
              : ['-?', '-cfg-'],
          directory: stage.directory.path,
          environment: stage.environment,
          timeout: const Duration(seconds: 10),
          isCancelled: isCancelled,
        ),
      );
      if (result.exitCode != 0) _fail(ArchiveExternalPackerFailure.unavailable);
      final pattern = configuration.kind == ArchiveExternalPackerKind.sevenZip
          ? RegExp(
              r'7-Zip(?:\s+\([^\r\n]+?\)|\s+\[[^\r\n]+?\])?\s+(\d+\.\d+(?:\.\d+)*)',
              caseSensitive: false,
            )
          : RegExp(r'(?:^|\s)RAR\s+(\d+\.\d+(?:\.\d+)*)');
      final parsed = pattern.firstMatch(result.output)?.group(1);
      if (parsed == null ||
          parsed.length > 32 ||
          int.parse(parsed.split('.').first) <
              (configuration.kind == ArchiveExternalPackerKind.sevenZip
                  ? 21
                  : 7)) {
        _fail(ArchiveExternalPackerFailure.unavailable);
      }
      version = parsed;
      if (await _identity(configuration) != identity) {
        _fail(ArchiveExternalPackerFailure.changed);
      }
    } on ArchiveExternalPackerException catch (error) {
      cleanup = error.failure != ArchiveExternalPackerFailure.cleanupFailed;
      rethrow;
    } finally {
      await stage.close(delete: cleanup);
    }
    final candidates = configuration.kind == ArchiveExternalPackerKind.sevenZip
        ? {
            ArchiveExternalPackerFormat.zip,
            ArchiveExternalPackerFormat.sevenZip,
          }
        : {ArchiveExternalPackerFormat.rar};
    final detected = ArchiveExternalPackerInstallation(
      configuration: configuration,
      identity: identity,
      version: version,
      formats: candidates,
    );
    final supported = <ArchiveExternalPackerFormat>{};
    for (final format in candidates) {
      _check(isCancelled);
      try {
        for (final compression in ArchiveExternalPackerCompression.values) {
          await _probeFormat(detected, format, compression, isCancelled);
        }
        supported.add(format);
      } on ArchiveExternalPackerException catch (error) {
        if (const {
          ArchiveExternalPackerFailure.cancelled,
          ArchiveExternalPackerFailure.changed,
          ArchiveExternalPackerFailure.cleanupFailed,
        }.contains(error.failure)) {
          rethrow;
        }
      } on ArchiveViewException {
        // A valid tool may not preserve this format's complete tested profile.
      }
    }
    if (supported.isEmpty) {
      _fail(ArchiveExternalPackerFailure.capabilityCheckFailed);
    }
    return ArchiveExternalPackerInstallation(
      configuration: configuration,
      identity: identity,
      version: version,
      formats: supported,
    );
  }

  Future<void> _probeFormat(
    ArchiveExternalPackerInstallation installation,
    ArchiveExternalPackerFormat format,
    ArchiveExternalPackerCompression compression,
    bool Function()? cancelled,
  ) async {
    // Compressible data must be long enough that Normal/Maximum actually
    // exercise the decoder, rather than the tool choosing Store for a tiny file.
    final bytes = utf8.encode(
      'CrispCloud installed packer verification\n' * 128,
    );
    final date = DateTime.utc(
      2024,
      1,
      2,
      3,
      4,
      5,
      format == ArchiveExternalPackerFormat.zip ? 0 : 123,
      format == ArchiveExternalPackerFormat.rar ? 456 : 0,
    );
    final entries = [
      ArchiveWriteEntry(
        path: 'folder',
        isDirectory: true,
        size: 0,
        modified: date,
        mode: platform == 'windows' ? null : 0x1e8,
      ),
      ArchiveWriteEntry(
        path: 'folder/日本語 file.txt',
        isDirectory: false,
        size: bytes.length,
        modified: date,
        mode: platform == 'windows' ? null : 0x1a0,
        readChunks: () => Stream.value(bytes),
      ),
      ArchiveWriteEntry(
        path: 'empty',
        isDirectory: true,
        size: 0,
        modified: date,
        mode: platform == 'windows' ? null : 0x1c0,
      ),
    ];
    final output = await collectArchiveWrite(
      (sink) => write(
        installation: installation,
        options: ArchiveExternalPackerOptions(
          name: 'probe${format.extension}',
          format: format,
          compression: compression,
        ),
        entries: entries,
        sink: sink,
        maxOutputBytes: 2 * 1024 * 1024,
        isCancelled: cancelled,
      ),
      maxBytes: 2 * 1024 * 1024,
    );
    if (compression != ArchiveExternalPackerCompression.store &&
        output.length >= bytes.length) {
      _fail(ArchiveExternalPackerFailure.invalidOutput);
    }
    final archive = await openViewerArchive(
      output,
      name: 'probe${format.extension}',
    );
    try {
      if (archive.members.length != entries.length ||
          archive.formatName.toLowerCase() !=
              (format == ArchiveExternalPackerFormat.sevenZip
                  ? '7z'
                  : format.name)) {
        _fail(ArchiveExternalPackerFailure.invalidOutput);
      }
      final remaining = {for (final entry in entries) entry.path: entry};
      for (final member in archive.members) {
        final expected = remaining.remove(
          member.name.replaceFirst(RegExp(r'/+$'), ''),
        );
        if (expected == null ||
            member.pathEscapedRoot ||
            member.isSpecial ||
            member.isEncrypted ||
            member.isFile == expected.isDirectory ||
            member.size != expected.size ||
            member.modified?.isAtSameMomentAs(date) != true ||
            expected.mode != null &&
                (member.posixMode == null ||
                    member.posixMode! & 0xfff != expected.mode)) {
          _fail(ArchiveExternalPackerFailure.invalidOutput);
        }
        if (member.isFile &&
            sha256.convert(await archive.readMember(member)) !=
                sha256.convert(bytes)) {
          _fail(ArchiveExternalPackerFailure.invalidOutput);
        }
      }
      if (remaining.isNotEmpty) {
        _fail(ArchiveExternalPackerFailure.invalidOutput);
      }
    } finally {
      await archive.close();
    }
  }

  @override
  Future<void> write({
    required ArchiveExternalPackerInstallation installation,
    required ArchiveExternalPackerOptions options,
    required List<ArchiveWriteEntry> entries,
    required Future<void> Function(List<int>) sink,
    required int maxOutputBytes,
    bool Function()? isCancelled,
  }) async {
    _check(isCancelled);
    if (!installation.formats.contains(options.format) ||
        installation.configuration.kind == ArchiveExternalPackerKind.rar &&
            options.format != ArchiveExternalPackerFormat.rar ||
        installation.configuration.kind == ArchiveExternalPackerKind.sevenZip &&
            options.format == ArchiveExternalPackerFormat.rar) {
      _fail(ArchiveExternalPackerFailure.unsupportedFormat);
    }
    if (maxOutputBytes <= 0 ||
        maxOutputBytes > kArchiveExternalPackerTotalLimit) {
      _fail(ArchiveExternalPackerFailure.outputTooLarge);
    }
    _validateEntries(entries, installation.configuration.kind);
    await _revalidate(installation);
    final stage = await _PackerStage.create(stagingRoot);
    var cleanup = true;
    try {
      await stage.capture(
        entries,
        installation.configuration.kind,
        isCancelled,
      );
      await _revalidate(installation);
      final output = p.join(
        stage.output.path,
        'candidate${options.format.extension}',
      );
      final invocation = ArchiveExternalPackerInvocation(
        executable: installation.identity.path,
        arguments: _arguments(
          installation.configuration.kind,
          options,
          stage,
          output,
        ),
        directory: stage.input.path,
        environment: stage.environment,
        timeout: const Duration(minutes: 5),
        outputPath: output,
        maxOutputBytes: maxOutputBytes,
        isCancelled: isCancelled,
      );
      final result = await _runner(invocation);
      _check(isCancelled);
      // Warnings can mean skipped or unreadable input. Only exact success can
      // proceed to the independent reader and publication checks.
      if (result.exitCode != 0) {
        _fail(ArchiveExternalPackerFailure.processFailed);
      }
      await _revalidate(installation);
      await stage.verifyInputs(entries, isCancelled);
      var outputCount = 0;
      await for (final object in stage.output.list(followLinks: false)) {
        if (++outputCount > 1 || object.path != output) {
          _fail(ArchiveExternalPackerFailure.invalidOutput);
        }
      }
      if (outputCount != 1 ||
          await FileSystemEntity.type(output, followLinks: false) !=
              FileSystemEntityType.file ||
          p.normalize(await File(output).resolveSymbolicLinks()) != output) {
        _fail(ArchiveExternalPackerFailure.invalidOutput);
      }
      final before = await File(output).stat();
      if (before.size <= 0 || before.size > maxOutputBytes) {
        _fail(ArchiveExternalPackerFailure.outputTooLarge);
      }
      var count = 0;
      await for (final chunk in File(output).openRead(0, maxOutputBytes + 1)) {
        _check(isCancelled);
        if (chunk.length > before.size - count) {
          _fail(ArchiveExternalPackerFailure.changed);
        }
        count += chunk.length;
        await sink(chunk);
      }
      if (count != before.size ||
          !_sameStat(before, await File(output).stat())) {
        _fail(ArchiveExternalPackerFailure.changed);
      }
    } on ArchiveExternalPackerException catch (error) {
      cleanup = error.failure != ArchiveExternalPackerFailure.cleanupFailed;
      rethrow;
    } finally {
      await stage.close(delete: cleanup);
    }
  }

  void _validateEntries(
    List<ArchiveWriteEntry> entries,
    ArchiveExternalPackerKind kind,
  ) {
    validateArchiveWriteEntries(entries);
    final names = <String>{};
    final explicit = {
      for (final entry in entries) entry.path: entry.isDirectory,
    };
    var total = 0;
    for (final entry in entries) {
      if (entry.attributes.isNotEmpty ||
          entry.size > kArchiveExternalPackerMemberLimit ||
          (total += entry.size) > kArchiveExternalPackerTotalLimit) {
        _fail(ArchiveExternalPackerFailure.unsupportedEntry);
      }
      final parts = entry.path.split('/');
      if (parts.any((part) => utf8.encode(part).length > 240) ||
          kind == ArchiveExternalPackerKind.rar &&
              RegExp(r'[?*]').hasMatch(entry.path) ||
          platform == 'windows' &&
              parts.any(
                (part) =>
                    RegExp(r'[<>:"|?*]').hasMatch(part) ||
                    part.endsWith('.') ||
                    part.endsWith(' ') ||
                    RegExp(
                      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
                      caseSensitive: false,
                    ).hasMatch(part),
              )) {
        _fail(ArchiveExternalPackerFailure.unsupportedEntry);
      }
      final key = platform == 'linux' ? entry.path : entry.path.toLowerCase();
      if (!names.add(key)) _fail(ArchiveExternalPackerFailure.unsupportedEntry);
      for (var end = 1; end < parts.length; end++) {
        if (explicit[parts.take(end).join('/')] != true) {
          _fail(ArchiveExternalPackerFailure.unsupportedEntry);
        }
      }
      final mode = entry.mode;
      if (mode != null &&
          (platform == 'windows' ||
              mode < 0 ||
              mode > 0xffff ||
              mode & 0xf000 != 0 &&
                  mode & 0xf000 != (entry.isDirectory ? 0x4000 : 0x8000) ||
              mode & 0xc00 != 0 ||
              mode & (entry.isDirectory ? 0x140 : 0x100) !=
                  (entry.isDirectory ? 0x140 : 0x100))) {
        _fail(ArchiveExternalPackerFailure.unsupportedEntry);
      }
    }
  }
}

List<String> _arguments(
  ArchiveExternalPackerKind kind,
  ArchiveExternalPackerOptions options,
  _PackerStage stage,
  String output,
) {
  final level = switch (options.compression) {
    ArchiveExternalPackerCompression.store => 0,
    ArchiveExternalPackerCompression.normal =>
      kind == ArchiveExternalPackerKind.rar ? 3 : 5,
    ArchiveExternalPackerCompression.maximum =>
      kind == ArchiveExternalPackerKind.rar ? 5 : 9,
  };
  if (kind == ArchiveExternalPackerKind.rar) {
    return [
      'a',
      '-cfg-',
      '-ma5',
      '-m$level',
      '-s-',
      '-r-',
      '-mt2',
      '-idq',
      '-scfl',
      '-tsm+',
      '-tsc-',
      '-tsa-',
      '-w${stage.temporary.path}',
      output,
      '@${stage.listFile.path}',
    ];
  }
  return [
    'a',
    '-t${options.format == ArchiveExternalPackerFormat.zip ? 'zip' : '7z'}',
    '-mx=$level',
    '-mmt=2',
    '-r-',
    '-spd',
    '-sse',
    '-y',
    '-bd',
    '-bso0',
    '-bsp0',
    '-bse1',
    '-sccUTF-8',
    '-scsUTF-8',
    '-mta=off',
    '-mtc=off',
    '-mtm=on',
    if (options.format == ArchiveExternalPackerFormat.sevenZip) ...[
      '-ms=off',
      '-m0=${level == 0 ? 'Copy' : 'LZMA2'}',
      if (level != 0) '-md=16m',
    ] else ...[
      '-mm=${level == 0 ? 'Copy' : 'Deflate'}',
      // The shared ZIP creation contract preserves UTC seconds. Ask the
      // vendor to emit its documented Unix extra field, not only NTFS time.
      '-mtp=1',
    ],
    '-w${stage.temporary.path}',
    output,
    '@${stage.listFile.path}',
  ];
}

bool _sameStat(FileStat a, FileStat b) =>
    a.type == b.type &&
    a.size == b.size &&
    a.modified == b.modified &&
    a.changed == b.changed &&
    a.mode == b.mode;

class _PackerStage {
  _PackerStage(this.directory, this.lease);
  final Directory directory;
  final NativeJournalLease lease;
  Directory get input => Directory(p.join(directory.path, 'input'));
  Directory get output => Directory(p.join(directory.path, 'output'));
  Directory get temporary => Directory(p.join(directory.path, 'temporary'));
  File get listFile => File(p.join(directory.path, 'members.txt'));
  final _digests = <String, String>{};

  Map<String, String> get environment => {
    'HOME': directory.path,
    'USERPROFILE': directory.path,
    'TMPDIR': temporary.path,
    'TMP': temporary.path,
    'TEMP': temporary.path,
    'LC_ALL': 'C.UTF-8',
    'LANG': 'C.UTF-8',
    'TZ': 'UTC',
    'TERM': 'dumb',
    if (Platform.isWindows && Platform.environment['SystemRoot'] != null)
      'SystemRoot': Platform.environment['SystemRoot']!,
    if (Platform.isWindows && Platform.environment['WINDIR'] != null)
      'WINDIR': Platform.environment['WINDIR']!,
  };

  static Future<_PackerStage> create(
    Future<String> Function()? rootProvider,
  ) async {
    final requested = rootProvider == null
        ? p.join(
            (await getApplicationSupportDirectory()).path,
            'archive_external_packer_v1',
          )
        : await rootProvider();
    if (!p.isAbsolute(requested) || requested.contains('\u0000')) {
      _fail(ArchiveExternalPackerFailure.unavailable);
    }
    final parent = Directory(p.dirname(requested));
    await parent.create(recursive: true);
    final root = Directory(
      p.join(await parent.resolveSymbolicLinks(), p.basename(requested)),
    );
    final rootType = await FileSystemEntity.type(root.path, followLinks: false);
    if (rootType == FileSystemEntityType.notFound) {
      await root.create();
      _mode(root.path, 0x1c0);
    }
    await _privateDirectory(root);
    final directory = Directory(p.join(root.path, const Uuid().v4()));
    await directory.create();
    _mode(directory.path, 0x1c0);
    NativeJournalLease? lease;
    try {
      await _privateDirectory(directory);
      lease = await tryAcquireNativeJournalLease(
        p.join(directory.path, 'lease'),
      );
      if (lease == null) _fail(ArchiveExternalPackerFailure.unavailable);
      final stage = _PackerStage(directory, lease);
      for (final child in [stage.input, stage.output, stage.temporary]) {
        await child.create();
        _mode(child.path, 0x1c0);
      }
      return stage;
    } catch (_) {
      lease?.close();
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  static void _mode(String path, int mode) {
    if (!Platform.isWindows && !setFileMode(path, mode)) {
      _fail(ArchiveExternalPackerFailure.unavailable);
    }
  }

  static Future<void> _privateDirectory(Directory directory) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        p.normalize(await directory.resolveSymbolicLinks()) != directory.path ||
        !Platform.isWindows &&
            ((await directory.stat()).mode & 0x3f != 0 ||
                currentUserId() == null ||
                fileOwnerUserId(directory.path) != currentUserId())) {
      _fail(ArchiveExternalPackerFailure.changed);
    }
  }

  Future<void> capture(
    List<ArchiveWriteEntry> entries,
    ArchiveExternalPackerKind kind,
    bool Function()? cancelled,
  ) async {
    await _privateDirectory(directory);
    final folders = entries.where((entry) => entry.isDirectory).toList()
      ..sort(
        (a, b) => a.path.split('/').length.compareTo(b.path.split('/').length),
      );
    for (final entry in folders) {
      _check(cancelled);
      final folder = Directory(
        p.joinAll([input.path, ...entry.path.split('/')]),
      );
      if (await FileSystemEntity.type(folder.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        _fail(ArchiveExternalPackerFailure.changed);
      }
      await folder.create();
      _mode(folder.path, 0x1c0);
    }
    for (final entry in entries.where((entry) => !entry.isDirectory)) {
      _check(cancelled);
      final file = File(p.joinAll([input.path, ...entry.path.split('/')]));
      await file.create(exclusive: true);
      _mode(file.path, 0x180);
      final output = await file.open(mode: FileMode.writeOnly);
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      try {
        await for (final chunk in entry.openRead()) {
          _check(cancelled);
          await output.writeFrom(chunk);
          hash.add(chunk);
        }
        await output.flush();
      } finally {
        hash.close();
        await output.close();
      }
      _digests[entry.path] = digest.value!.toString();
      if (entry.modified != null) {
        await setArchiveExternalPackerModified(
          file.path,
          entry.modified!,
          isDirectory: false,
        );
      }
      if (entry.mode != null) _mode(file.path, entry.mode! & 0xfff);
    }
    for (final entry in folders.reversed) {
      final folder = Directory(
        p.joinAll([input.path, ...entry.path.split('/')]),
      );
      if (entry.modified != null) {
        await setArchiveExternalPackerModified(
          folder.path,
          entry.modified!,
          isDirectory: true,
        );
      }
      if (entry.mode != null) _mode(folder.path, entry.mode! & 0xfff);
    }
    // List-file names are data, not shell or switch source. A ./ prefix keeps
    // leading '-' and '@' literal; control characters were rejected above.
    // 7-Zip recursively captures each explicitly listed directory even with
    // -r-. Listing its children again changes their stored base paths. RAR's
    // -r- instead includes only listed entries, so it needs the complete list.
    final listed = kind == ArchiveExternalPackerKind.sevenZip
        ? entries.where((entry) => !entry.path.contains('/'))
        : entries;
    await listFile.writeAsString(
      '${listed.map((entry) => './${entry.path}').join('\n')}\n',
      flush: true,
    );
    _mode(listFile.path, 0x180);
    await verifyInputs(entries, cancelled);
  }

  Future<void> verifyInputs(
    List<ArchiveWriteEntry> entries,
    bool Function()? cancelled,
  ) async {
    await _privateDirectory(directory);
    final expected = {for (final entry in entries) entry.path: entry};
    await for (final object in input.list(
      recursive: true,
      followLinks: false,
    )) {
      _check(cancelled);
      final name = p
          .relative(object.path, from: input.path)
          .split(p.separator)
          .join('/');
      final entry = expected.remove(name);
      final kind = await FileSystemEntity.type(object.path, followLinks: false);
      if (entry == null ||
          kind !=
              (entry.isDirectory
                  ? FileSystemEntityType.directory
                  : FileSystemEntityType.file) ||
          p.normalize(await object.resolveSymbolicLinks()) != object.path) {
        _fail(ArchiveExternalPackerFailure.changed);
      }
      final before = await object.stat();
      if ((!entry.isDirectory && before.size != entry.size) ||
          entry.modified != null &&
              !before.modified.isAtSameMomentAs(entry.modified!) ||
          entry.mode != null && before.mode & 0xfff != entry.mode! & 0xfff) {
        _fail(ArchiveExternalPackerFailure.changed);
      }
      if (!entry.isDirectory) {
        var length = 0;
        final digest = await sha256
            .bind(
              File(object.path).openRead(0, entry.size + 1).map((bytes) {
                _check(cancelled);
                length += bytes.length;
                if (length > entry.size) {
                  _fail(ArchiveExternalPackerFailure.changed);
                }
                return bytes;
              }),
            )
            .single;
        if (length != entry.size ||
            digest.toString() != _digests[name] ||
            !_sameStat(before, await object.stat())) {
          _fail(ArchiveExternalPackerFailure.changed);
        }
      }
    }
    if (expected.isNotEmpty) _fail(ArchiveExternalPackerFailure.changed);
  }

  Future<void> close({required bool delete}) async {
    try {
      if (delete) {
        await _privateDirectory(directory.parent);
        await _privateDirectory(directory);
        // Read-only source directory modes must not prevent private cleanup.
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is Directory) _mode(entity.path, 0x1c0);
        }
      }
    } finally {
      lease.close();
    }
    if (delete) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        _fail(ArchiveExternalPackerFailure.cleanupFailed);
      }
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Uses the already-shipped PTY native transport solely as a directly executed
/// process session. Its native POSIX groups / Windows jobs own cancellation;
/// no command interpreter, command string or detached process is involved.
Future<ArchiveExternalPackerProcessResult> runArchiveExternalPackerProcess(
  ArchiveExternalPackerInvocation invocation,
) async {
  _check(invocation.isCancelled);
  PtySession? session;
  StreamSubscription<Uint8List>? subscription;
  Timer? monitor;
  final output = BytesBuilder(copy: false);
  final stopped = Completer<PtyExit>();
  var checking = false, logBytes = 0;
  try {
    session = await Pty.spawn(
      PtySpawnOptions(
        executable: invocation.executable,
        arguments: invocation.arguments,
        workingDirectory: invocation.directory,
        environment: PtyEnvironment.replace(invocation.environment),
        size: const PtySize(columns: 160, rows: 40),
        outputWindowBytes: 64 * 1024,
      ),
    );
    subscription = session.output.listen(
      (chunk) {
        logBytes += chunk.length;
        if (output.length < 64 * 1024) {
          output.add(chunk.take(64 * 1024 - output.length).toList());
        }
        if (logBytes > 2 * 1024 * 1024 && !stopped.isCompleted) {
          stopped.completeError(
            const ArchiveExternalPackerException(
              ArchiveExternalPackerFailure.outputTooLarge,
            ),
          );
        }
      },
      onError: (Object _) {
        if (!stopped.isCompleted) {
          stopped.completeError(
            const ArchiveExternalPackerException(
              ArchiveExternalPackerFailure.processFailed,
            ),
          );
        }
      },
    );
    monitor = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (checking || stopped.isCompleted) return;
      checking = true;
      try {
        _check(invocation.isCancelled);
        if (invocation.outputPath case final String path) {
          final stat = await File(path).stat();
          if (stat.type != FileSystemEntityType.notFound &&
              (stat.type != FileSystemEntityType.file ||
                  stat.size > invocation.maxOutputBytes)) {
            _fail(ArchiveExternalPackerFailure.outputTooLarge);
          }
        }
      } catch (error, stack) {
        if (!stopped.isCompleted) stopped.completeError(error, stack);
      } finally {
        checking = false;
      }
    });
    final exit = await Future.any([session.done, stopped.future])
        .timeout(invocation.timeout);
    _check(invocation.isCancelled);
    return ArchiveExternalPackerProcessResult(switch (exit) {
      PtyExitCode(:final code) => code,
      PtySignalExit(:final signal) => 128 + signal,
    }, utf8.decode(output.takeBytes(), allowMalformed: true));
  } on TimeoutException {
    _fail(ArchiveExternalPackerFailure.timeout);
  } on PtyException {
    _fail(ArchiveExternalPackerFailure.unavailable);
  } finally {
    monitor?.cancel();
    if (session != null) {
      try {
        await session.close().timeout(const Duration(seconds: 5));
      } catch (_) {
        // A possibly live child must not race recursive staging deletion.
        _fail(ArchiveExternalPackerFailure.cleanupFailed);
      } finally {
        await subscription?.cancel();
      }
    }
  }
}
