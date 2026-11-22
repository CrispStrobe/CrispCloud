import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../proofing/word_proofing.dart';
import 'office_controller.dart';
import 'word_review_labels.dart';
import 'office_theme.dart';
import '../l10n/office_language.dart';
import '../l10n/office_plural.dart';

/// Chrome pane listing footnotes, endnotes, and tracked revisions.
class WordNotesPane extends StatefulWidget {
  /// WordNotesPane API.
  const WordNotesPane({
    super.key,
    required this.controller,
    this.arabic = false,
    this.german,
  });

  /// controller API.
  final WordEditorController controller;

  /// arabic API.
  final bool arabic;

  /// German labels; when null, German follows [OfficeStrings.german] in the
  /// controller's surface configuration. [arabic] takes precedence.
  final bool? german;

  @override
  State<WordNotesPane> createState() => _WordNotesPaneState();
}

class _WordNotesPaneState extends State<WordNotesPane> {
  final Map<WmlNote, _NoteProofingTextController> _noteEdits =
      <WmlNote, _NoteProofingTextController>{};
  final Map<WmlNote, FocusNode> _noteFocus = <WmlNote, FocusNode>{};
  final Map<WmlNote, GlobalKey> _noteLocations = <WmlNote, GlobalKey>{};
  bool _syncing = false;
  bool _focusScheduled = false;
  int _handledFocusRequest = 0;
  String? _notice;

  WordEditorController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(WordNotesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, _c)) {
      oldWidget.controller.removeListener(_controllerChanged);
      oldWidget.controller.clearNoteEditingTarget(notify: false);
      _disposeEdits();
      _handledFocusRequest = 0;
      _notice = null;
      _c.addListener(_controllerChanged);
    }
  }

  void _controllerChanged() {
    if (mounted && !_syncing) setState(() {});
  }

  void _scheduleEditingFocus() {
    if (_focusScheduled ||
        _handledFocusRequest == _c.noteFocusRequest ||
        _c.noteEditingTarget == null) {
      return;
    }
    _focusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScheduled = false;
      if (!mounted ||
          _c.isDisposed ||
          !_c.config.allowsSelection ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      final target = _c.noteEditingTarget;
      if (target == null ||
          _handledFocusRequest == _c.noteFocusRequest ||
          !_noteEdits.containsKey(target.note)) {
        return;
      }
      _handledFocusRequest = _c.noteFocusRequest;
      // Jump to the note first. EditableText then reveals the selected caret
      // when focus arrives, including offsets near the end of a long note.
      final location = _noteLocations[target.note]?.currentContext;
      if (location != null) {
        unawaited(Scrollable.ensureVisible(location, alignment: 0.2));
      }
      _focusFor(target.note).requestFocus();
    });
  }

  @override
  void dispose() {
    _c.removeListener(_controllerChanged);
    if (_noteEdits.containsKey(_c.noteEditingTarget?.note)) {
      _c.clearNoteEditingTarget(notify: false);
    }
    _disposeEdits();
    super.dispose();
  }

  void _disposeEdits() {
    _syncing = true;
    for (final TextEditingController edit in _noteEdits.values) {
      edit.dispose();
    }
    for (final FocusNode focus in _noteFocus.values) {
      focus.dispose();
    }
    _noteEdits.clear();
    _noteFocus.clear();
    _noteLocations.clear();
    _syncing = false;
  }

  FocusNode _focusFor(WmlNote note) => _noteFocus.putIfAbsent(note, () {
    final FocusNode focus = FocusNode();
    focus.addListener(() {
      if (_syncing || _c.isDisposed) return;
      if (focus.hasFocus) {
        _publishSelection(note);
      } else {
        _c.commitNoteEdit(note);
      }
    });
    return focus;
  });

  void _publishSelection(WmlNote note) {
    final edit = _noteEdits[note];
    if (_syncing ||
        edit == null ||
        !(_noteFocus[note]?.hasFocus ?? false) ||
        edit.text != _c.noteEditText(note) ||
        !edit.selection.isValid) {
      return;
    }
    _c.setNoteEditingTarget(
      note,
      edit.selection,
      composing: edit.value.composing,
    );
  }

  /// One controller per note object. Native replacements and undo update this
  /// view even if it retained focus while a keyboard command was running.
  _NoteProofingTextController _editFor(WmlNote note) {
    final String current = _c.noteEditText(note);
    final _NoteProofingTextController edit = _noteEdits.putIfAbsent(note, () {
      final edit = _NoteProofingTextController(text: current);
      edit.addListener(() => _publishSelection(note));
      return edit;
    });
    final target = _c.noteEditingTarget;
    final selection = identical(target?.note, note)
        ? target!.selection
        : edit.selection;
    final safeSelection = selection.isValid
        ? selection.copyWith(
            baseOffset: selection.baseOffset.clamp(0, current.length),
            extentOffset: selection.extentOffset.clamp(0, current.length),
          )
        : TextSelection.collapsed(offset: current.length);
    if (edit.text != current || edit.selection != safeSelection) {
      _syncing = true;
      try {
        edit.value = TextEditingValue(
          text: current,
          selection: safeSelection,
          composing: edit.text == current
              ? edit.value.composing
              : TextRange.empty,
        );
      } finally {
        _syncing = false;
      }
    }
    return edit;
  }

  OfficeUiLanguage get _language => OfficeUiLanguage.from(
    arabic: widget.arabic,
    german: widget.german ?? OfficeUiLanguage.of(_c.config).isGerman,
  );
  String _s(String english, String arabic) => _language.label(english, arabic);

  bool get _canInspect =>
      mounted &&
      !_c.isDisposed &&
      _c.config.allowsSelection &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  bool _composing(WmlNote note) {
    final composing = _noteEdits[note]?.value.composing;
    return composing != null && composing.isValid && !composing.isCollapsed;
  }

  Future<void> _check({bool includeManualProviders = true}) async {
    if (!_canInspect) return;
    final controller = _c;
    if (includeManualProviders) {
      await controller.checkDocumentProofing();
    } else {
      await controller.proofing.checkNow(includeManualProviders: false);
    }
  }

  void _history(WmlNote note, {required bool redo}) {
    if (!_canInspect ||
        !_c.canApplyProofingSuggestions ||
        _composing(note) ||
        !(note.endnote ? _c.document.endnotes : _c.document.footnotes).contains(
          note,
        )) {
      return;
    }
    _publishSelection(note);
    setState(() => _notice = null);
    if (redo) {
      _c.redo();
    } else {
      _c.undo();
    }
    _c.requestEditingFocus();
  }

  void _refreshAfterChoice() {
    if (!_c.proofing.enabled) {
      unawaited(_check(includeManualProviders: false));
    }
  }

  void _stepFinding(WmlNote note, int delta) {
    if (!_canInspect || _composing(note)) return;
    final issues = _c.proofingIssuesForNote(note);
    if (issues.isEmpty) return;
    final selected = _c.selectedProofingIssue;
    final current = issues.indexWhere(
      (entry) => identical(entry.issue, selected),
    );
    final next = current < 0
        ? (delta > 0 ? 0 : issues.length - 1)
        : (current + delta) % issues.length;
    _c.selectProofingIssue(issues[next].issue);
  }

  void _apply(WmlNote note, WordProofingIssue issue, String replacement) {
    if (!_canInspect || _composing(note)) return;
    // The issue belongs to the exact note and checked source represented by
    // this button. A retained callback cannot edit a replacement document.
    final current = _c.currentNoteProofingIssue(note, issue);
    if (current == null || !_c.canApplyProofingIssue(current)) return;
    final range = _c
        .proofingIssuesForNote(note)
        .firstWhere((entry) => identical(entry.issue, current))
        .range;
    _c.setNoteEditingTarget(
      note,
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    final applied = _c.applyProofingSuggestion(current, replacement);
    setState(() {
      _notice = applied
          ? _s(
              'Correction applied. Undo is available.',
              'تم التصحيح. يمكنك التراجع.',
            )
          : _s(
              'The text changed or is protected. Check it again before correcting.',
              'تغير النص أو أنه محمي. أعد تدقيقه قبل التصحيح.',
            );
    });
    if (applied) _c.requestEditingFocus();
    _refreshAfterChoice();
  }

  void _ignore(
    WmlNote note,
    WordProofingIssue issue,
    void Function(WordProofingIssue current) operation,
  ) {
    if (!_canInspect || _composing(note)) return;
    final current = _c.currentNoteProofingIssue(note, issue);
    if (current == null) return;
    operation(current);
    setState(() => _notice = null);
    _refreshAfterChoice();
    if (identical(_c.noteEditingTarget?.note, note)) _c.requestEditingFocus();
  }

  Widget _writingStatus(OfficeTheme theme) {
    final session = _c.proofing;
    final summary = session.summary;
    final status = summary.checking
        ? _s('Checking document…', 'جارٍ تدقيق المستند…')
        : summary.scheduled
        ? _s(
            'Waiting for a pause in typing…',
            'في انتظار توقف قصير عن الكتابة…',
          )
        : !session.enabled
        ? _s(
            'Check as you type is paused.',
            'التدقيق أثناء الكتابة متوقف مؤقتًا.',
          )
        : summary.statusMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _s('Check as you type', 'التدقيق أثناء الكتابة'),
                style: TextStyle(color: theme.chromeText, fontSize: 11),
              ),
            ),
            Switch.adaptive(
              key: const ValueKey<String>('notes-live-checking'),
              value: session.enabled,
              onChanged: _c.config.allowsSelection
                  ? (value) => session.enabled = value
                  : null,
            ),
          ],
        ),
        Text(
          status,
          key: const ValueKey<String>('notes-proofing-status'),
          style: TextStyle(color: theme.headerText, fontSize: 11),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: const ValueKey<String>('notes-check-now'),
            onPressed: !_c.config.allowsSelection
                ? null
                : () => unawaited(_check()),
            child: Text(_s('Check document (F7)', 'تدقيق المستند (F7)')),
          ),
        ),
        if (_notice != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _notice!,
              key: const ValueKey<String>('notes-proofing-notice'),
              style: TextStyle(color: theme.headerText, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _findingControls(
    WmlNote note,
    String identity,
    List<({WordProofingIssue issue, TextRange range})> issues,
    OfficeTheme theme,
  ) {
    final selected = _c.selectedProofingIssue;
    final entry =
        issues.where((entry) => identical(entry.issue, selected)).firstOrNull ??
        issues.first;
    final issue = entry.issue;
    final finding = issue.finding;
    final composing = _composing(note);
    final canInspect = _c.config.allowsSelection && !composing;
    final canApply = canInspect && _c.canApplyProofingIssue(issue);
    return Column(
      key: ValueKey<String>('notes-proofing-$identity'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _language.phrase(
                  '${issues.length} writing suggestions',
                  officePlural(
                    issues.length,
                    arabic: false,
                    german: true,
                    one: (n) => '$n writing suggestion',
                    other: (n) => '$n writing suggestions',
                    germanOne: (_) => '1 Schreibvorschlag',
                    germanOther: (n) => '$n Schreibvorschläge',
                  ),
                  '${issues.length} اقتراحات للكتابة',
                ),
                style: TextStyle(color: theme.headerText, fontSize: 11),
              ),
            ),
            IconButton(
              key: ValueKey<String>('notes-previous-finding-$identity'),
              tooltip: _s('Previous suggestion', 'الاقتراح السابق'),
              onPressed: canInspect ? () => _stepFinding(note, -1) : null,
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            ),
            IconButton(
              key: ValueKey<String>('notes-next-finding-$identity'),
              tooltip: _s('Next suggestion', 'الاقتراح التالي'),
              onPressed: canInspect ? () => _stepFinding(note, 1) : null,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            ),
          ],
        ),
        Text(
          finding.message,
          key: ValueKey<String>('notes-finding-message-$identity'),
          style: TextStyle(color: theme.chromeText, fontSize: 11),
        ),
        Wrap(
          spacing: 4,
          children: [
            for (var index = 0; index < finding.replacements.length; index++)
              TextButton(
                key: ValueKey<String>('notes-replacement-$identity-$index'),
                onPressed: canApply
                    ? () => _apply(note, issue, finding.replacements[index])
                    : null,
                child: Text(
                  finding.replacements[index].isEmpty
                      ? _s('Remove', 'إزالة')
                      : finding.replacements[index],
                ),
              ),
            TextButton(
              key: ValueKey<String>('notes-ignore-$identity'),
              onPressed: canInspect
                  ? () => _ignore(
                      note,
                      issue,
                      (current) => _c.proofing.ignoreOnce(current),
                    )
                  : null,
              child: Text(_s('Ignore once', 'تجاهل مرة واحدة')),
            ),
            if (finding.category == OfficeProofingCategory.spelling)
              TextButton(
                key: ValueKey<String>('notes-add-word-$identity'),
                onPressed: canInspect
                    ? () => _ignore(
                        note,
                        issue,
                        (current) => _c.proofing.addWord(current),
                      )
                    : null,
                child: Text(_s('Add to dictionary', 'إضافة إلى القاموس')),
              ),
          ],
        ),
        if (composing || (!canApply && finding.replacements.isNotEmpty))
          Text(
            composing
                ? _s(
                    'Finish composing before correcting.',
                    'أكمل إدخال النص قبل التصحيح.',
                  )
                : _s(
                    'Corrections are unavailable for this text.',
                    'التصحيحات غير متاحة لهذا النص.',
                  ),
            style: TextStyle(color: theme.headerText, fontSize: 11),
          ),
      ],
    );
  }

  void _dropStale(List<WmlNote> notes) {
    _syncing = true;
    for (final WmlNote gone
        in _noteEdits.keys.where((WmlNote n) => !notes.contains(n)).toList()) {
      _noteEdits.remove(gone)?.dispose();
      _noteFocus.remove(gone)?.dispose();
      _noteLocations.remove(gone);
    }
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) {
    final OfficeTheme theme = _c.config.theme;
    final numbering = WordNoteNumbering(_c.document);
    final List<WmlNote> notes = numbering.notes;
    _dropStale(notes);
    final bool editable = _c.config.allowsMutation;
    _scheduleEditingFocus();
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f7): () => unawaited(_check()),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
          final note = _c.noteEditingTarget?.note;
          if (note != null) _history(note, redo: true);
        },
        const SingleActivator(LogicalKeyboardKey.f7, alt: true): () {
          final target = _c.noteEditingTarget;
          if (target != null) _stepFinding(target.note, 1);
        },
        const SingleActivator(
          LogicalKeyboardKey.f7,
          alt: true,
          shift: true,
        ): () {
          final target = _c.noteEditingTarget;
          if (target != null) _stepFinding(target.note, -1);
        },
      },
      child: TextFieldTapRegion(
        child: ColoredBox(
          color: theme.chromeFill,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    _s('Notes', 'ملاحظات'),
                    style: TextStyle(
                      color: theme.chromeText,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  _writingStatus(theme),
                  if (editable) ...<Widget>[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      children: <Widget>[
                        GestureDetector(
                          key: const ValueKey<String>('notes-add-footnote'),
                          onTap: () => _c.insertFootnote(),
                          child: Text(
                            _s('+ Footnote', '+ حاشية سفلية'),
                            style: TextStyle(
                              color: theme.focusRing,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        GestureDetector(
                          key: const ValueKey<String>('notes-add-endnote'),
                          onTap: () => _c.insertFootnote(endnote: true),
                          child: Text(
                            _s('+ Endnote', '+ حاشية ختامية'),
                            style: TextStyle(
                              color: theme.focusRing,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (notes.isEmpty)
                    Text(
                      _s('No notes', 'لا توجد حواشٍ'),
                      style: TextStyle(color: theme.headerText, fontSize: 11),
                    )
                  else
                    ...notes.map((WmlNote note) {
                      final String label = numbering.labelFor(note);
                      final String mark = label.isEmpty
                          ? _s('custom', 'مخصصة')
                          : (note.endnote ? 'E$label' : label);
                      // Widget identity follows the native link, not its changing
                      // visible number, so edits and focus survive renumbering.
                      final String identity = note.endnote
                          ? 'E${note.id}'
                          : '${note.id}';
                      final String title = numbering.hasExactLabel(note)
                          ? _language.phrase(
                              'Note $mark',
                              '${note.endnote ? 'Endnote' : 'Fußnote'} $mark',
                              'حاشية $mark',
                            )
                          : _language.phrase(
                              'Note (source ID $identity)',
                              '${note.endnote ? 'Endnote' : 'Fußnote'} (Quell-ID $identity)',
                              'حاشية (معرّف المصدر $identity)',
                            );
                      final issues = _c.proofingIssuesForNote(note);
                      final edit = _editFor(note)
                        ..checkedText = _c.noteEditText(note)
                        ..issues = issues;
                      return Padding(
                        key: ValueKey<WmlNote>(note),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          key: _noteLocations.putIfAbsent(note, GlobalKey.new),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _c.jumpToNote(note),
                                    child: Text(
                                      title,
                                      style: TextStyle(
                                        color: theme.focusRing,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                if (editable)
                                  GestureDetector(
                                    key: ValueKey<String>(
                                      'notes-delete-$identity',
                                    ),
                                    onTap: () => _c.deleteNote(note),
                                    child: Text(
                                      _s('Delete', 'حذف'),
                                      style: TextStyle(
                                        color: theme.headerText,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Override EditableText's private text-only history:
                            // native Undo/Redo shortcuts must restore document
                            // revisions and formatting as well as the field text.
                            Actions(
                              actions: <Type, Action<Intent>>{
                                UndoTextIntent: CallbackAction<UndoTextIntent>(
                                  onInvoke: (_) {
                                    _history(note, redo: false);
                                    return null;
                                  },
                                ),
                                RedoTextIntent: CallbackAction<RedoTextIntent>(
                                  onInvoke: (_) {
                                    _history(note, redo: true);
                                    return null;
                                  },
                                ),
                              },
                              child: TextField(
                                key: ValueKey<String>('notes-edit-$identity'),
                                controller: edit,
                                focusNode: _focusFor(note),
                                minLines: 1,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                enabled: _c.config.allowsSelection,
                                readOnly: !editable,
                                enableInteractiveSelection:
                                    _c.config.allowsSelection,
                                style: TextStyle(
                                  color: theme.chromeText,
                                  fontSize: 11,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                ),
                                onChanged: editable
                                    ? (String value) {
                                        _notice = null;
                                        _c.setNoteText(note, value);
                                        _publishSelection(note);
                                      }
                                    : null,
                                onTapOutside: (_) => _focusFor(note).unfocus(),
                              ),
                            ),
                            if (issues.isNotEmpty)
                              _findingControls(note, identity, issues, theme),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const ValueKey<String>('notes-review-changes'),
                      onPressed: () =>
                          _c.openReviewPane(tab: WordReviewPaneTab.changes),
                      child: Text(_s('Review changes', 'مراجعة التغييرات')),
                    ),
                  ),
                  Text(
                    _s('Revisions', 'التغييرات'),
                    style: TextStyle(
                      color: theme.chromeText,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_c.document.revisions.isEmpty)
                    Text(
                      _s('No revisions', 'لا توجد تغييرات'),
                      style: TextStyle(color: theme.headerText, fontSize: 11),
                    )
                  else
                    ..._c.document.revisions.map((WmlRevision revision) {
                      final bool on = identical(revision, _c.selectedRevision);
                      final String kind = revision.kind.reviewLabel(
                        arabic: _language.isArabic,
                        german: _language.isGerman,
                      );
                      return GestureDetector(
                        onTap: () => _c.revealRevision(revision),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ColoredBox(
                            color: on
                                ? theme.focusRing.withValues(alpha: 0.12)
                                : const Color(0x00000000),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Text(
                                    '$kind · ${revision.author}',
                                    style: TextStyle(
                                      color: theme.chromeText,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    revision.displayText,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.headerText,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Row(
                                    children: <Widget>[
                                      GestureDetector(
                                        onTap:
                                            editable &&
                                                revision.conflict == null
                                            ? () => _c.acceptRevision(revision)
                                            : null,
                                        child: Text(
                                          _s('Accept', 'قبول'),
                                          style: TextStyle(
                                            color: theme.focusRing,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      GestureDetector(
                                        onTap:
                                            editable &&
                                                revision.conflict == null
                                            ? () => _c.rejectRevision(revision)
                                            : null,
                                        child: Text(
                                          _s('Reject', 'رفض'),
                                          style: TextStyle(
                                            color: theme.focusRing,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints source-bound findings without replacing text, composition, selection,
/// or the Notes pane's native editing/undo controller.
class _NoteProofingTextController extends TextEditingController {
  _NoteProofingTextController({super.text});

  String checkedText = '';
  List<({WordProofingIssue issue, TextRange range})> issues = const [];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (checkedText != text ||
        issues.isEmpty ||
        (value.composing.isValid && !value.composing.isCollapsed)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final valid = issues.where((entry) {
      final range = entry.range;
      return range.isValid &&
          !range.isCollapsed &&
          range.end <= text.length &&
          text.substring(range.start, range.end) ==
              entry.issue.finding.originalText;
    }).toList();
    final boundaries = <int>{0, text.length};
    for (final entry in valid) {
      boundaries.addAll([entry.range.start, entry.range.end]);
    }
    final sorted = boundaries.toList()..sort();
    return TextSpan(
      style: style,
      children: [
        for (var index = 0; index < sorted.length - 1; index++)
          TextSpan(
            text: text.substring(sorted[index], sorted[index + 1]),
            style: _findingStyle(
              valid
                  .where(
                    (entry) =>
                        entry.range.start <= sorted[index] &&
                        entry.range.end >= sorted[index + 1],
                  )
                  .firstOrNull
                  ?.issue
                  .finding
                  .category,
            ),
          ),
      ],
    );
  }

  TextStyle? _findingStyle(OfficeProofingCategory? category) => category == null
      ? null
      : TextStyle(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: switch (category) {
            OfficeProofingCategory.spelling => const Color(0xFFC62828),
            OfficeProofingCategory.grammar => const Color(0xFF1565C0),
            OfficeProofingCategory.style => const Color(0xFFAD6800),
          },
        );
}
