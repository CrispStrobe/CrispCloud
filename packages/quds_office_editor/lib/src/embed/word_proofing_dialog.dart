import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'office_controller.dart';

/// Review spelling and writing findings for every modeled document story.
Future<void> showWordProofingDialog(
  BuildContext context, {
  required WordEditorController controller,
}) {
  controller.commitPendingEdits();
  return showDialog<void>(
    context: context,
    builder: (_) => WordProofingDialog(controller: controller),
  );
}

/// Shared F7 review surface. Results stay live as the document changes.
class WordProofingDialog extends StatefulWidget {
  const WordProofingDialog({super.key, required this.controller});

  final WordEditorController controller;

  @override
  State<WordProofingDialog> createState() => _WordProofingDialogState();
}

class _WordProofingDialogState extends State<WordProofingDialog> {
  WordEditorController get _controller => widget.controller;
  WordProofingSession get _session => _controller.proofing;
  bool get _arabic => _controller.config.textDirection == TextDirection.rtl;
  String _text(String english, String arabic) => _arabic ? arabic : english;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _session.addListener(_changed);
    _session.attachView();
    _checkAfterBuild();
  }

  void _checkAfterBuild() {
    final session = _session;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(session, _session)) {
        unawaited(session.checkDocument());
      }
    });
  }

  @override
  void didUpdateWidget(WordProofingDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, _controller)) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.proofing.removeListener(_changed);
      oldWidget.controller.proofing.detachView();
      _controller.addListener(_changed);
      _session.addListener(_changed);
      _session.attachView();
      _notice = null;
      _checkAfterBuild();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _session.removeListener(_changed);
    _session.detachView();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _category(OfficeProofingCategory category) => switch (category) {
    OfficeProofingCategory.spelling => _text('Spelling', 'الإملاء'),
    OfficeProofingCategory.grammar => _text('Grammar', 'القواعد'),
    OfficeProofingCategory.style => _text('Writing style', 'أسلوب الكتابة'),
  };

  String _status(OfficeProofingStatus status) => switch (status) {
    OfficeProofingStatus.success => _text('Checked', 'تم التدقيق'),
    OfficeProofingStatus.unsupported => _text(
      'Unsupported language',
      'لغة غير مدعومة',
    ),
    OfficeProofingStatus.unavailable => _text('Unavailable', 'غير متاح'),
    OfficeProofingStatus.failed => _text('Check failed', 'تعذر التدقيق'),
  };

  String _summary(WordProofingSummary summary) {
    if (!_session.enabled) {
      return _text('Proofreading is off.', 'التدقيق متوقف.');
    }
    if (summary.running) {
      return _text('Checking document…', 'جارٍ تدقيق المستند…');
    }
    if (!summary.hasChecked) {
      return _text('Ready to check the document.', 'جاهز لتدقيق المستند.');
    }
    if (!summary.complete) {
      return _text(
        'The check is incomplete. Review provider status below.',
        'التدقيق غير مكتمل. راجع حالة أدوات التدقيق أدناه.',
      );
    }
    if (summary.issues.isEmpty) {
      return _text(
        'No findings in checked text.',
        'لا توجد ملاحظات في النص المدقق.',
      );
    }
    return _text(
      '${summary.issues.length} findings to review.',
      '${summary.issues.length} ملاحظات للمراجعة.',
    );
  }

  void _replace(WordProofingIssue issue, String replacement) {
    final bool changed = _session.applySuggestion(issue, replacement);
    setState(() {
      _notice = changed
          ? _text(
              'Correction applied. You can undo it.',
              'تم التصحيح. يمكنك التراجع عنه.',
            )
          : _text(
              'This finding changed or its text cannot be edited. Check again.',
              'تغيرت هذه الملاحظة أو تعذر تعديل النص. أعد التدقيق.',
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    final WordProofingSummary summary = _session.summary;
    final String language = _controller.proofingLanguage;
    final Map<String, String> languages = <String, String>{
      'de-DE': 'Deutsch (Deutschland)',
      'de-AT': 'Deutsch (Österreich)',
      'de-CH': 'Deutsch (Schweiz)',
      'en-US': 'English (United States)',
      'en-GB': 'English (United Kingdom)',
      if (!const <String>{
        'de-DE',
        'de-AT',
        'de-CH',
        'en-US',
        'en-GB',
      }.contains(language))
        language: language,
    };
    final bool canConfigure =
        _controller.config.allowsMutation &&
        !_controller.document.restrictEditing;
    final Map<String, OfficeProofingResult> providerStates =
        <String, OfficeProofingResult>{};
    for (final OfficeProofingResult result in summary.results) {
      final String key =
          '${result.providerId}/${result.request.language}/${result.status.name}';
      providerStates.putIfAbsent(key, () => result);
    }
    return Directionality(
      textDirection: _controller.config.textDirection,
      child: AlertDialog(
        title: Text(_text('Spelling and writing', 'الإملاء والكتابة')),
        content: SizedBox(
          width: 720,
          height: MediaQuery.sizeOf(context).height * .68,
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 285,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey<String>(
                              'proofing-language-$language',
                            ),
                            initialValue: language,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: _text(
                                'Default document language',
                                'لغة المستند الافتراضية',
                              ),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: <DropdownMenuItem<String>>[
                              for (final MapEntry<String, String> entry
                                  in languages.entries)
                                DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                            ],
                            onChanged: canConfigure
                                ? (String? value) {
                                    if (value != null) {
                                      _controller.setProofingLanguage(value);
                                    }
                                  }
                                : null,
                          ),
                        ),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Switch(
                              value: _session.enabled,
                              onChanged: _session.setEnabled,
                            ),
                            Text(_text('Enable proofreading', 'تفعيل التدقيق')),
                          ],
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        _text(
                          'Automatic German hyphenation',
                          'تقسيم الكلمات الألمانية تلقائيًا',
                        ),
                      ),
                      value: _controller.document.autoHyphenation,
                      onChanged: canConfigure
                          ? (bool? value) => _controller
                                .setAutomaticHyphenation(value ?? false)
                          : null,
                    ),
                    Text(
                      _text(
                        'German spelling and selected writing rules run locally. Suggestions require your review.',
                        'يعمل التدقيق الإملائي الألماني وقواعد كتابة محددة محليًا. تحتاج الاقتراحات إلى مراجعتك.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _summary(summary),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (summary.running) const LinearProgressIndicator(),
                    Text(
                      _text(
                        '${summary.paragraphCount} paragraphs · ${summary.checkedSegments} text segments checked',
                        '${summary.paragraphCount} فقرات · ${summary.checkedSegments} مقاطع مدققة',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (summary.skippedContentCount > 0 ||
                        summary.excludedSpanCount > 0)
                      Text(
                        _text(
                          '${summary.skippedContentCount} unsupported content blocks and ${summary.excludedSpanCount} excluded spans were not checked.',
                          'لم يتم تدقيق ${summary.skippedContentCount} كتل غير مدعومة و${summary.excludedSpanCount} مقاطع مستثناة.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (_notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _notice!,
                          key: const ValueKey<String>('proofing-notice'),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              SliverList.builder(
                itemCount:
                    summary.issues.length + (providerStates.isEmpty ? 0 : 1),
                itemBuilder: (BuildContext context, int index) {
                  if (providerStates.isNotEmpty && index == 0) {
                    return ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      initiallyExpanded: !summary.complete,
                      title: Text(_text('Checking status', 'حالة التدقيق')),
                      children: <Widget>[
                        for (final OfficeProofingResult result
                            in providerStates.values)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              result.status == OfficeProofingStatus.success
                                  ? Icons.check_circle_outline
                                  : Icons.info_outline,
                            ),
                            title: Text(
                              '${result.providerId} · ${result.request.language}: ${_status(result.status)}',
                            ),
                            subtitle: result.message == null
                                ? null
                                : Text(result.message!),
                          ),
                      ],
                    );
                  }
                  final issueIndex = index - (providerStates.isEmpty ? 0 : 1);
                  return _issueCard(summary.issues[issueIndex]);
                },
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: summary.running || !_session.enabled
                ? null
                : () => unawaited(_session.checkDocument()),
            icon: const Icon(Icons.refresh),
            label: Text(_text('Check document', 'تدقيق المستند')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_text('Close', 'إغلاق')),
          ),
        ],
      ),
    );
  }

  Widget _issueCard(WordProofingIssue issue) {
    final OfficeProofingFinding finding = issue.finding;
    final bool canApply = _session.canApplyForDisplay(issue);
    final bool current = _session.isCurrentForDisplay(issue);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${_category(finding.category)} · ${issue.story} · ${issue.language}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(
              finding.originalText.isEmpty ? '∣' : finding.originalText,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(finding.message),
            const SizedBox(height: 4),
            Text(
              issue.sourceText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final String replacement in finding.replacements.take(8))
                  ActionChip(
                    label: Text(
                      replacement.isEmpty
                          ? _text('Delete', 'حذف')
                          : replacement,
                    ),
                    onPressed: canApply
                        ? () => _replace(issue, replacement)
                        : null,
                  ),
                TextButton(
                  onPressed: current && _session.canSelectIssue(issue)
                      ? () {
                          if (_session.selectIssue(issue)) {
                            Navigator.of(context).pop();
                          }
                        }
                      : null,
                  child: Text(_text('Go to text', 'الانتقال إلى النص')),
                ),
                TextButton(
                  onPressed: current ? () => _session.ignoreOnce(issue) : null,
                  child: Text(_text('Ignore once', 'تجاهل مرة واحدة')),
                ),
                if (finding.category ==
                    OfficeProofingCategory.spelling) ...<Widget>[
                  TextButton(
                    onPressed: current
                        ? () => _session.ignoreWord(issue)
                        : null,
                    child: Text(_text('Ignore word', 'تجاهل الكلمة')),
                  ),
                  TextButton(
                    onPressed: current ? () => _session.addWord(issue) : null,
                    child: Text(
                      _text(
                        'Add to personal words',
                        'إضافة إلى الكلمات الشخصية',
                      ),
                    ),
                  ),
                ] else
                  TextButton(
                    onPressed: current
                        ? () => _session.ignoreRule(finding.ruleId)
                        : null,
                    child: Text(_text('Ignore this rule', 'تجاهل هذه القاعدة')),
                  ),
              ],
            ),
            if (!current)
              Text(
                _text('Text changed. Check again.', 'تغير النص. أعد التدقيق.'),
              )
            else if (!canApply && finding.replacements.isNotEmpty)
              Text(
                _text(
                  'This text cannot be corrected here.',
                  'لا يمكن تصحيح هذا النص هنا.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
