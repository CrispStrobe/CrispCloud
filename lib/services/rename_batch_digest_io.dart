import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Content is streamed; links are fingerprinted without traversing them. A
/// directory digest describes its names and contents independently of its own
/// basename, so an interrupted directory rename can be reconciled after restart.
Future<String?> nativeRenameDigest(String path, void Function() check) async {
  check();
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    return sha256
        .convert(utf8.encode('link:${await Link(path).target()}'))
        .toString();
  }
  if (type == FileSystemEntityType.file) {
    final digest = await sha256
        .bind(
          File(path).openRead().map((chunk) {
            check();
            return chunk;
          }),
        )
        .first;
    check();
    return digest.toString();
  }
  if (type == FileSystemEntityType.directory) {
    final entries = await Directory(path).list(followLinks: false).toList();
    entries.sort((a, b) => a.path.compareTo(b.path));
    final contents = <List<String>>[];
    for (final entry in entries) {
      check();
      contents.add([
        p.basename(entry.path),
        (await nativeRenameDigest(entry.path, check))!,
      ]);
    }
    return sha256.convert(utf8.encode(jsonEncode(contents))).toString();
  }
  throw FileSystemException(
    'The source disappeared while checking its contents.',
    path,
  );
}
