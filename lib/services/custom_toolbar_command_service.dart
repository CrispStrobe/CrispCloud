import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_toolbar_command.dart';
import '../utils/async_lock.dart';
import 'toolbar_command_runner.dart';
export '../models/custom_toolbar_command.dart';
export 'toolbar_command_runner.dart';

class CustomToolbarCommandService extends ChangeNotifier {
  CustomToolbarCommandService({this.processStarter});
  static const _prefsKey = 'custom_toolbar_commands_v1';
  final CommandProcessStarter? processStarter;
  final _lock = AsyncLock();
  final List<CustomToolbarCommand> _commands = [];
  bool _loaded = false, _disposed = false;
  List<CustomToolbarCommand> get commands => List.unmodifiable(_commands);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      if (raw.length > 4 * 1024 * 1024) {
        throw const FormatException('Command settings are too large.');
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.length > 256) {
        throw const FormatException('Invalid command settings.');
      }
      final restored = decoded
          .map(
            (e) => CustomToolbarCommand.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      if (restored.map((c) => c.id).toSet().length != restored.length) {
        throw const FormatException('Duplicate command identifiers.');
      }
      _commands.addAll(restored);
    }
    _loaded = true;
  }

  Future<void> load() => _lock.synchronized(() async {
    await _load();
    _changed();
  });
  Future<void> _save(List<CustomToolbarCommand> next) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _prefsKey,
      jsonEncode(next.map((c) => c.toJson()).toList()),
    )) {
      throw StateError('Command settings could not be saved.');
    }
    _commands
      ..clear()
      ..addAll(next);
    _changed();
  }

  Future<void> addCommand(CustomToolbarCommand command) => _lock.synchronized(
    () async {
      await _load();
      command.validate(allowLegacy: true);
      if (_commands.length >= 256 || _commands.any((c) => c.id == command.id)) {
        throw StateError('Duplicate command or command limit reached.');
      }
      await _save([
        ..._commands,
        CustomToolbarCommand.fromJson(command.toJson()),
      ]);
    },
  );
  Future<void> updateCommand(CustomToolbarCommand command) =>
      _lock.synchronized(() async {
        await _load();
        command.validate();
        final index = _commands.indexWhere((c) => c.id == command.id);
        if (index < 0) throw StateError('This command no longer exists.');
        final next = [..._commands]
          ..[index] = CustomToolbarCommand.fromJson(command.toJson());
        await _save(next);
      });
  Future<void> removeCommand(String id) => _lock.synchronized(() async {
    await _load();
    await _save(_commands.where((c) => c.id != id).toList());
  });
  Future<void> reorderCommands(int from, int to) =>
      _lock.synchronized(() async {
        await _load();
        if (from < 0 ||
            from >= _commands.length ||
            to < 0 ||
            to > _commands.length) {
          return;
        }
        final next = [..._commands];
        final command = next.removeAt(from);
        if (to > from) to--;
        next.insert(to, command);
        await _save(next);
      });
  PreparedToolbarCommand prepare(
    CustomToolbarCommand command,
    CommandInvocationContext context,
  ) => prepareToolbarCommand(command, context);
  Future<RunningToolbarCommand> start(
    CustomToolbarCommand command,
    CommandInvocationContext context, {
    int maxOutputBytes = 256 * 1024,
  }) => RunningToolbarCommand.start(
    command,
    context,
    processStarter: processStarter,
    maxOutputBytes: maxOutputBytes,
  );
  Future<String> execute(
    CustomToolbarCommand command, {
    required CommandInvocationContext context,
  }) async {
    final run = await start(command, context);
    try {
      final result = await run.completed;
      return '${result.output}${result.exitCode == 0 ? '' : '\n[Exit code: ${result.exitCode}]'}';
    } finally {
      run.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
