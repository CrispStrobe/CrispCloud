import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_compression_writer.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_endpoint_policy.dart';
import 'package:crisp_cloud/services/archive_unix_compress_codec.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_creation_backend.dart';
import 'support/archive_workflow_backend.dart';

void main() {
  for (final format in [
    ArchiveCreationFormat.compress,
    ArchiveCreationFormat.tarCompress,
  ]) {
    for (final profile in [
      (ArchiveCreationCompression.fast, 12),
      (ArchiveCreationCompression.normal, 14),
      (ArchiveCreationCompression.maximum, 16),
    ]) {
      test(
        '${format.name} creation honors ${profile.$1.name} dictionary',
        () async {
          final backend = ArchiveCreationBackend()
            ..put('/input/data.txt', utf8.encode('original source\n' * 1000));
          final result = await const ArchiveCreationService().create(
            source: backend,
            destination: backend,
            files: [(await backend.stat('/input/data.txt'))!],
            destinationDirectory: '/output',
            options: ArchiveCreationOptions(
              name: 'result${format.extension}',
              format: format,
              compression: profile.$1,
            ),
          );
          final bytes = backend.contents[result.path]!;
          expect(bytes.sublist(0, 3), [0x1f, 0x9d, 0x80 | profile.$2]);
          final opened = await openViewerArchive(bytes, name: result.path);
          addTearDown(opened.close);
          expect(
            await opened.readMember(opened.members.single),
            utf8.encode('original source\n' * 1000),
          );
          expect(backend.writes, [result.path]);
        },
      );
    }
    test('${format.name} rejects Store and password options', () {
      for (final options in [
        ArchiveCreationOptions(
          name: 'result${format.extension}',
          format: format,
          compression: ArchiveCreationCompression.none,
        ),
        ArchiveCreationOptions(
          name: 'result${format.extension}',
          format: format,
          password: 'unsupported',
        ),
      ]) {
        expect(
          () => options.validate(),
          throwsA(isA<ArchiveCreationException>()),
        );
      }
    });
    test('${format.name} accepts either extension case', () {
      for (final suffix in [format.extension, format.extension.toLowerCase()]) {
        expect(
          () => ArchiveCreationOptions(
            name: 'result$suffix',
            format: format,
          ).validate(),
          returnsNormally,
        );
      }
    });
  }

  for (final fixture in [
    'empty',
    'text',
    'width-clear',
    'nine-bit',
    'nonblock',
    'clear',
  ]) {
    test(
      'independent $fixture stream rewrites to canonical block coding',
      () async {
        final source = File(
          'test/fixtures/archives/compress-reference-$fixture.Z',
        ).readAsBytesSync();
        final original = decodeArchiveUnixCompress(source);
        final path = '/payload.Z';
        final client = ArchiveWorkflowClient()..put(path, source);
        final backend = ArchiveWorkflowBackend(client, isCurrent: () => true);
        final workspace = await ArchiveWorkspace.open(
          backend,
          (await backend.stat(path))!,
        );
        addTearDown(workspace.close);
        expect(workspace.canUpdate, isTrue, reason: workspace.updateSupport);
        expect(
          workspace.endpointCapabilities.format,
          ArchiveEndpointFormat.compress,
        );
        expect(workspace.endpointCapabilities.supportsModifiedTime, isFalse);
        expect(workspace.endpointCapabilities.supportsPermissions, isFalse);
        expect(await workspace.read('/payload'), original);
        final changed = Uint8List.fromList([
          ...original,
          ...utf8.encode('changed'),
        ]);
        workspace.replace('/payload', changed);
        final receipt = await workspace.save(
          reviewed: await workspace.review(),
        );
        expect(receipt!.record.phase, ArchivePublicationPhase.complete);
        expect(client.files[path]!.sublist(0, 3), [0x1f, 0x9d, 0x8e]);
        expect(decodeArchiveUnixCompress(client.files[path]!), changed);
        expect(client.files.keys, [path]);
        expect(workspace.canUpdate, isTrue);
      },
    );
  }

  test(
    'malformed physical flags and truncated codes refuse rewriting',
    () async {
      final valid = encodeArchiveUnixCompress(Uint8List.fromList([65]));
      final archive = await openViewerArchive(valid, name: 'payload.Z');
      addTearDown(archive.close);
      for (final invalid in [
        Uint8List.fromList(valid)..[2] |= 0x20,
        Uint8List.fromList(valid.sublist(0, 4)),
      ]) {
        expect(
          () => validateArchiveCompressionRewrite(
            invalid,
            ArchiveCompressionKind.compress,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        final policy = await ArchiveEndpointPolicy.inspect(
          invalid,
          'payload.Z',
          archive,
          null,
        );
        expect(policy.reason, isNotNull);
      }
    },
  );
}
