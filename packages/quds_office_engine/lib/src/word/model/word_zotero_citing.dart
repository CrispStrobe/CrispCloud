import 'dart:convert';

import '../../zotero/zotero_formatted_text.dart';
import '../properties/wml_properties.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_content_controls.dart';
import 'word_notes.dart';
import 'word_tree.dart';
import 'word_zotero.dart';
import 'word_zotero_data.dart';

/// A staged implementation of Zotero's HTTP document/field interface.
///
/// No command mutates [document]. The editor checks its revision/selection and
/// calls [apply] inside one undo command only after Document.complete. Native
/// fields are enumerated in reading order, with notes at their body anchors.
/// Unsupported stories and ambiguous note conversions fail before mutation.
final class WordZoteroCitingSession {
  WordZoteroCitingSession({
    required this.document,
    required this.documentId,
    this.insertionParagraph,
    this.insertionOffset = 0,
    WmlZoteroField? selectedField,
    ZoteroCitation? seedCitation,
  }) {
    if (document.trackRevisions || document.restrictEditing) {
      throw UnsupportedError(
        'Turn off Track changes and use an editable document before citing with Zotero.',
      );
    }
    _nativeData = WordZoteroDocumentData.read(document);
    _originalData = _nativeData;
    _body.addAll(_flowParagraphs(document.sections.expand((s) => s.blocks)));
    _bodyParagraphs.addAll(_body);
    if (_body.length > 100000) {
      throw UnsupportedError(
        'This document is too large for one Zotero transaction.',
      );
    }
    final all = WordZotero.fields(document);
    if (all.length > 10000 || all.any((f) => !_canProcessField(f))) {
      throw UnsupportedError(
        'Zotero needs editable citation fields or complete bibliography entry paragraphs. Locked, nested, malformed or ambiguous field structures must be resolved first.',
      );
    }
    final byParagraph = <WmlParagraph, List<WmlZoteroField>>{};
    for (final field in all) {
      byParagraph.putIfAbsent(field.paragraph, () => []).add(field);
    }
    final seen = <WmlZoteroField>{};
    final seenNotes = <WmlNote>{};
    // A note ID is unique only within its footnote/endnote bucket. Keep all
    // matches so duplicate IDs still fail when their body anchor is resolved.
    final footnotes = _notesById(document.footnotes);
    final endnotes = _notesById(document.endnotes);
    for (var p = 0; p < _body.length; p++) {
      final paragraph = _body[p];
      final entries = <({int offset, WmlZoteroField? field, WmlNote? note})>[
        for (final field in byParagraph[paragraph] ?? <WmlZoteroField>[])
          (offset: field.start, field: field, note: null),
      ];
      var offset = 0;
      for (final inline in paragraph.inlines) {
        if (inline is! WmlRun) continue;
        if (inline.noteRefId != null) {
          final matches =
              (inline.noteRefEndnote
                  ? endnotes
                  : footnotes)[inline.noteRefId] ??
              const <WmlNote>[];
          if (matches.length != 1 || !seenNotes.add(matches.single)) {
            throw UnsupportedError(
              'A note has a missing or repeated body reference. Resolve it before formatting citations.',
            );
          }
          entries.add((offset: offset, field: null, note: matches.single));
        }
        offset += inline.text.length;
      }
      entries.sort((a, b) => a.offset.compareTo(b.offset));
      for (final entry in entries) {
        if (entry.field != null) {
          seen.add(entry.field!);
          _addField(
            _CitingField.original(
              id: 'f${_fields.length}',
              original: entry.field!,
              bodyIndex: p,
              anchor: paragraph,
              anchorOffset: entry.offset,
            ),
          );
        } else {
          final note = entry.note!;
          _notes.add(_NoteAnchor(note, paragraph, p, entry.offset));
          var noteOrder = 0;
          for (final noteParagraph in _flowParagraphs(note.blocks)) {
            for (final field
                in byParagraph[noteParagraph] ?? <WmlZoteroField>[]) {
              seen.add(field);
              _addField(
                _CitingField.original(
                  id: 'f${_fields.length}',
                  original: field,
                  bodyIndex: p,
                  anchor: paragraph,
                  anchorOffset: entry.offset,
                  note: note,
                  noteOrder: noteOrder++,
                ),
              );
            }
          }
        }
      }
    }
    if (seen.length != all.length) {
      throw UnsupportedError(
        'Zotero citations in headers, footers, comments, text boxes or unanchored notes cannot be reformatted safely here. Move them into the body or an anchored note first.',
      );
    }
    for (final field in _fields) {
      if (selectedField != null && _sameField(field.original!, selectedField)) {
        _selected = field;
      }
    }
    if (selectedField != null && _selected == null) {
      throw StateError(
        'The selected Zotero field changed. Reopen the citation.',
      );
    }
    if (insertionParagraph != null &&
        _bodyParagraphs.contains(insertionParagraph)) {
      if (insertionOffset < 0 ||
          insertionOffset > insertionParagraph!.text.length) {
        throw ArgumentError(
          'The citation insertion point is outside the paragraph.',
        );
      }
      _selected ??= _fields
          .where(
            (f) =>
                f.note == null &&
                (f.original!.paragraphs.length > 1
                    ? f.original!.paragraphs.contains(insertionParagraph)
                    : identical(f.original?.paragraph, insertionParagraph) &&
                          insertionOffset >= f.original!.start &&
                          insertionOffset < f.original!.end),
          )
          .firstOrNull;
    }
    _sourceParagraphs.addAll(_body);
    for (final note in [...document.footnotes, ...document.endnotes]) {
      _sourceParagraphs.addAll(note.allParagraphs);
    }
    for (final paragraph in _sourceParagraphs) {
      _sourceTexts[paragraph] = paragraph.text;
    }
    if (document.revisions.any((revision) => revision.accepted == null)) {
      throw UnsupportedError(
        'Accept or reject tracked changes before running a document-wide Zotero transaction.',
      );
    }
    if (seedCitation != null) {
      _seedCitation(seedCitation);
    }
  }

  final WmlDocument document;
  final String documentId;
  final WmlParagraph? insertionParagraph;
  final int insertionOffset;
  final _body = <WmlParagraph>[];
  final _bodyParagraphs = Set<WmlParagraph>.identity();
  final _fields = <_CitingField>[];
  final _fieldsById = <String, _CitingField>{};
  final _originalFieldsPerNote = Map<WmlNote, int>.identity();
  final _notes = <_NoteAnchor>[];
  final _sourceParagraphs = <WmlParagraph>{};
  final _sourceTexts = <WmlParagraph, String>{};
  final formattingWarnings = <String>{};
  late final String _originalData;
  late String _nativeData;
  _CitingField? _selected;
  bool _complete = false;
  bool _applied = false;
  _BibliographyStyle? _bibliographyStyle;
  WmlParagraph? _insertedParagraph;
  WmlNote? _insertedNote;
  ({WmlParagraph paragraph, int offset})? _caretAfter;

  /// Resolved after application, including length changes in earlier fields.
  ({WmlParagraph paragraph, int offset})? get caretAfter => _caretAfter;

  bool get isComplete => _complete;
  String get documentData => _nativeData;
  bool get hasAcceptedSeedCitation => _fields.any(
    (field) =>
        field.seeded &&
        !field.deleted &&
        !field.unlinked &&
        (field.codeWasSet || field.textWasSet),
  );
  bool get hasChanges =>
      _nativeData != _originalData ||
      _bibliographyStyle != null ||
      _fields.any((f) => f.changed);
  int get changedFieldCount => _fields.where((f) => f.changed).length;
  List<String> get previewTexts => List.unmodifiable(
    _ordered().where((f) => !f.deleted && f.changed).map((f) => f.text),
  );

  /// All original paragraphs whose model state might be changed by [apply].
  /// The editor also snapshots the owning block lists and note buckets.
  List<WmlParagraph> get affectedParagraphs =>
      List.unmodifiable(_sourceParagraphs);

  /// Continue a completed preferences operation in the same staged edit.
  /// The first native picker can therefore choose a style before a catalog
  /// seed is placed, without saving preferences or changing the document if
  /// the following citation picker is cancelled or fails.
  void continueWithCitation(ZoteroCitation citation) {
    if (!_complete || _applied) {
      throw StateError('Finish choosing the Zotero document style first.');
    }
    assertUnchanged();
    _seedCitation(citation);
    _complete = false;
  }

  void _seedCitation(ZoteroCitation citation) {
    if (_selected != null) {
      throw UnsupportedError(
        'Move the caret outside the existing citation before inserting selected sources.',
      );
    }
    final field = _insert(WordZoteroDocumentData.citationNoteType(_nativeData));
    field.code = _toHttp(citation.fieldInstruction);
    field.text = citation.plainCitation;
    field.seeded = true;
    _selected = field;
  }

  /// Document.displayAlert is handled by the host UI, with Zotero's exact
  /// button return codes. It must not be silently acknowledged here.
  Object? handle(String command, List<dynamic> args) {
    if (_complete) {
      throw StateError('The Zotero transaction is already complete.');
    }
    if (command == 'Application.getActiveDocument') {
      _arity(args, 0);
      return <String, Object>{
        'documentID': documentId,
        'outputFormat': 'html',
        'supportedNotes': <String>['footnotes', 'endnotes'],
        'supportsImportExport': false,
        'supportsTextInsertion': false,
        'supportsCitationMerging': false,
        'processorName': 'Quds Office',
      };
    }
    if (args.isEmpty || args.first != documentId) {
      throw const FormatException('Zotero addressed another document.');
    }
    switch (command) {
      case 'Document.activate':
        _arity(args, 1);
        return null;
      case 'Document.canInsertField':
        _arity(args, 2);
        _httpType(args[1]);
        return _canInsert || _selected != null;
      case 'Document.getDocumentData':
        _arity(args, 1);
        // Earlier Quds versions accepted the callback but simplified its
        // values. Ask Zotero to send the style again when no applied native
        // paragraph layout is present, including a newly added bibliography.
        final hasLayout = _fields.any((field) {
          final original = field.original;
          return original?.kind == ZoteroFieldKind.bibliography &&
              original!.paragraph.properties.explicitIndent &&
              original.paragraph.properties.explicitLineSpacing &&
              original.paragraph.properties.explicitSpacingAfter;
        });
        return WordZoteroDocumentData.toHttp(
          hasLayout || _bibliographyStyle != null
              ? _nativeData
              : WordZoteroDocumentData.requestBibliographyStyle(_nativeData),
        );
      case 'Document.setDocumentData':
        _arity(args, 2);
        _nativeData = WordZoteroDocumentData.toNative(_string(args[1]));
        return null;
      case 'Document.cursorInField':
        _arity(args, 2);
        _httpType(args[1]);
        return _selected?.deleted == false && !_selected!.unlinked
            ? _json(_selected!)
            : null;
      case 'Document.getFields':
        _arity(args, 2);
        _httpType(args[1]);
        // One reading-order pass serves the whole response. Recompute on each
        // command so inserted, deleted and converted notes cannot leave a
        // stale cached index behind.
        final noteIndexes = _noteIndexes();
        return <Map<String, Object>>[
          for (final field in _ordered())
            if (!field.deleted && !field.unlinked)
              _json(field, noteIndexes: noteIndexes),
        ];
      case 'Document.insertField':
        _arity(args, 3);
        _httpType(args[1]);
        return _json(_insert(_noteType(args[2])));
      case 'Document.convert':
        _arity(args, 4);
        _httpType(args[2]);
        final ids = args[1];
        final types = args[3];
        if (ids is! List ||
            types is! List ||
            ids.length != types.length ||
            ids.length > 10000) {
          throw const FormatException(
            'Zotero returned invalid note conversions.',
          );
        }
        final changes = <(_CitingField, int)>[];
        final seen = <String>{};
        for (var i = 0; i < ids.length; i++) {
          final field = _field(ids[i]);
          if (!seen.add(field.id)) {
            throw const FormatException('Zotero repeated a conversion.');
          }
          final type = _noteType(types[i]);
          if (type != field.noteType) _assertCanConvert(field, type);
          changes.add((field, type));
        }
        for (final (field, type) in changes) {
          field.noteType = type;
        }
        return null;
      case 'Document.setBibliographyStyle':
        _arity(args, 7);
        _bibliographyStyle = _BibliographyStyle.fromArguments(args);
        return null;
      case 'Document.complete':
        _arity(args, 1);
        for (final field in _fields) {
          if (field.seeded && !field.codeWasSet && !field.textWasSet) {
            field.deleted = true;
          }
          if (field.seeded &&
              !field.deleted &&
              !field.unlinked &&
              field.noteType !=
                  WordZoteroDocumentData.citationNoteType(_nativeData)) {
            throw StateError(
              'Zotero changed the note placement while opening this citation. Choose Document style… first, then insert the selected sources again.',
            );
          }
        }
        for (final field in _fields) {
          if (!field.deleted && !field.unlinked) _validateCode(field.code);
        }
        _complete = true;
        return null;
      case 'Field.select':
        _arity(args, 2);
        _selected = _field(args[1]);
        return null;
      case 'Field.delete':
        _arity(args, 2);
        _field(args[1]).deleted = true;
        return null;
      case 'Field.removeCode':
        _arity(args, 2);
        _field(args[1]).unlinked = true;
        return null;
      case 'Field.setCode':
        _arity(args, 3);
        final field = _field(args[1]);
        final code = _string(args[2]);
        if (code != 'TEMP') _validateCode(code);
        if (field.original != null &&
            code != 'TEMP' &&
            WordZotero.kindOfInstruction(_toNative(code)) !=
                field.original!.kind) {
          throw UnsupportedError(
            'Zotero cannot change the kind of an existing field.',
          );
        }
        field.code = code;
        field.codeWasSet = true;
        return null;
      case 'Field.setText':
        _arity(args, 4);
        if (args[3] is! bool) {
          throw const FormatException('Invalid Zotero result format.');
        }
        final field = _field(args[1]);
        final text = _string(args[2]);
        field.formatted = args[3] == true
            ? ZoteroFormattedText.fromHtml(text)
            : null;
        field.text = field.formatted?.plainText ?? text;
        field.textWasSet = true;
        return null;
      default:
        throw UnsupportedError(
          'This Zotero document command is not supported: $command',
        );
    }
  }

  /// Collect output limitations after all setCode/setText calls, whose order
  /// is controlled by Zotero, and before the host offers its result review.
  void prepareReview() {
    if (!_complete) {
      throw StateError('Zotero has not completed this operation.');
    }
    for (final field in _fields.where((f) => !f.deleted && !f.unlinked)) {
      if (_bibliographyStyle != null &&
          _kind(field) == ZoteroFieldKind.bibliography &&
          field.original != null &&
          (!WordZotero.canReplaceNativeBibliography(
                document,
                field.original!,
              ) ||
              !_hasKnownBibliographyEntries(field))) {
        formattingWarnings.add(
          'Bibliography paragraph layout cannot be applied to a field mixed with surrounding text, structural markers or ambiguous legacy line breaks. Refresh the bibliography with Zotero to obtain its entry boundaries.',
        );
      }
      final formatted = field.formatted;
      if (formatted == null) continue;
      formattingWarnings.addAll(
        formatted.unsupportedFormatting.map(
          (v) => 'Unsupported formatting: $v.',
        ),
      );
      if (_kind(field) == ZoteroFieldKind.bibliography &&
          field.original != null &&
          !WordZotero.canReplaceNativeBibliography(document, field.original!)) {
        formattingWarnings.add(
          'An inline bibliography is kept as protected plain text.',
        );
      }
    }
  }

  /// Rechecks original field identity and text. The editor additionally checks
  /// its monotonic revision, selection, mutation permissions and lifecycle.
  void assertUnchanged() {
    if (_applied ||
        document.restrictEditing ||
        document.trackRevisions ||
        document.revisions.any((revision) => revision.accepted == null) ||
        WordZoteroDocumentData.read(document) != _originalData) {
      throw StateError('The Zotero document changed while formatting.');
    }
    final body = _flowParagraphs(document.sections.expand((s) => s.blocks))
        .toList();
    if (body.length != _body.length ||
        Iterable<int>.generate(body.length)
            .any((i) => !identical(body[i], _body[i])) ||
        _sourceTexts.entries.any((e) => e.key.text != e.value)) {
      throw StateError('The document changed while Zotero was open.');
    }
    final current = WordZotero.fields(document);
    final original = _fields.where((f) => f.original != null).toList();
    if (current.length != original.length) {
      throw StateError('A Zotero field changed while formatting.');
    }
    // Paragraph identity is part of a field's identity: equal text/codes in
    // another paragraph or story must never satisfy its current-state guard.
    // Match each occurrence once, including any duplicate-looking fields,
    // without rescanning the complete document for every original field.
    final byParagraph =
        Map<WmlParagraph, Map<(int, int, String, String), int>>.identity();
    for (final field in current) {
      if (!_canProcessField(field)) continue;
      final matches = byParagraph.putIfAbsent(field.paragraph, () => {});
      matches.update(
        (field.start, field.end, field.instruction, field.cachedText),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    for (final entry in original) {
      final field = entry.original!;
      final matches = byParagraph[field.paragraph];
      final identity = (
        field.start,
        field.end,
        field.instruction,
        field.cachedText,
      );
      final count = matches?[identity] ?? 0;
      if (count == 0) {
        throw StateError('A Zotero field changed while formatting.');
      }
      matches![identity] = count - 1;
    }
  }

  /// Applies a completed result. Call only inside the editor's rollback/undo
  /// boundary; a throwing application must restore all affected model state.
  void apply() {
    if (!_complete) {
      throw StateError('Zotero has not completed this operation.');
    }
    assertUnchanged();
    prepareReview();
    // Descending source positions keep the original handles/offsets valid.
    for (final field in _ordered().reversed) {
      if (!field.changed) continue;
      final original = field.original;
      if (original == null) {
        if (!field.deleted) {
          _insertResult(field, field.anchor, field.anchorOffset);
        }
        continue;
      }
      if (field.deleted) {
        if (original.kind == ZoteroFieldKind.bibliography &&
            WordZotero.canReplaceNativeBibliography(document, original)) {
          WordZotero.deleteNativeBibliography(document, original);
        } else if (field.note != null && _isSoleNoteField(field)) {
          WordNotes.delete(
            document,
            field.note!.id,
            endnote: field.note!.endnote,
          );
        } else {
          WordZotero.delete(original);
        }
      } else if (field.unlinked) {
        if (field.textWasSet || field.code != _toHttp(original.instruction)) {
          _replace(field);
          final current = WordZotero.fields(document).firstWhere(
            (f) =>
                identical(f.paragraph, original.paragraph) &&
                f.start == original.start,
          );
          WordZotero.unlink(current);
        } else {
          WordZotero.unlink(original);
        }
      } else if (field.noteType != field.originalNoteType) {
        _assertCanConvert(field, field.noteType);
        if (field.note != null) {
          WordNotes.delete(
            document,
            field.note!.id,
            endnote: field.note!.endnote,
          );
        } else {
          WordZotero.delete(original);
        }
        _insertResult(field, field.anchor, field.anchorOffset);
      } else {
        _replace(field);
      }
    }
    if (_bibliographyStyle != null) {
      var applied = false;
      var incomplete = false;
      for (final field in WordZotero.fields(document)) {
        if (field.kind != ZoteroFieldKind.bibliography) continue;
        final staged = _fields
            .where(
              (entry) =>
                  identical(entry.original?.paragraph, field.paragraph) ||
                  (entry.original == null &&
                      identical(_insertedParagraph, field.paragraph)),
            )
            .firstOrNull;
        if (!WordZotero.canReplaceNativeBibliography(document, field) ||
            staged == null ||
            !_hasKnownBibliographyEntries(staged)) {
          incomplete = true;
          continue;
        }
        for (final paragraph in field.paragraphs) {
          WordContentControls.assertCanEdit(
            paragraph,
            0,
            paragraph.text.length,
          );
          _bibliographyStyle!.applyTo(paragraph.properties);
        }
        applied = true;
      }
      if (!applied || incomplete) {
        _nativeData = WordZoteroDocumentData.requestBibliographyStyle(
          _nativeData,
        );
      }
    }
    if (_nativeData != _originalData || _bibliographyStyle != null) {
      document.zoteroDocumentData = _nativeData;
    }
    final inserted = _fields
        .where(
          (field) =>
              field.original == null && !field.deleted && !field.unlinked,
        )
        .firstOrNull;
    if (inserted != null) {
      if (_insertedNote != null) {
        var offset = 0;
        for (final inline in inserted.anchor.inlines) {
          if (inline is! WmlRun) continue;
          offset += inline.text.length;
          if (inline.noteRefId == _insertedNote!.id &&
              inline.noteRefEndnote == _insertedNote!.endnote) {
            _caretAfter = (paragraph: inserted.anchor, offset: offset);
            break;
          }
        }
      } else {
        final current = WordZotero.fields(document)
            .where(
              (field) =>
                  identical(field.paragraph, _insertedParagraph) &&
                  field.instruction == _resultInstruction(inserted),
            )
            .firstOrNull;
        if (current != null) {
          _caretAfter = (
            paragraph: current.paragraphs.last,
            offset: current.end,
          );
        }
      }
    }
    _applied = true;
  }

  void _replace(_CitingField field) {
    final original = field.original!;
    if (_kind(field) == ZoteroFieldKind.bibliography &&
        WordZotero.canReplaceNativeBibliography(document, original)) {
      WordZotero.replaceNativeBibliography(
        document,
        original,
        instruction: _resultInstruction(field),
        text: field.text,
        formattedText: field.formatted,
      );
      return;
    }
    final rich =
        _kind(field) != ZoteroFieldKind.bibliography ||
        WordZotero.canReplaceFormattedBibliography(original);
    WordZotero.replaceNativeResult(
      original,
      instruction: _resultInstruction(field),
      text: field.text,
      formattedText: rich ? field.formatted : null,
    );
  }

  void _insertResult(_CitingField field, WmlParagraph anchor, int offset) {
    WordContentControls.assertCanEdit(anchor, offset, offset);
    final instruction = _resultInstruction(field);
    if (_kind(field) == ZoteroFieldKind.bibliography) {
      if (field.noteType != 0) {
        throw UnsupportedError('A bibliography must be in the document body.');
      }
      final slot = WordTree.flowHost(document, anchor);
      if (slot == null) {
        throw StateError('The bibliography insertion point changed.');
      }
      final paragraphs = WordZotero.nativeBibliographyParagraphs(
        instruction: instruction,
        text: field.text,
        formattedText: field.formatted,
      );
      if (field.unlinked) {
        final temp = WmlDocument(sections: [WmlSection(blocks: paragraphs)]);
        WordZotero.unlink(WordZotero.fields(temp).single);
      }
      slot.parent.insertAll(slot.index + 1, paragraphs);
      if (field.original == null) _insertedParagraph = paragraphs.first;
      return;
    }
    var paragraph = anchor;
    var at = offset;
    if (field.noteType != 0) {
      final note = WordNotes.insert(
        document,
        anchor,
        endnote: field.noteType == 2,
      );
      if (field.original == null) _insertedNote = note;
      final reference = anchor.inlines.removeLast() as WmlRun;
      WmlRunEdit.insertRuns(anchor, offset, [reference]);
      paragraph = note.paragraphs.single;
      at = 0;
    }
    WordZotero.insertNativeCitation(
      paragraph,
      instruction: instruction,
      text: field.text,
      index: at,
      formattedText: field.formatted,
      preservedResultRuns: field.textWasSet ? null : field.originalRuns,
    );
    if (field.original == null) _insertedParagraph = paragraph;
    if (field.unlinked) {
      final current = WordZotero.fields(
        document,
      ).firstWhere((f) => identical(f.paragraph, paragraph) && f.start == at);
      WordZotero.unlink(current);
    }
  }

  bool get _canInsert =>
      insertionParagraph != null && _body.contains(insertionParagraph);

  _CitingField _insert(int noteType) {
    if (!_canInsert || _fields.any((f) => f.original == null && !f.deleted)) {
      throw UnsupportedError(
        'This Zotero operation needs one insertion point in the document body.',
      );
    }
    final paragraph = insertionParagraph!;
    if (_fields.any(
      (field) =>
          field.original != null &&
          field.original!.paragraphs.length > 1 &&
          field.original!.paragraphs.contains(paragraph),
    )) {
      throw UnsupportedError(
        'Move the caret outside the bibliography before inserting a citation.',
      );
    }
    final range = WmlRunEdit.normalizeRange(
      paragraph,
      insertionOffset,
      insertionOffset,
    );
    if (range.start != insertionOffset ||
        _fields.any(
          (f) =>
              f.note == null &&
              f.original != null &&
              identical(f.original!.paragraph, paragraph) &&
              insertionOffset > f.original!.start &&
              insertionOffset < f.original!.end,
        )) {
      throw UnsupportedError(
        'Move the caret outside the existing field before inserting a citation.',
      );
    }
    WordContentControls.assertCanEdit(
      paragraph,
      insertionOffset,
      insertionOffset,
    );
    final result = _CitingField.inserted(
      id: 'f${_fields.length}',
      bodyIndex: _body.indexOf(paragraph),
      anchor: paragraph,
      anchorOffset: insertionOffset,
      noteType: noteType,
    );
    _addField(result);
    _selected = result;
    return result;
  }

  void _assertCanConvert(_CitingField field, int type) {
    if (type == field.originalNoteType) return;
    if (_kind(field) == ZoteroFieldKind.bibliography && type != 0) {
      throw UnsupportedError('A bibliography cannot be moved into a note.');
    }
    if (field.note != null && !_isSoleNoteField(field)) {
      throw UnsupportedError(
        'Changing this citation between inline, footnote and endnote would move other note content. Use a note containing only one citation.',
      );
    }
  }

  bool _isSoleNoteField(_CitingField field) {
    final note = field.note;
    final original = field.original;
    if (note == null ||
        original == null ||
        note.blocks.length != 1 ||
        !identical(note.blocks.single, original.paragraph) ||
        _originalFieldsPerNote[note] != 1 ||
        original.paragraph.contentControlWrappers.isNotEmpty) {
      return false;
    }
    final paragraph = original.paragraph;
    final boundaries = paragraph.inlines.whereType<WmlFieldBoundary>().toList();
    if (paragraph.inlines.whereType<WmlNoteMarker>().length > 1) return false;
    if (original.run != null || original.wholeParagraph) {
      if (boundaries.isNotEmpty) return false;
    } else if (boundaries
                .where((b) => b.kind == WmlFieldBoundaryKind.begin)
                .length !=
            1 ||
        boundaries.where((b) => b.kind == WmlFieldBoundaryKind.end).length !=
            1 ||
        boundaries
                .where((b) => b.kind == WmlFieldBoundaryKind.instruction)
                .map((b) => b.text)
                .join()
                .trim() !=
            original.instruction.trim()) {
      return false;
    }
    if ((paragraph.text.substring(0, original.start) +
            paragraph.text.substring(original.end))
        .trim()
        .isNotEmpty) {
      return false;
    }
    return paragraph.inlines.every(
      (inline) =>
          inline is WmlNoteMarker ||
          inline is WmlFieldBoundary ||
          (inline is WmlRun &&
              inline.hyperlink == null &&
              inline.inlineVisual == null &&
              inline.noteRefId == null &&
              inline.commentIds.isEmpty &&
              (inline.fieldInstruction == null ||
                  inline.fieldInstruction == original.instruction)),
    );
  }

  List<_CitingField> _ordered() => List<_CitingField>.of(_fields)
    ..sort((a, b) {
      var value = a.bodyIndex.compareTo(b.bodyIndex);
      if (value == 0) value = a.anchorOffset.compareTo(b.anchorOffset);
      if (value == 0) value = a.noteOrder.compareTo(b.noteOrder);
      if (value == 0) {
        value = a.original == null
            ? -1
            : b.original == null
            ? 1
            : a.id.compareTo(b.id);
      }
      return value;
    });

  Map<String, Object> _json(
    _CitingField field, {
    Map<Object, int>? noteIndexes,
  }) => <String, Object>{
    'id': field.id,
    'code': field.code,
    'text': field.text,
    'noteIndex': _noteIndex(field, noteIndexes: noteIndexes),
    'adjacent': false,
  };

  Map<Object, int> _noteIndexes() {
    if (!_fields.any((field) => !field.deleted && field.noteType != 0)) {
      return const <Object, int>{};
    }
    final removed = <WmlNote>{
      for (final f in _fields)
        if (f.note != null &&
            (f.noteType != f.originalNoteType || f.deleted) &&
            _isSoleNoteField(f))
          f.note!,
    };
    final positions =
        <({int body, int offset, int priority, Object identity, int type})>[
          for (final n in _notes)
            if (!removed.contains(n.note))
              (
                body: n.bodyIndex,
                offset: n.offset,
                priority: 1,
                identity: n.note,
                type: n.note.endnote ? 2 : 1,
              ),
          for (final f in _fields)
            if (!f.deleted &&
                f.noteType != 0 &&
                (f.original == null || f.noteType != f.originalNoteType))
              (
                body: f.bodyIndex,
                offset: f.anchorOffset,
                priority: 0,
                identity: f,
                type: f.noteType,
              ),
        ]..sort((a, b) {
          final body = a.body.compareTo(b.body);
          if (body != 0) return body;
          final offset = a.offset.compareTo(b.offset);
          if (offset != 0) return offset;
          // Insertions at an existing note marker go immediately before it.
          return a.priority.compareTo(b.priority);
        });
    final indexes = Map<Object, int>.identity();
    final counts = <int, int>{};
    for (final position in positions) {
      final index = (counts[position.type] ?? 0) + 1;
      counts[position.type] = index;
      indexes[position.identity] = index;
    }
    return indexes;
  }

  int _noteIndex(_CitingField field, {Map<Object, int>? noteIndexes}) {
    if (field.noteType == 0) return 0;
    final identity =
        field.note != null && field.noteType == field.originalNoteType
        ? field.note!
        : field;
    final index = (noteIndexes ?? _noteIndexes())[identity];
    if (index != null) return index;
    throw StateError('The citation note no longer has a body position.');
  }

  void _addField(_CitingField field) {
    _fields.add(field);
    _fieldsById[field.id] = field;
    if (field.original != null && field.note != null) {
      _originalFieldsPerNote.update(
        field.note!,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }

  static Map<int, List<WmlNote>> _notesById(List<WmlNote> notes) {
    final result = <int, List<WmlNote>>{};
    for (final note in notes) {
      result.putIfAbsent(note.id, () => []).add(note);
    }
    return result;
  }

  _CitingField _field(Object? id) {
    if (id is! String) {
      throw const FormatException('Zotero returned an invalid field identity.');
    }
    final field = _fieldsById[id];
    if (field == null || field.deleted) {
      throw const FormatException('Zotero addressed an unknown field.');
    }
    return field;
  }

  static ZoteroFieldKind _kind(_CitingField field) =>
      WordZotero.kindOfInstruction(_toNative(field.code)) ??
      (throw const FormatException(
        'Zotero left an unfinished citation field.',
      ));
  static void _validateCode(String code) {
    final native = _toNative(code);
    final kind = WordZotero.kindOfInstruction(native);
    final data = WordZotero.metadataOf(native);
    if (kind == null || data == null) {
      throw const FormatException('Zotero returned invalid citation metadata.');
    }
    if (kind == ZoteroFieldKind.citation) ZoteroCitation.fromJson(data);
  }

  static String _toHttp(String native) {
    final kind = WordZotero.kindOfInstruction(native);
    final data = WordZotero.metadataOf(native);
    if (kind == null || data == null) {
      throw const FormatException('Invalid native Zotero field.');
    }
    return kind == ZoteroFieldKind.citation
        ? 'ITEM CSL_CITATION ${jsonEncode(data)}'
        : 'BIBL ${jsonEncode(data)} CSL_BIBLIOGRAPHY';
  }

  static String _toNative(String code) {
    if (code.startsWith('ITEM CSL_CITATION ')) return ' ADDIN ZOTERO_$code ';
    if (code.startsWith('BIBL ')) return ' ADDIN ZOTERO_$code ';
    if (code.startsWith('CITATION ')) {
      throw UnsupportedError(
        'This legacy Zotero field must be upgraded in Zotero first.',
      );
    }
    throw const FormatException('Zotero returned an unsupported field code.');
  }

  static String _resultInstruction(_CitingField field) {
    final native = _toNative(field.code);
    if (WordZotero.kindOfInstruction(native) != ZoteroFieldKind.citation) {
      return native;
    }
    final citation = ZoteroCitation.fromJson(WordZotero.metadataOf(native)!);
    // A former basic citation now belongs to Zotero's document processor.
    // Keep the basic fallback's refresh action from overwriting CSL output.
    return ZoteroCitation.fromJson({
      ...citation.toJson(),
      'properties': {...citation.properties, 'qudsFormat': 'zotero-desktop'},
    }).fieldInstruction;
  }

  static bool _sameField(WmlZoteroField a, WmlZoteroField b) =>
      identical(a.paragraph, b.paragraph) &&
      a.start == b.start &&
      a.end == b.end &&
      a.instruction == b.instruction;

  bool _canProcessField(WmlZoteroField field) =>
      field.canEdit ||
      (_bodyParagraphs.contains(field.paragraph) &&
          WordZotero.canReplaceNativeBibliography(document, field));

  static bool _hasKnownBibliographyEntries(_CitingField field) {
    final original = field.original;
    return original == null ||
        field.formatted != null ||
        // An identical plain-text response preserves the original result runs.
        // It supplies no new evidence about flattened legacy line breaks.
        (field.textWasSet && field.text != original.cachedText) ||
        original.paragraphs.length > 1 ||
        !original.cachedText.contains('\n') ||
        (original.paragraph.properties.explicitIndent &&
            original.paragraph.properties.explicitLineSpacing &&
            original.paragraph.properties.explicitSpacingAfter);
  }

  static void _arity(List<dynamic> args, int length) {
    if (args.length != length) {
      throw const FormatException('Zotero returned invalid command arguments.');
    }
  }

  static String _string(Object? value) {
    if (value is! String || value.length > 8 * 1024 * 1024) {
      throw const FormatException(
        'Zotero returned an invalid or oversized value.',
      );
    }
    return value;
  }

  static int _noteType(Object? value) {
    if (value is! int || value < 0 || value > 2) {
      throw const FormatException('Zotero returned an unsupported note type.');
    }
    return value;
  }

  static void _httpType(Object? value) {
    if (value != 'Http') {
      throw UnsupportedError('This Zotero field type is not supported.');
    }
  }

  static Iterable<WmlParagraph> _flowParagraphs(
    Iterable<WmlBlock> blocks,
  ) sync* {
    for (final block in blocks) {
      if (block is WmlParagraph) {
        yield block;
      } else if (block is WmlContentControlBlock) {
        yield* _flowParagraphs(block.blocks);
      } else if (block is WmlTable) {
        for (final row in block.rows) {
          for (final cell in row.cells) {
            yield* _flowParagraphs(cell.blocks);
          }
        }
      }
    }
  }
}

final class _CitingField {
  _CitingField.original({
    required this.id,
    required WmlZoteroField original,
    required this.bodyIndex,
    required this.anchor,
    required this.anchorOffset,
    this.note,
    this.noteOrder = 0,
  }) : original = original,
       originalNoteType = note == null
           ? 0
           : note.endnote
           ? 2
           : 1,
       noteType = note == null
           ? 0
           : note.endnote
           ? 2
           : 1,
       code = WordZoteroCitingSession._toHttp(original.instruction),
       text = original.cachedText,
       originalRuns = original.kind == ZoteroFieldKind.citation
           ? WordZotero.copyCitationResult(original)
           : null;
  _CitingField.inserted({
    required this.id,
    required this.bodyIndex,
    required this.anchor,
    required this.anchorOffset,
    required this.noteType,
  }) : original = null,
       originalNoteType = 0,
       note = null,
       noteOrder = -1,
       code = 'TEMP',
       text = '',
       originalRuns = null;
  final String id;
  final WmlZoteroField? original;
  final List<WmlRun>? originalRuns;
  final int bodyIndex;
  final WmlParagraph anchor;
  final int anchorOffset;
  final WmlNote? note;
  final int noteOrder;
  final int originalNoteType;
  int noteType;
  String code;
  String text;
  ZoteroFormattedText? formatted;
  bool textWasSet = false;
  bool codeWasSet = false;
  bool seeded = false;
  bool deleted = false;
  bool unlinked = false;
  bool get changed => original == null
      ? !deleted
      : deleted ||
            unlinked ||
            textWasSet ||
            (codeWasSet &&
                original!.citation?.properties['qudsFormat'] ==
                    'basic-author-year') ||
            noteType != originalNoteType ||
            code != WordZoteroCitingSession._toHttp(original!.instruction);
}

final class _NoteAnchor {
  const _NoteAnchor(this.note, this.paragraph, this.bodyIndex, this.offset);
  final WmlNote note;
  final WmlParagraph paragraph;
  final int bodyIndex;
  final int offset;
}

/// Zotero's native layout callback uses twips; line spacing is expressed in
/// 240ths of a line, and the first-line indent is relative to the body indent.
final class _BibliographyStyle {
  _BibliographyStyle.fromArguments(List<dynamic> args) {
    bool bounded(Object? value, {bool negative = false}) =>
        value is num &&
        value.isFinite &&
        value.abs() <= 1440000 &&
        (negative || value >= 0);
    if (!bounded(args[1], negative: true) ||
        !bounded(args[2], negative: true) ||
        !bounded(args[3]) ||
        (args[3] as num) <= 0 ||
        (args[3] as num) > 24000 ||
        !bounded(args[4]) ||
        args[5] is! List ||
        args[6] is! int ||
        (args[5] as List).length != args[6] ||
        (args[5] as List).length > 100 ||
        (args[5] as List).any((value) => !bounded(value))) {
      throw const FormatException(
        'Zotero returned an invalid bibliography layout.',
      );
    }
    firstLine = (args[1] as num).toDouble() / 20;
    indent = (args[2] as num).toDouble() / 20;
    lineSpacing = (args[3] as num).toDouble() / 240;
    entrySpacing = (args[4] as num).toDouble() / 20;
    tabs = (args[5] as List)
        .cast<num>()
        .map((value) => WmlTabStop(position: value.toDouble() / 20))
        .toList();
  }

  late final double firstLine;
  late final double indent;
  late final double lineSpacing;
  late final double entrySpacing;
  late final List<WmlTabStop> tabs;

  void applyTo(WmlParagraphProps properties) {
    properties
      ..indent = WmlIndent(
        left: indent,
        right: properties.indent.right,
        firstLine: firstLine > 0 ? firstLine : 0,
        hanging: firstLine < 0 ? -firstLine : 0,
      )
      ..explicitIndent = true
      ..lineSpacing = lineSpacing
      ..lineSpacingRule = WmlLineSpacingRule.auto
      ..explicitLineSpacing = true
      ..spacingBefore = 0
      ..explicitSpacingBefore = true
      ..spacingAfter = entrySpacing
      ..explicitSpacingAfter = true
      ..tabs = List.of(tabs);
  }
}
