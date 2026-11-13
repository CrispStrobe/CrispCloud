// lib/widgets/lock_screen.dart
//
// Full-screen lock overlay requiring PIN/password or biometric to access the app.

import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../l10n/app_localizations.dart';
import '../l10n/biometric_strings.dart';
import '../l10n/lock_extra_strings.dart';
import '../l10n/web_vault_strings.dart';

class LockScreen extends StatefulWidget {
  final AppLockService lockService;
  final VoidCallback onUnlocked;
  final void Function(Object error, StackTrace stack)? onStorageFailure;

  const LockScreen({
    super.key,
    required this.lockService,
    required this.onUnlocked,
    this.onStorageFailure,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;
  bool _isVerifying = false;
  int _attempts = 0;
  bool _biometricAvailable = false;
  bool _obscureCode = true;
  String _biometricLabel = 'Biometric';

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final bool enabled;
    try {
      enabled = await widget.lockService.isBiometricEnabled();
    } catch (error, stack) {
      if (mounted) widget.onStorageFailure?.call(error, stack);
      return;
    }
    if (!enabled) return;

    final available = await widget.lockService.isBiometricAvailable();
    if (!available) return;

    final label = await widget.lockService.getBiometricLabel();
    if (mounted) {
      setState(() {
        _biometricAvailable = true;
        _biometricLabel = label;
      });
      // Auto-prompt biometric on lock screen show
      _authenticateBiometric();
    }
  }

  Future<void> _authenticateBiometric() async {
    setState(() => _isVerifying = true);
    final ok = await widget.lockService.authenticateWithBiometric(
      localizedReason: BiometricStrings(context).text('reason'),
    );
    if (ok) {
      widget.onUnlocked();
    } else {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _focusNode.requestFocus();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final extra = LockExtraStrings(context);
    final isLocked = _attempts >= 5;

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(l10n.appLocked, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                _biometricAvailable
                    ? extra.useOrPin(
                        BiometricStrings(context).label(_biometricLabel),
                      )
                    : l10n.enterPinToContinue,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_biometricAvailable) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: isLocked || _isVerifying
                        ? null
                        : _authenticateBiometric,
                    icon: Icon(_biometricIcon),
                    label: Text(
                      extra.unlockWith(
                        BiometricStrings(context).label(_biometricLabel),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        extra.or,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: _codeController,
                focusNode: _focusNode,
                obscureText: _obscureCode,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                enabled: !isLocked && !_isVerifying,
                decoration: InputDecoration(
                  labelText: l10n.pinPassword,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.password),
                  suffixIcon: _isVerifying
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: _obscureCode
                              ? 'Show password'
                              : 'Hide password',
                          icon: Icon(
                            _obscureCode
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _obscureCode = !_obscureCode),
                        ),
                ),
                onSubmitted: isLocked ? null : (_) => _verify(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLocked || _isVerifying ? null : _verify,
                  child: Text(
                    isLocked
                        ? extra.lockedButton
                        : WebVaultStrings(context).unlock,
                  ),
                ),
              ),
              if (_attempts > 0 && !isLocked)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.attemptsRemaining(5 - _attempts),
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _biometricIcon {
    if (_biometricLabel == 'Windows Hello')
      return Icons.verified_user; // Windows Hello
    if (_biometricLabel == 'Face ID') return Icons.face;
    if (_biometricLabel == 'Fingerprint') return Icons.fingerprint;
    return Icons.security;
  }

  Future<void> _verify() async {
    if (_codeController.text.isEmpty) return;

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final bool ok;
    try {
      ok = await widget.lockService.verify(_codeController.text);
    } catch (error, stack) {
      if (mounted) {
        setState(() => _isVerifying = false);
        widget.onStorageFailure?.call(error, stack);
      }
      return;
    }
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _attempts++;
        _isVerifying = false;
        _error = _attempts >= 5
            ? AppLocalizations.of(context)!.tooManyAttempts
            : AppLocalizations.of(context)!.incorrectPin;
        _codeController.clear();
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

/// Dialog for setting up or changing the app lock.
class AppLockSetupDialog extends StatefulWidget {
  final AppLockService lockService;
  final bool isChanging;

  const AppLockSetupDialog({
    super.key,
    required this.lockService,
    this.isChanging = false,
  });

  @override
  State<AppLockSetupDialog> createState() => _AppLockSetupDialogState();
}

class _AppLockSetupDialogState extends State<AppLockSetupDialog> {
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  int _timeout = 300;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String _biometricLabel = 'Biometric';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final t = await widget.lockService.getTimeout();
    final bioAvail = await widget.lockService.isBiometricAvailable();
    final bioEnabled = await widget.lockService.isBiometricEnabled();
    final label = bioAvail
        ? await widget.lockService.getBiometricLabel()
        : 'Biometric';
    if (mounted) {
      setState(() {
        _timeout = t;
        _biometricAvailable = bioAvail;
        _biometricEnabled = bioEnabled;
        _biometricLabel = label;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final extra = LockExtraStrings(context);
    return AlertDialog(
      title: Text(
        widget.isChanging ? l10n.changeAppLockCode : l10n.appLockSetup,
      ),
      scrollable: true,
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                color: Colors.red.shade100,
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            if (widget.isChanging) ...[
              TextField(
                controller: _currentController,
                obscureText: _obscureCurrent,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(
                  labelText: l10n.currentPin,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscureCurrent
                        ? 'Show password'
                        : 'Hide password',
                    icon: Icon(
                      _obscureCurrent ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _newController,
              obscureText: _obscureNew,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: l10n.newPin,
                border: const OutlineInputBorder(),
                helperText: l10n.minFourChars,
                suffixIcon: IconButton(
                  tooltip: _obscureNew ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscureNew ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: l10n.confirmPin,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _timeout,
              decoration: InputDecoration(
                labelText: l10n.autoLockAfter,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 0, child: Text(l10n.immediately)),
                DropdownMenuItem(value: 60, child: Text(l10n.oneMinute)),
                DropdownMenuItem(value: 300, child: Text(l10n.fiveMinutes)),
                DropdownMenuItem(value: 900, child: Text(l10n.fifteenMinutes)),
                DropdownMenuItem(value: 1800, child: Text(l10n.thirtyMinutes)),
                DropdownMenuItem(value: 3600, child: Text(l10n.oneHour)),
              ],
              onChanged: (v) => setState(() => _timeout = v ?? 300),
            ),
            if (_biometricAvailable) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(
                  extra.unlockWith(
                    BiometricStrings(context).label(_biometricLabel),
                  ),
                ),
                subtitle: Text(
                  extra.alternative(
                    BiometricStrings(context).label(_biometricLabel),
                  ),
                ),
                secondary: Icon(
                  _biometricLabel == 'Windows Hello'
                      ? Icons.verified_user
                      : _biometricLabel == 'Face ID'
                      ? Icons.face
                      : _biometricLabel == 'Fingerprint'
                      ? Icons.fingerprint
                      : Icons.security,
                ),
                value: _biometricEnabled,
                onChanged: (v) => setState(() => _biometricEnabled = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(AppLocalizations.of(context)!.save),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final newCode = _newController.text;
    final confirm = _confirmController.text;

    if (newCode.length < 4) {
      setState(() => _error = LockExtraStrings(context).minLengthError);
      return;
    }
    if (newCode != confirm) {
      setState(() => _error = AppLocalizations.of(context)!.codesDoNotMatch);
      return;
    }

    if (widget.isChanging) {
      final ok = await widget.lockService.changeCode(
        _currentController.text,
        newCode,
      );
      if (!ok) {
        setState(() => _error = LockExtraStrings(context).incorrectCurrent);
        return;
      }
    } else {
      await widget.lockService.setup(newCode);
    }

    await widget.lockService.setTimeout(_timeout);
    if (_biometricAvailable) {
      await widget.lockService.setBiometricEnabled(_biometricEnabled);
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }
}
