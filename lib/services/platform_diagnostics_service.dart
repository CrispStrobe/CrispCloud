import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Non-sensitive platform checks that help diagnose packaged desktop builds.
class PlatformDiagnostics {
  final String platform;
  final bool packagedApplication;
  final bool sandboxed;
  final bool applicationSupportWritable;
  final String cryptoBackend;
  final String secureStorageBackend;

  const PlatformDiagnostics({
    required this.platform,
    required this.packagedApplication,
    required this.sandboxed,
    required this.applicationSupportWritable,
    required this.cryptoBackend,
    required this.secureStorageBackend,
  });

  static Future<PlatformDiagnostics> collect() async {
    if (kIsWeb) {
      return const PlatformDiagnostics(
        platform: 'Web',
        packagedApplication: false,
        sandboxed: true,
        applicationSupportWritable: true,
        cryptoBackend: 'WebCrypto',
        secureStorageBackend: 'Encrypted browser storage',
      );
    }

    var supportWritable = false;
    try {
      final support = await getApplicationSupportDirectory();
      supportWritable = await support.exists();
    } catch (_) {
      supportWritable = false;
    }

    final executable = Platform.resolvedExecutable;
    final home = Platform.environment['HOME'] ?? '';
    final isMacSandbox = Platform.isMacOS &&
        home.contains(
            '${Platform.pathSeparator}Library${Platform.pathSeparator}Containers${Platform.pathSeparator}');

    return PlatformDiagnostics(
      platform: Platform.operatingSystem,
      packagedApplication: executable
              .contains('.app${Platform.pathSeparator}') ||
          executable.contains(
              '${Platform.pathSeparator}Applications${Platform.pathSeparator}'),
      sandboxed: isMacSandbox,
      applicationSupportWritable: supportWritable,
      cryptoBackend: Platform.isMacOS
          ? 'CryptoKit (bundled)'
          : Platform.isWindows
              ? 'Windows CNG'
              : Platform.isLinux
                  ? 'System OpenSSL'
                  : 'Platform cryptography',
      secureStorageBackend: Platform.isMacOS || Platform.isIOS
          ? 'Keychain'
          : Platform.isAndroid
              ? 'Android Keystore'
              : Platform.isWindows
                  ? 'Windows protected storage'
                  : 'libsecret / platform storage',
    );
  }

  Map<String, String> get displayValues => {
        'Platform': platform,
        'Packaged app': packagedApplication ? 'Yes' : 'No',
        'App sandbox': sandboxed ? 'Enabled' : 'Not detected',
        'Application Support':
            applicationSupportWritable ? 'Available' : 'Unavailable',
        'Crypto backend': cryptoBackend,
        'Credential store': secureStorageBackend,
      };
}
