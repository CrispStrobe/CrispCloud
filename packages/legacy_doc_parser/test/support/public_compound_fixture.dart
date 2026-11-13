// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

const publicCompoundKinds = ['ole', 'vba'];
const publicCompoundMutations = [
  'valid',
  'not-compound',
  'missing-required-stream',
  'storage-instead-of-stream',
  'wrong-path',
  'truncated-stream',
];

List<String> publicCompoundMutationsFor(String kind) => [
  ...publicCompoundMutations,
  if (kind == 'ole') ...[
    'linked',
    'bad-version',
    'bad-flags',
    'bad-reserved',
    'bad-moniker',
  ],
];

Uint8List publicCompoundBytes(String kind, String mutation) {
  if (mutation == 'not-compound') return Uint8List.fromList([1, 2, 3]);
  final writer = CfbfWriter();
  if (kind == 'ole') {
    final record = Uint8List(20);
    final data = ByteData.sublistView(record);
    data.setUint32(0, 0x02000001, Endian.little);
    if (mutation == 'linked') data.setUint32(4, 1, Endian.little);
    if (mutation == 'bad-version') data.setUint32(0, 0, Endian.little);
    if (mutation == 'bad-flags') data.setUint32(4, 2, Endian.little);
    if (mutation == 'bad-reserved') data.setUint32(12, 1, Endian.little);
    if (mutation == 'bad-moniker') data.setUint32(16, 8, Endian.little);
    if (mutation == 'storage-instead-of-stream') {
      writer.addStorage('\x01Ole');
    } else if (mutation != 'missing-required-stream') {
      writer.addStream(
        mutation == 'wrong-path' ? 'Nested/\x01Ole' : '\x01Ole',
        record,
      );
    }
  } else {
    writer.addStream('PROJECT', [1]);
    writer.addStream('VBA/_VBA_PROJECT', [2]);
    if (mutation == 'storage-instead-of-stream') {
      writer.addStorage('VBA/dir');
    } else if (mutation != 'missing-required-stream') {
      writer.addStream(
        mutation == 'wrong-path' ? 'Nested/VBA/dir' : 'VBA/dir',
        [3],
      );
    }
  }
  writer.addStream('Payload', List<int>.filled(4096, 0x41));
  final bytes = writer.build();
  if (mutation == 'truncated-stream') {
    // The first regular stream is Payload. Its logical size still requires
    // eight sectors; its FAT chain now terminates after the first sector.
    final data = ByteData.sublistView(bytes);
    final fatSector = data.getUint32(76, Endian.little);
    data.setUint32((fatSector + 1) * 512, 0xfffffffe, Endian.little);
  }
  return bytes;
}

LegacyWordCompoundStorage publicCompoundStorage(
  String kind,
  String mutation, {
  Uint8List? rawBytes,
}) => LegacyWordCompoundStorage(
  sourcePath: kind == 'ole' ? 'ObjectPool/_1' : 'Macros',
  bytes: rawBytes ?? publicCompoundBytes(kind, mutation),
  // Intentionally plausible metadata: it cannot vouch for the distinct raw
  // container bytes that will be copied into the native package relationship.
  streams: [
    for (final path
        in kind == 'ole'
            ? ['\x01Ole', 'Payload']
            : ['PROJECT', 'VBA/dir', 'VBA/_VBA_PROJECT'])
      LegacyWordPreservedStream(path: path, bytes: Uint8List(1)),
  ],
  storages: const [],
);

LegacyWordDocument publicCompoundDocument(
  String kind,
  String mutation, {
  bool metadataAllowsEmbedding = true,
  Uint8List? rawBytes,
}) {
  final storage = publicCompoundStorage(kind, mutation, rawBytes: rawBytes);
  return LegacyWordDocument(
    blocks: const [
      LegacyWordParagraph(
        startCp: 0,
        endCp: 4,
        runs: [LegacyWordRun(startCp: 0, endCp: 3, text: 'A B')],
      ),
    ],
    sections: const [],
    plainText: 'A B',
    safeHtml: '',
    media: LegacyWordMediaCatalog.from(
      embeddedObjects: kind == 'ole'
          ? [
              LegacyWordEmbeddedObject(
                id: 'object-1',
                cp: 1,
                storage: storage,
                canEmbed: metadataAllowsEmbedding,
                linked: false,
              ),
            ]
          : const [],
      vbaProjects: kind == 'vba'
          ? [
              LegacyWordVbaProject(
                id: 'vba-1',
                storage: storage,
                hasRequiredStreams: metadataAllowsEmbedding,
              ),
            ]
          : const [],
    ),
  );
}
