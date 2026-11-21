import 'package:flutter/material.dart';

import '../proofing/word_proofing.dart';
import 'office_controller.dart';
import '../l10n/office_plural.dart';

/// Always-visible entry points and honest live-check status for Word review.
/// This is host chrome; it never edits the document or starts manual providers.
class WordReviewStatusBar extends StatefulWidget {
  const WordReviewStatusBar({super.key, required this.controller});

  final WordEditorController controller;

  @override
  State<WordReviewStatusBar> createState() => _WordReviewStatusBarState();
}

/// The inputs of one status bar frame. The bar rebuilds only when one of
/// them changes, not for every keystroke or proofing progress notification.
typedef _StatusChrome = ({
  bool arabic,
  int pending,
  bool tracking,
  String? language,
  bool hasTarget,
  bool isSelection,
  bool enabled,
});

class _WordReviewStatusBarState extends State<WordReviewStatusBar> {
  WordEditorController get controller => widget.controller;
  WordProofingSession? _session;
  late _StatusChrome _chrome;
  int _pendingRevision = -1;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(WordReviewStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, controller)) {
      oldWidget.controller.removeListener(_onController);
      _session?.status.removeListener(_onStatus);
      _pendingRevision = -1;
      _attach();
    }
  }

  void _attach() {
    controller.addListener(_onController);
    _session = controller.proofing..status.addListener(_onStatus);
    _chrome = _readChrome();
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    _session?.status.removeListener(_onStatus);
    super.dispose();
  }

  _StatusChrome _readChrome() {
    // Tracked changes are counted once per content revision.
    final revision = controller.contentRevision;
    if (revision != _pendingRevision) {
      _pendingRevision = revision;
      _pending = controller.document.revisions
          .where((revision) => revision.accepted == null)
          .length;
    }
    final target = controller.textProofingTarget;
    return (
      arabic: controller.config.textDirection == TextDirection.rtl,
      pending: _pending,
      tracking: controller.document.trackRevisions,
      language: target?.language,
      hasTarget: target != null,
      isSelection: target?.isSelection == true,
      enabled: controller.proofing.enabled,
    );
  }

  void _onController() {
    if (!mounted) return;
    final session = controller.proofing;
    if (!identical(session, _session)) {
      _session?.status.removeListener(_onStatus);
      _session = session..status.addListener(_onStatus);
    }
    final next = _readChrome();
    if (next != _chrome) setState(() => _chrome = next);
  }

  void _onStatus() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final status = controller.proofing.status.value;
    final chrome = _chrome;
    final arabic = chrome.arabic;
    final pending = chrome.pending;
    final issueCount = status.issueCount;
    final languageLabel = !chrome.hasTarget
        ? (arabic ? 'اللغة' : 'Language')
        : chrome.language ?? (arabic ? 'لغات متعددة' : 'Mixed');
    final textScope = chrome.isSelection
        ? (arabic ? 'النص المحدد' : 'Selected text')
        : (arabic ? 'الفقرة الحالية' : 'Current paragraph');
    final languageTooltip = arabic
        ? '$textScope · $languageLabel\nاللغة والتدقيق'
        : '$textScope · $languageLabel\nLanguage and checking';
    final issuesLabel = officeIssues(issueCount, arabic: arabic);
    final changesLabel = officeChanges(pending);
    final String label;
    final IconData icon;
    switch (status.phase) {
      case WordProofingPhase.checking:
        label = arabic ? 'جارٍ التدقيق…' : 'Checking…';
        icon = Icons.hourglass_top;
      case WordProofingPhase.waiting:
        label = arabic ? 'بانتظار توقف الكتابة…' : 'Waiting to check…';
        icon = Icons.more_horiz;
      case WordProofingPhase.paused:
        label = arabic ? 'التدقيق التلقائي متوقف' : 'Live checking paused';
        icon = Icons.pause_circle_outline;
      case WordProofingPhase.notChecked:
        label = arabic ? 'لم يُدقّق بعد' : 'Not checked yet';
        icon = Icons.spellcheck;
      case WordProofingPhase.partial:
        label = arabic
            ? '$issuesLabel · تدقيق جزئي'
            : '$issuesLabel · partial check';
        icon = Icons.info_outline;
      case WordProofingPhase.complete:
        label = issueCount == 0
            ? (arabic ? 'لا توجد ملاحظات' : 'No writing issues')
            : officeIssues(issueCount, arabic: arabic, writing: true);
        icon = issueCount == 0 ? Icons.check_circle_outline : Icons.spellcheck;
    }
    return Material(
      key: const ValueKey('word-review-status'),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: status.message,
                  child: TextButton.icon(
                    key: const ValueKey('word-review-writing-status'),
                    onPressed: () => controller.openReviewPane(),
                    icon: Icon(icon, size: 17),
                    label: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: TextButton.styleFrom(
                      alignment: AlignmentDirectional.centerStart,
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: languageTooltip,
                child: constraints.maxWidth >= 560
                    ? ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * .26,
                        ),
                        child: TextButton.icon(
                          key: const ValueKey('word-review-language-status'),
                          onPressed: controller.showTextProofingOptions,
                          icon: const Icon(Icons.language, size: 17),
                          label: Text(
                            languageLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    : IconButton(
                        key: const ValueKey('word-review-language-status'),
                        onPressed: controller.showTextProofingOptions,
                        icon: const Icon(Icons.language, size: 18),
                      ),
              ),
              Tooltip(
                message: arabic
                    ? '$pending تغييرات · مراجعة التغييرات المتعقبة'
                    : '$changesLabel · Review tracked changes',
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * .34,
                  ),
                  child: TextButton.icon(
                    key: const ValueKey('word-review-changes-status'),
                    onPressed: () => controller.openReviewPane(
                      tab: WordReviewPaneTab.changes,
                    ),
                    icon: Icon(
                      chrome.tracking
                          ? Icons.track_changes
                          : Icons.rate_review_outlined,
                      size: 17,
                    ),
                    label: Text(
                      arabic ? '$pending تغييرات' : changesLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('word-review-thesaurus'),
                tooltip: arabic
                    ? 'قاموس المرادفات (Shift+F7)'
                    : 'Thesaurus (Shift+F7)',
                onPressed: controller.requestThesaurus,
                icon: const Icon(Icons.menu_book_outlined, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
