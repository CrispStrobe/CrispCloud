import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/settings_strings.dart';
import '../providers/core_providers.dart';
import '../services/settings_backup_service.dart';

class SettingsBackupPanel extends ConsumerStatefulWidget {
  const SettingsBackupPanel({super.key});

  @override
  ConsumerState<SettingsBackupPanel> createState() =>
      _SettingsBackupPanelState();
}

class _SettingsBackupPanelState extends ConsumerState<SettingsBackupPanel> {
  bool _cloud = false;
  bool _credentials = false;
  bool _encrypted = false;
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() operation, String error) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await operation();
    } on SettingsRestoreException catch (failure) {
      if (mounted) {
        setState(
          () => _message = failure.rollbackFailed
              ? 'Restore failed and some changes could not be undone.'
              : error,
        );
      }
    } catch (_) {
      // Platform and parser errors can contain fields from the backup.
      if (mounted) setState(() => _message = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
    final s = SettingsStrings(context);
    final cloud = _cloud;
    final credentials = _credentials;
    final encrypt = _encrypted;
    final password = encrypt ? await _password(creating: true) : null;
    if (!mounted || (encrypt && password == null)) return;
    final storage = cloud || credentials
        ? ref.read(secureStorageProvider)
        : null;
    final prefs = await SharedPreferences.getInstance();
    final backup = await SettingsBackup.capture(
      prefs,
      storage: storage,
      includeCloud: cloud,
      includeCredentials: credentials,
    );
    final bytes = await backup.encode(password: password);
    if (!mounted) return;
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: s.text('Save settings file'),
      fileName: 'CrispCloud-settings.json',
      bytes: bytes,
    );
    if (mounted && saved != null) {
      setState(() => _message = 'Settings file saved.');
    }
  }, 'Could not save the settings file.');

  Future<void> _import() => _run(() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: false,
      withReadStream: true,
    );
    if (picked == null || !mounted) return;
    final bytes = await _readFile(picked.files.single);
    if (!mounted) return;
    final encrypted = SettingsBackup.isEncrypted(bytes);
    final password = encrypted ? await _password(creating: false) : null;
    if (!mounted || (encrypted && password == null)) return;
    final backup = await SettingsBackup.decode(bytes, password: password);
    if (!mounted) return;
    final options = await showDialog<(bool, bool)>(
      context: context,
      builder: (_) => _RestoreOptions(backup: backup),
    );
    if (!mounted || options == null) return;
    final (cloud, credentials) = options;
    final storage = cloud || credentials
        ? ref.read(secureStorageProvider)
        : null;
    final prefs = await SharedPreferences.getInstance();
    await backup.restore(
      prefs,
      storage: storage,
      includeCloud: cloud,
      includeCredentials: credentials,
    );
    if (mounted) {
      setState(
        () => _message = credentials && storage?.isPersistent == false
            ? 'Settings restored. Credentials are saved for this session only.'
            : 'Settings restored. Restart CrispCloud to apply them.',
      );
    }
  }, 'Could not load the settings file. Check the file and password.');

  Future<String?> _password({required bool creating}) => showDialog<String>(
    context: context,
    builder: (_) => _SettingsPassword(creating: creating),
  );

  static Future<Uint8List> _readFile(PlatformFile file) async {
    if (file.size > SettingsBackup.maxBytes) throw const FormatException();
    if (file.bytes case final bytes?
        when bytes.length <= SettingsBackup.maxBytes) {
      return bytes;
    }
    final stream = file.readStream;
    if (stream == null) throw const FormatException();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > SettingsBackup.maxBytes) {
        throw const FormatException();
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsStrings(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Text(
            s.text(
              'Save portable settings to a file or restore them from a backup.',
            ),
          ),
        ),
        CheckboxListTile(
          value: _cloud,
          title: Text(s.text('Include cloud provider settings')),
          subtitle: Text(
            s.text('Connection profiles and provider request options'),
          ),
          onChanged: _busy ? null : (value) => setState(() => _cloud = value!),
        ),
        CheckboxListTile(
          value: _credentials,
          title: Text(s.text('Include cloud credentials')),
          subtitle: Text(
            s.text('Saved logins, secret profile fields, and custom headers'),
          ),
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _credentials = value!;
                  if (_credentials) _encrypted = true;
                }),
        ),
        CheckboxListTile(
          value: _encrypted,
          title: Text(s.text('Encrypt settings file with a password')),
          onChanged: _busy
              ? null
              : (value) => setState(() => _encrypted = value!),
        ),
        if (_credentials && !_encrypted)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              s.text(
                'Anyone who can read this file can use the exported credentials.',
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.save_alt),
                label: Text(s.text('Save settings file')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.upload_file),
                label: Text(s.text('Load settings file')),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message case final message?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Semantics(liveRegion: true, child: Text(s.text(message))),
          ),
      ],
    );
  }
}

class _RestoreOptions extends StatefulWidget {
  const _RestoreOptions({required this.backup});
  final SettingsBackup backup;

  @override
  State<_RestoreOptions> createState() => _RestoreOptionsState();
}

class _RestoreOptionsState extends State<_RestoreOptions> {
  late bool _cloud = widget.backup.hasCloud;
  bool _credentials = false;

  @override
  Widget build(BuildContext context) {
    final s = SettingsStrings(context);
    return AlertDialog(
      title: Text(s.text('Restore settings')),
      scrollable: true,
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.text(
                'Matching settings and profiles will be updated. Other settings stay in place.',
              ),
            ),
            if (widget.backup.hasCloud)
              CheckboxListTile(
                value: _cloud,
                title: Text(s.text('Include cloud provider settings')),
                onChanged: (value) => setState(() => _cloud = value!),
              ),
            if (widget.backup.hasCredentials)
              CheckboxListTile(
                value: _credentials,
                title: Text(s.text('Include cloud credentials')),
                onChanged: (value) => setState(() => _credentials = value!),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.text('Cancel')),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, (_cloud, _credentials)),
          child: Text(s.text('Restore settings')),
        ),
      ],
    );
  }
}

class _SettingsPassword extends StatefulWidget {
  const _SettingsPassword({required this.creating});
  final bool creating;

  @override
  State<_SettingsPassword> createState() => _SettingsPasswordState();
}

class _SettingsPasswordState extends State<_SettingsPassword> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = FocusNode();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsStrings(context);
    return AlertDialog(
      title: Text(
        s.text(
          widget.creating
              ? 'Encrypt settings file with a password'
              : 'Unlock settings file',
        ),
      ),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _password,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(labelText: s.text('Password')),
                validator: (value) => value == null || value.isEmpty
                    ? s.text('Enter a password.')
                    : null,
                onFieldSubmitted: (_) =>
                    widget.creating ? _confirm.requestFocus() : _submit(),
              ),
              if (widget.creating)
                TextFormField(
                  focusNode: _confirm,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: s.text('Confirm password'),
                  ),
                  validator: (value) => value == _password.text
                      ? null
                      : s.text('Passwords do not match.'),
                  onFieldSubmitted: (_) => _submit(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.text('Cancel')),
        ),
        FilledButton(onPressed: _submit, child: Text(s.text('Continue'))),
      ],
    );
  }
}
