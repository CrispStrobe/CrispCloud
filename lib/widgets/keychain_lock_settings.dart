import 'package:flutter/material.dart';

import '../l10n/settings_strings.dart';
import '../services/macos_keychain_lock_settings.dart';
import '../services/secure_storage_macos_keychain.dart';

/// Controls only the active selected file keychain. Its OS settings are the
/// persistent source of truth, including changes made in Keychain Access.
class KeychainLockSettings extends StatefulWidget {
  const KeychainLockSettings({super.key, required this.storage});
  final MacOsCustomKeychainStorage storage;

  @override
  State<KeychainLockSettings> createState() => _KeychainLockSettingsState();
}

class _KeychainLockSettingsState extends State<KeychainLockSettings> {
  late Future<MacOsKeychainLockSettings> _settings = widget.storage
      .readLockSettings();
  bool _saving = false;
  bool _saveFailed = false;
  int _revision = 0;

  @override
  void didUpdateWidget(KeychainLockSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.storage, widget.storage)) {
      _revision++;
      _saving = false;
      _saveFailed = false;
      _settings = widget.storage.readLockSettings();
    }
  }

  void _retry() {
    widget.storage.allowUnlockRetry();
    setState(() {
      _revision++;
      _saveFailed = false;
      _settings = widget.storage.readLockSettings(unlockIfNeeded: true);
    });
  }

  Future<void> _save(MacOsKeychainLockSettings value) async {
    if (_saving) return;
    final revision = _revision;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      final saved = await widget.storage.writeLockSettings(value);
      if (mounted && revision == _revision) {
        setState(() {
          _settings = Future.value(saved);
        });
      }
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _saveFailed = true);
    } finally {
      if (mounted && revision == _revision) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsStrings(context);
    return FutureBuilder<MacOsKeychainLockSettings>(
      future: _settings,
      builder: (context, snapshot) {
        if (snapshot.hasError || _saveFailed) {
          return ListTile(
            title: Text(
              s.text('Could not read or update keychain lock settings.'),
            ),
            trailing: TextButton(
              onPressed: _retry,
              child: Text(s.text('Retry')),
            ),
          );
        }
        final settings = snapshot.data;
        if (settings == null) return const LinearProgressIndicator();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: const ValueKey('keychain-lock-on-sleep'),
              title: Text(s.text('Lock keychain when the Mac sleeps')),
              value: settings.lockOnSleep,
              onChanged: _saving
                  ? null
                  : (value) => _save(settings.copyWith(lockOnSleep: value)),
            ),
            SwitchListTile(
              key: const ValueKey('keychain-lock-after-inactivity'),
              title: Text(s.text('Lock keychain after inactivity')),
              value: settings.lockAfterInactivity,
              onChanged: _saving
                  ? null
                  : (value) =>
                        _save(settings.copyWith(lockAfterInactivity: value)),
            ),
            if (settings.lockAfterInactivity)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<int>(
                  key: ValueKey(
                    'keychain-idle-seconds-${settings.idleSeconds}',
                  ),
                  initialValue: settings.idleSeconds,
                  decoration: InputDecoration(
                    labelText: s.text('Inactivity timeout'),
                  ),
                  items:
                      ({300, 900, 1800, 3600, settings.idleSeconds}.toList()
                            ..sort())
                          .map(
                            (seconds) => DropdownMenuItem(
                              value: seconds,
                              child: Text(
                                seconds % 60 == 0
                                    ? s
                                          .text('{minutes} minutes')
                                          .replaceAll(
                                            '{minutes}',
                                            '${seconds ~/ 60}',
                                          )
                                    : s.seconds(seconds),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            _save(settings.copyWith(idleSeconds: value));
                          }
                        },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                s.text(
                  'Both automatic locks are off for new keychains. These settings apply to every app using this keychain. Restarting or locking it manually can still require an unlock.',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
