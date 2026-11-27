import 'dart:io';

import 'package:quds_office_engine/quds_productivity_live.dart';

import 'local_mcp_stdio.dart';

Future<void> main(List<String> args) async {
  final credential =
      Platform.environment[ProductivityGrantTicket.environmentKey];
  if (args.isNotEmpty || credential == null) {
    stderr.writeln(
      'Set CRISPOFFICE_MCP_GRANT in the local MCP client environment.',
    );
    exitCode = 64;
    return;
  }
  try {
    final relay = ProductivityGrantRelay(
      ProductivityGrantTicket.parse(credential),
    );
    try {
      await runLocalMcpStdio(relay.forward);
    } finally {
      relay.close();
    }
  } on Object {
    stderr.writeln('Could not serve the local productivity grant.');
    exitCode = 1;
  }
}
