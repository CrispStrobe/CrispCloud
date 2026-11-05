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
import 'services/internxt_client.dart' show ConfigService, ConfigStorage;
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
import 'services/locale_preference.dart';
import 'services/thumbnail_service.dart';
import 'services/proxy_service.dart';
import 'services/pdf_font_licenses.dart';
import 'services/secure_storage_service.dart';
import 'services/secure_storage_web.dart';
import 'widgets/lock_screen.dart';

/// Displays initialization failures without depending on app providers.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.error, this.locale});

  final Object error;
  final Locale? locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Scaffold(
          body: Center(child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              '${StartupFailureStrings(context).title}\n${localizedProviderError(context, error)}',
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          )),
        )),
      );
}

const _log = Log('Main');
const _appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.0',
);

Future<void> main() async {
  CrashReportingService? crashReporting;
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    registerBundledEditorAssets();
    registerPdfFontLicenses();
    LicenseRegistry.addLicense(() => Stream.value(
        const LicenseEntryWithLineBreaks(['libsmb2'], smbLicense)));

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

    // Initialize secure storage and migrate credentials.
    // On web, use encrypted localStorage with a master password.
    // On native platforms, use OS-level secure storage (Keychain, etc.).
    final SecureStorage secureStorage;
    if (kIsWeb) {
      final webStorage = WebEncryptedStorage(LocalStorageBackend());
      // The master password prompt is handled by WebMasterPasswordGate below.
      // We pass the un-initialized storage and let the gate handle it.
      secureStorage = webStorage;
    } else {
      secureStorage = PlatformSecureStorage();
      await CredentialMigration.migrateIfNeeded(secureStorage);
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
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      configPath = p.join(home, '.cloud-storage-config');
    }

    _log.info('Config path: $configPath');
    crashReporting!.reportBreadcrumb('Configuration path resolved', 'startup');

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
          'Internxt preference detected but provider is disabled. Forcing Filen.');
      defaultProvider = CloudProvider.filen;
    }

    try {
      final configService = await _createConfigService(
          configPath, defaultProvider, secureStorage);

      final savedLocale = await LocalePreference.read();
      runApp(ProviderScope(
        overrides: [
          localeProvider.overrideWith((ref) => LocaleNotifier(initialLocale: savedLocale, load: false)),
          secureStorageProvider.overrideWithValue(secureStorage),
          configPathProvider.overrideWithValue(configPath),
          proxyServiceProvider.overrideWithValue(proxyService),
          certPinningProvider.overrideWithValue(certPinning),
          fileCacheProvider.overrideWithValue(fileCache),
          thumbnailServiceProvider.overrideWithValue(thumbnailService),
          auditServiceProvider.overrideWithValue(auditService),
          crashReportingServiceProvider.overrideWithValue(crashReporting!),
          authProvider.overrideWith((ref) => AuthNotifier(
                ref,
                initialProvider: defaultProvider,
                config: configService,
                configPath: configPath,
                secureStorage: secureStorage,
              )),
        ],
        child: const MyApp(),
      ));
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
  }, (error, stack) {
    _log.error('Uncaught error', error, stack);
    final reporter = crashReporting;
    if (reporter != null) {
      unawaited(reporter.reportError(
        error,
        stack,
        context: const {'origin': 'root_zone'},
      ));
    }
  });
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
            configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.filen:
        return FilenConfigService(
            configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.ftp:
        return FTPConfigService(
            configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.gdrive:
        return GDriveConfigService(
            configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.onedrive:
        return OneDriveConfigService(
            configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.s3:
        return S3ConfigService(
            configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.nextcloud:
        return NextcloudConfigService(
            configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.pcloud:
        return PCloudConfigService(
            configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.sftp:
        return SFTPConfigService(
            configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.webdav:
        return WebDavConfigService(
            configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.smb:
        return SmbConfigService(secureStorage);
      case CloudProvider.internxt:
        if (CloudStorageFactory.isInternxtSupported) {
          return ConfigService(
            configPath: configPath,
            storage: kIsWeb ? _InMemoryConfigStorage() : null,
          );
        } else {
          return FilenConfigService(
              configPath: configPath, secureStorage: secureStorage);
        }
      case CloudProvider.azure:
        return AzureConfigService(secureStorage: secureStorage);
      case CloudProvider.b2:
        return B2ConfigService(secureStorage: secureStorage);
    }
  } catch (e) {
    _log.error('Critical error creating config service', e);
    return FilenConfigService(
        configPath: configPath, secureStorage: secureStorage);
  }
}

/// App lock service provider.
final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService(ref.watch(secureStorageProvider));
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
      home: kIsWeb ? const WebMasterPasswordGate() : const _AppLockGate(),
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
  DateTime? _lastPaused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
  }

  Future<void> _checkLock() async {
    final lockService = ref.read(appLockServiceProvider);
    final enabled = await lockService.isEnabled();
    if (mounted) {
      setState(() {
        _isLocked = enabled;
        _isChecking = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lastPaused = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _lastPaused != null) {
      _checkAutoLock();
    }
  }

  Future<void> _checkAutoLock() async {
    if (_isLocked) return;
    final lockService = ref.read(appLockServiceProvider);
    final enabled = await lockService.isEnabled();
    if (!enabled) return;

    final timeout = await lockService.getTimeout();
    final elapsed = DateTime.now().difference(_lastPaused!).inSeconds;
    if (elapsed >= timeout) {
      if (mounted) setState(() => _isLocked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

/// Gate widget shown on web that prompts for a master password to unlock
/// encrypted credential storage before proceeding to the app.
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

  @override
  void initState() {
    super.initState();
    _checkIfGateNeeded();
  }

  /// Decide whether to create or unlock a vault before the app saves secrets.
  Future<void> _checkIfGateNeeded() async {
    try {
      final storage = ref.read(secureStorageProvider) as WebEncryptedStorage;
      final backend = storage.backend;
      final existingSalt = await backend.getItem('crisp_enc_salt');
      _isNewVault = existingSalt == null;
    } catch (_) {
      // If check fails, show the gate as a safe default.
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final password = _controller.text.trim();
    if (password.isEmpty) return;
    if (_isNewVault && password != _confirmationController.text.trim()) {
      setState(() => _error = WebVaultStrings(context).mismatch);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final storage = ref.read(secureStorageProvider) as WebEncryptedStorage;
      await storage.initialize(password);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const _AppLockGate()),
        );
      }
    } on StateError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message == 'Incorrect master password' ||
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
                      obscureText: true,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: strings.password,
                        errorText: _error,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_isNewVault) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmationController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: strings.confirmation,
                          border: const OutlineInputBorder(),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                _isNewVault ? strings.create : strings.unlock),
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

/// No-op ConfigStorage for web — avoids dart:io Platform.environment calls.
class _InMemoryConfigStorage extends ConfigStorage {
  final Map<String, String> _store = {};

  @override
  void init(String dataDir, List<String> subDirs) {}

  @override
  Future<bool> exists(String key) async => _store.containsKey(key);

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}
