import 'dart:typed_data';

import '../sheet/model/sml_workbook.dart';
import '../slide/model/pml_presentation.dart';
import '../word/layout/word_layout.dart';
import '../word/model/wml_document.dart';
import 'office_isolate_save.dart';
import 'office_isolate_spawn.dart'
    if (dart.library.io) 'office_isolate_spawn_io.dart';
import 'office_open_decode.dart';
import 'office_open_types.dart';

export 'office_open_types.dart';

/// Decodes Office packages on a worker isolate so the UI isolate stays live.
///
/// On web / Wasm the decode runs on the current isolate.
abstract final class OfficeIsolateOpen {
  /// Whether [bytes] is large enough that a worker isolate is worthwhile.
  static bool isHeavyBytes(Uint8List bytes) =>
      bytes.length >= OfficeSaveCost.isolateThresholdBytes;

  /// Opens a Word package and lays it out.
  static Future<WordOpenPayload> word(
    Uint8List bytes, {
    String? password,
    void Function(OfficeOpenProgress progress)? onProgress,
  }) async {
    final Object raw = await _open(
      bytes: bytes,
      password: password,
      kind: 'word',
      onProgress: onProgress,
    );
    if (raw is WordOpenPayload) {
      return raw;
    }
    if (raw is List && raw.length >= 2) {
      return WordOpenPayload(
        document: raw[0] as WmlDocument,
        laidOut: raw[1] as LaidOutDocument,
      );
    }
    throw StateError('Word open isolate returned an unexpected payload');
  }

  /// Opens a workbook and recalculates formulas.
  static Future<SmlWorkbook> workbook(
    Uint8List bytes, {
    String? password,
    void Function(OfficeOpenProgress progress)? onProgress,
  }) async {
    final Object raw = await _open(
      bytes: bytes,
      password: password,
      kind: 'sheet',
      onProgress: onProgress,
    );
    return raw as SmlWorkbook;
  }

  /// Opens a PDF file and builds display lists.
  static Future<PdfOpenPayload> pdf(
    Uint8List bytes, {
    String? password,
    void Function(OfficeOpenProgress progress)? onProgress,
  }) async {
    final Object raw = await _open(
      bytes: bytes,
      password: password,
      kind: 'pdf',
      onProgress: onProgress,
    );
    if (raw is PdfOpenPayload) {
      return raw;
    }
    throw StateError('PDF open isolate returned an unexpected payload');
  }

  /// Opens a presentation.
  static Future<PmlPresentation> presentation(
    Uint8List bytes, {
    String? password,
    void Function(OfficeOpenProgress progress)? onProgress,
  }) async {
    final Object raw = await _open(
      bytes: bytes,
      password: password,
      kind: 'slide',
      onProgress: onProgress,
    );
    return raw as PmlPresentation;
  }

  static Future<Object> _open({
    required Uint8List bytes,
    required String? password,
    required String kind,
    void Function(OfficeOpenProgress progress)? onProgress,
  }) async {
    onProgress?.call(const OfficeOpenProgress(value: 0.06, stage: 'archive'));
    final Object? isolated = await officeTrySpawnOpen(
      bytes: bytes,
      password: password,
      kind: kind,
      onProgress: onProgress,
    );
    if (isolated != null) {
      return isolated;
    }
    return _openSync(bytes, password, kind, onProgress);
  }
}

Object _openSync(
  Uint8List bytes,
  String? password,
  String kind,

  /// Function API.
  void Function(OfficeOpenProgress progress)? onProgress,
) {
  /// call API.
  onProgress?.call(const OfficeOpenProgress(value: 0.2, stage: 'archive'));

  /// result API.
  final Object result = decodeOfficeOpen(bytes, password, kind, (
    OfficeOpenProgress p,
  ) {
    onProgress?.call(p);
  });

  /// call API.
  onProgress?.call(const OfficeOpenProgress(value: 0.96, stage: 'apply'));
  return result;
}
