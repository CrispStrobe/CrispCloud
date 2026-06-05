// test/file_type_color_test.dart
//
// Tests for per-extension file type colorization (Phase 2.2).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_type_color_service.dart';

void main() {
  group('FileTypeColorService', () {
    late FileTypeColorService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = FileTypeColorService();
      await service.load();
    });

    test('returns color for known archive extensions', () {
      final item = FileItem(name: 'file.zip', isFolder: false);
      expect(service.colorForFile(item), isNotNull);
    });

    test('returns color for code files', () {
      final item = FileItem(name: 'main.dart', isFolder: false);
      expect(service.colorForFile(item), isNotNull);
    });

    test('returns null for folders', () {
      final item = FileItem(name: 'src', isFolder: true);
      expect(service.colorForFile(item), isNull);
    });

    test('returns null for unknown extensions', () {
      final item = FileItem(name: 'file.xyz123', isFolder: false);
      expect(service.colorForFile(item), isNull);
    });

    test('returns null when disabled', () async {
      await service.setEnabled(false);
      final item = FileItem(name: 'file.dart', isFolder: false);
      expect(service.colorForFile(item), isNull);
    });

    test('returns null for files without extension', () {
      final item = FileItem(name: 'Makefile', isFolder: false);
      expect(service.colorForFile(item), isNull);
    });

    test('custom rules override defaults', () async {
      await service.setRules([
        const FileTypeColorRule(extensions: 'dart', color: Colors.red),
      ]);
      final item = FileItem(name: 'main.dart', isFolder: false);
      expect(service.colorForFile(item), Colors.red);
    });

    test('resetToDefaults restores original rules', () async {
      await service.setRules([]);
      expect(service.rules, isEmpty);
      await service.resetToDefaults();
      expect(service.rules, isNotEmpty);
    });
  });

  group('FileTypeColorRule', () {
    test('matches comma-separated extensions', () {
      const rule = FileTypeColorRule(extensions: 'zip,rar,7z', color: Colors.amber);
      expect(rule.matches('zip'), isTrue);
      expect(rule.matches('rar'), isTrue);
      expect(rule.matches('7z'), isTrue);
      expect(rule.matches('txt'), isFalse);
    });

    test('matching is case-insensitive', () {
      const rule = FileTypeColorRule(extensions: 'zip', color: Colors.amber);
      expect(rule.matches('ZIP'), isTrue);
      expect(rule.matches('Zip'), isTrue);
    });

    test('serialization round-trip', () {
      const original = FileTypeColorRule(extensions: 'dart,js', color: Color(0xFF0000FF));
      final json = original.toJson();
      final restored = FileTypeColorRule.fromJson(json);
      expect(restored.extensions, original.extensions);
      expect(restored.color.value, original.color.value);
    });
  });
}
