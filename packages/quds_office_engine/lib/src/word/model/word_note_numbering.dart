part of 'word_notes.dart';

/// A read-only snapshot of note labels in body reference order.
///
/// Native note IDs identify links; they are never display numbers. Rebuilding
/// this snapshot after an edit updates numbering without changing IDs, cached
/// source text, selections or undo history. Footnotes and endnotes have separate
/// sequences, including ordinary notes between Zotero citations.
final class WordNoteNumbering {
  WordNoteNumbering(WmlDocument document) {
    final definitions = <(bool, int), List<WmlNote>>{};
    for (final note in [...document.footnotes, ...document.endnotes]) {
      definitions.putIfAbsent((note.endnote, note.id), () => []).add(note);
    }
    final defaults = _documentOptions(document);
    final nextNumbers = <bool, int>{};
    final unknownCounters = <bool>{};
    final seen = <(bool, int)>{};
    for (final section in document.sections) {
      final sectionRoot = _xml(section.sourceProperties?.xml);
      final options = <bool, _NoteNumberOptions>{
        for (final endnote in [false, true])
          endnote: defaults[endnote]!.overlaid(
            sectionRoot?.firstChild(
              endnote ? 'endnotePr' : 'footnotePr',
              namespaceUri: OfficeNamespaces.w,
            ),
          ),
      };
      for (final entry in options.entries) {
        if (entry.value.restart == 'eachSect') {
          nextNumbers[entry.key] = entry.value.start;
          unknownCounters.remove(entry.key);
        }
      }
      for (final paragraph in _bodyParagraphs(section.blocks)) {
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
          if (run.text != '$id') {
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
              : _format(number, setting.format);
          if (label == null) {
            _labels[note] = '$id';
            _limited.add(note);
          } else {
            _labels[note] = label;
            _referenceLabels[key] = label;
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
  final _labels = <WmlNote, String>{};
  final _referenceLabels = <(bool, int), String>{};
  final _limited = <WmlNote>{};

  /// Anchored notes in body order followed by unanchored definitions.
  List<WmlNote> get notes => List<WmlNote>.unmodifiable(_ordered);

  String labelFor(WmlNote note) => _labels[note] ?? '${note.id}';

  /// False for page-based numbering, unsupported native formats and orphaned
  /// definitions. Their native settings remain intact for the word processor.
  bool hasExactLabel(WmlNote note) =>
      _labels.containsKey(note) && !_limited.contains(note);

  /// Replacement for a modeled automatic reference only. A host may paint this
  /// with different length while retaining the original source-offset range.
  String? referenceLabel(WmlRun run) {
    if (run.noteRefCustomMark) return '';
    return run.noteRefId == null || run.text != '${run.noteRefId}'
        ? null
        : _referenceLabels[(run.noteRefEndnote, run.noteRefId!)];
  }

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
          settings = _xml(
            package
                .getPart(
                  rel == null
                      ? OpcUris.resolve(main, 'settings.xml')
                      : relationships.resolve(rel),
                )
                ?.readText(),
          );
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

  static String? _format(int number, String format) {
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
  });

  final String format;
  final int start;
  final String restart;

  _NoteNumberOptions overlaid(XmlElement? properties) {
    String? value(String name) => properties
        ?.firstChild(name, namespaceUri: OfficeNamespaces.w)
        ?.getAttribute('val', namespaceUri: OfficeNamespaces.w);
    return _NoteNumberOptions(
      format: value('numFmt') ?? format,
      start: int.tryParse(value('numStart') ?? '') ?? start,
      restart: value('numRestart') ?? restart,
    );
  }
}
