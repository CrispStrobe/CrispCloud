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
  final Map<int, TextEditingController> _noteEdits =
      <int, TextEditingController>{};

  WordEditorController get _c => widget.controller;

  @override
  void dispose() {
    for (final TextEditingController edit in _noteEdits.values) {
      edit.dispose();
    }
    super.dispose();
  }

  TextEditingController _editFor(WmlNote note) {
    final int key = note.endnote ? -note.id : note.id;
    return _noteEdits.putIfAbsent(
      key,
      () => TextEditingController(text: note.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final OfficeTheme theme = _c.config.theme;
    final List<WmlNote> notes = <WmlNote>[
      ..._c.document.footnotes,
      ..._c.document.endnotes,
    ];
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
                      GestureDetector(
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
                      const SizedBox(height: 4),
                      TextField(
                        controller: edit,
                        maxLines: 2,
                        enabled: _c.config.allowsMutation,
                        style: TextStyle(color: theme.chromeText, fontSize: 11),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        onChanged: (String value) =>
                            _c.setNoteText(note, value),
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
