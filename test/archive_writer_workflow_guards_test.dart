import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_compression_writer.dart';
import 'package:crisp_cloud/services/archive_package_writers.dart';
import 'package:crisp_cloud/services/archive_tar_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/archive_writer_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_creation_backend.dart';
import 'support/archive_package_fixtures.dart';
import 'support/archive_package_writer_fixtures.dart';
import 'support/archive_tar_writer_fixtures.dart';
import 'support/archive_workflow_backend.dart';

Future<
  ({
    ArchiveWorkspace workspace,
    ArchiveWorkflowClient client,
    ArchiveWorkflowBackend backend,
  })
>
_open(Uint8List bytes, String name) async {
  final client = ArchiveWorkflowClient()..put('/$name', bytes);
  final backend = ArchiveWorkflowBackend(client, isCurrent: () => true);
  final workspace = await ArchiveWorkspace.open(
    backend,
    (await backend.stat('/$name'))!,
  );
  return (workspace: workspace, client: client, backend: backend);
}

void main() {
  for (final suffix in ['deb', 'udeb']) {
    test(
      '$suffix requires paired prepared payloads and blocks nested editing',
      () async {
        final original = debianFixture();
        final opened = await _open(original.archive, 'package.$suffix');
        addTearDown(opened.workspace.close);
        final workspace = opened.workspace;
        expect(workspace.canUpdate, isTrue, reason: workspace.updateSupport);
        final nested = await ArchiveWorkspace.openNested(
          opened.backend,
          (await opened.backend.stat('/package.$suffix'))!,
          ['data.tar.gz'],
        );
        expect(nested.canUpdate, isFalse);
        expect(nested.updateSupport, contains('external package build'));
        expect(
          () => nested.replace(
            '/usr/share/crisp/data.txt',
            Uint8List.fromList([1]),
          ),
          throwsUnsupportedError,
        );
        await nested.close();
        for (final mutation in [
          () => workspace.remove(['debian-binary']),
          () => workspace.rename('data.tar.gz', 'changed.tar.gz'),
          () => workspace.createDirectory('folder'),
        ]) {
          expect(mutation, throwsA(isA<ArchiveViewException>()));
          expect(workspace.dirty, isFalse);
        }
        final replacement = debianFixture(text: 'prepared replacement\n');
        workspace.replace('data.tar.gz', replacement.data);
        await expectLater(
          workspace.review(),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(opened.client.files['/package.$suffix'], original.archive);
        workspace.replace('control.tar.gz', replacement.control);
        final review = await workspace.review();
        expect(opened.client.files['/package.$suffix'], original.archive);
        expect(await workspace.save(reviewed: review), isNotNull);
        expect(await workspace.read('/control.tar.gz'), replacement.control);
        expect(await workspace.read('/data.tar.gz'), replacement.data);
      },
    );
  }

  test('inconsistent paired Debian payloads retain the original', () async {
    final original = debianFixture();
    final opened = await _open(original.archive, 'package.deb');
    addTearDown(opened.workspace.close);
    final bad = debianFixture(text: 'changed', checksumFor: 'old');
    opened.workspace.replace('control.tar.gz', bad.control);
    opened.workspace.replace('data.tar.gz', bad.data);
    await expectLater(
      opened.workspace.review(),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(opened.client.files['/package.deb'], original.archive);
    expect(opened.client.writes, isEmpty);
  });

  test(
    'replacing an AR import retains its owner metadata on repeated saves',
    () async {
      final bytes = arFixture([
        PackageFixtureEntry('item.txt', utf8.encode('original'), mode: 0x1e8),
      ]);
      bytes.setRange(36, 42, ascii.encode('123   '));
      bytes.setRange(42, 48, ascii.encode('456   '));
      final opened = await _open(bytes, 'files.ar');
      addTearDown(opened.workspace.close);
      final source = ArchiveCreationBackend()
        ..put('/input/item.txt', utf8.encode('imported'));
      await opened.workspace.addFiles(source, [
        (await source.stat('/input/item.txt'))!,
      ], replaceExisting: true);
      await opened.workspace.save();
      opened.workspace.replace('item.txt', Uint8List.fromList([1, 2]));
      await opened.workspace.save();
      final packed = opened.client.files['/files.ar']!;
      final archive = await openViewerArchive(packed, name: 'files.ar');
      addTearDown(archive.close);
      final inspection = await inspectPackageRewrite(packed, 'ar', archive);
      expect(inspection.supported, isTrue, reason: inspection.reason);
      expect(inspection.attributes['item.txt']!['ar.uid'], 123);
      expect(inspection.attributes['item.txt']!['ar.gid'], 456);
      expect(archive.members.single.posixMode! & 0xfff, 0x1e8);
    },
  );

  for (final kind in ['ustar', 'gnu', 'pax']) {
    test(
      'TAR $kind metadata survives editing and a second publication',
      () async {
        final original = referenceTar(kind);
        final opened = await _open(original, 'archive.tar');
        addTearDown(opened.workspace.close);
        final reader = await openViewerArchive(original, name: 'archive.tar');
        addTearDown(reader.close);
        final before = await inspectTarRewrite(original, reader);
        expect(
          opened.workspace.canUpdate,
          isTrue,
          reason: opened.workspace.updateSupport,
        );
        final member = reader.members.firstWhere((member) => member.isFile);
        opened.workspace.replace(member.name, Uint8List.fromList([3, 4]));
        await opened.workspace.save();
        opened.workspace.replace(member.name, Uint8List.fromList([5]));
        await opened.workspace.save();
        final output = opened.client.files['/archive.tar']!;
        final afterReader = await openViewerArchive(
          output,
          name: 'archive.tar',
        );
        addTearDown(afterReader.close);
        final after = await inspectTarRewrite(output, afterReader);
        expect(after.supported, isTrue, reason: after.reason);
        for (final key in [
          'tar.uid',
          'tar.gid',
          'tar.uname',
          'tar.gname',
          'tar.gnuAtime',
          'tar.gnuCtime',
        ]) {
          expect(
            after.attributes[member.name]![key],
            before.attributes[member.name]![key],
            reason: key,
          );
        }
        final oldPax = before.attributes[member.name]!['tar.pax'] as Map?;
        final newPax = after.attributes[member.name]!['tar.pax'] as Map?;
        for (final key in ['mtime', 'atime', 'ctime']) {
          expect(newPax?[key], oldPax?[key], reason: key);
        }
      },
    );
  }

  test(
    'writer dispatch refuses mismatched wrapper requests before output',
    () async {
      var writes = 0;
      for (final pair in [
        (ArchiveEndpointFormat.zip, ArchiveCompressionKind.xz),
        (ArchiveEndpointFormat.tarXz, null),
        (ArchiveEndpointFormat.gzip, ArchiveCompressionKind.gzip),
      ]) {
        await expectLater(
          writeArchiveEntries(
            pair.$1,
            <ArchiveWriteEntry>[],
            compression: pair.$2,
            sink: (_) async {
              writes++;
            },
          ),
          throwsA(isA<ArchiveViewException>()),
        );
      }
      expect(writes, 0);
    },
  );
}
