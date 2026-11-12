import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:quds_office_engine/quds_office_engine.dart';
import 'installed_office_converter_models.dart';
import 'installed_office_converter_scripts.dart';
import 'word_conversion_inspection.dart';

bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Probes existing applications only. No installation, downloads, preference
/// changes, COM application startup, or AppleEvents occur during discovery.
Future<List<InstalledOfficeInstallation>> discoverInstalledOfficeConverters({
  String? libreOfficeExecutable,
  Duration probeTimeout = const Duration(seconds: 8),
}) async {
  if (!_desktop) return const [];
  final found = <InstalledOfficeInstallation>[];
  if (Platform.isWindows) {
    final powershell = _windowsPowerShell();
    if (powershell != null) {
      try {
        final result = await _runProcess(
          powershell,
          _powershellArguments(installedOfficeWordProbeScript),
          timeout: probeTimeout,
        );
        if (result.exitCode == 0 &&
            result.stdout.contains('CRISPCLOUD_WORD_AVAILABLE')) {
          found.add(
            InstalledOfficeInstallation(
              kind: InstalledOfficeKind.microsoftWord,
              displayName: 'Microsoft Word',
              executablePath: powershell,
            ),
          );
        }
      } catch (_) {
        // A registered but blocked automation host is not offered.
      }
    }
  }
  final candidates = _libreOfficeCandidates(libreOfficeExecutable);
  final visited = <String>{};
  for (final candidate in candidates) {
    try {
      final executable = await File(candidate).resolveSymbolicLinks();
      if (!visited.add(executable)) continue;
      if ((await File(executable).stat()).type != FileSystemEntityType.file) {
        continue;
      }
      final workspace = await Directory.systemTemp.createTemp(
        'crisp-office-probe-',
      );
      try {
        final profile = Directory(p.join(workspace.path, 'profile'));
        await _writeLibreOfficeProfile(profile);
        final result = await _runProcess(
          executable,
          ['-env:UserInstallation=${profile.uri}', '--version'],
          timeout: probeTimeout,
          workingDirectory: workspace.path,
          environment: _temporaryEnvironment(workspace),
        );
        final version = RegExp(
          r'LibreOffice(?:Dev)?\s+(\d+(?:\.\d+)+(?:[.\w-]*))',
        ).firstMatch(result.stdout)?.group(1);
        final major = int.tryParse(version?.split('.').first ?? '');
        if (result.exitCode == 0 && version != null && (major ?? 0) >= 7) {
          found.add(
            InstalledOfficeInstallation(
              kind: InstalledOfficeKind.libreOffice,
              displayName: 'LibreOffice',
              version: version,
              executablePath: executable,
            ),
          );
          break;
        }
      } finally {
        await _deleteWorkspace(workspace);
      }
    } catch (_) {
      // Missing, outdated, unlaunchable, or sandbox-blocked candidates are not
      // evidence that an installed converter is usable by this process.
    }
  }
  // Word for Mac is deliberately absent: JXA/AppleScript has no verified
  // per-open macro policy here, and the shipping app is sandboxed. Do not
  // weaken another app's preferences or request broad scripting exceptions.
  return List.unmodifiable(found);
}

/// Converts a bounded, unencrypted binary DOC/DOT copy in an owned temporary
/// directory. The original storage provider and output destination are never
/// available to the child process. Returns its output bytes unchanged.
///
/// The caller must validate the OOXML package, inspect preservation, and save a
/// new file. A ZIP signature alone is not proof of a valid Word document.
/// PDF previews also accept inspected DOCX/DOCM packages and never save over
/// either the source or the converted Word package.
Future<InstalledOfficeConversionResult> convertWithInstalledOffice({
  required Uint8List bytes,
  required String sourceName,
  required InstalledOfficeInstallation installation,
  InstalledOfficeOutput output = InstalledOfficeOutput.docx,
  Duration timeout = kInstalledOfficeDefaultTimeout,
}) async {
  if (!_desktop) {
    throw const InstalledOfficeConversionException(
      InstalledOfficeConversionErrorCode.unsupportedPlatform,
    );
  }
  if (!installation.supportedOutputs.contains(output)) {
    throw const InstalledOfficeConversionException(
      InstalledOfficeConversionErrorCode.unsupportedOutput,
    );
  }
  if (installation.kind == InstalledOfficeKind.microsoftWord &&
      !Platform.isWindows) {
    throw const InstalledOfficeConversionException(
      InstalledOfficeConversionErrorCode.unsafeAutomation,
    );
  }
  if (timeout <= Duration.zero || timeout > const Duration(minutes: 10)) {
    throw ArgumentError.value(timeout, 'timeout');
  }
  await _validateInput(bytes, sourceName, output);
  final clock = Stopwatch()..start();
  Directory? workspace;
  try {
    if (!p.isAbsolute(installation.executablePath) ||
        !await File(installation.executablePath).exists()) {
      throw const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.unavailable,
      );
    }
    workspace = await Directory.systemTemp.createTemp('crisp-office-convert-');
    final inputExtension = p.extension(sourceName).toLowerCase();
    final input = File(p.join(workspace.path, 'input$inputExtension'));
    final outputDirectory = await Directory(
      p.join(workspace.path, 'output'),
    ).create();
    final converted = File(
      p.join(outputDirectory.path, 'input.${output.extension}'),
    );
    await input.writeAsBytes(bytes, flush: true);
    final environment = _temporaryEnvironment(workspace);
    _OfficeProcessResult result;
    if (installation.kind == InstalledOfficeKind.libreOffice) {
      final profile = Directory(p.join(workspace.path, 'profile'));
      await _writeLibreOfficeProfile(profile);
      final filter = switch (output) {
        InstalledOfficeOutput.docx => 'Office Open XML Text',
        InstalledOfficeOutput.docm => 'MS Word 2007 XML VBA',
        InstalledOfficeOutput.pdf => 'writer_pdf_Export',
      };
      result = await _runProcess(
        installation.executablePath,
        [
          '-env:UserInstallation=${profile.uri}',
          '--headless',
          '--nologo',
          '--nodefault',
          '--norestore',
          '--convert-to',
          '${output.extension}:$filter',
          '--outdir',
          outputDirectory.path,
          input.path,
        ],
        timeout: timeout,
        workingDirectory: workspace.path,
        environment: environment,
        outputFile: converted,
      );
    } else {
      final request = File(p.join(workspace.path, 'request.json'));
      final wordIdentity = File(p.join(workspace.path, 'word-process.json'));
      await request.writeAsString(
        jsonEncode({
          'inputPath': input.path,
          'outputPath': converted.path,
          'output': output.extension,
          'pidPath': wordIdentity.path,
        }),
        flush: true,
      );
      try {
        result = await _runProcess(
          installation.executablePath,
          _powershellArguments(installedOfficeWordConversionScript),
          timeout: timeout,
          workingDirectory: workspace.path,
          environment: {
            ...environment,
            'CRISPCLOUD_OFFICE_REQUEST': request.path,
          },
          outputFile: converted,
        );
      } on InstalledOfficeConversionException catch (error) {
        if (error.code == InstalledOfficeConversionErrorCode.timeout &&
            !await wordIdentity.exists()) {
          // COM activation may have started an unidentifiable server outside
          // our process tree. No document has been opened at this point. Never
          // guess which Word process to kill: another one may be user-owned.
          throw const InstalledOfficeConversionException(
            InstalledOfficeConversionErrorCode.unsafeAutomation,
          );
        }
        rethrow;
      } finally {
        if (await wordIdentity.exists()) {
          // COM servers may be outside the PowerShell process tree.
          final cleanup = await _runProcess(
            installation.executablePath,
            _powershellArguments(installedOfficeWordCleanupScript),
            timeout: const Duration(seconds: 5),
            workingDirectory: workspace.path,
            environment: {
              ...environment,
              'CRISPCLOUD_OFFICE_PID': wordIdentity.path,
            },
          );
          if (cleanup.exitCode != 0) {
            throw const InstalledOfficeConversionException(
              InstalledOfficeConversionErrorCode.cleanupFailed,
            );
          }
        }
      }
    }
    if (result.exitCode == 10 &&
        installation.kind == InstalledOfficeKind.microsoftWord) {
      throw const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.engineBusy,
      );
    }
    if (result.exitCode == 11) {
      throw const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.unsafeAutomation,
      );
    }
    if (result.exitCode != 0) {
      throw const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.conversionFailed,
      );
    }
    if (await FileSystemEntity.type(converted.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.invalidOutput,
      );
    }
    final length = await converted.length();
    if (length > kInstalledOfficeOutputLimit) {
      throw const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.outputTooLarge,
      );
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in converted.openRead(
      0,
      kInstalledOfficeOutputLimit + 1,
    )) {
      buffer.add(chunk);
      if (buffer.length > kInstalledOfficeOutputLimit) {
        throw const InstalledOfficeConversionException(
          InstalledOfficeConversionErrorCode.outputTooLarge,
        );
      }
    }
    final convertedBytes = buffer.takeBytes();
    if (output == InstalledOfficeOutput.pdf) {
      validateInstalledOfficePdf(convertedBytes);
    } else if (convertedBytes.length < 4 ||
        convertedBytes[0] != 0x50 ||
        convertedBytes[1] != 0x4b ||
        convertedBytes[2] != 0x03 ||
        convertedBytes[3] != 0x04) {
      throw const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.invalidOutput,
      );
    }
    return InstalledOfficeConversionResult(
      bytes: convertedBytes.asUnmodifiableView(),
      installation: installation,
      output: output,
      elapsed: clock.elapsed,
    );
  } on InstalledOfficeConversionException {
    rethrow;
  } on ProcessException {
    throw const InstalledOfficeConversionException(
      InstalledOfficeConversionErrorCode.unavailable,
    );
  } catch (_) {
    throw const InstalledOfficeConversionException(
      InstalledOfficeConversionErrorCode.conversionFailed,
    );
  } finally {
    if (workspace != null) await _deleteWorkspace(workspace);
  }
}

Future<void> _validateInput(
  Uint8List bytes,
  String sourceName,
  InstalledOfficeOutput output,
) async {
  if (bytes.length > kInstalledOfficeInputLimit) {
    throw const InstalledOfficeConversionException(
      InstalledOfficeConversionErrorCode.inputTooLarge,
    );
  }
  final extension = p.extension(sourceName).toLowerCase();
  if (output == InstalledOfficeOutput.pdf &&
      const {'.docx', '.docm'}.contains(extension)) {
    try {
      await inspectConvertedWord(
        bytes,
        extension: extension.substring(1),
        source: const LegacyWordSourceInspection(),
      );
      return;
    } on WordConversionInspectionException catch (error) {
      throw InstalledOfficeConversionException(
        error.issue == WordConversionInspectionIssue.tooLarge
            ? InstalledOfficeConversionErrorCode.inputTooLarge
            : InstalledOfficeConversionErrorCode.invalidInput,
      );
    }
  }
  _validateLegacyInput(bytes, sourceName);
}

void _validateLegacyInput(Uint8List bytes, String sourceName) {
  if (bytes.length > kInstalledOfficeInputLimit) {
    throw const InstalledOfficeConversionException(
      InstalledOfficeConversionErrorCode.inputTooLarge,
    );
  }
  if (!const {'.doc', '.dot'}.contains(p.extension(sourceName).toLowerCase())) {
    throw const InstalledOfficeConversionException(
      InstalledOfficeConversionErrorCode.invalidInput,
    );
  }
  try {
    final compound = BoundedCfbReader(
      bytes,
      maxFileBytes: kInstalledOfficeInputLimit,
      maxStreamBytes: kInstalledOfficeInputLimit,
      maxTotalReadBytes: kInstalledOfficeInputLimit,
    );
    final word = compound.readPath('WordDocument');
    if (word == null || word.length < 32) throw const FormatException();
    final header = ByteData.sublistView(word);
    if (header.getUint16(0, Endian.little) != 0xa5ec) {
      throw const FormatException();
    }
    if ((header.getUint16(10, Endian.little) & 0x8100) != 0) {
      throw const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.encryptedInput,
      );
    }
  } on InstalledOfficeConversionException {
    rethrow;
  } catch (_) {
    throw const InstalledOfficeConversionException(
      InstalledOfficeConversionErrorCode.invalidInput,
    );
  }
}

List<String> _libreOfficeCandidates(String? configured) {
  final result = <String>[];
  if (configured != null && p.isAbsolute(configured)) result.add(configured);
  final names = Platform.isWindows
      ? ['soffice.com', 'soffice.exe', 'libreoffice.exe']
      : ['soffice', 'libreoffice'];
  final separator = Platform.isWindows ? ';' : ':';
  for (final directory in (Platform.environment['PATH'] ?? '').split(
    separator,
  )) {
    // Never search the document directory or an implicit current directory.
    if (directory.isEmpty || !p.isAbsolute(directory)) continue;
    for (final name in names) {
      result.add(p.join(directory, name));
    }
  }
  if (Platform.isMacOS) {
    result.add('/Applications/LibreOffice.app/Contents/MacOS/soffice');
    final userDirectory = Platform.environment['HOME'];
    if (userDirectory != null) {
      result.add(
        p.join(
          userDirectory,
          'Applications/LibreOffice.app/Contents/MacOS/soffice',
        ),
      );
    }
  } else if (Platform.isWindows) {
    for (final variable in ['ProgramFiles', 'ProgramFiles(x86)']) {
      final directory = Platform.environment[variable];
      if (directory != null) {
        result.add(p.join(directory, 'LibreOffice', 'program', 'soffice.com'));
      }
    }
  } else {
    result.addAll(['/usr/bin/soffice', '/usr/local/bin/soffice']);
  }
  return result;
}

String? _windowsPowerShell() {
  final systemRoot = Platform.environment['SystemRoot'];
  if (systemRoot == null || !p.isAbsolute(systemRoot)) return null;
  final executable = p.join(
    systemRoot,
    'System32',
    'WindowsPowerShell',
    'v1.0',
    'powershell.exe',
  );
  return File(executable).existsSync() ? executable : null;
}

List<String> _powershellArguments(String script) => [
  '-NoLogo',
  '-NoProfile',
  '-NonInteractive',
  '-Command',
  script,
];

Map<String, String> _temporaryEnvironment(Directory workspace) => {
  'TMPDIR': workspace.path,
  'TMP': workspace.path,
  'TEMP': workspace.path,
  if (Platform.isLinux) 'SAL_USE_VCLPLUGIN': 'svp',
};

Future<void> _writeLibreOfficeProfile(Directory directory) async {
  final user = await Directory(
    p.join(directory.path, 'user'),
  ).create(recursive: true);
  await File(
    p.join(user.path, 'registrymodifications.xcu'),
  ).writeAsString(installedOfficeLibreOfficeProfile, flush: true);
}

Future<void> _deleteWorkspace(Directory directory) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }
  throw const InstalledOfficeConversionException(
    InstalledOfficeConversionErrorCode.cleanupFailed,
  );
}

class _OfficeProcessResult {
  const _OfficeProcessResult(this.exitCode, this.stdout);
  final int exitCode;
  final String stdout;
}

Future<_OfficeProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  String? workingDirectory,
  Map<String, String>? environment,
  File? outputFile,
}) async {
  // A launcher may fork a worker or exit before that worker. A fixed supervisor
  // owns a separate process group; one descendant snapshot cannot close this
  // race. All executable/argument values remain separate from shell source.
  final supervised = !Platform.isWindows;
  final groupRecord = supervised && workingDirectory != null
      ? File(p.join(workingDirectory, 'owned-process-group'))
      : null;
  if (supervised &&
      (groupRecord == null || !await File('/bin/bash').exists())) {
    throw const InstalledOfficeConversionException(
      InstalledOfficeConversionErrorCode.unavailable,
    );
  }
  final process = await Process.start(
    supervised ? '/bin/bash' : executable,
    supervised
        ? [
            '--noprofile',
            '--norc',
            '-c',
            installedOfficePosixSupervisor,
            'crisp-office-supervisor',
            executable,
            ...arguments,
          ]
        : arguments,
    workingDirectory: workingDirectory,
    environment: {
      ...?environment,
      if (groupRecord != null) 'CRISPCLOUD_OFFICE_GROUP': groupRecord.path,
    },
    runInShell: false,
  );
  await process.stdin.close();
  var exited = false;
  final exit = process.exitCode.then((value) {
    exited = true;
    return value;
  });
  final stdout = BytesBuilder(copy: false);
  final outputDone = Completer<void>();
  final errorDone = Completer<void>();
  const logLimit = 16 * 1024;
  final outputSubscription = process.stdout.listen(
    (chunk) {
      if (stdout.length < logLimit) {
        stdout.add(chunk.take(logLimit - stdout.length).toList());
      }
    },
    onDone: outputDone.complete,
    onError: (_) {
      if (!outputDone.isCompleted) outputDone.complete();
    },
  );
  final errorSubscription = process.stderr.listen(
    (_) {},
    onDone: errorDone.complete,
    onError: (_) {
      if (!errorDone.isCompleted) errorDone.complete();
    },
  );
  final oversize = Completer<int>();
  var checking = false;
  final monitor = outputFile == null
      ? null
      : Timer.periodic(const Duration(milliseconds: 200), (_) async {
          if (checking || exited) return;
          checking = true;
          try {
            if (await outputFile.exists() &&
                await outputFile.length() > kInstalledOfficeOutputLimit &&
                !oversize.isCompleted) {
              oversize.completeError(
                const InstalledOfficeConversionException(
                  InstalledOfficeConversionErrorCode.outputTooLarge,
                ),
              );
            }
          } on FileSystemException {
            // The output may not have been created yet.
          } finally {
            checking = false;
          }
        });
  try {
    final code = await Future.any([exit, oversize.future]).timeout(timeout);
    await Future.wait([
      outputDone.future,
      errorDone.future,
    ]).timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
    return _OfficeProcessResult(
      code,
      utf8.decode(stdout.takeBytes(), allowMalformed: true),
    );
  } on TimeoutException {
    await _stopProcessTree(process, () => exited, groupRecord: groupRecord);
    throw const InstalledOfficeConversionException(
      InstalledOfficeConversionErrorCode.timeout,
    );
  } catch (_) {
    await _stopProcessTree(process, () => exited, groupRecord: groupRecord);
    rethrow;
  } finally {
    monitor?.cancel();
    await outputSubscription.cancel();
    await errorSubscription.cancel();
  }
}

/// Kill only descendants of the process we launched. Do not use global
/// `killall soffice`/`taskkill /IM WINWORD`, which could destroy user sessions.
Future<void> _stopProcessTree(
  Process process,
  bool Function() exited, {
  File? groupRecord,
}) async {
  if (exited()) return;
  if (Platform.isWindows) {
    final root = Platform.environment['SystemRoot'];
    if (root != null) {
      try {
        final killer = await Process.start(
          p.join(root, 'System32', 'taskkill.exe'),
          ['/PID', process.pid.toString(), '/T', '/F'],
          runInShell: false,
        );
        unawaited(killer.stdout.drain<void>());
        unawaited(killer.stderr.drain<void>());
        await killer.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            killer.kill();
            return -1;
          },
        );
      } catch (_) {
        if (!exited()) process.kill();
      }
    }
  } else {
    // The supervisor handles TERM by stopping/killing its entire job group.
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
      return;
    } on TimeoutException {
      // A stopped/unresponsive supervisor still has a private group record.
      if (!exited() && groupRecord != null && await groupRecord.exists()) {
        final recordLength = await groupRecord.length();
        if (recordLength > 0 && recordLength <= 20) {
          final group = int.tryParse(await groupRecord.readAsString());
          if (group != null && group > 1 && group != process.pid) {
            Process.killPid(-group, ProcessSignal.sigkill);
          }
        }
      }
      if (!exited()) process.kill(ProcessSignal.sigkill);
    }
  }
  try {
    await process.exitCode.timeout(const Duration(seconds: 3));
  } on TimeoutException {
    if (!exited()) process.kill(ProcessSignal.sigkill);
  }
}
