import 'package:flutter/material.dart';

import '../l10n/lrc_strings.dart';
import '../services/lrc_parser.dart';

// Bound individual layout work as well as the parser's total input. Complete
// text remains available through the host's ordinary source viewer.
const int _maxLineCodeUnits = 8192;
const int _maxWordDetails = 100;

String _displayText(String value, [int limit = _maxLineCodeUnits]) {
  if (value.length <= limit) return value;
  var end = limit;
  final last = value.codeUnitAt(end - 1);
  if (last >= 0xd800 && last <= 0xdbff) end--;
  return '${value.substring(0, end)}…';
}

/// Static, selectable LRC timeline. No links, markup, media or sidecars are
/// opened by the preview. The host retains the complete Text/Hex routes.
class LrcPreview extends StatefulWidget {
  const LrcPreview({
    super.key,
    required this.document,
    required this.onShowSource,
    this.fontScale = 1,
  });

  final LrcDocument document;
  final VoidCallback onShowSource;
  final double fontScale;

  @override
  State<LrcPreview> createState() => _LrcPreviewState();
}

class _LrcPreviewState extends State<LrcPreview> {
  bool _timeline = true;

  @override
  Widget build(BuildContext context) {
    final strings = LrcStrings(context);
    final document = widget.document;
    if (document.isTruncated) {
      return LrcPreviewUnavailable(
        message: strings.text('limit'),
        onShowSource: widget.onShowSource,
      );
    }
    final cues = _timeline
        ? [
            ...document.timedCues,
            ...document.cues.where((cue) => cue.timeMs == null),
          ]
        : document.cues;
    final metadataCount = document.metadata.length;
    final theme = Theme.of(context);
    return ListView.builder(
      key: ValueKey('lrc-rows-$_timeline'),
      padding: const EdgeInsets.all(12),
      itemCount: 1 + metadataCount + cues.length,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: Text(strings.text('timeline')),
                      selected: _timeline,
                      onSelected: (_) => setState(() => _timeline = true),
                    ),
                    ChoiceChip(
                      label: Text(strings.text('lyrics')),
                      selected: !_timeline,
                      onSelected: (_) => setState(() => _timeline = false),
                    ),
                    TextButton.icon(
                      key: const ValueKey('lrc-source'),
                      onPressed: widget.onShowSource,
                      icon: const Icon(Icons.code),
                      label: Text(strings.text('source')),
                    ),
                  ],
                ),
                Text(strings.timedLines(document.timedCues.length)),
                if (document.offsetMs != 0)
                  Text(strings.offset(document.offsetMs)),
                if (document.source.isEmpty)
                  Text(strings.text('empty'))
                else if (document.timedCues.isEmpty)
                  Text(strings.text('noTimedLines')),
              ],
            ),
          );
        }
        if (index <= metadataCount) {
          final metadata = document.metadata[index - 1];
          final value = '${metadata.key}: ${metadata.value}';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  _displayText(value),
                  style: TextStyle(
                    fontSize: 13 * widget.fontScale,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (value.length > _maxLineCodeUnits)
                  Text(strings.text('shortened')),
              ],
            ),
          );
        }
        final cue = cues[index - metadataCount - 1];
        return _LrcCueTile(
          key: ValueKey('lrc-cue-${cue.sourceOrder}'),
          cue: cue,
          showTiming: _timeline,
          fontScale: widget.fontScale,
        );
      },
    );
  }
}

class _LrcCueTile extends StatelessWidget {
  const _LrcCueTile({
    super.key,
    required this.cue,
    required this.showTiming,
    required this.fontScale,
  });

  final LrcCue cue;
  final bool showTiming;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final strings = LrcStrings(context);
    final theme = Theme.of(context);
    final hasWordTiming = cue.words.any((word) => word.timeMs != null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTiming || cue.role != null)
            Wrap(
              spacing: 12,
              children: [
                if (showTiming)
                  Text(
                    cue.timeMs == null
                        ? strings.text('untimed')
                        : formatLrcTimestamp(cue.timeMs!),
                    textDirection: cue.timeMs == null
                        ? null
                        : TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 12 * fontScale,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                if (cue.role != null) Text('${cue.role}:'),
              ],
            ),
          SelectableText(
            _displayText(cue.text),
            style: TextStyle(fontSize: 15 * fontScale, height: 1.4),
          ),
          if (cue.text.length > _maxLineCodeUnits)
            Text(strings.text('shortened')),
          if (showTiming && hasWordTiming)
            ExpansionTile(
              key: PageStorageKey('lrc-words-${cue.sourceOrder}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(strings.text('wordTiming')),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final word in cue.words.take(_maxWordDetails))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              word.timeMs == null
                                  ? strings.text('untimed')
                                  : formatLrcTimestamp(word.timeMs!),
                              textDirection: word.timeMs == null
                                  ? null
                                  : TextDirection.ltr,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11 * fontScale,
                              ),
                            ),
                            Text(_displayText(word.text, 128)),
                          ],
                        ),
                    ],
                  ),
                ),
                if (cue.words.length > _maxWordDetails ||
                    cue.words.any((word) => word.text.length > 128))
                  Text(strings.text('shortened')),
              ],
            ),
        ],
      ),
    );
  }
}

class LrcPreviewUnavailable extends StatelessWidget {
  const LrcPreviewUnavailable({
    super.key,
    required this.message,
    required this.onShowSource,
  });

  final String message;
  final VoidCallback onShowSource;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 12),
        TextButton.icon(
          key: const ValueKey('lrc-source'),
          onPressed: onShowSource,
          icon: const Icon(Icons.code),
          label: Text(LrcStrings(context).text('source')),
        ),
      ],
    ),
  );
}
