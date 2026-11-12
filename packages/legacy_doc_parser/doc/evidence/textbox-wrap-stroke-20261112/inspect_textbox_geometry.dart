import 'dart:convert';
import 'dart:io';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';

void main(List<String> args) {
  for (final path in args) {
    final doc = parseLegacyWordDocument(File(path).readAsBytesSync());
    print(
      jsonEncode({
        'path': path,
        'drawings': [
          for (final d in doc.media.drawings.where((d) => d.textboxId != null))
            {
              'shapeId': d.shapeId,
              'header': d.headerStory,
              'rectangle': [
                d.leftTwips,
                d.topTwips,
                d.rightTwips,
                d.bottomTwips,
              ],
              'sourceFlags': d.shape?.sourceFlags,
              'type': d.shape?.type,
              'rotation': d.shape?.rotationFixed16,
              'flipH': d.shape?.flipHorizontal,
              'flipV': d.shape?.flipVertical,
              'line': {
                'enabled': d.shape?.line?.enabled,
                'type': d.shape?.line?.type,
                'width': d.shape?.line?.widthEmu,
                'dash': d.shape?.line?.dash,
              },
              'position': {
                'h': d.shape?.position?.horizontalMode,
                'v': d.shape?.position?.verticalMode,
                'hOrigin': d.shape?.position?.horizontalRelativeTo,
                'vOrigin': d.shape?.position?.verticalRelativeTo,
              },
              'insets': [
                d.shape?.text?.insetLeftEmu,
                d.shape?.text?.insetTopEmu,
                d.shape?.text?.insetRightEmu,
                d.shape?.text?.insetBottomEmu,
              ],
              'unsupported': d.shape?.unsupportedProperties,
            },
        ],
      }),
    );
  }
}
