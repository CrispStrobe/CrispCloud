import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/biometric_vault_strings.dart';
import '../services/biometric_vault_unlock.dart';
import '../services/secure_storage_web.dart';

/// Settings toggle for unlocking the encrypted credential vault with Touch ID.
/// Hidden where the platform has no implementation; disabled with the reason
/// when Touch ID is not enrolled or the build cannot use the protected keychain.
class BiometricVaultSettingsTile extends ConsumerStatefulWidget {
  const BiometricVaultSettingsTile({super.key, required this.storage});

  /// The unlocked vault of the current session.
  final WebEncryptedStorage storage;

  @override
  ConsumerState<BiometricVaultSettingsTile> createState() =>
      _BiometricVaultSettingsTileState();
}

class _BiometricVaultSettingsTileState
    extends ConsumerState<BiometricVaultSettingsTile> {
  bool _enabled = false;
  BiometricAvailability? _availability;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final unlock = ref.read(biometricVaultUnlockProvider);
    var enabled = false;
    var availability = BiometricAvailability.unavailable;
    try {
      enabled = await unlock.isEnabled();
      availability = await unlock.availability();
    } catch (_) {
      // Shown as unavailable.
    }
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _availability = availability;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    final strings = BiometricVaultStrings(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    final unlock = ref.read(biometricVaultUnlockProvider);
    try {
      if (value) {
        final failure = await unlock.enable(widget.storage);
        if (failure != null) {
          messenger?.showSnackBar(
            SnackBar(content: Text(strings.enableFailed)),
          );
        }
      } else {
        await unlock.disable();
      }
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(strings.enableFailed)));
    } finally {
      _busy = false;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;
    if (availability == null ||
        availability == BiometricAvailability.unsupportedPlatform) {
      return const SizedBox.shrink();
    }
    final strings = BiometricVaultStrings(context);
    final usable = availability == BiometricAvailability.available;
    final subtitle = usable || _enabled
        ? strings.settingsSubtitle
        : switch (availability) {
            BiometricAvailability.notEnrolled => strings.notEnrolled,
            BiometricAvailability.missingEntitlement =>
              strings.missingEntitlement,
            _ => strings.unavailable,
          };
    return SwitchListTile(
      key: const ValueKey('settings-biometric-vault-unlock'),
      secondary: const Icon(Icons.fingerprint),
      title: Text(strings.settingsTitle),
      subtitle: Text(subtitle),
      value: _enabled,
      // Turning it off always works; turning it on needs usable Touch ID.
      onChanged: _busy || (!_enabled && !usable) ? null : _toggle,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    );
  }
}
