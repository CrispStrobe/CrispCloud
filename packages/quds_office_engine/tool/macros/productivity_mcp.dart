import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_productivity_automation.dart';

import 'local_mcp_stdio.dart';

Future<void> main(List<String> args) async {
  final jsonOnly = args.length == 2 && args.first == '--json';
  if (!jsonOnly && (args.length != 1 || args.first.startsWith('--'))) {
    stderr.writeln(
      'Usage: dart run tool/macros/productivity_mcp.dart [--json] SNAPSHOT',
    );
    exitCode = 64;
    return;
  }
  try {
    final snapshot = ProductivitySnapshot.parse(
      utf8.decode(
        await readLocalMcpInput(File(args.last), ProductivitySnapshot.maxBytes),
      ),
    );
    if (jsonOnly) {
      stdout.writeln(jsonEncode(snapshot.toJson()));
      await stdout.flush();
    } else {
      await runLocalMcpStdio(ProductivityMcp(snapshot).handleMessage);
    }
  } on Object {
    stderr.writeln('Could not open or serve the productivity snapshot.');
    exitCode = 1;
  }
}
