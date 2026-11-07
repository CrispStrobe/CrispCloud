// lib/services/windows_integration_service.dart
//
// Windows Explorer shell integration for CrispCloud.
// Manages the "Upload to CrispCloud" right-click context menu entry by writing
// to HKCU\Software\Classes\*\shell\CrispCloud through the Win32 registry API.
//
// All public methods are no-ops on non-Windows platforms.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log_service.dart';
import 'windows_registry.dart';

class WindowsIntegrationService {
  static const _log = Log('WindowsIntegrationService');

  /// Registry key path for the CrispCloud shell entry (user-level).
  static const _shellKey = r'Software\Classes\*\shell\CrispCloud';
  static const _commandKey = r'Software\Classes\*\shell\CrispCloud\command';

  /// Returns true when running on Windows (not web).
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  // ---------------------------------------------------------------------------
  // Context menu registration
  // ---------------------------------------------------------------------------

  /// Register the "Upload to CrispCloud" context menu entry.
  ///
  /// Writes the required HKCU registry keys through the Win32 API. No admin
  /// rights are needed for HKCU writes.
  ///
  /// Returns true on success.
  Future<bool> registerContextMenu() async {
    if (!isSupported) {
      _log.debug('registerContextMenu: not on Windows, skipping');
      return false;
    }

    final exePath = Platform.resolvedExecutable;
    _log.info('Registering Windows Explorer context menu', {'exe': exePath});

    try {
      // 1. Shell key — menu display label (default value).
      if (!await _regAdd(_shellKey, null, 'Upload to CrispCloud')) {
        _log.error('Failed to write shell label key');
        return false;
      }

      // 2. Shell key — icon (exe,0 resource syntax).
      if (!await _regAdd(_shellKey, 'Icon', '$exePath,0')) {
        _log.warn(
          'Failed to write Icon value — proceeding without custom icon',
        );
        // Non-fatal.
      }

      // 3. Command sub-key — launch app with the selected file path.
      final command = '"$exePath" "crispcloud://upload?paths=%1"';
      if (!await _regAdd(_commandKey, null, command)) {
        _log.error('Failed to write command key — rolling back');
        await _deleteKey(_shellKey);
        return false;
      }

      _log.info('Context menu registered successfully');
      return true;
    } catch (e, st) {
      _log.error('Exception during context menu registration', e, st);
      return false;
    }
  }

  /// Unregister the "Upload to CrispCloud" context menu entry.
  ///
  /// Returns true on success (including when the key did not exist).
  Future<bool> unregisterContextMenu() async {
    if (!isSupported) {
      _log.debug('unregisterContextMenu: not on Windows, skipping');
      return false;
    }

    _log.info('Unregistering Windows Explorer context menu');

    try {
      final result = await _deleteKey(_shellKey);
      if (result) {
        _log.info('Context menu unregistered successfully');
      } else {
        _log.warn('Context menu key not found or could not be deleted');
      }
      return result;
    } catch (e, st) {
      _log.error('Exception during context menu unregistration', e, st);
      return false;
    }
  }

  /// Returns true if the context menu entry is currently registered.
  Future<bool> isContextMenuRegistered() async {
    if (!isSupported) return false;

    try {
      return registryKeyExists(_shellKey);
    } catch (e) {
      _log.warn('Failed to query context menu registration', e);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Writes a REG_SZ value. A null [valueName] writes the default value.
  Future<bool> _regAdd(
    String registryKey,
    String? valueName,
    String data,
  ) async => registrySetString(registryKey, valueName, data);

  /// Deletes the key and its children. Missing keys count as success.
  Future<bool> _deleteKey(String registryKey) async =>
      registryDeleteTree(registryKey);
}
