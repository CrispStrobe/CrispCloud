import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/custom_toolbar_command.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/command_entry_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

CommandEntryFileIdentity commandIdentity(
  String path, {
  bool directory = false,
  int version = 1,
  int size = 4,
  int mode = 0x1ed,
}) => CommandEntryFileIdentity(
  resolvedPath: path,
  isDirectory: directory,
  size: size,
  modified: DateTime.utc(2026, 1, version),
  changed: DateTime.utc(2026, 1, version),
  mode: mode,
);

class CommandEntryTestHost implements CommandEntryHost {
  @override
  String? platform = 'linux';
  @override
  List<String> searchPath = ['/bin'];
  final identities = <String, CommandEntryFileIdentity>{
    '/work': commandIdentity('/work', directory: true),
    '/bin/tool': commandIdentity('/bin/tool'),
  };
  final inspected = <String>[];
  Future<void> Function(String path)? beforeInspect;

  @override
  Future<CommandEntryFileIdentity?> inspect(String path) async {
    inspected.add(path);
    await beforeInspect?.call(path);
    return identities[path];
  }
}

CommandEntryContext commandContext({
  String directory = '/work',
  List<String> selected = const [],
  bool Function()? isCurrent,
  Future<bool> Function(String)? access,
  StorageReference storage = const StorageReference(
    kind: 'local',
    provider: 'local',
    accountKey: 'fixture',
  ),
  String? target,
  bool Function()? targetCurrent,
  bool windows = false,
}) => CommandEntryContext(
  invocation: CommandInvocationContext(
    storage: storage,
    currentPath: directory,
    selectedPaths: selected,
    isCurrent: isCurrent ?? () => true,
    targetPath: target,
    targetIsCurrent: targetCurrent,
  ),
  selection: [
    for (final path in selected)
      CommandEntrySelection(
        path: path,
        name: (windows ? p.windows : p.posix).basename(path),
        isDirectory: false,
        size: 4,
        modified: DateTime.utc(2026, 1, 1),
      ),
  ],
  hasExistingAccess: access ?? (_) async => true,
);

class CommandEntryTestProcess extends Fake implements Process {
  final out = StreamController<List<int>>();
  final err = StreamController<List<int>>();
  final exit = Completer<int>();
  int kills = 0;

  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills++;
    finish(143);
    return true;
  }

  void finish([int code = 0]) {
    if (exit.isCompleted) return;
    out.close();
    err.close();
    exit.complete(code);
  }
}
