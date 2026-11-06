import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/providers/plugin_provider.dart';
import 'package:crisp_cloud/services/plugin_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Plugin extends CrispCloudPlugin {
  _Plugin(this.id);
  @override
  final String id;
  @override
  String get name => id;
  @override
  String get version => '1.0.0';
  @override
  String get description => 'Lifecycle test';
  @override
  String? get author => null;
  @override
  String? get homepage => null;
  @override
  List<PluginCapability> get capabilities => [
    PluginCapability.toolbar,
    PluginCapability.contextMenu,
    PluginCapability.fileAction,
  ];
  int initializes = 0, disposes = 0, actions = 0;
  int menuClicks = 0, toolbarClicks = 0;
  bool fail = false;
  bool saveOnDispose = false;
  Object? disposeWriteError;
  Completer<void>? waitForInitialize;
  PluginContext? context;
  Map<String, dynamic>? settingsAtInitialize;
  @override
  Future<void> initialize(PluginContext context) async {
    initializes++;
    this.context = context;
    settingsAtInitialize = await context.getSettings();
    if (waitForInitialize != null) await waitForInitialize!.future;
    if (fail) throw StateError('Initialization failed');
  }

  @override
  Future<void> dispose() async {
    disposes++;
    if (saveOnDispose) {
      try {
        await context!.saveSettings({'value': -1});
      } catch (error) {
        disposeWriteError = error;
      }
    }
  }

  @override
  Future<void> onFileAction(FileAction action, List<String> paths) async {
    actions++;
  }

  @override
  List<PluginMenuItem> getContextMenuItems(List<String> paths) => [
    PluginMenuItem(
      id: 'menu',
      label: 'Menu',
      icon: 'extension',
      onSelected: (_) => menuClicks++,
    ),
  ];
  @override
  List<PluginToolbarButton> getToolbarButtons() => [
    PluginToolbarButton(
      id: 'button',
      label: 'Button',
      tooltip: 'Button',
      icon: 'extension',
      onPressedKey: 'test',
      onPressed: (_) => toolbarClicks++,
    ),
  ];
  @override
  Map<String, dynamic> getDefaultSettings() => {
    'value': 1,
    'defaultOnly': true,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PluginRegistry registry;
  var created = 0, released = 0;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    created = 0;
    released = 0;
    registry = PluginRegistry(
      workspaceFactory: (id) async =>
          PluginWorkspace('memory:/$id/${created++}', () async {
            released++;
          }),
    );
  });
  tearDown(() => registry.disposeAll());

  test(
    'persisted disabled plugins never initialize or receive early hooks',
    () async {
      SharedPreferences.setMockInitialValues({
        'plugin_enabled_com.example.disabled': false,
      });
      final plugin = _Plugin('com.example.disabled');
      registry.registerPlugin(plugin);
      expect(registry.getContextMenuItems(['/file']), isEmpty);
      expect(registry.getToolbarButtons(), isEmpty);
      await registry.notifyFileAction(FileAction.copy, ['/file']);
      expect(plugin.initializes, 0);
      expect(plugin.actions, 0);
      expect(created, 0);
      expect(registry.statusOf(plugin.id), PluginRuntimeStatus.disabled);
    },
  );

  test('concurrent repeated initialization runs once and exposes hooks only after completion', () async {
    final plugin = _Plugin('com.example.once')
      ..waitForInitialize = Completer<void>();
    registry.registerPlugin(plugin);
    final first = registry.initializeAll();
    final second = registry.initializeAll();
    await Future<void>.delayed(Duration.zero);
    expect(plugin.initializes, 1);
    expect(registry.getEnabledPlugins(), isEmpty);
    plugin.waitForInitialize!.complete();
    await Future.wait([first, second]);
    await registry.initializeAll();
    expect(plugin.initializes, 1);
    expect(registry.getToolbarButtons(), hasLength(1));
  });

  test('disable disposes and releases resources, re-enable creates a fresh context', () async {
    final plugin = _Plugin('com.example.toggle');
    registry.registerPlugin(plugin);
    await registry.initializeAll();
    final previous = plugin.context!;
    await registry.setEnabled(plugin.id, false);
    expect(plugin.disposes, 1);
    expect(released, 1);
    expect(registry.getEnabledPlugins(), isEmpty);
    await expectLater(previous.saveSettings({'stale': true}), throwsStateError);
    await registry.setEnabled(plugin.id, true);
    expect(plugin.initializes, 2);
    expect(identical(previous, plugin.context), isFalse);
    expect(created, 2);
  });

  test(
    'captured plugin callbacks expire across disable and settings restart',
    () async {
      final plugin = _Plugin('com.example.actions');
      registry.registerPlugin(plugin);
      await registry.initializeAll();
      final menu = registry.getContextMenuItems(['/file']).single;
      final toolbar = registry.getToolbarButtons().single;
      menu.onSelected!(['/file']);
      toolbar.onPressed!(['/file']);
      expect(plugin.menuClicks, 1);
      expect(plugin.toolbarClicks, 1);
      await registry.setEnabled(plugin.id, false);
      expect(() => menu.onSelected!(['/file']), throwsStateError);
      expect(() => toolbar.onPressed!(['/file']), throwsStateError);
      await registry.setEnabled(plugin.id, true);
      expect(() => menu.onSelected!(['/file']), throwsStateError);
      final current = registry.getToolbarButtons().single;
      await registry.savePluginSettings(plugin.id, {'value': 2});
      expect(() => current.onPressed!(['/file']), throwsStateError);
      registry.getToolbarButtons().single.onPressed!(['/file']);
      expect(plugin.toolbarClicks, 2);
    },
  );

  test(
    'a disposed instance cannot overwrite newly saved user settings',
    () async {
      final plugin = _Plugin('com.example.settings-lease')
        ..saveOnDispose = true;
      registry.registerPlugin(plugin);
      await registry.initializeAll();
      await registry.savePluginSettings(plugin.id, {'value': 2});
      expect(plugin.disposeWriteError, isA<StateError>());
      expect(plugin.settingsAtInitialize!['value'], 2);
      expect(registry.getPluginSettings(plugin.id)!.settings['value'], 2);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'plugin_settings_${plugin.id}',
        ),
        contains('"value":2'),
      );
    },
  );

  test('failed initialization releases partial resources and stays excluded until explicit retry', () async {
    final plugin = _Plugin('com.example.failed')..fail = true;
    registry.registerPlugin(plugin);
    await registry.initializeAll();
    await registry.initializeAll();
    await registry.notifyFileAction(FileAction.rename, ['/file']);
    expect(plugin.initializes, 1);
    expect(plugin.disposes, 1);
    expect(released, 1);
    expect(registry.getContextMenuItems(['/file']), isEmpty);
    expect(registry.errors[plugin.id], contains('Initialization failed'));
    plugin.fail = false;
    await registry.retryPlugin(plugin.id);
    expect(plugin.initializes, 2);
    expect(registry.isReady(plugin.id), isTrue);
    expect(registry.errors, isEmpty);
  });

  test('plugins registered after startup load their own persisted disabled setting', () async {
    await registry.initializeAll();
    SharedPreferences.setMockInitialValues({
      'plugin_enabled_com.example.late': false,
    });
    final plugin = _Plugin('com.example.late');
    registry.registerPlugin(plugin);
    await registry.initializeAll();
    expect(plugin.initializes, 0);
    expect(registry.getPluginSettings(plugin.id)!.enabled, isFalse);
  });

  test(
    'settings update persists then disposes and reinitializes with new values',
    () async {
      final plugin = _Plugin('com.example.settings');
      registry.registerPlugin(plugin);
      await registry.initializeAll();
      final previous = plugin.context!;
      await registry.savePluginSettings(plugin.id, {'value': 7});
      expect(plugin.initializes, 2);
      expect(plugin.disposes, 1);
      expect(plugin.settingsAtInitialize, {'value': 7, 'defaultOnly': true});
      await expectLater(previous.getSettings(), throwsStateError);
      final exposed = registry.getPluginSettings(plugin.id)!.settings;
      exposed['value'] = 999;
      expect(registry.getPluginSettings(plugin.id)!.settings['value'], 7);
    },
  );

  test(
    'disabled settings can be edited without initializing a plugin',
    () async {
      final plugin = _Plugin('com.example.disabled');
      registry.registerPlugin(plugin, enabledByDefault: false);
      await registry.savePluginSettings(plugin.id, {'value': 4});
      expect(plugin.initializes, 0);
      await registry.setEnabled(plugin.id, true);
      expect(plugin.settingsAtInitialize!['value'], 4);
    },
  );

  test(
    'corrupt saved settings block hooks and can be explicitly replaced',
    () async {
      SharedPreferences.setMockInitialValues({
        'plugin_settings_com.example.broken': 'not JSON',
      });
      final plugin = _Plugin('com.example.broken');
      registry.registerPlugin(plugin);
      await registry.initializeAll();
      expect(plugin.initializes, 0);
      expect(registry.errors, contains(plugin.id));
      await expectLater(registry.setEnabled(plugin.id, true), throwsStateError);
      await registry.savePluginSettings(plugin.id, {'value': 5});
      expect(plugin.initializes, 1);
      expect(plugin.settingsAtInitialize!['value'], 5);
    },
  );

  test('invalid IDs are rejected before allocating resources or accessing settings', () async {
    for (final id in [
      '../escape',
      'com/escape',
      r'com\escape',
      'a..b',
      '.hidden',
    ]) {
      expect(() => registry.registerPlugin(_Plugin(id)), throwsFormatException);
    }
    expect(registry.getAllPlugins(), isEmpty);
    expect(created, 0);
    await expectLater(
      createPluginWorkspace('../escape'),
      throwsFormatException,
    );
  });

  test('native temporary directories are real, unique and cleaned within their supplied root', () async {
    final directory = await Directory.current.createTemp(
      'plugin-workspace-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final first = await createPluginWorkspace(
      'com.example.native',
      baseDirectory: directory.path,
    );
    final second = await createPluginWorkspace(
      'com.example.native',
      baseDirectory: directory.path,
    );
    expect(first.path, isNot(second.path));
    expect(first.path, startsWith(directory.absolute.path));
    await File('${first.path}/owned.txt').writeAsString('owned');
    await first.close();
    await first.close();
    expect(await Directory(first.path).exists(), isFalse);
    expect(await Directory(second.path).exists(), isTrue);
    await second.close();
  });

  test(
    'provider containers have separate plugin registries and lifecycles',
    () async {
      final first = ProviderContainer();
      final second = ProviderContainer();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final left = first.read(pluginRegistryProvider);
      final right = second.read(pluginRegistryProvider);
      left.registerPlugin(_Plugin('com.example.first'));
      expect(identical(left.registry, right.registry), isFalse);
      expect(right.getAllPlugins(), isEmpty);
      await left.disposeAll();
      expect(right.getAllPlugins(), isEmpty);
    },
  );
}
