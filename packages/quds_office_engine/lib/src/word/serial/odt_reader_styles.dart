import '../../odf/odf_text.dart';
import '../../xml/xml_node.dart';
import '../model/wml_document.dart';
import '../model/word_notes.dart';
import '../model/word_proofing_language.dart';
import '../properties/wml_properties.dart';
import 'odt_note_start_convention.dart';
import 'odt_reader_text_style.dart';

const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _svg = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';
const _xml = 'http://www.w3.org/XML/1998/namespace';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _loext =
    'urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0';

/// A validated, continuous ODT automatic note sequence.
final class OdtReaderNoteConfiguration {
  const OdtReaderNoteConfiguration({
    this.nativeFormat = 'decimal',
    this.start = 1,
    this.verifyCachedOrdinal = false,
  });

  final String nativeFormat;
  final int start;
  final bool verifyCachedOrdinal;

  String? labelFor(int ordinal) => ordinal < 1
      ? null
      : WordNoteNumbering.formatLabel(start + ordinal - 1, nativeFormat);
}

/// Resolves the bounded style subset supported by the rich ODT reader.
///
/// Formatting is flattened into model properties, without creating dangling
/// Word style references. Unsupported properties on a used style fail import;
/// unused definitions are not interpreted. The caller bounds XML/package input.
final class OdtReaderStyles {
  OdtReaderStyles(XmlElement content, {XmlElement? styles}) {
    if (styles != null) _collect(styles);
    _collect(content);
  }

  static const maxDefinitions = 4096;
  static const maxParentDepth = 64;
  final _styles = <String, XmlElement>{};
  final _defaults = <String, XmlElement>{};
  final _fonts = <String, String>{};
  final _unsupportedFonts = <String>{};
  final _lists = <String, XmlElement>{};
  final _masters = <String, XmlElement>{};
  final _layouts = <String, XmlElement>{};
  final _noteConfigurations = <XmlElement>[];
  final _outlineStyles = <XmlElement>[];
  final _chains = <String, List<XmlElement>>{};
  final _paragraphContexts = <String, _OdtParagraphContext>{};
  final _usedMasters = <String>{};
  bool _implicitMasterUsed = false;
  int _definitionCount = 0;

  bool hasParagraphStyle(String name) => _styles.containsKey('paragraph/$name');

  bool hasTextStyle(String name) => _styles.containsKey('text/$name');

  /// Returns default and named ancestor definitions, in inheritance order.
  /// The immutable list refers to the caller's already bounded input DOM.
  List<XmlElement> styleChain(String family, String? name) {
    final key = '$family/${name ?? ''}';
    return _chains.putIfAbsent(key, () {
      final result = <XmlElement>[];
      final seen = <String>{};
      var current = name;
      while (current != null && current.isNotEmpty) {
        if (!seen.add(current)) {
          throw FormatException('Cyclic ODT $family style: $current');
        }
        if (seen.length > maxParentDepth) {
          throw const FormatException('ODT style inheritance limit exceeded.');
        }
        final definition = _styles['$family/$current'];
        if (definition == null) {
          throw FormatException('Missing ODT $family style: $current');
        }
        result.add(definition);
        current = _attr(definition, _style, 'parent-style-name');
      }
      final chain = <XmlElement>[?_defaults[family], ...result.reversed];
      for (final definition in chain) {
        _checkDefinition(definition, family);
      }
      return List<XmlElement>.unmodifiable(chain);
    });
  }

  XmlElement? listStyle(String? name) {
    if (name == null || name.isEmpty) return null;
    final result = _lists[name];
    if (result == null) throw FormatException('Missing ODT list style: $name');
    _checkAttributes(result, {
      _style: {'name', 'display-name'},
      odfTextNamespace: {'consecutive-numbering'},
      _xml: {'id'},
    });
    final consecutive = _attr(
      result,
      odfTextNamespace,
      'consecutive-numbering',
    );
    if (consecutive != null && _boolean(consecutive)) {
      throw UnsupportedError(
        'Consecutive ODT list numbering is not supported.',
      );
    }
    return result;
  }

  /// Rejects note numbering and styling not represented by the reader.
  ///
  /// ODF 1.3 section 19.874.5 describes an initial number, defaulting to one.
  /// LibreOffice writes its zero-based StartAt offset instead. The caller may
  /// opt into that producer convention only after qualifying the metadata, and
  /// must require a nonempty cached label matching each native ordinal when
  /// [OdtReaderNoteConfiguration.verifyCachedOrdinal] is true. Unknown
  /// producers retain the normative start-value interpretation.
  OdtReaderNoteConfiguration validateNoteConfiguration(
    bool endnote, {
    bool libreOfficeNoteOffsets = false,
    bool crispOfficeNoteOffsets = false,
  }) {
    final offsetStarts = libreOfficeNoteOffsets || crispOfficeNoteOffsets;
    final kind = endnote ? 'endnote' : 'footnote';
    final matching = <XmlElement>[];
    for (final configuration in _noteConfigurations) {
      final configuredKind = _attr(
        configuration,
        odfTextNamespace,
        'note-class',
      );
      if (configuredKind != 'footnote' && configuredKind != 'endnote') {
        throw const FormatException('Invalid ODT note configuration class.');
      }
      if (configuredKind == kind) matching.add(configuration);
    }
    if (matching.length > 1) {
      throw const FormatException('Duplicate ODT note configuration.');
    }
    if (matching.isEmpty) {
      if (crispOfficeNoteOffsets) {
        throw UnsupportedError(
          'The declared Quds note-offset convention requires explicit note configurations.',
        );
      }
      // ODF leaves the absent-configuration defaults implementation-defined.
      // Qualified LibreOffice producers use Roman endnotes and decimal
      // footnotes. Keep the existing generic decimal default, never infer a
      // different format from cached labels alone.
      return OdtReaderNoteConfiguration(
        nativeFormat: libreOfficeNoteOffsets && endnote
            ? 'lowerRoman'
            : 'decimal',
        verifyCachedOrdinal: libreOfficeNoteOffsets,
      );
    }
    final configuration = matching.single;
    if (!RegExp(r'^[ \t\r\n]*$').hasMatch(configuration.text)) {
      throw UnsupportedError('Authored ODT note configuration text.');
    }
    _checkAttributes(configuration, {
      odfTextNamespace: {
        'note-class',
        'start-value',
        'start-numbering-at',
        'footnotes-position',
        'citation-style-name',
        'citation-body-style-name',
        'default-style-name',
        'master-page-name',
      },
      _style: {'num-format', 'num-prefix', 'num-suffix', 'num-letter-sync'},
    });
    final format = _attr(configuration, _style, 'num-format');
    final nativeFormat = switch (format) {
      '1' => 'decimal',
      // ODF's present-but-omitted format suppresses numbering. LibreOffice's
      // importer instead starts an explicit configuration with decimal; use
      // that producer convention only with its qualified exact-cache check.
      null when libreOfficeNoteOffsets => 'decimal',
      'i' => 'lowerRoman',
      'I' => 'upperRoman',
      _ => throw UnsupportedError('Unsupported ODT note numbering format.'),
    };
    for (final name in ['num-prefix', 'num-suffix']) {
      final value = _attr(configuration, _style, name);
      if (value != null && value.isNotEmpty) {
        throw UnsupportedError('ODT note number affixes are not supported.');
      }
    }
    final sync = _attr(configuration, _style, 'num-letter-sync');
    if (sync != null && _boolean(sync)) {
      throw UnsupportedError(
        'ODT synchronized note lettering is not supported.',
      );
    }
    final declaredStart = _attr(configuration, odfTextNamespace, 'start-value');
    if (crispOfficeNoteOffsets && declaredStart == null) {
      throw UnsupportedError(
        'The declared Quds note-offset convention requires explicit start values.',
      );
    }
    final startMatch = declaredStart == null
        ? null
        : RegExp(r'^(0|[1-9][0-9]{0,4})$').firstMatch(declaredStart);
    final canonicalStart =
        declaredStart == null ||
        (startMatch != null && startMatch.end == declaredStart.length);
    final rawStart = declaredStart == null
        ? (offsetStarts ? 0 : 1)
        : int.tryParse(declaredStart);
    final start = rawStart == null ? null : rawStart + (offsetStarts ? 1 : 0);
    if (!canonicalStart ||
        start == null ||
        start < 1 ||
        start > odtNoteStartMaximum) {
      throw UnsupportedError(
        'ODT $kind start values must describe an initial number from 1 to 32768.',
      );
    }
    final restart = _attr(
      configuration,
      odfTextNamespace,
      'start-numbering-at',
    );
    if (restart != null && restart != 'document') {
      throw UnsupportedError('ODT note numbering restarts are not supported.');
    }
    final position = _attr(
      configuration,
      odfTextNamespace,
      'footnotes-position',
    );
    if (position != null && (endnote || position != 'page')) {
      throw UnsupportedError('Unsupported ODT note placement.');
    }
    for (final name in ['citation-style-name', 'citation-body-style-name']) {
      final value = _attr(configuration, odfTextNamespace, name);
      if (value != null) {
        if (value.isEmpty) {
          throw const FormatException('Empty ODT note marker style reference.');
        }
        _validateNoteMarkerStyle(value);
      }
    }
    final paragraphStyle = _attr(
      configuration,
      odfTextNamespace,
      'default-style-name',
    );
    if (paragraphStyle != null) {
      throw UnsupportedError('ODT configured note paragraph styles.');
    }
    final master = _attr(configuration, odfTextNamespace, 'master-page-name');
    if (master != null) {
      if (master.isEmpty) {
        throw const FormatException('Empty ODT note master page reference.');
      }
      if (!endnote) {
        throw UnsupportedError('ODT configured footnote master pages.');
      }
      // The native model has one compatible page layout. Resolve the note
      // master together with every used body master, never discard its layout.
      _usedMasters.add(master);
    }
    for (final child in configuration.childElements) {
      if (child.namespaceUri != odfTextNamespace ||
          !{
            'note-continuation-notice-forward',
            'note-continuation-notice-backward',
          }.contains(child.localName)) {
        throw UnsupportedError('Unsupported ODT note configuration content.');
      }
      _checkAttributes(child, const {});
      if (child.childElements.isNotEmpty || child.text.isNotEmpty) {
        throw UnsupportedError(
          'ODT note continuation notices are not supported.',
        );
      }
    }
    return OdtReaderNoteConfiguration(
      nativeFormat: nativeFormat,
      start: start,
      verifyCachedOrdinal: offsetStarts || start != 1,
    );
  }

  void _validateNoteMarkerStyle(String name) {
    final values = <String, String>{};
    for (final definition in styleChain('text', name)) {
      if (!RegExp(r'^[ \t\r\n]*$').hasMatch(definition.text)) {
        throw UnsupportedError('Authored ODT note marker style text.');
      }
      final properties = _singleChild(definition, _style, 'text-properties');
      if (properties == null) continue;
      if (properties.childElements.isNotEmpty) {
        throw UnsupportedError('Nested ODT note marker text properties.');
      }
      _mergeProperties(values, properties);
    }
    final position = values.remove('$_style/text-position');
    // Both native reference runs and note markers use semantic superscript.
    // Bare `super` leaves the font height up to the consumer; the qualified
    // native export uses 65% explicitly. Other formatting cannot be dropped.
    if (position == null ||
        !RegExp(
          r'^[ \t\r\n]*super[ \t\r\n]+65%[ \t\r\n]*$',
        ).hasMatch(position)) {
      throw UnsupportedError('Unsupported ODT note marker position.');
    }
    _requireEmpty(values, 'note marker');
  }

  /// Validates a document-wide outline before importing any heading.
  /// Numbered outlines and list-level indentation need separate conversion.
  /// LibreOffice's explicit unnumbered, unpositioned alignment is inert.
  void validateHeadingConfiguration() {
    if (_outlineStyles.length > 1) {
      throw const FormatException('Ambiguous ODT outline styles.');
    }
    if (_outlineStyles.isEmpty) return;
    final outline = _outlineStyles.single;
    _checkAttributes(outline, {
      _style: {'name', 'display-name'},
    });
    if (!RegExp(r'^[ \t\r\n]*$').hasMatch(outline.text)) {
      throw UnsupportedError('Authored ODT outline style text.');
    }
    final levels = <int>{};
    for (final level in outline.childElements) {
      if (level.namespaceUri != odfTextNamespace ||
          level.localName != 'outline-level-style') {
        throw UnsupportedError('Unsupported ODT outline style content.');
      }
      _checkAttributes(level, {
        odfTextNamespace: {'level'},
        _style: {'num-format'},
        _loext: {'num-list-format'},
      });
      final number = int.tryParse(
        _attr(level, odfTextNamespace, 'level') ?? '',
      );
      if (number == null || number < 1 || number > 10 || !levels.add(number)) {
        throw const FormatException('Invalid ODT outline level.');
      }
      if (_attr(level, _style, 'num-format') != '') {
        throw UnsupportedError(
          'Numbered or positioned ODT outlines are not supported.',
        );
      }
      // The single matching placeholder is emitted on subsequent Writer
      // saves even with an empty num-format. Do not admit literal labels,
      // other levels or any wider extension-language interpretation.
      final format = _attr(level, _loext, 'num-list-format');
      if (format != null && format != '%$number%') {
        throw UnsupportedError('Unsupported ODT outline number template.');
      }
      final children = level.childElements.toList();
      if (children.isEmpty) continue;
      if (children.length != 1 ||
          children.single.namespaceUri != _style ||
          children.single.localName != 'list-level-properties') {
        throw UnsupportedError('Unsupported ODT outline level properties.');
      }
      final properties = children.single;
      _checkAttributes(properties, {
        odfTextNamespace: {'list-level-position-and-space-mode'},
      });
      if (_attr(
            properties,
            odfTextNamespace,
            'list-level-position-and-space-mode',
          ) !=
          'label-alignment') {
        throw UnsupportedError('Positioned ODT outlines are not supported.');
      }
      final alignments = properties.childElements.toList();
      if (alignments.length != 1 ||
          alignments.single.namespaceUri != _style ||
          alignments.single.localName != 'list-level-label-alignment') {
        throw UnsupportedError('Unsupported ODT outline label alignment.');
      }
      final alignment = alignments.single;
      _checkAttributes(alignment, {
        odfTextNamespace: {'label-followed-by'},
      });
      // ODF 1.3 §§17.20, 19.504 and 19.833: an empty num-format emits no
      // number; "nothing" emits no following character. With no positioning
      // properties, paragraph indentation is the only effective geometry.
      if (_attr(alignment, odfTextNamespace, 'label-followed-by') !=
              'nothing' ||
          alignment.childElements.isNotEmpty) {
        throw UnsupportedError('Positioned ODT outlines are not supported.');
      }
    }
  }

  OdtReaderTextStyle paragraphRunProperties(String? styleName) {
    final result = OdtReaderTextStyle.from(WmlRunProps(kerningHalfPoints: 0));
    for (final definition in styleChain('paragraph', styleName)) {
      _checkDefinition(definition, 'paragraph');
      final properties = _singleChild(definition, _style, 'text-properties');
      if (properties != null) _applyRun(result, properties);
    }
    return result;
  }

  OdtReaderTextStyle runProperties(
    String? styleName, {
    WmlRunProps? inherited,
  }) {
    final result = inherited == null
        ? paragraphRunProperties(null)
        : OdtReaderTextStyle.from(inherited);
    for (final definition in styleChain('text', styleName)) {
      // A span inherits its paragraph. The text-family default is a fallback,
      // not a replacement for explicitly resolved paragraph formatting.
      if (inherited != null && definition.localName == 'default-style') {
        continue;
      }
      _checkDefinition(definition, 'text');
      final properties = _singleChild(definition, _style, 'text-properties');
      if (properties != null) _applyRun(result, properties);
    }
    return result;
  }

  WmlParagraphProps paragraphProperties(String? styleName) {
    final values = <String, String>{};
    XmlElement? tabs;
    String? master;
    int? heading;
    for (final definition in styleChain('paragraph', styleName)) {
      _checkDefinition(definition, 'paragraph');
      master = _attr(definition, _style, 'master-page-name') ?? master;
      final outline = _attr(definition, _style, 'default-outline-level');
      if (outline != null) {
        final parsed = int.tryParse(outline);
        if (parsed == null || parsed < 0 || parsed > 9) {
          throw UnsupportedError('Unsupported ODT outline level: $outline');
        }
        heading = parsed == 0 ? null : parsed;
      }
      final properties = _singleChild(
        definition,
        _style,
        'paragraph-properties',
      );
      if (properties == null) continue;
      _mergeProperties(values, properties);
      for (final child in properties.childElements) {
        if (child.namespaceUri != _style || child.localName != 'tab-stops') {
          throw UnsupportedError(
            'Unsupported ODT paragraph element: ${child.qualifiedName}',
          );
        }
        if (properties
                .childrenNamed('tab-stops', namespaceUri: _style)
                .length !=
            1) {
          throw const FormatException('Ambiguous ODT tab stops.');
        }
        tabs = child;
      }
    }
    if (master == null || master.isEmpty) {
      _implicitMasterUsed = true;
    } else {
      _usedMasters.add(master);
    }
    final result = WmlParagraphProps(
      lineSpacing: 1,
      spacingAfter: 0,
      headingLevel: heading,
    );
    String? take(String ns, String name) => values.remove('$ns/$name');
    final writing = take(_style, 'writing-mode');
    result.rightToLeft = switch (writing) {
      null || 'page' => false,
      'lr-tb' || 'lr' => false,
      'rl-tb' || 'rl' => true,
      _ => throw UnsupportedError('Unsupported ODT writing mode: $writing'),
    };
    final automatic = take(_style, 'writing-mode-automatic');
    if (automatic != null) {
      if (_boolean(automatic)) {
        if (writing != null && writing != 'page') {
          throw UnsupportedError(
            'Automatic ODT writing mode with an explicit direction.',
          );
        }
        result.rightToLeft = null;
      }
    }
    final alignment = take(_fo, 'text-align');
    if (alignment != null) {
      if (result.rightToLeft == null && {'start', 'end'}.contains(alignment)) {
        throw UnsupportedError(
          'Logical ODT alignment with automatic direction.',
        );
      }
      result.explicitJustification = true;
      result.justification = switch (alignment) {
        'left' => WmlJustification.left,
        'right' => WmlJustification.right,
        'center' => WmlJustification.center,
        'justify' => WmlJustification.justify,
        'start' =>
          result.rightToLeft == true
              ? WmlJustification.right
              : WmlJustification.left,
        'end' =>
          result.rightToLeft == true
              ? WmlJustification.left
              : WmlJustification.right,
        _ => throw UnsupportedError('Unsupported ODT alignment: $alignment'),
      };
    }
    final left = take(_fo, 'margin-left');
    final right = take(_fo, 'margin-right');
    final first = take(_fo, 'text-indent');
    if (left != null || right != null || first != null) {
      final logicalLeft = left == null
          ? 0.0
          : lengthPoints(left, allowNegative: true);
      final logicalRight = right == null
          ? 0.0
          : lengthPoints(right, allowNegative: true);
      final firstLine = first == null
          ? 0.0
          : lengthPoints(first, allowNegative: true);
      result.explicitIndent = true;
      result.indent = WmlIndent(
        left: result.rightToLeft == true ? logicalRight : logicalLeft,
        right: result.rightToLeft == true ? logicalLeft : logicalRight,
        firstLine: firstLine > 0 ? firstLine : 0,
        hanging: firstLine < 0 ? -firstLine : 0,
      );
    }
    final before = take(_fo, 'margin-top');
    final after = take(_fo, 'margin-bottom');
    if (before != null) {
      result.spacingBefore = lengthPoints(before);
      result.explicitSpacingBefore = true;
    }
    if (after != null) {
      result.spacingAfter = lengthPoints(after);
      result.explicitSpacingAfter = true;
    }
    final line = take(_fo, 'line-height');
    final minimumLine = take(_style, 'line-height-at-least');
    if (line != null && minimumLine != null) {
      throw UnsupportedError(
        'Combined ODT line-height and minimum line-height.',
      );
    }
    if (line != null) {
      result.explicitLineSpacing = true;
      if (line == 'normal') {
        result.lineSpacing = 1;
      } else if (line.endsWith('%')) {
        result.lineSpacing =
            _positiveNumber(line.substring(0, line.length - 1)) / 100;
      } else {
        result.lineSpacing = lengthPoints(line);
        result.lineSpacingRule = WmlLineSpacingRule.exact;
      }
      if (result.lineSpacing <= 0) {
        throw const FormatException('Zero ODT line height.');
      }
    }
    if (minimumLine != null) {
      result.lineSpacing = lengthPoints(minimumLine);
      if (result.lineSpacing <= 0) {
        throw const FormatException('Zero ODT minimum line height.');
      }
      result.lineSpacingRule = WmlLineSpacingRule.atLeast;
      result.explicitLineSpacing = true;
    }
    final keep = take(_fo, 'keep-together');
    if (keep != null) result.keepTogether = _autoAlways(keep);
    final next = take(_fo, 'keep-with-next');
    if (next != null && next != 'auto') {
      throw UnsupportedError('ODT keep-with-next.');
    }
    final breakBefore = take(_fo, 'break-before');
    if (breakBefore != null) {
      switch (breakBefore) {
        case 'auto':
          break;
        case 'page':
          result.pageBreakBefore = true;
        case 'column':
          result.columnBreakBefore = true;
        default:
          throw UnsupportedError('Unsupported ODT break: $breakBefore');
      }
    }
    final breakAfter = take(_fo, 'break-after');
    if (breakAfter != null && breakAfter != 'auto') {
      throw UnsupportedError('ODT break-after.');
    }
    final background = take(_fo, 'background-color');
    if (background != null && background != 'transparent') {
      result.shadingFill = _color(background);
    }
    final border = take(_fo, 'border');
    if (border != null && border != 'none') {
      final parts = border.trim().split(RegExp(r'\s+'));
      if (parts.length != 3 ||
          parts[1] != 'solid' ||
          (lengthPoints(parts[0]) - 0.5).abs() > 0.00001) {
        throw UnsupportedError(
          'ODT paragraph borders require a solid half-point border.',
        );
      }
      result.borderColor = _color(parts[2]);
    }
    final pageNumber = take(_style, 'page-number');
    if (pageNumber != null && pageNumber != 'auto') {
      throw UnsupportedError('ODT page-number restart.');
    }
    final autoIndent = take(_style, 'auto-text-indent');
    if (autoIndent != null && _boolean(autoIndent)) {
      throw UnsupportedError('Automatic ODT text indent.');
    }
    // These settings are evaluated after inheritance. Only inactive values or
    // values whose actual text use can be checked below are accepted. This is
    // deliberately not a general allowlist for a producer's style attributes.
    for (final (namespace, name) in [
      (_style, 'contextual-spacing'),
      (_style, 'justify-single-word'),
      (_loext, 'paragraph-composer'),
    ]) {
      final value = take(namespace, name);
      if (value != null && _boolean(value)) {
        throw UnsupportedError('Active ODT paragraph setting: $name');
      }
    }
    for (final (namespace, name, supported) in [
      (_fo, 'hyphenation-ladder-count', 'no-limit'),
      (_fo, 'hyphenation-keep', 'auto'),
      (_loext, 'hyphenation-keep-type', 'column'),
    ]) {
      final value = take(namespace, name);
      if (value != null && value != supported) {
        throw UnsupportedError('Unsupported ODT hyphenation setting: $name');
      }
    }
    final hyphenationKeepLine = take(_loext, 'hyphenation-keep-line');
    if (hyphenationKeepLine != null && _boolean(hyphenationKeepLine)) {
      throw UnsupportedError('Active ODT hyphenation keep-line.');
    }
    final autospace = take(_style, 'text-autospace');
    if (autospace != null && !{'none', 'ideograph-alpha'}.contains(autospace)) {
      throw UnsupportedError('Unsupported ODT text autospace: $autospace');
    }
    final punctuation = take(_style, 'punctuation-wrap');
    if (punctuation != null && !{'simple', 'hanging'}.contains(punctuation)) {
      throw UnsupportedError('Unsupported ODT punctuation wrap: $punctuation');
    }
    final lineBreak = take(_style, 'line-break');
    if (lineBreak != null && !{'normal', 'strict'}.contains(lineBreak)) {
      throw UnsupportedError('Unsupported ODT line-break rule: $lineBreak');
    }
    final tabDistance = take(_style, 'tab-stop-distance');
    final tabPoints = tabDistance == null ? null : lengthPoints(tabDistance);
    if (tabPoints != null && tabPoints <= 0) {
      throw const FormatException('ODT default tab distance must be positive.');
    }
    _paragraphContexts[styleName ?? ''] = _OdtParagraphContext(
      asianTypography:
          autospace == 'ideograph-alpha' ||
          punctuation == 'hanging' ||
          lineBreak != null,
      requiresKnownBreakLocale: punctuation == 'hanging' || lineBreak != null,
      defaultTabDistance: tabPoints,
    );
    _requireEmpty(values, 'paragraph');
    if (tabs != null) result.tabs = _tabs(tabs);
    final mark = paragraphRunProperties(styleName);
    if (heading != null) validateHeadingConfiguration();
    result.importedParagraphMark = mark.nativeProperties();
    result.proofingLanguage = mark.proofingLanguage;
    return result;
  }

  /// Qualifies conditional defaults against this paragraph's actual text.
  /// Asian typography and nonstandard implicit tabs are not represented by the
  /// native model. They may be dormant in a source style, but must not silently
  /// change an active paragraph. Explicit tab stops retain their own contract.
  void validateParagraphContent(String? styleName, WmlParagraph paragraph) {
    final context = _paragraphContexts[styleName ?? ''];
    if (context == null) return;
    final text = paragraph.text;
    // LibreOffice's CJK line-break iterator can hang ASCII punctuation too.
    // Its dispatch follows the effective language as well as the text script;
    // checking only for Han/Kana/Hangul characters would drop active behavior.
    var asianLocale = false;
    for (final run in paragraph.inlines.whereType<WmlRun>()) {
      // Note labels are materialized after source field offsets are attached.
      // They still use a visible normal-script number in this paragraph.
      if (run.text.isEmpty && run.noteRefId == null) continue;
      final normal =
          run.properties.proofingLanguage ??
          paragraph.properties.proofingLanguage;
      final complex = run.properties.complexScriptLanguage ?? normal;
      final languages = <String?>{
        if (wordRunUsesLatinScriptLanguage(run)) normal,
        if (wordRunUsesComplexScriptLanguage(run)) complex,
      };
      if (context.requiresKnownBreakLocale && languages.contains(null)) {
        throw UnsupportedError(
          'ODT paragraph typography requires an explicit supported break locale.',
        );
      }
      asianLocale = asianLocale || languages.any(_isAsianBreakLanguage);
    }
    if (context.asianTypography &&
        (_asianTypographyText.hasMatch(text) || asianLocale)) {
      throw UnsupportedError(
        'Active ODT Asian paragraph typography is not supported.',
      );
    }
    final distance = context.defaultTabDistance;
    // The native Word layout uses a 36 pt implicit interval. A source interval
    // differing from it needs a separate model/layout implementation, including
    // positions beyond the last explicit stop.
    if (distance != null &&
        (distance - 36).abs() > 0.00001 &&
        text.contains('\t')) {
      throw UnsupportedError(
        'Active ODT nonstandard default tab distance is not supported.',
      );
    }
  }

  /// Qualifies a native bibliography's section wrapper before flattening it.
  ///
  /// LibreOffice assigns even an ordinary Zotero TextSection an automatic
  /// section style. Only effective properties with no nested-region layout or
  /// protection effect are admitted. Page geometry is not a substitute for
  /// section-local margins, columns, background or note configuration.
  void validateBibliographySection(String? styleName) {
    if (styleName != null && styleName.isEmpty) {
      throw const FormatException('Empty ODT bibliography section style.');
    }
    final values = <String, String>{};
    XmlElement? columns;
    for (final definition in styleChain('section', styleName)) {
      if (!RegExp(r'^[ \t\r\n]*$').hasMatch(definition.text)) {
        throw UnsupportedError('ODT section style contains authored text.');
      }
      final properties = _singleChild(definition, _style, 'section-properties');
      if (properties == null) continue;
      _mergeProperties(values, properties);
      for (final child in properties.childElements) {
        if (child.namespaceUri != _style || child.localName != 'columns') {
          throw UnsupportedError(
            'Unsupported ODT bibliography section content.',
          );
        }
      }
      final ownColumns = _singleChild(properties, _style, 'columns');
      if (ownColumns != null) columns = ownColumns;
    }
    String? take(String ns, String name) => values.remove('$ns/$name');
    for (final name in ['editable', 'protect']) {
      final value = take(_style, name);
      if (value != null && _boolean(value)) {
        // ODF 1.3 20.265: editable means EditInReadonly, not IsProtected.
        // Neither an editing exception nor actual protection is represented.
        throw UnsupportedError(
          'Active ODT bibliography section setting: $name',
        );
      }
    }
    for (final name in ['margin-left', 'margin-right']) {
      final value = take(_fo, name);
      if (value != null && lengthPoints(value, allowNegative: true) != 0) {
        throw UnsupportedError(
          'ODT bibliography section margins are not supported.',
        );
      }
    }
    final background = take(_fo, 'background-color');
    if (background != null && background != 'transparent') {
      throw UnsupportedError(
        'ODT bibliography section backgrounds are not supported.',
      );
    }
    _requireEmpty(values, 'bibliography section');
    if (columns == null) return;
    _checkAttributes(columns, {
      _fo: {'column-count', 'column-gap'},
    });
    if (columns.childElements.isNotEmpty ||
        !RegExp(r'^[ \t\r\n]*$').hasMatch(columns.text)) {
      throw UnsupportedError('ODT bibliography section column content.');
    }
    final count = _attr(columns, _fo, 'column-count');
    // fo:column-count is required by the ODF schema when columns is present.
    if (count == null ||
        !RegExp(r'^[ \t\r\n]*\+?0*1[ \t\r\n]*$').hasMatch(count)) {
      throw UnsupportedError('ODT bibliography sections require one column.');
    }
    final gap = _attr(columns, _fo, 'column-gap');
    if (gap != null && lengthPoints(gap) != 0) {
      throw UnsupportedError(
        'ODT bibliography section column gaps are not supported.',
      );
    }
  }

  /// Applies the single compatible layout after the body has resolved styles.
  WmlFootnoteSeparator? applyPageLayout(
    WmlSection section, {
    bool hasFootnotes = false,
    bool libreOfficeZeroSeparatorLengths = false,
  }) {
    final names = <String>{..._usedMasters};
    if (_masters.isNotEmpty && (_implicitMasterUsed || names.isEmpty)) {
      names.add(_masters.keys.first);
    }
    if (names.isEmpty) return null;
    String? signature;
    WmlSection? resolved;
    WmlFootnoteSeparator? resolvedSeparator;
    var separatorInitialized = false;
    var compatibleSeparator = true;
    for (final name in names) {
      final master = _masters[name];
      if (master == null) {
        throw FormatException('Missing ODT master page: $name');
      }
      _checkAttributes(master, {
        _style: {'name', 'display-name', 'page-layout-name', 'next-style-name'},
        _draw: {'style-name'},
      });
      if (master.childElements.isNotEmpty ||
          !RegExp(r'^[ \t\r\n]*$').hasMatch(master.text)) {
        throw UnsupportedError('ODT master-page stories are not supported.');
      }
      final next = _attr(master, _style, 'next-style-name');
      if (next != null && next.isNotEmpty && next != name) {
        throw UnsupportedError(
          'Alternating ODT master pages are not supported.',
        );
      }
      final drawingStyle = _attr(master, _draw, 'style-name');
      if (drawingStyle != null) _validateDrawingPage(drawingStyle);
      final layoutName = _attr(master, _style, 'page-layout-name');
      final layout = _layouts[layoutName];
      if (layout == null) {
        throw FormatException('Missing ODT page layout: $layoutName');
      }
      final parsed = _pageLayout(
        layout,
        hasFootnotes: hasFootnotes,
        libreOfficeZeroSeparatorLengths: libreOfficeZeroSeparatorLengths,
      );
      final candidate = parsed.section;
      final separator = parsed.separator;
      final candidateSignature = [
        candidate.pageSize.width,
        candidate.pageSize.height,
        candidate.margins.left,
        candidate.margins.right,
        candidate.margins.top,
        candidate.margins.bottom,
        candidate.columnCount,
        candidate.columnSpace,
        if (hasFootnotes) ...[
          separator?.beforeSpacing,
          separator?.thickness,
          separator?.afterSpacing,
          separator?.relativeWidth,
          separator?.alignment,
          separator?.color,
          separator?.lineStyle,
        ],
      ].join('/');
      if (signature != null && candidateSignature != signature) {
        throw UnsupportedError(
          'Multiple applied ODT page layouts are not supported.',
        );
      }
      signature = candidateSignature;
      resolved = candidate;
      if (!separatorInitialized) {
        resolvedSeparator = separator;
        separatorInitialized = true;
      } else if (resolvedSeparator != separator) {
        compatibleSeparator = false;
      }
    }
    if (resolved != null) {
      section.pageSize = resolved.pageSize;
      section.margins = resolved.margins;
      section.columnCount = resolved.columnCount;
      section.columnSpace = resolved.columnSpace;
    }
    // Dormant presets outside the single native geometry retain the existing
    // validation-only behavior. Fully supported uniform presets survive even
    // when the last footnote has been deleted and a later edit may add one.
    return compatibleSeparator ? resolvedSeparator : null;
  }

  void _validateDrawingPage(String name) {
    if (name.isEmpty) {
      throw const FormatException('Empty ODT drawing-page style reference.');
    }
    final values = <String, String>{};
    for (final definition in styleChain('drawing-page', name)) {
      final properties = _singleChild(
        definition,
        _style,
        'drawing-page-properties',
      );
      if (properties == null) continue;
      if (properties.childElements.isNotEmpty) {
        throw UnsupportedError('ODT drawing-page background content.');
      }
      _mergeProperties(values, properties);
    }
    final fill = values.remove('$_draw/fill');
    if (fill != null && fill != 'none') {
      throw UnsupportedError('ODT page drawing background.');
    }
    final size = values.remove('$_draw/background-size');
    if (size != null && !{'full', 'border'}.contains(size)) {
      throw UnsupportedError('Unsupported ODT background size.');
    }
    _requireEmpty(values, 'drawing-page');
  }

  /// Converts an absolute ODF length. Relative and non-finite values reject.
  static double lengthPoints(String value, {bool allowNegative = false}) {
    final match = RegExp(
      r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+))(pt|pc|in|cm|mm)$',
    ).firstMatch(value.trim());
    if (match == null) throw UnsupportedError('Unsupported ODT length: $value');
    final number = double.parse(match[1]!);
    final scale = switch (match[2]) {
      'pt' => 1.0,
      'pc' => 12.0,
      'in' => 72.0,
      'cm' => 72 / 2.54,
      'mm' => 72 / 25.4,
      _ => 1.0,
    };
    final result = number * scale;
    if (!result.isFinite ||
        result.abs() > 1000000 ||
        (!allowNegative && result < 0)) {
      throw FormatException('Invalid ODT length: $value');
    }
    return result;
  }

  void _collect(XmlElement root) {
    for (final group in root.childElements) {
      if (group.namespaceUri != odfOfficeNamespace) continue;
      if (!{
        'styles',
        'automatic-styles',
        'font-face-decls',
        'master-styles',
      }.contains(group.localName)) {
        continue;
      }
      for (final definition in group.childElements) {
        if (++_definitionCount > maxDefinitions) {
          throw const FormatException('ODT style definition limit exceeded.');
        }
        final name = _attr(definition, _style, 'name');
        if (name != null && (name.isEmpty || name.length > 1024)) {
          throw const FormatException('Invalid ODT style name.');
        }
        if (definition.namespaceUri == _style &&
            definition.localName == 'font-face') {
          final family = _attr(definition, _svg, 'font-family');
          if (name == null || family == null) continue;
          final previous = _fonts[name];
          final resolved = family.trim();
          if (previous != null && previous != resolved) {
            throw FormatException('Ambiguous ODT font alias: $name');
          }
          _fonts[name] = resolved;
          if (definition.childElements.isNotEmpty) _unsupportedFonts.add(name);
        } else if (definition.namespaceUri == _style &&
            definition.localName == 'style') {
          final family = _attr(definition, _style, 'family');
          if (name == null || family == null) {
            throw const FormatException('Unnamed ODT style.');
          }
          _insert(_styles, '$family/$name', definition);
        } else if (definition.namespaceUri == _style &&
            definition.localName == 'default-style') {
          final family = _attr(definition, _style, 'family');
          if (family == null) {
            throw const FormatException('ODT default style has no family.');
          }
          _insert(_defaults, family, definition);
        } else if (definition.namespaceUri == odfTextNamespace &&
            definition.localName == 'list-style') {
          if (name == null) {
            throw const FormatException('Unnamed ODT list style.');
          }
          _insert(_lists, name, definition);
        } else if (definition.namespaceUri == _style &&
            definition.localName == 'master-page') {
          if (name == null) {
            throw const FormatException('Unnamed ODT master page.');
          }
          _insert(_masters, name, definition);
        } else if (definition.namespaceUri == _style &&
            definition.localName == 'page-layout') {
          if (name == null) {
            throw const FormatException('Unnamed ODT page layout.');
          }
          _insert(_layouts, name, definition);
        } else if (definition.namespaceUri == odfTextNamespace &&
            definition.localName == 'notes-configuration') {
          _noteConfigurations.add(definition);
        } else if (definition.namespaceUri == odfTextNamespace &&
            definition.localName == 'outline-style') {
          _outlineStyles.add(definition);
        }
      }
    }
  }

  static void _insert(
    Map<String, XmlElement> target,
    String key,
    XmlElement value,
  ) {
    if (target.containsKey(key)) {
      throw FormatException('Duplicate ODT style definition: $key');
    }
    target[key] = value;
  }

  static void _checkDefinition(XmlElement definition, String family) {
    if (_attr(definition, _style, 'family') != family) {
      throw const FormatException('Ambiguous ODT style family identity.');
    }
    _checkAttributes(definition, {
      _style: {
        'name',
        'family',
        'display-name',
        'parent-style-name',
        'class',
        'auto-update',
        if (family == 'paragraph') ...{
          'next-style-name',
          'default-outline-level',
          'master-page-name',
          'list-style-name',
        },
      },
      _xml: {'id'},
    });
    final list = _attr(definition, _style, 'list-style-name');
    if (list != null && list.isNotEmpty) {
      throw UnsupportedError('ODT paragraph style numbering is not supported.');
    }
    final update = _attr(definition, _style, 'auto-update');
    if (update != null && _boolean(update)) {
      throw UnsupportedError(
        'Automatically updating ODT styles are not supported.',
      );
    }
    final propertyNames = <String>{};
    for (final child in definition.childElements) {
      final allowed = switch (family) {
        'paragraph' => const {'text-properties', 'paragraph-properties'},
        'text' => const {'text-properties'},
        'table' => const {'table-properties'},
        'table-column' => const {'table-column-properties'},
        'table-row' => const {'table-row-properties'},
        'table-cell' => const {'table-cell-properties'},
        'section' => const {'section-properties'},
        'drawing-page' => const {'drawing-page-properties'},
        'graphic' => const {
          'graphic-properties',
          'paragraph-properties',
          'text-properties',
        },
        _ => const <String>{},
      };
      if (child.namespaceUri != _style || !allowed.contains(child.localName)) {
        throw UnsupportedError(
          'Unsupported used ODT style element: ${child.qualifiedName}',
        );
      }
      if (!propertyNames.add(child.localName)) {
        throw FormatException('Duplicate used ODT ${child.localName}.');
      }
    }
  }

  void _applyRun(OdtReaderTextStyle result, XmlElement element) {
    if (element.childElements.isNotEmpty) {
      throw UnsupportedError('Nested ODT text properties.');
    }
    final values = <String, String>{};
    _mergeProperties(values, element);
    String? take(String ns, String name) => values.remove('$ns/$name');
    final inheritedSize = result.fontSizeHalfPoints;
    final inheritedComplexSize = result.complex.size ?? inheritedSize;
    final inheritedAsianSize = result.asian.size ?? inheritedSize;
    final font = take(_fo, 'font-family');
    final alias = take(_style, 'font-name');
    if (font != null) result.asciiFont = _fontFamily(font);
    if (alias != null) {
      final declared = _resolveFont(alias);
      if (font != null && result.asciiFont != declared) {
        throw const FormatException('Conflicting ODT font family and alias.');
      }
      result.asciiFont = declared;
    }
    if (font != null || alias != null) {
      result.explicitProperties.add('asciiFont');
    }
    _fontHints(
      take(_style, 'font-family-generic'),
      take(_style, 'font-pitch'),
      named: result.explicitProperties.contains('asciiFont'),
    );
    for (final entry in {
      'complex': result.complex,
      'asian': result.asian,
    }.entries) {
      final script = entry.key;
      final slot = entry.value;
      final family = take(_style, 'font-family-$script');
      final scriptAlias = take(_style, 'font-name-$script');
      if (family != null) slot.font = _fontFamily(family);
      if (scriptAlias != null) {
        final declared = _resolveFont(scriptAlias);
        if (family != null && slot.font != declared) {
          throw FormatException(
            'Conflicting ODT $script font family and alias.',
          );
        }
        slot.font = declared;
      }
      if (script == 'complex' && slot.font != null) {
        result.csFont = slot.font!;
        result.explicitProperties.add('csFont');
      }
      _fontHints(
        take(_style, 'font-family-generic-$script'),
        take(_style, 'font-pitch-$script'),
        named: slot.font != null,
      );
    }
    if ((font != null || alias != null) &&
        !result.explicitProperties.contains('csFont')) {
      result.csFont = result.asciiFont;
    }
    final size = take(_fo, 'font-size');
    if (size != null) {
      result.fontSizeHalfPoints = _fontSize(size, inheritedSize);
      result.explicitProperties.add('fontSizeHalfPoints');
    }
    final weight = take(_fo, 'font-weight');
    if (weight != null) {
      result.bold = _weight(weight);
      result.explicitProperties.add('bold');
    }
    final italic = take(_fo, 'font-style');
    if (italic != null) {
      result.italic = _italic(italic);
      result.explicitProperties.add('italic');
    }
    for (final entry in {
      'complex': result.complex,
      'asian': result.asian,
    }.entries) {
      final script = entry.key;
      final slot = entry.value;
      final scriptSize = take(_style, 'font-size-$script');
      if (scriptSize != null) {
        slot.size = _fontSize(
          scriptSize,
          script == 'complex' ? inheritedComplexSize : inheritedAsianSize,
        );
      }
      final scriptWeight = take(_style, 'font-weight-$script');
      if (scriptWeight != null) slot.bold = _weight(scriptWeight);
      final scriptItalic = take(_style, 'font-style-$script');
      if (scriptItalic != null) slot.italic = _italic(scriptItalic);
    }
    final caps = take(_fo, 'font-variant');
    if (caps != null) {
      result.smallCaps = switch (caps) {
        'normal' => false,
        'small-caps' => true,
        _ => throw UnsupportedError('Unsupported ODT font variant: $caps'),
      };
      result.explicitProperties.add('smallCaps');
    }
    final color = take(_fo, 'color');
    if (color != null) {
      result.color = _color(color);
      // LibreOffice maps explicit color and use-window-font-color to the
      // same CharColor property. A child color replaces inherited automatic.
      result.automaticColor = false;
      result.explicitProperties.add('color');
    }
    final automaticColor = take(_style, 'use-window-font-color');
    if (automaticColor != null) {
      result.automaticColor = _boolean(automaticColor);
    }
    final opacity = take(_loext, 'opacity');
    if (opacity != null) {
      if (!RegExp(r'^(?:\d+(?:\.\d+)?|\.\d+)%$').hasMatch(opacity)) {
        throw const FormatException('Invalid ODT text opacity.');
      }
      final number = double.parse(opacity.substring(0, opacity.length - 1));
      if (!number.isFinite || number > 100) {
        throw const FormatException('Invalid ODT text opacity.');
      }
      result.opacity = number;
    }
    final transform = take(_fo, 'text-transform');
    if (transform != null) {
      // ODF uppercase is presentation formatting, like Word's w:caps. Keep
      // authored Unicode and the native citation's UTF-16 endpoints intact;
      // transforming the string would move fields after expanding characters.
      result.allCaps = switch (transform) {
        'none' => false,
        'uppercase' => true,
        _ => throw UnsupportedError(
          'Unsupported ODT text transformation: $transform',
        ),
      };
      result.explicitProperties.add('allCaps');
    }
    final opticalSizing = take(_loext, 'font-optical-sizing');
    if (opticalSizing != null && opticalSizing != 'auto') {
      throw UnsupportedError('Explicit ODT optical sizing is not supported.');
    }
    final background = take(_fo, 'background-color');
    if (background != null) {
      result.highlight = background == 'transparent'
          ? null
          : _color(background);
      result.explicitProperties.add('highlight');
    }
    // Writer stores its shading pattern separately from the background.
    // CharShadingValue 0 is CLEAR (no pattern), not a transparent background.
    // Require the same declaration's color: compound brush inheritance when
    // only shading is set has not been qualified against Writer output.
    // Solid/patterned/unknown values require a richer native brush model.
    final shading = take(_loext, 'char-shading-value');
    if (shading != null && (shading != '0' || background == null)) {
      throw UnsupportedError(
        'ODT character shading requires a clear pattern with an explicit background.',
      );
    }
    final underline = take(_style, 'text-underline-style');
    final underlineType = take(_style, 'text-underline-type');
    final underlineWidth = take(_style, 'text-underline-width');
    final underlineMode = take(_style, 'text-underline-mode');
    final underlineColor = take(_style, 'text-underline-color');
    if (underlineColor != null && underlineColor != 'font-color') {
      throw UnsupportedError('Distinct ODT underline color.');
    }
    if (underline != null ||
        underlineType != null ||
        underlineWidth != null ||
        underlineMode != null) {
      result.underline = _underline(
        underline ?? _underlineStyle(result.underline),
        underlineType ??
            (result.underline == WmlUnderline.double ||
                    result.underline == WmlUnderline.wavyDouble
                ? 'double'
                : 'single'),
        underlineWidth ?? (result.underline.isHeavy ? 'bold' : 'auto'),
        underlineMode ??
            (result.underline == WmlUnderline.words
                ? 'skip-white-space'
                : 'continuous'),
      );
      result.explicitProperties.add('underline');
    }
    final strike = take(_style, 'text-line-through-style');
    final strikeType = take(_style, 'text-line-through-type');
    if (strikeType != null && !{'none', 'single'}.contains(strikeType)) {
      throw UnsupportedError('Double ODT strike-through.');
    }
    if (strike != null || strikeType != null) {
      result.strike =
          strikeType != 'none' &&
          switch (strike ?? 'solid') {
            'none' => false,
            'solid' => true,
            _ => throw UnsupportedError(
              'Unsupported ODT strike-through: $strike',
            ),
          };
      result.explicitProperties.add('strike');
    }
    final position = take(_style, 'text-position');
    if (position != null) {
      result.vertAlign = switch (position.trim()) {
        'super' || 'super 65%' => WmlVertAlign.superscript,
        'sub' || 'sub 65%' => WmlVertAlign.subscript,
        '0%' || '0% 100%' => WmlVertAlign.baseline,
        _ => throw UnsupportedError(
          'Unsupported exact ODT text position: $position',
        ),
      };
      result.explicitProperties.add('vertAlign');
    }
    final language = take(_fo, 'language');
    final country = take(_fo, 'country');
    if (language != null || country != null) {
      result.proofingLanguage = _language(
        language,
        country,
        result.proofingLanguage,
      );
      result.explicitProperties.add('proofingLanguage');
      if (language != null) {
        result.noProof = language == 'none';
        result.explicitProperties.add('noProof');
      }
    }
    final csLanguage = take(_style, 'language-complex');
    final csCountry = take(_style, 'country-complex');
    if (csLanguage != null || csCountry != null) {
      result.complexScriptLanguage = _language(
        csLanguage,
        csCountry,
        result.complexScriptLanguage,
      );
      result.complex
        ..language = result.complexScriptLanguage
        ..languageSpecified = true;
      if (csLanguage != null) result.complex.noProof = csLanguage == 'none';
      result.explicitProperties.add('complexScriptLanguage');
    }
    final asianLanguage = take(_style, 'language-asian');
    final asianCountry = take(_style, 'country-asian');
    if (asianLanguage != null || asianCountry != null) {
      result.asian.language = _language(
        asianLanguage,
        asianCountry,
        result.asian.languageSpecified
            ? result.asian.language
            : result.proofingLanguage,
      );
      result.asian.languageSpecified = true;
      if (asianLanguage != null) result.asian.noProof = asianLanguage == 'none';
    }
    final kern = take(_style, 'letter-kerning');
    if (kern != null) {
      result.kerningHalfPoints = _boolean(kern) ? 1 : 0;
      result.explicitProperties.add('kerningHalfPoints');
    }
    final spacing = take(_fo, 'letter-spacing');
    if (spacing != null &&
        spacing != 'normal' &&
        lengthPoints(spacing, allowNegative: true) != 0) {
      throw UnsupportedError('ODT character spacing.');
    }
    final hyphenate = take(_fo, 'hyphenate');
    if (hyphenate != null) result.hyphenate = _boolean(hyphenate);
    // These parameters are dormant when effective automatic hyphenation is
    // off. Validate their values even though no native layout setting is made.
    for (final entry in {
      _fo: ['hyphenation-remain-char-count', 'hyphenation-push-char-count'],
      _loext: [
        'hyphenation-word-char-count',
        'hyphenation-compound-remain-char-count',
        'hyphenation-compound-push-char-count',
      ],
    }.entries) {
      for (final name in entry.value) {
        final value = take(entry.key, name);
        if (value == null) continue;
        if (!RegExp(r'^\d+$').hasMatch(value) || int.tryParse(value) == null) {
          throw FormatException('Invalid ODT $name.');
        }
      }
    }
    for (final name in ['hyphenation-no-caps', 'hyphenation-no-last-word']) {
      final value = take(_loext, name);
      if (value != null) _boolean(value);
    }
    final zone = take(_loext, 'hyphenation-zone');
    if (zone != null && zone != 'no-limit') lengthPoints(zone);
    _requireEmpty(values, 'text');
  }

  static int _fontSize(String value, int inheritedHalfPoints) {
    final halfPoints = value.endsWith('%')
        ? inheritedHalfPoints *
              _positiveNumber(value.substring(0, value.length - 1)) /
              100
        : lengthPoints(value) * 2;
    if (halfPoints < 1 ||
        halfPoints > 3276 ||
        (halfPoints - halfPoints.round()).abs() > 0.00001) {
      throw UnsupportedError(
        'ODT font size is outside exact half-point representation: $value',
      );
    }
    return halfPoints.round();
  }

  static void _fontHints(String? family, String? pitch, {required bool named}) {
    if (family == null && pitch == null) return;
    if (!named ||
        (family != null &&
            !{
              'decorative',
              'modern',
              'roman',
              'script',
              'swiss',
              'system',
            }.contains(family)) ||
        (pitch != null && !{'fixed', 'variable'}.contains(pitch))) {
      throw UnsupportedError('ODT font matching hints require a named family.');
    }
  }

  static WmlUnderline _underline(
    String style,
    String type,
    String width,
    String mode,
  ) {
    if (style == 'none' || type == 'none') return WmlUnderline.none;
    if (!{'single', 'double'}.contains(type) ||
        !{'auto', 'normal', 'bold'}.contains(width) ||
        !{'continuous', 'skip-white-space'}.contains(mode)) {
      throw UnsupportedError('Unsupported ODT underline dimensions.');
    }
    if (mode == 'skip-white-space') {
      if (style == 'solid' && type == 'single' && width != 'bold') {
        return WmlUnderline.words;
      }
      throw UnsupportedError('Unsupported ODT word underline.');
    }
    if (type == 'double') {
      if (width == 'bold') {
        throw UnsupportedError('Heavy double ODT underline.');
      }
      return switch (style) {
        'solid' => WmlUnderline.double,
        'wave' => WmlUnderline.wavyDouble,
        _ => throw UnsupportedError('Unsupported double ODT underline.'),
      };
    }
    final heavy = width == 'bold';
    return switch (style) {
      'solid' => heavy ? WmlUnderline.thick : WmlUnderline.single,
      'dotted' => heavy ? WmlUnderline.dottedHeavy : WmlUnderline.dotted,
      'dash' => heavy ? WmlUnderline.dashedHeavy : WmlUnderline.dash,
      'long-dash' => heavy ? WmlUnderline.dashLongHeavy : WmlUnderline.dashLong,
      'dot-dash' => heavy ? WmlUnderline.dashDotHeavy : WmlUnderline.dotDash,
      'dot-dot-dash' =>
        heavy ? WmlUnderline.dashDotDotHeavy : WmlUnderline.dotDotDash,
      'wave' => heavy ? WmlUnderline.wavyHeavy : WmlUnderline.wavy,
      _ => throw UnsupportedError('Unsupported ODT underline: $style'),
    };
  }

  static String _underlineStyle(WmlUnderline value) => switch (value) {
    WmlUnderline.none => 'none',
    WmlUnderline.single ||
    WmlUnderline.double ||
    WmlUnderline.thick ||
    WmlUnderline.words => 'solid',
    WmlUnderline.dotted || WmlUnderline.dottedHeavy => 'dotted',
    WmlUnderline.dash || WmlUnderline.dashedHeavy => 'dash',
    WmlUnderline.dashLong || WmlUnderline.dashLongHeavy => 'long-dash',
    WmlUnderline.dotDash || WmlUnderline.dashDotHeavy => 'dot-dash',
    WmlUnderline.dotDotDash || WmlUnderline.dashDotDotHeavy => 'dot-dot-dash',
    WmlUnderline.wavy ||
    WmlUnderline.wavyHeavy ||
    WmlUnderline.wavyDouble => 'wave',
  };

  static ({WmlSection section, WmlFootnoteSeparator? separator}) _pageLayout(
    XmlElement layout, {
    required bool hasFootnotes,
    required bool libreOfficeZeroSeparatorLengths,
  }) {
    _checkAttributes(layout, {
      _style: {'name', 'page-usage'},
    });
    final usage = _attr(layout, _style, 'page-usage');
    if (usage != null && usage != 'all') {
      throw UnsupportedError('ODT mirrored/parity page layout.');
    }
    final containers = <String>{};
    for (final child in layout.childElements) {
      if (child.namespaceUri != _style ||
          !{
            'page-layout-properties',
            'header-style',
            'footer-style',
          }.contains(child.localName)) {
        throw UnsupportedError('Unsupported ODT page layout child.');
      }
      if (!containers.add(child.localName)) {
        throw const FormatException('Duplicate ODT page-layout container.');
      }
      if (child.localName != 'page-layout-properties') {
        _checkAttributes(child, const {});
        if (child.childElements.isNotEmpty || child.text.trim().isNotEmpty) {
          throw UnsupportedError('ODT header/footer layout content.');
        }
      }
    }
    final properties = _singleChild(layout, _style, 'page-layout-properties');
    final result = WmlSection();
    if (properties == null) return (section: result, separator: null);
    final values = <String, String>{};
    _mergeProperties(values, properties);
    String? take(String ns, String name) => values.remove('$ns/$name');
    final width = take(_fo, 'page-width');
    final height = take(_fo, 'page-height');
    result.pageSize = WmlPageSize(
      width: width == null ? result.pageSize.width : lengthPoints(width),
      height: height == null ? result.pageSize.height : lengthPoints(height),
    );
    if (result.pageSize.width <= 0 || result.pageSize.height <= 0) {
      throw const FormatException('Invalid ODT page size.');
    }
    final orientation = take(_style, 'print-orientation');
    if (orientation != null &&
        orientation !=
            (result.pageSize.isLandscape ? 'landscape' : 'portrait')) {
      throw UnsupportedError('ODT orientation disagrees with page geometry.');
    }
    final margin = take(_fo, 'margin');
    final common = margin == null ? null : lengthPoints(margin);
    double side(String name, double fallback) {
      final value = take(_fo, name);
      return value == null ? common ?? fallback : lengthPoints(value);
    }

    result.margins = WmlPageMargins(
      left: side('margin-left', result.margins.left),
      right: side('margin-right', result.margins.right),
      top: side('margin-top', result.margins.top),
      bottom: side('margin-bottom', result.margins.bottom),
    );
    if (result.margins.left + result.margins.right >= result.pageSize.width ||
        result.margins.top + result.margins.bottom >= result.pageSize.height) {
      throw const FormatException('ODT margins consume the page.');
    }
    final writing = take(_style, 'writing-mode');
    if (writing != null && writing != 'lr-tb') {
      throw UnsupportedError('ODT page writing mode.');
    }
    final background = take(_fo, 'background-color');
    if (background != null && background != 'transparent') {
      throw UnsupportedError('ODT page background.');
    }
    final pageNumberFormat = take(_style, 'num-format');
    if (pageNumberFormat != null && pageNumberFormat != '1') {
      throw UnsupportedError('ODT page numbering format.');
    }
    final gutter = take(_loext, 'margin-gutter');
    if (gutter != null && lengthPoints(gutter) != 0) {
      throw UnsupportedError('ODT page gutter.');
    }
    final noteHeight = take(_style, 'footnote-max-height');
    if (noteHeight != null && lengthPoints(noteHeight) != 0) {
      throw UnsupportedError('ODT maximum footnote height.');
    }
    final grid = take(_style, 'layout-grid-mode');
    if (grid != null && grid != 'none') {
      throw UnsupportedError('Active ODT page layout grid.');
    }
    final gridColor = take(_style, 'layout-grid-color');
    if (gridColor != null) {
      if (grid != 'none') {
        throw UnsupportedError('ODT grid metadata without a disabled grid.');
      }
      _color(gridColor);
    }
    final gridLines = take(_style, 'layout-grid-lines');
    if (gridLines != null) {
      if (grid != 'none') {
        throw UnsupportedError('ODT grid metadata without a disabled grid.');
      }
      final count = int.tryParse(gridLines);
      if (count == null || count < 1 || count > 1000000) {
        throw const FormatException('Invalid ODT layout-grid line count.');
      }
    }
    for (final name in [
      'layout-grid-base-height',
      'layout-grid-base-width',
      'layout-grid-ruby-height',
    ]) {
      final value = take(_style, name);
      if (value != null) {
        if (grid != 'none') {
          throw UnsupportedError('ODT grid metadata without a disabled grid.');
        }
        lengthPoints(value);
      }
    }
    for (final name in [
      'layout-grid-ruby-below',
      'layout-grid-print',
      'layout-grid-display',
      'layout-grid-snap-to',
      'layout-grid-standard-mode',
    ]) {
      final value = take(_style, name);
      if (value != null) {
        if (grid != 'none') {
          throw UnsupportedError('ODT grid metadata without a disabled grid.');
        }
        _boolean(value);
      }
    }
    _requireEmpty(values, 'page layout');
    if (properties.childrenNamed('columns', namespaceUri: _style).length > 1) {
      throw const FormatException('Ambiguous ODT page columns.');
    }
    var hasSeparator = false;
    WmlFootnoteSeparator? separator;
    for (final child in properties.childElements) {
      if (child.namespaceUri == _style && child.localName == 'footnote-sep') {
        if (hasSeparator) {
          throw const FormatException('Duplicate ODT footnote separator.');
        }
        hasSeparator = true;
        _validateDormantFootnoteSeparator(child);
        try {
          separator = _activeFootnoteSeparator(
            child,
            libreOfficeZeroLengths: libreOfficeZeroSeparatorLengths,
          );
        } on UnsupportedError {
          if (hasFootnotes) rethrow;
        }
        continue;
      }
      if (child.namespaceUri != _style || child.localName != 'columns') {
        throw UnsupportedError('Unsupported ODT page-layout content.');
      }
      _checkAttributes(child, {
        _fo: {'column-count', 'column-gap'},
      });
      if (child.childElements.isNotEmpty) {
        throw UnsupportedError('Unequal ODT columns.');
      }
      final count = int.tryParse(_attr(child, _fo, 'column-count') ?? '1');
      if (count == null || count < 1 || count > 16) {
        throw const FormatException('Invalid ODT page column count.');
      }
      result.columnCount = count;
      final gap = _attr(child, _fo, 'column-gap');
      if (gap != null) result.columnSpace = lengthPoints(gap);
    }
    if (hasFootnotes &&
        separator != null &&
        separator.reservedHeight >= result.contentHeight) {
      throw UnsupportedError('ODT footnote separator consumes the page.');
    }
    return (section: result, separator: separator);
  }

  static void _validateDormantFootnoteSeparator(XmlElement separator) {
    _checkAttributes(separator, {
      _style: {
        'width',
        'distance-before-sep',
        'distance-after-sep',
        'line-style',
        'adjustment',
        'rel-width',
        'color',
      },
    });
    if (separator.childElements.isNotEmpty ||
        separator.text.trim().isNotEmpty) {
      throw UnsupportedError('ODT footnote separator content.');
    }
    for (final name in ['width', 'distance-before-sep', 'distance-after-sep']) {
      final value = _attr(separator, _style, name);
      if (value != null) lengthPoints(value);
    }
    final line = _attr(separator, _style, 'line-style');
    if (line != null && !{'none', 'solid', 'dotted', 'dash'}.contains(line)) {
      throw UnsupportedError('Unsupported ODT footnote separator line.');
    }
    final alignment = _attr(separator, _style, 'adjustment');
    if (alignment != null && !{'left', 'center', 'right'}.contains(alignment)) {
      throw UnsupportedError('Unsupported ODT footnote separator alignment.');
    }
    final width = _attr(separator, _style, 'rel-width');
    if (width != null) {
      final match = RegExp(r'^(\d+(?:\.\d+)?)%$').firstMatch(width);
      final percent = match == null ? null : double.tryParse(match[1]!);
      if (percent == null || !percent.isFinite || percent > 100) {
        throw const FormatException('Invalid ODT footnote separator width.');
      }
    }
    final color = _attr(separator, _style, 'color');
    if (color != null) _color(color);
  }

  /// Active separators need explicit geometry. ODF specifies only the default
  /// physical alignment; absent producer-dependent dimensions must not become
  /// invented defaults when opening an editable document.
  static WmlFootnoteSeparator _activeFootnoteSeparator(
    XmlElement element, {
    required bool libreOfficeZeroLengths,
  }) {
    String requiredValue(String name) =>
        _attr(element, _style, name) ??
        (throw UnsupportedError(
          'Active ODT footnote separator requires explicit $name.',
        ));
    final line = requiredValue('line-style');
    if (line != 'solid' && line != 'none') {
      throw UnsupportedError('Active ODT footnote separator line style.');
    }
    final relative = requiredValue('rel-width');
    double length(String name) {
      // The qualified stock LibreOffice exporter omits these three attributes
      // exactly when their lengths are zero. Generic ODF has no corresponding
      // normative defaults. Producer qualification never changes explicit data.
      final value = _attr(element, _style, name);
      if (value == null && libreOfficeZeroLengths) return 0;
      return lengthPoints(value ?? requiredValue(name));
    }

    final separator = WmlFootnoteSeparator(
      beforeSpacing: length('distance-before-sep'),
      thickness: length('width'),
      afterSpacing: length('distance-after-sep'),
      relativeWidth:
          double.parse(relative.substring(0, relative.length - 1)) / 100,
      alignment: switch (_attr(element, _style, 'adjustment') ?? 'left') {
        'left' => WmlFootnoteSeparatorAlignment.left,
        'center' => WmlFootnoteSeparatorAlignment.center,
        'right' => WmlFootnoteSeparatorAlignment.right,
        _ => throw UnsupportedError('Active ODT footnote separator alignment.'),
      },
      color: int.parse(_color(requiredValue('color')), radix: 16),
      lineStyle: line == 'solid'
          ? WmlFootnoteSeparatorLineStyle.solid
          : WmlFootnoteSeparatorLineStyle.none,
    );
    separator.validate();
    return separator;
  }

  static List<WmlTabStop> _tabs(XmlElement element) {
    _checkAttributes(element, const {});
    final result = <WmlTabStop>[];
    for (final tab in element.childElements) {
      if (result.length >= 256) {
        throw const FormatException('ODT tab-stop limit exceeded.');
      }
      if (tab.namespaceUri != _style ||
          tab.localName != 'tab-stop' ||
          tab.childElements.isNotEmpty) {
        throw UnsupportedError('Unsupported ODT tab stop.');
      }
      _checkAttributes(tab, {
        _style: {
          'position',
          'type',
          'char',
          'leader-type',
          'leader-style',
          'leader-text',
        },
      });
      final position = _attr(tab, _style, 'position');
      if (position == null) {
        throw const FormatException('ODT tab without position.');
      }
      final alignment = switch (_attr(tab, _style, 'type') ?? 'left') {
        'left' => WmlTabAlignment.left,
        'right' => WmlTabAlignment.right,
        'center' => WmlTabAlignment.center,
        'char' => WmlTabAlignment.decimal,
        _ => throw UnsupportedError('Unsupported ODT tab alignment.'),
      };
      final char = _attr(tab, _style, 'char');
      if (char != null &&
          (alignment != WmlTabAlignment.decimal || char != '.')) {
        throw UnsupportedError('Unsupported ODT decimal tab character.');
      }
      final leaderType = _attr(tab, _style, 'leader-type');
      if (leaderType != null &&
          leaderType != 'single' &&
          leaderType != 'none') {
        throw UnsupportedError('Unsupported ODT tab leader type.');
      }
      final leaderStyle = _attr(tab, _style, 'leader-style');
      final leaderText = _attr(tab, _style, 'leader-text');
      final leader = leaderType == 'none'
          ? WmlTabLeader.none
          : switch ((leaderStyle, leaderText)) {
              (null, null) || ('none', null) => WmlTabLeader.none,
              ('dotted', '.') => WmlTabLeader.dot,
              ('solid', '-') => WmlTabLeader.hyphen,
              ('solid', '_') => WmlTabLeader.underscore,
              _ => throw UnsupportedError('Unsupported ODT tab leader.'),
            };
      result.add(
        WmlTabStop(
          position: lengthPoints(position),
          alignment: alignment,
          leader: leader,
        ),
      );
    }
    return result;
  }

  static String? _attr(XmlElement e, String namespace, String name) =>
      e.getAttribute(name, namespaceUri: namespace);
  static XmlElement? _singleChild(XmlElement e, String namespace, String name) {
    final children = e.childrenNamed(name, namespaceUri: namespace);
    if (children.length > 1) throw FormatException('Duplicate ODT $name.');
    return children.isEmpty ? null : children.single;
  }

  static void _mergeProperties(Map<String, String> values, XmlElement e) {
    final seen = <String>{};
    for (final a in e.attributes) {
      if (a.prefix == 'xmlns' || a.qualifiedName == 'xmlns') continue;
      final key = '${a.namespaceUri}/${a.localName}';
      if (!seen.add(key)) {
        throw const FormatException('Duplicate ODT style attribute.');
      }
      values[key] = a.value;
    }
  }

  static void _checkAttributes(XmlElement e, Map<String, Set<String>> allowed) {
    final seen = <String>{};
    for (final a in e.attributes) {
      if (a.prefix == 'xmlns' || a.qualifiedName == 'xmlns') continue;
      if (!seen.add('${a.namespaceUri}/${a.localName}')) {
        throw const FormatException('Duplicate ODT style attribute.');
      }
      if (!(allowed[a.namespaceUri]?.contains(a.localName) ?? false)) {
        throw UnsupportedError(
          'Unsupported ODT ${e.localName} attribute: ${a.qualifiedName}',
        );
      }
    }
  }

  static void _requireEmpty(Map<String, String> values, String kind) {
    if (values.isNotEmpty) {
      throw UnsupportedError(
        'Unsupported ODT $kind property: ${values.keys.first}',
      );
    }
  }

  static String _fontFamily(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 1024 || trimmed.contains(',')) {
      throw UnsupportedError('Unsupported ODT font family list.');
    }
    if ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
        (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
      if (trimmed.length < 3) {
        throw const FormatException('Empty ODT font family.');
      }
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  String _resolveFont(String alias) {
    if (_unsupportedFonts.contains(alias)) {
      throw UnsupportedError('Embedded ODT font sources are not supported.');
    }
    final family = _fonts[alias];
    if (family == null) {
      throw FormatException('Missing ODT font alias: $alias');
    }
    return _fontFamily(family);
  }

  static String _color(String value) {
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      throw UnsupportedError('Unsupported ODT color: $value');
    }
    return value.substring(1).toUpperCase();
  }

  static bool _boolean(String value) => switch (value) {
    'true' || '1' => true,
    'false' || '0' => false,
    _ => throw FormatException('Invalid ODT boolean: $value'),
  };
  static bool _autoAlways(String value) => switch (value) {
    'auto' => false,
    'always' => true,
    _ => throw UnsupportedError('Unsupported ODT keep value: $value'),
  };
  static bool _weight(String value) => switch (value) {
    'normal' || '400' => false,
    'bold' || '700' => true,
    _ => throw UnsupportedError('Unsupported ODT font weight: $value'),
  };
  static bool _italic(String value) => switch (value) {
    'normal' => false,
    'italic' => true,
    _ => throw UnsupportedError('Unsupported ODT font style: $value'),
  };
  static double _positiveNumber(String value) {
    final result = double.tryParse(value);
    if (result == null || !result.isFinite || result <= 0 || result > 100000) {
      throw FormatException('Invalid ODT number: $value');
    }
    return result;
  }

  static String? _language(
    String? language,
    String? country,
    String? inherited,
  ) {
    final inheritedParts = inherited?.split('-');
    final base = language ?? inheritedParts?.first;
    if (base == 'none') {
      if (country != null && country != 'none') {
        throw const FormatException('ODT country without language.');
      }
      return null;
    }
    if (base == null || !RegExp(r'^[A-Za-z]{2,8}$').hasMatch(base)) {
      throw const FormatException('Invalid ODT language.');
    }
    final region =
        country ??
        ((inheritedParts?.length ?? 0) > 1 ? inheritedParts!.last : null);
    if (region == null || region == 'none') return base.toLowerCase();
    if (!RegExp(r'^(?:[A-Za-z]{2}|[0-9]{3})$').hasMatch(region)) {
      throw const FormatException('Invalid ODT country.');
    }
    return '${base.toLowerCase()}-${region.toUpperCase()}';
  }
}

final _asianTypographyText = RegExp(
  r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}'
  r'\p{Script=Hangul}\p{Script=Bopomofo}'
  r'\p{Script=Yi}\p{Script=Tangut}\p{Script=Khitan_Small_Script}'
  r'\u2e80-\u33ff\ufe10-\ufe1f\ufe30-\ufe4f\uff00-\uffef]',
  unicode: true,
);

bool _isAsianBreakLanguage(String? language) =>
    language != null &&
    {'zh', 'ja', 'ko'}.contains(language.split('-').first.toLowerCase());

final class _OdtParagraphContext {
  const _OdtParagraphContext({
    required this.asianTypography,
    required this.requiresKnownBreakLocale,
    required this.defaultTabDistance,
  });

  final bool asianTypography;
  final bool requiresKnownBreakLocale;
  final double? defaultTabDistance;
}
