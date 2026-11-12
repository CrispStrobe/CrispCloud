import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native macOS window chrome; commands remain owned by the Flutter browser.
class MacBrowserToolbar {
  MacBrowserToolbar(this.onAction) {
    if (supported) _channel.setMethodCallHandler(_handle);
  }
  static const _channel = MethodChannel('crispcloud/browser_toolbar');
  final Future<void> Function(String) onAction;
  String? _configuration;
  bool _available = false;
  bool _disposed = false;
  Set<String> _enabled = {};
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> _handle(MethodCall call) async {
    if (_disposed || call.method != 'action' || call.arguments is! String)
      return;
    final id = call.arguments as String;
    if (_enabled.contains(id)) await onAction(id);
  }

  Future<bool> configure({
    required String title,
    required bool visible,
    required bool dark,
    required List<Map<String, Object>> items,
  }) async {
    if (!supported || _disposed) return false;
    final payload = {
      'title': title,
      'visible': visible,
      'dark': dark,
      'items': items,
    };
    final configuration = jsonEncode(payload);
    _enabled = visible
        ? items
              .where((item) => item['enabled'] != false)
              .map((item) => item['id']! as String)
              .toSet()
        : {};
    if (_configuration == configuration) return _available;
    try {
      final available =
          await _channel.invokeMethod<bool>('configure', payload) ?? false;
      if (_disposed) return false;
      _configuration = configuration;
      _available = available;
      return available;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _enabled = {};
    if (!supported) return;
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod<void>('configure', {
        'visible': false,
        'items': [],
      });
    } on MissingPluginException {
      // Widget tests and older platform hosts retain their Flutter toolbar.
    } on PlatformException {
      // Window teardown may precede the browser route's teardown.
    }
  }
}
