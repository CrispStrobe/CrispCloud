// lib/services/saf_service.dart
//
// Storage Access Framework (SAF) integration for Android.
//
// Allows the app to browse Android external storage (SD cards, USB drives)
// using ACTION_OPEN_DOCUMENT and ACTION_OPEN_DOCUMENT_TREE via a platform
// channel backed by Kotlin.  On non-Android platforms every method is a no-op
// that returns null so callers can platform-guard with a single `isSupported`
// check.

import 'dart:io';

import 'package:flutter/services.dart';

import 'log_service.dart';

/// Result returned by [SAFService.openDocumentTree].
class SAFFolder {
  /// Android content URI (e.g. "content://com.android.externalstorage.documents/tree/…")
  final String uri;

  /// Human-readable display name of the selected folder.
  final String displayName;

  const SAFFolder({required this.uri, required this.displayName});

  @override
  String toString() => 'SAFFolder(uri: $uri, displayName: $displayName)';
}

/// Result returned by [SAFService.openDocument].
class SAFFile {
  /// Android content URI for the selected file.
  final String uri;

  /// Display name (file name).
  final String displayName;

  /// MIME type as reported by Android.
  final String mimeType;

  /// File size in bytes, or -1 if unknown.
  final int size;

  const SAFFile({
    required this.uri,
    required this.displayName,
    required this.mimeType,
    required this.size,
  });

  @override
  String toString() =>
      'SAFFile(displayName: $displayName, mimeType: $mimeType, size: $size)';
}

/// Service wrapping Android Storage Access Framework via a MethodChannel.
///
/// The Kotlin side must be registered in [MainActivity] (or a separate plugin).
/// The channel is defined here so both sides agree on the name.
class SAFService {
  static const _channelName = 'com.CrispStrobe.cloud_dart/saf';
  static const _channel = MethodChannel(_channelName);

  static const _log = Log('SAFService');

  // -------------------------------------------------------------------------
  // Platform guard
  // -------------------------------------------------------------------------

  /// True only on Android.  All public methods short-circuit to null on other
  /// platforms so callers do not need their own platform checks.
  static bool get isSupported => !kIsTestEnvironment && Platform.isAndroid;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Opens the Android folder picker (ACTION_OPEN_DOCUMENT_TREE).
  ///
  /// Returns the selected [SAFFolder] or `null` if the user cancelled or the
  /// platform is not Android.
  Future<SAFFolder?> openDocumentTree({
    /// Optionally pre-seed the picker with a starting URI.
    String? initialUri,
  }) async {
    if (!isSupported) {
      _log.debug('SAF not supported on ${Platform.operatingSystem}');
      return null;
    }

    try {
      _log.info('Opening SAF document tree picker');
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'openDocumentTree',
        initialUri != null ? {'initialUri': initialUri} : null,
      );

      if (result == null) {
        _log.debug('SAF document tree picker cancelled by user');
        return null;
      }

      final folder = SAFFolder(
        uri: result['uri'] as String,
        displayName: result['displayName'] as String,
      );
      _log.info('SAF folder selected', {
        'displayName': folder.displayName,
        'uri': folder.uri,
      });
      return folder;
    } on PlatformException catch (e, st) {
      _log.error('SAF openDocumentTree failed', e, st);
      return null;
    }
  }

  /// Opens the Android file picker (ACTION_OPEN_DOCUMENT).
  ///
  /// [mimeTypes] restricts which files are shown.  Pass `['*/*']` to show all.
  /// [allowMultiple] enables multi-selection (returns only the first file when
  /// false, which is the default).
  ///
  /// Returns the selected [SAFFile] or `null` if cancelled / not Android.
  Future<SAFFile?> openDocument({
    List<String> mimeTypes = const ['*/*'],
    bool allowMultiple = false,
  }) async {
    if (!isSupported) {
      _log.debug('SAF not supported on ${Platform.operatingSystem}');
      return null;
    }

    try {
      _log.info('Opening SAF document picker', {
        'mimeTypes': mimeTypes,
        'allowMultiple': allowMultiple,
      });

      final result = await _channel.invokeMapMethod<String, dynamic>(
        'openDocument',
        {
          'mimeTypes': mimeTypes,
          'allowMultiple': allowMultiple,
        },
      );

      if (result == null) {
        _log.debug('SAF document picker cancelled by user');
        return null;
      }

      final file = SAFFile(
        uri: result['uri'] as String,
        displayName: result['displayName'] as String,
        mimeType: result['mimeType'] as String? ?? '*/*',
        size: (result['size'] as int?) ?? -1,
      );
      _log.info('SAF file selected', {
        'displayName': file.displayName,
        'mimeType': file.mimeType,
        'size': file.size,
      });
      return file;
    } on PlatformException catch (e, st) {
      _log.error('SAF openDocument failed', e, st);
      return null;
    }
  }

  /// Opens the Android file picker allowing multiple files to be selected.
  ///
  /// Returns a (possibly empty) list of [SAFFile] items.
  Future<List<SAFFile>> openDocuments({
    List<String> mimeTypes = const ['*/*'],
  }) async {
    if (!isSupported) {
      _log.debug('SAF not supported on ${Platform.operatingSystem}');
      return [];
    }

    try {
      _log.info('Opening SAF multi-document picker', {'mimeTypes': mimeTypes});

      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'openDocuments',
        {'mimeTypes': mimeTypes},
      );

      if (raw == null || raw.isEmpty) {
        _log.debug('SAF multi-document picker returned no files');
        return [];
      }

      final files = raw.map((m) {
        final map = Map<String, dynamic>.from(m);
        return SAFFile(
          uri: map['uri'] as String,
          displayName: map['displayName'] as String,
          mimeType: map['mimeType'] as String? ?? '*/*',
          size: (map['size'] as int?) ?? -1,
        );
      }).toList();

      _log.info('SAF multi-document picker returned ${files.length} files');
      return files;
    } on PlatformException catch (e, st) {
      _log.error('SAF openDocuments failed', e, st);
      return [];
    }
  }

  /// Lists the children of a SAF folder URI.
  ///
  /// Returns a list of [SAFFile] items (directories are included with
  /// mimeType "vnd.android.document/directory").
  Future<List<SAFFile>> listFolder(String folderUri) async {
    if (!isSupported) {
      _log.debug('SAF not supported on ${Platform.operatingSystem}');
      return [];
    }

    try {
      _log.debug('Listing SAF folder', {'uri': folderUri});

      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'listFolder',
        {'uri': folderUri},
      );

      if (raw == null) return [];

      final items = raw.map((m) {
        final map = Map<String, dynamic>.from(m);
        return SAFFile(
          uri: map['uri'] as String,
          displayName: map['displayName'] as String,
          mimeType: map['mimeType'] as String? ?? '*/*',
          size: (map['size'] as int?) ?? -1,
        );
      }).toList();

      _log.debug('SAF folder contains ${items.length} items',
          {'uri': folderUri});
      return items;
    } on PlatformException catch (e, st) {
      _log.error('SAF listFolder failed', e, st);
      return [];
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// True when [mimeType] represents a directory in SAF.
  static bool isDirectory(String mimeType) =>
      mimeType == 'vnd.android.document/directory';
}

/// Allows unit tests to exercise SAF logic without a real Android device.
/// Set to `true` in test setUp; reset in tearDown.
// ignore: prefer_const_declarations
bool kIsTestEnvironment = false;
