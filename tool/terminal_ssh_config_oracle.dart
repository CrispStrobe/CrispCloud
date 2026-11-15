// Reads only the runner's authored fixtures from stdin and evaluates the
// production importer. It does not connect, read identities, or execute config.
import 'dart:convert';
import 'dart:io';

// The standalone oracle deliberately bypasses package resolution.
// ignore: avoid_relative_lib_imports
import '../lib/models/ssh_config_import.dart';

Future<void> main() async {
  final fixtures =
      jsonDecode(await stdin.transform(utf8.decoder).join()) as List<dynamic>;
  final output = <Map<String, Object?>>[];
  for (final value in fixtures) {
    final fixture = value as Map<String, dynamic>;
    final result = SshConfigImport.parse(
      fixture['source'] as String,
      defaultUsername: fixture['defaultUsername'] as String,
    );
    final entry = result.entries.singleWhere(
      (entry) => entry.alias == fixture['alias'],
    );
    final config = entry.config;
    output.add({
      'alias': entry.alias,
      'host': config?.host,
      'user': config?.username,
      'port': config?.port,
      'identity': entry.identityFileHints.map((hint) => hint.path).toList(),
      'errors': [...result.diagnostics, ...entry.diagnostics]
          .where((d) => d.severity == SshConfigImportSeverity.error)
          .map((d) => d.code)
          .toList(),
    });
  }
  stdout.write(jsonEncode(output));
}
