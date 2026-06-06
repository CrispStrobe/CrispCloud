// lib/services/intent_handler_service.dart
//
// Handles incoming Android intents (share-to / open-with) via the
// receive_sharing_intent package.
//
// Responsibilities:
//   1. Listen for files shared to CrispCloud via ACTION_SEND / SEND_MULTIPLE.
//   2. Show a dialog so the user can pick a destination cloud folder.
//   3. Trigger the upload once a destination is chosen.
//   4. Handle ACTION_VIEW for opening files from other apps.
//
// Platform guard: all public methods are no-ops on non-Android platforms.
//
// Usage:
//   final handler = IntentHandlerService(
//     onUploadRequested: (files, destination) { /* enqueue upload */ },
//   );
//   handler.initialize();
//   // …later…
//   handler.dispose();

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'log_service.dart';

/// Describes an incoming share event that requires user action.
class IncomingShareEvent {
  /// Absolute file paths of the shared files.
  final List<String> filePaths;

  /// Display names corresponding to [filePaths].
  final List<String> fileNames;

  const IncomingShareEvent({
    required this.filePaths,
    required this.fileNames,
  });
}

/// Callback type invoked when the user approves an upload.
///
/// [filePaths] — local paths of files to upload.
/// [destinationFolder] — cloud folder path chosen by the user.
typedef UploadRequestCallback = Future<void> Function(
  List<String> filePaths,
  String destinationFolder,
);

/// Callback type invoked when the service needs the UI to prompt the user for
/// a destination folder and then call [approve] or [cancel].
typedef ShareUiCallback = Future<void> Function(
  IncomingShareEvent event,
  Future<void> Function(String destinationFolder) approve,
  void Function() cancel,
);

class IntentHandlerService {
  static const _log = Log('IntentHandlerService');

  /// True only on Android (non-web dart:io build).
  static bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  final UploadRequestCallback onUploadRequested;

  /// Called when incoming files arrive — the implementation should show a
  /// folder-picker dialog and then call the provided approve/cancel callbacks.
  final ShareUiCallback onShowShareUi;

  StreamSubscription<List<SharedMediaFile>>? _subscription;

  IntentHandlerService({
    required this.onUploadRequested,
    required this.onShowShareUi,
  });

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Start listening for incoming intents.  Call from your app's [initState]
  /// or app-level setup code (after the widget tree is ready so dialogs can
  /// be shown).
  void initialize() {
    if (!isSupported) {
      _log.debug(
          'IntentHandlerService: not supported on ${kIsWeb ? 'web' : Platform.operatingSystem}');
      return;
    }

    _log.info('IntentHandlerService: initializing');

    // Stream for intents received while the app is running
    _subscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleIncomingFiles,
      onError: (Object err, StackTrace st) {
        _log.error('IntentHandlerService: stream error', err, st);
      },
    );

    // Handle the intent that launched the app (app was cold-started by a share)
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then(_handleIncomingFiles)
        .catchError((Object err, StackTrace st) {
      _log.error('IntentHandlerService: initial media error', err, st);
    });
  }

  /// Stop listening.  Call from your app's dispose / cleanup.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _log.debug('IntentHandlerService: disposed');
  }

  // -------------------------------------------------------------------------
  // Internal handling
  // -------------------------------------------------------------------------

  Future<void> _handleIncomingFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    _log.info(
        'IntentHandlerService: received ${files.length} file(s) via share intent');

    // Tell the intent plugin we've consumed this intent so it won't replay
    ReceiveSharingIntent.instance.reset();

    final filePaths = <String>[];
    final fileNames = <String>[];

    for (final f in files) {
      final path = f.path;
      if (path.isEmpty) continue;
      filePaths.add(path);
      // Derive display name from path; SharedMediaFile.path is the local cache
      fileNames.add(_baseName(path));
    }

    if (filePaths.isEmpty) {
      _log.warn('IntentHandlerService: all received files had empty paths');
      return;
    }

    final event = IncomingShareEvent(
      filePaths: filePaths,
      fileNames: fileNames,
    );

    // Hand off to the UI layer to show the destination picker.
    await onShowShareUi(
      event,
      // approve callback
      (String destinationFolder) async {
        _log.info(
            'IntentHandlerService: user approved upload to "$destinationFolder"',
            {'files': filePaths.length});
        await onUploadRequested(filePaths, destinationFolder);
      },
      // cancel callback
      () {
        _log.info('IntentHandlerService: user cancelled share upload');
      },
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static String _baseName(String path) {
    final sep = path.contains('/') ? '/' : r'\';
    return path.split(sep).last;
  }
}
