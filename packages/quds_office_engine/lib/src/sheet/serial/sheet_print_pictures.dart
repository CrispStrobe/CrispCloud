import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';

/// Images named by &G in the worksheet's default print header or footer.
abstract final class SheetPrintPictures {
  static List<SheetPrintPicture> read(OpcPackage? package, String? sheetUri) {
    if (package == null || sheetUri == null) return const [];
    final sheetPart = package.getPart(sheetUri);
    if (sheetPart == null) return const [];
    final sheet = XmlDocument.parse(sheetPart.readText()).root;
    final drawingId = sheet
        ?.firstChild('legacyDrawingHF', namespaceUri: OfficeNamespaces.x)
        ?.getAttribute('id', namespaceUri: OfficeNamespaces.r);
    if (drawingId == null) return const [];

    final sheetRelationships = package.relationshipsFor(sheetUri);
    final drawingLink = sheetRelationships.byId(drawingId);
    if (drawingLink == null ||
        drawingLink.targetMode != RelationshipTargetMode.internal ||
        drawingLink.type != '${OfficeNamespaces.r}/vmlDrawing') {
      return const [];
    }
    final drawingPart = package.getPart(
      sheetRelationships.resolve(drawingLink),
    );
    if (drawingPart == null || drawingPart.length > 1024 * 1024) {
      return const [];
    }
    final drawing = XmlDocument.parse(drawingPart.readText()).root;
    if (drawing == null) return const [];

    final drawingRelationships = package.relationshipsFor(drawingPart.uri);
    final pictures = <SheetPrintPicture>[];
    final seen = <String>{};
    for (final shape in drawing.childrenNamed(
      'shape',
      namespaceUri: OfficeNamespaces.v,
    )) {
      final slot = shape.getAttribute('id');
      if (slot == null ||
          !const {'LH', 'CH', 'RH', 'LF', 'CF', 'RF'}.contains(slot) ||
          seen.contains(slot)) {
        continue;
      }
      final imageId = shape
          .firstChild('imagedata', namespaceUri: OfficeNamespaces.v)
          ?.getAttribute('relid', namespaceUri: OfficeNamespaces.o);
      if (imageId == null) continue;
      final imageLink = drawingRelationships.byId(imageId);
      if (imageLink == null ||
          imageLink.type != RelationshipTypes.image ||
          imageLink.targetMode != RelationshipTargetMode.internal) {
        continue;
      }
      final image = package.getPart(drawingRelationships.resolve(imageLink));
      if (image == null ||
          image.length > 16 * 1024 * 1024 ||
          !const {'image/png', 'image/jpeg'}.contains(image.contentType)) {
        continue;
      }
      final style = shape.getAttribute('style') ?? '';
      final width = _sizeInPoints(style, 'width');
      final height = _sizeInPoints(style, 'height');
      if (width == null || height == null) continue;
      seen.add(slot);
      pictures.add(
        SheetPrintPicture(slot, image, width: width, height: height),
      );
    }
    return pictures;
  }

  static double? _sizeInPoints(String style, String property) {
    final match = RegExp(
      '(?:^|;)\\s*$property\\s*:\\s*(\\d+(?:\\.\\d+)?)(pt|in|cm|mm|px)\\s*(?:;|\$)',
      caseSensitive: false,
    ).firstMatch(style);
    if (match == null) return null;
    final value = double.parse(match.group(1)!);
    final points =
        value *
        switch (match.group(2)!.toLowerCase()) {
          'in' => 72,
          'cm' => 72 / 2.54,
          'mm' => 72 / 25.4,
          'px' => 72 / 96,
          _ => 1,
        };
    return points > 0 && points <= 14400 ? points : null;
  }
}

class SheetPrintPicture {
  const SheetPrintPicture(
    this.slot,
    this.part, {
    required this.width,
    required this.height,
  });

  final String slot;
  final PackagePart part;
  final double width;
  final double height;
}
