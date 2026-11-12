import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_endpoint_policy.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_cab_fixtures.dart';
import 'support/archive_package_fixtures.dart';
import 'support/archive_pbzx_fixtures.dart';
import 'support/archive_rpm_fixtures.dart';
import 'support/archive_workflow_backend.dart';

const _message = 'hello\n';

Uint8List _cab({String name = 'docs/hello.txt'}) => cabFixture([
  CabFixtureFolder([CabFixtureFile(name, utf8.encode(_message))], method: 1),
]);

Uint8List _pbzx() => pbzxFixture(
  [
    cpioFixture([PackageFixtureEntry('docs/hello.txt', utf8.encode(_message))]),
  ],
  compressedChunks: {0},
);

void main() {
  final formats = <String, ({String format, Uint8List Function() bytes})>{
    'cab': (format: 'cab', bytes: _cab),
    'rpm': (format: 'rpm', bytes: () => RpmFixture().bytes),
    'pbzx': (format: 'pbzx/cpio', bytes: _pbzx),
  };
  for (final entry in formats.entries) {
    final suffix = entry.key;
    final sample = entry.value;
    test(
      '$suffix routes by signature even under a misleading writable suffix',
      () async {
        final bytes = sample.bytes();
        for (final name in ['archive.$suffix', 'misnamed.zip', 'Payload']) {
          final archive = await openViewerArchive(bytes, name: name);
          addTearDown(archive.close);
          expect(archive.formatName, sample.format);
          final member = archive.members.singleWhere(
            (m) => m.name == 'docs/hello.txt',
          );
          expect(utf8.decode(await archive.readMember(member)), _message);
          final policy = await ArchiveEndpointPolicy.inspect(
            bytes,
            name,
            archive,
            null,
          );
          expect(
            policy.reason,
            isNotNull,
            reason: 'a filename must not grant a writer',
          );
        }
      },
    );

    test(
      '$suffix is detected inside a gzip wrapper with an opaque inner name',
      () async {
        final archive = await openViewerArchive(
          Uint8List.fromList(const codec.GZipEncoder().encode(sample.bytes())),
          name: 'opaque.gz',
        );
        addTearDown(archive.close);
        expect(archive.formatName, sample.format);
        final member = archive.members.singleWhere(
          (m) => m.name == 'docs/hello.txt',
        );
        expect(utf8.decode(await archive.readMember(member)), _message);
      },
    );

    test(
      '$suffix extracts through the existing validated operation service',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'crisp-package-extract-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final files = await ArchiveService.extractArchiveBytes(
          'archive.$suffix',
          sample.bytes(),
          directory.path,
          selectedPaths: {'docs'},
        );
        expect(files, contains('${directory.path}/docs/hello.txt'));
        expect(
          await File('${directory.path}/docs/hello.txt').readAsString(),
          _message,
        );
      },
    );

    test(
      '$suffix workspace is read-only and cannot stage or publish replacements',
      () async {
        final bytes = sample.bytes();
        final client = ArchiveWorkflowClient()..put('/package.$suffix', bytes);
        final backend = ArchiveWorkflowBackend(client, isCurrent: () => true);
        final workspace = await ArchiveWorkspace.open(
          backend,
          (await backend.stat('/package.$suffix'))!,
        );
        addTearDown(workspace.close);
        expect(
          workspace.endpointCapabilities.format,
          ArchiveEndpointFormat.readOnly,
        );
        expect(workspace.canUpdate, isFalse);
        expect(utf8.decode(await workspace.read('/docs/hello.txt')), _message);
        expect(
          () => workspace.replace('/docs/hello.txt', Uint8List(1)),
          throwsUnsupportedError,
        );
        expect(workspace.dirty, isFalse);
        expect(client.writes, isEmpty);
        expect(client.files['/package.$suffix'], bytes);
      },
    );
  }

  test('F3 recognizes extensionless package and portable CPIO signatures', () {
    const viewer = InternalViewerService();
    for (final bytes in [
      _cab(),
      RpmFixture().bytes,
      _pbzx(),
      File('test/fixtures/archives/reference-odc.cpio').readAsBytesSync(),
    ]) {
      expect(
        viewer.detectMode(
          'Payload',
          header: Uint8List.sublistView(bytes, 0, 16),
        ),
        ViewerMode.archive,
      );
    }
  });

  for (final fixture in [
    'reference-odc.pbzx',
    'reference-odc-unchecked.pbzx',
  ]) {
    test(
      'opens independent $fixture and reads CPIO headers crossing chunks',
      () async {
        final bytes = File('test/fixtures/archives/$fixture').readAsBytesSync();
        final archive = await openViewerArchive(bytes, name: 'Payload');
        addTearDown(archive.close);
        expect(archive.formatName, 'pbzx/cpio');
        expect(archive.members.map((m) => m.name), [
          'docs',
          'docs/hello.txt',
          'docs/odd',
        ]);
        expect(
          utf8.decode(await archive.readMember(archive.members[1])),
          'Independent portable CPIO fixture\n',
        );
        expect(
          utf8.decode(await archive.readMember(archive.members[2])),
          'odd',
        );
        expect(archive.notices.join(' '), contains('CHECK_NONE'));
      },
    );
  }

  test('a PKG Payload preview opens its PBZX/ODC file tree', () async {
    final payload = File('test/fixtures/archives/reference-odc.pbzx')
        .readAsBytesSync();
    final outer = await openViewerArchive(
      xarMemberFixture(payload, name: 'Payload'),
      name: 'installer.pkg',
    );
    addTearDown(outer.close);
    final member = outer.members.single;
    final innerBytes = await outer.readMember(member);
    expect(
      const InternalViewerService().detectMode(member.name, header: innerBytes),
      ViewerMode.archive,
    );
    final inner = await openViewerArchive(innerBytes, name: member.name);
    addTearDown(inner.close);
    expect(inner.formatName, 'pbzx/cpio');
    expect(utf8.decode(await inner.readMember(inner.members.last)), 'odd');
    expect(
      outer.notices.join(' '),
      contains('Publisher signatures are not verified'),
    );
  });

  test(
    'PBZX exposes an unknown payload without inventing an archive format',
    () async {
      final archive = await openViewerArchive(
        pbzxFixture([utf8.encode('plain text')]),
        name: 'notes.txt.pbzx',
      );
      addTearDown(archive.close);
      expect(archive.formatName, 'pbzx');
      expect(archive.members.single.name, 'notes.txt');
      expect(
        utf8.decode(await archive.readMember(archive.members.single)),
        'plain text',
      );
    },
  );

  test('PBZX and other compression share the nesting-depth guard', () async {
    var bytes = _pbzx();
    for (var i = 0; i < 4; i++) {
      bytes = pbzxFixture([bytes]);
    }
    await expectLater(
      openViewerArchive(bytes, name: 'nested.pbzx'),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test(
    'new readers retain extraction traversal guards and safe-subset selection',
    () async {
      final cpio = cpioFixture([
        const PackageFixtureEntry('../outside', [1]),
        const PackageFixtureEntry('safe.txt', [2]),
      ]);
      final examples = <String, Uint8List>{
        'bad.cab': cabFixture([
          const CabFixtureFolder([
            CabFixtureFile('../outside', [1]),
            CabFixtureFile('safe.txt', [2]),
          ]),
        ]),
        'bad.rpm': RpmFixture(payload: cpio).bytes,
        'bad.pbzx': pbzxFixture([cpio]),
      };
      for (final example in examples.entries) {
        final directory = await Directory.systemTemp.createTemp(
          'crisp-package-unsafe-',
        );
        addTearDown(() => directory.delete(recursive: true));
        await expectLater(
          ArchiveService.extractArchiveBytes(
            example.key,
            example.value,
            directory.path,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(
          await directory.list().length,
          0,
          reason: 'validate all selected paths before writing',
        );
        await ArchiveService.extractArchiveBytes(
          example.key,
          example.value,
          directory.path,
          selectedPaths: {'safe.txt'},
        );
        expect(await File('${directory.path}/safe.txt').readAsBytes(), [2]);
      }
    },
  );
}
