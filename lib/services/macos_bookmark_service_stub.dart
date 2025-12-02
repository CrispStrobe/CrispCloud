// lib/services/macos_bookmark_service_stub.dart
import 'dart:io';

class MacOSBookmarkService {
  static Future<String?> requestDirectoryAccess({String? initialDirectory}) async => null;
  static Future<String?> getLastGrantedDirectory() async => null;
  static Future<FileSystemEntity?> getResolvedBookmark() async => null;
  static Future<bool> hasAccessToPath(String path) async => true;
  static Future<void> clearBookmarks() async {}
}

class SecureBookmarks {
  Future<String> bookmark(dynamic file) async => '';
  Future<dynamic> resolveBookmark(String bookmark) async => null;
  Future<void> startAccessingSecurityScopedResource(dynamic file) async {}
  Future<void> stopAccessingSecurityScopedResource(dynamic file) async {}
}