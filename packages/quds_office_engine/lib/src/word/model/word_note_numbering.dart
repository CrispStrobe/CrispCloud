part of 'word_notes.dart';

/// The effective native settings for one exactly resolved automatic note.
///
/// Formats and restart values retain their native Word names. Exporters must
/// explicitly accept the values they can represent; a display label alone
/// cannot distinguish a Roman numeral from an alphabetic sequence.
final class WordNoteAutomaticNumber {
  const WordNoteAutomaticNumber({
    required this.number,
    required this.format,
    required this.start,
    required this.restart,
  });

  final int number;
  final String format;
  final int start;
  final String restart;
}

/// A read-only snapshot of note labels in body reference order.
///
/// Native note IDs identify links; they are never display numbers. Rebuilding
/// this snapshot after an edit updates numbering without changing IDs, cached
/// source text, selections or undo history. Footnotes and endnotes have separate
/// sequences, including ordinary notes between Zotero citations.
final class WordNoteNumbering {
  /// Builds labels without modifying the document or cached reference text.
  ///
  /// Export adapters may treat empty authored references as automatic and
  /// supply their visible body paragraphs. Defaults retain the native/editor
  /// interpretation, including its existing body traversal.
  WordNoteNumbering(
    WmlDocument document, {
    this.emptyReferencesAreAutomatic = false,
    Iterable<WmlParagraph> Function(WmlSection section)? paragraphsForSection,
  }) {
    final definitions = <(bool, int), List<WmlNote>>{};
    for (final note in [...document.footnotes, ...document.endnotes]) {
      definitions.putIfAbsent((note.endnote, note.id), () => []).add(note);
    }
    final defaults = _documentOptions(document);
    final nextNumbers = <bool, int>{};
    final unknownCounters = <bool>{};
    final seen = <(bool, int)>{};
    for (final section in document.sections) {
      final sectionXml = section.sourceProperties?.xml;
      final sectionRoot = _xml(sectionXml);
      final options = <bool, _NoteNumberOptions>{
        for (final endnote in [false, true])
          endnote: defaults[endnote]!.overlaid(
            sectionRoot?.firstChild(
              endnote ? 'endnotePr' : 'footnotePr',
              namespaceUri: OfficeNamespaces.w,
            ),
            unambiguous: _unambiguousProperties(
              sectionXml,
              sectionRoot,
              'sectPr',
              endnote,
            ),
          ),
      };
      for (final entry in options.entries) {
        if (entry.value.restart == 'eachSect') {
          nextNumbers[entry.key] = entry.value.start;
          unknownCounters.remove(entry.key);
        }
      }
      for (final paragraph
          in paragraphsForSection?.call(section) ??
              _bodyParagraphs(section.blocks)) {
        for (final run in paragraph.inlines.whereType<WmlRun>()) {
          final id = run.noteRefId;
          if (id == null) continue;
          final key = (run.noteRefEndnote, id);
          final matches = definitions[key];
          if (matches == null || matches.length != 1 || !seen.add(key)) {
            continue;
          }
          final note = matches.single;
          _ordered.add(note);
          if (run.noteRefCustomMark) {
            _labels[note] = '';
            _referenceLabels[key] = '';
            continue;
          }
          // Imported/custom visible text is not an automatically numbered
          // placeholder. Keep it exactly as authored and outside the sequence.
          if (!_isAutomaticReference(run)) {
            _labels[note] = run.text;
            continue;
          }
          final setting = options[note.endnote]!;
          // numStart applies at the first automatic mark and at restart
          // points. A continuous section carries the previous section's next
          // number, even if that section used a different start or restart.
          final number = nextNumbers.putIfAbsent(
            note.endnote,
            () => setting.start,
          );
          if (!const {'continuous', 'eachSect'}.contains(setting.restart) ||
              number < 0 ||
              number > 1000000) {
            unknownCounters.add(note.endnote);
          } else {
            nextNumbers[note.endnote] = number + 1;
          }
          // Page numbering cannot be inferred before pagination. Its unknown
          // counter also propagates into following continuous sections until
          // an explicit section restart restores a known start.
          final label = unknownCounters.contains(note.endnote)
              ? null
              : formatLabel(number, setting.format);
          if (label == null) {
            _labels[note] = '$id';
            _limited.add(note);
          } else {
            _labels[note] = label;
            _referenceLabels[key] = label;
            if (setting.unambiguous) {
              _automatic[note] = WordNoteAutomaticNumber(
                number: number,
                format: setting.format,
                start: setting.start,
                restart: setting.restart,
              );
            }
          }
        }
      }
    }
    // Keep unanchored definitions accessible for repair without assigning a
    // fictitious position in the body sequence.
    for (final note in [...document.footnotes, ...document.endnotes]) {
      if (!_labels.containsKey(note)) {
        _ordered.add(note);
        _labels[note] = '${note.id}';
        _limited.add(note);
      }
    }
  }

  final _ordered = <WmlNote>[];

  /// Whether empty reference runs participate in automatic numbering.
  final bool emptyReferencesAreAutomatic;
  final _labels = <WmlNote, String>{};
  final _referenceLabels = <(bool, int), String>{};
  final _limited = <WmlNote>{};
  final _automatic = <WmlNote, WordNoteAutomaticNumber>{};

  /// Anchored notes in body order followed by unanchored definitions.
  List<WmlNote> get notes => List<WmlNote>.unmodifiable(_ordered);

  String labelFor(WmlNote note) => _labels[note] ?? '${note.id}';

  /// False for page-based numbering, unsupported native formats and orphaned
  /// definitions. Their native settings remain intact for the word processor.
  bool hasExactLabel(WmlNote note) =>
      _labels.containsKey(note) && !_limited.contains(note);

  /// Effective numbering for an automatic reference with an exact label and
  /// unambiguous native settings. Custom/orphaned references, unsupported
  /// numbering and malformed/duplicate configuration return null. This does
  /// not change the editor's existing cached-label fallback behavior.
  WordNoteAutomaticNumber? automaticNumberFor(WmlNote note) => _automatic[note];

  /// Replacement for a modeled automatic reference only. A host may paint this
  /// with different length while retaining the original source-offset range.
  String? referenceLabel(WmlRun run) {
    if (run.noteRefCustomMark) return '';
    return !_isAutomaticReference(run)
        ? null
        : _referenceLabels[(run.noteRefEndnote, run.noteRefId!)];
  }

  bool _isAutomaticReference(WmlRun run) =>
      run.noteRefId != null &&
      (run.text == '${run.noteRefId}' ||
          (emptyReferencesAreAutomatic && run.text.isEmpty));

  static Iterable<WmlParagraph> _bodyParagraphs(
    Iterable<WmlBlock> blocks,
  ) sync* {
    for (final block in blocks) {
      if (block is WmlParagraph) {
        yield block;
      } else if (block is WmlContentControlBlock) {
        yield* _bodyParagraphs(block.blocks);
      } else if (block is WmlTable) {
        for (final row in block.rows) {
          for (final cell in row.cells) {
            yield* _bodyParagraphs(cell.blocks);
          }
        }
      }
      // Text boxes, headers, footers and note stories do not participate in
      // Word's body-note sequence.
    }
  }

  static Map<bool, _NoteNumberOptions> _documentOptions(WmlDocument document) {
    XmlElement? settings;
    String? settingsXml;
    final package = document.package;
    if (package != null) {
      final office = package.packageRelationships.firstByType(
        RelationshipTypes.officeDocument,
      );
      if (office?.targetMode != RelationshipTargetMode.external) {
        final main = office == null
            ? '/word/document.xml'
            : package.packageRelationships.resolve(office);
        final relationships = package.relationshipsFor(main);
        final rel = relationships.firstByType(RelationshipTypes.settings);
        if (rel?.targetMode != RelationshipTargetMode.external) {
          settingsXml = package
              .getPart(
                rel == null
                    ? OpcUris.resolve(main, 'settings.xml')
                    : relationships.resolve(rel),
              )
              ?.readText();
          settings = _xml(settingsXml);
        }
      }
    }
    return {
      for (final endnote in [false, true])
        endnote:
            _NoteNumberOptions(
              // Match Word's documented endnote default (MS-OI29500 2.1.306).
              format: endnote ? 'lowerRoman' : 'decimal',
            ).overlaid(
              settings?.firstChild(
                endnote ? 'endnotePr' : 'footnotePr',
                namespaceUri: OfficeNamespaces.w,
              ),
              unambiguous: _unambiguousProperties(
                settingsXml,
                settings,
                'settings',
                endnote,
              ),
            ),
    };
  }

  static XmlElement? _xml(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      return XmlDocument.parse(source).root;
    } on FormatException {
      return null;
    }
  }

  static bool _unambiguousProperties(
    String? source,
    XmlElement? root,
    String rootName,
    bool endnote,
  ) {
    if (source == null || source.isEmpty) return true;
    if (root == null ||
        root.localName != rootName ||
        root.namespaceUri != OfficeNamespaces.w ||
        !_completeNumberingXml(source)) {
      return false;
    }
    final name = endnote ? 'endnotePr' : 'footnotePr';
    if (root.childrenNamed(name, namespaceUri: OfficeNamespaces.w).length > 1) {
      return false;
    }
    bool containsProperties(XmlElement element) =>
        (element.localName == name &&
            element.namespaceUri == OfficeNamespaces.w) ||
        element.childElements.any(containsProperties);
    // This reader does not project markup-compatibility alternatives. A
    // wrapped native configuration must not masquerade as an absent one.
    return root.childElements.every(
      (child) =>
          child.localName == name && child.namespaceUri == OfficeNamespaces.w ||
          !containsProperties(child),
    );
  }

  // The shared DOM reader intentionally tolerates incomplete native source
  // for preservation. Exportable numbering needs a stronger proof without
  // changing that reader or the editor's existing label fallback.
  static bool _completeNumberingXml(String source) {
    if (source.length > 8 * 1024 * 1024) return false;
    final stack = <String>[];
    var roots = 0;
    var elements = 0;
    try {
      final reader = XmlPullReader(source);
      while (reader.next()) {
        switch (reader.eventType) {
          case XmlEventType.startElement:
            if (++elements > 50000 ||
                stack.length >= 128 ||
                reader.attributeCount > 128) {
              return false;
            }
            if (stack.isEmpty && ++roots != 1) return false;
            final qualifiedAttributes = <String>{};
            final expandedAttributes = <(String, String)>{};
            for (var index = 0; index < reader.attributeCount; index++) {
              if (!qualifiedAttributes.add(
                    reader.attributeQualifiedName(index),
                  ) ||
                  !expandedAttributes.add((
                    reader.attributeNamespace(index),
                    reader.attributeLocalName(index),
                  ))) {
                return false;
              }
            }
            stack.add(reader.qualifiedName);
          case XmlEventType.endElement:
            if (stack.isEmpty || stack.removeLast() != reader.qualifiedName) {
              return false;
            }
          case XmlEventType.characters:
            if (stack.isEmpty && !reader.isWhitespace) return false;
          case XmlEventType.cdata:
            if (stack.isEmpty) return false;
          case XmlEventType.dtd:
            return false;
          case XmlEventType.none:
          case XmlEventType.xmlDeclaration:
          case XmlEventType.processingInstruction:
          case XmlEventType.comment:
          case XmlEventType.endDocument:
            break;
        }
      }
      return roots == 1 && stack.isEmpty;
    } on FormatException {
      return false;
    }
  }

  /// Formats an exact positive ordinal using a supported native Word format.
  /// Returns null outside the native implementation's supported range.
  static String? formatLabel(int number, String format) {
    if (number < 1 || number > 1000000) return null;
    switch (format) {
      case 'none':
        return '';
      case 'decimal':
      case 'bullet': // Word treats bullet note numbering as decimal.
        return '$number';
      case 'decimalZero':
        return '$number'.padLeft(2, '0');
      case 'upperLetter':
      case 'lowerLetter':
        var value = number;
        var label = '';
        while (value > 0) {
          value--;
          label = String.fromCharCode(65 + value % 26) + label;
          value ~/= 26;
        }
        return format == 'lowerLetter' ? label.toLowerCase() : label;
      case 'upperRoman':
      case 'lowerRoman':
        if (number >= 4000) return null;
        var value = number;
        final label = StringBuffer();
        const digits = {
          1000: 'M',
          900: 'CM',
          500: 'D',
          400: 'CD',
          100: 'C',
          90: 'XC',
          50: 'L',
          40: 'XL',
          10: 'X',
          9: 'IX',
          5: 'V',
          4: 'IV',
          1: 'I',
        };
        for (final digit in digits.entries) {
          while (value >= digit.key) {
            label.write(digit.value);
            value -= digit.key;
          }
        }
        return format == 'lowerRoman'
            ? label.toString().toLowerCase()
            : label.toString();
      default:
        return null;
    }
  }
}

final class _NoteNumberOptions {
  const _NoteNumberOptions({
    required this.format,
    this.start = 1,
    this.restart = 'continuous',
    this.unambiguous = true,
  });

  final String format;
  final int start;
  final String restart;
  final bool unambiguous;

  _NoteNumberOptions overlaid(
    XmlElement? properties, {
    bool unambiguous = true,
  }) {
    String? value(String name) => properties
        ?.firstChild(name, namespaceUri: OfficeNamespaces.w)
        ?.getAttribute('val', namespaceUri: OfficeNamespaces.w);
    var exact = this.unambiguous && unambiguous;
    if (properties != null &&
        (properties.childElements.any(
              (child) =>
                  child.namespaceUri != OfficeNamespaces.w ||
                  !const {
                    'pos',
                    'numFmt',
                    'numStart',
                    'numRestart',
                    'footnote',
                    'endnote',
                  }.contains(child.localName) ||
                  child.childElements.isNotEmpty ||
                  !RegExp(r'^[ \t\r\n]*$').hasMatch(child.text),
            ) ||
            !RegExp(r'^[ \t\r\n]*$').hasMatch(properties.text))) {
      exact = false;
    }
    for (final name in ['numFmt', 'numStart', 'numRestart']) {
      final matches = properties
          ?.childrenNamed(name, namespaceUri: OfficeNamespaces.w)
          .toList();
      if (matches == null || matches.isEmpty) continue;
      final raw = value(name);
      if (matches.length != 1 ||
          raw == null ||
          raw.isEmpty ||
          matches.single.childElements.isNotEmpty ||
          !RegExp(r'^[ \t\r\n]*$').hasMatch(matches.single.text) ||
          (name == 'numStart' &&
              (!RegExp(r'^[0-9]+$').hasMatch(raw) ||
                  int.tryParse(raw) == null))) {
        exact = false;
      }
    }
    return _NoteNumberOptions(
      format: value('numFmt') ?? format,
      start: int.tryParse(value('numStart') ?? '') ?? start,
      restart: value('numRestart') ?? restart,
      unambiguous: exact,
    );
  }
}
