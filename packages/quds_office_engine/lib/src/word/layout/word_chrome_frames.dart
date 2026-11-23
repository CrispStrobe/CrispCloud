part of 'word_layout.dart';

bool _isPositionedPageField(WmlParagraph paragraph) {
  var started = false;
  var separated = false;
  var ended = false;
  final instruction = StringBuffer();
  for (final inline in paragraph.inlines) {
    if (inline is WmlBookmarkBoundary) continue;
    if (inline is WmlRun) {
      if (inline.text.trim().isNotEmpty && (!separated || ended)) return false;
      if (inline.inlineVisual != null || inline.noteRefId != null) return false;
      continue;
    }
    if (inline is! WmlFieldBoundary || ended) return false;
    switch (inline.kind) {
      case WmlFieldBoundaryKind.begin:
        if (started) return false;
        started = true;
        final source = inline.sourceXml;
        if (source != null && source.contains('fldLock')) {
          final lock = XmlDocument.parse(
            source,
          ).root?.getAttribute('fldLock', namespaceUri: OfficeNamespaces.w);
          if (const {'1', 'true', 'on'}.contains(lock)) return false;
        }
      case WmlFieldBoundaryKind.instruction:
        if (!started || separated) return false;
        instruction.write(inline.text);
      case WmlFieldBoundaryKind.separate:
        if (!started || separated) return false;
        separated = true;
      case WmlFieldBoundaryKind.end:
        if (!started) return false;
        ended = true;
    }
  }
  return ended && WordFields.isPlainPageInstruction(instruction.toString());
}

class _WordChromeFlow {
  _WordChromeFlow({this.frame});

  final _WordChromeFrame? frame;
  final lines = <LaidOutLine>[];
  double height = 0;
  WmlParagraphProps? previousParagraph;
  double? textAnchor;
}

/// Supported native paragraph frame geometry for the footer story.
/// The authored attributes remain in the paragraph's source XML for save.
class _WordChromeFrame {
  const _WordChromeFrame({
    required this.key,
    required this.x,
    required this.y,
    required this.width,
    required this.horizontal,
    required this.vertical,
    required this.alignment,
  });

  final String key;
  final double x;
  final double y;
  final double? width;
  final String horizontal;
  final String vertical;
  final WmlJustification? alignment;

  static _WordChromeFrame? read(String? xml) {
    if (xml == null || !xml.contains('framePr')) return null;
    final frame = XmlDocument.parse(
      xml,
    ).root?.firstChild('framePr', namespaceUri: OfficeNamespaces.w);
    if (frame == null) return null;
    String? attr(String name) =>
        frame.getAttribute(name, namespaceUri: OfficeNamespaces.w);
    final drop = attr('dropCap');
    if ((drop != null && drop != 'none') || attr('yAlign') != null) return null;
    final horizontal = attr('hAnchor') ?? 'text';
    final vertical = attr('vAnchor') ?? 'text';
    const anchors = {'text', 'margin', 'page'};
    if (!anchors.contains(horizontal) || !anchors.contains(vertical))
      return null;
    final xAlign = attr('xAlign');
    final alignment = switch (xAlign) {
      'left' => WmlJustification.left,
      'center' => WmlJustification.center,
      'right' => WmlJustification.right,
      _ => null,
    };
    if (xAlign != null && alignment == null) return null;
    final width = int.tryParse(attr('w') ?? '') ?? 0;
    final keys =
        frame.attributes
            .where((attribute) => attribute.namespaceUri == OfficeNamespaces.w)
            .map((attribute) => '${attribute.localName}=${attribute.value}')
            .toList()
          ..sort();
    return _WordChromeFrame(
      key: keys.join('|'),
      x: (int.tryParse(attr('x') ?? '') ?? 0) / 20,
      y: (int.tryParse(attr('y') ?? '') ?? 0) / 20,
      width: width > 0 ? width / 20 : null,
      horizontal: horizontal,
      vertical: vertical,
      alignment: alignment,
    );
  }

  ({double left, double width}) horizontalBox(WmlSection section) {
    final left = horizontal == 'page' ? 0.0 : section.margins.left;
    final available = horizontal == 'page'
        ? section.pageSize.width
        : section.contentWidth;
    final frameWidth = width ?? available;
    final offset = switch (alignment) {
      WmlJustification.left => 0.0,
      WmlJustification.center => (available - frameWidth) / 2,
      WmlJustification.right => available - frameWidth,
      _ => x,
    };
    return (left: left + offset, width: frameWidth);
  }
}
