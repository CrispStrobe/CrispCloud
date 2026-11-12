import 'dart:async';

import 'package:crisp_cloud/services/external_terminal_service.dart';

class TerminalHostFixture implements ExternalTerminalHost {
  TerminalHostFixture({this.platform = 'linux'});
  @override
  final String? platform;
  bool executableExists = true, directoryExists = true;
  Completer<void>? executableGate, directoryGate;
  final checkedExecutables = <String>[];
  final checkedDirectories = <String>[];
  final launches =
      <({String executable, List<String> arguments, String directory})>[];
  Object? launchError;
  @override
  Future<bool> executableAvailable(String path) async {
    checkedExecutables.add(path);
    await executableGate?.future;
    return executableExists;
  }

  @override
  Future<bool> directoryAvailable(String path) async {
    checkedDirectories.add(path);
    await directoryGate?.future;
    return directoryExists;
  }

  @override
  Future<void> launch(
    String executable,
    List<String> arguments,
    String directory,
  ) async {
    if (launchError case final error?) throw error;
    launches.add((
      executable: executable,
      arguments: List.of(arguments),
      directory: directory,
    ));
  }
}
