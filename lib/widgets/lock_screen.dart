// lib/widgets/lock_screen.dart
//
// Full-screen lock overlay requiring PIN/password to access the app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_service.dart';

class LockScreen extends StatefulWidget {
  final AppLockService lockService;
  final VoidCallback onUnlocked;

  const LockScreen({
    super.key,
    required this.lockService,
    required this.onUnlocked,
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

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Text(
                'CrispCloud is Locked',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your PIN or password to continue',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
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
                      Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: _codeController,
                focusNode: _focusNode,
                obscureText: true,
                enabled: !isLocked && !_isVerifying,
                decoration: InputDecoration(
                  labelText: 'PIN / Password',
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
                      : null,
                ),
                onSubmitted: isLocked ? null : (_) => _verify(),
                inputFormatters: [
                  // Allow any characters (PIN or password)
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLocked || _isVerifying ? null : _verify,
                  child: Text(isLocked ? 'Too many attempts' : 'Unlock'),
                ),
              ),
              if (_attempts > 0 && !isLocked)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${5 - _attempts} attempts remaining',
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

  Future<void> _verify() async {
    if (_codeController.text.isEmpty) return;

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final ok = await widget.lockService.verify(_codeController.text);

    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _attempts++;
        _isVerifying = false;
        _error = _attempts >= 5
            ? 'Too many failed attempts. Restart the app to try again.'
            : 'Incorrect PIN or password';
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
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  int _timeout = 300;

  @override
  void initState() {
    super.initState();
    _loadTimeout();
  }

  Future<void> _loadTimeout() async {
    final t = await widget.lockService.getTimeout();
    if (mounted) setState(() => _timeout = t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isChanging ? 'Change App Lock' : 'Set Up App Lock'),
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
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            if (widget.isChanging) ...[
              TextField(
                controller: _currentController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current PIN / Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _newController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New PIN / Password',
                border: OutlineInputBorder(),
                helperText: 'Minimum 4 characters',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm PIN / Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _timeout,
              decoration: const InputDecoration(
                labelText: 'Auto-lock after',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Immediately')),
                DropdownMenuItem(value: 60, child: Text('1 minute')),
                DropdownMenuItem(value: 300, child: Text('5 minutes')),
                DropdownMenuItem(value: 900, child: Text('15 minutes')),
                DropdownMenuItem(value: 1800, child: Text('30 minutes')),
                DropdownMenuItem(value: 3600, child: Text('1 hour')),
              ],
              onChanged: (v) => setState(() => _timeout = v ?? 300),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final newCode = _newController.text;
    final confirm = _confirmController.text;

    if (newCode.length < 4) {
      setState(() => _error = 'PIN/password must be at least 4 characters');
      return;
    }
    if (newCode != confirm) {
      setState(() => _error = 'Codes do not match');
      return;
    }

    if (widget.isChanging) {
      final ok = await widget.lockService.changeCode(_currentController.text, newCode);
      if (!ok) {
        setState(() => _error = 'Current PIN/password is incorrect');
        return;
      }
    } else {
      await widget.lockService.setup(newCode);
    }

    await widget.lockService.setTimeout(_timeout);

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
