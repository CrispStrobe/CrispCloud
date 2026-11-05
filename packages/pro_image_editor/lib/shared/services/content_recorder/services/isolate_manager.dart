import '/core/platform/io/io_helper.dart';
import '/shared/services/content_recorder/utils/processor_helper.dart';
import '../models/isolate_thread.dart';
import 'thread_manager.dart';

/// Manages the lifecycle and communication of isolates.
///
/// This class handles the creation, management, and disposal of isolates
/// for performing background tasks. It ensures proper communication with
/// the main thread and handles the results from isolate operations.
class IsolateManager extends ThreadManager<IsolateThread> {
  /// Constructs an instance of `IsolateManager` with the provided
  /// configuration.
  IsolateManager(super.configs);

  @override
  void initialize() async {
    int processors = getNumberOfProcessors(
      configs: configs.processorConfigs,
      deviceNumberOfProcessors: Platform.numberOfProcessors,
    );
    for (var i = 0; i < processors && !isDestroyed; i++) {
      IsolateThread isolate = IsolateThread(
        coreNumber: i + 1,
        onMessage: (message) {
          int i = tasks.indexWhere((el) => el.taskId == message.id);
          if (i >= 0) tasks[i].bytes$.complete(message.bytes);
        },
      );
      threads.add(isolate);

      /// Await that isolate is ready before spawn a new one.
      await isolate.readyState.future;
      isolate.isReady = true;
      if (isDestroyed) {
        isolate.destroy();
      }
    }
  }
}
