// lib/services/link_service.dart
//
// Create symbolic and hard links on local filesystem and SFTP.

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'link_operation_failure.dart';
import 'native_system.dart';

class LinkService {
  /// Create a symbolic link at [linkPath] pointing to [target].
  static Future<void> createSymlink(String target, String linkPath) async {
    if (kIsWeb) throw LinkUnsupportedError(LinkOperationCode.webUnsupported, 'Link creation not supported on Web');
    await Link(linkPath).create(target);
  }

  /// Create a hard link at [linkPath] pointing to [target].
  /// Only supported on POSIX systems (macOS, Linux).
  static Future<void> createHardlink(String target, String linkPath) async {
    if (kIsWeb) throw LinkUnsupportedError(LinkOperationCode.webUnsupported, 'Link creation not supported on Web');
    if (Platform.isWindows) {
      throw LinkUnsupportedError(LinkOperationCode.windowsHardlink, 'Hard links on Windows require elevated privileges');
    }
    if (!createHardLink(target, linkPath)) {
      throw LinkOperationException(
        LinkOperationCode.hardlinkFailed,
        'Failed to create hard link: $target → $linkPath',
        {'detail': 'link(2) failed'},
      );
    }
  }

  /// Create a symbolic link on a remote SFTP server via SSH command.
  /// Requires an [execute] function that runs commands on the remote host.
  static Future<void> createRemoteSymlink(
    String target,
    String linkPath,
    Future<String> Function(String command) execute,
  ) async {
    String escaped(String s) => s.replaceAll("'", "'\\''");
    final result = await execute("ln -s '${escaped(target)}' '${escaped(linkPath)}'");
    if (result.contains('Permission denied') || result.contains('Operation not permitted')) {
      throw LinkOperationException(LinkOperationCode.symlinkDenied, 'Permission denied creating symlink', {'detail': result});
    }
  }

  /// Check if a path is a symbolic link.
  static Future<bool> isSymlink(String path) async {
    if (kIsWeb) return false;
    final type = await FileSystemEntity.type(path, followLinks: false);
    return type == FileSystemEntityType.link;
  }

  /// Get the target of a symbolic link.
  static Future<String?> symlinkTarget(String path) async {
    if (kIsWeb) return null;
    try {
      return await Link(path).target();
    } catch (_) {
      return null;
    }
  }
}
