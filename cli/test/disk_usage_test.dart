import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crisp/cli_app.dart';
import 'package:crisp/disk_usage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class Capture implements Stdout {
  final buffer = StringBuffer();
  @override
  void writeln([Object? object = '']) => buffer.writeln(object);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('$invocation');
}

class FakeSource implements DiskUsageSource {
  FakeSource(this.metadata, this.children);
  final Map<String, UsageMetadata> metadata;
  final Map<String, List<String>> children;
  final denied = <String>{};
  @override
  p.Context get paths => p.Context(style: p.Style.posix);
  @override
  Future<String> resolveRoot(String path) async => path;
  @override
  Future<UsageMetadata> inspect(String path) async {
    if (denied.contains(path)) throw FileSystemException('denied', path);
    return metadata[path]!;
  }

  @override
  Stream<String> list(String path) async* {
    if (denied.contains('$path/')) throw FileSystemException('denied', path);
    yield* Stream.fromIterable(children[path] ?? []);
  }
}

void main() {
  late Directory tmp;
  late String root;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('crisp_du_');
    root = tmp.resolveSymbolicLinksSync();
    Directory('$root/folder/empty').createSync(recursive: true);
    File('$root/folder/big').writeAsBytesSync(List.filled(50, 0));
    File('$root/folder/small').writeAsBytesSync(List.filled(10, 0));
    File('$root/a').writeAsBytesSync(List.filled(20, 0));
    File('$root/z').writeAsBytesSync(List.filled(20, 0));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('ranks immediate aggregate folders and deterministic ties', () async {
    final result = await DiskUsageScanner().scan(root);
    expect(result.root.bytes, 100);
    expect(result.root.files, 4);
    expect(result.root.directories, 2);
    expect(result.root.complete, isTrue);
    expect(result.rows.map((r) => p.basename(r.path)), ['folder', 'a', 'z']);
    expect(result.rows.first.bytes, 60);
  });
  test('bounded top includes deep individual files', () async {
    final result = await DiskUsageScanner().scan(root, filesOnly: true, top: 2);
    expect(result.rows.map((r) => p.basename(r.path)), ['big', 'a']);
    expect(result.root.bytes, 100);
  });
  test('recursive directory totals overlap explicitly', () async {
    final result = await DiskUsageScanner().scan(
      root,
      recursive: true,
      directoriesOnly: true,
    );
    expect(result.rows.map((r) => p.basename(r.path)), ['folder', 'empty']);
  });
  test('single file root is supported', () async {
    final result = await DiskUsageScanner().scan('$root/a');
    expect(result.root.bytes, 20);
    expect(result.rows.single.kind, UsageKind.file);
  });
  test('zero entry budget means unlimited rather than an empty scan', () async {
    final full = await DiskUsageScanner().scan(root, maxEntries: 0);
    expect(full.root.bytes, 100);
    expect(full.root.complete, isTrue);
    expect(full.limited, isFalse);
    final limited = await DiskUsageScanner().scan(root, maxEntries: 2);
    expect(limited.root.complete, isFalse);
    expect(limited.limited, isTrue);
  });
  test('entry and depth limits produce partial totals', () async {
    for (final result in [
      await DiskUsageScanner().scan(root, maxEntries: 1),
      await DiskUsageScanner().scan(root, maxDepth: 0),
    ]) {
      expect(result.root.complete, isFalse);
      expect(result.limited, isTrue);
      expect(result.root.bytes, 0);
      expect(result.issues, isNotEmpty);
    }
  });
  test(
    'explicit root link resolves, child links including loops are excluded',
    () async {
      if (Platform.isWindows) return; // Windows requires symlink privileges.
      Link('$root/folder/loop').createSync(root);
      Link('$root/broken').createSync('$root/missing');
      Link('$root/alias').createSync('$root/a');
      final outer = Directory.systemTemp.createTempSync('crisp_du_link_');
      try {
        Link('${outer.path}/root').createSync(root);
        final result = await DiskUsageScanner().scan('${outer.path}/root');
        expect(result.root.bytes, 100);
        expect(result.linksSkipped, 3);
        expect(result.root.complete, isTrue);
      } finally {
        outer.deleteSync(recursive: true);
      }
    },
  );
  test('unreadable descendants propagate partial state to ancestors', () async {
    final source = FakeSource(
      {
        '/r': const UsageMetadata(UsageKind.directory),
        '/r/d': const UsageMetadata(UsageKind.directory),
        '/r/good': const UsageMetadata(UsageKind.file, bytes: 7),
      },
      {
        '/r': ['/r/d', '/r/good'],
      },
    )..denied.add('/r/d/');
    final result = await DiskUsageScanner(source: source).scan('/r');
    expect(result.root.bytes, 7);
    expect(result.root.complete, isFalse);
    expect(result.rows.singleWhere((r) => r.path == '/r/d').complete, isFalse);
    expect(result.issues.single.code, 'unreadable_directory');
  });
  test('duplicate and escaping entries cannot inflate totals', () async {
    final source = FakeSource(
      {
        '/r': const UsageMetadata(UsageKind.directory),
        '/r/a': const UsageMetadata(UsageKind.file, bytes: 7),
      },
      {
        '/r': ['/r/a', '/r/a', '/outside', '/r/nested/escape'],
      },
    );
    final result = await DiskUsageScanner(source: source).scan('/r');
    expect(result.root.bytes, 7);
    expect(result.root.complete, isFalse);
    expect(result.issues.length, 3);
  });
  test('overflow, cancellation and issue retention are bounded', () async {
    final source = FakeSource(
      {
        '/r': const UsageMetadata(UsageKind.directory),
        '/r/a': const UsageMetadata(
          UsageKind.file,
          bytes: DiskUsageScanner.maxBytes,
        ),
        '/r/b': const UsageMetadata(UsageKind.file, bytes: 1),
      },
      {
        '/r': ['/r/a', '/r/b'],
      },
    );
    final overflow = await DiskUsageScanner(source: source).scan('/r');
    expect(overflow.root.bytes, DiskUsageScanner.maxBytes);
    expect(overflow.root.complete, isFalse);
    expect(overflow.issues.single.code, 'byte_limit');
    final cancelled = await DiskUsageScanner(
      source: source,
    ).scan('/r', isCancelled: () => true);
    expect(cancelled.cancelled, isTrue);
    expect(cancelled.root.complete, isFalse);
    source.children['/r'] = List.filled(150, '/outside');
    final errors = await DiskUsageScanner(source: source).scan('/r');
    expect(errors.issues.length, 100);
    expect(errors.suppressedIssues, 50);
  });
  test('CLI emits JSON without loading malformed credential config', () async {
    final config = File('$root/config.yaml')..writeAsStringSync(': [ invalid');
    final output = Capture();
    await IOOverrides.runZoned(() async {
      final runner = buildRunner(configPath: config.path);
      expect(
        await runner.run(['du', root, '--files-only', '--top', '1', '--json']),
        0,
      );
      final result = jsonDecode(output.buffer.toString());
      expect(result['entries'].single['bytes'], 50);
      expect(result['measurement'], 'logical_file_bytes');
      expect(result['complete'], isTrue);
      for (final args in [
        ['--top', '0'],
        ['--max-depth', '-1'],
        ['--files-only', '--dirs-only'],
      ]) {
        expect(
          () => runner.run(['du', root, ...args]),
          throwsA(isA<UsageException>()),
        );
      }
    }, stdout: () => output);
  });
  test(
    'CLI missing root and partial scans return failure with valid JSON',
    () async {
      final output = Capture();
      final errors = Capture();
      await IOOverrides.runZoned(
        () async {
          final runner = buildRunner(configPath: '$root/not-loaded');
          expect(await runner.run(['du', '$root/missing', '--json']), 1);
          expect(
            jsonDecode(errors.buffer.toString())['error']['code'],
            'root_unavailable',
          );
          expect(
            await runner.run(['du', root, '--max-entries', '1', '--json']),
            1,
          );
          expect(jsonDecode(output.buffer.toString())['complete'], isFalse);
        },
        stdout: () => output,
        stderr: () => errors,
      );
    },
  );
}
