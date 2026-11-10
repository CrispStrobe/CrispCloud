import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/workspace_ux_strings.dart';
import '../providers/keyboard_shortcut_provider.dart';
import '../services/keyboard_shortcut_service.dart';

Future<void> showKeyboardShortcutSettings(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const KeyboardShortcutDialog(),
);

class KeyboardShortcutDialog extends ConsumerStatefulWidget {
  const KeyboardShortcutDialog({super.key});
  @override
  ConsumerState<KeyboardShortcutDialog> createState() => _KeyboardShortcutDialogState();
}

class _KeyboardShortcutDialogState extends ConsumerState<KeyboardShortcutDialog> {
  String _query = '';

  Future<void> _record(ShortcutAction action) async {
    final binding = await showDialog<ShortcutBinding>(
      context: context,
      builder: (_) => _RecordShortcutDialog(action: action),
    );
    if (!mounted || binding == null) return;
    await ref.read(shortcutBindingsProvider.notifier).setBinding(action, binding);
  }

  Future<void> _resetAll() async {
    final s = WorkspaceUxStrings(context);
    final l = AppLocalizations.of(context)!;
    final reset = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(s.text('resetAll')),
      content: Text(s.text('resetConfirm')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.text('reset'))),
      ],
    ));
    if (mounted && reset == true) await ref.read(shortcutBindingsProvider.notifier).resetAll();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(shortcutBindingsProvider);
    final service = ref.watch(keyboardShortcutServiceProvider);
    final s = WorkspaceUxStrings(context);
    final l = AppLocalizations.of(context)!;
    final actions = browserShortcutActions.where((action) =>
      '${s.action(action)} ${service.browserDisplay(action)}'.toLowerCase().contains(_query.toLowerCase())).toList();
    return AlertDialog(
      title: Text(s.text('customize')),
      content: SizedBox(
        width: 640,
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(labelText: s.text('search'), prefixIcon: const Icon(Icons.search)),
            onChanged: (query) => setState(() => _query = query),
          ),
          const SizedBox(height: 12),
          Expanded(child: ListView.builder(
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              return ListTile(
                key: ValueKey('shortcut-${action.name}'),
                title: Text(s.action(action)),
                subtitle: Text(service.browserDisplay(action), textDirection: TextDirection.ltr),
                onTap: () => _record(action),
                trailing: service.isCustomized(action) ? IconButton(
                  tooltip: s.text('reset'),
                  icon: const Icon(Icons.restart_alt),
                  onPressed: () => ref.read(shortcutBindingsProvider.notifier).resetBinding(action),
                ) : const Icon(Icons.keyboard_outlined),
              );
            },
          )),
        ]),
      ),
      actions: [
        TextButton(onPressed: _resetAll, child: Text(s.text('resetAll'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
      ],
    );
  }
}

class _RecordShortcutDialog extends ConsumerStatefulWidget {
  const _RecordShortcutDialog({required this.action});
  final ShortcutAction action;
  @override
  ConsumerState<_RecordShortcutDialog> createState() => _RecordShortcutDialogState();
}

class _RecordShortcutDialogState extends ConsumerState<_RecordShortcutDialog> {
  final _focus = FocusNode();
  ShortcutBinding? _binding;
  List<ShortcutAction> _conflicts = [];
  @override
  void dispose() { _focus.dispose(); super.dispose(); }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if ([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight,
        LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight,
        LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight,
        LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight].contains(key)) {
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final binding = ShortcutBinding(key: key.keyLabel,
        ctrl: keyboard.isControlPressed, meta: keyboard.isMetaPressed,
        shift: keyboard.isShiftPressed, alt: keyboard.isAltPressed);
    if (!binding.isValid) return KeyEventResult.handled;
    setState(() {
      _binding = binding;
      _conflicts = ref.read(keyboardShortcutServiceProvider).browserConflicts(widget.action, binding);
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final s = WorkspaceUxStrings(context);
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(s.action(widget.action)),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(s.text('recordHint')),
        const SizedBox(height: 16),
        Focus(autofocus: true, focusNode: _focus, onKeyEvent: _onKey,
          child: Semantics(button: true, label: s.text('record'),
            child: InkWell(onTap: _focus.requestFocus,
              child: Container(width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary), borderRadius: BorderRadius.circular(8)),
                child: Text(_binding?.toDisplayString() ?? s.text('record'), textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
        if (_conflicts.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text('${s.text('conflict')}: ${_conflicts.map(s.action).join(', ')}',
            style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: _binding != null && _conflicts.isEmpty
            ? () => Navigator.pop(context, _binding) : null, child: Text(l.save)),
      ],
    );
  }
}
