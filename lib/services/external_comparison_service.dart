import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/external_comparison.dart';
import '../models/file_item.dart';
import '../utils/async_lock.dart';
import 'command_entry_service.dart';
import 'external_comparison_store.dart';
import 'file_operation_service.dart';
import 'private_tool_staging.dart';
import 'transfer_recovery_service.dart';

export '../models/external_comparison.dart';

abstract interface class ExternalComparisonHost {
  String? get platform;
  Future<CommandEntryFileIdentity?> inspectExecutable(String path);
  Future<void> launch(
    String executable,
    List<String> arguments,
    String directory,
  );
}

class NativeExternalComparisonHost implements ExternalComparisonHost {
  const NativeExternalComparisonHost();
  static const _host = NativeCommandEntryHost();
  @override
  String? get platform => _host.platform;
  @override
  Future<CommandEntryFileIdentity?> inspectExecutable(String path) =>
      _host.inspect(path);
  @override
  Future<void> launch(
    String executable,
    List<String> arguments,
    String directory,
  ) async {
    if (platform == null) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.unsupported,
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

class ExternalComparisonSession {
  ExternalComparisonSession(this.stage, this.manifest);
  final PrivateToolStage stage;
  Map<String, dynamic> manifest;
  bool busy = false;
  String get id => stage.id;
  String get state => switch (manifest['state']) {
    final String state => state,
    _ => 'unavailable',
  };
  bool get launchRequested => manifest['launchRequested'] == true;
  String get executable => switch (manifest['tool']) {
    {'executable': final String executable} => executable,
    _ => '',
  };
  String sourceLabel(String side) {
    final source = manifest[side];
    if (source is! Map) return '';
    final storage = source['storage'];
    return '${storage is Map ? '${storage['provider']} · ${storage['accountKey']} · ${storage['root']}' : ''}\n${source['path'] ?? ''}';
  }
}

class PreparedExternalComparison {
  PreparedExternalComparison._({
    required this.session,
    required this.pair,
    required this.configuration,
    required this.executable,
    required this.left,
    required this.right,
    required this.leftSourceVersion,
    required this.rightSourceVersion,
    required this.arguments,
    required this.isDraftCurrent,
    required this.generation,
  });
  final ExternalComparisonSession session;
  final ExternalComparisonPair pair;
  final ExternalComparisonConfiguration configuration;
  final CommandEntryFileIdentity executable;
  final PrivateStagedFile left, right;
  final FileItem leftSourceVersion, rightSourceVersion;
  final List<String> arguments;
  final bool Function() isDraftCurrent;
  final int generation;
  bool _used = false;
}

/// Stages two originals and retains launch-attempted copies until the user
/// explicitly confirms that every external window using them has closed.
class ExternalComparisonService extends ChangeNotifier {
  ExternalComparisonService({
    this.host = const NativeExternalComparisonHost(),
    PrivateToolStagingStore? staging,
    ExternalComparisonStore? preferences,
    this.maxInputBytes = 256 * 1024 * 1024,
    this.preparationTimeout = const Duration(minutes: 15),
  }) : staging = staging ?? PrivateToolStagingStore(),
       preferences =
           preferences ??
           ExternalComparisonStore(host.platform ?? 'unsupported') {
    if (maxInputBytes < 1 ||
        maxInputBytes > 256 * 1024 * 1024 ||
        preparationTimeout <= Duration.zero) {
      throw ArgumentError('Invalid comparison limits');
    }
    ready = _load();
  }
  static const stageKind = 'external-compare';
  static const maxSessions = 8;
  final ExternalComparisonHost host;
  final PrivateToolStagingStore staging;
  final ExternalComparisonStore preferences;
  final int maxInputBytes;
  final Duration preparationTimeout;
  late final Future<void> ready;
  bool loaded = false, _disposed = false;
  Object? loadError;
  int _generation = 0;
  FileOperationControl? _preparing;
  final _sessions = <String, ExternalComparisonSession>{};
  final _admission = AsyncLock();
  Map<ExternalComparisonKind, ExternalComparisonConfiguration> _configurations =
      {};
  List<ExternalComparisonSession> get sessions =>
      List.unmodifiable(_sessions.values);
  ExternalComparisonConfiguration? configuration(ExternalComparisonKind kind) =>
      _configurations[kind];
  String? get platform => host.platform;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    if (platform == null) {
      loaded = true;
      return;
    }
    try {
      _configurations = await preferences.load();
      final ids = await staging.list(stageKind);
      // Refuse to silently ignore retained copies beyond the advertised limit.
      if (ids.length > 64) {
        throw const ExternalComparisonException(
          ExternalComparisonFailure.sessionLimit,
        );
      }
      for (final id in ids) {
        final stage = await staging.open(kind: stageKind, id: id);
        Map<String, dynamic> manifest;
        try {
          manifest = await stage.readManifest() ?? {};
          if (manifest['version'] != 1 ||
              manifest['id'] != id ||
              manifest['kind'] != stageKind ||
              manifest['launchRequested'] is! bool ||
              !const {
                'preparing',
                'prepared',
                'launching',
                'retained',
                'launchFailed',
              }.contains(manifest['state']) ||
              manifest['tool'] is! Map ||
              manifest['left'] is! Map ||
              manifest['right'] is! Map) {
            manifest = {};
          }
        } catch (_) {
          manifest = {};
        }
        _sessions[id] = ExternalComparisonSession(stage, manifest);
      }
    } catch (error) {
      loadError = error;
    }
    loaded = true;
    if (_disposed) {
      for (final session in _sessions.values) {
        await session.stage.close();
      }
    } else {
      _changed();
    }
  }

  Future<void> saveConfiguration(ExternalComparisonConfiguration value) async {
    if (!loaded) await ready;
    if (_disposed) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.changed,
      );
    }
    await preferences.save(value);
    _configurations = {..._configurations, value.kind: value};
    _changed();
  }

  void _checkPair(
    ExternalComparisonPair pair,
    bool Function() current,
    int generation,
  ) {
    if (_disposed ||
        generation != _generation ||
        !current() ||
        !pair.isCurrent) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.changed,
      );
    }
  }

  Future<CommandEntryFileIdentity> _executable(
    ExternalComparisonConfiguration configuration,
  ) async {
    if (platform == null) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.unsupported,
      );
    }
    configuration.validate();
    if (configuration.platform != platform) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.invalidConfiguration,
      );
    }
    final identity = await host.inspectExecutable(configuration.executable);
    if (identity == null ||
        identity.isDirectory ||
        platform != 'windows' && identity.mode & 0x49 == 0) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.executableUnavailable,
      );
    }
    ExternalComparisonConfiguration(
      platform: configuration.platform,
      kind: configuration.kind,
      executable: identity.resolvedPath,
      arguments: configuration.arguments,
    );
    return identity;
  }

  Future<FileItem> _fresh(
    ExternalComparisonInput input,
    _ComparisonGuard guard, {
    FileItem? expected,
  }) async {
    guard.check();
    final current = await guard.wait(input.backend.stat(input.file.path!));
    if (current == null ||
        current.isFolder ||
        current.isSymlink == true ||
        !sameTransferVersion(expected ?? input.file, current)) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.changed,
      );
    }
    if ((current.size ?? 0) > maxInputBytes) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.tooLarge,
      );
    }
    return ExternalComparisonInput.snapshot(
      current.copyWith(path: input.file.path),
    );
  }

  Future<PreparedExternalComparison> prepare(
    ExternalComparisonConfiguration configuration,
    ExternalComparisonPair pair, {
    required FileOperationControl control,
    required bool Function() isCurrent,
    void Function(String side, int bytes)? onProgress,
  }) async {
    final generation = ++_generation;
    _preparing?.cancel();
    _preparing = control;
    final guard = _ComparisonGuard(
      control,
      preparationTimeout,
      () => _checkPair(pair, isCurrent, generation),
    );
    ExternalComparisonSession? session;
    try {
      if (!loaded) await guard.wait(ready);
      guard.check();
      if (loadError != null) {
        throw const ExternalComparisonException(
          ExternalComparisonFailure.storageFailed,
        );
      }
      if (_sessions.length >= maxSessions) {
        throw const ExternalComparisonException(
          ExternalComparisonFailure.sessionLimit,
        );
      }
      final executable = await guard.wait(_executable(configuration));
      final a = await _fresh(pair.left, guard);
      final b = await _fresh(pair.right, guard);
      // Creation is awaited to retain cleanup ownership even if cancelled.
      final admitted = await _admission.synchronized<ExternalComparisonSession>(
        () async {
          guard.check();
          if (_sessions.length >= maxSessions) {
            throw const ExternalComparisonException(
              ExternalComparisonFailure.sessionLimit,
            );
          }
          final stage = await staging.create(kind: stageKind);
          final created = ExternalComparisonSession(stage, {
            'version': 1,
            'id': stage.id,
            'kind': stageKind,
            'created': DateTime.now().toUtc().toIso8601String(),
            'state': 'preparing',
            'launchRequested': false,
            'tool': configuration.toJson(),
            'left': pair.left.descriptor,
            'right': pair.right.descriptor,
          })..busy = true;
          _sessions[created.id] = created;
          return created;
        },
      );
      session = admitted;
      final stage = session.stage;
      guard.check();
      await stage.writeManifest(session.manifest);
      guard.check();
      Future<PrivateStagedFile> copy(
        String side,
        ExternalComparisonInput input,
        FileItem file,
      ) async {
        final extension = p.posix.extension(input.file.name);
        final suffix = RegExp(r'^\.[A-Za-z0-9]{1,12}$').hasMatch(extension)
            ? extension
            : '';
        var received = 0;
        Stream<List<int>> bytes() async* {
          await for (final chunk in control.bind(
            input.backend.readFile(file),
          )) {
            guard.check();
            received += chunk.length;
            if (received > maxInputBytes) {
              throw const ExternalComparisonException(
                ExternalComparisonFailure.tooLarge,
              );
            }
            onProgress?.call(side, received);
            yield chunk;
          }
          guard.check();
        }

        final result = await stage.write(
          '$side$suffix',
          bytes(),
          maxBytes: maxInputBytes,
          expectedLength: file.size,
          checkpoint: () async => guard.check(),
        );
        guard.check();
        final after = await _fresh(input, guard, expected: file);
        if (!sameTransferVersion(file, after) ||
            file.size != null && file.size != result.length) {
          throw const ExternalComparisonException(
            ExternalComparisonFailure.changed,
          );
        }
        return result;
      }

      final left = await copy('left', pair.left, a);
      final right = await copy('right', pair.right, b);
      await _fresh(pair.left, guard, expected: a);
      await _fresh(pair.right, guard, expected: b);
      final arguments = configuration.expand(left.path, right.path);
      session.manifest = {
        ...session.manifest,
        'state': 'prepared',
        'files': [
          for (final file in [left, right])
            {'name': file.name, 'length': file.length, 'sha256': file.sha256},
        ],
      };
      await stage.writeManifest(session.manifest);
      guard.check();
      session.busy = false;
      _changed();
      return PreparedExternalComparison._(
        session: session,
        pair: pair,
        configuration: configuration,
        executable: executable,
        left: left,
        right: right,
        leftSourceVersion: a,
        rightSourceVersion: b,
        arguments: arguments,
        isDraftCurrent: isCurrent,
        generation: generation,
      );
    } catch (error) {
      if (session != null) {
        try {
          await session.stage.delete();
          _sessions.remove(session.id);
        } catch (_) {
          session.manifest = {...session.manifest, 'state': 'unavailable'};
        }
        session.busy = false;
        if (_disposed) await session.stage.close();
        _changed();
      }
      guard.rethrowIfStopped();
      if (error is ExternalComparisonException) rethrow;
      throw const ExternalComparisonException(
        ExternalComparisonFailure.unavailable,
      );
    } finally {
      guard.close();
      if (identical(_preparing, control)) _preparing = null;
    }
  }

  Future<void> launch(
    PreparedExternalComparison prepared, {
    required FileOperationControl control,
    required bool Function() isReviewCurrent,
  }) async {
    final session = prepared.session;
    if (prepared._used || session.busy || !_sessions.containsKey(session.id)) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.changed,
      );
    }
    prepared._used = true;
    session.busy = true;
    final guard = _ComparisonGuard(control, preparationTimeout, () {
      _checkPair(
        prepared.pair,
        () => prepared.isDraftCurrent() && isReviewCurrent(),
        prepared.generation,
      );
    });
    try {
      guard.check();
      final executable = await guard.wait(_executable(prepared.configuration));
      if (executable != prepared.executable) {
        throw const ExternalComparisonException(
          ExternalComparisonFailure.changed,
        );
      }
      await _fresh(
        prepared.pair.left,
        guard,
        expected: prepared.leftSourceVersion,
      );
      await _fresh(
        prepared.pair.right,
        guard,
        expected: prepared.rightSourceVersion,
      );
      for (final file in [prepared.left, prepared.right]) {
        final current = await session.stage.inspect(
          file.name,
          maxBytes: maxInputBytes,
          checkpoint: () async => guard.check(),
        );
        guard.check();
        if (current.path != file.path ||
            current.length != file.length ||
            current.sha256 != file.sha256) {
          throw const ExternalComparisonException(
            ExternalComparisonFailure.stageChanged,
          );
        }
      }
      // Persist before handing paths to the OS. A lost launch acknowledgement
      // must never cause files still used by a detached child to be deleted.
      session.manifest = {
        ...session.manifest,
        'launchRequested': true,
        'state': 'launching',
      };
      _changed();
      await session.stage.writeManifest(session.manifest);
      guard.check();
      await host.launch(
        prepared.executable.resolvedPath,
        prepared.arguments,
        session.stage.directoryPath,
      );
      session.manifest = {...session.manifest, 'state': 'retained'};
      await session.stage.writeManifest(session.manifest);
    } catch (error) {
      if (session.launchRequested) {
        session.manifest = {...session.manifest, 'state': 'launchFailed'};
        try {
          await session.stage.writeManifest(session.manifest);
        } catch (_) {
          /* Existing launch intent retains the copies. */
        }
      }
      guard.rethrowIfStopped();
      if (error is ExternalComparisonException) rethrow;
      if (error is PrivateStageException &&
          (error.failure == PrivateStageFailure.changed ||
              error.failure == PrivateStageFailure.tooLarge)) {
        throw const ExternalComparisonException(
          ExternalComparisonFailure.stageChanged,
        );
      }
      throw const ExternalComparisonException(
        ExternalComparisonFailure.launchFailed,
      );
    } finally {
      guard.close();
      session.busy = false;
      if (_disposed) await session.stage.close();
      _changed();
    }
  }

  Future<void> discard(PreparedExternalComparison prepared) async {
    if (!prepared.session.launchRequested && !prepared.session.busy) {
      await release(prepared.session.id, toolClosed: false);
    }
  }

  Future<void> release(String id, {required bool toolClosed}) async {
    if (!loaded) await ready;
    final session = _sessions[id];
    if (session == null) return;
    if (session.busy ||
        !toolClosed &&
            (session.launchRequested || session.state == 'unavailable')) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.changed,
      );
    }
    session.busy = true;
    try {
      await session.stage.delete();
      _sessions.remove(id);
    } finally {
      session.busy = false;
      if (_disposed) await session.stage.close();
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _preparing?.cancel();
    for (final session in _sessions.values) {
      if (!session.busy) {
        unawaited(session.stage.close().catchError((Object _) {}));
      }
    }
    super.dispose();
  }
}

class _ComparisonGuard {
  _ComparisonGuard(this.control, Duration timeout, this.current) {
    _deadline = Timer(timeout, () {
      _failure = ExternalComparisonFailure.timedOut;
      control.cancel();
    });
    _watcher = Timer.periodic(const Duration(milliseconds: 50), (_) {
      try {
        current();
      } catch (_) {
        _failure ??= ExternalComparisonFailure.changed;
        control.cancel();
      }
    });
  }
  final FileOperationControl control;
  final void Function() current;
  late final Timer _deadline, _watcher;
  ExternalComparisonFailure? _failure;
  void check() {
    if (_failure != null) throw ExternalComparisonException(_failure!);
    current();
    if (control.isCancelled) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.cancelled,
      );
    }
  }

  Future<T> wait<T>(Future<T> pending) async {
    check();
    final result = await Future.any<T>([
      pending,
      control.cancellationFuture.then<T>((_) {
        check();
        throw const ExternalComparisonException(
          ExternalComparisonFailure.cancelled,
        );
      }),
    ]);
    check();
    return result;
  }

  void rethrowIfStopped() => check();
  void close() {
    _deadline.cancel();
    _watcher.cancel();
  }
}
