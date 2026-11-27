import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'word_docx_clipboard.dart';
import 'word_html_clipboard.dart';
import 'word_image_import.dart';
import 'word_rtf_clipboard.dart';

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
    this.wordSections,
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

  /// Builds an editable fragment from an application's clipboard representations.
  factory OfficeClipboardPayload.fromWordClipboard({
    String? plain,
    String? html,
    String? rtf,
  }) {
    List<WmlBlock> blocks = [];
    if (html != null) {
      try {
        blocks = readWordClipboardHtml(html);
      } on Exception {
        // Some native apps advertise a format without a usable fragment.
      }
    }
    if (!_hasClipboardText(blocks) && rtf != null) {
      try {
        blocks = readWordClipboardRtf(rtf);
      } on Exception {
        // The plain representation remains available.
      }
    }
    if (!_hasClipboardText(blocks)) {
      return OfficeClipboardPayload.fromPlain(plain ?? '');
    }
    return OfficeClipboardPayload._fromWordBlocks(blocks, plain);
  }

  factory OfficeClipboardPayload._fromWordBlocks(
    List<WmlBlock> blocks,
    String? plain, {
    List<WmlSection>? sections,
  }) {
    final projected = [
      for (final block in blocks)
        for (final paragraph in WmlClone.paragraphsOf(block))
          [
            for (final inline in paragraph.inlines)
              if (inline is WmlRun)
                inline.text
              else if (inline is WmlBreak)
                '\n',
          ].join(),
    ].join('\n');
    return OfficeClipboardPayload(
      kind: OfficeClipboardKind.richText,
      plain: plain == null || plain.isEmpty ? projected : plain,
      wordBlocks: blocks,
      wordSections: sections,
    );
  }

  static bool _hasClipboardText(List<WmlBlock> blocks) => blocks.any(
    (block) => WmlClone.paragraphsOf(block).any(
      (para) =>
          para.text.isNotEmpty ||
          para.inlines.any((inline) => inline is WmlBreak),
    ),
  );

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

  /// Optional native page layout carried by the copied sections.
  final List<WmlSection>? wordSections;

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
  Future<OfficeClipboardPayload> read({
    bool wordFormatting = false,
    bool preferPlain = false,
    bool includeImages = false,
  }) async {
    var system = '';
    if (useSystem && wordFormatting && !preferPlain) {
      final external = await _readWordClipboard(includeImages: includeImages);
      if (external != null &&
          (external.hasWordBlocks || external.visual != null)) {
        return external;
      }
      system = external?.plain ?? '';
    }
    if (useSystem && system.isEmpty) {
      try {
        system = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      } on Object {
        // Some platforms only expose the richer representation.
      }
      if (system.isEmpty && wordFormatting && preferPlain) {
        final external = await _readWordClipboard();
        if (external != null && external.plain.isNotEmpty) {
          return OfficeClipboardPayload.fromPlain(external.plain);
        }
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

  Future<OfficeClipboardPayload?> _readWordClipboard({
    bool includeImages = false,
  }) async {
    try {
      final reader = await SystemClipboard.instance?.read();
      if (reader == null) return null;
      return await readWordRepresentations(
        reader,
        includeImages: includeImages,
      );
    } on Object {
      return null;
    }
  }

  /// Reads application-supplied text and rich formats from a clipboard snapshot.
  static Future<OfficeClipboardPayload?> readWordRepresentations(
    ClipboardDataReader reader, {
    bool includeImages = false,
  }) async {
    final plain = await _readFormat(reader, Formats.plainText);
    final native = await _readFormat(reader, _nativeWord);
    if (native != null) {
      final fragment = await readWordClipboardDocx(native);
      if (fragment != null && fragment.blocks.isNotEmpty) {
        return OfficeClipboardPayload._fromWordBlocks(
          fragment.blocks,
          plain,
          sections: fragment.sections,
        );
      }
    }
    final html =
        await _readFormat(reader, _windowsHtml) ??
        await _readFormat(reader, Formats.htmlText);
    final htmlPayload = OfficeClipboardPayload.fromWordClipboard(
      plain: plain,
      html: html,
    );
    final plainUri = Uri.tryParse(plain?.trim() ?? '');
    final imageOnly =
        plain == null ||
        plain.trim().isEmpty ||
        plainUri != null &&
            const {'http', 'https', 'file'}.contains(plainUri.scheme);
    if (includeImages && imageOnly) {
      final picture = await _readWordPicture(reader, plain);
      if (picture != null) return picture;
    }
    if (htmlPayload.hasWordBlocks) return htmlPayload;
    final rtf = await _readFormat(reader, _rtf);
    final text = rtf == null
        ? htmlPayload
        : OfficeClipboardPayload.fromWordClipboard(plain: plain, rtf: rtf);
    if (text.hasWordBlocks) return text;
    if (includeImages && !imageOnly) {
      final picture = await _readWordPicture(reader, plain);
      if (picture != null) return picture;
    }
    return text.isEmpty ? null : text;
  }

  static Future<OfficeClipboardPayload?> _readWordPicture(
    DataReader reader,
    String? plain,
  ) async {
    final bytes = await WordImageImport.readBytes(reader, localFiles: true);
    final picture = bytes == null
        ? null
        : await WordImageImport.normalize(bytes);
    return picture == null
        ? null
        : OfficeClipboardPayload(
            kind: OfficeClipboardKind.visual,
            plain: plain ?? '',
            visual: picture,
          );
  }

  static Future<T?> _readFormat<T extends Object>(
    ClipboardDataReader reader,
    ValueFormat<T> format,
  ) async {
    try {
      return reader.canProvide(format) ? await reader.readValue(format) : null;
    } on Object {
      return null;
    }
  }

  /// clear API.
  void clear() {
    _local = null;
  }
}

// Maintain the HTML header and ancestor styles around the selected fragment.
const _windowsHtml = SimpleValueFormat<String>(
  windows: SimplePlatformCodec(
    formats: ['HTML Format'],
    onDecode: _decodeWindowsHtml,
  ),
);

Future<String?> _decodeWindowsHtml(
  PlatformDataProvider data,
  String format,
) async {
  final bytes = await data.getData(format);
  if (bytes is! List<int> || bytes.length > wordClipboardLimit) return null;
  final header = latin1.decode(bytes.take(1024).toList());
  int? offset(String label) => int.tryParse(
    RegExp('(?:^|[\\r\\n])$label:[ \t]*([0-9]+)').firstMatch(header)?[1] ?? '',
  );
  final startHtml = offset('StartHTML');
  final endHtml = offset('EndHTML');
  final startFragment = offset('StartFragment');
  final endFragment = offset('EndFragment');
  if (startHtml == null ||
      endHtml == null ||
      startFragment == null ||
      endFragment == null ||
      startHtml > startFragment ||
      startFragment >= endFragment ||
      endFragment > endHtml ||
      endHtml > bytes.length) {
    return null;
  }
  String decode(int start, int end) =>
      utf8.decode(bytes.sublist(start, end), allowMalformed: true);
  final full = decode(startHtml, endHtml);
  if (full.contains('<!--StartFragment-->') &&
      full.contains('<!--EndFragment-->')) {
    return full;
  }
  return '${decode(startHtml, startFragment)}<!--StartFragment-->'
      '${decode(startFragment, endFragment)}<!--EndFragment-->'
      '${decode(endFragment, endHtml)}';
}

const _nativeWord = SimpleValueFormat<Uint8List>(
  macos: SimplePlatformCodec(
    formats: [
      'com.microsoft.Embed-Source',
      'org.openxmlformats.wordprocessingml.document',
    ],
    onDecode: _wordNativeBytes,
  ),
  windows: SimplePlatformCodec(
    formats: [
      'Embed Source',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ],
    onDecode: _wordNativeBytes,
  ),
  fallback: SimplePlatformCodec(
    formats: [
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ],
    onDecode: _wordNativeBytes,
  ),
);

Future<Uint8List?> _wordNativeBytes(
  PlatformDataProvider data,
  String format,
) async {
  final raw = await data.getData(format);
  if (raw is! List<int> || raw.length > wordNativeClipboardLimit) return null;
  return raw is Uint8List ? raw : Uint8List.fromList(raw);
}

const _rtf = SimpleValueFormat<String>(
  ios: SimplePlatformCodec(formats: ['public.rtf'], onDecode: _decodeRtf),
  macos: SimplePlatformCodec(formats: ['public.rtf'], onDecode: _decodeRtf),
  windows: SimplePlatformCodec(
    formats: ['Rich Text Format'],
    onDecode: _decodeRtf,
  ),
  fallback: SimplePlatformCodec(
    formats: ['text/rtf', 'application/rtf'],
    onDecode: _decodeRtf,
  ),
);

Future<String?> _decodeRtf(PlatformDataProvider data, String format) async {
  final value = await data.getData(format);
  final String text;
  if (value is String && value.length <= wordClipboardLimit) {
    text = value;
  } else if (value is List<int> && value.length <= wordClipboardLimit) {
    text = latin1.decode(value);
  } else {
    return null;
  }
  final terminator = text.indexOf('\u0000');
  return terminator < 0 ? text : text.substring(0, terminator);
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
    transform: source.transform.copyWith(
      x: source.transform.x + nudgeEmu,
      y: source.transform.y + nudgeEmu,
      cx: source.transform.cx,
      cy: source.transform.cy,
      rot: source.transform.rot,
      flipH: source.transform.flipH,
      flipV: source.transform.flipV,
    ),
    text: source.text,
    fillColor: source.fillColor,
    textColor: source.textColor,
    fontSizePt: source.fontSizePt,
    strokeColor: source.strokeColor,
    strokeWidth: source.strokeWidth,
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
