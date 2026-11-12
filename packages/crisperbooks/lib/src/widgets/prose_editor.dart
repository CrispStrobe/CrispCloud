import 'dart:async';
import 'dart:math' as math;

import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:flutter/material.dart';

String _identity(String value) => value;

/// Edits existing text-node values, retaining their formatting and protected
/// neighbors. A failed application leaves the dialog and all typed text intact.
class EbookProseEditorDialog extends StatefulWidget {
  const EbookProseEditorDialog({
    super.key,
    required this.block,
    required this.onApply,
    this.onPlainTextApply,
    this.translate = _identity,
    this.errorMessage,
  });

  final EpubStructuredProseBlock block;
  final FutureOr<void> Function(Map<int, String> replacements) onApply;
  final FutureOr<void> Function(String text)? onPlainTextApply;
  final String Function(String value) translate;
  final String Function(Object error)? errorMessage;

  @override
  State<EbookProseEditorDialog> createState() => _EbookProseEditorDialogState();
}

class _EbookProseEditorDialogState extends State<EbookProseEditorDialog> {
  late final EpubStructuredProseBlock _block;
  late final bool _plainMode;
  TextEditingController? _plainText;
  final _controllers = <int, TextEditingController>{};
  final _scroll = ScrollController();
  bool _applying = false;
  bool _stale = false;
  String? _error;

  String _tr(String value) => widget.translate(value);

  @override
  void initState() {
    super.initState();
    _block = widget.block;
    _plainMode =
        _block.allowsLineBreakEditing && widget.onPlainTextApply != null;
    if (_plainMode) {
      _plainText = TextEditingController(text: _block.text);
    } else {
      for (final segment in _block.segments.where(
        (segment) => segment.editable,
      )) {
        _controllers[segment.index] = TextEditingController(text: segment.text);
      }
    }
  }

  @override
  void didUpdateWidget(covariant EbookProseEditorDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.block.resourcePath != _block.resourcePath ||
        widget.block.resourceFingerprint != _block.resourceFingerprint ||
        widget.block.index != _block.index ||
        _plainMode !=
            (widget.block.allowsLineBreakEditing &&
                widget.onPlainTextApply != null)) {
      // Do not retarget typed text if a host replaces the paragraph snapshot.
      _stale = true;
      _error = _tr(
        'This paragraph changed. Copy your edits before reopening it.',
      );
    }
  }

  Map<int, String> get _changes => {
    for (final segment in _block.segments)
      if (segment.editable && _controllers[segment.index]!.text != segment.text)
        segment.index: _controllers[segment.index]!.text,
  };

  bool get _hasChanges =>
      _plainMode ? _plainText!.text != _block.text : _changes.isNotEmpty;

  Future<void> _apply() async {
    if (_applying || _stale) return;
    if (!_hasChanges) return;
    final changes = _plainMode
        ? const <int, String>{}
        : Map<int, String>.unmodifiable(_changes);
    final plainText = _plainText?.text;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      if (_plainMode) {
        await widget.onPlainTextApply!(plainText!);
      } else {
        await widget.onApply(changes);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = widget.errorMessage?.call(error) ?? error.toString(),
      );
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _plainText?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final available = media.size.height - media.viewInsets.bottom;
    final height = math.max(80.0, math.min(480.0, available * .60));
    return PopScope(
      canPop: !_applying,
      child: AlertDialog(
        title: Text(_tr(_plainMode ? 'Edit text' : 'Edit formatted text')),
        content: SizedBox(
          width: 640,
          height: height,
          child: ListView.builder(
            controller: _scroll,
            itemCount: _plainMode ? 2 : _block.segments.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _header(context);
              if (_plainMode) return _plainTextField();
              final segment = _block.segments[index - 1];
              return segment.editable
                  ? _textField(segment)
                  : _protectedItem(segment);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: _applying
                ? null
                : () => Navigator.of(context).pop(false),
            child: Text(_tr('Cancel')),
          ),
          FilledButton(
            onPressed: _applying || _stale || !_hasChanges ? null : _apply,
            child: Text(_tr('Apply')),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _tr(
          _plainMode ? 'Edit paragraph text. New lines become line breaks.' : 'Formatting and links are preserved. Edit source to change protected content.',
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              key: const ValueKey('ebook-prose-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      const SizedBox(height: 16),
      Text(_tr('Preview'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text.rich(
            TextSpan(children: _previewSpans(context)),
            key: const ValueKey('ebook-prose-preview'),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      const SizedBox(height: 18),
    ],
  );

  Widget _plainTextField() => TextField(
    key: const ValueKey('ebook-prose-plain-text'),
    controller: _plainText,
    enabled: !_applying,
    minLines: 4,
    maxLines: 10,
    keyboardType: TextInputType.multiline,
    decoration: InputDecoration(
      border: const OutlineInputBorder(),
      labelText: _tr('Text'),
    ),
    onChanged: (_) => setState(() {
      if (!_stale) _error = null;
    }),
  );

  Widget _textField(EpubProseSegment segment) {
    final labels = segment.marks.map((mark) => _tr(_markLabel(mark))).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        key: ValueKey('ebook-prose-segment-${segment.index}'),
        controller: _controllers[segment.index],
        enabled: !_applying,
        minLines: 1,
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        style: _textStyle(context, segment.marks),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: '${_tr('Text segment')} ${segment.index + 1}',
          helperText: labels.isEmpty ? null : labels.join(' · '),
          helperMaxLines: 2,
        ),
        onChanged: (_) => setState(() {
          if (!_stale) _error = null;
        }),
      ),
    );
  }

  Widget _protectedItem(EpubProseSegment segment) => Padding(
    key: ValueKey('ebook-prose-protected-${segment.index}'),
    padding: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.lock_outline, size: 20),
      title: Text(
        _tr(
          segment.kind == EpubProseSegmentKind.lineBreak
              ? 'Line break'
              : 'Protected content',
        ),
      ),
      subtitle: Text(
        segment.tag == null
            ? _previewSlice(segment.text, 160)
            : '${segment.tag}${segment.text.trim().isEmpty ? '' : ': ${_previewSlice(segment.text, 160)}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  List<InlineSpan> _previewSpans(BuildContext context) {
    if (_plainMode) {
      final text = _plainText!.text;
      return [
        TextSpan(
          text: '${_previewSlice(text, 4000)}${text.length > 4000 ? '…' : ''}',
        ),
      ];
    }
    final spans = <InlineSpan>[];
    var budget = 4000;
    for (final segment in _block.segments) {
      final value = segment.editable
          ? _controllers[segment.index]!.text
          : segment.text.isEmpty &&
                segment.kind == EpubProseSegmentKind.protectedContent
          ? '[${segment.tag ?? _tr('Protected content')}]'
          : segment.text;
      final text = _previewSlice(value, budget);
      spans.add(
        TextSpan(text: text, style: _textStyle(context, segment.marks)),
      );
      budget -= text.length;
      if (budget <= 0 || text.length < value.length) {
        spans.add(const TextSpan(text: '…'));
        break;
      }
    }
    return spans;
  }
}

String _previewSlice(String value, int length) {
  var end = math.min(value.length, length);
  if (end > 0 &&
      end < value.length &&
      value.codeUnitAt(end - 1) >= 0xd800 &&
      value.codeUnitAt(end - 1) <= 0xdbff &&
      value.codeUnitAt(end) >= 0xdc00 &&
      value.codeUnitAt(end) <= 0xdfff) {
    end--;
  }
  return value.substring(0, end);
}

String _markLabel(EpubProseMark mark) => switch (mark) {
  EpubProseMark.bold => 'Bold',
  EpubProseMark.italic => 'Italic',
  EpubProseMark.underline => 'Underline',
  EpubProseMark.strikethrough => 'Strikethrough',
  EpubProseMark.code => 'Code',
  EpubProseMark.link => 'Link text',
  EpubProseMark.superscript => 'Superscript',
  EpubProseMark.subscript => 'Subscript',
};

TextStyle _textStyle(BuildContext context, Set<EpubProseMark> marks) =>
    TextStyle(
      fontWeight: marks.contains(EpubProseMark.bold) ? FontWeight.bold : null,
      fontStyle: marks.contains(EpubProseMark.italic) ? FontStyle.italic : null,
      fontFamily: marks.contains(EpubProseMark.code) ? 'monospace' : null,
      color: marks.contains(EpubProseMark.link)
          ? Theme.of(context).colorScheme.primary
          : null,
      decoration: TextDecoration.combine([
        if (marks.contains(EpubProseMark.underline) ||
            marks.contains(EpubProseMark.link))
          TextDecoration.underline,
        if (marks.contains(EpubProseMark.strikethrough))
          TextDecoration.lineThrough,
      ]),
    );
