import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// How pasted content is applied, matching Office paste options.
enum OfficePasteMode {
  /// Keep source formatting / formulas (Ctrl+V when rich data is available).
  keepSource,

  /// Apply destination character style; cell values without formulas.
  mergeFormatting,

  /// Unicode text only (Ctrl+Shift+V).
  keepTextOnly,
}

/// Enum OfficeClipboardKind.
enum OfficeClipboardKind { empty, text, richText, cells, shape, visual, slide }

/// Class OfficeClipboardSpan.
class OfficeClipboardSpan {
  /// OfficeClipboardSpan API.
  OfficeClipboardSpan({required this.text, required this.props});

  /// text API.
  final String text;

  /// props API.
  final WmlRunProps props;

  /// toRun API.
  WmlRun toRun() => WmlRun(text: text, properties: props.copy());
}

/// Class OfficeClipboardCell.
class OfficeClipboardCell {
  /// OfficeClipboardCell API.
  const OfficeClipboardCell({
    this.value,
    this.formula,
    this.type = SmlCellType.string,
    this.text = '',
  });

  /// value API.
  final Object? value;

  /// formula API.
  final String? formula;

  /// type API.
  final SmlCellType type;

  /// text API.
  final String text;
}

/// In-memory Office payload plus the last plain text written to the OS clipboard.
class OfficeClipboardPayload {
  /// OfficeClipboardPayload API.
  OfficeClipboardPayload({
    required this.kind,
    required this.plain,
    List<List<OfficeClipboardSpan>>? paragraphs,
    List<List<OfficeClipboardCell>>? cells,
    List<WmlBlock>? wordBlocks,
    this.shape,
    this.visual,
    this.slide,
  }) : paragraphs = paragraphs ?? <List<OfficeClipboardSpan>>[],
       cells = cells ?? <List<OfficeClipboardCell>>[],
       wordBlocks = wordBlocks ?? <WmlBlock>[];

  /// empty API.
  factory OfficeClipboardPayload.empty() =>
      OfficeClipboardPayload(kind: OfficeClipboardKind.empty, plain: '');

  /// fromPlain API.
  factory OfficeClipboardPayload.fromPlain(String text) {
    if (text.isEmpty) {
      return OfficeClipboardPayload.empty();
    }
    return OfficeClipboardPayload(kind: OfficeClipboardKind.text, plain: text);
  }

  /// kind API.
  final OfficeClipboardKind kind;

  /// plain API.
  final String plain;

  /// paragraphs API.
  final List<List<OfficeClipboardSpan>> paragraphs;

  /// cells API.
  final List<List<OfficeClipboardCell>> cells;

  /// wordBlocks API.
  final List<WmlBlock> wordBlocks;

  /// shape API.
  final PmlShape? shape;

  /// visual API.
  final OfficeVisual? visual;

  /// slide API.
  final PmlSlide? slide;

  /// isEmpty API.
  bool get isEmpty {
    return plain.isEmpty &&
        paragraphs.every((List<OfficeClipboardSpan> p) => p.isEmpty) &&
        wordBlocks.isEmpty &&
        cells.isEmpty &&
        shape == null &&
        visual == null &&
        slide == null;
  }

  /// hasWordBlocks API.
  bool get hasWordBlocks => wordBlocks.isNotEmpty;

  /// hasRichText API.
  bool get hasRichText =>
      kind == OfficeClipboardKind.richText &&
      (wordBlocks.isNotEmpty || paragraphs.isNotEmpty);

  /// hasCells API.
  bool get hasCells => cells.isNotEmpty;

  /// splitPlainLines API.
  static List<String> splitPlainLines(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  }

  /// parseTsv API.
  static List<List<String>> parseTsv(String text) {
    final List<String> lines = splitPlainLines(text);
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return <List<String>>[for (final String line in lines) line.split('\t')];
  }
}

/// Process-wide clipboard: rich Office data plus optional system text.
class OfficeClipboard {
  OfficeClipboard._();

  /// instance API.
  static final OfficeClipboard instance = OfficeClipboard._();

  OfficeClipboardPayload? _local;

  /// useSystem API.
  var useSystem = true;

  /// local API.
  OfficeClipboardPayload? get local => _local;

  /// hasContent API.
  bool get hasContent => _local != null && !_local!.isEmpty;

  /// write API.
  Future<void> write(OfficeClipboardPayload payload) async {
    _local = payload;
    if (useSystem) {
      await Clipboard.setData(ClipboardData(text: payload.plain));
    }
  }

  /// writeLocal API.
  void writeLocal(OfficeClipboardPayload payload) {
    _local = payload;
  }

  /// read API.
  Future<OfficeClipboardPayload> read() async {
    var system = '';
    if (useSystem) {
      try {
        system = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      } catch (_) {
        system = '';
      }
    }
    final OfficeClipboardPayload? local = _local;
    if (local != null &&
        !local.isEmpty &&
        (system.isEmpty || system == local.plain)) {
      return local;
    }
    if (system.isNotEmpty) {
      return OfficeClipboardPayload.fromPlain(system);
    }
    return local ?? OfficeClipboardPayload.empty();
  }

  /// clear API.
  void clear() {
    _local = null;
  }
}

/// cloneClipboardShape helper.
PmlShape cloneClipboardShape(
  PmlShape source, {

  /// id API.
  int id = 0,

  /// nudgeEmu API.
  int nudgeEmu = 127000,
}) {
  return PmlShape(
    id: id == 0 ? source.id : id,
    name: source.name,
    preset: source.preset,
    transform: PmlTransform(
      x: source.transform.x + nudgeEmu,
      y: source.transform.y + nudgeEmu,
      cx: source.transform.cx,
      cy: source.transform.cy,
      rot: source.transform.rot,
    ),
    text: source.text,
    fillColor: source.fillColor,
    textColor: source.textColor,
    fontSizePt: source.fontSizePt,
    path: <PmlPathPoint>[
      for (final PmlPathPoint point in source.path)
        PmlPathPoint(point.x, point.y),
    ],
    visual: source.visual?.copy(),
    table: source.table?.copy(),
    rightToLeft: source.rightToLeft,
    textAlign: source.textAlign,
  );
}
