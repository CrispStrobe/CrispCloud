// bin/crisp.dart
//
// Entry point for the crisp CLI tool.
//
// Compile to a self-contained binary:
//   cd cli && dart compile exe bin/crisp.dart -o crisp
//
// Or run directly:
//   dart run bin/crisp.dart <command> [args...]

import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:crisp/cli_app.dart';

Future<void> main(List<String> arguments) async {
  // Handle --version before routing to CommandRunner
  if (arguments.contains('--version') || arguments.contains('-V')) {
    stdout.writeln('crisp 0.1.0');
    exit(0);
  }

  final runner = buildRunner();

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
