// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:async';

import 'package:provider/provider.dart' as legacy_provider;

import 'providers/providers.dart';
import 'screens/file_browser_screen.dart';
import 'services/cloud_storage_interface.dart';
import 'services/dropbox_config_service.dart';
import 'services/filen_config_service.dart';
import 'services/ftp_config_service.dart';
import 'services/gdrive_config_service.dart';
import 'services/internxt_client.dart' show ConfigService;
import 'services/onedrive_config_service.dart';
import 'services/s3_config_service.dart';
import 'services/sftp_config_service.dart';
import 'services/webdav_config_service.dart';
import 'services/secure_storage_service.dart';
import 'services/theme_service.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    debugPrint('[Main] App starting...');

    // Initialize secure storage and migrate credentials
    final secureStorage = PlatformSecureStorage();
    await CredentialMigration.migrateIfNeeded(secureStorage);

    // Platform-specific config path
    String configPath;
    if (kIsWeb) {
      configPath = 'cloud-storage-config';
    } else if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationSupportDirectory();
      configPath = p.join(dir.path, '.cloud-storage-config');
    } else {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      configPath = p.join(home, '.cloud-storage-config');
    }

    debugPrint('[Main] Config path: $configPath');

    CloudProvider defaultProvider = await _getDefaultProvider();

    if (defaultProvider == CloudProvider.internxt && !CloudStorageFactory.isInternxtSupported) {
      debugPrint('Internxt preference detected but provider is disabled. Forcing Filen.');
      defaultProvider = CloudProvider.filen;
    }

    try {
      final configService = await _createConfigService(configPath, defaultProvider, secureStorage);

      runApp(ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(secureStorage),
          configPathProvider.overrideWithValue(configPath),
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
    } catch (e, stack) {
      debugPrint('[Main] Critical Error creating config service: $e');
      debugPrint('$stack');
    }
  }, (error, stack) {
    debugPrint('[Global Error Catch] $error');
    debugPrint('$stack');
  });
}

Future<CloudProvider> _getDefaultProvider() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final providerName = prefs.getString('cloud_provider');

    if (providerName == null) return CloudProvider.filen;

    switch (providerName.toLowerCase()) {
      case 'dropbox': return CloudProvider.dropbox;
      case 'filen': return CloudProvider.filen;
      case 'ftp': return CloudProvider.ftp;
      case 'gdrive': return CloudProvider.gdrive;
      case 'internxt': return CloudProvider.internxt;
      case 'onedrive': return CloudProvider.onedrive;
      case 's3': return CloudProvider.s3;
      case 'sftp': return CloudProvider.sftp;
      case 'webdav': return CloudProvider.webdav;
      default: return CloudProvider.filen;
    }
  } catch (e) {
    debugPrint('Error reading provider preference: $e, defaulting to Filen');
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
        return DropboxConfigService(configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.filen:
        return FilenConfigService(configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.ftp:
        return FTPConfigService(configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.gdrive:
        return GDriveConfigService(configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.onedrive:
        return OneDriveConfigService(configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.s3:
        return S3ConfigService(configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.sftp:
        return SFTPConfigService(configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.webdav:
        return WebDavConfigService(configPath: configPath, secureStorage: secureStorage);
      case CloudProvider.internxt:
        if (CloudStorageFactory.isInternxtSupported) {
          return ConfigService(configPath: configPath);
        } else {
          return FilenConfigService(configPath: configPath, secureStorage: secureStorage);
        }
    }
  } catch (e) {
    debugPrint('Critical error creating config service: $e');
    return FilenConfigService(configPath: configPath, secureStorage: secureStorage);
  }
}

/// ThemeService exposed via Riverpod.
final themeProvider = ChangeNotifierProvider<ThemeService>((ref) => ThemeService());

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeService = ref.watch(themeProvider);

    // ThemeService also exposed via legacy Provider for widgets not yet migrated
    return legacy_provider.ChangeNotifierProvider<ThemeService>.value(
      value: themeService,
      child: MaterialApp(
        title: 'CrispCloud',
        theme: themeService.lightTheme,
        darkTheme: themeService.darkTheme,
        themeMode: themeService.themeMode,
        home: const FileBrowserScreen(),
      ),
    );
  }
}
