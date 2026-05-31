// lib/services/multi_window_service.dart
//
// iPadOS Stage Manager / Multi-Window support for CrispCloud.
//
// Stage Manager (iPadOS 16+) allows the user to open several windows of the
// same app side-by-side.  Flutter supports this via the
// UIApplicationSceneManifest scene lifecycle (UISupportsMultipleScenes = YES
// in Info.plist).
//
// This service:
//   1. Detects whether the app is running in a multi-window environment.
//   2. Provides a stable per-window identity so each scene can maintain its
//      own independent browser state (current folder, selection, etc.).
//   3. Exposes helpers for requesting new windows and sharing data between
//      scenes via the App Group shared container (same group used by the
//      FileProvider and Share extensions).
//
// Platform guard: all methods are no-ops on Android, macOS, Windows, Linux,
// and Web.  On iOS < 13 multi-window is unavailable and the service reports
// [isMultiWindowCapable] = false.
//
// Native counterpart: ios/Runner/SceneDelegate.swift handles the UIScene
// lifecycle and forwards scene user-activity payloads back to Flutter via the
// "com.crispcloud/multi_window" MethodChannel.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'log_service.dart';

const _log = Log('MultiWindowService');

/// Identifies a CrispCloud scene / window.
class CrispWindowId {
  /// The opaque system-assigned scene identifier (matches
  /// UIScene.session.persistentIdentifier on the native side).
  final String sceneId;

  /// Optional user-visible label (set when the window was requested).
  final String? label;

  const CrispWindowId({required this.sceneId, this.label});

  @override
  String toString() => 'CrispWindowId($sceneId${label != null ? ", $label" : ""})';
}

/// Snapshot of multi-window state reported by the native side.
class MultiWindowState {
  /// All currently open scene identifiers.
  final List<CrispWindowId> openWindows;

  /// The scene identifier of this window.
  final String currentSceneId;

  /// Whether the device / OS supports multiple windows.
  final bool isCapable;

  const MultiWindowState({
    required this.openWindows,
    required this.currentSceneId,
    required this.isCapable,
  });

  /// Whether more than one window is actually open right now.
  bool get isMultiWindowActive => openWindows.length > 1;
}

/// Service that manages Stage Manager / multi-window behaviour for iPadOS.
///
/// Typical setup (in main.dart or AppState):
/// ```dart
/// final mw = MultiWindowService.instance;
/// await mw.initialize();
/// if (mw.state.isMultiWindowActive) {
///   // Restore per-window browser state for mw.state.currentSceneId
/// }
/// ```
class MultiWindowService {
  MultiWindowService._();

  static final MultiWindowService instance = MultiWindowService._();

  static const _channel = MethodChannel('com.crispcloud/multi_window');

  bool get isAvailable => !kIsWeb && Platform.isIOS;

  MultiWindowState _state = const MultiWindowState(
    openWindows:    [],
    currentSceneId: '',
    isCapable:      false,
  );

  /// Current multi-window state.  Call [initialize] first.
  MultiWindowState get state => _state;

  /// Callback invoked whenever a window is opened or closed.
  void Function(MultiWindowState state)? onStateChanged;

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Query the native side for initial multi-window state and start listening
  /// for scene lifecycle changes.
  ///
  /// No-op on non-iOS platforms.
  Future<void> initialize() async {
    if (!isAvailable) {
      _log.debug('MultiWindowService: not iOS — multi-window unavailable');
      return;
    }

    _channel.setMethodCallHandler(_handleMethodCall);

    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getWindowState');
      if (raw != null) {
        _updateState(raw);
      }
      _log.info('MultiWindowService initialised', {
        'capable': _state.isCapable,
        'windows': _state.openWindows.length,
        'current': _state.currentSceneId,
      });
    } on PlatformException catch (e) {
      _log.warn('Failed to get window state: ${e.message}');
    } on MissingPluginException {
      _log.debug('MultiWindow channel not available (expected on simulator/non-iOS)');
    }
  }

  /// Request a new window from the system.
  ///
  /// The system may decline (e.g. on iPhone, or if multi-window is disabled in
  /// Settings).  Returns `true` if the request was accepted.
  ///
  /// [label] is stored in the new scene's user activity and used to give the
  /// window a descriptive title in the App Switcher.
  Future<bool> requestNewWindow({String? label}) async {
    if (!isAvailable) return false;
    if (!_state.isCapable) {
      _log.debug('requestNewWindow: device not capable — ignoring');
      return false;
    }

    try {
      final accepted = await _channel.invokeMethod<bool>(
        'requestNewWindow',
        {'label': label ?? 'CrispCloud'},
      );
      _log.info('New window requested', {'accepted': accepted, 'label': label});
      return accepted ?? false;
    } on PlatformException catch (e) {
      _log.warn('requestNewWindow failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Close the window identified by [sceneId].
  ///
  /// Passing [currentSceneId] closes the calling window.
  Future<void> closeWindow(String sceneId) async {
    if (!isAvailable) return;

    try {
      await _channel.invokeMethod('closeWindow', {'sceneId': sceneId});
      _log.info('Close window requested', {'sceneId': sceneId});
    } on PlatformException catch (e) {
      _log.warn('closeWindow failed: ${e.message}');
    } on MissingPluginException {
      // No-op.
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────────────

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'windowStateChanged':
        final args = call.arguments as Map<dynamic, dynamic>?;
        if (args != null) {
          _updateState(args.cast<String, dynamic>());
          _log.debug('Window state updated', {
            'windows': _state.openWindows.length,
            'active':  _state.isMultiWindowActive,
          });
          onStateChanged?.call(_state);
        }
        return null;
      default:
        throw MissingPluginException('${call.method} not implemented in MultiWindowService');
    }
  }

  void _updateState(Map<String, dynamic> raw) {
    final capable    = raw['isCapable']      as bool?   ?? false;
    final currentId  = raw['currentSceneId'] as String? ?? '';
    final rawWindows = raw['openWindows']    as List<dynamic>? ?? [];

    final windows = rawWindows
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => CrispWindowId(
              sceneId: (m['sceneId'] as String?) ?? '',
              label:   m['label']   as String?,
            ))
        .where((w) => w.sceneId.isNotEmpty)
        .toList();

    _state = MultiWindowState(
      openWindows:    windows,
      currentSceneId: currentId,
      isCapable:      capable,
    );
  }
}
