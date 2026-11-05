// ignore_for_file: public_member_api_docs

import '../../util/_internal.dart';

enum PngDisposeMode { none, background, previous }

enum PngBlendMode { source, over }

// Decodes a frame from a PNG animation.
class PngFrame {
  PngFrame({
    this.sequenceNumber = 0,
    this.width = 0,
    this.height = 0,
    this.xOffset = 0,
    this.yOffset = 0,
    this.delayNum = 0,
    this.delayDen = 0,
    this.dispose = PngDisposeMode.none,
    this.blend = PngBlendMode.source,
  });
  int sequenceNumber;
  int width;
  int height;
  int xOffset;
  int yOffset;
  int delayNum;
  int delayDen;
  PngDisposeMode dispose;
  PngBlendMode blend;

  double get delay => delayNum == 0 || delayDen == 0 ? 0 : delayNum / delayDen;
}

@internal
class InternalPngFrame extends PngFrame {
  InternalPngFrame({
    super.sequenceNumber,
    super.width,
    super.height,
    super.xOffset,
    super.yOffset,
    super.delayNum,
    super.delayDen,
    super.dispose,
    super.blend,
  });

  final fdat = <int>[];
}
