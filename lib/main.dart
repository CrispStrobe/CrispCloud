// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/file_browser_screen.dart';
import 'services/app_state.dart';
import 'services/cloud_storage_interface.dart'; //
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:async';

import 'services/filen_config_service.dart';
import 'services/internxt_client.dart' show ConfigService; //
import 'services/sftp_config_service.dart';
import 'services/webdav_config_service.dart';

Future<void> main() async {
  // Catch errors that happen during startup (like ConfigService crashing on Web)
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    debugPrint("🚀 [Main] App starting...");

    // Determine the platform-specific config path
    String configPath;
    if (kIsWeb) {
      // NOTE: On Web, this path is symbolic. 
      // If ConfigService uses io.File(configPath).writeAsString, it WILL crash.
      // Ideally, ConfigService should use SharedPreferences on Web.
      configPath = 'cloud-storage-config'; 
    } else if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationSupportDirectory();
      configPath = p.join(dir.path, '.cloud-storage-config');
    } else {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      configPath = p.join(home, '.cloud-storage-config');
    }

    debugPrint("📂 [Main] Config path: $configPath");

    CloudProvider defaultProvider = await _getDefaultProvider();

    if (defaultProvider == CloudProvider.internxt && !CloudStorageFactory.isInternxtSupported) {
      debugPrint('⚠️ Internxt preference detected but provider is disabled. Forcing Filen.');
      defaultProvider = CloudProvider.filen;
    }
    
    try {
      final configService = await _createConfigService(configPath, defaultProvider);
      
      runApp(MyApp(
        configService: configService,
        initialProvider: defaultProvider,
      ));
    } catch (e, stack) {
      debugPrint("🔥 [Main] Critical Error creating config service: $e");
      debugPrint(stack);
      // Fallback to basic app or error screen could go here
    }
  }, (error, stack) {
    debugPrint("🔥 [Global Error Catch] $error");
    debugPrint(stack);
  });
}

// Helper to determine default provider from saved preference
Future<CloudProvider> _getDefaultProvider() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final providerName = prefs.getString('cloud_provider');
    
    if (providerName == null) {
      debugPrint('📂 No saved provider preference, defaulting to Filen');
      return CloudProvider.filen;
    }
    
    switch (providerName.toLowerCase()) {
      case 'filen':
        debugPrint('✅ Using saved provider: Filen');
        return CloudProvider.filen;
      case 'internxt':
        debugPrint('✅ Using saved provider: Internxt');
        return CloudProvider.internxt;
      case 'sftp': 
        debugPrint('✅ Using saved provider: SFTP');
        return CloudProvider.sftp;
      case 'webdav':
        debugPrint('✅ Using saved provider: WebDAV');
        return CloudProvider.webdav;
      default:
        debugPrint('⚠️ Unknown provider: $providerName, defaulting to Filen');
        return CloudProvider.filen;
    }
  } catch (e) {
    debugPrint('⚠️ Error reading provider preference: $e, defaulting to Filen');
    return CloudProvider.filen;
  }
}

// Helper to create appropriate config service
Future<dynamic> _createConfigService(String configPath, CloudProvider provider) async {
  // ROBUSTNESS: Wrap creation in try/catch to handle missing dependencies or logic errors
  try {
    switch (provider) {
      case CloudProvider.filen:
        debugPrint('🔧 Creating Filen config service');
        return FilenConfigService(configPath: configPath);
      case CloudProvider.sftp:
        debugPrint('🔧 Creating SFTP config service');
        return SFTPConfigService(configPath: configPath);
      case CloudProvider.webdav:
        debugPrint('🔧 Creating WebDAV config service');
        return WebDavConfigService(configPath: configPath);
      case CloudProvider.internxt:
        // Only attempt to create if supported
        if (CloudStorageFactory.isInternxtSupported) {
          debugPrint('🔧 Creating Internxt config service');
          return ConfigService(configPath: configPath);
        } else {
           debugPrint('⚠️ Internxt config requested but disabled. Falling back to Filen config.');
           return FilenConfigService(configPath: configPath);
        }
    }
  } catch (e) {
    debugPrint('❌ Critical error creating config service: $e');
    debugPrint('   Falling back to Filen defaults.');
    return FilenConfigService(configPath: configPath);
  }
}

class MyApp extends StatelessWidget {
  final dynamic configService;
  final CloudProvider initialProvider;
  
  const MyApp({
    super.key, 
    required this.configService,
    required this.initialProvider,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(
        config: configService,
        initialProvider: initialProvider,
      ),
      child: MaterialApp(
        title: 'Cloud Storage Manager',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const FileBrowserScreen(),
      ),
    );
  }
}