import 'dart:convert';
import 'dart:typed_data';

import '../../odf/odf_text.dart';
import '../../opc/zip/zip_reader.dart';
import '../../visual/office_visual.dart';
import '../../xml/xml_node.dart';
import '../model/word_zotero_note_image.dart';
import 'odt_reader_styles.dart';

const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _svg = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';
const _xml = 'http://www.w3.org/XML/1998/namespace';

/// Shared bounded raster qualification for native ODT pictures.
///
/// Each instance owns the existing Zotero note raster budgets for a complete
/// document. The same bytes, dimensions, orientation and pixel validation apply
/// to native ODT input and the explicit editable Zotero copy export.
final class OdtInlineImageValidator {
  final _reader = WordZoteroNoteImageReader();

  OfficeVisual decode(
    Uint8List bytes, {
    required double width,
    required double height,
    String title = '',
    String description = '',
  }) {
    if (bytes.length > WordZoteroNoteImageReader.maxImageBytes) {
      throw const FormatException('ODT inline picture exceeds 4 MiB.');
    }
    if (!width.isFinite ||
        !height.isFinite ||
        width < 1 ||
        height < 1 ||
        width > 4000 ||
        height > 4000) {
      throw const FormatException(
        'ODT inline picture dimensions are out of bounds.',
      );
    }
    final mime = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80
        ? 'image/png'
        : bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8
        ? 'image/jpeg'
        : throw UnsupportedError(
            'ODT inline pictures require PNG or JPEG data.',
          );
    // The reused decoder accepts CSS pixels, while ODF/native extents use
    // points. Retain exact admitted ODF extents after byte/raster validation.
    final visual = _reader.read({
      'src': 'data:$mime;base64,${base64.encode(bytes)}',
      'width': (width / 0.75).toString(),
      'height': (height / 0.75).toString(),
      'title': title,
      'alt': description,
    });
    visual.width = width;
    visual.height = height;
    return visual;
  }

  void validateVisual(OfficeVisual visual) {
    final picture = visual.picture;
    if (!visual.isPicture ||
        visual.imageBytes == null ||
        visual.offsetX != 0 ||
        visual.offsetY != 0 ||
        picture.wrap != PictureWrap.inline ||
        picture.cropLeft != 0 ||
        picture.cropTop != 0 ||
        picture.cropRight != 0 ||
        picture.cropBottom != 0 ||
        picture.rotationDeg != 0 ||
        picture.brightness != 0 ||
        picture.contrast != 1 ||
        picture.transparency != 0 ||
        picture.borderColor.isNotEmpty ||
        picture.borderWidth != 0 ||
        !picture.lockAspect ||
        picture.flipH ||
        picture.flipV ||
        picture.shadow) {
      throw UnsupportedError(
        'Editable Zotero ODT requires unadjusted inline PNG or JPEG pictures.',
      );
    }
    decode(
      visual.imageBytes!,
      width: visual.width,
      height: visual.height,
      title: picture.altTitle,
      description: picture.altDescription,
    );
  }
}

/// Reads only complete, embedded, character-anchored raster picture frames.
/// Floating drawings, external URLs, transformations, image maps, OLE, SVG,
/// text boxes and multiple image alternatives remain explicit refusals.
final class OdtReaderImages {
  OdtReaderImages(this.zip, this.styles);

  final ZipReader zip;
  final OdtReaderStyles styles;
  final _rasters = OdtInlineImageValidator();

  /// Character styles for a link's visited state do not paint glyphs when
  /// its entire content is pictures. Actual frames/styles are still validated
  /// by [read]; this predicate never licenses an unsupported frame or story.
  static bool isImageOnlyLink(XmlElement link) {
    var frames = 0;
    bool content(XmlElement owner) {
      for (final child in owner.children) {
        if (child is XmlText || child is XmlCdata) {
          final value = child is XmlText
              ? child.text
              : (child as XmlCdata).text;
          // Literal XML whitespace can become an authored underlined space.
          // This exemption therefore requires no text between the pictures.
          if (value.isNotEmpty) return false;
        } else if (child is XmlElement) {
          if (child.namespaceUri == _draw && child.localName == 'frame') {
            frames++;
          } else if (child.namespaceUri == odfTextNamespace &&
              child.localName == 'span') {
            if (!content(child)) return false;
          } else {
            return false;
          }
        }
      }
      return true;
    }

    return content(link) && frames > 0;
  }

  OfficeVisual read(XmlElement frame) {
    _attributes(frame, {
      odfTextNamespace: {'anchor-type'},
      _draw: {'name', 'style-name'},
      _svg: {'width', 'height'},
      _xml: {'id'},
    });
    if (frame.getAttribute('anchor-type', namespaceUri: odfTextNamespace) !=
        'as-char') {
      throw UnsupportedError(
        'Only character-anchored ODT pictures are supported.',
      );
    }
    _graphicStyle(frame.getAttribute('style-name', namespaceUri: _draw));
    final width = _dimension(frame.getAttribute('width', namespaceUri: _svg));
    final height = _dimension(frame.getAttribute('height', namespaceUri: _svg));
    XmlElement? image;
    String? title;
    String? description;
    for (final child in frame.children) {
      if (child is XmlText || child is XmlCdata) {
        final value = child is XmlText ? child.text : (child as XmlCdata).text;
        if (!_xmlWhitespace(value)) _unsupported();
      } else if (child is XmlElement) {
        if (child.namespaceUri == _draw && child.localName == 'image') {
          if (image != null) _unsupported();
          image = child;
        } else if (child.namespaceUri == _svg &&
            (child.localName == 'title' || child.localName == 'desc')) {
          _attributes(child, {});
          if (child.childElements.isNotEmpty) _unsupported();
          if (child.localName == 'title') {
            if (title != null) _unsupported();
            title = child.text;
          } else {
            if (description != null) _unsupported();
            description = child.text;
          }
        } else {
          _unsupported();
        }
      }
    }
    if (image == null) _unsupported();
    _attributes(image, {
      _xlink: {'href', 'type', 'show', 'actuate'},
      _draw: {'mime-type'},
    });
    if (image.childElements.isNotEmpty || !_xmlWhitespace(image.text)) {
      _unsupported();
    }
    for (final entry in {
      'type': 'simple',
      'show': 'embed',
      'actuate': 'onLoad',
    }.entries) {
      final value = image.getAttribute(entry.key, namespaceUri: _xlink);
      if (value != null && value != entry.value) _unsupported();
    }
    final path = _packagePath(image.getAttribute('href', namespaceUri: _xlink));
    if (!zip.contains(path)) {
      throw const FormatException('Missing embedded ODT picture.');
    }
    final bytes = zip.read(
      path,
      maxBytes: WordZoteroNoteImageReader.maxImageBytes,
    );
    final visual = _rasters.decode(
      bytes,
      width: width,
      height: height,
      title: title ?? '',
      description: description ?? '',
    );
    final declaredMime = image.getAttribute('mime-type', namespaceUri: _draw);
    if (declaredMime != null &&
        declaredMime != (bytes[0] == 137 ? 'image/png' : 'image/jpeg')) {
      throw const FormatException(
        'ODT picture MIME type does not match its bytes.',
      );
    }
    visual.title =
        frame.getAttribute('name', namespaceUri: _draw) ?? title ?? '';
    return visual;
  }

  void _graphicStyle(String? name) {
    final values = <String, String>{};
    for (final definition in styles.styleChain('graphic', name)) {
      for (final properties in definition.childElements) {
        if (properties.localName == 'graphic-properties') {
          if (properties.childElements.isNotEmpty ||
              !_xmlWhitespace(properties.text)) {
            _unsupported();
          }
          for (final attribute in properties.attributes) {
            if (attribute.prefix == 'xmlns' ||
                attribute.qualifiedName == 'xmlns') {
              continue;
            }
            values['${attribute.namespaceUri}/${attribute.localName}'] =
                attribute.value;
          }
        } else {
          // These properties format text inside the drawing object. This
          // parser admits exactly one image and metadata, never a text box.
          // Only the observed empty paragraph/tab and text-property shapes
          // are inert; embedded children are not silently dropped.
          if (!_xmlWhitespace(_directText(properties))) _unsupported();
          for (final child in properties.childElements) {
            if (properties.localName != 'paragraph-properties' ||
                child.namespaceUri != _style ||
                child.localName != 'tab-stops' ||
                child.childElements.isNotEmpty ||
                !_xmlWhitespace(child.text)) {
              _unsupported();
            }
            _attributes(child, {});
          }
        }
      }
    }
    String? take(String namespace, String local) =>
        values.remove('$namespace/$local');
    void oneOf(String namespace, String local, Set<String> accepted) {
      final value = take(namespace, local);
      if (value != null && !accepted.contains(value)) _unsupported();
    }

    void zeroLength(String namespace, String local) {
      final value = take(namespace, local);
      if (value != null && !_isZeroLength(value)) _unsupported();
    }

    // No explicit paint/effect may be enabled. Stored fill colours require an
    // explicit no-fill setting: ODF otherwise leaves that fallback to the
    // consumer. Inactive raster-frame stroke/shadow defaults are bounded below.
    oneOf(_draw, 'stroke', {'none'});
    final fill = take(_draw, 'fill');
    if (fill != null && fill != 'none') _unsupported();
    oneOf(_draw, 'shadow', {'hidden'});
    for (final key in [(_svg, 'stroke-color'), (_draw, 'fill-color')]) {
      final color = take(key.$1, key.$2);
      if (key.$2 == 'fill-color' && color != null && fill != 'none') {
        _unsupported();
      }
      if (color != null && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
        _unsupported();
      }
    }
    for (final key in [
      'shadow-offset-x',
      'shadow-offset-y',
      'start-line-spacing-horizontal',
      'start-line-spacing-vertical',
      'end-line-spacing-horizontal',
      'end-line-spacing-vertical',
    ]) {
      final value = take(_draw, key);
      if (value != null && !_boundedLength(value)) _unsupported();
    }

    // Explicit text:anchor-type="as-char" on the frame is authoritative.
    // Writer inherits the following floating-frame defaults even for inline
    // images. Nondefault inline positioning, spacing or contour effects are
    // still outside the native baseline-picture contract.
    final inheritedAnchor = take(odfTextNamespace, 'anchor-type');
    if (inheritedAnchor != null &&
        inheritedAnchor != 'paragraph' &&
        inheritedAnchor != 'as-char') {
      _unsupported();
    }
    zeroLength(_svg, 'x');
    zeroLength(_svg, 'y');
    final horizontal = take(_style, 'horizontal-pos');
    final horizontalRelative = take(_style, 'horizontal-rel');
    final vertical = take(_style, 'vertical-pos');
    final verticalRelative = take(_style, 'vertical-rel');
    if ((horizontal != null || horizontalRelative != null) &&
        !(inheritedAnchor == 'paragraph' &&
            horizontal == 'center' &&
            horizontalRelative == 'paragraph')) {
      _unsupported();
    }
    if ((vertical != null || verticalRelative != null) &&
        !(inheritedAnchor == 'paragraph' &&
            vertical == 'top' &&
            verticalRelative == 'paragraph')) {
      _unsupported();
    }
    oneOf(_style, 'wrap', {'dynamic', 'none'});
    oneOf(_style, 'number-wrapped-paragraphs', {'no-limit'});
    oneOf(_style, 'wrap-contour', {'false'});
    oneOf(_style, 'flow-with-text', {'false'});
    oneOf(_fo, 'wrap-option', {'no-wrap'});
    for (final side in ['top', 'bottom', 'left', 'right']) {
      zeroLength(_fo, 'margin-$side');
    }

    oneOf(_style, 'mirror', {'none'});
    final clip = take(_fo, 'clip');
    if (clip != null) {
      final match = RegExp(r'^rect\(([^()]*)\)$').firstMatch(clip);
      final parts = match?.group(1)?.trim().split(RegExp(r'[ ,]+'));
      if (parts == null || parts.length != 4 || !parts.every(_isZeroLength)) {
        _unsupported();
      }
    }
    for (final channel in ['luminance', 'contrast', 'red', 'green', 'blue']) {
      oneOf(_draw, channel, {'0%'});
    }
    oneOf(_draw, 'gamma', {'100%'});
    oneOf(_draw, 'image-opacity', {'100%'});
    oneOf(_draw, 'color-inversion', {'false'});
    oneOf(_draw, 'color-mode', {'standard'});
    if (values.isNotEmpty) _unsupported();
  }

  static String _packagePath(String? href) {
    if (href == null || href.isEmpty || href.length > 2048) _unsupported();
    final uri = Uri.tryParse(href);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        href.startsWith('/') ||
        href.contains('\\')) {
      _unsupported();
    }
    // Uri normalizes dot segments during parsing. Check the original decoded
    // segments before any normalization so an alias cannot traverse or escape
    // the explicit package picture namespace.
    final segments = href.split('/').map(Uri.decodeComponent).toList();
    if (segments.length < 2 ||
        segments.first != 'Pictures' ||
        segments.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains('\\') ||
              part.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f),
        )) {
      _unsupported();
    }
    return segments.join('/');
  }

  static double _dimension(String? value) {
    if (value == null || value.length > 32) _unsupported();
    final match = RegExp(
      r'^((?:\d+(?:\.\d*)?|\.\d+))(pt|in|cm|mm|pc)$',
    ).firstMatch(value);
    if (match == null) _unsupported();
    final factor = switch (match.group(2)) {
      'in' => 72.0,
      'cm' => 72 / 2.54,
      'mm' => 72 / 25.4,
      'pc' => 12.0,
      _ => 1.0,
    };
    final points = double.parse(match.group(1)!) * factor;
    if (!points.isFinite || points < 1 || points > 4000) _unsupported();
    return points;
  }
}

void _attributes(XmlElement element, Map<String, Set<String>> allowed) {
  for (final attribute in element.attributes) {
    if (attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns') {
      continue;
    }
    if (allowed[attribute.namespaceUri]?.contains(attribute.localName) !=
        true) {
      _unsupported();
    }
  }
}

bool _xmlWhitespace(String value) => value.codeUnits.every(
  (unit) => unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d,
);

String _directText(XmlElement element) => element.children
    .where((node) => node is XmlText || node is XmlCdata)
    .map((node) => node is XmlText ? node.text : (node as XmlCdata).text)
    .join();

bool _isZeroLength(String value) =>
    RegExp(r'^[+-]?0+(?:\.0*)?(?:pt|in|cm|mm|pc)$').hasMatch(value);

bool _boundedLength(String value) {
  if (value.length > 32) return false;
  final match = RegExp(
    r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+))(pt|in|cm|mm|pc)$',
  ).firstMatch(value);
  if (match == null) return false;
  final number = double.tryParse(match.group(1)!);
  return number != null && number.isFinite && number.abs() <= 4000;
}

Never _unsupported() => throw UnsupportedError(
  'Native ODT inline picture properties or package reference are unsupported.',
);
