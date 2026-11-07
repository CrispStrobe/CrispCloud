// lib/main.dart
import 'package:flutter/material.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'l10n/web_vault_strings.dart';
import 'l10n/startup_failure_strings.dart';
import 'l10n/provider_operation_strings.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:crisp_storage/crisp_storage.dart' show smbLicense;
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'dart:io';
import 'dart:async';

import 'providers/providers.dart';
import 'screens/file_browser_screen.dart';
import 'services/cloud_storage_interface.dart';
import 'services/dropbox_config_service.dart';
import 'services/filen_config_service.dart';
import 'services/ftp_config_service.dart';
import 'services/gdrive_config_service.dart';
import 'services/internxt_flutter/secure_config_storage.dart';
import 'services/onedrive_config_service.dart';
import 'services/s3_config_service.dart';
import 'services/nextcloud_config_service.dart';
import 'services/pcloud_config_service.dart';
import 'services/sftp_config_service.dart';
import 'services/webdav_config_service.dart';
import 'services/smb_config_service.dart';
import 'services/azure_config_service.dart';
import 'services/b2_config_service.dart';
import 'services/app_lock_service.dart';
import 'services/audit_service.dart';
import 'services/background_sync_service.dart';
import 'services/cert_pinning_service.dart';
import 'services/crash_reporting_service.dart';
import 'services/file_cache_service.dart';
import 'services/log_service.dart';
import 'services/installation_identity.dart';
import 'services/locale_preference.dart';
import 'services/thumbnail_service.dart';
import 'services/proxy_service.dart';
import 'services/pdf_font_licenses.dart';
import 'services/terminal_licenses.dart';
import 'services/secure_storage_service.dart';
import 'services/secure_storage_web.dart';
import 'services/secure_storage_file.dart';
import 'services/secure_storage_macos_keychain.dart';
import 'services/credential_storage_bootstrap.dart';
import 'services/credential_storage_config.dart';
import 'services/credential_storage_first_setup.dart';
import 'services/credential_storage_first_setup_io.dart';
import 'widgets/credential_storage_setup.dart';
import 'widgets/lock_screen.dart';
import 'services/media_video_backend.dart' show registerMediaVideoLicenses;

/// Displays initialization failures without depending on app providers.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.error,
    this.locale,
    this.onRetry,
  });

  final Object error;
  final Locale? locale;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${StartupFailureStrings(context).title}\n${localizedProviderError(context, error)}',
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: onRetry,
                    child: Text(AppLocalizations.of(context)!.retry),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

const _log = Log('Main');
const _appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.0',
);

Future<void> main() async {
  CrashReportingService? crashReporting;
  var applicationMounted = false;
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // First-install evidence must precede all startup preference/log/cache
      // writes. An interrupted storage choice has not exposed a profile yet.
      final firstSetup = !kIsWeb &&
          await CredentialStorageFirstSetup.capture(
            profileIsEmpty: (preferences) => nativeCredentialProfileIsEmpty(
              setupPreferences: preferences,
            ),
          );
      final nativeStorage = kIsWeb
          ? null
          : await _initializeNativeSecureStorage(allowFirstSetup: firstSetup);
      if (!kIsWeb) await CredentialStorageFirstSetup.complete();
      await InstallationIdentityService.instance.initialize();
      registerBundledEditorAssets();
      registerPdfFontLicenses();
      registerTerminalLicenses();
      registerMediaVideoLicenses();
      LicenseRegistry.addLicense(
        () => Stream.value(
          const LicenseEntryWithLineBreaks(['libsmb2'], smbLicense),
        ),
      );

      crashReporting = CrashReportingService(
        backend: LocalBackend(),
        appVersion: _appVersion,
      );
      await crashReporting!.initialize();
      crashReporting!.installGlobalHandlers();
      crashReporting!.reportBreadcrumb('Flutter binding ready', 'startup');

      // Route AES-GCM to the platform's hardware-accelerated crypto on native
      // (Android Keystore / Apple CryptoKit) — ~1000 MB/s vs ~1-9 MB/s pure-Dart
      // for file encryption. No-op on web (which uses WebCrypto directly).
      if (!kIsWeb) {
        FlutterCryptography.enable();
      }

      // Disable browser context menu on web so our custom context menu works.
      if (kIsWeb) {
        BrowserContextMenu.disableContextMenu();
      }

      // Register the Workmanager background task callback (Android/iOS only).
      // Must be called before runApp() so the callback isolate can be spawned.
      await BackgroundSyncService.initialize();
      crashReporting!.reportBreadcrumb('Background services ready', 'startup');

      _log.info('App starting...');

      // Open exactly the selected storage. Unavailable keychains must not
      // silently fall back to a store that lacks the existing app-lock policy.
      final SecureStorage secureStorage;
      var vaultRequired = false;
      var effectiveMode = CredentialStorageMode.systemKeychain;
      if (kIsWeb) {
        final webStorage = WebEncryptedStorage(LocalStorageBackend());
        // The master password prompt is handled by WebMasterPasswordGate below.
        // We pass the un-initialized storage and let the gate handle it.
        secureStorage = webStorage;
      } else {
        final selected = nativeStorage!;
        secureStorage = selected.storage;
        effectiveMode = selected.mode;
        vaultRequired = selected.requiresUnlock;
      }
      crashReporting!.reportBreadcrumb('Secure storage ready', 'startup');

      // Platform-specific config path
      String configPath;
      if (kIsWeb) {
        configPath = 'cloud-storage-config';
      } else if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getApplicationSupportDirectory();
        configPath = p.join(dir.path, '.cloud-storage-config');
      } else {
        final home =
            Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.';
        configPath = p.join(home, '.cloud-storage-config');
      }

      _log.info('Config path: $configPath');
      crashReporting!.reportBreadcrumb(
        'Configuration path resolved',
        'startup',
      );

      // Load proxy and certificate pinning configuration
      final certPinning = CertPinningService();
      await certPinning.load();

      final proxyService = ProxyService();
      await proxyService.load();
      proxyService.setCertPinning(certPinning);
      proxyService.applyGlobally();
      crashReporting!.reportBreadcrumb('Network policy ready', 'startup');

      // Initialize file cache, thumbnail service, and audit service
      final fileCache = FileCacheService();
      await fileCache.init();

      final thumbnailService = ThumbnailService();
      await thumbnailService.init();

      final auditService = AuditService();
      await auditService.init();
      crashReporting!.reportBreadcrumb('Caches and audit log ready', 'startup');

      CloudProvider defaultProvider = await _getDefaultProvider();

      if (defaultProvider == CloudProvider.internxt &&
          !CloudStorageFactory.isInternxtSupported) {
        _log.warn(
          'Internxt preference detected but provider is disabled. Forcing Filen.',
        );
        defaultProvider = CloudProvider.filen;
      }

      try {
        final configService = await _createConfigService(
          configPath,
          defaultProvider,
          secureStorage,
        );

        final savedLocale = await LocalePreference.read();
        runApp(
          ProviderScope(
            overrides: [
              localeProvider.overrideWith(
                (ref) =>
                    LocaleNotifier(initialLocale: savedLocale, load: false),
              ),
              secureStorageProvider.overrideWithValue(secureStorage),
              credentialStorageModeProvider.overrideWith(
                (ref) => effectiveMode,
              ),
              credentialVaultRequiredProvider.overrideWith(
                (ref) => vaultRequired,
              ),
              configPathProvider.overrideWithValue(configPath),
              proxyServiceProvider.overrideWithValue(proxyService),
              certPinningProvider.overrideWithValue(certPinning),
              fileCacheProvider.overrideWithValue(fileCache),
              thumbnailServiceProvider.overrideWithValue(thumbnailService),
              auditServiceProvider.overrideWithValue(auditService),
              crashReportingServiceProvider.overrideWithValue(crashReporting!),
              authProvider.overrideWith(
                (ref) => AuthNotifier(
                  ref,
                  initialProvider: defaultProvider,
                  config: configService,
                  configPath: configPath,
                  secureStorage: secureStorage,
                ),
              ),
            ],
            child: const MyApp(),
          ),
        );
        applicationMounted = true;
        crashReporting!.reportBreadcrumb('Application UI mounted', 'startup');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _log.info('Startup UI rendered');
        });
      } catch (e, stack) {
        _log.error('Critical error creating config service', e, stack);
        await crashReporting!.reportError(
          e,
          stack,
          context: const {'origin': 'startup_config'},
        );
        // Show an error screen instead of a black screen
        runApp(StartupFailureApp(error: e));
      }
    },
    (error, stack) {
      _log.error('Uncaught error', error, stack);
      final reporter = crashReporting;
      if (reporter != null) {
        unawaited(
          reporter.reportError(
            error,
            stack,
            context: const {'origin': 'root_zone'},
          ),
        );
      }
      // Storage preferences, support-directory lookup, and other early startup
      // work run before the config-service catch. Always render those failures.
      if (!applicationMounted) runApp(StartupFailureApp(error: error));
    },
  );
}

Future<CredentialStorageBootstrapResult> _initializeNativeSecureStorage({
  required bool allowFirstSetup,
}) async {
  String? firstVaultPassword;
  final bootstrap = CredentialStorageBootstrap(
    openKeychain: (customPath) async {
      try {
        if (Platform.isMacOS && customPath != null) {
          final custom = MacOsCustomKeychainStorage(path: customPath);
          await custom.initialize();
          return custom;
        }
        final keychain = PlatformSecureStorage();
        if (!await keychain.isAvailable()) {
          throw const CredentialStorageUnavailable();
        }
        return keychain;
      } catch (_) {
        throw const CredentialStorageUnavailable();
      }
    },
    openFileVault: () {
      final password = firstVaultPassword;
      firstVaultPassword = null;
      return createEncryptedFileStorage(masterPassword: password);
    },
  );
  CredentialStorageSetupResult? pendingSelection;
  var showFirstSetup = false;
  while (true) {
    CredentialStorageMode? attemptedMode;
    try {
      final configured = await CredentialStorageConfig.readSelection();
      if (allowFirstSetup && (showFirstSetup || configured.mode == null)) {
        pendingSelection ??= await _runFirstRunCredentialSetup();
        showFirstSetup = false;
      }
      final selection = pendingSelection;
      if (selection != null) {
        // Persist the user's explicit intent before creating a file vault. An
        // interrupted setup then resumes the selected backend's unlock gate.
        // The password never enters preferences and is used at most once.
        await CredentialStorageConfig.writeSelection(
          mode: selection.mode,
          customKeychainPath: selection.keychainPath,
        );
        firstVaultPassword = selection.masterPassword;
        pendingSelection = null;
      }
      final mode = selection?.mode ??
          configured.mode ??
          CredentialStorageMode.systemKeychain;
      attemptedMode = mode;
      final customPath = Platform.isMacOS
          ? (selection != null
                ? selection.keychainPath
                : configured.customKeychainPath)
          : null;
      final selected = await bootstrap.open(
        mode: mode,
        customKeychainPath: customPath,
      );
      return selected;
    } catch (error) {
      _log.warn('The selected credential store could not be opened.');
      if (allowFirstSetup &&
          attemptedMode == CredentialStorageMode.systemKeychain &&
          error is CredentialStorageUnavailable) {
        // This process has not exposed an initialized profile. Only the
        // independently verified fresh-setup path may choose another backend.
        showFirstSetup = true;
        continue;
      }
      final retry = Completer<void>();
      runApp(
        StartupFailureApp(
          error: const CredentialStorageUnavailable(),
          onRetry: () {
            if (!retry.isCompleted) retry.complete();
          },
        ),
      );
      // Retry the same configured store. Offering a different empty backend
      // here could bypass an app lock held in the inaccessible store.
      await retry.future;
    }
  }
}

Future<CredentialStorageSetupResult> _runFirstRunCredentialSetup() {
  final completer = Completer<CredentialStorageSetupResult>();
  runApp(
    CredentialStorageSetupScreen(
      onComplete: (result) {
        if (!completer.isCompleted) completer.complete(result);
      },
    ),
  );
  return completer.future;
}

Future<CloudProvider> _getDefaultProvider() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final providerName = prefs.getString('cloud_provider');

    if (providerName == null) return CloudProvider.filen;

    switch (providerName.toLowerCase()) {
      case 'dropbox':
        return CloudProvider.dropbox;
      case 'filen':
        return CloudProvider.filen;
      case 'ftp':
        return CloudProvider.ftp;
      case 'gdrive':
        return CloudProvider.gdrive;
      case 'internxt':
        return CloudProvider.internxt;
      case 'nextcloud':
        return CloudProvider.nextcloud;
      case 'onedrive':
        return CloudProvider.onedrive;
      case 'pcloud':
        return CloudProvider.pcloud;
      case 's3':
        return CloudProvider.s3;
      case 'sftp':
        return CloudProvider.sftp;
      case 'webdav':
        return CloudProvider.webdav;
      case 'smb':
        return CloudProvider.smb;
      default:
        return CloudProvider.filen;
    }
  } catch (e) {
    _log.warn('Error reading provider preference, defaulting to Filen', e);
    return CloudProvider.filen;
  }
}

Future<dynamic> _createConfigService(
  String configPath,
  CloudProvider provider,
  SecureStorage secureStorage,
) async {
  try {
    switch (provider) {
      case CloudProvider.dropbox:
        return DropboxConfigService(
          configPath: configPath,
          secureStorage: secureStorage,
        );
      case CloudProvider.filen:
        return FilenConfigService(
          configPath: configPath,
          secureStorage: secureStorage,
        );
      case CloudProvider.ftp:
        return FTPConfigService(
          configPath: configPath,
          secureStorage: secureStorage,
        );
      case CloudProvider.gdrive:
        return GDriveConfigService(
          configPath: configPath,
          secureStorage: secureStorage,
        );
      case CloudProvider.onedrive:
        return OneDriveConfigService(
          configPath: configPath,
          secureStorage: secureStorage,
        );
      case CloudProvider.s3:
        return S3ConfigService(
          configPath: configPath,
          secureStorage: secureStorage,
        );
      case CloudProvider.nextcloud:
        return NextcloudConfigService(
          configPath: configPath,
          secureStorage: secureStorage,
        );
      case CloudProvider.pcloud:
        return PCloudConfigService(
          configPath: configPath,
          secureStorage: secureStorage,
        );
      case CloudProvider.sftp:
        return SFTPConfigService(
          configPath: configPath,
          secureStorage: secureStorage,
        );
      case CloudProvider.webdav:
        return WebDavConfigService(
          configPath: configPath,
          secureStorage: secureStorage,
        );
      case CloudProvider.smb:
        return SmbConfigService(secureStorage);
      case CloudProvider.internxt:
        if (CloudStorageFactory.isInternxtSupported) {
          return createSecureInternxtConfig(
            configPath: configPath,
            secureStorage: secureStorage,
          );
        } else {
          return FilenConfigService(
            configPath: configPath,
            secureStorage: secureStorage,
          );
        }
      case CloudProvider.azure:
        return AzureConfigService(secureStorage: secureStorage);
      case CloudProvider.b2:
        return B2ConfigService(secureStorage: secureStorage);
    }
  } catch (e) {
    _log.error('Critical error creating config service', e);
    return FilenConfigService(
      configPath: configPath,
      secureStorage: secureStorage,
    );
  }
}

/// App lock service provider.
final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService(
    ref.watch(secureStorageProvider),
    beforeSetup: () async {
      if (ref.read(credentialStoragePendingModeProvider) != null ||
          ref.read(credentialStorageKeychainRestartRequiredProvider)) {
        throw StateError(
          'Restart CrispCloud before enabling App Lock after changing credential storage.',
        );
      }
      if (!kIsWeb) {
        // A preference write can reach disk even if its acknowledgement fails,
        // or another process can change it without updating our UI providers.
        // Read failures and differences both block enabling an old-store lock.
        final configured = await CredentialStorageConfig.readSelection();
        final activeMode = ref.read(credentialStorageModeProvider);
        final activeStore = ref.read(secureStorageProvider);
        final activePath = activeStore is MacOsCustomKeychainStorage
            ? activeStore.path
            : null;
        if ((configured.mode ?? CredentialStorageMode.systemKeychain) != activeMode ||
            (Platform.isMacOS &&
                activeMode == CredentialStorageMode.systemKeychain &&
                configured.customKeychainPath != activePath)) {
          throw StateError(
            'Restart CrispCloud before enabling App Lock after changing credential storage.',
          );
        }
      }
    },
  );
});

/// Certificate pinning service provider.
final certPinningProvider = Provider<CertPinningService>((ref) {
  return CertPinningService(); // Overridden in ProviderScope
});

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeService = ref.watch(themeProvider);
    ref.listen<Locale?>(localeProvider, (_, locale) {
      unawaited(LocalePreference.write(locale));
    });

    return MaterialApp(
      title: 'CrispCloud',
      theme: themeService.lightTheme,
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
              WebVaultStrings(context).failure(
                const CredentialStorageUnavailable(),
              ),
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
      await storage.initialize(password, expectedExisting: !_isNewVault);
      if (!storage.isInitialized) throw const CredentialStorageUnavailable();
      await CredentialMigration.migrateIfNeeded(storage);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const _AppLockGate()),
        );
      }
    } on StateError catch (e) {
      if (mounted) {
        setState(() {
          _error =
              e.message == 'Incorrect master password' ||
                  e.message == 'Incorrect master password or damaged vault' ||
                  e.message == 'Master password verification failed'
              ? WebVaultStrings(context).incorrect
              : WebVaultStrings(context).failure(e.message);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = WebVaultStrings(context).failure(e);
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
