// lib/services/tray_service.dart
//
// System tray integration for desktop platforms.
// Shows a tray icon with sync status, quick actions, and notifications.
// Only active on macOS, Windows, and Linux.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';

import 'log_service.dart';
import 'sync_engine.dart';

/// Manages the system tray icon and menu for background sync.
class TrayService {
  static final _log = Log('TrayService');
  SystemTray? _tray;
  AppWindow? _appWindow;
  bool _initialized = false;

  /// Whether the tray service is available on this platform.
  static bool get isSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Initialize the system tray icon and menu.
  Future<void> initialize({
    required VoidCallback onSyncAll,
    required VoidCallback onShowApp,
    required VoidCallback onQuit,
  }) async {
    if (!isSupported) return;

    _tray = SystemTray();
    _appWindow = AppWindow();

    await _tray!.initSystemTray(
      title: 'CrispCloud',
      iconPath: _iconPath,
      toolTip: 'CrispCloud — Cloud File Manager',
    );

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(label: 'Show CrispCloud', onClicked: (_) => onShowApp()),
      MenuSeparator(),
      MenuItemLabel(label: 'Sync All', onClicked: (_) => onSyncAll()),
      MenuSeparator(),
      MenuItemLabel(label: 'Quit', onClicked: (_) => onQuit()),
    ]);

    await _tray!.setContextMenu(menu);

    // Left-click shows the app
    _tray!.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        onShowApp();
      } else if (eventName == kSystemTrayEventRightClick) {
        _tray!.popUpContextMenu();
      }
    });

    _initialized = true;
    _log.info('Initialized');
  }

  /// Update the tray tooltip to show sync status.
  Future<void> updateStatus({
    required bool isSyncing,
    String? currentPairName,
    SyncResult? lastResult,
    int pairCount = 0,
  }) async {
    if (!_initialized || _tray == null) return;

    String tooltip;
    if (isSyncing) {
      tooltip = 'CrispCloud — Syncing${currentPairName != null ? ' $currentPairName' : ''}...';
    } else if (lastResult != null && lastResult.hasChanges) {
      tooltip = 'CrispCloud — Last sync: ${lastResult.uploaded} up, ${lastResult.downloaded} down';
    } else {
      tooltip = 'CrispCloud — $pairCount sync pair${pairCount != 1 ? 's' : ''}';
    }

    await _tray!.setToolTip(tooltip);
  }

  /// Show the app window (bring to front).
  void showApp() {
    _appWindow?.show();
  }

  /// Destroy the tray icon.
  Future<void> dispose() async {
    if (_tray != null) {
      await _tray!.destroy();
      _tray = null;
      _initialized = false;
    }
  }

  String get _iconPath {
    if (Platform.isMacOS) return 'assets/images/app_icon.png';
    if (Platform.isWindows) return 'assets/images/app_icon.png';
    return 'assets/images/app_icon.png';
  }
}
