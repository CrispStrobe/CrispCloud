// Captures Mac App Store screenshots from the real application.
//
// Runs only in the "Store screenshots" workflow on a fresh macOS runner:
//   flutter test integration_test/store_screenshots_test.dart -d macos
// It seeds demo files in the app's (sandbox) home, selects session-only
// credential storage so no keychain or account is involved, boots the
// production `main()`, and renders each screen at 1440x900 points @2x
// (2880x1800, an accepted Mac App Store size) straight from the layer tree.
// PNGs land in the app's temporary directory as crispcloud-store-NN-*.png;
// the workflow collects them from there.
//
// Steps are best-effort: a missing control is logged and the capture still
// happens, so one UI change cannot hide every other screenshot.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crisp_cloud/main.dart' as app;
import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _logicalSize = Size(1440, 900);
const _pixelRatio = 2.0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture Mac App Store screenshots', (tester) async {
    WidgetsApp.debugAllowBannerOverride = false;
    tester.view.physicalSize = _logicalSize * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;

    final home = Platform.environment['HOME']!;
    final out = Directory('${Directory.systemTemp.path}/crispcloud-store')
      ..createSync(recursive: true);
    _log('home=$home out=${out.path}');
    await _seedDemoHome(home);
    await CredentialStorageConfig.writeSelection(
      mode: CredentialStorageMode.sessionOnly,
    );

    app.main();
    await _settle(tester, const Duration(seconds: 8));
    _dumpTexts('after boot');

    await _shot(tester, out, '01-dual-panel');

    await _step('open Photos as large items', () async {
      await _openFolder(tester, 'Photos', panel: 0);
      await _tapTooltip(tester, 'Large Items');
    });
    await _settle(tester, const Duration(seconds: 3));
    _dumpTexts('photos');
    await _shot(tester, out, '02-photos-grid');

    await _step('open Projects with preview', () async {
      await _openFolder(tester, 'Projects', panel: 1);
      awai…39314 tokens truncated…Service.lightTheme,
      darkTheme: themeService.darkTheme,
      themeMode: themeService.themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      locale: ref.watch(localeProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      home: kIsWeb || ref.watch(credentialVaultRequiredProvider)
          ? const WebMasterPasswordGate()
          : const _AppLockGate(),
    );
  }
}

/// Gate widget that shows the lock screen if app lock is enabled.
class _AppLockGate extends ConsumerStatefulWidget {
  const _AppLockGate();

  @override
  ConsumerState<_AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<_AppLockGate>
    with WidgetsBindingObserver {
  bool _isLocked = false;
  bool _isChecking = true;
  bool _checkFailed = false;
  DateTime? _lastPaused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
  }

  Future<void> _checkLock() async {
    if (mounted) {
      setState(() {
        _isChecking = true;
        _checkFailed = false;
      });
    }
    try {
      final lockService = ref.read(appLockServiceProvider);
      final enabled = await lockService.isEnabled();
      if (mounted) {
        setState(() {
          _isLocked = enabled;
          _isChecking = false;
        });
      }
    } catch (_) {
      // An unavailable policy is not evidence that app lock is disabled.
      if (mounted) {
        setState(() {
          _checkFailed = true;
          _isChecking = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lastPaused = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_resume());
    }
  }

  Future<void> _resume() async {
    if (_lastPaused != null) await _checkAutoLock();
    if (mounted && !_isChecking && !_checkFailed && !_isLocked) {
      await ref.read(transferProvider).refreshBackgroundRecovery();
    }
  }

  Future<void> _checkAutoLock() async {
    if (_isLocked) return;
    try {
      final lockService = ref.read(appLockServiceProvider);
      final enabled = await lockService.isEnabled();
      if (!enabled) return;

      final timeout = await lockService.getTimeout();
      final elapsed = DateTime.now().difference(_lastPaused!).inSeconds;
      if (elapsed >= timeout) {
        if (mounted) setState(() => _isLocked = true);
      }
    } catch (_) {
      if (mounted) setState(() => _checkFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_checkFailed) {
      return _CredentialGateFailure(onRetry: _checkLock);
    }

    if (_isLocked) {
      return LockScreen(
        lockService: ref.read(appLockServiceProvider),
        onUnlocked: () => setState(() => _isLocked = false),
      );
    }

    return const FileBrowserScreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Shows a retryable credential failure without exposing the app or treating
/// unreadable lock/vault metadata as an empty new profile.
class _CredentialGateFailure extends StatelessWidget {
  const _CredentialGateFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              StartupFailureStrings(context).credentialStorageUnavailable,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context)?.retry ?? 'Retry'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Prompts for a master password on web and native encrypted-file backends
/// before proceeding to provider authentication or the app-lock gate.
class WebMasterPasswordGate extends ConsumerStatefulWidget {
  const WebMasterPasswordGate({super.key});

  @override
  ConsumerState<WebMasterPasswordGate> createState() =>
      WebMasterPasswordGateState();
}

class WebMasterPasswordGateState extends ConsumerState<WebMasterPasswordGate> {
  final _controller = TextEditingController();
  final _confirmationController = TextEditingController();
  String? _error;
  bool _loading = true;
  bool _isNewVault = false;
  bool _inspectionFailed = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  @override
  void initState() {
    super.initState();
    _checkIfGateNeeded();
  }

  /// Decide whether to create or unlock a vault before the app saves secrets.
  Future<void> _checkIfGateNeeded() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _inspectionFailed = false;
      });
    }
    try {
      final storage = ref.read(secureStorageProvider) as WebEncryptedStorage;
      _isNewVault = !await storage.hasVault();
      if (_isNewVault && ref.read(credentialVaultCreationProvider) == null) {
        throw const CredentialStorageUnavailable();
      }
    } catch (_) {
      // Corrupt/inaccessible metadata must never lead to a create/overwrite
      // prompt or to provider initialization without an unlocked vault.
      _inspectionFailed = true;
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_loading || _inspectionFailed) return;
    final password = _controller.text;
    if (password.isEmpty) return;
    if (_isNewVault && password.length < 8) {
      setState(
        () =>
            _error = SettingsStrings(context)
                .text('Use at least 8 characters for the master password.'),
      );
      return;
    }
    if (_isNewVault && password != _confirmationController.text) {
      setState(() => _error = WebVaultStrings(context).mismatch);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final storage = ref.read(secureStorageProvider) as WebEncryptedStorage;
      final consumeCreation = ref.read(credentialVaultCreationProvider);
      if (_isNewVault && consumeCreation == null) {
        throw const CredentialStorageUnavailable();
      }
      if (consumeCreation != null) {
        // Consume before writing a vault: a stale or unacknowledged grant must
        // never leave an empty replacement vault that a restart could trust.
        // Neither a failed consume nor a failed creation restores this grant.
        ref.read(credentialVaultCreationProvider.notifier).state = null;
        await consumeCreation();
      }
      await storage.initialize(password, expectedExisting: !_isNewVault);
      if (!storage.isInitialized) throw const CredentialStorageUnavailable();
      _isNewVault = false;
      await CredentialMigration.migrateIfNeeded(storage);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const _AppLockGate()),
        );
      }
    } on StateError catch (e) {
      if (mounted) {
        setState(() {
          _inspectionFailed =
              _isNewVault && ref.read(credentialVaultCreationProvider) == null;
          _error =
              e.message == 'Incorrect master password' ||
                  e.message == 'Incorrect master password or damaged vault' ||
                  e.message == 'Master password verification failed'
              ? WebVaultStrings(context).incorrect
              : WebVaultStrings(context).failure;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _inspectionFailed =
              _isNewVault && ref.read(credentialVaultCreationProvider) == null;
          _error = WebVaultStrings(context).failure;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // While checking if gate is needed, show a loading screen
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_inspectionFailed) {
      return _CredentialGateFailure(onRetry: _checkIfGateNeeded);
    }

    final strings = WebVaultStrings(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              margin: const EdgeInsets.all(32),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      strings.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isNewVault
                          ? strings.createDescription
                          : strings.unlockDescription,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _controller,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      obscureText: _obscurePassword,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: strings.password,
                        errorText: _error,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_isNewVault) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmationController,
                        autocorrect: false,
                        enableSuggestions: false,
                        enableIMEPersonalizedLearning: false,
                        obscureText: _obscureConfirmation,
                        decoration: InputDecoration(
                          labelText: strings.confirmation,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscureConfirmation
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscureConfirmation
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () => setState(
                              () =>
                                  _obscureConfirmation = !_obscureConfirmation,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _isNewVault ? strings.create : strings.unlock,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _confirmationController.dispose();
    _controller.dispose();
    super.dispose();
  }
}
