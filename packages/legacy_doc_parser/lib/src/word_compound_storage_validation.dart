// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

/// Checks the immutable container that will actually be emitted. Public
/// metadata and separately preserved stream lists are not byte provenance.
/// This applies the reader's bounded structural policy, not full CFB, OLE or
/// VBA conformance or a claim that embedded code is safe to execute.
class _ConversionCompoundInspection {
  final _results =
      Map<LegacyWordCompoundStorage, _WordCompoundInspection?>.identity();
  var _bytesInspected = 0;

  _WordCompoundInspection? inspect(LegacyWordCompoundStorage storage) =>
      _results.putIfAbsent(storage, () {
        _bytesInspected += storage.bytes.length;
        if (_bytesInspected > kLegacyWordPackageLimit) _tooComplex();
        try {
          final reader = BoundedCfbReader(storage.bytes);
          final paths = <String>{};
          bool? linked;
          final pending = <(CfbfDirectoryEntry, String, int)>[
            (reader.root, '', 0),
          ];
          while (pending.isNotEmpty) {
            final (parent, prefix, depth) = pending.removeLast();
            if (depth > 32) return null;
            for (final entry in reader.childrenOf(parent)) {
              final path = '$prefix${entry.name.toUpperCase()}';
              if (entry.isStorage) {
                pending.add((entry, '$path/', depth + 1));
              } else {
                // Validate every reachable stream's actual allocation, even
                // when only its presence is relevant to project activation.
                final bytes = reader.readEntry(entry);
                paths.add(path);
                if (path == '\x01OLE') linked = _linkedOleStream(bytes);
              }
            }
          }
          return _WordCompoundInspection(
            linked: linked,
            hasRequiredVbaStreams: paths.containsAll({
              'PROJECT',
              'VBA/DIR',
              'VBA/_VBA_PROJECT',
            }),
          );
        } on FormatException {
          return null;
        } on CfbfException {
          return null;
        }
      });

  // MS-OLEDS 2.3.3, matching the existing binary parser's bounded identity
  // check. No link monikers are followed or executed. Only an embedded record
  // has an exact end after the optional reserved moniker.
  static bool? _linkedOleStream(Uint8List bytes) {
    if (bytes.length < 20) return null;
    final data = ByteData.sublistView(bytes);
    final flags = data.getUint32(4, Endian.little);
    final size = data.getUint32(16, Endian.little);
    final monikerBytes = size == 0 ? 0 : size - 4;
    if (data.getUint32(0, Endian.little) != 0x02000001 ||
        (flags & ~0x1001) != 0 ||
        data.getUint32(12, Endian.little) != 0 ||
        monikerBytes < 0 ||
        monikerBytes > bytes.length - 20) {
      return null;
    }
    final linked = (flags & 1) != 0;
    return linked || bytes.length == 20 + monikerBytes ? linked : null;
  }
}

class _WordCompoundInspection {
  const _WordCompoundInspection({
    required this.linked,
    required this.hasRequiredVbaStreams,
  });
  final bool? linked;
  final bool hasRequiredVbaStreams;
}
