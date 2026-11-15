import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm2/xterm.dart';

import '../l10n/terminal_controls_strings.dart';
import '../l10n/terminal_key_binding_strings.dart';
import '../l10n/terminal_strings.dart';
import '../models/terminal_key_binding.dart';
import '../providers/keyboard_shortcut_provider.dart';
import '../providers/terminal_key_bindings_provider.dart';
import '../services/keyboard_shortcut_service.dart';
import '../services/terminal_key_bindings.dart';

class TerminalKeyBindingsDialog extends ConsumerStatefulWidget {
  const TerminalKeyBindingsDialog({super.key});

  @override
  ConsumerState<TerminalKeyBindingsDialog> createState() =>
      _TerminalKeyBindingsDialogState();
}

class _TerminalKeyBindingsDialogState
    extends ConsumerState<TerminalKeyBindingsDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _edit(
    List<TerminalKeyBinding> bindings, [
    TerminalKeyBinding? binding,
  ]) async {
    if (_busy) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          EditTerminalKeyBindingDialog(binding: binding, existing: bindings),
    );
  }

  Future<void> _change(TerminalKeyBinding binding, {bool? enabled}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final store = ref.read(terminalKeyBindingsProvider);
      if (enabled == null) {
        await store.delete(binding.chord);
      } else {
        await store.save(
          binding.copyWith(enabled: enabled),
          replacing: binding.chord,
        );
      }
      if (!mounted) return;
      ref.invalidate(terminalKeyBindingListProvider);
      await ref.read(terminalKeyBindingListProvider.future);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = enabled == null
              ? 'Could not delete key binding.'
              : 'Could not save key binding.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(terminalKeyBindingListProvider);
    final bindings = state.valueOrNull;
    final error =
        _error ?? (state.hasError ? 'Could not load key bindings.' : null);
    return AlertDialog(
      title: Text(context.terminalKeyBindingTr('Key bindings')),
      content: SizedBox(
        width: 500,
        height: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.terminalKeyBindingTr(
                'Mappings are stored locally as plain text.',
              ),
            ),
            const SizedBox(height: 8),
            if (error != null)
              Text(
                context.terminalKeyBindingTr(error),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Expanded(
              child: bindings == null
                  ? state.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : const SizedBox.shrink()
                  : bindings.isEmpty
                  ? Center(
                      child: Text(
                        context.terminalKeyBindingTr('No key bindings'),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final binding in bindings)
                          ListTile(
                            key: ValueKey(
                              'terminal-key-binding-${binding.chord.storageId}',
                            ),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              binding.chord.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              binding.action == TerminalKeyBindingAction.text
                                  ? context
                                        .terminalKeyBindingTr(
                                          'Send text ({count} characters)',
                                        )
                                        .replaceAll(
                                          '{count}',
                                          '${binding.text!.length}',
                                        )
                                  : context
                                        .terminalKeyBindingTr('Send key: {key}')
                                        .replaceAll(
                                          '{key}',
                                          binding.keyDescription,
                                        ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: _busy
                                ? null
                                : () => unawaited(_edit(bindings, binding)),
                            trailing: SizedBox(
                              width: 96,
                              child: Row(
                                children: [
                                  Switch(
                                    key: ValueKey(
                                      'terminal-key-binding-enabled-${binding.chord.storageId}',
                                    ),
                                    value: binding.enabled,
                                    onChanged: _busy
                                        ? null
                                        : (value) => unawaited(
                                            _change(binding, enabled: value),
                                          ),
                                  ),
                                  Expanded(
                                    child: IconButton(
                                      tooltip: context.terminalControlsTr(
                                        'Delete',
                                      ),
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: _busy
                                          ? null
                                          : () => unawaited(_change(binding)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('terminal-add-key-binding'),
          onPressed:
              _busy ||
                  bindings == null ||
                  state.hasError ||
                  bindings.length >= TerminalKeyBindings.maximumBindings
              ? null
              : () => unawaited(_edit(bindings)),
          icon: const Icon(Icons.add),
          label: Text(context.terminalKeyBindingTr('Add binding')),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.terminalKeyBindingTr('Done')),
        ),
      ],
    );
  }
}

class EditTerminalKeyBindingDialog extends ConsumerStatefulWidget {
  const EditTerminalKeyBindingDialog({
    super.key,
    this.binding,
    required this.existing,
  });

  final TerminalKeyBinding? binding;
  final List<TerminalKeyBinding> existing;

  @override
  ConsumerState<EditTerminalKeyBindingDialog> createState() =>
      _EditTerminalKeyBindingDialogState();
}

class _EditTerminalKeyBindingDialogState
    extends ConsumerState<EditTerminalKeyBindingDialog> {
  final _captureFocus = FocusNode(debugLabel: 'Record terminal shortcut');
  final _text = TextEditingController();
  final _form = GlobalKey<FormState>();
  TerminalKeyChord? _chord;
  TerminalKeyBindingAction _action = TerminalKeyBindingAction.text;
  TerminalKey _key = TerminalKey.escape;
  bool _ctrl = false;
  bool _alt = false;
  bool _shift = false;
  bool _meta = false;
  bool _enabled = true;
  bool _recording = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final binding = widget.binding;
    if (binding != null) {
      _chord = binding.chord;
      _action = binding.action;
      _text.text = binding.text ?? '';
      _key = binding.key ?? TerminalKey.escape;
      _ctrl = binding.ctrl;
      _alt = binding.alt;
      _shift = binding.shift;
      _meta = binding.meta;
      _enabled = binding.enabled;
    }
    _captureFocus.addListener(() {
      if (!_captureFocus.hasFocus && _recording && mounted) {
        setState(() => _recording = false);
      }
    });
  }

  bool get _apple =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  KeyEventResult _capture(FocusNode node, KeyEvent event) {
    if (!_recording || _saving) return KeyEventResult.ignored;
    if (event is! KeyDownEvent || event.synthesized) {
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isShiftPressed) {
      setState(() => _recording = false);
      return KeyEventResult.handled;
    }
    if (!TerminalKeyChord.isBindableKey(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    TerminalKeyChord chord;
    try {
      chord = TerminalKeyChord(
        keyId: event.logicalKey.keyId,
        ctrl: keyboard.isControlPressed,
        alt: keyboard.isAltPressed,
        shift: keyboard.isShiftPressed,
        meta: keyboard.isMetaPressed,
      );
    } on FormatException {
      setState(
        () => _error = 'Use Ctrl, Alt or Meta, or a function/navigation key.',
      );
      return KeyEventResult.handled;
    }
    final appAction = ref
        .read(keyboardShortcutServiceProvider)
        .resolveBrowser(
          event,
          isCtrl: chord.ctrl,
          isAlt: chord.alt,
          isShift: chord.shift,
          isMeta: chord.meta,
        );
    if (chord.isReserved(apple: _apple) ||
        appAction == ShortcutAction.terminal) {
      setState(
        () => _error = 'This shortcut is reserved for terminal controls.',
      );
    } else if (widget.existing.any(
      (binding) =>
          binding.chord == chord && binding.chord != widget.binding?.chord,
    )) {
      setState(() => _error = 'This shortcut already has a binding.');
    } else {
      setState(() {
        _chord = chord;
        _recording = false;
        _error = null;
      });
    }
    return KeyEventResult.handled;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_chord == null) {
      setState(() => _error = 'Choose a shortcut.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    if (_chord!.isReserved(apple: _apple)) {
      setState(
        () => _error = 'This shortcut is reserved for terminal controls.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _recording = false;
      _error = null;
    });
    try {
      final binding = TerminalKeyBinding(
        chord: _chord!,
        action: _action,
        enabled: _enabled,
        text: _action == TerminalKeyBindingAction.text ? _text.text : null,
        key: _action == TerminalKeyBindingAction.key ? _key : null,
        ctrl: _action == TerminalKeyBindingAction.key && _ctrl,
        alt: _action == TerminalKeyBindingAction.key && _alt,
        shift: _action == TerminalKeyBindingAction.key && _shift,
        meta: _action == TerminalKeyBindingAction.key && _meta,
      );
      await ref
          .read(terminalKeyBindingsProvider)
          .save(binding, replacing: widget.binding?.chord);
      if (!mounted) return;
      ref.invalidate(terminalKeyBindingListProvider);
      await ref.read(terminalKeyBindingListProvider.future);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save key binding.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(
        context.terminalKeyBindingTr(
          widget.binding == null ? 'Add binding' : 'Edit key binding',
        ),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Focus(
                  focusNode: _captureFocus,
                  onKeyEvent: _capture,
                  child: OutlinedButton.icon(
                    key: const ValueKey('terminal-record-key-binding'),
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _recording = true;
                              _error = null;
                            });
                            _captureFocus.requestFocus();
                          },
                    icon: const Icon(Icons.keyboard),
                    label: Text(
                      _recording
                          ? context.terminalKeyBindingTr(
                              'Press a shortcut. Escape cancels.',
                            )
                          : _chord?.label ??
                                context.terminalKeyBindingTr('Record shortcut'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TerminalKeyBindingAction>(
                  key: const ValueKey('terminal-key-binding-action'),
                  initialValue: _action,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.terminalKeyBindingTr('Action'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: TerminalKeyBindingAction.text,
                      child: Text(context.terminalKeyBindingTr('Send text')),
                    ),
                    DropdownMenuItem(
                      value: TerminalKeyBindingAction.key,
                      child: Text(context.terminalKeyBindingTr('Send key')),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _action = value;
                              _error = null;
                            });
                          }
                        },
                ),
                const SizedBox(height: 12),
                if (_action == TerminalKeyBindingAction.text)
                  TextFormField(
                    key: const ValueKey('terminal-key-binding-text'),
                    controller: _text,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: TerminalKeyBinding.maximumTextLength,
                    decoration: InputDecoration(
                      labelText: context.terminalKeyBindingTr('Text'),
                      errorMaxLines: 3,
                    ),
                    validator: (value) =>
                        TerminalKeyBinding.isValidText(value ?? '')
                        ? null
                        : context.terminalKeyBindingTr(
                            'Enter 1–4096 characters. Use Send key for control keys.',
                          ),
                  )
                else ...[
                  DropdownButtonFormField<TerminalKey>(
                    key: const ValueKey('terminal-key-binding-key'),
                    initialValue: _key,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.terminalKeyBindingTr('Terminal key'),
                    ),
                    items: [
                      for (final key in TerminalKeyBinding.supportedKeys)
                        DropdownMenuItem(
                          value: key,
                          child: Text(TerminalKeyBinding.keyLabel(key)),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) setState(() => _key = value);
                          },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      FilterChip(
                        label: const Text('Ctrl'),
                        selected: _ctrl,
                        onSelected: _saving
                            ? null
                            : (v) => setState(() => _ctrl = v),
                      ),
                      FilterChip(
                        label: const Text('Alt'),
                        selected: _alt,
                        onSelected: _saving
                            ? null
                            : (v) => setState(() => _alt = v),
                      ),
                      FilterChip(
                        label: const Text('Shift'),
                        selected: _shift,
                        onSelected: _saving
                            ? null
                            : (v) => setState(() => _shift = v),
                      ),
                      FilterChip(
                        label: const Text('Meta'),
                        selected: _meta,
                        onSelected: _saving
                            ? null
                            : (v) => setState(() => _meta = v),
                      ),
                    ],
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.terminalKeyBindingTr('Enabled')),
                  value: _enabled,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
                Text(
                  context.terminalKeyBindingTr(
                    'Mappings run once per press. No Enter is added.',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.terminalKeyBindingTr(
                    'Mappings are stored locally as plain text.',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.terminalKeyBindingTr(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
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
          key: const ValueKey('terminal-save-key-binding'),
          onPressed: _saving ? null : () => unawaited(_save()),
          child: Text(context.terminalControlsTr('Save')),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _captureFocus.dispose();
    _text.dispose();
    super.dispose();
  }
}
