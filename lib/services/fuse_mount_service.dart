import 'terminal_mount_failure.dart';
// lib/services/fuse_mount_service.dart
//
// FuseMountService manages the lifecycle of FUSE-based mounted drives.
// It bridges cloud storage providers to local filesystem mount points using
// platform-native FUSE implementations:
//   - macOS: macFUSE (https://osxfuse.github.io) or FUSE-T
//   - Linux: libfuse / fusermount3 (usually in fuse3 package)
//   - Windows: WinFsp (https://winfsp.dev)
//
// PREREQUISITE: The appropriate native FUSE library must be installed by the
// user. This Dart layer only orchestrates the mount process; it does NOT
// bundle native FUSE binaries.
//
// Platform guard: FUSE mounts are available on desktop (macOS, Linux,
// Windows) only. Calling any mount operation on mobile/web returns an
// UnsupportedError.

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_storage_interface.dart';
import 'fuse_filesystem.dart';
import 'log_service.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Runtime used for a mount on macOS.
enum MacFuseBackend {
  automatic, fuseT, macFuseFsKit, macFuseKernel, rcloneNfs, fuseTSmb;

  bool get usesFuseT => this == fuseT || this == fuseTSmb;
}

/// Describes a single active or configured FUSE mount.
class MountEntry {
  /// Unique key = mount point path, normalised with no trailing slash.
  final String mountPoint;

  /// Human-readable label (defaults to provider + remote path).
  final String label;

  /// The cloud provider name (matches CloudStorageClient.providerName).
  final String provider;

  /// Remote path on the cloud provider to expose as the mount root.
  final String remotePath;
  final MacFuseBackend macBackend;

  /// Current lifecycle state.
  MountStatus status;

  /// Optional error message when [status] == [MountStatus.error].
  String? errorMessage;

  /// Stable app-authored message key and values for the mount UI.
  String? errorKey;
  Map<String, Object> errorValues;

  /// PID of the helper process, if running.
  int? helperPid;

  MountEntry({
    required this.mountPoint,
    required this.label,
    required this.provider,
    required this.remotePath,
    this.macBackend = MacFuseBackend.automatic,
    this.status = MountStatus.unmounted,
    this.errorMessage,
    this.errorKey,
    this.errorValues = const {},
    this.helperPid,
  });

  /// Serialise to a SharedPreferences-compatible string map.
  Map<String, String> toMap() => {
    'mountPoint': mountPoint,
    'label': label,
    'provider': provider,
    'remotePath': remotePath,
    'macBackend': macBackend.name,
  };

  factory MountEntry.fromMap(Map<String, String> m) => MountEntry(
    mountPoint: m['mountPoint']!,
    label: m['label']!,
    provider: m['provider']!,
    remotePath: m['remotePath']!,
    macBackend: MacFuseBackend.values.where((v) => v.name == m['macBackend']).firstOrNull ?? MacFuseBackend.automatic,
  );

  MountEntry copyWith({
    MountStatus? status,
    String? errorMessage,
    String? errorKey,
    Map<String, Object>? errorValues,
    int? helperPid,
  }) => MountEntry(
    mountPoint: mountPoint,
    label: label,
    provider: provider,
    remotePath: remotePath,
    macBackend: macBackend,
    status: status ?? this.status,
    errorMessage: errorMessage ?? this.errorMessage,
    errorKey: errorKey ?? this.errorKey,
    errorValues: errorValues ?? this.errorValues,
    helperPid: helperPid ?? this.helperPid,
  );
}

class _MountBridgeFailure implements Exception {
  final String key;
  final String message;
  final Map<String, Object> values;

  const _MountBridgeFailure(this.key, this.message, this.values);

  @override
  String toString() => message;
}

enum MountStatus { unmounted, mounting, mounted, unmounting, error }

// ---------------------------------------------------------------------------
// FuseMountService
// ---------------------------------------------------------------------------

class FuseMountService {
  static const _log = Log('FuseMountService');

  /// Accept configured remote names and the credential-free local backend;
  /// reject connection-string options that could expose secrets in argv.
  static bool isValidRcloneRemote(String remote) =>
      remote.startsWith(':local:') ||
      RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_. -]*:').hasMatch(remote);

  @visibleForTesting
  static String macFuseRuntime(MacFuseBackend backend) => switch (backend) {
    MacFuseBackend.automatic => 'macfuse-fskit',
    MacFuseBackend.fuseT => 'fuse-t',
    MacFuseBackend.fuseTSmb => 'fuse-t-smb',
    MacFuseBackend.macFuseFsKit => 'macfuse-fskit',
    MacFuseBackend.macFuseKernel => 'macfuse-kernel',
    MacFuseBackend.rcloneNfs => throw ArgumentError('rclone does not use the FUSE bridge'),
  };

  // Stable app-authored messages used by the mount UI for localization.
  static const linuxMissing =
      'libfuse / fusermount3 not found. Install via: sudo apt install fuse3  '
      '(or equivalent for your distro).';
  static const macMissing =
      'macFUSE or FUSE-T not found. Install macFUSE from '
      'https://osxfuse.github.io or FUSE-T from https://www.fuse-t.org/.';
  static const winMissing = 'WinFsp not found. Install from https://winfsp.dev';
  static const unsupportedPlatform = 'Unsupported platform';
  static const bridgeMissing =
      'This build does not include the native FUSE bridge '
      'required to mount drives.';
  static const availabilityFailedPrefix = 'Error checking FUSE availability: ';
  static const createFailedPrefix = 'Cannot create mount point: ';
  static const rcloneMissing = 'rclone not found';

  // Persisted config key prefix for SharedPreferences.
  static const _prefKey = 'fuse_mounts_v1';

  /// Whether FUSE mounts are supported on the current platform/runtime.
  ///
  /// Returns true only on macOS, Linux, and Windows when not running in a
  /// web context. Note that even when this returns true the user must have
  /// the appropriate native FUSE library installed.
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isLinux || Platform.isWindows;
  }

  // In-memory mount registry: mountPoint → entry.
  final Map<String, MountEntry> _mounts = {};

  // Active FuseFilesystem bridges keyed by mountPoint.
  final Map<String, FuseFilesystem> _filesystems = {};

  // Active helper processes keyed by mountPoint.
  final Map<String, Process> _processes = {};

  // Mount startup can still be running before a helper has been registered.
  // Track it so shutdown cannot miss a mount that appears moments later.
  final Map<String, Completer<void>> _pendingMounts = {};
  final Map<String, Completer<void>> _pendingUnmounts = {};
  Completer<void>? _unmountAllComplete;

  /// Notifier called whenever the mount list changes (for Riverpod providers).
  void Function()? onChanged;

  // ---------------------------------------------------------------------------
  // Availability check
  // ---------------------------------------------------------------------------

  /// Detects whether the platform FUSE library is installed and runnable.
  ///
  /// On Linux this checks for `fusermount3` or `fusermount`.
  /// On macOS it checks for macFUSE or the FUSE-T runtime library.
  /// On Windows it checks for the WinFsp launcher (`winfsp-launcher`).
  ///
  /// Returns null if available, or a human-readable error string if not.
  Future<String?> checkFuseAvailability() async {
    _requireDesktop();
    try {
      if (Platform.isLinux) {
        return await _checkLinuxFuse();
      } else if (Platform.isMacOS) {
        return await _checkMacFuse();
      } else if (Platform.isWindows) {
        return await _checkWinFsp();
      }
    } catch (e) {
      return '$availabilityFailedPrefix$e';
    }
    return unsupportedPlatform;
  }

  Future<String?> _checkLinuxFuse() async {
    // Try fusermount3 first (fuse3), fall back to fusermount (fuse2).
    for (final cmd in ['fusermount3', 'fusermount']) {
      final result = await Process.run('which', [cmd]);
      if (result.exitCode == 0) return null; // found
    }
    return linuxMissing;
  }

  Future<String?> _checkMacFuse() async {
    if (await _rclonePath() != null) return null;
    if (!await File(macBridgePath).exists()) return bridgeMissing;
    if (await File('/usr/local/lib/libfuse-t.dylib').exists()) return null;
    if (await File('/usr/local/lib/libfuse.2.dylib').exists() &&
        await Directory('/Library/Filesystems/macfuse.fs').exists()) {
      return null;
    }
    return macMissing;
  }

  Future<String?> _rclonePath() async {
    for (final path in ['/opt/homebrew/bin/rclone', '/usr/local/bin/rclone']) {
      if (await File(path).exists()) return path;
    }
    return null;
  }

  Future<String?> _checkWinFsp() async {
    // WinFsp typically installs to Program Files.
    for (final path in [
      r'C:\Program Files (x86)\WinFsp\bin\winfsp-launcher-x64.exe',
      r'C:\Program Files\WinFsp\bin\winfsp-launcher-x64.exe',
    ]) {
      if (await File(path).exists()) return null;
    }
    return winMissing;
  }

  // ---------------------------------------------------------------------------
  // Mount lifecycle
  // ---------------------------------------------------------------------------

  /// Mount [remotePath] of [provider] at [mountPoint].
  ///
  /// [label] is the human-readable display name.
  /// The mount is performed asynchronously; the returned [MountEntry] will
  /// initially have status [MountStatus.mounting].
  ///
  /// Throws [UnsupportedError] on web/mobile, [ArgumentError] if the
  /// mount point is already in use.
  Future<MountEntry> mount({
    required CloudStorageClient? client,
    required String remotePath,
    required String mountPoint,
    String? label,
    MacFuseBackend macBackend = MacFuseBackend.automatic,
    bool fuseTNonCommercialAcknowledged = false,
  }) async {
    _requireDesktop();
    if (_unmountAllComplete != null) {
      throw StateError('Cannot mount while mounts are being shut down');
    }
    if (macBackend.usesFuseT && !fuseTNonCommercialAcknowledged) {
      throw ArgumentError('FUSE-T requires non-commercial-use acknowledgement');
    }
    if (macBackend != MacFuseBackend.rcloneNfs && client == null) {
      throw ArgumentError('Cloud client required');
    }
    if (macBackend == MacFuseBackend.rcloneNfs && !Platform.isMacOS) {
      throw UnsupportedError('rclone NFS is currently available on macOS only');
    }
    if (macBackend == MacFuseBackend.rcloneNfs &&
        !isValidRcloneRemote(remotePath)) {
      throw ArgumentError('An rclone remote such as work:documents is required');
    }

    final canonical = _canonicalize(mountPoint);
    if (_pendingMounts.containsKey(canonical) ||
        _pendingUnmounts.containsKey(canonical) ||
        _processes.containsKey(canonical) || {
      MountStatus.mounting,
      MountStatus.mounted,
      MountStatus.unmounting,
    }.contains(_mounts[canonical]?.status)) {
      throw TerminalMountArgumentError(
        TerminalMountCode.mountDuplicate,
        'Mount point "$canonical" is already mounted',
        {'path': canonical},
      );
    }

    final startupComplete = Completer<void>();
    _pendingMounts[canonical] = startupComplete;
    try {
      final entry = MountEntry(
        mountPoint: canonical,
        label: label ?? '${client?.providerName ?? 'rclone'}:$remotePath',
        provider: client?.providerName ?? 'rclone',
        remotePath: remotePath,
        macBackend: macBackend,
        status: MountStatus.mounting,
      );
      _mounts[canonical] = entry;
      _notify();

      // A mount created by another process must never be replaced or unmounted.
      // Probe before creating the directory or starting the native helper.
      try {
        if (await isPlatformMountPoint(canonical)) {
          _setError(
            canonical,
            'Mount point "$canonical" is already in use',
            errorKey: 'mountPointOccupied',
            errorValues: {'path': canonical},
          );
          return _mounts[canonical]!;
        }
      } catch (e) {
        _setError(
          canonical,
          'Cannot inspect mount point "$canonical": $e',
          errorKey: 'mountProbeFailed',
          errorValues: {'path': canonical, 'error': '$e'},
        );
        return _mounts[canonical]!;
      }

      // Ensure mount point directory exists.
      try {
        await Directory(canonical).create(recursive: true);
      } catch (e) {
        _setError(canonical, '$createFailedPrefix$e');
        return _mounts[canonical]!;
      }

      // Check FUSE availability before proceeding.
      final fuseError = macBackend == MacFuseBackend.rcloneNfs
          ? (await _rclonePath() == null ? rcloneMissing : null)
          : await checkFuseAvailability();
      if (fuseError != null) {
        _setError(canonical, fuseError);
        return _mounts[canonical]!;
      }

      // Build and start the FUSE bridge.
      try {
        if (macBackend == MacFuseBackend.rcloneNfs) {
          await _startRclone(entry);
        } else {
          await _startBridge(entry, client!);
        }
        // The helper can exit immediately after the OS reports a mount. Its
        // exit handler may already have changed the entry to an error.
        if (_processes.containsKey(canonical) &&
            _mounts[canonical]?.status != MountStatus.error) {
          _mounts[canonical] = entry.copyWith(status: MountStatus.mounted);
          _log.info('Mounted ${entry.provider}:${entry.remotePath} → $canonical');
        }
      } on _MountBridgeFailure catch (e, st) {
        _log.error('Mount failed for $canonical', e, st);
        _setError(canonical, e.message, errorKey: e.key, errorValues: e.values);
      } catch (e, st) {
        _log.error('Mount failed for $canonical', e, st);
        _setError(canonical, e.toString());
      }

      await _persistMounts();
      _notify();
      return _mounts[canonical]!;
    } finally {
      _pendingMounts.remove(canonical);
      startupComplete.complete();
    }
  }

  /// Unmount the drive at [mountPoint].
  ///
  /// Sends the platform unmount command and tears down the helper process.
  Future<void> unmount(String mountPoint) async {
    _requireDesktop();

    final canonical = _canonicalize(mountPoint);
    final pending = _pendingUnmounts[canonical];
    if (pending != null) return pending.future;
    final entry = _mounts[canonical];
    if (entry == null) return;
    if (!_processes.containsKey(canonical) ||
        (entry.status != MountStatus.mounted && entry.status != MountStatus.error)) {
      return;
    }

    final unmountComplete = Completer<void>();
    _pendingUnmounts[canonical] = unmountComplete;
    try {
      _mounts[canonical] = entry.copyWith(status: MountStatus.unmounting);
      _notify();

      try {
        await performPlatformUnmount(canonical);
        await _stopBridge(canonical);
        _mounts[canonical] = entry.copyWith(status: MountStatus.unmounted);
        _log.info('Unmounted $canonical');
      } catch (e, st) {
        _log.error('Unmount failed for $canonical', e, st);
        _setError(canonical, e.toString(),
            errorKey: 'unmountFailed', errorValues: {'error': '$e'});
      }

      await _persistMounts();
      _notify();
    } finally {
      _pendingUnmounts.remove(canonical);
      unmountComplete.complete();
    }
  }

  /// Unmount all active mounts. Typically called on app exit.
  Future<void> unmountAll() async {
    if (!isSupported) return;
    final existing = _unmountAllComplete;
    if (existing != null) return existing.future;
    final completion = Completer<void>();
    _unmountAllComplete = completion;
    try {
      await Future.wait(_pendingMounts.values.map((pending) => pending.future));
      await Future.wait(_pendingUnmounts.values.map((pending) => pending.future));
      final keys = List<String>.from(_mounts.keys);
      for (final key in keys) {
        if (_processes.containsKey(key)) {
          await unmount(key);
        }
      }
      // A separate unmount can start while a previous operation is awaited,
      // including one whose helper subsequently exits.
      await Future.wait(_pendingUnmounts.values.map((pending) => pending.future));
    } finally {
      _unmountAllComplete = null;
      completion.complete();
    }
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Returns all known [MountEntry] objects (mounted, unmounted, and error).
  List<MountEntry> getMounts() => List.unmodifiable(_mounts.values.toList());

  /// Returns only the entries that are currently mounted.
  List<MountEntry> getActiveMounts() =>
      _mounts.values.where((e) => e.status == MountStatus.mounted).toList();

  /// Returns true if [mountPoint] currently has status [MountStatus.mounted].
  bool isMounted(String mountPoint) {
    final e = _mounts[_canonicalize(mountPoint)];
    return e?.status == MountStatus.mounted;
  }

  /// Remove a mount entry entirely (must be unmounted first).
  Future<void> removeMount(String mountPoint) async {
    final canonical = _canonicalize(mountPoint);
    if (_pendingMounts.containsKey(canonical) ||
        _pendingUnmounts.containsKey(canonical) ||
        {MountStatus.mounting, MountStatus.unmounting}
        .contains(_mounts[canonical]?.status)) {
      throw StateError('Cannot remove a mount while its state is changing');
    }
    if (_processes.containsKey(canonical)) {
      await unmount(canonical);
      if (_processes.containsKey(canonical)) {
        throw StateError('Cannot remove a mount that is still active');
      }
    }
    _mounts.remove(canonical);
    await _persistMounts();
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Load persisted mount configurations from SharedPreferences.
  /// Does not automatically remount — call [mount] for each entry if desired.
  Future<void> loadPersistedMounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefKey) ?? [];
      for (final item in raw) {
        final parts = item.split('\x1F'); // unit separator
        if (parts.length < 4) continue;
        final m = MountEntry.fromMap({
          'mountPoint': parts[0],
          'label': parts[1],
          'provider': parts[2],
          'remotePath': parts[3],
          if (parts.length > 4) 'macBackend': parts[4],
        });
        _mounts.putIfAbsent(m.mountPoint, () => m);
      }
      _notify();
    } catch (e) {
      _log.error('Failed to load persisted mounts', e);
    }
  }

  Future<void> _persistMounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _mounts.values
          .map(
            (e) =>
                [e.mountPoint, e.label, e.provider, e.remotePath, e.macBackend.name].join('\x1F'),
          )
          .toList();
      await prefs.setStringList(_prefKey, list);
    } catch (e) {
      _log.error('Failed to persist mounts', e);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _requireDesktop() {
    if (!isSupported) {
      throw TerminalMountUnsupportedError(
        TerminalMountCode.mountUnsupported,
        'FUSE mounts are only available on macOS, Linux, and Windows desktop.',
      );
    }
  }

  String _canonicalize(String path) {
    // Normalise path, remove trailing slash (unless root).
    final norm = p.normalize(path);
    if (norm != p.separator && norm.endsWith(p.separator)) {
      return norm.substring(0, norm.length - 1);
    }
    return norm;
  }

  /// Checks the OS mount table before taking ownership of a mount point.
  /// Overridable so state tests never need to mount a real filesystem.
  Future<bool> isPlatformMountPoint(String mountPoint) async {
    var physicalPath = p.normalize(p.absolute(mountPoint));
    if (await Directory(mountPoint).exists()) {
      physicalPath = await Directory(mountPoint).resolveSymbolicLinks();
    }
    if (Platform.isMacOS) {
      final result = await Process.run('/sbin/mount', []);
      if (result.exitCode != 0) {
        throw StateError('mount returned ${result.exitCode}: ${result.stderr}');
      }
      return (result.stdout as String)
          .split('\n')
          .any((line) => line.contains(' on $physicalPath ('));
    }
    if (Platform.isLinux) {
      final lines = await File('/proc/self/mountinfo').readAsLines();
      for (final line in lines) {
        final fields = line.split(' ');
        if (fields.length < 5) continue;
        final path = fields[4]
            .replaceAll(r'\040', ' ')
            .replaceAll(r'\011', '\t')
            .replaceAll(r'\012', '\n')
            .replaceAll(r'\134', r'\');
        if (path == physicalPath) return true;
      }
    }
    return false;
  }

  void _setError(
    String canonical,
    String message, {
    String? errorKey,
    Map<String, Object> errorValues = const {},
  }) {
    final previous =
        _mounts[canonical] ??
        MountEntry(
          mountPoint: canonical,
          label: canonical,
          provider: '',
          remotePath: '',
        );
    _mounts[canonical] = MountEntry(
      mountPoint: previous.mountPoint,
      label: previous.label,
      provider: previous.provider,
      remotePath: previous.remotePath,
      macBackend: previous.macBackend,
      status: MountStatus.error,
      errorMessage: message,
      errorKey: errorKey,
      errorValues: errorValues,
      helperPid: _processes.containsKey(canonical) ? previous.helperPid : null,
    );
    _log.warn('Mount error at $canonical: $message');
    _notify();
  }

  void _notify() => onChanged?.call();

  // ---------------------------------------------------------------------------
  // Bridge management
  // ---------------------------------------------------------------------------

  Future<void> _startBridge(MountEntry entry, CloudStorageClient client) async {
    if (!Platform.isMacOS || !await File(macBridgePath).exists()) {
      throw StateError(bridgeMissing);
    }
    final runtime = macFuseRuntime(entry.macBackend);
    final fs = FuseFilesystem(client: client, remotePath: entry.remotePath);
    _filesystems[entry.mountPoint] = fs;
    unawaited(fs.serveRequests());
    Process? process;
    try {
      final socketPath = await fs.ready.timeout(const Duration(seconds: 5));
      process = await Process.start(macBridgePath, [
        entry.mountPoint,
        socketPath,
        runtime,
      ]);
      int? exitStatus;
      unawaited(process.exitCode.then((code) => exitStatus = code));
      final mounted = Completer<void>();
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line == 'MOUNTED' && !mounted.isCompleted) mounted.complete();
            },
            onError: (Object e) {
              if (!mounted.isCompleted) mounted.completeError(e);
            },
          );
      final errors = StringBuffer();
      process.stderr.transform(utf8.decoder).listen((chunk) {
        if (errors.length < 4096) errors.write(chunk);
      });
      await Future.any<void>([
        mounted.future,
        process.exitCode.then(
          (code) => throw _MountBridgeFailure(
            'helperExited',
            'FUSE bridge exited ($code): $errors',
            {'code': code, 'error': '$errors'},
          ),
        ),
      ]).timeout(const Duration(seconds: 20));
      var visible = false;
      for (var attempt = 0; attempt < 20; attempt++) {
        if (exitStatus != null) {
          throw _MountBridgeFailure(
            'helperExited',
            'FUSE bridge exited ($exitStatus): $errors',
            {'code': exitStatus!, 'error': '$errors'},
          );
        }
        if (await isPlatformMountPoint(entry.mountPoint)) {
          visible = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!visible) {
        throw _MountBridgeFailure(
          'mountNotVisible',
          'FUSE bridge started, but no mount appeared at '
              '${entry.mountPoint}: $errors',
          {'path': entry.mountPoint, 'error': '$errors'},
        );
      }
      _processes[entry.mountPoint] = process;
      entry.helperPid = process.pid;
      unawaited(
        process.exitCode.then((code) {
          if (_processes[entry.mountPoint] == process) {
            _processes.remove(entry.mountPoint);
            final stoppedFilesystem = _filesystems.remove(entry.mountPoint);
            if (stoppedFilesystem != null) unawaited(stoppedFilesystem.dispose());
            _setError(
              entry.mountPoint,
              'FUSE bridge exited ($code)',
              errorKey: 'helperExited',
              errorValues: {'code': code, 'error': ''},
            );
          }
        }),
      );
    } catch (_) {
      if (process != null && runtime.startsWith('macfuse-')) {
        // macFUSE can leave mount_macfuse waiting for an unavailable kext.
        // Stop that child before the bridge exits and it is reparented.
        try {
          final children = await Process.run('/usr/bin/pgrep', [
            '-P',
            '${process.pid}',
          ]);
          for (final line in (children.stdout as String).split('\n')) {
            final pid = int.tryParse(line.trim());
            if (pid != null) Process.killPid(pid, ProcessSignal.sigterm);
          }
        } catch (_) {}
      }
      process?.kill(ProcessSignal.sigterm);
      _filesystems.remove(entry.mountPoint);
      await fs.dispose();
      rethrow;
    }
  }

  Future<void> _startRclone(MountEntry entry) async {
    final executable = await _rclonePath();
    if (executable == null) throw StateError(rcloneMissing);
    final process = await Process.start(executable, [
      'nfsmount', entry.remotePath, entry.mountPoint, '--read-only',
      '--addr', '127.0.0.1:0',
    ]);
    final errors = StringBuffer();
    process.stdout.drain<void>();
    process.stderr.transform(utf8.decoder).listen((text) {
      if (errors.length < 4096) errors.write(text);
    });
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    try {
      var mounted = false;
      for (var attempt = 0; attempt < 100 && !exited; attempt++) {
        if (await isPlatformMountPoint(entry.mountPoint)) {
          mounted = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted) {
        throw _MountBridgeFailure(
          'rcloneFailed', 'rclone NFS mount failed: $errors', {'error': '$errors'},
        );
      }
      _processes[entry.mountPoint] = process;
      entry.helperPid = process.pid;
      unawaited(process.exitCode.then((code) {
        if (_processes[entry.mountPoint] == process) {
          _processes.remove(entry.mountPoint);
          _setError(entry.mountPoint, 'rclone exited ($code)',
              errorKey: 'helperExited', errorValues: {'code': code, 'error': ''});
        }
      }));
    } catch (_) {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 3), onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      });
      rethrow;
    }
  }

  @visibleForTesting
  String get macBridgePath => p.normalize(
    p.join(
      p.dirname(Platform.resolvedExecutable),
      '../Resources/crispcloud_fuse_bridge',
    ),
  );

  Future<void> _stopBridge(String mountPoint) async {
    final process = _processes.remove(mountPoint);
    if (process != null) {
      try {
        process.kill(ProcessSignal.sigterm);
        // Give it a moment to clean up, then force-kill.
        await process.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (_) {}
    }
    final fs = _filesystems.remove(mountPoint);
    await fs?.dispose();
  }

  @visibleForTesting
  Future<void> performPlatformUnmount(String mountPoint) async {
    ProcessResult? result;
      if (Platform.isLinux) {
        // Try fusermount3 first, fall back to fusermount.
        result = await Process.run('fusermount3', ['-u', mountPoint]);
        if (result.exitCode != 0) {
          result = await Process.run('fusermount', ['-u', mountPoint]);
        }
      } else if (Platform.isMacOS) {
        result = await Process.run('diskutil', [
          'unmount',
          'force',
          mountPoint,
        ]);
      } else if (Platform.isWindows) {
        // WinFsp: net use /delete or the WinFsp net command.
        result = await Process.run('net', ['use', mountPoint, '/delete', '/y']);
      }
    if (result != null && result.exitCode != 0 &&
        await isPlatformMountPoint(mountPoint)) {
      throw FileSystemException('Unmount failed: ${result.stderr}', mountPoint);
    }
    if (await isPlatformMountPoint(mountPoint)) {
      throw FileSystemException('Mount is still active', mountPoint);
    }
  }
}
