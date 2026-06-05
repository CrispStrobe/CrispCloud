// lib/services/xdg_service.dart
//
// XDG Base Directory Specification compliance for Linux.
// On Linux, paths follow XDG conventions (respecting env vars):
//   config  → $XDG_CONFIG_HOME/crispcloud  (~/.config/crispcloud)
//   data    → $XDG_DATA_HOME/crispcloud    (~/.local/share/crispcloud)
//   cache   → $XDG_CACHE_HOME/crispcloud   (~/.cache/crispcloud)
//   state   → $XDG_STATE_HOME/crispcloud   (~/.local/state/crispcloud)
//   runtime → $XDG_RUNTIME_DIR            (nullable, no fallback)
//
// On non-Linux platforms the service delegates to path_provider.
//
// Public API:
//   XdgService.instance  — singleton (call XdgService.init() first)
//   configHome / dataHome / cacheHome / stateHome / runtimeDir  — directory paths
//   getConfigPath(filename) / getDataPath / getCachePath / getStatePath
//   ensureDirectories()  — mkdir -p for all non-null XDG dirs
//   migrateFromLegacy()  — detect and optionally move old path_provider data
//   isLinux              — true only on Linux (not web)

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// XDG Base Directory categories.
enum XdgDirectory {
  config,
  data,
  cache,
  state,
  runtime,
}

/// Resolves XDG-compliant paths on Linux and delegates to [path_provider] on
/// other platforms.
class XdgService {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  static XdgService? _instance;

  /// Returns the singleton instance. Must call [init] first.
  static XdgService get instance {
    assert(_instance != null,
        'XdgService.init() must be called before accessing XdgService.instance');
    return _instance!;
  }

  /// Initialise the singleton. Safe to call multiple times; subsequent calls
  /// are no-ops unless [force] is true (useful in tests).
  static Future<XdgService> init({
    Map<String, String>? environmentOverride,
    bool force = false,
  }) async {
    if (_instance != null && !force) return _instance!;
    final svc = XdgService._();
    await svc._initialise(environmentOverride: environmentOverride);
    _instance = svc;
    return svc;
  }

  /// Reset the singleton (for testing).
  static void reset() => _instance = null;

  /// Create an instance that **always** uses the XDG Linux code path,
  /// regardless of the host platform. Intended for unit tests only.
  ///
  /// Does NOT register the result as the global singleton so individual tests
  /// remain independent. Call [reset] before/after if you want a clean slate.
  static Future<XdgService> initForTest(Map<String, String> env) async {
    final svc = XdgService._();
    await svc._initialiseLinux(env);
    return svc;
  }

  XdgService._();

  // ---------------------------------------------------------------------------
  // Resolved paths
  // ---------------------------------------------------------------------------

  late final String configHome;
  late final String dataHome;
  late final String cacheHome;
  late final String stateHome;

  /// May be null when XDG_RUNTIME_DIR is not set (no fallback per spec).
  String? runtimeDir;

  // ---------------------------------------------------------------------------
  // Platform detection
  // ---------------------------------------------------------------------------

  /// True only on Linux (excludes web).
  bool get isLinux => !kIsWeb && Platform.isLinux;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Core XDG initialisation logic; extracted so it can be called from both
  /// [_initialise] (production) and [initForTest] (test-only factory).
  Future<void> _initialiseLinux(Map<String, String> env) async {
    final home = _resolveHome(env);

    configHome = _xdgDir(
      env: env,
      variable: 'XDG_CONFIG_HOME',
      fallback: p.join(home, '.config', 'crispcloud'),
      appSubdir: true,
    );

    dataHome = _xdgDir(
      env: env,
      variable: 'XDG_DATA_HOME',
      fallback: p.join(home, '.local', 'share', 'crispcloud'),
      appSubdir: true,
    );

    cacheHome = _xdgDir(
      env: env,
      variable: 'XDG_CACHE_HOME',
      fallback: p.join(home, '.cache', 'crispcloud'),
      appSubdir: true,
    );

    stateHome = _xdgDir(
      env: env,
      variable: 'XDG_STATE_HOME',
      fallback: p.join(home, '.local', 'state', 'crispcloud'),
      appSubdir: true,
    );

    // Runtime dir has no fallback per XDG spec.
    final rawRuntime = env['XDG_RUNTIME_DIR'];
    runtimeDir = (rawRuntime != null && rawRuntime.isNotEmpty)
        ? _stripTrailingSlash(rawRuntime)
        : null;
  }

  Future<void> _initialise({Map<String, String>? environmentOverride}) async {
    if (isLinux) {
      final env = environmentOverride ?? Platform.environment;
      await _initialiseLinux(env);
    } else if (kIsWeb) {
      // Web: return safe in-memory stubs so callers don't crash.
      configHome = '/crispcloud/config';
      dataHome = '/crispcloud/data';
      cacheHome = '/crispcloud/cache';
      stateHome = '/crispcloud/state';
      runtimeDir = null;
    } else {
      // macOS / Windows / iOS / Android: delegate to path_provider.
      final support = await getApplicationSupportDirectory();
      final cache = await getTemporaryDirectory();

      configHome = p.join(support.path, 'config');
      dataHome = p.join(support.path, 'data');
      cacheHome = p.join(cache.path, 'crispcloud');
      stateHome = p.join(support.path, 'state');
      runtimeDir = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Path helpers
  // ---------------------------------------------------------------------------

  /// Full path for [filename] inside the config directory.
  String getConfigPath(String filename) => p.join(configHome, filename);

  /// Full path for [filename] inside the data directory.
  String getDataPath(String filename) => p.join(dataHome, filename);

  /// Full path for [filename] inside the cache directory.
  String getCachePath(String filename) => p.join(cacheHome, filename);

  /// Full path for [filename] inside the state directory.
  String getStatePath(String filename) => p.join(stateHome, filename);

  /// Full path for [filename] inside the runtime directory.
  /// Returns null when [runtimeDir] is null.
  String? getRuntimePath(String filename) =>
      runtimeDir != null ? p.join(runtimeDir!, filename) : null;

  /// Path for the given [directory] type and [filename].
  String? getPath(XdgDirectory directory, String filename) {
    switch (directory) {
      case XdgDirectory.config:
        return getConfigPath(filename);
      case XdgDirectory.data:
        return getDataPath(filename);
      case XdgDirectory.cache:
        return getCachePath(filename);
      case XdgDirectory.state:
        return getStatePath(filename);
      case XdgDirectory.runtime:
        return getRuntimePath(filename);
    }
  }

  // ---------------------------------------------------------------------------
  // Directory creation
  // ---------------------------------------------------------------------------

  /// Create all XDG base directories (and any intermediate directories).
  /// Safe to call when directories already exist.
  /// Does nothing on web.
  Future<void> ensureDirectories() async {
    if (kIsWeb) return;
    for (final dir in [configHome, dataHome, cacheHome, stateHome]) {
      await Directory(dir).create(recursive: true);
    }
    // runtime dir is managed by the OS/session manager, do not create it.
  }

  /// Create a single subdirectory inside one of the XDG base directories.
  Future<Directory> ensureSubdir(XdgDirectory base, String subdirName) async {
    final basePath = _basePathFor(base);
    if (basePath == null) {
      throw StateError('Cannot create subdir for runtime dir when it is null');
    }
    final dir = Directory(p.join(basePath, subdirName));
    await dir.create(recursive: true);
    return dir;
  }

  // ---------------------------------------------------------------------------
  // Legacy migration
  // ---------------------------------------------------------------------------

  /// Detect whether legacy config (stored by path_provider before XDG support)
  /// exists and — if so — move it to the correct XDG location.
  ///
  /// Returns a [XdgMigrationResult] describing what happened.
  /// On non-Linux platforms this is a no-op.
  Future<XdgMigrationResult> migrateFromLegacy() async {
    if (!isLinux) {
      return XdgMigrationResult(
        needed: false,
        completed: false,
        message: 'Migration only applies to Linux.',
      );
    }

    Directory? legacyDir;
    try {
      legacyDir = await getApplicationSupportDirectory();
    } catch (_) {
      return XdgMigrationResult(
        needed: false,
        completed: false,
        message: 'Could not determine legacy path.',
      );
    }

    final legacyPath = legacyDir.path;

    // If the legacy path already equals the XDG config home there is nothing
    // to migrate.
    if (legacyPath == configHome || !Directory(legacyPath).existsSync()) {
      return XdgMigrationResult(
        needed: false,
        completed: false,
        message: 'No legacy data found at $legacyPath.',
      );
    }

    // List files that should be moved.
    final legacyFiles = <FileSystemEntity>[];
    try {
      legacyFiles.addAll(
        Directory(legacyPath).listSync(recursive: false),
      );
    } catch (_) {
      return XdgMigrationResult(
        needed: false,
        completed: false,
        message: 'Legacy directory is empty or unreadable.',
      );
    }

    if (legacyFiles.isEmpty) {
      return XdgMigrationResult(
        needed: false,
        completed: false,
        message: 'Legacy directory is empty.',
      );
    }

    // Ensure destination exists.
    await ensureDirectories();

    final moved = <String>[];
    final failed = <String>[];

    for (final entity in legacyFiles) {
      final dest = p.join(configHome, p.basename(entity.path));
      try {
        if (entity is File) {
          await entity.copy(dest);
          await entity.delete();
          moved.add(entity.path);
        } else if (entity is Directory) {
          // Recursively copy directory then remove source.
          await _copyDirectory(entity, Directory(dest));
          await entity.delete(recursive: true);
          moved.add(entity.path);
        }
      } catch (_) {
        failed.add(entity.path);
      }
    }

    return XdgMigrationResult(
      needed: true,
      completed: failed.isEmpty,
      movedPaths: moved,
      failedPaths: failed,
      message: failed.isEmpty
          ? 'Migrated ${moved.length} item(s) from $legacyPath to $configHome.'
          : 'Partial migration: ${moved.length} moved, ${failed.length} failed.',
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Resolve the current user's home directory from the environment.
  String _resolveHome(Map<String, String> env) {
    final home = env['HOME'];
    if (home != null && home.isNotEmpty) {
      return _stripTrailingSlash(home);
    }
    // Fallback: ask the OS.
    try {
      return Platform.environment['HOME'] ?? '/tmp';
    } catch (_) {
      return '/tmp';
    }
  }

  /// Build an XDG path from [env], reading [variable].
  /// If the variable is absent/empty, uses [fallback].
  /// When [appSubdir] is true and the env variable is set, appends 'crispcloud'
  /// as a subdirectory (per XDG spec: apps use $XDG_*_HOME/<appname>).
  String _xdgDir({
    required Map<String, String> env,
    required String variable,
    required String fallback,
    bool appSubdir = true,
  }) {
    final raw = env[variable];
    if (raw == null || raw.isEmpty) return fallback;
    final base = _stripTrailingSlash(raw);
    return appSubdir ? p.join(base, 'crispcloud') : base;
  }

  String _stripTrailingSlash(String path) {
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  String? _basePathFor(XdgDirectory base) {
    switch (base) {
      case XdgDirectory.config:
        return configHome;
      case XdgDirectory.data:
        return dataHome;
      case XdgDirectory.cache:
        return cacheHome;
      case XdgDirectory.state:
        return stateHome;
      case XdgDirectory.runtime:
        return runtimeDir;
    }
  }

  Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final destPath = p.join(dst.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Migration result
// ---------------------------------------------------------------------------

/// Describes the outcome of a [XdgService.migrateFromLegacy] call.
class XdgMigrationResult {
  /// Whether migration was needed (i.e. legacy data was found).
  final bool needed;

  /// Whether migration completed without errors.
  final bool completed;

  /// Human-readable message.
  final String message;

  /// Paths that were successfully moved.
  final List<String> movedPaths;

  /// Paths that could not be moved.
  final List<String> failedPaths;

  const XdgMigrationResult({
    required this.needed,
    required this.completed,
    required this.message,
    this.movedPaths = const [],
    this.failedPaths = const [],
  });

  @override
  String toString() => 'XdgMigrationResult(needed: $needed, '
      'completed: $completed, message: "$message")';
}
