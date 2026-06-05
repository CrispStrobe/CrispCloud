// lib/services/file_type_color_service.dart
//
// Per-extension color rules for file list entries.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/file_item.dart';

/// A rule mapping file extension patterns to display colors.
class FileTypeColorRule {
  /// Comma-separated list of extensions (without dots), e.g. "zip,rar,7z".
  final String extensions;
  final Color color;

  const FileTypeColorRule({required this.extensions, required this.color});

  /// Returns true if [ext] matches any extension in this rule.
  bool matches(String ext) {
    final parts = extensions.split(',').map((e) => e.trim().toLowerCase());
    return parts.contains(ext.toLowerCase());
  }

  Map<String, dynamic> toJson() => {
        'extensions': extensions,
        'color': color.value,
      };

  factory FileTypeColorRule.fromJson(Map<String, dynamic> json) =>
      FileTypeColorRule(
        extensions: json['extensions'] as String,
        color: Color(json['color'] as int),
      );
}

class FileTypeColorService extends ChangeNotifier {
  static const _prefsKey = 'file_type_color_rules_v1';
  static const _prefsEnabledKey = 'file_type_color_enabled_v1';

  bool _enabled = true;
  bool get enabled => _enabled;

  List<FileTypeColorRule> _rules = List.of(_defaultRules);
  List<FileTypeColorRule> get rules => List.unmodifiable(_rules);

  static const _defaultRules = [
    FileTypeColorRule(extensions: 'zip,rar,7z,tar,gz,bz2,xz,zst,tgz', color: Colors.amber),
    FileTypeColorRule(extensions: 'exe,app,dmg,deb,rpm,sh,bash,bat,cmd,msi', color: Color(0xFFE53935)), // red
    FileTypeColorRule(extensions: 'png,jpg,jpeg,gif,bmp,svg,ico,webp,tiff,avif,heic', color: Color(0xFF1E88E5)), // blue
    FileTypeColorRule(extensions: 'mp4,avi,mkv,mov,wmv,flv,webm,m4v', color: Color(0xFF00ACC1)), // cyan
    FileTypeColorRule(extensions: 'mp3,wav,aac,flac,ogg,m4a,wma,opus', color: Color(0xFF43A047)), // green
    FileTypeColorRule(extensions: 'pdf,doc,docx,xls,xlsx,ppt,pptx,odt,ods', color: Color(0xFFE64A19)), // deep orange
    FileTypeColorRule(extensions: 'dart,js,ts,jsx,tsx,py,rs,go,java,kt,swift,c,cpp,h,hpp,cs,php,rb,lua,r', color: Color(0xFF8E24AA)), // purple
    FileTypeColorRule(extensions: 'txt,md,log,csv,ini,cfg,conf,toml,env', color: Color(0xFF757575)), // grey
  ];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsEnabledKey) ?? true;
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _rules = list
            .map((e) => FileTypeColorRule.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _rules = List.of(_defaultRules);
      }
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, value);
    notifyListeners();
  }

  Future<void> setRules(List<FileTypeColorRule> rules) async {
    _rules = List.of(rules);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_rules.map((r) => r.toJson()).toList()));
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _rules = List.of(_defaultRules);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }

  /// Returns the color for a file item, or null if no rule matches or disabled.
  Color? colorForFile(FileItem item) {
    if (!_enabled || item.isFolder) return null;
    final ext = item.extension;
    if (ext.isEmpty) return null;
    for (final rule in _rules) {
      if (rule.matches(ext)) return rule.color;
    }
    return null;
  }
}
