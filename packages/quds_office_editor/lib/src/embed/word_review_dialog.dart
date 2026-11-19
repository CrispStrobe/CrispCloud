import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'office_controller.dart';

/// The two independent workflows in the document review workspace.
enum WordReviewTab { changes, compare }

/// A host-picked document. Picking never replaces the open editor document.
class WordComparisonDocument {
  const WordComparisonDocument({required this.document, required this.name});

  final WmlDocument document;
  final String name;
}

typedef WordComparisonDocumentPicker =
    Future<WordComparisonDocument?> Function();

/// Returns false when the user cancels the export destination picker.
typedef WordComparisonReportExporter =
    Future<bool> Function(String suggestedName, String json);

/// Opens tracked-change review and an independent two-document comparison.
/// Hosts supply their existing picker/export integration; the editor package
/// does not acquire filesystem or file-picker dependencies.
Future<void> showWordReviewDialog(
  BuildContext context, {
  required WordEditorController controller,
  String documentName = 'Current document',
  WordComparisonDocumentPicker? pickDocument,
  WordComparisonReportExporter? onExportReport,
  WordReviewTab initialTab = WordReviewTab.changes,
  bool arabic = false,
}) {
  controller.commitPendingEdits();
  return showDialog<void>(
    context: context,
    builder: (context) => WordReviewDialog(
      controller: controller,
      documentName: documentName,
      pickDocument: pickDocument,
      onExportReport: onExportReport,
      initialTab: initialTab,
      arabic: arabic,
    ),
  );
}

/// Review controls are undoable controller commands. Comparisons are immutable
/// reports; neither input is turned into tracked revisions or overwritten.
class WordReviewDialog extends StatefulWidget {
  const WordReviewDialog({
    super.key,
    required this.controller,
    this.documentName = 'Current document',
    this.pickDocument,
    this.onExportReport,
    this.initialTab = WordReviewTab.changes,
    this.arabic = false,
  });

  final WordEditorController controller;
  final String documentName;
  final WordComparisonDocumentPicker? pickDocument;
  final WordComparisonReportExporter? onExportReport;
  final WordReviewTab initialTab;
  final bool arabic;

  @override
  State<WordReviewDialog> createState() => _WordReviewDialogState();
}

class _WordReviewDialogState extends State<WordReviewDialog> {
  late WordReviewTab _tab;
  late final TextEditingController _author;
  final TextEditingController _search = TextEditingController();
  final TextEditingController _comparisonSearch = TextEditingController();
  String? _authorFilter;
  WmlRevisionKind? _kindFilter;
  String _query = '';
  WmlRevision? _selected;
  WordComparisonRevisionView _preview = WordComparisonRevisionView.markup;
  WordComparisonDocument? _original;
  WordComparisonDocument? _revised;
  bool _originalIsCurrent = true;
  bool _revisedIsCurrent = false;
  bool _ignoreCase = false;
  bool _ignoreWhitespace = false;
  bool _includeFormatting = true;
  WordComparisonRevisionView _revisionView =
      WordComparisonRevisionView.finalText;
  WordComparisonResult? _result;
  String _resultOriginalName = '';
  String _resultRevisedName = '';
  bool _inline = false;
  bool _changesOnly = true;
  WordComparisonKind? _comparisonKind;
  String _comparisonQuery = '';
  int? _comparisonSelection;
  bool _focusDifference = false;
  final ScrollController _comparisonScroll = ScrollController();
  bool _busy = false;
  String? _notice;
  int _generation = 0;
  WmlDocument? _comparedCurrent;
  int? _comparedRevision;

  WordEditorController get _c => widget.controller;
  String _s(String english, String arabic) => widget.arabic ? arabic : english;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _author = TextEditingController(text: _c.revisionAuthor);
  }

  @override
  void didUpdateWidget(WordReviewDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, _c)) {
      _generation++;
      _busy = false;
      _selected = null;
      _result = null;
      _author.text = _c.revisionAuthor;
    }
  }

  @override
  void dispose() {
    _generation++;
    _author.dispose();
    _search.dispose();
    _comparisonSearch.dispose();
    _comparisonScroll.dispose();
    super.dispose();
  }

  List<WmlRevision> get _pending => _c.document.revisions
      .where((revision) => revision.accepted == null)
      .toList();

  List<WmlRevision> _filteredChanges(List<WmlRevision> pending) {
    final query = _query.trim().toLowerCase();
    return pending.where((revision) {
      return (_authorFilter == null || revision.author == _authorFilter) &&
          (_kindFilter == null || revision.kind == _kindFilter) &&
          (query.isEmpty ||
              revision.text.toLowerCase().contains(query) ||
              revision.author.toLowerCase().contains(query));
    }).toList();
  }

  Map<WmlRevision, WmlParagraph?> _reviewTargets(List<WmlRevision> pending) {
    // Most imported/editor revisions already capture paragraph identity. Only
    // legacy index-only entries need a single shared body traversal. Resolving
    // every revision separately would rescan the whole document per preview.
    final body = pending.any((revision) => !revision.hasCapturedTarget)
        ? _c.document.paragraphs.toList()
        : const <WmlParagraph>[];
    return <WmlRevision, WmlParagraph?>{
      for (final revision in pending)
        revision:
            revision.targetParagraph ??
            (!revision.hasCapturedTarget &&
                    revision.paragraphIndex >= 0 &&
                    revision.paragraphIndex < body.length
                ? body[revision.paragraphIndex]
                : null),
    };
  }

  void _act(VoidCallback action) {
    try {
      action();
      if (mounted) {
        setState(
          () => _notice = _s(
            'Review updated. Undo restores the previous changes.',
            'تم تحديث المراجعة. التراجع يعيد التغييرات السابقة.',
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _notice = '$error');
    }
  }

  void _select(WmlRevision revision) {
    _c.selectRevision(revision);
    setState(() => _selected = revision);
  }

  void _setAuthor() {
    try {
      _c.revisionAuthor = _author.text;
      _author.text = _c.revisionAuthor;
      setState(
        () => _notice = _s(
          'New tracked changes will use ${_c.revisionAuthor}.',
          'ستستخدم التغييرات الجديدة اسم ${_c.revisionAuthor}.',
        ),
      );
    } on ArgumentError catch (error) {
      setState(() => _notice = '$error');
    }
  }

  void _step(List<WmlRevision> visible, WmlRevision? selected, int delta) {
    if (visible.isEmpty) return;
    final index = selected == null ? -1 : visible.indexOf(selected);
    final next = index < 0
        ? (delta < 0 ? visible.length - 1 : 0)
        : (index + delta) % visible.length;
    _select(visible[next]);
  }

  void _showInDocument(WmlRevision revision) {
    if (_c.revealRevision(revision)) {
      Navigator.of(context).pop();
    } else {
      setState(
        () => _notice = _s(
          'This change is available here, but its story cannot be selected in the current canvas.',
          'يمكن مراجعة هذا التغيير هنا، ولكن لا يمكن تحديد موضعه في العرض الحالي.',
        ),
      );
    }
  }

  void _invalidateComparison() {
    _result = null;
    _comparisonSelection = null;
    _focusDifference = false;
    _notice = null;
    _generation++;
  }

  Future<void> _pick(bool original) async {
    final picker = widget.pickDocument;
    if (picker == null || _busy) return;
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final picked = await picker();
      if (!mounted || generation != _generation || picked == null) return;
      setState(() {
        if (original) {
          _original = picked;
          _originalIsCurrent = false;
        } else {
          _revised = picked;
          _revisedIsCurrent = false;
        }
        _result = null;
        _comparisonSelection = null;
        _notice = null;
      });
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _notice =
              '${_s('Could not open document', 'تعذر فتح المستند')}: $error',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  WordComparisonDocument? _source(bool original) {
    final current = original ? _originalIsCurrent : _revisedIsCurrent;
    if (current) {
      return WordComparisonDocument(
        document: _c.document,
        name: widget.documentName,
      );
    }
    return original ? _original : _revised;
  }

  Future<void> _compare() async {
    if (_busy || _source(true) == null || _source(false) == null) return;
    _c.commitPendingEdits();
    final original = _source(true)!;
    final revised = _source(false)!;
    final current = _c.document;
    final revision = _c.contentRevision;
    final usesCurrent = _originalIsCurrent || _revisedIsCurrent;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _notice = null;
      _result = null;
    });
    try {
      final result = await compute(
        _compareWordDocuments,
        _WordComparisonRequest(
          original.document,
          revised.document,
          WordComparisonOptions(
            ignoreCase: _ignoreCase,
            ignoreWhitespace: _ignoreWhitespace,
            includeFormatting: _includeFormatting,
            revisionView: _revisionView,
          ),
        ),
      );
      if (!mounted || generation != _generation) return;
      if (usesCurrent &&
          (!identical(current, _c.document) ||
              revision != _c.contentRevision)) {
        setState(
          () => _notice = _s(
            'The current document changed during comparison. Compare again.',
            'تغير المستند الحالي أثناء المقارنة. أعد المقارنة.',
          ),
        );
        return;
      }
      setState(() {
        _result = result;
        _resultOriginalName = original.name;
        _resultRevisedName = revised.name;
        _comparedCurrent = usesCurrent ? current : null;
        _comparedRevision = usesCurrent ? revision : null;
        _comparisonSelection = result.changes.isEmpty
            ? null
            : result.changes.first.id;
      });
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _notice =
              '${_s('Comparison could not finish', 'تعذر إكمال المقارنة')}: $error',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  bool get _stale =>
      _result != null &&
      _comparedCurrent != null &&
      (!identical(_comparedCurrent, _c.document) ||
          _comparedRevision != _c.contentRevision);

  String _reportJson() =>
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'originalName': _resultOriginalName,
        'revisedName': _resultRevisedName,
        'comparison': _result!.toJson(),
      });

  Future<void> _export({required bool copy}) async {
    if (_result == null || _busy || _stale) return;
    setState(() => _busy = true);
    try {
      final json = _reportJson();
      var saved = true;
      if (copy) {
        await Clipboard.setData(ClipboardData(text: json));
      } else {
        saved = await widget.onExportReport!('document-comparison.json', json);
      }
      if (mounted && saved) {
        setState(
          () => _notice = copy
              ? _s(
                  'Comparison report copied as JSON.',
                  'تم نسخ تقرير المقارنة بصيغة JSON.',
                )
              : _s('Comparison report exported.', 'تم تصدير تقرير المقارنة.'),
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _notice = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Directionality(
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 1180,
          height: math.max(240, math.min(860, size.height - 32)),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _s('Document review', 'مراجعة المستند'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('review-close'),
                        tooltip: _s('Close', 'إغلاق'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      ChoiceChip(
                        key: const ValueKey('review-changes-tab'),
                        label: Text(
                          _s('Tracked changes', 'التغييرات المتعقبة'),
                        ),
                        selected: _tab == WordReviewTab.changes,
                        onSelected: (_) => setState(() {
                          _tab = WordReviewTab.changes;
                          _notice = null;
                        }),
                      ),
                      ChoiceChip(
                        key: const ValueKey('review-compare-tab'),
                        label: Text(
                          _s('Compare documents', 'مقارنة المستندات'),
                        ),
                        selected: _tab == WordReviewTab.compare,
                        onSelected: (_) => setState(() {
                          _tab = WordReviewTab.compare;
                          _notice = null;
                        }),
                      ),
                    ],
                  ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _notice!,
                          key: const ValueKey('review-notice'),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final body = _tab == WordReviewTab.changes
                            ? _changesBody()
                            : _compareBody();
                        // Keep all controls reachable when mobile wraps or a
                        // keyboard leaves too little space for the review panes.
                        if (constraints.maxWidth < 680 ||
                            constraints.maxHeight < 580) {
                          return SingleChildScrollView(
                            key: const ValueKey('review-compact-scroll'),
                            child: SizedBox(
                              height: math.max(
                                constraints.maxHeight,
                                _tab == WordReviewTab.compare ? 1120 : 900,
                              ),
                              child: body,
                            ),
                          );
                        }
                        return body;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _changesBody() {
    final pending = _pending;
    final visible = _filteredChanges(pending);
    final selected = visible.contains(_selected)
        ? _selected
        : (visible.isEmpty ? null : visible.first);
    final authors = <String>{
      ...pending.map((revision) => revision.author),
      ?_authorFilter,
    }.toList()..sort();
    final editable = _c.config.allowsMutation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Switch(
                  key: const ValueKey('review-track'),
                  value: _c.document.trackRevisions,
                  onChanged: editable ? _c.setTrackRevisions : null,
                ),
                Flexible(
                  child: Text(_s('Track text changes', 'تعقب تغييرات النص')),
                ),
              ],
            ),
            SizedBox(
              width: 210,
              child: TextField(
                key: const ValueKey('review-author'),
                controller: _author,
                enabled: editable,
                decoration: InputDecoration(
                  labelText: _s('Reviewer name', 'اسم المراجع'),
                  isDense: true,
                ),
                onSubmitted: (_) => _setAuthor(),
              ),
            ),
            TextButton(
              key: const ValueKey('review-set-author'),
              onPressed: editable ? _setAuthor : null,
              child: Text(_s('Set author', 'تعيين الاسم')),
            ),
            TextButton.icon(
              key: const ValueKey('review-undo'),
              onPressed: editable && _c.canUndo ? _c.undo : null,
              icon: const Icon(Icons.undo),
              label: Text(_s('Undo', 'تراجع')),
            ),
            TextButton.icon(
              key: const ValueKey('review-redo'),
              onPressed: editable && _c.canRedo ? _c.redo : null,
              icon: const Icon(Icons.redo),
              label: Text(_s('Redo', 'إعادة')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 220,
              child: TextField(
                key: const ValueKey('review-search'),
                controller: _search,
                decoration: InputDecoration(
                  labelText: _s('Search changes', 'بحث في التغييرات'),
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() {
                  _query = value;
                  _selected = null;
                }),
              ),
            ),
            _reviewDropdown<String?>(
              key: const ValueKey('review-author-filter'),
              value: authors.contains(_authorFilter) ? _authorFilter : null,
              hint: Text(_s('All authors', 'كل المراجعين')),
              items: <DropdownMenuItem<String?>>[
                DropdownMenuItem(
                  value: null,
                  child: Text(_s('All authors', 'كل المراجعين')),
                ),
                for (final author in authors)
                  DropdownMenuItem(
                    value: author,
                    child: Text(
                      author.isEmpty
                          ? _s('Unknown author', 'مراجع غير معروف')
                          : author,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _authorFilter = value;
                _selected = null;
              }),
            ),
            _reviewDropdown<WmlRevisionKind?>(
              key: const ValueKey('review-kind-filter'),
              value: _kindFilter,
              hint: Text(_s('All change types', 'كل أنواع التغييرات')),
              items: <DropdownMenuItem<WmlRevisionKind?>>[
                DropdownMenuItem(
                  value: null,
                  child: Text(_s('All change types', 'كل أنواع التغييرات')),
                ),
                DropdownMenuItem(
                  value: WmlRevisionKind.insert,
                  child: Text(_s('Insertions', 'إدراج')),
                ),
                DropdownMenuItem(
                  value: WmlRevisionKind.delete,
                  child: Text(_s('Deletions', 'حذف')),
                ),
              ],
              onChanged: (value) => setState(() {
                _kindFilter = value;
                _selected = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              _s(
                '${visible.length} of ${pending.length} pending',
                '${visible.length} من ${pending.length} قيد المراجعة',
              ),
            ),
            IconButton(
              key: const ValueKey('review-previous'),
              tooltip: _s('Previous shown change', 'التغيير السابق'),
              onPressed: visible.isEmpty
                  ? null
                  : () => _step(visible, selected, -1),
              icon: const Icon(Icons.arrow_upward, size: 18),
            ),
            IconButton(
              key: const ValueKey('review-next'),
              tooltip: _s('Next shown change', 'التغيير التالي'),
              onPressed: visible.isEmpty
                  ? null
                  : () => _step(visible, selected, 1),
              icon: const Icon(Icons.arrow_downward, size: 18),
            ),
            TextButton(
              key: const ValueKey('review-accept-shown'),
              onPressed: editable && visible.isNotEmpty
                  ? () => _act(() => _c.acceptRevisions(visible))
                  : null,
              child: Text(
                _s(
                  'Accept ${visible.length} shown',
                  'قبول ${visible.length} المعروضة',
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('review-reject-shown'),
              onPressed: editable && visible.isNotEmpty
                  ? () => _act(() => _c.rejectRevisions(visible))
                  : null,
              child: Text(
                _s(
                  'Reject ${visible.length} shown',
                  'رفض ${visible.length} المعروضة',
                ),
              ),
            ),
          ],
        ),
        const Divider(),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    pending.isEmpty
                        ? _s(
                            'No pending tracked changes.',
                            'لا توجد تغييرات متعقبة قيد المراجعة.',
                          )
                        : _s(
                            'No changes match these filters.',
                            'لا توجد تغييرات تطابق عوامل التصفية.',
                          ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final list = ListView.builder(
                      key: const ValueKey('review-change-list'),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final revision = visible[index];
                        return ListTile(
                          key: ValueKey('review-change-${revision.id}'),
                          selected: identical(selected, revision),
                          leading: Icon(
                            revision.kind == WmlRevisionKind.insert
                                ? Icons.add
                                : Icons.remove,
                            color: revision.kind == WmlRevisionKind.insert
                                ? _insertColor(context)
                                : _deleteColor(context),
                          ),
                          title: Text(
                            '${revision.kind == WmlRevisionKind.insert ? _s('Inserted', 'إدراج') : _s('Deleted', 'حذف')} · ${revision.author}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            revision.text.isEmpty
                                ? _s('(empty text)', '(نص فارغ)')
                                : revision.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: revision.conflict == null
                              ? null
                              : const Icon(Icons.warning_amber),
                          onTap: () => _select(revision),
                        );
                      },
                    );
                    final detail = _changeDetail(
                      selected!,
                      _reviewTargets(pending),
                    );
                    if (constraints.maxWidth < 680) {
                      return Column(
                        children: <Widget>[
                          Expanded(flex: 2, child: list),
                          const Divider(),
                          Expanded(flex: 3, child: detail),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(
                          width: math.min(340, constraints.maxWidth * .4),
                          child: list,
                        ),
                        const VerticalDivider(),
                        Expanded(child: detail),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _changeDetail(
    WmlRevision revision,
    Map<WmlRevision, WmlParagraph?> targets,
  ) {
    final paragraph = WordRevisions.resolveParagraph(_c.document, revision);
    targets[revision] = paragraph;
    String? problem;
    try {
      WordRevisions.validateRevision(_c.document, revision, resolved: targets);
    } on Object catch (error) {
      problem = '$error';
    }
    final editable = _c.config.allowsMutation && problem == null;
    return SingleChildScrollView(
      key: const ValueKey('review-change-detail'),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${revision.author} · ${_dateLabel(revision.dateIso)}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(
            _s(
              'Change ${revision.id} · ${revision.kind.name}',
              'التغيير ${revision.id} · ${revision.kind == WmlRevisionKind.insert ? 'إدراج' : 'حذف'}',
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            revision.text,
            key: const ValueKey('review-selected-text'),
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                problem,
                key: const ValueKey('review-conflict'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                key: const ValueKey('review-accept'),
                onPressed: editable
                    ? () => _act(() => _c.acceptRevision(revision))
                    : null,
                child: Text(_s('Accept change', 'قبول التغيير')),
              ),
              OutlinedButton(
                key: const ValueKey('review-reject'),
                onPressed: editable
                    ? () => _act(() => _c.rejectRevision(revision))
                    : null,
                child: Text(_s('Reject change', 'رفض التغيير')),
              ),
              TextButton(
                key: const ValueKey('review-reveal'),
                onPressed: _c.config.allowsSelection && problem == null
                    ? () => _showInDocument(revision)
                    : null,
                child: Text(_s('Show in document', 'عرض في المستند')),
              ),
            ],
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                _s('Paragraph preview', 'معاينة الفقرة'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              _reviewDropdown<WordComparisonRevisionView>(
                key: const ValueKey('review-preview-mode'),
                value: _preview,
                items: [
                  for (final value in WordComparisonRevisionView.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_viewLabel(value)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _preview = value);
                },
              ),
            ],
          ),
          if (paragraph != null) _paragraphPreview(paragraph, targets),
          const SizedBox(height: 12),
          Text(
            _s(
              'Preview only. Changing this view does not accept or reject changes.',
              'هذه معاينة فقط. تغيير العرض لا يقبل التغييرات أو يرفضها.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _paragraphPreview(
    WmlParagraph paragraph,
    Map<WmlRevision, WmlParagraph?> targets,
  ) {
    final revisions =
        targets.entries
            .where((entry) => identical(entry.value, paragraph))
            .map((entry) => entry.key)
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final text = paragraph.text;
    final spans = <TextSpan>[];
    var at = 0;
    for (final revision in revisions) {
      if (revision.conflict != null ||
          revision.start < at ||
          revision.end < revision.start ||
          revision.end > text.length ||
          text.substring(revision.start, revision.end) != revision.text) {
        return SelectableText(text, key: const ValueKey('review-preview-text'));
      }
      if (revision.start > at) {
        spans.add(TextSpan(text: text.substring(at, revision.start)));
      }
      final inserted = revision.kind == WmlRevisionKind.insert;
      final show =
          _preview == WordComparisonRevisionView.markup ||
          (_preview == WordComparisonRevisionView.finalText && inserted) ||
          (_preview == WordComparisonRevisionView.originalText && !inserted);
      if (show) {
        spans.add(
          TextSpan(
            text: revision.text,
            style: _preview == WordComparisonRevisionView.markup
                ? TextStyle(
                    color: inserted
                        ? _insertColor(context)
                        : _deleteColor(context),
                    decoration: inserted
                        ? TextDecoration.underline
                        : TextDecoration.lineThrough,
                  )
                : null,
          ),
        );
      }
      at = revision.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return SelectableText.rich(
      TextSpan(children: spans),
      key: const ValueKey('review-preview-text'),
    );
  }

  String _dateLabel(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) {
      return value.isEmpty
          ? _s('Date unavailable', 'التاريخ غير متوفر')
          : value;
    }
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _viewLabel(WordComparisonRevisionView view) => switch (view) {
    WordComparisonRevisionView.finalText => _s('Final text', 'النص النهائي'),
    WordComparisonRevisionView.originalText => _s(
      'Original text',
      'النص الأصلي',
    ),
    WordComparisonRevisionView.markup => _s(
      'All markup text',
      'كل النص مع التغييرات',
    ),
  };

  Widget _sourceCard(bool original) {
    final current = original ? _originalIsCurrent : _revisedIsCurrent;
    final source = _source(original);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              original
                  ? _s('Original', 'الأصل')
                  : _s('Revised', 'النسخة المعدلة'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              source?.name ?? _s('Choose a document', 'اختر مستنداً'),
              key: ValueKey(
                original ? 'compare-original-name' : 'compare-revised-name',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (current)
              Text(
                _s('Current editor document', 'المستند الحالي في المحرر'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton.icon(
                  key: ValueKey(
                    original ? 'compare-pick-original' : 'compare-pick-revised',
                  ),
                  onPressed: _busy || widget.pickDocument == null
                      ? null
                      : () => _pick(original),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(_s('Choose file', 'اختيار ملف')),
                ),
                TextButton(
                  key: ValueKey(
                    original
                        ? 'compare-current-original'
                        : 'compare-current-revised',
                  ),
                  onPressed: _busy || current
                      ? null
                      : () => setState(() {
                          if (original) {
                            _originalIsCurrent = true;
                          } else {
                            _revisedIsCurrent = true;
                          }
                          _invalidateComparison();
                        }),
                  child: Text(_s('Use current', 'استخدام الحالي')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _compareBody() {
    final result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: _sourceCard(true)),
                  Expanded(child: _sourceCard(false)),
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: _sourceCard(true)),
                IconButton(
                  key: const ValueKey('compare-swap'),
                  tooltip: _s('Swap documents', 'تبديل المستندين'),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          final source = _original;
                          _original = _revised;
                          _revised = source;
                          final current = _originalIsCurrent;
                          _originalIsCurrent = _revisedIsCurrent;
                          _revisedIsCurrent = current;
                          _invalidateComparison();
                        }),
                  icon: const Icon(Icons.swap_horiz),
                ),
                Expanded(child: _sourceCard(false)),
              ],
            );
          },
        ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilterChip(
              key: const ValueKey('compare-ignore-case'),
              label: Text(_s('Ignore case', 'تجاهل حالة الأحرف')),
              selected: _ignoreCase,
              onSelected: _busy
                  ? null
                  : (value) => setState(() {
                      _ignoreCase = value;
                      _invalidateComparison();
                    }),
            ),
            FilterChip(
              key: const ValueKey('compare-ignore-whitespace'),
              label: Text(_s('Ignore whitespace', 'تجاهل المسافات')),
              selected: _ignoreWhitespace,
              onSelected: _busy
                  ? null
                  : (value) => setState(() {
                      _ignoreWhitespace = value;
                      _invalidateComparison();
                    }),
            ),
            FilterChip(
              key: const ValueKey('compare-formatting'),
              label: Text(_s('Compare formatting', 'مقارنة التنسيق')),
              selected: _includeFormatting,
              onSelected: _busy
                  ? null
                  : (value) => setState(() {
                      _includeFormatting = value;
                      _invalidateComparison();
                    }),
            ),
            _reviewDropdown<WordComparisonRevisionView>(
              key: const ValueKey('compare-revision-view'),
              value: _revisionView,
              items: [
                for (final value in WordComparisonRevisionView.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_viewLabel(value)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _revisionView = value;
                          _invalidateComparison();
                        });
                      }
                    },
            ),
            FilledButton.icon(
              key: const ValueKey('compare-run'),
              onPressed:
                  _busy || _source(true) == null || _source(false) == null
                  ? null
                  : _compare,
              icon: const Icon(Icons.compare_arrows),
              label: Text(_s('Compare', 'مقارنة')),
            ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        if (_stale)
          Text(
            _s(
              'This report is out of date. Compare again before exporting.',
              'هذا التقرير قديم. أعد المقارنة قبل التصدير.',
            ),
            key: const ValueKey('compare-stale'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (result == null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _s(
                    'Choose an original and a revised document, then compare. Both documents stay unchanged. Final text hides pending deletions; original text hides pending insertions.',
                    'اختر المستند الأصلي والنسخة المعدلة ثم قارن. يبقى المستندان دون تغيير. النص النهائي يخفي الحذف المعلق، والنص الأصلي يخفي الإدراج المعلق.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else ...<Widget>[
          const Divider(),
          Expanded(child: _comparisonResults(result)),
        ],
      ],
    );
  }

  List<WordComparisonEntry> _filteredEntries(WordComparisonResult result) {
    final query = _comparisonQuery.trim().toLowerCase();
    return result.entries
        .where(
          (entry) =>
              (!_changesOnly || entry.isChange) &&
              (_comparisonKind == null || entry.kind == _comparisonKind) &&
              (query.isEmpty ||
                  '${entry.originalText}\n${entry.revisedText}\n${entry.label}'
                      .toLowerCase()
                      .contains(query)),
        )
        .toList();
  }

  Widget _comparisonResults(WordComparisonResult result) {
    final entries = _filteredEntries(result);
    final selected = entries
        .where((entry) => entry.id == _comparisonSelection)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _s(
            '${result.changeCount} changes · ${result.insertedCount} insertions · ${result.deletedCount} deletions · ${result.modifiedCount} edits · ${result.formattingCount} formatting · ${result.structureCount} structure',
            '${result.changeCount} تغييرات · ${result.insertedCount} إدراج · ${result.deletedCount} حذف · ${result.modifiedCount} تعديل · ${result.formattingCount} تنسيق · ${result.structureCount} بنية',
          ),
          key: const ValueKey('compare-summary'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (result.warnings.isNotEmpty)
          ExpansionTile(
            key: const ValueKey('compare-warnings'),
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              _s(
                'Comparison scope and notices (${result.warnings.length})',
                'نطاق المقارنة والملاحظات (${result.warnings.length})',
              ),
            ),
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final warning in result.warnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            warning,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            ChoiceChip(
              key: const ValueKey('compare-side-by-side'),
              label: Text(_s('Side by side', 'جنباً إلى جنب')),
              selected: !_inline,
              onSelected: (_) => setState(() => _inline = false),
            ),
            ChoiceChip(
              key: const ValueKey('compare-inline'),
              label: Text(_s('Inline markup', 'علامات التغيير')),
              selected: _inline,
              onSelected: (_) => setState(() => _inline = true),
            ),
            FilterChip(
              key: const ValueKey('compare-changes-only'),
              label: Text(_s('Changes only', 'التغييرات فقط')),
              selected: _changesOnly,
              onSelected: (value) => setState(() => _changesOnly = value),
            ),
            TextButton(
              key: const ValueKey('compare-copy-report'),
              onPressed: _busy || _stale ? null : () => _export(copy: true),
              child: Text(_s('Copy JSON report', 'نسخ تقرير JSON')),
            ),
            if (widget.onExportReport != null)
              TextButton(
                key: const ValueKey('compare-export-report'),
                onPressed: _busy || _stale ? null : () => _export(copy: false),
                child: Text(_s('Export report', 'تصدير التقرير')),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 200,
              child: TextField(
                key: const ValueKey('compare-search'),
                controller: _comparisonSearch,
                decoration: InputDecoration(
                  labelText: _s('Search comparison', 'بحث في المقارنة'),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _comparisonQuery = value),
              ),
            ),
            _reviewDropdown<WordComparisonKind?>(
              key: const ValueKey('compare-kind-filter'),
              value: _comparisonKind,
              hint: Text(_s('All differences', 'كل الاختلافات')),
              items: [
                DropdownMenuItem<WordComparisonKind?>(
                  value: null,
                  child: Text(_s('All differences', 'كل الاختلافات')),
                ),
                for (final kind in WordComparisonKind.values)
                  DropdownMenuItem(value: kind, child: Text(_kindLabel(kind))),
              ],
              onChanged: (value) => setState(() => _comparisonKind = value),
            ),
            IconButton(
              key: const ValueKey('compare-previous'),
              tooltip: _s('Previous difference', 'الاختلاف السابق'),
              onPressed: entries.isEmpty
                  ? null
                  : () => _stepComparison(entries, selected, -1),
              icon: const Icon(Icons.arrow_upward, size: 18),
            ),
            IconButton(
              key: const ValueKey('compare-next'),
              tooltip: _s('Next difference', 'الاختلاف التالي'),
              onPressed: entries.isEmpty
                  ? null
                  : () => _stepComparison(entries, selected, 1),
              icon: const Icon(Icons.arrow_downward, size: 18),
            ),
            Text(_s('${entries.length} shown', '${entries.length} معروضة')),
            if (_focusDifference && selected != null)
              TextButton(
                key: const ValueKey('compare-show-all'),
                onPressed: () => setState(() => _focusDifference = false),
                child: Text(_s('Show all differences', 'عرض كل الاختلافات')),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    result.hasChanges
                        ? _s(
                            'No differences match these filters.',
                            'لا توجد اختلافات تطابق عوامل التصفية.',
                          )
                        : _s(
                            'No differences in the compared content with these options.',
                            'لا توجد اختلافات في المحتوى المقارن بهذه الخيارات.',
                          ),
                  ),
                )
              : _focusDifference && selected != null
              ? SingleChildScrollView(
                  key: const ValueKey('compare-focused-result'),
                  child: _comparisonEntry(selected),
                )
              : ListView.builder(
                  key: const ValueKey('compare-results'),
                  controller: _comparisonScroll,
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _comparisonEntry(entries[index]),
                ),
        ),
      ],
    );
  }

  void _stepComparison(
    List<WordComparisonEntry> entries,
    WordComparisonEntry? selected,
    int delta,
  ) {
    final index = selected == null ? -1 : entries.indexOf(selected);
    final next = index < 0
        ? (delta < 0 ? entries.length - 1 : 0)
        : (index + delta) % entries.length;
    setState(() {
      _comparisonSelection = entries[next].id;
      _focusDifference = true;
    });
  }

  Widget _comparisonEntry(WordComparisonEntry entry) {
    final selected = entry.id == _comparisonSelection;
    return Card.outlined(
      key: ValueKey('compare-entry-${entry.id}'),
      color: selected
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: .25)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${_kindLabel(entry.kind)} · ${entry.label}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (entry.originalLocation?.label != entry.revisedLocation?.label &&
                entry.originalLocation != null &&
                entry.revisedLocation != null)
              Text(
                '${entry.originalLocation!.label} → ${entry.revisedLocation!.label}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            if (_inline)
              _inlineEntry(entry)
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final left = _comparisonText(entry, original: true);
                  final right = _comparisonText(entry, original: false);
                  if (constraints.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        left,
                        const SizedBox(height: 10),
                        right,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: left),
                      const SizedBox(width: 16),
                      Expanded(child: right),
                    ],
                  );
                },
              ),
            if (entry.formattingChanges.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(entry.formattingChanges.join(' · ')),
              ),
            for (final detail in entry.details)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _comparisonText(WordComparisonEntry entry, {required bool original}) {
    final spans = <TextSpan>[];
    for (final span in entry.spans) {
      if (original && span.kind == WordComparisonSpanKind.insert ||
          !original && span.kind == WordComparisonSpanKind.delete) {
        continue;
      }
      final changed = span.kind != WordComparisonSpanKind.equal;
      spans.add(
        TextSpan(
          text: original ? span.originalText : span.text,
          style: changed
              ? TextStyle(
                  backgroundColor:
                      (original ? _deleteColor(context) : _insertColor(context))
                          .withValues(alpha: .12),
                  decoration: original
                      ? TextDecoration.lineThrough
                      : TextDecoration.underline,
                )
              : null,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          original ? _s('Original', 'الأصل') : _s('Revised', 'النسخة المعدلة'),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 4),
        if (spans.isEmpty)
          SelectableText(
            (original ? entry.originalText : entry.revisedText).isEmpty
                ? '∅'
                : (original ? entry.originalText : entry.revisedText),
          )
        else
          SelectableText.rich(TextSpan(children: spans)),
      ],
    );
  }

  Widget _inlineEntry(WordComparisonEntry entry) {
    if (entry.spans.isEmpty) {
      return SelectableText(
        entry.revisedText.isEmpty ? entry.originalText : entry.revisedText,
      );
    }
    return SelectableText.rich(
      TextSpan(
        children: <TextSpan>[
          for (final span in entry.spans)
            TextSpan(
              text: span.text,
              style: switch (span.kind) {
                WordComparisonSpanKind.equal => null,
                WordComparisonSpanKind.insert => TextStyle(
                  color: _insertColor(context),
                  backgroundColor: _insertColor(context).withValues(alpha: .1),
                  decoration: TextDecoration.underline,
                ),
                WordComparisonSpanKind.delete => TextStyle(
                  color: _deleteColor(context),
                  backgroundColor: _deleteColor(context).withValues(alpha: .1),
                  decoration: TextDecoration.lineThrough,
                ),
              },
            ),
        ],
      ),
    );
  }

  String _kindLabel(WordComparisonKind kind) => switch (kind) {
    WordComparisonKind.unchanged => _s('Unchanged', 'دون تغيير'),
    WordComparisonKind.inserted => _s('Inserted', 'إدراج'),
    WordComparisonKind.deleted => _s('Deleted', 'حذف'),
    WordComparisonKind.modified => _s('Modified', 'تعديل'),
    WordComparisonKind.formatting => _s('Formatting', 'تنسيق'),
    WordComparisonKind.structure => _s('Structure', 'بنية'),
  };
}

Color _insertColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xff81d4a5)
    : const Color(0xff146c43);
Color _deleteColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xffffa4a8)
    : const Color(0xffb3261e);

class _WordComparisonRequest {
  const _WordComparisonRequest(this.original, this.revised, this.options);
  final WmlDocument original;
  final WmlDocument revised;
  final WordComparisonOptions options;
}

WordComparisonResult _compareWordDocuments(_WordComparisonRequest request) =>
    WordDocumentComparison.compare(
      request.original,
      request.revised,
      options: request.options,
    );

Widget _reviewDropdown<T>({
  Key? key,
  required T? value,
  Widget? hint,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?>? onChanged,
}) => SizedBox(
  width: 200,
  child: DropdownButton<T>(
    key: key,
    value: value,
    hint: hint,
    isExpanded: true,
    items: items,
    onChanged: onChanged,
  ),
);
