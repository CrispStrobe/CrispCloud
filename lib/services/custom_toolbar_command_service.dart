// lib/services/custom_toolbar_command_service.dart
//
// User-defined shell commands as toolbar buttons.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A user-defined shell command that can be run from the toolbar.
class CustomToolbarCommand {
  final String id;
  final String label;
  final String iconName;
  final String command;
  final String? workingDir;
  final bool useCurrentPanelPath;

  const CustomToolbarCommand({
    required this.id,
    required this.label,
    this.iconName = 'terminal',
    required this.command,
    this.workingDir,
    this.useCurrentPanelPath = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'iconName': iconName,
        'command': command,
        'workingDir': workingDir,
        'useCurrentPanelPath': useCurrentPanelPath,
      };

  factory CustomToolbarCommand.fromJson(Map<String, dynamic> json) =>
      CustomToolbarCommand(
        id: json['id'] as String,
        label: json['label'] as String,
        iconName: json['iconName'] as String? ?? 'terminal',
        command: json['command'] as String,
        workingDir: json['workingDir'] as String?,
        useCurrentPanelPath: json['useCurrentPanelPath'] as bool? ?? true,
      );
}

class CustomToolbarCommandService extends ChangeNotifier {
  static const _prefsKey = 'custom_toolbar_commands_v1';

  List<CustomToolbarCommand> _commands = [];
  List<CustomToolbarCommand> get commands => List.unmodifiable(_commands);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _commands = list
            .map((e) => CustomToolbarCommand.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _commands = [];
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_commands.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> addCommand(CustomToolbarCommand cmd) async {
    _commands.add(cmd);
    await _save();
    notifyListeners();
  }

  Future<void> removeCommand(String id) async {
    _commands.removeWhere((c) => c.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> reorderCommands(int from, int to) async {
    if (from < 0 || from >= _commands.length) return;
    if (to < 0 || to > _commands.length) return;
    final cmd = _commands.removeAt(from);
    if (to > from) to--;
    _commands.insert(to, cmd);
    await _save();
    notifyListeners();
  }

  /// Execute a command and return its stdout + stderr output.
  /// Only available on desktop platforms.
  Future<String> execute(
    CustomToolbarCommand cmd, {
    String? currentPath,
    List<String>? selectedPaths,
  }) async {
    if (kIsWeb || (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)) {
      return 'Command execution not available on this platform';
    }

    final workDir = cmd.useCurrentPanelPath
        ? currentPath ?? cmd.workingDir ?? '.'
        : cmd.workingDir ?? '.';

    // Expand {SELECTED} placeholder with selected file paths
    var expandedCommand = cmd.command;
    if (selectedPaths != null && selectedPaths.isNotEmpty) {
      expandedCommand = expandedCommand.replaceAll(
        '{SELECTED}',
        selectedPaths.map((p) => '"$p"').join(' '),
      );
    }

    final ProcessResult result;
    if (Platform.isWindows) {
      result = await Process.run('cmd', ['/c', expandedCommand],
          workingDirectory: workDir);
    } else {
      result = await Process.run('sh', ['-c', expandedCommand],
          workingDirectory: workDir);
    }

    final output = StringBuffer();
    if ((result.stdout as String).isNotEmpty) output.writeln(result.stdout);
    if ((result.stderr as String).isNotEmpty) output.writeln(result.stderr);
    if (result.exitCode != 0) {
      output.writeln('[Exit code: ${result.exitCode}]');
    }
    return output.toString();
  }
}
