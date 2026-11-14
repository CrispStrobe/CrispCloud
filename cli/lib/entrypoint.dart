// Shared executable entrypoint; both command names retain identical behavior.
import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:crisp/cli_app.dart';

Future<void> runCrispCloudCli(
  List<String> arguments, {
  String executableName = 'crispcloud',
}) async {
  // Handle --version before routing to CommandRunner
  if (arguments.isNotEmpty &&
      (arguments.first == '--version' || arguments.first == '-V')) {
    stdout.writeln('$executableName 1.3.2');
    exit(0);
  }

  final runner = buildRunner(executableName: executableName);

  try {
    final exitCode = await runner.run(arguments) ?? 0;
    exit(exitCode);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('');
    stderr.writeln(e.usage);
    exit(2);
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}
