// services/receive_service.dart
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'log_service.dart';

class ReceiveService {
  static const _log = Log('ReceiveService');

  static StreamSubscription? _intentSubscription;

  static void initialize({
    required Function(List<String>) onFilesReceived,
    required Function(String) onTextReceived,
  }) {
    // Only initialize on mobile platforms
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      _log.warn('Receive sharing intent not supported on ${Platform.operatingSystem}');
      return;
    }

    try {
      // For files
      _intentSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> files) {
          if (files.isNotEmpty) {
            final paths = files.map((f) => f.path).toList();
            onFilesReceived(paths);
          }
        },
        onError: (err) {
          _log.error("Error receiving shared files: $err");
        },
      );

      // Get initial media (when app was closed)
      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          final paths = files.map((f) => f.path).toList();
          onFilesReceived(paths);
        }
        ReceiveSharingIntent.instance.reset();
      }).catchError((err) {
        _log.error("Error getting initial media: $err");
      });
    } catch (e) {
      _log.error("Error initializing receive service: $e");
    }
  }

  static void dispose() {
    _intentSubscription?.cancel();
  }
}