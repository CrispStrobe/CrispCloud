// CrispCloud modification: optional overprint retries need a native isolate.
// Ordinary browser rendering continues to use the existing render backend.
import 'dart:typed_data';

const overprintRerecordSupported = false;

Future<Uint8List?> rerecordOverprintCommands(
  Uint8List bytes, {
  required int pageIndex,
  required int maxDimension,
  required bool annotations,
  required Set<String> hiddenAnnotationSubtypes,
  List<int>? populatedRanges,
  double? maxImagePixelRatio,
}) async =>
    null;
