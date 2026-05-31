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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_storage_interface.dart';
import 'fuse_filesystem.dart';
import 'fuse_helper_script.dart';
import 'log_service.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

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

  /// Current lifecycle state.
  MountStatus status;

  /// Optional error message when [status] == [MountStatus.error].
  String? errorMessage;

  /// PID of the helper process, if running.
  int? helperPid;

  MountEntry({
    required this.mountPoint,
    required this.label,
    required this.provider,
    required this.remotePath,
    this.status = MountStatus.unmounted,
    this.errorMessage,
    this.helperPid,
  });

  /// Serialise to a SharedPreferences-compatible string map.
  Map<String, String> toMap() => {
        'mountPoint': mountPoint,
        'label': label,
        'provider': provider,
        'remotePath': remotePath,
      };

  factory MountEntry.fromMap(Map<String, String> m) => MountEntry(
        mountPoint: m['mountPoint']!,
        label: m['label']!,
        provider: m['provider']!,
        remotePath: m['remotePath']!,
      );

  MountEntry copyWith({MountStatus? status, String? errorMessage, int? helperPid}) =>
      MountEntry(
        mountPoint: mountPoint,
        label: label,
        provider: provider,
        remotePath: remotePath,
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
        helperPid: helperPid ?? this.helperPid,
      );
}

enum MountStatus { unmounted, mounting, mounted, unmounting, error }

// ---------------------------------------------------------------------------
// FuseMountService
// ---------------------------------------------------------------------------

class FuseMountService {
  static const _log = Log('FuseMountService');

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

  /// Notifier called whenever the mount list changes (for Riverpod providers).
  void Function()? onChanged;

  // ---------------------------------------------------------------------------
  // Availability check
  // ---------------------------------------------------------------------------

  /// Detects whether the platform FUSE library is installed and runnable.
  ///
  /// On Linux this checks for `fusermount3` or `fusermount`.
  /// On macOS it checks for `mount_macfuse` or `/Library/Filesystems/macfuse.fs`.
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
      return 'Error checking FUSE availability: $e';
    }
    return 'Unsupported platform';
  }

  Future<String?> _checkLinuxFuse() async {
    // Try fusermount3 first (fuse3), fall back to fusermount (fuse2).
    for (final cmd in ['fusermount3', 'fusermount']) {
      final result = await Process.run('which', [cmd]);
      if (result.exitCode == 0) return null; // found
    }
    return 'libfuse / fusermount3 not found. Install via: sudo apt install fuse3  '
        '(or equivalent for your distro).';
  }

  Future<String?> _checkMacFuse() async {
    // macFUSE installs a kext; check for the filesystem bundle.
    if (await Directory('/Library/Filesystems/macfuse.fs').exists()) return null;
    // FUSE-T alternative.
    if (await File('/Library/Filesystems/fuse-t.fs/Contents/MacOS/fuse-t').exists()) {
      return null;
    }
    final result = await Process.run('which', ['mount_macfuse']);
    if (result.exitCode == 0) return null;
    return 'macFUSE not found. Install from https://osxfuse.github.io '
        'or via Homebrew: brew install macfuse';
  }

  Future<String?> _checkWinFsp() async {
    // WinFsp typically installs to Program Files.
    for (final path in [
      r'C:\Program Files (x86)\WinFsp\bin\winfsp-launcher-x64.exe',
      r'C:\Program Files\WinFsp\bin\winfsp-launcher-x64.exe',
    ]) {
      if (await File(path).exists()) return null;
    }
    return 'WinFsp not found. Install from https://winfsp.dev';
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
    required CloudStorageClient client,
    required String remotePath,
    required String mountPoint,
    String? label,
  }) async {
    _requireDesktop();

    final canonical = _canonicalize(mountPoint);
    if (_mounts.containsKey(canonical) &&
        _mounts[canonical]!.status == MountStatus.mounted) {
      throw ArgumentError('Mount point "$canonical" is already mounted');
    }

    final entry = MountEntry(
      mountPoint: canonical,
      label: label ?? '${client.providerName}:$remotePath',
      provider: client.providerName,
      remotePath: remotePath,
      status: MountStatus.mounting,
    );
    _mounts[canonical] = entry;
    _notify();

    // Ensure mount point directory exists.
    try {
      await Directory(canonical).create(recursive: true);
    } catch (e) {
      _setError(canonical, 'Cannot create mount point: $e');
      return _mounts[canonical]!;
    }

    // Check FUSE availability before proceeding.
    final fuseError = await checkFuseAvailability();
    if (fuseError != null) {
      _setError(canonical, fuseError);
      return _mounts[canonical]!;
    }

    // Build and start the FUSE bridge.
    try {
      await _startBridge(entry, client);
      _mounts[canonical] = entry.copyWith(status: MountStatus.mounted);
      _log.info('Mounted ${entry.provider}:${entry.remotePath} → $canonical');
    } catch (e, st) {
      _log.error('Mount failed for $canonical', e, st);
      _setError(canonical, e.toString());
    }

    await _persistMounts();
    _notify();
    return _mounts[canonical]!;
  }

  /// Unmount the drive at [mountPoint].
  ///
  /// Sends the platform unmount command and tears down the helper process.
  Future<void> unmount(String mountPoint) async {
    _requireDesktop();

    final canonical = _canonicalize(mountPoint);
    final entry = _mounts[canonical];
    if (entry == null) return;

    _mounts[canonical] = entry.copyWith(status: MountStatus.unmounting);
    _notify();

    try {
      await _stopBridge(canonical);
      await _platformUnmount(canonical);
      _mounts[canonical] = entry.copyWith(status: MountStatus.unmounted);
      _log.info('Unmounted $canonical');
    } catch (e, st) {
      _log.error('Unmount failed for $canonical', e, st);
      _setError(canonical, e.toString());
    }

    await _persistMounts();
    _notify();
  }

  /// Unmount all active mounts. Typically called on app exit.
  Future<void> unmountAll() async {
    if (!isSupported) return;
    final keys = List<String>.from(_mounts.keys);
    for (final key in keys) {
      if (_mounts[key]?.status == MountStatus.mounted) {
        await unmount(key);
      }
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
    if (_mounts[canonical]?.status == MountStatus.mounted) {
      await unmount(canonical);
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
          .map((e) => [e.mountPoint, e.label, e.provider, e.remotePath]
              .join('\x1F'))
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
      throw UnsupportedError(
          'FUSE mounts are only available on macOS, Linux, and Windows desktop.');
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

  void _setError(String canonical, String message) {
    _mounts[canonical] = (_mounts[canonical] ?? MountEntry(
      mountPoint: canonical,
      label: canonical,
      provider: '',
      remotePath: '',
    )).copyWith(status: MountStatus.error, errorMessage: message);
    _log.warn('Mount error at $canonical: $message');
    _notify();
  }

  void _notify() => onChanged?.call();

  // ---------------------------------------------------------------------------
  // Bridge management
  // ---------------------------------------------------------------------------

  Future<void> _startBridge(MountEntry entry, CloudStorageClient client) async {
    // Create the in-process FUSE filesystem bridge.
    final fs = FuseFilesystem(client: client, remotePath: entry.remotePath);
    _filesystems[entry.mountPoint] = fs;

    // Write the platform-specific helper script.
    final scriptPath = await FuseHelperScript.writeScript(entry.mountPoint);
    _log.debug('Helper script written to $scriptPath');

    // Spawn the helper process that performs the actual FUSE mount.
    final process = await _spawnHelper(scriptPath, entry.mountPoint);
    _processes[entry.mountPoint] = process;

    // Monitor the process in the background.
    unawaited(process.exitCode.then((code) {
      if (code != 0) {
        _log.warn('FUSE helper exited with code $code for ${entry.mountPoint}');
        if (_mounts[entry.mountPoint]?.status == MountStatus.mounted) {
          _setError(entry.mountPoint,
              'FUSE helper process exited unexpectedly (code $code).');
        }
      }
    }));

    // Give the helper a brief moment to establish the mount.
    await Future.delayed(const Duration(milliseconds: 800));

    // Start the filesystem event loop in a separate zone.
    unawaited(fs.serveRequests());
  }

  Future<Process> _spawnHelper(String scriptPath, String mountPoint) async {
    if (Platform.isWindows) {
      return Process.start('cmd', ['/c', scriptPath, mountPoint],
          mode: ProcessStartMode.detachedWithStdio);
    } else {
      await Process.run('chmod', ['+x', scriptPath]);
      return Process.start('/bin/sh', [scriptPath, mountPoint],
          mode: ProcessStartMode.detachedWithStdio);
    }
  }

  Future<void> _stopBridge(String mountPoint) async {
    final fs = _filesystems.remove(mountPoint);
    await fs?.dispose();

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
  }

  Future<void> _platformUnmount(String mountPoint) async {
    try {
      if (Platform.isLinux) {
        // Try fusermount3 first, fall back to fusermount.
        var result = await Process.run('fusermount3', ['-u', mountPoint]);
        if (result.exitCode != 0) {
          result = await Process.run('fusermount', ['-u', mountPoint]);
        }
        if (result.exitCode != 0) {
          _log.warn('fusermount returned ${result.exitCode}: ${result.stderr}');
        }
      } else if (Platform.isMacOS) {
        final result = await Process.run('diskutil', ['unmount', 'force', mountPoint]);
        if (result.exitCode != 0) {
          _log.warn('diskutil unmount returned ${result.exitCode}: ${result.stderr}');
        }
      } else if (Platform.isWindows) {
        // WinFsp: net use /delete or the WinFsp net command.
        await Process.run('net', ['use', mountPoint, '/delete', '/y']);
      }
    } catch (e) {
      _log.warn('Platform unmount command failed: $e');
    }
  }
}
