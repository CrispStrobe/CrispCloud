// Property fuzzing for archive member-name normalization. Any accepted name
// must resolve inside a synthetic extraction root, without parent traversal,
// absolute prefixes, drive letters or NUL bytes.
//
// Run: dart run tool/fuzz_archive_names.dart [budgetMs]

import 'dart:io';

import 'package:covfuzz/covfuzz.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/archive_path_policy.dart';

const _root = '/synthetic/extraction/root';

void _check(String name) {
  try {
    final safe = safeArchiveMemberPath(name);
    if (safe.isEmpty ||
        safe.startsWith('/') ||
        safe
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..') ||
        safe.contains('\\') ||
        safe.contains('\u0000') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(safe)) {
      throw StateError('Accepted unsafe member name: $name -> $safe');
    }
    final joined = p.posix.normalize(p.posix.join(_root, safe));
    if (!p.posix.isWithin(_root, joined)) {
      throw StateError('Accepted member name escapes root: $name -> $joined');
    }
  } on ArchivePathException {
    // Documented rejection.
  }
}

void main(List<String> args) {
  const seeds = <String>[
    'safe.txt',
    'folder/file.bin',
    '../escape',
    '/absolute',
    r'C:\Windows\system32',
    'a/../../b',
    'a//b',
    './a',
    '..',
    '.',
    'a/./b',
    'a\\..\\b',
    'CON',
    'trailing.',
    'nul\u0000byte',
  ];
  final report = fuzz<String>(
    seeds: seeds,
    entry: _check,
    mutate: mutateString,
    // _check converts the documented rejection to a return. Any escape is a
    // contract violation.
    isClean: (_) => false,
    iterations: 100000,
    budgetMs: int.tryParse(args.firstOrNull ?? '') ?? 20000,
  );
  exit(report.report());
}
