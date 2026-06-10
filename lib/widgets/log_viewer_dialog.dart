// lib/widgets/log_viewer_dialog.dart
//
// Live log viewer dialog. Shows structured log entries with filtering,
// level selection, auto-scroll, copy, and export.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../l10n/app_localizations.dart';
import '../services/log_service.dart';

void showLogViewerDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _LogViewerDialog(),
  );
}

class _LogViewerDialog extends StatefulWidget {
  const _LogViewerDialog();

  @override
  State<_LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<_LogViewerDialog> {
  StreamSubscription<LogEntry>? _sub;
  List<LogEntry> _entries = const [];
  final TextEditingController _filter = TextEditingController();
  LogLevel _minDisplay = LogLevel.debug;
  bool _autoScroll = true;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _entries = LogConfig.entries;
    _sub = LogConfig.stream.listen((e) {
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, e];
      });
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _filter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<LogEntry> get _visible {
    final q = _filter.text.trim().toLowerCase();
    return _entries.where((e) {
      if (e.level.index < _minDisplay.index) return false;
      if (q.isEmpty) return true;
      return e.message.toLowerCase().contains(q) ||
          e.logger.toLowerCase().contains(q) ||
          (e.error?.toString().toLowerCase().contains(q) ?? false);
    }).toList(growable: false);
  }

  Color _colorFor(LogLevel l) {
    return switch (l) {
      LogLevel.trace => Colors.blueGrey,
      LogLevel.debug => Colors.blue,
      LogLevel.info => Colors.teal,
      LogLevel.warn => Colors.orange,
      LogLevel.error => Colors.red,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final items = _visible;
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 800,
        height: 600,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(l.systemLogTitle(items.length)),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              PopupMenuButton<LogLevel>(
                tooltip: l.minimumLevel,
                icon: const Icon(Icons.filter_list),
                initialValue: _minDisplay,
                onSelected: (v) => setState(() => _minDisplay = v),
                itemBuilder: (_) => LogLevel.values
                    .map((lv) => PopupMenuItem(
                          value: lv,
                          child: Row(
                            children: [
                              Icon(Icons.circle, size: 10, color: _colorFor(lv)),
                              const SizedBox(width: 8),
                              Text(lv.name.toUpperCase()),
                            ],
                          ),
                        ))
                    .toList(),
              ),
              IconButton(
                tooltip: _autoScroll ? l.pauseAutoScroll : l.resumeAutoScroll,
                icon: Icon(_autoScroll ? Icons.pause : Icons.play_arrow),
                onPressed: () => setState(() => _autoScroll = !_autoScroll),
              ),
              PopupMenuButton<String>(
                onSelected: _action,
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'copy', child: Text(l.copyVisible)),
                  PopupMenuItem(value: 'copy_all', child: Text(l.copyAll)),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: 'clear', child: Text(l.clear)),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _filter,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: l.filterLogs,
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: items.length,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemBuilder: (context, i) {
                    final e = items[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: theme.colorScheme.onSurface,
                          ),
                          children: [
                            TextSpan(
                              text: '${_formatTime(e.timestamp)} ',
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            TextSpan(
                              text: e.level.name.toUpperCase().padRight(5),
                              style: TextStyle(
                                color: _colorFor(e.level),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: ' [${e.logger}] ',
                              style: const TextStyle(color: Colors.purple),
                            ),
                            TextSpan(text: e.message),
                            if (e.error != null)
                              TextSpan(
                                text: '  :: ${e.error}',
                                style: const TextStyle(color: Colors.red),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }

  Future<void> _action(String a) async {
    final l = AppLocalizations.of(context)!;
    switch (a) {
      case 'copy':
        final text = _visible.map((e) =>
            '${e.timestamp.toIso8601String()} ${e.level.name.toUpperCase()} [${e.logger}] ${e.message}'
            '${e.error != null ? ' :: ${e.error}' : ''}').join('\n');
        await Clipboard.setData(ClipboardData(text: text));
        _toast(l.visibleLinesCopied);
      case 'copy_all':
        await Clipboard.setData(ClipboardData(text: LogConfig.export()));
        _toast(l.allLogsCopied);
      case 'clear':
        LogConfig.clear();
        setState(() => _entries = const []);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
