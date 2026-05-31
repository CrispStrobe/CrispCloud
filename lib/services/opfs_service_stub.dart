// lib/services/opfs_service_stub.dart
//
// No-op stub compiled on non-web platforms.

import 'dart:typed_data';
import 'opfs_service.dart';

OpfsService createOpfsService() => _StubOpfsService();

class _StubOpfsService implements OpfsService {
  @override
  bool get isSupported => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> writeFile(String relativePath, Uint8List data) async {}

  @override
  Future<Uint8List?> readFile(String relativePath) async => null;

  @override
  Future<void> deleteFile(String relativePath) async {}

  @override
  Future<bool> exists(String relativePath) async => false;

  @override
  Future<void> clearAll() async {}
}
