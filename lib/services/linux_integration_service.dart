// lib/services/linux_integration_service.dart
//
// Linux desktop integration for CrispCloud.
//
// Manages Nautilus/Dolphin/Thunar right-click context menu entries and desktop
// file installation, plus D-Bus notifications via notify-send.
//
// All public methods are no-ops on non-Linux platforms (platform guard).
//
// File manager script / action paths follow the XDG Base Directory spec:
//   Nautilus scripts  : ~/.local/share/nautilus/scripts/
//   Dolphin actions   : ~/.local/share/kservices5/ServiceMenus/
//   Thunar actions    : ~/.config/Thunar/uca.xml
//   Desktop entry     : ~/.local/share/applications/crispcloud.desktop

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log_service.dart';

// ---------------------------------------------------------------------------
// Urgency levels for D-Bus notifications
// ---------------------------------------------------------------------------

enum NotificationUrgency { low, normal, critical }

// ---------------------------------------------------------------------------
// LinuxIntegrationService
// ---------------------------------------------------------------------------

class LinuxIntegrationService {
  static const _log = Log('LinuxIntegrationService');

  // XDG paths (resolved lazily so tests can override via [home]).
  final String? _overrideHome;

  LinuxIntegrationService({String? overrideHome}) : _overrideHome = overrideHome;

  /// Returns true when running on Linux (not web).
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  String get _home {
    if (_overrideHome != null) return _overrideHome!;
    return Platform.environment['HOME'] ?? '/tmp';
  }

  // ---------------------------------------------------------------------------
  // Installation paths
  // ---------------------------------------------------------------------------

  String get _nautilusScriptPath =>
      '$_home/.local/share/nautilus/scripts/Upload to CrispCloud';

  String get _dolphinDesktopPath =>
      '$_home/.local/share/kservices5/ServiceMenus/crispcloud.desktop';

  String get _thunarUcaPath => '$_home/.config/Thunar/uca.xml';

  String get _desktopFilePath =>
      '$_home/.local/share/applications/crispcloud.desktop';

  // ---------------------------------------------------------------------------
  // File manager detection
  // ---------------------------------------------------------------------------

  /// Returns true if Nautilus is present in PATH.
  Future<bool> isNautilusInstalled() async {
    if (!isLinux) return false;
    return _commandExists('nautilus');
  }

  /// Returns true if Dolphin is present in PATH.
  Future<bool> isDolphinInstalled() async {
    if (!isLinux) return false;
    return _commandExists('dolphin');
  }

  /// Returns true if Thunar is present in PATH.
  Future<bool> isThunarInstalled() async {
    if (!isLinux) return false;
    return _commandExists('thunar');
  }

  /// Returns list of detected file manager names (e.g. ['nautilus', 'thunar']).
  Future<List<String>> getInstalledFileManagers() async {
    if (!isLinux) return [];

    final results = <String>[];
    final checks = <String, Future<bool> Function()>{
      'nautilus': isNautilusInstalled,
      'dolphin': isDolphinInstalled,
      'thunar': isThunarInstalled,
    };

    for (final entry in checks.entries) {
      if (await entry.value()) {
        results.add(entry.key);
      }
    }

    _log.debug('Detected file managers', {'managers': results});
    return results;
  }

  // ---------------------------------------------------------------------------
  // Nautilus
  // ---------------------------------------------------------------------------

  /// Creates a Nautilus script at ~/.local/share/nautilus/scripts/Upload to
  /// CrispCloud that encodes selected paths into a crispcloud:// URL and opens
  /// the app.
  ///
  /// Returns true on success.
  Future<bool> installNautilusExtension() async {
    if (!isLinux) {
      _log.debug('installNautilusExtension: not on Linux, skipping');
      return false;
    }

    _log.info('Installing Nautilus script', {'path': _nautilusScriptPath});

    const scriptContent = '''#!/usr/bin/env bash
# CrispCloud Nautilus script
# Encodes the selected file paths as a comma-separated, percent-encoded list
# and opens CrispCloud via its custom URL scheme.

set -euo pipefail

# NAUTILUS_SCRIPT_SELECTED_FILE_PATHS contains newline-separated paths.
paths=""
while IFS= read -r line; do
  [ -z "\$line" ] && continue
  encoded=\$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "\$line")
  if [ -z "\$paths" ]; then
    paths="\$encoded"
  else
    paths="\$paths,\$encoded"
  fi
done <<< "\$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS"

if [ -n "\$paths" ]; then
  xdg-open "crispcloud://upload?paths=\$paths"
fi
''';

    try {
      final file = File(_nautilusScriptPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(scriptContent);
      // Make the script executable.
      await _runProcess('chmod', ['+x', _nautilusScriptPath]);
      _log.info('Nautilus script installed successfully');
      return true;
    } catch (e, st) {
      _log.error('Failed to install Nautilus script', e, st);
      return false;
    }
  }

  /// Removes the Nautilus upload script.
  Future<bool> uninstallNautilusExtension() async {
    if (!isLinux) {
      _log.debug('uninstallNautilusExtension: not on Linux, skipping');
      return false;
    }

    _log.info('Uninstalling Nautilus script');

    try {
      final file = File(_nautilusScriptPath);
      if (await file.exists()) {
        await file.delete();
        _log.info('Nautilus script removed');
      } else {
        _log.debug('Nautilus script not found — nothing to remove');
      }
      return true;
    } catch (e, st) {
      _log.error('Failed to remove Nautilus script', e, st);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Dolphin
  // ---------------------------------------------------------------------------

  /// Creates a KDE service menu .desktop file at
  /// ~/.local/share/kservices5/ServiceMenus/crispcloud.desktop so Dolphin
  /// shows "Upload to CrispCloud" in the context menu.
  ///
  /// Returns true on success.
  Future<bool> installDolphinAction() async {
    if (!isLinux) {
      _log.debug('installDolphinAction: not on Linux, skipping');
      return false;
    }

    _log.info('Installing Dolphin service menu', {'path': _dolphinDesktopPath});

    const desktopContent = '''[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=all/all;
Actions=uploadToCrispCloud

[Desktop Action uploadToCrispCloud]
Name=Upload to CrispCloud
Icon=crispcloud
Exec=crispcloud upload %U
''';

    try {
      final file = File(_dolphinDesktopPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(desktopContent);
      _log.info('Dolphin service menu installed successfully');
      return true;
    } catch (e, st) {
      _log.error('Failed to install Dolphin action', e, st);
      return false;
    }
  }

  /// Removes the Dolphin service menu .desktop file.
  Future<bool> uninstallDolphinAction() async {
    if (!isLinux) {
      _log.debug('uninstallDolphinAction: not on Linux, skipping');
      return false;
    }

    _log.info('Uninstalling Dolphin service menu');

    try {
      final file = File(_dolphinDesktopPath);
      if (await file.exists()) {
        await file.delete();
        _log.info('Dolphin service menu removed');
      } else {
        _log.debug('Dolphin service menu not found — nothing to remove');
      }
      return true;
    } catch (e, st) {
      _log.error('Failed to remove Dolphin action', e, st);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Thunar
  // ---------------------------------------------------------------------------

  /// Appends (or creates) a Thunar custom action in ~/.config/Thunar/uca.xml
  /// that adds "Upload to CrispCloud" to the context menu.
  ///
  /// Returns true on success.
  Future<bool> installThunarAction() async {
    if (!isLinux) {
      _log.debug('installThunarAction: not on Linux, skipping');
      return false;
    }

    _log.info('Installing Thunar custom action', {'path': _thunarUcaPath});

    const actionXml = '''    <action>
        <icon>crispcloud</icon>
        <name>Upload to CrispCloud</name>
        <unique-id>crispcloud-upload-001</unique-id>
        <command>crispcloud upload %F</command>
        <description>Upload selected files to CrispCloud</description>
        <patterns>*</patterns>
        <startup-notify/>
        <directories/>
        <audio-files/>
        <image-files/>
        <other-files/>
        <text-files/>
        <video-files/>
    </action>''';

    try {
      final file = File(_thunarUcaPath);
      await file.parent.create(recursive: true);

      String content;
      if (await file.exists()) {
        final existing = await file.readAsString();
        // Check if already installed.
        if (existing.contains('crispcloud-upload-001')) {
          _log.debug('Thunar action already present — skipping');
          return true;
        }
        // Insert before the closing </actions> tag.
        if (existing.contains('</actions>')) {
          content = existing.replaceFirst(
              '</actions>', '$actionXml\n</actions>');
        } else {
          // Malformed or empty — replace entirely.
          content = _thunarUcaTemplate(actionXml);
        }
      } else {
        content = _thunarUcaTemplate(actionXml);
      }

      await file.writeAsString(content);
      _log.info('Thunar custom action installed successfully');
      return true;
    } catch (e, st) {
      _log.error('Failed to install Thunar action', e, st);
      return false;
    }
  }

  String _thunarUcaTemplate(String actionXml) => '''<?xml version="1.0" encoding="UTF-8"?>
<actions>
$actionXml
</actions>
''';

  /// Removes the CrispCloud entry from Thunar's uca.xml.
  Future<bool> uninstallThunarAction() async {
    if (!isLinux) {
      _log.debug('uninstallThunarAction: not on Linux, skipping');
      return false;
    }

    _log.info('Uninstalling Thunar custom action');

    try {
      final file = File(_thunarUcaPath);
      if (!await file.exists()) {
        _log.debug('Thunar uca.xml not found — nothing to remove');
        return true;
      }

      final content = await file.readAsString();
      if (!content.contains('crispcloud-upload-001')) {
        _log.debug('CrispCloud Thunar action not present — nothing to remove');
        return true;
      }

      // Remove the <action>...</action> block containing the unique-id.
      final cleaned = _removeXmlActionBlock(content, 'crispcloud-upload-001');
      await file.writeAsString(cleaned);
      _log.info('Thunar custom action removed');
      return true;
    } catch (e, st) {
      _log.error('Failed to remove Thunar action', e, st);
      return false;
    }
  }

  /// Naively removes the first <action>…</action> block that contains
  /// [uniqueId].
  String _removeXmlActionBlock(String xml, String uniqueId) {
    final start = xml.indexOf('<action>');
    final end = xml.indexOf('</action>');
    if (start == -1 || end == -1) return xml;

    // Walk through all <action> blocks.
    final buffer = StringBuffer();
    var offset = 0;
    while (true) {
      final blockStart = xml.indexOf('<action>', offset);
      if (blockStart == -1) {
        buffer.write(xml.substring(offset));
        break;
      }
      final blockEnd = xml.indexOf('</action>', blockStart);
      if (blockEnd == -1) {
        buffer.write(xml.substring(offset));
        break;
      }
      final block = xml.substring(blockStart, blockEnd + '</action>'.length);
      if (block.contains(uniqueId)) {
        // Skip this block — write everything before it.
        buffer.write(xml.substring(offset, blockStart));
        offset = blockEnd + '</action>'.length;
        // Consume one optional leading newline.
        if (offset < xml.length && xml[offset] == '\n') offset++;
      } else {
        buffer.write(xml.substring(offset, blockEnd + '</action>'.length));
        offset = blockEnd + '</action>'.length;
      }
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Desktop file
  // ---------------------------------------------------------------------------

  /// Creates (or overwrites) ~/.local/share/applications/crispcloud.desktop
  /// so the app appears in the system application launcher.
  ///
  /// Returns true on success.
  Future<bool> installDesktopFile() async {
    if (!isLinux) {
      _log.debug('installDesktopFile: not on Linux, skipping');
      return false;
    }

    _log.info('Installing desktop file', {'path': _desktopFilePath});

    const desktopContent = '''[Desktop Entry]
Name=CrispCloud
Comment=Cross-platform cloud file manager
Exec=crispcloud %U
Icon=crispcloud
Terminal=false
Type=Application
Categories=Network;FileTransfer;Cloud;
MimeType=x-scheme-handler/crispcloud;
StartupNotify=true
StartupWMClass=CrispCloud
Keywords=cloud;storage;files;upload;download;sync;
''';

    try {
      final file = File(_desktopFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(desktopContent);

      // Register with the MIME database (best-effort).
      await _runProcess('update-desktop-database',
          ['$_home/.local/share/applications']);

      _log.info('Desktop file installed successfully');
      return true;
    } catch (e, st) {
      _log.error('Failed to install desktop file', e, st);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // D-Bus notifications (via notify-send)
  // ---------------------------------------------------------------------------

  /// Sends a desktop notification using notify-send (which bridges to D-Bus
  /// org.freedesktop.Notifications under the hood).
  ///
  /// [urgency] maps to notify-send --urgency=low|normal|critical.
  /// [icon] is an icon name or path; defaults to 'crispcloud'.
  ///
  /// Returns true on success.
  Future<bool> sendNotification(
    String title,
    String body, {
    String icon = 'crispcloud',
    NotificationUrgency urgency = NotificationUrgency.normal,
  }) async {
    if (!isLinux) {
      _log.debug('sendNotification: not on Linux, skipping');
      return false;
    }

    final urgencyStr = _urgencyString(urgency);
    _log.debug('Sending notification', {
      'title': title,
      'body': body,
      'urgency': urgencyStr,
    });

    final args = [
      '--app-name=CrispCloud',
      '--icon=$icon',
      '--urgency=$urgencyStr',
      title,
      body,
    ];

    try {
      final ok = await _runProcess('notify-send', args);
      if (ok) {
        _log.debug('Notification sent successfully');
      } else {
        _log.warn('notify-send exited with non-zero status');
      }
      return ok;
    } catch (e, st) {
      _log.error('Failed to send notification', e, st);
      return false;
    }
  }

  String _urgencyString(NotificationUrgency urgency) {
    switch (urgency) {
      case NotificationUrgency.low:
        return 'low';
      case NotificationUrgency.normal:
        return 'normal';
      case NotificationUrgency.critical:
        return 'critical';
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Runs [command] with [args] and returns true if the exit code is 0.
  Future<bool> _runProcess(String command, List<String> args) async {
    try {
      final result = await Process.run(command, args);
      if (result.exitCode != 0) {
        _log.warn('Process exited non-zero', {
          'command': command,
          'args': args,
          'exitCode': result.exitCode,
          'stderr': result.stderr.toString().trim(),
        });
      }
      return result.exitCode == 0;
    } on ProcessException catch (e) {
      _log.warn('Process execution failed', {'command': command, 'error': e.message});
      return false;
    } catch (e, st) {
      _log.error('Unexpected error running process', e, st);
      return false;
    }
  }

  /// Returns true if [command] is found in PATH via `which`.
  Future<bool> _commandExists(String command) async {
    try {
      final result = await Process.run('which', [command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
