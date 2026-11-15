import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/terminal_arrangement_strings.dart';
import '../l10n/terminal_controls_strings.dart';
import '../l10n/terminal_strings.dart';
import '../models/terminal_arrangement.dart';
import '../providers/terminal_arrangements_provider.dart';
import '../services/terminal_arrangements.dart';

class TerminalArrangementsDialog extends ConsumerStatefulWidget {
  const TerminalArrangementsDialog({super.key});

  @override
  ConsumerState<TerminalArrangementsDialog> createState() =>
      _TerminalArrangementsDialogState();
}

class _TerminalArrangementsDialogState
    extends ConsumerState<TerminalArrangementsDialog> {
  List<TerminalArrangement>? _arrangements;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(terminalArrangementsProvider).load();
      if (mounted) setState(() => _arrangements = items);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load arrangements.');
      }
    }
  }

  Future<void> _delete(TerminalArrangement arrangement) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.terminalArrangementTr('Delete arrangement?')),
          content: Text(arrangement.name),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.terminalTr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.terminalControlsTr('Delete')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await ref.read(terminalArrangementsProvider).delete(arrangement.name);
      if (!mounted) return;
      setState(() => _error = null);
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not delete arrangement.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _arrangements;
    return AlertDialog(
      title: Text(context.terminalArrangementTr('Saved arrangements')),
      content: SizedBox(
        width: 460,
        height: 320,
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  context.terminalArrangementTr(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: items == null
                  ? _error == null
                        ? const Center(child: CircularProgressIndicator())
                        : const SizedBox.shrink()
                  : items.isEmpty
                  ? Center(
                      child: Text(
                        context.terminalArrangementTr('No saved arrangements'),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final item in items)
                          ListTile(
                            key: ValueKey('terminal-arrangement-${item.name}'),
                            enabled: !_busy,
                            leading: const Icon(Icons.space_dashboard_outlined),
                            title: Text(item.name),
                            subtitle: Text(
                              context
                                  .terminalArrangementTr('Terminals: {count}')
                                  .replaceAll('{count}', '${item.tabs.length}'),
                            ),
                            onTap: _busy
                                ? null
                                : () => Navigator.pop(context, item),
                            trailing: IconButton(
                              tooltip: context.terminalControlsTr('Delete'),
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_delete(item)),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.terminalTr('Cancel')),
        ),
      ],
    );
  }
}

class SaveTerminalArrangementDialog extends ConsumerStatefulWidget {
  const SaveTerminalArrangementDialog({
    super.key,
    required this.createArrangement,
  });

  final TerminalArrangement Function(String name) createArrangement;

  @override
  ConsumerState<SaveTerminalArrangementDialog> createState() =>
      _SaveTerminalArrangementDialogState();
}

class _SaveTerminalArrangementDialogState
    extends ConsumerState<SaveTerminalArrangementDialog> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  Set<String>? _names;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final saved = await ref.read(terminalArrangementsProvider).load();
      if (mounted) {
        setState(() => _names = saved.map((item) => item.name).toSet());
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load arrangements.');
    }
  }

  Future<void> _save() async {
    if (_saving || _names == null || !_form.currentState!.validate()) return;
    final name = _name.text.trim();
    if (!_names!.contains(name) &&
        _names!.length >= TerminalArrangements.maxArrangements) {
      setState(() => _error = 'At most 20 arrangements can be saved.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final arrangement = widget.createArrangement(name);
      await ref.read(terminalArrangementsProvider).save(arrangement);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save arrangement.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.terminalArrangementTr('Save arrangement')),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const ValueKey('terminal-arrangement-name'),
                controller: _name,
                autofocus: true,
                enabled: !_saving,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: context.terminalArrangementTr('Arrangement name'),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1f\x7f]')),
                ],
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => unawaited(_save()),
                validator: (value) =>
                    TerminalArrangement.isValidName(value ?? '')
                    ? null
                    : context.terminalControlsTr(
                        'Enter a name from 1 to 80 characters.',
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                context.terminalArrangementTr(
                  'Only tab names, layout, text size and connection destinations are saved.',
                ),
              ),
              if (_names?.contains(_name.text.trim()) == true) ...[
                const SizedBox(height: 8),
                Text(
                  context.terminalArrangementTr(
                    'A saved arrangement with this name will be replaced.',
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  context.terminalArrangementTr(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_names == null && _error == null) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: Text(context.terminalTr('Cancel')),
      ),
      FilledButton(
        onPressed: _saving || _names == null ? null : () => unawaited(_save()),
        child: Text(context.terminalControlsTr('Save')),
      ),
    ],
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }
}
