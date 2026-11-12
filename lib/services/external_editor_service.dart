import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/async_lock.dart';
import 'command_entry_service.dart';
import 'external_remote_editing_service.dart';
import 'local_file_service.dart';
import 'private_tool_staging.dart';

class ExternalEditorConfiguration {
  ExternalEditorConfiguration({
    required this.platform,
    required this.executable,
    required List<String> arguments,
  }) : arguments = List.unmodifiable(arguments) {
    validate();
  }
  final String platform, executable;
  final List<String> arguments;
  p.Context get paths => platform == 'windows' ? p.windows : p.posix;

  void validate() {
    var basename = paths.basename(executable).toLowerCase();
    if (basename.endsWith('.exe')) {
      basename = basename.substring(0, basename.length - 4);
    }
    if (!const {'linux', 'macos', 'windows'}.contains(platform) ||
        !paths.isAbsolute(executable) ||
        executable.length > 4096 ||
        executable.contains('\u0000') ||
        arguments.length > 64 ||
        platform == 'windows' && !executable.toLowerCase().endsWith('.exe') ||
        const {
          'sh',
          'bash',
          'dash',
          'zsh',
          'fish',
          'csh',
          'tcsh',
          'ksh',
          'nu',
          'xonsh',
          'cmd',
          'powershell',
          'pwsh',
          'node',
          'nodejs',
          'perl',
          'ruby',
          'php',
          'lua',
          'rscript',
        }.contains(basename) ||
        RegExp(r'^python(?:\d+(?:\.\d+)*)?$').hasMatch(basename) ||
        const ['.bat', '.cmd', '.ps1'].any(executable.toLowerCase().endsWith) ||
        arguments.where((argument) => argument == '{file}').length != 1 ||
        arguments.any(
          (argument) =>
              argument.contains('\u0000') ||
              argument.length > 4096 ||
              argument.contains('{file}') && argument != '{file}',
        ) ||
        executable.length +
                arguments.fold<int>(
                  0,
                  (length, argument) => length + argument.length,
                ) >
            32768) {
      throw const ExternalEditException(ExternalEditFailure.invalid);
    }
  }

  List<String> argumentsFor(String file) {
    if (!paths.isAbsolute(file) ||
        file.contains('\u0000') ||
        file.length > 4096) {
      throw const ExternalEditException(ExternalEditFailure.invalid);
    }
    final resolved = [
      for (final argument in arguments) argument == '{file}' ? file : argument,
    ];
    if (executable.length +
            resolved.fold<int>(0, (length, value) => length + value.length) >
        32768) {
      throw const ExternalEditException(ExternalEditFailure.invalid);
    }
    return List.unmodifiable(resolved);
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'platform': platform,
    'executable': executable,
    'arguments': arguments,
  };
  factory ExternalEditorConfiguration.fromJson(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['platform'] is! String ||
        value['executable'] is! String ||
        value['arguments'] is! List ||
        !(value['arguments'] as List).every((item) => item is String)) {
      throw const ExternalEditException(ExternalEditFailure.invalid);
    }
    return ExternalEditorConfiguration(
      platform: value['platform'] as String,
      executable: value['executable'] as String,
      arguments: List<String>.from(value['arguments'] as List),
    );
  }
}

class ExternalEditorStore {
  ExternalEditorStore(this.platform);
  final String platform;
  static final AsyncLock _lock = AsyncLock();
  String get _key => 'external_editor_v1_$platform';
  Future<ExternalEditorConfiguration?> load() => _lock.synchronized(() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return null;
    if (raw.length > 65536) {
      throw const ExternalEditException(ExternalEditFailure.invalid);
    }
    try {
      final result = ExternalEditorConfiguration.fromJson(jsonDecode(raw));
      if (result.platform != platform) {
        throw const ExternalEditException(ExternalEditFailure.invalid);
      }
      return result;
    } catch (_) {
      throw const ExternalEditException(ExternalEditFailure.invalid);
    }
  });
  Future<void> save(ExternalEditorConfiguration configuration) =>
      _lock.synchronized(() async {
        configuration.validate();
        if (configuration.platform != platform) {
          throw const ExternalEditException(ExternalEditFailure.invalid);
        }
        if (!await (await SharedPreferences.getInstance()).setString(
          _key,
          jsonEncode(configuration.toJson()),
        )) {
          throw const ExternalEditException(ExternalEditFailure.saveFailed);
        }
      });
  Future<void> reset() => _lock.synchronized(() async {
    if (!await (await SharedPreferences.getInstance()).remove(_key)) {
      throw const ExternalEditException(ExternalEditFailure.saveFailed);
    }
  });
}

abstract interface class ExternalEditorHost {
  String? get platform;
  Future<bool> hasExistingAccess(String path);
  Future<CommandEntryFileIdentity?> inspectPath(String path);
  Future<void> launch(
    String executable,
    List<String> arguments,
    String directory,
  );
}

class NativeExternalEditorHost implements ExternalEditorHost {
  const NativeExternalEditorHost();
  @override
  String? get platform => const NativeCommandEntryHost().platform;
  @override
  Future<bool> hasExistingAccess(String path) =>
      LocalFileService().hasAccessToPath(path);
  @override
  Future<CommandEntryFileIdentity?> inspectPath(String path) =>
      const NativeCommandEntryHost().inspect(path);
  @override
  Future<void> launch(
    String executable,
    List<String> arguments,
    String directory,
  ) async {
    if (platform == null) {
      throw const ExternalEditException(ExternalEditFailure.unsupported);
    }
    await Process.start(
      executable,
      arguments,
      workingDirectory: directory,
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
  }
}

class PreparedExternalEditorLaunch {
  PreparedExternalEditorLaunch._({
    required this.session,
    required this.configuration,
    required this.identity,
    required this.file,
    required this.arguments,
    required this.directory,
    required this.checkCurrent,
  });
  final ExternalEditSession session;
  final ExternalEditorConfiguration configuration;
  final CommandEntryFileIdentity identity;
  final PrivateStagedFile file;
  final List<String> arguments;
  final String directory;
  final void Function() checkCurrent;
  String get executable => identity.resolvedPath;
  bool _used = false;
}

class ExternalEditorLauncher {
  const ExternalEditorLauncher({this.host = const NativeExternalEditorHost()});
  final ExternalEditorHost host;
  String? get platform => host.platform;

  Future<CommandEntryFileIdentity> _executable(
    ExternalEditorConfiguration configuration,
    void Function() check,
  ) async {
    check();
    if (!await host.hasExistingAccess(configuration.executable)) {
      throw const ExternalEditException(
        ExternalEditFailure.executableUnavailable,
      );
    }
    check();
    final identity = await host.inspectPath(configuration.executable);
    check();
    if (identity == null ||
        identity.isDirectory ||
        platform != 'windows' && identity.mode & 0x49 == 0) {
      throw const ExternalEditException(
        ExternalEditFailure.executableUnavailable,
      );
    }
    ExternalEditorConfiguration(
      platform: configuration.platform,
      executable: identity.resolvedPath,
      arguments: configuration.arguments,
    );
    if (!await host.hasExistingAccess(identity.resolvedPath)) {
      throw const ExternalEditException(
        ExternalEditFailure.executableUnavailable,
      );
    }
    check();
    return identity;
  }

  Future<PreparedExternalEditorLaunch> prepare(
    ExternalEditSession session,
    ExternalEditorConfiguration configuration, {
    required bool Function() isCurrent,
  }) async {
    if (platform == null || platform != configuration.platform) {
      throw const ExternalEditException(ExternalEditFailure.unsupported);
    }
    configuration.validate();
    final sourceGuard = session.captureLaunchGuard();
    void check() {
      if (!isCurrent()) {
        throw const ExternalEditException(ExternalEditFailure.localChanged);
      }
      sourceGuard();
    }

    final identity = await _executable(configuration, check);
    final file = await session.workingFile();
    check();
    if (session.record?.localSha256 == null) {
      throw const ExternalEditException(
        ExternalEditFailure.retainedUnavailable,
      );
    }
    return PreparedExternalEditorLaunch._(
      session: session,
      configuration: configuration,
      identity: identity,
      file: file,
      arguments: configuration.argumentsFor(file.path),
      directory: session.directoryPath,
      checkCurrent: check,
    );
  }

  Future<void> launch(
    PreparedExternalEditorLaunch prepared, {
    required bool autoUpload,
  }) async {
    if (prepared._used) {
      throw const ExternalEditException(ExternalEditFailure.localChanged);
    }
    prepared._used = true;
    prepared.checkCurrent();
    if (autoUpload && !prepared.session.canPublish) {
      throw const ExternalEditException(ExternalEditFailure.unsupported);
    }
    await prepared.session.runReviewedLaunch(() async {
      prepared.checkCurrent();
      final identity = await _executable(
        prepared.configuration,
        prepared.checkCurrent,
      );
      final file = await prepared.session.workingFile();
      final directory = await host.inspectPath(prepared.directory);
      prepared.checkCurrent();
      if (identity != prepared.identity ||
          file.sha256 != prepared.file.sha256 ||
          file.length != prepared.file.length ||
          file.path != prepared.file.path ||
          directory == null ||
          !directory.isDirectory ||
          directory.resolvedPath != prepared.directory) {
        throw const ExternalEditException(ExternalEditFailure.localChanged);
      }
      try {
        await host.launch(
          prepared.executable,
          prepared.arguments,
          prepared.directory,
        );
      } catch (_) {
        throw const ExternalEditException(ExternalEditFailure.launchFailed);
      }
    });
    if (!prepared.session.isClosing) {
      await prepared.session.watch(autoUpload: autoUpload);
    }
  }
}
