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
