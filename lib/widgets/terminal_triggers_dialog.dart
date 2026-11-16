import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/terminal_trigger_strings.dart';
import '../models/terminal_trigger.dart';
import '../providers/terminal_triggers_provider.dart';
import '../services/terminal_triggers.dart';

class TerminalTriggersDialog extends ConsumerStatefulWidget {
  const TerminalTriggersDialog({super.key});

  @override
  ConsumerState<TerminalTriggersDialog> createState() =>
      _TerminalTriggersDialogState();
}

class _TerminalTriggersDialogState
    extends ConsumerState<TerminalTriggersDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _edit([TerminalTrigger? trigger]) async {
    if (_busy) return;
    await showDialog<void>(
      context: context,
      builder: (_) => EditTerminalTriggerDialog(trigger: trigger),
    );
  }

  Future<void> _change(TerminalTrigger trigger, {bool? enabled}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final store = ref.read(terminalTriggersProvider);
      if (enabled == null) {
        await store.delete(trigger.id);
      } else {
        await store.save(
          trigger.copyWith(enabled: enabled),
          replacing: trigger.id,
        );
      }
      if (!mounted) return;
      ref.invalidate(terminalTriggerListProvider);
      await ref.read(terminalTriggerListProvider.future);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save triggers.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(terminalTriggerListProvider);
    final triggers = state.valueOrNull;
    final error =
        _error ?? (state.hasError ? 'Could not load triggers.' : null);
    final listHeight = (MediaQuery.sizeOf(context).height * .35).clamp(
      72.0,
      340.0,
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(context.terminalTriggerTr('Output triggers')),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.terminalTriggerTr(
                  'Rules are stored locally as plain text.',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.terminalTriggerTr(
                  'Match completed output lines. Full-screen applications are ignored.',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  context.terminalTriggerTr(error),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: listHeight,
                child: triggers == null
                    ? state.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : const SizedBox.shrink()
                    : triggers.isEmpty
                    ? Center(
                        child: Text(
                          context.terminalTriggerTr('No output triggers'),
                        ),
                      )
                    : ListView.builder(
                        itemCount: triggers.length,
                        itemBuilder: (context, index) {
                          final trigger = triggers[index];
                          return Card(
                            key: ValueKey('terminal-trigger-${trigger.id}'),
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  title: Text(
                                    trigger.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    trigger.pattern,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: _busy
                                      ? null
                                      : () => unawaited(_edit(trigger)),
                                  trailing: Switch(
                                    key: ValueKey(
                                      'terminal-trigger-enabled-${trigger.id}',
                                    ),
                                    value: trigger.enabled,
                                    onChanged: _busy
                                        ? null
                                        : (value) => unawaited(
                                            _change(trigger, enabled: value),
                                          ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 10,
                                    right: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          context.terminalTriggerTr(
                                            trigger.action ==
                                                    TerminalTriggerAction.mark
                                                ? 'Add mark'
                                                : 'Notify in app',
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: context.terminalTriggerTr(
                                          'Edit trigger',
                                        ),
                                        onPressed: _busy
                                            ? null
                                            : () => unawaited(_edit(trigger)),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                          'terminal-trigger-delete-${trigger.id}',
                                        ),
                                        tooltip: context.terminalTriggerTr(
                                          'Delete',
                                        ),
                                        onPressed: _busy
                                            ? null
                                            : () => unawaited(_change(trigger)),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('terminal-add-trigger'),
            onPressed:
                _busy ||
                    triggers == null ||
                    state.hasError ||
                    triggers.length >= TerminalTriggers.maximumTriggers
                ? null
                : () => unawaited(_edit()),
            icon: const Icon(Icons.add),
            label: Text(context.terminalTriggerTr('Add trigger')),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(context.terminalTriggerTr('Done')),
          ),
        ],
      ),
    );
  }
}

class EditTerminalTriggerDialog extends ConsumerStatefulWidget {
  const EditTerminalTriggerDialog({super.key, this.trigger});
  final TerminalTrigger? trigger;

  @override
  ConsumerState<EditTerminalTriggerDialog> createState() =>
      _EditTerminalTriggerDialogState();
}

class _EditTerminalTriggerDialogState
    extends ConsumerState<EditTerminalTriggerDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pattern = TextEditingController();
  final _cooldown = TextEditingController(text: '5');
  final _sample = TextEditingController();
  late final String _id;
  TerminalTriggerMatchKind _kind = TerminalTriggerMatchKind.literal;
  TerminalTriggerAction _action = TerminalTriggerAction.notify;
  bool _enabled = true;
  bool _caseSensitive = true;
  bool _once = false;
  bool _saving = false;
  String? _error;
  String? _preview;

  @override
  void initState() {
    super.initState();
    final trigger = widget.trigger;
    _id =
        trigger?.id ??
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
    if (trigger != null) {
      _name.text = trigger.name;
      _pattern.text = trigger.pattern;
      _cooldown.text = '${trigger.cooldownSeconds}';
      _kind = trigger.matchKind;
      _action = trigger.action;
      _enabled = trigger.enabled;
      _caseSensitive = trigger.caseSensitive;
      _once = trigger.oncePerSession;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    _cooldown.dispose();
    _sample.dispose();
    super.dispose();
  }

  TerminalTrigger _value({bool preview = false}) => TerminalTrigger(
    id: _id,
    name: preview ? 'Preview' : _name.text.trim(),
    pattern: _pattern.text,
    matchKind: _kind,
    action: _action,
    enabled: preview || _enabled,
    caseSensitive: _caseSensitive,
    oncePerSession: !preview && _once,
    cooldownSeconds: preview
        ? 0
        : _once
        ? (int.tryParse(_cooldown.text) ?? 5).clamp(
            0,
            TerminalTrigger.maximumCooldownSeconds,
          )
        : int.parse(_cooldown.text),
  );

  String? _patternError(String? value) {
    if (!TerminalTrigger.validPattern(value ?? '')) {
      return context.terminalTriggerTr('Enter 1–256 printable characters.');
    }
    if (_kind == TerminalTriggerMatchKind.safePattern) {
      try {
        TerminalTriggerPattern(value!, caseSensitive: _caseSensitive);
      } on FormatException {
        return context.terminalTriggerTr(
          'Unsupported pattern. Use the syntax shown below.',
        );
      }
    }
    return null;
  }

  void _test() {
    final error = _patternError(_pattern.text);
    if (error != null) {
      setState(() {
        _preview = null;
        _error = 'Check the matching pattern.';
      });
      _form.currentState!.validate();
      return;
    }
    var matched = false;
    final engine = TerminalTriggerEngine(onMatch: (_) => matched = true);
    engine.updateTriggers([_value(preview: true)]);
    engine.addOutput(_sample.text);
    engine.finish();
    setState(() {
      _error = null;
      _preview = matched ? 'Pattern matches sample.' : 'No match in sample.';
    });
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(terminalTriggersProvider)
          .save(_value(), replacing: widget.trigger?.id);
      if (!mounted) return;
      ref.invalidate(terminalTriggerListProvider);
      await ref.read(terminalTriggerListProvider.future);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save triggers.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _changed() {
    if (_preview != null) setState(() => _preview = null);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        context.terminalTriggerTr(
          widget.trigger == null ? 'Add trigger' : 'Edit trigger',
        ),
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const ValueKey('terminal-trigger-name'),
                controller: _name,
                enabled: !_saving,
                maxLength: TerminalTrigger.maximumNameLength,
                decoration: InputDecoration(
                  labelText: context.terminalTriggerTr('Name'),
                  errorMaxLines: 3,
                ),
                validator: (value) => TerminalTrigger.validName(value ?? '')
                    ? null
                    : context.terminalTriggerTr(
                        'Enter a name of 1–80 characters.',
                      ),
              ),
              DropdownButtonFormField<TerminalTriggerMatchKind>(
                key: const ValueKey('terminal-trigger-kind'),
                initialValue: _kind,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.terminalTriggerTr('Match using'),
                ),
                items: [
                  DropdownMenuItem(
                    value: TerminalTriggerMatchKind.literal,
                    child: Text(context.terminalTriggerTr('Literal text')),
                  ),
                  DropdownMenuItem(
                    value: TerminalTriggerMatchKind.safePattern,
                    child: Text(context.terminalTriggerTr('Safe pattern')),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _kind = value;
                            _preview = null;
                          });
                        }
                      },
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('terminal-trigger-pattern'),
                controller: _pattern,
                enabled: !_saving,
                maxLength: TerminalTrigger.maximumPatternLength,
                decoration: InputDecoration(
                  labelText: context.terminalTriggerTr('Pattern'),
                  errorMaxLines: 4,
                ),
                validator: _patternError,
                onChanged: (_) => _changed(),
              ),
              if (_kind == TerminalTriggerMatchKind.safePattern)
                Text(
                  context.terminalTriggerTr(
                    r'Supports . [a-z] ^ $ ? * + and \d \s \w. No groups, alternatives or backreferences.',
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.terminalTriggerTr('Case sensitive')),
                value: _caseSensitive,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _caseSensitive = value;
                        _preview = null;
                      }),
              ),
              DropdownButtonFormField<TerminalTriggerAction>(
                key: const ValueKey('terminal-trigger-action'),
                initialValue: _action,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.terminalTriggerTr('Action'),
                ),
                items: [
                  DropdownMenuItem(
                    value: TerminalTriggerAction.notify,
                    child: Text(context.terminalTriggerTr('Notify in app')),
                  ),
                  DropdownMenuItem(
                    value: TerminalTriggerAction.mark,
                    child: Text(context.terminalTriggerTr('Add mark')),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _action = value);
                      },
              ),
              SwitchListTile(
                key: const ValueKey('terminal-trigger-once'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.terminalTriggerTr('Once per connection')),
                value: _once,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _once = value),
              ),
              TextFormField(
                key: const ValueKey('terminal-trigger-cooldown'),
                controller: _cooldown,
                enabled: !_saving && !_once,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  labelText: context.terminalTriggerTr('Cooldown (seconds)'),
                  errorMaxLines: 3,
                ),
                validator: (value) {
                  if (_once) return null;
                  final seconds = int.tryParse(value ?? '');
                  return seconds != null &&
                          seconds >= 0 &&
                          seconds <= TerminalTrigger.maximumCooldownSeconds
                      ? null
                      : context.terminalTriggerTr('Enter 0–3600 seconds.');
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.terminalTriggerTr('Enabled')),
                value: _enabled,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _enabled = value),
              ),
              const Divider(),
              TextFormField(
                key: const ValueKey('terminal-trigger-sample'),
                controller: _sample,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                maxLength: 2048,
                decoration: InputDecoration(
                  labelText: context.terminalTriggerTr('Sample output'),
                ),
                onChanged: (_) => _changed(),
              ),
              OutlinedButton.icon(
                key: const ValueKey('terminal-test-trigger'),
                onPressed: _saving ? null : _test,
                icon: const Icon(Icons.play_arrow),
                label: Text(context.terminalTriggerTr('Test pattern')),
              ),
              if (_preview != null)
                Text(
                  context.terminalTriggerTr(_preview!),
                  key: const ValueKey('terminal-trigger-preview'),
                ),
              const SizedBox(height: 8),
              Text(
                context.terminalTriggerTr(
                  'Rules are stored locally as plain text.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  context.terminalTriggerTr(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(context.terminalTriggerTr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('terminal-save-trigger'),
          onPressed: _saving ? null : () => unawaited(_save()),
          child: Text(context.terminalTriggerTr('Save')),
        ),
      ],
    ),
  );
}
