// test/plugin_context_menu_wire_test.dart
//
// Tests for plugin context menu wiring (Phase 1.3).

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/plugin_service.dart';

/// Minimal test plugin that provides context menu items.
class _TestPlugin extends CrispCloudPlugin {
  final List<PluginMenuItem> _items;

  _TestPlugin(this._items);

  @override String get id => 'com.test.ctxmenu';
  @override String get name => 'Test Context Menu Plugin';
  @override String get version => '1.0.0';
  @override String get description => 'Test plugin';
  @override String? get author => null;
  @override String? get homepage => null;
  @override List<PluginCapability> get capabilities => [PluginCapability.contextMenu];

  @override Future<void> initialize(PluginContext context) async {}
  @override Future<void> dispose() async {}
  @override Future<void> onFileAction(FileAction action, List<String> filePaths) async {}
  @override List<PluginMenuItem> getContextMenuItems(List<String> filePaths) => _items;
  @override List<PluginToolbarButton> getToolbarButtons() => [];
  @override Map<String, dynamic> getDefaultSettings() => {};
}

void main() {
  group('PluginMenuItem.onSelected', () {
    test('PluginMenuItem supports onSelected callback', () {
      var callbackCalled = false;
      List<String>? receivedPaths;

      final item = PluginMenuItem(
        id: 'test-item',
        label: 'Test Action',
        icon: 'Icons.star',
        onSelected: (paths) {
          callbackCalled = true;
          receivedPaths = paths;
        },
      );

      item.onSelected?.call(['/tmp/test.txt']);
      expect(callbackCalled, isTrue);
      expect(receivedPaths, ['/tmp/test.txt']);
    });

    test('PluginMenuItem onSelected is optional (backward compat)', () {
      const item = PluginMenuItem(
        id: 'test',
        label: 'Test',
        icon: 'Icons.star',
      );
      expect(item.onSelected, isNull);
    });
  });

  group('PluginRegistry.getContextMenuItems', () {
    test('collects items from enabled plugins', () {
      final registry = PluginRegistry();
      registry.registerPlugin(_TestPlugin([
        const PluginMenuItem(id: 'a', label: 'Action A', icon: 'Icons.star'),
        const PluginMenuItem(id: 'b', label: 'Action B', icon: 'Icons.edit'),
      ]));

      final items = registry.getContextMenuItems(['/tmp/file.txt']);
      expect(items.length, 2);
      expect(items[0].label, 'Action A');
      expect(items[1].label, 'Action B');
    });

    test('returns empty list when no plugins registered', () {
      final registry = PluginRegistry();
      final items = registry.getContextMenuItems(['/tmp/test.txt']);
      expect(items, isEmpty);
    });

    test('skips plugins without contextMenu capability', () {
      final registry = PluginRegistry();
      // Register a plugin that declares no capabilities
      registry.registerPlugin(_NoCapPlugin());
      final items = registry.getContextMenuItems(['/tmp/test.txt']);
      expect(items, isEmpty);
    });
  });
}

class _NoCapPlugin extends CrispCloudPlugin {
  @override String get id => 'com.test.nocap';
  @override String get name => 'No Cap Plugin';
  @override String get version => '1.0.0';
  @override String get description => 'No capabilities';
  @override String? get author => null;
  @override String? get homepage => null;
  @override List<PluginCapability> get capabilities => []; // No capabilities

  @override Future<void> initialize(PluginContext context) async {}
  @override Future<void> dispose() async {}
  @override Future<void> onFileAction(FileAction action, List<String> filePaths) async {}
  @override List<PluginMenuItem> getContextMenuItems(List<String> filePaths) => [
    const PluginMenuItem(id: 'x', label: 'Should Not Appear', icon: 'Icons.star'),
  ];
  @override List<PluginToolbarButton> getToolbarButtons() => [];
  @override Map<String, dynamic> getDefaultSettings() => {};
}
