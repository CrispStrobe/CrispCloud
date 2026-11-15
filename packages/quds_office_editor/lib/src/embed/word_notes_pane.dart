import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'office_controller.dart';
import 'office_theme.dart';

/// Chrome pane listing footnotes, endnotes, and tracked revisions.
class WordNotesPane extends StatefulWidget {
  /// WordNotesPane API.
  const WordNotesPane({
    super.key,
    required this.controller,
    this.arabic = false,
  });

  /// controller API.
  final WordEditorController controller;

  /// arabic API.
  final bool arabic;

  @override
  State<WordNotesPane> createState() => _WordNotesPaneState();
}

class _WordNotesPaneState extends State<WordNotesPane> {
  final Map<WmlNote, TextEditingController> _noteEdits =
      <WmlNote, TextEditingController>{};
  final Map<WmlNote, FocusNode> _noteFocus = <WmlNote, FocusNode>{};

  WordEditorController get _c => widget.controller;

  @override
  void dispose() {
    for (final TextEditingController edit in _noteEdits.values) {
      edit.dispose();
    }
    for (final FocusNode focus in _noteFocus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  FocusNode _focusFor(WmlNote note) => _noteFocus.putIfAbsent(note, () {
    final FocusNode focus = FocusNode();
    focus.addListener(() {
      if (!focus.hasFocus) {
        _c.commitNoteEdit(note);
      }
    });
    return focus;
  });

  /// One controller per note object. Text changed elsewhere (undo, another
  /// view) is pulled in while the field is not being typed in.
  TextEditingController _editFor(WmlNote note) {
    final String current = _c.noteEditText(note);
    final TextEditingController edit = _noteEdits.putIfAbsent(
      note,
      () => TextEditingController(text: current),
    );
    if (edit.text != current && !(_noteFocus[note]?.hasFocus ?? false)) {
      edit.value = TextEditingValue(
        text: current,
        selection: TextSelection.collapsed(offset: current.length),
      );
    }
    return edit;
  }

  void _dropStale(List<WmlNote> notes) {
    for (final WmlNote gone
        in _noteEdits.keys.where((WmlNote n) => !notes.contains(n)).toList()) {
      _noteEdits.remove(gone)?.dispose();
      _noteFocus.remove(gone)?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final OfficeTheme theme = _c.config.theme;
    final List<WmlNote> notes = <WmlNote>[
      ..._c.document.footnotes,
      ..._c.document.endnotes,
    ];
    _dropStale(notes);
    final bool editable = _c.config.allowsMutation;
    return ColoredBox(
      color: theme.chromeFill,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.arabic ? 'ملاحظات' : 'Notes',
              style: TextStyle(
                color: theme.chromeText,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            if (editable) ...<Widget>[
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                children: <Widget>[
                  GestureDetector(
                    key: const ValueKey<String>('notes-add-footnote'),
                    onTap: () => _c.insertFootnote(),
                    child: Text(
                      widget.arabic ? '+ حاشية سفلية' : '+ Footnote',
                      style: TextStyle(color: theme.focusRing, fontSize: 11),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey<String>('notes-add-endnote'),
                    onTap: () => _c.insertFootnote(endnote: true),
                    child: Text(
                      widget.arabic ? '+ حاشية ختامية' : '+ Endnote',
                      style: TextStyle(color: theme.focusRing, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            if (notes.isEmpty)
              Text(
                widget.arabic ? 'لا توجد حواشٍ' : 'No notes',
                style: TextStyle(color: theme.headerText, fontSize: 11),
              )
            else
              ...notes.map((WmlNote note) {
                final String mark = note.endnote ? 'E${note.id}' : '${note.id}';
                final TextEditingController edit = _editFor(note);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _c.jumpToNote(note),
                              child: Text(
                                widget.arabic ? 'حاشية $mark' : 'Note $mark',
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
                              key: ValueKey<String>('notes-delete-$mark'),
                              onTap: () => _c.deleteNote(note),
                              child: Text(
                                widget.arabic ? 'حذف' : 'Delete',
                                style: TextStyle(
                                  color: theme.headerText,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        key: ValueKey<String>('notes-edit-$mark'),
                        controller: edit,
                        focusNode: _focusFor(note),
                        minLines: 1,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        enabled: editable,
                        style: TextStyle(color: theme.chromeText, fontSize: 11),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        onChanged: (String value) =>
                            _c.setNoteText(note, value),
                        onTapOutside: (_) => _focusFor(note).unfocus(),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 12),
            Text(
              widget.arabic ? 'التغييرات' : 'Revisions',
              style: TextStyle(
                color: theme.chromeText,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            if (_c.document.revisions.isEmpty)
              Text(
                widget.arabic ? 'لا توجد تغييرات' : 'No revisions',
                style: TextStyle(color: theme.headerText, fontSize: 11),
              )
            else
              ..._c.document.revisions.map((WmlRevision revision) {
                final bool on = identical(revision, _c.selectedRevision);
                final String kind = revision.kind == WmlRevisionKind.insert
                    ? (widget.arabic ? 'إدراج' : 'Insert')
                    : (widget.arabic ? 'حذف' : 'Delete');
                return GestureDetector(
                  onTap: () => _c.selectRevision(revision),
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
                              revision.text,
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
                                  onTap: () => _c.acceptRevision(revision),
                                  child: Text(
                                    widget.arabic ? 'قبول' : 'Accept',
                                    style: TextStyle(
                                      color: theme.focusRing,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: () => _c.rejectRevision(revision),
                                  child: Text(
                                    widget.arabic ? 'رفض' : 'Reject',
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
    );
  }
}
