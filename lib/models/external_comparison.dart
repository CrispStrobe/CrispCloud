import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/storage_reference.dart';
import '../services/file_operation_service.dart';

enum ExternalComparisonKind { text, image }

enum ExternalComparisonFailure {
  unsupported,
  invalidConfiguration,
  unavailable,
  changed,
  tooLarge,
  cancelled,
  timedOut,
  executableUnavailable,
  stageChanged,
  launchFailed,
  storageFailed,
  sessionLimit,
}

class ExternalComparisonException implements Exception {
  const ExternalComparisonException(this.failure);
  final ExternalComparisonFailure failure;
  @override
  String toString() => 'External comparison: ${failure.name}';
}

/// Only complete argument tokens are substituted, exactly once. Inputs are
/// private copies; an original local/remote path is never a launch argument.
class ExternalComparisonConfiguration {
  ExternalComparisonConfiguration({
    required this.platform,
    required this.kind,
    required this.executable,
    required List<String> arguments,
  }) : arguments = List.unmodifiable(arguments) {
    validate();
  }
  final String platform, executable;
  final ExternalComparisonKind kind;
  final List<String> arguments;

  p.Context get paths => platform == 'windows' ? p.windows : p.posix;

  void validate() {
    final name = paths.basename(executable).toLowerCase();
    final base = name.endsWith('.exe')
        ? name.substring(0, name.length - 4)
        : name;
    if (!const {'linux', 'macos', 'windows'}.contains(platform) ||
        !paths.isAbsolute(executable) ||
        executable.length > 4096 ||
        executable.contains(RegExp(r'[\x00\r\n]')) ||
        platform == 'windows' && !name.endsWith('.exe') ||
        const {
          'sh',
          'bash',
          'dash',
          'zsh',
          'ksh',
          'fish',
          'csh',
          'tcsh',
          'cmd',
          'powershell',
          'pwsh',
          'node',
          'nodejs',
          'ruby',
          'perl',
          'php',
          'lua',
        }.contains(base) ||
        RegExp(r'^python(?:\d+(?:\.\d+)*)?$').hasMatch(base) ||
        arguments.length > 64 ||
        arguments.where((argument) => argument == '{left}').length != 1 ||
        arguments.where((argument) => argument == '{right}').length != 1 ||
        arguments.any(
          (argument) =>
              argument.length > 4096 ||
              argument.contains('\u0000') ||
              (argument.contains('{') || argument.contains('}')) &&
                  argument != '{left}' &&
                  argument != '{right}',
        ) ||
        utf8.encode(jsonEncode(toJson())).length > 32 * 1024) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.invalidConfiguration,
      );
    }
  }

  List<String> expand(String left, String right) {
    validate();
    if (![left, right].every(
      (path) =>
          paths.isAbsolute(path) &&
          path.length <= 4096 &&
          !path.contains('\u0000'),
    )) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.invalidConfiguration,
      );
    }
    return List.unmodifiable([
      for (final argument in arguments)
        switch (argument) {
          '{left}' => left,
          '{right}' => right,
          _ => argument,
        },
    ]);
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'platform': platform,
    'kind': kind.name,
    'executable': executable,
    'arguments': arguments,
  };

  factory ExternalComparisonConfiguration.fromJson(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['arguments'] is! List ||
        !(value['arguments'] as List).every((argument) => argument is String)) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.invalidConfiguration,
      );
    }
    try {
      return ExternalComparisonConfiguration(
        platform: value['platform'] as String,
        kind: ExternalComparisonKind.values.byName(value['kind'] as String),
        executable: value['executable'] as String,
        arguments: List<String>.from(value['arguments'] as List),
      );
    } catch (_) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.invalidConfiguration,
      );
    }
  }
}

/// Construct synchronously while the original verified row is still selected.
/// The backend is used only for stat/read; this object exposes no write action.
class ExternalComparisonInput {
  ExternalComparisonInput({
    required this.backend,
    required FileItem file,
    required bool Function() isCurrent,
    StorageReference? storage,
  }) : storage =
           storage ??
           backend.storageReference ??
           (throw const ExternalComparisonException(
             ExternalComparisonFailure.unavailable,
           )),
       identity = backend.identity,
       // Keep the public guard name while storing it privately.
       // ignore: prefer_initializing_formals
       _isCurrent = isCurrent,
       file = snapshot(file) {
    if (file.isFolder ||
        file.isSymlink == true ||
        file.path == null ||
        !backend.paths.isAbsolute(file.path!) ||
        file.path!.contains('\u0000') ||
        file.name == '..' ||
        file.name == '.' ||
        file.name.isEmpty) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.unavailable,
      );
    }
  }

  /// Retain scalar metadata, never mutable adapter objects or access handles.
  static FileItem snapshot(FileItem file) => FileItem(
    name: file.name,
    path: file.path,
    uuid: file.uuid,
    storageId: file.storageId,
    isFolder: file.isFolder,
    size: file.size,
    updatedAt: file.updatedAt,
    isSymlink: file.isSymlink,
    symlinkTarget: file.symlinkTarget,
    metadata: Map.unmodifiable({
      for (final key in const [
        'version',
        'versionId',
        'eTag',
        'etag',
        'rev',
        'cTag',
      ])
        if (file.metadata?[key] != null) key: file.metadata![key].toString(),
    }),
  );
  final FileOperationBackend backend;
  final FileItem file;
  final StorageReference storage;
  final Object identity;
  final bool Function() _isCurrent;
  bool _lost = false;
  bool get isCurrent {
    if (_lost) return false;
    _lost =
        !_isCurrent() ||
        !backend.isCurrent ||
        backend.identity != identity ||
        backend.storageReference != null && backend.storageReference != storage;
    return !_lost;
  }

  Map<String, dynamic> get descriptor => {
    'storage': storage.toJson(),
    'path': file.path,
    'name': file.name,
    if (file.uuid != null) 'objectId': file.uuid,
  };
}

class ExternalComparisonPair {
  ExternalComparisonPair({required this.left, required this.right});
  final ExternalComparisonInput left, right;
  bool _disposed = false;
  bool get isCurrent => !_disposed && left.isCurrent && right.isCurrent;
  void dispose() => _disposed = true;
}
