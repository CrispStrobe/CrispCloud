// lib/utils/secure_clipboard.dart
//
// Clipboard helper that auto-clears sensitive data after a timeout.

import 'dart:async';

import 'package:flutter/services.dart';

class SecureClipboard {
  static Timer? _clearTimer;

  /// Copy [text] to clipboard and auto-clear after [clearAfter] (default 30s).
  static Future<void> copy(String text, {Duration clearAfter = const Duration(seconds: 30)}) async {
    _clearTimer?.cancel();
    await Clipboard.setData(ClipboardData(text: text));
    _clearTimer = Timer(clearAfter, () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  /// Cancel any pending auto-clear timer.
  static void cancelAutoClear() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }
}
