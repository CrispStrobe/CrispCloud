// lib/services/siri_shortcuts_service.dart
//
// Siri Shortcuts / App Shortcuts integration for CrispCloud (iOS only).
//
// Registers three shortcuts with INVoiceShortcutCenter via a platform channel:
//   1. "Upload to CrispCloud"  — opens the app ready to pick a file for upload.
//   2. "Show recent files"     — navigates directly to the Recent Files screen.
//   3. "Sync now"              — triggers an immediate background sync cycle.
//
// Design decisions
// ─────────────────
// • We use a lightweight custom MethodChannel rather than a Flutter plugin so
//   we don't add a pub.dev dependency for a feature that works only on iOS.
// • On iOS 16+ Apple recommends App Shortcuts (INAppShortcutItem / Shortcuts
//   App integration).  The native side registers both the legacy donated
//   INShortcut and the newer App Shortcut phrase via INShortcutCenter.
// • This service is fully platform-guarded; every public method is a no-op on
//   Android, macOS, Windows, Linux, and Web.
//
// Native counterpart: AppDelegate.swift  handleSiriShortcutsCall(_:result:)
// (added in the AppDelegate update below).

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'log_service.dart';

const _log = Log('SiriShortcutsService');

/// Identifiers for the shortcuts CrispCloud can handle.
///
/// These match the activity type strings registered in AppDelegate and any
/// Intents extension.
class SiriShortcutId {
  SiriShortcutId._();

  static const uploadToCloud   = 'com.crispcloud.shortcut.upload';
  static const showRecentFiles = 'com.crispcloud.shortcut.recent';
  static const syncNow         = 'com.crispcloud.shortcut.sync';
}

/// A donated shortcut descriptor.
class SiriShortcut {
  /// Unique activity-type identifier (matches [SiriShortcutId]).
  final String identifier;

  /// Human-readable title shown in the Shortcuts app and Siri suggestions.
  final String title;

  /// Subtitle displayed below the title in the Shortcuts app.
  final String subtitle;

  /// Suggested invocation phrase (used for Siri voice activation).
  final String suggestedInvocationPhrase;

  const SiriShortcut({
    required this.identifier,
    required this.title,
    required this.subtitle,
    required this.suggestedInvocationPhrase,
  });

  Map<String, String> toMap() => {
        'identifier':                identifier,
        'title':                     title,
        'subtitle':                  subtitle,
        'suggestedInvocationPhrase': suggestedInvocationPhrase,
      };
}

/// Built-in shortcut definitions for CrispCloud.
const _kShortcuts = [
  SiriShortcut(
    identifier:                SiriShortcutId.uploadToCloud,
    title:                     'Upload to CrispCloud',
    subtitle:                  'Pick a file and upload it to your active cloud storage',
    suggestedInvocationPhrase: 'Upload to CrispCloud',
  ),
  SiriShortcut(
    identifier:                SiriShortcutId.showRecentFiles,
    title:                     'Show recent files',
    subtitle:                  'Open CrispCloud and display your most recent files',
    suggestedInvocationPhrase: 'Show my recent files in CrispCloud',
  ),
  SiriShortcut(
    identifier:                SiriShortcutId.syncNow,
    title:                     'Sync now',
    subtitle:                  'Trigger an immediate sync with your cloud providers',
    suggestedInvocationPhrase: 'Sync CrispCloud now',
  ),
];

/// Service that manages Siri Shortcuts / App Shortcuts for CrispCloud.
///
/// Typical usage (call once during app initialisation):
/// ```dart
/// await SiriShortcutsService.instance.registerShortcuts();
/// ```
///
/// Handle an activated shortcut from `AppState` or the root widget:
/// ```dart
/// SiriShortcutsService.instance.setActivationHandler((id) {
///   switch (id) {
///     case SiriShortcutId.uploadToCloud:   navigator.push(UploadRoute());
///     case SiriShortcutId.showRecentFiles: navigator.push(RecentRoute());
///     case SiriShortcutId.syncNow:         syncEngine.runNow();
///   }
/// });
/// ```
class SiriShortcutsService {
  SiriShortcutsService._();

  static final SiriShortcutsService instance = SiriShortcutsService._();

  static const _channel = MethodChannel('com.crispcloud/siri_shortcuts');

  bool get isAvailable => !kIsWeb && Platform.isIOS;

  void Function(String shortcutId)? _activationHandler;

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Register (donate) all built-in CrispCloud shortcuts with Siri.
  ///
  /// Safe to call on every launch — the native side is idempotent.
  /// No-op on non-iOS platforms.
  Future<void> registerShortcuts() async {
    if (!isAvailable) return;

    _setupCallHandler();

    try {
      final payload = _kShortcuts.map((s) => s.toMap()).toList();
      await _channel.invokeMethod('registerShortcuts', {'shortcuts': payload});
      _log.info('Registered ${_kShortcuts.length} Siri shortcut(s)');
    } on PlatformException catch (e) {
      _log.warn('Failed to register Siri shortcuts: ${e.message}');
    } on MissingPluginException {
      _log.debug('Siri shortcuts channel not available (expected on simulator/non-iOS)');
    }
  }

  /// Donate one specific shortcut interaction to Siri (call after the user
  /// actually performs the action in-app to increase suggestion relevance).
  Future<void> donateShortcut(String shortcutId) async {
    if (!isAvailable) return;

    final shortcut = _kShortcuts.cast<SiriShortcut?>()
        .firstWhere((s) => s?.identifier == shortcutId, orElse: () => null);
    if (shortcut == null) {
      _log.warn('donateShortcut: unknown id "$shortcutId"');
      return;
    }

    try {
      await _channel.invokeMethod('donateShortcut', shortcut.toMap());
      _log.debug('Donated shortcut: $shortcutId');
    } on PlatformException catch (e) {
      _log.warn('Failed to donate shortcut "$shortcutId": ${e.message}');
    } on MissingPluginException {
      // Expected on non-iOS.
    }
  }

  /// Remove all donated shortcuts (e.g. on logout).
  Future<void> removeAllShortcuts() async {
    if (!isAvailable) return;

    try {
      await _channel.invokeMethod('removeAllShortcuts');
      _log.info('Removed all Siri shortcuts');
    } on PlatformException catch (e) {
      _log.warn('Failed to remove Siri shortcuts: ${e.message}');
    } on MissingPluginException {
      // Expected on non-iOS.
    }
  }

  /// Set a handler that is called when the user invokes a CrispCloud shortcut
  /// via Siri or the Shortcuts app.
  ///
  /// The handler receives the [SiriShortcutId] that was activated.
  void setActivationHandler(void Function(String shortcutId) handler) {
    _activationHandler = handler;
    _setupCallHandler();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────────────

  bool _callHandlerSetup = false;

  void _setupCallHandler() {
    if (_callHandlerSetup || !isAvailable) return;
    _callHandlerSetup = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'shortcutActivated':
          final id = call.arguments as String?;
          if (id != null && _activationHandler != null) {
            _log.info('Siri shortcut activated', {'id': id});
            _activationHandler!(id);
          }
          return null;
        default:
          throw MissingPluginException('${call.method} not implemented');
      }
    });
  }
}
