import 'package:flutter/material.dart';

import '../l10n/email_viewer_strings.dart';
import '../l10n/mbox_viewer_strings.dart';
import '../services/email_message_service.dart';
import '../services/mbox_message_service.dart';
import 'email_message_view.dart';

/// The host owns selection, lazy MIME parsing, search and clipboard state.
/// Only the selected message is decoded; all indexed messages are selectable.
class MboxMessageView extends StatelessWidget {
  const MboxMessageView({
    super.key,
    required this.document,
    required this.selectedIndex,
    required this.onSelectMessage,
    required this.onShowSource,
    this.message,
    this.messageError,
    this.fontScale = 1,
    this.onOpenAttachment,
  });

  final MboxDocument document;
  final int selectedIndex;
  final EmailMessageDocument? message;
  final MboxMessageError? messageError;
  final ValueChanged<int> onSelectMessage;
  final VoidCallback onShowSource;
  final double fontScale;
  final ValueChanged<EmailAttachment>? onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final strings = MboxViewerStrings(context);
    final entries = document.messages;
    final selected = selectedIndex >= 0 && selectedIndex < entries.length
        ? entries[selectedIndex]
        : null;
    final currentMessage = message;
    return LayoutBuilder(
      builder: (_, constraints) {
        final headerLimit = constraints.hasBoundedHeight
            ? (constraints.maxHeight * .45).clamp(0.0, 200.0)
            : 200.0;
        return Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: headerLimit),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          IconButton(
                            key: const ValueKey('mbox-previous'),
                            tooltip: strings.text('previous'),
                            onPressed: selected != null && selectedIndex > 0
                                ? () => onSelectMessage(selectedIndex - 1)
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text(
                            strings.position(
                              selected == null ? 0 : selectedIndex + 1,
                              entries.length,
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('mbox-next'),
                            tooltip: strings.text('next'),
                            onPressed:
                                selected != null &&
                                    selectedIndex + 1 < entries.length
                                ? () => onSelectMessage(selectedIndex + 1)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                          TextButton.icon(
                            key: const ValueKey('mbox-choose'),
                            onPressed: entries.isEmpty
                                ? null
                                : () async {
                                    final choice = await showDialog<int>(
                                      context: context,
                                      builder: (_) => _MboxMessageChooser(
                                        document: document,
                                        selectedIndex: selectedIndex,
                                      ),
                                    );
                                    if (!context.mounted || choice == null) {
                                      return;
                                    }
                                    final current = context.widget;
                                    if (current is MboxMessageView &&
                                        identical(current.document, document)) {
                                      current.onSelectMessage(choice);
                                    }
                                  },
                            icon: const Icon(Icons.list_alt),
                            label: Text(strings.text('chooseMessage')),
                          ),
                          TextButton.icon(
                            key: const ValueKey('mbox-source'),
                            onPressed: onShowSource,
                            icon: const Icon(Icons.code),
                            label: Text(strings.text('source')),
                          ),
                        ],
                      ),
                      Text(
                        strings.text('searchScope'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (selected != null)
                        Text(
                          strings.text(
                            selected.usesContentLength
                                ? 'contentLengthNotice'
                                : 'mboxrdNotice',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: currentMessage != null && selected != null
                  ? EmailMessageView(
                      key: ValueKey('mbox-message-${selected.index}'),
                      message: currentMessage,
                      fontScale: fontScale,
                      onOpenAttachment: onOpenAttachment,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        entries.isEmpty
                            ? strings.text('empty')
                            : strings.messageError(
                                messageError ?? MboxMessageError.invalidMessage,
                              ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _MboxMessageChooser extends StatefulWidget {
  const _MboxMessageChooser({
    required this.document,
    required this.selectedIndex,
  });

  final MboxDocument document;
  final int selectedIndex;

  @override
  State<_MboxMessageChooser> createState() => _MboxMessageChooserState();
}

class _MboxMessageChooserState extends State<_MboxMessageChooser> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final strings = MboxViewerStrings(context);
    final emailStrings = EmailViewerStrings(context);
    final entries = widget.document.messages
        .where((entry) {
          if (_query.isEmpty) return true;
          return entry.subject.toLowerCase().contains(_query) ||
              entry.from.toLowerCase().contains(_query);
        })
        .toList(growable: false);
    return AlertDialog(
      scrollable: true,
      title: Text(strings.text('chooseMessage')),
      content: SizedBox(
        width: 540,
        height: (MediaQuery.sizeOf(context).height * .5).clamp(160.0, 420.0),
        child: Column(
          children: [
            TextField(
              key: const ValueKey('mbox-message-search'),
              decoration: InputDecoration(
                labelText: strings.text('searchMessages'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text(strings.text('noMatches')))
                  : ListView.builder(
                      key: const ValueKey('mbox-message-list'),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          key: ValueKey('mbox-entry-${entry.index}'),
                          selected: entry.index == widget.selectedIndex,
                          title: Text(
                            '${entry.index + 1}. ${entry.subject.isEmpty ? emailStrings.text('noSubject') : _summary(entry.subject)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: entry.from.isEmpty && entry.date.isEmpty
                              ? null
                              : Text(
                                  [
                                    if (entry.from.isNotEmpty)
                                      _summary(entry.from),
                                    if (entry.date.isNotEmpty)
                                      _summary(entry.date),
                                  ].join('\n'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.of(context).pop(entry.index),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('close')),
        ),
      ],
    );
  }
}

String _summary(String text) {
  const maxUnits = 256;
  if (text.length <= maxUnits) return text;
  var end = maxUnits;
  final last = text.codeUnitAt(end - 1);
  if (last >= 0xd800 && last <= 0xdbff) end--;
  return '${text.substring(0, end)}…';
}
