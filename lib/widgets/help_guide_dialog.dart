import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/help_guide_strings.dart';
import '../services/help_guide_service.dart';

Future<void> showUserGuide(BuildContext context, {String? topicId}) =>
    showDialog<void>(
      context: context,
      builder: (_) => HelpGuideDialog(topicId: topicId),
    );

class HelpGuideDialog extends StatefulWidget {
  const HelpGuideDialog({super.key, this.topicId, this.service, this.openLink});
  final String? topicId;
  final HelpGuideService? service;
  final Future<bool> Function(Uri)? openLink;

  @override
  State<HelpGuideDialog> createState() => _HelpGuideDialogState();
}

class _HelpGuideDialogState extends State<HelpGuideDialog> {
  late final _service = widget.service ?? HelpGuideService();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _language = 'auto';
  String? _appLanguage, _selected, _notice;
  HelpGuide? _guide;
  bool _failed = false, _loading = true;
  int _generation = 0, _navigation = 0;

  List<HelpTopic> get _visibleTopics {
    final query = _search.text.trim().toLowerCase();
    return _guide?.topics
            .where(
              (topic) =>
                  query.isEmpty ||
                  topic.title.toLowerCase().contains(query) ||
                  topic.markdown.toLowerCase().contains(query),
            )
            .toList() ??
        const [];
  }

  HelpTopic? get _visibleTopic {
    final topics = _visibleTopics;
    return topics.where((topic) => topic.id == _selected).firstOrNull ??
        topics.firstOrNull;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    if (_appLanguage != language) {
      _appLanguage = language;
      if (_language == 'auto') _changeLanguage('auto');
    }
  }

  void _changeLanguage(String value) {
    _selected = _visibleTopic?.id ?? _selected;
    _search.clear();
    _language = value;
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _navigation++;
    final requestedTopic = _selected ?? widget.topicId;
    setState(() {
      _loading = true;
      _failed = false;
      _notice = null;
    });
    try {
      final guide = await _service.load(
        _language == 'auto' ? _appLanguage! : _language,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _guide = guide;
        _selected =
            guide.topic(requestedTopic ?? '')?.id ?? guide.topics.first.id;
        if (requestedTopic != null && guide.topic(requestedTopic) == null) {
          _notice = 'unavailableTopic';
        }
        _loading = false;
      });
      _resetScroll();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
        _guide = null;
      });
    }
  }

  void _resetScroll() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _select(String id) {
    setState(() {
      _selected = id;
      _notice = null;
      _navigation++;
    });
    _resetScroll();
  }

  Future<void> _link(String? href) async {
    if (href == null || _guide == null) return;
    final topic = HelpGuideService.internalTopic(href, _guide!);
    if (topic != null) {
      _search.clear();
      _select(topic);
      return;
    }
    final generation = _generation, navigation = _navigation;
    final uri = HelpGuideService.externalLink(href);
    var opened = false;
    if (uri != null) {
      try {
        opened =
            await (widget.openLink?.call(uri) ??
                launchUrl(uri, mode: LaunchMode.externalApplication));
      } catch (_) {
        /* Show a localized failure only in its original view. */
      }
    }
    if (mounted &&
        generation == _generation &&
        navigation == _navigation &&
        !opened) {
      setState(() => _notice = 'linkUnavailable');
    }
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = HelpGuideStrings(context);
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 720;
    final query = _search.text.trim().toLowerCase();
    final topics = _visibleTopics;
    final selected = _visibleTopic;

    Widget topicChooser() => DropdownButtonFormField<String>(
      key: ValueKey('help-topics-${_guide?.language}-$query-${selected?.id}'),
      initialValue: selected?.id,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: strings.text('topics'),
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final topic in topics)
          DropdownMenuItem(
            value: topic.id,
            child: Text(
              topic.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) _select(value);
      },
    );

    Widget reader({bool embedded = false}) {
      if (selected == null) {
        return Center(child: Text(strings.text('noResults')));
      }
      final key = ValueKey('help-content-${_guide?.language}-${selected.id}');
      final data = '## ${selected.title}\n\n${selected.markdown}';
      return Directionality(
        textDirection: TextDirection.ltr,
        child: embedded
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: MarkdownBody(
                  key: key,
                  selectable: true,
                  data: data,
                  onTapLink: (_, href, _) => unawaited(_link(href)),
                ),
              )
            : Markdown(
                key: key,
                controller: _scroll,
                selectable: true,
                padding: const EdgeInsets.all(16),
                data: data,
                onTapLink: (_, href, _) => unawaited(_link(href)),
              ),
      );
    }

    Widget failure() => Column(
      children: [
        Text(strings.text('unavailable')),
        TextButton(
          onPressed: () => unawaited(_load()),
          child: Text(strings.text('retry')),
        ),
      ],
    );

    final header = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              strings.text('title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            key: const ValueKey('help-close-icon'),
            tooltip: strings.text('close'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: const ValueKey('help-language'),
        initialValue: _language,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: strings.text('language'),
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem(
            value: 'auto',
            child: Text(strings.text('automatic')),
          ),
          const DropdownMenuItem(value: 'en', child: Text('English')),
          const DropdownMenuItem(value: 'de', child: Text('Deutsch')),
          const DropdownMenuItem(value: 'fr', child: Text('Français')),
        ],
        onChanged: (value) {
          if (value != null) _changeLanguage(value);
        },
      ),
      const SizedBox(height: 8),
      if (!_loading && !_failed) ...[
        TextField(
          key: const ValueKey('help-search'),
          controller: _search,
          onChanged: (_) => setState(() {
            _navigation++;
            _notice = null;
          }),
          decoration: InputDecoration(
            labelText: strings.text('search'),
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (_guide?.fallback != null || _notice != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 110),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_guide?.fallback case final reason?)
                  Text(
                    strings.text(reason.name),
                    key: const ValueKey('help-fallback'),
                  ),
                if (_notice != null)
                  Text(
                    strings.text(_notice!),
                    key: const ValueKey('help-notice'),
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
    ];
    final footer = Align(
      alignment: AlignmentDirectional.centerEnd,
      child: TextButton(
        key: const ValueKey('help-close'),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(strings.text('close')),
      ),
    );

    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 8 : 24),
      child: SizedBox(
        width: math.min(1040, size.width - 16),
        height: math.min(800, size.height - 32),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final short =
                  constraints.maxHeight < (compact ? 540 : 440) * scale;
              if (short) {
                // The on-screen keyboard and short windows can leave less space
                // than the controls need. Let the entire topic surface scroll.
                return SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...header,
                      if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else if (_failed)
                        failure()
                      else ...[
                        if (topics.isNotEmpty) topicChooser(),
                        reader(embedded: true),
                      ],
                      footer,
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...header,
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _failed
                        ? SingleChildScrollView(child: failure())
                        : compact
                        ? Column(
                            children: [
                              if (topics.isNotEmpty) topicChooser(),
                              const SizedBox(height: 8),
                              Expanded(child: reader()),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 240,
                                child: ListView(
                                  children: [
                                    for (final topic in topics)
                                      ListTile(
                                        key: ValueKey('help-topic-${topic.id}'),
                                        selected: topic.id == selected?.id,
                                        title: Text(topic.title),
                                        onTap: () => _select(topic.id),
                                      ),
                                  ],
                                ),
                              ),
                              const VerticalDivider(width: 1),
                              Expanded(child: reader()),
                            ],
                          ),
                  ),
                  footer,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
