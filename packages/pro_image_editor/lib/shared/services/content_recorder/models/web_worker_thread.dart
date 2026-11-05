// Dart imports:
import 'dart:js_interop' as js;

import 'package:web/web.dart' as web;

import '/core/constants/editor_web_constants.dart';
import '/core/models/multi_threading/thread_request_model.dart';
import '/core/models/multi_threading/thread_response_model.dart';
import '../utils/web_worker_utils.dart';
import 'thread.dart';

/// A browser worker which reports load, execution, and message failures to its
/// manager so pending image captures can fall back instead of waiting forever.
class WebWorkerThread extends Thread {
  /// Creates a worker using the published asset path unless explicitly supplied.
  WebWorkerThread({
    required super.onMessage,
    required super.coreNumber,
    this.onError,
    this.scriptUrl = kImageEditorWebWorkerPath,
  });

  /// The URL of the compiled worker script.
  final String scriptUrl;

  /// Reports failures for every pending task assigned to this worker.
  final void Function(WebWorkerThread thread, Object error, StackTrace stack)?
  onError;

  web.Worker? _worker;
  Object? _failure;
  bool _isDestroyed = false;

  /// The underlying worker, available after successful construction.
  web.Worker get worker => _worker!;

  @override
  void init() {
    try {
      final instance = _worker = web.Worker(
        scriptUrl.toJS,
        web.WorkerOptions(name: '$debugThreadName-$coreNumber'),
      );
      instance.onerror = (web.Event event) {
        // The failed task is reported through its Future below. Do not also
        // surface it as an unhandled browser error after fallback succeeds.
        event.preventDefault();
        _fail(StateError('Image worker failed to load or execute: $scriptUrl'));
      }.toJS;
      instance.onmessageerror = (web.Event event) {
        event.preventDefault();
        _fail(StateError('Image worker returned an unreadable message.'));
      }.toJS;
      instance.onmessage = (web.MessageEvent event) {
        if (_failure != null || _isDestroyed) return;
        try {
          final jsObj = event.data as js.JSObject?;
          if (jsObj == null) {
            throw StateError('Image worker returned an empty message.');
          }
          final dartId = (jsGetProperty(jsObj, 'id') as js.JSString).toDart;
          final jsBytes = jsGetProperty(jsObj, 'bytes');
          final dartBytes = (jsBytes as js.JSArrayBuffer?)?.toDart;
          if (activeTasks > 0) activeTasks--;
          activeTaskIds.remove(dartId);
          onMessage(ThreadResponse(bytes: dartBytes?.asUint8List(), id: dartId));
        } catch (error, stack) {
          _fail(error, stack);
        }
      }.toJS;
      // Worker.postMessage queues work while the script is loading. A later
      // network/CSP/script error is handled by onerror and rejects that work.
      readyState.complete(true);
      isReady = true;
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_failure != null || _isDestroyed) return;
    _failure = error;
    isReady = false;
    activeTasks = 0;
    activeTaskIds.clear();
    if (!readyState.isCompleted) readyState.complete(false);
    _worker?.terminate();
    onError?.call(this, error, stack ?? StackTrace.current);
  }

  @override
  void send(ThreadRequest data) {
    if (!isReady || _isDestroyed || _failure != null) {
      throw StateError('Image worker is unavailable.');
    }
    activeTaskIds.add(data.id);
    try {
      // ThreadManager already counted this task. Counting twice makes normal
      // successive exports appear to exceed the concurrency limit.
      worker.postMessage(jsify(data.toMap()));
    } catch (error, stack) {
      // The manager completes its pending Future with this failure. Returning
      // here lets it attach the awaiting handler before that error is delivered.
      _fail(error, stack);
    }
  }

  @override
  void destroyActiveTasks(String ignoreTaskId) {
    if (!isReady || _isDestroyed) return;
    try {
      worker.postMessage(
        jsify({'mode': 'destroyActiveTasks', 'ignoreTaskId': ignoreTaskId}),
      );
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  @override
  void destroy() {
    if (_isDestroyed) return;
    _isDestroyed = true;
    isReady = false;
    _worker?.terminate();
  }
}
