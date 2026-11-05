import 'dart:typed_data';

/// Splits an arbitrarily chunked stream into bounded upload parts. The next
/// part is read only after the consumer resumes, preserving backpressure.
Stream<Uint8List> transferParts(Stream<List<int>> source, int partSize) async* {
  if (partSize <= 0) throw ArgumentError.value(partSize, 'partSize');
  var pending = BytesBuilder(copy: false);
  await for (final chunk in source) {
    var offset = 0;
    while (offset < chunk.length) {
      final count = (partSize - pending.length).clamp(0, chunk.length - offset);
      pending.add(chunk.sublist(offset, offset + count));
      offset += count;
      if (pending.length == partSize) {
        yield pending.takeBytes();
        pending = BytesBuilder(copy: false);
      }
    }
  }
  if (pending.isNotEmpty) yield pending.takeBytes();
}

/// Validates the declared size before releasing the final upload part. A
/// provider must not commit an apparently final part and only then discover
/// that its source contains additional bytes. Earlier parts retain bounded
/// backpressure, and at most the final part is held while checking EOF.
Stream<Uint8List> validatedTransferParts(
  Stream<List<int>> source,
  int length,
  int partSize,
) async* {
  if (length < 0) throw ArgumentError.value(length, 'length');
  var received = 0;
  Uint8List? finalPart;
  await for (final part in transferParts(source, partSize)) {
    if (finalPart != null || received + part.length > length) {
      throw StateError('Upload source exceeded its declared length.');
    }
    received += part.length;
    if (part.length < partSize && received < length) {
      throw StateError('Upload source ended before its declared length.');
    }
    if (received == length) {
      finalPart = part;
    } else {
      yield part;
    }
  }
  if (received != length) {
    throw StateError('Upload source ended before its declared length.');
  }
  if (finalPart != null) yield finalPart;
}
