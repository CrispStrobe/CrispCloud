import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/file_conversion_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/file_conversion_backend.dart';

void main() {
  const service = FileConversionService();
  late ConversionMemoryBackend backend;
  setUp(() => backend = ConversionMemoryBackend());
  Future<FileConversionResult> run({
    String input = 'source.bin',
    String output = 'converted.mime',
    FileConversionFormat format = FileConversionFormat.mime,
    FileConversionDirection direction = FileConversionDirection.encode,
    FileOperationControl? control,
  }) => service.convert(
    source: backend,
    file: backend.nodes['/files/$input']!,
    destination: backend,
    destinationDirectory: '/files',
    options: FileConversionOptions(
      direction: direction,
      format: format,
      outputName: output,
    ),
    control: control,
  );
  Matcher problem(FileConversionProblem value) => isA<FileConversionException>()
      .having((error) => error.problem, 'problem', value);

  test(
    'native staged encode/decode preserves bytes and refuses an occupied output',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'crisp_conversion_',
      );
      addTearDown(() => directory.delete(recursive: true));
      // Use the same real local backend as native transfer/integrity tests.
      // Successful publication therefore goes through the platform's exclusive
      // rename primitive, not the in-memory staged-write fixture below.
      final local = LocalOperationBackend(
        LocalFileService(),
        isCurrent: () => true,
      );
      expect(local.capabilities.noReplaceMove, isTrue);
      final bytes = Uint8List.fromList(
        List.generate(128 * 1024 + 7, (i) => i % 256),
      );
      final original = File(p.join(directory.path, 'original-Ü.bin'));
      await original.writeAsBytes(bytes, flush: true);
      final selected = (await local.stat(original.path))!;
      const encodeOptions = FileConversionOptions(
        direction: FileConversionDirection.encode,
        format: FileConversionFormat.mime,
        outputName: 'message.mime',
      );
      final encoded = await service.convert(
        source: local,
        file: selected,
        destination: local,
        destinationDirectory: directory.path,
        options: encodeOptions,
      );
      final encodedBytes = await File(encoded.path).readAsBytes();
      expect(encoded.outputSha256, sha256.convert(encodedBytes).toString());
      expect(ascii.decode(encodedBytes), contains("filename*=UTF-8''"));
      final decoded = await service.convert(
        source: local,
        file: (await local.stat(encoded.path))!,
        destination: local,
        destinationDirectory: directory.path,
        options: const FileConversionOptions(
          direction: FileConversionDirection.decode,
          format: FileConversionFormat.mime,
          outputName: 'restored.bin',
        ),
      );
      expect(await File(decoded.path).readAsBytes(), bytes);
      expect(await original.readAsBytes(), bytes);
      await expectLater(
        service.convert(
          source: local,
          file: selected,
          destination: local,
          destinationDirectory: directory.path,
          options: encodeOptions,
        ),
        throwsA(problem(FileConversionProblem.destinationExists)),
      );
      expect(await File(encoded.path).readAsBytes(), encodedBytes);
      expect(await original.readAsBytes(), bytes);
      expect(
        (await directory.list().toList()).map(
          (entry) => p.basename(entry.path),
        ),
        unorderedEquals(['original-Ü.bin', 'message.mime', 'restored.bin']),
      );
    },
    skip: !Platform.isLinux && !Platform.isWindows
        ? 'Uses the Linux/Windows local backend; macOS grants require native acceptance testing.'
        : false,
  );

  for (final format in FileConversionFormat.values) {
    test(
      '${format.name} streamed output round trips through verified new files',
      () async {
        final bytes = List.generate(100013, (i) => i % 256);
        backend.put('source.bin', bytes);
        final encoded = await run(format: format);
        expect(encoded.outputBytes, backend.contents[encoded.path]!.length);
        expect(
          encoded.outputSha256,
          sha256.convert(backend.contents[encoded.path]!).toString(),
        );
        expect(backend.readCounts['/files/source.bin'], 3);
        final decoded = await run(
          input: 'converted.mime',
          output: 'decoded.bin',
          format: format,
          direction: FileConversionDirection.decode,
        );
        expect(backend.contents[decoded.path], bytes);
        expect(backend.contents['/files/source.bin'], bytes);
        expect(
          backend.nodes.keys.any((path) => path.endsWith('.staged')),
          isFalse,
        );
        expect(backend.commits, 2);
      },
    );
  }
  test('invalid decoding publishes and stages nothing', () async {
    backend.put('source.bin', ascii.encode('begin 600 x\n#0V%T\n'));
    await expectLater(
      run(
        format: FileConversionFormat.uue,
        direction: FileConversionDirection.decode,
      ),
      throwsA(isA<FileConversionCodecException>()),
    );
    expect(backend.writes, 0);
    expect(backend.commits, 0);
  });
  test(
    'safe embedded filename and mode never control explicit output',
    () async {
      backend.put(
        'source.bin',
        ascii.encode('begin 777 embedded-name.bin\n#0V%T\n`\nend\n'),
      );
      final result = await run(
        format: FileConversionFormat.uue,
        direction: FileConversionDirection.decode,
      );
      expect(result.path, '/files/converted.mime');
      expect(backend.contents[result.path], ascii.encode('Cat'));
      expect(
        backend.nodes.keys,
        unorderedEquals([
          '/files',
          '/files/source.bin',
          '/files/converted.mime',
        ]),
      );
    },
  );
  test('unsafe embedded names in every format fail before staging or publication', () async {
    for (final name in [
      '.',
      '..',
      '../outside',
      '/absolute',
      'folder/file',
      r'folder\file',
      'C:drive',
      r'C:\outside',
      r'\\server\share',
    ]) {
      final inputs = {
        FileConversionFormat.uue: 'begin 600 $name\n#0V%T\n`\nend\n',
        FileConversionFormat.xxe: 'begin 600 $name\n1Eq3o\n+\nend\n',
        FileConversionFormat.mime:
            'Content-Type: application/octet-stream\nContent-Transfer-Encoding: base64\n'
            "Content-Disposition: attachment; filename*=UTF-8''${Uri.encodeComponent(name)}\n\nQ2F0\n",
      };
      for (final entry in inputs.entries) {
        final bytes = ascii.encode(entry.value);
        backend.put('source.bin', bytes);
        await expectLater(
          run(format: entry.key, direction: FileConversionDirection.decode),
          throwsA(isA<FileConversionCodecException>()),
          reason: '${entry.key.name}: $name',
        );
        expect(backend.contents['/files/source.bin'], bytes);
        expect(backend.writes, 0);
        expect(backend.commits, 0);
        expect(
          backend.nodes.keys,
          unorderedEquals(['/files', '/files/source.bin']),
        );
      }
    }
  });
  test(
    'rejects existing output before reads and preserves its bytes',
    () async {
      backend.put('source.bin', [1]);
      backend.put('converted.mime', [9]);
      await expectLater(
        run(),
        throwsA(problem(FileConversionProblem.destinationExists)),
      );
      expect(backend.readCounts, isEmpty);
      expect(backend.contents['/files/converted.mime'], [9]);
      expect(backend.writes, 0);
    },
  );
  test('rejects self overwrite, traversal and reserved output names', () async {
    backend.put('source.bin', [1]);
    await expectLater(
      run(output: 'source.bin'),
      throwsA(problem(FileConversionProblem.invalidDestination)),
    );
    for (final name in [
      '../escape',
      '/absolute',
      'a/b',
      'a\\b',
      'CON',
      'LPT1.bin',
      'bad\nname',
      'trailing.',
    ]) {
      await expectLater(
        run(output: name),
        throwsA(problem(FileConversionProblem.invalidName)),
      );
    }
    expect(backend.writes, 0);
  });
  test('unbounded, unverified or nonexclusive destination is rejected before reads', () async {
    backend.put('source.bin', [1]);
    backend.bounded = false;
    await expectLater(
      run(),
      throwsA(problem(FileConversionProblem.unsupportedStorage)),
    );
    backend.bounded = true;
    backend.staged = false;
    await expectLater(
      run(),
      throwsA(problem(FileConversionProblem.unsupportedStorage)),
    );
    backend.staged = true;
    backend.exclusive = false;
    await expectLater(
      run(),
      throwsA(problem(FileConversionProblem.unsupportedStorage)),
    );
    expect(backend.readCounts, isEmpty);
    expect(backend.stats, 0);
  });
  test('captured metadata mutation before execution is rejected', () async {
    final file = backend.put('source.bin', [1]);
    backend.nodes[file.path!] = file.copyWith(size: 2);
    await expectLater(
      service.convert(
        source: backend,
        file: file,
        destination: backend,
        destinationDirectory: '/files',
        options: const FileConversionOptions(
          direction: FileConversionDirection.encode,
          format: FileConversionFormat.mime,
          outputName: 'new.mime',
        ),
      ),
      throwsA(problem(FileConversionProblem.sourceChanged)),
    );
    expect(backend.writes, 0);
  });
  test(
    'same-size same-time source changes between passes fail before publication',
    () async {
      backend.put('source.bin', [1, 2, 3]);
      backend.readOverride = (file, count) {
        if (file.path == '/files/source.bin' && count == 2) {
          return Stream.value([4, 5, 6]);
        }
        return null;
      };
      await expectLater(
        run(),
        throwsA(problem(FileConversionProblem.sourceChanged)),
      );
      expect(backend.commits, 0);
      expect(backend.nodes.containsKey('/files/converted.mime'), isFalse);
    },
  );
  test(
    'same-size source mutation after writing is caught by final source hash',
    () async {
      backend.put('source.bin', [1, 2, 3]);
      backend.beforeVerify = (_) async {
        backend.contents['/files/source.bin'] = Uint8List.fromList([4, 5, 6]);
      };
      await expectLater(
        run(),
        throwsA(problem(FileConversionProblem.sourceChanged)),
      );
      expect(backend.commits, 0);
    },
  );
  test('corrupted staged output never becomes visible', () async {
    backend.put('source.bin', [1, 2, 3]);
    backend.beforeVerify = (path) async {
      backend.contents[path]![0] ^= 1;
    };
    await expectLater(
      run(),
      throwsA(problem(FileConversionProblem.verificationFailed)),
    );
    expect(backend.commits, 0);
    expect(backend.nodes.keys.any((path) => path.endsWith('.staged')), isFalse);
  });
  test('racing destination is preserved by exclusive publication', () async {
    backend.put('source.bin', [1]);
    backend.beforeCommit = (path) async {
      backend.put('converted.mime', [42]);
    };
    await expectLater(run(), throwsA(isA<StateError>()));
    expect(backend.contents['/files/converted.mime'], [42]);
    expect(backend.commits, 0);
  });
  test(
    'cancellation interrupts a stalled source stream and releases it',
    () async {
      backend.put('source.bin', [1]);
      final subscribed = Completer<void>(), released = Completer<void>();
      final stalled = StreamController<List<int>>(
        onListen: () => subscribed.complete(),
        onCancel: () {
          if (!released.isCompleted) released.complete();
        },
      );
      backend.readOverride = (_, _) => stalled.stream;
      final control = FileOperationControl();
      final operation = run(control: control);
      final expectation = expectLater(
        operation,
        throwsA(problem(FileConversionProblem.cancelled)),
      );
      await subscribed.future;
      control.cancel();
      await expectation.timeout(const Duration(seconds: 2));
      await released.future.timeout(const Duration(seconds: 2));
      expect(backend.writes, 0);
      await stalled.close();
    },
  );
  test(
    'account replacement while source read stalls cancels original work',
    () async {
      backend.put('source.bin', [1]);
      final subscribed = Completer<void>();
      final stalled = StreamController<List<int>>(
        onListen: () => subscribed.complete(),
      );
      backend.readOverride = (_, _) => stalled.stream;
      final operation = run();
      final expectation = expectLater(
        operation,
        throwsA(problem(FileConversionProblem.sourceUnavailable)),
      );
      await subscribed.future;
      backend.session = Object();
      await expectation.timeout(const Duration(seconds: 2));
      expect(backend.writes, 0);
      await stalled.close();
    },
  );
  test('source size mismatch is detected before writing', () async {
    backend.put('source.bin', [1, 2, 3]);
    backend.readOverride = (_, _) => Stream.value([1, 2]);
    await expectLater(
      run(),
      throwsA(problem(FileConversionProblem.sourceChanged)),
    );
    expect(backend.writes, 0);
  });
}
