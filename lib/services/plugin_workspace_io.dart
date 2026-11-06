import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<(String, Future<void> Function())> createWorkspace(
  String id, {
  String? baseDirectory,
}) async {
  Directory base;
  if (baseDirectory != null) {
    base = Directory(baseDirectory);
  } else {
    try {
      base = await getTemporaryDirectory();
    } catch (_) {
      base = Directory.systemTemp;
    }
  }
  final root = await Directory(p.join(base.path, 'crispcloud_plugins'))
      .create(recursive: true);
  final directory = await root.createTemp('$id-');
  return (
    directory.absolute.path,
    () async {
      if (await directory.exists()) await directory.delete(recursive: true);
    },
  );
}
