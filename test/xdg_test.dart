// test/xdg_test.dart
//
// Unit tests for XdgService and XdgMigrationResult.
//
// Strategy:
//   - XdgService.initForTest(env) bypasses the platform guard and always runs
//     the XDG Linux initialisation path with an injected env map.
//   - File-system tests use a real temporary directory created per-test.
//   - The singleton is reset (XdgService.reset()) between tests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:crisp_cloud/services/xdg_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      '/tmp/crispcloud-support';

  @override
  Future<String?> getTemporaryPath() async => '/tmp';
}

// ---------------------------------------------------------------------------
// Convenience wrapper
// ---------------------------------------------------------------------------

/// Shorthand to create an XdgService driven by an explicit env map via the
/// test-only [XdgService.initForTest] factory.
Future<XdgService> _svc({
  String home = '/home/testuser',
  String? config,
  String? data,
  String? cache,
  String? state,
  String? runtime,
}) {
  final env = <String, String>{
    'HOME': home,
    if (config != null) 'XDG_CONFIG_HOME': config,
    if (data != null) 'XDG_DATA_HOME': data,
    if (cache != null) 'XDG_CACHE_HOME': cache,
    if (state != null) 'XDG_STATE_HOME': state,
    if (runtime != null) 'XDG_RUNTIME_DIR': runtime,
  };
  return XdgService.initForTest(env);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProvider();

  tearDown(() => XdgService.reset());

  // -------------------------------------------------------------------------
  // XdgDirectory enum
  // -------------------------------------------------------------------------
  group('XdgDirectory enum', () {
    test('has the expected values', () {
      expect(XdgDirectory.values, hasLength(5));
      expect(XdgDirectory.values, contains(XdgDirectory.config));
      expect(XdgDirectory.values, contains(XdgDirectory.data));
      expect(XdgDirectory.values, contains(XdgDirectory.cache));
      expect(XdgDirectory.values, contains(XdgDirectory.state));
      expect(XdgDirectory.values, contains(XdgDirectory.runtime));
    });

    test('each value has a distinct name', () {
      final names = XdgDirectory.values.map((e) => e.name).toSet();
      expect(names, hasLength(XdgDirectory.values.length));
    });
  });

  // -------------------------------------------------------------------------
  // Default paths (no XDG env vars set)
  // -------------------------------------------------------------------------
  group('Default XDG paths (no env vars)', () {
    late XdgService svc;
    setUp(() async {
      svc = await _svc(home: '/home/alice');
    });

    test('configHome defaults to ~/.config/crispcloud', () {
      expect(svc.configHome, '/home/alice/.config/crispcloud');
    });

    test('dataHome defaults to ~/.local/share/crispcloud', () {
      expect(svc.dataHome, '/home/alice/.local/share/crispcloud');
    });

    test('cacheHome defaults to ~/.cache/crispcloud', () {
      expect(svc.cacheHome, '/home/alice/.cache/crispcloud');
    });

    test('stateHome defaults to ~/.local/state/crispcloud', () {
      expect(svc.stateHome, '/home/alice/.local/state/crispcloud');
    });

    test('runtimeDir is null when XDG_RUNTIME_DIR is absent', () {
      expect(svc.runtimeDir, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Custom XDG_CONFIG_HOME
  // -------------------------------------------------------------------------
  group('Custom XDG_CONFIG_HOME', () {
    test('uses env var value + crispcloud subdir', () async {
      final svc = await _svc(home: '/home/bob', config: '/custom/cfg');
      expect(svc.configHome, '/custom/cfg/crispcloud');
    });

    test('trailing slash in env var is stripped', () async {
      final svc = await _svc(home: '/home/bob', config: '/custom/cfg/');
      expect(svc.configHome, '/custom/cfg/crispcloud');
    });

    test('data / cache / state still use defaults', () async {
      final svc = await _svc(home: '/home/bob', config: '/custom/cfg');
      expect(svc.dataHome, '/home/bob/.local/share/crispcloud');
      expect(svc.cacheHome, '/home/bob/.cache/crispcloud');
      expect(svc.stateHome, '/home/bob/.local/state/crispcloud');
    });
  });

  // -------------------------------------------------------------------------
  // Custom XDG_DATA_HOME
  // -------------------------------------------------------------------------
  group('Custom XDG_DATA_HOME', () {
    test('uses env var value + crispcloud subdir', () async {
      final svc = await _svc(home: '/home/carol', data: '/mnt/data');
      expect(svc.dataHome, '/mnt/data/crispcloud');
    });

    test('trailing slash stripped', () async {
      final svc = await _svc(home: '/home/carol', data: '/mnt/data/');
      expect(svc.dataHome, '/mnt/data/crispcloud');
    });
  });

  // -------------------------------------------------------------------------
  // Custom XDG_CACHE_HOME
  // -------------------------------------------------------------------------
  group('Custom XDG_CACHE_HOME', () {
    test('uses env var value + crispcloud subdir', () async {
      final svc = await _svc(home: '/home/dave', cache: '/tmp/mycache');
      expect(svc.cacheHome, '/tmp/mycache/crispcloud');
    });

    test('trailing slash stripped', () async {
      final svc = await _svc(home: '/home/dave', cache: '/tmp/mycache/');
      expect(svc.cacheHome, '/tmp/mycache/crispcloud');
    });
  });

  // -------------------------------------------------------------------------
  // Custom XDG_STATE_HOME
  // -------------------------------------------------------------------------
  group('Custom XDG_STATE_HOME', () {
    test('uses env var value + crispcloud subdir', () async {
      final svc = await _svc(home: '/home/eve', state: '/var/state');
      expect(svc.stateHome, '/var/state/crispcloud');
    });

    test('trailing slash stripped', () async {
      final svc = await _svc(home: '/home/eve', state: '/var/state/');
      expect(svc.stateHome, '/var/state/crispcloud');
    });
  });

  // -------------------------------------------------------------------------
  // XDG_RUNTIME_DIR
  // -------------------------------------------------------------------------
  group('XDG_RUNTIME_DIR', () {
    test('is null when not set', () async {
      final svc = await _svc(home: '/home/frank');
      expect(svc.runtimeDir, isNull);
    });

    test('is set when env var is present', () async {
      final svc = await _svc(home: '/home/frank', runtime: '/run/user/1000');
      expect(svc.runtimeDir, '/run/user/1000');
    });

    test('trailing slash stripped from runtime dir', () async {
      final svc = await _svc(home: '/home/frank', runtime: '/run/user/1000/');
      expect(svc.runtimeDir, '/run/user/1000');
    });

    test('empty string treated as absent (null)', () async {
      final svc = await XdgService.initForTest({
        'HOME': '/home/frank',
        'XDG_RUNTIME_DIR': '',
      });
      expect(svc.runtimeDir, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Path construction helpers
  // -------------------------------------------------------------------------
  group('getConfigPath', () {
    late XdgService svc;
    setUp(() async {
      svc = await _svc(home: '/home/greta');
    });

    test('appends filename to configHome', () {
      expect(svc.getConfigPath('settings.json'),
          '/home/greta/.config/crispcloud/settings.json');
    });

    test('appends nested filename', () {
      expect(svc.getConfigPath('themes/dark.json'),
          '/home/greta/.config/crispcloud/themes/dark.json');
    });

    test('result is absolute', () {
      expect(p.isAbsolute(svc.getConfigPath('any.json')), isTrue);
    });
  });

  group('getDataPath', () {
    late XdgService svc;
    setUp(() async {
      svc = await _svc(home: '/home/hank');
    });

    test('appends filename to dataHome', () {
      expect(svc.getDataPath('bookmarks.db'),
          '/home/hank/.local/share/crispcloud/bookmarks.db');
    });

    test('result is absolute', () {
      expect(p.isAbsolute(svc.getDataPath('any.db')), isTrue);
    });
  });

  group('getCachePath', () {
    late XdgService svc;
    setUp(() async {
      svc = await _svc(home: '/home/iris');
    });

    test('appends filename to cacheHome', () {
      expect(svc.getCachePath('thumbnail.png'),
          '/home/iris/.cache/crispcloud/thumbnail.png');
    });

    test('result is absolute', () {
      expect(p.isAbsolute(svc.getCachePath('any.png')), isTrue);
    });
  });

  group('getStatePath', () {
    late XdgService svc;
    setUp(() async {
      svc = await _svc(home: '/home/jack');
    });

    test('appends filename to stateHome', () {
      expect(svc.getStatePath('session.json'),
          '/home/jack/.local/state/crispcloud/session.json');
    });

    test('result is absolute', () {
      expect(p.isAbsolute(svc.getStatePath('any.json')), isTrue);
    });
  });

  group('getRuntimePath', () {
    test('returns null when runtimeDir is null', () async {
      final svc = await _svc(home: '/home/kim');
      expect(svc.getRuntimePath('lock'), isNull);
    });

    test('appends filename when runtimeDir is set', () async {
      final svc = await _svc(home: '/home/kim', runtime: '/run/user/1234');
      expect(svc.getRuntimePath('crispcloud.lock'),
          '/run/user/1234/crispcloud.lock');
    });
  });

  group('getPath dispatch', () {
    late XdgService svc;
    setUp(() async {
      svc = await _svc(home: '/home/leo');
    });

    test('config', () {
      expect(svc.getPath(XdgDirectory.config, 'f.json'),
          svc.getConfigPath('f.json'));
    });

    test('data', () {
      expect(svc.getPath(XdgDirectory.data, 'f.db'), svc.getDataPath('f.db'));
    });

    test('cache', () {
      expect(
          svc.getPath(XdgDirectory.cache, 'f.png'), svc.getCachePath('f.png'));
    });

    test('state', () {
      expect(svc.getPath(XdgDirectory.state, 'f.json'),
          svc.getStatePath('f.json'));
    });

    test('runtime returns null when no runtime dir', () {
      expect(svc.getPath(XdgDirectory.runtime, 'f.lock'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // All paths are absolute
  // -------------------------------------------------------------------------
  group('All paths are absolute', () {
    test('with default env', () async {
      final svc = await _svc(home: '/home/mia');
      expect(p.isAbsolute(svc.configHome), isTrue);
      expect(p.isAbsolute(svc.dataHome), isTrue);
      expect(p.isAbsolute(svc.cacheHome), isTrue);
      expect(p.isAbsolute(svc.stateHome), isTrue);
    });

    test('with all custom env vars', () async {
      final svc = await _svc(
        home: '/home/mia',
        config: '/cfg',
        data: '/dat',
        cache: '/cch',
        state: '/st',
        runtime: '/run/user/999',
      );
      expect(p.isAbsolute(svc.configHome), isTrue);
      expect(p.isAbsolute(svc.dataHome), isTrue);
      expect(p.isAbsolute(svc.cacheHome), isTrue);
      expect(p.isAbsolute(svc.stateHome), isTrue);
      expect(p.isAbsolute(svc.runtimeDir!), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Path separator handling
  // -------------------------------------------------------------------------
  group('Path separator handling', () {
    test('no double slashes in default config path', () async {
      final svc = await _svc(home: '/home/nina');
      expect(svc.configHome.contains('//'), isFalse);
    });

    test('no double slashes with trailing slash in XDG_CONFIG_HOME', () async {
      final svc = await _svc(home: '/home/nina', config: '/custom/config/');
      expect(svc.configHome.contains('//'), isFalse);
    });

    test('getConfigPath does not produce double slashes', () async {
      final svc = await _svc(home: '/home/nina');
      expect(svc.getConfigPath('file.json').contains('//'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Tilde expansion (HOME env var used, not literal ~)
  // -------------------------------------------------------------------------
  group('Tilde expansion via HOME env var', () {
    test('different HOME values produce different paths', () async {
      final svc1 = await _svc(home: '/home/user1');
      final svc2 = await _svc(home: '/home/user2');
      expect(svc1.configHome, isNot(svc2.configHome));
    });

    test('HOME with trailing slash does not produce double slashes', () async {
      final svc = await XdgService.initForTest({'HOME': '/home/user/'});
      expect(svc.configHome, isNot(contains('//')));
    });
  });

  // -------------------------------------------------------------------------
  // ensureDirectories — real filesystem
  // -------------------------------------------------------------------------
  group('ensureDirectories (real FS)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('xdg_test_');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('creates all XDG directories', () async {
      final svc = await _svc(
        home: '/home/nobody',
        config: p.join(tmp.path, 'cfg'),
        data: p.join(tmp.path, 'dat'),
        cache: p.join(tmp.path, 'cch'),
        state: p.join(tmp.path, 'st'),
      );
      await svc.ensureDirectories();
      expect(Directory(svc.configHome).existsSync(), isTrue);
      expect(Directory(svc.dataHome).existsSync(), isTrue);
      expect(Directory(svc.cacheHome).existsSync(), isTrue);
      expect(Directory(svc.stateHome).existsSync(), isTrue);
    });

    test('is idempotent — calling twice does not throw', () async {
      final svc = await _svc(
        home: '/home/nobody',
        config: p.join(tmp.path, 'cfg2'),
        data: p.join(tmp.path, 'dat2'),
        cache: p.join(tmp.path, 'cch2'),
        state: p.join(tmp.path, 'st2'),
      );
      await svc.ensureDirectories();
      await expectLater(svc.ensureDirectories(), completes);
    });

    test('creates nested subdirectory via ensureSubdir', () async {
      final svc = await _svc(
        home: '/home/nobody',
        config: p.join(tmp.path, 'cfg3'),
        data: p.join(tmp.path, 'dat3'),
        cache: p.join(tmp.path, 'cch3'),
        state: p.join(tmp.path, 'st3'),
      );
      await svc.ensureDirectories();
      final subDir = await svc.ensureSubdir(XdgDirectory.config, 'profiles');
      expect(subDir.existsSync(), isTrue);
      expect(subDir.path, p.join(svc.configHome, 'profiles'));
    });

    test('ensureSubdir with deeply nested name', () async {
      final svc = await _svc(
        home: '/home/nobody',
        config: p.join(tmp.path, 'cfg4'),
        data: p.join(tmp.path, 'dat4'),
        cache: p.join(tmp.path, 'cch4'),
        state: p.join(tmp.path, 'st4'),
      );
      await svc.ensureDirectories();
      final subDir = await svc.ensureSubdir(XdgDirectory.data, 'thumbnails');
      expect(subDir.existsSync(), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // migrateFromLegacy detection logic
  // -------------------------------------------------------------------------
  group('migrateFromLegacy', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('xdg_migrate_test_');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('always returns an XdgMigrationResult', () async {
      final svc = await _svc(
        home: '/home/nobody',
        config: p.join(tmp.path, 'cfg'),
        data: p.join(tmp.path, 'dat'),
        cache: p.join(tmp.path, 'cch'),
        state: p.join(tmp.path, 'st'),
      );
      // migrateFromLegacy calls getApplicationSupportDirectory which may fail;
      // the service handles errors gracefully.
      final result = await svc.migrateFromLegacy();
      expect(result, isA<XdgMigrationResult>());
    });

    test('XdgMigrationResult toString includes key fields', () {
      const r = XdgMigrationResult(
        needed: true,
        completed: false,
        message: 'test message',
        movedPaths: ['/a'],
        failedPaths: ['/b'],
      );
      final s = r.toString();
      expect(s, contains('needed: true'));
      expect(s, contains('completed: false'));
      expect(s, contains('test message'));
    });

    test('XdgMigrationResult default lists are empty', () {
      const r = XdgMigrationResult(
        needed: false,
        completed: false,
        message: 'nothing',
      );
      expect(r.movedPaths, isEmpty);
      expect(r.failedPaths, isEmpty);
    });

    test('XdgMigrationResult fields are accessible', () {
      const r = XdgMigrationResult(
        needed: true,
        completed: true,
        message: 'done',
        movedPaths: ['/old/a', '/old/b'],
        failedPaths: [],
      );
      expect(r.needed, isTrue);
      expect(r.completed, isTrue);
      expect(r.movedPaths, hasLength(2));
      expect(r.failedPaths, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Singleton lifecycle
  // -------------------------------------------------------------------------
  group('Singleton lifecycle', () {
    test('XdgService.reset() clears the instance', () {
      XdgService.reset();
      expect(() => XdgService.instance, throwsAssertionError);
    });

    test('XdgService.init() is idempotent without force', () async {
      final svc1 = await XdgService.init(
        environmentOverride: {'HOME': '/home/test'},
      );
      final svc2 = await XdgService.init(
        environmentOverride: {'HOME': '/home/other'},
      );
      expect(identical(svc1, svc2), isTrue);
    });

    test('XdgService.init(force: true) replaces the instance', () async {
      final svc1 = await XdgService.init(
        environmentOverride: {'HOME': '/home/test'},
      );
      final svc2 = await XdgService.init(
        environmentOverride: {'HOME': '/home/other'},
        force: true,
      );
      expect(identical(svc1, svc2), isFalse);
    });

    test('initForTest does not pollute the singleton', () async {
      XdgService.reset();
      await XdgService.initForTest({'HOME': '/home/test'});
      // singleton should still be unset
      expect(() => XdgService.instance, throwsAssertionError);
    });
  });

  // -------------------------------------------------------------------------
  // Edge cases
  // -------------------------------------------------------------------------
  group('Edge cases', () {
    test('XDG env var set to empty string falls back to default', () async {
      final svc = await XdgService.initForTest({
        'HOME': '/home/zoe',
        'XDG_CONFIG_HOME': '',
      });
      expect(svc.configHome, '/home/zoe/.config/crispcloud');
    });

    test('configHome always ends with crispcloud', () async {
      final svc = await _svc(home: '/home/zoe', config: '/my/custom');
      expect(p.basename(svc.configHome), 'crispcloud');
    });

    test('dataHome always ends with crispcloud', () async {
      final svc = await _svc(home: '/home/zoe', data: '/my/data');
      expect(p.basename(svc.dataHome), 'crispcloud');
    });

    test('cacheHome always ends with crispcloud', () async {
      final svc = await _svc(home: '/home/zoe', cache: '/my/cache');
      expect(p.basename(svc.cacheHome), 'crispcloud');
    });

    test('stateHome always ends with crispcloud', () async {
      final svc = await _svc(home: '/home/zoe', state: '/my/state');
      expect(p.basename(svc.stateHome), 'crispcloud');
    });
  });
}
