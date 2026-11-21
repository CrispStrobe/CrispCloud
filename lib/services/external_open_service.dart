// Files handed to CrispCloud from outside the app: "Open with" / double-click
// on a registered file type, and files received through the system share
// sheet. Every platform feeds the same queue:
//
//   Windows/Linux  command-line arguments (main(args))
//   macOS/iOS      native "open" events and share extensions via the
//                  `com.crispcloud/external_open` channel
//   Android        VIEW/SEND intents via receive_sharing_intent, with the
//                  intent action read from the same channel
//
// The UI (lib/widgets/external_open_handler.dart) consumes the queue once the
// file browser is on screen; requests that arrive earlier wait in [pending].

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'log_service.dart';

/// One hand-off from another app.
@immutable
class ExternalOpenRequest {
  const ExternalOpenRequest(
    this.paths, {
    this.shared = false,
    this.reveal = false,
    this.cleanup,
    this.deleteSources = false,
  });

  /// Absolute local file (or folder) paths.
  final List<String> paths;

  /// True for files received through a share sheet: they are kept in the
  /// app's Received folder and shown there, ready to copy to any storage.
  /// False for "Open with": the file opens in the matching viewer.
  final bool shared;

  /// True when the files should only be shown selected in their folder (the
  /// Finder "Upload to CrispCloud" action): copy them anywhere with F5.
  final bool reveal;

  /// A temporary hand-off folder (share extension inbox) to delete once the
  /// files have been kept.
  final String? cleanup;

  /// The paths are private hand-off copies (iOS share extension inbox) to
  /// delete once kept.
  final bool deleteSources;

  @override
  String toString() =>
      'ExternalOpenRequest(${shared ? 'shared' : 'open'}, $paths)';
}

/// File extensions CrispCloud registers for "Open with" on Windows (and that
/// match the viewer/editor coverage; macOS/iOS use content types, Linux MIME
/// types and Android accepts any file).
const externalOpenExtensions = <String>[
  // Documents
  'pdf', 'docx', 'docm', 'dotx', 'dotm', 'doc', 'dot', 'rtf', 'odt',
  'xlsx', 'xlsm', 'xltx', 'xlsb', 'xls', 'xlt', 'ods',
  'pptx', 'pptm', 'potx', 'ppt', 'pps', 'pot', 'odp', 'wpd', 'ps', 'eps',
  // E-books
  'epub', 'mobi', 'azw', 'azw3', 'fb2', 'cbz', 'cbr', 'cb7',
  // Images
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico', 'tif', 'tiff',
  'avif', 'heic', 'heif', 'psd',
  // Audio and video
  'mp4', 'm4v', 'mov', 'avi', 'mkv', 'webm', 'wmv', 'mpg', 'mpeg', 'mp3',
  'wav', 'flac', 'aac', 'ogg', 'opus', 'm4a', 'wma', 'aiff', 'mid', 'midi',
  // Text and code
  'txt', 'md', 'markdown', 'json', 'yaml', 'yml', 'xml', 'csv', 'tsv',
  'log', 'ini', 'toml', 'html', 'htm', 'css', 'js', 'ts', 'dart', 'py',
  'java', 'kt', 'swift', 'c', 'cpp', 'h', 'cs', 'go', 'rs', 'sh', 'srt', 'vtt',
  // Mail, fonts, 3D, password databases
  'eml', 'msg', 'mbox', 'ttf', 'otf', 'woff', 'woff2', 'stl', '3mf', 'kdbx',
  // Archives and disk images
  'zip', '7z', 'rar', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'zst', 'cab', 'iso',
  'dmg', 'img', 'jar', 'apk', 'deb', 'rpm', 'msix', 'appx',
];

class ExternalOpenService {
  ExternalOpenService._();

  static final instance = ExternalOpenService._();
  static const channel = MethodChannel('com.crispcloud/external_open');
  static const _log = Log('ExternalOpen');

  final _controller = StreamController<ExternalOpenRequest>.broadcast();
  final _pending = <ExternalOpenRequest>[];
  bool _platformStarted = false;
  StreamSubscription<List<SharedMediaFile>>? _androidMedia;

  Stream<ExternalOpenRequest> get requests => _controller.stream;

  /// Requests that arrived before the UI started listening.
  List<ExternalOpenRequest> takePending() {
    final pending = List.of(_pending);
    _pending.clear();
    return pending;
  }

  @visibleForTesting
  void reset() {
    _pending.clear();
  }

  void add(ExternalOpenRequest request) {
    if (request.paths.isEmpty) return;
    _log.info('Received $request');
    if (_controller.hasListener) {
      _controller.add(request);
    } else {
      _pending.add(request);
    }
  }

  /// Desktop command line: existing files and folders open; flags, URLs and
  /// anything that does not exist are ignored (the `crispcloud://` scheme and
  /// `--register-…` switches are handled elsewhere).
  void addArguments(List<String> arguments) {
    final paths = <String>[];
    final reveal = <String>[];
    for (final argument in arguments) {
      if (argument.isEmpty || argument.startsWith('-')) continue;
      var path = argument;
      if (argument.startsWith('file://')) {
        final uri = Uri.tryParse(argument);
        if (uri == null) continue;
        path = uri.toFilePath();
      } else if (argument.startsWith('crispcloud://upload?paths=')) {
        // Explorer "Upload to CrispCloud": a raw Windows path follows.
        reveal.add(argument.substring('crispcloud://upload?paths='.length));
        continue;
      } else if (argument.contains('://')) {
        continue;
      }
      path = p.normalize(p.absolute(path));
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
        paths.add(path);
      }
    }
    add(ExternalOpenRequest(paths));
    final existing = reveal
        .map((path) => p.normalize(path))
        .where(
          (path) =>
              FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound,
        )
        .toList();
    add(ExternalOpenRequest(existing, reveal: true));
  }

  /// Connects the native sources once. Safe to call repeatedly.
  Future<void> startPlatformSources() async {
    if (_platformStarted || kIsWeb) return;
    _platformStarted = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'open') _addNative(call.arguments);
      return null;
    });
    if (Platform.isMacOS ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isLinux) {
      try {
        // Native code queues events until Dart is ready; drain that queue.
        final queued = await channel.invokeMethod<List<Object?>>('ready');
        for (final entry in queued ?? const <Object?>[]) {
          _addNative(entry);
        }
      } on MissingPluginException {
        // Runner without the channel (older native build, tests).
      } catch (e) {
        _log.warn('External open channel unavailable: $e');
      }
    }
    if (Platform.isAndroid) await _startAndroid();
  }

  void _addNative(Object? arguments) {
    if (arguments is! Map) return;
    // Windows: a second process forwarded its command line.
    final forwarded = arguments['arguments'];
    if (forwarded is List) {
      addArguments(forwarded.whereType<String>().toList());
      return;
    }
    final paths = (arguments['paths'] as List?)?.whereType<String>().toList();
    if (paths == null) return;
    add(
      ExternalOpenRequest(
        paths,
        shared: arguments['shared'] == true,
        reveal: arguments['reveal'] == true,
        cleanup: arguments['cleanup'] as String?,
        deleteSources: arguments['deleteSources'] == true,
      ),
    );
  }

  Future<void> _startAndroid() async {
    final sharing = ReceiveSharingIntent.instance;
    Future<void> handle(List<SharedMediaFile> media) async {
      final paths = [
        for (final item in media)
          if (item.type != SharedMediaType.url &&
              item.type != SharedMediaType.text &&
              item.path.isNotEmpty)
            item.path,
      ];
      if (paths.isEmpty) return;
      // The plugin reports VIEW and SEND alike; the activity remembers which.
      String? action;
      try {
        action = await channel.invokeMethod<String>('lastIntentAction');
      } catch (_) {}
      add(
        ExternalOpenRequest(
          paths,
          shared: action == null
              ? paths.length > 1
              : action != 'android.intent.action.VIEW',
        ),
      );
    }

    try {
      await handle(await sharing.getInitialMedia());
      await sharing.reset();
    } catch (e) {
      _log.warn('Initial Android intent unavailable: $e');
    }
    _androidMedia = sharing.getMediaStream().listen(
      (media) => unawaited(handle(media)),
      onError: (Object e) => _log.warn('Android intent stream failed: $e'),
    );
  }

  /// Copies received files into `<app support>/Received/<timestamp>/` so they
  /// stay available after the sending app cleans up, and returns that folder.
  Future<String> keepReceived(
    List<String> paths, {
    Directory? root,
    DateTime? now,
  }) async {
    final base =
        root ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'Received'),
        );
    final stamp = (now ?? DateTime.now())
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    var folder = Directory(p.join(base.path, stamp));
    for (var n = 2; await folder.exists(); n++) {
      folder = Directory(p.join(base.path, '$stamp ($n)'));
    }
    await folder.create(recursive: true);
    for (final path in paths) {
      final type = await FileSystemEntity.type(path);
      if (type != FileSystemEntityType.file) continue;
      var target = p.join(folder.path, p.basename(path));
      for (var n = 2; await File(target).exists(); n++) {
        target = p.join(
          folder.path,
          '${p.basenameWithoutExtension(path)} ($n)${p.extension(path)}',
        );
      }
      await File(path).copy(target);
    }
    return folder.path;
  }

  /// Removes a share-extension hand-off folder after its files were kept.
  Future<void> removeHandOff(String? path) async {
    if (path == null) return;
    try {
      if (await FileSystemEntity.isDirectory(path)) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _androidMedia?.cancel();
  }
}
