import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Content is streamed; links are fingerprinted without traversing them. A
/// directory digest describes its names and contents independently of its own
/// basename, so an interrupted directory rename can be reconciled after restart.
Future<String?> nativeRenameDigest(
  String path,
  void Function() check, {
  int maxEntries = 200000,
  int maxDepth = 256,
  int maxListedPathBytes = 32 * 1024 * 1024,
}) async {
  if (maxEntries < 1 || maxDepth < 0 || maxListedPathBytes < 1) {
    throw ArgumentError('Rename fingerprint limits must be positive.');
  }
  var listedEntries = 1;
  var listedPathBytes = 0;

  Future<String> digest(String current, int depth) async {
    check();
    if (depth > maxDepth) {
      throw FileSystemException(
        'The rename fingerprint depth limit was exceeded.',
        current,
      );
    }
    final type = await FileSystemEntity.type(current, followLinks: false);
    check();
    if (type == FileSystemEntityType.link) {
      final target = await Link(current).target();
      check();
      return sha256.convert(utf8.encode('link:$target')).toString();
    }
    if (type == FileSystemEntityType.file) {
      final value = await sha256
          .bind(
            File(current).openRead().map((chunk) {
              check();
              return chunk;
            }),
          )
          .first;
      check();
      return value.toString();
    }
    if (type == FileSystemEntityType.directory) {
      // Sort only bounded path records. Check cancellation while enumeration is
      // still in progress, rather than after toList has consumed a huge folder.
      final entries = <FileSystemEntity>[];
      await for (final entry in Directory(current).list(followLinks: false)) {
        check();
        listedEntries++;
        listedPathBytes += utf8.encode(entry.path).length;
        if (listedEntries > maxEntries ||
            listedPathBytes > maxListedPathBytes) {
          throw FileSystemException(
            'The rename fingerprint enumeration limit was exceeded.',
            current,
          );
        }
        entries.add(entry);
      }
      check();
      entries.sort((a, b) => a.path.compareTo(b.path));
      final output = _DigestResult();
      final sink = sha256.startChunkedConversion(output);
      sink.add(const [0x5b]); // '['
      for (var index = 0; index < entries.length; index++) {
        check();
        final entry = entries[index];
        final child = await digest(entry.path, depth + 1);
        if (index != 0) sink.add(const [0x2c]); // ','
        // This is byte-for-byte the previous JSON list encoding, so saved
        // rename fingerprints and restart recovery remain compatible.
        sink.add(utf8.encode(jsonEncode([p.basename(entry.path), child])));
      }
      sink.add(const [0x5d]); // ']'
      sink.close();
      check();
      return output.value!.toString();
    }
    throw FileSystemException(
      'The source disappeared while checking its contents.',
      current,
    );
  }

  return digest(path, 0);
}

class _DigestResult implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
