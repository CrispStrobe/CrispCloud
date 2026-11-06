// lib/services/tray_service.dart
//
// System tray integration for desktop platforms.
// Shows a tray icon with sync status, quick actions, and notifications.
// Only active on macOS, Windows, and Linux.

import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:system_tray/system_tray.dart';

import '../l10n/tray_strings.dart';
import 'log_service.dart';
import 'sync_engine.dart';

/// Manages the system tray icon and menu for background sync.
class TrayService with WidgetsBindingObserver {
  static const _log = Log('TrayService');
  SystemTray? _tray;
  AppWindow? _appWindow;
  bool _initialized = false;
  Locale? _localeOverride;
  VoidCallback? _onSyncAll;
  VoidCallback? _onShowApp;
  VoidCallback? _onQuit;
  bool _syncing = false;
  String? _pairName;
  SyncResult? _lastResult;
  int _pairCount = 0;
  Future<void> _refreshQueue = Future.value();

  static const _supportedLocales = [
    Locale('en'), Locale('de'), Locale('fr'), Locale('es'), Locale('pt'),
    Locale('zh'), Locale('ja'), Locale('ko'), Locale('ar'),
  ];

  @visibleForTesting
  static Locale resolveLocale(Locale? override, List<Locale> systemLocales) =>
      basicLocaleListResolution(override == null ? systemLocales : [override], _supportedLocales);

  TrayStrings get _strings => TrayStrings(resolveLocale(
      _localeOverride, WidgetsBinding.instance.platformDispatcher.locales));

  /// Whether the tray service is available on this platform.
  static bool get isSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Initialize the system tray icon and menu.
  Future<void> initialize({
    required VoidCallback onSyncAll,
    required VoidCallback onShowApp,
    required VoidCallback onQuit,
    Locale? locale,
  }) async {
    if (!isSupported) return;

    _localeOverride = locale;
    _onSyncAll = onSyncAll;
    _onShowApp = onShowApp;
    _onQuit = onQuit;
    _tray = SystemTray();
    _appWindow = AppWindow();

    await _tray!.initSystemTray(
      title: 'CrispCloud',
      iconPath: _iconPath,
      toolTip: 'CrispCloud — ${_strings.text('manager')}',
    );

    await _rebuildMenu();

    // Left-click shows the app
    _tray!.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        onShowApp();
      } else if (eventName == kSystemTrayEventRightClick) {
        _tray!.popUpContextMenu();
      }
    });

    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    await _queueRefresh(menu: true);
    _log.info('Initialized');
  }

  /// Update the tray tooltip to show sync status.
  Future<void> updateStatus({
    required bool isSyncing,
    String? currentPairName,
    SyncResult? lastResult,
    int pairCount = 0,
  }) async {
    _syncing = isSyncing;
    _pairName = currentPairName;
    _lastResult = lastResult;
    _pairCount = pairCount;
    if (!_initialized || _tray == null) return;
    await _queueRefresh(menu: false);
  }

  /// Changes the app locale; null follows the operating system locale.
  Future<void> setLocale(Locale? locale) async {
    _localeOverride = locale;
    if (_initialized) await _queueRefresh(menu: true);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_localeOverride == null && _initialized) {
      unawaited(_queueRefresh(menu: true));
    }
  }

  Future<void> _queueRefresh({required bool menu}) {
    // Serialize native updates so rapid language changes cannot restore stale labels.
    _refreshQueue = _refreshQueue.catchError((_) {}).then((_) async {
      if (!_initialized || _tray == null) return;
      if (menu) await _rebuildMenu();
      final strings = _strings;
      final status = _syncing
          ? strings.text('syncing', {'pair': _pairName == null ? '' : ' $_pairName'})
          : _lastResult != null && _lastResult!.hasChanges
              ? strings.text('last', {'up': _lastResult!.uploaded, 'down': _lastResult!.downloaded})
              : strings.text('pairs', {'count': _pairCount});
      await _tray?.setToolTip('CrispCloud — $status');
    });
    return _refreshQueue;
  }

  Future<void> _rebuildMenu() async {
    final strings = _strings;
    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(label: strings.text('show'), onClicked: (_) => _onShowApp?.call()),
      MenuSeparator(),
      MenuItemLabel(label: strings.text('syncAll'), onClicked: (_) => _onSyncAll?.call()),
      MenuSeparator(),
      MenuItemLabel(label: strings.text('quit'), onClicked: (_) => _onQuit?.call()),
    ]);
    await _tray?.setContextMenu(menu);
  }

  /// Show the app window (bring to front).
  void showApp() {
    _appWindow?.show();
  }

  /// Destroy the tray icon.
  Future<void> dispose() async {
    if (_tray != null) {
      WidgetsBinding.instance.removeObserver(this);
      _initialized = false;
      await _refreshQueue.catchError((_) {});
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
