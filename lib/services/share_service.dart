// services/share_service.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'dart:io';

import 'log_service.dart';

class ShareService {
  static const _log = Log('ShareService');

  /// The system share sheet can send files on Android, iOS, macOS and
  /// Windows 10 1809+ (share_plus). Linux has no share sheet; web is excluded.
  static bool get isFileSharingSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows);

  static Future<void> shareFiles(List<String> filePaths) async {
    if (filePaths.isEmpty || !isFileSharingSupported) return;
    try {
      // No accompanying text: many targets would add it as an extra item.
      await Share.shareXFiles(filePaths.map(XFile.new).toList());
    } catch (e) {
      _log.error('Error sharing files: $e');
      rethrow;
    }
  }

  static Future<void> shareFile(String filePath, {String? text}) async {
    try {
      await Share.shareXFiles([XFile(filePath)], text: text);
    } catch (e) {
      _log.error('Error sharing file: $e');
      rethrow;
    }
  }

  static Future<void> shareText(String text) async {
    try {
      await Share.share(text);
    } catch (e) {
      _log.error('Error sharing text: $e');
      rethrow;
    }
  }
}