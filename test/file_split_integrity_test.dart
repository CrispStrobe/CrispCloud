import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/file_split_service.dart';
import 'package:crisp_cloud/services/file_integrity_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';

import 'support/workflow_fake_client.dart';

void main() {
  late WorkflowFakeClient input;
  late WorkflowFakeClient output;
  late CloudOperationBackend source;
  late CloudOperationBackend destination;
  setUp(() {
    input = WorkflowFakeClient()
      ..put('/data.bin', List.generate(10, (index) => index));
    output = WorkflowFakeClient();
    source = CloudOperationBackend(input, isCurrent: () => input.current);
    destination = CloudOperationBackend(
      output,
      isCurrent: () => output.current,
    );
  });
  Future<SplitResult> split({
    bool Function()? isCancelled,
    void Function(String, int, int)? onProgress,
  }) async => FileSplitService.splitToBackend(
    source: source,
    file: (await source.stat('/data.bin'))!,
    destination: destination,
    targetDirectory: '/',
    chunkSizeBytes: 3,
    isCancelled: isCancelled,
    onProgress: onProgress,
  );

  test('cloud split and combine use verified complete manifests', () async {
    final result = await split();
    expect(result.manifest.status, SplitManifestStatus.complete);
    expect(result.manifest.parts.map((part) => part.size), [3, 3, 3, 1]);
    expect(
      result.manifest.parts.every((part) => part.sha256.length == 64),
      true,
    );
    final path = await FileSplitService.combineFromManifest(
      source: destination,
      manifestFile: (await destination.stat(result.manifestPath))!,
      destination: source,
      outputPath: '/combined.bin',
    );
    expect(input.files[path], input.files['/data.bin']);
    expect(
      output.files.keys.where((path) => path.contains('.crisp-transfer-')),
      isEmpty,
    );
    await expectLater(split(), throwsStateError);
  });

  test('reviewed manifest rejects same-identity replacement before destination work', () async {
    final result = await split();
    final captured = (await destination.stat(result.manifestPath))!;
    final originalBytes = output.files[result.manifestPath]!;
    final reviewed = await FileSplitService.readManifest(destination, captured);
    final replacementBytes = <int>[];
    final replacementParts = <SplitPart>[];
    for (final part in reviewed.parts) {
      final path = part.path.replaceFirst('data.bin', 'next.bin');
      final bytes = output.files['/${part.path}']!
          .map((byte) => byte + 20)
          .toList();
      replacementBytes.addAll(bytes);
      output.put('/$path', bytes);
      final digest = ChecksumAccumulator(ChecksumAlgorithm.sha256)..add(bytes);
      replacementParts.add(
        SplitPart(
          index: part.index,
          path: path,
          size: part.size,
          sha256: digest.finish(),
        ),
      );
    }
    final digest = ChecksumAccumulator(ChecksumAlgorithm.sha256)
      ..add(replacementBytes);
    final replacement = SplitManifest(
      originalName: 'next.bin',
      totalBytes: reviewed.totalBytes,
      chunkSize: reviewed.chunkSize,
      status: SplitManifestStatus.complete,
      parts: replacementParts,
      sha256: digest.finish(),
    );
    final encoded = replacement.encode();
    expect(encoded.length, originalBytes.length);
    output.put(result.manifestPath, encoded, date: captured.updatedAt);
    final replaced = (await destination.stat(result.manifestPath))!;
    expect(replaced.path, captured.path);
    expect(replaced.uuid, captured.uuid);
    expect(replaced.size, captured.size);
    expect(replaced.updatedAt, captured.updatedAt);
    final writesBefore = input.writes.length;
    await expectLater(
      FileSplitService.combineFromManifest(
        source: destination,
        manifestFile: captured,
        reviewedManifest: reviewed,
        destination: source,
        outputPath: '/combined.bin',
      ),
      throwsA(isA<SplitManifestChangedException>()),
    );
    expect(input.writes.length, writesBefore);
    expect(input.files['/combined.bin'], isNull);
    expect(
      input.files.keys.where((path) => path.contains('.crisp-transfer-')),
      isEmpty,
    );

    final reopened = await FileSplitService.readManifest(destination, replaced);
    await FileSplitService.combineFromManifest(
      source: destination,
      manifestFile: replaced,
      reviewedManifest: reopened,
      destination: source,
      outputPath: '/combined.bin',
    );
    expect(input.files['/combined.bin'], replacementBytes);
  });

  test(
    'equivalent reformatted manifest preserves reviewed combination',
    () async {
      final result = await split();
      final manifest = (await destination.stat(result.manifestPath))!;
      final reviewed = await FileSplitService.readManifest(
        destination,
        manifest,
      );
      final json = reviewed.toJson()
        ..['annotation'] = 'No operation fields changed';
      output.put(
        result.manifestPath,
        utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
      );
      await FileSplitService.combineFromManifest(
        source: destination,
        manifestFile: manifest,
        reviewedManifest: reviewed,
        destination: source,
        outputPath: '/combined.bin',
      );
      expect(input.files['/combined.bin'], input.files['/data.bin']);
    },
  );

  test(
    'missing and corrupt parts are rejected before any output is committed',
    () async {
      final result = await split();
      final manifest = (await destination.stat(result.manifestPath))!;
      final last = output.files.remove(result.partPaths.last)!;
      await expectLater(
        FileSplitService.combineFromManifest(
          source: destination,
          manifestFile: manifest,
          destination: source,
          outputPath: '/combined.bin',
        ),
        throwsStateError,
      );
      expect(input.files['/combined.bin'], isNull);
      output.put(result.partPaths.last, last);
      output.put(result.partPaths[1], [9, 9, 9]);
      await expectLater(
        FileSplitService.combineFromManifest(
          source: destination,
          manifestFile: manifest,
          destination: source,
          outputPath: '/combined.bin',
        ),
        throwsStateError,
      );
      expect(input.files['/combined.bin'], isNull);
    },
  );

  test(
    'cancellation leaves a partial manifest with only completed parts',
    () async {
      var cancelled = false;
      await expectLater(
        split(
          isCancelled: () => cancelled,
          onProgress: (_, bytes, _) {
            if (bytes > 3) cancelled = true;
          },
        ),
        throwsA(isA<FileIntegrityCancelled>()),
      );
      final manifest = await FileSplitService.readManifest(
        destination,
        (await destination.stat('/data.bin.split.json'))!,
      );
      expect(manifest.status, SplitManifestStatus.cancelled);
      expect(manifest.parts.length, 1);
      expect(output.files['/data.bin.part001'], [0, 1, 2]);
      expect(output.files['/data.bin.part002'], isNull);
      await expectLater(
        FileSplitService.combineFromManifest(
          source: destination,
          manifestFile: (await destination.stat('/data.bin.split.json'))!,
          destination: source,
          outputPath: '/combined.bin',
        ),
        throwsStateError,
      );
    },
  );

  test('a part changed during combination cannot be committed', () async {
    final result = await split();
    await expectLater(
      FileSplitService.combineFromManifest(
        source: destination,
        manifestFile: (await destination.stat(result.manifestPath))!,
        destination: source,
        outputPath: '/combined.bin',
        onProgress: (phase, _, _) {
          if (phase.startsWith('Combining part 1')) {
            output.put(result.partPaths.first, [9, 9, 9]);
          }
        },
      ),
      throwsStateError,
    );
    expect(input.files['/combined.bin'], isNull);
    expect(
      input.files.keys.where((path) => path.contains('.crisp-transfer-')),
      isEmpty,
    );
  });

  test(
    'wrong whole checksum and traversal manifests fail without writing output',
    () async {
      final result = await split();
      final json = jsonDecode(
        utf8.decode(output.files[result.manifestPath]!),
      ) as Map<String, dynamic>;
      json['sha256'] = '0' * 64;
      output.put(result.manifestPath, utf8.encode(jsonEncode(json)));
      await expectLater(
        FileSplitService.combineFromManifest(
          source: destination,
          manifestFile: (await destination.stat(result.manifestPath))!,
          destination: source,
          outputPath: '/combined.bin',
        ),
        throwsStateError,
      );
      expect(input.files['/combined.bin'], isNull);
      (json['parts'] as List).first['path'] = '../outside.part001';
      output.put(result.manifestPath, utf8.encode(jsonEncode(json)));
      await expectLater(
        FileSplitService.combineFromManifest(
          source: destination,
          manifestFile: (await destination.stat(result.manifestPath))!,
          destination: source,
          outputPath: '/combined.bin',
        ),
        throwsFormatException,
      );
    },
  );

  test('existing output and part collisions are never overwritten', () async {
    output.put('/data.bin.part003', [99]);
    await expectLater(split(), throwsStateError);
    expect(output.files.keys, ['/data.bin.part003']);
    output.files.clear();
    final result = await split();
    input.put('/combined.bin', [77]);
    await expectLater(
      FileSplitService.combineFromManifest(
        source: destination,
        manifestFile: (await destination.stat(result.manifestPath))!,
        destination: source,
        outputPath: '/combined.bin',
      ),
      throwsStateError,
    );
    expect(input.files['/combined.bin'], [77]);
  });

  test('empty source has one verified zero-byte part', () async {
    input.put('/data.bin', []);
    final result = await split();
    expect(result.manifest.parts.single.size, 0);
    expect(output.files[result.partPaths.single], isEmpty);
    await FileSplitService.combineFromManifest(
      source: destination,
      manifestFile: (await destination.stat(result.manifestPath))!,
      destination: source,
      outputPath: '/combined.bin',
    );
    expect(input.files['/combined.bin'], isEmpty);
  });

  test(
    'legacy commander parts require explicit consent and contiguous indices',
    () async {
      output.put('/legacy.001', [1, 2]);
      output.put('/legacy.003', [3, 4]);
      final files = [
        (await destination.stat('/legacy.001'))!,
        (await destination.stat('/legacy.003'))!,
      ];
      await expectLater(
        FileSplitService.combineLegacy(
          source: destination,
          files: files,
          destination: source,
          outputPath: '/legacy',
          allowUnverifiedLegacy: false,
        ),
        throwsStateError,
      );
      await expectLater(
        FileSplitService.combineLegacy(
          source: destination,
          files: files,
          destination: source,
          outputPath: '/legacy',
          allowUnverifiedLegacy: true,
        ),
        throwsStateError,
      );
      output.put('/legacy.002', [3, 4]);
      await FileSplitService.combineLegacy(
        source: destination,
        files: [(await destination.stat('/legacy.002'))!, files.first],
        destination: source,
        outputPath: '/legacy',
        allowUnverifiedLegacy: true,
      );
      expect(input.files['/legacy'], [1, 2, 3, 4]);
    },
  );

  test('source account loss never reads a replacement account', () async {
    await expectLater(
      split(onProgress: (_, _, _) => input.current = false),
      throwsStateError,
    );
    final manifest = await FileSplitService.readManifest(
      destination,
      (await destination.stat('/data.bin.split.json'))!,
    );
    expect(manifest.status, SplitManifestStatus.failed);
    expect(manifest.parts, isEmpty);
    expect(output.files['/data.bin.part001'], isNull);
  });
}
