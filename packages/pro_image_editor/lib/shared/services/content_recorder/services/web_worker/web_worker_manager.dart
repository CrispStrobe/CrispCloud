import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '/core/constants/editor_web_constants.dart';
import '/core/models/multi_threading/thread_request_model.dart';
import '../../models/web_worker_thread.dart';
import '../../utils/processor_helper.dart';
import '../thread_manager.dart';

/// Manages browser image workers and propagates failures to the converter's
/// existing main-thread fallback.
class WebWorkerManager extends ThreadManager<WebWorkerThread> {
  /// Creates a manager using the normal bundled worker by default.
  ///
  /// [workerScriptUrl] also permits a host with a custom asset base to supply
  /// the URL of the same compiled worker.
  WebWorkerManager(
    super.configs, {
    this.workerScriptUrl = kImageEditorWebWorkerPath,
  });

  /// The URL used by all workers owned by this manager.
  final String workerScriptUrl;

  /// A supported, non-failed worker already owned by this manager is available.
  /// Checking support must not create an extra worker or leak its resources.
  @override
  bool get isSupported => !isDestroyed && threads.any((thread) => thread.isReady);

  @override
  void initialize() {
    final processors = getNumberOfProcessors(
      configs: configs.processorConfigs,
      deviceNumberOfProcessors: web.window.navigator.hardwareConcurrency,
    );
    for (var i = 0; i < processors && !isDestroyed; i++) {
      threads.add(
        WebWorkerThread(
          coreNumber: i + 1,
          scriptUrl: workerScriptUrl,
          onMessage: (message) {
            final index = tasks.indexWhere((task) => task.taskId == message.id);
            if (index >= 0 && !tasks[index].bytes$.isCompleted) {
              tasks[index].bytes$.complete(message.bytes);
            }
          },
          onError: (thread, error, stack) {
            for (final task in tasks.where((task) => task.threadId == thread.id)) {
              if (!task.bytes$.isCompleted) task.bytes$.completeError(error, stack);
            }
          },
        ),
      );
    }
  }

  @override
  Future<Uint8List?> send(ThreadRequest data) {
    if (!isSupported) {
      return Future<Uint8List?>.error(StateError('No image worker is available.'));
    }
    return super.send(data);
  }
}
