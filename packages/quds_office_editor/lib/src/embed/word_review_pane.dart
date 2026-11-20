import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../proofing/word_proofing.dart';
import 'office_controller.dart';
import 'word_review_labels.dart';

/// Non-modal writing and tracked-change review beside the document canvas.
///
/// The controller owns the proofing session and all document edits. Opening
/// this pane never runs optional manual providers; only Check document does.
/// Hosts can retain the advanced dialogs through [onMoreOptions].
class WordReviewPane extends StatefulWidget {
  const WordReviewPane({
    super.key,
    required this.controller,
    this.initialTab = WordReviewPaneTab.proofing,
    this.onClose,
    this.onMoreOptions,
    this.onTabChanged,
  });

  final WordEditorController controller;
  final WordReviewPaneTab initialTab;
  final VoidCallback? onClose;
  final VoidCallback? onMoreOptions;
  final ValueChanged<WordReviewPaneTab>? onTabChanged;

  @override
  State<WordReviewPane> createState() => _WordReviewPaneState();
}

enum _ProofingFilter { all, spelling, grammar, style }

class _WordReviewPaneState extends State<WordReviewPane> {
  static const Map<String, String> _languages = <String, String>{
    'de-DE': 'Deutsch (Deutschland)',
    'de-AT': 'Deutsch (Österreich)',
    'de-CH': 'Deutsch (Schweiz)',
    'en-US': 'English (United States)',
    'en-GB': 'English (United Kingdom)',
    'en-CA': 'English (Canada)',
    'en-AU': 'English (Australia)',
    'en-IN': 'English (India)',
  };

  /// English and Arabic names of the primary languages the detector and
  /// the per-script summary name most often.
  static const Map<String, (String, String)> _languageNames = {
    'ar': ('Arabic', 'العربية'),
    'de': ('German', 'الألمانية'),
    'el': ('Greek', 'اليونانية'),
    'en': ('English', 'الإنجليزية'),
    'es': ('Spanish', 'الإسبانية'),
    'fa': ('Persian', 'الفارسية'),
    'fr': ('French', 'الفرنسية'),
    'he': ('Hebrew', 'العبرية'),
    'it': ('Italian', 'الإيطالية'),
    'ku': ('Kurdish', 'الكردية'),
    'la': ('Latin', 'اللاتينية'),
    'nl': ('Dutch', 'الهولندية'),
    'pl': ('Polish', 'البولندية'),
    'ps': ('Pashto', 'البشتوية'),
    'pt': ('Portuguese', 'البرتغالية'),
    'ru': ('Russian', 'الروسية'),
    'sd': ('Sindhi', 'السندية'),
    'tr': ('Turkish', 'التركية'),
    'ug': ('Uyghur', 'الأويغورية'),
    'uk': ('Ukrainian', 'الأوكرانية'),
    'ur': ('Urdu', 'الأردية'),
    'yi': ('Yiddish', 'اليديشية'),
  };

  String _languageName(String? tag) {
    if (tag == null) return _s('several languages', 'عدة لغات');
    final name = _languageNames[primaryLanguageSubtag(tag)];
    return name == null ? tag : _s(name.$1, name.$2);
  }

  String _scriptLabel(TextScript script) => switch (script) {
    TextScript.latin => _s('Latin text', 'النص اللاتيني'),
    TextScript.arabic => _s('Arabic text', 'النص العربي'),
    TextScript.hebrew => _s('Hebrew text', 'النص العبري'),
    TextScript.cyrillic => _s('Cyrillic text', 'النص السيريلي'),
    TextScript.greek => _s('Greek text', 'النص اليوناني'),
    TextScript.other => _s('Other text', 'نص آخر'),
  };

  /// "Latin text: German · Arabic text: Arabic".
  String _scriptSummary(Map<TextScript, String?> languages) => [
    for (final entry in languages.entries)
      '${_scriptLabel(entry.key)}: ${_languageName(entry.value)}',
  ].join(' · ');

  WordTextProofingTarget? _detectionRequested;

  late WordReviewPaneTab _tab;
  late final TextEditingController _author;
  final TextEditingController _changeSearch = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _keyboardFocus = FocusNode(
    debugLabel: 'word-review-navigation',
    skipTraversal: true,
  );
  _ProofingFilter _filter = _ProofingFilter.all;
  String? _changeAuthor;
  WmlRevisionKind? _changeKind;
  String _changeQuery = '';
  WordComparisonRevisionView _preview = WordComparisonRevisionView.markup;
  String? _notice;
  bool _textOptionsWereVisible = false;
  int _textOptionsRequest = -1;

  WordEditorController get _c => widget.controller;
  bool get _arabic => _c.config.textDirection == TextDirection.rtl;
  String _s(String english, String arabic) => _arabic ? arabic : english;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _author = TextEditingController(text: _c.revisionAuthor);
    _textOptionsWereVisible = _c.reviewTextProofingOptionsVisible;
    _scheduleInitialCheck();
  }

  @override
  void didUpdateWidget(WordReviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, _c)) {
      _author.text = _c.revisionAuthor;
      _filter = _ProofingFilter.all;
      _changeSearch.clear();
      _changeAuthor = null;
      _changeKind = null;
      _changeQuery = '';
      _preview = WordComparisonRevisionView.markup;
      _notice = null;
      _textOptionsWereVisible = false;
      _textOptionsRequest = -1;
      _scheduleInitialCheck();
    }
    if (oldWidget.initialTab != widget.initialTab) {
      _tab = widget.initialTab;
      _notice = null;
      _scheduleInitialCheck();
    }
  }

  @override
  void dispose() {
    _author.dispose();
    _changeSearch.dispose();
    _scroll.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _scheduleInitialCheck() {
    final controller = _c;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(controller, _c) ||
          _tab != WordReviewPaneTab.proofing ||
          controller.proofing.summary.hasResults ||
          controller.proofing.checking) {
        return;
      }
      unawaited(_check(includeManualProviders: false));
    });
  }

  Future<void> _check({required bool includeManualProviders}) async {
    final controller = _c;
    try {
      if (includeManualProviders) {
        await controller.checkDocumentProofing();
      } else {
        await controller.proofing.checkNow(includeManualProviders: false);
      }
    } on Object {
      if (mounted && identical(controller, _c)) {
        setState(() {
          _notice = _s(
            'The document check could not finish. Try Check document again.',
            'تعذر إكمال التدقيق. حاول تدقيق المستند مرة أخرى.',
          );
        });
      }
    }
  }

  void _refreshAfterChoice() {
    // Enabled sessions already scheduled their typing debounce. With checking
    // paused, update the reviewed result without silently running manual tools.
    if (!_c.proofing.enabled) {
      unawaited(_check(includeManualProviders: false));
    }
  }

  void _setTab(WordReviewPaneTab tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _notice = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    widget.onTabChanged?.call(tab);
    if (tab == WordReviewPaneTab.proofing) _scheduleInitialCheck();
  }

  void _selectIssue(WordProofingIssue issue) {
    final revealed = _c.selectProofingIssue(issue);
    setState(() {
      _notice = revealed
          ? null
          : _s(
              'This location cannot be selected on the canvas. Review it here.',
              'لا يمكن تحديد هذا الموضع في الصفحة. يمكنك مراجعته هنا.',
            );
    });
  }

  void _stepWritingFinding(int delta) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (_c.input.composing.isValid && !_c.input.composing.isCollapsed) return;
    _setTab(WordReviewPaneTab.proofing);
    final issues = _c.proofing.summary.issues.where(_matchesFilter).toList();
    if (issues.isEmpty) return;
    final selected = _c.selectedProofingIssue;
    final current = selected == null ? -1 : issues.indexOf(selected);
    final next = current < 0
        ? (delta > 0 ? 0 : issues.length - 1)
        : (current + delta) % issues.length;
    _selectIssue(issues[next]);
    // Revealing text normally focuses the canvas. Keep keyboard review in
    // this pane so the next shortcut still respects its active category filter.
    _keyboardFocus.requestFocus();
  }

  void _apply(WordProofingIssue issue, String replacement) {
    final applied = _c.applyProofingSuggestion(issue, replacement);
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
    _refreshAfterChoice();
  }

  void _ignore(WordProofingIssue issue, VoidCallback operation) {
    if (!_c.proofing.isCurrent(issue)) return;
    operation();
    setState(() => _notice = null);
    _refreshAfterChoice();
  }

  void _changeAction(VoidCallback operation) {
    try {
      operation();
      setState(() => _notice = null);
    } on Object catch (error) {
      setState(() => _notice = '$error');
    }
  }

  void _selectRevision(WmlRevision revision) {
    final revealed = _c.revealRevision(revision);
    setState(() {
      _notice = revealed
          ? null
          : _s(
              'This change cannot be selected on the canvas. Review its details here.',
              'لا يمكن تحديد هذا التغيير في الصفحة. راجع تفاصيله هنا.',
            );
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      final theme = Theme.of(context);
      final textOptionsVisible = _c.reviewTextProofingOptionsVisible;
      final request = _c.textProofingOptionsRequest;
      if (textOptionsVisible &&
          (!_textOptionsWereVisible || _textOptionsRequest != request)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
        });
      }
      _textOptionsWereVisible = textOptionsVisible;
      _textOptionsRequest = request;
      return Directionality(
        textDirection: _c.config.textDirection,
        child: Material(
          key: const ValueKey<String>('word-review-pane'),
          color: theme.colorScheme.surface,
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.f7): () {
                if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
                _setTab(WordReviewPaneTab.proofing);
                unawaited(_check(includeManualProviders: true));
              },
              const SingleActivator(LogicalKeyboardKey.f7, shift: true): () {
                if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
                _c.requestThesaurus();
              },
              const SingleActivator(LogicalKeyboardKey.f7, alt: true): () =>
                  _stepWritingFinding(1),
              const SingleActivator(
                LogicalKeyboardKey.f7,
                alt: true,
                shift: true,
              ): () =>
                  _stepWritingFinding(-1),
              if (widget.onClose != null)
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  if (ModalRoute.of(context)?.isCurrent ?? true) {
                    widget.onClose!();
                  }
                },
            },
            child: Focus(
              focusNode: _keyboardFocus,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 12,
                      end: 4,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _s('Review', 'مراجعة'),
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          key: const ValueKey<String>('live-review-thesaurus'),
                          tooltip: _s(
                            'Thesaurus (Shift+F7)',
                            'قاموس المرادفات (Shift+F7)',
                          ),
                          onPressed: widget.controller.requestThesaurus,
                          icon: const Icon(Icons.menu_book_outlined),
                        ),
                        if (widget.onMoreOptions != null)
                          IconButton(
                            key: const ValueKey<String>('live-review-more'),
                            tooltip: _s(
                              'More review options',
                              'خيارات مراجعة إضافية',
                            ),
                            onPressed: widget.onMoreOptions,
                            icon: const Icon(Icons.more_horiz),
                          ),
                        if (widget.onClose != null)
                          IconButton(
                            key: const ValueKey<String>('live-review-close'),
                            tooltip: _s(
                              'Close review pane',
                              'إغلاق لوحة المراجعة',
                            ),
                            onPressed: widget.onClose,
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: <Widget>[
                        for (final tab in WordReviewPaneTab.values)
                          Expanded(
                            child: TextButton(
                              key: ValueKey<String>(
                                'live-review-${tab.name}-tab',
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: _tab == tab
                                    ? theme.colorScheme.secondaryContainer
                                    : null,
                              ),
                              onPressed: () => _setTab(tab),
                              child: Text(
                                tab == WordReviewPaneTab.proofing
                                    ? _s('Writing', 'الكتابة')
                                    : _s('Changes', 'التغييرات'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 8),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Tooltip(
                          message: _notice!,
                          child: Text(
                            _notice!,
                            key: const ValueKey<String>('live-review-notice'),
                            style: theme.textTheme.bodySmall,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      key: ValueKey<String>('live-review-${_tab.name}-content'),
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      children: <Widget>[
                        if (_tab == WordReviewPaneTab.proofing)
                          ..._proofingContent()
                        else
                          ..._changesContent(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _proofingContent() {
    final session = _c.proofing;
    final summary = session.summary;
    final issues = summary.issues.where(_matchesFilter).toList();
    final controllerSelection = _c.selectedProofingIssue;
    final selected = issues.contains(controllerSelection)
        ? controllerSelection
        : issues.firstOrNull;
    final selectedIndex = selected == null ? -1 : issues.indexOf(selected);
    final actionable = selected != null && session.isCurrent(selected);
    final problems = <String>{
      for (final report in summary.reports)
        for (final result in report.results)
          if (result.status != OfficeProofingStatus.success &&
              result.status != OfficeProofingStatus.unsupported)
            '${result.providerId}: ${result.message ?? result.status.name}',
    };
    return <Widget>[
      if (_c.reviewTextProofingOptionsVisible) _textProofingOptions(),
      if (_c.onManageProofingDownloads != null)
        TextButton.icon(
          key: const ValueKey<String>('proofing-downloads-manager'),
          onPressed: _c.onManageProofingDownloads,
          icon: const Icon(Icons.download_outlined),
          label: Text(_s('Language downloads', 'تنزيلات اللغة')),
        ),
      SwitchListTile.adaptive(
        key: const ValueKey<String>('live-proofing-background'),
        contentPadding: EdgeInsets.zero,
        title: Text(_s('Check as you type', 'تدقيق أثناء الكتابة')),
        value: session.enabled,
        onChanged: (value) => session.enabled = value,
      ),
      if (summary.checking)
        const LinearProgressIndicator(
          key: ValueKey<String>('live-proofing-progress'),
        ),
      const SizedBox(height: 4),
      Semantics(
        liveRegion: true,
        child: Text(
          summary.statusMessage,
          key: const ValueKey<String>('live-proofing-status'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      if (problems.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            problems.join('\n'),
            key: const ValueKey<String>('live-proofing-provider-status'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          OutlinedButton.icon(
            key: const ValueKey<String>('live-proofing-check'),
            onPressed: () => unawaited(_check(includeManualProviders: true)),
            icon: const Icon(Icons.spellcheck, size: 18),
            label: Text(_s('Check document', 'تدقيق المستند')),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _changeDropdown<String>(
        key: const ValueKey<String>('live-proofing-language'),
        label: _s('Document language', 'لغة المستند'),
        value: session.language,
        items: <DropdownMenuItem<String>>[
          for (final entry in _languages.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(
                entry.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (!_languages.containsKey(session.language))
            DropdownMenuItem(
              value: session.language,
              child: Text(session.language),
            ),
        ],
        onChanged: !_c.canApplyProofingSuggestions
            ? null
            : (value) {
                if (value == null) return;
                _c.setProofingLanguage(value);
                _refreshAfterChoice();
              },
      ),
      if (!_c.reviewTextProofingOptionsVisible) _textProofingOptions(),
      const Divider(height: 20),
      DropdownButtonFormField<_ProofingFilter>(
        key: const ValueKey<String>('live-proofing-filter'),
        initialValue: _filter,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _s('Show', 'عرض'),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: <DropdownMenuItem<_ProofingFilter>>[
          for (final filter in _ProofingFilter.values)
            DropdownMenuItem(value: filter, child: Text(_filterLabel(filter))),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _filter = value);
        },
      ),
      const SizedBox(height: 4),
      _navigation(
        label: issues.isEmpty
            ? _s('0 findings', 'لا توجد نتائج')
            : _s(
                '${selectedIndex + 1} of ${issues.length} findings',
                '${selectedIndex + 1} من ${issues.length} نتائج',
              ),
        previousKey: 'live-proofing-previous',
        nextKey: 'live-proofing-next',
        onPrevious: issues.isEmpty
            ? null
            : () => _selectIssue(issues[(selectedIndex - 1) % issues.length]),
        onNext: issues.isEmpty
            ? null
            : () => _selectIssue(issues[(selectedIndex + 1) % issues.length]),
      ),
      if (selected != null) ...<Widget>[
        _issueDetail(selected, actionable),
        if (issues.length > 1)
          ExpansionTile(
            key: const ValueKey<String>('live-proofing-list'),
            tilePadding: EdgeInsets.zero,
            title: Text(_s('All shown findings', 'كل النتائج المعروضة')),
            children: <Widget>[
              for (final issue in issues)
                ListTile(
                  key: ValueKey<String>(
                    'live-proofing-item-${issue.finding.blockId}-${issue.finding.providerId}-${issue.finding.ruleId}-${issue.finding.start}',
                  ),
                  dense: true,
                  selected: identical(issue, selected),
                  title: Text(
                    issue.finding.originalText.isEmpty
                        ? issue.finding.message
                        : issue.finding.originalText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_categoryLabel(issue.finding.category)} · ${issue.story}',
                  ),
                  onTap: () => _selectIssue(issue),
                ),
            ],
          ),
      ] else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            summary.checking
                ? _s(
                    'New results will appear here.',
                    'ستظهر النتائج الجديدة هنا.',
                  )
                : summary.hasResults
                ? summary.issues.isNotEmpty
                      ? _s(
                          'No findings match this filter.',
                          'لا توجد نتائج تطابق هذا المرشح.',
                        )
                      : summary.complete
                      ? _s(
                          'No issues found by the configured providers.',
                          'لم يعثر المدققون المفعّلون على مشكلات.',
                        )
                      : _s(
                          'No findings to display. Check coverage above.',
                          'لا توجد نتائج لعرضها. راجع حالة التدقيق أعلاه.',
                        )
                : _s(
                    'Waiting for the next check.',
                    'في انتظار التدقيق التالي.',
                  ),
            key: const ValueKey<String>('live-proofing-empty'),
          ),
        ),
      if (session.hasIgnoredOccurrences ||
          session.ignoredRuleIds.isNotEmpty ||
          _ignoredWords(session).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              OutlinedButton.icon(
                key: const ValueKey<String>('live-proofing-review-ignored'),
                onPressed: _restoreIgnoredFindings,
                icon: const Icon(Icons.restore, size: 18),
                label: Text(
                  _s(
                    'Review ignored findings again',
                    'مراجعة النتائج المتجاهلة مجدداً',
                  ),
                ),
              ),
              Text(
                _s(
                  'Restore ignored occurrences, words, and rules. Personal dictionary entries stay unchanged.',
                  'استعادة المواضع والكلمات والقواعد المتجاهلة. تبقى كلمات القاموس الشخصي كما هي.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      _historyActions(),
    ];
  }

  Widget _textProofingOptions() {
    final target = _c.textProofingTarget;
    final expanded = _c.reviewTextProofingOptionsVisible;
    final language = target?.language;
    final languageLabel = target == null
        ? _s('Select document text', 'حدد نص المستند')
        : language == null
        ? _s('Mixed languages', 'لغات متعددة')
        : _languages[language] ?? language;
    final scope = target?.isSelection == true
        ? _s('Selected text', 'النص المحدد')
        : _s('Current paragraph', 'الفقرة الحالية');
    final editable = target?.canEdit ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          key: const ValueKey<String>('live-proofing-text-options'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(_s('Language and checking', 'اللغة والتدقيق')),
          subtitle: Text(
            target == null ? languageLabel : '$scope · $languageLabel',
            key: const ValueKey<String>('live-proofing-text-summary'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          onTap: () => _c.setTextProofingOptionsVisible(!expanded),
        ),
        if (expanded) ...<Widget>[
          Text(
            target?.isSelection == true
                ? _s('Applies to the selected text.', 'يُطبّق على النص المحدد.')
                : _s(
                    'Applies to the current paragraph.',
                    'يُطبّق على الفقرة الحالية.',
                  ),
            key: const ValueKey<String>('live-proofing-text-scope'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _changeDropdown<String>(
            key: const ValueKey<String>('live-proofing-text-language'),
            label: target?.isSelection == true
                ? _s('Selected text language', 'لغة النص المحدد')
                : _s('Paragraph language', 'لغة الفقرة'),
            value: language,
            hint: languageLabel,
            items: <DropdownMenuItem<String>>[
              for (final entry in _languages.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (language != null && !_languages.containsKey(language))
                DropdownMenuItem(value: language, child: Text(language)),
            ],
            onChanged: !editable
                ? null
                : (value) {
                    if (value != null) _setTextLanguage(target!, value);
                  },
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey<String>('live-proofing-text-inherit'),
              onPressed: editable
                  ? () => _setTextLanguage(target!, null)
                  : null,
              child: Text(
                _s('Use inherited language', 'استخدام اللغة الموروثة'),
              ),
            ),
          ),
          ..._detectedLanguageOptions(target, editable),
          CheckboxListTile(
            key: const ValueKey<String>('live-proofing-text-enabled'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            tristate: true,
            value: target?.checkingEnabled,
            title: Text(_s('Check this text', 'تدقيق هذا النص')),
            subtitle: Text(
              target?.checkingEnabled == null && target != null
                  ? _s(
                      'Mixed checking settings. Turn on to check all selected text.',
                      'إعدادات تدقيق مختلطة. فعّل لتدقيق كل النص المحدد.',
                    )
                  : _s(
                      'Spelling, grammar, and writing suggestions',
                      'الإملاء والقواعد واقتراحات الكتابة',
                    ),
            ),
            onChanged: !editable
                ? null
                : (_) =>
                      _setTextChecking(target!, target.checkingEnabled != true),
          ),
          if (target == null || !editable)
            Text(
              target?.unavailableReason ??
                  _s(
                    'Select editable document text to change these settings.',
                    'حدد نصاً قابلاً للتحرير لتغيير هذه الإعدادات.',
                  ),
              key: const ValueKey<String>('live-proofing-text-unavailable'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  List<Widget> _detectedLanguageOptions(
    WordTextProofingTarget? target,
    bool editable,
  ) {
    if (target == null || target.scriptLanguages.isEmpty) return const [];
    if (target.detectionPending && !identical(_detectionRequested, target)) {
      _detectionRequested = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_c.detectTextProofingLanguages(target));
      });
    }
    final detected = target.detectedLanguages;
    final differs = target.canApplyDetectedLanguages;
    return <Widget>[
      Text(
        _scriptSummary(target.scriptLanguages),
        key: const ValueKey<String>('live-proofing-text-scripts'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (detected.isNotEmpty)
        Text(
          '${_s('Detected', 'المكتشفة')}: ${_scriptSummary(detected)}',
          key: const ValueKey<String>('live-proofing-text-detected'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      if (detected.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: const ValueKey<String>('live-proofing-apply-detected'),
            onPressed: editable && differs
                ? () => _applyDetectedLanguages(target)
                : null,
            child: Text(_s('Apply detected language', 'تطبيق اللغة المكتشفة')),
          ),
        ),
    ];
  }

  void _applyDetectedLanguages(WordTextProofingTarget target) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final revision = _c.contentRevision;
    _afterTextProofingChange(
      _c.applyDetectedTextProofingLanguages(target: target),
      changedFrom: revision,
    );
  }

  void _setTextLanguage(WordTextProofingTarget target, String? language) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final revision = _c.contentRevision;
    _afterTextProofingChange(
      _c.setTextProofingLanguage(language, target: target),
      changedFrom: revision,
    );
  }

  void _setTextChecking(WordTextProofingTarget target, bool enabled) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final revision = _c.contentRevision;
    _afterTextProofingChange(
      _c.setTextProofingEnabled(enabled, target: target),
      changedFrom: revision,
    );
  }

  void _afterTextProofingChange(bool applied, {required int changedFrom}) {
    final changed = _c.contentRevision != changedFrom;
    setState(() {
      _notice = applied
          ? changed
                ? _s(
                    'Text checking settings updated. Undo is available.',
                    'تم تحديث إعدادات تدقيق النص. يمكنك التراجع.',
                  )
                : _s(
                    'Text checking settings are already up to date.',
                    'إعدادات تدقيق النص محدّثة بالفعل.',
                  )
          : _s(
              'The text or selection changed, or editing is unavailable. Choose the text again.',
              'تغير النص أو التحديد، أو أن التحرير غير متاح. حدد النص مجدداً.',
            );
    });
    if (applied && changed) _refreshAfterChoice();
  }

  List<({String language, String word})> _ignoredWords(
    WordProofingSession session,
  ) {
    final ignored =
        session.vocabulary.toJson()['ignoredWords']! as Map<String, Object?>;
    return <({String language, String word})>[
      for (final entry in ignored.entries)
        for (final word in entry.value! as List<String>)
          (language: entry.key, word: word),
    ];
  }

  void _restoreIgnoredFindings() {
    final session = _c.proofing;
    final words = _ignoredWords(session);
    final rules = session.ignoredRuleIds.toList();
    session.clearIgnoredOnce();
    for (final entry in words) {
      session.unignoreWord(entry.word, language: entry.language);
    }
    for (final rule in rules) {
      session.restoreRule(rule);
    }
    setState(() => _notice = null);
    _refreshAfterChoice();
  }

  Widget _issueDetail(WordProofingIssue issue, bool current) {
    final finding = issue.finding;
    final canApply = current && _c.canApplyProofingIssue(issue);
    final spelling =
        finding.category == OfficeProofingCategory.spelling &&
        finding.originalText.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${_categoryLabel(finding.category)} · ${issue.story} · ${issue.language}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        Text(
          finding.message,
          key: const ValueKey<String>('live-proofing-message'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        _excerpt(issue.sourceText, finding.start, finding.end),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: <Widget>[
            for (var index = 0; index < finding.replacements.length; index++)
              OutlinedButton(
                key: ValueKey<String>('live-proofing-replace-$index'),
                onPressed: canApply
                    ? () => _apply(issue, finding.replacements[index])
                    : null,
                child: Text(_replacementLabel(finding.replacements[index])),
              ),
          ],
        ),
        if (!canApply && finding.replacements.isNotEmpty)
          Text(
            _s(
              'Corrections are unavailable for this text in the current editing mode.',
              'التصحيح غير متاح لهذا النص في وضع التحرير الحالي.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        Wrap(
          spacing: 4,
          children: <Widget>[
            TextButton(
              key: const ValueKey<String>('live-proofing-reveal'),
              onPressed: current && _c.config.allowsSelection
                  ? () => _selectIssue(issue)
                  : null,
              child: Text(_s('Show in document', 'عرض في المستند')),
            ),
            TextButton(
              key: const ValueKey<String>('live-proofing-ignore-once'),
              onPressed: current
                  ? () => _ignore(issue, () => _c.proofing.ignoreOnce(issue))
                  : null,
              child: Text(_s('Ignore once', 'تجاهل مرة واحدة')),
            ),
            if (spelling) ...<Widget>[
              TextButton(
                key: const ValueKey<String>('live-proofing-ignore-word'),
                onPressed: current
                    ? () => _ignore(issue, () => _c.proofing.ignoreWord(issue))
                    : null,
                child: Text(_s('Ignore word', 'تجاهل الكلمة')),
              ),
              TextButton(
                key: const ValueKey<String>('live-proofing-add-word'),
                onPressed: current
                    ? () => _ignore(issue, () => _c.proofing.addWord(issue))
                    : null,
                child: Text(_s('Add to dictionary', 'إضافة إلى القاموس')),
              ),
            ] else
              TextButton(
                key: const ValueKey<String>('live-proofing-ignore-rule'),
                onPressed: current
                    ? () => _ignore(
                        issue,
                        () => _c.proofing.ignoreRule(finding.ruleId),
                      )
                    : null,
                child: Text(_s('Ignore rule', 'تجاهل القاعدة')),
              ),
          ],
        ),
      ],
    );
  }

  bool get _hasChangeFilters =>
      _changeAuthor != null ||
      _changeKind != null ||
      _changeQuery.trim().isNotEmpty;

  List<WmlRevision> _filteredChanges(List<WmlRevision> pending) {
    final query = _changeQuery.trim().toLowerCase();
    return pending.where((revision) {
      return (_changeAuthor == null || revision.author == _changeAuthor) &&
          (_changeKind == null || revision.kind == _changeKind) &&
          (query.isEmpty ||
              revision.text.toLowerCase().contains(query) ||
              revision.author.toLowerCase().contains(query));
    }).toList();
  }

  WmlRevision? _selectedShownChange(List<WmlRevision> shown) {
    if (shown.isEmpty) return null;
    final selected = _c.selectedRevision;
    if (shown.contains(selected)) return selected;
    if (selected != null) {
      final current = _c.document.revisions.indexOf(selected);
      for (final revision in shown) {
        if (_c.document.revisions.indexOf(revision) >= current) return revision;
      }
      return shown.last;
    }
    return shown.first;
  }

  Map<WmlRevision, WmlParagraph?> _reviewTargets(List<WmlRevision> pending) {
    // validateRevision trusts an explicitly supplied map. Resolve attachment
    // once across every supported story before using it for controls/previews.
    final document = _c.document;
    final body = document.paragraphs.toList();
    final attached = Set<WmlParagraph>.identity()..addAll(body);
    for (final section in document.sections) {
      attached
        ..addAll(section.header)
        ..addAll(section.footer)
        ..addAll(section.firstHeader)
        ..addAll(section.firstFooter)
        ..addAll(section.evenHeader)
        ..addAll(section.evenFooter);
    }
    for (final note in <WmlNote>[...document.footnotes, ...document.endnotes]) {
      attached.addAll(note.allParagraphs);
    }
    for (final comment in document.comments) {
      attached.addAll(comment.paragraphs);
    }
    WmlParagraph? target(WmlRevision revision) {
      final paragraph =
          revision.targetParagraph ??
          (!revision.hasCapturedTarget &&
                  revision.paragraphIndex >= 0 &&
                  revision.paragraphIndex < body.length
              ? body[revision.paragraphIndex]
              : null);
      return paragraph != null && attached.contains(paragraph)
          ? paragraph
          : null;
    }

    return <WmlRevision, WmlParagraph?>{
      for (final revision in pending) revision: target(revision),
    };
  }

  void _clearChangeFilters() {
    setState(() {
      _changeAuthor = null;
      _changeKind = null;
      _changeQuery = '';
      _changeSearch.clear();
      _notice = null;
    });
  }

  void _resolveChanges(
    List<WmlRevision> revisions, {
    required bool accept,
    required WmlRevision? selected,
  }) {
    if (!_c.config.allowsMutation) return;
    try {
      // The displayed filtered selection must be the one restored by Undo,
      // even if the canvas previously selected a change outside these filters.
      if (selected != null && _c.document.revisions.contains(selected)) {
        _c.selectedRevisionIndex = _c.document.revisions.indexOf(selected);
      }
      if (accept) {
        _c.acceptRevisions(revisions);
      } else {
        _c.rejectRevisions(revisions);
      }
      setState(() {
        _notice = _s(
          'Review updated. Undo restores the previous changes.',
          'تم تحديث المراجعة. التراجع يعيد التغييرات السابقة.',
        );
      });
    } on Object catch (error) {
      setState(() => _notice = '$error');
    }
  }

  List<Widget> _changesContent() {
    final pending = _c.document.revisions
        .where((revision) => revision.accepted == null)
        .toList();
    final shown = _filteredChanges(pending);
    final selected = _selectedShownChange(shown);
    final selectedIndex = selected == null ? -1 : shown.indexOf(selected);
    final authors = <String>{
      ...pending.map((revision) => revision.author),
      ?_changeAuthor,
    }.toList()..sort();
    final targets = _reviewTargets(pending);
    final editable = _c.config.allowsMutation;
    return <Widget>[
      SwitchListTile.adaptive(
        key: const ValueKey<String>('live-review-track'),
        contentPadding: EdgeInsets.zero,
        title: Text(_s('Track text changes', 'تعقب تغييرات النص')),
        value: _c.document.trackRevisions,
        onChanged: editable ? _c.setTrackRevisions : null,
      ),
      TextField(
        key: const ValueKey<String>('live-review-author'),
        controller: _author,
        enabled: editable,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: _s('Reviewer for new changes', 'مراجع التغييرات الجديدة'),
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: IconButton(
            key: const ValueKey<String>('live-review-set-author'),
            tooltip: _s('Set reviewer', 'تعيين المراجع'),
            onPressed: editable ? _setAuthor : null,
            icon: const Icon(Icons.check, size: 20),
          ),
        ),
        onSubmitted: (_) => _setAuthor(),
      ),
      ExpansionTile(
        key: const ValueKey<String>('live-review-filters'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
        initiallyExpanded: _hasChangeFilters,
        maintainState: true,
        title: Text(_s('Filter changes', 'تصفية التغييرات')),
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('live-review-search'),
            controller: _changeSearch,
            decoration: InputDecoration(
              labelText: _s('Search changes', 'بحث في التغييرات'),
              border: const OutlineInputBorder(),
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _changeQuery.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey<String>('live-review-clear-search'),
                      tooltip: _s('Clear search', 'مسح البحث'),
                      onPressed: () => setState(() {
                        _changeSearch.clear();
                        _changeQuery = '';
                      }),
                      icon: const Icon(Icons.clear, size: 18),
                    ),
            ),
            onChanged: (value) => setState(() {
              _changeQuery = value;
              _notice = null;
            }),
          ),
          const SizedBox(height: 8),
          _changeDropdown<String?>(
            key: const ValueKey<String>('live-review-author-filter'),
            label: _s('Author', 'المراجع'),
            value: _changeAuthor,
            hint: _s('All authors', 'كل المراجعين'),
            items: <DropdownMenuItem<String?>>[
              DropdownMenuItem(
                value: null,
                child: Text(
                  _s('All authors', 'كل المراجعين'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final author in authors)
                DropdownMenuItem(
                  value: author,
                  child: Text(
                    author.isEmpty
                        ? _s('Unknown author', 'مراجع غير معروف')
                        : author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() {
              _changeAuthor = value;
              _notice = null;
            }),
          ),
          const SizedBox(height: 8),
          _changeDropdown<WmlRevisionKind?>(
            key: const ValueKey<String>('live-review-kind-filter'),
            label: _s('Change type', 'نوع التغيير'),
            value: _changeKind,
            hint: _s('All change types', 'كل أنواع التغييرات'),
            items: <DropdownMenuItem<WmlRevisionKind?>>[
              DropdownMenuItem(
                value: null,
                child: Text(
                  _s('All change types', 'كل أنواع التغييرات'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: WmlRevisionKind.insert,
                child: Text(_s('Insertions', 'إدراج')),
              ),
              DropdownMenuItem(
                value: WmlRevisionKind.delete,
                child: Text(_s('Deletions', 'حذف')),
              ),
              for (final kind in [
                WmlRevisionKind.moveFrom,
                WmlRevisionKind.moveTo,
                WmlRevisionKind.runFormat,
                WmlRevisionKind.paragraphFormat,
              ])
                DropdownMenuItem(
                  value: kind,
                  child: Text(kind.reviewLabel(arabic: _arabic)),
                ),
            ],
            onChanged: (value) => setState(() {
              _changeKind = value;
              _notice = null;
            }),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            _s(
              '${shown.length} of ${pending.length} pending changes',
              '${shown.length} من ${pending.length} تغييرات معلقة',
            ),
            key: const ValueKey<String>('live-review-filter-count'),
          ),
          if (_hasChangeFilters)
            TextButton(
              key: const ValueKey<String>('live-review-clear-filters'),
              onPressed: _clearChangeFilters,
              child: Text(_s('Clear filters', 'مسح المرشحات')),
            ),
        ],
      ),
      _navigation(
        label: shown.isEmpty
            ? _s('0 shown changes', 'لا توجد تغييرات معروضة')
            : _s(
                '${selectedIndex + 1} of ${shown.length} changes',
                '${selectedIndex + 1} من ${shown.length} تغييرات',
              ),
        previousKey: 'live-review-previous',
        nextKey: 'live-review-next',
        onPrevious: shown.isEmpty
            ? null
            : () => _selectRevision(shown[(selectedIndex - 1) % shown.length]),
        onNext: shown.isEmpty
            ? null
            : () => _selectRevision(shown[(selectedIndex + 1) % shown.length]),
      ),
      if (selected != null)
        _revisionDetail(selected, targets)
      else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            pending.isEmpty
                ? _s(
                    'No pending tracked changes. Turn on tracking to review future text edits.',
                    'لا توجد تغييرات متعقبة معلقة. فعّل التعقب لمراجعة تعديلات النص القادمة.',
                  )
                : _s(
                    'No changes match these filters.',
                    'لا توجد تغييرات تطابق عوامل التصفية.',
                  ),
            key: const ValueKey<String>('live-review-empty'),
          ),
        ),
      _historyActions(),
      if (pending.isNotEmpty) ...<Widget>[
        const Divider(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            TextButton(
              key: const ValueKey<String>('live-review-accept-shown'),
              onPressed: editable && shown.isNotEmpty
                  ? () =>
                        _resolveChanges(shown, accept: true, selected: selected)
                  : null,
              child: Text(
                _s(
                  'Accept ${shown.length} shown',
                  'قبول ${shown.length} المعروضة',
                ),
              ),
            ),
            TextButton(
              key: const ValueKey<String>('live-review-reject-shown'),
              onPressed: editable && shown.isNotEmpty
                  ? () => _resolveChanges(
                      shown,
                      accept: false,
                      selected: selected,
                    )
                  : null,
              child: Text(
                _s(
                  'Reject ${shown.length} shown',
                  'رفض ${shown.length} المعروضة',
                ),
              ),
            ),
          ],
        ),
        Text(
          _s(
            'Only the changes matching these filters are included. Undo restores the whole batch.',
            'تشمل العملية التغييرات المطابقة لهذه المرشحات فقط. التراجع يعيد المجموعة كاملة.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      if (shown.length > 1)
        ExpansionTile(
          key: const ValueKey<String>('live-review-change-list'),
          tilePadding: EdgeInsets.zero,
          title: Text(_s('All shown changes', 'كل التغييرات المعروضة')),
          children: <Widget>[
            for (final revision in shown)
              ListTile(
                key: ValueKey<String>('live-review-change-${revision.id}'),
                contentPadding: EdgeInsets.zero,
                selected: identical(selected, revision),
                leading: Icon(
                  revision.kind.isFormatting
                      ? Icons.format_paint
                      : revision.kind.isMove
                      ? Icons.drive_file_move_outline
                      : revision.kind.isInsertion
                      ? Icons.add
                      : Icons.remove,
                  size: 20,
                ),
                title: Text(
                  revision.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${revision.kind.reviewLabel(arabic: _arabic)}: ${revision.displayText}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: revision.conflict == null
                    ? null
                    : const Icon(Icons.warning_amber, size: 18),
                onTap: () => _selectRevision(revision),
              ),
          ],
        ),
    ];
  }

  Widget _changeDropdown<T>({
    required Key key,
    required String label,
    required T? value,
    String? hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),
    child: DropdownButton<T>(
      key: key,
      value: value,
      isExpanded: true,
      hint: hint == null
          ? null
          : Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis),
      underline: const SizedBox.shrink(),
      items: items,
      onChanged: onChanged,
    ),
  );

  void _setAuthor() {
    if (!_c.config.allowsMutation) return;
    _changeAction(() {
      _c.revisionAuthor = _author.text;
      _author.text = _c.revisionAuthor;
    });
  }

  Widget _revisionDetail(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${revision.kind.reviewLabel(arabic: _arabic)} · ${revision.author}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (revision.kind.isMove || revision.kind.isFormatting)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              revision.kind.isMove
                  ? _s(
                      'Accept or reject applies to both locations of this move.',
                      'يطبق القبول أو الرفض على موقعي هذا النقل.',
                    )
                  : _s(
                      'Accept keeps current formatting. Reject restores previous formatting.',
                      'يبقي القبول التنسيق الحالي ويستعيد الرفض التنسيق السابق.',
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          revision.displayText,
          key: const ValueKey<String>('live-review-selected-text'),
          style: TextStyle(
            decoration: revision.kind.isFormatting
                ? null
                : revision.kind.isInsertion
                ? TextDecoration.underline
                : TextDecoration.lineThrough,
          ),
        ),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              problem,
              key: const ValueKey<String>('live-review-conflict'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: <Widget>[
            FilledButton.tonal(
              key: const ValueKey<String>('live-review-accept'),
              onPressed: editable
                  ? () => _resolveChanges(
                      <WmlRevision>[revision],
                      accept: true,
                      selected: revision,
                    )
                  : null,
              child: Text(_s('Accept', 'قبول')),
            ),
            OutlinedButton(
              key: const ValueKey<String>('live-review-reject'),
              onPressed: editable
                  ? () => _resolveChanges(
                      <WmlRevision>[revision],
                      accept: false,
                      selected: revision,
                    )
                  : null,
              child: Text(_s('Reject', 'رفض')),
            ),
            TextButton(
              key: const ValueKey<String>('live-review-reveal'),
              onPressed: _c.config.allowsSelection && problem == null
                  ? () => _selectRevision(revision)
                  : null,
              child: Text(_s('Show in document', 'عرض في المستند')),
            ),
          ],
        ),
        if (paragraph != null) ...<Widget>[
          const Divider(height: 20),
          _changeDropdown<WordComparisonRevisionView>(
            key: const ValueKey<String>('live-review-preview-mode'),
            label: _s('Paragraph preview', 'معاينة الفقرة'),
            value: _preview,
            items: <DropdownMenuItem<WordComparisonRevisionView>>[
              for (final view in WordComparisonRevisionView.values)
                DropdownMenuItem(
                  value: view,
                  child: Text(
                    _previewLabel(view),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _preview = value);
            },
          ),
          const SizedBox(height: 8),
          _paragraphPreview(paragraph, targets),
          const SizedBox(height: 6),
          Text(
            _s(
              'Preview only. Changing this view does not accept or reject changes.',
              'هذه معاينة فقط. تغيير العرض لا يقبل التغييرات أو يرفضها.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  String _previewLabel(WordComparisonRevisionView view) => switch (view) {
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

  Widget _paragraphPreview(
    WmlParagraph paragraph,
    Map<WmlRevision, WmlParagraph?> targets,
  ) {
    final revisions =
        targets.entries
            .where(
              (entry) =>
                  identical(entry.value, paragraph) &&
                  !entry.key.kind.isFormatting,
            )
            .map((entry) => entry.key)
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final text = paragraph.text;
    final spans = <TextSpan>[];
    var at = 0;
    try {
      for (final revision in revisions) {
        // A read-only text projection does not require permission to resolve
        // the change across native field/control boundaries. Validate its
        // attached source text and non-overlap; decision controls separately
        // enforce the complete editing guards.
        if (revision.conflict != null ||
            revision.start < at ||
            revision.end < revision.start ||
            revision.end > text.length ||
            text.substring(revision.start, revision.end) != revision.text) {
          throw StateError('The tracked source text is stale or conflicted.');
        }
        if (revision.start > at) {
          spans.add(TextSpan(text: text.substring(at, revision.start)));
        }
        final inserted = revision.kind.isInsertion;
        final show =
            _preview == WordComparisonRevisionView.markup ||
            (_preview == WordComparisonRevisionView.finalText && inserted) ||
            (_preview == WordComparisonRevisionView.originalText && !inserted);
        if (show) {
          spans.add(
            TextSpan(
              text: revision.displayText,
              style: _preview == WordComparisonRevisionView.markup
                  ? TextStyle(
                      color: inserted
                          ? (Theme.of(context).brightness == Brightness.dark
                                ? Colors.greenAccent.shade100
                                : Colors.green.shade800)
                          : (Theme.of(context).brightness == Brightness.dark
                                ? Colors.redAccent.shade100
                                : Colors.red.shade800),
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
    } on Object {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _s(
              'A change in this paragraph is stale or conflicted. The stored text is shown; final and original previews are unavailable.',
              'يوجد تغيير قديم أو متعارض في هذه الفقرة. يُعرض النص المخزّن؛ معاينتا النص النهائي والأصلي غير متاحتين.',
            ),
            key: const ValueKey<String>('live-review-preview-unavailable'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 6),
          SelectableText(
            text,
            key: const ValueKey<String>('live-review-preview-text'),
          ),
        ],
      );
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return SelectableText.rich(
      TextSpan(children: spans),
      key: const ValueKey<String>('live-review-preview-text'),
    );
  }

  Widget _historyActions() => Wrap(
    spacing: 8,
    children: <Widget>[
      TextButton.icon(
        key: const ValueKey<String>('live-review-undo'),
        onPressed: _c.config.allowsMutation && _c.canUndo
            ? () => _changeAction(_c.undo)
            : null,
        icon: const Icon(Icons.undo, size: 18),
        label: Text(_s('Undo', 'تراجع')),
      ),
      TextButton.icon(
        key: const ValueKey<String>('live-review-redo'),
        onPressed: _c.config.allowsMutation && _c.canRedo
            ? () => _changeAction(_c.redo)
            : null,
        icon: const Icon(Icons.redo, size: 18),
        label: Text(_s('Redo', 'إعادة')),
      ),
    ],
  );

  Widget _navigation({
    required String label,
    required String previousKey,
    required String nextKey,
    required VoidCallback? onPrevious,
    required VoidCallback? onNext,
  }) => Row(
    children: <Widget>[
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
      IconButton(
        key: ValueKey<String>(previousKey),
        tooltip: _s('Previous', 'السابق'),
        onPressed: onPrevious,
        icon: const Icon(Icons.keyboard_arrow_up),
      ),
      IconButton(
        key: ValueKey<String>(nextKey),
        tooltip: _s('Next', 'التالي'),
        onPressed: onNext,
        icon: const Icon(Icons.keyboard_arrow_down),
      ),
    ],
  );

  Widget _excerpt(String source, int start, int end) {
    final boundaries = <int>[
      0,
      for (final cluster in GraphemeClusters.segment(source)) cluster.end,
    ];
    final first = boundaries.indexOf(start);
    final last = boundaries.indexOf(end);
    if (first < 0 || last < first) return Text(source);
    final from = math.max(0, first - 32);
    final to = math.min(boundaries.length - 1, last + 40);
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text:
                '${from == 0 ? '' : '…'}${source.substring(boundaries[from], start)}',
          ),
          TextSpan(
            text: start == end ? '│' : source.substring(start, end),
            semanticsLabel: start == end
                ? _s('insertion point', 'موضع الإدراج')
                : null,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onPrimaryContainer,
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          ),
          TextSpan(
            text:
                '${source.substring(end, boundaries[to])}${to == boundaries.length - 1 ? '' : '…'}',
          ),
        ],
      ),
      key: const ValueKey<String>('live-review-context'),
      style: theme.textTheme.bodyMedium,
    );
  }

  bool _matchesFilter(WordProofingIssue issue) => switch (_filter) {
    _ProofingFilter.all => true,
    _ProofingFilter.spelling =>
      issue.finding.category == OfficeProofingCategory.spelling,
    _ProofingFilter.grammar =>
      issue.finding.category == OfficeProofingCategory.grammar,
    _ProofingFilter.style =>
      issue.finding.category == OfficeProofingCategory.style,
  };

  String _filterLabel(_ProofingFilter filter) => switch (filter) {
    _ProofingFilter.all => _s('All findings', 'كل النتائج'),
    _ProofingFilter.spelling => _categoryLabel(OfficeProofingCategory.spelling),
    _ProofingFilter.grammar => _categoryLabel(OfficeProofingCategory.grammar),
    _ProofingFilter.style => _categoryLabel(OfficeProofingCategory.style),
  };

  String _categoryLabel(OfficeProofingCategory category) => switch (category) {
    OfficeProofingCategory.spelling => _s('Spelling', 'الإملاء'),
    OfficeProofingCategory.grammar => _s('Grammar', 'القواعد'),
    OfficeProofingCategory.style => _s('Writing style', 'أسلوب الكتابة'),
  };

  String _replacementLabel(String replacement) => switch (replacement) {
    '' => _s('Delete', 'حذف'),
    ' ' => _s('Use space', 'استخدام مسافة'),
    '\u00a0' => _s('Use nonbreaking space', 'استخدام مسافة غير قابلة للكسر'),
    '\u202f' => _s(
      'Use narrow nonbreaking space',
      'استخدام مسافة ضيقة غير قابلة للكسر',
    ),
    '\t' => _s('Use tab', 'استخدام مسافة جدولة'),
    _ => replacement,
  };
}
