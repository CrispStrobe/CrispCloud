import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_iso_fixtures.dart';
import 'support/archive_package_fixtures.dart';
import 'support/archive_workflow_backend.dart';
import 'support/hfs_fixture.dart';

const _message = 'Package payload contents\n';

Uint8List _zip() => Uint8List.fromList(
  ar.ZipEncoder().encode(
    ar.Archive()
      ..addFile(ar.ArchiveFile.bytes('docs/hello.txt', utf8.encode(_message)))
      ..addFile(ar.ArchiveFile.bytes('empty.bin', const <int>[])),
  ),
);

Uint8List _crx(Uint8List payload, {int version = 3}) {
  // Dummy opaque signature/header bytes, deliberately not a signed extension.
  // A reader may expose ZIP contents but must not imply publisher validation.
  final extensionHeader = version == 2
      ? List.filled(17, 0x51)
      : List.filled(9, 0x63);
  final header = ByteData(version == 2 ? 16 : 12)
    ..setUint32(0, 0x34327243, Endian.little)
    ..setUint32(4, version, Endian.little);
  if (version == 2) {
    header.setUint32(8, 7, Endian.little);
    header.setUint32(12, 10, Endian.little);
  } else {
    header.setUint32(8, extensionHeader.length, Endian.little);
  }
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...extensionHeader,
    ...payload,
  ]);
}

Future<void> _expectPackageContents(ViewerArchive archive) async {
  expect(archive.formatName, 'zip');
  expect(
    archive.members.map((member) => member.name),
    containsAll(['docs/hello.txt', 'empty.bin']),
  );
  final text = archive.members.singleWhere(
    (member) => member.name == 'docs/hello.txt',
  );
  expect(utf8.decode(await archive.readMember(text)), _message);
}

class _OwnedSource implements koni.ByteSource {
  _OwnedSource(this.bytes, {this.failRead = false});
  final Uint8List bytes;
  final bool failRead;
  final reads = <(int, int)>[];
  bool closed = false;
  int releases = 0;
  @override
  int get length => bytes.length;
  @override
  String? get name => 'owned-input';
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (closed) throw StateError('Read after close');
    reads.add((offset, length));
    if (failRead) throw StateError('Injected input failure');
    if (offset < 0 ||
        length < 0 ||
        offset > bytes.length ||
        length > bytes.length - offset) {
      throw StateError('Reader attempted an out-of-bounds read');
    }
    return Uint8List.sublistView(bytes, offset, offset + length);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    releases++;
  }
}

void main() {
  for (final version in [2, 3]) {
    test(
      'CRX$version reads its ZIP slice without claiming signature verification',
      () async {
        final source = _OwnedSource(_crx(_zip(), version: version));
        final archive = await openViewerArchiveSource(
          source,
          name: 'extension.crx',
        );
        await _expectPackageContents(archive);
        expect(
          archive.notices.join(' '),
          contains('signatures are not verified'),
        );
        expect(source.closed, isFalse);
        await archive.close();
        await archive.close();
        expect(source.releases, 1);
      },
    );
  }

  test(
    'CRX3 allows an empty opaque header before a complete ZIP payload',
    () async {
      final header = ByteData(12)
        ..setUint32(0, 0x34327243, Endian.little)
        ..setUint32(4, 3, Endian.little);
      final archive = await openViewerArchive(
        Uint8List.fromList([...header.buffer.asUint8List(), ..._zip()]),
        name: 'extension.crx',
      );
      addTearDown(archive.close);
      await _expectPackageContents(archive);
    },
  );

  final badCrx = <String, Uint8List Function()>{
    'truncated fixed header': () => Uint8List.fromList(ascii.encode('Cr24')),
    'unsupported version': () {
      final bytes = _crx(_zip());
      ByteData.sublistView(bytes).setUint32(4, 4, Endian.little);
      return bytes;
    },
    'CRX2 overflowing declared key and signature lengths': () {
      final bytes = _crx(_zip(), version: 2);
      ByteData.sublistView(bytes)
        ..setUint32(8, 0xffffffff, Endian.little)
        ..setUint32(12, 0xffffffff, Endian.little);
      return bytes;
    },
    'CRX3 oversized declared header': () {
      final bytes = _crx(_zip());
      ByteData.sublistView(bytes).setUint32(8, 17 * 1024 * 1024, Endian.little);
      return bytes;
    },
    'CRX3 header extends beyond input': () {
      final bytes = _crx(_zip());
      ByteData.sublistView(bytes).setUint32(8, bytes.length, Endian.little);
      return bytes;
    },
    'missing ZIP payload': () => _crx(Uint8List(0)),
    'non-ZIP payload': () =>
        _crx(Uint8List.fromList(utf8.encode('plain-text payload'))),
    'truncated ZIP payload': () =>
        _crx(Uint8List.fromList([0x50, 0x4b, 3, 4, 0, 0, 0, 0])),
  };
  for (final example in badCrx.entries) {
    test('rejects ${example.key} and releases its input', () async {
      final source = _OwnedSource(example.value());
      await expectLater(
        openViewerArchiveSource(source, name: 'extension.crx'),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.releases, 1);
      expect(
        source.reads.every((read) => read.$1 + read.$2 <= source.length),
        isTrue,
      );
    });
  }

  for (final name in [
    'misnamed.iso',
    'misnamed.dmg',
    'misnamed.cpio',
    'misnamed.xar',
  ]) {
    test('ZIP bytes take priority over $name', () async {
      final archive = await openViewerArchive(_zip(), name: name);
      addTearDown(archive.close);
      await _expectPackageContents(archive);
    });
  }

  test('ISO bytes take priority over a misleading DMG suffix', () async {
    final archive = await openViewerArchive(
      IsoFixture().bytes,
      name: 'misnamed.dmg',
    );
    addTearDown(archive.close);
      expect(archive.formatName, 'iso');
    final text = archive.members.singleWhere(
      (entry) => entry.name == 'HELLO.TXT',
    );
    expect(utf8.decode(await archive.readMember(text)), 'hello iso');
  });

  test('HFS bytes take priority over a misleading ISO suffix', () async {
    final archive = await openViewerArchive(
      HfsFixture().bytes,
      name: 'misnamed.iso',
    );
    addTearDown(archive.close);
    expect(archive.formatName, 'hfs+');
    final text = archive.members.singleWhere(
      (entry) => entry.name == 'hello.txt',
    );
    expect(await archive.readMember(text), HfsFixture.helloBytes);
  });

  final codecs = <String, Uint8List Function(List<int>)>{
    'gzip': (bytes) => Uint8List.fromList(const ar.GZipEncoder().encode(bytes)),
    'bzip2': (bytes) => Uint8List.fromList(ar.BZip2Encoder().encode(bytes)),
    'xz': (bytes) => Uint8List.fromList(ar.XZEncoder().encode(bytes)),
    'zstd': (bytes) => Uint8List.fromList(ar.ZstdEncoder().encode(bytes)),
  };
  for (final codec in codecs.entries) {
    for (final container in <String, Uint8List Function()>{
      'cpio': referenceNewc,
      'xar': referenceXar,
    }.entries) {
      test(
        '${codec.key}-compressed ${container.key} is discovered from bytes without a suffix',
        () async {
          final source = _OwnedSource(codec.value(container.value()));
          final archive = await openViewerArchiveSource(
            source,
            name: 'download.bin',
          );
          addTearDown(archive.close);
          expect(
            source.closed,
            isTrue,
            reason: 'buffered codec must release original source',
          );
          expect(archive.formatName, container.key);
          final text = archive.members.singleWhere(
            (entry) => entry.name == 'docs/hello.txt',
          );
          expect(
            utf8.decode(await archive.readMember(text)),
            'Independent container fixture\n',
          );
        },
      );
    }
  }

  test('compressed CRX is discovered after decoding without relying on the inner filename', () async {
    final archive = await openViewerArchive(
      Uint8List.fromList(const ar.GZipEncoder().encode(_crx(_zip()))),
      name: 'bundle.gz',
    );
    addTearDown(archive.close);
    await _expectPackageContents(archive);
  });

  test(
    'XAR payload can be opened as CPIO without writing an intermediate file',
    () async {
      final package = await openViewerArchive(
        xarMemberFixture(
          referenceNewc(),
          name: 'Payload',
          encoding: 'application/x-gzip',
        ),
        name: 'installer.pkg',
      );
      addTearDown(package.close);
      final payload = package.members.single;
      final inner = await openViewerArchive(
        await package.readMember(payload),
        name: payload.name,
      );
      addTearDown(inner.close);
      expect(inner.formatName, 'cpio');
      final text = inner.members.singleWhere(
        (entry) => entry.name == 'docs/hello.txt',
      );
      expect(
        utf8.decode(await inner.readMember(text)),
        'Independent container fixture\n',
      );
    },
  );

  test(
    'nested codec wrappers are bounded and release the outer source',
    () async {
      var bytes = _zip();
      for (var i = 0; i < 4; i++) {
        bytes = Uint8List.fromList(const ar.GZipEncoder().encode(bytes));
      }
      final allowed = await openViewerArchive(bytes, name: 'four-wrappers.gz');
      await _expectPackageContents(allowed);
      await allowed.close();
      final rejected = _OwnedSource(
        Uint8List.fromList(const ar.GZipEncoder().encode(bytes)),
      );
      await expectLater(
        openViewerArchiveSource(rejected, name: 'five-wrappers.gz'),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(rejected.closed, isTrue);
    },
  );

  test(
    'codec output and buffered input limits apply before nested decoding',
    () async {
      final wrapped = Uint8List.fromList(
        const ar.GZipEncoder().encode(referenceNewc()),
      );
      for (final inputLimit in [true, false]) {
        final source = _OwnedSource(wrapped);
        await expectLater(
          openViewerArchiveSource(
            source,
            name: 'payload.cpio.gz',
            maxMemberBytes: inputLimit ? 1024 : 16,
            maxBufferedContainerBytes: inputLimit ? 16 : 1024,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.closed, isTrue);
      }
    },
  );

  test('input errors and invalid limits close the owned source', () async {
    final failing = _OwnedSource(_zip(), failRead: true);
    await expectLater(
      openViewerArchiveSource(failing, name: 'input.zip'),
      throwsStateError,
    );
    expect(failing.closed, isTrue);
    final invalid = _OwnedSource(_zip());
    await expectLater(
      openViewerArchiveSource(invalid, name: 'input.zip', maxMemberBytes: 0),
      throwsArgumentError,
    );
    expect(invalid.closed, isTrue);
  });

  for (final suffix in ['apk', 'whl', 'msix', 'crx']) {
    test(
      '$suffix contents remain readable while workspace refuses repacking',
      () async {
        final original = suffix == 'crx' ? _crx(_zip()) : _zip();
        final client = ArchiveWorkflowClient()
          ..put('/package.$suffix', original);
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
          () => workspace.replace('/docs/hello.txt', Uint8List.fromList([1])),
          throwsUnsupportedError,
        );
        expect(workspace.dirty, isFalse);
        expect(client.writes, isEmpty);
        expect(client.files['/package.$suffix'], original);
      },
    );
  }

  test('package aliases extract validated files through the normal extraction service', () async {
    final directory = await Directory.systemTemp.createTemp(
      'crisp-archive-alias-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final extracted = await ArchiveService.extractArchiveBytes(
      'package.apk',
      _zip(),
      directory.path,
    );
    expect(extracted, hasLength(2));
    expect(
      await File('${directory.path}/docs/hello.txt').readAsString(),
      _message,
    );
    expect(await File('${directory.path}/empty.bin').length(), 0);
  });
}
