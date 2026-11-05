// ignore_for_file: public_member_api_docs

import 'pvr_color.dart';

class PvrColorBoundingBox<PvrColor extends PvrColorRgbCore<PvrColor>> {
  PvrColorBoundingBox(PvrColor min, PvrColor max)
    : min = min.copy(),
      max = max.copy();
  PvrColor min;
  PvrColor max;

  void add(PvrColor c) {
    min.setMin(c);
    max.setMax(c);
  }
}
