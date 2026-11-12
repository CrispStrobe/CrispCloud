import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:archive/archive.dart' show getCrc32;
import 'package:koni_codecs/koni_codecs.dart' as codecs;

import 'archive_sevenz_byte_reader.dart';
import 'archive_sevenz_metadata.dart';
import 'archive_streaming_lzma.dart';
import 'archive_streaming_lzma2.dart';
import 'archive_streaming_unsupported.dart';
import 'archive_types.dart';

/// Native 7z reader with bounded metadata and dictionaries. Copy, Deflate,
/// LZMA and LZMA2 folders stream, including solid folders; selected members are
/// sliced from the folder stream and both member and folder CRCs are checked.
Future<ViewerArchive> openStreamedSevenZipSource(
  koni.ByteSource source, {
  int maxBytes = kArchiveStreamingLimit,
}) async {
  try {
    return await _open(source, maxBytes);
  } on koni.UnsupportedFeatureException catch (error) {
    throw ArchiveStreamingUnsupported(error.message);
  } on koni.ArchiveException catch (error) {
    throw ArchiveViewException('Invalid 7z container: ${error.message}');
  } on FormatException catch (error) {
    throw ArchiveViewException('Invalid 7z container: ${error.message}');
  }
}

Future<ViewerArchive> _open(koni.ByteSource source, int maxBytes) async {
  if (source.length < 32 || source.length > maxBytes) {
    throw const ArchiveViewException('7z input exceeds its supported bounds.');
  }
  final start = await source.read(0, 32);
  const magic = [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c];
  for (var i = 0; i < magic.length; i++) {
    if (start[i] != magic[i]) {
      throw const ArchiveViewException('Invalid 7z signature.');
    }
  }
  if (start[6] != 0) {
    throw const ArchiveStreamingUnsupported('Unsupported 7z major version.');
  }
  final sd = ByteData.sublistView(start);
  if (getCrc32(Uint8List.sublistView(start, 12)) !=
      sd.getUint32(8, Endian.little)) {
    throw const ArchiveViewException(
      '7z start-header checksum does not match.',
    );
  }
  final offset = sd.getUint64(12, Endian.little),
      length = sd.getUint64(20, Endian.little);
  if (offset < 0 ||
      length < 0 ||
      length > 16 * 1024 * 1024 ||
      offset > source.length - 32 ||
      length > source.length - 32 - offset ||
      32 + offset + length != source.length) {
    throw const ArchiveViewException(
      '7z header is truncated, oversized or has trailing data.',
    );
  }
  if (length == 0) {
    if (source.length != 32) {
      throw const ArchiveViewException('An empty 7z has unexpected data.');
    }
    return ViewerArchive.reader(
      maxStreamingMemberBytes: maxBytes,
      formatName: '7z',
      members: const [],
      read: (_, _) async => Uint8List(0),
      close: source.close,
    );
  }
  var headerBytes = await source.read(32 + offset, length);
  if (getCrc32(headerBytes) != sd.getUint32(28, Endian.little)) {
    throw const ArchiveViewException('7z metadata checksum does not match.');
  }
  var header = ByteReader(headerBytes);
  var id = readSevenZipNumber(header);
  if (id == SevenZId.encodedHeader) {
    final encoded = SevenZStreamsInfo.read(header);
    if (encoded.folders.length != 1 ||
        encoded.folders.single.unpackSize > 16 * 1024 * 1024 ||
        header.remaining != 0) {
      throw const ArchiveViewException(
        '7z encoded header exceeds its supported bounds.',
      );
    }
    final chunks = BytesBuilder(copy: false);
    await for (final part in _decodeFolder(
      source,
      encoded,
      0,
      16 * 1024 * 1024,
      () {},
    )) {
      chunks.add(part);
    }
    headerBytes = chunks.takeBytes();
    header = ByteReader(headerBytes);
    id = readSevenZipNumber(header);
  }
  if (id != SevenZId.header) {
    throw const ArchiveViewException('Missing 7z file header.');
  }
  SevenZStreamsInfo? streams;
  SevenZFileInfo? files;
  id = readSevenZipNumber(header);
  if (id == SevenZId.archiveProperties ||
      id == SevenZId.additionalStreamsInfo) {
    throw const ArchiveStreamingUnsupported(
      'This 7z contains metadata outside the streaming rewrite profile.',
    );
  }
  if (id == SevenZId.mainStreamsInfo) {
    streams = SevenZStreamsInfo.read(header);
    id = readSevenZipNumber(header);
  }
  if (id == SevenZId.filesInfo) {
    files = SevenZFileInfo.read(header);
    id = readSevenZipNumber(header);
  }
  if (id != SevenZId.end || header.remaining != 0) {
    throw const ArchiveViewException(
      '7z has unexpected trailing header properties.',
    );
  }
  if (files == null) {
    if (streams != null) {
      throw const ArchiveStreamingUnsupported(
        '7z content without file metadata is not writable.',
      );
    }
    return ViewerArchive.reader(
      maxStreamingMemberBytes: maxBytes,
      formatName: '7z',
      members: const [],
      read: (_, _) async => Uint8List(0),
      close: source.close,
    );
  }
  final locations = <(int, int, int, int?)>[];
  var total = 0;
  if (streams != null) {
    if (streams.folders.length > 200000 ||
        streams.packSizes.length != streams.folders.length) {
      throw const ArchiveStreamingUnsupported(
        'Complex 7z packed stream graphs are not supported.',
      );
    }
    var streamIndex = 0;
    for (var f = 0; f < streams.folders.length; f++) {
      final folder = streams.folders[f];
      _coder(folder);
      if (folder.unpackSize < 0 || folder.unpackSize > maxBytes - total) {
        throw const ArchiveViewException(
          'Expanded 7z contents exceed their streaming limit.',
        );
      }
      total += folder.unpackSize;
      var folderOffset = 0;
      for (var i = 0; i < streams.numUnpackStreams[f]; i++) {
        if (streamIndex >= streams.substreamSizes.length) {
          throw const ArchiveViewException(
            '7z substream metadata is truncated.',
          );
        }
        final size = streams.substreamSizes[streamIndex];
        if (size < 0 || size > folder.unpackSize - folderOffset) {
          throw const ArchiveViewException('7z substream exceeds its folder.');
        }
        locations.add((
          f,
          folderOffset,
          size,
          streams.substreamCrcs[streamIndex],
        ));
        folderOffset += size;
        streamIndex++;
      }
      if (folderOffset != folder.unpackSize) {
        throw const ArchiveViewException(
          '7z folder substream sizes do not add up.',
        );
      }
    }
    if (streamIndex != streams.substreamSizes.length) {
      throw const ArchiveViewException('Unclaimed 7z content streams.');
    }
  }
  final members = <ViewerArchiveMember>[];
  final memberLocations = <(int, int, int, int?)?>[];
  var content = 0, empty = 0, nameBytes = 0;
  for (var i = 0; i < files.count; i++) {
    if (i >= files.names.length) {
      throw const ArchiveViewException('7z file names are missing.');
    }
    final rawName = files.names[i];
    nameBytes += rawName.length * 2;
    if (rawName.length > 4096 || nameBytes > 16 * 1024 * 1024) {
      throw const ArchiveViewException('7z file names exceed their bounds.');
    }
    final normalized = koni.normalizeEntryPath(rawName);
    final attributes = i < files.attributes.length ? files.attributes[i] : null;
    final mode = attributes != null && attributes & 0x8000 != 0
        ? (attributes >> 16) & 0xffff
        : null;
    final noStream = files.emptyStream.isNotEmpty && files.emptyStream[i];
    final emptyFile =
        noStream && empty < files.emptyFile.length && files.emptyFile[empty];
    if (noStream) empty++;
    final isDirectory = noStream && !emptyFile;
    final type = (mode ?? 0) & 0xf000;
    final special = type != 0 && type != (isDirectory ? 0x4000 : 0x8000);
    if (attributes != null && (attributes & 0x10 != 0) != isDirectory) {
      throw const ArchiveViewException(
        '7z directory attributes conflict with its content type.',
      );
    }
    (int, int, int, int?)? location;
    if (!noStream) {
      if (content >= locations.length) {
        throw const ArchiveViewException('7z file has no content stream.');
      }
      location = locations[content++];
    }
    members.add(
      ViewerArchiveMember(
        name: normalized.path.isEmpty ? '/' : normalized.path,
        size: location?.$3 ?? 0,
        isFile: !isDirectory,
        isEncrypted: false,
        isSpecial: special,
        pathEscapedRoot: normalized.escapedRoot,
        index: i,
        modified: i < files.mTimes.length ? files.mTimes[i] : null,
        posixMode: mode == null ? null : mode & 0xfff,
      ),
    );
    memberLocations.add(location);
  }
  if (content != locations.length) {
    throw const ArchiveViewException('7z has unclaimed content streams.');
  }
  var closed = false;
  void check() {
    if (closed) {
      throw const ArchiveViewException('This 7z archive has been closed.');
    }
  }

  Stream<List<int>> read(ViewerArchiveMember member) async* {
    check();
    final location = memberLocations[member.index];
    if (location == null) return;
    var crc = 0;
    var position = 0, received = 0;
    await for (final chunk in _decodeFolder(
      source,
      streams!,
      location.$1,
      maxBytes,
      check,
    )) {
      final begin = location.$2 > position ? location.$2 - position : 0;
      final end = location.$2 + location.$3 - position < chunk.length
          ? location.$2 + location.$3 - position
          : chunk.length;
      if (begin < end && begin < chunk.length && end > 0) {
        final part = Uint8List.fromList(chunk.sublist(begin, end));
        crc = getCrc32(part, crc);
        received += part.length;
        yield part;
      }
      position += chunk.length;
    }
    if (received != location.$3 || location.$4 != null && crc != location.$4) {
      throw const ArchiveViewException(
        '7z member checksum or length does not match.',
      );
    }
  }

  return ViewerArchive.reader(
    maxStreamingMemberBytes: maxBytes,
    formatName: '7z',
    members: List.unmodifiable(members),
    read: (member, limit) async {
      final result = BytesBuilder(copy: false);
      await for (final chunk in read(member)) {
        if (chunk.length > limit - result.length) {
          throw const ArchiveViewException('7z member exceeds its read limit.');
        }
        result.add(chunk);
      }
      return result.takeBytes();
    },
    streamReader: (member, _) => read(member),
    close: () async {
      closed = true;
      await source.close();
    },
  );
}

SevenZCoder _coder(SevenZFolder folder) {
  if (folder.coders.any((c) => c.idHex == '06f10701')) {
    throw const ArchiveStreamingUnsupported(
      'Protected 7z containers use the bounded password-preserving workspace.',
    );
  }
  if (folder.coders.length != 1 ||
      folder.packedIndices.length != 1 ||
      folder.packedIndices.single != 0 ||
      folder.bindPairs.isNotEmpty ||
      folder.coders.single.numInStreams != 1 ||
      folder.coders.single.numOutStreams != 1) {
    throw const ArchiveStreamingUnsupported(
      'Filtered or complex 7z coder chains are outside the streaming profile.',
    );
  }
  final coder = folder.coders.single;
  if (!const {'00', '040108', '030101', '21'}.contains(coder.idHex)) {
    throw ArchiveStreamingUnsupported(
      '7z codec ${coder.idHex} has no streaming decoder.',
    );
  }
  if (coder.idHex == '21') {
    if (coder.props.length != 1 || coder.props.single > 28) {
      throw const ArchiveStreamingUnsupported(
        '7z LZMA2 dictionaries above 64 MiB are not supported.',
      );
    }
  }
  if (coder.idHex == '030101') {
    if (coder.props.length != 5) {
      throw const ArchiveViewException('Invalid LZMA properties.');
    }
    final size = ByteData.sublistView(coder.props).getUint32(1, Endian.little);
    if (size > 64 * 1024 * 1024) {
      throw const ArchiveStreamingUnsupported(
        '7z LZMA dictionaries above 64 MiB are not supported.',
      );
    }
  }
  return coder;
}

Stream<Uint8List> _decodeFolder(
  koni.ByteSource source,
  SevenZStreamsInfo streams,
  int index,
  int maxBytes,
  void Function() check,
) async* {
  final folder = streams.folders[index], coder = _coder(streams.folders[index]);
  final outSize = folder.unpackSize;
  if (outSize < 0 || outSize > maxBytes) {
    throw const ArchiveViewException('7z folder exceeds its streaming limit.');
  }
  final start = streams.packStreamStarts()[index];
  if (start >= streams.packSizes.length) {
    throw const ArchiveViewException('7z packed stream is missing.');
  }
  var offset = 32 + streams.packPos;
  for (var i = 0; i < start; i++) {
    offset += streams.packSizes[i];
  }
  final packedSize = streams.packSizes[start];
  if (offset < 32 ||
      offset > source.length ||
      packedSize < 0 ||
      packedSize > source.length - offset) {
    throw const ArchiveViewException('7z packed stream is truncated.');
  }
  final pending = <Uint8List>[];
  var crc = 0;
  var produced = 0;
  void emit(Uint8List chunk) {
    if (chunk.length > outSize - produced) {
      throw const ArchiveViewException(
        '7z decoded output exceeds its declared length.',
      );
    }
    produced += chunk.length;
    crc = getCrc32(chunk, crc);
    pending.add(chunk);
  }

  codecs.RawInflater? deflate;
  ArchiveStreamingLzmaDecoder? lzma;
  ArchiveStreamingLzma2Decoder? lzma2;
  switch (coder.idHex) {
    case '00':
      if (packedSize != outSize) {
        throw const ArchiveViewException('7z Copy sizes disagree.');
      }
    case '040108':
      deflate = codecs.RawInflater(onOutput: emit);
    case '030101':
      final dict = ByteData.sublistView(coder.props)
          .getUint32(1, Endian.little);
      lzma = ArchiveStreamingLzmaDecoder(
        outputSize: outSize,
        dictionarySize: dict < 4096 ? 4096 : dict,
        onOutput: emit,
      )..setProps(coder.props[0]);
    case '21':
      lzma2 = ArchiveStreamingLzma2Decoder(
        outputSize: outSize,
        dictSizeProp: coder.props.single,
        onOutput: emit,
      );
  }
  // Copy has no decompression expansion, so larger positional reads remain
  // bounded while avoiding one filesystem round trip per 4 KiB of a large
  // stored member. Compressed inputs retain the smaller expansion budget.
  final inputChunkSize = coder.idHex == '00' ? 64 * 1024 : 4096;
  for (var at = 0; at < packedSize;) {
    check();
    final count = packedSize - at < inputChunkSize
        ? packedSize - at
        : inputChunkSize;
    final input = await source.read(offset + at, count);
    if (deflate != null) {
      final consumed = deflate.addInput(input);
      if (consumed != input.length ||
          deflate.isFinished &&
              (at + count != packedSize ||
                  deflate.takeLeftoverBytes().isNotEmpty)) {
        throw const ArchiveViewException(
          '7z Deflate stream contains trailing data.',
        );
      }
    } else if (lzma != null) {
      lzma.addInput(input);
    } else if (lzma2 != null) {
      lzma2.addInput(input);
    } else {
      emit(input);
    }
    at += count;
    for (final chunk in pending) {
      check();
      yield chunk;
    }
    pending.clear();
    await Future<void>.delayed(Duration.zero);
  }
  deflate?.finish();
  if (lzma != null) {
    lzma.setInputComplete();
    if (!lzma.isChunkComplete || lzma.outputPosition != outSize) {
      throw const ArchiveViewException('Truncated 7z LZMA folder.');
    }
    lzma.flush();
  }
  lzma2?.finish();
  for (final chunk in pending) {
    check();
    yield chunk;
  }
  if (produced != outSize || folder.crc != null && crc != folder.crc) {
    throw const ArchiveViewException(
      '7z folder checksum or length does not match.',
    );
  }
}
