// ignore_for_file: annotate_overrides, public_member_api_docs

import 'dart:io';
import 'dart:typed_data';

import '/plugins/archive/src/utils/input_stream.dart';
import '/plugins/archive/src/utils/output_stream.dart';

import '_zlib_encoder_base.dart';

const platformZLibEncoder = _ZLibEncoder();

class _ZLibEncoder extends ZLibEncoderBase {
  const _ZLibEncoder();

  Uint8List encodeBytes(
    List<int> bytes, {
    int? level,
    int? windowBits,
    bool raw = false,
  }) =>
      ZLibCodec(
            level: level ?? 6,
            windowBits: windowBits ?? 15,
            raw: raw,
          ).encode(bytes)
          as Uint8List;

  @override
  void encodeStream(
    InputStream input,
    OutputStream output, {
    int? level,
    int? windowBits,
    bool raw = false,
  }) {
    throw ArgumentError('Not implemented');
  }
}
