import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/ssh_config_import_strings.dart';
import '../l10n/terminal_controls_strings.dart';
import '../models/ssh_config_import.dart';
import '../models/ssh_terminal_profile.dart';
import '../services/ssh_terminal_profiles.dart';

/// Imports only the explicitly selected, reviewed destinations. It does not
/// connect, read key paths, load Include files or execute configuration text.
class SshConfigImportDialog extends StatefulWidget {
  const SshConfigImportDialog({super.key, required this.store});
  final SshTerminalProfiles store;

  @override
  State<SshConfigImportDialog> createState() => _SshConfigImportDialogState();
}

class _SshConfigImportDialogState extends State<SshConfigImportDialog> {
  final _source = TextEditingController();
  final _username = TextEditingController();
  final _names = <String, TextEditingController>{};
  final _selected = <String>{};
  Set<String> _existing = {};
  SshConfigImportResult? _result;
  bool _busy = false;
  bool _inputRejected = false;
  String? _error;

  @override
  void dispose() {
    _source.dispose();
    _username.dispose();
    for (final controller in _names.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _invalidate(String _) {
    setState(() {
      _clearPreview();
      _error = null;
      _inputRejected = false;
    });
  }

  void _clearPreview() {
    _result = null;
    _selected.clear();
    for (final controller in _names.values) {
      controller.dispose();
    }
    _names.clear();
  }

  TextEditingValue _boundedEdit(
    TextEditingValue oldValue,
    TextEditingValue value,
  ) {
    if (value.text.length <= SshConfigImport.maxCharacters) return value;
    // Reject the complete edit. Truncating a paste could silently omit a route
    // or a matching Host block and produce a different destination.
    setState(() {
      _clearPreview();
      _inputRejected = true;
    });
    return oldValue;
  }

  String _uniqueName(String alias, Set<String> used) {
    final base = alias.length > 80 ? alias.substring(0, 80) : alias;
    if (used.add(base)) return base;
    for (var index = 1; ; index++) {
      final suffix = ' ($index)';
      final prefix = base.length + suffix.length > 80
          ? base.substring(0, 80 - suffix.length)
          : base;
      final name = '$prefix$suffix';
      if (used.add(name)) return name;
    }
  }

  Future<void> _preview() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.store.load();
      if (!mounted) return;
      final result = SshConfigImport.parse(
        _source.text,
        defaultUsername: _username.text.trim(),
      );
      setState(() {
        _existing = saved.map((profile) => profile.name).toSet();
        _selected.clear();
        for (final controller in _names.values) {
          controller.dispose();
        }
        _names.clear();
        final used = _existing.toSet();
        for (final entry in result.entries.where((entry) => entry.canImport)) {
          _names[entry.alias] = TextEditingController(
            text: _uniqueName(entry.alias, used),
          );
        }
        _result = result;
        _inputRejected = false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load SSH profiles.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _nameError(String alias) {
    final value = _names[alias]!.text.trim();
    if (!SshTerminalProfile.isValidName(value)) {
      return 'Enter a unique profile name from 1 to 80 characters.';
    }
    if (_existing.contains(value)) {
      return 'A profile with this name already exists.';
    }
    if (_selected.contains(alias) &&
        _selected.any(
          (other) => other != alias && _names[other]!.text.trim() == value,
        )) {
      return 'Enter a unique profile name from 1 to 80 characters.';
    }
    return null;
  }

  bool get _overCapacity =>
      _existing.length + _selected.length > SshTerminalProfiles.maxProfiles;
  bool get _canSave =>
      !_busy &&
      !_inputRejected &&
      _selected.isNotEmpty &&
      !_overCapacity &&
      _selected.every((alias) => _nameError(alias) == null);

  Future<void> _save() async {
    if (!_canSave) return;
    final additions = _result!.entries
        .where((entry) => _selected.contains(entry.alias))
        .map(
          (entry) => SshTerminalProfile(
            name: _names[entry.alias]!.text.trim(),
            config: entry.config!,
          ),
        )
        .toList();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The store repeats collision/capacity checks under its mutation lock,
      // so another tab cannot race this preview into overwriting a profile.
      await widget.store.addAllNew(additions);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not import profiles. Check names and available space, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _diagnostic(SshConfigImportDiagnostic diagnostic) {
    final line = diagnostic.lineNumber > 0
        ? '${context.sshConfigImportTr('Line')} ${diagnostic.lineNumber}: '
        : '';
    final option = diagnostic.directive.isEmpty
        ? ''
        : ' (${diagnostic.directive})';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$line${context.sshConfigImportTr(diagnostic.message)}$option',
        style: TextStyle(
          color: diagnostic.severity == SshConfigImportSeverity.error
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      ),
    );
  }

  Widget _entry(SshConfigImportEntry entry) {
    final config = entry.config;
    return Card(
      key: ValueKey('ssh-config-entry-${entry.alias}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              key: ValueKey('ssh-config-select-${entry.alias}'),
              contentPadding: EdgeInsets.zero,
              title: Text(entry.alias),
              value: _selected.contains(entry.alias),
              onChanged: _busy || !entry.canImport
                  ? null
                  : (selected) => setState(() {
                      if (selected == true) {
                        _selected.add(entry.alias);
                      } else {
                        _selected.remove(entry.alias);
                      }
                    }),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (config != null) ...[
              SelectableText(
                '${config.username}@${config.host}:${config.port}',
              ),
              if (config.jumpHosts.isNotEmpty)
                Text(
                  '${context.sshConfigImportTr('Via')}: ${config.jumpHosts.map((jump) => '${jump.username}@${jump.host}:${jump.port}').join(' → ')}',
                ),
              const SizedBox(height: 8),
              TextField(
                key: ValueKey('ssh-config-name-${entry.alias}'),
                controller: _names[entry.alias],
                enabled: !_busy,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.terminalControlsTr('Profile name'),
                  errorText: _nameError(entry.alias) == null
                      ? null
                      : context.sshConfigImportTr(_nameError(entry.alias)!),
                ),
              ),
            ],
            if (entry.identityFileHints.isNotEmpty) ...[
              Text(
                context.sshConfigImportTr(
                  'IdentityFile paths are hints only; choose the key when connecting.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final hint in entry.identityFileHints)
                SelectableText(
                  '${hint.alias}: ${hint.path}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            for (final diagnostic in entry.diagnostics) _diagnostic(diagnostic),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(context.sshConfigImportTr('Import OpenSSH config')),
      content: SizedBox(
        width: 620,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.sshConfigImportTr(
                    'Profiles are saved disconnected. Passwords and key files are requested when connecting.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('ssh-config-source'),
                  controller: _source,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 7,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [
                    TextInputFormatter.withFunction(_boundedEdit),
                  ],
                  onChanged: _invalidate,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: context.sshConfigImportTr('Paste SSH config'),
                    errorText: _inputRejected
                        ? context.sshConfigImportTr(
                            'Input is too long. Nothing was pasted.',
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('ssh-config-default-user'),
                  controller: _username,
                  enabled: !_busy,
                  maxLength: 128,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: _invalidate,
                  decoration: InputDecoration(
                    labelText: context.sshConfigImportTr('Default username'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('ssh-config-preview'),
                    onPressed: _busy ? null : _preview,
                    child: Text(context.sshConfigImportTr('Preview')),
                  ),
                ),
                if (_error != null)
                  Text(
                    context.sshConfigImportTr(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_result case final result?) ...[
                  for (final diagnostic in result.diagnostics)
                    _diagnostic(diagnostic),
                  if (result.entries.isNotEmpty) ...[
                    Text(
                      context.sshConfigImportTr('Select aliases to import.'),
                    ),
                    Text(
                      context.sshConfigImportTr(
                        'Existing profile names are kept. Review the new names before importing.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  for (final entry in result.entries) _entry(entry),
                  if (_overCapacity)
                    Text(
                      context.sshConfigImportTr(
                        'The selection exceeds the 50-profile limit.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.terminalControlsTr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('ssh-config-import'),
          onPressed: _canSave ? _save : null,
          child: Text(context.sshConfigImportTr('Import selected')),
        ),
      ],
    ),
  );
}
