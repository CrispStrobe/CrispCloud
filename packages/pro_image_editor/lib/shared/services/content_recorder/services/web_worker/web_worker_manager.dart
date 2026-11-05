import 'dart:js_interop' as js;

import 'package:web/web.dart' as web;

import '/core/constants/editor_web_constants.dart';
import '../../models/web_worker_thread.dart';
import '../../utils/processor_helper.dart';
import '../../utils/web_worker_utils.dart';
import '../thread_manager.dart';

/// Manages web workers for background processing tasks.
///
/// Extends [ThreadManager] to initialize and handle web worker threads.
/// Uses the browser's Web Worker API to offload tasks.
class WebWorkerManager extends ThreadManager<WebWorkerThread> {
  /// Constructs an instance of `WebWorkerManager` with the provided
  /// configuration.
  WebWorkerManager(super.configs);

  /// Indicates whether web workers are supported by the browser.
  @override
  bool get isSupported =>
      web.Worker(jsify(kImageEditorWebWorkerPath)!).isDefinedAndNotNull;

  @override
  void initialize() {
    int processors = getNumberOfProcessors(
      configs: configs.processorConfigs,
      deviceNumberOfProcessors: _deviceNumberOfProcessors(),
    );

    for (var i = 0; i < processors && !isDestroyed; i++) {
      threads.add(
        WebWorkerThread(
          coreNumber: i + 1,
          onMessage: (message) {
            int i = tasks.indexWhere((el) => el.taskId == message.id);
            if (i >= 0) tasks[i].bytes$.complete(message.bytes);
          },
        ),
      );
    }
  }

  /// Retrieves the number of processors available on the device.
  int _deviceNumberOfProcessors() {
    return web.window.navigator.hardwareConcurrency;
  }
}
