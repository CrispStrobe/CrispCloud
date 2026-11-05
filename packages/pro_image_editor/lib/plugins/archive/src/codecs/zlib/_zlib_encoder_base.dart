// ignore_for_file: public_member_api_docs

import 'dart:typed_data';
import '../../utils/input_stream.dart';
import '../../utils/output_stream.dart';

abstract class ZLibEncoderBase {
  const ZLibEncoderBase();

  Uint8List encodeBytes(
    List<int> bytes, {
    int? level,
    int? windowBits,
    bool raw = false,
  });

  void encodeStream(
    InputStream input,
    OutputStream output, {
    int? level,
    int? windowBits,
    bool raw = false,
  });
}
