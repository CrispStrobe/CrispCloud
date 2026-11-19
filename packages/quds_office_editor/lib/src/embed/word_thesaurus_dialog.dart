import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../thesaurus/bundled_thesaurus.dart';
import 'office_controller.dart';

/// Captures the selection before focus leaves the document. Active composition
/// is reported to the user rather than committed as a side effect of lookup.
/// No modal route is opened during composition: a non-focus-taking notice is
/// shown when a Scaffold is available; otherwise this returns without opening.
Future<void> showWordThesaurusDialog(
  BuildContext context, {
  required WordEditorController controller,
  OfficeThesaurusService? service,
  WordThesaurusCapture? capture,
}) {
  final target = capture ?? controller.captureThesaurusTarget();
  // A menu may supply an earlier capture. Recheck the live IME before opening
  // a route, because returning focus to the editor would reset its composition.
  if (target.status == WordThesaurusTargetStatus.composing ||
      (controller.input.composing.isValid &&
          !controller.input.composing.isCollapsed)) {
    if (Scaffold.maybeOf(context) != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Finish the current text composition before using Thesaurus.',
          ),
        ),
      );
    }
    return Future<void>.value();
  }
  return showDialog<void>(
    context: context,
    builder: (context) => WordThesaurusDialog(
      controller: controller,
      service: service ?? BundledOfficeThesaurus.shared,
      capture: target,
    ),
  );
}

/// Explicit, offline alternatives grouped by their original source meanings.
class WordThesaurusDialog extends StatefulWidget {
  const WordThesaurusDialog({
    super.key,
    required this.controller,
    required this.service,
    required this.capture,
  });

  final WordEditorController controller;
  final OfficeThesaurusService service;
  final WordThesaurusCapture capture;

  @override
  State<WordThesaurusDialog> createState() => _WordThesaurusDialogState();
}

class _WordThesaurusDialogState extends State<WordThesaurusDialog> {
  static const _languages = <String, String>{
    'en-US': 'English (United States)',
    'en-GB': 'English (United Kingdom)',
    'en-CA': 'English (Canada)',
    'en-AU': 'English (Australia)',
    'en-IN': 'English (India)',
    'de-DE': 'Deutsch (Deutschland)',
    'de-AT': 'Deutsch (Österreich)',
    'de-CH': 'Deutsch (Schweiz)',
  };

  String? _languageOverride;
  WordThesaurusLookup? _lookup;
  OfficeThesaurusTerm? _selected;
  bool _loading = false;
  bool _applied = false;
  String? _notice;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(WordThesaurusDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller) ||
        !identical(widget.service, oldWidget.service) ||
        !identical(widget.capture, oldWidget.capture)) {
      _languageOverride = null;
      _applied = false;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final target = widget.capture.target;
    final generation = ++_generation;
    if (target == null || _applied) return;
    setState(() {
      _loading = true;
      _lookup = null;
      _selected = null;
      _notice = null;
    });
    try {
      final lookup = await widget.controller.lookupThesaurus(
        target,
        widget.service,
        languageOverride: _languageOverride,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _lookup = lookup;
        _loading = false;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _notice = 'The lookup could not finish. Try again.';
      });
    }
  }

  void _replace() {
    final lookup = _lookup;
    final term = _selected;
    if (lookup == null || term == null) return;
    final applied = widget.controller.applyThesaurusTerm(lookup, term);
    setState(() {
      _applied = applied;
      _notice = applied
          ? 'Replaced with “${term.text}”. You can undo this change.'
          : 'The selection or thesaurus has changed. Close this dialog and look up the text again.';
      _selected = null;
    });
  }

  void _retry() {
    // Failed manifest futures and old shards are cached until invalidation.
    // Explicit retry must be able to read a repaired/reinstalled pack.
    widget.service.clear();
    unawaited(_load());
  }

  Future<void> _showSources() async {
    final lookup = _lookup;
    if (lookup?.result.pack == null) return;
    final result = lookup!.result;
    final pack = result.pack!;
    // Start the read in the dialog build, where FutureBuilder attaches its
    // error handler immediately (before a missing/corrupt notice can fail).
    Future<List<OfficeThesaurusNotice>>? notices;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thesaurus sources and licenses'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  '${pack.name} · ${pack.version}\n${pack.license}',
                ),
                const SizedBox(height: 12),
                SelectableText(pack.attribution),
                const SizedBox(height: 8),
                SelectableText(pack.sourceUrl),
                const SizedBox(height: 16),
                FutureBuilder<List<OfficeThesaurusNotice>>(
                  future: notices ??= widget.service.notices(result),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text(
                        'The bundled notices could not be verified. Reinstall the thesaurus pack.',
                      );
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator(
                        semanticsLabel: 'Loading source notices',
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final notice in snapshot.data!)
                          ExpansionTile(
                            title: Text(notice.path.split('/').last),
                            childrenPadding: const EdgeInsets.all(12),
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [SelectableText(notice.text)],
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close sources'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final target = widget.capture.target;
      final lookup = _lookup;
      final result = lookup?.result;
      final current =
          target != null && widget.controller.isThesaurusTargetCurrent(target);
      final stale =
          !_applied &&
          target != null &&
          (!current ||
              (lookup != null &&
                  !widget.controller.isThesaurusLookupCurrent(lookup)));
      final canReplace =
          !_applied &&
          !_loading &&
          lookup != null &&
          _selected != null &&
          widget.controller.canApplyThesaurusTerm(lookup, _selected!);
      final height = math.min(720.0, MediaQuery.sizeOf(context).height - 48);
      final language = _languageOverride ?? target?.language ?? 'en-US';
      return Dialog(
        key: const ValueKey('word-thesaurus-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 760,
          height: math.max(120, height),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Thesaurus',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close thesaurus',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const LinearProgressIndicator(
                  key: ValueKey('thesaurus-progress'),
                  semanticsLabel: 'Looking up alternatives',
                )
              else
                const Divider(height: 4),
              Expanded(
                child: ListView(
                  key: const ValueKey('thesaurus-content'),
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  children: [
                    if (target != null) ...[
                      SelectableText(
                        target.text,
                        key: const ValueKey('thesaurus-query'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Look up in',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            key: const ValueKey('thesaurus-language'),
                            value: language,
                            isExpanded: true,
                            items: [
                              for (final entry in _languages.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              if (!_languages.containsKey(language))
                                DropdownMenuItem(
                                  value: language,
                                  child: Text(language),
                                ),
                            ],
                            onChanged: !current || _applied
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    _languageOverride = value;
                                    unawaited(_load());
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Document language: ${_languages[target.language] ?? target.language}. '
                        'This choice applies to the lookup only.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (target == null)
                      _status(
                        widget.capture.message ??
                            'Select a word or a short phrase in one paragraph.',
                      ),
                    if (stale)
                      _status(
                        'The selection or thesaurus has changed. Close this dialog and look up the text again.',
                      ),
                    if (_notice != null)
                      _status(_notice!, key: 'thesaurus-notice'),
                    if (_loading) const Text('Looking up alternatives…'),
                    if (result != null &&
                        result.status != OfficeThesaurusStatus.ready)
                      _status(
                        result.message ??
                            switch (result.status) {
                              OfficeThesaurusStatus.noEntry =>
                                'No entry found.',
                              OfficeThesaurusStatus.unsupportedLanguage =>
                                'This language is not supported.',
                              OfficeThesaurusStatus.missingPack =>
                                'The thesaurus pack is not installed.',
                              OfficeThesaurusStatus.failedPack =>
                                'The thesaurus pack could not be verified.',
                              OfficeThesaurusStatus.ready => '',
                            },
                        key: 'thesaurus-${result.status.name}',
                      ),
                    if (result?.status == OfficeThesaurusStatus.ready) ...[
                      Text(
                        '${result!.senses.length} meaning group${result.senses.length == 1 ? '' : 's'} · '
                        '${result.pack?.name ?? ''}',
                        key: const ValueKey('thesaurus-summary'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Choose an alternative, then Replace. Check its meaning, register and grammar in your sentence; word endings are not adjusted automatically.',
                      ),
                      if (result.matchedTerms.any(
                        (match) => match.reason != 'lexical',
                      ))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Also matched: ${result.matchedTerms.where((match) => match.reason != 'lexical').map((match) => '${match.text} (${_matchLabel(match.reason)})').join(', ')}',
                            key: const ValueKey('thesaurus-word-forms'),
                          ),
                        ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < result.senses.length; i++)
                        _sense(result.senses[i], i + 1, !stale && !_applied),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (result?.pack != null)
                      TextButton(
                        key: const ValueKey('thesaurus-sources'),
                        onPressed: () => unawaited(_showSources()),
                        child: const Text('Sources and licenses'),
                      ),
                    if (!_applied &&
                        current &&
                        !_loading &&
                        (result?.status == OfficeThesaurusStatus.failedPack ||
                            _notice != null))
                      TextButton(
                        onPressed: _retry,
                        child: const Text('Try again'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    FilledButton(
                      key: const ValueKey('thesaurus-replace'),
                      onPressed: canReplace ? _replace : null,
                      child: const Text('Replace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _status(String text, {String key = 'thesaurus-status'}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(liveRegion: true, child: Text(text, key: ValueKey(key))),
  );

  Widget _sense(OfficeThesaurusSense sense, int number, bool enabled) {
    final text = widget.capture.target?.text ?? '';
    final alternatives = sense.terms
        .where((term) => term.text != text)
        .toList();
    return Card(
      key: ValueKey('thesaurus-sense-${sense.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meaning $number${sense.pos == null ? '' : ' · ${_posLabel(sense.pos!)}'}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (sense.gloss != null) ...[
              const SizedBox(height: 4),
              Text(sense.gloss!),
            ],
            if (sense.labels.isNotEmpty) Text(sense.labels.join(' · ')),
            for (final example in sense.examples)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '“$example”',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            if (alternatives.isEmpty)
              const Text('This meaning has no other lexical alternative.'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final term in alternatives)
                  ChoiceChip(
                    key: ValueKey('thesaurus-term-${sense.id}-${term.id}'),
                    selected: identical(_selected, term),
                    label: Text(
                      '${term.text}${term.labels.isEmpty ? '' : ' · ${term.labels.join(', ')}'}${term.note == null ? '' : ' (${term.note})'}',
                    ),
                    onSelected: !enabled
                        ? null
                        : (selected) => setState(
                            () => _selected = selected ? term : null,
                          ),
                  ),
              ],
            ),
            if (sense.relations.isNotEmpty ||
                sense.terms.any((term) => term.relations.isNotEmpty))
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Related concepts (not replacements)'),
                children: [
                  for (final relation in sense.relations)
                    ListTile(
                      dense: true,
                      title: Text(
                        '${relation.type}: ${relation.label ?? relation.target}',
                      ),
                    ),
                  for (final term in sense.terms)
                    for (final relation in term.relations)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${term.text} · ${relation.type}: ${relation.label ?? relation.target}',
                        ),
                      ),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              '${sense.source} · ${sense.id}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _posLabel(String pos) => switch (pos) {
    'n' => 'noun',
    'v' => 'verb',
    'a' || 's' => 'adjective',
    'r' => 'adverb',
    _ => pos,
  };

  String _matchLabel(String reason) => switch (reason) {
    'wordnet-detachment' => 'English word form',
    'unicode-noun-form' => 'German noun form',
    'canonical-form' => 'Unicode spelling',
    _ => 'source word form',
  };
}
