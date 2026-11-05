// Dart imports:
import 'dart:async';
import 'dart:js_interop' as js;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '/core/constants/editor_web_constants.dart';
import '/core/models/multi_threading/thread_request_model.dart';
import '/core/models/multi_threading/thread_response_model.dart';
import '../utils/web_worker_utils.dart';
import 'thread.dart';

/// A class representing a web worker thread.
///
/// Extends [Thread] to handle web worker operations including
/// sending messages, receiving responses, and managing the worker's lifecycle.
class WebWorkerThread extends Thread {
  /// Creates an instance of [WebWorkerThread].
  ///
  /// The [onMessage] callback is required to handle messages received
  /// from the web worker.
  WebWorkerThread({required super.onMessage, required super.coreNumber});

  /// The [web.Worker] instance managing the web worker.
  ///
  /// This is the web worker instance that executes the worker script
  /// and communicates with the main thread.
  late final web.Worker worker;

  @override
  void init() {
    try {
      worker = web.Worker(
        kImageEditorWebWorkerPath.toJS,
        web.WorkerOptions(name: '$debugThreadName-$coreNumber'),
      );

      if (worker.isDefinedAndNotNull) {
        worker.onmessage = (web.MessageEvent event) {
          try {
            final jsObj = event.data as js.JSObject?;

            if (jsObj == null) return;

            /// Grab the "id" property as a JSString and convert to Dart String
            final jsId = jsGetProperty(jsObj, 'id');
            final dartId = (jsId as js.JSString).toDart; // String

            /// Grab the "bytes" property as a JSArrayBuffer and convert to
            /// Dart ByteBuffer
            final jsBytes = jsGetProperty(jsObj, 'bytes');
            final dartBytes = (jsBytes as js.JSArrayBuffer?)?.toDart;

            activeTasks--;
            onMessage(
              ThreadResponse(bytes: dartBytes?.asUint8List(), id: dartId),
            );
          } catch (e) {
            debugPrint(e.toString());
          }
        }.toJS;

        readyState.complete(true);
        isReady = true;
      } else {
        debugPrint('Your browser doesn\'t support web workers.');
        readyState.complete(false);
      }
    } catch (e) {
      if (readyState.isCompleted) readyState = Completer();
      readyState.complete(false);
    }
  }

  @override
  void send(ThreadRequest data) {
    activeTasks++;
    var convertedData = jsify(data.toMap());

    worker.postMessage(convertedData);
  }

  @override
  void destroyActiveTasks(String ignoreTaskId) async {
    worker.postMessage(
      jsify({'mode': 'destroyActiveTasks', 'ignoreTaskId': ignoreTaskId}),
    );
  }

  @override
  void destroy() {
    worker
      ..postMessage(jsify({'mode': 'kill'}))
      ..terminate();
  }
}
