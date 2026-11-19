import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'bundled_thesaurus_manifest.dart';

/// The installed English and German packs. No document text leaves the device.
/// Packs and individual shards are read only when a user requests a lookup.
abstract final class BundledOfficeThesaurus {
  static final OfficeThesaurusService shared = create();

  /// A separate service is useful when a host owns its own asset/cache lifetime.
  static OfficeThesaurusService create({AssetBundle? bundle}) {
    final assets = bundle ?? rootBundle;
    Future<ByteData?> read(String path) async {
      try {
        return await assets.load(
          'packages/quds_office_editor/assets/thesaurus/$path',
        );
      } on FlutterError catch (error) {
        if (error.message.contains('Unable to load asset')) return null;
        rethrow;
      }
    }

    return OfficeThesaurusService(
      manifestSha256: bundledThesaurusManifestSha256,
      loadAsset: (path) async {
        final bytes = await read(path);
        return bytes == null
            ? null
            : utf8.decode(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              );
      },
      loadCompressedAsset: (path) async {
        final bytes = await read(path);
        return bytes?.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      },
    );
  }
}
