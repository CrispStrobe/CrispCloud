import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_endpoint_policy.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_endpoint_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared local metadata cannot grant archive write capability', () async {
    // The independent reader accepts distinct central names sharing one local
    // record. Repeated scanning of its large extra range must not be permitted.
    final bytes = _storedZip(_localRecord('entry0', _emptyExtras(65532)), [
      for (var index = 0; index < 32; index++) ('entry$index', 0),
    ]);
    await _expectReadOnly(
      bytes,
      count: 32,
      firstName: 'entry0',
      firstContents: const [],
      replaceName: 'entry31',
    );
  });

  test('overlapping local metadata cannot grant archive write capability', () async {
    // The second complete local record is inside an opaque extra of the first.
    // Their own names and field boundaries are valid, but their ranges overlap.
    final second = _localRecord('second', _emptyExtras(64));
    final extra = Uint8List(4 + second.length);
    ByteData.sublistView(extra)
      ..setUint16(0, 0xcafe, Endian.little)
      ..setUint16(2, second.length, Endian.little);
    extra.setRange(4, extra.length, second);
    final first = _localRecord('first', extra);
    final secondOffset = 30 + utf8.encode('first').length + 4;
    final bytes = _storedZip(first, [('first', 0), ('second', secondOffset)]);
    await _expectReadOnly(
      bytes,
      count: 2,
      firstName: 'first',
      firstContents: const [],
      replaceName: 'second',
    );
  });

  for (final strongMarker in [false, true]) {
    test(
      strongMarker
          ? 'strong encryption marker without the ordinary flag is refused after a valid member'
          : 'AES method with missing encryption flag and another strength is refused after a valid member',
      () async {
        final bytes = await _encryptedZip();
        final data = ByteData.sublistView(bytes);
        final first = data.getUint32(bytes.length - 6, Endian.little);
        final second = _nextCentral(data, first);
        expect(data.getUint32(second, Endian.little), 0x02014b50);
        final flags = data.getUint16(second + 8, Endian.little);
        data.setUint16(
          second + 8,
          (flags & ~1) | (strongMarker ? 0x40 : 0),
          Endian.little,
        );
        if (strongMarker) {
          data.setUint16(second + 10, 0, Endian.little);
        } else {
          final extra =
              second + 46 + data.getUint16(second + 28, Endian.little);
          expect(data.getUint16(extra, Endian.little), 0x9901);
          bytes[extra + 8] = 1;
        }

        // The first protected member still authenticates. Merely checking it
        // must not authorize replacement of the later malformed member.
        await _expectReadOnly(
          bytes,
          count: 2,
          firstName: 'first',
          firstContents: const [1, 2, 3],
          replaceName: 'second',
          password: 'original-secret',
          encrypted: true,
        );
      },
    );
  }
}

Future<void> _expectReadOnly(
  Uint8List bytes, {
  required int count,
  required String firstName,
  required List<int> firstContents,
  required String replaceName,
  String? password,
  bool encrypted = false,
}) async {
  final original = Uint8List.fromList(bytes);
  final archive = await openViewerArchive(
    bytes,
    name: 'malformed.zip',
    password: password,
  );
  try {
    expect(archive.members.length, count);
    expect(archive.members.first.name, firstName);
    expect(
      archive.members.every((member) => member.isEncrypted == encrypted),
      isTrue,
    );
    expect(await archive.readMember(archive.members.first), firstContents);
    final policy = await ArchiveEndpointPolicy.inspect(
      bytes,
      'malformed.zip',
      archive,
      password,
    );
    expect(policy.format, ArchiveEndpointFormat.zip);
    expect(policy.encrypted, encrypted);
    expect(policy.reason, isNotNull);
    expect(bytes, original);
  } finally {
    await archive.close();
  }

  final backend = ArchiveEndpointTestBackend()
    ..put('/out/malformed.zip', bytes);
  final journal = ArchivePublicationJournal(
    storage: MemoryFileCollectionStorage(),
  );
  final workspace = await ArchiveWorkspace.open(
    backend,
    (await backend.stat('/out/malformed.zip'))!,
    password: password,
    journal: journal,
  );
  try {
    expect(workspace.canUpdate, isFalse);
    expect(workspace.endpointCapabilities.supportsMemberWrites, isFalse);
    expect(await workspace.read('/$firstName'), firstContents);
    expect(
      () => workspace.replace('/$replaceName', Uint8List.fromList([9])),
      throwsUnsupportedError,
    );
    await expectLater(workspace.review(), throwsUnsupportedError);
    expect(workspace.dirty, isFalse);
    expect(backend.files, {'/out/malformed.zip': original});
    expect(backend.mutations, isEmpty);
    expect(journal.records, isEmpty);
  } finally {
    await workspace.close();
  }
}

Uint8List _emptyExtras(int length) {
  assert(length % 4 == 0);
  final bytes = Uint8List(length);
  final data = ByteData.sublistView(bytes);
  for (var offset = 0; offset < length; offset += 4) {
    data.setUint16(offset, 0xcafe, Endian.little);
  }
  return bytes;
}

Uint8List _localRecord(String name, Uint8List extra) {
  final encoded = utf8.encode(name);
  final bytes = Uint8List(30 + encoded.length + extra.length);
  ByteData.sublistView(bytes)
    ..setUint32(0, 0x04034b50, Endian.little)
    ..setUint16(4, 20, Endian.little)
    ..setUint16(6, 0x800, Endian.little)
    ..setUint16(12, 0x21, Endian.little)
    ..setUint16(26, encoded.length, Endian.little)
    ..setUint16(28, extra.length, Endian.little);
  bytes.setRange(30, 30 + encoded.length, encoded);
  bytes.setRange(30 + encoded.length, bytes.length, extra);
  return bytes;
}

/// An independent stored-empty-file layout keeps malformed local references
/// precise without depending on a writer agreeing to emit them.
Uint8List _storedZip(Uint8List locals, List<(String, int)> entries) {
  final output = BytesBuilder(copy: false)..add(locals);
  for (final (name, local) in entries) {
    final encoded = utf8.encode(name);
    final record = Uint8List(46);
    ByteData.sublistView(record)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x800, Endian.little)
      ..setUint16(14, 0x21, Endian.little)
      ..setUint16(28, encoded.length, Endian.little)
      ..setUint32(42, local, Endian.little);
    output.add(record);
    output.add(encoded);
  }
  final end = Uint8List(22);
  ByteData.sublistView(end)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, output.length - locals.length, Endian.little)
    ..setUint32(16, locals.length, Endian.little);
  output.add(end);
  return output.takeBytes();
}

int _nextCentral(ByteData data, int offset) =>
    offset +
    46 +
    data.getUint16(offset + 28, Endian.little) +
    data.getUint16(offset + 30, Endian.little) +
    data.getUint16(offset + 32, Endian.little);

Future<Uint8List> _encryptedZip() async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: const koni.ZipWriteFormat(),
    options: const koni.ArchiveWriteOptions(password: 'original-secret'),
  );
  for (final name in ['first', 'second']) {
    await writer.addBytes(
      koni.ArchiveEntrySpec(path: name),
      Uint8List.fromList([1, 2, 3]),
    );
  }
  await writer.close();
  await sink.close();
  return sink.takeBytes();
}
