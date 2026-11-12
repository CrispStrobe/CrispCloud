import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../l10n/email_viewer_strings.dart';
import '../services/email_message_service.dart';

/// A saved-message preview. Attachments open through the host's bounded viewer;
/// this widget never follows email links or loads remote content.
class EmailMessageView extends StatefulWidget {
  const EmailMessageView({
    super.key,
    required this.message,
    this.fontScale = 1,
    this.onOpenAttachment,
  });

  final EmailMessageDocument message;
  final double fontScale;
  final ValueChanged<EmailAttachment>? onOpenAttachment;

  @override
  State<EmailMessageView> createState() => _EmailMessageViewState();
}

class _EmailMessageViewState extends State<EmailMessageView> {
  bool _formatted = true;

  @override
  Widget build(BuildContext context) {
    final strings = EmailViewerStrings(context);
    final message = widget.message;
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14 * widget.fontScale,
      height: 1.5,
    );
    final showHtml = _formatted && message.safeHtml != null;
    return SelectionArea(
      child: ListView(
        key: const ValueKey('email-message-view'),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            message.subject.isEmpty
                ? strings.text('noSubject')
                : message.subject,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 23 * widget.fontScale,
            ),
          ),
          const SizedBox(height: 16),
          for (final header in [
            ('from', message.from),
            ('to', message.to),
            ('cc', message.cc),
            ('bcc', message.bcc),
            ('date', message.date),
          ])
            if (header.$2.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        strings.text(header.$1),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Expanded(child: Text(header.$2, style: textStyle)),
                  ],
                ),
              ),
          if (message.attachments.isNotEmpty) ...[
            const Divider(height: 28),
            Text(
              '${strings.text('attachments')} (${message.attachments.length})',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final attachment in message.attachments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(attachment.name),
                subtitle: Text(
                  attachment.bytes == null
                      ? strings.text('embedded')
                      : '${attachment.contentType} · ${_size(attachment.bytes!.length)}',
                ),
                trailing:
                    attachment.bytes != null && widget.onOpenAttachment != null
                    ? IconButton(
                        tooltip: strings.text('openAttachment'),
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => widget.onOpenAttachment!(attachment),
                      )
                    : null,
                onTap:
                    attachment.bytes != null && widget.onOpenAttachment != null
                    ? () => widget.onOpenAttachment!(attachment)
                    : null,
              ),
          ],
          for (final warning in message.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                strings.warning(warning),
                style: textStyle.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const Divider(height: 28),
          if (message.safeHtml != null) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(strings.text('text')),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(strings.text('formatted')),
                  ),
                ],
                selected: {_formatted},
                onSelectionChanged: (selection) =>
                    setState(() => _formatted = selection.single),
              ),
            ),
            const SizedBox(height: 10),
            Text(strings.text('safeHtml'), style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
          ],
          if (showHtml)
            HtmlWidget(
              message.safeHtml!,
              textStyle: textStyle,
              onTapUrl: (_) => true,
              customWidgetBuilder: (element) =>
                  const {
                    'img',
                    'iframe',
                    'audio',
                    'video',
                    'object',
                    'embed',
                  }.contains(element.localName)
                  ? const SizedBox.shrink()
                  : null,
            )
          else
            Text(
              message.plainText.isEmpty
                  ? strings.text('emptyBody')
                  : message.plainText,
              style: textStyle,
            ),
        ],
      ),
    );
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}
