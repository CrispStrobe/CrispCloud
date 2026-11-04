// lib/services/system_preview_service.dart
//
// Opens an Office document in the platform's Quick Look preview.
//
// macOS: QLPreviewView in a separate window (QuickLookUI).
// iOS:   UIDocumentInteractionController / Quick Look.
//
// This is App Store-safe (system frameworks only) and is the exact-rendering
// fallback for legacy .ppt/.pps, which no pure-Dart engine parses.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class SystemPreviewException implements Exception {
  final String message;
  const SystemPreviewException(this.message);

  @override
  String toString() => message;
}

class SystemPreviewService {
  static const MethodChannel _channel =
      MethodChannel('crispcloud/system_preview');

  bool get isSupported => !kIsWeb && (Platform.isMacOS || Platform.isIOS);

  Future<void> show(Uint8List bytes, String name) async {
    if (!isSupported) {
      throw const SystemPreviewException(
        'System preview is only available on macOS and iOS.',
      );
    }

    final supportDir = await getApplicationSupportDirectory();
    final folder = Directory('${supportDir.path}/viewer_system');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    await _cleanupOldFiles(folder);

    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '${folder.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName';
    await File(path).writeAsBytes(bytes, flush: true);

    try {
      await _channel.invokeMethod<void>('show', {
        'path': path,
        'title': name,
      });
    } on PlatformException catch (e) {
      throw SystemPreviewException(
        e.message ?? 'The system could not preview this document.',
      );
    }
  }

  Future<void> _cleanupOldFiles(Directory dir) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 12));
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) await entity.delete();
        } catch (_) {
          // Skip entries that disappear or cannot be inspected.
        }
      }
    } catch (_) {
      // Cleanup is best-effort.
    }
  }
}
