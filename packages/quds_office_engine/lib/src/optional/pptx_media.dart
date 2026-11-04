import 'dart:typed_data';

import '../opc/opc_archive.dart';
import '../opc/package_part.dart';
import '../opc/relationships.dart';
import '../slide/model/pml_presentation.dart';
import '../xml/namespaces.dart';

/// Optional PPT media part IO (not on the default engine export surface).
///
/// Hosts that need audio/video round-trip import this API explicitly.
/// Core PDF/slide paint still treats [PmlShape.mediaBytes] as in-memory only.
abstract final class PptxMediaIo {
  /// Writes non-empty [PmlShape.mediaBytes] into `/ppt/media/` and links them
  /// from each slide's relationship part. Returns media relationship ids.
  static Map<PmlShape, String> sync(
    PmlPresentation deck,
    OpcPackage package,
  ) {
    final Map<PmlShape, String> ids = <PmlShape, String>{};
    var index = 1;
    for (int s = 0; s < deck.slides.length; s++) {
      final PmlSlide slide = deck.slides[s];
      final String slideUri = '/ppt/slides/slide${s + 1}.xml';
      if (package.getPart(slideUri) == null) {
        continue;
      }
      final RelationshipCollection rels = package.relationshipsFor(slideUri);
      for (final PmlShape shape in slide.shapes) {
        if (!shape.hasMedia || shape.mediaBytes.isEmpty) {
          continue;
        }
        final String name = shape.mediaName.isEmpty
            ? 'media$index.bin'
            : shape.mediaName;
        final String uri = '/ppt/media/$name';
        index++;
        final Uint8List bytes = Uint8List.fromList(shape.mediaBytes);
        final String contentType = _mimeOf(name);
        final PackagePart? existing = package.getPart(uri);
        if (existing == null) {
          package.createPart(uri, contentType, bytes);
        } else {
          existing.writeBytes(bytes);
        }
        final String target = '../media/$name';
        PackageRelationship? found;
        for (final PackageRelationship rel in rels.items) {
          if (rel.target == target) {
            found = rel;
            break;
          }
        }
        found ??= rels.add(
          type: RelationshipTypes.media,
          target: target,
        );
        ids[shape] = found.id;
      }
    }
    return ids;
  }

  /// Loads `/ppt/media/` bytes back onto shapes that already name a media file.
  static void hydrate(PmlPresentation deck, OpcPackage package) {
    for (final PackagePart part in package.parts) {
      if (!part.uri.startsWith('/ppt/media/')) {
        continue;
      }
      final String fileName = part.uri.split('/').last;
      final Uint8List bytes = part.readBytes();
      for (final PmlSlide slide in deck.slides) {
        for (final PmlShape shape in slide.shapes) {
          if (shape.mediaName == fileName ||
              (shape.mediaName.isEmpty && shape.hasMedia)) {
            if (shape.mediaName.isEmpty) {
              shape.mediaName = fileName;
            }
            shape.mediaBytes
              ..clear()
              ..addAll(bytes);
          }
        }
      }
    }
  }

  static String _mimeOf(String name) {
    final String lower = name.toLowerCase();
    if (lower.endsWith('.mp4')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.mp3')) {
      return 'audio/mpeg';
    }
    if (lower.endsWith('.wav')) {
      return 'audio/wav';
    }
    if (lower.endsWith('.m4a')) {
      return 'audio/mp4';
    }
    return 'application/octet-stream';
  }
}
