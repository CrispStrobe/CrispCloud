// Execute the newly implemented codec in JavaScript, comparing exact output
// against original fixtures independently decoded by gzip and libarchive.
// ignore_for_file: avoid_print
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_unix_compress_codec.dart';

import 'archive_unix_compress_writer_fixtures.dart';

void main() {
  const expected = <String, String>{
    'empty-12.Z':
        'ec243afa8ebdd414e8719086e484730e19a28262eead0732bcb5fd95c3e798f3',
    'empty-14.Z':
        'df24d6734ed06884b591e676254c55eeac68d359a7b18fcbe5c03d48d98c028e',
    'empty-16.Z':
        '7aa6f58a0a8f57b9e6a70d89961f4668b7d69eb177a8da8344d4e5ed12d7858e',
    'byte-12.Z':
        'bf5c3966b94c0314ca3e3632a32beaa86f9a2048d2a79069de31eea535b1990c',
    'byte-14.Z':
        '4fa5550abe67248d38129ddc482f55f38e9686f11cc16c65d7459e6e01c4f377',
    'byte-16.Z':
        '93690bd4d3ac8cc55468cc93cf80abc094991a9dad81f27884cf704fd397c879',
    'width-boundary-12.Z':
        '4b68a4de7720ebdf2217c746ee35dec825acb3980bdfcbf48b0b21dd45a929e2',
    'width-boundary-14.Z':
        '245cd39fed8aca1b88d5075fa35c07a41696f91da27760fd3291ff0576544e4c',
    'width-boundary-16.Z':
        '2d79d7c0c7561562e357cbf9cbf2d60007ace7fea264a002d295ddf0f7b9937f',
    'phrases-12.Z':
        '58298db9524a24f1076845732802e5a239b31cbf33fc5b98b7bc94457a2fbca3',
    'phrases-14.Z':
        '52135031a6f66887380ac7cc779e3a3dfd58b475c8d894a48bfc7434958b95a4',
    'phrases-16.Z':
        '6ba9545fa982d4a0157a4b04b1a82c27b44b3203e51c06153e0b6d9b78663b6a',
    'text-12.Z':
        '54c5d60b11fe58c7f054d757697602b890f9157470411443bf69371461419a35',
    'text-14.Z':
        'df81a9b71b1ea10f46dd14915a851a575cc070f640ae736478b1441e42e35858',
    'text-16.Z':
        'ef8da8b6809e9231c524b030eecb169db766db748b24b44c76b7687a411b947f',
    'noise-reset-12.Z':
        'f79f3055e1f95fff863d1f911bf391dda1d9a935a04f823fa4d6376308af5123',
    'noise-reset-14.Z':
        '3a58b14c51e50df91810a4ef10227b8f2ce328223a6761bb9697e5286016029c',
    'noise-reset-16.Z':
        '45497e9e17543117b1e101145c22b92b5148ff7748baa5a8613f9a33a3531f0a',
  };
  var checked = 0;
  for (final payload in unixCompressWriterPayloads().entries) {
    for (final width in [12, 14, 16]) {
      final name = '${payload.key}-$width.Z';
      final bytes = encodeArchiveUnixCompress(payload.value, maxBits: width);
      if (sha256.convert(bytes).toString() != expected[name]) {
        throw StateError('Portable $name differs from native-verified output.');
      }
      final decoded = decodeArchiveUnixCompress(bytes);
      if (sha256.convert(decoded) != sha256.convert(payload.value)) {
        throw StateError('Portable $name decoded payload differs.');
      }
      checked++;
    }
  }
  print(
    'All $checked native-verified UNIX compress profiles passed in JavaScript.',
  );
}
