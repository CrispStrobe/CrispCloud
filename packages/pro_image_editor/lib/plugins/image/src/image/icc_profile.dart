// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import '/plugins/archive/src/codecs/zlib_encoder.dart';

enum IccProfileCompression { none, deflate }

/// ICC Profile data stored with an image.
class IccProfile {
  IccProfile(this.name, this.compression, this.data);

  IccProfile.from(IccProfile other)
    : name = other.name,
      compression = other.compression,
      data = other.data.sublist(0);
  String name = '';
  IccProfileCompression compression;
  Uint8List data;

  IccProfile clone() => IccProfile.from(this);

  /// Returns the compressed data of the ICC Profile, compressing the stored
  /// data as necessary.
  Uint8List compressed() {
    if (compression == IccProfileCompression.deflate) {
      return data;
    }
    data = const ZLibEncoder().encode(data) as Uint8List;
    compression = IccProfileCompression.deflate;
    return data;
  }
}
