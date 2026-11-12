import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/async_lock.dart';
import 'macos_app_store.dart';

enum ExternalTerminalFailure {
  unsupported,
  invalidConfiguration,
  localFolderRequired,
  changed,
  accessUnavailable,
  executableUnavailable,
  launchFailed,
  saveFailed,
}

class ExternalTerminalException implements Exception {
  const ExternalTerminalException(this.failure);
  final ExternalTerminalFailure failure;
  @override
  String toString() => 'External terminal: ${failure.name}';
}

/// An executable and literal argv, never a shell command string.
class ExternalTerminalConfiguration {
  ExternalTerminalConfiguration({
    required this.platform,
    required this.executable,
    required List<String> arguments,
  }) : arguments = List.unmodifiable(arguments) {
    validate();
  }

  final String platform;
  final String executable;
  final List<String> arguments;

  p.Context get paths => platform == 'windows' ? p.windows : p.posix;

  void validate() {
    final basename = paths.basename(executable).toLowerCase();
    if (!const {'macos', 'linux', 'windows'}.contains(platform) ||
        executable.isEmpty ||
        executable.length > 4096 ||
        executable.contains('\u0000') ||
        !paths.isAbsolute(executable) ||
        arguments.length > 64 ||
        (platform == 'windows' && !basename.endsWith('.exe')) ||
        const {
          'sh',
          'bash',
          'zsh',
          'dash',
          'fish',
          'csh',
          'tcsh',
          'cmd.exe',
          'powershell.exe',
          'pwsh.exe',
        }.contains(basename)) {
      throw const ExternalTerminalException(
        ExternalTerminalFailure.invalidConfiguration,
      );
    }
    var size = executable.length;
    for (final argument in arguments) {
      size += argument.length;
      if (argument.length > 4096 ||
          argument.contains('\u0000') ||
          (argument.contains('{') || argument.contains('}')) &&
              argument != '{directory}') {
        throw const ExternalTerminalException(
          ExternalTerminalFailure.invalidConfiguration,
        );
      }
    }
    if (size > 32768) {
      throw const ExternalTerminalException(
        ExternalTerminalFailure.invalidConfiguration,
      );
    }
  }

  List<String> argumentsFor(String directory) {
    final resolved = [
      for (final argument in arguments)
        argument == '{directory}' ? directory : argument,
    ];
    if (directory.length > 4096 ||
        directory.contains('\u0000') ||
        resolved.any((argument) => argument.length > 4096) ||
        executable.length +
                directory.length +
                resolved.fold<int>(
                  0,
                  (size, argument) => size + argument.length,
                ) >
            32768) {
      throw const ExternalTerminalException(
        ExternalTerminalFailure.invalidConfiguration,
      );
    }
    return List.unmodifiable(resolved);
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'platform': platform,
    'executable': executable,
    'arguments': arguments,
  };

  factory ExternalTerminalConfiguration.fromJson(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['platform'] is! String ||
        value['executable'] is! String ||
        value['arguments'] is! List ||
        !(value['arguments'] as List).every((item) => item is String)) {
      throw const ExternalTerminalException(
        ExternalTerminalFailure.invalidConfiguration,
      );
    }
    return ExternalTerminalConfiguration(
      platform: value['platform'] as String,
      executable: value['executable'] as String,
      arguments: List<String>.from(value['arguments'] as List),
    );
  }
}

class ExternalTerminalStore {
  ExternalTerminalStore(this.platform);
  final String platform;
  final _lock = AsyncLock();
  String get key => 'external_terminal_v1_$platform';

  Future<ExternalTerminalConfiguration?> load() => _lock.synchronized(() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return null;
    if (raw.length > 65536) {
      throw const ExternalTerminalException(
        ExternalTerminalFailure.invalidConfiguration,
      );
    }
    try {
      final configuration = ExternalTerminalConfiguration.fromJson(
        jsonDecode(raw),
      );
      if (configuration.platform != platform) {
        throw const ExternalTerminalException(
          ExternalTerminalFailure.invalidConfiguration,
        );
      }
      return configuration;
    } catch (_) {
      throw const ExternalTerminalException(
        ExternalTerminalFailure.invalidConfiguration,
      );
    }
  });

  Future<void> save(ExternalTerminalConfiguration value) =>
      _lock.synchronized(() async {
        value.validate();
        if (value.platform != platform) {
          throw const ExternalTerminalException(
            ExternalTerminalFailure.invalidConfiguration,
          );
        }
        final encoded = jsonEncode(value.toJson());
        if (encoded.length > 65536) {
          throw const ExternalTerminalException(
            ExternalTerminalFailure.invalidConfiguration,
          );
        }
        if (!await (await SharedPreferences.getInstance()).setString(
          key,
          encoded,
        )) {
          throw const ExternalTerminalException(
            ExternalTerminalFailure.saveFailed,
          );
        }
      });

  Future<void> reset() => _lock.synchronized(() async {
    if (!await (await SharedPreferences.getInstance()).remove(key)) {
      throw const ExternalTerminalException(ExternalTerminalFailure.saveFailed);
    }
  });
}

/// Captured before opening the preferences/review; no fallback folder is used.
class ExternalTerminalDirectory {
  const ExternalTerminalDirectory({
    required this.path,
    required this.isCurrent,
    required this.hasExistingAccess,
  });
  final String path;
  final bool Function() isCurrent;
  final Future<bool> Function() hasExistingAccess;
}

abstract interface class ExternalTerminalHost {
  String? get platform;
  Future<bool> executableAvailable(String path);
  Future<bool> directoryAvailable(String path);
  Future<void> launch(
    String executable,
    List<String> arguments,
    String directory,
  );
}

class NativeExternalTerminalHost implements ExternalTerminalHost {
  const NativeExternalTerminalHost();
  @override
  String? get platform {
    if (kIsWeb ||
        !const {
          'linux',
          'macos',
          'windows',
        }.contains(Platform.operatingSystem) ||
        isMacAppStoreBuild()) {
      return null;
    }
    return Platform.operatingSystem;
  }

  @override
  Future<bool> executableAvailable(String path) async {
    final stat = await FileStat.stat(path);
    return stat.type == FileSystemEntityType.file &&
        (Platform.isWindows || stat.mode & 0x49 != 0);
  }

  @override
  Future<bool> directoryAvailable(String path) async =>
      (await FileStat.stat(path)).type == FileSystemEntityType.directory;

  @override
  Future<void> launch(
    String executable,
    List<String> arguments,
    String directory,
  ) async {
    if (platform == null) {
      throw const ExternalTerminalException(
        ExternalTerminalFailure.unsupported,
      );
    }
    await Process.start(
      executable,
      arguments,
      workingDirectory: directory,
      runInShell: false,
      mode: ProcessStartMode.detached,
    );
  }
}

class ExternalTerminalService {
  const ExternalTerminalService({
    this.host = const NativeExternalTerminalHost(),
  });
  final ExternalTerminalHost host;
  String? get platform => host.platform;

  Future<void> launch(
    ExternalTerminalConfiguration configuration,
    ExternalTerminalDirectory directory,
  ) async {
    if (platform == null) {
      throw const ExternalTerminalException(
        ExternalTerminalFailure.unsupported,
      );
    }
    configuration.validate();
    if (configuration.platform != platform ||
        directory.path.contains('\u0000') ||
        !configuration.paths.isAbsolute(directory.path)) {
      throw const ExternalTerminalException(
        ExternalTerminalFailure.invalidConfiguration,
      );
    }
    final arguments = configuration.argumentsFor(directory.path);
    void check() {
      if (!directory.isCurrent()) {
        throw const ExternalTerminalException(ExternalTerminalFailure.changed);
      }
    }

    check();
    try {
      final access = await directory.hasExistingAccess();
      check();
      if (!access || !await host.directoryAvailable(directory.path)) {
        check();
        throw const ExternalTerminalException(
          ExternalTerminalFailure.accessUnavailable,
        );
      }
      check();
      final available = await host.executableAvailable(
        configuration.executable,
      );
      check();
      if (!available) {
        throw const ExternalTerminalException(
          ExternalTerminalFailure.executableUnavailable,
        );
      }
      await host.launch(configuration.executable, arguments, directory.path);
    } on ExternalTerminalException {
      rethrow;
    } catch (_) {
      throw const ExternalTerminalException(
        ExternalTerminalFailure.launchFailed,
      );
    }
  }
}
