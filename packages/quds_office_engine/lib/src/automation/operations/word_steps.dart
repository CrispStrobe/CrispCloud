import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_property_io.dart';

import 'step_input.dart';
import 'word_header_footer_guard.dart';
import 'word_list_steps.dart';
import 'word_page_setup_steps.dart';
import 'word_section_start_steps.dart';
import 'word_shading_steps.dart';
import 'word_spacing_steps.dart';
import 'word_structure_steps.dart';
import 'word_style_steps.dart';
import 'word_table_cell_text_steps.dart';
import 'word_text_columns_steps.dart';

const _storyFields = <String>['story', 'section', 'note', 'comment'];
const _formatStoryFields = <String>[..._storyFields, 'table', 'row', 'column'];
const _cellFormattingOperations = <String>{
  'runFormat',
  'paragraphFormat',
  'paragraphStyle',
  'paragraphShading',
  'tabStop',
  'clearTabStops',
  'lineSpacing',
  'paragraphSpaceBefore',
};
const wordOperations = <String, List<String>>{
  ...wordStructureOperations,
  'replaceText': ['paragraph', 'text', 'start', 'end', ..._storyFields],
  'heading': ['paragraph', 'level', ..._storyFields],
  'applyStyle': ['paragraph', 'style', ..._storyFields],
  'paragraphStyle': ['paragraph', 'name', 'builtin', ..._formatStoryFields],
  'paragraphShading': ['paragraph', 'color', ..._formatStoryFields],
  'characterStyle': ['paragraph', 'run', 'style', ..._storyFields],
  'tableStyle': ['table', 'style'],
  'styleDefinition': ['style', 'type', 'rPr', 'pPr', 'tblPr', 'tcPr'],
  'tabStop': [
    'paragraph',
    'position',
    'alignment',
    'leader',
    ..._formatStoryFields,
  ],
  'clearTabStops': ['paragraph', ..._formatStoryFields],
  'lineSpacing': ['paragraph', 'rule', 'points', ..._formatStoryFields],
  'paragraphSpaceBefore': ['paragraph', 'action', ..._formatStoryFields],
  'pageSetup': ['section', 'property', 'points'],
  'pageOrientation': ['section', 'orientation'],
  'sectionStart': ['section', 'kind'],
  'textColumns': ['section', 'count', 'spacing', 'lineBetween'],
  'paragraphFormat': [
    'paragraph',
    'alignment',
    'before',
    'after',
    'lineSpacing',
    'keepTogether',
    'pageBreakBefore',
    'suppressAutoHyphens',
    'rtl',
    'lineSpacingRule',
    'left',
    'right',
    'firstLine',
    'hanging',
    'tabs',
    'columnBreakBefore',
    'dropCapLines',
    'shading',
    'border',
    ..._formatStoryFields,
  ],
  'runFormat': [
    'paragraph',
    'start',
    'end',
    'bold',
    'italic',
    'color',
    'highlight',
    'font',
    'csFont',
    'language',
    'size',
    'kerning',
    'position',
    'noProof',
    'underline',
    'strike',
    'allCaps',
    'smallCaps',
    'superscript',
    'subscript',
    ..._formatStoryFields,
  ],
  'addNote': ['paragraph', 'text', 'endnote', 'offset'],
  'editNote': ['id', 'text', 'endnote'],
  'deleteNote': ['id', 'endnote'],
  'imageSize': ['image', 'width', 'height', ..._storyFields],
  'imageReplace': ['image', 'file', ..._storyFields],
  'imageAdd': ['section', 'index', 'file', 'width', 'height', 'title'],
  'imageRemove': ['image', ..._storyFields],
  'paragraphInsert': ['section', 'index', 'text', 'style'],
  'paragraphSplit': ['paragraph', 'offset'],
  'paragraphDelete': ['paragraph'],
  'list': ['paragraph', 'numbered', 'level'],
  'listClear': ['paragraph'],
  'listRestart': ['paragraph', 'at'],
  'listDefault': ['paragraph', 'numbered'],
  'listOutlineDefault': ['paragraph'],
  'listLevel': ['paragraph', 'level', 'delta'],
  'removeNumbers': ['paragraph', 'numberType'],
  'hyperlink': ['paragraph', 'run', 'target', ..._storyFields],
  'tableCellText': ['table', 'row', 'column', 'gridColumn', 'text'],
  'tableCellRangeText': ['table', 'row', 'column', 'text'],
  'tableCellRangeInsertBefore': ['table', 'row', 'column', 'text'],
  'headerFooterText': ['section', 'story', 'paragraph', 'text'],
  'sectionFormat': [
    'section',
    'width',
    'height',
    'top',
    'bottom',
    'left',
    'right',
    'header',
    'footer',
    'columns',
    'columnSpace',
    'columnSep',
    'breakKind',
    'differentFirstPage',
    'differentOddEven',
  ],
};

/// Apply one validated word-processing operation. Indices follow inspect output.
void applyStep(
  WmlDocument doc,
  Map<String, Object?> values, {
  OfficeMacroAssetResolver? resolveAsset,
}) {
  final s = StepInput(values);
  final op = s.string('op');
  final fields = wordOperations[op];
  if (fields == null) throw ArgumentError('Unknown DOCX operation: $op');
  s.fields(fields);
  _validateCellFormattingSelector(s, op);
  WmlParagraph paragraph() => s.item('paragraph', _paragraphs(doc, s));
  WmlSection section() => s.item('section', doc.sections, fallback: 0);
  WmlTable table() => s.item('table', _tables(doc));
  WmlVisual picture() {
    final value = s.item('image', _visuals(doc, s));
    if (!value.visual.isPicture) {
      throw ArgumentError('image must select a picture');
    }
    return value;
  }

  switch (op) {
    case 'replaceText':
      final p = paragraph();
      final range = _range(p, s);
      final text = s.string('text');
      final previousText = p.text;
      // Structural guards run before either text or revision metadata changes.
      WmlRunEdit.replaceRange(p, range.$1, range.$2, text);
      WordRevisions.rebaseEdit(
        doc,
        p,
        start: range.$1,
        end: range.$2,
        insertedLength: text.length,
        previousText: previousText,
      );
      _noteHint(p);
    case 'heading':
      WordHeadingIo.apply(doc, paragraph(), s.integer('level', max: 9));
      WordLink.ensureHeadingBookmarks(doc);
    case 'applyStyle':
      final style = s.string('style');
      if (WordStyles.byId(style, document: doc) == null) {
        throw ArgumentError('Unknown paragraph style: $style');
      }
      WordStyles.apply(paragraph(), style, document: doc);
    case 'paragraphStyle':
      setWordParagraphStyle(doc, paragraph(), s);
    case 'paragraphShading':
      // Validate ownership before the general paragraph selector traverses
      // the model, so malformed shared/cyclic trees cannot hide a target.
      final targets = wordShadingTargets(doc);
      setWordParagraphShading(
        doc,
        paragraph(),
        color: s.string('color'),
        targets: targets,
      );
    case 'characterStyle':
      final id = s.string('style');
      _sourceStyle(doc, id, 'character');
      s
              .item('run', paragraph().inlines.whereType<WmlRun>())
              .properties
              .styleId =
          id;
      WordDeserializer().refreshStyles(doc);
    case 'tableStyle':
      final id = s.string('style');
      _sourceStyle(doc, id, 'table');
      table().properties.styleId = id;
      WordDeserializer().refreshStyles(doc);
    case 'styleDefinition':
      _editStyle(doc, s);
    case 'tabStop':
      final position = s.number('position', min: -1584, max: 1584);
      final twips = position * 20;
      if (twips.round() / 20 != position) {
        throw ArgumentError('position must use exact 0.05-point increments');
      }
      final alignment = WmlTabAlignment.values.byName(
        s.string('alignment', fallback: 'left'),
      );
      final leader = WmlTabLeader.values.byName(
        s.string('leader', fallback: 'none'),
      );
      WordDeserializer().editParagraphTabStops(
        doc,
        paragraph(),
        tab: WmlTabStop(
          position: position,
          alignment: alignment,
          leader: leader,
        ),
      );
    case 'clearTabStops':
      WordDeserializer().editParagraphTabStops(doc, paragraph());
    case 'lineSpacing':
      setWordLineSpacing(
        doc,
        paragraph(),
        rule: s.string('rule'),
        points: s.number('points'),
      );
    case 'paragraphSpaceBefore':
      setWordParagraphSpaceBefore(doc, paragraph(), action: s.string('action'));
    case 'paragraphFormat':
      final target = paragraph();
      if (s.has('lineSpacing') || s.has('lineSpacingRule')) {
        validateWordLineSpacingSource(doc, target);
      }
      final p = target.properties.copy();
      List<WmlTabStop>? replacementTabs;
      // An explicit script assignment must remain direct formatting even
      // when the requested default equals the current inherited value.
      for (final entry in <String, String>{
        'alignment': 'jc',
        'before': 'spacing:before',
        'after': 'spacing:after',
        'lineSpacing': 'spacing:line',
        'keepTogether': 'keepLines',
        'pageBreakBefore': 'pageBreakBefore',
        'suppressAutoHyphens': 'suppressAutoHyphens',
        'rtl': 'bidi',
        'lineSpacingRule': 'spacing:line',
        'left': 'ind',
        'right': 'ind',
        'firstLine': 'ind',
        'hanging': 'ind',
        'dropCapLines': 'framePr',
        'shading': 'shd',
        'border': 'pBdr',
      }.entries) {
        if (s.has(entry.key)) p.importedValues?.remove(entry.value);
      }
      if (s.has('alignment')) {
        p.justification = WmlJustification.parse(s.string('alignment'));
        p.explicitJustification = true;
      }
      if (s.has('before')) {
        p.spacingBefore = s.number('before', min: 0);
        p.explicitSpacingBefore = true;
      }
      if (s.has('after')) {
        p.spacingAfter = s.number('after', min: 0);
        p.explicitSpacingAfter = true;
      }
      if (s.has('lineSpacing')) {
        p.lineSpacing = s.number('lineSpacing', min: 0.01);
        p.explicitLineSpacing = true;
      }
      if (s.has('lineSpacingRule')) {
        p.lineSpacingRule = WmlLineSpacingRule.values.byName(
          s.string('lineSpacingRule'),
        );
        p.explicitLineSpacing = true;
      }
      if (['left', 'right', 'firstLine', 'hanging'].any(s.has)) {
        p.indent = WmlIndent(
          left: s.number('left', fallback: p.indent.left),
          right: s.number('right', fallback: p.indent.right),
          firstLine: s.number(
            'firstLine',
            fallback: p.indent.firstLine,
            min: 0,
          ),
          hanging: s.number('hanging', fallback: p.indent.hanging, min: 0),
        );
        if (p.indent.firstLine != 0 && p.indent.hanging != 0) {
          throw ArgumentError('firstLine and hanging are mutually exclusive');
        }
        p.explicitIndent = true;
      }
      if (s.has('tabs')) {
        final input = values['tabs'];
        if (input is! List<Object?>) {
          throw ArgumentError('tabs must be an array');
        }
        final positions = <double>{};
        replacementTabs = [for (final value in input) _tab(value, positions)];
        replacementTabs.sort((a, b) => a.position.compareTo(b.position));
      }
      if (s.has('columnBreakBefore')) {
        p.columnBreakBefore = s.boolean('columnBreakBefore');
      }
      if (s.has('dropCapLines')) {
        p.dropCapLines = s.integer('dropCapLines', max: 10);
      }
      if (s.has('shading')) {
        p.shadingFill = values['shading'] == null ? null : s.color('shading');
      }
      if (s.has('border')) {
        p.borderColor = values['border'] == null ? null : s.color('border');
      }
      if (s.has('keepTogether')) p.keepTogether = s.boolean('keepTogether');
      if (s.has('pageBreakBefore')) {
        p.pageBreakBefore = s.boolean('pageBreakBefore');
      }
      if (s.has('suppressAutoHyphens')) {
        _validateScalarPackageSource(doc, const {'suppressAutoHyphens'});
        _validateScalarPropertySource(
          target.properties.sourcePropertiesXml,
          'suppressAutoHyphens',
        );
        p.suppressAutoHyphens = s.boolean('suppressAutoHyphens');
      }
      if (s.has('rtl')) p.rightToLeft = s.boolean('rtl');
      if (replacementTabs != null) {
        // Replacing a legacy native tabs array owns the full effective custom
        // set. Clear inherited positions before adding its requested stops;
        // prepare all formatting on a detached candidate before publication.
        WordDeserializer().editParagraphTabStops(
          doc,
          target,
          replacement: replacementTabs,
          paragraphProperties: p,
        );
      } else {
        target.properties = p;
      }
      if (s.has('columnBreakBefore') && !p.columnBreakBefore) {
        // A saved leading break reopens as an inline token. Clear that token
        // as well as the paragraph hint, without removing breaks within text.
        var index = 0;
        while (index < target.inlines.length) {
          final inline = target.inlines[index];
          if (inline is WmlRun && inline.text.isEmpty) {
            index++;
            continue;
          }
          if (inline is WmlBreak && inline.type == WmlBreakType.column) {
            target.inlines.removeAt(index);
          }
          break;
        }
      }
    case 'runFormat':
      final target = paragraph();
      // Public in-memory documents may share property objects or their import
      // snapshots even when their runs are uniquely owned. Prepare cell edits
      // on copied runs so formatting cannot leak into a neighboring paragraph.
      final p = values['story'] == 'tableCell'
          ? WmlClone.paragraph(target)
          : target;
      final range = _range(p, s);
      if (range.$1 == range.$2) {
        throw ArgumentError('runFormat requires a non-empty text range');
      }
      // Validate before applyRange splits source runs or touches their imported
      // property snapshots. A late invalid color must not partially bold text.
      final bold = s.has('bold') ? s.boolean('bold') : null;
      final italic = s.has('italic') ? s.boolean('italic') : null;
      final strike = s.has('strike') ? s.boolean('strike') : null;
      final allCaps = s.has('allCaps') ? s.boolean('allCaps') : null;
      final smallCaps = s.has('smallCaps') ? s.boolean('smallCaps') : null;
      if (allCaps == true && smallCaps == true) {
        throw ArgumentError(
          'allCaps and smallCaps cannot both be enabled in one runFormat operation',
        );
      }
      if (s.has('superscript') && s.has('subscript')) {
        throw ArgumentError(
          'Set only one of superscript or subscript per runFormat operation',
        );
      }
      final superscript = s.has('superscript')
          ? s.boolean('superscript')
          : null;
      final subscript = s.has('subscript') ? s.boolean('subscript') : null;
      final underline = s.has('underline')
          ? WmlUnderline.parse(s.string('underline'))
          : null;
      // Automatic foreground is a native value, not a fixed black color or
      // an omitted property that could revive an inherited theme color.
      final color = s.has('color')
          ? s.string('color') == 'auto'
                ? 'auto'
                : s.color('color')
          : null;
      final highlight = s.has('highlight') && values['highlight'] != null
          ? s.color('highlight')
          : null;
      final font = s.has('font') ? s.string('font') : null;
      final csFont = s.has('csFont')
          ? _complexScriptFont(s.string('csFont'))
          : null;
      final language = s.has('language')
          ? _runLanguage(s.string('language'))
          : null;
      final size = s.has('size')
          ? (s.number('size', min: 0.5, max: 1638) * 2).round()
          : null;
      final kerning = s.has('kerning')
          ? s.number('kerning', min: 0, max: 1638) * 2
          : null;
      if (kerning != null && kerning != kerning.truncateToDouble()) {
        throw ArgumentError('kerning must use exact 0.5-point increments');
      }
      final position = s.has('position')
          ? s.number('position', min: -1584, max: 1584) * 2
          : null;
      if (position != null && position != position.truncateToDouble()) {
        throw ArgumentError('position must use exact 0.5-point increments');
      }
      final noProof = s.has('noProof') ? s.boolean('noProof') : null;
      if (color != null ||
          kerning != null ||
          position != null ||
          noProof != null ||
          allCaps != null ||
          smallCaps != null ||
          font != null ||
          csFont != null ||
          language != null) {
        _validateScalarPackageSource(doc, {
          if (color != null) 'color',
          if (kerning != null) 'kern',
          if (position != null) ...{'position', 'noSpaceRaiseLower'},
          if (noProof != null) 'noProof',
          if (smallCaps != null || allCaps == true) 'smallCaps',
          if (allCaps != null || smallCaps == true) 'caps',
          if (font != null || csFont != null) 'rFonts',
          if (language != null) 'lang',
        });
        final affected = WmlRunEdit.normalizeRange(p, range.$1, range.$2);
        // Validate every affected source run before applyRange can split any
        // runs or publish earlier formatting fields on a later failure.
        var offset = 0;
        for (final run in p.inlines.whereType<WmlRun>()) {
          final end = offset + run.text.length;
          if (offset < affected.end && end > affected.start) {
            if (color != null) {
              _validateScalarPropertySource(
                run.properties.sourcePropertiesXml,
                'color',
                ownedAttributes: const {
                  'val',
                  'themeColor',
                  'themeShade',
                  'themeTint',
                },
              );
            }
            if (kerning != null) {
              _validateScalarPropertySource(
                run.properties.sourcePropertiesXml,
                'kern',
              );
            }
            if (position != null) {
              _validateScalarPropertySource(
                run.properties.sourcePropertiesXml,
                'position',
              );
            }
            if (noProof != null) {
              _validateScalarPropertySource(
                run.properties.sourcePropertiesXml,
                'noProof',
              );
            }
            if (font != null || csFont != null) {
              _validateScalarPropertySource(
                run.properties.sourcePropertiesXml,
                'rFonts',
                ownedAttributes: {
                  if (font != null) ...{
                    'ascii',
                    'hAnsi',
                    'asciiTheme',
                    'hAnsiTheme',
                  },
                  if (csFont != null) ...{'cs', 'cstheme'},
                },
              );
            }
            if (language != null) {
              _validateScalarPropertySource(
                run.properties.sourcePropertiesXml,
                'lang',
              );
            }
            if (smallCaps != null || allCaps == true) {
              _validateScalarPropertySource(
                run.properties.sourcePropertiesXml,
                'smallCaps',
              );
            }
            if (allCaps != null || smallCaps == true) {
              _validateScalarPropertySource(
                run.properties.sourcePropertiesXml,
                'caps',
              );
            }
          }
          offset = end;
        }
      }
      WmlRunEdit.applyRange(p, range.$1, range.$2, (r) {
        if (font != null || csFont != null) {
          final imported = r.importedValues;
          if (imported != null &&
              r.sourcePropertiesXml != null &&
              imported['rFonts:granular'] != '1' &&
              !imported.containsKey('rFonts:ascii') &&
              !imported.containsKey('rFonts:cs')) {
            // Preserve pending legacy edits before establishing independent
            // slot baselines. A same-value cs write must become direct even
            // when the old aggregate snapshot has not changed.
            r.sourcePropertiesXml = WordSerializer().runPropertiesXml(r);
            r.importedValues = WordPropertyIo.runValues(r);
          }
        }
        // Word enabling either capitalization mode explicitly disables the
        // other, including an inherited true value. A false assignment owns
        // only its named property and retains the other mode unchanged.
        if (smallCaps == true) {
          r.allCaps = false;
          r.importedValues?.remove('caps');
          r.explicitProperties.add('caps');
        }
        if (allCaps == true) {
          r.smallCaps = false;
          r.importedValues?.remove('smallCaps');
          r.explicitProperties.add('smallCaps');
        }
        for (final entry in <String, String>{
          'bold': 'b',
          'italic': 'i',
          'strike': 'strike',
          'allCaps': 'caps',
          'smallCaps': 'smallCaps',
          'superscript': 'vertAlign',
          'subscript': 'vertAlign',
          'underline': 'u',
          'color': 'color',
          'highlight': 'highlight',
          'font': 'rFonts:ascii',
          'csFont': 'rFonts:cs',
          'language': 'lang',
          'size': 'sz',
          'kerning': 'kern',
          'position': 'position',
          'noProof': 'noProof',
        }.entries) {
          if (s.has(entry.key)) {
            r.importedValues?.remove(entry.value);
            r.explicitProperties.add(entry.value);
          }
        }
        if (bold != null) r.bold = bold;
        if (italic != null) r.italic = italic;
        if (strike != null) r.strike = strike;
        if (allCaps != null) r.allCaps = allCaps;
        if (smallCaps != null) r.smallCaps = smallCaps;
        if (superscript != null) {
          if (superscript) {
            r.vertAlign = WmlVertAlign.superscript;
          } else if (r.vertAlign == WmlVertAlign.superscript) {
            r.vertAlign = WmlVertAlign.baseline;
          }
        }
        if (subscript != null) {
          if (subscript) {
            r.vertAlign = WmlVertAlign.subscript;
          } else if (r.vertAlign == WmlVertAlign.subscript) {
            r.vertAlign = WmlVertAlign.baseline;
          }
        }
        if (underline != null) r.underline = underline;
        if (color != null) r.color = color;
        if (s.has('highlight')) r.highlight = highlight;
        if (font != null) r.asciiFont = font;
        if (csFont != null) r.csFont = csFont;
        if (language != null) r.proofingLanguage = language;
        if (size != null) r.fontSizeHalfPoints = size;
        if (kerning != null) r.kerningHalfPoints = kerning.toInt();
        if (position != null) r.positionHalfPoints = position.toInt();
        if (noProof != null) r.noProof = noProof;
      });
      if (!identical(p, target)) target.inlines = p.inlines;
    case 'addNote':
      final p = paragraph();
      final at = s.integer(
        'offset',
        fallback: p.text.length,
        max: p.text.length,
      );
      _boundary(p, at);
      WordNotes.insert(
        doc,
        p,
        endnote: s.boolean('endnote', fallback: false),
        text: s.string('text'),
      );
      final mark = p.inlines.removeLast() as WmlRun;
      WmlRunEdit.insertRuns(p, at, <WmlRun>[mark]);
      _noteHint(p);
    case 'editNote':
      final note = WordNotes.byId(
        doc,
        s.integer('id'),
        endnote: s.boolean('endnote', fallback: false),
      );
      if (note == null) throw ArgumentError('Unknown note id');
      note.text = s.string('text');
    case 'deleteNote':
      if (!WordNotes.delete(
        doc,
        s.integer('id'),
        endnote: s.boolean('endnote', fallback: false),
      )) {
        throw ArgumentError('Unknown note id');
      }
    case 'imageSize':
      final image = picture().visual;
      if (!s.has('width') && !s.has('height')) {
        throw ArgumentError('imageSize needs width or height');
      }
      final width = s.has('width') ? s.number('width', min: 0.01) : image.width;
      final height = s.has('height')
          ? s.number('height', min: 0.01)
          : image.height;
      image
        ..width = width
        ..height = height;
    case 'imageReplace':
      picture().visual.imageBytes = readPicture(s, resolveAsset);
    case 'imageAdd':
      final blocks = section().blocks;
      final at = s.integer(
        'index',
        fallback: blocks.length,
        max: blocks.length,
      );
      final visual = OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: s.string('title', fallback: ''),
        imageBytes: readPicture(s, resolveAsset),
        width: s.number('width', min: 0.01),
        height: s.number('height', min: 0.01),
      );
      blocks.insert(at, WmlVisual(visual: visual));
    case 'imageRemove':
      final image = picture();
      if (!_removeVisual(doc, image)) {
        throw StateError('Picture container not found');
      }
    case 'paragraphInsert':
      final blocks = section().blocks;
      final at = s.integer(
        'index',
        fallback: blocks.length,
        max: blocks.length,
      );
      final p = WmlParagraph(
        inlines: <WmlInline>[WmlRun(text: s.string('text'))],
      );
      if (s.has('style')) {
        final id = s.string('style');
        if (WordStyles.byId(id, document: doc) == null) {
          throw ArgumentError('Unknown paragraph style: $id');
        }
        WordStyles.apply(p, id, document: doc);
      }
      blocks.insert(at, p);
    case 'paragraphSplit':
      final p = paragraph();
      final at = s.integer('offset', max: p.text.length);
      _boundary(p, at);
      final container = _container(doc, p);
      final split = WmlClone.splitInlines(p, at);
      // Like Return in Word: a paragraph split off at the end continues the
      // character formatting in force there (not the document defaults).
      if (!split.tail.any((inline) => inline is WmlRun)) {
        final props = WmlRunEdit.propsAt(p, at).copy();
        // A link's character style does not continue past the link.
        if (props.styleId == 'Hyperlink' ||
            props.styleId == 'FollowedHyperlink') {
          props.styleId = null;
        }
        split.tail.insert(0, WmlRun(properties: props));
      }
      final tail = WmlParagraph(
        properties: p.properties.copy()
          ..bookmarkName = null
          ..listRestart = null,
        inlines: split.tail,
      );
      p.inlines
        ..clear()
        ..addAll(split.head);
      _noteHint(p);
      _noteHint(tail);
      container.insert(container.indexOf(p) + 1, tail);
    case 'paragraphDelete':
      final p = paragraph();
      final container = _container(doc, p);
      if (WordBookmarks.ranges(doc).any(
        (range) =>
            identical(range.startParagraph, p) !=
            identical(range.endParagraph, p),
      )) {
        throw ArgumentError(
          'Deleting this paragraph would orphan a cross-paragraph bookmark endpoint',
        );
      }
      container.remove(p);
      if (container.isEmpty) container.add(WmlParagraph());
    case 'list':
      WordLists.applyLevel(
        paragraph(),
        numbered: s.boolean('numbered'),
        level: s.integer('level', fallback: 0, max: 8),
        document: doc,
      );
    case 'listDefault':
      applyDefaultWordList(doc, paragraph(), numbered: s.boolean('numbered'));
    case 'listOutlineDefault':
      applyDefaultWordOutline(doc, paragraph());
    case 'listLevel':
      changeWordListLevel(
        doc,
        paragraph(),
        level: s.has('level') ? s.integer('level', max: 8) : null,
        delta: s.has('delta') ? s.integer('delta', min: -1, max: 1) : null,
      );
    case 'removeNumbers':
      removeWordNumbers(
        doc,
        paragraph(),
        numberType: s.string('numberType', fallback: 'all'),
      );
    case 'listClear':
      WordLists.clear(paragraph());
    case 'listRestart':
      final p = paragraph();
      if (p.properties.numId == null) {
        throw ArgumentError('Paragraph is not a list');
      }
      WordLists.restart(p, at: s.integer('at', fallback: 1));
    case 'hyperlink':
      final run = s.item('run', paragraph().inlines.whereType<WmlRun>());
      run.hyperlink = WmlHyperlink.fromTarget(s.string('target'));
    case 'tableCellText':
      final cell = wordStepCell(table(), s).cell;
      final text = s.string('text');
      checkWordCellReplacement(doc, cell);
      cell.blocks
        ..clear()
        ..add(WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]));
    case 'tableCellRangeText':
      setWordTableCellRangeText(doc, s);
    case 'tableCellRangeInsertBefore':
      insertBeforeWordTableCellRange(doc, s);
    case 'headerFooterText':
      final story = s.string('story');
      if (!_headerStories.contains(story)) {
        throw ArgumentError('Expected a header/footer story');
      }
      final paragraphs = _headerParagraphs(section(), story);
      final at = s.integer('paragraph', fallback: 0, max: paragraphs.length);
      final text = s.string('text');
      if (at == paragraphs.length) paragraphs.add(WmlParagraph());
      final p = paragraphs[at];
      WmlRunEdit.replaceRange(p, 0, p.text.length, text);
    case 'pageSetup':
      setWordPageSetup(
        doc,
        s.item('section', doc.sections),
        property: s.string('property'),
        points: s.number('points'),
      );
    case 'pageOrientation':
      setWordPageOrientation(
        doc,
        s.item('section', doc.sections),
        orientation: s.string('orientation'),
      );
    case 'sectionStart':
      setWordSectionStart(
        doc,
        s.item('section', doc.sections),
        kind: s.string('kind'),
      );
    case 'textColumns':
      if (['count', 'spacing', 'lineBetween'].where(s.has).length != 1) {
        throw ArgumentError(
          'Text columns require exactly one of count, spacing, or lineBetween.',
        );
      }
      setWordTextColumns(
        doc,
        s.item('section', doc.sections),
        count: s.has('count') ? s.integer('count', min: 1, max: 45) : null,
        spacing: s.has('spacing') ? s.number('spacing', min: 0) : null,
        lineBetween: s.has('lineBetween') ? s.boolean('lineBetween') : null,
      );
    case 'sectionFormat':
      final sec = section();
      final width = s.number('width', fallback: sec.pageSize.width, min: 1);
      final height = s.number('height', fallback: sec.pageSize.height, min: 1);
      final old = sec.margins;
      final margins = WmlPageMargins(
        top: s.number('top', fallback: old.top, min: 0),
        bottom: s.number('bottom', fallback: old.bottom, min: 0),
        left: s.number('left', fallback: old.left, min: 0),
        right: s.number('right', fallback: old.right, min: 0),
        header: s.number('header', fallback: old.header, min: 0),
        footer: s.number('footer', fallback: old.footer, min: 0),
      );
      if (margins.left + margins.right >= width ||
          margins.top + margins.bottom >= height) {
        throw ArgumentError('Margins leave no page body');
      }
      final columns = s.integer(
        'columns',
        fallback: sec.columnCount,
        min: 1,
        max: 45,
      );
      final gap = s.number('columnSpace', fallback: sec.columnSpace, min: 0);
      if (gap * (columns - 1) >= width - margins.left - margins.right) {
        throw ArgumentError('Columns leave no text width');
      }
      final separator = s.boolean('columnSep', fallback: sec.columnSep);
      final breakKind = s.has('breakKind')
          ? WmlSectionBreakKind.values.byName(s.string('breakKind'))
          : sec.breakKind;
      final firstPage = s.boolean(
        'differentFirstPage',
        fallback: sec.differentFirstPage,
      );
      final oddEven = s.boolean(
        'differentOddEven',
        fallback: sec.differentOddEven,
      );
      sec.pageSize = WmlPageSize(width: width, height: height);
      sec.margins = margins;
      sec.columnCount = columns;
      sec.columnSpace = gap;
      sec.columnSep = separator;
      sec.breakKind = breakKind;
      sec.differentFirstPage = firstPage;
      sec.differentOddEven = oddEven;
    default:
      applyWordStructureStep(doc, values);
  }
}

const _headerStories = <String>{
  'header',
  'footer',
  'firstHeader',
  'firstFooter',
  'evenHeader',
  'evenFooter',
};
List<WmlParagraph> _headerParagraphs(WmlSection s, String story) =>
    switch (story) {
      'header' => s.header,
      'footer' => s.footer,
      'firstHeader' => s.firstHeader,
      'firstFooter' => s.firstFooter,
      'evenHeader' => s.evenHeader,
      'evenFooter' => s.evenFooter,
      _ => throw ArgumentError('Unknown story: $story'),
    };
List<WmlVisual> _headerVisuals(WmlSection s, String story) => switch (story) {
  'header' => s.headerVisuals,
  'footer' => s.footerVisuals,
  'firstHeader' => s.firstHeaderVisuals,
  'firstFooter' => s.firstFooterVisuals,
  'evenHeader' => s.evenHeaderVisuals,
  'evenFooter' => s.evenFooterVisuals,
  _ => throw ArgumentError('Unknown story: $story'),
};
WmlNote _note(WmlDocument doc, StepInput s, String story) {
  final result = WordNotes.byId(
    doc,
    s.integer('note'),
    endnote: story == 'endnote',
  );
  if (result == null) throw ArgumentError('Unknown $story id');
  return result;
}

void _validateScalarPackageSource(WmlDocument document, Set<String> names) {
  final package = document.package;
  if (package == null) return;
  for (final part in package.parts) {
    if (!part.contentType.endsWith('+xml') ||
        (!part.contentType.contains('wordprocessingml') &&
            !part.contentType.contains('vnd.ms-word'))) {
      continue;
    }
    // Import projects selected MC branches before retaining pPr/rPr snapshots.
    // Inspect raw Word XML as well, so a projected value cannot conceal a
    // competing branch that another consumer would select on reopening.
    final source = package.getPart(part.uri)!.readText();
    if ((names.contains('position') || names.contains('color')) &&
        source.contains('rPr')) {
      _validateRunPropertyOwnership(source);
    }
    if (!source.contains('AlternateContent') &&
        !source.contains('ProcessContent')) {
      continue;
    }
    for (final name in names) {
      if (source.contains(name)) _validateScalarPropertySource(source, name);
    }
  }
}

void _validateRunPropertyOwnership(String source) {
  final root = XmlDocument.parse(source).root;
  if (root == null) return;
  bool word(XmlElement element, String name) =>
      element.localName == name &&
      (element.namespaceUri == OfficeNamespaces.w ||
          (element.namespaceUri.isEmpty && element.prefix == 'w'));
  void checkRun(XmlElement run) {
    var properties = 0;
    void visitContent(XmlElement parent, {required bool direct}) {
      for (final child in parent.childElements) {
        if (child.localName == 'rPr') {
          if (!direct || !word(child, 'rPr') || ++properties > 1) {
            throw UnsupportedError(
              'Refuses foreign, nested, or duplicate run-property ownership',
            );
          }
          // Native rPr owns its retained extension metadata and rPrChange;
          // neither is another direct run-property container.
          continue;
        }
        // These subtrees are consumed as independent text/field/drawing
        // objects by the importer, so their properties do not own this run.
        if (const {
              't',
              'delText',
              'instrText',
              'fldChar',
              'object',
              'drawing',
              'OLEObject',
            }.contains(child.localName) ||
            word(child, 'pict')) {
          continue;
        }
        visitContent(child, direct: false);
      }
    }

    visitContent(run, direct: true);
  }

  void visit(XmlElement node) {
    if (word(node, 'r')) checkRun(node);
    for (final child in node.childElements) {
      if (!word(child, 'rPr')) visit(child);
    }
  }

  visit(root);
}

void _validateScalarPropertySource(
  String? source,
  String name, {
  Set<String> ownedAttributes = const {'val'},
}) {
  if (source == null || source.isEmpty) return;
  final properties = XmlDocument.parse(source).root;
  if (properties == null) return;
  bool nativeName(String namespace, String prefix) =>
      namespace == OfficeNamespaces.w || (namespace.isEmpty && prefix == 'w');
  if ((name == 'position' || name == 'color') &&
      properties.localName == 'rPr' &&
      !nativeName(properties.namespaceUri, properties.prefix)) {
    throw UnsupportedError('Refuses $name in a foreign run-property root');
  }
  bool containsControl(XmlElement node) =>
      (node.localName == name && nativeName(node.namespaceUri, node.prefix)) ||
      node.childElements.any(containsControl);
  void checkAlternatives(XmlElement node) {
    final alternate =
        node.localName == 'AlternateContent' &&
        node.namespaceUri == OfficeNamespaces.mc;
    final processContent = node.attributes.any(
      (attribute) =>
          attribute.localName == 'ProcessContent' &&
          attribute.namespaceUri == OfficeNamespaces.mc,
    );
    if ((alternate || processContent) && containsControl(node)) {
      throw UnsupportedError(
        'Refuses $name in markup-compatibility alternatives or processed content',
      );
    }
    for (final child in node.childElements) {
      checkAlternatives(child);
    }
  }

  checkAlternatives(properties);
  final values = properties.childElements
      .where(
        (element) =>
            element.localName == name &&
            nativeName(element.namespaceUri, element.prefix),
      )
      .toList(growable: false);
  if (values.length > 1) {
    throw UnsupportedError('Refuses duplicate native $name properties');
  }
  if (values.isNotEmpty) {
    for (final owned in ownedAttributes) {
      if (values.single.attributes
              .where(
                (attribute) =>
                    attribute.localName == owned &&
                    nativeName(attribute.namespaceUri, attribute.prefix),
              )
              .length >
          1) {
        throw UnsupportedError('Refuses duplicate native $name $owned values');
      }
    }
    if (name == 'position') {
      final raw = values.single.getAttribute(
        'val',
        namespaceUri: OfficeNamespaces.w,
      );
      final value =
          raw == null || !RegExp(r'^[+-]?[0-9]+$').hasMatch(raw.trim())
          ? null
          : int.tryParse(raw.trim());
      if (value == null || value < -2147483648 || value > 2147483647) {
        throw UnsupportedError('Refuses an unsupported native position value');
      }
    }
    if ((name == 'position' || name == 'color') &&
        values.single.childElements.any(
          (child) => nativeName(child.namespaceUri, child.prefix),
        )) {
      throw UnsupportedError('Refuses nested native $name content');
    }
  }
}

String _runLanguage(String value) {
  // This is an intentionally conservative BCP 47 subset, without implicit
  // normalization, extension sequences, or private-use language identifiers.
  // Proofing-provider normalization is unsuitable: it changes tags (for
  // example en-Latn-US) and deliberately leaves malformed unknown tags intact.
  if (value.length > 63 ||
      !RegExp(
        r'^[a-z]{2,3}(?:-[A-Z][a-z]{3})?(?:-(?:[A-Z]{2}|[0-9]{3}))?'
        r'(?:-(?:[a-z0-9]{5,8}|[0-9][a-z0-9]{3}))*$',
      ).hasMatch(value)) {
    throw ArgumentError('language must be a canonical supported BCP 47 tag');
  }
  final variants = <String>{};
  for (final part in value.split('-').skip(1)) {
    if ((part.length >= 5 ||
            (part.length == 4 &&
                part.codeUnitAt(0) >= 48 &&
                part.codeUnitAt(0) <= 57)) &&
        !variants.add(part)) {
      throw ArgumentError('language must not repeat variant subtags');
    }
  }
  return value;
}

String _complexScriptFont(String value) {
  if (value.isEmpty) throw ArgumentError('csFont must not be empty');
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit < 0x20 || unit == 0xfffe || unit == 0xffff) {
      throw ArgumentError('csFont must be XML-safe text without controls');
    }
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= value.length) {
        throw ArgumentError('csFont must contain valid UTF-16');
      }
      final trail = value.codeUnitAt(index);
      if (trail < 0xdc00 || trail > 0xdfff) {
        throw ArgumentError('csFont must contain valid UTF-16');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw ArgumentError('csFont must contain valid UTF-16');
    }
  }
  return value;
}

void _validateCellFormattingSelector(StepInput s, String op) {
  final cellStory = s.values['story'] == 'tableCell';
  if (!cellStory) {
    if (_cellFormattingOperations.contains(op) &&
        const ['table', 'row', 'column'].any(s.has)) {
      throw ArgumentError(
        'Cell formatting coordinates require story: tableCell',
      );
    }
    return;
  }
  if (!_cellFormattingOperations.contains(op)) {
    throw UnsupportedError('The tableCell story supports only cell formatting');
  }
  if (const ['section', 'note', 'comment', 'start', 'end'].any(s.has)) {
    throw ArgumentError(
      'Cell formatting requires the whole cell paragraph without other story '
      'selectors or text offsets',
    );
  }
  s.integer('paragraph', max: 0);
  for (final field in const ['table', 'row', 'column']) {
    s.integer(field);
  }
}

Iterable<WmlParagraph> _paragraphs(WmlDocument doc, StepInput s) {
  final story = s.string('story', fallback: 'body');
  if (story == 'tableCell') {
    return [editableWordTableCellRangeParagraph(doc, s)];
  }
  if (story == 'body') return doc.paragraphs;
  if (story == 'comment') return _comment(doc, s).paragraphs;
  if (story == 'footnote' || story == 'endnote') {
    return _note(doc, s, story).allParagraphs;
  }
  return editableWordHeaderFooterParagraphs(
    doc,
    s.item('section', doc.sections, fallback: 0),
    story,
  );
}

Iterable<WmlVisual> _visuals(WmlDocument doc, StepInput s) {
  final story = s.string('story', fallback: 'body');
  if (story == 'body') return doc.visuals;
  if (story == 'comment') return _comment(doc, s).visuals;
  if (story == 'footnote' || story == 'endnote') {
    return _note(doc, s, story).visuals;
  }
  return _headerVisuals(s.item('section', doc.sections, fallback: 0), story);
}

Iterable<WmlTable> _tables(WmlDocument doc) sync* {
  for (final section in doc.sections) {
    yield* WordTree.descendants(section.blocks).whereType<WmlTable>();
  }
}

List<WmlBlock> _container(WmlDocument doc, WmlBlock target) {
  final found = WordTree.locate(doc, target);
  if (found != null) return found.parent;
  throw ArgumentError('Block is not in a document story');
}

bool _removeVisual(WmlDocument doc, WmlVisual target) {
  for (final comment in doc.comments) {
    if (comment.visuals.remove(target)) return true;
  }
  for (final section in doc.sections) {
    for (final story in _headerStories) {
      if (_headerVisuals(section, story).remove(target)) return true;
    }
  }
  return _container(doc, target).remove(target);
}

WmlComment _comment(WmlDocument doc, StepInput s) {
  final comment = WordComment.byId(doc, s.integer('comment'));
  if (comment == null) throw ArgumentError('Unknown comment id');
  return comment;
}

WmlTabStop _tab(Object? value, Set<double> positions) {
  if (value is! Map<String, Object?>) {
    throw ArgumentError('tab must be an object');
  }
  final s = StepInput({'op': 'tab', ...value});
  s.fields(['position', 'alignment', 'leader']);
  final position = s.number('position', min: 0);
  if (!positions.add(position)) throw ArgumentError('Duplicate tab position');
  return WmlTabStop(
    position: position,
    alignment: WmlTabAlignment.values.byName(
      s.string('alignment', fallback: 'left'),
    ),
    leader: WmlTabLeader.values.byName(s.string('leader', fallback: 'none')),
  );
}

void _noteHint(WmlParagraph p) {
  final mark = p.inlines
      .whereType<WmlRun>()
      .where((r) => r.noteRefId != null)
      .firstOrNull;
  p.properties.noteId = mark?.noteRefId;
  p.properties.endnoteRef = mark?.noteRefEndnote ?? false;
}

void _boundary(WmlParagraph p, int at) {
  final text = p.text;
  if (at > 0 &&
      at < text.length &&
      text.codeUnitAt(at - 1) >= 0xD800 &&
      text.codeUnitAt(at - 1) <= 0xDBFF &&
      text.codeUnitAt(at) >= 0xDC00 &&
      text.codeUnitAt(at) <= 0xDFFF) {
    throw ArgumentError('Offset splits a UTF-16 surrogate pair');
  }
  var position = 0;
  for (final run in p.inlines.whereType<WmlRun>()) {
    if (run.isAtomic && at > position && at < position + run.text.length) {
      throw ArgumentError('Offset splits an atomic note or field result');
    }
    position += run.text.length;
  }
}

(int, int) _range(WmlParagraph p, StepInput s) {
  final start = s.integer('start', fallback: 0, max: p.text.length);
  final end = s.integer(
    'end',
    fallback: p.text.length,
    min: start,
    max: p.text.length,
  );
  _boundary(p, start);
  _boundary(p, end);
  return (start, end);
}

(PackagePart, XmlDocument) _styles(WmlDocument doc) {
  final package = doc.package;
  if (package == null) {
    throw ArgumentError('Style definitions require an imported package');
  }
  final office = package.packageRelationships.firstByType(
    RelationshipTypes.officeDocument,
  );
  final uri = office == null
      ? '/word/document.xml'
      : package.packageRelationships.resolve(office);
  final rels = package.relationshipsFor(uri);
  final rel = rels.firstByType(RelationshipTypes.styles);
  final part = package.getPart(
    rel == null ? '/word/styles.xml' : rels.resolve(rel),
  );
  if (part == null) throw ArgumentError('No styles part');
  return (part, XmlDocument.parse(part.readText()));
}

XmlElement _sourceStyle(WmlDocument doc, String id, String type) {
  final style = _styles(doc).$2.root!
      .childrenNamed('style', namespaceUri: OfficeNamespaces.w)
      .where((s) => s.getAttribute('styleId') == id)
      .firstOrNull;
  if (style == null || style.getAttribute('type') != type) {
    throw ArgumentError('Unknown $type style: $id');
  }
  return style;
}

void _editStyle(WmlDocument doc, StepInput s) {
  final source = _styles(doc);
  final style = source.$2.root!
      .childrenNamed('style', namespaceUri: OfficeNamespaces.w)
      .where((e) => e.getAttribute('styleId') == s.string('style'))
      .firstOrNull;
  if (style == null) throw ArgumentError('Unknown style id');
  if (s.has('type') && style.getAttribute('type') != s.string('type')) {
    throw ArgumentError('Style type mismatch');
  }
  for (final group in <String>['pPr', 'rPr', 'tblPr', 'tcPr']) {
    if (!s.has(group)) continue;
    var props = style.firstChild(group, namespaceUri: OfficeNamespaces.w);
    if (props == null) {
      props = _wordPropertyElement(group);
      style.addChild(props);
    }
    for (final entry in s.object(group).entries) {
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(entry.key)) {
        throw ArgumentError('Invalid property name');
      }
      props.children.removeWhere(
        (n) =>
            n is XmlElement &&
            n.localName == entry.key &&
            n.namespaceUri == OfficeNamespaces.w,
      );
      if (entry.value == null) continue;
      final attributes = entry.value;
      if (attributes is! Map<String, Object?>) {
        throw ArgumentError('${entry.key} must be an attribute object or null');
      }
      final element = _wordPropertyElement(entry.key);
      for (final attribute in attributes.entries) {
        if (!RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(attribute.key) ||
            (attribute.value is! String &&
                attribute.value is! num &&
                attribute.value is! bool)) {
          throw ArgumentError('Invalid XML attribute ${attribute.key}');
        }
        element.setAttribute(
          attribute.key,
          '${attribute.value}',
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        );
      }
      props.addChild(element);
    }
    WordPropertyIo.orderChildren(props);
  }
  // A newly added property group must also take its schema position.
  WordPropertyIo.orderChildren(style);
  source.$1.writeText(source.$2.toXmlString());
  WordDeserializer().refreshStyles(doc);
}

// Imported parts can use another Word prefix and bind `w` to an extension.
// Bind only generated nodes so the source's namespace scopes remain intact.
XmlElement _wordPropertyElement(String name) =>
    XmlElement(localName: name, prefix: 'w', namespaceUri: OfficeNamespaces.w)
      ..setAttribute(
        'w',
        OfficeNamespaces.w,
        prefix: 'xmlns',
        namespaceUri: 'http://www.w3.org/2000/xmlns/',
      );
