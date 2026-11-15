import 'package:flutter/material.dart';

import '../l10n/ssh_config_import_strings.dart';
import '../l10n/terminal_controls_strings.dart';
import '../l10n/terminal_strings.dart';
import '../models/ssh_terminal_config.dart';
import '../models/ssh_terminal_profile.dart';
import '../services/ssh_terminal_profiles.dart';
import 'ssh_config_import_dialog.dart';

class SshTerminalProfilesDialog extends StatefulWidget {
  const SshTerminalProfilesDialog({super.key, required this.store});
  final SshTerminalProfiles store;

  @override
  State<SshTerminalProfilesDialog> createState() =>
      _SshTerminalProfilesDialogState();
}

class _SshTerminalProfilesDialogState extends State<SshTerminalProfilesDialog> {
  late Future<List<SshTerminalProfile>> _profiles;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profiles = widget.store.load();
  }

  Future<void> _delete(SshTerminalProfile profile) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.delete(profile.name);
      if (mounted) setState(() => _profiles = widget.store.load());
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not delete SSH profile.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importConfig() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SshConfigImportDialog(store: widget.store),
      );
      if (mounted && saved == true) {
        setState(() {
          _profiles = widget.store.load();
          _error = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.terminalControlsTr('Saved SSH profiles')),
    content: SizedBox(
      width: 460,
      height: 340,
      child: FutureBuilder<List<SshTerminalProfile>>(
        future: _profiles,
        builder: (context, snapshot) => ListView(
          children: [
            Text(
              context.terminalControlsTr(
                'Connection settings are saved without passwords, private keys or passphrases.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('ssh-profiles-import-config'),
                onPressed: _busy ? null : _importConfig,
                icon: const Icon(Icons.file_download_outlined),
                label: Text(context.sshConfigImportTr('Import OpenSSH config')),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.terminalControlsTr(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            if (snapshot.hasError)
              Center(
                child: Text(
                  context.terminalControlsTr('Could not load SSH profiles.'),
                ),
              )
            else if (snapshot.data == null)
              const Center(child: CircularProgressIndicator())
            else if (snapshot.data!.isEmpty)
              Center(
                child: Text(
                  context.terminalControlsTr('No saved SSH profiles'),
                ),
              )
            else
              for (final profile in snapshot.data!)
                ListTile(
                  key: ValueKey('ssh-profile-${profile.name}'),
                  title: Text(profile.name),
                  subtitle: Text(_destination(profile.config)),
                  onTap: _busy
                      ? null
                      : () => Navigator.pop(
                          context,
                          profile.config.withoutSecrets(),
                        ),
                  trailing: IconButton(
                    tooltip: context.terminalControlsTr('Delete'),
                    onPressed: _busy ? null : () => _delete(profile),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(context.terminalTr('Cancel')),
      ),
    ],
  );

  String _destination(SshTerminalConfig config) {
    final session = config.tmux != null
        ? ' · tmux: ${config.tmux!.sessionName}'
        : config.screen != null
        ? ' · screen: ${config.screen!.sessionName}'
        : '';
    return '${config.username}@${config.host}:${config.port}$session';
  }
}

class SaveSshTerminalProfileDialog extends StatefulWidget {
  const SaveSshTerminalProfileDialog({
    super.key,
    required this.store,
    required this.config,
  });
  final SshTerminalProfiles store;
  final SshTerminalConfig config;

  @override
  State<SaveSshTerminalProfileDialog> createState() =>
      _SaveSshTerminalProfileDialogState();
}

class _SaveSshTerminalProfileDialogState
    extends State<SaveSshTerminalProfileDialog> {
  late final TextEditingController _name;
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = '${widget.config.username}@${widget.config.host}';
    _name = TextEditingController(
      text: initial.length > 80 ? initial.substring(0, 80) : initial,
    );
  }

  Future<void> _save() async {
    if (_saving || _form.currentState?.validate() != true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.save(
        SshTerminalProfile(name: _name.text.trim(), config: widget.config),
      );
      if (mounted) {
        setState(() {
          _saved = true;
          _saving = false;
        });
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save SSH profile.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving || _saved,
    child: AlertDialog(
      title: Text(context.terminalControlsTr('Save SSH profile')),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('ssh-profile-name'),
                  controller: _name,
                  autofocus: true,
                  maxLength: 80,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    labelText: context.terminalControlsTr('Profile name'),
                  ),
                  validator: (value) =>
                      SshTerminalProfile.isValidName(value ?? '')
                      ? null
                      : context.terminalControlsTr(
                          'Enter a name from 1 to 80 characters.',
                        ),
                  onFieldSubmitted: (_) => _save(),
                ),
                Text(
                  context.terminalControlsTr(
                    'Connection settings are saved without passwords, private keys or passphrases.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  context.terminalControlsTr(
                    'A profile with this name will be replaced.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      context.terminalControlsTr(_error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
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
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.terminalControlsTr('Save')),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }
}
