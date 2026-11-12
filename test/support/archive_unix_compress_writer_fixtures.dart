import 'dart:convert';
import 'dart:typed_data';

/// Original deterministic payloads shared by native and web acceptance tools.
Map<String, Uint8List> unixCompressWriterPayloads() {
  var state = 0x12345678;
  final noise = Uint8List(300000);
  for (var i = 0; i < noise.length; i++) {
    state = (state * 1664525 + 1013904223) % 0x100000000;
    noise[i] = state ~/ 0x1000000;
  }
  return {
    'empty': Uint8List(0),
    'byte': Uint8List.fromList([0x80]),
    'width-boundary': Uint8List.fromList(List.generate(256, (i) => i)),
    'phrases': Uint8List.fromList(utf8.encode('ABABABA' * 10000)),
    'text': Uint8List.fromList(
      utf8.encode('CrispCloud UNIX compress writer.\n' * 5000),
    ),
    'noise-reset': noise,
  };
}
