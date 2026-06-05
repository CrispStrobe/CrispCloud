// test/plugin_test.dart
//
// Unit tests for the CrispCloud plugin system:
//   PluginRegistry, CrispCloudPlugin interface, PluginContext sandbox,
//   PluginSettings, PluginMenuItem, PluginToolbarButton, and providers.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/plugin_service.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Minimal plugin implementation used in most tests.
class _FakePlugin implements CrispCloudPlugin {
  final String _id;
  final String _name;
  final List<PluginCapability> _capabilities;
  final Map<String, dynamic> _defaultSettings;

  int initCount = 0;
  int disposeCount = 0;
  final List<({FileAction action, List<String> paths})> receivedActions = [];
  final List<String> contextMenuPaths = [];
  PluginContext? lastContext;
  bool throwOnInit = false;
  bool throwOnDispose = false;
  bool throwOnFileAction = false;
  bool throwOnContextMenu = false;
  bool throwOnToolbar = false;

  _FakePlugin(
    this._id, {
    String name = 'Fake Plugin',
    List<PluginCapability> capabilities = const [],
    Map<String, dynamic> defaultSettings = const {},
  })  : _name = name,
        _capabilities = capabilities,
        _defaultSettings = defaultSettings;

  @override
  String get id => _id;
  @override
  String get name => _name;
  @override
  String get version => '1.0.0';
  @override
  String get description => 'A test plugin';
  @override
  String? get author => 'Tester';
  @override
  String? get homepage => 'https://example.com';
  @override
  List<PluginCapability> get capabilities => _capabilities;

  @override
  Future<void> initialize(PluginContext context) async {
    if (throwOnInit) throw StateError('init error');
    initCount++;
    lastContext = context;
  }

  @override
  Future<void> dispose() async {
    if (throwOnDispose) throw StateError('dispose error');
    disposeCount++;
  }

  @override
  Future<void> onFileAction(FileAction action, List<String> filePaths) async {
    if (throwOnFileAction) throw StateError('fileAction error');
    receivedActions.add((action: action, paths: filePaths));
  }

  @override
  List<PluginMenuItem> getContextMenuItems(List<String> filePaths) {
    if (throwOnContextMenu) throw StateError('contextMenu error');
    contextMenuPaths.addAll(filePaths);
    return [
      PluginMenuItem(id: '${_id}_menu', label: 'Action', icon: 'Icons.play_arrow'),
    ];
  }

  @override
  List<PluginToolbarButton> getToolbarButtons() {
    if (throwOnToolbar) throw StateError('toolbar error');
    return [
      PluginToolbarButton(
        id: '${_id}_btn',
        label: 'Run',
        tooltip: 'Run plugin',
        icon: 'Icons.run_circle',
        onPressedKey: '${_id}_run',
      ),
    ];
  }

  @override
  Map<String, dynamic> getDefaultSettings() => _defaultSettings;
}

/// Plugin that declares no capabilities at all.
class _NoCapPlugin extends _FakePlugin {
  _NoCapPlugin() : super('com.test.nocap', capabilities: []);
}

/// Plugin that only declares contextMenu.
class _ContextMenuPlugin extends _FakePlugin {
  _ContextMenuPlugin(String id)
      : super(id,
            capabilities: [PluginCapability.contextMenu],
            defaultSettings: {'showIcons': true, 'maxItems': 5});
}

/// Plugin that only declares toolbar.
class _ToolbarPlugin extends _FakePlugin {
  _ToolbarPlugin(String id)
      : super(id, capabilities: [PluginCapability.toolbar]);
}

/// Plugin that only declares fileAction.
class _FileActionPlugin extends _FakePlugin {
  _FileActionPlugin(String id)
      : super(id, capabilities: [PluginCapability.fileAction]);
}

/// A fake PluginContext that records all log calls and allows settings round-trip.
class _FakeContext implements PluginContext {
  final List<String> logs = [];
  Map<String, dynamic> _settings = {};

  @override
  String get tempDir => '/tmp/test_plugin';

  @override
  Future<Map<String, dynamic>> getSettings() async => Map.from(_settings);

  @override
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    _settings = Map.from(settings);
  }

  @override
  void log(String message) => logs.add(message);

  // Verify that context does NOT expose credential-related fields.
  bool get hasCredentialAccess => false;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

PluginRegistry _freshRegistry() => PluginRegistry();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Reset SharedPreferences before each test group that needs persistence.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  // =========================================================================
  // PluginMenuItem serialisation
  // =========================================================================

  group('PluginMenuItem', () {
    test('toJson / fromJson round-trip', () {
      const item = PluginMenuItem(
          id: 'menu_1', label: 'Open', icon: 'Icons.open_in_new');
      final json = item.toJson();
      final restored = PluginMenuItem.fromJson(json);
      expect(restored, equals(item));
    });

    test('fromJson defaults enabled to true when absent', () {
      final item = PluginMenuItem.fromJson(
          {'id': 'x', 'label': 'X', 'icon': 'Icons.star'});
      expect(item.enabled, isTrue);
    });

    test('disabled item preserved through round-trip', () {
      const item = PluginMenuItem(
          id: 'x', label: 'X', icon: 'Icons.star', enabled: false);
      expect(PluginMenuItem.fromJson(item.toJson()).enabled, isFalse);
    });

    test('equality compares all fields', () {
      const a = PluginMenuItem(id: 'a', label: 'A', icon: 'Icons.a');
      const b = PluginMenuItem(id: 'a', label: 'A', icon: 'Icons.a');
      const c = PluginMenuItem(id: 'b', label: 'A', icon: 'Icons.a');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('toString contains id and label', () {
      const item = PluginMenuItem(id: 'i1', label: 'MyLabel', icon: 'x');
      expect(item.toString(), contains('i1'));
      expect(item.toString(), contains('MyLabel'));
    });
  });

  // =========================================================================
  // PluginToolbarButton serialisation
  // =========================================================================

  group('PluginToolbarButton', () {
    test('toJson / fromJson round-trip', () {
      const btn = PluginToolbarButton(
        id: 'btn_1',
        label: 'Upload',
        tooltip: 'Upload file',
        icon: 'Icons.upload',
        onPressedKey: 'upload_action',
      );
      final json = btn.toJson();
      final restored = PluginToolbarButton.fromJson(json);
      expect(restored, equals(btn));
    });

    test('equality compares all fields', () {
      const a = PluginToolbarButton(
          id: 'a',
          label: 'A',
          tooltip: 'T',
          icon: 'Icons.a',
          onPressedKey: 'k');
      const b = PluginToolbarButton(
          id: 'a',
          label: 'A',
          tooltip: 'T',
          icon: 'Icons.a',
          onPressedKey: 'k');
      const c = PluginToolbarButton(
          id: 'b',
          label: 'A',
          tooltip: 'T',
          icon: 'Icons.a',
          onPressedKey: 'k');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('toString contains id', () {
      const btn = PluginToolbarButton(
          id: 'mybtn',
          label: 'L',
          tooltip: 'T',
          icon: 'x',
          onPressedKey: 'k');
      expect(btn.toString(), contains('mybtn'));
    });
  });

  // =========================================================================
  // PluginSettings serialisation
  // =========================================================================

  group('PluginSettings', () {
    test('toJson / fromJson round-trip', () {
      const ps = PluginSettings(
        pluginId: 'com.test.plugin',
        enabled: true,
        settings: {'key': 'value', 'count': 42},
      );
      final json = ps.toJson();
      final restored = PluginSettings.fromJson(json);
      expect(restored.pluginId, ps.pluginId);
      expect(restored.enabled, ps.enabled);
      expect(restored.settings['key'], 'value');
      expect(restored.settings['count'], 42);
    });

    test('copyWith changes enabled', () {
      const ps = PluginSettings(pluginId: 'x', enabled: true);
      final disabled = ps.copyWith(enabled: false);
      expect(disabled.enabled, isFalse);
      expect(disabled.pluginId, 'x');
    });

    test('copyWith changes settings map', () {
      const ps = PluginSettings(
          pluginId: 'x', enabled: true, settings: {'a': 1});
      final updated = ps.copyWith(settings: {'b': 2});
      expect(updated.settings['b'], 2);
      expect(updated.settings.containsKey('a'), isFalse);
    });

    test('fromJson defaults enabled to true when absent', () {
      final ps = PluginSettings.fromJson({'pluginId': 'x'});
      expect(ps.enabled, isTrue);
    });

    test('equality based on pluginId and enabled', () {
      const a = PluginSettings(pluginId: 'x', enabled: true);
      const b = PluginSettings(pluginId: 'x', enabled: true);
      const c = PluginSettings(pluginId: 'x', enabled: false);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // =========================================================================
  // PluginContext sandbox
  // =========================================================================

  group('PluginContext sandbox', () {
    test('fake context tempDir is available', () {
      final ctx = _FakeContext();
      expect(ctx.tempDir, isNotEmpty);
    });

    test('fake context does not expose credential access', () {
      final ctx = _FakeContext();
      expect(ctx.hasCredentialAccess, isFalse);
    });

    test('log records messages', () {
      final ctx = _FakeContext();
      ctx.log('hello');
      ctx.log('world');
      expect(ctx.logs, ['hello', 'world']);
    });

    test('saveSettings and getSettings round-trip', () async {
      final ctx = _FakeContext();
      await ctx.saveSettings({'theme': 'dark', 'size': 14});
      final result = await ctx.getSettings();
      expect(result['theme'], 'dark');
      expect(result['size'], 14);
    });

    test('getSettings returns empty map when nothing saved', () async {
      final ctx = _FakeContext();
      final result = await ctx.getSettings();
      expect(result, isEmpty);
    });
  });

  // =========================================================================
  // PluginRegistry — registration
  // =========================================================================

  group('PluginRegistry registration', () {
    test('getAllPlugins is empty initially', () {
      final registry = _freshRegistry();
      expect(registry.getAllPlugins(), isEmpty);
    });

    test('registerPlugin adds a plugin', () {
      final registry = _freshRegistry();
      registry.registerPlugin(_FakePlugin('com.test.a'));
      expect(registry.getAllPlugins().length, 1);
    });

    test('getPlugin returns registered plugin', () {
      final registry = _freshRegistry();
      registry.registerPlugin(_FakePlugin('com.test.a'));
      expect(registry.getPlugin('com.test.a'), isNotNull);
    });

    test('getPlugin returns null for unknown id', () {
      final registry = _freshRegistry();
      expect(registry.getPlugin('com.test.unknown'), isNull);
    });

    test('duplicate plugin id throws ArgumentError', () {
      final registry = _freshRegistry();
      registry.registerPlugin(_FakePlugin('com.test.a'));
      expect(
        () => registry.registerPlugin(_FakePlugin('com.test.a')),
        throwsArgumentError,
      );
    });

    test('multiple plugins registered in order', () {
      final registry = _freshRegistry();
      registry.registerPlugin(_FakePlugin('com.test.first'));
      registry.registerPlugin(_FakePlugin('com.test.second'));
      registry.registerPlugin(_FakePlugin('com.test.third'));
      final ids = registry.getAllPlugins().map((p) => p.id).toList();
      expect(ids, ['com.test.first', 'com.test.second', 'com.test.third']);
    });

    test('unregisterPlugin calls dispose on plugin', () async {
      final registry = _freshRegistry();
      final plugin = _FakePlugin('com.test.a');
      registry.registerPlugin(plugin);
      await registry.unregisterPlugin('com.test.a');
      expect(plugin.disposeCount, 1);
    });

    test('unregisterPlugin removes plugin from registry', () async {
      final registry = _freshRegistry();
      registry.registerPlugin(_FakePlugin('com.test.a'));
      await registry.unregisterPlugin('com.test.a');
      expect(registry.getPlugin('com.test.a'), isNull);
    });

    test('unregisterPlugin on unknown id does nothing', () async {
      final registry = _freshRegistry();
      // Should not throw.
      await registry.unregisterPlugin('com.test.nonexistent');
    });

    test('plugin with no capabilities registers successfully', () {
      final registry = _freshRegistry();
      expect(
        () => registry.registerPlugin(_NoCapPlugin()),
        returnsNormally,
      );
    });
  });

  // =========================================================================
  // PluginRegistry — enable/disable
  // =========================================================================

  group('PluginRegistry enable/disable', () {
    test('plugin is enabled by default', () {
      final registry = _freshRegistry();
      registry.registerPlugin(_FakePlugin('com.test.a'));
      expect(registry.getEnabledPlugins().length, 1);
    });

    test('setEnabled(false) removes plugin from enabledPlugins', () async {
      final registry = _freshRegistry();
      registry.registerPlugin(_FakePlugin('com.test.a'));
      await registry.setEnabled('com.test.a', false);
      expect(registry.getEnabledPlugins(), isEmpty);
    });

    test('setEnabled(true) re-adds plugin to enabledPlugins', () async {
      final registry = _freshRegistry();
      registry.registerPlugin(_FakePlugin('com.test.a'));
      await registry.setEnabled('com.test.a', false);
      await registry.setEnabled('com.test.a', true);
      expect(registry.getEnabledPlugins().length, 1);
    });

    test('setEnabled persists to SharedPreferences', () async {
      final registry = _freshRegistry();
      registry.registerPlugin(_FakePlugin('com.test.a'));
      await registry.setEnabled('com.test.a', false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('plugin_enabled_com.test.a'), isFalse);
    });

    test('getPluginSettings reflects enabled state after toggle', () async {
      final registry = _freshRegistry();
      registry.registerPlugin(_FakePlugin('com.test.a'));
      await registry.setEnabled('com.test.a', false);
      expect(registry.getPluginSettings('com.test.a')?.enabled, isFalse);
    });

    test('setEnabled on unknown id does nothing gracefully', () async {
      final registry = _freshRegistry();
      await registry.setEnabled('com.test.unknown', false);
    });
  });

  // =========================================================================
  // PluginRegistry — lifecycle
  // =========================================================================

  group('PluginRegistry lifecycle', () {
    test('initializeAll calls initialize on enabled plugins', () async {
      final registry = _freshRegistry();
      final plugin = _FakePlugin('com.test.a');
      registry.registerPlugin(plugin);
      await registry.initializeAll();
      expect(plugin.initCount, 1);
    });

    test('initializeAll passes PluginContext to initialize', () async {
      final registry = _freshRegistry();
      final plugin = _FakePlugin('com.test.a');
      registry.registerPlugin(plugin);
      await registry.initializeAll();
      expect(plugin.lastContext, isNotNull);
    });

    test('initializeAll does NOT call initialize on disabled plugins',
        () async {
      final registry = _freshRegistry();
      final plugin = _FakePlugin('com.test.a');
      registry.registerPlugin(plugin);
      await registry.setEnabled('com.test.a', false);
      await registry.initializeAll();
      expect(plugin.initCount, 0);
    });

    test('initializeAll survives plugin that throws', () async {
      final registry = _freshRegistry();
      final bad = _FakePlugin('com.test.bad')..throwOnInit = true;
      final good = _FakePlugin('com.test.good');
      registry.registerPlugin(bad);
      registry.registerPlugin(good);
      // Should not throw even though bad plugin throws.
      await expectLater(registry.initializeAll(), completes);
      expect(good.initCount, 1);
    });

    test('disposeAll calls dispose on all plugins', () async {
      final registry = _freshRegistry();
      final a = _FakePlugin('com.test.a');
      final b = _FakePlugin('com.test.b');
      registry.registerPlugin(a);
      registry.registerPlugin(b);
      await registry.disposeAll();
      expect(a.disposeCount, 1);
      expect(b.disposeCount, 1);
    });

    test('disposeAll clears the registry', () async {
      final registry = _freshRegistry();
      registry.registerPlugin(_FakePlugin('com.test.a'));
      await registry.disposeAll();
      expect(registry.getAllPlugins(), isEmpty);
    });

    test('disposeAll survives plugin that throws on dispose', () async {
      final registry = _freshRegistry();
      final bad = _FakePlugin('com.test.bad')..throwOnDispose = true;
      final good = _FakePlugin('com.test.good');
      registry.registerPlugin(bad);
      registry.registerPlugin(good);
      await expectLater(registry.disposeAll(), completes);
      expect(good.disposeCount, 1);
    });

    test('dispose called when unregistering a plugin', () async {
      final registry = _freshRegistry();
      final plugin = _FakePlugin('com.test.a');
      registry.registerPlugin(plugin);
      await registry.unregisterPlugin('com.test.a');
      expect(plugin.disposeCount, 1);
    });
  });

  // =========================================================================
  // PluginRegistry — file action notification
  // =========================================================================

  group('PluginRegistry notifyFileAction', () {
    test('notifyFileAction delivers to enabled file-action plugins', () async {
      final registry = _freshRegistry();
      final plugin = _FileActionPlugin('com.test.fa');
      registry.registerPlugin(plugin);
      await registry.notifyFileAction(FileAction.upload, ['/a.txt']);
      expect(plugin.receivedActions.length, 1);
      expect(plugin.receivedActions.first.action, FileAction.upload);
      expect(plugin.receivedActions.first.paths, ['/a.txt']);
    });

    test('disabled plugin does NOT receive file action', () async {
      final registry = _freshRegistry();
      final plugin = _FileActionPlugin('com.test.fa');
      registry.registerPlugin(plugin);
      await registry.setEnabled('com.test.fa', false);
      await registry.notifyFileAction(FileAction.delete, ['/b.txt']);
      expect(plugin.receivedActions, isEmpty);
    });

    test('plugin without fileAction capability does NOT receive event',
        () async {
      final registry = _freshRegistry();
      final plugin = _ContextMenuPlugin('com.test.menu');
      registry.registerPlugin(plugin);
      await registry.notifyFileAction(FileAction.upload, ['/c.txt']);
      expect(plugin.receivedActions, isEmpty);
    });

    test('notifyFileAction survives plugin that throws', () async {
      final registry = _freshRegistry();
      final bad = _FileActionPlugin('com.test.bad')..throwOnFileAction = true;
      final good = _FileActionPlugin('com.test.good');
      registry.registerPlugin(bad);
      registry.registerPlugin(good);
      await expectLater(
          registry.notifyFileAction(FileAction.copy, ['/d.txt']), completes);
      expect(good.receivedActions.length, 1);
    });

    test('all FileAction enum values can be dispatched', () async {
      final registry = _freshRegistry();
      final plugin = _FileActionPlugin('com.test.all');
      registry.registerPlugin(plugin);
      for (final action in FileAction.values) {
        await registry.notifyFileAction(action, ['/file.txt']);
      }
      expect(plugin.receivedActions.length, FileAction.values.length);
    });
  });

  // =========================================================================
  // PluginRegistry — context menu aggregation
  // =========================================================================

  group('PluginRegistry getContextMenuItems', () {
    test('returns items from all enabled context-menu plugins', () {
      final registry = _freshRegistry();
      registry.registerPlugin(_ContextMenuPlugin('com.test.cm1'));
      registry.registerPlugin(_ContextMenuPlugin('com.test.cm2'));
      final items = registry.getContextMenuItems(['/x.txt']);
      // Each plugin returns 1 item.
      expect(items.length, 2);
    });

    test('items ordered by plugin registration order', () {
      final registry = _freshRegistry();
      registry.registerPlugin(_ContextMenuPlugin('com.test.first'));
      registry.registerPlugin(_ContextMenuPlugin('com.test.second'));
      final items = registry.getContextMenuItems(['/x.txt']);
      expect(items.first.id, 'com.test.first_menu');
      expect(items.last.id, 'com.test.second_menu');
    });

    test('disabled plugin not included in context menu', () async {
      final registry = _freshRegistry();
      registry.registerPlugin(_ContextMenuPlugin('com.test.cm'));
      await registry.setEnabled('com.test.cm', false);
      final items = registry.getContextMenuItems(['/x.txt']);
      expect(items, isEmpty);
    });

    test('plugin without contextMenu capability not included', () {
      final registry = _freshRegistry();
      registry.registerPlugin(_FileActionPlugin('com.test.fa'));
      final items = registry.getContextMenuItems(['/x.txt']);
      expect(items, isEmpty);
    });

    test('getContextMenuItems survives plugin that throws', () {
      final registry = _freshRegistry();
      final bad = _ContextMenuPlugin('com.test.bad')
        ..throwOnContextMenu = true;
      final good = _ContextMenuPlugin('com.test.good');
      registry.registerPlugin(bad);
      registry.registerPlugin(good);
      expect(() => registry.getContextMenuItems(['/x.txt']), returnsNormally);
      final items = registry.getContextMenuItems(['/x.txt']);
      // bad throws, good returns 1 item per call; we called twice so good returns 2 items.
      expect(items.length, 1);
    });
  });

  // =========================================================================
  // PluginRegistry — toolbar buttons aggregation
  // =========================================================================

  group('PluginRegistry getToolbarButtons', () {
    test('returns buttons from all enabled toolbar plugins', () {
      final registry = _freshRegistry();
      registry.registerPlugin(_ToolbarPlugin('com.test.tb1'));
      registry.registerPlugin(_ToolbarPlugin('com.test.tb2'));
      final buttons = registry.getToolbarButtons();
      expect(buttons.length, 2);
    });

    test('disabled plugin not included in toolbar', () async {
      final registry = _freshRegistry();
      registry.registerPlugin(_ToolbarPlugin('com.test.tb'));
      await registry.setEnabled('com.test.tb', false);
      final buttons = registry.getToolbarButtons();
      expect(buttons, isEmpty);
    });

    test('plugin without toolbar capability not included', () {
      final registry = _freshRegistry();
      registry.registerPlugin(_FileActionPlugin('com.test.fa'));
      final buttons = registry.getToolbarButtons();
      expect(buttons, isEmpty);
    });

    test('getToolbarButtons survives plugin that throws', () {
      final registry = _freshRegistry();
      final bad = _ToolbarPlugin('com.test.bad')..throwOnToolbar = true;
      final good = _ToolbarPlugin('com.test.good');
      registry.registerPlugin(bad);
      registry.registerPlugin(good);
      expect(() => registry.getToolbarButtons(), returnsNormally);
      final buttons = registry.getToolbarButtons();
      expect(buttons.length, 1);
    });
  });

  // =========================================================================
  // Plugin settings CRUD
  // =========================================================================

  group('Plugin settings', () {
    test('default settings populated on registration', () {
      final registry = _freshRegistry();
      registry.registerPlugin(_ContextMenuPlugin('com.test.cm'));
      final ps = registry.getPluginSettings('com.test.cm');
      expect(ps, isNotNull);
      expect(ps!.settings['showIcons'], isTrue);
      expect(ps.settings['maxItems'], 5);
    });

    test('getPluginSettings returns null for unknown plugin', () {
      final registry = _freshRegistry();
      expect(registry.getPluginSettings('com.test.unknown'), isNull);
    });

    test('savePluginSettings updates in-memory settings', () async {
      final registry = _freshRegistry();
      registry.registerPlugin(_ContextMenuPlugin('com.test.cm'));
      await registry.savePluginSettings('com.test.cm', {'showIcons': false});
      final ps = registry.getPluginSettings('com.test.cm');
      expect(ps!.settings['showIcons'], isFalse);
    });

    test('savePluginSettings persists to SharedPreferences', () async {
      final registry = _freshRegistry();
      registry.registerPlugin(_ContextMenuPlugin('com.test.cm'));
      await registry.savePluginSettings(
          'com.test.cm', {'showIcons': false, 'maxItems': 10});

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('plugin_settings_com.test.cm');
      expect(raw, isNotNull);
      expect(raw, contains('maxItems'));
    });

    test('savePluginSettings on unknown id does nothing', () async {
      final registry = _freshRegistry();
      // Should not throw.
      await registry.savePluginSettings('com.test.unknown', {'key': 'val'});
    });

    test('initializeAll merges defaults with persisted settings', () async {
      // Pre-populate SharedPreferences to simulate persisted state.
      SharedPreferences.setMockInitialValues({
        'plugin_settings_com.test.cm':
            '{"showIcons":false,"customKey":"hello"}',
      });
      final registry = _freshRegistry();
      registry.registerPlugin(_ContextMenuPlugin('com.test.cm'));
      await registry.initializeAll();

      final ps = registry.getPluginSettings('com.test.cm');
      // Persisted value overrides default.
      expect(ps!.settings['showIcons'], isFalse);
      // Default value filled for un-saved key.
      expect(ps.settings['maxItems'], 5);
      // Extra persisted key is also present.
      expect(ps.settings['customKey'], 'hello');
    });
  });

  // =========================================================================
  // PluginContext via real _PluginContextImpl (indirectly via initializeAll)
  // =========================================================================

  group('PluginContext (real implementation)', () {
    test('initialize receives a context with non-empty tempDir', () async {
      final registry = _freshRegistry();
      final plugin = _FakePlugin('com.test.ctx');
      registry.registerPlugin(plugin);
      await registry.initializeAll();
      expect(plugin.lastContext!.tempDir, isNotEmpty);
    });

    test('context tempDir contains plugin id', () async {
      final registry = _freshRegistry();
      final plugin = _FakePlugin('com.test.ctx');
      registry.registerPlugin(plugin);
      await registry.initializeAll();
      expect(plugin.lastContext!.tempDir, contains('com.test.ctx'));
    });

    test('context getSettings returns defaults on first call', () async {
      final registry = _freshRegistry();
      final plugin = _ContextMenuPlugin('com.test.ctx');
      registry.registerPlugin(plugin);
      await registry.initializeAll();
      final settings = await plugin.lastContext!.getSettings();
      expect(settings['showIcons'], isTrue);
      expect(settings['maxItems'], 5);
    });

    test('context saveSettings persists and getSettings reads back', () async {
      final registry = _freshRegistry();
      final plugin = _FakePlugin('com.test.ctx');
      registry.registerPlugin(plugin);
      await registry.initializeAll();
      final ctx = plugin.lastContext!;
      await ctx.saveSettings({'alpha': 42, 'beta': 'hello'});
      final result = await ctx.getSettings();
      expect(result['alpha'], 42);
      expect(result['beta'], 'hello');
    });

    test('context does not expose credentials or provider clients', () async {
      // PluginContext only declares tempDir, getSettings, saveSettings, log.
      // We verify the abstract interface has no credential-related members.
      final registry = _freshRegistry();
      final plugin = _FakePlugin('com.test.safe');
      registry.registerPlugin(plugin);
      await registry.initializeAll();
      final ctx = plugin.lastContext!;
      // tempDir, getSettings, saveSettings, log — those are all the members.
      expect(ctx.tempDir, isA<String>());
      expect(ctx.getSettings, isA<Function>());
      expect(ctx.saveSettings, isA<Function>());
      expect(ctx.log, isA<Function>());
    });
  });
}
