// ignore_for_file: public_member_api_docs

import '../util/point.dart';
import 'ico_encoder.dart';

class CurEncoder extends WinEncoder {
  CurEncoder({this.hotSpots});

  /// Number of image mapped with x and y hotspot coordinates
  Map<int, Point>? hotSpots;

  @override
  int colorPlanesOrXHotSpot(int index) {
    if (hotSpots != null) {
      if (hotSpots!.containsKey(index)) {
        return hotSpots![index]!.xi;
      }
    }
    return 0;
  }

  @override
  int bitsPerPixelOrYHotSpot(int index) {
    if (hotSpots != null) {
      if (hotSpots!.containsKey(index)) {
        return hotSpots![index]!.yi;
      }
    }
    return 0;
  }

  @override
  int get type => 2;
}
