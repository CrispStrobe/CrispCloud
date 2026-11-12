import 'wml_document.dart';

/// An inline content-control boundary; the enclosed runs remain ordinary runs.
final class WmlSdtInlineBoundary extends WmlZeroWidthInline {
  WmlSdtInlineBoundary(this.control, {required this.isStart});

  final WmlSdtInfo control;

  @override
  final bool isStart;

  @override
  bool get canCrossParagraph => false;

  @override
  WmlSdtInlineBoundary copy() =>
      WmlSdtInlineBoundary(control, isStart: isStart);
}
